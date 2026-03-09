# Benchmarking Protocol

Purpose: detect performance regressions and output-size anomalies across core
pipeline steps.

## Scope

Benchmarked steps:

1. Step 3 merge/classification
2. Step 4 lithology join
3. Step 5 SAR merge
4. Step 6 CRI computation

## Datasets

1. `toy` profile: synthetic data in `data/toy/` (CI-friendly).
2. `staging` profile: fixed, non-public sample held outside the repository.

Each benchmark run must record which profile was used.

## Metrics

For each step, collect:

1. Wall-clock runtime (seconds)
2. Peak memory (GB), when available from scheduler or `/usr/bin/time -v`
3. Input row/cell count
4. Output row/cell count
5. Output file size (bytes)

## Regression thresholds

Default alert thresholds vs baseline:

1. Runtime increase > 20%
2. Peak memory increase > 20%
3. Output row count change > 5% (unless expected by documented method change)
4. Missing expected output artifact

## Execution recipe

1. Prepare deterministic environment:
   - `renv::restore()`
   - `pip install -r requirements.txt`
2. Run the selected step(s) with fixed config and seed where applicable.
3. Export benchmark summary CSV to `output_V6/benchmarks/`.
4. Compare against committed baseline metrics.

## Reporting template

Suggested CSV columns:

1. `run_id`
2. `date_utc`
3. `git_commit`
4. `profile`
5. `step`
6. `runtime_sec`
7. `peak_mem_gb`
8. `n_input`
9. `n_output`
10. `output_bytes`
11. `status`

## Governance

1. Any regression above threshold requires either:
   - rollback/fix, or
   - explicit approval with rationale in PR/release notes.
2. Baseline can be updated only after documented methodological or platform
   change.
