#!/usr/bin/env Rscript
# ============================================================================
# sensitivity_sobol_realgrid.R
# Global Sensitivity Analysis (Sobol' indices) for the fi / C_ri formulation,
# evaluated on the REAL model grid instead of a synthetic patch.
#
# Written 2026-07-28. Companion to scripts_principaux/sensitivity_sobol.R,
# which it is intended to replace. The original is left untouched.
#
# WHY THIS SCRIPT EXISTS -----------------------------------------------------
# Three defects were found in sensitivity_sobol.R on 2026-07-28.
#
#  (1) alpha_dep was DEAD. `alpha_dep_v <- pars[1]` was extracted and never
#      used in fi_model(). Its Sobol index was therefore zero by construction,
#      not by result. Cause: the proxy used raw p_l, whereas alpha_dep acts on
#      p_l_eff (step5_merge_tiles_optimized.R:214).
#
#  (2) k was collapsed to an UNWEIGHTED MEAN over seven provinces
#      (Gulf of Mexico 16.8 included), replacing the per-cell k_fast. Because k
#      enters through exp(-k), this is the one substitution that genuinely
#      distorts the indices: unlike SVR and p_l, cell-to-cell variation in k
#      does not factor out of the sum.
#
#  (3) The header CAVEAT claimed the proxy was "a 3x3 test region:
#      10-12.5N, 60-62.5E". No geography is loaded anywhere in that script.
#      The comment is simply false and should be removed from the repository.
#
# WHAT WAS *NOT* A DEFECT ----------------------------------------------------
# Using synthetic SVR and p_l did not, on its own, bias the indices. In that
# formulation every cell contributes SVR*p_l multiplied by one and the same
# function of the parameters, so the sum is (constant) x f(params). Sobol
# indices are RELATIVE variance shares and are invariant under that constant.
# The synthetic draws were nonetheless wildly unrepresentative - uniform on
# [0, 0.10] against a real SVR median of 0.0016 and a maximum of 8.3 - which
# matters here only because k now varies per cell, so the weighting of cells
# no longer cancels.
#
# SELF-CHECK -----------------------------------------------------------------
# Before running the analysis, the script rebuilds f_i at default parameters
# and compares it cell by cell with the stored f_i_full column. If the
# reconstruction does not match, it ABORTS rather than produce indices for a
# formula that is not the pipeline's.
#
# USAGE ----------------------------------------------------------------------
#   Rscript --vanilla scripts_principaux/sensitivity_sobol_realgrid.R
#
# OUTPUT ---------------------------------------------------------------------
#   ~/scratch/output_V6/sensitivity/sobol_indices_realgrid.csv
# ============================================================================

# -- 0. User library ----------------------------------------------------------
# GRIT has no ~/.Renviron and no ~/.Rprofile, so R_LIBS_USER is not picked up:
# .libPaths() returns the three system directories only, with or without
# --vanilla. Every package installed for this project lives in ~/R/library and
# is invisible unless the path is added explicitly. The other pipeline scripts
# do this with `export R_LIBS_USER=~/R/library` in their shell wrapper; doing it
# inside the script makes it work however it is launched.
user_lib <- path.expand("~/R/library")
if (dir.exists(user_lib)) .libPaths(unique(c(user_lib, .libPaths())))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})
if (!requireNamespace("sensitivity", quietly = TRUE)) {
  stop("Package 'sensitivity' is required. ",
       "Install with: Rscript -e \"install.packages('sensitivity', lib='~/R/library')\"")
}
library(sensitivity)

t0 <- proc.time()["elapsed"]
cat("=== Sobol' GSA on the real grid ===\n")
cat(sprintf("Date: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

# -- 1. Load the most recent fi_grid ------------------------------------------
grid_dir <- path.expand("~/scratch/output_V6")
cand <- list.files(grid_dir, pattern = "^fi_grid.*\\.parquet$",
                   full.names = TRUE, recursive = TRUE)
if (!length(cand)) stop("No fi_grid*.parquet found under ", grid_dir)
grid_file <- tail(sort(cand), 1)
cat(sprintf("\nGrid file: %s\n", grid_file))

d <- as.data.table(arrow::read_parquet(grid_file))
need <- c("SVR", "p_l", "p_d", "k_fast", "f_i_full")
miss <- setdiff(need, names(d))
if (length(miss)) stop("Missing column(s) in fi_grid: ", paste(miss, collapse = ", "))

has_fresh <- "fresh_fact" %in% names(d)
keep <- c(need, if (has_fresh) "fresh_fact")
d <- d[stats::complete.cases(d[, ..keep])]
cat(sprintf("Cells retained: %d\n", nrow(d)))
if (!nrow(d)) stop("No complete cases in the grid.")

cat(sprintf("Real SVR   : median %.6g   mean %.6g   max %.6g\n",
            median(d$SVR), mean(d$SVR), max(d$SVR)))
cat(sprintf("Real p_l   : median %.6g   range [%.3g, %.3g]\n",
            median(d$p_l), min(d$p_l), max(d$p_l)))
cat(sprintf("Real k_fast: median %.6g   range [%.3g, %.3g]\n",
            median(d$k_fast), min(d$k_fast), max(d$k_fast)))
cat("  (the synthetic patch drew SVR ~ U(0, 0.10), p_l ~ U(0.20, 0.80),",
    "and replaced k_fast by one unweighted province mean)\n")

# -- 2. Parameters and their ranges -------------------------------------------
# Same defaults and the same +/-50% envelope as the original script, so that
# the two runs remain comparable. Nothing here is re-tuned.
fi_defaults <- list(
  alpha_dep           = 0.25,
  fast_fraction       = 0.30,
  slow_k              = 0.05,
  preservation_factor = 0.87,
  k_fast_multiplier   = 1.00
)
param_min <- lapply(fi_defaults, function(v) v * 0.50)
param_max <- lapply(fi_defaults, function(v) v * 1.50)
param_min$fast_fraction       <- max(param_min$fast_fraction, 0.05)
param_max$fast_fraction       <- min(param_max$fast_fraction, 0.95)
param_min$slow_k              <- max(param_min$slow_k, 0.001)
param_min$preservation_factor <- max(param_min$preservation_factor, 0.10)
param_max$preservation_factor <- min(param_max$preservation_factor, 1.00)
param_min$k_fast_multiplier   <- max(param_min$k_fast_multiplier, 0.05)
param_names <- names(fi_defaults)

# -- 3. Per-cell fi, rebuilt from raw inputs ----------------------------------
# Depth weights, copied from step5_merge_tiles_optimized.R:209-214. They are
# constants of the grid (they depend on p_d only), so they are computed once.
d[, p_d_safe := fifelse(is.na(p_d) | p_d <= 0, 1, p_d)]
d[, w1 := pmin(0.05, p_d_safe) / p_d_safe]
d[, w2 := pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe]

SVR_v   <- d$SVR
pl_v    <- d$p_l
w1_v    <- d$w1
w2_v    <- d$w2
kfast_v <- d$k_fast
fresh_v <- if (has_fresh) d$fresh_fact else rep(1, nrow(d))

fi_cells <- function(alpha_dep, fast_frac, slow_k, preserv, k_mult) {
  # p_l_eff: surface layer + capped deep layer, the deep one damped by alpha_dep
  p_l_eff <- w1_v * pl_v + w2_v * pl_v * alpha_dep
  # freshness correction, per cell, as carried by the grid
  p_l_corr <- p_l_eff * fresh_v
  # two-pool first-year remineralisation, k_fast now varying cell by cell
  SVR_v * p_l_corr * preserv *
    (fast_frac * (1 - exp(-kfast_v * k_mult)) +
     (1 - fast_frac) * (1 - exp(-slow_k)))
}

# -- 4. Self-check: does the reconstruction reproduce f_i_full? ---------------
cat("\n-- Reconstruction check at default parameters --\n")
fi_hat <- do.call(fi_cells, unname(fi_defaults))
ok <- is.finite(fi_hat) & is.finite(d$f_i_full) & d$f_i_full > 0
rel <- abs(fi_hat[ok] - d$f_i_full[ok]) / d$f_i_full[ok]
cat(sprintf("  correlation with f_i_full : %.6f\n", stats::cor(fi_hat[ok], d$f_i_full[ok])))
cat(sprintf("  median relative deviation : %.3g\n", median(rel)))
cat(sprintf("  90th percentile deviation : %.3g\n", stats::quantile(rel, 0.90)))
cat(sprintf("  sum rebuilt / sum stored  : %.6f\n", sum(fi_hat[ok]) / sum(d$f_i_full[ok])))

if (median(rel) > 0.01) {
  stop("ABORTING: the rebuilt f_i does not match the stored f_i_full ",
       "(median relative deviation ", signif(median(rel), 3), "). ",
       "The formula above is not the one step5 actually applies - read ",
       "step5_merge_tiles_optimized.R sections 4-6 and fix fi_cells() before ",
       "trusting any index produced here.")
}
cat("  OK - reconstruction matches; proceeding.\n")

# -- 5. Sobol' analysis -------------------------------------------------------
fi_model <- function(X) {
  apply(X, 1, function(p) sum(fi_cells(p[1], p[2], p[3], p[4], p[5]), na.rm = TRUE))
}

N <- 1000L
cat(sprintf("\nSample size N = %d -> %d model evaluations over %d cells\n",
            N, 2L * N, nrow(d)))
set.seed(2024)
mk <- function() {
  X <- as.data.frame(mapply(function(lo, hi) runif(N, lo, hi),
                            lo = unlist(param_min), hi = unlist(param_max)))
  names(X) <- param_names
  X
}
X1 <- mk(); X2 <- mk()

cat("Running Sobol' analysis... ")
sa <- sobolSalt(model = fi_model, X1 = X1, X2 = X2,
                scheme = "A", conf = 0.95, nboot = 200)
cat("done\n")

# -- 6. Output ----------------------------------------------------------------
out <- data.table(
  parameter = param_names,
  S1        = sa$S[, 1], S1_lower = sa$S[, 4], S1_upper = sa$S[, 5],
  ST        = sa$T[, 1], ST_lower = sa$T[, 4], ST_upper = sa$T[, 5]
)
setorder(out, -ST)
print(out)

out_dir <- file.path(grid_dir, "sensitivity")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path(out_dir, "sobol_indices_realgrid.csv")
fwrite(out, out_csv)
cat(sprintf("\nSaved: %s\n", out_csv))
cat(sprintf("Grid used: %s (%d cells)\n", basename(grid_file), nrow(d)))
cat(sprintf("Elapsed: %.1f s\n", proc.time()["elapsed"] - t0))
