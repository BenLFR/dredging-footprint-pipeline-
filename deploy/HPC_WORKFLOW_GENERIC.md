# Generic HPC Workflow

This document describes the public deployment flow for any Slurm-based cluster.

## 1. Prepare local configuration

1. Copy `deploy/config.example.env` to `deploy/config.env`.
2. Fill in `HPC_HOST`, `HPC_BASEDIR`, `HPC_SCRATCH`, and any optional scheduler defaults.
3. Keep `deploy/config.env` out of version control.

## 2. Run preflight checks

```bash
bash deploy/preflight_hpc.sh --ping
```

This confirms that required local tools exist and that the remote host is reachable.

## 3. Sync the public project subset

```bash
bash deploy/hpc_sync.sh
```

Use `--dry-run` first for release-critical transfers:

```bash
bash deploy/hpc_sync.sh --dry-run --checksum
```

## 4. Submit jobs through Slurm

```bash
bash deploy/hpc_submit.sh pipeline/step0_window_select.sh
```

For arrays and dependencies, use the dedicated Slurm templates in `deploy/`.

## 5. Fetch outputs

```bash
bash deploy/hpc_fetch.sh --path output_V6
```

## 6. Capture scheduler evidence

```bash
bash deploy/capture_sacct.sh 123456
```

Store scheduler accounting next to other reproducibility evidence.

## 7. Operational rules

- Use login nodes only for preparation, sync, and submission.
- Use scratch for temporary high-I/O data.
- Stage out important outputs from scratch before site cleanup policies remove them.
- Run a smoke test before any production-scale run.
