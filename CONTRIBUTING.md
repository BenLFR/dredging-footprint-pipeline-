# Contributing

Thank you for your interest in contributing to the dredging footprint pipeline.

## Reporting issues

Open an issue on the
[GitHub issue tracker](https://github.com/BenLFR/dredging-footprint-pipeline-/issues)
and include:

- R or MATLAB version
- Operating system
- Full error message and stack trace
- Pipeline step that failed (`step0` – `step7`)
- Minimal reproduction (toy data or anonymised excerpt if possible)

## Pull requests

1. Fork the repository and branch from `main`.
2. Name your branch `feature/stepN-description` or `fix/short-description`.
3. Keep commits focused; use `stepN: short imperative description` (≤ 72 chars).
4. Run the smoke test before opening a PR:
   ```bash
   Rscript tests/smoke_test_steps2_5.R
   Rscript tests/smoke_test_steps3_6_entrypoints.R
   ```
5. Do not commit large binary files (`.rds`, `.mat`, `.parquet`, `.tif` > 1 MB).
6. Do not commit cluster-specific paths, credentials, or SSH config files.

## Code style

**R**
- Follow [tidyverse style](https://style.tidyverse.org/): snake_case, 2-space indent, no trailing whitespace.
- Use `data.table` idioms for performance-critical sections.
- Write comments in English.

**Shell**
- Start every script with `set -euo pipefail`.
- Prefer `[[` over `[`; quote all variable expansions.
- Write comments in English.

**MATLAB**
- ALLCAPS for constants; each function in its own `.m` file.
- Write comments in English.

## Testing

The repository includes three test layers:

| Test | Command |
|------|---------|
| Smoke test (steps 2–5, toy data) | `Rscript tests/smoke_test_steps2_5.R` |
| Entrypoint parse check (steps 3–6) | `Rscript tests/smoke_test_steps3_6_entrypoints.R` |
| HPC template sanity check | `Rscript tests/hpc_template_path_check.R` |
| testthat suite | `Rscript -e "testthat::test_dir('tests/testthat')"` |

All tests must pass before a PR can be merged.

## Versioning

This project follows [Semantic Versioning](https://semver.org/).
Update `CHANGELOG.md` and `CITATION.cff` before tagging a release.
