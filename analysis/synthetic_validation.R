#!/usr/bin/env Rscript
# ============================================================================
# synthetic_validation.R
# PURPOSE: This is an internal formula consistency check, NOT an independent
# validation. Both fi_known and fi_pipeline use the same formula, so a PASS only
# confirms algebraic self-consistency. External validation against real dredging
# records is still required for scientific claims.
#
# Creates 5 virtual dredgers with known swept area and verifies that the
# pipeline fi formula recovers the same value within +/-15%.
#
# Output: output_V6/validation/synthetic_test_results.txt
# ============================================================================

suppressPackageStartupMessages(library(data.table))

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")
validation_dir <- file.path(output_root, "validation")
dir.create(validation_dir, showWarnings = FALSE, recursive = TRUE)

CELL_SIZE_M <- 1000L
CELL_AREA_M2 <- 1e6
KN_TO_MS <- 0.5144444

ALPHA_DEP <- 0.25
FAST_FRACTION <- 0.30
SLOW_K <- 0.05
PRESERVATION_FACTOR <- 0.87
K_FAST_GLOBAL_MEAN <- 1.67

PASS_THRESHOLD <- 0.15
PASS_MIN_FRAC <- 0.80

vessels <- data.table(
  vessel_id = c("V001", "V002", "V003", "V004", "V005"),
  dredge_width_m = c(20L, 15L, 25L, 18L, 22L),
  speed_kn = c(2.0, 1.5, 2.5, 1.8, 2.2),
  hours_dredging_day = c(16, 12, 20, 14, 18),
  region = c("North Sea", "Persian Gulf", "South China Sea", "Bay of Biscay", "Gulf of Mexico"),
  box_lon = c(3.0, 52.0, 110.0, -4.0, -90.0),
  box_lat = c(54.0, 26.0, 15.0, 45.0, 25.0)
)

# The synthetic setup uses a shared formula on both sides of the comparison.
p_d_safe <- 1.0
w1 <- min(0.05, p_d_safe) / p_d_safe
w2 <- min(0.05, max(p_d_safe - 0.05, 0)) / p_d_safe
p_l_eff <- w1 * 1.0 + w2 * 1.0 * ALPHA_DEP
p_l_corr <- p_l_eff
miner_factor <- FAST_FRACTION * (1 - exp(-K_FAST_GLOBAL_MEAN)) +
  (1 - FAST_FRACTION) * (1 - exp(-SLOW_K))

cat(sprintf("Mineralization factor: %.6f\n", miner_factor))
cat(sprintf("Preservation factor:   %.3f\n\n", PRESERVATION_FACTOR))
cat("NOTE: This test checks formula self-consistency only.\n")

generate_pings <- function(v, n_days = 30, delta_t_s = 600) {
  speed_ms <- v$speed_kn * KN_TO_MS
  dist_ping <- speed_ms * delta_t_s

  pings_per_day <- as.integer(v$hours_dredging_day * 3600 / delta_t_s)
  total_pings <- pings_per_day * n_days
  box_half_m <- 25000

  set.seed(as.integer(chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "01234567890123456789012345",
    substr(v$vessel_id, 2, 4)
  )))

  heading <- runif(1, 0, 360)
  x <- 0
  y <- 0
  xs <- numeric(total_pings)
  ys <- numeric(total_pings)

  for (i in seq_len(total_pings)) {
    heading <- (heading + rnorm(1, 0, 5)) %% 360
    dx <- dist_ping * sin(heading * pi / 180)
    dy <- dist_ping * cos(heading * pi / 180)
    x <- max(-box_half_m, min(box_half_m, x + dx))
    y <- max(-box_half_m, min(box_half_m, y + dy))
    xs[i] <- x
    ys[i] <- y
  }

  data.table(
    ssvid = v$vessel_id,
    x_m = xs,
    y_m = ys,
    speed_kn = v$speed_kn + rnorm(total_pings, 0, 0.1),
    Dragage_flag = 1L,
    dredge_width_m = v$dredge_width_m
  )
}

compute_fi_pipeline <- function(pings, v) {
  pings[, cell_x := floor(x_m / CELL_SIZE_M)]
  pings[, cell_y := floor(y_m / CELL_SIZE_M)]
  pings[, cell_id := paste0(cell_x, "_", cell_y)]

  dist_ping_m <- v$speed_kn * KN_TO_MS * 600
  cell_stats <- pings[Dragage_flag == 1, .(n_pings_dredge = .N), by = cell_id]

  cell_stats[, SAR_pipeline := (v$dredge_width_m * n_pings_dredge * dist_ping_m) / CELL_AREA_M2]
  cell_stats[, fi_pipeline := SAR_pipeline * p_l_corr * PRESERVATION_FACTOR * miner_factor]
  cell_stats
}

compute_fi_known <- function(pings, v) {
  dist_ping_m <- v$speed_kn * KN_TO_MS * 600

  pings[, cell_x := floor(x_m / CELL_SIZE_M)]
  pings[, cell_y := floor(y_m / CELL_SIZE_M)]
  pings[, cell_id := paste0(cell_x, "_", cell_y)]

  cell_truth <- pings[Dragage_flag == 1, .(n_pings_dredge = .N), by = cell_id]
  cell_truth[, SAR_known := (v$dredge_width_m * n_pings_dredge * dist_ping_m) / CELL_AREA_M2]
  cell_truth[, fi_known := SAR_known * p_l_corr * PRESERVATION_FACTOR * miner_factor]
  cell_truth
}

N_DAYS <- 30
DELTA_T_S <- 600

results_all <- list()
pass_log <- character()

cat(sprintf("%-8s %-18s %9s %9s %9s %8s %6s\n",
            "Vessel", "Region", "fi_known", "fi_pipe", "err_pct", "n_cells", "Pass?"))
cat(strrep("-", 72), "\n")

for (i in seq_len(nrow(vessels))) {
  v <- vessels[i]
  pings <- generate_pings(v, n_days = N_DAYS, delta_t_s = DELTA_T_S)

  fi_pipe <- compute_fi_pipeline(pings, v)
  fi_truth <- compute_fi_known(pings, v)
  comp <- merge(fi_pipe, fi_truth[, .(cell_id, fi_known)], by = "cell_id")

  if (nrow(comp) == 0) {
    line <- sprintf("FAIL [%s - %s]: no cells to compare", v$vessel_id, v$region)
    cat(line, "\n")
    pass_log <- c(pass_log, line)
    next
  }

  comp[, rel_err := abs(fi_pipeline - fi_known) / pmax(fi_known, 1e-12)]
  frac_pass <- mean(comp$rel_err < PASS_THRESHOLD, na.rm = TRUE)
  cell_pass <- if (frac_pass >= PASS_MIN_FRAC) "PASS" else "FAIL"

  med_known <- median(comp$fi_known, na.rm = TRUE)
  med_pipe <- median(comp$fi_pipeline, na.rm = TRUE)
  med_err <- median(comp$rel_err, na.rm = TRUE) * 100

  cat(sprintf("%-8s %-18s %9.4f %9.4f %8.1f%% %8d  %s\n",
              v$vessel_id, v$region, med_known, med_pipe, med_err, nrow(comp), cell_pass))

  line <- sprintf(
    "%s [%s - %s]: median fi_known=%.6f, fi_pipeline=%.6f, err=%.1f%%, cells_passing=%.0f%% (%d cells)",
    cell_pass, v$vessel_id, v$region, med_known, med_pipe, med_err, frac_pass * 100, nrow(comp)
  )
  pass_log <- c(pass_log, line)

  results_all[[v$vessel_id]] <- comp[, .(
    cell_id,
    fi_known,
    fi_pipeline,
    rel_err,
    cell_pass = rel_err < PASS_THRESHOLD
  )]
}

n_pass <- sum(grepl("^PASS", pass_log))
n_total <- nrow(vessels)
overall <- if (n_pass >= 4) "OVERALL PASS" else "OVERALL FAIL"

cat(strrep("-", 72), "\n")
cat(sprintf("%s: %d/%d vessels pass (threshold: %d/5)\n\n", overall, n_pass, n_total, 4L))

out_txt <- file.path(validation_dir, "synthetic_test_results.txt")
out_csv <- file.path(validation_dir, "synthetic_test_details.csv")

writeLines(c(
  "=== Synthetic Validation Results [FORMULA INTEGRITY CHECK - not an external validation] ===",
  sprintf("Date: %s", Sys.time()),
  "PURPOSE: internal formula consistency check only; fi_known and fi_pipeline use the same formula.",
  sprintf(
    "N_DAYS=%d | DELTA_T=%ds | PASS_THRESHOLD=%.0f%% | PASS_MIN_FRAC=%.0f%%",
    N_DAYS, DELTA_T_S, PASS_THRESHOLD * 100, PASS_MIN_FRAC * 100
  ),
  "",
  "Per-vessel results (median cell-level statistics):",
  pass_log,
  "",
  sprintf("%s: %d/%d vessels pass", overall, n_pass, n_total)
), out_txt)

if (length(results_all) > 0) {
  all_dt <- rbindlist(results_all, idcol = "vessel_id")
  fwrite(all_dt, out_csv)
}

cat(sprintf("Saved: %s\n", out_txt))
cat(sprintf("Saved: %s\n", out_csv))
