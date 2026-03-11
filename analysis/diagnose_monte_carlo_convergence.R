#!/usr/bin/env Rscript
# ============================================================================
# diagnose_monte_carlo_convergence.R
# Assesses whether Monte Carlo C_ri summaries stabilize across iterations.
#
# Outputs:
#   output_V6/diagnostics/mc_iteration_summary.csv
#   output_V6/diagnostics/mc_convergence_summary.csv
#   output_V6/diagnostics/mc_convergence_plot.png
#
# Usage:
#   Rscript analysis/diagnose_monte_carlo_convergence.R
#   Rscript analysis/diagnose_monte_carlo_convergence.R 50
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
window_n <- if (length(args) >= 1) as.integer(args[1]) else 50L
if (is.na(window_n) || window_n < 5L) {
  stop("window_n must be an integer >= 5.")
}

read_table_auto <- function(path) {
  if (grepl("\\.parquet$", path, ignore.case = TRUE)) {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Package 'arrow' is required to read parquet files.")
    }
    return(setDT(arrow::read_parquet(path)))
  }
  setDT(readRDS(path))
}

load_mc_table <- function() {
  search_dirs <- c(
    file.path("output_V6", "uncertainty"),
    file.path(path.expand("~"), "scratch", "output_V6", "uncertainty")
  )

  batch_files <- character(0)
  for (root in search_dirs) {
    if (!dir.exists(root)) {
      next
    }
    batch_files <- c(
      batch_files,
      list.files(root, pattern = "^mc_batch_.*\\.(parquet|rds)$", full.names = TRUE)
    )
  }

  if (length(batch_files) > 0L) {
    batch_files <- batch_files[order(batch_files)]
    dt_list <- lapply(batch_files, read_table_auto)
    return(list(source = "mc_batch", paths = batch_files, data = rbindlist(dt_list, fill = TRUE)))
  }

  summary_files <- character(0)
  for (root in search_dirs) {
    if (!dir.exists(root)) {
      next
    }
    summary_files <- c(
      summary_files,
      list.files(root, pattern = "^mc_results_summary\\.(parquet|rds)$", full.names = TRUE)
    )
  }

  if (length(summary_files) == 0L) {
    stop("No mc_batch_* or mc_results_summary files found in output_V6/uncertainty.")
  }

  summary_files <- summary_files[order(file.info(summary_files)$mtime, decreasing = TRUE)]
  list(source = "mc_summary", paths = summary_files[1], data = read_table_auto(summary_files[1]))
}

summarise_iterations <- function(mc_dt) {
  if (!("iteration" %in% names(mc_dt))) {
    stop("Monte Carlo input does not contain an iteration column.")
  }

  c_ri_candidates <- c("C_ri_value", "C_ri", "c_ri_value")
  value_col <- c_ri_candidates[c_ri_candidates %in% names(mc_dt)][1]
  fi_candidates <- c("fi_value", "f_i_full", "fi_mc")
  fi_col <- fi_candidates[fi_candidates %in% names(mc_dt)][1]
  sum_candidates <- c("c_ri_sum", "C_ri_sum")
  sum_col <- sum_candidates[sum_candidates %in% names(mc_dt)][1]

  if (!is.na(sum_col)) {
    keep_cols <- c("iteration", sum_col)
    if (!is.na(fi_col)) {
      keep_cols <- c(keep_cols, fi_col)
    }
    if ("n_cells" %in% names(mc_dt)) {
      keep_cols <- c(keep_cols, "n_cells")
    }
    out <- unique(mc_dt[, ..keep_cols])
    setnames(out, old = sum_col, new = "c_ri_sum")
    if (!is.na(fi_col) && fi_col %in% names(out)) {
      setnames(out, old = fi_col, new = "fi_sum")
    }
    if (!("n_cells" %in% names(out))) {
      out[, n_cells := NA_integer_]
    }
    return(out[order(iteration)])
  }

  if (is.na(value_col)) {
    stop("Could not identify a Monte Carlo C_ri column.")
  }

  mc_dt[
    ,
    .(
      c_ri_sum = sum(get(value_col), na.rm = TRUE),
      fi_sum = if (!is.na(fi_col)) sum(get(fi_col), na.rm = TRUE) else NA_real_,
      n_cells = if ("grid_id" %in% names(mc_dt)) uniqueN(grid_id) else .N
    ),
    by = iteration
  ][order(iteration)]
}

t0 <- proc.time()[["elapsed"]]
cat("=== Monte Carlo convergence diagnostic ===\n")

mc_obj <- load_mc_table()
iter_dt <- summarise_iterations(mc_obj$data)

if (nrow(iter_dt) < 2L) {
  stop("Need at least two Monte Carlo iterations to assess convergence.")
}

iter_dt[, cum_mean := cumsum(c_ri_sum) / seq_len(.N)]
iter_dt[, cum_sd := vapply(seq_len(.N), function(i) if (i < 2L) NA_real_ else sd(c_ri_sum[seq_len(i)]), numeric(1))]
iter_dt[, cum_q05 := vapply(seq_len(.N), function(i) as.numeric(quantile(c_ri_sum[seq_len(i)], 0.05, na.rm = TRUE)), numeric(1))]
iter_dt[, cum_q95 := vapply(seq_len(.N), function(i) as.numeric(quantile(c_ri_sum[seq_len(i)], 0.95, na.rm = TRUE)), numeric(1))]

status <- "INSUFFICIENT_ITERATIONS"
mean_shift_pct <- NA_real_
q05_shift_pct <- NA_real_
q95_shift_pct <- NA_real_

if (nrow(iter_dt) >= 2L * window_n) {
  recent <- tail(iter_dt, window_n)
  previous <- tail(iter_dt, 2L * window_n)[seq_len(window_n)]

  pct_shift <- function(a, b) 100 * abs(a - b) / max(abs(b), 1e-12)
  mean_shift_pct <- pct_shift(mean(recent$c_ri_sum), mean(previous$c_ri_sum))
  q05_shift_pct <- pct_shift(
    as.numeric(quantile(recent$c_ri_sum, 0.05, na.rm = TRUE)),
    as.numeric(quantile(previous$c_ri_sum, 0.05, na.rm = TRUE))
  )
  q95_shift_pct <- pct_shift(
    as.numeric(quantile(recent$c_ri_sum, 0.95, na.rm = TRUE)),
    as.numeric(quantile(previous$c_ri_sum, 0.95, na.rm = TRUE))
  )

  status <- if (mean_shift_pct <= 5 && q05_shift_pct <= 10 && q95_shift_pct <= 10) {
    "PASS"
  } else {
    "WARN"
  }
}

summary_dt <- data.table(
  source_type = mc_obj$source,
  source_path = paste(mc_obj$paths, collapse = " | "),
  n_iterations = nrow(iter_dt),
  window_n = window_n,
  final_cum_mean = tail(iter_dt$cum_mean, 1),
  final_cum_sd = tail(iter_dt$cum_sd, 1),
  final_cum_q05 = tail(iter_dt$cum_q05, 1),
  final_cum_q95 = tail(iter_dt$cum_q95, 1),
  mean_shift_pct = mean_shift_pct,
  q05_shift_pct = q05_shift_pct,
  q95_shift_pct = q95_shift_pct,
  convergence_flag = status
)

out_dir <- "output_V6/diagnostics"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

iter_csv <- file.path(out_dir, "mc_iteration_summary.csv")
summary_csv <- file.path(out_dir, "mc_convergence_summary.csv")
fwrite(iter_dt, iter_csv)
fwrite(summary_dt, summary_csv)

cat(sprintf("Saved: %s\n", iter_csv))
cat(sprintf("Saved: %s\n", summary_csv))
print(summary_dt)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  p <- ggplot(iter_dt, aes(x = iteration, y = cum_mean)) +
    geom_line(color = "#2c7fb8", linewidth = 0.7) +
    geom_ribbon(aes(ymin = cum_q05, ymax = cum_q95), fill = "#a6bddb", alpha = 0.35) +
    labs(
      title = "Monte Carlo convergence diagnostic",
      subtitle = sprintf("Cumulative mean and 5-95%% band | %d iterations", nrow(iter_dt)),
      x = "Iteration",
      y = "Cumulative C_ri summary"
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())

  plot_path <- file.path(out_dir, "mc_convergence_plot.png")
  ggsave(plot_path, p, width = 8, height = 5, dpi = 300)
  cat(sprintf("Saved: %s\n", plot_path))
} else {
  cat("ggplot2 not available; skipping MC convergence plot.\n")
}

runtime_sec <- proc.time()[["elapsed"]] - t0
cat(sprintf("Done in %.1f seconds.\n", runtime_sec))
