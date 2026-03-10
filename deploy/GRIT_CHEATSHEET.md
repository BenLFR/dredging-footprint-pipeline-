# Generic HPC Cheat Sheet

Use placeholders from `deploy/config.env` rather than editing scripts inline.

## Preflight

```bash
bash deploy/preflight_hpc.sh --ping
```

## Sync

```bash
bash deploy/hpc_sync.sh --dry-run
bash deploy/hpc_sync.sh
```

## Submit

```bash
bash deploy/hpc_submit.sh pipeline/step0_window_select.sh
```

## Fetch

```bash
bash deploy/hpc_fetch.sh --path output_V6
```

## Accounting

```bash
bash deploy/capture_sacct.sh <job_id>
```
