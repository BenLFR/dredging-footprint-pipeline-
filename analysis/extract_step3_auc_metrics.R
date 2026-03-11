#!/usr/bin/env Rscript
# ============================================================================
# extract_step3_auc_metrics.R
# Reads the most recent dragage_gridsearch_results_V6_*.rds produced by
# step3_merge_final.R and extracts per-fold LOYO AUC metrics.
#
# Outputs:
#   output_V6/step3_auc_metrics.csv  — columns: fold_id, auc, mean_auc, sd_auc
#
# Usage:
#   Rscript analysis/extract_step3_auc_metrics.R
#   # Runs locally on any machine with the output_V6/ folder accessible.
# ============================================================================

suppressPackageStartupMessages(library(data.table))

# ── 1. Locate most recent gridsearch RDS ─────────────────────────────────────
# Search both local output_V6/ and cluster-style ~/scratch/output_V6/
search_dirs <- c(
  "output_V6",
  file.path(path.expand("~"), "scratch", "output_V6")
)

rds_files <- character(0)
for (d in search_dirs) {
  if (dir.exists(d)) {
    found <- list.files(d, pattern = "^dragage_gridsearch_results_V6_.*\\.rds$",
                        full.names = TRUE)
    rds_files <- c(rds_files, found)
  }
}

if (length(rds_files) == 0) {
  stop(paste(
    "No dragage_gridsearch_results_V6_*.rds found.",
    "Expected in output_V6/ or ~/scratch/output_V6/.",
    "Run step3_merge_final.R first."
  ))
}

# Pick the most recently modified file
rds_path <- rds_files[which.max(file.info(rds_files)$mtime)]
cat("Reading gridsearch RDS:", basename(rds_path), "\n")

# ── 2. Load and extract AUC fields ───────────────────────────────────────────
gs <- readRDS(rds_path)

# Structure from step3_merge_final.R:
#   list(best_weights, best_auc, auc_sd, auc_folds, n_folds, method, timestamp)
if (!is.list(gs)) {
  stop("Unexpected RDS structure: expected a list with best_auc, auc_folds, etc.")
}

mean_auc  <- gs$best_auc
sd_auc    <- gs$auc_sd
auc_folds <- gs$auc_folds       # numeric vector, one value per LOYO fold
n_folds   <- gs$n_folds
method    <- gs$method

if (is.null(auc_folds) || length(auc_folds) == 0) {
  # Fallback: check inside best_weights sublist
  if (!is.null(gs$best_weights$auc_folds)) {
    auc_folds <- gs$best_weights$auc_folds
    mean_auc  <- gs$best_weights$mean_auc
    sd_auc    <- gs$best_weights$sd_auc
    n_folds   <- gs$best_weights$n_folds
    method    <- gs$best_weights$method
  } else {
    stop("Cannot locate auc_folds vector in RDS. Check step3 output structure.")
  }
}

# ── 3. Compute summary stats ──────────────────────────────────────────────────
valid_auc <- auc_folds[!is.na(auc_folds)]
n_valid   <- length(valid_auc)

if (n_valid == 0) {
  stop("All auc_folds values are NA. Check step3 run for errors.")
}

# Use stored mean/sd if available; otherwise compute
if (is.null(mean_auc) || is.na(mean_auc)) mean_auc <- mean(valid_auc)
if (is.null(sd_auc)   || is.na(sd_auc))   sd_auc   <- sd(valid_auc)

cat(sprintf("\nStep 3 LOYO AUC: mean=%.4f, SD=%.4f (%d folds, method=%s)\n",
            mean_auc, sd_auc, n_valid, method))
cat(sprintf("  Min = %.4f | Max = %.4f\n", min(valid_auc), max(valid_auc)))

if (any(is.na(auc_folds))) {
  cat(sprintf("  Note: %d fold(s) returned NA (mono-class test set)\n",
              sum(is.na(auc_folds))))
}

# ── 4. Build output CSV ───────────────────────────────────────────────────────
metrics_dt <- data.table(
  fold_id     = seq_along(auc_folds),
  auc         = auc_folds,
  mean_auc    = mean_auc,
  sd_auc      = sd_auc,
  model_config = method
)

# ── 5. Save ───────────────────────────────────────────────────────────────────
dir.create("output_V6", showWarnings = FALSE, recursive = TRUE)
out_path <- "output_V6/step3_auc_metrics.csv"
fwrite(metrics_dt, out_path)
cat(sprintf("\nSaved: %s\n", out_path))
cat("Columns:", paste(names(metrics_dt), collapse = ", "), "\n")
