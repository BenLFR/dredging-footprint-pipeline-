# Generic HPC Deploy Toolkit

This folder is being migrated from site-specific GRIT helpers to a public, generic Slurm/HPC deployment interface.

## Current public entry points

1. Create a private config file:

```bash
cp deploy/config.example.env deploy/config.env
```

2. Validate the local and remote setup:

```bash
bash deploy/preflight_hpc.sh --ping
```

3. Sync the public project subset:

```bash
bash deploy/hpc_sync.sh
```

4. Submit a Slurm job:

```bash
bash deploy/hpc_submit.sh pipeline/step0_window_select.sh
```

5. Fetch outputs:

```bash
bash deploy/hpc_fetch.sh --path output_V6
```

6. Capture scheduler accounting:

```bash
bash deploy/capture_sacct.sh <job_id>
```

## Design rules

- Public files must not expose real hostnames, usernames, SSH key names, or personal workstation paths.
- Login nodes are for preparation and submission only.
- High-I/O temporary data should stage to scratch storage.
- Slurm jobs should use explicit working directories, logs, and environment export.
- Production runs should follow a smoke test.

## Documentation

- [SETUP_GENERIC.md](SETUP_GENERIC.md)
- [HPC_WORKFLOW_GENERIC.md](HPC_WORKFLOW_GENERIC.md)
- [STEP0_GUIDE.md](STEP0_GUIDE.md)
- `upload_step6_assets.sh`
- `upload_step7_assets.sh`
- `upload_postproc_assets.sh`
