# Reproducibility Guide

## Two reproducibility paths

There are two paths depending on whether you have access to the raw AIS data:

| | Path A — Full end-to-end | Path B — From published outputs |
|---|---|---|
| **Requires** | GFW AIS data access | Published fi_grid + CRI (Zenodo) |
| **Reproduces** | Steps 0–7 | Steps 5b onward, CO2 model, sensitivity |
| **Who** | Authors and data partners | Any reader with the paper |

Both paths use the same pipeline code from this repository.

---

## Common prerequisites

### R environment

The reference R version is **4.4.1**. Dependencies are locked in [`renv.lock`](../renv.lock).

```bash
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org')"
Rscript -e "renv::consent(provided = TRUE); renv::restore(lockfile='renv.lock', prompt=FALSE)"
```

### Python environment

Post-processing scripts use Python 3.11+. Pin dependencies:

```bash
python -m venv .venv
source .venv/bin/activate       # Linux/macOS
# or: .venv\Scripts\Activate.ps1  (Windows PowerShell)
pip install -r requirements.txt
```

### Config files

All config files are included in `config/`. No download required:

```
config/ship_specs.yaml              # 10 TSHD vessel specifications
config/outlier_config_V6.yaml       # Isolation Forest + DBSCAN parameters
config/fi_parameters_with_freshness.yaml  # Biogeochemical parameters (3 scenarios)
config/runtime_thresholds.csv       # Step-level resource thresholds
```

### External data assets

Large datasets are **not** included in the repository. See [`data/README.md`](../data/README.md) for
download instructions and expected placement paths.

Run the preflight check before any cluster run:

```bash
bash deploy/preflight_hpc.sh --env-file deploy/config.example.env
```

---

## Path A — Full end-to-end reproducibility (with GFW AIS data)

### Study vessels

The pipeline processes 10 deep-water TSHDs (trailing-suction hopper dredgers). Their
MMSI/SSVIDs are listed in `config/ship_specs.yaml`:

| Vessel | SSVID |
|--------|-------|
| Cristobal Colon | 253373000 |
| Leiv Eiriksson | 253403000 |
| Ham 318 | 245508000 |
| Fairway | 209469000 |
| Queen of the Netherlands | 210138000 |
| Inai Kenanga | 533180137 |
| Vasco da Gama | 205744000 (also 253193000 pre-2018) |
| Vox Maxima | 246351000 |
| Charles Darwin | 253422000 |
| Congo River | 253688000 |

Note: Goryo 6 Ho (MMSI 312062000) was excluded due to corrupted data.

### AIS data format

Place raw GFW AIS data in `data/external/ais/` (or set `AIS_INPUT_FILE` / `AIS_INPUT_PATTERN`).
Required columns:

```
ssvid       — vessel MMSI (GFW naming)
timestamp   — ISO 8601 UTC, e.g. "2020-06-01T12:00:00Z"
lat         — WGS84 latitude (decimal degrees)
lon         — WGS84 longitude (decimal degrees)
speed       — speed over ground (knots)
course      — course over ground (degrees)
```

Filter to the study vessels before running step 0:

```r
library(data.table)
target_ssv <- c(253373000, 253403000, 245508000, 209469000, 210138000,
                533180137, 205744000, 253193000, 246351000, 253422000, 253688000)
ais <- fread("data/external/ais/ais_raw.csv")
ais <- ais[ssvid %in% target_ssv]
fwrite(ais, "data/external/ais/ais_filtered.csv")
```

### Step-by-step pipeline commands (HPC / SLURM)

Set environment variables common to all steps:

```bash
export SCRATCH_DIR=~/scratch
export CONFIG_DIR=$(pwd)/config
export PIPELINE_DIR=$(pwd)/pipeline
```

Upload code and configs to the cluster (adapt hostnames as needed):

```bash
bash deploy/sync_pipeline.sh --env-file deploy/config.example.env
```

Then submit steps in order:

```bash
# Step 0 — Core temporal window selection
sbatch config/templates/slurm/submit_step.sh pipeline/step0/step0_core_window.R

# Step 1 — Split AIS data by vessel
sbatch config/templates/slurm/submit_step.sh pipeline/step1/step1_split_navires.R

# Step 2 — Per-vessel track filtering (array job, one task per vessel)
sbatch pipeline/step2/step2_process_array.sh

# Step 3 — Merge vessels, GMM activity classification, DBSCAN
sbatch config/templates/slurm/submit_step.sh pipeline/step3/step3_merge_final.R

# Step 4 — Join dbSEABED lithology
sbatch config/templates/slurm/submit_step.sh pipeline/step4/step4_add_lithology.R

# Step 5 — Tiled SAR computation + global merge
sbatch pipeline/step5/step5_tile_job.sh          # parallel tile workers
sbatch pipeline/step5/step5_merge_slurm.sh       # after all tiles complete

# Step 6 — CRI (cumulative risk index)
sbatch config/templates/slurm/submit_step.sh pipeline/step6/step6_calculate_cri.R

# Step 7 — Export Jdredge forcing for OCIM CO2 model
sbatch config/templates/slurm/submit_step.sh pipeline/step7/step7_export_jdredge.R
```

### Expected outputs

| Step | Output path | Key columns / format |
|------|-------------|----------------------|
| step0 | `$SCRATCH_DIR/output_V6/coverage_matrix.csv` | vessel × month coverage |
| step1 | `$SCRATCH_DIR/ais_split_*/vessel_*.rds` | per-vessel raw tracks |
| step2 | `$SCRATCH_DIR/ais_results_*/vessel_*_clean.rds` | filtered tracks + `outlier_IF`, `is_stop` |
| step3 | `$SCRATCH_DIR/output_V6/AIS_data_core_preprocessed_V6_*.rds` | merged, activity-classified |
| step4 | `$SCRATCH_DIR/output_V6/AIS_with_lithology_*.rds` | + lithology columns |
| step5 | `$SCRATCH_DIR/output_V6/fi_grid_*.parquet` / `.tif` | lon, lat, SAR, fi |
| step6 | `$SCRATCH_DIR/output_V6/cri_grid_*.parquet` / `.tif` | lon, lat, CRI |
| step7 | `$SCRATCH_DIR/output_V6/Jdredge.mat` | OCIM2-48L forcing matrix |

### Result verification

After step 5, basic sanity checks:

```r
library(arrow)
fi <- read_parquet(Sys.glob("output_V6/fi_grid_*.parquet")[1])
stopifnot(nrow(fi) > 0,
          all(c("lon", "lat", "fi") %in% names(fi)),
          all(fi$fi >= 0, na.rm = TRUE))
cat("Active cells:", sum(fi$fi > 0, na.rm = TRUE), "\n")
cat("Global mean fi:", mean(fi$fi, na.rm = TRUE), "\n")
```

After step 6:

```r
cri <- read_parquet(Sys.glob("output_V6/cri_grid_*.parquet")[1])
stopifnot(nrow(cri) > 0,
          all(c("lon", "lat", "cri") %in% names(cri)))
cat("Active cells:", sum(cri$cri > 0, na.rm = TRUE), "\n")
```

Compare your summary statistics against the values reported in the published paper.
Flag any deviation > 5% as unexpected and re-check the config files and data versions.

---

## Path B — Partial reproducibility from published Zenodo outputs

If you do not have access to raw GFW AIS data, you can still reproduce the downstream
analysis starting from the published grid files.

### Download published outputs

```bash
# fi_grid, cri_grid, Jdredge — all in single Zenodo deposit
wget -O data/external/zenodo_outputs.zip "https://doi.org/10.5281/zenodo.XXXXXXX"
unzip data/external/zenodo_outputs.zip -d data/external/zenodo/
```

### Sensitivity analysis (OAT, Sobol, Monte Carlo)

These scripts read the local fi_grid parquet and recompute C_ri under parameter
variations without re-running the full pipeline:

```bash
Rscript scripts/sensitivity/sensitivity_oat_analysis.R
Rscript scripts/sensitivity/sensitivity_sobol.R
Rscript scripts/sensitivity/monte_carlo_uncertainty.R
```

### CO2 perturbation model

After placing OCIM2 data (see `data/README.md` section 6):

```bash
# Run the MATLAB CO2 model with the published Jdredge forcing
matlab -batch "run('co2model/co2model_batch.m')"
```

---

## Apptainer container (optional, reproducible software environment)

Build a container from the definition file to pin the full software environment:

```bash
apptainer build ais-pipeline.sif deploy/apptainer.def
sha256sum ais-pipeline.sif > ais-pipeline.sif.sha256
```

Smoke-test the container:

```bash
apptainer exec ais-pipeline.sif R --version
apptainer exec ais-pipeline.sif Rscript tests/smoke_test_steps2_5.R
```

---

## Note on the CI smoke test

The GitHub Actions smoke test (`tests/smoke_test_steps2_5.R`, `tests/e2e_step2_canonical.R`)
is **not** a reproducibility test. It uses fully synthetic toy data and verifies that
the pipeline code runs correctly on a fresh clone without any external data.

Its purpose is: *"does a new contributor get a working repo on first checkout?"*

Scientific reproducibility — *"do we get the same published numbers with the same data?"* —
requires raw AIS access and the full pipeline run described in Path A above.

---

## Citation

If you use this pipeline or the published outputs, please cite:

```
[CITATION_PLACEHOLDER — see CITATION.cff]
```

Published derived outputs (fi_grid, cri_grid, Jdredge): Zenodo `10.5281/zenodo.XXXXXXX`
