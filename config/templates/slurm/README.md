# Generic SLURM Templates

This folder provides cluster-neutral templates for running Step 4-7 wrappers.

## Files

- `cluster_overrides.env.example`: environment-path and SLURM override template.
- `submit_step.sh`: generic `sbatch` helper that injects optional cluster flags.

## Quick start

```bash
cp config/templates/slurm/cluster_overrides.env.example config/local/cluster_overrides.env
source config/local/cluster_overrides.env
bash config/templates/slurm/submit_step.sh pipeline/step6_calculate_cri.sh
```

The wrappers now accept:
- `PIPELINE_DIR`
- `SCRATCH_DIR`
- `OUTPUT_DIR`
- `CONFIG_DIR`
- `LOGS_DIR`

so you can run the same scripts on different SLURM clusters without editing
hard-coded paths.
