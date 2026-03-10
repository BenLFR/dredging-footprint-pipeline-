# HPC Deployment

This directory contains cluster-neutral scripts for deploying and running
the pipeline on any SLURM-based HPC system.

## Quick start

```bash
# 1. Copy and fill in your cluster paths
cp deploy/config.example.env deploy/local.env
# Edit deploy/local.env: set PIPELINE_DIR, SCRATCH_DIR, HPC_HOST, etc.

# 2. Verify connectivity
source deploy/local.env
bash deploy/preflight_hpc.sh

# 3. Sync pipeline code to cluster
bash deploy/hpc_sync.sh

# 4. Submit a step
bash deploy/hpc_submit.sh pipeline/step3/step3_merge.sh

# 5. Fetch results
bash deploy/hpc_fetch.sh output_V6/fi_grid_*.parquet .
```

## File reference

### Configuration
| File | Purpose |
|------|---------|
| `config.example.env` | Template for cluster paths and SLURM overrides — copy to `local.env` |

### Core scripts
| File | Purpose |
|------|---------|
| `_common.sh` | Shared helper functions sourced by other scripts |
| `preflight_hpc.sh` | Check SSH, R version, disk space before a run |
| `hpc_ping.sh` | Test SSH connectivity |
| `hpc_sync.sh` | Rsync pipeline code to cluster |
| `hpc_submit.sh` | Generic `sbatch` wrapper with env-var overrides |
| `hpc_fetch.sh` | Download results from cluster scratch |
| `capture_sacct.sh` | Export SLURM accounting data after a run |
| `cleanup_scratch.sh` | Remove completed job scratch directories |

### Upload helpers (step-specific assets)
| File | Purpose |
|------|---------|
| `upload_step7_assets.sh` | Upload OCIM assets and optional co2model source |
| `upload_step6_assets.sh` | Upload Atwood C0 rasters |
| `upload_postproc_assets.sh` | Upload post-processing scripts |

### Container
| File | Purpose |
|------|---------|
| `apptainer.def` | Apptainer/Singularity container definition (R + Python environment) |

### SLURM job templates
| File | Purpose |
|------|---------|
| `slurm_job.template.sbatch` | Single-task job template |
| `slurm_array.template.sbatch` | Array job template (step 2) |
| `slurm_signal_safe.template.sbatch` | Template with SIGTERM checkpoint handler |

### Documentation
| File | Purpose |
|------|---------|
| `HPC_WORKFLOW_GENERIC.md` | End-to-end deployment walkthrough |
| `SETUP_GENERIC.md` | First-time cluster environment setup |
| `TRANSFER_POLICY.md` | What to sync, what to leave on cluster |
| `HPC_OPERATIONS_CHECKLIST.md` | Pre-run checklist |
| `STEP0_GUIDE.md` | Step 0 temporal coverage analysis guide |
| `STEP2_ONLAND_TUNING.md` | Land-mask tuning guide for step 2 |

## Environment variables

All scripts read from `deploy/local.env` (gitignored) if present, or fall back
to defaults. Key variables:

| Variable | Description |
|----------|-------------|
| `HPC_HOST` | SSH alias for your cluster (e.g. `beluga`) |
| `PIPELINE_DIR` | Remote path to the pipeline repository |
| `SCRATCH_DIR` | Remote scratch directory for outputs |
| `OUTPUT_DIR` | Remote output directory (default: `$SCRATCH_DIR/output_V6`) |
| `CONFIG_DIR` | Remote config directory (default: `$SCRATCH_DIR/configuration`) |
| `LOGS_DIR` | Remote log directory |
| `SBATCH_PARTITION` | SLURM partition (optional) |
| `SBATCH_ACCOUNT` | SLURM account (optional) |
