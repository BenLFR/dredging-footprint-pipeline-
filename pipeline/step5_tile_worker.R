#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5 ─ WORKER TILE (pipeline V6, cluster Rorqual)
# Traite une tile individuelle with gestion memory optimisee
# ────────────────────────────────────────────────────────────────────────────────

## 0. Bibliotheques ------------------------------------------------------------
pkgs <- c("sf","dplyr","data.table","tidyr","rlang","tidyselect","lubridate","yaml","arrow")

safe_library <- function(pkg){
  tryCatch({ library(pkg, character.only = TRUE)
             cat("", pkg, "OK\n")},
           error=function(e) stop(" Package missing : ", pkg, "\nMessage : ", e$message))
}

# Loading robuste of sf
tryCatch({
  library(sf)
  cat(" sf OK\n")
  options(sf_max_print = 20)
  sf::sf_use_s2(FALSE)
}, error=function(e) {
  stop(" The package 'sf' ne peut pas etre loaded.\nMessage : ", e$message)
})

# Loading the other packages
invisible(lapply(pkgs[pkgs != "sf"], safe_library)); cat("\n")

# Loading the constantes partagees
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

# ───── PARAMETERS f_i (k, alpha_dep, etc.) ────────────────────────────────
args     <- commandArgs(trailingOnly = TRUE)
tile_id  <- as.integer(args[1])

if(is.na(tile_id) || tile_id < 1) {
  stop(" ID of tile invalide. Usage: Rscript step5_tile_worker.R <tile_id>")
}

cat(" Traitement tile :", tile_id, "\n")

# Loading the parameters YAML
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

# — table the k regionaux ------------------------------------------------------
k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast       = unlist(par$k_fast) *
                 ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k     # a−1
preserv_fact  <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)  # p_r factor with valeur par default

cat(" Parameters f_i :\n")
cat(" - alpha_dep:", alpha_dep, "\n")
cat(" - fast_fraction:", fast_frac, "\n")
cat(" - slow_k:", slow_k, "a−1\n")
cat(" - preservation_factor:", preserv_fact, "\n")

# Limitation the threads BLAS/OMP for eviter the surconsommation memory
Sys.setenv(OMP_NUM_THREADS = 1,
           MKL_NUM_THREADS = 1,
           OPENBLAS_NUM_THREADS = 1)

# Configuration data.table
data.table::setDTthreads(1)
cat(" data.table threads fixes a 1\n")

## 1. Loading of the tile ---------------------------------------------------
cat(" Loading of the tile...\n")
# Utiliser the variable d'environnement CELL_KM si definie
cell_km_env <- Sys.getenv("CELL_KM", "1000")
if (!is.na(as.integer(cell_km_env))) {
  CELL_KM <- as.integer(cell_km_env)
}

tiles_file <- sprintf("~/scratch/output_V6/tiles_%dkm.gpkg", CELL_KM)
tiles   <- st_read(tiles_file, quiet=TRUE)
tile_bb <- tiles[tiles$tile_id == tile_id, ]

if(nrow(tile_bb) == 0) {
  cat(" Tile", tile_id, "not found in", tiles_file, "- creation file vide\n")
  # Creation d'un data.table vide to bon format
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
  cat(" File of output vide written :", output_file, "\n")
  quit(save="no")
}

cat(" Tile chargee :", tile_id, "\n")

## 2. Pre-filtrage the data -------------------------------------------------
cat(" Pre-filtrage the data AIS...\n")

# Loading of file with lithology (step 4)
# Accepte the deux conventions of nommage observees:
# - AIS_with_lithology_clean_*.rds
# - AIS_with_lithology_*.rds
output_dir <- "~/scratch/output_V6/"
pat_clean <- "AIS_with_lithology_clean_.*\\.rds$"
pat_base  <- "AIS_with_lithology_.*\\.rds$"

lithology_files <- unique(c(
  list.files(output_dir, pattern = pat_clean, full.names = TRUE),
  list.files(output_dir, pattern = pat_base, full.names = TRUE)
))

if(!length(lithology_files)) {
  stop(
    " No file with lithology found (Step 4).\n",
    "   Tested patterns: ", pat_clean, " ; ", pat_base
  )
}

latest_idx <- which.max(file.info(lithology_files)$mtime)
lithology_path <- lithology_files[latest_idx]
dt_lithology <- readRDS(lithology_path)
cat(" File with lithology lu :", basename(lithology_path), "(", nrow(dt_lithology), "lines)\n")

# CORRECTION : Selection spatiale correcte with reprojection
# 1. Filtrer the pings of dredging with coordinates valides
dredge_raw <- dt_lithology[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
cat(" dredging pings with coordinates :", nrow(dredge_raw), "\n")

if(nrow(dredge_raw) == 0) {
  cat(" No ping of dredging in the data - clean output\n")
  quit(save="no")
}

# 2. Convertir en sf et reproject en EPSG:6933 (metres)
dredge_sf <- st_as_sf(dredge_raw, coords=c("Lon","Lat"), crs=4326) %>%
             st_transform(CRS_EQUIVALENT)

# 3. Buffer autour of the tile for capture the lines qui tratoent
tile_geom <- st_geometry(tile_bb)
tile_buffered <- st_buffer(tile_geom, TILE_BUFFER_M)

# 4. Selection spatiale correcte
sel <- st_intersects(dredge_sf, tile_buffered, sparse=FALSE)[,1]
dredge_sf <- dredge_sf[sel, ]

if(nrow(dredge_sf) == 0) {
  cat(" No ping of dredging in the tile", tile_id, "- empty file written\n")
  # Creation d'un data.table vide to bon format
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
  cat(" File of output vide written :", output_file, "\n")
  quit(save="no")
}

# 4bis. Extraire the coordinates projetees X,Y en metres depuis the geometrie
coords <- st_coordinates(dredge_sf)
dredge_sf$X <- coords[,1]
dredge_sf$Y <- coords[,2]

# 5. Reconvertir en data.table for the suite of pipeline (on conserve X,Y + toutes the other columns)
dredge <- as.data.table(dredge_sf)
dredge[, geometry := NULL]  # Supprimer the column geometry

cat(" dredging pings filters :", nrow(dredge), "\n")

## 3. Loading the specs navires ---------------------------------------------
cat(" Loading the specs navires...\n")
specs_list <- yaml::read_yaml("~/scratch/configuration/ship_specs_clean.yaml")$ship_specs

# Protection contre the erreurs of parsing YAML
if (is.null(specs_list) || !length(specs_list)) {
  stop(" ship_specs_clean.yaml n'a pas pu etre parse - check l'encodage UTF-8 et l'indentation")
}

specs_dt <- rbindlist(lapply(specs_list, as.data.table), fill=TRUE)
specs_dt[, suction_pipe_diameter_m := (suction_pipe_diameter_mm/1000) * ifelse(is.na(twin_pipes), 1, twin_pipes)]
specs_dt <- specs_dt[, .(ssvid, name, suction_pipe_diameter_m, dredging_depth_m, dredge_width_m)]

# Debug : afficher the columns disponibles
cat(" Columns in dredge :", paste(names(dredge), collapse=", "), "\n")

# Harmoniser the nom of the column d'identifiant si besoin
# Check multiple variantes possible
vessel_id_cols <- c("ssvid", "SSVID", "mmsi", "MMSI", "vessel_id", "VESSEL_ID")
found_col <- NULL

for(col in vessel_id_cols) {
  if(col %in% names(dredge)) {
    found_col <- col
    break
  }
}

if(!is.null(found_col) && found_col != "ssvid") {
  cat(" Renommage of", found_col, "to ssvid\n")
  setnames(dredge, found_col, "ssvid")
} else if(is.null(found_col)) {
  cat(" No column d'identifiant vessel found parmi :", paste(vessel_id_cols, collapse=", "), "\n")
  cat(" Columns disponibles :", paste(names(dredge), collapse=", "), "\n")
}

# Merge specs on dredge with suffixes for eviter the conflits
if("ssvid" %in% names(dredge)) {
  dredge <- merge(
    dredge,
    specs_dt,
    by = "ssvid",
    all.x = TRUE,
    suffixes = c("", ".spec")
  )
  cat(" Merge specs realise\n")
  cat(" - Pings with specs :", sum(!is.na(dredge$dredging_depth_m.spec)), "\n")
  cat(" - Pings without specs :", sum(is.na(dredge$dredging_depth_m.spec)), "\n")
  
  # Debug : afficher the columns after merge
  cat(" Columns after merge :", paste(names(dredge), collapse=", "), "\n")
} else {
  warning(" No column ssvid found for joindre the specs YAML.")
}

# Valeurs par default si missing
if(any(is.na(dredge$suction_pipe_diameter_m))) {
  dredge[is.na(suction_pipe_diameter_m), suction_pipe_diameter_m := 0.5]
}

# Gestion of dredging_depth_m : priorite aux specs YAML, sinon valeur d'origine, sinon default
if("dredging_depth_m.spec" %in% names(dredge)) {
  # Utiliser the specs YAML quand disponibles, sinon the valeur d'origine
  dredge[, dredging_depth_m := fifelse(!is.na(dredging_depth_m.spec), dredging_depth_m.spec, dredging_depth_m)]
  # Valeur par default for the cas restants
  dredge[is.na(dredging_depth_m), dredging_depth_m := 1.0]
} else {
  # Si pas of specs, utiliser the valeur d'origine ou default
  if(any(is.na(dredge$dredging_depth_m))) {
    dredge[is.na(dredging_depth_m), dredging_depth_m := 1.0]
  }
}

## 4. Utilisation the data of lithology ------------------------------------
cat(" Utilisation the data of lithology...\n")

# The data of lithology are already in dt_lithology
# Check que the columns of lithology are present
litho_cols <- c("lithologie", "pl_base", "dist_km")
missing_cols <- setdiff(litho_cols, names(dredge))

if(length(missing_cols) > 0) {
  cat(" Columns of lithology missing :", paste(missing_cols, collapse=", "), "\n")
  # Add the columns par default si missing
  if("pl_base" %in% missing_cols) dredge[, pl_base := 0]
  if("lithologie" %in% missing_cols) dredge[, lithologie := "unknown"]
  if("dist_km" %in% missing_cols) dredge[, dist_km := NA_real_]
}

# Gestion the missing values
dredge[, `:=`(
  has_lithology = !is.na(pl_base),
  pl_base = fifelse(is.na(pl_base), 0, pl_base)
)]

cat(" Lithology disponible :", sum(dredge$has_lithology), "pings with lithology\n")

# Protection contre largeur of dredging missing
dredge[is.na(dredge_width_m), dredge_width_m := 2.6]  # valeur par default
# Warning si too of valeurs par default
default_n <- dredge[dredge_width_m == 2.6, .N]
if (default_n > 0 && default_n / nrow(dredge) > 0.10) {
  cat(sprintf(" %d pings (%.1f%%) utilisent the largeur of dredging par default (2.6 m)\n",
              default_n, 100*default_n / nrow(dredge)))
}

## 5. Contoion en lines -----------------------------------------------------
cat(" Contoion en lines...\n")
# The data are already en EPSG:6933 depuis the pre-filtrage, on utilise the coordinates X/Y
dredge_sf <- st_as_sf(dredge, coords=c("X","Y"), crs=CRS_EQUIVALENT, remove=FALSE)

dredge_sf$sub_seg_id <- paste0(dredge_sf$Navire,"_",format(dredge_sf$Timestamp,"%Y%m%d"))

# Regroupement par segment of navigation
lines_sf  <- dredge_sf %>%
  group_by(sub_seg_id) %>%
  filter(n()>1) %>%
  summarise(W_v   = first(dredge_width_m),
            p_d_i = first(dredging_depth_m),
            pl_b  = first(pl_base),
            geometry = st_cast(st_combine(geometry),"MULTILINESTRING"),
            .groups="drop")

if(nrow(lines_sf) == 0) {
  cat(" No line valide in the tile", tile_id, "- creation file vide\n")
  # Creation d'un data.table vide to bon format
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
  cat(" File of output vide written :", output_file, "\n")
  quit(save="no")
}

cat(" Lines creees :", nrow(lines_sf), "\n")

## 6. Grid locale 1 km ------------------------------------------------------
cat(" Creation of the grid locale...\n")
grid1km <- st_make_grid(tile_bb, cellsize=CELL_SIZE_M) %>%
           st_sf(grid_id = seq_along(.), geometry = ., crs=CRS_EQUIVALENT)

# Add the coordinates of the grid globale (coherent with constants.R)
# NOTE: WORLD_XMIN/YMIN doivent etre the multiples of CELL_SIZE_M for eviter the decalages
grid_coords <- st_coordinates(st_centroid(grid1km))
grid1km$col <- as.integer(floor((grid_coords[,1] - WORLD_XMIN)/CELL_SIZE_M))
grid1km$row <- as.integer(floor((WORLD_YMAX - grid_coords[,2])/CELL_SIZE_M))
grid1km$global_grid_id <- grid1km$row*GRID_COLS + grid1km$col + 1L

cat(" Grid locale :", nrow(grid1km), "cells\n")

## 7. Intersection & agregation streaming --------------------------------------
cat(" Intersections line/grid (mode streaming)...\n")
start_time <- Sys.time()

# Initialisation of result
res <- data.table(grid_id = integer(),
                  sum_dw = numeric(), sum_dw_pd = numeric(),
                  sum_d = numeric(), sum_d_pl = numeric())

# Traitement line par line for economiser the memory
for (i in seq_len(nrow(lines_sf))) {
  if(i %% 100 == 0) {
    cat(" Progression:", i, "/", nrow(lines_sf), "\n")
    gc()  # Nettoyage memory regulier
  }
  
  # Intersection with the grid (optimisation C++)
  cand <- sf::st_intersects(lines_sf[i,], grid1km, sparse = FALSE)[1, ]
  if (!any(cand)) next
  
  inter <- sf::st_intersection(lines_sf[i,], grid1km[cand,])
  if (!nrow(inter)) next
  
  # Calcul the longueurs
  len <- as.numeric(st_length(inter))
  
  # Agregation the results
  res_i <- data.table(grid_id      = inter$global_grid_id,
                      sum_dw       = len * lines_sf$W_v[i],
                      sum_dw_pd    = len * lines_sf$W_v[i] * lines_sf$p_d_i[i],
                      sum_d        = len,
                      sum_d_pl     = len * lines_sf$pl_b[i])
  
  # Fusion optimisee with accumulateur (evite O(n2))
  if (nrow(res)) {
    # Mise a jour the lines existantes
    res[res_i, on="grid_id", `:=`(
      sum_dw     = sum_dw     + i.sum_dw,
      sum_dw_pd  = sum_dw_pd  + i.sum_dw_pd,
      sum_d      = sum_d      + i.sum_d,
      sum_d_pl   = sum_d_pl   + i.sum_d_pl
    )]
    
    # Add the nouvelles lines (grid_id not presents in res)
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

# Optimisation finale of the table of results
if(nrow(res) > 0) {
  setkey(res, grid_id)  # Cle for optimiser the fusions downstream
}

# Nettoyage final
rm(lines_sf, grid1km, dredge_sf, dredge)
gc()

cat(" Intersections completed :", nrow(res), "cells touched\n")
cat("⏱ Duration :", round(difftime(Sys.time(), start_time, units="mins"), 2), "minutes\n")

## 8. Save partielle -----------------------------------------------------
cat(" Save the results...\n")
output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)

# Verification of the toion d'arrow et save
if(requireNamespace("arrow", quietly = TRUE) && 
   packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
  arrow::write_parquet(res, output_file)
  cat(" Results saved en Parquet :", basename(output_file), "\n")
} else {
  # Fallback RDS si arrow not disponible ou toion too ancienne
  saveRDS(res, sub("\\.parquet$", ".rds", output_file))
  cat(" Arrow not disponible ou toion <", PARQUET_VERSION_MIN, "- save RDS :", 
      basename(sub("\\.parquet$", ".rds", output_file)), "\n")
}

# Statistiques finales
cat("\n STATISTIQUES TILE", tile_id, "\n")
cat(" - Cells touched :", nrow(res), "\n")
if(nrow(res) > 0) {
  cat(" - Distance totale :", format(sum(res$sum_d), scientific=FALSE), "m\n")
  cat(" - SAR moyen :", format(mean(res$sum_dw / CELL_AREA_M2), scientific=FALSE), "\n")
  cat(" - SAR max :", format(max(res$sum_dw / CELL_AREA_M2), scientific=FALSE), "\n")
}

cat("\n Tile", tile_id, "completed successfully !\n") 
