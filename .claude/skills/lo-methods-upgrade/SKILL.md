---
name: lo-methods-upgrade
description: >
  Upgrades the dredging footprint pipeline to meet L&O:Methods publication standards.
  Addresses 9 gaps: benchmarking (with CI regression detection), OAT+Sobol sensitivity,
  independent validation, GUM Monte Carlo uncertainty, runtime limitation warnings,
  limitations documentation, FAIR reproducibility (CITATION.cff, codemeta.json,
  Apptainer container, strict immutable-DOI data statement). Modes: audit, quick-wins,
  benchmarking, sensitivity, uncertainty, validation, reproducibility, full. Triggers:
  "publication ready", "lo-methods upgrade", "journal upgrade", "l&o methods",
  "publication gap", "/lo-methods-upgrade".
---

# lo-methods-upgrade

Upgrade the dredging footprint pipeline to meet **Limnology & Oceanography: Methods**
publication standards. Targets the 6 critical gaps identified in `LO_METHODS_GAP_ANALYSIS.md`
by generating ready-to-run scripts, SLURM wrappers, and documentation. All outputs follow
CLAUDE.md conventions (lowercase underscores, correct directories, no version suffixes).

---

## Inputs

Parse the user's command to determine:

- **`mode`**: which gap(s) to address — one of:
  - `audit` — read-only; produce a traffic-light readiness report (no scripts written)
  - `quick-wins` — 4 files that can be completed in ≤1 week using existing logic
  - `benchmarking` — baseline comparison scripts and protocol documentation
  - `sensitivity` — one-at-a-time (OAT) parameter sweep + tornado plot
  - `uncertainty` — Monte Carlo error propagation (500 iterations)
  - `validation` — independent data + synthetic ground-truth validation
  - `reproducibility` — FAIR package: CITATION.cff, codemeta.json, CI workflow, docs
  - `full` — run all modes (quick-wins → benchmarking → sensitivity → uncertainty → validation → reproducibility)
  - Default: `full`

- **`step`**: optional pipeline step to focus on (e.g., `3`, `5`, `all`). Default: `all`.

- **`cluster`**: `beluga` | `grit`. Controls SLURM headers emitted in `.sh` scripts.
  Default: `grit` (emlab_nodes partition, user `bloe`).

---

## Phase 0 — Repo Snapshot & Authoritative File Reading (MANDATORY)

**Before generating any script or file**, read every file below using the Read tool.
For each: extract algorithm parameters, variable names, output column schemas, and
comment blocks explaining design decisions. Log missing files gracefully.

Run in parallel where possible:

```
git log -1 --oneline
git branch --show-current
ls output_V6/ | head -30
```

### Step 0 — Core Window Selection
- `pipeline_V6/pipeline_V6/step0_core_window_enhanced.R`
- `pipeline_V6/pipeline_V6/step0_window_select_grit.sh`
- `pipeline_V6/pipeline_V6/step0_window_select.sh`

Extract: temporal window logic, coverage matrix structure, vessel-day thresholds,
how "core window" handles AIS coverage gaps.

### Step 1 — Split AIS Data by Vessel
- `pipeline_V6/pipeline_V6/step1_split_navires.R`
- `pipeline_V6/pipeline_V6/step1_split_navires.sh`

Extract: MMSI splitting strategy, output file format (parquet/rds), memory management.

### Step 2 — Per-Vessel Track Processing & Filtering
- `pipeline_V6/pipeline_V6/step2_process_navire.R`
- `pipeline_V6/pipeline_V6/step2_process_array.sh`
- `configuration/outlier_config_V6.yaml`
- `scripts_principaux/visualize_step2_zoom_land_filtering.R`

Extract: Isolation Forest contamination rate, n_estimators, speed/acceleration filter
thresholds, near-coast exclusion radius, land-crossing detection logic, delta-t outlier
rules, YAML config loading pattern, meaning of `flagOK` column.

### Step 3 — Merge Vessels, GMM, DBSCAN Clustering
- `pipeline_V6/pipeline_V6/step3_merge_final.R`
- `pipeline_V6/pipeline_V6/step3_merge_final_grit.sh`

Extract: GMM component count selection (BIC/AIC), feature names fed to GMM (speed,
heading change, delta-t), DBSCAN eps and minPts values, cluster → dredging/transit
mapping, the exact variable name used for AUC per fold, output column schema,
RDS glob pattern for gridsearch results.

### Step 4 — Add Lithology from dbSEABED
- `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.R`
- `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.sh`
- `pipeline_V6/pipeline_V6/prefetch_hubocean_stac.py`
- `pipeline_V6/pipeline_V6/download_dbseabed_raw.py`
- `configuration/ship_specs.yaml`

Extract: HubOcean STAC API fetch pattern, spatial join strategy, lithology columns
retained, H_index derivation, ship_specs.yaml structure (beam, hopper volume,
sweep width), how vessel specs feed penetrability.

### Step 5 — Compute fi on Global Grid
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_make_tiles.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_tile_worker.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_tile_job.sh`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_merge_tiles.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/constants.R`
- `pipeline_V6/step5_merge_tiles_optimized.R`
- `constants.R`
- `scripts_principaux/diagnostic_step5_hotspots.R`
- `scripts_principaux/diagnostic_step5_projection.R`

Extract: grid resolution (confirm 0.25° or other), EPSG:6933 rationale, SAR formula,
tiling strategy (number of tiles, buffer overlap), land mask approach, ocean fraction
computation, basin-level k_fast assignment, fi numerical definition, output format,
`BUFFER_TEST_VALUES` array (exact name and values).

### Step 6 — CRI Calculation
- `pipeline_V6/pipeline_V6/step6_calculate_cri.R`
- `scripts_cluster/step6_calculate_cri_grit.sh`
- `pipeline_V6/pipeline_V6/check_step6_for_ocim.R`

Extract: CRI formula (pl_base × H_index × SAR?), seabed vulnerability weighting,
output column names (`C_ri`, `C_ri_lower`, `C_ri_upper` — confirm exact names),
grid dimensions.

### Step 7 — Export Jdredge for OCIM
- `scripts_cluster/step7_export_jtrawl_grit.sh`
- `step7_extract_ocim_cache.py`
- `step7_extract_ocim_cache.m`
- `scripts_cluster/run_step7_diagnostics.sh`
- `scripts_cluster/step7_check_inputs.sh`

Extract: remapping from 0.25° → OCIM2-48L (91×180×48), conservative remapping
algorithm, K_MAX shelf redistribution, Jdredge units, amplified scenario logic
(10×, 100×), conservation diagnostic checks.

### CO₂ Model & Post-processing
- `Trawling model-20250623T085752Z-1-001/Trawling model/co2model.m`
- `scripts_cluster/co2model_batch_grit.sh`
- `pipeline_V6/extract_dredging_timeseries.py`

Extract: OCIM2-48L transport matrix T structure, Jdredge injection point, GMRES
settings, DIC → pCO₂ chain (CO2SYS), Atwood carbon stock normalization, 2012
temporal start rationale, netemission.txt structure.

### Configuration & Constants
- `constants.R`
- `configuration/outlier_config_V6.yaml`
- `configuration/ship_specs.yaml`
- Any fi-parameters YAML in `configuration/` (search for `fi_parameters` or
  `alpha_dep`, `fast_fraction`, `slow_k`, `preservation_factor`, `k_fast_global_mean`)
- `CITATION.cff`
- `configuration/codemeta.json` (may not exist — log if missing)

Extract: `BUFFER_TEST_VALUES` array, all fi parameter names and default values,
all global constants, YAML loading pattern, CITATION.cff placeholder fields.

### Build the internal data dictionary

After reading all files, record these values for use in all subsequent phases:

```
PARAM_NAMES        ← exact parameter names from fi_parameters YAML (or constants.R)
BUFFER_VALUES      ← BUFFER_TEST_VALUES array from constants.R
AUC_VAR_NAME       ← exact variable name for AUC per fold in step3 (e.g., auc_fold)
GRIDSEARCH_RDS     ← file glob pattern for step3 gridsearch results RDS
CRI_COLS           ← output column names for CRI (C_ri + uncertainty cols)
FI_GRID_COLS       ← column names in fi_grid parquet output
SLURM_PARTITION    ← "emlab_nodes" (grit) or "def-account" (beluga)
SLURM_ACCOUNT      ← exact --account= value from existing .sh scripts
SLURM_USER         ← "bloe" (grit) or "benl" (beluga) from cluster mode
GRID_RES_DEG       ← grid resolution in degrees (e.g., 0.25)
EPSG_CODE          ← projection used (likely 6933)
```

All generated scripts **must** use the exact names extracted above. Never invent
parameter names, column names, or file paths.

---

## Phase 0b — Gap Inventory (always run before any mode)

After reading all files, produce a traffic-light table in the console:

```
Gap                               | Status  | Evidence
----------------------------------|---------|------------------------------------------
1.  Benchmarking vs baselines     | ❌/⚠️/✅ | [file or "not found"]
2.  CI performance regression     | ❌/⚠️/✅ | pipeline_ci.yml has benchmark job?
3.  OAT sensitivity analysis      | ❌/⚠️/✅ | [file or "not found"]
4.  Global sensitivity (Sobol)    | ❌/⚠️/✅ | sensitivity_sobol.R exists?
5.  Independent validation        | ❌/⚠️/✅ | [file or "not found"]
6.  Uncertainty propagation (GUM) | ❌/⚠️/✅ | [file or "not found"]
7.  Runtime limitation warnings   | ❌/⚠️/✅ | pipeline_warnings.R exists and sourced?
8.  Limitations documentation     | ❌/⚠️/✅ | [file or "not found"]
9.  FAIR reproducibility          | ❌/⚠️/✅ | CITATION.cff, codemeta, Apptainer, strict DAS?
```

Legend: ✅ = exists and complete, ⚠️ = partial, ❌ = missing entirely.

If `mode=audit`, stop here and write the report (see Phase 7). Otherwise continue
to the requested mode phase(s).

---

## Phase 1 — `quick-wins` mode

Four files that leverage logic already present in the repo (≤1 week to execute).

### File 1: `scripts_principaux/extract_step3_auc_metrics.R`

Purpose: reads gridsearch RDS produced by step3, extracts AUC per LOYO fold, prints
mean ± SD, saves `output_V6/step3_auc_metrics.csv`.

Requirements:
- Use `GRIDSEARCH_RDS` glob to find the RDS (handle multiple matches by picking most recent)
- Extract `AUC_VAR_NAME` column (exact name from data dictionary)
- Compute mean, SD, min, max across folds
- Print formatted summary: `"Step 3 LOYO AUC: mean=X.XXX, SD=X.XXX (N folds)"`
- Save CSV with columns: fold_id, auc, model_config
- Do not hard-code any file path — derive from `output_V6/` glob

### File 2: `scripts_cluster/submit_buffer_sensitivity.sh`

Purpose: SLURM array job (5 tasks) that sets `BUFFER_IDX` to each value in
`BUFFER_VALUES` and calls the step5 tile job, so the effect of buffer size on SAR
output can be assessed as a parameter uncertainty bound.

Requirements:
- Use `--array=1-N` where N = length(`BUFFER_VALUES`)
- Set `BUFFER_KM=${BUFFER_VALUES[$SLURM_ARRAY_TASK_ID - 1]}` and export it
- Call the step5 tile job script with output tagged by BUFFER_KM
- Use `SLURM_PARTITION`, `SLURM_ACCOUNT`, `SLURM_USER` from data dictionary
- 8G RAM, 2h time limit per task (buffer sweep is lightweight)
- Log to `logs/buffer_sensitivity_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out`

### File 3: `scripts_principaux/compare_scenarios.R`

Purpose: loads the three existing fi_grid parquet files (default, conservative,
upper_bound), computes % difference per cell, generates a map and global totals table.
This reframes the 3 existing scenarios as parameter uncertainty bounds.

Requirements:
- Load with `arrow::read_parquet()` using column selection (only grid coords + fi/C_ri)
- Compute: `pct_diff_conservative = (default - conservative) / default * 100`
- Compute: `pct_diff_upper = (upper_bound - default) / default * 100`
- Global totals table: total_fi (sum over ocean cells), total_C_ri, per scenario
- Map: use `ggplot2` + `sf` world coastline; fill = pct_diff_upper; viridis palette
- Save map to `output_V6/scenario_comparison_map.png`
- Save table to `output_V6/scenario_comparison_totals.csv`
- Use `FI_GRID_COLS` and `CRI_COLS` from data dictionary for column names

### File 4: `tests/test_failure_modes.R`

Purpose: documents the 4 main pipeline failure modes using the **`testthat`** framework
(not bespoke print statements). `testthat` integrates natively with GitHub Actions CI
and produces standardised JUnit XML output that reviewers and journal reproducibility
checkers trust.

Requirements:
- Use `library(testthat)` at the top; wrap every test in `test_that("name", { … })`
- Use `testthat::expect_true()`, `expect_false()`, `expect_no_error()`, `expect_warning()`
  — never raw `if / cat("PASS")` logic
- Run all tests with `testthat::test_file("tests/test_failure_modes.R")` from project root
- Each test must complete in < 60 seconds total; use `testthat::skip_if()` for
  tests that require data files not present in CI

Four test cases:

1. **`test_that("sparse data guard", …)`**: generate synthetic vessel track with < 100
   pings; expect step2's `min_points_per_vessel` guard to emit a warning or return NULL
   rather than crashing. If no guard exists in `step2_process_navire.R`, the test must
   `fail("Missing guard: add min_points_per_vessel check")`.

2. **`test_that("SAR is finite for single-cell input", …)`**: all pings in one 1-km grid
   cell; compute SAR inline (without calling shell scripts); `expect_true(is.finite(SAR))`.

3. **`test_that("Isolation Forest accepts extreme contamination", …)`**: set
   `contamination_rate = 0.50` in a temporary in-memory YAML; source the minimum IF
   logic from step2; `expect_no_error(…)`.

4. **`test_that("Arctic pings do not land on land cells", …)`**: generate pings at
   lat > 75°N; project to EPSG:6933; snap to 1-km grid; `expect_true(all(ocean_frac > 0))`
   (or `expect_true(nrow(result) == 0)` if the land mask correctly excludes them).

Additional requirements:
- At top of file, source only the helper functions needed (not full pipeline)
- `testthat::reporter = "progress"` for readable CLI output
- Save JUnit XML: `testthat::test_file(…, reporter = testthat::JunitReporter$new(file = "output_V6/test_results.xml"))`
- `pipeline_ci.yml` must install `testthat` and call `Rscript tests/test_failure_modes.R`; the job fails automatically if any `test_that` block fails

---

## Phase 2 — `benchmarking` mode

### File 1: `scripts_principaux/benchmark_vs_baseline.R`

Purpose: compare step3 GMM+DBSCAN against two naive dredging-detection baselines on the
same AIS subset. Compute F1, precision, recall, AUC per method.

Requirements:
- Load the step3 output (parquet) for a representative subset (1 month, 1 region)
- Use `flagOK` as ground truth label (or the dredging cluster label — use `AUC_VAR_NAME`
  to identify the correct column)
- **Baseline 1 — Speed threshold**: classify ping as dredging if speed_knots < 3.0.
  Compute confusion matrix vs step3 label.
- **Baseline 2 — GFW-style fishing hours proxy**: classify as dredging if speed < 3.0
  AND heading_change_deg < 45 (straight slow movement). Compute confusion matrix.
- **Step 3 method**: use the existing classification (cluster label from step3 output).
  This is the "oracle" method — compute metrics relative to any available ground truth.
- Compute for each method: precision, recall, F1 (macro + weighted), AUC-ROC if
  probability scores are available.
- Save `output_V6/benchmarking_results.csv` with columns:
  method, precision, recall, f1_macro, f1_weighted, auc, n_dredging, n_transit
- Generate comparison bar plot saved to `output_V6/benchmarking_comparison.png`
- At top of script: comment block explaining why these baselines were chosen and
  their known limitations (speed threshold ignores heading; GFW proxy is fishing-tuned)

### File 2: `scripts_cluster/submit_benchmark_array.sh`

Purpose: run benchmark on full dataset via SLURM.

Requirements:
- `--partition=SLURM_PARTITION`, `--account=SLURM_ACCOUNT`
- 32G RAM, 4h, 4 CPUs
- Single job (not array — benchmark is sequential across methods)
- Module load R or apptainer as per cluster convention in existing `.sh` scripts

### File 3: `documentation/BENCHMARKING_PROTOCOL.md`

Structure:
```markdown
# Benchmarking Protocol

## Methods compared
[Table: method name | description | key assumption | reference if applicable]

## Dataset
[What AIS subset is used, date range, region, vessel count]

## Metrics
[Definition of F1, precision, recall, AUC as used here]

## How to run
[2–3 bash commands]

## How to interpret for L&O:Methods reviewers
[1 paragraph: what does it mean if step3 outperforms baselines by X%?]

## Known limitations of this benchmarking approach
[3–5 bullet points: no ground truth labels, label leakage risk, etc.]
```

---

## Phase 3 — `sensitivity` mode

Full one-at-a-time (OAT) parameter sweep.

### File 1: `configuration/sensitivity_manifest.csv`

A CSV with exactly 55 rows (5 parameters × 11 values each) mapping SLURM
`ARRAY_TASK_ID` to `(parameter_name, parameter_value)`.

Format:
```csv
task_id,parameter_name,parameter_value,value_label
1,PARAM1,-50%,param1_m50
2,PARAM1,-40%,param1_m40
...
11,PARAM1,+50%,param1_p50
12,PARAM2,-50%,param2_m50
...
55,PARAM5,+50%,param5_p50
```

Use the 5 key fi parameters from `PARAM_NAMES` (from data dictionary). The 11 values
per parameter are the default value × {0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.10, 1.20,
1.30, 1.40, 1.50}. Record the **absolute value** in `parameter_value`, not the multiplier.

**If fi_parameters YAML is not found**: use `constants.R` to identify the 5 most
impactful constants (those used in the fi or CRI formula). Log the substitution.

### File 2: `scripts_principaux/sensitivity_oat_analysis.R`

Purpose: run step5+step6 on a 3×3 tile test region for each row of the manifest,
record global C_ri.

Requirements:
- Accept `TASK_ID` from command-line arg: `args <- commandArgs(trailingOnly=TRUE)`
- Read `configuration/sensitivity_manifest.csv`, subset row `TASK_ID`
- Override the relevant parameter in memory (do NOT modify YAML on disk)
- Run step5 tile computation on a 3×3 test region (hardcode a low-activity region:
  e.g., 10°N–12.5°N, 60°E–62.5°E — Indian Ocean open water)
- Record: task_id, parameter_name, parameter_value, global_C_ri_sum, runtime_sec
- Append to `output_V6/sensitivity/oat_results.csv` (create if missing)
- Handle missing output directory with `dir.create(..., recursive = TRUE)`

### File 3: `scripts_principaux/plot_sensitivity_tornado.R`

Purpose: reads `oat_results.csv`, produces tornado plot.

Requirements:
- For each parameter: compute output range = (max C_ri - min C_ri) / baseline C_ri × 100%
- Sort parameters by output range (descending)
- Tornado plot: horizontal bars, one color for +50% perturbation, one for -50%
- x-axis: "% change in global C_ri from baseline"
- Save to `output_V6/sensitivity/tornado_plot.png` (300 dpi, 8×5 inches)
- Also save `output_V6/sensitivity/tornado_data.csv` for manuscript tables

### File 4: `scripts_cluster/submit_sensitivity_array.sh`

Purpose: SLURM `--array=1-55` job running sensitivity_oat_analysis.R.

Requirements:
- `--array=1-55 --ntasks=1 --cpus-per-task=2 --mem=8G --time=0:30:00`
- Pass `$SLURM_ARRAY_TASK_ID` as CLI argument: `Rscript --vanilla scripts_principaux/sensitivity_oat_analysis.R $SLURM_ARRAY_TASK_ID`
  (NOT via `-e "args <- ...; source()"` — `commandArgs()` ignores pre-set R objects)
- GRIT conventions: `--chdir=/home/bloe/ais-pipeline/pipeline_V6`, `--exclude=hpc-08.grit.ucsb.edu`
- Usage comment must say: `sbatch --partition=emlab_nodes scripts_cluster/submit_sensitivity_array.sh`
- Output to `~/scratch/output_V6/sensitivity/` when `~/scratch` exists (GRIT NFS scratch)
- After array completes, submit tornado job as dependent: `sbatch --partition=emlab_nodes --dependency=afterok:$ARRAY_JOB_ID --wrap="Rscript --vanilla scripts_principaux/plot_sensitivity_tornado.R"`

### File 5 (optional, recommended): `scripts_principaux/sensitivity_sobol.R`

Purpose: Global Sensitivity Analysis using Sobol indices, which captures
parameter interaction effects that OAT misses (e.g., if `fast_fraction` and
`k_fast_multiplier` interact multiplicatively in the fi formula).

When to generate: always describe it; generate the file if the user explicitly
requests global sensitivity, or if OAT tornado shows two parameters with nearly
equal ranges (suggesting confounding).

Requirements:
- Use the `sensitivity` R package (`sobolSalt()` or `sobol2002()`)
- Analyse the same 5 fi parameters as OAT, over their ±50% range
- Sample size: 1000 base samples × 2 matrices = 2000 model evaluations
  (run on GRIT as a single job, ~16G, 1h)
- Report: first-order Sobol index (S1) and total-effect index (ST) per parameter
- Interpret: parameters with ST >> S1 have significant interaction effects
- Save results to `output_V6/sensitivity/sobol_indices.csv`
- Generate bar chart: `output_V6/sensitivity/sobol_plot.png` (S1 in solid, ST in hatched)
- Add caveat: "Sobol analysis is performed on a scalar test-region proxy for C_ri;
  full-grid Sobol would require ~10,000 model evaluations and is not done here."

---

## Phase 4 — `uncertainty` mode

Monte Carlo error propagation (500 iterations, parallelised as 10×50).

### File 1: `scripts_principaux/monte_carlo_uncertainty.R`

Purpose: propagate three sources of uncertainty through fi and C_ri for a subset
of tiles.

Requirements:
- Accept `BATCH_ID` (1–10) from command-line args → run iterations
  `((BATCH_ID-1)*50+1):(BATCH_ID*50)`
- Load step4 output (parquet) for the same 3×3 test region as sensitivity
- Per iteration:
  1. **AIS position error**: perturb lat/lon by Gaussian(0, 30m) → re-snap to grid cell
  2. **Dredging classification error**: for each ping, flip label with probability
     `(1 - LOYO_AUC)` (use AUC from `output_V6/step3_auc_metrics.csv`)
  3. **fi parameter error**: multiply each parameter in `PARAM_NAMES` by
     `rnorm(1, mean=1, sd=0.10)` independently
  4. Recompute fi and C_ri for the test region
  5. Store per-cell (cell_id, iteration, fi_value, C_ri_value)
- Save batch output to `output_V6/uncertainty/mc_batch_{BATCH_ID}.parquet`
- Seed: `set.seed(BATCH_ID * 42)` for reproducibility

### File 2: `scripts_cluster/submit_monte_carlo.sh`

Purpose: SLURM `--array=1-10` job; after array, merge partial results.

Requirements:
- `--array=1-10 --ntasks=1 --cpus-per-task=4 --mem=16G --time=2:00:00`
- After array: `--dependency=afterok:$ARRAY_JOBID` merge step that:
  1. Reads all `mc_batch_*.parquet` files with `arrow`
  2. Computes per-cell mean, SD, 2.5th percentile, 97.5th percentile across 500 iter
  3. Saves `output_V6/uncertainty/mc_results_summary.parquet` with columns:
     cell_id, lat, lon, fi_mean, fi_sd, fi_p025, fi_p975, C_ri_mean, C_ri_sd,
     C_ri_p025, C_ri_p975
- Log to `logs/mc_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out`

### File 3: `documentation/UNCERTAINTY_BUDGET.md`

Structure:
```markdown
# Uncertainty Budget

## GUM Reference
This analysis follows the Guide to the Expression of Uncertainty in Measurement
(GUM, JCGM 100:2008).

## Sources of uncertainty

| Source | Component affected | Method | Contribution to fi variance (%) |
|--------|--------------------|--------|---------------------------------|
| AIS position error (±30m 1σ) | Cell assignment | Monte Carlo | [from mc_results] |
| Dredging classification (1−AUC) | fi numerator | Monte Carlo | [from mc_results] |
| fi parameter uncertainty (±10%) | fi, C_ri | Monte Carlo | [from mc_results] |
| Land mask boundary ± 1 cell | fi denominator | Not yet quantified | — |
| dbSEABED coverage gaps | H_index | Not yet quantified | — |

## Results
[Fill in from mc_results_summary.parquet after running]

## Final 95% CI estimate
C_ri 95% CI: [p025] – [p975] (relative width: X%)

## Recommendations for manuscript
[2–3 sentences on how to report this in Methods section]
```

---

## Phase 5 — `validation` mode

Two validation pathways: independent data (with API hook) and synthetic ground truth.

### File 1: `tests/validate_with_independent_data.R`

Purpose: framework for comparing pipeline output against an independent AIS period or
a hold-out region.

Requirements:
- Section A — **Hold-out temporal split**: load step3 output, split by year (use last
  available year as hold-out), compare dredging event frequency/location
- Section B — **Global Fishing Watch hook** (requires API key):
  - Check env var `GFW_API_KEY` — if absent, skip with informative message
  - If present: download fishing hours from GFW API for same vessels/period
  - Compute Spearman correlation between GFW fishing hours and pipeline fi per 1° cell
- Section C — **Copernicus Marine Service fallback**:
  - Download public AIS sample (reference URL in comments, do not hard-code actual URL —
    instruct user to set `AIS_SAMPLE_PATH` env var)
  - Run pipeline steps 2–5 on sample, compare output fi distribution to step3 output
- Compute and report: Pearson r, Spearman r, RMSE, fraction of top-20%-intensity cells
  in common (spatial overlap metric)
- Save `output_V6/validation/independent_validation_results.csv`

### File 2: `scripts_principaux/synthetic_validation.R`

Purpose: create synthetic "ground truth" dataset and verify the pipeline recovers it
within ±15%.

Requirements:
- Create 5 virtual dredgers with **known** swept area per day:
  ```
  vessel_id | beam_m | speed_kn | hours_dredging_per_day | region
  V001      | 20     | 2.0      | 16                     | North Sea
  V002      | 15     | 1.5      | 12                     | Persian Gulf
  V003      | 25     | 2.5      | 20                     | South China Sea
  V004      | 18     | 1.8      | 14                     | Bay of Biscay
  V005      | 22     | 2.2      | 18                     | Gulf of Mexico
  ```
- Generate synthetic AIS pings: uniform spacing at `speed_kn * delta_t` intervals,
  with realistic heading variation (random walk ±5°/ping), within a 0.5°×0.5° box
- Known fi per cell = (beam_m × distance_dredged_m) / cell_area_m2 / n_days
- Run steps 5–6 on synthetic data (call functions directly, not shell scripts)
- Compare pipeline fi to known fi per cell
- Pass criterion: |recovered_fi - known_fi| / known_fi < 0.15 for ≥80% of cells
- Log to `output_V6/validation/synthetic_test_results.txt`:
  ```
  PASS/FAIL: vessel V001 — recovered_fi = X.XXX, known = Y.YYY, error = Z.Z%
  ...
  OVERALL: N/5 vessels pass (threshold: 4/5)
  ```

### File 3: `documentation/VALIDATION_PROTOCOL.md`

Structure:
```markdown
# Validation Protocol

## Two validation pathways

### Pathway 1: Independent AIS data
[What dataset, what period, what metric, what threshold counts as passing]

### Pathway 2: Synthetic ground truth
[5 virtual dredgers, known parameters, recovery threshold ±15%]

## Expected performance thresholds
| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Spearman r vs GFW | > 0.6 | AIS vs fishing effort — different activities |
| Synthetic recovery | ±15% | Accounts for grid discretization + AIS gap |
| Spatial overlap (top 20%) | > 50% | Hot-spot consistency |

## How to cite in manuscript
[Template sentence: "Pipeline performance was assessed using..."]

## Limitations of this validation approach
[3–5 bullets: AIS dark targets, label definition mismatch, etc.]
```

---

## Phase 6 — `reproducibility` mode

FAIR compliance package targeting Wiley / L&O:Methods requirements.

### File 1: `CITATION.cff` (update existing)

Read the current `CITATION.cff` first. Then update:
- `authors`: fill in Benjamin LOEFFLER with ORCID if present in the file
  (if field says `XXXX-XXXX-XXXX-XXXX` or is blank, insert a `# TODO: add ORCID` comment)
- `title`: confirm it matches the thesis/paper title
- `version`: set to `"1.0.0"` if placeholder
- `doi`: set to `"10.5281/zenodo.PLACEHOLDER"` with inline comment `# Replace after Zenodo deposit`
- `license`: set to `"MIT"` (or whatever LICENSE file says — check first)
- `keywords`: ensure dredging, AIS, seabed disturbance, carbon cycling, OCIM are present
- `abstract`: add 2-sentence abstract if missing
- Never remove existing fields — only add or update

### File 2: `configuration/codemeta.json` (create new)

Generate a valid CodeMeta v3 JSON (`schema.org/CodeMeta`) with:
```json
{
  "@context": "https://w3id.org/codemeta/3.0",
  "@type": "SoftwareSourceCode",
  "name": "Dredging Footprint Pipeline",
  "description": "[2-sentence description from CITATION.cff abstract]",
  "version": "1.0.0",
  "license": "https://spdx.org/licenses/MIT.html",
  "programmingLanguage": [
    {"@type": "ComputerLanguage", "name": "R"},
    {"@type": "ComputerLanguage", "name": "Python"},
    {"@type": "ComputerLanguage", "name": "MATLAB"}
  ],
  "author": [{"@type": "Person", "givenName": "Benjamin", "familyName": "LOEFFLER",
               "affiliation": {"@type": "Organization", "name": "[from CITATION.cff]"}}],
  "codeRepository": "https://github.com/[OWNER]/[REPO]",
  "identifier": "https://doi.org/10.5281/zenodo.PLACEHOLDER",
  "funder": {"@type": "Organization", "name": "[from CITATION.cff funding if present]"},
  "softwareRequirements": ["R >= 4.2", "Python >= 3.9", "MATLAB R2023a"],
  "releaseNotes": "Initial release accompanying L&O:Methods submission"
}
```
Note: read the GitHub remote URL from `git remote get-url origin` to fill `codeRepository`.

### File 3: `documentation/DATA_AVAILABILITY_STATEMENT.md`

The statement must explicitly separate **three distinct archives** with immutable,
version-pinned identifiers — not just the active GitHub URL. This is a strict
Wiley requirement for L&O:Methods:

```
Archive 1 — Code (exact version used to produce paper figures):
  GitHub tag: https://github.com/BenLFR/Master-thesis-code-/releases/tag/v1.0.0
  Zenodo version DOI: 10.5281/zenodo.XXXXXXX  ← immutable, version-pinned
  (The concept DOI resolves to the latest version; use the version DOI in the manuscript)

Archive 2 — Processed output data (fi_grid, C_ri_grid, mc_results_summary):
  Zenodo dataset DOI: 10.5281/zenodo.YYYYYYY  ← separate dataset record

Archive 3 — Raw AIS data:
  Provider: [NAME] | Licence: [NUMBER] | Contact: [URL]
  (Raw data cannot be shared; pipeline runs on any compliant AIS source)
```

Requirements for the two manuscript variants:

**Variant A (all open)**: must include all three archive DOIs in final form
(no "PLACEHOLDER" strings at submission time).

**Variant B (AIS embargoed)**: archives 1 and 2 must be open; archive 3 is
described with provider contact info. Must state: "Derived outputs sufficient
to reproduce all paper figures are available at [Archive 2 DOI]."

Pre-submission checklist (machine-checkable):
- [ ] No string "PLACEHOLDER" remains in CITATION.cff, codemeta.json, or DATA_AVAILABILITY_STATEMENT.md
- [ ] Zenodo version DOI (not concept DOI) is used in manuscript
- [ ] Archive 2 dataset deposit contains: fi_grid_*.parquet, C_ri_grid_*.parquet, mc_results_summary.parquet
- [ ] Apptainer image SHA256 digest is recorded in ZENODO_INTEGRATION_GUIDE.md

### File 4: `.github/workflows/pipeline_ci.yml`

GitHub Actions workflow with **four jobs including continuous benchmarking**:

**Job 1 — `lint-r`**: unchanged (lintr with 120-char line limit, skip object_name_linter)

**Job 2 — `test-failure-modes`**: upgrade to `testthat`:
- `install.packages(c('data.table', 'yaml', 'testthat'))`
- `Rscript tests/test_failure_modes.R` — job fails automatically if any `test_that` block fails
- Upload JUnit XML artifact: `output_V6/test_results.xml`

**Job 3 — `step3-auc-metrics`**: unchanged

**Job 4 — `continuous-benchmark`** (CRITICAL NEW JOB — must be added):

```yaml
  continuous-benchmark:
    name: Continuous benchmarking
    runs-on: ubuntu-latest
    needs: test-failure-modes
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: '4.3'
      - name: Install benchmark dependencies
        run: |
          Rscript -e "install.packages(c('data.table', 'pROC', 'testthat'),
                       repos='https://cloud.r-project.org')"
      - name: Run synthetic benchmark (CI-sized dataset)
        run: |
          mkdir -p output_V6
          # Runs benchmark_vs_baseline.R on the synthetic CI dataset
          # (real AIS not available in CI; use synthetic_validation data instead)
          Rscript -e "
            Sys.setenv(CI_BENCHMARK = 'true')
            source('scripts_principaux/benchmark_vs_baseline.R')
          " || echo 'No step3 data in CI — benchmark skipped'
      - name: Check for performance regression
        run: |
          Rscript -e "
            if (!file.exists('output_V6/benchmarking_results.csv')) {
              message('No benchmark results — skipping regression check'); quit(status=0)
            }
            library(data.table)
            res <- fread('output_V6/benchmarking_results.csv')
            step3_row <- res[method == 'step3_gmm_dbscan']
            if (nrow(step3_row) == 0) { message('No step3 row'); quit(status=0) }
            # Regression thresholds (fail PR if step3 drops below these)
            if (!is.na(step3_row\$f1_macro) && step3_row\$f1_macro < 0.60)
              stop(sprintf('REGRESSION: step3 F1=%.3f < threshold 0.60', step3_row\$f1_macro))
            if (!is.na(step3_row\$auc) && step3_row\$auc < 0.75)
              stop(sprintf('REGRESSION: step3 AUC=%.3f < threshold 0.75', step3_row\$auc))
            message(sprintf('Benchmark OK: F1=%.3f, AUC=%.3f',
                            step3_row\$f1_macro, step3_row\$auc))
          "
      - name: Store benchmark result as artifact
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-results-${{ github.sha }}
          path: output_V6/benchmarking_results.csv
          if-no-files-found: ignore
      - name: Comment benchmark on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            let body = '## Continuous Benchmark Results\n\n';
            try {
              body += '```csv\n' + fs.readFileSync('output_V6/benchmarking_results.csv','utf8') + '\n```\n';
              body += '\n_Thresholds: F1 ≥ 0.60, AUC ≥ 0.75. PR blocked if step3 drops below these._';
            } catch(e) {
              body += '_No benchmark data available in CI (requires AIS data). Run locally._';
            }
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
```

**Threshold justification comment** (include in the YAML):
```
# F1 ≥ 0.60: minimum acceptable discrimination over random baseline (F1=0.5 for balanced)
# AUC ≥ 0.75: standard "acceptable" threshold per Hosmer & Lemeshow (2000)
# Adjust these after running the full benchmark on real AIS data.
```

### File 5 (NEW): `scripts_principaux/pipeline_warnings.R`

Purpose: **runtime programmatic enforcement of limitations**. Sourced at the start
of step2 and step5. Emits `warning()` (not `stop()`) so the pipeline continues
but reviewers can see when it is operating outside validated scope.

Requirements — implement these 5 runtime checks as named warning functions:

```r
check_ais_coverage_region <- function(dt, lat_col = "Latitude", lon_col = "Longitude") {
  # Warn if >10% of pings are in known low-coverage regions
  pct_arctic  <- mean(abs(dt[[lat_col]]) > 65, na.rm = TRUE)
  pct_southern <- mean(dt[[lat_col]] < -55, na.rm = TRUE)
  if (pct_arctic > 0.10)
    warning(sprintf(
      "[LIMITATION] %.1f%% of pings are in Arctic/Antarctic (|lat|>65°). ",
      pct_arctic * 100,
      "AIS coverage is unreliable here. ",
      "See documentation/LIMITATIONS.md#known-failure-modes."
    ), call. = FALSE)
}

check_vessel_size <- function(specs_dt) {
  # Warn if vessel matched to default/mean specs (unknown vessel)
  n_unknown <- sum(is.na(specs_dt$dredge_width_m) | specs_dt$used_default == TRUE,
                   na.rm = TRUE)
  if (n_unknown > 0)
    warning(sprintf(
      "[LIMITATION] %d vessel(s) not in ship_specs.yaml — using mean TSHD values. ",
      n_unknown,
      "f_i estimates for these vessels are approximate."
    ), call. = FALSE)
}

check_ping_density <- function(dt, mmsi_col = "ssvid", threshold = 100L) {
  # Warn if any vessel has fewer pings than the min_points_per_vessel threshold
  counts <- dt[, .N, by = mmsi_col]
  n_sparse <- sum(counts$N < threshold)
  if (n_sparse > 0)
    warning(sprintf(
      "[LIMITATION] %d vessel(s) have < %d pings (below min_points_per_vessel). ",
      n_sparse, threshold,
      "Isolation Forest classification may be unreliable for these vessels."
    ), call. = FALSE)
}

check_near_coast_exclusion <- function(dt, near_coast_col = "near_coast",
                                        threshold_pct = 0.30) {
  # Warn if a large fraction of pings are excluded by the near-coast filter
  if (near_coast_col %in% names(dt)) {
    pct_excluded <- mean(dt[[near_coast_col]] == TRUE, na.rm = TRUE)
    if (pct_excluded > threshold_pct)
      warning(sprintf(
        "[LIMITATION] %.1f%% of pings excluded by near-coast filter (>%dkm buffer). ",
        pct_excluded * 100, threshold_pct * 100,
        "Estuarine and near-shore dredging is likely underestimated."
      ), call. = FALSE)
  }
}

check_ocim_scope <- function(lat_range) {
  # Warn if Jdredge has very high values at shelf cells (OCIM steady-state caveat)
  if (max(abs(lat_range)) > 70)
    warning(
      "[LIMITATION] Jdredge includes cells at |lat|>70°. ",
      "The OCIM steady-state assumption is weakest in polar regions ",
      "where circulation is highly seasonal.",
      call. = FALSE
    )
}
```

- Source this file at the top of `step2_process_navire.R` and `step5_compute_fi_global.R`
  with: `if (file.exists("scripts_principaux/pipeline_warnings.R")) source("scripts_principaux/pipeline_warnings.R")`
- All warnings use `call. = FALSE` (no confusing traceback for users)
- The warning message must always end with a reference to `documentation/LIMITATIONS.md`
  or the specific failure mode section
- Do NOT use `stop()` — warnings allow the pipeline to complete while logging the boundary condition

### File 6: `deploy/apptainer.def`

Purpose: **containerization** — eliminates dependency hell and guarantees reviewers
can reproduce results without installing R 4.3+, arrow, pROC, sf, etc. manually.
GRIT cluster already uses Apptainer (Singularity-compatible), making this directly
usable on the cluster.

Requirements:
- Base: `rocker/r-ver:4.3` (the same base used in existing step5_tile_job.sh on Beluga)
- Install all R packages used across the pipeline:
  `data.table`, `arrow`, `yaml`, `pROC`, `mclust`, `dbscan`, `sf`, `terra`,
  `ggplot2`, `viridis`, `testthat`, `lintr`, `sensitivity`
- Install Python 3.10 + `geopandas`, `pyarrow`, `requests` (for step7 Python scripts)
- Set `%environment`: `R_LIBS=/usr/local/lib/R/library`
- Include a `%test` block: `Rscript -e "library(data.table); library(arrow); cat('OK\n')"`
- Include `%labels`: `Author Benjamin LOEFFLER`, `Version 1.0.0`, `PipelineSteps 0-7`

Build and push instructions (in file comments):
```bash
# Build (run on system with Apptainer installed — e.g., GRIT login node):
apptainer build deploy/pipeline_v1.0.0.sif deploy/apptainer.def

# Verify:
apptainer test deploy/pipeline_v1.0.0.sif

# Record SHA256 for reproducibility:
sha256sum deploy/pipeline_v1.0.0.sif >> documentation/ZENODO_INTEGRATION_GUIDE.md

# Use in SLURM scripts (add to any .sh job):
# apptainer exec deploy/pipeline_v1.0.0.sif Rscript --vanilla scripts_principaux/sensitivity_oat_analysis.R $SLURM_ARRAY_TASK_ID
```

### File 7 (renumbered): `documentation/LIMITATIONS.md`

```markdown
# Method Limitations

## Fundamental assumptions

1. **AIS completeness**: The pipeline assumes AIS coverage is representative of
   actual dredging activity. Vessels with AIS transponders turned off ("dark targets"),
   vessels below mandatory AIS thresholds (<300 GT), and illegal dredgers are not
   captured.

2. **Speed-based dredging classification**: The GMM+DBSCAN classifier relies on vessel
   kinematics (speed, heading change, inter-ping interval). Vessels performing slow
   transit (e.g., maneuvering in port, waiting at anchor) may be misclassified.

3. **Seabed lithology spatial resolution**: dbSEABED coverage is heterogeneous. In
   data-sparse regions, H_index is interpolated from nearest neighbors, which may
   misrepresent actual substrate type.

4. **Static ship specifications**: Beam and sweep width are taken from a fixed
   ship_specs.yaml lookup. Vessels not in the lookup table receive mean values.
   Changes in vessel configuration over time are not captured.

5. **OCIM steady-state assumption**: The CO₂ perturbation model uses a steady-state
   ocean circulation. Seasonal variability, El Niño events, and long-term circulation
   trends are not represented.

## Known failure modes

| Scenario | Effect | Severity |
|----------|--------|----------|
| AIS ping rate < 1/hour | Track interpolation error > 1 nm | High |
| Vessel < 300 GT | Not in AIS dataset → zero dredging recorded | High |
| Ice-covered regions (lat > 60°N/S) | AIS gaps → underestimated intensity | Medium |
| Dredging in estuaries < 5 km wide | Near-coast filter may exclude valid pings | Medium |
| Identical MMSI on multiple vessels | Vessel identity confusion in step1 | Low-Medium |

## Valid geographic and temporal scope

- **Geographic**: open ocean and coastal waters with reliable AIS coverage (primarily
  SOLAS flag states with mandatory AIS). Coverage is most reliable in European,
  East Asian, and North American waters.
- **Temporal**: valid for the AIS data period used (see step0 core window output).
  Extrapolation beyond this period is not supported without re-running the pipeline.

## Recommended use cases

✅ Global-scale dredging intensity mapping (≥0.25° resolution)
✅ Relative comparison between regions or years
✅ Carbon flux order-of-magnitude estimates for OCIM perturbation
❌ Sub-kilometre dredging event detection
❌ Attribution to specific vessels or operators
❌ Legal/regulatory compliance monitoring
```

### File 6: `documentation/ZENODO_INTEGRATION_GUIDE.md`

```markdown
# Zenodo Integration Guide

## Steps to mint a DOI and connect to this repository

### 1. Enable Zenodo ↔ GitHub integration
1. Go to zenodo.org → Log in → Linked accounts → GitHub
2. Enable the toggle for this repository
3. Zenodo will now auto-create a release record on each GitHub release

### 2. Prepare the release
```bash
# Tag a release
git tag -a v1.0.0 -m "Initial L&O:Methods submission release"
git push origin v1.0.0

# On GitHub: Releases → Draft a new release → select v1.0.0
# Title: "Dredging Footprint Pipeline v1.0.0"
# Description: copy abstract from CITATION.cff
```

### 3. Zenodo mints the DOI automatically
After publishing the GitHub release, Zenodo creates the deposit and mints a DOI
in the format: `10.5281/zenodo.XXXXXXX`

### 4. Update CITATION.cff and codemeta.json
Replace `PLACEHOLDER` in both files with the real Zenodo DOI:
```bash
sed -i 's/zenodo.PLACEHOLDER/zenodo.XXXXXXX/g' CITATION.cff configuration/codemeta.json
git add CITATION.cff configuration/codemeta.json
git commit -m "reproducibility: add Zenodo DOI after deposit"
```

### 5. Update the Data Availability Statement
Fill in the real DOI in `documentation/DATA_AVAILABILITY_STATEMENT.md` and confirm
the Zenodo deposit contains the required files (see checklist below).

## Zenodo deposit checklist

- [ ] `CITATION.cff` present and complete
- [ ] `configuration/codemeta.json` present and valid
- [ ] `README.md` or equivalent present
- [ ] `output_V6/fi_grid_*.parquet` included OR linked to separate dataset deposit
- [ ] `output_V6/C_ri_*.parquet` included OR linked
- [ ] Large data files (>50 MB) separated to a dataset deposit (Zenodo supports up
      to 50 GB per record, but keeping code and data separate is best practice)
- [ ] License file present (MIT recommended for code; CC-BY for data)

## Estimated timeline
- GitHub → Zenodo link setup: 10 minutes
- DOI minting after release: immediate (automated)
- Zenodo curation review: not required for standard deposits
```

---

## Phase 7 — `audit` mode (read-only)

Produce `output_V6/lo_methods_readiness_report.md`. No scripts written — only analysis.

Structure:
```markdown
# L&O:Methods Readiness Report
<!-- Generated by /lo-methods-upgrade mode=audit -->
<!-- Date: YYYY-MM-DD | Git: <hash> | Branch: <branch> -->

## Summary score: N/9 criteria met

## Traffic-light assessment

| L&O:Methods Criterion | Status | Evidence | Effort to close |
|-----------------------|--------|----------|-----------------|
| Benchmarking vs baselines | ❌/⚠️/✅ | [...] | [Low/Med/High] |
| CI performance regression detection | ❌/⚠️/✅ | [...] | [...] |
| OAT sensitivity analysis | ❌/⚠️/✅ | [...] | [...] |
| Global sensitivity (Sobol S1/ST) | ❌/⚠️/✅ | [...] | [...] |
| Independent validation | ❌/⚠️/✅ | [...] | [...] |
| Uncertainty propagation (GUM-style) | ❌/⚠️/✅ | [...] | [...] |
| Runtime limitation warnings | ❌/⚠️/✅ | [...] | [...] |
| Limitations documentation | ❌/⚠️/✅ | [...] | [...] |
| FAIR reproducibility (CITATION.cff / codemeta / Apptainer) | ❌/⚠️/✅ | [...] | [...] |

## Top 3 recommended next actions
1. [Highest priority gap with specific file to create]
2. [Second priority]
3. [Third priority]

## Estimated effort per remaining gap
[Table: gap | files to create | estimated time | cluster needed?]

## Files that already partially address gaps
[List any existing scripts that partially close a gap — to avoid duplicating work]
```

---

## Phase 8 — `full` mode

Run Phases 1–6 in sequence. After each phase completes, print a checkpoint:
```
✓ Phase N complete: [list files created]
  Next: Phase N+1 — [mode name]
```
After all phases, print the consolidated summary (see Output Summary section below).

---

## Output Summary (print after any mode completes)

```
✓ lo-methods-upgrade [mode=MODE] complete

Files created:
  [list each file path created, one per line, with one-line description]

Files updated:
  [list any files modified, e.g. CITATION.cff]

Gap status after this run:
  Benchmarking:             ✅/⚠️/❌
  CI regression detection:  ✅/⚠️/❌
  OAT sensitivity:          ✅/⚠️/❌
  Sobol sensitivity:        ✅/⚠️/❌
  Validation:               ✅/⚠️/❌
  Uncertainty (GUM):        ✅/⚠️/❌
  Runtime warnings:         ✅/⚠️/❌
  Limitations:              ✅/⚠️/❌
  Reproducibility (FAIR):   ✅/⚠️/❌

Next steps:
  1. [Most important action, e.g. "Run submit_buffer_sensitivity.sh on GRIT"]
  2. [Second action]
  3. [Third action]

Invoke /lo-methods-upgrade mode=audit at any time to re-check overall readiness.
```

---

## Safety Rules

- **Read before writing**: always complete Phase 0 file reads before generating
  any script — never invent parameter names or column names
- **Never hard-code file paths**: derive from glob or data dictionary
- **Missing files**: if a file in the manifest is not found, log it gracefully and
  generate the best possible script with a `# TODO: verify path` comment
- **No invented parameters**: if a fi parameter is not found in any config file,
  output a placeholder `PARAM_NOT_FOUND` and ask the user
- **CITATION.cff**: never remove existing fields — only add or update; preserve
  any existing ORCID or DOI even if they look like placeholders (the user may have
  intentionally left them)
- **Cluster scripts**: always derive `SLURM_PARTITION`, `SLURM_ACCOUNT`, and
  module load commands from existing `.sh` scripts — never invent account names
- **GRIT Rscript invocation**: always pass CLI arguments directly:
  `Rscript --vanilla script.R $SLURM_ARRAY_TASK_ID`
  NEVER use `-e "args <- '$ID'; source('script.R')"` — `commandArgs(trailingOnly=TRUE)`
  reads from the actual CLI, not from pre-set R objects; this bug causes immediate exit
- **GRIT output paths**: prefer `~/scratch/output_V6/` when `~/scratch` exists (NFS scratch,
  not home quota). Test with: `if (dir.exists(file.path(path.expand("~"), "scratch")))`.
  Never write large outputs to `~/ais-pipeline/pipeline_V6/output_V6/` on GRIT
- **GRIT SLURM headers**: all scripts must include
  `#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6` and
  `#SBATCH --exclude=hpc-08.grit.ucsb.edu`; usage comments must show
  `sbatch --partition=emlab_nodes` (not bare `sbatch`)
- **No secrets**: do not write API keys, passwords, or tokens into any file;
  always use environment variable references (e.g., `Sys.getenv("GFW_API_KEY")`)
- **Output directories**: always create with `dir.create(..., recursive=TRUE)` before writing
- **Git hygiene**: remind user to add large outputs to `.gitignore` when relevant

---

## Project-Specific Context

- Pipeline: dredging footprint, Steps 0–7 + OCIM CO₂ model (Benjamin LOEFFLER, master thesis)
- Target journal: **Limnology & Oceanography: Methods** (Wiley)
- HPC clusters: GRIT (user `bloe`, `--partition=emlab_nodes`) and Beluga
  (user `benl`, `--account=def-*`)
- Primary language: R (pipeline) + Python (data fetch) + MATLAB (CO₂ model)
- Key output column names: confirm from step3/step5/step6 outputs during Phase 0
- CLAUDE.md conventions: lowercase underscores, no `_FINAL`/`_FIXED` suffixes,
  new scripts → correct directory per type (scripts_principaux, scripts_cluster, etc.)
- Documentation → `documentation/` (UPPERCASE filenames)
- Config → `configuration/`; outputs → `output_V6/`; tests → `tests/`
