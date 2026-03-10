#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
scheduler_script=""
declare -a extra_items=()

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
    --scheduler-script)
      [[ $# -ge 2 ]] || deploy::usage_error "--scheduler-script requires a path"
      scheduler_script="$2"
      shift 2
      ;;
    --item)
      [[ $# -ge 2 ]] || deploy::usage_error "--item requires a path"
      extra_items+=("$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/upload_postproc_assets.sh [options]

Options:
  --env-file PATH
  --dry-run
  --scheduler-script PATH
  --item PATH

This syncs the public post-processing assets to the remote project root.
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_vars HPC_HOST HPC_BASEDIR

sync_cmd=(bash "${SCRIPT_DIR}/hpc_sync.sh" --env-file "${DEPLOY_ENV_FILE}" --item postproc)

if (( dry_run == 1 )); then
  sync_cmd+=(--dry-run)
fi

if [[ -n "${scheduler_script}" ]]; then
  if ! resolved_scheduler="$(deploy::resolve_local_path "${scheduler_script}")"; then
    deploy::usage_error "Scheduler script not found: ${scheduler_script}"
  fi
  sync_cmd+=(--item "${resolved_scheduler}")
fi

if (( ${#extra_items[@]} > 0 )); then
  for item in "${extra_items[@]}"; do
    sync_cmd+=(--item "${item}")
  done
fi

"${sync_cmd[@]}"

deploy::info "Post-processing assets synced."
deploy::info "If you use a site-specific scheduler script, submit it with deploy/hpc_submit.sh or your local Slurm wrapper."
