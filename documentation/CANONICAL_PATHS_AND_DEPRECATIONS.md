# Canonical Paths and Deprecations

Date: 2026-03-08  
Reference baseline: `documentation/GRIT_SCRIPT_BASELINE_20260308.md`

## Rule

Scripts considered valid are those from the latest GRIT baseline provided by the user.
This file maps each baseline script name to one canonical local path in this repository.

## Canonical mapping

| Baseline script | Canonical local path | Status |
|---|---|---|
| `step0_core_window_enhanced.R` | `pipeline_V6/pipeline_V6/step0_core_window_enhanced.R` | FOUND |
| `step0_window_select_grit.sh` | `pipeline_V6/pipeline_V6/step0_window_select_grit.sh` | FOUND |
| `step1_split_navires.R` | `pipeline/step1_split_navires.R` | FOUND |
| `step1_split_navires.sh` | `pipeline/step1_split_navires.sh` | FOUND |
| `step2_process_array.sh` | `pipeline/step2_process_array.sh` | FOUND |
| `step2_process_navire.R` | `pipeline/step2_process_navire.R` | FOUND |
| `step3_merge_final.R` | `pipeline/step3_merge_final.R` | FOUND |
| `step3_merge_grit.sh` | `pipeline_V6/step3_merge_grit.sh` | FOUND |
| `step3_merge_grit_256G.sh` | `pipeline_V6/step3_merge_grit_256G.sh` | FOUND |
| `step4_add_lithology_vNext.R` | `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.R` | FOUND |
| `step4_add_lithology_vNext.sh` | `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.sh` | FOUND |
| `step5_make_tiles.R` | `pipeline/step5_make_tiles.R` | FOUND |
| `step5_tile_job.sh` | `pipeline/step5_tile_job.sh` | FOUND |
| `step5_tile_worker_corrected.R` | `ORGANISATION_BELUGA/pipeline_study/step5_intensity_grid/step5_tile_worker_corrected.R` | FOUND |
| `step5_subtile_worker_corrected.R` | `N/A` | MISSING |
| `step5_subtile_worker.sh` | `N/A` | MISSING |
| `step5_merge_tiles_optimized_corrected.R` | `N/A` | MISSING |
| `step5_merge_tiles_optimized.R` | `pipeline_V6/step5_merge_tiles_optimized.R` | FOUND |
| `step5_merge_slurm_optimized.sh` | `pipeline_V6/step5_merge_slurm_optimized.sh` | FOUND |
| `step6_calculate_cri_corrected.R` | `ORGANISATION_BELUGA/pipeline_study/step6_cri/step6_calculate_cri_corrected.R` | FOUND |
| `step6_calculate_cri_grit.sh` | `scripts_cluster/step6_calculate_cri_grit.sh` | FOUND |
| `step7_export_jtrawl.R` | `step7_export_jtrawl.R` | FOUND |
| `step7_export_jtrawl_grit.sh` | `scripts_cluster/step7_export_jtrawl_grit.sh` | FOUND |
| `step7_extract_ocim_cache.py` | `step7_extract_ocim_cache.py` | FOUND |
| `step7_extract_ocim_cache.m` | `step7_extract_ocim_cache.m` | FOUND |

## Wrapper alignment done

1. `pipeline/step4_add_lithology.sh`: robust script resolution across canonical candidates.
2. `pipeline/step5_tile_worker.R`: accepts both Step4 output name patterns.
3. `pipeline/step5_merge_slurm.sh`: robust Step5 merge script resolution.
4. `pipeline/step6_calculate_cri.sh`: robust Step6 script resolution.
5. `pipeline/step7_export_jtrawl.sh`: robust Step7 script resolution.
6. `step7_export_jtrawl.R`: fallback search for `constants.R` in canonical locations.
7. `tests/smoke_test_steps3_6_entrypoints.R`: lightweight entrypoint + `t_seuil` guard test.

## Deprecation policy

1. For duplicate scripts, only the canonical path above should be called by wrappers/CI.
2. Non-canonical duplicates must be tagged as `legacy` in comments or moved to archive folders.
3. Missing baseline scripts (`MISSING`) must be either restored from GRIT or removed from baseline list with rationale.
