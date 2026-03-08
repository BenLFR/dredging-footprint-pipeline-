# GRIT Script Baseline (authoritative)

Date de reference: 2026-03-08  
Source: liste fournie par l'utilisateur (scripts les plus recents valides sur GRIT)

## Regle

Ces scripts constituent la reference canonique pour les phases 0 et 2 du plan.
En cas de divergence locale, la version GRIT la plus recente prime.

## Baseline recue

| Script | Taille | Horodatage |
|---|---:|---|
| `step7_extract_ocim_cache.py` | 18.71 kB | 2026-02-17 09:22:57 |
| `step7_extract_ocim_cache.m` | 6.50 kB | 2026-02-13 09:39:17 |
| `step7_export_jtrawl_grit.sh` | 2.54 kB | 2026-02-13 10:32:13 |
| `step7_export_jtrawl.R` | 38.40 kB | 2026-02-17 10:38:25 |
| `step6_calculate_cri_grit.sh` | 2.45 kB | 2026-02-10 10:58:02 |
| `step6_calculate_cri_corrected.R` | 7.28 kB | 2026-02-10 11:45:41 |
| `step5_tile_worker_corrected.R` | 15.84 kB | 2026-02-06 13:48:19 |
| `step5_tile_job.sh` | 1.71 kB | 2026-03-06 14:56:39 |
| `step5_subtile_worker_corrected.R` | 6.24 kB | 2026-02-04 10:42:15 |
| `step5_subtile_worker.sh` | 1.85 kB | 2026-02-04 10:43:27 |
| `step5_merge_tiles_optimized_corrected.R` | 5.66 kB | 2026-02-04 10:42:16 |
| `step5_merge_tiles_optimized.R` | 22.75 kB | 2026-03-06 12:52:21 |
| `step5_merge_slurm_optimized.sh` | 3.00 kB | 2026-03-06 13:15:44 |
| `step5_make_tiles.R` | 4.76 kB | 2026-02-04 10:52:07 |
| `step4_add_lithology_vNext.sh` | 3.11 kB | 2026-02-03 11:44:13 |
| `step4_add_lithology_vNext.R` | 27.45 kB | 2026-02-03 15:22:21 |
| `step3_merge_grit_256G.sh` | 1.57 kB | 2026-01-29 17:23:41 |
| `step3_merge_grit.sh` | 1.35 kB | 2026-01-29 14:40:12 |
| `step3_merge_final.R` | 73.81 kB | 2026-03-04 11:54:18 |
| `step2_process_navire_NO_CROSSING.R` | 18.61 kB | 2026-01-16 11:23:01 |
| `step2_process_navire.R.backup` | 18.29 kB | 2026-01-12 02:06:22 |
| `step2_process_navire.R` | 36.81 kB | 2026-03-03 18:06:09 |
| `step2_process_array.sh.backup_32g` | 2.51 kB | 2026-01-12 17:45:55 |
| `step2_process_array.sh` | 2.20 kB | 2026-01-29 11:14:54 |
| `step2_NO_CROSSING_test.sh` | 1.38 kB | 2026-01-16 11:31:56 |
| `step1_split_navires.sh` | 1.31 kB | 2026-01-08 18:05:18 |
| `step1_split_navires.R` | 14.43 kB | 2026-01-08 18:04:54 |
| `step0_window_select_grit.sh` | 1.71 kB | 2026-01-08 16:04:48 |
| `step0_core_window_enhanced.R` | 13.60 kB | 2026-01-08 16:13:31 |

## Actions obligatoires liees a cette baseline

1. Construire un mapping `script_baseline -> chemin_local`.
2. Ajuster wrappers/CI pour pointer uniquement vers ces scripts.
3. Marquer explicitement les alternatives locales comme legacy/obsolete.
