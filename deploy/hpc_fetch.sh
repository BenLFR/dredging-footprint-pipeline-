#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
use_checksum=0
destination_dir="${PWD}/remote_fetch"
declare -a requested_paths=()

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --checksum)
      use_checksum=1
      shift
      ;;
    --dest)
      [[ $# -ge 2 ]] || deploy::usage_error "--dest requires a path"
      destination_dir="$2"
      shift 2
      ;;
    --path)
      [[ $# -ge 2 ]] || deploy::usage_error "--path requires a value"
      requested_paths+=("$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/hpc_fetch.sh [options]

Options:
  --env-file PATH
  --dry-run
  --checksum
  --dest PATH
  --path REMOTE_PATH

Without --path, the script fetches paths listed in FETCH_ITEMS.
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_commands rsync
deploy::require_vars HPC_HOST HPC_BASEDIR

if (( ${#requested_paths[@]} == 0 )); then
  if [[ -n "${FETCH_ITEMS:-}" ]]; then
    for item in ${FETCH_ITEMS}; do
      requested_paths+=("${item}")
    done
  else
    requested_paths=(output_V6 logs documentation)
  fi
fi

mkdir -p "${destination_dir}"

declare -a rsync_args
rsync_args=(-a --human-readable --itemize-changes)

if (( dry_run == 1 )); then
  rsync_args+=(--dry-run)
fi

if (( use_checksum == 1 )); then
  rsync_args+=(--checksum)
fi

rsync_args+=(-e "$(deploy::rsync_rsh)")

for remote_item in "${requested_paths[@]}"; do
  remote_path="$(deploy::remote_path "${remote_item}")"
  deploy::info "Fetching ${remote_item}"
  rsync "${rsync_args[@]}" "$(deploy::ssh_target):${remote_path}" "${destination_dir}/"
done

deploy::info "Fetch completed."
