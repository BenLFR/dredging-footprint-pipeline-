#!/usr/bin/env Rscript
OUT_DIR <- Sys.getenv("OUT_DIR", "~/scratch/output_V6")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
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

source("~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/constants.R")
terraOptions(tempdir = "/scratch/benl/tmp")

cat("--- Étape 6 : Calcul de Cri ---\n")

# Fichier f_i
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("ℹ️  Aucun fichier f_i spécifié. Recherche du plus récent…\n")
  fi_files <- list.files(OUT_DIR, pattern="^fi_grid_.*\\.(parquet|rds)$", full.names=TRUE)
  if(length(fi_files) == 0) stop("❌ Aucun fichier f_i trouvé dans ~/scratch/output_V6/")
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
} else fi_path <- args[1]
cat("✔️ Fichier f_i utilisé :", basename(fi_path), "\n")

# Lecture
fi_dt <- if (grepl("\\.parquet$", fi_path)) arrow::read_parquet(fi_path) else readRDS(fi_path)
setDT(fi_dt)
stopifnot("grid_id" %in% names(fi_dt))

# Reconstruit col/row/x/y si nécessaire — en utilisant constants.R (PAS 36k×18k)
if (!("col" %in% names(fi_dt) && "row" %in% names(fi_dt))) {
  fi_dt[, col := as.integer((grid_id-1L) %% GRID_COLS)]
  fi_dt[, row := as.integer((grid_id-1L) %/% GRID_COLS)]
}
if (!("x" %in% names(fi_dt) && "y" %in% names(fi_dt))) {
  fi_dt[, x := WORLD_XMIN + col*CELL_SIZE_M + CELL_SIZE_M/2]
  fi_dt[, y := WORLD_YMIN + row*CELL_SIZE_M + CELL_SIZE_M/2]
  cat("✅ Coordonnées x/y reconstruites sur la grille Step-5\n")
}

# Caps f_i par sécurité (au cas où)
if ("f_i_full" %in% names(fi_dt))  fi_dt[, f_i_full := pmin(pmax(f_i_full, 0), 1)]
if ("f_i_conservative" %in% names(fi_dt)) fi_dt[, f_i_conservative := pmin(pmax(f_i_conservative, 0), 1)]

## 2) Chargement C0i (Atwood) et reprojection vers 6933 si besoin --------------
cat("🔄 Chargement des rasters C0i…\n")
carbon_dir <- path.expand("/home/benl/scratch/configuration/atwood_carbon_full")
carbon_files <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE)
if(length(carbon_files) == 0) stop("❌ Aucun TIF C0i dans ", carbon_dir)

# Canevas cible aligné Step-5
template_raster <- terra::rast(nrows=GRID_ROWS, ncols=GRID_COLS, crs="EPSG:6933",
                               xmin=WORLD_XMIN, xmax=WORLD_XMAX, ymin=WORLD_YMIN, ymax=WORLD_YMAX)

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
output_prefix <- file.path(OUT_DIR, paste0("cri_final_", timestamp))

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
  g[fi_dt$grid_id] <- values
  writeRaster(g, filename, datatype = "FLT4S", overwrite = TRUE,
              gdal = c("COMPRESS=LZW", "TILED=YES"))
  cat("✔️", basename(filename), "écrit\n")
}
cat("🗺️  GeoTIFF…\n")
write_cri_raster(fi_dt$C_ri, paste0(output_prefix, ".tif"))
if ("C_ri_lower" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_lower, paste0(output_prefix, "_lower.tif"))
if ("C_ri_upper" %in% names(fi_dt)) write_cri_raster(fi_dt$C_ri_upper, paste0(output_prefix, "_upper.tif"))

cat("✅ Étape 6 terminée\n")
