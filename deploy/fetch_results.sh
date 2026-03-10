#!/usr/bin/env bash
# Legacy compatibility wrapper. Prefer deploy/hpc_fetch.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
  exec "${SCRIPT_DIR}/hpc_fetch.sh"
fi

exec "${SCRIPT_DIR}/hpc_fetch.sh" --path "$1"
