#!/usr/bin/env Rscript
# ============================================================================
# benchmark_vs_baseline.R
# Compares step3 GMM+DBSCAN dredging classifier against two naive baselines
# on the same AIS subset.
#
# Baselines:
#   1. Speed threshold: ping = dredging if speed_knots < 4.0 kn
#      (uses dredging_threshold from outlier_config_V6.yaml)
#   2. GFW-style proxy: speed < 4.0 kn AND heading_change_deg < 45°
#
# Reference method: step3 'behavior_smooth' or 'Dragage_flag' column
#
# Outputs:
#   output_V6/benchmarking_results.csv     — precision, recall, F1, AUC per method
#   output_V6/benchmarking_comparison.png  — grouped bar chart
#
# Usage:
#   Rscript scripts_principaux/benchmark_vs_baseline.R
#   Rscript scripts_principaux/benchmark_vs_baseline.R [path/to/AIS_data_core.rds]
#
# Why these baselines?
#   Speed threshold: the simplest possible proxy for dredging; ignores heading,
#   port anchoring, and slow transit. Overestimates dredging in congested areas.
#   GFW proxy: adds a heading-change filter inspired by Global Fishing Watch's
#   fishing hour estimation (Kroodsma et al. 2018, Science). It is tuned for
#   trawling / fishing, not dredging — heading-change filter may miss slow-arc
#   TSHD dredging patterns. Both baselines serve as lower-bound reference points.
# ============================================================================

# ── Speed threshold used in pipeline (from outlier_config_V6.yaml) ────────────
DREDGING_SPEED_THRESHOLD_KN <- 4.0   # contextual$dredging_threshold
GFW_HEADING_CHANGE_MAX_DEG  <- 45.0  # GFW heuristic (not from repo config)

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# ── 1. Locate input data ──────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)

find_core_rds <- function() {
  search_dirs <- c(
    "output_V6",
    file.path(path.expand("~"), "scratch", "output_V6"),
    "scripts_cluster"
  )
  for (d in search_dirs) {
    if (!dir.exists(d)) next
    found <- list.files(d, pattern = "^AIS_data_core_preprocessed_V6_.*_flagOK\\.rds$",
                        full.names = TRUE)
    if (length(found) > 0)
      return(found[which.max(file.info(found)$mtime)])
  }
  NULL
}

rds_path <- if (length(args) > 0) args[1] else find_core_rds()

if (is.null(rds_path) || !file.exists(rds_path)) {
  stop(paste(
    "No AIS_data_core_preprocessed_V6_*_flagOK.rds found.",
    "Provide path as argument or ensure output_V6/ is accessible.",
    "Expected output from step3_merge_final.R."
  ))
}

cat("Loading step3 output:", basename(rds_path), "\n")
ais <- setDT(readRDS(rds_path))
cat(sprintf("Loaded: %d rows, %d columns\n", nrow(ais), ncol(ais)))
cat("Columns:", paste(head(names(ais), 20), collapse = ", "), "...\n\n")

# ── 2. Identify the reference (step3) dredging label ──────────────────────────
# step3 produces either 'behavior_smooth' (categorical) or 'Dragage_flag' (0/1)
ref_col <- if ("behavior_smooth" %in% names(ais)) "behavior_smooth" else
           if ("Dragage_flag" %in% names(ais)) "Dragage_flag" else NULL

if (is.null(ref_col)) {
  stop("Neither 'behavior_smooth' nor 'Dragage_flag' found. Check step3 output columns.")
}

cat(sprintf("Using '%s' as step3 reference label.\n", ref_col))

# Normalise reference to binary: 1 = dredging, 0 = other
if (is.character(ais[[ref_col]]) || is.factor(ais[[ref_col]])) {
  ais[, ref_binary := as.integer(get(ref_col) == "dredging")]
} else {
  ais[, ref_binary := as.integer(as.logical(get(ref_col)))]
}

# Drop rows where label is NA or where speed is missing
required_cols <- c("speed_knots", ref_col)
ais <- ais[complete.cases(ais[, ..required_cols])]

cat(sprintf("After filtering: %d rows | Dredging: %d (%.1f%%)\n",
            nrow(ais),
            sum(ais$ref_binary),
            mean(ais$ref_binary) * 100))

# ── 3. Apply baselines ────────────────────────────────────────────────────────
# Baseline 1: speed threshold
ais[, pred_speed := as.integer(speed_knots < DREDGING_SPEED_THRESHOLD_KN)]

# Baseline 2: GFW-style (speed + heading change)
has_heading_change <- "heading_change_deg" %in% names(ais) ||
                      "turn_rate" %in% names(ais)

if ("heading_change_deg" %in% names(ais)) {
  ais[, pred_gfw := as.integer(speed_knots < DREDGING_SPEED_THRESHOLD_KN &
                                abs(heading_change_deg) < GFW_HEADING_CHANGE_MAX_DEG)]
} else if ("turn_rate" %in% names(ais)) {
  ais[, pred_gfw := as.integer(speed_knots < DREDGING_SPEED_THRESHOLD_KN &
                                abs(turn_rate) < GFW_HEADING_CHANGE_MAX_DEG)]
} else {
  cat("No heading_change column found — GFW baseline uses speed-only fallback.\n")
  ais[, pred_gfw := pred_speed]
  has_heading_change <- FALSE
}

# ── 4. Compute metrics per method ─────────────────────────────────────────────
compute_metrics <- function(pred, true, method_name) {
  tp <- sum(pred == 1 & true == 1, na.rm = TRUE)
  fp <- sum(pred == 1 & true == 0, na.rm = TRUE)
  fn <- sum(pred == 0 & true == 1, na.rm = TRUE)
  tn <- sum(pred == 0 & true == 0, na.rm = TRUE)

  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall    <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  f1_macro  <- if (!is.na(precision) && !is.na(recall) && precision + recall > 0)
                 2 * precision * recall / (precision + recall) else NA_real_

  # AUC-ROC (binary, using pred as probability proxy)
  auc_val <- tryCatch({
    if (requireNamespace("pROC", quietly = TRUE)) {
      roc_obj <- pROC::roc(true, pred, quiet = TRUE)
      as.numeric(pROC::auc(roc_obj))
    } else NA_real_
  }, error = function(e) NA_real_)

  data.table(
    method        = method_name,
    precision     = round(precision, 4),
    recall        = round(recall, 4),
    f1_macro      = round(f1_macro, 4),
    f1_weighted   = round(f1_macro, 4),   # same for binary
    auc           = round(auc_val, 4),
    n_dredging    = as.integer(sum(pred == 1, na.rm = TRUE)),
    n_transit     = as.integer(sum(pred == 0, na.rm = TRUE)),
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}

results <- rbindlist(list(
  compute_metrics(ais$pred_speed, ais$ref_binary,
                  sprintf("speed_threshold_%.0fkn", DREDGING_SPEED_THRESHOLD_KN)),
  compute_metrics(ais$pred_gfw, ais$ref_binary,
                  if (has_heading_change) "gfw_speed_heading" else "gfw_speed_only"),
  compute_metrics(ais$ref_binary, ais$ref_binary,
                  "step3_gmm_dbscan")   # oracle (reference vs itself) = perfect by definition
))

cat("\n=== Benchmarking Results ===\n")
print(results[, .(method, precision, recall, f1_macro, auc, n_dredging)])

# ── 5. Save CSV ───────────────────────────────────────────────────────────────
dir.create("output_V6", showWarnings = FALSE, recursive = TRUE)
fwrite(results, "output_V6/benchmarking_results.csv")
cat("Saved: output_V6/benchmarking_results.csv\n")

# ── 6. Bar chart ──────────────────────────────────────────────────────────────
plot_dt <- melt(results[, .(method, precision, recall, f1_macro, auc)],
                id.vars = "method", variable.name = "metric", value.name = "value")

# Remove oracle from plot (trivially perfect)
plot_dt <- plot_dt[method != "step3_gmm_dbscan"]

p <- ggplot(plot_dt, aes(x = metric, y = value, fill = method)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  scale_fill_manual(values = c("#2166ac", "#d6604d"),
                    labels = c("GFW-style proxy", "Speed threshold")) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    title    = "Dredging Classifier Benchmarking",
    subtitle = sprintf("Baselines vs Step 3 GMM+DBSCAN reference | n = %d pings",
                       nrow(ais)),
    x        = "Metric",
    y        = "Score",
    fill     = "Method",
    caption  = sprintf("Speed threshold: < %.0f kn | GFW heading filter: < %.0f°",
                       DREDGING_SPEED_THRESHOLD_KN, GFW_HEADING_CHANGE_MAX_DEG)
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave("output_V6/benchmarking_comparison.png", p,
       width = 8, height = 5, dpi = 150)
cat("Saved: output_V6/benchmarking_comparison.png\n")

cat("\nNote: step3_gmm_dbscan row compares reference vs itself (trivially perfect).\n")
cat("The meaningful comparison is between the two baselines.\n")
cat("A reviewer will ask: how much better is step3 than these naive approaches?\n")
cat("Use 'drag_score' probability column (if present) for a soft AUC comparison.\n")
