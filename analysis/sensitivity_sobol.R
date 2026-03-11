#!/usr/bin/env Rscript
# ============================================================================
# sensitivity_sobol.R
# Global sensitivity analysis using Sobol indices for the fi / C_ri formula.
# Uses a local 25-cell synthetic test-patch proxy for C_ri, not the global grid.
#
# Outputs:
#   output_V6/sensitivity/sobol_indices.csv
#   output_V6/sensitivity/sobol_plot.png
#
# Usage:
#   Rscript analysis/sensitivity_sobol.R
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

if (!requireNamespace("sensitivity", quietly = TRUE)) {
  stop(paste(
    "Package 'sensitivity' is required.",
    "Install with: install.packages('sensitivity')",
    "On cluster: Rscript -e \"install.packages('sensitivity', lib='~/R/library')\""
  ))
}
library(sensitivity)

t0 <- proc.time()[["elapsed"]]
cat("=== Sobol Global Sensitivity Analysis ===\n")
cat(sprintf("Date: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("NOTE: This uses a local 25-cell synthetic proxy, not the global fi_grid.\n")

# fi parameters and default values
fi_defaults <- list(
  alpha_dep = 0.25,
  fast_fraction = 0.30,
  slow_k = 0.05,
  preservation_factor = 0.87,
  k_fast_multiplier = 1.00
)

# +/-50% parameter range
param_min <- lapply(fi_defaults, function(v) v * 0.50)
param_max <- lapply(fi_defaults, function(v) v * 1.50)

param_min$fast_fraction <- max(param_min$fast_fraction, 0.05)
param_max$fast_fraction <- min(param_max$fast_fraction, 0.95)
param_min$slow_k <- max(param_min$slow_k, 0.001)
param_min$preservation_factor <- max(param_min$preservation_factor, 0.10)
param_max$preservation_factor <- min(param_max$preservation_factor, 1.00)
param_min$k_fast_multiplier <- max(param_min$k_fast_multiplier, 0.05)

param_names <- names(fi_defaults)
cat(sprintf("\nParameters analysed: %s\n", paste(param_names, collapse = ", ")))

# Local test-patch proxy inputs.
set.seed(99)
n_cells <- 25L
SVR_vals <- runif(n_cells, 0, 0.10)
pl_vals <- runif(n_cells, 0.20, 0.80)

# Mean k_fast across ocean provinces.
k_fast_by_province <- c(
  North_Pacific = 1.67,
  South_Pacific = 3.84,
  Atlantic = 1.00,
  Indian = 4.76,
  Mediterranean = 12.3,
  Arctic = 0.275,
  Gulf_Mexico_Caribbean = 16.8
)

fi_model <- function(X) {
  apply(X, 1, function(pars) {
    alpha_dep_v <- pars[1]
    fast_frac_v <- pars[2]
    slow_k_v <- pars[3]
    preserv_v <- pars[4]
    k_mult_v <- pars[5]

    k_mean_v <- mean(k_fast_by_province * k_mult_v)

    # Depth-weighting: p_d = 1 m (TSHD default in the production worker).
    w1 <- 0.05
    w2 <- 0.05
    pl_eff <- w1 * pl_vals + w2 * pl_vals * alpha_dep_v

    # Known limitation: fresh_fact is not represented on the synthetic patch.
    f_i_vals <- SVR_vals * pl_eff * preserv_v *
      (fast_frac_v * (1 - exp(-k_mean_v)) +
         (1 - fast_frac_v) * (1 - exp(-slow_k_v)))

    sum(f_i_vals, na.rm = TRUE)
  })
}

N <- 1000L
cat(sprintf("\nSample size N = %d -> %d total model evaluations\n", N, N * 2))

set.seed(2024)
X1 <- as.data.frame(
  mapply(function(lo, hi) runif(N, lo, hi),
         lo = unlist(param_min),
         hi = unlist(param_max))
)
X2 <- as.data.frame(
  mapply(function(lo, hi) runif(N, lo, hi),
         lo = unlist(param_min),
         hi = unlist(param_max))
)
names(X1) <- param_names
names(X2) <- param_names

cat("Running Sobol analysis... ")
sa <- sobolSalt(
  model = fi_model,
  X1 = X1,
  X2 = X2,
  scheme = "A",
  conf = 0.95,
  nboot = 200
)
cat("done.\n")

S1 <- sa$S[, c("original", "bias", "std. error", "min. c.i.", "max. c.i.")]
ST <- sa$T[, c("original", "bias", "std. error", "min. c.i.", "max. c.i.")]
rownames(S1) <- param_names
rownames(ST) <- param_names

cat("\n-- First-order Sobol indices (S1) --\n")
print(round(S1, 4))
cat("\n-- Total-effect Sobol indices (ST) --\n")
print(round(ST, 4))

cat("\n-- Interaction interpretation --\n")
for (p in param_names) {
  s1_v <- S1[p, "original"]
  st_v <- ST[p, "original"]
  ratio <- if (!is.na(s1_v) && s1_v > 0.01) st_v / s1_v else NA_real_
  if (!is.na(ratio) && ratio > 1.3) {
    cat(sprintf("  %s: ST/S1 = %.2f -> significant interaction effects\n", p, ratio))
  } else if (!is.na(ratio)) {
    cat(sprintf("  %s: ST/S1 = %.2f -> mostly additive\n", p, ratio))
  }
}

out_dir <- if (dir.exists(file.path(path.expand("~"), "scratch"))) {
  file.path(path.expand("~"), "scratch", "output_V6", "sensitivity")
} else {
  "output_V6/sensitivity"
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

sobol_dt <- data.table(
  parameter = param_names,
  S1 = S1[, "original"],
  S1_lower = S1[, "min. c.i."],
  S1_upper = S1[, "max. c.i."],
  ST = ST[, "original"],
  ST_lower = ST[, "min. c.i."],
  ST_upper = ST[, "max. c.i."],
  ST_S1_ratio = ST[, "original"] / pmax(S1[, "original"], 0.001),
  default_value = unlist(fi_defaults)
)
setorder(sobol_dt, -ST)

sobol_csv <- file.path(out_dir, "sobol_indices.csv")
fwrite(sobol_dt, sobol_csv)
cat(sprintf("\nSaved: %s\n", sobol_csv))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)

  plot_dt <- rbindlist(list(
    sobol_dt[, .(parameter, value = S1, ci_lo = S1_lower, ci_hi = S1_upper,
                 index_type = "S1 (first-order)")],
    sobol_dt[, .(parameter, value = ST, ci_lo = ST_lower, ci_hi = ST_upper,
                 index_type = "ST (total-effect)")]
  ))
  plot_dt[, parameter := factor(parameter, levels = rev(sobol_dt$parameter))]

  p <- ggplot(plot_dt, aes(x = parameter, y = value, fill = index_type)) +
    geom_col(position = position_dodge(0.6), width = 0.5) +
    geom_errorbar(
      aes(ymin = ci_lo, ymax = ci_hi),
      position = position_dodge(0.6),
      width = 0.2,
      linewidth = 0.5
    ) +
    geom_hline(yintercept = 0, linewidth = 0.4, color = "grey50") +
    coord_flip() +
    scale_fill_manual(
      values = c("S1 (first-order)" = "#4393c3", "ST (total-effect)" = "#d6604d"),
      name = "Sobol index"
    ) +
    labs(
      title = "Sobol Global Sensitivity Analysis - fi Parameters",
      subtitle = sprintf(
        "N=%d samples | +/-50%% parameter range | local 25-cell test patch proxy, not the global grid",
        N
      ),
      x = "Parameter",
      y = "Sobol index value (0-1)",
      caption = paste(
        "S1 = first-order effect; ST = total effect including interactions.",
        "fresh_fact is not represented on this synthetic patch."
      )
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      plot.caption = element_text(size = 7, color = "grey40")
    )

  sobol_png <- file.path(out_dir, "sobol_plot.png")
  ggsave(sobol_png, p, width = 8, height = 5, dpi = 300)
  cat(sprintf("Saved: %s\n", sobol_png))
} else {
  cat("ggplot2 not available - skipping plot.\n")
}

runtime <- proc.time()[["elapsed"]] - t0
cat(sprintf("\nDone in %.1f seconds.\n", runtime))
cat(sprintf("Total model evaluations: %d\n", N * 2))
