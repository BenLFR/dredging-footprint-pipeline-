#!/usr/bin/env Rscript
# ============================================================================
# monte_carlo_uncertainty.R
# Monte Carlo uncertainty propagation through the f_i and C_ri calculations.
# Uses the full fi_grid when available, with a stratified fallback only if the
# grid is very large for local RAM.
#
# Propagated error sources:
#   1. AIS position error (+/-30 m Gaussian, 1 sigma)
#   2. Dredging classification error (Bernoulli flip proportional to 1 - LOYO_AUC)
#   3. fi parameter uncertainty (+/-10% Gaussian for each of 5 parameters)
#
# Usage:
#   Rscript analysis/monte_carlo_uncertainty.R <BATCH_ID>
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript monte_carlo_uncertainty.R <BATCH_ID>  (BATCH_ID: 1-10)")
}
BATCH_ID <- as.integer(args[1])
if (is.na(BATCH_ID) || BATCH_ID < 1 || BATCH_ID > 10) {
  stop("BATCH_ID must be an integer 1-10.")
}

ITER_START <- (BATCH_ID - 1) * 50 + 1
ITER_END <- BATCH_ID * 50
N_ITER <- ITER_END - ITER_START + 1

set.seed(BATCH_ID * 42)

cat(sprintf("=== Monte Carlo Uncertainty | Batch %d (iter %d-%d) ===\n",
            BATCH_ID, ITER_START, ITER_END))
t0 <- proc.time()[["elapsed"]]

suppressPackageStartupMessages({
  library(data.table)
})

CELL_SIZE_M <- 1000
AIS_POS_ERROR_M_1SIGMA <- 30.0
FI_PARAM_CV <- 0.10
MAX_FULL_GRID_CELLS <- 200000L

fi_params_default <- list(
  alpha_dep = 0.25,
  fast_fraction = 0.30,
  slow_k = 0.05,
  preservation_factor = 0.87,
  k_fast_multiplier = 1.00
)

k_fast_defaults <- c(
  North_Pacific = 1.67,
  South_Pacific = 3.84,
  Atlantic = 1.00,
  Indian = 4.76,
  Mediterranean = 12.3,
  Arctic = 0.275,
  Gulf_Mexico_Caribbean = 16.8
)

load_latest_fi_grid <- function(search_roots) {
  fi_files <- character(0)
  for (d in search_roots) {
    if (!dir.exists(d)) {
      next
    }
    fi_files <- c(
      fi_files,
      list.files(d, pattern = "^fi_grid_.*\\.(parquet|rds)$", full.names = TRUE)
    )
  }
  if (length(fi_files) == 0) {
    return(NULL)
  }

  fi_files <- fi_files[order(file.info(fi_files)$mtime, decreasing = TRUE)]
  for (candidate in fi_files) {
    fi_dt <- tryCatch(
      if (grepl("\\.parquet$", candidate)) {
        if (!requireNamespace("arrow", quietly = TRUE)) {
          stop("arrow package not available for parquet input.")
        }
        setDT(arrow::read_parquet(candidate))
      } else {
        setDT(readRDS(candidate))
      },
      error = function(e) {
        cat(sprintf("Skipping unreadable fi_grid candidate %s: %s\n",
                    basename(candidate), conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(fi_dt)) {
      return(list(path = candidate, data = fi_dt))
    }
  }

  NULL
}

sample_large_grid <- function(fi_dt, max_cells) {
  if (nrow(fi_dt) <= max_cells) {
    return(list(data = fi_dt, sampled = FALSE, stratifier = NA_character_))
  }

  stratifier <- NULL
  if ("longhurst_pr" %in% names(fi_dt)) {
    stratifier <- "longhurst_pr"
  } else if ("ProvDescr" %in% names(fi_dt)) {
    stratifier <- "ProvDescr"
  }

  if (is.null(stratifier)) {
    sampled_dt <- fi_dt[sample(.N, max_cells)]
    return(list(data = sampled_dt, sampled = TRUE, stratifier = NA_character_))
  }

  sampled_dt <- fi_dt[
    ,
    .SD[sample(.N, max(1L, round(max_cells * .N / nrow(fi_dt))))],
    by = stratifier
  ]
  if (nrow(sampled_dt) > max_cells) {
    sampled_dt <- sampled_dt[sample(.N, max_cells)]
  }
  list(data = sampled_dt, sampled = TRUE, stratifier = stratifier)
}

# Load LOYO AUC from step3 benchmarking output if available.
auc_metrics_path <- "output_V6/step3_auc_metrics.csv"
LOYO_AUC <- 0.85
if (file.exists(auc_metrics_path)) {
  auc_dt <- fread(auc_metrics_path)
  if ("mean_auc" %in% names(auc_dt)) {
    LOYO_AUC <- auc_dt$mean_auc[1]
    cat(sprintf("LOYO AUC loaded from CSV: %.4f\n", LOYO_AUC))
  }
} else {
  cat(sprintf("step3_auc_metrics.csv not found. Using fallback AUC=%.2f.\n", LOYO_AUC))
  cat("Run extract_step3_auc_metrics.R first for more accurate uncertainty estimates.\n")
}

search_dirs <- c(
  "output_V6",
  file.path(path.expand("~"), "scratch", "output_V6")
)
fi_grid_obj <- load_latest_fi_grid(search_dirs)

if (!is.null(fi_grid_obj)) {
  fi_raw <- fi_grid_obj$data
  fi_sample <- sample_large_grid(fi_raw, MAX_FULL_GRID_CELLS)
  fi_dt <- fi_sample$data

  cat(sprintf("Loading fi_grid: %s\n", basename(fi_grid_obj$path)))
  cat(sprintf("Source fi_grid cells: %d\n", nrow(fi_raw)))
  if (isTRUE(fi_sample$sampled)) {
    if (!is.na(fi_sample$stratifier)) {
      cat(sprintf(
        "Using stratified sample of %d cells by %s (limit=%d)\n",
        nrow(fi_dt), fi_sample$stratifier, MAX_FULL_GRID_CELLS
      ))
    } else {
      cat(sprintf(
        "Using random sample of %d cells (limit=%d)\n",
        nrow(fi_dt), MAX_FULL_GRID_CELLS
      ))
    }
  } else {
    cat(sprintf("Using full fi_grid: %d cells\n", nrow(fi_dt)))
  }
} else {
  cat("No fi_grid found - using synthetic 25-cell test patch.\n")
  fi_dt <- data.table(
    grid_id = seq_len(25L),
    SVR = runif(25L, 0, 0.1),
    p_l = runif(25L, 0.2, 0.8),
    p_d = 1.0,
    fresh_fact = 1.0,
    k_used = mean(k_fast_defaults),
    C0i = 1.0,
    Dragage_flag = 1L
  )
}

n_cells <- nrow(fi_dt)
cat(sprintf("n_cells used for this batch: %d\n", n_cells))
cat("Known limitation: classification error is applied at cell level, not at ping level.\n")

if (!("SVR" %in% names(fi_dt))) {
  stop("Cannot perform Monte Carlo: SVR column missing from fi_grid.")
}

grid_id_base <- if ("grid_id" %in% names(fi_dt)) fi_dt$grid_id else seq_len(n_cells)
svr_base <- fi_dt$SVR
c0i_base <- if ("C0i" %in% names(fi_dt)) fi_dt$C0i else rep(1.0, n_cells)
dflag_col <- if ("Dragage_flag" %in% names(fi_dt)) {
  "Dragage_flag"
} else if ("ref_binary" %in% names(fi_dt)) {
  "ref_binary"
} else {
  NULL
}
dflag_base <- if (!is.null(dflag_col)) as.integer(fi_dt[[dflag_col]]) else rep(1L, n_cells)

has_raw_depth <- all(c("p_l", "p_d") %in% names(fi_dt))
has_fresh_fact <- "fresh_fact" %in% names(fi_dt)
has_p_l_corr <- "p_l_corr" %in% names(fi_dt)
has_k_used <- "k_used" %in% names(fi_dt)

if (has_raw_depth) {
  p_l_base <- fi_dt$p_l
  p_d_safe <- fifelse(is.finite(fi_dt$p_d) & fi_dt$p_d > 0, fi_dt$p_d, 1.0)
  w1_v <- pmin(0.05, p_d_safe) / p_d_safe
  w2_v <- pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe
  fresh_fact_base <- if (has_fresh_fact) fi_dt$fresh_fact else rep(1.0, n_cells)
  cat("alpha_dep will be reapplied from p_l and p_d for each Monte Carlo iteration.\n")
  if (!has_fresh_fact) {
    cat("Known limitation: fresh_fact missing from fi_grid; using pl_eff without freshness weighting.\n")
  }
} else if (has_p_l_corr) {
  p_l_corr_base <- fi_dt$p_l_corr
  cat("Known limitation: p_l/p_d missing from fi_grid; reusing p_l_corr, so alpha_dep cannot be perturbed.\n")
} else {
  stop("Cannot perform Monte Carlo: need either p_l+p_d or p_l_corr in fi_grid.")
}

if (has_k_used) {
  k_used_base <- fi_dt$k_used
} else {
  k_used_base <- rep(mean(k_fast_defaults), n_cells)
  cat("Known limitation: k_used missing from fi_grid; using mean k_fast fallback.\n")
}

pos_frac <- AIS_POS_ERROR_M_1SIGMA / CELL_SIZE_M
flip_prob <- max(0, min(1, 1 - LOYO_AUC))
results_list <- vector("list", N_ITER)

for (iter_offset in seq_len(N_ITER)) {
  iter_id <- ITER_START + iter_offset - 1

  svr_mc <- svr_base * pmax(0, 1 + rnorm(n_cells, mean = 0, sd = pos_frac))
  flips <- rbinom(n_cells, 1, flip_prob)
  dragage_flag_mc <- fifelse(flips == 1L, 1L - dflag_base, dflag_base)
  svr_mc <- svr_mc * dragage_flag_mc

  alpha_dep_mc <- fi_params_default$alpha_dep * rnorm(1, 1, FI_PARAM_CV)
  fast_frac_mc <- pmin(1, pmax(0, fi_params_default$fast_fraction * rnorm(1, 1, FI_PARAM_CV)))
  slow_k_mc <- pmax(0, fi_params_default$slow_k * rnorm(1, 1, FI_PARAM_CV))
  preserv_fact_mc <- pmin(
    1,
    pmax(0, fi_params_default$preservation_factor * rnorm(1, 1, FI_PARAM_CV))
  )
  k_mult_mc <- pmax(0, fi_params_default$k_fast_multiplier * rnorm(1, 1, FI_PARAM_CV))

  if (has_raw_depth) {
    pl_eff_new <- w1_v * p_l_base + w2_v * p_l_base * alpha_dep_mc
    pl_corr_new <- pl_eff_new * fresh_fact_base
  } else {
    pl_corr_new <- p_l_corr_base
  }

  k_new <- k_used_base * k_mult_mc
  fi_mc <- svr_mc * pl_corr_new * preserv_fact_mc *
    (fast_frac_mc * (1 - exp(-k_new)) +
       (1 - fast_frac_mc) * (1 - exp(-slow_k_mc)))
  c_ri_mc <- c0i_base * fi_mc

  results_list[[iter_offset]] <- data.table(
    cell_id = seq_len(n_cells),
    grid_id = grid_id_base,
    iteration = iter_id,
    fi_value = fi_mc,
    C_ri_value = c_ri_mc
  )
}

mc_results <- rbindlist(results_list)
cat(sprintf("Generated %d MC rows (%d cells x %d iterations)\n",
            nrow(mc_results), n_cells, N_ITER))

out_dir <- if (dir.exists(file.path(path.expand("~"), "scratch"))) {
  file.path(path.expand("~"), "scratch", "output_V6", "uncertainty")
} else {
  "output_V6/uncertainty"
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_file <- file.path(out_dir, sprintf("mc_batch_%02d.parquet", BATCH_ID))

if (requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_parquet(mc_results, out_file)
  cat(sprintf("Saved (parquet): %s\n", out_file))
} else {
  out_rds <- sub("\\.parquet$", ".rds", out_file)
  saveRDS(mc_results, out_rds, compress = "xz")
  cat(sprintf("Saved (rds): %s\n", out_rds))
}

runtime_sec <- proc.time()[["elapsed"]] - t0
cat(sprintf("Batch %d done in %.1f seconds.\n", BATCH_ID, runtime_sec))
