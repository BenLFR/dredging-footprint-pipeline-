# Pipeline Architecture

## Overview

This pipeline estimates the global seafloor swept-area ratio (SAR) and
cumulative risk index (CRI) from AIS vessel-tracking data for trailing-suction
hopper dredgers (TSHDs). It runs on HPC clusters (Beluga / GRIT) using SLURM.

## Data Flow Diagram

```
AIS tracks (CSV/Parquet)
        │
        ▼
[step0] Coverage matrix → core time window (YAML)
        │
        ▼
[step1] Split by MMSI → N vessel RDS files
        │
        ▼
[step2] Per-vessel filter: IF, speed, land-crossing, DBSCAN
        │  Output: *_clean.rds per vessel
        ▼
[step3] Merge all vessels → GMM classification → dredging_flag
        │  Output: AIS_merged_V6_*.rds
        ▼
[step4] Join dbSEABED lithology → penetrability index (PI)
        │  Output: AIS_with_lithology_*.rds
        ▼
[step5a] Make 630-tile global grid (EPSG:6933, 1000 km tiles)
[step5b] Tile workers: compute SAR per cell → sar_NNN.parquet (parallel)
[step5c] Merge tiles → f_i grid → fi_grid_*.parquet + GeoTIFF
        │
        ▼
[step6] C_ri = C0_i × f_i × depletion_factor
        │  Output: cri_grid_*.parquet + GeoTIFF
        ▼
[step7] Export J_dredge array → OCIM2 grid (KDTree matching)
        │  Output: Jdredge_*.mat
        ▼
[co2model] MATLAB OCIM2 solver → pCO2 perturbation + net emission flux
        │  Output: co2_output_*.mat
        ▼
[postproc] Atwood-style figures, timeseries CSVs
```

## Step I/O Table

| Step | Key inputs | Key outputs | Cluster |
|------|-----------|-------------|---------|
| step0 | AIS CSV, config | core_window.yaml | GRIT |
| step1 | AIS CSV, core_window.yaml | vessel_*.rds | GRIT |
| step2 | vessel_*.rds, outlier_config.yaml | vessel_*_clean.rds | GRIT (array) |
| step3 | vessel_*_clean.rds | AIS_merged_V6.rds | GRIT |
| step4 | AIS_merged.rds, dbseabed.tif | AIS_with_lithology.rds | GRIT |
| step5a | — | tile_grid.rds | GRIT |
| step5b | AIS_with_lithology.rds, tile_grid.rds | sar_NNN.parquet | GRIT (array) |
| step5c | sar_*.parquet, Longhurst.shp, C0.tif | fi_grid.parquet, fi_grid.tif | GRIT |
| step6 | fi_grid.parquet, C0.tif | cri_grid.parquet, cri_grid.tif | GRIT |
| step7 | cri_grid.parquet, OCIM2_48L.mat | Jdredge.mat | GRIT |
| co2model | Jdredge.mat, OCIM2_48L.mat | co2_output.mat | GRIT (MATLAB) |

## Projection

All spatial computations use **EPSG:6933** (WGS 84 / NSIDC EASE-Grid 2.0 Global),
an equal-area cylindrical projection. Cell size: **0.5° × 0.5°** (reprojected
from the equal-area grid for output GeoTIFFs).

## Key Formulas

### Swept-Area Ratio (SAR)
```
SAR_i = (beam_m × distance_dredging_m) / cell_area_m2
f_i   = Σ SAR_i  (summed over all vessels in cell i)
```

### Cumulative Risk Index (CRI)
```
C_ri = C0_i × f_i × (1 - exp(-depletion_factor × f_i))
```
where C0_i is the organic carbon stock density (t C m⁻²) from Atwood et al. (2020).

### Dredging flag (GMM + DBSCAN)
Step 3 fits a 2-component Gaussian Mixture Model on (speed, turning_rate) to
separate dredging from transit, then applies DBSCAN spatial clustering to
remove isolated points.

## Reproducibility

See `docs/reproducibility.md` for environment setup instructions (renv, Apptainer).
