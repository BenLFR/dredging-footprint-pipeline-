#!/usr/bin/env Rscript
# ============================================================================
# pipeline_warnings.R
# Runtime programmatic enforcement of known method limitations.
# Sourced at the start of step2_process_navire.R and step5_compute_fi_global.R.
#
# Emits warning() (NOT stop()) so the pipeline continues while logging when it
# is operating outside validated scope. All messages reference LIMITATIONS.md.
#
# Usage (at top of step2 / step5):
#   if (file.exists("scripts_principaux/pipeline_warnings.R"))
#     source("scripts_principaux/pipeline_warnings.R")
#
# Then call inside each step:
#   check_ais_coverage_region(dt)
#   check_vessel_size(specs_dt)
#   check_ping_density(dt)
#   check_near_coast_exclusion(dt)
#   check_ocim_scope(range(fi_dt$lat, na.rm = TRUE))
# ============================================================================

# ── 1. AIS coverage region ───────────────────────────────────────────────────
check_ais_coverage_region <- function(dt,
                                      lat_col = "Latitude",
                                      lon_col = "Longitude") {
  # Warn if >10% of pings are in known low-coverage regions (Arctic/Antarctic).
  # AIS coverage is unreliable at high latitudes; see LIMITATIONS.md §Known failure modes.
  if (!lat_col %in% names(dt)) return(invisible(NULL))
  lats <- dt[[lat_col]]

  pct_polar <- mean(abs(lats) > 65, na.rm = TRUE)
  if (pct_polar > 0.10)
    warning(sprintf(
      paste0(
        "[LIMITATION] %.1f%% of pings are at |lat| > 65° (Arctic/Antarctic). ",
        "AIS coverage is unreliable in these regions and dredging intensity ",
        "is likely underestimated. ",
        "See documentation/LIMITATIONS.md#known-failure-modes."
      ),
      pct_polar * 100
    ), call. = FALSE)

  # Also warn if southern hemisphere south of -55° (no commercial AIS there)
  pct_southern <- mean(lats < -55, na.rm = TRUE)
  if (pct_southern > 0.05)
    warning(sprintf(
      paste0(
        "[LIMITATION] %.1f%% of pings are south of 55°S. ",
        "No commercial dredging is expected here; verify data integrity. ",
        "See documentation/LIMITATIONS.md#valid-geographic-and-temporal-scope."
      ),
      pct_southern * 100
    ), call. = FALSE)

  invisible(NULL)
}

# ── 2. Vessel size / ship specs ───────────────────────────────────────────────
check_vessel_size <- function(specs_dt) {
  # Warn when vessels are not found in ship_specs.yaml and received mean TSHD values.
  # The column name for the flag varies — check both common patterns.
  flag_col <- intersect(c("used_default", "default_specs", "specs_source"),
                        names(specs_dt))[1]
  width_col <- intersect(c("dredge_width_m", "beam_m", "sweep_width_m"),
                         names(specs_dt))[1]

  n_unknown <- 0L
  if (!is.na(flag_col))
    n_unknown <- sum(specs_dt[[flag_col]] == TRUE, na.rm = TRUE)
  else if (!is.na(width_col))
    n_unknown <- sum(is.na(specs_dt[[width_col]]))

  if (n_unknown > 0L)
    warning(sprintf(
      paste0(
        "[LIMITATION] %d vessel(s) not found in configuration/ship_specs.yaml ",
        "— using mean TSHD sweep-width values. ",
        "f_i estimates for unknown vessels are approximate. ",
        "See documentation/LIMITATIONS.md#fundamental-assumptions (point 4)."
      ),
      n_unknown
    ), call. = FALSE)

  invisible(NULL)
}

# ── 3. Ping density ───────────────────────────────────────────────────────────
check_ping_density <- function(dt,
                               mmsi_col    = "ssvid",
                               threshold   = 100L) {
  # Warn when vessels have fewer pings than min_points_per_vessel.
  # Isolation Forest classification is unreliable with sparse inputs.
  if (!mmsi_col %in% names(dt)) {
    # Try common alternatives
    mmsi_col <- intersect(c("MMSI", "mmsi", "vessel_id"), names(dt))[1]
    if (is.na(mmsi_col)) return(invisible(NULL))
  }

  counts <- dt[, .N, by = mmsi_col]
  n_sparse <- sum(counts$N < threshold, na.rm = TRUE)

  if (n_sparse > 0L)
    warning(sprintf(
      paste0(
        "[LIMITATION] %d vessel(s) have fewer than %d pings ",
        "(below min_points_per_vessel threshold). ",
        "Isolation Forest outlier classification may be unreliable for these vessels. ",
        "See documentation/LIMITATIONS.md#known-failure-modes."
      ),
      n_sparse, threshold
    ), call. = FALSE)

  invisible(NULL)
}

# ── 4. Near-coast exclusion ───────────────────────────────────────────────────
check_near_coast_exclusion <- function(dt,
                                       near_coast_col = "near_coast",
                                       threshold_pct  = 0.30) {
  # Warn when a large fraction of pings are removed by the near-coast filter.
  # High exclusion rates indicate the study region has significant near-shore
  # dredging that the pipeline cannot capture.
  if (!near_coast_col %in% names(dt)) return(invisible(NULL))

  pct_excluded <- mean(dt[[near_coast_col]] == TRUE, na.rm = TRUE)

  if (pct_excluded > threshold_pct)
    warning(sprintf(
      paste0(
        "[LIMITATION] %.1f%% of pings excluded by the near-coast buffer filter. ",
        "Estuarine and near-shore dredging is likely underestimated for this region. ",
        "Consider reducing the buffer radius in outlier_config_V6.yaml if your ",
        "study area is primarily coastal. ",
        "See documentation/LIMITATIONS.md#known-failure-modes."
      ),
      pct_excluded * 100
    ), call. = FALSE)

  invisible(NULL)
}

# ── 5. OCIM scope ─────────────────────────────────────────────────────────────
check_ocim_scope <- function(lat_range) {
  # Warn when Jdredge contains high-latitude cells where OCIM steady-state
  # assumptions are weakest (polar circulation is highly seasonal).
  if (length(lat_range) < 1 || all(is.na(lat_range))) return(invisible(NULL))

  if (max(abs(lat_range), na.rm = TRUE) > 70)
    warning(
      paste0(
        "[LIMITATION] Jdredge contains cells at |lat| > 70°. ",
        "The OCIM2-48L transport matrix assumes steady-state ocean circulation, ",
        "which is weakest in polar regions where seasonal variability is high. ",
        "Interpret CO2 flux estimates at high latitudes with caution. ",
        "See documentation/LIMITATIONS.md#fundamental-assumptions (point 5)."
      ),
      call. = FALSE
    )

  invisible(NULL)
}

cat("[pipeline_warnings.R] Runtime limitation checks loaded.\n",
    "  Functions: check_ais_coverage_region, check_vessel_size,\n",
    "             check_ping_density, check_near_coast_exclusion,\n",
    "             check_ocim_scope\n")
