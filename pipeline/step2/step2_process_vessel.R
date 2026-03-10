#!/usr/bin/env Rscript
# ====================================================================
# STEP 2: INDIVIDUAL VESSEL PROCESSING (ARRAY JOB)
# OPTIMISED V8 - Tiled spatial land mask
#   - Partitions vessel footprint into spatial tiles (tile_deg degrees)
#   - Loads land mask PER TILE (avoids OOM & timeout)
#   - Per-tile cache for crosses_land in the iterative loop
#   - Fallback single-bbox if tiling disabled or too many tiles
#   - Static pre-computations: on_land + near_land outside loop
#   - crosses_land in metric CRS (EPSG:3857) + time filter BEFORE geometry
# ====================================================================

cat("=== INDIVIDUAL VESSEL PROCESSING (OPTIMISED V8 - TILED) ===\n")
cat("SCRIPT_VERSION: step2_process_vessel.R 2026-01-27 tiled-v8\n")
cat("Start:", format(Sys.time()), "\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
.libPaths("~/R/library")
cat("R library path:", .libPaths()[1], "\n")

# ---- CONFIGURATION ANTI-GFORCE ----
options(mc.cores = 1)
Sys.setenv(MC_CORES = 1)
Sys.setenv(DT_GForce = "FALSE")
Sys.setenv(OMP_NUM_THREADS = 1)

# ---- CHARGEMENT PACKAGES ----
suppressPackageStartupMessages({
  library(data.table)

  use_qs <- FALSE
  tryCatch({
    if (requireNamespace("qs", quietly = TRUE)) {
      library(qs)
      use_qs <- TRUE
      cat("[INFO] Package qs available\n")
    }
  }, error = function(e) {
    cat("[WARN] Package qs unavailable, falling back to RDS\n")
  })

  library(lubridate)
  library(yaml)
  library(solitude)
  library(mclust)
  library(zoo)
  library(sf)
})

# Disable S2 spherical geometry — use GEOS planar
sf::sf_use_s2(FALSE)
cat("[INFO] S2 disabled — using GEOS\n")

setDTthreads(1)
options(datatable.optimize = 1)
cat("[INFO] Packages loaded — single-thread mode enabled\n")

# ── Runtime limitation warnings ───────────────────────────────────────────────
# Sourced here so check_ais_coverage_region(), check_ping_density(), etc. are
# available throughout this step. Emits warning() (not stop()) — pipeline
# continues; warnings are logged to SLURM .out file and CI artifact.
# See documentation/LIMITATIONS.md for the full list of known failure modes.
local({
  candidates <- c(
    "scripts_principaux/pipeline_warnings.R",    # project root (local dev)
    "../scripts_principaux/pipeline_warnings.R"  # pipeline_V6/ dir (cluster)
  )
  found <- Filter(file.exists, candidates)
  if (length(found) > 0L) source(found[1L]) else
    message("[INFO] pipeline_warnings.R not found — limitation checks skipped.")
})

# ---- GEOSPATIAL PARAMETERS ----
land_mask_path_raw <- Sys.getenv("LAND_MASK_FILE", unset = "~/ais-pipeline/configuration/land_mask/land_polygons.shp")
land_mask_path     <- path.expand(land_mask_path_raw)
land_buffer_m      <- suppressWarnings(as.numeric(Sys.getenv("LAND_MASK_BUFFER_M", unset = "0")))
if (is.na(land_buffer_m)) land_buffer_m <- 0

cat("\n--- Geospatial configuration ---\n")
cat("LAND_MASK_FILE (raw):", land_mask_path_raw, "\n")
cat("LAND_MASK_FILE (expanded):", land_mask_path, "\n")
cat("LAND_MASK_BUFFER_M:", land_buffer_m, "\n")

near_coast_km <- suppressWarnings(as.numeric(Sys.getenv("LAND_NEAR_COAST_KM", unset = "5")))
if (is.na(near_coast_km) || near_coast_km <= 0) near_coast_km <- 5
cat("LAND_NEAR_COAST_KM:", near_coast_km, "\n")

default_speed_kn    <- suppressWarnings(as.numeric(Sys.getenv("MAX_JUMP_SPEED_KN", unset = "30")))
if (is.na(default_speed_kn) || default_speed_kn <= 0) default_speed_kn <- 30

spike_dist_min_nm   <- suppressWarnings(as.numeric(Sys.getenv("SPIKE_DIST_MIN_NM", unset = "1")))
if (is.na(spike_dist_min_nm) || spike_dist_min_nm <= 0) spike_dist_min_nm <- 1

spike_bridge_max_nm <- suppressWarnings(as.numeric(Sys.getenv("SPIKE_BRIDGE_MAX_NM", unset = "0.3")))
if (is.na(spike_bridge_max_nm) || spike_bridge_max_nm <= 0) spike_bridge_max_nm <- 0.3

sf_chunk <- suppressWarnings(as.integer(Sys.getenv("SF_CHUNK", unset = "100000")))
if (is.na(sf_chunk) || sf_chunk < 1000) sf_chunk <- 100000

cat("SF_CHUNK:", sf_chunk, "\n")

# ---- TILING PARAMETERS ----
land_tile_enable <- as.logical(Sys.getenv("LAND_TILE_ENABLE", unset = "TRUE"))
if (is.na(land_tile_enable)) land_tile_enable <- TRUE
land_tile_deg <- suppressWarnings(as.numeric(Sys.getenv("LAND_TILE_DEG", unset = "5")))
if (is.na(land_tile_deg) || land_tile_deg <= 0) land_tile_deg <- 5
land_tile_max <- suppressWarnings(as.integer(Sys.getenv("LAND_TILE_MAX_TILES", unset = "200")))
if (is.na(land_tile_max) || land_tile_max < 1) land_tile_max <- 200

cat("LAND_TILE_ENABLE:", land_tile_enable, "\n")
cat("LAND_TILE_DEG:", land_tile_deg, "\n")
cat("LAND_TILE_MAX_TILES:", land_tile_max, "\n")
cat("---\n\n")

# ---- FONCTIONS OUTILS ----
haversine_nm <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  (r * c) / 1852
}

chunk_any_intersects <- function(x, y, chunk = 100000, label = "intersects") {
  n <- nrow(x)
  out <- logical(n)
  if (n == 0) return(out)

  # Handle both sf and sfc objects for y
  n_y <- if (inherits(y, "sfc")) length(y) else nrow(y)

  n_chunks <- ceiling(n / chunk)
  cat("        [", label, "] ", n, " pts / ", n_y, " polys (", n_chunks, " chunks)...", sep = "")
  for (i in seq(1, n, by = chunk)) {
    j <- min(i + chunk - 1, n)
    out[i:j] <- suppressMessages(lengths(sf::st_intersects(x[i:j, ], y)) > 0)
  }
  cat(" done\n")
  out
}

# Near-land via st_is_within_distance (avoids OOM from st_union+st_buffer)
chunk_any_within_distance <- function(x, y, dist_m, chunk = 100000, label = "within_dist") {
  n <- nrow(x)
  out <- logical(n)
  if (n == 0) return(out)

  n_y <- if (inherits(y, "sfc")) length(y) else nrow(y)

  n_chunks <- ceiling(n / chunk)
  cat("        [", label, "] ", n, " pts / ", n_y, " polys, dist=", dist_m/1000, "km (", n_chunks, " chunks)...", sep = "")
  for (i in seq(1, n, by = chunk)) {
    j <- min(i + chunk - 1, n)
    out[i:j] <- suppressMessages(lengths(sf::st_is_within_distance(x[i:j, ], y, dist = dist_m)) > 0)
  }
  cat(" done\n")
  out
}

# ---- TILING UTILITIES ----
wrap_lon <- function(x) ((x + 180) %% 360) - 180

tile_assign <- function(lon, lat, tile_deg) {
  tx <- floor(lon / tile_deg)
  ty <- floor(lat / tile_deg)
  paste0(tx, "_", ty)
}

tile_bbox_4326 <- function(tile_key, tile_deg, margin_deg = 0) {
  parts <- as.integer(strsplit(tile_key, "_", fixed = TRUE)[[1]])
  tx <- parts[1]; ty <- parts[2]
  xmin <- tx * tile_deg - margin_deg
  ymin <- max(ty * tile_deg - margin_deg, -90)
  xmax <- (tx + 1) * tile_deg + margin_deg
  ymax <- min((ty + 1) * tile_deg + margin_deg, 90)
  sf::st_bbox(c(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax), crs = sf::st_crs(4326))
}

cache_new  <- function() new.env(hash = TRUE, parent = emptyenv())
cache_get  <- function(cache, key) {
  if (exists(key, envir = cache, inherits = FALSE)) get(key, envir = cache, inherits = FALSE)
  else NULL
}
cache_set  <- function(cache, key, value) assign(key, value, envir = cache)

# Lightweight tile loader (minimal output for per-tile loop)
load_land_tile <- function(path, bbox_4326, buffer_m = 0) {
  path_exp <- path.expand(prefer_land_datasource(path))
  if (!file.exists(path_exp)) return(NULL)

  bbox_sfc <- sf::st_as_sfc(bbox_4326)
  sf::st_crs(bbox_sfc) <- 4326
  wkt <- sf::st_as_text(bbox_sfc)

  land <- tryCatch(sf::st_read(path_exp, wkt_filter = wkt, quiet = TRUE),
                   error = function(e) NULL)
  if (is.null(land) || !inherits(land, "sf") || nrow(land) == 0) return(NULL)

  if (isFALSE(sf::st_is_longlat(land))) {
    land <- tryCatch(sf::st_transform(land, 4326), error = function(e) land)
  }
  land <- sf::st_make_valid(land)
  land <- land[!sf::st_is_empty(land), ]
  if (nrow(land) == 0) return(NULL)

  land_m <- tryCatch(sf::st_transform(land, 3857), error = function(e) NULL)
  if (is.null(land_m)) return(NULL)

  if (is.finite(buffer_m) && buffer_m != 0) {
    land_m <- tryCatch({
      x <- sf::st_buffer(land_m, dist = buffer_m)
      sf::st_make_valid(x)
    }, error = function(e) land_m)
  }

  land_m
}

# --- Land mask local via WKT filter (avoids global load) ---
prefer_land_datasource <- function(path) {
  # Prefer .gpkg alongside .shp when present (faster + spatial index)
  if (grepl("\\.shp$", path, ignore.case = TRUE)) {
    gpkg <- sub("\\.shp$", ".gpkg", path, ignore.case = TRUE)
    if (file.exists(gpkg)) return(gpkg)
  }
  path
}

get_layer_crs_fast <- function(path) {
  # Minimal read to determine CRS; n_max=1 limits cost.
  crs <- tryCatch({
    x <- sf::st_read(path, quiet = TRUE, n_max = 1)
    sf::st_crs(x)
  }, error = function(e) {
    NA
  })
  crs
}

load_land_local_wkt <- function(path, bbox_expanded_4326, buffer_m = 0) {
  cat("\n============================================================\n")
  cat("CHARGEMENT LAND MASK (LOCAL via WKT)\n")
  cat("============================================================\n")

  path <- prefer_land_datasource(path)
  cat("Datasource:", path, "\n")

  path_expanded <- path.expand(path)
  cat("Resolved path:", path_expanded, "\n")

  if (!file.exists(path_expanded)) {
    cat("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n")
    cat("ATTENTION: LAND MASK NOT FOUND!\n")
    cat("Path:", path_expanded, "\n")
    cat("Land filters on_land / near_land / crosses_land will be DISABLED!\n")
    cat("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n")
    return(list(land_local_4326 = NULL, land_local_3857 = NULL))
  }

  # Construire bbox sfc en 4326
  bbox_sfc <- sf::st_as_sfc(bbox_expanded_4326)
  sf::st_crs(bbox_sfc) <- 4326

  # Adapt bbox to layer CRS if different
  layer_crs <- get_layer_crs_fast(path_expanded)
  bbox_for_filter <- bbox_sfc
  if (!is.na(layer_crs)[1] && !identical(layer_crs$epsg, 4326)) {
    bbox_for_filter <- tryCatch(sf::st_transform(bbox_sfc, layer_crs), error = function(e) bbox_sfc)
  }

  wkt <- sf::st_as_text(bbox_for_filter)

  cat("Lecture st_read(wkt_filter=...)...\n")
  land_local <- tryCatch({
    sf::st_read(path_expanded, wkt_filter = wkt, quiet = TRUE)
  }, error = function(e) {
    cat("ERREUR st_read wkt_filter:", e$message, "\n")
    NULL
  })

  if (is.null(land_local) || !inherits(land_local, "sf") || nrow(land_local) == 0) {
    cat("Local land empty — land filters disabled\n")
    cat("============================================================\n\n")
    return(list(land_local_4326 = NULL, land_local_3857 = NULL))
  }

  # Harmoniser CRS -> 4326
  if (isFALSE(sf::st_is_longlat(land_local))) {
    land_local <- tryCatch(sf::st_transform(land_local, 4326), error = function(e) land_local)
  } else {
    # Si longlat mais pas 4326, transformer
    if (!is.na(sf::st_crs(land_local)$epsg) && sf::st_crs(land_local)$epsg != 4326) {
      land_local <- tryCatch(sf::st_transform(land_local, 4326), error = function(e) land_local)
    }
  }

  # Validation locale
  land_local <- sf::st_make_valid(land_local)
  land_local <- land_local[!sf::st_is_empty(land_local), ]

  cat("Local land loaded:", nrow(land_local), "polygons\n")

  # Optional metric buffer
  land_local_m <- tryCatch(sf::st_transform(land_local, 3857), error = function(e) NULL)

  if (!is.null(land_local_m) && is.finite(buffer_m) && buffer_m != 0) {
    cat("Applying buffer +", buffer_m, "m...\n", sep = "")
    land_local_m <- tryCatch({
      x <- sf::st_buffer(land_local_m, dist = buffer_m)
      x <- sf::st_make_valid(x)
      x <- x[!sf::st_is_empty(x), ]
      x
    }, error = function(e) {
      cat("Erreur buffer:", e$message, "- utilisation sans buffer\n")
      land_local_m
    })
  }

  # Rebuild 4326 version consistent with 3857 (after optional buffer)
  if (!is.null(land_local_m)) {
    land_local_4326 <- tryCatch(sf::st_transform(land_local_m, 4326), error = function(e) land_local)
  } else {
    land_local_4326 <- land_local
  }

  cat("Local land ready (4326):", nrow(land_local_4326), "polygons\n")
  if (!is.null(land_local_m)) cat("Local land ready (3857):", nrow(land_local_m), "polygons\n")

  cat("============================================================\n\n")
  list(land_local_4326 = land_local_4326, land_local_3857 = land_local_m)
}

# ============================================================
# OPTIMISED FUNCTION — dynamic flags only
# ============================================================
flag_geospatial_anomalies_instrumented <- function(dt, land_local_m, default_speed_kn,
                                                   spike_dist_min_nm = 1, spike_bridge_max_nm = 0.3,
                                                   land_cache = NULL, tile_key_col = NULL,
                                                   speed_margin_pct = 0.15) {

  dt[, `:=`(
    flag_on_land       = if ("flag_on_land_static" %in% names(dt)) flag_on_land_static else FALSE,
    flag_crosses_land  = FALSE,
    flag_speed_jump    = FALSE,
    flag_long_jump     = FALSE,
    flag_spike         = FALSE
  )]

  # Dynamic calculations (neighbours change after removal)
  dt[, `:=`(
    gc_nm  = haversine_nm(Lat, Lon, shift(Lat), shift(Lon)),
    dt_sec = as.numeric(delta_t)
  )]

  dt[, avg_speed_kn := ifelse(!is.na(dt_sec) & dt_sec > 0, gc_nm / dt_sec * 3600, NA_real_)]

  # max plausible
  dt[, max_plausible_kn := default_speed_kn]
  if ("Service_speed" %in% names(dt)) {
    dt[!is.na(Service_speed), max_plausible_kn := Service_speed * (1 + speed_margin_pct)]
  }

  # 1) Log on_land (statique)
  n_on_land <- sum(dt$flag_on_land, na.rm = TRUE)
  if (n_on_land > 0) cat("      on_land (static):", n_on_land, "\n")

  # 2) crosses_land (semi-dynamique) - tiled or single-land
  use_tiled_crosses <- !is.null(land_cache) && !is.null(tile_key_col) && tile_key_col %in% names(dt)
  has_near_land <- "flag_near_land_static" %in% names(dt)
  can_do_crosses <- has_near_land && (use_tiled_crosses || !is.null(land_local_m))

  if (can_do_crosses) {
    near_curr <- dt$flag_near_land_static
    near_next <- shift(near_curr, type = "lead", fill = FALSE)
    on_curr   <- dt$flag_on_land

    seg_candidates <- which((near_curr | near_next) & !on_curr)
    seg_candidates <- seg_candidates[seg_candidates < nrow(dt)]

    # Time filter BEFORE geometry tests
    next_dt_sec <- dt$dt_sec[seg_candidates + 1]
    seg_candidates <- seg_candidates[!is.na(next_dt_sec) & next_dt_sec < 3600]

    # Filtre coords finites
    ok_seg <- is.finite(dt$Lon[seg_candidates]) & is.finite(dt$Lat[seg_candidates]) &
      is.finite(dt$Lon[seg_candidates + 1]) & is.finite(dt$Lat[seg_candidates + 1])
    seg_candidates <- seg_candidates[ok_seg]

    if (length(seg_candidates) > 0) {
      if (use_tiled_crosses) {
        # --- Per-tile crosses_land ---
        seg_tiles <- dt[[tile_key_col]][seg_candidates]
        unique_seg_tiles <- unique(seg_tiles)
        total_crosses <- 0L

        for (tk in unique_seg_tiles) {
          tile_land <- cache_get(land_cache, tk)
          if (is.null(tile_land)) next
          if (inherits(tile_land, "sf") && nrow(tile_land) == 0) next

          tile_mask <- seg_tiles == tk
          tile_segs <- seg_candidates[tile_mask]

          seg_lines_ll <- sf::st_sfc(
            mapply(function(i) {
              sf::st_linestring(matrix(
                c(dt$Lon[i], dt$Lat[i], dt$Lon[i + 1], dt$Lat[i + 1]),
                ncol = 2, byrow = TRUE
              ))
            }, tile_segs, SIMPLIFY = FALSE),
            crs = 4326
          )

          seg_lines_m <- tryCatch(sf::st_transform(seg_lines_ll, 3857), error = function(e) seg_lines_ll)
          crosses <- lengths(sf::st_intersects(seg_lines_m, tile_land)) > 0

          if (any(crosses)) {
            bad_idx <- tile_segs[crosses] + 1L
            dt[bad_idx, flag_crosses_land := TRUE]
            total_crosses <- total_crosses + length(bad_idx)
          }
        }

        if (total_crosses > 0) cat("      crosses_land:", total_crosses, "(tiled)\n")

      } else {
        # --- Single-land crosses_land (fallback) ---
        seg_lines_ll <- sf::st_sfc(
          mapply(function(i) {
            sf::st_linestring(matrix(
              c(dt$Lon[i], dt$Lat[i], dt$Lon[i + 1], dt$Lat[i + 1]),
              ncol = 2, byrow = TRUE
            ))
          }, seg_candidates, SIMPLIFY = FALSE),
          crs = 4326
        )

        seg_lines_m <- tryCatch(sf::st_transform(seg_lines_ll, 3857), error = function(e) seg_lines_ll)
        crosses <- lengths(sf::st_intersects(seg_lines_m, land_local_m)) > 0

        if (any(crosses)) {
          bad_idx <- seg_candidates[crosses] + 1L
          dt[bad_idx, flag_crosses_land := TRUE]
          cat("      crosses_land:", length(bad_idx), "\n")
        }
      }
    }
  }

  # 3) Sauts vitesse
  speed_jump_mask <- !is.na(dt$avg_speed_kn) & dt$avg_speed_kn > dt$max_plausible_kn
  dt[speed_jump_mask, flag_speed_jump := TRUE]
  cat("      speed_jump:", sum(speed_jump_mask), "\n")

  # 4) Sauts distance
  long_jump_mask <- !is.na(dt$gc_nm) & !is.na(dt$dt_sec) & dt$gc_nm > 100 & dt$dt_sec <= 3600
  dt[long_jump_mask, flag_long_jump := TRUE]
  cat("      long_jump:", sum(long_jump_mask), "\n")

  # 5) Spikes
  dt[, `:=`(
    dist_prev      = haversine_nm(shift(Lat), shift(Lon), Lat, Lon),
    dist_next      = haversine_nm(Lat, Lon, shift(Lat, type = "lead"), shift(Lon, type = "lead")),
    dist_prev_next = haversine_nm(shift(Lat), shift(Lon), shift(Lat, type = "lead"), shift(Lon, type = "lead"))
  )]

  spike_mask <- !is.na(dt$dist_prev) & !is.na(dt$dist_next) & !is.na(dt$dist_prev_next) &
    dt$dist_prev > spike_dist_min_nm &
    dt$dist_next > spike_dist_min_nm &
    dt$dist_prev_next < spike_bridge_max_nm
  dt[spike_mask, flag_spike := TRUE]
  cat("      spike:", sum(spike_mask), "\n")

  dt[, geo_flag := flag_on_land | flag_crosses_land | flag_speed_jump | flag_long_jump | flag_spike]

  dt[, c("gc_nm", "dt_sec", "avg_speed_kn", "max_plausible_kn",
         "dist_prev", "dist_next", "dist_prev_next") := NULL]

  dt
}

# ---- ENVIRONMENT PARAMETERS ----
task_id <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID"))
split_job_id <- Sys.getenv("SPLIT_JOB_ID")

cat("Task ID:", task_id, "\n")
cat("Split Job ID:", split_job_id, "\n")

# ---- CHEMINS FICHIERS ----
split_dir <- file.path("~/scratch", paste0("ais_split_", split_job_id))
metadata_file <- file.path(split_dir, "navires_metadata.csv")

if (!file.exists(metadata_file)) stop("Metadata file not found: ", metadata_file)

metadata <- fread(metadata_file)
cat("Metadata loaded:", nrow(metadata), "vessels\n")

if (task_id > nrow(metadata)) stop("Task ID ", task_id, " > nombre navires ", nrow(metadata))

# ---- VESSEL SELECTION ----
navire_info <- metadata[task_id]
input_file  <- navire_info$file_path
navire_name <- navire_info$Navire

cat("Vessel selected:", navire_name, "\n")
cat("Fichier input:", input_file, "\n")
if (!file.exists(input_file)) stop("Fichier navire introuvable: ", input_file)

# ---- LOAD VESSEL DATA ----
cat("Loading vessel data...\n")
system.time({
  if (grepl("\\.qs$", input_file, ignore.case = TRUE)) {
    dt_nav <- qs::qread(input_file, as.data.table = TRUE)
    cat("QS format detected and loaded\n")
  } else if (grepl("\\.rds$", input_file, ignore.case = TRUE)) {
    dt_nav <- readRDS(input_file)
    setDT(dt_nav)
    cat("RDS format detected and loaded\n")
  } else {
    stop("Format de fichier non reconnu: ", input_file)
  }
})

# Harmoniser le type de ssvid
if ("ssvid" %in% names(dt_nav)) dt_nav[, ssvid := as.character(ssvid)]

# Safe coordinate normalisation
if ("Lon" %in% names(dt_nav)) dt_nav[, Lon := suppressWarnings(as.numeric(gsub(",", ".", Lon, fixed = TRUE)))]
if ("Lat" %in% names(dt_nav)) dt_nav[, Lat := suppressWarnings(as.numeric(gsub(",", ".", Lat, fixed = TRUE)))]

cat("Data loaded:", nrow(dt_nav), "observations\n")
cat("   Lon NA:", sum(is.na(dt_nav$Lon)), " Lat NA:", sum(is.na(dt_nav$Lat)), "\n")
if (nrow(dt_nav) > 0) {
  cat("   Lon range:", paste(range(dt_nav$Lon, na.rm = TRUE), collapse = " "),
      " Lat range:", paste(range(dt_nav$Lat, na.rm = TRUE), collapse = " "), "\n")
}

# ---- READ VESSEL SPECIFICATIONS ----
spec_file <- "~/ais-pipeline/configuration/ship_specs.yaml"
if (!file.exists(spec_file)) stop("ship_specs.yaml not found: ", spec_file)

spec_list  <- yaml::read_yaml(spec_file)$ship_specs
ship_specs <- rbindlist(spec_list, fill = TRUE)
ship_specs[, ssvid := as.character(ssvid)]
ship_specs <- ship_specs[, .SD[1], by = ssvid]
setnames(ship_specs, "service_speed_kn", "Service_speed")
setkey(ship_specs, ssvid)

if ("ssvid" %chin% names(dt_nav)) {
  dt_nav <- merge(dt_nav, ship_specs[, .(ssvid, Service_speed, dredge_width_m, dredging_depth_m)],
                  by = "ssvid", all.x = TRUE)
  dt_nav[, Service_speed := as.numeric(Service_speed)]
  dt_nav[, `:=`(dredge_width_m = as.numeric(dredge_width_m),
                dredging_depth_m = as.numeric(dredging_depth_m))]
  setkey(dt_nav, ssvid)
}

if (!"Service_speed" %chin% names(dt_nav) || all(is.na(dt_nav$Service_speed))) {
  warning("No service speed found for vessel ", navire_name)
}

# ---- FILTRE VITESSE PHYSIQUE ----
if ("Service_speed" %chin% names(dt_nav)) {
  dt_nav[, speed_limit := Service_speed * 1.15]
  n_before <- nrow(dt_nav)
  dt_nav   <- dt_nav[is.na(speed_limit) | Speed <= speed_limit]
  n_after  <- nrow(dt_nav)
  cat(sprintf("Physical speed filter: %d -> %d rows (%.2f %% retained)\n",
              n_before, n_after, 100 * n_after / n_before))
  dt_nav[, speed_limit := NULL]
}

# Initial preparation
setorder(dt_nav, Timestamp)
dt_nav[, delta_t := c(NA_real_, diff(as.numeric(Timestamp)))]

# Unique stable index for debug/log
# (useful for mapping back to original data)
dt_nav[, .row_id := .I]

cat("Applying geospatial filters...\n")

# ============================================================
# STATIC PRE-COMPUTATIONS (outside loop) — SPATIAL TILING
# ============================================================
cat("\n--- Static land relations pre-computation ---\n")

dt_nav[, flag_on_land_static   := FALSE]
dt_nav[, flag_near_land_static := FALSE]

land_local_3857 <- NULL
land_cache <- cache_new()

# Check valid coordinates
coord_ok <- is.finite(dt_nav$Lon) & is.finite(dt_nav$Lat) &
  dt_nav$Lon >= -180 & dt_nav$Lon <= 180 &
  dt_nav$Lat >= -90  & dt_nav$Lat <= 90
coord_ok[is.na(coord_ok)] <- FALSE
idx_ok <- which(coord_ok)

if (length(idx_ok) > 0) {
  # Assign tile keys to all points
  dt_nav[, tile_key := tile_assign(Lon, Lat, land_tile_deg)]
  tile_keys <- unique(dt_nav$tile_key[idx_ok])
  n_tiles <- length(tile_keys)

  cat("  Tiles uniques:", n_tiles, " (deg=", land_tile_deg, ")\n", sep = "")

  use_tiled_mode <- land_tile_enable && n_tiles <= land_tile_max

  if (use_tiled_mode) {
    # ============================================================
    # MODE TILING: charge land par tuile
    # ============================================================
    cat("  >>> TILING mode enabled <<<\n")

    # Margin: near_coast for on_land/near_land + max segment length for crosses_land
    margin_deg <- max(near_coast_km / 111, default_speed_kn / 60) + 0.05

    total_polys <- 0
    t_tile_start <- Sys.time()

    for (k in seq_along(tile_keys)) {
      tk <- tile_keys[k]
      tile_bbox <- tile_bbox_4326(tk, land_tile_deg, margin_deg = margin_deg)

      tile_land_m <- tryCatch(
        load_land_tile(land_mask_path, tile_bbox, buffer_m = land_buffer_m),
        error = function(e) { cat("    ERREUR tile", tk, ":", e$message, "\n"); NULL }
      )

      # Cache for crosses_land in iterative loop
      cache_set(land_cache, tk, tile_land_m)

      tile_idx <- idx_ok[dt_nav$tile_key[idx_ok] == tk]
      n_polys <- if (!is.null(tile_land_m)) nrow(tile_land_m) else 0L
      total_polys <- total_polys + n_polys

      cat(sprintf("  Tile %d/%d [%s]: %d pts, %d polys", k, n_tiles, tk, length(tile_idx), n_polys))

      if (!is.null(tile_land_m) && nrow(tile_land_m) > 0 && length(tile_idx) > 0) {
        pts_sf <- sf::st_as_sf(dt_nav[tile_idx, .(Lon, Lat)],
                                coords = c("Lon", "Lat"), crs = 4326, remove = TRUE)
        pts_m <- sf::st_transform(pts_sf, 3857)

        on_land_vec <- chunk_any_intersects(pts_m, tile_land_m, chunk = sf_chunk,
                                             label = paste0("on_land[", tk, "]"))
        dt_nav[tile_idx, flag_on_land_static := on_land_vec]

        near_land_vec <- chunk_any_within_distance(pts_m, tile_land_m,
                                                    dist_m = near_coast_km * 1000,
                                                    chunk = sf_chunk,
                                                    label = paste0("near_land[", tk, "]"))
        dt_nav[tile_idx, flag_near_land_static := near_land_vec]

        rm(pts_sf, pts_m)
        cat(" -> on_land:", sum(on_land_vec), " near_land:", sum(near_land_vec), "\n")
      } else {
        cat(" (no land or no pts)\n")
      }
    }

    cat("  Total polygones (somme tiles):", total_polys, "\n")
    cat("  Tiling duration:", round(as.numeric(difftime(Sys.time(), t_tile_start, units = "secs")), 1), "s\n")
    gc()

  } else {
    # ============================================================
    # FALLBACK: single BBOX (original approach)
    # ============================================================
    if (!land_tile_enable) {
      cat("  TILING mode disabled by configuration\n")
    } else {
      cat("  Too many tiles (", n_tiles, " > ", land_tile_max, ") — fallback to single bbox\n", sep = "")
    }

    # Robust bounding box (quantiles) to avoid outliers
    lon_q <- as.numeric(quantile(dt_nav$Lon[idx_ok], probs = c(0.001, 0.999), na.rm = TRUE))
    lat_q <- as.numeric(quantile(dt_nav$Lat[idx_ok], probs = c(0.001, 0.999), na.rm = TRUE))

    dx <- near_coast_km / 111
    bbox_expanded <- sf::st_bbox(c(
      xmin = lon_q[1] - dx,
      ymin = lat_q[1] - dx,
      xmax = lon_q[2] + dx,
      ymax = lat_q[2] + dx
    ), crs = sf::st_crs(4326))

    cat("  bbox expanded (robust): xmin=", round(bbox_expanded[["xmin"]], 2),
        " ymin=", round(bbox_expanded[["ymin"]], 2),
        " xmax=", round(bbox_expanded[["xmax"]], 2),
        " ymax=", round(bbox_expanded[["ymax"]], 2), "\n", sep = "")

    land_res <- load_land_local_wkt(land_mask_path, bbox_expanded, buffer_m = land_buffer_m)
    land_local_3857 <- land_res$land_local_3857

    if (!is.null(land_local_3857) && nrow(land_local_3857) > 0) {
      pts_sf_all <- sf::st_as_sf(dt_nav[idx_ok, .(Lon, Lat)],
                                  coords = c("Lon", "Lat"), crs = 4326, remove = TRUE)
      pts_m_all  <- sf::st_transform(pts_sf_all, 3857)

      cat("  Calcul on_land (static)...\n")
      on_land_vec <- chunk_any_intersects(pts_m_all, land_local_3857, chunk = sf_chunk, label = "on_land")
      dt_nav[idx_ok, flag_on_land_static := on_land_vec]

      cat("  Calcul near_land (static) via st_is_within_distance...\n")
      near_land_vec <- chunk_any_within_distance(pts_m_all, land_local_3857,
                                                  dist_m = near_coast_km * 1000,
                                                  chunk = sf_chunk,
                                                  label = "near_land")
      dt_nav[idx_ok, flag_near_land_static := near_land_vec]

      rm(pts_sf_all, pts_m_all)
      gc()
    } else {
      cat("  Local land unavailable — land filters disabled\n")
    }
  }
} else {
  cat("  No valid coordinates — land filters disabled\n")
}

cat("---\n\n")

n_before_geo <- nrow(dt_nav)

# Load speed_margin_pct from YAML config (technique.speed_margin_pct), fallback 0.15
speed_margin_pct <- 0.15
{
  cfg_file_sm <- "~/ais-pipeline/configuration/outlier_config_V6.yaml"
  if (file.exists(cfg_file_sm)) {
    cfg_sm <- tryCatch(yaml.load_file(cfg_file_sm), error = function(e) list())
    if (!is.null(cfg_sm$technique$speed_margin_pct))
      speed_margin_pct <- cfg_sm$technique$speed_margin_pct
  }
  cat("speed_margin_pct:", speed_margin_pct, "\n")
}

# ============================================================
# ITERATIVE LOOP WITH EXACT LOGGING
# ============================================================
iteration <- 0
max_iterations <- 3
total_removed <- 0
removed_log <- data.table()

repeat {
  iteration <- iteration + 1
  cat(sprintf("  Iteration %d...\n", iteration))

  dt_nav <- flag_geospatial_anomalies_instrumented(
    dt_nav,
    land_local_m = land_local_3857,
    default_speed_kn = default_speed_kn,
    spike_dist_min_nm = spike_dist_min_nm,
    spike_bridge_max_nm = spike_bridge_max_nm,
    land_cache = land_cache,
    tile_key_col = if ("tile_key" %in% names(dt_nav)) "tile_key" else NULL,
    speed_margin_pct = speed_margin_pct
  )

  n_flagged <- sum(dt_nav$geo_flag, na.rm = TRUE)

  if (n_flagged == 0) {
    cat("  No new points to remove\n")
    dt_nav[, c("geo_flag", "flag_on_land", "flag_crosses_land", "flag_speed_jump", "flag_long_jump", "flag_spike") := NULL]
    break
  }

  # LOG: points flagged for removal before deletion
  removed_iter <- dt_nav[geo_flag == TRUE, .(
    .row_id, Timestamp, Lat, Lon, Speed,
    flag_on_land, flag_crosses_land, flag_speed_jump, flag_long_jump, flag_spike
  )]
  removed_iter[, iteration := iteration]
  removed_log <- rbind(removed_log, removed_iter, fill = TRUE)

  if (iteration >= max_iterations) {
    cat(sprintf("  Max iterations reached (%d), %d remaining flagged points removed\n",
                max_iterations, n_flagged))
    dt_nav <- dt_nav[geo_flag == FALSE | is.na(geo_flag)]
    dt_nav[, c("geo_flag", "flag_on_land", "flag_crosses_land", "flag_speed_jump", "flag_long_jump", "flag_spike") := NULL]
    total_removed <- total_removed + n_flagged
    break
  }

  # Remove flagged points
  dt_nav <- dt_nav[geo_flag == FALSE | is.na(geo_flag)]
  dt_nav[, c("geo_flag", "flag_on_land", "flag_crosses_land", "flag_speed_jump", "flag_long_jump", "flag_spike") := NULL]
  total_removed <- total_removed + n_flagged

  cat(sprintf("  -> %d points removed (cumulative: %d)\n", n_flagged, total_removed))

  # Recalculer delta_t
  setorder(dt_nav, Timestamp)
  dt_nav[, delta_t := c(NA_real_, diff(as.numeric(Timestamp)))]
}

# Nettoyer l'index temporaire et tile_key
dt_nav[, .row_id := NULL]
if ("tile_key" %in% names(dt_nav)) dt_nav[, tile_key := NULL]

n_after_geo <- nrow(dt_nav)
cat(sprintf("Geospatial filters: %d rows removed in %d iteration(s) (%.2f %%)\n",
            n_before_geo - n_after_geo, iteration,
            if (n_before_geo > 0) 100 * (n_before_geo - n_after_geo) / n_before_geo else 0))

# ============================================================
# EXACT REMOVAL BREAKDOWN
# ============================================================
cat("\n============================================================\n")
cat("EXACT REMOVAL BREAKDOWN\n")
cat("============================================================\n")

if (nrow(removed_log) > 0) {
  cat("\nPar flag (multi-label, un point peut cocher plusieurs):\n")
  cat(sprintf("  on_land:       %8d\n", sum(removed_log$flag_on_land)))
  cat(sprintf("  crosses_land:  %8d\n", sum(removed_log$flag_crosses_land)))
  cat(sprintf("  speed_jump:    %8d\n", sum(removed_log$flag_speed_jump)))
  cat(sprintf("  long_jump:     %8d\n", sum(removed_log$flag_long_jump)))
  cat(sprintf("  spike:         %8d\n", sum(removed_log$flag_spike)))

  removed_log[, reason := fcase(
    flag_on_land, "on_land",
    flag_crosses_land, "crosses_land",
    flag_speed_jump, "speed_jump",
    flag_long_jump, "long_jump",
    flag_spike, "spike",
    default = "other"
  )]

  decomp_one_label <- removed_log[, .(n = .N, pct = round(100 * .N / nrow(removed_log), 2)), by = reason][order(-n)]

  cat("\nBy category (single-label, priority order):\n")
  print(decomp_one_label)

  cat("\nBy iteration:\n")
  iter_summary <- removed_log[, .(n = .N), by = iteration][order(iteration)]
  print(iter_summary)

} else {
  cat("No points removed by geospatial filters.\n")
}
cat("============================================================\n\n")

# ---- ISOLATION FOREST ----
setorder(dt_nav, Timestamp)
dt_nav[, delta_t       := c(NA_real_, diff(as.numeric(Timestamp)))]
dt_nav[, Course_change := c(NA_real_, abs(diff(Course)))]
dt_nav[Course_change > 180, Course_change := 360 - Course_change]
dt_nav[, Accel         := c(NA_real_, diff(Speed * 0.514444) / pmax(delta_t[-1], 1))]

config_file <- "~/ais-pipeline/configuration/outlier_config_V6.yaml"
if (file.exists(config_file)) {
  config <- yaml.load_file(config_file)
  outlier_config <- list(
    contamination_rate = config$isolation_forest$contamination_rate,
    if_sample_size     = config$isolation_forest$sample_size,
    if_num_trees       = config$isolation_forest$num_trees,
    memory_conservative = TRUE
  )
  cat("[INFO] Configuration loaded:", config_file, "\n")
} else {
  outlier_config <- list(
    contamination_rate = 0.03,
    if_sample_size     = 512,
    if_num_trees       = 50,
    memory_conservative = TRUE
  )
  cat("[INFO] Using default configuration\n")
}

cat("IF parameters: contamination =", outlier_config$contamination_rate,
    "| trees =", outlier_config$if_num_trees, "\n")

detect_outliers_IF_optimized <- function(dt, config) {
  cat("  Starting Isolation Forest...\n")

  features <- c("Lat", "Lon")
  if ("delta_t" %in% names(dt)) features <- c(features, "delta_t")
  if ("Speed" %in% names(dt))   features <- c(features, "Speed")

  dt_features <- dt[, ..features]
  dt_features <- dt_features[complete.cases(dt_features)]

  if (nrow(dt_features) < 50) {
    cat("  Too few data points (", nrow(dt_features), ") — skipping IF\n")
    return(rep(FALSE, nrow(dt)))
  }

  if_model <- isolationForest$new(
    sample_size = min(config$if_sample_size, nrow(dt_features)),
    num_trees   = config$if_num_trees,
    seed        = 42
  )

  if_model$fit(dt_features)
  scores  <- if_model$predict(dt_features)
  thr     <- quantile(scores$anomaly_score, 1 - config$contamination_rate)
  outliers <- scores$anomaly_score > thr

  result <- rep(FALSE, nrow(dt))
  if (nrow(dt_features) == nrow(dt)) {
    result <- outliers
  } else {
    complete_idx <- which(complete.cases(dt[, ..features]))
    result[complete_idx] <- outliers
  }

  cat("  IF done:", sum(result), "outliers out of", nrow(dt), "points\n")
  result
}

cat("Running Isolation Forest...\n")
system.time({
  dt_nav[, outlier_IF := detect_outliers_IF_optimized(dt_nav, outlier_config)]
})

# ---- CRÉATION COLONNES SUPPLÉMENTAIRES ----
cat("Creating is_stop column...\n")
setorder(dt_nav, Timestamp)
dt_nav[, is_stop := (Speed < 1) | (delta_t > 300)]
dt_nav[is.na(is_stop), is_stop := FALSE]
cat("is_stop column created:", sum(dt_nav$is_stop), "stops detected\n")

dt_nav[, Annee := year(Timestamp)]
cat("Additional columns created (Annee, Course_change, Accel)\n")

# ---- STATISTIQUES ----
n_outliers   <- sum(dt_nav$outlier_IF)
outlier_rate <- round(n_outliers / nrow(dt_nav) * 100, 2)
n_stops      <- sum(dt_nav$is_stop)
stop_rate    <- round(n_stops / nrow(dt_nav) * 100, 2)

cat("\nVESSEL RESULTS:", navire_name, "\n")
cat("  Total observations:", nrow(dt_nav), "\n")
cat("  Outliers detected:", n_outliers, "(", outlier_rate, "%)\n")
cat("  Stops detected:", n_stops, "(", stop_rate, "%)\n")

# ---- SAUVEGARDE ----
output_dir <- file.path("~/scratch", paste0("ais_results_", Sys.getenv("SLURM_ARRAY_JOB_ID")))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

safe_name <- gsub("[^A-Za-z0-9_-]", "_", navire_name)
output_file <- file.path(output_dir, sprintf("%02d_%s_%s_clean.rds", task_id, split_job_id, safe_name))

cat("Sauvegarde:", output_file, "\n")
system.time({
  saveRDS(dt_nav, output_file, compress = "xz")
})

# Log suppressions
if (nrow(removed_log) > 0) {
  removed_log_file <- file.path(output_dir, sprintf("%02d_%s_%s_removed_log.rds", task_id, split_job_id, safe_name))
  saveRDS(removed_log, removed_log_file)
  cat("Log suppressions:", removed_log_file, "\n")

  decomp_file <- file.path(output_dir, sprintf("%02d_%s_%s_decomp.csv", task_id, split_job_id, safe_name))
  fwrite(decomp_one_label, decomp_file)
  cat("Breakdown:", decomp_file, "\n")
}

# ---- NETTOYAGE ----
rm(dt_nav)
gc()

cat("\nVessel", navire_name, "processed successfully:", format(Sys.time()), "\n")
cat("Output:", output_file, "\n")
