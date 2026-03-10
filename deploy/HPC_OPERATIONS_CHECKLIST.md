# HPC Operations Checklist

Use this checklist for reviewer-safe and release-safe public runs.

## Before first use on a site

- Copy `deploy/config.example.env` to `deploy/config.env`.
- Set `HPC_HOST`, `HPC_BASEDIR`, `HPC_SCRATCH`, and optional scheduler defaults.
- Keep SSH keys and SSH config outside the repository.
- Run `bash deploy/preflight_hpc.sh --ping`.
- Review `deploy/TRANSFER_POLICY.md`.

## Before syncing code

- Confirm that only public-safe files are included in `SYNC_ITEMS`.
- Run `bash deploy/hpc_sync.sh --dry-run --checksum`.
- Run `bash deploy/hpc_sync.sh` only after the preview looks correct.

## Before submitting jobs

- Confirm that the target job script is repo-relative and public-safe.
- Set explicit `--job-name`, logs, runtime, memory, and exports as needed.
- Run a smoke test before any production-scale submission.
- Record the exact submit command and returned job ID.

## During execution

- Use login nodes only for preparation, sync, and submission.
- Keep high-I/O intermediates on scratch, not in home storage.
- Avoid scheduler polling loops from worker tasks.
- Keep stdout and stderr logs for each submitted job.

## After completion

- Fetch outputs with `bash deploy/hpc_fetch.sh`.
- Capture accounting with `bash deploy/capture_sacct.sh <job_id>`.
- Stage out important scratch outputs with `bash deploy/cleanup_scratch.sh`.
- Remove temporary scratch paths once stage-out is confirmed.

## Release evidence

- Archive the submit command, job IDs, and key environment variables.
- Archive `sacct` outputs or equivalent accounting summaries.
- Archive checksums for release-critical outputs and manifests.
- Keep restricted data and external dependencies outside the public repository.