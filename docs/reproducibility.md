# Reproducibility Guide

## Scope

This repository ships a cluster-neutral pipeline (steps 0-7) and an optional
external MATLAB CO2 step.

## R Environment (locked with `renv`)

The reference dependency set is tracked in [`renv.lock`](../renv.lock).
The lockfile was generated with R `4.4.1`.

Restore with:

```bash
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org')"
Rscript -e "renv::consent(provided = TRUE); renv::restore(lockfile='renv.lock', prompt=FALSE)"
```

If you need to refresh the lockfile after intentional dependency changes:

```bash
Rscript -e "renv::consent(provided = TRUE); renv::snapshot(prompt=FALSE)"
```

## Python Environment (`requirements.txt`)

Step 7 and post-processing scripts use Python dependencies pinned in
[`requirements.txt`](../requirements.txt).

```bash
python -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## MATLAB CO2 Dependency (external, not vendored)

The exact OCIM CO2 MATLAB source is not redistributed in this repository.
According to Atwood-related data-availability wording, access is via email
request to TD:

- `tdevries@geog.ucsb.edu`

After receiving the package, place it under:

```bash
data/external/co2model_vendor/
```

Then use:

```bash
bash deploy/upload_step7_to_cluster.sh --co2model-src data/external/co2model_vendor
```

See [`co2model/README.md`](../co2model/README.md) and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) for compliance details.

## Apptainer Container

Container definition file: [`deploy/apptainer.def`](../deploy/apptainer.def).

Build:

```bash
apptainer build ais-pipeline.sif deploy/apptainer.def
```

Quick checks:

```bash
apptainer exec ais-pipeline.sif R --version
apptainer exec ais-pipeline.sif python3 --version
apptainer exec ais-pipeline.sif Rscript tests/smoke_test_steps3_6_entrypoints.R
```

Record image checksum:

```bash
sha256sum ais-pipeline.sif > ais-pipeline.sif.sha256
```

## Output Verification

After a full run, verify expected columns and non-empty output:

```r
library(arrow)
fi <- read_parquet("output_V6/fi_grid_YYYYMMDD.parquet")
stopifnot(nrow(fi) > 0)
stopifnot(all(c("lon", "lat", "fi") %in% names(fi)))
summary(fi$fi)
```

