#!/usr/bin/env Rscript
# ============================================================================
# benchmark_vs_baseline.R
# Compares the step3 dredging classifier against two naive baselines on the
# same AIS subset.
#
# Baselines:
#   1. Speed threshold baseline
#   2. GFW-style speed + heading proxy
#
# Outputs:
#   output_V6/benchmarking_results.csv
#   output_V6/benchmarking_comparison.png
# ============================================================================

DREDGING_SPEED_THRESHOLD_KN <- 4.0
GFW_HEADING_CHANGE_MAX_DEG <- 45.0

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")

find_core_rds <- function() {
  search_dirs <- unique(c(
    output_root,
    "output_V6",
    "scripts_cluster"
  ))
  for (d in search_dirs) {
    if (!dir.exists(d)) {
      next
    }
    found <- list.files(
      d,
      pattern = "^AIS_data_core_preprocessed_V6_.*_flagOK\\.rds$",
      full.names = TRUE
    )
    if (length(found) > 0) {
      return(found[which.max(file.info(found)$mtime)])
    }
  }
  NULL
}

rds_path <- if (length(args) > 0) args[1] else find_core_rds()
if (is.null(rds_path) || !file.exists(rds_path)) {
  stop(paste(
    "No AIS_data_core_preprocessed_V6_*_flagOK.rds found.",
    "Provide a path as argument or ensure OUTPUT_DIR (default: output_V6/) is accessible."
  ))
}

cat("Loading step3 output:", basename(rds_path), "\n")
ais <- setDT(readRDS(rds_path))
cat(sprintf("Loaded: %d rows, %d columns\n", nrow(ais), ncol(ais)))

ref_col <- if ("behavior_smooth" %in% names(ais)) {
  "behavior_smooth"
} else if ("Dragage_flag" %in% names(ais)) {
  "Dragage_flag"
} else {
  NULL
}
if (is.null(ref_col)) {
  stop("Neither 'behavior_smooth' nor 'Dragage_flag' found in step3 output.")
}
cat(sprintf("Using '%s' as step3 reference label.\n", ref_col))

speed_candidates <- c("speed_knots", "Speed", "speed", "SOG", "sog", "Vitesse")
speed_col <- speed_candidates[speed_candidates %in% names(ais)][1]
if (is.na(speed_col)) {
  stop("No speed column found. Tried: ", paste(speed_candidates, collapse = ", "))
}
if (speed_col != "speed_knots") {
  ais[, speed_knots := as.numeric(get(speed_col))]
}
cat(sprintf("Using '%s' as speed column.\n", speed_col))

drag_score_col <- if ("drag_score" %in% names(ais)) "drag_score" else NULL
if (!is.null(drag_score_col)) {
  cat("Found 'drag_score' column for soft AUC benchmarking.\n")
}

if (is.character(ais[[ref_col]]) || is.factor(ais[[ref_col]])) {
  ais[, ref_binary := as.integer(grepl("dredg|drag", as.character(get(ref_col)), ignore.case = TRUE))]
} else {
  ais[, ref_binary := as.integer(as.logical(get(ref_col)))]
}

required_cols <- c("speed_knots", ref_col)
ais <- ais[complete.cases(ais[, ..required_cols])]
cat(sprintf("After filtering: %d rows | Dredging: %d (%.1f%%)\n",
            nrow(ais), sum(ais$ref_binary), mean(ais$ref_binary) * 100))

heading_candidates <- c("heading_change_deg", "turn_rate", "Course_change", "course_change")
heading_col <- heading_candidates[heading_candidates %in% names(ais)][1]
has_heading_change <- !is.na(heading_col)

ais[, pred_speed := as.integer(speed_knots < DREDGING_SPEED_THRESHOLD_KN)]
if (has_heading_change) {
  ais[, pred_gfw := as.integer(
    speed_knots < DREDGING_SPEED_THRESHOLD_KN &
      abs(get(heading_col)) < GFW_HEADING_CHANGE_MAX_DEG
  )]
  cat(sprintf("Using '%s' as heading-change column.\n", heading_col))
} else {
  ais[, pred_gfw := pred_speed]
  cat("No heading-change column found - GFW baseline falls back to speed only.\n")
}

compute_metrics <- function(pred, true, method_name) {
  tp <- sum(pred == 1 & true == 1, na.rm = TRUE)
  fp <- sum(pred == 1 & true == 0, na.rm = TRUE)
  fn <- sum(pred == 0 & true == 1, na.rm = TRUE)
  tn <- sum(pred == 0 & true == 0, na.rm = TRUE)

  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  f1_macro <- if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0) {
    2 * precision * recall / (precision + recall)
  } else {
    NA_real_
  }

  auc_val <- tryCatch({
    if (requireNamespace("pROC", quietly = TRUE)) {
      roc_obj <- pROC::roc(true, pred, quiet = TRUE)
      as.numeric(pROC::auc(roc_obj))
    } else {
      NA_real_
    }
  }, error = function(e) NA_real_)

  data.table(
    method = method_name,
    precision = round(precision, 4),
    recall = round(recall, 4),
    f1_macro = round(f1_macro, 4),
    f1_weighted = round(f1_macro, 4),
    auc = round(auc_val, 4),
    n_dredging = as.integer(sum(pred == 1, na.rm = TRUE)),
    n_transit = as.integer(sum(pred == 0, na.rm = TRUE)),
    tp = tp,
    fp = fp,
    fn = fn,
    tn = tn
  )
}

speed_method <- sprintf("speed_threshold_%.0fkn", DREDGING_SPEED_THRESHOLD_KN)
gfw_method <- if (has_heading_change) "gfw_speed_heading" else "gfw_speed_only"

results <- rbindlist(list(
  compute_metrics(ais$pred_speed, ais$ref_binary, speed_method),
  compute_metrics(ais$pred_gfw, ais$ref_binary, gfw_method)
))

if (!is.null(drag_score_col)) {
  if (requireNamespace("pROC", quietly = TRUE)) {
    valid_soft <- ais[is.finite(get(drag_score_col))]
    if (nrow(valid_soft) > 0) {
      auc_soft <- pROC::roc(valid_soft$ref_binary, valid_soft[[drag_score_col]], quiet = TRUE)
      soft_auc_value <- round(as.numeric(pROC::auc(auc_soft)), 4)
      cat(sprintf("Soft AUC (drag_score): %.4f\n", soft_auc_value))
      results <- rbindlist(list(
        results,
        data.table(
          method = "step3_drag_score_auc",
          precision = NA_real_,
          recall = NA_real_,
          f1_macro = NA_real_,
          f1_weighted = NA_real_,
          auc = soft_auc_value,
          n_dredging = NA_integer_,
          n_transit = NA_integer_,
          tp = NA_integer_,
          fp = NA_integer_,
          fn = NA_integer_,
          tn = NA_integer_
        )
      ), fill = TRUE)
    }
  } else {
    cat("pROC not available - skipping soft AUC from drag_score.\n")
  }
}

cat("\n=== Benchmarking Results ===\n")
print(results[, .(method, precision, recall, f1_macro, auc, n_dredging)])
cat("Oracle step3-vs-step3 metrics are intentionally omitted from the CSV because they are trivially perfect.\n")

dir.create(output_root, showWarnings = FALSE, recursive = TRUE)
results_csv <- file.path(output_root, "benchmarking_results.csv")
fwrite(results, results_csv)
cat("Saved:", results_csv, "\n")

speed_label <- sprintf("Speed threshold baseline (< %.1f kn)", DREDGING_SPEED_THRESHOLD_KN)
gfw_label <- if (has_heading_change) {
  sprintf("GFW-style baseline (< %.1f kn, |heading| < %.0f deg)",
          DREDGING_SPEED_THRESHOLD_KN, GFW_HEADING_CHANGE_MAX_DEG)
} else {
  sprintf("GFW-style baseline (speed-only fallback < %.1f kn)",
          DREDGING_SPEED_THRESHOLD_KN)
}

plot_dt <- melt(
  results[method %in% c(speed_method, gfw_method), .(method, precision, recall, f1_macro, auc)],
  id.vars = "method",
  variable.name = "metric",
  value.name = "value"
)
plot_dt[, metric := factor(metric, levels = c("precision", "recall", "f1_macro", "auc"))]
plot_dt[, method_label := fifelse(method == speed_method, speed_label, gfw_label)]

p <- ggplot(plot_dt, aes(x = metric, y = value, fill = method_label)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  scale_fill_manual(
    values = setNames(c("#2166ac", "#d6604d"), c(speed_label, gfw_label))
  ) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    title = "Dredging Classifier Benchmarking",
    subtitle = sprintf("Naive baselines vs step3 reference | n = %d pings", nrow(ais)),
    x = "Metric",
    y = "Score",
    fill = "Baseline",
    caption = "Soft AUC from drag_score, when available, is reported separately in the CSV and console."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

plot_path <- file.path(output_root, "benchmarking_comparison.png")
ggsave(plot_path, p, width = 8, height = 5, dpi = 150)
cat("Saved:", plot_path, "\n")
