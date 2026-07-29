#!/usr/bin/env Rscript
# ============================================================================
# decompose_conservative.R
# What actually produces the -64% of the "strict conservative scenario"?
#
# Written 2026-07-29. The manuscript halves BOTH the labile proportions and the
# decay constants, then reports a single reduction. A Sobol index cannot tell
# us how that reduction splits: it measures a share of variance over a sampling
# range, not the effect of one specific perturbation. So we compute it.
#
# Four grid-wide sums, all from the same reconstruction that was validated
# against f_i_full (correlation 1.000000):
#   full      : default parameters
#   half_pl   : labile proportions halved, decay constants untouched
#   half_k    : decay constants halved, labile proportions untouched
#   both      : the published conservative scenario
#
# The script also compares `both` with the stored f_i_conservative column, so
# that the decomposition is only trusted if it reproduces the published number.
#
# USAGE: Rscript decompose_conservative.R
# ============================================================================

user_lib <- path.expand("~/R/library")
if (dir.exists(user_lib)) .libPaths(unique(c(user_lib, .libPaths())))
suppressPackageStartupMessages({ library(data.table); library(arrow) })

grid_dir <- path.expand("~/scratch/output_V6")
f <- tail(sort(list.files(grid_dir, pattern = "^fi_grid.*\\.parquet$",
                          full.names = TRUE, recursive = TRUE)), 1)
cat("Grid:", f, "\n")
d <- as.data.table(arrow::read_parquet(f))

need <- c("SVR", "p_l", "p_d", "k_fast", "f_i_full")
d <- d[stats::complete.cases(d[, ..need])]
has_fresh <- "fresh_fact" %in% names(d)
has_cons  <- "f_i_conservative" %in% names(d)
cat("Cells:", nrow(d), "\n\n")

ALPHA <- 0.25; FF <- 0.30; SLOW_K <- 0.05; PRESERV <- 0.87

d[, p_d_safe := fifelse(is.na(p_d) | p_d <= 0, 1, p_d)]
d[, w1 := pmin(0.05, p_d_safe) / p_d_safe]
d[, w2 := pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe]
pl_corr <- (d$w1 * d$p_l + d$w2 * d$p_l * ALPHA) *
           (if (has_fresh) d$fresh_fact else 1)

fi_sum <- function(pl_mult = 1, k_mult = 1) {
  sum(d$SVR * pl_corr * pl_mult * PRESERV *
      (FF * (1 - exp(-d$k_fast * k_mult)) +
       (1 - FF) * (1 - exp(-SLOW_K * k_mult))), na.rm = TRUE)
}

full    <- fi_sum(1,   1)
half_pl <- fi_sum(0.5, 1)
half_k  <- fi_sum(1,   0.5)
both    <- fi_sum(0.5, 0.5)

pct <- function(x) sprintf("%+.1f%%", 100 * (x / full - 1))
cat("-- Grid-wide sum of first-year remineralised carbon --\n")
cat(sprintf("  full (defaults)          : %.6g\n", full))
cat(sprintf("  labile proportions /2    : %.6g   %s\n", half_pl, pct(half_pl)))
cat(sprintf("  decay constants /2       : %.6g   %s\n", half_k,  pct(half_k)))
cat(sprintf("  both halved (published)  : %.6g   %s\n", both,    pct(both)))

if (has_cons) {
  stored <- sum(d$f_i_conservative, na.rm = TRUE)
  cat(sprintf("\n  stored f_i_conservative  : %.6g   %s\n", stored,
              sprintf("%+.1f%%", 100 * (stored / sum(d$f_i_full, na.rm = TRUE) - 1))))
  cat(sprintf("  rebuilt 'both' / stored  : %.6f", both / stored))
  cat(if (abs(both / stored - 1) < 0.01) "   OK\n" else
      "   MISMATCH - the scenario is not a plain halving of these two, do not use\n")
}

cat("\n-- Where the saturation bites --\n")
# The grid-wide sum is dominated by a few very high-SVR cells. If those sit in
# provinces where k_fast is already large, 1 - exp(-k) is saturated and halving
# k barely moves the total, however much it moves a median cell. Hence the
# contribution-weighted median below, not the plain one.
w  <- d$SVR * pl_corr
o  <- order(w, decreasing = TRUE)
cw <- cumsum(w[o]) / sum(w)
wm <- d$k_fast[o][which(cumsum(w[o]) >= 0.5 * sum(w))[1]]
cat(sprintf("  k_fast, plain median                         : %.3g\n", median(d$k_fast, na.rm = TRUE)))
cat(sprintf("  k_fast of the cell at the 50%% of total mass  : %.3g\n", wm))
cat(sprintf("  share of the total carried by the top 1%% cells: %.1f%%\n",
            100 * cw[ceiling(0.01 * length(w))]))
