#!/usr/bin/env Rscript
# ============================================================================
# check_fi_grid_consistency.R
# Audits the latest fi_grid output against the production step5 formula.
#
# Outputs:
#   output_V6/diagnostics/fi_grid_consistency_checks.csv
#   output_V6/diagnostics/fi_grid_consistency_summary.txt
#
# Usage:
#   Rscript analysis/check_fi_grid_consistency.R
#   Rscript analysis/check_fi_grid_consistency.R 0.25
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
alpha_dep_override <- if (length(args) >= 1) as.numeric(args[1]) else NA_real_
if (!is.na(alpha_dep_override)) {
  cat(sprintf("alpha_dep override from CLI: %.6f\n", alpha_dep_override))
}

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")
config_root <- get_env_path("CONFIG_DIR", if (dir.exists("configuration")) "configuration" else "config")
config_dirs <- unique(c(config_root, "configuration", "config"))

read_table_auto <- function(path) {
  if (grepl("\\.parquet$", path, ignore.case = TRUE)) {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Package 'arrow' is required to read parquet files.")
    }
    return(setDT(arrow::read_parquet(path)))
  }
  setDT(readRDS(path))
}

load_latest_fi_grid <- function(search_roots) {
  candidates <- character(0)
  for (root in search_roots) {
    if (!dir.exists(root)) {
      next
    }
    candidates <- c(
      candidates,
      list.files(root, pattern = "^fi_grid_.*\\.(parquet|rds)$", full.names = TRUE)
    )
  }
  if (length(candidates) == 0) {
    stop("No fi_grid_*.parquet or fi_grid_*.rds found in OUTPUT_DIR (default: output_V6/).")
  }

  candidates <- candidates[order(file.info(candidates)$mtime, decreasing = TRUE)]
  for (path in candidates) {
    dt <- tryCatch(read_table_auto(path), error = function(e) NULL)
    if (!is.null(dt)) {
      return(list(path = path, data = dt))
    }
  }

  stop("Could not read any fi_grid candidate.")
}

load_fi_defaults <- function() {
  yaml_candidates <- unique(c(
    file.path(config_dirs, "fi_parameters_with_freshness.yaml"),
    file.path(config_dirs, "fi_parameters.yaml")
  ))
  yaml_path <- yaml_candidates[file.exists(yaml_candidates)][1]
  if (is.na(yaml_path)) {
    return(list(source = NA_character_, alpha_dep = 0.25))
  }

  params_raw <- yaml::read_yaml(yaml_path)
  if (!is.null(params_raw$scenarios$default)) {
    par <- params_raw$scenarios$default
  } else if (!is.null(params_raw$default)) {
    par <- params_raw$default
  } else {
    par <- params_raw
  }

  list(
    source = yaml_path,
    alpha_dep = if (!is.null(par$alpha_dep)) as.numeric(par$alpha_dep) else 0.25
  )
}

check_equal <- function(lhs, rhs, tol = 1e-8) {
  ok <- is.na(lhs) & is.na(rhs)
  ok <- ok | (is.finite(lhs) & is.finite(rhs) & abs(lhs - rhs) <= tol)
  ok
}

diagnostics <- vector("list", 0)
add_check <- function(check_id, severity, status, detail) {
  diagnostics[[length(diagnostics) + 1L]] <<- data.table(
    check_id = check_id,
    severity = severity,
    status = status,
    detail = detail
  )
}

t0 <- proc.time()[["elapsed"]]
cat("=== fi_grid consistency audit ===\n")

fi_obj <- load_latest_fi_grid(unique(c(output_root, "output_V6")))
fi_dt <- fi_obj$data
cat(sprintf("Loaded fi_grid: %s\n", fi_obj$path))
cat(sprintf("Rows: %d | Cols: %d\n", nrow(fi_dt), ncol(fi_dt)))

fi_defaults <- load_fi_defaults()
alpha_dep_used <- if (!is.na(alpha_dep_override)) alpha_dep_override else fi_defaults$alpha_dep
cat(sprintf("alpha_dep used for p_l_eff reconstruction: %.6f\n", alpha_dep_used))
if (!is.na(fi_defaults$source)) {
  cat(sprintf("Parameter YAML: %s\n", fi_defaults$source))
} else {
  cat("Parameter YAML not found; using alpha_dep fallback = 0.25\n")
}

core_required <- c("grid_id", "SVR", "p_l_eff", "fresh_fact", "k_used", "p_l_corr", "f_i_full")
missing_core <- setdiff(core_required, names(fi_dt))
if (length(missing_core) == 0) {
  add_check("required_core_columns", "critical", "PASS", "All core fi_grid columns are present.")
} else {
  add_check(
    "required_core_columns",
    "critical",
    "FAIL",
    paste("Missing core columns:", paste(missing_core, collapse = ", "))
  )
}

depth_cols <- c("p_l", "p_d")
missing_depth <- setdiff(depth_cols, names(fi_dt))
if (length(missing_depth) == 0) {
  add_check("depth_inputs_available", "warning", "PASS", "p_l and p_d are available for alpha_dep replay.")
} else {
  add_check(
    "depth_inputs_available",
    "warning",
    "WARN",
    paste("Missing depth inputs:", paste(missing_depth, collapse = ", "))
  )
}

if ("grid_id" %in% names(fi_dt)) {
  dup_n <- fi_dt[, .N, by = grid_id][N > 1L, sum(N - 1L)]
  if (is.na(dup_n) || dup_n == 0L) {
    add_check("grid_id_unique", "critical", "PASS", "grid_id is unique.")
  } else {
    add_check("grid_id_unique", "critical", "FAIL", sprintf("Duplicate grid_id rows detected: %d", dup_n))
  }
}

non_negative_cols <- intersect(
  c("SAR", "p_d", "p_l", "p_l_eff", "SVR", "fresh_fact", "k_used", "p_l_corr", "f_i_full", "f_i_conservative"),
  names(fi_dt)
)
if (length(non_negative_cols) > 0) {
  neg_counts <- vapply(
    non_negative_cols,
    function(col) sum(is.finite(fi_dt[[col]]) & fi_dt[[col]] < 0),
    numeric(1)
  )
  bad_cols <- names(neg_counts)[neg_counts > 0]
  if (length(bad_cols) == 0) {
    add_check("non_negative_fields", "critical", "PASS", "Checked fields are non-negative.")
  } else {
    add_check(
      "non_negative_fields",
      "critical",
      "FAIL",
      paste(sprintf("%s=%d", bad_cols, neg_counts[bad_cols]), collapse = " | ")
    )
  }
}

if (all(c("p_l", "p_d", "p_l_eff") %in% names(fi_dt))) {
  p_d_safe <- fifelse(is.finite(fi_dt$p_d) & fi_dt$p_d > 0, fi_dt$p_d, 1.0)
  w1_v <- pmin(0.05, p_d_safe) / p_d_safe
  w2_v <- pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe
  p_l_eff_expected <- w1_v * fi_dt$p_l + w2_v * fi_dt$p_l * alpha_dep_used
  mismatch_n <- sum(!check_equal(fi_dt$p_l_eff, p_l_eff_expected, tol = 1e-8), na.rm = TRUE)
  if (mismatch_n == 0L) {
    add_check("p_l_eff_formula", "critical", "PASS", "p_l_eff matches the depth-weighted alpha_dep formula.")
  } else {
    add_check(
      "p_l_eff_formula",
      "critical",
      "FAIL",
      sprintf("Rows failing p_l_eff reconstruction: %d", mismatch_n)
    )
  }
}

if (all(c("p_l_eff", "fresh_fact", "p_l_corr") %in% names(fi_dt))) {
  p_l_corr_expected <- fi_dt$p_l_eff * fi_dt$fresh_fact
  mismatch_n <- sum(!check_equal(fi_dt$p_l_corr, p_l_corr_expected, tol = 1e-8), na.rm = TRUE)
  if (mismatch_n == 0L) {
    add_check("p_l_corr_formula", "critical", "PASS", "p_l_corr matches p_l_eff * fresh_fact.")
  } else {
    add_check(
      "p_l_corr_formula",
      "critical",
      "FAIL",
      sprintf("Rows failing p_l_corr reconstruction: %d", mismatch_n)
    )
  }
}

if (all(c("f_i_full", "f_i_conservative") %in% names(fi_dt))) {
  bad_n <- sum(
    is.finite(fi_dt$f_i_full) &
      is.finite(fi_dt$f_i_conservative) &
      fi_dt$f_i_conservative > fi_dt$f_i_full + 1e-8
  )
  if (bad_n == 0L) {
    add_check("conservative_le_full", "warning", "PASS", "f_i_conservative never exceeds f_i_full.")
  } else {
    add_check(
      "conservative_le_full",
      "warning",
      "WARN",
      sprintf("Rows with f_i_conservative > f_i_full: %d", bad_n)
    )
  }
}

if ("f_i_full" %in% names(fi_dt)) {
  out_of_bounds <- sum(is.finite(fi_dt$f_i_full) & (fi_dt$f_i_full < 0 | fi_dt$f_i_full > 1))
  if (out_of_bounds == 0L) {
    add_check("fi_full_bounds", "critical", "PASS", "f_i_full remains within [0, 1].")
  } else {
    add_check(
      "fi_full_bounds",
      "critical",
      "FAIL",
      sprintf("Rows with f_i_full outside [0, 1]: %d", out_of_bounds)
    )
  }
}

sum_fi <- if ("f_i_full" %in% names(fi_dt)) sum(fi_dt$f_i_full, na.rm = TRUE) else NA_real_
sum_svr <- if ("SVR" %in% names(fi_dt)) sum(fi_dt$SVR, na.rm = TRUE) else NA_real_
if (is.finite(sum_fi) && is.finite(sum_svr) && sum_fi > 0 && sum_svr > 0) {
  add_check(
    "aggregate_totals",
    "critical",
    "PASS",
    sprintf("sum(SVR)=%.6e | sum(f_i_full)=%.6e", sum_svr, sum_fi)
  )
} else {
  add_check(
    "aggregate_totals",
    "critical",
    "FAIL",
    sprintf("Non-finite or non-positive totals: sum(SVR)=%.6e | sum(f_i_full)=%.6e", sum_svr, sum_fi)
  )
}

diag_dt <- rbindlist(diagnostics, fill = TRUE)
out_dir <- file.path(output_root, "diagnostics")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

checks_csv <- file.path(out_dir, "fi_grid_consistency_checks.csv")
fwrite(diag_dt, checks_csv)

critical_fail <- diag_dt[severity == "critical" & status == "FAIL"]
warn_n <- nrow(diag_dt[status == "WARN"])
pass_n <- nrow(diag_dt[status == "PASS"])
fail_n <- nrow(diag_dt[status == "FAIL"])
runtime_sec <- proc.time()[["elapsed"]] - t0

summary_lines <- c(
  "fi_grid consistency audit",
  sprintf("fi_grid_path: %s", fi_obj$path),
  sprintf("rows: %d", nrow(fi_dt)),
  sprintf("alpha_dep_used: %.6f", alpha_dep_used),
  sprintf("checks_pass: %d", pass_n),
  sprintf("checks_warn: %d", warn_n),
  sprintf("checks_fail: %d", fail_n),
  sprintf("runtime_sec: %.2f", runtime_sec),
  sprintf("status: %s", if (nrow(critical_fail) == 0L) "PASS" else "FAIL")
)
summary_txt <- file.path(out_dir, "fi_grid_consistency_summary.txt")
writeLines(summary_lines, summary_txt, useBytes = TRUE)

cat(sprintf("Saved: %s\n", checks_csv))
cat(sprintf("Saved: %s\n", summary_txt))

if (nrow(critical_fail) > 0L) {
  print(critical_fail)
  stop("fi_grid consistency audit failed on at least one critical check.")
}

cat("All critical fi_grid consistency checks passed.\n")
