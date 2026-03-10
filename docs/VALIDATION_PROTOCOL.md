# Validation Protocol

Purpose: verify that outputs remain scientifically and technically coherent.

## Validation layers

## 1. Structural validation (required every run)

1. Required input files exist before each step.
2. Required output files are created after each step.
3. Output schemas contain mandatory columns.

Examples:

1. `fi_grid`: must include `lon`, `lat`, `fi`.
2. `cri_grid`: must include `lon`, `lat`, `cri`.
3. `Jdredge`: expected dimensions must match OCIM grid expectations.

## 2. Statistical sanity checks (required every run)

1. Non-empty outputs (`nrow > 0`).
2. No impossible negative values for non-negative quantities (`fi`, `cri`).
3. Percentile checks remain within expected envelope from baseline runs.

## 3. Spatial sanity checks (recommended)

1. Hotspot regions remain detectable in known dredging zones.
2. Land-only cells do not show systematic false positives.
3. Lithology join coverage above minimum threshold.

## 4. Cross-run consistency checks (recommended)

1. Compare key summary metrics against previous stable run:
   - global mean/median `fi`,
   - global mean/median `cri`,
   - number of active cells.
2. Flag deviations above agreed tolerance.

## 5. Independent validation (publication stage)

Where feasible, compare pipeline-derived activity proxies with one or more:

1. Independent dredging logs or permits (regional).
2. Port/campaign records.
3. Published external products with comparable spatial scope.

## Acceptance criteria

A run is considered valid when:

1. Structural checks pass.
2. No critical sanity check fails.
3. Any warnings are reviewed and documented.

## Audit trail

For each release candidate, store:

1. Git commit hash.
2. Validation date.
3. Validator identity.
4. Outcome (`PASS`, `PASS_WITH_WARNINGS`, `FAIL`) and rationale.
