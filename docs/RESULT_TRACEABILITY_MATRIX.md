# Result Traceability Matrix

Mapping of major results to scripts, required inputs, and produced outputs.

| Result ID | Product | Script(s) | Main inputs | Main outputs |
|---|---|---|---|---|
| R0 | Core temporal window selection | `pipeline/step0/step0_core_window.R` via `pipeline/step0/step0_window_select.sh` | Raw AIS tracks | `core_window.yaml`, coverage matrix |
| R1 | Vessel split by identifier | `pipeline/step1/step1_split_vessels.R` via `pipeline/step1/step1_split_vessels.sh` | Raw AIS tracks, `core_window.yaml`, `config/ship_specs.yaml` | Per-vessel RDS files, `navires_metadata.csv` |
| R2 | Cleaned vessel trajectories | `pipeline/step2/step2_process_vessel.R` via `pipeline/step2/step2_process_array.sh` | Step1 vessel files, `config/ship_specs.yaml`, `config/outlier_config_V6.yaml`, `config/land_mask/land_polygons.shp` | `*_clean.rds` files |
| R3 | Merged + classified AIS tracks | `pipeline/step3/step3_merge.R` via `pipeline/step3/step3_merge.sh` | Step2 clean files, `config/outlier_config_V6.yaml` | `AIS_data_core_preprocessed_V6_*.rds` |
| R4 | Lithology-enriched AIS tracks | `pipeline/step4/step4_add_lithology.R` via `pipeline/step4/step4_add_lithology.sh` | Step3 merged RDS, dbSEABED rasters | `AIS_with_lithology_*.rds` |
| R5 | SAR and f_i grids | `pipeline/step5/step5_make_tiles.R`, `pipeline/step5/step5_tile_worker.R`, `pipeline/step5/step5_merge_tiles.R` | Step4 outputs, `config/ship_specs.yaml`, `config/fi_parameters_with_freshness.yaml`, `config/longhurst_v4_2010/Longhurst_world_v4_2010.shp`, land mask | `sar_*.parquet`, `fi_grid_*.parquet`, `fi_grid_*.tif` |
| R6 | CRI grids | `pipeline/step6/step6_calculate_cri.R` via `pipeline/step6/step6_calculate_cri.sh` | `fi_grid_*.parquet`, Atwood C0 rasters, `constants.R` | `cri_final_*.parquet`, `cri_final_*.tif` |
| R7 | OCIM forcing export | `pipeline/step7/step7_export_jdredge.R` via `pipeline/step7/step7_export_jdredge.sh` | `cri_final_*.parquet`, `ocim_cache.mat`, `constants.R` | `jdredge_ocim2_48l_*.mat` |
| R8 (optional) | CO2 perturbation diagnostics | External `co2model` MATLAB code (not vendored) | Step7 outputs + external OCIM solver package | CO2 perturbation output files (external workflow) |

## Notes

1. Runtime limitation warnings are emitted by wrappers for Steps 3-7 and point
   to `docs/LIMITATIONS.md`.
2. All scripts listed above are the canonical versions. See `pipeline/` for
   the complete directory structure.
3. `config/fi_parameters_with_freshness.yaml` contains three scenarios
   (`default`, `conservative`, `upper_bound`) used by Steps 5b and 5c.
   `config/outlier_config_V6.yaml` controls Isolation Forest contamination rate
   and speed-margin parameters used by Steps 2 and 3.
