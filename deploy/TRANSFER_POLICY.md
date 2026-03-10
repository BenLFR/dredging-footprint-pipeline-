# Transfer Policy

This repository uses three transfer modes for public HPC workflows.

## 1. Preview mode

Use preview mode before first use on a new cluster, after changing sync items,
or before a release-critical transfer.

```bash
bash deploy/hpc_sync.sh --dry-run --checksum
bash deploy/hpc_fetch.sh --dry-run --checksum --path output_V6
```

Purpose:

- confirm the source and destination paths,
- confirm excludes and included files,
- confirm remote hierarchy creation,
- detect unexpected large deltas before production.

## 2. Production mode

Use production mode for normal code sync and result collection after preview has
been checked.

```bash
bash deploy/hpc_sync.sh
bash deploy/hpc_fetch.sh --path output_V6
```

Use `--delete` only when you explicitly want the remote tree to mirror local
deletions.

## 3. Release-critical verification mode

Use checksum validation when transferring files that will support release
evidence, archived outputs, or reviewer reruns.

```bash
bash deploy/hpc_sync.sh --checksum
bash deploy/hpc_fetch.sh --checksum --path documentation
```

Typical cases:

- release notes,
- scheduler accounting reports,
- archived manifests,
- final output summaries used for manuscript support.

## 4. Scratch stage-out policy

Temporary compute products should live under `HPC_SCRATCH` during execution and
must be staged back to a persistent path before scratch cleanup.

```bash
bash deploy/cleanup_scratch.sh \
  --stage-out output_V6:output_V6 \
  --stage-out logs:logs \
  --remove-after-stage
```

Run `--dry-run` first when defining a new stage-out map.

## 5. Prohibited practices

- Do not commit `deploy/config.env`, SSH keys, or site-specific SSH config.
- Do not copy hidden personal paths into tracked docs or scripts.
- Do not treat scratch as persistent storage.
- Do not skip the dry-run path for first-time or release-critical transfers.