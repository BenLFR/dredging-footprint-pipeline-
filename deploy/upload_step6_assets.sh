#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
carbon_dir=""
trawling_history_path=""

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
    --carbon-dir)
      [[ $# -ge 2 ]] || deploy::usage_error "--carbon-dir requires a path"
      carbon_dir="$2"
      shift 2
      ;;
    --trawling-history)
      [[ $# -ge 2 ]] || deploy::usage_error "--trawling-history requires a path"
      trawling_history_path="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/upload_step6_assets.sh [options]

Options:
  --env-file PATH
  --dry-run
  --carbon-dir PATH
  --trawling-history PATH

This syncs the public Step 6 code and optionally stages external Step 6 assets to remote scratch storage.
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

sync_cmd=(
  bash "${SCRIPT_DIR}/hpc_sync.sh"
  --env-file "${DEPLOY_ENV_FILE}"
  --item pipeline/step6/step6_calculate_cri.sh
  --item pipeline/step6/step6_calculate_cri.R
  --item pipeline/constants.R
)

if (( dry_run == 1 )); then
  sync_cmd+=(--dry-run)
fi

"${sync_cmd[@]}"

external_rsync_args=()
if (( dry_run == 1 )); then
  external_rsync_args+=(--dry-run)
fi

if [[ -n "${carbon_dir}" ]]; then
  if ! resolved_carbon_dir="$(deploy::resolve_local_path "${carbon_dir}")"; then
    deploy::usage_error "Carbon directory not found: ${carbon_dir}"
  fi

  deploy::require_vars STEP6_CARBON_REMOTE_DIR
  deploy::ensure_remote_dir "${STEP6_CARBON_REMOTE_DIR}"
  deploy::rsync_to_remote "${resolved_carbon_dir%/}/" "${STEP6_CARBON_REMOTE_DIR%/}/" "${external_rsync_args[@]}"
  deploy::info "Carbon rasters staged to ${STEP6_CARBON_REMOTE_DIR}"
else
  deploy::warn "No --carbon-dir provided. Step 6 will still require external carbon rasters on the cluster."
fi

if [[ -n "${trawling_history_path}" ]]; then
  if ! resolved_history_path="$(deploy::resolve_local_path "${trawling_history_path}")"; then
    deploy::usage_error "Trawling history file not found: ${trawling_history_path}"
  fi

  deploy::require_vars STEP6_TRAWLING_HISTORY_REMOTE_PATH
  deploy::ensure_remote_dir "$(dirname "${STEP6_TRAWLING_HISTORY_REMOTE_PATH}")"
  deploy::rsync_to_remote "${resolved_history_path}" "${STEP6_TRAWLING_HISTORY_REMOTE_PATH}" "${external_rsync_args[@]}"
  deploy::info "Trawling history staged to ${STEP6_TRAWLING_HISTORY_REMOTE_PATH}"
else
  deploy::warn "No --trawling-history provided. Step 6 will fall back to its default depletion behavior if the file is absent."
fi

deploy::info "Step 6 code sync completed."
deploy::info "Suggested submission command:"
printf 'bash deploy/hpc_submit.sh --export CARBON_DIR=%q pipeline/step6/step6_calculate_cri.sh\n' "${STEP6_CARBON_REMOTE_DIR:-<remote_carbon_dir>}"
