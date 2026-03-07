#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  TILE WORKER (pipeline V6)
# Processes one spatial tile with optimised memory management
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Libraries ----------------------------------------------------------------
pkgs <- c("sf","dplyr","data.table","tidyr","rlang","tidyselect","lubridate","yaml","arrow")

safe_library <- function(pkg){
  tryCatch({ library(pkg, character.only = TRUE)
             cat("", pkg, "OK\n")},
           error=function(e) stop("Missing package: ", pkg, "\nMessage: ", e$message))
}

# Robust sf loading with error fallback
tryCatch({
  library(sf)
  cat(" sf OK\n")
  options(sf_max_print = 20)
  sf::sf_use_s2(FALSE)
}, error=function(e) {
  stop("Package 'sf' could not be loaded.\nMessage: ", e$message)
})

# Load remaining packages
invisible(lapply(pkgs[pkgs != "sf"], safe_library)); cat("\n")

# Load shared constants
this_file <- function() {
  # Rscript --file=... syntax
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) return(normalizePath(f))
  # fallback when sourced
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile))
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))

# ─────  f_i PARAMETERS  (k, alpha_dep, etc.)  ────────────────────────────────
args     <- commandArgs(trailingOnly = TRUE)
tile_id  <- as.integer(args[1])

if(is.na(tile_id) || tile_id < 1) {
  stop("Invalid tile ID. Usage: Rscript step5_tile_worker.R <tile_id>")
}

cat("Processing tile:", tile_id, "\n")

# Load YAML parameters
param_yaml <- "~/scratch/configuration/fi_parameters.yaml"
params_raw <- yaml::read_yaml(param_yaml)

# — inheritance helper ---------------------------------------------------------
get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit)
    s$inherit <- NULL
    modifyList(parent, s)
  } else s
}
par <- get_scenario("default")

# — regional k table -----------------------------------------------------------
k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast       = unlist(par$k_fast) *
                 ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k     # a⁻¹
preserv_fact  <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)  # p_r factor with default value

cat("  Paramètres f_i :\n")
cat("   - alpha_dep:", alpha_dep, "\n")
cat("   - fast_fraction:", fast_frac, "\n")
cat("   - slow_k:", slow_k, "a⁻¹\n")
cat("   - preservation_factor:", preserv_fact, "\n")

# Limit BLAS/OMP threads to avoid excessive memory use
Sys.setenv(OMP_NUM_THREADS = 1,
           MKL_NUM_THREADS = 1,
           OPENBLAS_NUM_THREADS = 1)

# Configuration data.table
data.table::setDTthreads(1)
cat(" data.table threads fixés à 1\n")

## 1.  Chargement de la tuile ---------------------------------------------------
cat("📂 Chargement de la tuile...\n")
# Use CELL_KM environment variable if defined
cell_km_env <- Sys.getenv("CELL_KM", "1000")
if (!is.na(as.integer(cell_km_env))) {
  CELL_KM <- as.integer(cell_km_env)
}

tiles_file <- sprintf("~/scratch/output_V6/tiles_%dkm.gpkg", CELL_KM)
tiles   <- st_read(tiles_file, quiet=TRUE)
tile_bb <- tiles[tiles$tile_id == tile_id, ]

if(nrow(tile_bb) == 0) {
  cat("  Tuile", tile_id, "non trouvée dans", tiles_file, "- création fichier vide\n")
  # Create an empty data.table with the correct format
  res <- data.table(
    grid_id = integer(),
    sum_dw = numeric(),
    sum_dw_pd = numeric(),
    sum_d = numeric(),
    sum_d_pl = numeric()
  )
  output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
  if(requireNamespace("arrow", quietly = TRUE) &&
     packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
    arrow::write_parquet(res, output_file)
  } else {
    saveRDS(res, sub("\\.parquet$", ".rds", output_file))
  }
  cat(" Fichier de sortie vide écrit :", output_file, "\n")
  quit(save="no")
}

cat(" Tuile chargée :", tile_id, "\n")

## 2.  Data pre-filtering -------------------------------------------------------
cat(" Pré-filtrage des données AIS...\n")

# Load the file with lithology data (step 4)
lithology_files <- list.files("~/scratch/output_V6/", pattern="AIS_with_lithology_clean_.*\\.rds$", full.names=TRUE)
if(!length(lithology_files)) {
  stop(" Aucun fichier avec lithologie trouvé (étape 4)")
}

dt_lithology <- readRDS(max(lithology_files))
cat(" Fichier avec lithologie lu :", nrow(dt_lithology), "lignes\n")

# FIX: Correct spatial selection with reprojection
# 1. Filter dredging pings with valid coordinates
dredge_raw <- dt_lithology[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
cat(" Pings dragage avec coordonnées :", nrow(dredge_raw), "\n")

if(nrow(dredge_raw) == 0) {
  cat("  Aucun ping de dragage dans les données - sortie propre\n")
  quit(save="no")
}

# 2. Convert to sf and reproject to EPSG:6933 (metres)
dredge_sf <- st_as_sf(dredge_raw, coords=c("Lon","Lat"), crs=4326) %>%
             st_transform(CRS_EQUIVALENT)

# 3. Buffer autour de la tuile pour capturer les lignes qui traversent
tile_geom <- st_geometry(tile_bb)
tile_buffered <- st_buffer(tile_geom, TILE_BUFFER_M)

# 4. Correct spatial selection
sel <- st_intersects(dredge_sf, tile_buffered, sparse=FALSE)[,1]
dredge_sf <- dredge_sf[sel, ]

if(nrow(dredge_sf) == 0) {
  cat("  Aucun ping de dragage dans la tuile", tile_id, "- fichier vide écrit\n")
  # Create an empty data.table with the correct format
  res <- data.table(
    grid_id = integer(),
    sum_dw = numeric(),
    sum_dw_pd = numeric(),
    sum_d = numeric(),
    sum_d_pl = numeric()
  )
  output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
  if(requireNamespace("arrow", quietly = TRUE) && 
     packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
    arrow::write_parquet(res, output_file)
  } else {
    saveRDS(res, sub("\\.parquet$", ".rds", output_file))
  }
  cat(" Fichier de sortie vide écrit :", output_file, "\n")
  quit(save="no")
}

# 4bis. Extract projected X,Y coordinates in metres from the geometry
coords <- st_coordinates(dredge_sf)
dredge_sf$X <- coords[,1]
dredge_sf$Y <- coords[,2]

# 5. Reconvertir en data.table pour la suite du pipeline (on conserve X,Y + toutes les autres colonnes)
dredge <- as.data.table(dredge_sf)
dredge[, geometry := NULL]  # Supprimer la colonne geometry

cat(" Pings dragage filtrés :", nrow(dredge), "\n")

## 3.  Chargement des specs navires ---------------------------------------------
cat(" Chargement des specs navires...\n")
specs_list <- yaml::read_yaml("~/scratch/configuration/ship_specs_clean.yaml")$ship_specs

# Protection contre les erreurs de parsing YAML
if (is.null(specs_list) || !length(specs_list)) {
  stop(" ship_specs_clean.yaml n'a pas pu être parsé - vérifiez l'encodage UTF-8 et l'indentation")
}

specs_dt <- rbindlist(lapply(specs_list, as.data.table), fill=TRUE)
specs_dt[, suction_pipe_diameter_m := (suction_pipe_diameter_mm/1000) * ifelse(is.na(twin_pipes), 1, twin_pipes)]
specs_dt <- specs_dt[, .(ssvid, name, suction_pipe_diameter_m, dredging_depth_m, dredge_width_m)]

# Debug : afficher les colonnes disponibles
cat(" Colonnes dans dredge :", paste(names(dredge), collapse=", "), "\n")

# Harmoniser le nom de la colonne d'identifiant si besoin
# Check several possible column name variants
vessel_id_cols <- c("ssvid", "SSVID", "mmsi", "MMSI", "vessel_id", "VESSEL_ID")
found_col <- NULL

for(col in vessel_id_cols) {
  if(col %in% names(dredge)) {
    found_col <- col
    break
  }
}

if(!is.null(found_col) && found_col != "ssvid") {
  cat(" Renommage de", found_col, "vers ssvid\n")
  setnames(dredge, found_col, "ssvid")
} else if(is.null(found_col)) {
  cat("  Aucune colonne d'identifiant navire trouvée parmi :", paste(vessel_id_cols, collapse=", "), "\n")
  cat("   Colonnes disponibles :", paste(names(dredge), collapse=", "), "\n")
}

# Merge specs onto dredge with suffixes to avoid column conflicts
if("ssvid" %in% names(dredge)) {
  dredge <- merge(
    dredge,
    specs_dt,
    by = "ssvid",
    all.x = TRUE,
    suffixes = c("", ".spec")
  )
  cat(" Merge specs réalisé\n")
  cat("   - Pings avec specs :", sum(!is.na(dredge$dredging_depth_m.spec)), "\n")
  cat("   - Pings sans specs :", sum(is.na(dredge$dredging_depth_m.spec)), "\n")
  
  # Debug: display columns after merge
  cat(" Colonnes après merge :", paste(names(dredge), collapse=", "), "\n")
} else {
  warning(" Aucune colonne ssvid trouvée pour joindre les specs YAML.")
}

# Default values if missing
if(any(is.na(dredge$suction_pipe_diameter_m))) {
  dredge[is.na(suction_pipe_diameter_m), suction_pipe_diameter_m := 0.5]
}

# Handle dredging_depth_m: YAML specs take priority, then original value, then default
if("dredging_depth_m.spec" %in% names(dredge)) {
  # Use YAML specs when available, otherwise keep original value
  dredge[, dredging_depth_m := fifelse(!is.na(dredging_depth_m.spec), dredging_depth_m.spec, dredging_depth_m)]
  # Default value for remaining cases
  dredge[is.na(dredging_depth_m), dredging_depth_m := 1.0]
} else {
  # If no specs, use original value or default
  if(any(is.na(dredge$dredging_depth_m))) {
    dredge[is.na(dredging_depth_m), dredging_depth_m := 1.0]
  }
}

## 4.  Use lithology data -------------------------------------------------------
cat(" Utilisation des données de lithologie...\n")

# Lithology data is already in dt_lithology
# Verify that lithology columns are present
litho_cols <- c("lithologie", "pl_base", "dist_km")
missing_cols <- setdiff(litho_cols, names(dredge))

if(length(missing_cols) > 0) {
  cat("  Colonnes de lithologie manquantes :", paste(missing_cols, collapse=", "), "\n")
  # Add default columns if missing
  if("pl_base" %in% missing_cols) dredge[, pl_base := 0]
  if("lithologie" %in% missing_cols) dredge[, lithologie := "unknown"]
  if("dist_km" %in% missing_cols) dredge[, dist_km := NA_real_]
}

# Gestion des valeurs manquantes
dredge[, `:=`(
  has_lithology = !is.na(pl_base),
  pl_base = fifelse(is.na(pl_base), 0, pl_base)
)]

cat(" Lithologie disponible :", sum(dredge$has_lithology), "pings avec lithologie\n")

# Protection contre largeur de dragage manquante
dredge[is.na(dredge_width_m), dredge_width_m := 2.6]  # default value
# Warn if too many default values
default_n <- dredge[dredge_width_m == 2.6, .N]
if (default_n > 0 && default_n / nrow(dredge) > 0.10) {
  cat(sprintf("  %d pings (%.1f%%) utilisent la largeur de dragage par défaut (2.6 m)\n",
              default_n, 100*default_n / nrow(dredge)))
}

## 5.  Conversion en lignes -----------------------------------------------------
cat(" Conversion en lignes...\n")
# Data is already in EPSG:6933 from pre-filtering; use the X/Y coordinates directly
dredge_sf <- st_as_sf(dredge, coords=c("X","Y"), crs=CRS_EQUIVALENT, remove=FALSE)

dredge_sf$sub_seg_id <- paste0(dredge_sf$Navire,"_",format(dredge_sf$Timestamp,"%Y%m%d"))

# Regroupement par segment de navigation
lines_sf  <- dredge_sf %>%
  group_by(sub_seg_id) %>%
  filter(n()>1) %>%
  summarise(W_v   = first(dredge_width_m),
            p_d_i = first(dredging_depth_m),
            pl_b  = first(pl_base),
            geometry = st_cast(st_combine(geometry),"MULTILINESTRING"),
            .groups="drop")

if(nrow(lines_sf) == 0) {
  cat("  Aucune ligne valide dans la tuile", tile_id, "- création fichier vide\n")
  # Create an empty data.table with the correct format
  res <- data.table(
    grid_id = integer(),
    sum_dw = numeric(),
    sum_dw_pd = numeric(),
    sum_d = numeric(),
    sum_d_pl = numeric()
  )
  output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
  if(requireNamespace("arrow", quietly = TRUE) && 
     packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
    arrow::write_parquet(res, output_file)
  } else {
    saveRDS(res, sub("\\.parquet$", ".rds", output_file))
  }
  cat(" Fichier de sortie vide écrit :", output_file, "\n")
  quit(save="no")
}

cat(" Lignes créées :", nrow(lines_sf), "\n")

## 6.  Grille locale 1 km ------------------------------------------------------
cat(" Création de la grille locale...\n")
grid1km <- st_make_grid(tile_bb, cellsize=CELL_SIZE_M) %>%
           st_sf(grid_id = seq_along(.), geometry = ., crs=CRS_EQUIVALENT)

# Add global grid coordinates (consistent with constants.R)
# NOTE: WORLD_XMIN/YMIN must be multiples of CELL_SIZE_M to avoid alignment offsets
grid_coords <- st_coordinates(st_centroid(grid1km))
grid1km$col <- as.integer(floor((grid_coords[,1] - WORLD_XMIN)/CELL_SIZE_M))
grid1km$row <- as.integer(floor((WORLD_YMAX - grid_coords[,2])/CELL_SIZE_M))
grid1km$global_grid_id <- grid1km$row*GRID_COLS + grid1km$col + 1L

cat(" Grille locale :", nrow(grid1km), "cellules\n")

## 7.  Intersection & streaming aggregation ------------------------------------
cat(" Intersections ligne/grille (mode streaming)...\n")
start_time <- Sys.time()

# Initialise result accumulator
res <- data.table(grid_id = integer(),
                  sum_dw = numeric(), sum_dw_pd = numeric(),
                  sum_d = numeric(), sum_d_pl = numeric())

# Row-by-row processing to save memory
for (i in seq_len(nrow(lines_sf))) {
  if(i %% 100 == 0) {
    cat("   Progression:", i, "/", nrow(lines_sf), "\n")
    gc()  # Nettoyage mémoire régulier
  }
  
  # Intersection avec la grille (optimisation C++)
  cand <- sf::st_intersects(lines_sf[i,], grid1km, sparse = FALSE)[1, ]
  if (!any(cand)) next
  
  inter <- sf::st_intersection(lines_sf[i,], grid1km[cand,])
  if (!nrow(inter)) next
  
  # Calcul des longueurs
  len <- as.numeric(st_length(inter))
  
  # Aggregate results
  res_i <- data.table(grid_id      = inter$global_grid_id,
                      sum_dw       = len * lines_sf$W_v[i],
                      sum_dw_pd    = len * lines_sf$W_v[i] * lines_sf$p_d_i[i],
                      sum_d        = len,
                      sum_d_pl     = len * lines_sf$pl_b[i])
  
  # Optimised merge with accumulator (avoids O(n²))
  if (nrow(res)) {
    # Update existing rows
    res[res_i, on="grid_id", `:=`(
      sum_dw     = sum_dw     + i.sum_dw,
      sum_dw_pd  = sum_dw_pd  + i.sum_dw_pd,
      sum_d      = sum_d      + i.sum_d,
      sum_d_pl   = sum_d_pl   + i.sum_d_pl
    )]
    
    # Append new rows (grid_ids not yet in res)
    new_rows <- res_i[!res, on="grid_id"]
    if (nrow(new_rows) > 0) {
      res <- rbindlist(list(res, new_rows))
    }
  } else {
    res <- res_i
  }
  
  # Nettoyage
  rm(inter, res_i)
}

# Final optimisation of the result table
if(nrow(res) > 0) {
  setkey(res, grid_id)  # Key to speed up downstream joins
}

# Nettoyage final
rm(lines_sf, grid1km, dredge_sf, dredge)
gc()

cat(" Intersections terminées :", nrow(res), "cellules touchées\n")
cat("  Durée :", round(difftime(Sys.time(), start_time, units="mins"), 2), "minutes\n")

## 8.  Sauvegarde partielle -----------------------------------------------------
cat(" Sauvegarde des résultats...\n")
output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)

# Check arrow version and save
if(requireNamespace("arrow", quietly = TRUE) && 
   packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
  arrow::write_parquet(res, output_file)
  cat(" Résultats sauvegardés en Parquet :", basename(output_file), "\n")
} else {
  # Fallback RDS si arrow non disponible ou version trop ancienne
  saveRDS(res, sub("\\.parquet$", ".rds", output_file))
  cat("  Arrow non disponible ou version <", PARQUET_VERSION_MIN, "- sauvegarde RDS :", 
      basename(sub("\\.parquet$", ".rds", output_file)), "\n")
}

# Statistiques finales
cat("\n STATISTIQUES TUILE", tile_id, "\n")
cat("   - Cellules touchées :", nrow(res), "\n")
if(nrow(res) > 0) {
  cat("   - Distance totale :", format(sum(res$sum_d), scientific=FALSE), "m\n")
  cat("   - SAR moyen :", format(mean(res$sum_dw / CELL_AREA_M2), scientific=FALSE), "\n")
  cat("   - SAR max :", format(max(res$sum_dw / CELL_AREA_M2), scientific=FALSE), "\n")
}

cat("\n Tuile", tile_id, "terminée avec succès !\n") 
