#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-6  ─  REMINERALISED CARBON CALCULATION (CRI)
# Also produces lower/upper bounds; robust coordinate handling
# Optimised version with improved memory management and robustness
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Libraries and Parameters -------------------------------------------------
pkgs <- c("sf","dplyr","data.table","terra","lubridate")
invisible(sapply(pkgs, function(pkg) suppressPackageStartupMessages(library(pkg, character.only=TRUE))))

# Configure Terra to avoid memory issues
terraOptions(tempdir = path.expand("~/scratch/tmp_terra"))

cat("--- Étape 6 : Calcul de Cri ---\n")

# Argument: path to the fi_grid file produced by step 5
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  # No argument given: find the most recent file
  cat("No f_i file specified. Searching for the most recent...\n")
  fi_files <- list.files("~/scratch/output_V6/", pattern="^fi_grid_.*\\.(parquet|rds)$", full.names=TRUE)
  if(length(fi_files) == 0) stop("No f_i file found in ~/scratch/output_V6/")
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
} else {
  fi_path <- args[1]
}
cat("✔ Fichier f_i utilisé :", basename(fi_path), "\n")

## 1.  Load f_i data --------------------------------------------------------------
cat("1. Loading f_i data...\n")
if (grepl("\\.parquet$", fi_path)) {
  if(!requireNamespace("arrow", quietly=TRUE)) stop("The 'arrow' package is required to read Parquet files.")
  fi_dt <- arrow::read_parquet(fi_path)
} else {
  fi_dt <- readRDS(fi_path)
}
setDT(fi_dt)
cat(nrow(fi_dt), "cells loaded.\n")

# Add x/y columns if missing
if (!("x" %in% names(fi_dt) && "y" %in% names(fi_dt))) {
  if ("col" %in% names(fi_dt) && "row" %in% names(fi_dt)) {
    fi_dt[, x := -18000000 + col*1000 + 500]
    fi_dt[, y :=  9000000 - row*1000 - 500]
    cat("x/y coordinates reconstructed from col/row.\n")
  } else if ("grid_id" %in% names(fi_dt)) {
    fi_dt[, col := (grid_id-1L) %% 36000L]
    fi_dt[, row := (grid_id-1L) %/% 36000L]
    fi_dt[, x := -18000000 + col*1000 + 500]
    fi_dt[, y :=  9000000 - row*1000 - 500]
    cat("x/y coordinates reconstructed from grid_id.\n")
  } else {
    stop("Cannot recover coordinates: neither x/y nor col/row nor grid_id found in fi_dt.")
  }
}

# Verify grid_id contiguity
stopifnot(all(fi_dt$grid_id >= 1 & fi_dt$grid_id <= 18000*36000))
cat("grid_id contiguity check OK.\n")

coords <- fi_dt[, .(x, y)]

## 2.  Load carbon stock (C0i) and uncertainties ------------------------------------------
cat("2. Loading carbon stock (C0i) and uncertainties...\n")
carbon_dir <- Sys.getenv("CARBON_DIR", path.expand("~/scratch/configuration/atwood_carbon_full"))

# Charger tous les fichiers TIF de carbone
carbon_files <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE)
cat("TIF files found:", length(carbon_files), "\n")
cat("   ", paste(basename(carbon_files), collapse=", "), "\n")

if(length(carbon_files) == 0) {
  stop("No carbon stock TIF files found in ", carbon_dir,
       "\n   Please upload Atwood et al. data there.")
}

# Load carbon rasters
carbon_rasters <- list()
for(file in carbon_files) {
  name <- tools::file_path_sans_ext(basename(file))
  name_clean <- tolower(gsub(" ", "_", name)) # e.g. "Mean carbon_stock" -> "mean_carbon_stock"
  carbon_rasters[[name_clean]] <- terra::rast(file)
  cat("Raster loaded:", basename(file), "->", name_clean, "\n")
}

# Reproject once if needed (optimisation)
template_raster <- terra::rast(nrows=18000, ncols=36000, crs="EPSG:6933",
                              xmin=-18000000, xmax=18000000, ymin=-9000000, ymax=9000000)

for(name in names(carbon_rasters)) {
  # Check if projection matches
  if (!terra::compareGeom(carbon_rasters[[name]], template_raster, stopOnError = FALSE)) {
    cat("Reprojecting raster", name, "to EPSG:6933...\n")
    carbon_rasters[[name]] <- terra::project(carbon_rasters[[name]], template_raster)
  }
}

# Extract values for each cell
for(name in names(carbon_rasters)) {
  col_name <- paste0("C0i_", name)
  fi_dt[[col_name]] <- terra::extract(carbon_rasters[[name]], coords, ID=FALSE)[[1]]
  fi_dt[is.na(get(col_name)), (col_name) := 0] # Replace NA with 0
  cat(col_name, "extracted for", sum(fi_dt[[col_name]] > 0), "cells.\n")
}

# Determine central layer and min/max bounds
if("C0i_mean_carbon_stock" %in% names(fi_dt)) {
  fi_dt$C0i <- fi_dt$C0i_mean_carbon_stock
} else {
  stop("Raster 'Mean carbon_stock' not found. Check the file name.")
}
if("C0i_global_error_lower_bound" %in% names(fi_dt)) {
  fi_dt$C0i_lower <- fi_dt$C0i_global_error_lower_bound
} else {
  cat("WARNING: 'global_error_lower_bound' raster not found. No Cri_lower.\n")
}
if("C0i_global_error_upper_bound" %in% names(fi_dt)) {
  fi_dt$C0i_upper <- fi_dt$C0i_global_error_upper_bound
} else {
  cat("WARNING: 'global_error_upper_bound' raster not found. No Cri_upper.\n")
}
cat("Carbon stock (C0i) extracted for", sum(fi_dt$C0i > 0), "cells.\n")

## 3.  Compute depletion factor (di) --------------------------------------
cat("3. Computing depletion factor (di)...\n")
trawling_history_path <- path.expand("~/scratch/configuration/trawling_history.rds")
if (!file.exists(trawling_history_path)) {
  cat("Trawling history file not found at:", trawling_history_path, "\n")
  cat("   Applying default depletion factor (di) of 1.0\n")
  fi_dt[, di := 1.0]
} else {
  cat("Trawling history file found.\n")
  trawling_dt <- readRDS(trawling_history_path)
  setDT(trawling_dt)
  
  #  FIX: use fifelse instead of ifelse with na argument
  if ("years_trawled" %in% names(trawling_dt)) {
  fi_dt <- merge(fi_dt, trawling_dt[, .(grid_id, years_trawled)], by = "grid_id", all.x = TRUE)
    fi_dt[, di := fifelse(is.na(years_trawled), 1.0,
                          fifelse(years_trawled > 10, 0.272, 1.0))]
  } else {
    fi_dt[, di := 1.0]
  }
  cat("Depletion factor (di) computed.\n")
}

## 4.  Compute final Cri --------------------------------------------------------
cat("4. Computing remineralised carbon (Cri)...\n")
fi_dt[, C_ri := C0i * f_i_full * di]
fi_dt[, C_ri_conservative := C0i * f_i_conservative * di]
if("C0i_lower" %in% names(fi_dt)) {
  fi_dt[, C_ri_lower := C0i_lower * f_i_full * di]
}
if("C0i_upper" %in% names(fi_dt)) {
  fi_dt[, C_ri_upper := C0i_upper * f_i_full * di]
}
cat("Cri (central and uncertainty bounds) computed.\n")

## 5.  Final save ----------------------------------------------------------
cat("5. Final save...\n")
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_prefix <- file.path(path.expand("~/scratch/output_V6/"), paste0("cri_final_", timestamp))

# Save full dataset
out_rds <- paste0(output_prefix, ".rds")
saveRDS(fi_dt, out_rds)
cat("Full dataset saved as RDS:", basename(out_rds), "\n")
if(requireNamespace("arrow", quietly = TRUE)) {
  out_parquet <- paste0(output_prefix, ".parquet")
  arrow::write_parquet(fi_dt, out_parquet)
  cat("Full dataset saved as Parquet:", basename(out_parquet), "\n")
}

# Optimised block-write function for rasters
write_cri_raster <- function(values, filename) {
  cat("Creating raster:", basename(filename), "\n")
  g <- rast(nrows = 18000, ncols = 36000,
            xmin = -18000000, xmax = 18000000,
            ymin =  -9000000, ymax =   9000000,
            crs  = "EPSG:6933")
  g[] <- NA_real_
  g[fi_dt$grid_id] <- values
  writeRaster(g, filename, datatype = "FLT4S", overwrite = TRUE,
              gdal = c("COMPRESS=LZW", "TILED=YES"))
  cat("Raster saved:", basename(filename), "\n")
}

# Save GeoTIFF rasters (central, lower, upper)
cat("Creating GeoTIFF rasters...\n")

# Main (central) raster
write_cri_raster(fi_dt$C_ri, paste0(output_prefix, ".tif"))

# Lower bound raster
if("C_ri_lower" %in% names(fi_dt)) {
  write_cri_raster(fi_dt$C_ri_lower, paste0(output_prefix, "_lower.tif"))
}

# Upper bound raster
if("C_ri_upper" %in% names(fi_dt)) {
  write_cri_raster(fi_dt$C_ri_upper, paste0(output_prefix, "_upper.tif"))
}

cat("\nDone.\n")
