#!/usr/bin/env bash
# Legacy compatibility wrapper. Prefer deploy/preflight_hpc.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/preflight_hpc.sh" "$@"
