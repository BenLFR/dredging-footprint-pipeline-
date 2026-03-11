# Analysis

This folder contains post-pipeline analysis scripts used to benchmark the step 3
classifier, run sensitivity and uncertainty analyses around `f_i` and `C_ri`,
compare scenario outputs, and run lightweight diagnostic checks on published
artifacts.

These scripts are not part of the main production pipeline. They operate on
artifacts already produced by the pipeline, typically written under `OUTPUT_DIR`
(default: `output_V6/`).

Run them from the repository root unless a script documents otherwise.

## Path Conventions

The public branch is cluster-neutral. Analysis scripts should therefore:

- default to repository-relative paths such as `output_V6/`
- accept environment overrides such as `OUTPUT_DIR` and `CONFIG_DIR`
- avoid personal workstation paths, host-specific paths, and hard-coded scratch locations

## Folder Structure

The scripts fall into five groups:

- `benchmark_vs_baseline.R`, `extract_step3_auc_metrics.R`
  Benchmarking and classifier context for step 3 outputs.
- `sensitivity_oat_analysis.R`, `plot_sensitivity_tornado.R`,
  `sensitivity_sobol.R`, `diagnose_sobol_convergence.R`
  Local and global sensitivity analysis around the `f_i` formula.
- `monte_carlo_uncertainty.R`, `diagnose_monte_carlo_convergence.R`
  Monte Carlo uncertainty propagation and convergence checks.
- `compare_scenarios.R`
  Comparison across multiple `fi_grid` scenario outputs.
- `synthetic_validation.R`, `check_fi_grid_consistency.R`
  Internal consistency checks for formula integrity and step 5 outputs.

## Expected Inputs

Most scripts read from `OUTPUT_DIR` if defined, otherwise from `output_V6/`.
Some scripts also look for configuration files under `CONFIG_DIR` if defined,
otherwise under `configuration/` and then `config/`.

Common upstream artifacts:

- `fi_grid_*.parquet` or `fi_grid_*.rds`
- `sensitivity/oat_results.csv`
- `uncertainty/mc_batch_*.parquet`
- `dragage_gridsearch_results_V6_*.rds`
- `AIS_data_core_preprocessed_V6_*_flagOK.rds`

## Recommended Run Order

For the current publication workflow:

1. Run step 3 and export LOYO metrics with `extract_step3_auc_metrics.R`.
2. Run OAT sensitivity with `sensitivity_oat_analysis.R` and plot with
   `plot_sensitivity_tornado.R`.
3. Run `sensitivity_sobol.R`, then `diagnose_sobol_convergence.R`.
4. Run `monte_carlo_uncertainty.R` batches, then `diagnose_monte_carlo_convergence.R`.
5. Run `check_fi_grid_consistency.R` and `synthetic_validation.R` as integrity checks.

## Script Reference

| Script | Purpose | Main inputs | Main outputs | Typical usage |
|---|---|---|---|---|
| `extract_step3_auc_metrics.R` | Extracts LOYO AUC values from the latest step 3 grid-search result. | `dragage_gridsearch_results_V6_*.rds` | `OUTPUT_DIR/step3_auc_metrics.csv` | `Rscript analysis/extract_step3_auc_metrics.R` |
| `benchmark_vs_baseline.R` | Compares the internal step 3 labelling scheme against simple speed-rule baselines. | `AIS_data_core_preprocessed_V6_*_flagOK.rds` | `OUTPUT_DIR/benchmarking_results.csv`, `OUTPUT_DIR/benchmarking_comparison.png` | `Rscript analysis/benchmark_vs_baseline.R <path_to_rds>` |
| `sensitivity_oat_analysis.R` | Runs one OAT task from the sensitivity manifest and recomputes `C_ri` on the full `fi_grid` when available. | sensitivity manifest, fi parameter YAML, `fi_grid_*` | `OUTPUT_DIR/sensitivity/oat_results.csv` and/or `oat_task_XX.csv` | `Rscript analysis/sensitivity_oat_analysis.R 28` |
| `plot_sensitivity_tornado.R` | Aggregates OAT outputs and generates a tornado plot. | `OUTPUT_DIR/sensitivity/oat_results.csv` or `oat_task_*.csv` | `OUTPUT_DIR/sensitivity/tornado_plot.png`, `tornado_data.csv` | `Rscript analysis/plot_sensitivity_tornado.R` |
| `sensitivity_sobol.R` | Runs the published Sobol sensitivity analysis on a synthetic 25-cell proxy. | fi defaults hard-coded in script | `OUTPUT_DIR/sensitivity/sobol_indices.csv`, `sobol_plot.png` | `Rscript analysis/sensitivity_sobol.R` |
| `diagnose_sobol_convergence.R` | Re-runs the synthetic Sobol proxy at several sample sizes to check whether rankings and `ST` values stabilize. | fi parameter YAML if available | `OUTPUT_DIR/diagnostics/sobol_convergence_*.csv`, `sobol_convergence_plot.png` | `Rscript analysis/diagnose_sobol_convergence.R 250,500,1000` |
| `monte_carlo_uncertainty.R` | Runs one Monte Carlo batch for uncertainty propagation through `f_i` and `C_ri`. | `fi_grid_*`, optional `step3_auc_metrics.csv` | `OUTPUT_DIR/uncertainty/mc_batch_XX.parquet` or `.rds` | `Rscript analysis/monte_carlo_uncertainty.R 1` |
| `diagnose_monte_carlo_convergence.R` | Checks whether Monte Carlo summaries stabilize across iterations. | `mc_batch_*` or `mc_results_summary` | `OUTPUT_DIR/diagnostics/mc_iteration_summary.csv`, `mc_convergence_summary.csv`, `mc_convergence_plot.png` | `Rscript analysis/diagnose_monte_carlo_convergence.R 50` |
| `compare_scenarios.R` | Compares three scenario-specific `fi_grid` outputs and maps the spread. | scenario-tagged `fi_grid_*.parquet` or three recent `fi_grid` files | `OUTPUT_DIR/scenario_comparison_totals.csv`, `scenario_comparison_map.png` | `Rscript analysis/compare_scenarios.R` |
| `synthetic_validation.R` | Internal formula integrity check using synthetic dredger cases. This is not an external validation dataset. | none beyond script constants | `OUTPUT_DIR/validation/synthetic_test_results.txt` | `Rscript analysis/synthetic_validation.R` |
| `check_fi_grid_consistency.R` | Audits a published `fi_grid` against the step 5 formula and core schema assumptions. | latest `fi_grid_*`, optional fi parameter YAML | `OUTPUT_DIR/diagnostics/fi_grid_consistency_checks.csv`, `fi_grid_consistency_summary.txt` | `Rscript analysis/check_fi_grid_consistency.R` |

## Important Method Notes

- `sensitivity_sobol.R` is intentionally synthetic and does not represent the
  full global `fi_grid`.
- `synthetic_validation.R` is a formula self-consistency test, not an external
  scientific validation.
- `benchmark_vs_baseline.R` is an internal discriminative comparison against the
  step 3 internal labels, not an absolute accuracy estimate.
- `monte_carlo_uncertainty.R` currently applies classification uncertainty at
  cell level, not at raw ping level.

## Minimal Commands

```bash
Rscript analysis/extract_step3_auc_metrics.R
Rscript analysis/sensitivity_oat_analysis.R 1
Rscript analysis/plot_sensitivity_tornado.R
Rscript analysis/sensitivity_sobol.R
Rscript analysis/diagnose_sobol_convergence.R 250,500,1000
Rscript analysis/monte_carlo_uncertainty.R 1
Rscript analysis/diagnose_monte_carlo_convergence.R 50
Rscript analysis/check_fi_grid_consistency.R
Rscript analysis/synthetic_validation.R
```