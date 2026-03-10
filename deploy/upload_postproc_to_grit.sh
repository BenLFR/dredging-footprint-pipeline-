#!/usr/bin/env bash
# Legacy compatibility wrapper. Prefer deploy/upload_postproc_assets.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/upload_postproc_assets.sh" "$@"
