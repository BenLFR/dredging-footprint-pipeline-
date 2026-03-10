#!/usr/bin/env Rscript
# =============================================================================
# generate_toy_data.R
# Generates a synthetic single-vessel AIS dataset for pipeline smoke testing.
#
# Output: data/toy/toy_ais.csv  (~500 rows, 30 days, North Sea TSHD profile)
# Usage:  Rscript data/toy/generate_toy_data.R
# =============================================================================

set.seed(42)

# --- Parameters ---------------------------------------------------------------
SSVID       <- "123456789"         # Synthetic ssvid (GFW vessel identifier)
VESSEL_TYPE <- "dredging"          # GFW vessel_class value
START_TIME  <- as.POSIXct("2020-06-01 00:00:00", tz = "UTC")
N_DAYS      <- 30
# North Sea bounding box (degrees)
LON_MIN <- 2.0;  LON_MAX <- 6.0
LAT_MIN <- 51.5; LAT_MAX <- 53.5

# --- Simulate TSHD motion profile --------------------------------------------
# Pattern: dredging leg (slow, 2-4 kn, straight) → transit (fast, 8-12 kn) → repeat
records <- vector("list", 0)
t       <- START_TIME
lon     <- 4.0   # starting position
lat     <- 52.5

while (t < START_TIME + N_DAYS * 86400) {

  # -- Dredging leg (30-90 min) ------------------------------------------------
  leg_duration <- sample(30:90, 1) * 60   # seconds
  speed_kn     <- runif(1, 1.5, 3.5)
  speed_ms     <- speed_kn * 0.514444
  heading      <- runif(1, 0, 360)
  n_pts        <- max(3, floor(leg_duration / 120))  # 1 point every ~2 min

  for (i in seq_len(n_pts)) {
    dt   <- leg_duration / n_pts
    dlat <- speed_ms * dt * cos(heading * pi / 180) / 111320
    dlon <- speed_ms * dt * sin(heading * pi / 180) / (111320 * cos(lat * pi / 180))
    lat  <- lat + dlat
    lon  <- lon + dlon
    # Bounce off bounding box
    lat <- pmax(LAT_MIN, pmin(LAT_MAX, lat))
    lon <- pmax(LON_MIN, pmin(LON_MAX, lon))
    records[[length(records) + 1]] <- list(
      ssvid       = SSVID,
      timestamp   = format(t + (i - 1) * dt, "%Y-%m-%dT%H:%M:%SZ"),
      latitude    = round(lat, 6),
      longitude   = round(lon, 6),
      speed_knots = round(speed_kn + rnorm(1, 0, 0.1), 2),
      course      = round(heading + rnorm(1, 0, 2)) %% 360,
      vessel_type = VESSEL_TYPE
    )
  }
  t <- t + leg_duration

  # -- Transit (15-45 min) -----------------------------------------------------
  transit_duration <- sample(15:45, 1) * 60
  speed_kn         <- runif(1, 7.5, 12.0)
  heading          <- runif(1, 0, 360)
  n_pts            <- max(2, floor(transit_duration / 120))

  for (i in seq_len(n_pts)) {
    dt   <- transit_duration / n_pts
    speed_ms <- speed_kn * 0.514444
    dlat <- speed_ms * dt * cos(heading * pi / 180) / 111320
    dlon <- speed_ms * dt * sin(heading * pi / 180) / (111320 * cos(lat * pi / 180))
    lat  <- pmax(LAT_MIN, pmin(LAT_MAX, lat + dlat))
    lon  <- pmax(LON_MIN, pmin(LON_MAX, lon + dlon))
    records[[length(records) + 1]] <- list(
      ssvid       = SSVID,
      timestamp   = format(t + (i - 1) * dt, "%Y-%m-%dT%H:%M:%SZ"),
      latitude    = round(lat, 6),
      longitude   = round(lon, 6),
      speed_knots = round(speed_kn + rnorm(1, 0, 0.3), 2),
      course      = round(heading + rnorm(1, 0, 5)) %% 360,
      vessel_type = VESSEL_TYPE
    )
  }
  t <- t + transit_duration
}

df <- do.call(rbind, lapply(records, as.data.frame, stringsAsFactors = FALSE))

# --- Write output -------------------------------------------------------------
script_path <- NA_character_
cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- sub("^--file=", "", file_arg[[1]])
}

if (!is.na(script_path) && nzchar(script_path)) {
  out_dir <- dirname(normalizePath(script_path, winslash = "/", mustWork = FALSE))
  out_file <- file.path(out_dir, "toy_ais.csv")
} else {
  # Fallback for interactive use
  out_file <- "data/toy/toy_ais.csv"
}

dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
write.csv(df, out_file, row.names = FALSE)

message(sprintf("Toy dataset written to: %s", out_file))
message(sprintf("Rows: %d | Days: %d | ssvid: %s", nrow(df), N_DAYS, SSVID))
