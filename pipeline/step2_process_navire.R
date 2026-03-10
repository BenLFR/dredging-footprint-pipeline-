#!/usr/bin/env Rscript
# ====================================================================
# STEP 2: INDIVIDUAL VESSEL PROCESSING (ARRAY JOB)
# ====================================================================

cat("=== INDIVIDUAL VESSEL PROCESSING ===\n")
cat("Start:", format(Sys.time()), "\n")

# CRITICAL R CONFIGURATION - BEFORE LOADING PACKAGES
.libPaths("~/R/library")
cat("R library path:", .libPaths()[1], "\n")

# ---- ANTI-GFORCE CONFIGURATION ----
options(mc.cores = 1)
Sys.setenv(MC_CORES = 1)
Sys.setenv(DT_GForce = "FALSE")  # CRITICAL: disables gforce
Sys.setenv(OMP_NUM_THREADS = 1)

# ---- LOAD PACKAGES ----
suppressPackageStartupMessages({
  library(data.table)
  
  # Test qs with fallback (same as step1)
  use_qs <- FALSE
  tryCatch({
    if (requireNamespace("qs", quietly = TRUE)) {
      library(qs)
      use_qs <- TRUE
      cat("Package qs available\n")
    }
  }, error = function(e) {
    cat("Package qs not available - falling back to RDS\n")
  })
  
  library(lubridate)
  library(yaml)
  library(solitude)   # Isolation Forest
  library(mclust)     # GMM
  library(zoo)        # rollmean
  library(sf)         # geospatial filters
})
sf::sf_use_s2(TRUE)  # ensure buffers/distances are computed in metres on WGS84

# Configuration data.table conservative
setDTthreads(1)  # Mono-thread obligatoire
options(datatable.optimize = 1)

cat("Packages loaded - single-thread configuration active\n")

# ---- GEOSPATIAL PARAMETERS ----
# The land mask is optional; if absent, polygon-based geospatial filters are
# skipped. An RDS or GPkg file can be provided via the LAND_MASK_FILE env var.
# A small buffer (metres) prevents false positives near quayside.
land_mask_path   <- Sys.getenv("LAND_MASK_FILE", unset = "~/ais-pipeline/configuration/land_mask/land_polygons.shp")
land_buffer_m    <- as.numeric(Sys.getenv("LAND_MASK_BUFFER_M", unset = "200"))
near_coast_km    <- as.numeric(Sys.getenv("LAND_NEAR_COAST_KM", unset = "10"))
default_speed_kn <- as.numeric(Sys.getenv("MAX_JUMP_SPEED_KN", unset = "30"))
spike_dist_min_nm   <- as.numeric(Sys.getenv("SPIKE_DIST_MIN_NM", unset = "1"))
spike_bridge_max_nm <- as.numeric(Sys.getenv("SPIKE_BRIDGE_MAX_NM", unset = "0.3"))

# ---- UTILITY FUNCTIONS ----
haversine_nm <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  (r * c) / 1852  # in nautical miles
}

load_land_polygons <- function(path, buffer_m = 0) {
  if (!file.exists(path)) {
    cat("Land mask not found (", path, ") - land filters disabled\n")
    return(NULL)
  }

  land <- if (grepl("\\.gpkg$", path, ignore.case = TRUE) ||
              grepl("\\.shp$", path, ignore.case = TRUE)) {
    sf::st_read(path, quiet = TRUE)
  } else {
    readRDS(path)
  }
  if (!inherits(land, "sf")) {
    stop("Land mask must be an sf object")
  }

  if (isFALSE(sf::st_is_longlat(land))) {
    land <- sf::st_transform(land, 4326)
  }

  land <- sf::st_make_valid(land)
  if (!is.na(buffer_m) && buffer_m != 0) {
    land <- sf::st_transform(land, 3857)
    land <- sf::st_buffer(land, dist = buffer_m)
    land <- sf::st_transform(land, 4326)
  }
  land
}

flag_geospatial_anomalies <- function(dt, land_polygons, near_coast_km, default_speed_kn,
                                      spike_dist_min_nm = 1, spike_bridge_max_nm = 0.3) {
  # Split into 2 steps to avoid 'dt_sec not found' error
  # Step 1: create gc_nm and dt_sec
  dt[, `:=`(
    gc_nm = haversine_nm(Lat, Lon, shift(Lat), shift(Lon)),
    dt_sec = as.numeric(delta_t)
  )]
  
  # Step 2: create avg_speed_kn and max_plausible_kn which depend on dt_sec
  dt[, `:=`(
    avg_speed_kn = ifelse(!is.na(dt_sec) & dt_sec > 0, gc_nm / dt_sec * 3600, NA_real_),
    max_plausible_kn = fifelse(!is.na(Service_speed), Service_speed * 1.5, default_speed_kn)
  )]
  dt[, geo_flag := FALSE]

  # 1) Points on land (if mask available)
  if (!is.null(land_polygons)) {
    pts_sf <- sf::st_as_sf(dt, coords = c("Lon", "Lat"), crs = 4326, remove = FALSE)
    bbox <- sf::st_bbox(pts_sf)
    bbox_expanded <- bbox + c(-near_coast_km / 111, near_coast_km / 111,
                              -near_coast_km / 111, near_coast_km / 111)
    land_local <- sf::st_crop(land_polygons, bbox_expanded)
    if (is.null(land_local) || nrow(land_local) == 0) {
      land_local <- land_polygons
    }

    on_land <- lengths(sf::st_intersects(pts_sf, land_local)) > 0
    dt[on_land, geo_flag := TRUE]

    # 2) Segments crossing land (limited to coastal zones for performance)
    near_land <- lengths(sf::st_is_within_distance(pts_sf, land_local, dist = near_coast_km * 1000)) > 0
    segment_idx <- which(near_land | shift(near_land, type = "lead", fill = FALSE))
    segment_idx <- segment_idx[segment_idx < nrow(dt)]
    if (length(segment_idx)) {
      seg_lines <- sf::st_sfc(
        mapply(
          function(i) sf::st_linestring(matrix(c(dt$Lon[i], dt$Lon[i + 1], dt$Lat[i], dt$Lat[i + 1]), ncol = 2)),
          segment_idx,
          SIMPLIFY = FALSE
        ),
        crs = 4326
      )
      crosses_land <- lengths(sf::st_intersects(seg_lines, land_local)) > 0
      if (any(crosses_land)) {
        bad_idx <- segment_idx[crosses_land] + 1L

        # Only flag if the time gap is short (impossible to go around the land)
        # If gap > 1h, the vessel could legitimately have rounded the land mass
        dt_sec_at_idx <- dt$dt_sec[bad_idx]
        short_time_jumps <- !is.na(dt_sec_at_idx) & dt_sec_at_idx < 3600

        dt[bad_idx[short_time_jumps], geo_flag := TRUE]
      }
    }
  }

  # 3) Distance/time jumps (unreasonable average speed)
  dt[avg_speed_kn > max_plausible_kn, geo_flag := TRUE]
  dt[gc_nm > 100 & dt_sec <= 3600, geo_flag := TRUE]  # large jump in under 1 h

  # 4) Short off-track sequences (isolated spikes)
  dt[, `:=`(
    dist_prev = haversine_nm(shift(Lat), shift(Lon), Lat, Lon),
    dist_next = haversine_nm(Lat, Lon, shift(Lat, type = "lead"), shift(Lon, type = "lead")),
    dist_prev_next = haversine_nm(shift(Lat), shift(Lon), shift(Lat, type = "lead"), shift(Lon, type = "lead"))
  )]

  spike_idx <- which(dt$dist_prev > spike_dist_min_nm &
                       dt$dist_next > spike_dist_min_nm &
                       dt$dist_prev_next < spike_bridge_max_nm)
  if (length(spike_idx)) dt[spike_idx, geo_flag := TRUE]

  dt[, c("gc_nm", "dt_sec", "avg_speed_kn", "max_plausible_kn", "dist_prev", "dist_next", "dist_prev_next") := NULL]
  dt
}

# ---- ENVIRONMENT PARAMETERS ----
task_id <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID"))
split_job_id <- Sys.getenv("SPLIT_JOB_ID")

cat("Task ID:", task_id, "\n")
cat("Split Job ID:", split_job_id, "\n")

# ---- FILE PATHS ----
split_dir <- file.path("~/scratch", paste0("ais_split_", split_job_id))
metadata_file <- file.path(split_dir, "navires_metadata.csv")

if (!file.exists(metadata_file)) {
  stop("Metadata not found: ", metadata_file)
}

# Read metadata
metadata <- fread(metadata_file)
cat("Metadata loaded:", nrow(metadata), "vessels\n")

if (task_id > nrow(metadata)) {
  stop("Task ID ", task_id, " > vessel count ", nrow(metadata))
}

# ---- SELECT VESSEL ----
navire_info <- metadata[task_id]
input_file <- navire_info$file_path
navire_name <- navire_info$Navire

cat("Vessel selected:", navire_name, "\n")
cat("Input file:", input_file, "\n")

if (!file.exists(input_file)) {
  stop("Vessel file not found: ", input_file)
}

# ---- LOAD VESSEL DATA ----
cat("Loading vessel data...\n")
system.time({
  # Auto-detect format (qs or rds)
  if (grepl("\\.qs$", input_file)) {
    # QS format
    dt_nav <- qs::qread(input_file, as.data.table = TRUE)
    cat("QS format detected and loaded\n")
  } else if (grepl("\\.rds$", input_file)) {
    # RDS format
    dt_nav <- readRDS(input_file)
    setDT(dt_nav)  # Ensure it is a data.table
    cat("RDS format detected and loaded\n")
  } else {
    stop("Unrecognised file format: ", input_file)
  }
})

# Normalise ssvid to character everywhere
if ("ssvid" %in% names(dt_nav)) dt_nav[, ssvid := as.character(ssvid)]

cat("Data loaded:", nrow(dt_nav), "observations\n")

# ------------------------------------------------------------------
# READ VESSEL SPECIFICATIONS
# ------------------------------------------------------------------
spec_file <- "~/ais-pipeline/configuration/ship_specs.yaml"
if (!file.exists(spec_file))
  stop("ship_specs.yaml not found: ", spec_file)

spec_list  <- yaml::read_yaml(spec_file)$ship_specs
ship_specs <- rbindlist(spec_list, fill = TRUE)

## --- fix BEGIN -------------------------------------------------------
# 1) normalise type
ship_specs[, ssvid := as.character(ssvid)]

# 2) keep first row per ssvid (removes duplicates)
#    unique(..., by="ssvid") works from data.table 1.14.4;
#    .SD[1] is universally safe.
ship_specs <- ship_specs[, .SD[1], by = ssvid]
## --- fix END ---------------------------------------------------------

# reformat
setnames(ship_specs, "service_speed_kn", "Service_speed")
setkey(ship_specs, ssvid)

# (2) Explicit conversion immediately after merge
if ("ssvid" %chin% names(dt_nav)) {
  dt_nav <- merge(dt_nav, ship_specs[, .(ssvid, Service_speed, dredge_width_m, dredging_depth_m)],
                  by = "ssvid", all.x = TRUE)
  dt_nav[, Service_speed := as.numeric(Service_speed)]
  # Ensure spec columns are numeric
  dt_nav[, `:=`(dredge_width_m = as.numeric(dredge_width_m),
                dredging_depth_m = as.numeric(dredging_depth_m))]
  # Set key to speed up operations
  setkey(dt_nav, ssvid)
} else {
  warning("ssvid column missing: cannot merge vessel specs")
}

# (4) Warn if Service_speed is entirely missing
if (!"Service_speed" %chin% names(dt_nav) || all(is.na(dt_nav$Service_speed))) {
  warning("Aucune vitesse de service pour ", navire_name)
}

# -----------------------------------------------------------------
# PHYSICAL SPEED FILTER (service_speed × 1.15)
# -----------------------------------------------------------------
if ("Service_speed" %chin% names(dt_nav)) {
  dt_nav[, speed_limit := Service_speed * 1.15]
  n_before <- nrow(dt_nav)
  dt_nav   <- dt_nav[is.na(speed_limit) | Speed <= speed_limit]
  n_after  <- nrow(dt_nav)
  cat(sprintf(" Filtre vitesse physique : %d → %d lignes (%.2f %% conservées)\n",
              n_before, n_after, 100 * n_after / n_before))
  dt_nav[, speed_limit := NULL]
  # (3) Keep specs for step 3
  # dt_nav[, Service_speed := NULL]  # KEPT for step 3
}

# Initial preparation for geospatial filters (delta_t before filtering)
setorder(dt_nav, Timestamp)
dt_nav[, delta_t := c(NA_real_, diff(as.numeric(Timestamp)))]

land_polygons <- load_land_polygons(land_mask_path, buffer_m = land_buffer_m)

cat("Applying geospatial filters (land, segments, jumps)...\n")
n_before_geo <- nrow(dt_nav)

# Iterative filtering to handle tight curves around land masses
iteration <- 0
max_iterations <- 3
total_removed <- 0

repeat {
  iteration <- iteration + 1
  cat(sprintf("  Itération %d...\n", iteration))

  # Apply geospatial filtering
  dt_nav <- flag_geospatial_anomalies(dt_nav, land_polygons, near_coast_km, default_speed_kn,
                                      spike_dist_min_nm = spike_dist_min_nm,
                                      spike_bridge_max_nm = spike_bridge_max_nm)

  # Count flagged points
  n_flagged <- sum(dt_nav$geo_flag, na.rm = TRUE)

  # If no points to remove, we are done
  if (n_flagged == 0) {
    cat("  No new points to remove\n")
    dt_nav[, geo_flag := NULL]
    break
  }

  # If max iterations reached
  if (iteration >= max_iterations) {
    cat(sprintf("  Max iterations reached (%d), %d points still flagged\n",
                max_iterations, n_flagged))
    dt_nav <- dt_nav[geo_flag == FALSE | is.na(geo_flag)]
    dt_nav[, geo_flag := NULL]
    total_removed <- total_removed + n_flagged
    break
  }

  # Remove flagged points
  dt_nav <- dt_nav[geo_flag == FALSE | is.na(geo_flag)]
  dt_nav[, geo_flag := NULL]
  total_removed <- total_removed + n_flagged

  cat(sprintf("  → %d points supprimés (total cumulé: %d)\n", n_flagged, total_removed))

  # Recalculate delta_t for next iteration (required after point removal)
  setorder(dt_nav, Timestamp)
  dt_nav[, delta_t := c(NA_real_, diff(as.numeric(Timestamp)))]
}

n_after_geo <- nrow(dt_nav)
cat(sprintf(" Filtres géospatiaux : %d lignes supprimées en %d itération(s) (%.2f %%)\n",
            n_before_geo - n_after_geo, iteration,
            if (n_before_geo > 0) 100 * (n_before_geo - n_after_geo) / n_before_geo else 0))
cat("   - Total geospatial anomalies detected:", total_removed, "\n")

# (1) Compute derivatives just before Isolation Forest (after geospatial filtering)
setorder(dt_nav, Timestamp)
dt_nav[, delta_t       := c(NA_real_, diff(as.numeric(Timestamp)))]
dt_nav[, Course_change := c(NA_real_, abs(diff(Course)))]
dt_nav[Course_change > 180, Course_change := 360 - Course_change]
dt_nav[, Accel         := c(NA_real_, diff(Speed))]

# ---- LOAD CONFIGURATION ----
config_file <- "~/ais-pipeline/configuration/outlier_config_V6.yaml"
if (file.exists(config_file)) {
  config <- yaml.load_file(config_file)
  # Use parameters from the isolation_forest section
  outlier_config <- list(
    contamination_rate = config$isolation_forest$contamination_rate,
    if_sample_size = config$isolation_forest$sample_size,
    if_num_trees = config$isolation_forest$num_trees,
    memory_conservative = TRUE
  )
  cat("Configuration loaded:", config_file, "\n")
} else {
  # Default ultra-conservative configuration
  outlier_config <- list(
    contamination_rate = 0.02,
    if_sample_size = 256,
    if_num_trees = 25,
    memory_conservative = TRUE
  )
  cat("Default configuration applied\n")
}

cat(" Paramètres IF: contamination =", outlier_config$contamination_rate, 
    "| trees =", outlier_config$if_num_trees, "\n")

# ---- OPTIMISED ISOLATION FOREST FUNCTIONS ----
detect_outliers_IF_optimized <- function(dt, config) {
  cat("  Isolation Forest starting...\n")

  # Prepare features (basic set for a single vessel)
  features <- c("Lat", "Lon")
  if ("delta_t" %in% names(dt)) features <- c(features, "delta_t")
  if ("Speed" %in% names(dt)) features <- c(features, "Speed")
  
  # Extract numeric data
  dt_features <- dt[, ..features]
  dt_features <- dt_features[complete.cases(dt_features)]
  
  if (nrow(dt_features) < 50) {
    cat("  Too few observations (", nrow(dt_features), ") - skipping IF\n")
    return(rep(FALSE, nrow(dt)))
  }
  
  # Isolation Forest with conservative parameters
  if_model <- isolationForest$new(
    sample_size = min(config$if_sample_size, nrow(dt_features)),
    num_trees = config$if_num_trees,
    seed = 42
  )
  
  if_model$fit(dt_features)
  
  # Prediction
  scores <- if_model$predict(dt_features)
  outliers <- scores$anomaly_score > quantile(scores$anomaly_score, 
                                             1 - config$contamination_rate)
  
  # Align with original data
  result <- rep(FALSE, nrow(dt))
  if (nrow(dt_features) == nrow(dt)) {
    result <- outliers
  } else {
    # Case with NAs - align by index
    complete_idx <- which(complete.cases(dt[, ..features]))
    result[complete_idx] <- outliers
  }
  
  cat("  IF complete:", sum(result), "outliers out of", nrow(dt), "points\n")
  return(result)
}

# ---- MAIN PROCESSING ----
cat("Starting Isolation Forest processing...\n")
system.time({
  dt_nav[, outlier_IF := detect_outliers_IF_optimized(dt_nav, outlier_config)]
})

# ---- CREATE is_stop COLUMN (REQUIRED FOR STEP 3) ----
cat("Creating is_stop column...\n")

# Sort by timestamp for temporal calculations
setorder(dt_nav, Timestamp)

# delta_t already computed above, no need to recalculate

# Stop detection based on speed and time intervals
# A stop = speed < 1 knot OR interval > 5 minutes
dt_nav[, is_stop := (Speed < 1) | (delta_t > 300)]

# Clean up NA values
dt_nav[is.na(is_stop), is_stop := FALSE]

cat("is_stop column created:", sum(dt_nav$is_stop), "stops detected\n")

# ---- CREATE ADDITIONAL COLUMNS (USEFUL FOR STEP 3) ----
cat("Creating additional columns...\n")

# Add year
dt_nav[, Annee := year(Timestamp)]

# Course_change and Accel already computed above, no need to recalculate

cat("Additional columns created (Annee, Course_change, Accel)\n")

# ---- STATISTIQUES ----
n_outliers <- sum(dt_nav$outlier_IF)
outlier_rate <- round(n_outliers / nrow(dt_nav) * 100, 2)
n_stops <- sum(dt_nav$is_stop)
stop_rate <- round(n_stops / nrow(dt_nav) * 100, 2)

cat("VESSEL RESULTS:", navire_name, "\n")
cat("  - Total observations:", nrow(dt_nav), "\n")
cat("  - Outliers detected:", n_outliers, "(", outlier_rate, "%)\n")
cat("  - Stops detected:", n_stops, "(", stop_rate, "%)\n")

# ---- SAVE OUTPUT ----
# Use the output directory defined in the bash script
output_dir <- file.path("~/scratch", paste0("ais_results_", Sys.getenv("SLURM_ARRAY_JOB_ID")))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Output filename
safe_name <- gsub("[^A-Za-z0-9_-]", "_", navire_name)
output_file <- file.path(output_dir, sprintf("%02d_%s_clean.rds", task_id, safe_name))

cat("Saving:", output_file, "\n")

system.time({
  saveRDS(dt_nav, output_file, compress = "xz")
})

# ---- MEMORY CLEANUP ----
if (exists("if_model")) rm(if_model)
rm(dt_nav)
gc()

cat("Vessel", navire_name, "processed successfully:", format(Sys.time()), "\n")
cat("Output:", output_file, "\n")
