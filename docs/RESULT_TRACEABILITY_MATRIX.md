# Result Traceability Matrix

Mapping of major results to scripts, required inputs, and produced outputs.

| Result ID | Product | Script(s) | Main inputs | Main outputs |
|---|---|---|---|---|
| R0 | Core temporal window selection | `pipeline/step0_core_window.R` via `pipeline/step0_window_select.sh` | Raw AIS tracks | Core-window config and diagnostics |
| R1 | Vessel split by identifier | `pipeline/step1_split_navires.R` via `pipeline/step1_split_navires.sh` | Raw AIS tracks, core-window config | Per-vessel files (`*_vessel.rds` style outputs) |
| R2 | Cleaned vessel trajectories | `pipeline/step2_process_navire.R` via `pipeline/step2_process_array.sh` | Step1 vessel files, `config/outlier_config.yaml` | `*_clean.rds` files |
| R3 | Merged + classified AIS tracks | `pipeline/step3_merge_final.R` via `pipeline/step3_merge_final.sh` | Step2 clean files, model params in script/config | `AIS_data_core_preprocessed_V6_*.rds` |
| R4 | Lithology-enriched AIS tracks | `pipeline/step4_add_lithology.R` (or vNext equivalent) via `pipeline/step4_add_lithology.sh` | Step3 merged AIS, dbSEABED rasters | `AIS_with_lithology_*.rds` |
| R5 | SAR and f_i grids | `pipeline/step5_make_tiles.R`, `pipeline/step5_tile_worker.R`, `pipeline/step5_merge_tiles.R` via Step5 wrappers | Step4 outputs, vessel specs, Longhurst, land mask, carbon layers | `sar_*.parquet`, `fi_grid_*.parquet`, optional `fi_grid_*.tif` |
| R6 | CRI grids | `pipeline/step6_calculate_cri.R` via `pipeline/step6_calculate_cri.sh` | `fi_grid_*`, carbon raster(s), constants | `cri_final_*.parquet`, optional rasters |
| R7 | OCIM forcing export | `step7_export_jtrawl.R` or `pipeline/step7_export_jtrawl.R` via `pipeline/step7_export_jtrawl.sh` | Step6 CRI, `ocim_cache.mat`, constants | `jdredge_ocim2_48l_*` outputs |
| R8 (optional) | CO2 perturbation diagnostics | External `co2model` MATLAB code (not vendored) | Step7 outputs + external OCIM solver package | CO2 perturbation output files (external workflow) |

## Notes

1. Canonical scripts and deprecations are tracked in
   `documentation/CANONICAL_PATHS_AND_DEPRECATIONS.md`.
2. Runtime limitation warnings are emitted by wrappers for Steps 3-7 and point
   to `documentation/LIMITATIONS.md`.
