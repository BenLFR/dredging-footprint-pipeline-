#!/usr/bin/env Rscript
# ============================================================================
# sensitivity_oat_analysis.R
# One-at-a-time (OAT) parameter sensitivity for f_i / C_ri.
# Runs step5+step6 logic on a small 3×3 tile test region for one row of
# configuration/sensitivity_manifest.csv.
#
# Called by scripts_cluster/submit_sensitivity_array.sh with TASK_ID as arg.
#
# Output: appends one row to output_V6/sensitivity/oat_results.csv
#
# Usage:
#   Rscript scripts_principaux/sensitivity_oat_analysis.R 28   # task_id=28 (slow_k baseline)
#   Rscript scripts_principaux/sensitivity_oat_analysis.R 6    # alpha_dep baseline
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript sensitivity_oat_analysis.R <TASK_ID>")
}
TASK_ID <- as.integer(args[1])
if (is.na(TASK_ID) || TASK_ID < 1 || TASK_ID > 55) {
  stop("TASK_ID must be an integer between 1 and 55.")
}

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

cat(sprintf("=== OAT Sensitivity | task_id=%d ===\n", TASK_ID))
t0 <- proc.time()["elapsed"]

# ── 1. Load sensitivity manifest ──────────────────────────────────────────────
manifest_path <- "configuration/sensitivity_manifest.csv"
if (!file.exists(manifest_path)) {
  stop("configuration/sensitivity_manifest.csv not found. Run from project root.")
}
manifest <- fread(manifest_path)
row <- manifest[task_id == TASK_ID]
if (nrow(row) == 0) stop(sprintf("task_id=%d not found in manifest.", TASK_ID))

param_name  <- row$parameter_name
param_value <- row$parameter_value
value_label <- row$value_label
cat(sprintf("Parameter: %s = %g  (label: %s)\n", param_name, param_value, value_label))

# ── 2. Load fi_parameters.yaml and override the target parameter ──────────────
yaml_paths <- c(
  "~/scratch/configuration/fi_parameters.yaml",
  "_-SpectreBen/scratch/configuration/fi_parameters.yaml",
  "configuration/fi_parameters.yaml"
)
yaml_path <- NULL
for (p in yaml_paths) {
  expanded <- path.expand(p)
  if (file.exists(expanded)) { yaml_path <- expanded; break }
}
if (is.null(yaml_path)) {
  stop("fi_parameters.yaml not found. Checked: ", paste(yaml_paths, collapse = ", "))
}
params_raw <- yaml::read_yaml(yaml_path)
par <- params_raw$scenarios$default

# Override in memory (do NOT modify YAML on disk)
if (param_name == "k_fast_multiplier") {
  par$k_fast_multiplier <- param_value
} else {
  par[[param_name]] <- param_value
}

alpha_dep    <- par$alpha_dep
fast_frac    <- par$fast_fraction
slow_k       <- par$slow_k
preserv_fact <- par$preservation_factor
k_mult       <- if (!is.null(par$k_fast_multiplier)) par$k_fast_multiplier else 1.0

cat(sprintf("  alpha_dep=%.4f  fast_fraction=%.4f  slow_k=%.4f\n",
            alpha_dep, fast_frac, slow_k))
cat(sprintf("  preservation_factor=%.4f  k_fast_multiplier=%.2f\n",
            preserv_fact, k_mult))

# ── 3. Test region: 3×3 tiles in the Indian Ocean (low dredging activity) ─────
# Approx: 10°N–12.5°N, 60°E–62.5°E in WGS84
# This is a quiet open-ocean region; any result here is methodological baseline.
# In a full run, replace with the actual fi_grid merged output from step5.
TEST_LAT_MIN <- 10.0; TEST_LAT_MAX <- 12.5
TEST_LON_MIN <- 60.0; TEST_LON_MAX <- 62.5
CELL_SIZE_M  <- 1000
CELL_AREA_M2 <- CELL_SIZE_M * CELL_SIZE_M

# Load the most recent merged fi tile output if available
search_dirs <- c("output_V6",
                 file.path(path.expand("~"), "scratch", "output_V6"))
fi_files <- character(0)
for (d in search_dirs) {
  if (dir.exists(d)) {
    found <- list.files(d, pattern = "^fi_grid_.*\\.(parquet|rds)$", full.names = TRUE)
    fi_files <- c(fi_files, found)
  }
}

if (length(fi_files) > 0 && requireNamespace("arrow", quietly = TRUE)) {
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
  cat(sprintf("Loading fi_grid: %s\n", basename(fi_path)))
  if (grepl("\\.parquet$", fi_path)) {
    fi_dt <- setDT(arrow::read_parquet(fi_path))
  } else {
    fi_dt <- setDT(readRDS(fi_path))
  }
  # Filter to test region if lon/lat available
  if ("lon" %in% names(fi_dt) && "lat" %in% names(fi_dt)) {
    fi_sub <- fi_dt[lat >= TEST_LAT_MIN & lat <= TEST_LAT_MAX &
                    lon >= TEST_LON_MIN & lon <= TEST_LON_MAX]
    cat(sprintf("Test region: %d cells\n", nrow(fi_sub)))
  } else {
    # Use all cells (may be slow for large grids — subsample if needed)
    fi_sub <- fi_dt[sample(.N, min(.N, 10000))]
    cat(sprintf("No lat/lon columns — using random subsample of %d cells\n", nrow(fi_sub)))
  }

  # Extract SVR and p_l columns for recalculation
  has_svr <- "SVR" %in% names(fi_sub)
  has_pl  <- "p_l_corr" %in% names(fi_sub) || "p_l" %in% names(fi_sub)

  if (has_svr && has_pl) {
    pl_col <- if ("p_l_corr" %in% names(fi_sub)) "p_l_corr" else "p_l"

    # Recalculate f_i with overridden parameters
    # k_fast: use mean of provincial values * multiplier as scalar approximation
    k_table <- data.frame(
      prov  = names(par$k_fast),
      k_val = unlist(par$k_fast) * k_mult
    )
    k_mean <- mean(k_table$k_val)

    fi_sub[, f_i_new := SVR * get(pl_col) * preserv_fact *
                        (fast_frac       * (1 - exp(-k_mean)) +
                         (1 - fast_frac) * (1 - exp(-slow_k)))]

    # C_ri proxy: use mean C0i = 1.0 (normalised) if not available
    if ("C0i" %in% names(fi_sub)) {
      fi_sub[, C_ri_new := C0i * f_i_new]
    } else {
      fi_sub[, C_ri_new := f_i_new]   # dimensionless proxy
    }

    C_ri_sum <- sum(fi_sub$C_ri_new, na.rm = TRUE)
    cat(sprintf("Recomputed C_ri sum (test region): %.6e\n", C_ri_sum))
  } else {
    cat("SVR or p_l columns not found in fi_grid — using f_i_full if available.\n")
    col <- intersect(c("f_i_full", "f_i_reduced", "C_ri"), names(fi_sub))[1]
    C_ri_sum <- if (!is.na(col)) sum(fi_sub[[col]], na.rm = TRUE) else NA_real_
    cat(sprintf("C_ri_sum proxy (column: %s): %.6e\n", col, C_ri_sum))
  }

} else {
  # Synthetic fallback: generate a 5×5 km patch of representative SVR values
  cat("No fi_grid found — using synthetic 5×5 km test patch\n")
  n_cells <- 25
  set.seed(TASK_ID * 7)
  SVR_vals <- runif(n_cells, 0, 0.1)
  pl_vals  <- runif(n_cells, 0.2, 0.8)

  k_mean <- mean(unlist(par$k_fast) * k_mult)
  f_i_vals <- SVR_vals * pl_vals * preserv_fact *
               (fast_frac       * (1 - exp(-k_mean)) +
                (1 - fast_frac) * (1 - exp(-slow_k)))

  C_ri_sum <- sum(f_i_vals)
  cat(sprintf("Synthetic C_ri sum (25 cells): %.6e\n", C_ri_sum))
}

# ── 4. Record result ──────────────────────────────────────────────────────────
runtime_sec <- (proc.time()["elapsed"] - t0)
result_row <- data.table(
  task_id         = TASK_ID,
  parameter_name  = param_name,
  parameter_value = param_value,
  value_label     = value_label,
  global_C_ri_sum = C_ri_sum,
  runtime_sec     = round(runtime_sec, 1)
)

# ── 5. Append to results CSV ──────────────────────────────────────────────────
# On GRIT, prefer ~/scratch/output_V6/ (NFS scratch); fall back to local output_V6/
scratch_dir <- file.path(path.expand("~"), "scratch", "output_V6", "sensitivity")
out_dir <- if (dir.exists(file.path(path.expand("~"), "scratch"))) {
  scratch_dir
} else {
  "output_V6/sensitivity"
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path(out_dir, "oat_results.csv")

if (file.exists(out_csv)) {
  # Remove existing row for this task_id (idempotent re-run)
  existing <- fread(out_csv)
  existing <- existing[task_id != TASK_ID]
  fwrite(rbindlist(list(existing, result_row), fill = TRUE), out_csv)
} else {
  fwrite(result_row, out_csv)
}

cat(sprintf("Appended task_id=%d to %s\n", TASK_ID, out_csv))
cat(sprintf("Done in %.1f seconds.\n", runtime_sec))
