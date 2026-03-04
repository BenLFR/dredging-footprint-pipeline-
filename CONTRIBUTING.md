# Contributing

Thank you for your interest in contributing to the global dredging footprint pipeline.

## Reporting issues

Use the [GitHub issue tracker](https://github.com/BenLFR/Master-thesis-code-/issues).
Please include: R/MATLAB version, operating system, full error message, and the
step that failed.

## Pull requests

1. Fork the repository and branch from `pub/v1.0-clean`.
2. Name your branch `feature/stepN-description` or `fix/short-description`.
3. Commit messages: `stepN: short imperative description` (max 72 chars).
4. Run the smoke test before submitting: `bash tests/smoke_test_steps2_5.sh`.
5. Do not commit large binary files (`.rds`, `.mat`, `.parquet`, `.tif`).

## Code style

- **R**: follow [tidyverse style](https://style.tidyverse.org/) — snake_case,
  2-space indent, no trailing whitespace.
- **Shell**: `set -euo pipefail` at the top; prefer `[[` over `[`.
- **MATLAB**: ALLCAPS for constants, functions in separate `.m` files.
- Comments in English; French is acceptable in thesis-facing documentation.

## Versioning

This project follows [Semantic Versioning](https://semver.org/).
Update `CHANGELOG.md` and `CITATION.cff` before tagging a release.
