#!/usr/bin/env Rscript
# ============================================================================
# plot_sensitivity_tornado.R
# Reads output_V6/sensitivity/oat_results.csv and produces a tornado plot
# showing the relative influence of each fi parameter on C_ri.
#
# Outputs:
#   output_V6/sensitivity/tornado_plot.png
#   output_V6/sensitivity/tornado_data.csv
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")
sens_dirs <- unique(c(
  file.path(output_root, "sensitivity"),
  file.path("output_V6", "sensitivity")
))
sens_dir <- sens_dirs[dir.exists(sens_dirs)][1]
if (is.na(sens_dir)) {
  stop("Sensitivity output directory not found.")
}

oat_path <- file.path(sens_dir, "oat_results.csv")
task_files <- list.files(sens_dir, pattern = "^oat_task_[0-9]+\\.csv$", full.names = TRUE)
if (!file.exists(oat_path) && length(task_files) == 0) {
  stop("No OAT results found. Run sensitivity_oat_analysis.R first.")
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

has_global_col <- "global_C_ri_sum" %in% names(oat)
has_patch_col <- "test_patch_C_ri_sum" %in% names(oat)
if (!has_global_col && !has_patch_col) {
  stop("No C_ri result column found in OAT CSV. Tried global_C_ri_sum and test_patch_C_ri_sum.")
}

if (!("result_scope" %in% names(oat))) {
  oat[, result_scope := NA_character_]
}

if (has_global_col && has_patch_col) {
  oat[, c_ri_value := fcoalesce(global_C_ri_sum, test_patch_C_ri_sum)]
  oat[is.na(result_scope) & !is.na(global_C_ri_sum), result_scope := "global_fi_grid"]
  oat[is.na(result_scope) & !is.na(test_patch_C_ri_sum), result_scope := "synthetic_test_patch"]
} else if (has_patch_col) {
  oat[, c_ri_value := test_patch_C_ri_sum]
  oat[is.na(result_scope), result_scope := "synthetic_test_patch"]
} else {
  oat[, c_ri_value := global_C_ri_sum]
  # Legacy CSVs used global_C_ri_sum for the test patch. Assume that scope unless
  # a newer result_scope column says otherwise.
  oat[is.na(result_scope), result_scope := "legacy_test_patch_proxy"]
}

oat[, is_baseline := grepl("_base$", value_label)]
baselines <- oat[is_baseline == TRUE, .(parameter_name, C_ri_base = c_ri_value)]
cat("Baselines:\n")
print(baselines)

if (nrow(baselines) == 0) {
  stop("No baseline rows found (value_label ending in '_base').")
}

oat <- merge(oat, baselines, by = "parameter_name", all.x = TRUE)

ranges_dt <- oat[, {
  valid <- c_ri_value[!is.na(c_ri_value)]
  base <- C_ri_base[1]
  if (length(valid) == 0 || is.na(base) || base == 0) {
    list(
      output_range_pct = NA_real_,
      pct_at_p50 = NA_real_,
      pct_at_m50 = NA_real_,
      n_runs = .N
    )
  } else {
    p50_row <- .SD[value_label == paste0(parameter_name[1], "_p50") | grepl("p50$", value_label)]
    m50_row <- .SD[value_label == paste0(parameter_name[1], "_m50") | grepl("m50$", value_label)]
    pct_p50 <- if (nrow(p50_row) > 0 && !is.na(p50_row$c_ri_value[1])) {
      (p50_row$c_ri_value[1] - base) / base * 100
    } else {
      NA_real_
    }
    pct_m50 <- if (nrow(m50_row) > 0 && !is.na(m50_row$c_ri_value[1])) {
      (m50_row$c_ri_value[1] - base) / base * 100
    } else {
      NA_real_
    }
    list(
      output_range_pct = (max(valid) - min(valid)) / base * 100,
      pct_at_p50 = pct_p50,
      pct_at_m50 = pct_m50,
      n_runs = .N
    )
  }
}, by = parameter_name]

setorder(ranges_dt, -output_range_pct)
cat("\nSensitivity ranking (% output range):\n")
print(ranges_dt[, .(parameter_name, output_range_pct, pct_at_p50, pct_at_m50, n_runs)])

tornado_dt <- ranges_dt[!is.na(output_range_pct)]
tornado_dt[, param_label := factor(parameter_name, levels = rev(tornado_dt$parameter_name))]

plot_dt <- rbindlist(list(
  tornado_dt[, .(param_label, pct = pct_at_p50, direction = "+50%")],
  tornado_dt[, .(param_label, pct = pct_at_m50, direction = "-50%")]
))
plot_dt <- plot_dt[!is.na(pct)]

scope_values <- unique(oat$result_scope[!is.na(oat$c_ri_value)])
scope_note <- if (length(scope_values) == 1 && scope_values %in% c("synthetic_test_patch", "legacy_test_patch_proxy")) {
  "NOTE: C_ri computed on an Indian Ocean test patch, not the global grid"
} else if (length(scope_values) == 1 && scope_values == "global_fi_grid") {
  "Scope: full fi_grid recalculation"
} else {
  "Scope: mixed or legacy OAT rows; rerun all tasks for a fully consistent figure"
}

p <- ggplot(plot_dt, aes(x = pct, y = param_label, fill = direction)) +
  geom_col(orientation = "y", position = position_dodge(0.6), width = 0.5) +
  geom_vline(xintercept = 0, linewidth = 0.8, color = "grey30") +
  scale_fill_manual(
    values = c("+50%" = "#d6604d", "-50%" = "#4393c3"),
    name = "Perturbation"
  ) +
  scale_x_continuous(labels = function(x) paste0(ifelse(x > 0, "+", ""), round(x, 1), "%")) +
  labs(
    title = "OAT Sensitivity: Parameter Influence on C_ri",
    subtitle = paste(
      "Parameters from fi parameter defaults | +/-50% perturbation from baseline",
      sprintf("| %d task IDs completed", nrow(oat)),
      "|",
      scope_note
    ),
    x = "% change in C_ri from baseline",
    y = "Parameter",
    caption = paste(
      "Defaults: alpha_dep=0.25, fast_fraction=0.30, slow_k=0.05,",
      "preservation_factor=0.87, k_fast_multiplier=1.0"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

out_dir <- file.path(output_root, "sensitivity")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

tornado_png <- file.path(out_dir, "tornado_plot.png")
ggsave(tornado_png, p, width = 8, height = 5, dpi = 300)
cat("Saved:", tornado_png, "\n")

tornado_csv <- file.path(out_dir, "tornado_data.csv")
fwrite(ranges_dt, tornado_csv)
cat("Saved:", tornado_csv, "\n")

cat("\nDone.\n")
