#!/usr/bin/env Rscript
# ============================================================================
# plot_sensitivity_tornado.R
# Reads output_V6/sensitivity/oat_results.csv and produces a tornado plot
# showing the relative influence of each fi_parameter on global C_ri.
#
# Outputs:
#   output_V6/sensitivity/tornado_plot.png  — 300 dpi, 8×5 inches
#   output_V6/sensitivity/tornado_data.csv  — data for manuscript tables
#
# Usage:
#   Rscript analysis/plot_sensitivity_tornado.R
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# ── 1. Load OAT results ───────────────────────────────────────────────────────
# Search scratch first (cluster ~/scratch), then local output_V6/
sens_dirs <- c(
  file.path(path.expand("~"), "scratch", "output_V6", "sensitivity"),
  "output_V6/sensitivity"
)
sens_dir <- sens_dirs[dir.exists(sens_dirs)][1]
if (is.na(sens_dir)) {
  stop("Sensitivity output directory not found (expected ~/scratch/output_V6/sensitivity or output_V6/sensitivity).")
}

oat_path <- file.path(sens_dir, "oat_results.csv")
task_files <- list.files(sens_dir, pattern = "^oat_task_[0-9]+\\.csv$", full.names = TRUE)

if (!file.exists(oat_path) && length(task_files) == 0) {
  stop(paste(
    "No OAT results found.",
    "Expected oat_results.csv or oat_task_*.csv in:", sens_dir,
    "Run sensitivity_oat_analysis.R via SLURM array first."
  ))
}

oat_parts <- list()
if (file.exists(oat_path)) {
  oat_parts[[length(oat_parts) + 1]] <- fread(oat_path)
}
if (length(task_files) > 0) {
  oat_parts[[length(oat_parts) + 1]] <- rbindlist(lapply(task_files, fread), fill = TRUE)
}

oat <- rbindlist(oat_parts, fill = TRUE)
setorder(oat, task_id)
oat <- oat[!duplicated(task_id, fromLast = TRUE)]
fwrite(oat, oat_path)
cat(sprintf("Loaded %d rows (deduplicated) from %s\n", nrow(oat), sens_dir))

# ── 2. Identify baseline rows (value_label ends in _base) ─────────────────────
oat[, is_baseline := grepl("_base$", value_label)]

baselines <- oat[is_baseline == TRUE, .(parameter_name, C_ri_base = global_C_ri_sum)]
cat("Baselines:\n"); print(baselines)

if (nrow(baselines) == 0) {
  stop("No baseline rows found (value_label ending in '_base'). Check manifest.")
}

# ── 3. Merge baseline C_ri into all rows ─────────────────────────────────────
oat <- merge(oat, baselines, by = "parameter_name", all.x = TRUE)

# ── 4. Compute relative output range per parameter ───────────────────────────
# For each parameter: range = (max C_ri - min C_ri) / baseline C_ri × 100
# Also track the direction of the +50% perturbation (up or down?)
ranges_dt <- oat[, {
  valid <- global_C_ri_sum[!is.na(global_C_ri_sum)]
  base  <- C_ri_base[1]
  if (length(valid) == 0 || is.na(base) || base == 0) {
    list(output_range_pct = NA_real_,
         pct_at_p50 = NA_real_,
         pct_at_m50 = NA_real_,
         n_runs = .N)
  } else {
    p50_row <- .SD[value_label == paste0(parameter_name[1], "_p50") |
                   grepl("p50$", value_label)]
    m50_row <- .SD[value_label == paste0(parameter_name[1], "_m50") |
                   grepl("m50$", value_label)]
    pct_p50 <- if (nrow(p50_row) > 0 && !is.na(p50_row$global_C_ri_sum[1]))
                 (p50_row$global_C_ri_sum[1] - base) / base * 100 else NA_real_
    pct_m50 <- if (nrow(m50_row) > 0 && !is.na(m50_row$global_C_ri_sum[1]))
                 (m50_row$global_C_ri_sum[1] - base) / base * 100 else NA_real_
    list(
      output_range_pct = (max(valid) - min(valid)) / base * 100,
      pct_at_p50       = pct_p50,
      pct_at_m50       = pct_m50,
      n_runs           = .N
    )
  }
}, by = parameter_name]

setorder(ranges_dt, -output_range_pct)
cat("\nSensitivity ranking (% output range):\n")
print(ranges_dt[, .(parameter_name, output_range_pct, pct_at_p50, pct_at_m50, n_runs)])

# ── 5. Build tornado plot data ────────────────────────────────────────────────
# Long format: one row per perturbation direction per parameter
tornado_dt <- ranges_dt[!is.na(output_range_pct)]

# Reorder factor by output range (largest at top)
tornado_dt[, param_label := factor(parameter_name,
             levels = rev(tornado_dt$parameter_name))]

# Long format for +50% and -50% bars
plot_dt <- rbindlist(list(
  tornado_dt[, .(param_label, pct = pct_at_p50, direction = "+50%")],
  tornado_dt[, .(param_label, pct = pct_at_m50, direction = "-50%")]
))
plot_dt <- plot_dt[!is.na(pct)]

# ── 6. Plot ───────────────────────────────────────────────────────────────────
p <- ggplot(plot_dt, aes(x = pct, y = param_label, fill = direction)) +
  geom_col(orientation = "y", position = position_dodge(0.6), width = 0.5) +
  geom_vline(xintercept = 0, linewidth = 0.8, color = "grey30") +
  scale_fill_manual(
    values = c("+50%" = "#d6604d", "-50%" = "#4393c3"),
    name   = "Perturbation"
  ) +
  scale_x_continuous(labels = function(x) paste0(ifelse(x > 0, "+", ""), round(x, 1), "%")) +
  labs(
    title    = "OAT Sensitivity: Parameter Influence on Global C_ri",
    subtitle = paste("Parameters from fi_parameters_with_freshness.yaml | +/-50% perturbation from defaults",
                     sprintf("| %d task IDs completed", nrow(oat))),
    x        = "% change in global C_ri from baseline",
    y        = "Parameter",
    caption  = paste(
      "Defaults: alpha_dep=0.25, fast_fraction=0.30, slow_k=0.05,",
      "preservation_factor=0.87, k_fast_multiplier=1.0"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position  = "bottom",
    panel.grid.minor = element_blank()
  )

out_dir <- if (dir.exists(file.path(path.expand("~"), "scratch"))) {
  file.path(path.expand("~"), "scratch", "output_V6", "sensitivity")
} else {
  "output_V6/sensitivity"
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

tornado_png <- file.path(out_dir, "tornado_plot.png")
ggsave(tornado_png, p, width = 8, height = 5, dpi = 300)
cat("Saved:", tornado_png, "\n")

# ── 7. Save tornado data CSV ──────────────────────────────────────────────────
tornado_csv <- file.path(out_dir, "tornado_data.csv")
fwrite(ranges_dt, tornado_csv)
cat("Saved:", tornado_csv, "\n")

cat("\nDone.\n")
