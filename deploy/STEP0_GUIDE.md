# Step 0 Guide

This public guide covers the generic preparation and submission pattern for Step 0.

## Purpose

Step 0 selects the core temporal window used by the downstream pipeline.

## Inputs

- restricted AIS input file obtained through the documented access route,
- public pipeline code synced to the remote cluster,
- a writable scratch or output destination on the cluster.

## Recommended public workflow

1. Stage the required AIS input on the cluster in a site-appropriate location.
2. Set `AIS_INPUT_FILE` or `AIS_INPUT_PATTERN` for the Step 0 script.
3. Set `AIS_OUTPUT_DIR` to a writable output location, ideally under scratch if the site policy recommends it.
4. Sync the repository subset:

```bash
bash deploy/hpc_sync.sh
```

5. Submit the Step 0 wrapper:

```bash
bash deploy/hpc_submit.sh pipeline/step0_window_select.sh
```

6. Fetch the output files:

```bash
bash deploy/hpc_fetch.sh --path output_V6
```

## Notes

- Keep site-specific storage paths in `deploy/config.env`, not in tracked files.
- Run a smoke test first when adapting Step 0 to a new cluster.
- If Step 0 needs additional environment variables, export them explicitly at submission time.
