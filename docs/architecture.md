# Pipeline Architecture

## Overview

This pipeline estimates the global seafloor swept-area ratio (SAR) and
cumulative risk index (CRI) from AIS vessel-tracking data for trailing-suction
hopper dredgers (TSHDs). It runs on any HPC cluster with SLURM, using the
scripts in `pipeline/` and the orchestrator `pipeline/run_pipeline.sh`.

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
        │  Output: AIS_data_core_preprocessed_V6_*.rds
        ▼
[step4] Join dbSEABED lithology → penetrability index (PI)
        │  Output: AIS_with_lithology_*.rds
        ▼
[step5a] Make 630-tile global grid (EPSG:6933, 1000 km tiles)
[step5b] Tile workers: compute SAR per cell → sar_NNN.parquet (parallel)
[step5c] Merge tiles → f_i grid → fi_grid_*.parquet + GeoTIFF
        │
        ▼
[step6] C_ri = min(C0_i × f_i × d_i, C0_i)
        │  Output: cri_final_*.parquet + GeoTIFF
        ▼
[step7] Export J_dredge array → OCIM2 grid (KDTree matching)
        │  Output: jdredge_ocim2_48l_*.mat
        ▼
[co2model, external] MATLAB OCIM2 solver → pCO2 perturbation + net emission flux
        │  Output: co2_output_*.mat
        ▼
[postproc] Atwood-style figures, timeseries CSVs
```

## Step I/O Table

| Step | Script | Key inputs | Key outputs |
|------|--------|-----------|-------------|
| step0 | `pipeline/step0/step0_core_window.R` | AIS CSV/RDS, config | `core_window.yaml`, coverage matrix |
| step1 | `pipeline/step1/step1_split_vessels.R` | AIS CSV/RDS, `core_window.yaml` | `vessel_*.rds` (one per MMSI) |
| step2 | `pipeline/step2/step2_process_vessel.R` | `vessel_*.rds`, `config/outlier_config.yaml` | `vessel_*_clean.rds` |
| step3 | `pipeline/step3/step3_merge.R` | `vessel_*_clean.rds` | `AIS_data_core_preprocessed_V6_*.rds` |
| step4 | `pipeline/step4/step4_add_lithology.R` | step3 merged RDS, dbSEABED rasters | `AIS_with_lithology_*.rds` |
| step5a | `pipeline/step5/step5_make_tiles.R` | `pipeline/constants.R` | `tiles_1000km.gpkg` |
| step5b | `pipeline/step5/step5_tile_worker.R` | `AIS_with_lithology_*.rds`, tiles, YAML params | `sar_NNN.parquet` (parallel array) |
| step5c | `pipeline/step5/step5_merge_tiles.R` | `sar_*.parquet`, Longhurst, `config/fi_parameters.yaml` | `fi_grid_*.parquet`, `fi_grid_*.tif` |
| step6 | `pipeline/step6/step6_calculate_cri.R` | `fi_grid_*.parquet`, Atwood C0 rasters | `cri_final_*.parquet`, `cri_final_*.tif` |
| step7 | `pipeline/step7/step7_export_jdredge.R` | `cri_final_*.parquet`, `ocim_cache.mat` | `jdredge_ocim2_48l_*.mat` |
| co2model (external) | external MATLAB code | `jdredge_*.mat`, OCIM2-48L matrix | `co2_output_*.mat` |

## Projection

All spatial computations use **EPSG:6933** (WGS 84 / NSIDC EASE-Grid 2.0 Global),
an equal-area cylindrical projection. Grid cell size: **1 km × 1 km**.
Output GeoTIFFs are written in the same CRS.

## Key Formulas

### Swept-Area Ratio (SAR)
```
SAR_i = (W_v × p_d × distance_dredging_m) / cell_area_m2
f_i   = Σ SAR_i  (summed over all vessel-days in cell i)
```
where `W_v` is the vessel beam (m) and `p_d` is the dredging depth factor.

### Cumulative Risk Index (CRI)
```
C_ri = min(C0_i × f_i × d_i, C0_i)
```
where `C0_i` is the organic carbon stock density (t C m⁻²) from Atwood et al.
(2020) and `d_i` is the depletion factor (1.0 if no trawling history, 0.272
after >10 years of trawling).

### Dredging flag (GMM + DBSCAN)
Step 3 fits a 2-component Gaussian Mixture Model on (speed, turning_rate) to
separate dredging from transit, then applies DBSCAN spatial clustering to
remove isolated points.

## Reproducibility

See `docs/reproducibility.md` for environment setup instructions (renv, Apptainer).
