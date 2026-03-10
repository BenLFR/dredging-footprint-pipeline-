#!/usr/bin/env bash
# Legacy compatibility wrapper. Prefer deploy/hpc_ping.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/hpc_ping.sh" "$@"
