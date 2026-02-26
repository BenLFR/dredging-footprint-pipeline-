# Project: Dredging Footprint Pipeline (Master Thesis)

AIS-based global dredging footprint estimation pipeline (steps 0-7 + OCIM CO2 model).
Runs on **Beluga** (Alliance Canada, R) and **GRIT** (MATLAB + R) HPC clusters.

## Directory Map

```
pipeline_V6/              # Production pipeline scripts (step0-step7 .R + .sh)
scripts_cluster/          # SLURM wrappers & cluster-only helpers (step4-step7)
scripts_principaux/       # Local analysis, visualization, model training
configuration/            # YAML configs, shapefiles, lithology, land_mask
documentation/            # All .md docs (guides, changelogs, checklists)
deploy/                   # Sync/upload/run scripts for GRIT cluster
installation/             # R package install scripts for cluster environments
maintenance/              # Cleanup scripts, old package fixes
batch_windows/            # Windows .bat launchers
tests/                    # Test scripts and test logs
submission/               # SLURM job submission scripts
Trawling model-.../       # MATLAB OCIM trawling model (step7+)
output_V6/                # Pipeline outputs (parquet, rds, tif, logs)
GeoTIFF_Step5/            # Step5 GeoTIFF raster exports
GeoTIFF_Step6/            # Step6 GeoTIFF raster exports
outputs_step6/            # Step6 CRI parquet/rds
logs/                     # SLURM execution logs
```

## Naming Conventions

- **Scripts**: `stepN_description_verb.R` or `.sh` — lowercase, underscores, no spaces
- **Outputs**: `type_description_YYYYMMDD_HHMMSS.{parquet,rds,tif}`
- **Docs**: `UPPERCASE_TOPIC.md` in `documentation/`
- **No version suffixes** like `_FINAL`, `_FIXED`, `_V2` — use git instead
- **Language**: English for code and filenames; French is OK in comments and docs

## Rules for New Files

- Never create files at project root — pick the right directory
- New pipeline scripts → `pipeline_V6/`
- New cluster/SLURM wrappers → `scripts_cluster/`
- New visualization or analysis → `scripts_principaux/`
- New documentation → `documentation/`
- Config or reference data → `configuration/`
- Pipeline outputs → `output_V6/` (or `GeoTIFF_StepN/` for rasters)
- Test scripts → `tests/`

## Cluster Context

| Cluster | Connection | Software |
|---------|-----------|----------|
| Beluga  | `ssh benl@beluga.alliancecan.ca` | R only |
| GRIT    | `ssh -F ~/.ssh/config_grit grit` (user `bloe`) | MATLAB + R |

- SLURM logs → `~/logs/` on cluster, `logs/` locally
- Deploy/sync scripts live in `deploy/`

## Pipeline Overview

| Step | Description | Location |
|------|-------------|----------|
| step0 | Core window selection & coverage analysis | `pipeline_V6/pipeline_V6/step0_*` |
| step1 | Split AIS data by vessel | `pipeline_V6/pipeline_V6/step1_*` |
| step2 | Per-vessel track processing & filtering | `pipeline_V6/pipeline_V6/step2_*` |
| step3 | Merge vessels, GMM mapping, DBSCAN clustering | `pipeline_V6/pipeline_V6/step3_*` |
| step4 | Add lithology from dbSEABED | `pipeline_V6/pipeline_V6/step4_*` |
| step5 | Compute fishing intensity (fi) on global grid | `pipeline_V6/pipeline_V6/step5_*` |
| step6 | Calculate CRI (cumulative risk index) | `pipeline_V6/pipeline_V6/step6_*` |
| step7 | Export Jdredge for OCIM | `scripts_cluster/step7_*` |
| co2model | OCIM CO2 perturbation model (MATLAB) | `Trawling model-.../` |

## How to Run (GRIT cluster)

All scripts live in `~/ais-pipeline/pipeline_V6/` on GRIT.
Connect: `ssh -F ~/.ssh/config_grit grit` (user `bloe`).

**Important**: Steps needing R must run on `--partition=emlab_nodes` (sequoia node).
The default `grit_node` partition (hpc-*) does NOT have R installed.

```bash
cd ~/ais-pipeline/pipeline_V6

# Step 0: Core window selection
sbatch --partition=emlab_nodes step0_window_select_grit.sh

# Step 1: Split AIS by vessel
sbatch --partition=emlab_nodes step1_split_navires.sh

# Step 2: Per-vessel track processing (array job)
sbatch --partition=emlab_nodes step2_process_array.sh

# Step 3: Merge vessels + GMM + DBSCAN
sbatch --partition=emlab_nodes step3_merge_grit.sh            # 32G version
# sbatch --partition=emlab_nodes step3_merge_grit_256G.sh     # if OOM

# Step 4: Add lithology
sbatch --partition=emlab_nodes step4_add_lithology_vNext.sh

# Step 5: Compute fi tiles + merge
sbatch --partition=emlab_nodes step5_tile_job.sh              # parallel tile workers
sbatch --partition=emlab_nodes step5_merge_slurm_optimized.sh # merge tiles after

# Step 6: CRI calculation
sbatch --partition=emlab_nodes step6_calculate_cri_grit.sh

# Step 7: Export Jdredge for OCIM
sbatch --partition=emlab_nodes step7_export_jtrawl_grit.sh

# CO2 model (MATLAB, after step 7)
sbatch co2model_batch_grit.sh
```

### Monitoring

```bash
squeue -u bloe                          # check running jobs
tail -f ~/logs/step7_jtrawl_JOBID.out   # follow a log
ls -lh ~/scratch/output_V6/             # check outputs
```

### Upload from local (Windows)

```bash
scp -F ~/.ssh/config_grit <local_file> grit:~/ais-pipeline/pipeline_V6/
scp -F ~/.ssh/config_grit <matlab_file> grit:~/scratch/configuration/ocim/
```

## Git Conventions

- Branch from `main`; feature branches: `feature/stepN-description`
- Commit messages: `stepN: short description` or `co2model: short description`
- Never commit large data files (.mat, .rds >10 MB, .parquet >10 MB)
