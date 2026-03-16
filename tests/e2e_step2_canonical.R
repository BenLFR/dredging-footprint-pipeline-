#!/usr/bin/env Rscript
# =============================================================================
# e2e_step2_canonical.R
# End-to-end smoke test: invokes the CANONICAL pipeline/step2_process_navire.R
# script on synthetic toy data — not a mock.
#
# This is the first test that proves "external clone succeeds":
#   1. Generates toy AIS data (generate_toy_data.R)
#   2. Formats it to match step2's expected column schema
#   3. Wires temp SCRATCH_DIR / CONFIG_DIR via env vars
#   4. Runs Rscript pipeline/step2_process_navire.R as a subprocess
#   5. Verifies the canonical output (*_clean.rds) is produced
#
# Scope: step 2 only. Step 3 requires >5 000 points for GMM — incompatible
#   with a fast CI smoke test. Step 3 entrypoint is covered by
#   smoke_test_steps3_6_entrypoints.R.
#
# Usage:
#   Rscript tests/e2e_step2_canonical.R
#
# Requirements:
#   R packages: data.table, lubridate, yaml, mclust, solitude, zoo, sf
#   (the same packages needed to run step 2 for real)
# =============================================================================

suppressPackageStartupMessages(library(data.table))

log <- function(msg) cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))

# ── 0. Locate repo root ────────────────────────────────────────────────────────
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit  <- grep("^--file=", args, value = TRUE)
  if (!length(hit)) stop("Cannot resolve script path.")
  dirname(normalizePath(sub("^--file=", "", hit[[1]]), winslash = "/", mustWork = TRUE))
}
script_dir <- get_script_dir()
repo_root  <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(repo_root)
log(paste("Repo root:", repo_root))

# ── 1. Generate toy AIS CSV ────────────────────────────────────────────────────
log("Generating toy AIS data...")
toy_csv <- file.path(repo_root, "data", "toy", "toy_ais.csv")
status  <- system2("Rscript", args = "data/toy/generate_toy_data.R")
if (status != 0L) stop("[FAIL] generate_toy_data.R exited with code ", status)
if (!file.exists(toy_csv)) stop("[FAIL] toy_ais.csv was not created.")

raw <- fread(toy_csv)
if (!nrow(raw)) stop("[FAIL] toy_ais.csv is empty.")
log(sprintf("Toy rows: %d  |  ssvid: %s", nrow(raw), raw$ssvid[1]))

# ── 2. Create temp scratch layout ──────────────────────────────────────────────
scratch    <- tempfile("e2e_step2_")
split_dir  <- file.path(scratch, "ais_split_e2e")
results_dir <- file.path(scratch, "ais_results_e2e")
dir.create(split_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
log(paste("Scratch:", scratch))

# ── 3. Convert toy CSV to step2's expected column schema ──────────────────────
# step2_process_navire.R expects: Timestamp (POSIXct), Lat, Lon, Speed, Course, ssvid
vessel <- copy(raw)
vessel[, Timestamp := as.POSIXct(timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
setnames(vessel, c("latitude", "longitude", "speed_knots", "course"),
                 c("Lat",      "Lon",       "Speed",       "Course"))
vessel[, ssvid := as.character(ssvid)]
# Drop original columns that have been renamed
vessel[, c("timestamp") := NULL]
setorder(vessel, Timestamp)

vessel_rds <- file.path(split_dir, "vessel_123456789.rds")
saveRDS(vessel, vessel_rds)
log(sprintf("Vessel RDS written: %s  (%d rows)", basename(vessel_rds), nrow(vessel)))

# ── 4. Write navires_metadata.csv ─────────────────────────────────────────────
meta <- data.table(
  Navire    = "vessel_123456789",
  file_path = vessel_rds
)
fwrite(meta, file.path(split_dir, "navires_metadata.csv"))
log("navires_metadata.csv written.")

# ── 5. Run canonical step2 script via env vars ────────────────────────────────
config_dir <- file.path(repo_root, "config")  # uses repo-shipped YAML configs

env_vars <- c(
  sprintf("SCRATCH_DIR=%s",         scratch),
  sprintf("CONFIG_DIR=%s",          config_dir),
  "SPLIT_JOB_ID=e2e",
  "SLURM_ARRAY_TASK_ID=1",
  "SLURM_ARRAY_JOB_ID=e2e",
  # Suppress land-mask lookup (no shp available — step2 skips gracefully)
  sprintf("LAND_MASK_FILE=%s",      file.path(scratch, "nonexistent.shp")),
  sprintf("SHIP_SPECS_FILE=%s",     file.path(config_dir, "ship_specs.yaml")),
  sprintf("OUTLIER_CONFIG_FILE=%s", file.path(config_dir, "outlier_config_V6.yaml"))
)

log("Running pipeline/step2_process_navire.R (canonical script)...")
t_start <- proc.time()

# system2 inherits env; prepend our vars via env= argument
exit_code <- system2(
  "Rscript",
  args = "pipeline/step2_process_navire.R",
  env  = env_vars,
  stdout = "",   # inherit stdout (show in CI log)
  stderr = ""    # inherit stderr
)

elapsed <- round((proc.time() - t_start)["elapsed"], 1)
log(sprintf("step2 exited with code %d  (%.1f s)", exit_code, elapsed))

if (exit_code != 0L) {
  stop(sprintf("[FAIL] pipeline/step2_process_navire.R failed (exit %d).", exit_code))
}

# ── 6. Verify canonical output ────────────────────────────────────────────────
clean_files <- list.files(results_dir, pattern = "_clean\\.rds$", full.names = TRUE)
if (!length(clean_files)) {
  stop(sprintf(
    "[FAIL] No *_clean.rds produced in %s\nContents: %s",
    results_dir,
    paste(list.files(results_dir), collapse = ", ") %||% "(empty)"
  ))
}

clean_dt <- readRDS(clean_files[[1]])
log(sprintf("Output: %s  (%d rows)", basename(clean_files[[1]]), nrow(clean_dt)))

required_cols <- c("Timestamp", "Lat", "Lon", "Speed", "ssvid", "outlier_IF", "is_stop")
missing_cols  <- setdiff(required_cols, names(clean_dt))
if (length(missing_cols)) {
  stop(sprintf("[FAIL] Output missing columns: %s", paste(missing_cols, collapse = ", ")))
}

if (!nrow(clean_dt)) {
  stop("[FAIL] Output *_clean.rds is empty — step 2 filtered all rows.")
}

log(sprintf("Output columns OK. Rows retained: %d / %d (%.0f%%)",
            nrow(clean_dt), nrow(vessel),
            100 * nrow(clean_dt) / nrow(vessel)))

cat("\n[PASS] e2e_step2_canonical.R\n")
cat("       Canonical step2 executed successfully on synthetic toy data.\n")
cat("       This confirms: repo clone -> env var wiring -> step2 output works.\n\n")
