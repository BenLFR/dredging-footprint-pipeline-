#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-6  ─  CALCUL DU CARBONE REMINÉRALISÉ (Cri) — corrigé
#  - Grille identique à constants.R (6933, 34735×14685)
#  - Utilise x/y/col/row de fi_grid si disponibles (pas de canevas 36k×18k)
#  - Caps physiques : f_i ∈ [0,1], C_ri ≤ C0i
# ────────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(data.table); library(terra); library(lubridate); library(arrow)
})
sf::sf_use_s2(FALSE)

# GRIT: constants.R dans le meme repertoire que ce script
script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
if (length(script_dir) == 0 || script_dir == "") script_dir <- "~/ais-pipeline/pipeline_V6"
source(file.path(script_dir, "constants.R"))

# Terra temp directory
tmp_terra <- file.path(path.expand("~"), "scratch/tmp_terra")
dir.create(tmp_terra, showWarnings = FALSE, recursive = TRUE)
terraOptions(tempdir = tmp_terra)

cat("--- Étape 6 : Calcul de Cri ---\n")

# Fichier f_i
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("ℹ️  Aucun fichier f_i spécifié. Recherche du plus récent…\n")
  fi_files <- list.files("~/scratch/output_V6/", pattern="^fi_grid_.*\\.(parquet|rds)$", full.names=TRUE)
  if(length(fi_files) == 0) stop("❌ Aucun fichier f_i trouvé dans ~/scratch/output_V6/")
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
} else fi_path <- args[1]
cat("✔️ Fichier f_i utilisé :", basename(fi_path), "\n")

# Lecture
fi_dt <- if (grepl("\\.parquet$", fi_path)) arrow::read_parquet(fi_path) else readRDS(fi_path)
setDT(fi_dt)
stopifnot("grid_id" %in% names(fi_dt))

# Canevas cible aligne Step-5 (cree tot pour xyFromCell)
template_raster <- terra::rast(nrows=GRID_ROWS, ncols=GRID_COLS, crs="EPSG:6933",
                               xmin=WORLD_XMIN, xmax=WORLD_XMAX, ymin=WORLD_YMIN, ymax=WORLD_YMAX)

# Reconstruit x/y via Terra (source de verite pour extraction + GeoTIFF)
# grid_id est bottom-up (row=0=sud), Terra est top-down (cell 1=NW)
# Conversion: terra_cell = (GRID_ROWS - 1 - row) * GRID_COLS + col + 1
fi_dt[, col := as.integer((grid_id - 1L) %% GRID_COLS)]
fi_dt[, row := as.integer((grid_id - 1L) %/% GRID_COLS)]
fi_dt[, terra_cell := (GRID_ROWS - 1L - row) * GRID_COLS + col + 1L]

if (!("x" %in% names(fi_dt) && "y" %in% names(fi_dt))) {
  xy <- terra::xyFromCell(template_raster, fi_dt$terra_cell)
  fi_dt[, `:=`(x = xy[,1], y = xy[,2])]
  cat("✅ Coordonnées x/y reconstruites via xyFromCell\n")
}

# Sanity check: roundtrip terra_cell -> xy -> terra_cell
n_check <- min(2000L, nrow(fi_dt))
check_idx <- fi_dt$terra_cell[sample.int(nrow(fi_dt), n_check)]
check_xy <- terra::xyFromCell(template_raster, check_idx)
check_back <- terra::cellFromXY(template_raster, check_xy)
if (!all(check_back == check_idx)) {
  stop("FATAL: grid_id <-> Terra cell roundtrip mismatch!")
}
cat("✅ Sanity check OK:", n_check, "cellules verifiees\n")

# Caps f_i par securite + NA -> 0 (pas de dredging = impact 0)
if ("f_i_full" %in% names(fi_dt)) {
  fi_dt[is.na(f_i_full), f_i_full := 0]
  fi_dt[, f_i_full := pmin(pmax(f_i_full, 0), 1)]
}
if ("f_i_conservative" %in% names(fi_dt)) {
  fi_dt[is.na(f_i_conservative), f_i_conservative := 0]
  fi_dt[, f_i_conservative := pmin(pmax(f_i_conservative, 0), 1)]
}

## 2) Chargement C0i (Atwood) et reprojection vers 6933 si besoin --------------
cat("🔄 Chargement des rasters C0i…\n")
carbon_dir <- path.expand("~/scratch/configuration/atwood_carbon_full")
carbon_files <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE)
if(length(carbon_files) == 0) stop("❌ Aucun TIF C0i dans ", carbon_dir)

carbon_rasters <- list()
for(file in carbon_files) {
  nm <- tools::file_path_sans_ext(basename(file))
  nm <- tolower(gsub(" ", "_", nm))
  r  <- terra::rast(file)
  if (!terra::compareGeom(r, template_raster, stopOnError = FALSE)) {
    cat("🔄 Reprojection :", basename(file), "→ EPSG:6933 (template)\n")
    r <- terra::project(r, template_raster)
  }
  carbon_rasters[[nm]] <- r
}

coords <- fi_dt[, .(x, y)]
for(nm in names(carbon_rasters)) {
  col_name <- paste0("C0i_", nm)
  fi_dt[[col_name]] <- terra::extract(carbon_rasters[[nm]], coords, ID=FALSE)[[1]]
  fi_dt[is.na(get(col_name)), (col_name) := 0]
  cat("✔️", col_name, "extrait\n")
}

# Colonnes centrales/bornes
stopifnot("C0i_mean_carbon_stock" %in% names(fi_dt))
fi_dt[, C0i := C0i_mean_carbon_stock]
if ("C0i_global_error_lower_bound" %in% names(fi_dt)) fi_dt[, C0i_lower := C0i_global_error_lower_bound]
if ("C0i_global_error_upper_bound" %in% names(fi_dt)) fi_dt[, C0i_upper := C0i_global_error_upper_bound]

## 3) Facteur de déplétion di ---------------------------------------------------
cat("🔄 Facteur de déplétion (di)…\n")
trawling_history_path <- path.expand("~/scratch/configuration/trawling_history.rds")
if (!file.exists(trawling_history_path)) {
  fi_dt[, di := 1.0]
  cat("⚠️  Historique absent → di=1.0\n")
} else {
  trawling_dt <- readRDS(trawling_history_path)
  setDT(trawling_dt)
  fi_dt <- merge(fi_dt, trawling_dt[, .(grid_id, years_trawled)], by="grid_id", all.x=TRUE)
  fi_dt[, di := fifelse(is.na(years_trawled), 1.0, fifelse(years_trawled > 10, 0.272, 1.0))]
  fi_dt[, years_trawled := NULL]
  cat("✅ di calculé\n")
}

## 4) C_ri (caps inclus) --------------------------------------------------------
cat("🔄 C_ri…\n")
fi_dt[, C_ri := pmin(C0i * f_i_full * di, C0i)]
if ("C0i_lower" %in% names(fi_dt)) fi_dt[, C_ri_lower := pmin(C0i_lower * f_i_full * di, C0i_lower)]
if ("C0i_upper" %in% names(fi_dt)) fi_dt[, C_ri_upper := pmin(C0i_upper * f_i_full * di, C0i_upper)]
fi_dt[, C_ri_conservative := pmin(C0i * f_i_conservative * di, C0i)]

## 5) Sauvegardes ---------------------------------------------------------------
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_prefix <- file.path(path.expand("~/scratch/output_V6/"), paste0("cri_final_", timestamp))

saveRDS(fi_dt, paste0(output_prefix, ".rds"))
cat("✔️ RDS écrit\n")
if(requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_parquet(fi_dt, paste0(output_prefix, ".parquet"))
  cat("✔️ Parquet écrit\n")
}

# GeoTIFF (optionnels mais utiles)
write_cri_raster <- function(values, filename) {
  g <- template_raster
  g[] <- NA_real_
  g[fi_dt$terra_cell] <- values
  writeRaster(g, filename, datatype = "FLT4S", overwrite = TRUE,
              gdal = c("COMPRESS=LZW", "TILED=YES"))
  cat("✔️", basename(filename), "écrit\n")
}
cat("🗺️  GeoTIFF…\n")
write_cri_raster(fi_dt$C_ri, paste0(output_prefix, ".tif"))
if ("C_ri_lower" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_lower, paste0(output_prefix, "_lower.tif"))
if ("C_ri_upper" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_upper, paste0(output_prefix, "_upper.tif"))

cat("✅ Étape 6 terminée\n")
