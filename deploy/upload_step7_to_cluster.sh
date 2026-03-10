#!/bin/bash
# Generic wrapper for Step 7 upload on an HPC cluster.
# Keeps public docs cluster-neutral while preserving legacy script behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/upload_step7_to_grit.sh" "$@"
