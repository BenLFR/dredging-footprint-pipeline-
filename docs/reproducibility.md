# Reproducibility Guide

## R Environment

The pipeline was developed and validated on **R 4.3.x** with the package
versions listed in `renv.lock` (to be generated — see below).

### Using renv (recommended)

```r
# Install renv if needed
install.packages("renv")

# Restore the exact package versions
renv::restore()
```

If `renv.lock` is not yet present, bootstrap from the GRIT R session:
```bash
# On GRIT cluster (emlab_nodes):
Rscript -e "renv::snapshot()"
scp -F ~/.ssh/config_grit grit:~/ais-pipeline/renv.lock .
```

### Key R packages

| Package | Version | Purpose |
|---------|---------|---------|
| data.table | ≥ 1.14 | Fast tabular I/O |
| sf | ≥ 1.0 | Vector spatial operations |
| terra | ≥ 1.7 | Raster operations (replaces raster) |
| mclust | ≥ 6.0 | GMM classification (step3) |
| dbscan | ≥ 1.1 | DBSCAN clustering (step3) |
| arrow | ≥ 12.0 | Parquet I/O |
| qs | ≥ 0.25 | Fast RDS-like serialisation |
| yaml | ≥ 2.3 | Config file parsing |
| dplyr | ≥ 1.1 | Data manipulation |
| ggplot2 | ≥ 3.4 | Visualisation |

## Python Environment

Post-processing scripts require Python ≥ 3.10.

```bash
pip install -r pipeline_V6/requirements_postproc_atwood.txt
```

Key packages: `numpy`, `scipy` (KDTree, step7), `pandas`, `pyarrow`,
`matplotlib`, `cartopy`.

## MATLAB Environment

The CO2 model (`co2model/`) requires **MATLAB R2021a or later** with the
Parallel Computing Toolbox (optional, for faster OCIM solves).

No additional toolboxes are required — all solver internals are included as
`.m` files.

## Apptainer / Singularity Container (for cluster portability)

For fully reproducible HPC execution, an Apptainer image is available:

```bash
# Pull (if published):
apptainer pull oras://ghcr.io/BenLFR/ais-pipeline:v1.0

# Run a step:
apptainer exec ais-pipeline_v1.0.sif Rscript pipeline/step3_merge_final.R
```

To build locally from the definition file:
```bash
apptainer build ais-pipeline.sif apptainer.def  # definition file TBD
```

## SLURM Cluster Setup

Tested on:
- **GRIT** (UCSB emlab, `sequoia` node): R 4.3.1, MATLAB R2022b
- **Beluga** (Alliance Canada): R 4.2.x, modules `r/4.3.1` and `gcc/11.3.0`

Account: `def-wailung` (Beluga) / `emlab_nodes` (GRIT).

## Step-by-step verification

After a full run, verify outputs:
```r
library(arrow)
fi <- read_parquet("output_V6/fi_grid_YYYYMMDD.parquet")
stopifnot(nrow(fi) > 0)
stopifnot(all(c("lon", "lat", "fi") %in% names(fi)))
summary(fi$fi)
```

Expected: non-zero SAR values in known dredging hotspots (North Sea, Manila Bay,
Rotterdam Waterway, Singapore Strait).
