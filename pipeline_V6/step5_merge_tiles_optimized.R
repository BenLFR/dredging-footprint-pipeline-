#!/usr/bin/env Rscript
# =============================================================================
# Step 5 : Fusion des tuiles SAR -> grille f_i finale
# =============================================================================
# Fixes applied:
#  A : Dedup keeps ALL cells (prefer owner tile, fallback to max sum_dw)
#  B : k_fast mapping works with basin-keyed OR province-keyed YAML
#  C : p_l = pl_sum / n_with_pl (worker-corrected schema)
#  D : Centroid coordinates use constants.R (bottom-up)
#  E : GeoTIFF row inversion (terra top-down)
#  F : Minimal but actionable diagnostics
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(data.table)
  library(tidyr)
  library(rlang)
  library(tidyselect)
  library(lubridate)
  library(yaml)
  library(arrow)
  library(terra)
})

# --- Source constants.R -------------------------------------------------------
this_file <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) return(normalizePath(f))
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile))
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))

sf_use_s2(FALSE)

cat("Grille :", GRID_COLS, "x", GRID_ROWS, " cellules de", CELL_SIZE_M, "m\n")
cat("Emprise X :", WORLD_XMIN, "->", WORLD_XMAX, "\n")
cat("Emprise Y :", WORLD_YMIN, "->", WORLD_YMAX, "\n\n")

# --- Parametres de ligne de commande ------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
scenario <- if(length(args) > 0) args[1] else "default"
cat("Fusion finale - Scenario :", scenario, "\n")

# --- Chargement des parametres YAML -------------------------------------------
param_yaml <- "~/scratch/configuration/fi_parameters_with_freshness.yaml"
params_raw <- yaml::read_yaml(param_yaml)

get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit)
    s$inherit <- NULL
    modifyList(parent, s)
  } else s
}
par <- get_scenario(scenario)

# --- Verification des parametres requis ---------------------------------------
required <- c("alpha_dep","fast_fraction","slow_k","preservation_factor","k_fast")
miss <- setdiff(required, names(par))
if(length(miss)) stop("Parametres YAML manquants : ", paste(miss, collapse=", "))
if (length(par$k_fast) == 0) stop("k_fast vide dans le YAML")

# --- Table des k regionaux (raw from YAML) ------------------------------------
k_yaml_names <- names(par$k_fast)
k_yaml_vals  <- unlist(par$k_fast) *
                ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k
preserv_fact  <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)

cat("Parametres f_i :\n")
cat("   - alpha_dep       :", alpha_dep, "\n")
cat("   - fast_fraction   :", fast_frac, "\n")
cat("   - slow_k          :", slow_k, "a-1\n")
cat("   - preserv_factor  :", preserv_fact, "\n")
cat("   - k_fast keys     :", paste(k_yaml_names, collapse=", "), "\n")
stopifnot(!is.na(alpha_dep), !is.na(fast_frac), !is.na(slow_k), !is.na(preserv_fact))
cat("Tous les parametres sont valides\n\n")

# =============================================================================
# 1) Fusion des tuiles SAR
# =============================================================================
cat("== 1) Fusion des tuiles SAR ==\n")

sar_files <- list.files("~/scratch/output_V6/", pattern="^sar_.*\\.(parquet|rds)$", full.names=TRUE)
if(length(sar_files) == 0) stop("Aucun fichier sar_* trouve dans ~/scratch/output_V6/")

parquet_count <- sum(grepl("\\.parquet$", sar_files))
rds_count     <- sum(grepl("\\.rds$", sar_files))
cat("Fichiers trouves :", length(sar_files), "(Parquet:", parquet_count, "RDS:", rds_count, ")\n")

# Chargement SAR avec provenance tile_id
tile_from_file <- function(f) as.integer(sub("^sar_", "", sub("\\.(parquet|rds)$", "", basename(f))))

sar_list <- vector("list", length(sar_files))
for(i in seq_along(sar_files)) {
  file <- sar_files[i]
  cat("   Chargement :", basename(file), "\n")
  dt <- if(grepl("\\.parquet$", file)) as.data.table(read_parquet(file))
        else as.data.table(readRDS(file))
  dt[, source_tile_id := tile_from_file(file)]
  sar_list[[i]] <- dt
}

cat("Assemblage des donnees...\n")
sar_global <- rbindlist(sar_list, fill=TRUE)
rm(sar_list); gc()
setDT(sar_global)

n_rows_raw   <- nrow(sar_global)
n_gridid_raw <- uniqueN(sar_global$grid_id)
cat("Avant deduplication :", n_rows_raw, "lignes,", n_gridid_raw, "grid_id uniques\n")

# =============================================================================
# 2) Deduplication — Fix A : keep ALL cells, no drops
# =============================================================================
cat("\n== 2) Deduplication owner-tile ==\n")

# Centres cellules EPSG:6933
cent <- unique(sar_global[, .(grid_id)])
cent[, `:=`(
  col = (grid_id - 1L) %% GRID_COLS,
  row = (grid_id - 1L) %/% GRID_COLS
)]
cent[, `:=`(
  x = WORLD_XMIN + col * CELL_SIZE_M + CELL_SIZE_M / 2,
  y = WORLD_YMIN + row * CELL_SIZE_M + CELL_SIZE_M / 2
)]
cent_sf <- st_as_sf(cent, coords = c("x", "y"), crs = 6933)

# Charger les tuiles core (sans buffer) — auto-detect layer with tile_id
tiles_path <- "~/scratch/output_V6/tiles_1000km.gpkg"
if (!file.exists(path.expand(tiles_path))) {
  stop("Fichier tuiles introuvable : ", tiles_path)
}
ly <- st_layers(path.expand(tiles_path))
layer_ok <- NULL
for (L in ly$name) {
  s <- try(st_read(path.expand(tiles_path), layer = L, quiet = TRUE), silent = TRUE)
  if (!inherits(s, "try-error") && "tile_id" %in% names(s)) { layer_ok <- L; break }
}
if (is.null(layer_ok)) stop("Aucun layer avec colonne tile_id dans ", tiles_path)
tiles <- st_read(path.expand(tiles_path), layer = layer_ok, quiet = TRUE)
cat("Tiles layer :", layer_ok, "->", nrow(tiles), "tuiles\n")

# Jointure spatiale : trouver la tuile owner de chaque cellule
owner <- as.data.table(st_join(cent_sf, tiles[, "tile_id"], left = TRUE))
owner[, geometry := NULL]
setnames(owner, "tile_id", "owner_tile_id")

# Merge owner info into sar_global
sar_global <- merge(sar_global, owner, by = "grid_id", all.x = TRUE)

# Robust dedup: for each grid_id, prefer the owner-tile row, else max sum_dw
# NA-safe: owner_tile_id can be NA for cells outside all core tiles
sar_global[, is_owner := as.integer(!is.na(owner_tile_id) & source_tile_id == owner_tile_id)]
# Temp ordering column: NA sum_dw must not win over real values
sar_global[, sort_dw := fifelse(is.na(sum_dw), -Inf, sum_dw)]
setorder(sar_global, grid_id, -is_owner, -sort_dw)
sar_global[, sort_dw := NULL]
sar_global <- sar_global[, .SD[1], by = grid_id]

stopifnot(nrow(sar_global) == uniqueN(sar_global$grid_id))

# Zero-drop check: must keep ALL unique grid_ids
if (nrow(sar_global) != n_gridid_raw) {
  warning("Dedup a modifie le nombre de grid_id: ", n_gridid_raw, " -> ", nrow(sar_global))
}

n_with_owner    <- sum(sar_global$is_owner == 1L, na.rm = TRUE)
n_without_owner <- nrow(sar_global) - n_with_owner
cat("Deduplication :", nrow(sar_global), "cellules uniques\n")
cat("   avec owner-tile :", n_with_owner, "\n")
cat("   sans owner (fallback max sum_dw) :", n_without_owner, "\n")

# Nettoyage colonnes temporaires
sar_global[, c("source_tile_id", "owner_tile_id", "is_owner") := NULL]

# =============================================================================
# 3) Calcul des metriques SAR / SVR — Fix C
# =============================================================================
cat("\n== 3) Calcul des metriques SAR/SVR ==\n")

sar_global[, SAR := sum_dw / CELL_AREA_M2]
sar_global[, p_d := fifelse(sum_dw > 0, sum_dw_pd / sum_dw, NA_real_)]
sar_global[, SVR := SAR * p_d]

# p_l compatible worker corrige
if ("n_with_pl" %in% names(sar_global) && "pl_sum" %in% names(sar_global)) {
  sar_global[, p_l := fifelse(n_with_pl > 0, pl_sum / n_with_pl, NA_real_)]
} else if (all(c("sum_d_pl", "sum_d") %in% names(sar_global))) {
  sar_global[, p_l := fifelse(sum_d > 0, sum_d_pl / sum_d, NA_real_)]
} else {
  sar_global[, p_l := NA_real_]
}
# Option B depth-weighting: surface layer [0-5 cm] + capped deep layer [5-10 cm].
# Sediment below 10 cm contributes 0 labile fraction on a 1-year timescale
# (beyond Holocene bioturbated layer; k < 1e-4 a-1, negligible in 365 days).
# Guard against p_d = 0 or NA (→ treated as 1 m default, consistent with tile worker).
sar_global[, p_d_safe := fifelse(is.na(p_d) | p_d <= 0, 1, p_d)]
sar_global[, `:=`(
  w1 = pmin(0.05, p_d_safe) / p_d_safe,
  w2 = pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe  # Option B: capped at 5 cm thick
)]
sar_global[, p_l_eff := w1 * p_l + w2 * p_l * alpha_dep]
sar_global[, c("p_d_safe", "w1", "w2") := NULL]

cat("SAR  : min=", min(sar_global$SAR, na.rm=TRUE),
    " max=", max(sar_global$SAR, na.rm=TRUE), "\n")
cat("SVR  : min=", min(sar_global$SVR, na.rm=TRUE),
    " max=", max(sar_global$SVR, na.rm=TRUE), "\n")
cat("p_l  : non-NA =", sum(!is.na(sar_global$p_l)), "/", nrow(sar_global), "\n")

# =============================================================================
# 4) Provinces Longhurst + k_fast mapping — Fix B
# =============================================================================
cat("\n== 4) Provinces Longhurst ==\n")

longhurst <- st_read(
  path.expand("~/scratch/configuration/longhurst_v4_2010/Longhurst_world_v4_2010.shp"),
  quiet = TRUE
)
longhurst <- st_transform(longhurst, 6933)

# Detecter la colonne code
code_col <- grep("code$", names(longhurst), value = TRUE, ignore.case = TRUE)[1]
if(is.na(code_col) || code_col == "") stop("Champ code Longhurst introuvable dans le shapefile")
longhurst <- dplyr::rename(longhurst, longhurst_pr = !!sym(code_col))

prov_codes <- unique(longhurst$longhurst_pr)
cat("Provinces Longhurst chargees :", length(prov_codes), "codes\n")

# --- Fix B : Detect basin-keyed vs province-keyed YAML -----------------------
# Safety init for basin-mode objects (used later in section 5)
basin_k <- NULL
norm_basin <- NULL

# Strict binary: if ANY key matches a Longhurst code -> province mode
is_province_mode <- any(k_yaml_names %in% prov_codes)

cat("k_fast mode :", ifelse(is_province_mode, "PROVINCE-keyed", "BASIN-keyed"), "\n")

if (is_province_mode) {
  # Province-keyed: direct join
  overlap <- length(intersect(k_yaml_names, prov_codes))
  if (overlap < 0.8 * length(k_yaml_names)) {
    warning("Province-mode mais overlap faible: ", overlap, "/", length(k_yaml_names),
            " (verifier les cles YAML)")
  }
  k_table <- data.table(longhurst_pr = k_yaml_names, k_fast = k_yaml_vals)
  longhurst <- dplyr::left_join(longhurst, k_table, by = "longhurst_pr")
  if (!"k_fast" %in% names(longhurst)) {
    stop("Province mode actif mais k_fast n'a pas ete joint sur longhurst (verifier code_col / YAML keys)")
  }
} else {
  # Basin-keyed: map province -> basin using geographic rules
  # Normalisation function for fuzzy matching of basin names
  norm_basin <- function(x) gsub("[^a-z0-9]+", "", tolower(x))

  # Build basin lookup from YAML with normalized key
  basin_k <- data.table(basin = k_yaml_names, k_fast = k_yaml_vals)
  basin_k[, basin_norm := norm_basin(basin)]
  cat("Basin k_fast values:\n")
  print(basin_k)

  # Authoritative province -> basin lookup (source: Longhurst v4 documentation)
  PROV_BASIN_LUT <- data.table(
    prov_code = c("ARCT","SARC","NADR","GFST","NASW","NATR","WTRA","ETRA","SATL",
                  "NECS","CNRY","GUIN","GUIA","NWCS","MEDI","CARB","NASE","BRAZ",
                  "FKLD","BENG","MONS","ISSG","EAFR","REDS","ARAB","INDE","SUND",
                  "NEWZ","SSTC","SANT","CHIL","CHIN","CAMR","CCAL","WARM","NPTG",
                  "NPPF","NPSG","NPTE","NPEQ","SPTG","SPPF","SPSG","SPTE","SPEQ",
                  "PEQD","ARCH","ANTA","APLR","BPLR","ALSK","AUSE","AUSW","BERS",
                  "INDW","KURO","NPSW","PNEC","PSAE","PSAW","TASM"),
    basin_raw = c("Arctic","Arctic","Atlantic","Atlantic","Atlantic","Atlantic","Atlantic",
                  "Atlantic","Atlantic","Atlantic","Atlantic","Atlantic","Atlantic","Atlantic",
                  "Mediterranean","Gulf of Mexico and Caribbean","Atlantic","Atlantic",
                  "Atlantic","Atlantic","Indian","Indian","Indian","Indian","Indian","Indian",
                  "Pacific","Pacific","Pacific","Pacific","Pacific","Pacific","Pacific",
                  "Pacific","Pacific","Pacific","Pacific","Pacific","Pacific","Pacific",
                  "Pacific","Pacific","Pacific","Pacific","Pacific","Pacific","Pacific",
                  "Antarctic","Arctic","Arctic","Arctic","Pacific","Pacific","Arctic",
                  "Indian","Pacific","Pacific","Pacific","Pacific","Pacific","Pacific")
  )
  cat("PROV_BASIN_LUT loaded :", nrow(PROV_BASIN_LUT), "provinces\n")

  # We will assign basin AFTER the spatial join with Longhurst (section 5)
  # Store basin_k for later
  cat("Basin mapping will be applied after Longhurst spatial join\n")
}

# =============================================================================
# 5) Jointure spatiale et calcul f_i — Fix D
# =============================================================================
cat("\n== 5) Jointure spatiale et calcul f_i ==\n")

# Centroid coordinates (bottom-up, constants.R)
grid_cent <- data.table(grid_id = as.integer(sar_global$grid_id))
grid_cent[, `:=`(
  col = (grid_id - 1L) %% GRID_COLS,
  row = (grid_id - 1L) %/% GRID_COLS
)]
grid_cent[, `:=`(
  x = WORLD_XMIN + col * CELL_SIZE_M + CELL_SIZE_M / 2,
  y = WORLD_YMIN + row * CELL_SIZE_M + CELL_SIZE_M / 2
)]

sf_cent <- st_as_sf(grid_cent, coords = c("x","y"), crs = 6933)

# Jointure avec Longhurst
fi_dt <- as.data.table(st_join(sf_cent, longhurst, left=TRUE))[, geometry := NULL]

# Fusion avec les donnees SAR
fi_dt <- merge(fi_dt, sar_global, by="grid_id", all.x=TRUE)

# --- Lon/lat from sf_cent (reuse, no recalculation) --------------------------
tmp_4326 <- st_transform(sf_cent, 4326)
coords_4326 <- as.data.table(st_coordinates(tmp_4326))
setnames(coords_4326, c("lon_deg", "lat_deg"))
coords_4326[, grid_id := grid_cent$grid_id]
fi_dt <- merge(fi_dt, coords_4326, by = "grid_id", all.x = TRUE)

# --- k_fast assignment (basin mode) ------------------------------------------
if (!is_province_mode) {
  if (is.null(basin_k)) stop("basin_k non defini (bug logique)")

  # Join LUT on longhurst province code
  fi_dt <- merge(fi_dt, PROV_BASIN_LUT, by.x = "longhurst_pr", by.y = "prov_code", all.x = TRUE)

  # Split Pacific N/S by centroid latitude
  fi_dt[, basin_yaml := basin_raw]
  fi_dt[basin_raw == "Pacific", basin_yaml := fifelse(lat_deg >= 0, "North Pacific", "South Pacific")]

  # Antarctic fallback: no YAML key -> route to nearest basin
  fi_dt[basin_raw == "Antarctic", basin_yaml := fifelse(lat_deg >= -60, "South Pacific", "Arctic")]

  # Fallback for cells without Longhurst province (NA or not in LUT)
  fi_dt[is.na(basin_yaml), basin_yaml := fifelse(
    lat_deg >= 0 & (lon_deg > 100 | lon_deg < -100), "North Pacific",
    fifelse(lat_deg < 0 & (lon_deg > 100 | lon_deg < -100), "South Pacific",
    fifelse(lon_deg > 20 & lon_deg <= 100, "Indian",
    "Atlantic"))
  )]

  # Remove any pre-existing k_fast column to prevent merge collision (k_fast.x/y)
  if ("k_fast" %in% names(fi_dt)) fi_dt[, k_fast := NULL]

  # Normalized join to handle YAML key variants
  fi_dt[, basin_norm := norm_basin(basin_yaml)]
  fi_dt <- merge(fi_dt, basin_k[, .(basin_norm, k_fast)], by = "basin_norm", all.x = TRUE)

  # Guard: warn if too many NA after basin join
  pct_na_k <- 100 * mean(is.na(fi_dt$k_fast))
  if (pct_na_k > 5) {
    unmatched <- setdiff(unique(fi_dt$basin_norm), basin_k$basin_norm)
    warning("k_fast NA > 5% en basin mode (", round(pct_na_k, 1), "%). Basins non matches: ",
            paste(unmatched, collapse = ", "))
  }

  # Diagnostics
  cat("Basin assignment counts:\n")
  print(fi_dt[, .N, by = basin_yaml][order(-N)])

  # Clean up temp cols
  fi_dt[, c("basin_raw", "basin_norm", "basin_yaml") := NULL]
}
# lon/lat already merged above for both modes

# --- k_fast coverage diagnostics ---------------------------------------------
n_with_k <- sum(!is.na(fi_dt$k_fast))
cat("k_fast non-NA :", n_with_k, "/", nrow(fi_dt),
    sprintf("(%.1f%%)\n", 100 * n_with_k / nrow(fi_dt)))

# --- Charger le facteur de fraicheur depuis le YAML ---------------------------
if (!is.null(par$fresh_fact) && length(par$fresh_fact) > 0) {
  fresh_fact_table <- data.table(
    longhurst_pr = names(par$fresh_fact),
    fresh_fact = unlist(par$fresh_fact)
  )
  fi_dt <- merge(fi_dt, fresh_fact_table, by="longhurst_pr", all.x=TRUE)
} else {
  fi_dt[, fresh_fact := NA_real_]
}
fi_dt[is.na(fresh_fact), fresh_fact := 1.0]

# --- Calcul f_i final ---------------------------------------------------------
fi_dt[, `:=`(
  k_used   = coalesce(k_fast, 1.0),
  p_l_corr = p_l_eff * fresh_fact
)]

t <- 1
fi_dt[, `:=`(
  f_i_full = SVR * p_l_corr * preserv_fact *
             ( fast_frac * (1 - exp(-k_used * t)) +
               (1 - fast_frac) * (1 - exp(-slow_k * t)) ),

  f_i_conservative = SVR * (p_l_corr / 2) * preserv_fact *
                ( fast_frac * (1 - exp(-k_used / 2 * t)) +
                  (1 - fast_frac) * (1 - exp(-slow_k / 2 * t)) )
)]

# CAP f_i dans [0, 1]
fi_dt[, f_i_full         := pmin(pmax(f_i_full, 0), 1)]
fi_dt[, f_i_conservative := pmin(pmax(f_i_conservative, 0), 1)]

cat("f_i calcule\n")

# --- Fix F : Diagnostics -----------------------------------------------------
# Fallback = k_fast was NA (not just k_used==1.0 which could be a real YAML value)
fi_dt[, is_fallback := is.na(k_fast) & !is.na(SVR) & SVR > 0]
nb_fallback <- fi_dt[, sum(is_fallback, na.rm=TRUE)]
nb_active   <- fi_dt[, sum(SVR > 0, na.rm=TRUE)]
if (nb_active == 0) nb_active <- 1

cat(sprintf("   Cellules k_fast manquant (fallback k_used=1.0) : %d / %d (%.1f%%)\n",
            nb_fallback, nb_active, 100*nb_fallback/nb_active))
if (nb_fallback / nb_active > 0.05) {
  warning("Plus de 5% des cellules n'ont pas de k_fast (fallback k_used=1.0)")
}

cat(sprintf("   p_l non-NA        : %d / %d (%.1f%%)\n",
            sum(!is.na(fi_dt$p_l)), nrow(fi_dt),
            100 * sum(!is.na(fi_dt$p_l)) / nrow(fi_dt)))
cat(sprintf("   f_i_full non-NA   : %d / %d (%.1f%%)\n",
            sum(!is.na(fi_dt$f_i_full)), nrow(fi_dt),
            100 * sum(!is.na(fi_dt$f_i_full)) / nrow(fi_dt)))

cat("\nTop-10 f_i_full (with lon/lat EPSG:4326) :\n")
print(head(fi_dt[order(-f_i_full),
                 .(grid_id, SAR, SVR, p_l_eff, p_l_corr, k_used, longhurst_pr,
                   f_i_full, lon_deg, lat_deg)], 10))

# =============================================================================
# 6) Sauvegarde finale
# =============================================================================
cat("\n== 6) Sauvegarde ==\n")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Parquet
out_parquet <- sprintf("~/scratch/output_V6/fi_grid_%s.parquet", timestamp)
write_parquet(fi_dt, out_parquet)
cat("Parquet :", basename(out_parquet), "\n")

# RDS
out_rds <- sprintf("~/scratch/output_V6/fi_grid_%s.rds", timestamp)
saveRDS(fi_dt, out_rds)
cat("RDS     :", basename(out_rds), "\n")

# =============================================================================
# 7) GeoTIFF — Fix E : inversion row top-down
# =============================================================================
CREATE_GEOTIFF <- as.logical(Sys.getenv("MAKE_TIFF", "TRUE"))
if (is.na(CREATE_GEOTIFF)) CREATE_GEOTIFF <- TRUE

if(CREATE_GEOTIFF) {
  cat("\n== 7) Creation du raster GeoTIFF ==\n")

  tryCatch({
    raster_data <- fi_dt[, .(grid_id, f_i_full)]
    raster_data <- raster_data[!is.na(f_i_full)]

    if(nrow(raster_data) > 0) {
      raster_data[, `:=`(
        col = (grid_id - 1L) %% GRID_COLS,
        row = (grid_id - 1L) %/% GRID_COLS
      )]

      r <- rast(
        nrows = GRID_ROWS, ncols = GRID_COLS,
        xmin = WORLD_XMIN, xmax = WORLD_XMAX,
        ymin = WORLD_YMIN, ymax = WORLD_YMAX,
        crs = "EPSG:6933"
      )
      names(r) <- "f_i_full"

      vals <- rep(NA_real_, ncell(r))

      # Terra indexes top-down, our rows are bottom-up
      inds <- (GRID_ROWS - 1L - raster_data$row) * ncol(r) + raster_data$col + 1L

      vals[inds] <- raster_data$f_i_full
      values(r) <- vals

      out_tif <- sprintf("~/scratch/output_V6/fi_grid_%s.tif", timestamp)
      writeRaster(
        r, out_tif,
        datatype  = "FLT4S",
        overwrite = TRUE,
        gdal      = c("COMPRESS=LZW", "TILED=YES", "BLOCKXSIZE=512", "BLOCKYSIZE=512")
      )

      cat("GeoTIFF cree :", basename(out_tif), "\n")
      cat("Statistiques raster :", nrow(raster_data), "cellules non-NA sur", ncell(r), "pixels\n")
    } else {
      cat("Aucune donnee f_i valide pour creer le raster\n")
    }
  }, error = function(e) {
    cat("Echec creation GeoTIFF :", e$message, "\n")
    cat("Les fichiers Parquet et RDS sont disponibles\n")
  })
} else {
  cat("\nCreation GeoTIFF desactivee\n")
}

cat("\nStep 5 merge termine avec succes !\n")
cat("Fichiers crees :\n")
cat("   -", basename(out_parquet), "\n")
cat("   -", basename(out_rds), "\n")
if(CREATE_GEOTIFF) cat("   -", sprintf("fi_grid_%s.tif", timestamp), "\n")
