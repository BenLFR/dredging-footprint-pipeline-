#!/usr/bin/env Rscript
# ============================================================================
# diagnose_sobol_convergence.R
# Re-runs the synthetic Sobol proxy at several sample sizes and checks whether
# parameter rankings and total-effect magnitudes stabilize.
#
# Outputs:
#   output_V6/diagnostics/sobol_convergence_long.csv
#   output_V6/diagnostics/sobol_convergence_summary.csv
#   output_V6/diagnostics/sobol_convergence_overall.csv
#   output_V6/diagnostics/sobol_convergence_plot.png
#
# Usage:
#   Rscript analysis/diagnose_sobol_convergence.R
#   Rscript analysis/diagnose_sobol_convergence.R 250,500,1000
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

if (!requireNamespace("sensitivity", quietly = TRUE)) {
  stop("Package 'sensitivity' is required. Install it before running this script.")
}
library(sensitivity)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1) {
  n_values <- sort(unique(as.integer(strsplit(args[1], ",")[[1]])))
} else {
  n_values <- c(250L, 500L, 1000L)
}
if (length(n_values) == 0L || any(is.na(n_values)) || any(n_values < 64L)) {
  stop("Provide Sobol sample sizes as integers >= 64, for example: 250,500,1000")
}

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")
config_root <- get_env_path("CONFIG_DIR", if (dir.exists("configuration")) "configuration" else "config")
config_dirs <- unique(c(config_root, "configuration", "config"))

load_fi_defaults <- function() {
  yaml_candidates <- unique(c(
    file.path(config_dirs, "fi_parameters_with_freshness.yaml")
  ))
  yaml_path <- yaml_candidates[file.exists(yaml_candidates)][1]

  defaults <- list(
    alpha_dep = 0.25,
    fast_fraction = 0.30,
    slow_k = 0.05,
    preservation_factor = 0.87,
    k_fast_multiplier = 1.00,
    k_fast = c(
      North_Pacific = 1.67,
      South_Pacific = 3.84,
      Atlantic = 1.00,
      Indian = 4.76,
      Mediterranean = 12.3,
      Arctic = 0.275,
      Gulf_Mexico_Caribbean = 16.8
    ),
    source = NA_character_
  )

  if (is.na(yaml_path)) {
    return(defaults)
  }

  params_raw <- yaml::read_yaml(yaml_path)
  if (!is.null(params_raw$scenarios$default)) {
    par <- params_raw$scenarios$default
  } else if (!is.null(params_raw$default)) {
    par <- params_raw$default
  } else {
    par <- params_raw
  }

  defaults$source <- yaml_path
  for (nm in c("alpha_dep", "fast_fraction", "slow_k", "preservation_factor", "k_fast_multiplier")) {
    if (!is.null(par[[nm]])) {
      defaults[[nm]] <- as.numeric(par[[nm]])
    }
  }
  if (!is.null(par$k_fast) && length(par$k_fast) > 0) {
    defaults$k_fast <- suppressWarnings(as.numeric(unlist(par$k_fast)))
    names(defaults$k_fast) <- names(par$k_fast)
  }

  defaults
}

fi_defaults <- load_fi_defaults()
param_names <- c("alpha_dep", "fast_fraction", "slow_k", "preservation_factor", "k_fast_multiplier")
param_min <- lapply(fi_defaults[param_names], function(v) v * 0.50)
param_max <- lapply(fi_defaults[param_names], function(v) v * 1.50)
param_min$fast_fraction <- max(param_min$fast_fraction, 0.05)
param_max$fast_fraction <- min(param_max$fast_fraction, 0.95)
param_min$slow_k <- max(param_min$slow_k, 0.001)
param_min$preservation_factor <- max(param_min$preservation_factor, 0.10)
param_max$preservation_factor <- min(param_max$preservation_factor, 1.00)
param_min$k_fast_multiplier <- max(param_min$k_fast_multiplier, 0.05)

set.seed(99)
n_cells <- 25L
SVR_vals <- runif(n_cells, 0, 0.10)
pl_vals <- runif(n_cells, 0.20, 0.80)
k_fast_by_province <- fi_defaults$k_fast
nboot <- 200L

fi_model <- function(X) {
  apply(X, 1, function(pars) {
    alpha_dep_v <- pars[1]
    fast_frac_v <- pars[2]
    slow_k_v <- pars[3]
    preserv_v <- pars[4]
    k_mult_v <- pars[5]

    k_mean_v <- mean(k_fast_by_province * k_mult_v)
    w1 <- 0.05
    w2 <- 0.05
    pl_eff <- w1 * pl_vals + w2 * pl_vals * alpha_dep_v

    f_i_vals <- SVR_vals * pl_eff * preserv_v *
      (fast_frac_v * (1 - exp(-k_mean_v)) +
         (1 - fast_frac_v) * (1 - exp(-slow_k_v)))

    sum(f_i_vals, na.rm = TRUE)
  })
}

run_one_sobol <- function(N) {
  set.seed(2024 + N)
  X1 <- as.data.frame(
    mapply(function(lo, hi) runif(N, lo, hi), lo = unlist(param_min), hi = unlist(param_max))
  )
  X2 <- as.data.frame(
    mapply(function(lo, hi) runif(N, lo, hi), lo = unlist(param_min), hi = unlist(param_max))
  )
  names(X1) <- param_names
  names(X2) <- param_names

  cat(sprintf("Running Sobol convergence diagnostic for N=%d\n", N))
  sa <- sobolSalt(
    model = fi_model,
    X1 = X1,
    X2 = X2,
    scheme = "A",
    conf = 0.95,
    nboot = nboot
  )

  S1 <- sa$S[, c("original", "min. c.i.", "max. c.i.")]
  ST <- sa$T[, c("original", "min. c.i.", "max. c.i.")]
  rownames(S1) <- param_names
  rownames(ST) <- param_names

  dt <- data.table(
    N = N,
    parameter = param_names,
    S1 = S1[, "original"],
    S1_lower = S1[, "min. c.i."],
    S1_upper = S1[, "max. c.i."],
    ST = ST[, "original"],
    ST_lower = ST[, "min. c.i."],
    ST_upper = ST[, "max. c.i."]
  )
  dt[, rank_ST := frank(-ST, ties.method = "min")]
  dt[, rank_S1 := frank(-S1, ties.method = "min")]
  dt[]
}

t0 <- proc.time()[["elapsed"]]
cat("=== Sobol convergence diagnostic ===\n")
cat(sprintf("N values: %s\n", paste(n_values, collapse = ", ")))
if (!is.na(fi_defaults$source)) {
  cat(sprintf("Parameter YAML: %s\n", fi_defaults$source))
} else {
  cat("Parameter YAML not found; using default fi parameter values.\n")
}
cat("Known limitation: fresh_fact is not represented in this synthetic Sobol proxy.\n")

sobol_long <- rbindlist(lapply(n_values, run_one_sobol))
setorder(sobol_long, N, rank_ST, parameter)

summary_dt <- data.table()
overall_dt <- data.table(
  n_values = paste(n_values, collapse = ","),
  nboot = nboot,
  convergence_flag = if (length(n_values) >= 2L) "WARN" else "INSUFFICIENT_LEVELS",
  ranking_identical = NA,
  spearman_ST = NA_real_,
  max_abs_delta_ST = NA_real_
)

if (length(n_values) >= 2L) {
  prev_n <- n_values[length(n_values) - 1L]
  last_n <- n_values[length(n_values)]
  prev_dt <- sobol_long[N == prev_n][match(param_names, parameter)]
  last_dt <- sobol_long[N == last_n][match(param_names, parameter)]

  summary_dt <- data.table(
    parameter = param_names,
    N_previous = prev_n,
    N_current = last_n,
    ST_previous = prev_dt$ST,
    ST_current = last_dt$ST,
    delta_ST = last_dt$ST - prev_dt$ST,
    S1_previous = prev_dt$S1,
    S1_current = last_dt$S1,
    delta_S1 = last_dt$S1 - prev_dt$S1,
    rank_ST_previous = prev_dt$rank_ST,
    rank_ST_current = last_dt$rank_ST
  )

  ranking_identical <- identical(prev_dt$parameter[order(prev_dt$rank_ST)], last_dt$parameter[order(last_dt$rank_ST)])
  spearman_st <- suppressWarnings(cor(prev_dt$ST, last_dt$ST, method = "spearman"))
  max_abs_delta_st <- max(abs(summary_dt$delta_ST), na.rm = TRUE)

  overall_dt <- data.table(
    n_values = paste(n_values, collapse = ","),
    nboot = nboot,
    convergence_flag = if (isTRUE(spearman_st >= 0.9) && max_abs_delta_st <= 0.05) "PASS" else "WARN",
    ranking_identical = ranking_identical,
    spearman_ST = spearman_st,
    max_abs_delta_ST = max_abs_delta_st
  )
}

out_dir <- file.path(output_root, "diagnostics")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

long_csv <- file.path(out_dir, "sobol_convergence_long.csv")
summary_csv <- file.path(out_dir, "sobol_convergence_summary.csv")
overall_csv <- file.path(out_dir, "sobol_convergence_overall.csv")
fwrite(sobol_long, long_csv)
fwrite(summary_dt, summary_csv)
fwrite(overall_dt, overall_csv)

cat(sprintf("Saved: %s\n", long_csv))
cat(sprintf("Saved: %s\n", summary_csv))
cat(sprintf("Saved: %s\n", overall_csv))
print(overall_dt)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  p <- ggplot(sobol_long, aes(x = N, y = ST, color = parameter)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    labs(
      title = "Sobol convergence diagnostic",
      subtitle = "Total-effect indices across increasing sample sizes",
      x = "Sobol sample size N",
      y = "ST (total-effect index)",
      color = "Parameter"
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())

  plot_path <- file.path(out_dir, "sobol_convergence_plot.png")
  ggsave(plot_path, p, width = 8, height = 5, dpi = 300)
  cat(sprintf("Saved: %s\n", plot_path))
} else {
  cat("ggplot2 not available; skipping Sobol convergence plot.\n")
}

runtime_sec <- proc.time()[["elapsed"]] - t0
cat(sprintf("Done in %.1f seconds.\n", runtime_sec))
