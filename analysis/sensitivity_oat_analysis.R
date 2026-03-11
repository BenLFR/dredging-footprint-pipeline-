#!/usr/bin/env Rscript
# ============================================================================
# sensitivity_oat_analysis.R
# One-at-a-time (OAT) parameter sensitivity for f_i / C_ri.
# Recomputes C_ri on the full fi_grid when step5 output is available, and falls
# back to a 25-cell synthetic test patch only when fi_grid is unavailable.
#
# Called by scripts_cluster/submit_sensitivity_array.sh with TASK_ID as arg.
#
# Output: appends one row to output_V6/sensitivity/oat_results.csv
#
# Usage:
#   Rscript analysis/sensitivity_oat_analysis.R 28
#   Rscript analysis/sensitivity_oat_analysis.R 6
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
t0 <- proc.time()[["elapsed"]]

# Load sensitivity manifest
manifest_path <- "configuration/sensitivity_manifest.csv"
if (!file.exists(manifest_path)) {
  stop("configuration/sensitivity_manifest.csv not found. Run from project root.")
}
manifest <- fread(manifest_path)
row <- manifest[task_id == TASK_ID]
if (nrow(row) == 0) {
  stop(sprintf("task_id=%d not found in manifest.", TASK_ID))
}

param_name <- row$parameter_name
param_value <- row$parameter_value
value_label <- row$value_label
cat(sprintf("Parameter: %s = %g  (label: %s)\n", param_name, param_value, value_label))

# Load fi parameter defaults and override the target parameter in memory.
yaml_paths <- c(
  "~/scratch/configuration/fi_parameters_with_freshness.yaml",
  "_-SpectreBen/scratch/configuration/fi_parameters_with_freshness.yaml",
  "configuration/fi_parameters_with_freshness.yaml",
  "~/scratch/configuration/fi_parameters.yaml",
  "_-SpectreBen/scratch/configuration/fi_parameters.yaml",
  "configuration/fi_parameters.yaml"
)
yaml_path <- NULL
for (p in yaml_paths) {
  expanded <- path.expand(p)
  if (file.exists(expanded)) {
    yaml_path <- expanded
    break
  }
}
if (is.null(yaml_path)) {
  stop("No fi parameter YAML found. Checked: ", paste(yaml_paths, collapse = ", "))
}
cat(sprintf("Using fi parameter YAML: %s\n", yaml_path))

params_raw <- yaml::read_yaml(yaml_path)
if (!is.null(params_raw$scenarios$default)) {
  par <- params_raw$scenarios$default
} else if (!is.null(params_raw$default)) {
  par <- params_raw$default
} else {
  par <- params_raw
}
if (is.null(par) || !is.list(par)) {
  stop("Cannot parse fi parameters from YAML: expected a list/scenario structure.")
}

if (param_name == "k_fast_multiplier") {
  par$k_fast_multiplier <- param_value
} else {
  par[[param_name]] <- param_value
}

alpha_dep <- par$alpha_dep
fast_frac <- par$fast_fraction
slow_k <- par$slow_k
preserv_fact <- par$preservation_factor
k_mult <- if (!is.null(par$k_fast_multiplier)) par$k_fast_multiplier else 1.0

cat(sprintf("  alpha_dep=%.4f  fast_fraction=%.4f  slow_k=%.4f\n",
            alpha_dep, fast_frac, slow_k))
cat(sprintf("  preservation_factor=%.4f  k_fast_multiplier=%.2f\n",
            preserv_fact, k_mult))

compute_k_mean <- function(par_list, k_mult_value) {
  if (!is.null(par_list$k_fast)) {
    k_vals <- suppressWarnings(as.numeric(unlist(par_list$k_fast)))
    k_vals <- k_vals[is.finite(k_vals)]
    if (length(k_vals) > 0) {
      return(mean(k_vals * k_mult_value))
    }
  }
  if (!is.null(par_list$k_fast_global_mean)) {
    return(as.numeric(par_list$k_fast_global_mean) * k_mult_value)
  }
  5.0 * k_mult_value
}

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

recompute_c_ri <- function(fi_dt, alpha_dep_value, fast_frac_value, slow_k_value,
                           preserv_value, k_mult_value, par_list) {
  notes <- character(0)
  alpha_dep_applied <- FALSE

  if (!("SVR" %in% names(fi_dt))) {
    stop("Cannot recalculate C_ri: SVR column missing from fi_grid.")
  }

  if (all(c("p_l", "p_d") %in% names(fi_dt))) {
    p_d_safe <- fifelse(is.finite(fi_dt$p_d) & fi_dt$p_d > 0, fi_dt$p_d, 1.0)
    w1_v <- pmin(0.05, p_d_safe) / p_d_safe
    w2_v <- pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe
    pl_eff_new <- w1_v * fi_dt$p_l + w2_v * fi_dt$p_l * alpha_dep_value
    alpha_dep_applied <- TRUE

    if ("fresh_fact" %in% names(fi_dt)) {
      pl_corr_new <- pl_eff_new * fi_dt$fresh_fact
    } else {
      pl_corr_new <- pl_eff_new
      notes <- c(
        notes,
        "fresh_fact missing from fi_grid; province-specific freshness weighting was not reproduced."
      )
    }
  } else if ("p_l_corr" %in% names(fi_dt)) {
    pl_corr_new <- fi_dt$p_l_corr
    notes <- c(
      notes,
      "p_l/p_d missing from fi_grid; alpha_dep could not be reapplied and existing p_l_corr was reused."
    )
  } else {
    stop("Cannot recalculate C_ri: need either p_l+p_d or p_l_corr in fi_grid.")
  }

  if ("k_used" %in% names(fi_dt)) {
    k_new <- fi_dt$k_used * k_mult_value
  } else {
    k_mean <- compute_k_mean(par_list, k_mult_value)
    k_new <- rep(k_mean, nrow(fi_dt))
    notes <- c(
      notes,
      "k_used missing from fi_grid; falling back to scalar mean k_fast approximation."
    )
  }

  f_i_new <- fi_dt$SVR * pl_corr_new * preserv_value *
    (fast_frac_value * (1 - exp(-k_new)) +
       (1 - fast_frac_value) * (1 - exp(-slow_k_value)))

  c_ri_new <- if ("C0i" %in% names(fi_dt)) fi_dt$C0i * f_i_new else f_i_new

  list(
    c_ri_sum = sum(c_ri_new, na.rm = TRUE),
    alpha_dep_applied = alpha_dep_applied,
    notes = unique(notes)
  )
}

# NOTE: When fi_grid is available, C_ri is recomputed on the full grid.
# The synthetic 25-cell patch is retained only as a fallback when fi_grid is absent.
search_dirs <- c(
  "output_V6",
  file.path(path.expand("~"), "scratch", "output_V6")
)
fi_grid_obj <- load_latest_fi_grid(search_dirs)

global_C_ri_sum <- NA_real_
test_patch_C_ri_sum <- NA_real_
result_scope <- "synthetic_test_patch"
limitations_note <- NA_character_
alpha_dep_applied <- FALSE
n_cells_used <- 25L

if (!is.null(fi_grid_obj)) {
  fi_dt <- fi_grid_obj$data
  cat(sprintf("Loading fi_grid: %s\n", basename(fi_grid_obj$path)))
  cat(sprintf("Using full fi_grid: %d cells\n", nrow(fi_dt)))

  recalc <- recompute_c_ri(
    fi_dt = fi_dt,
    alpha_dep_value = alpha_dep,
    fast_frac_value = fast_frac,
    slow_k_value = slow_k,
    preserv_value = preserv_fact,
    k_mult_value = k_mult,
    par_list = par
  )

  global_C_ri_sum <- recalc$c_ri_sum
  result_scope <- "global_fi_grid"
  alpha_dep_applied <- recalc$alpha_dep_applied
  n_cells_used <- nrow(fi_dt)
  if (length(recalc$notes) > 0) {
    limitations_note <- paste(recalc$notes, collapse = " | ")
    cat(sprintf("Known limitations: %s\n", limitations_note))
  }
  if (alpha_dep_applied) {
    cat("alpha_dep reapplied via depth-weighting on p_l and p_d from fi_grid.\n")
  }
  cat(sprintf("Recomputed global C_ri sum: %.6e\n", global_C_ri_sum))
} else {
  cat("No fi_grid found - using synthetic 25-cell test patch.\n")
  set.seed(TASK_ID * 7)
  SVR_vals <- runif(n_cells_used, 0, 0.1)
  pl_vals <- runif(n_cells_used, 0.2, 0.8)

  # Depth-weighting (Step5 production formula, synthetic fallback uses p_d = 1 m).
  p_d_safe <- 1.0
  w1 <- min(0.05, p_d_safe) / p_d_safe
  w2 <- min(0.05, max(p_d_safe - 0.05, 0)) / p_d_safe
  pl_eff <- w1 * pl_vals + w2 * pl_vals * alpha_dep
  alpha_dep_applied <- TRUE

  k_mean <- compute_k_mean(par, k_mult)
  f_i_vals <- SVR_vals * pl_eff * preserv_fact *
    (fast_frac * (1 - exp(-k_mean)) +
       (1 - fast_frac) * (1 - exp(-slow_k)))

  test_patch_C_ri_sum <- sum(f_i_vals, na.rm = TRUE)
  limitations_note <- paste(
    "Synthetic fallback only: result is a 25-cell proxy, not the global grid.",
    "fresh_fact is not reproduced without a Longhurst join."
  )
  cat(sprintf("Known limitations: %s\n", limitations_note))
  cat(sprintf("Synthetic test-patch C_ri sum: %.6e\n", test_patch_C_ri_sum))
}

runtime_sec <- proc.time()[["elapsed"]] - t0
result_row <- data.table(
  task_id = TASK_ID,
  parameter_name = param_name,
  parameter_value = param_value,
  value_label = value_label,
  global_C_ri_sum = global_C_ri_sum,
  test_patch_C_ri_sum = test_patch_C_ri_sum,
  result_scope = result_scope,
  alpha_dep_applied = alpha_dep_applied,
  n_cells_used = n_cells_used,
  limitations_note = limitations_note,
  runtime_sec = round(runtime_sec, 1)
)

# On cluster, prefer ~/scratch/output_V6/ (NFS scratch); fall back to local output_V6/
scratch_dir <- file.path(path.expand("~"), "scratch", "output_V6", "sensitivity")
out_dir <- if (dir.exists(file.path(path.expand("~"), "scratch"))) {
  scratch_dir
} else {
  "output_V6/sensitivity"
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path(out_dir, "oat_results.csv")

# Write one file per task to avoid concurrent write collisions in SLURM arrays.
task_csv <- file.path(out_dir, sprintf("oat_task_%02d.csv", TASK_ID))
fwrite(result_row, task_csv)

# Best effort combined CSV refresh for convenience.
ok_merge <- TRUE
all_task_files <- list.files(out_dir, pattern = "^oat_task_[0-9]+\\.csv$", full.names = TRUE)
if (length(all_task_files) > 0) {
  merged <- tryCatch(
    rbindlist(lapply(all_task_files, fread), fill = TRUE),
    error = function(e) {
      ok_merge <<- FALSE
      NULL
    }
  )
  if (!is.null(merged)) {
    setorder(merged, task_id)
    merged <- merged[!duplicated(task_id, fromLast = TRUE)]
    fwrite(merged, out_csv)
  }
}

cat(sprintf("Wrote task result: %s\n", task_csv))
if (ok_merge) {
  cat(sprintf("Refreshed combined file: %s\n", out_csv))
} else {
  cat("Combined oat_results.csv not refreshed this run (likely concurrent write).\n")
}
cat(sprintf("Done in %.1f seconds.\n", runtime_sec))
