#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-6 — REMINERALISED CARBON CALCULATION (Cri)
#  - Grid identical to constants.R (EPSG:6933, 34735x14685)
#  - Utilise x/y/col/row de fi_grid si disponibles (pas de canevas 36k×18k)
#  - Caps physiques : f_i ∈ [0,1], C_ri ≤ C0i
# ────────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(data.table); library(terra); library(lubridate); library(arrow)
})
sf::sf_use_s2(FALSE)

# constants.R must be in the same directory as this script
script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
if (length(script_dir) == 0 || script_dir == "") script_dir <- getwd()
source(file.path(script_dir, "constants.R"))

# ---- PATH CONFIGURATION (override via env vars) ----
scratch_dir <- path.expand(Sys.getenv("SCRATCH_DIR", unset = "~/scratch"))
config_dir  <- path.expand(Sys.getenv("CONFIG_DIR",  unset = file.path(scratch_dir, "configuration")))
output_dir  <- path.expand(Sys.getenv("OUTPUT_DIR",  unset = file.path(scratch_dir, "output_V6")))

# Terra temp directory
tmp_terra <- file.path(scratch_dir, "tmp_terra")
dir.create(tmp_terra, showWarnings = FALSE, recursive = TRUE)
terraOptions(tempdir = tmp_terra)

cat("--- Step 6: Cri calculation ---\n")

# Fichier f_i
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("[INFO] No f_i file specified; searching for most recent...\n")
  fi_files <- list.files(output_dir, pattern="^fi_grid_.*\\.(parquet|rds)$", full.names=TRUE)
  if(length(fi_files) == 0) stop("No f_i file found in ", output_dir)
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
} else fi_path <- args[1]
cat("[INFO] f_i file:", basename(fi_path), "\n")

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
  cat("[INFO] x/y coordinates reconstructed via xyFromCell\n")
}

# Sanity check: roundtrip terra_cell -> xy -> terra_cell
n_check <- min(2000L, nrow(fi_dt))
check_idx <- fi_dt$terra_cell[sample.int(nrow(fi_dt), n_check)]
check_xy <- terra::xyFromCell(template_raster, check_idx)
check_back <- terra::cellFromXY(template_raster, check_xy)
if (!all(check_back == check_idx)) {
  stop("FATAL: grid_id <-> Terra cell roundtrip mismatch!")
}
cat("[INFO] Sanity check OK:", n_check, "cells verified\n")

# Cap f_i for safety; NA -> 0 (no dredging = zero impact)
if ("f_i_full" %in% names(fi_dt)) {
  fi_dt[is.na(f_i_full), f_i_full := 0]
  fi_dt[, f_i_full := pmin(pmax(f_i_full, 0), 1)]
}
if ("f_i_conservative" %in% names(fi_dt)) {
  fi_dt[is.na(f_i_conservative), f_i_conservative := 0]
  fi_dt[, f_i_conservative := pmin(pmax(f_i_conservative, 0), 1)]
}

## 2) Load C0i rasters (Atwood) and reproject to EPSG:6933 if needed ----------
cat("[INFO] Loading C0i rasters...\n")
carbon_dir <- Sys.getenv("CARBON_DIR", unset = file.path(config_dir, "atwood_carbon_full"))
carbon_files <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE)
if(length(carbon_files) == 0) stop("No C0i TIF files in ", carbon_dir)

carbon_rasters <- list()
for(file in carbon_files) {
  nm <- tools::file_path_sans_ext(basename(file))
  nm <- tolower(gsub(" ", "_", nm))
  r  <- terra::rast(file)
  if (!terra::compareGeom(r, template_raster, stopOnError = FALSE)) {
    cat("[INFO] Reprojecting:", basename(file), "to EPSG:6933\n")
    r <- terra::project(r, template_raster)
  }
  carbon_rasters[[nm]] <- r
}

coords <- fi_dt[, .(x, y)]
for(nm in names(carbon_rasters)) {
  col_name <- paste0("C0i_", nm)
  fi_dt[[col_name]] <- terra::extract(carbon_rasters[[nm]], coords, ID=FALSE)[[1]]
  fi_dt[is.na(get(col_name)), (col_name) := 0]
  cat("[INFO]", col_name, "extracted\n")
}

# Colonnes centrales/bornes
stopifnot("C0i_mean_carbon_stock" %in% names(fi_dt))
fi_dt[, C0i := C0i_mean_carbon_stock]
if ("C0i_global_error_lower_bound" %in% names(fi_dt)) fi_dt[, C0i_lower := C0i_global_error_lower_bound]
if ("C0i_global_error_upper_bound" %in% names(fi_dt)) fi_dt[, C0i_upper := C0i_global_error_upper_bound]

## 3) Depletion factor di -------------------------------------------------------
cat("[INFO] Computing depletion factor (di)...\n")
trawling_history_path <- Sys.getenv("TRAWLING_HISTORY_FILE", unset = file.path(config_dir, "trawling_history.rds"))
if (!file.exists(trawling_history_path)) {
  fi_dt[, di := 1.0]
  cat("[WARN] Trawling history absent — di set to 1.0\n")
} else {
  trawling_dt <- readRDS(trawling_history_path)
  setDT(trawling_dt)
  fi_dt <- merge(fi_dt, trawling_dt[, .(grid_id, years_trawled)], by="grid_id", all.x=TRUE)
  fi_dt[, di := fifelse(is.na(years_trawled), 1.0, fifelse(years_trawled > 10, 0.272, 1.0))]
  fi_dt[, years_trawled := NULL]
  cat("[INFO] di computed\n")
}

## 4) C_ri (with caps) ----------------------------------------------------------
cat("[INFO] Computing C_ri...\n")
fi_dt[, C_ri := pmin(C0i * f_i_full * di, C0i)]
if ("C0i_lower" %in% names(fi_dt)) fi_dt[, C_ri_lower := pmin(C0i_lower * f_i_full * di, C0i_lower)]
if ("C0i_upper" %in% names(fi_dt)) fi_dt[, C_ri_upper := pmin(C0i_upper * f_i_full * di, C0i_upper)]
fi_dt[, C_ri_conservative := pmin(C0i * f_i_conservative * di, C0i)]

## 5) Save outputs --------------------------------------------------------------
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_prefix <- file.path(output_dir, paste0("cri_final_", timestamp))

saveRDS(fi_dt, paste0(output_prefix, ".rds"))
cat("[INFO] RDS written\n")
if(requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_parquet(fi_dt, paste0(output_prefix, ".parquet"))
  cat("[INFO] Parquet written\n")
}

# GeoTIFFs (optional but useful for visualisation)
write_cri_raster <- function(values, filename) {
  g <- template_raster
  g[] <- NA_real_
  g[fi_dt$terra_cell] <- values
  writeRaster(g, filename, datatype = "FLT4S", overwrite = TRUE,
              gdal = c("COMPRESS=LZW", "TILED=YES"))
  cat("[INFO]", basename(filename), "written\n")
}
cat("[INFO] Writing GeoTIFFs...\n")
write_cri_raster(fi_dt$C_ri, paste0(output_prefix, ".tif"))
if ("C_ri_lower" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_lower, paste0(output_prefix, "_lower.tif"))
if ("C_ri_upper" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_upper, paste0(output_prefix, "_upper.tif"))

cat("Step 6 complete\n")
