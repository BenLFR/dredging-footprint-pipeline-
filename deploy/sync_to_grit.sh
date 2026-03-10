#!/usr/bin/env bash
# Legacy compatibility wrapper. Prefer deploy/hpc_sync.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/hpc_sync.sh" "$@"
