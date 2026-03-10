#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
use_delete=0
use_checksum=0
declare -a requested_items=()

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
    --delete)
      use_delete=1
      shift
      ;;
    --checksum)
      use_checksum=1
      shift
      ;;
    --item)
      [[ $# -ge 2 ]] || deploy::usage_error "--item requires a path"
      requested_items+=("$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/hpc_sync.sh [options]

Options:
  --env-file PATH   Load deploy variables from PATH.
  --dry-run         Preview rsync operations.
  --delete          Mirror deletions on the remote side.
  --checksum        Validate transfers with checksums.
  --item PATH       Sync a specific file or directory. Repeatable.

Without --item, the script syncs paths listed in SYNC_ITEMS.
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_commands ssh rsync
deploy::require_vars HPC_HOST HPC_BASEDIR

if (( ${#requested_items[@]} == 0 )); then
  if [[ -n "${SYNC_ITEMS:-}" ]]; then
    for item in ${SYNC_ITEMS}; do
      requested_items+=("${item}")
    done
  else
    requested_items=(deploy pipeline config documentation tests data/toy postproc README.md LICENSE THIRD_PARTY_NOTICES.md CITATION.cff requirements.txt renv.lock)
  fi
fi

deploy::info "Ensuring remote base directory exists: ${HPC_BASEDIR}"
deploy::run_remote_shell "mkdir -p $(printf '%q' "${HPC_BASEDIR}")"

declare -a rsync_args
rsync_args=(-a --human-readable --itemize-changes)

if (( dry_run == 1 )); then
  rsync_args+=(--dry-run)
fi

if (( use_delete == 1 )); then
  rsync_args+=(--delete)
fi

if (( use_checksum == 1 )); then
  rsync_args+=(--checksum)
fi

rsync_args+=(
  --exclude=.git/
  --exclude=.worktrees/
  --exclude=.claude/
  --exclude=__pycache__/
  --exclude=config.env
  --exclude=known_hosts
  --exclude=ssh_config
  --exclude=id_*
  --exclude=*.pem
  --exclude=*.key
  --exclude=reports/
  --exclude=.Rproj.user/
  --exclude=.Rhistory
  --exclude=.RData
  --exclude=*.tmp
  --exclude=*.out
  --exclude=*.err
  -e "$(deploy::rsync_rsh)"
)

for item in "${requested_items[@]}"; do
  remote_dest="${HPC_BASEDIR%/}/"

  if ! local_path="$(deploy::resolve_local_path "${item}")"; then
    deploy::warn "Skipping missing path: ${item}"
    continue
  fi

  if [[ ! "${item}" =~ ^[A-Za-z]:[/\\] ]] && [[ "${item}" != /* ]]; then
    item_dir="$(dirname "${item}")"
    if [[ "${item_dir}" != "." ]]; then
      remote_dest="${HPC_BASEDIR%/}/${item_dir%/}/"
      deploy::run_remote_shell "mkdir -p $(printf '%q' "${remote_dest}")"
    fi
  fi

  deploy::info "Syncing ${item}"
  rsync "${rsync_args[@]}" "${local_path}" "$(deploy::ssh_target):${remote_dest}"
done

deploy::info "Sync completed."
