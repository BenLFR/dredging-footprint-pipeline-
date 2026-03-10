# Upload and Run Step 0

Use the generic public workflow:

1. Configure `deploy/config.env`.
2. Run `bash deploy/preflight_hpc.sh --ping`.
3. Run `bash deploy/hpc_sync.sh`.
4. Submit `bash deploy/hpc_submit.sh pipeline/step0_window_select.sh`.
5. Fetch results with `bash deploy/hpc_fetch.sh --path output_V6`.

See [STEP0_GUIDE.md](STEP0_GUIDE.md) for the public Step 0 notes.
