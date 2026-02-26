#!/usr/bin/env Rscript
# ============================================================================
# monte_carlo_uncertainty.R
# Monte Carlo uncertainty propagation through the f_i and C_ri calculations.
# Propagates three independent error sources:
#   1. AIS position error (±30 m Gaussian, 1σ) → cell assignment uncertainty
#   2. Dredging classification error (Bernoulli flip ∝ 1 - LOYO_AUC)
#   3. fi parameter uncertainty (±10% Gaussian for each of 5 parameters)
#
# Runs in batches of 50 iterations each. Full run = 10 batches × 50 = 500 iter.
#
# Usage:
#   Rscript scripts_principaux/monte_carlo_uncertainty.R <BATCH_ID>
#   # BATCH_ID: integer 1–10; each batch does iterations (BATCH_ID-1)*50+1 to BATCH_ID*50
#
# Output:
#   output_V6/uncertainty/mc_batch_<BATCH_ID>.parquet
#   (after all 10 batches: run submit_monte_carlo.sh merge step)
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript monte_carlo_uncertainty.R <BATCH_ID>  (BATCH_ID: 1-10)")
}
BATCH_ID <- as.integer(args[1])
if (is.na(BATCH_ID) || BATCH_ID < 1 || BATCH_ID > 10) {
  stop("BATCH_ID must be an integer 1–10.")
}

ITER_START <- (BATCH_ID - 1) * 50 + 1
ITER_END   <- BATCH_ID * 50
N_ITER     <- ITER_END - ITER_START + 1

# Reproducible seed per batch
set.seed(BATCH_ID * 42)

cat(sprintf("=== Monte Carlo Uncertainty | Batch %d (iter %d–%d) ===\n",
            BATCH_ID, ITER_START, ITER_END))
t0 <- proc.time()["elapsed"]

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

# ── Constants from constants.R ────────────────────────────────────────────────
CELL_SIZE_M  <- 1000L
CELL_AREA_M2 <- CELL_SIZE_M * CELL_SIZE_M
GRID_COLS    <- 34735L
WORLD_XMIN   <- -17367530.45
WORLD_YMAX   <-  7342699.72

# AIS position error (1σ) in metres
AIS_POS_ERROR_M_1SIGMA <- 30.0

# fi parameter uncertainty (1σ as fraction of default)
FI_PARAM_CV <- 0.10   # coefficient of variation

# ── Default fi parameters (from fi_parameters.yaml) ──────────────────────────
fi_params_default <- list(
  alpha_dep           = 0.25,
  fast_fraction       = 0.30,
  slow_k              = 0.05,
  preservation_factor = 0.87,
  k_fast_multiplier   = 1.00
)

# ── 1. Load AUC from step3 gridsearch results ──────────────────────────────────
auc_metrics_path <- "output_V6/step3_auc_metrics.csv"
LOYO_AUC <- 0.85   # fallback if step3_auc_metrics.csv not yet available

if (file.exists(auc_metrics_path)) {
  auc_dt <- fread(auc_metrics_path)
  if ("mean_auc" %in% names(auc_dt)) {
    LOYO_AUC <- auc_dt$mean_auc[1]
    cat(sprintf("LOYO AUC loaded from CSV: %.4f\n", LOYO_AUC))
  }
} else {
  cat(sprintf("step3_auc_metrics.csv not found. Using fallback AUC=%.2f.\n", LOYO_AUC))
  cat("Run extract_step3_auc_metrics.R first for accurate uncertainty estimates.\n")
}

# ── 2. Load fi_grid data for the test region ──────────────────────────────────
# Same test region as sensitivity analysis: Indian Ocean ~10–12.5°N, 60–62.5°E
search_dirs <- c("output_V6",
                 file.path(path.expand("~"), "scratch", "output_V6"))
fi_files <- character(0)
for (d in search_dirs) {
  if (dir.exists(d)) {
    found <- list.files(d, pattern = "^fi_grid_.*\\.(parquet|rds)$", full.names = TRUE)
    fi_files <- c(fi_files, found)
  }
}

if (length(fi_files) > 0) {
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
  cat(sprintf("Loading fi_grid: %s\n", basename(fi_path)))
  if (grepl("\\.parquet$", fi_path) && requireNamespace("arrow", quietly = TRUE)) {
    fi_dt <- setDT(arrow::read_parquet(fi_path))
  } else {
    fi_dt <- setDT(readRDS(fi_path))
  }
  # Subset to test region or random sample for performance
  if ("lon" %in% names(fi_dt) && "lat" %in% names(fi_dt)) {
    fi_sub <- fi_dt[lat >= 10 & lat <= 12.5 & lon >= 60 & lon <= 62.5]
    if (nrow(fi_sub) == 0) {
      cat("Test region empty — using random subsample.\n")
      fi_sub <- fi_dt[sample(.N, min(.N, 500))]
    }
  } else {
    fi_sub <- fi_dt[sample(.N, min(.N, 500))]
  }
  cat(sprintf("Test region: %d cells\n", nrow(fi_sub)))
  USE_REAL_DATA <- TRUE
} else {
  cat("No fi_grid found — using synthetic test patch (25 cells).\n")
  set.seed(99)
  n_cells <- 25
  fi_sub <- data.table(
    grid_id = 1:n_cells,
    SVR     = runif(n_cells, 0, 0.1),
    p_l_corr = runif(n_cells, 0.2, 0.8),
    C0i     = runif(n_cells, 0.5, 5.0),
    Dragage_flag = rbinom(n_cells, 1, 0.3)
  )
  USE_REAL_DATA <- FALSE
}

# ── 3. Monte Carlo iterations ─────────────────────────────────────────────────
n_cells    <- nrow(fi_sub)
has_svr    <- "SVR" %in% names(fi_sub)
has_pl     <- any(c("p_l_corr", "p_l") %in% names(fi_sub))
has_c0i    <- "C0i" %in% names(fi_sub)
has_dflag  <- any(c("Dragage_flag", "ref_binary") %in% names(fi_sub))
pl_col     <- if ("p_l_corr" %in% names(fi_sub)) "p_l_corr" else "p_l"
dflag_col  <- if ("Dragage_flag" %in% names(fi_sub)) "Dragage_flag" else "ref_binary"

if (!has_svr || !has_pl) {
  # Reconstruct a minimal representation from f_i_full if SVR not present
  if ("f_i_full" %in% names(fi_sub)) {
    fi_sub[, SVR     := f_i_full / max(f_i_full, na.rm = TRUE) * 0.1]
    fi_sub[, p_l_corr := 0.5]
    has_svr <- TRUE; has_pl <- TRUE; pl_col <- "p_l_corr"
    cat("SVR/p_l reconstructed from f_i_full for MC purposes.\n")
  } else {
    stop("Cannot perform MC: SVR and p_l_corr columns missing from fi_grid.")
  }
}

if (!has_c0i) fi_sub[, C0i := 1.0]  # dimensionless proxy
if (!has_dflag) fi_sub[, Dragage_flag := 1L]  # assume all cells are dredging

results_list <- vector("list", N_ITER)

for (iter_offset in seq_len(N_ITER)) {
  iter_id <- ITER_START + iter_offset - 1

  dt_iter <- copy(fi_sub)

  # ── Error source 1: AIS position error ──────────────────────────────────────
  # Perturb SVR slightly: position error shifts cells by ~AIS_POS_ERROR_M_1SIGMA/CELL_SIZE_M
  # This is a fractional effect on SVR (conservative approximation)
  pos_frac <- AIS_POS_ERROR_M_1SIGMA / CELL_SIZE_M   # ~0.03
  dt_iter[, SVR := SVR * pmax(0, 1 + rnorm(.N, mean = 0, sd = pos_frac))]

  # ── Error source 2: Classification error ────────────────────────────────────
  # Flip the Dragage_flag with probability (1 - LOYO_AUC) per ping
  # For cell-level, this approximates the expected mislabel rate
  flip_prob <- 1 - LOYO_AUC
  flips <- rbinom(n_cells, 1, flip_prob)
  dt_iter[, Dragage_flag_mc := fifelse(flips == 1,
                                        as.integer(1 - get(dflag_col)),
                                        as.integer(get(dflag_col)))]
  dt_iter[, SVR := SVR * Dragage_flag_mc]

  # ── Error source 3: fi parameter uncertainty ─────────────────────────────────
  alpha_dep_mc     <- fi_params_default$alpha_dep * rnorm(1, 1, FI_PARAM_CV)
  fast_frac_mc     <- pmin(1, pmax(0, fi_params_default$fast_fraction *
                                       rnorm(1, 1, FI_PARAM_CV)))
  slow_k_mc        <- pmax(0, fi_params_default$slow_k * rnorm(1, 1, FI_PARAM_CV))
  preserv_fact_mc  <- pmin(1, pmax(0, fi_params_default$preservation_factor *
                                       rnorm(1, 1, FI_PARAM_CV)))
  k_mult_mc        <- pmax(0, fi_params_default$k_fast_multiplier *
                               rnorm(1, 1, FI_PARAM_CV))

  # Use mean k_fast across provinces (scalar approximation)
  k_fast_defaults <- c(
    North_Pacific = 1.67, South_Pacific = 3.84, Atlantic = 1.00,
    Indian = 4.76, Mediterranean = 12.3, Arctic = 0.275,
    Gulf_Mexico_Caribbean = 16.8
  )
  k_mean_mc <- mean(k_fast_defaults * k_mult_mc)

  # Recalculate f_i with perturbed parameters
  dt_iter[, f_i_mc := SVR * get(pl_col) * preserv_fact_mc *
                       (fast_frac_mc       * (1 - exp(-k_mean_mc)) +
                        (1 - fast_frac_mc) * (1 - exp(-slow_k_mc)))]

  dt_iter[, C_ri_mc := C0i * f_i_mc]

  results_list[[iter_offset]] <- data.table(
    cell_id   = seq_len(n_cells),
    grid_id   = if ("grid_id" %in% names(fi_sub)) fi_sub$grid_id else seq_len(n_cells),
    iteration = iter_id,
    fi_value  = dt_iter$f_i_mc,
    C_ri_value = dt_iter$C_ri_mc
  )
}

mc_results <- rbindlist(results_list)

cat(sprintf("Generated %d MC rows (%d cells × %d iterations)\n",
            nrow(mc_results), n_cells, N_ITER))

# ── 4. Save batch output ──────────────────────────────────────────────────────
# On GRIT, prefer ~/scratch/output_V6/ (NFS scratch); fall back to local output_V6/
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

runtime_sec <- proc.time()["elapsed"] - t0
cat(sprintf("Batch %d done in %.1f seconds.\n", BATCH_ID, runtime_sec))
