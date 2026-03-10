#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
skip_ocim=0
ocim_dir=""
co2model_src=""

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
    --no-ocim)
      skip_ocim=1
      shift
      ;;
    --ocim-dir)
      [[ $# -ge 2 ]] || deploy::usage_error "--ocim-dir requires a path"
      ocim_dir="$2"
      shift 2
      ;;
    --co2model-src)
      [[ $# -ge 2 ]] || deploy::usage_error "--co2model-src requires a path"
      co2model_src="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/upload_step7_assets.sh [options]

Options:
  --env-file PATH
  --dry-run
  --no-ocim
  --ocim-dir PATH
  --co2model-src PATH

This syncs the public Step 7 code and optionally stages OCIM/CO2 assets to remote scratch storage.
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
  --item pipeline/step7/step7_export_jdredge.sh
  --item pipeline/step7/step7_export_jdredge.R
  --item pipeline/step7/step7_extract_ocim_cache.py
  --item pipeline/step7/step7_extract_ocim_cache.m
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

if (( skip_ocim == 0 )); then
  if [[ -n "${ocim_dir}" ]]; then
    if ! resolved_ocim_dir="$(deploy::resolve_local_path "${ocim_dir}")"; then
      deploy::usage_error "OCIM directory not found: ${ocim_dir}"
    fi

    deploy::require_vars STEP7_OCIM_REMOTE_DIR
    deploy::ensure_remote_dir "${STEP7_OCIM_REMOTE_DIR}"
    deploy::rsync_to_remote "${resolved_ocim_dir%/}/" "${STEP7_OCIM_REMOTE_DIR%/}/" "${external_rsync_args[@]}"
    deploy::info "OCIM assets staged to ${STEP7_OCIM_REMOTE_DIR}"
  else
    deploy::warn "No --ocim-dir provided. Step 7 still requires OCIM assets on the cluster."
  fi
fi

if [[ -n "${co2model_src}" ]]; then
  if ! resolved_co2_dir="$(deploy::resolve_local_path "${co2model_src}")"; then
    deploy::usage_error "CO2 model source directory not found: ${co2model_src}"
  fi

  deploy::require_vars STEP7_OCIM_REMOTE_DIR
  deploy::ensure_remote_dir "${STEP7_OCIM_REMOTE_DIR}"
  deploy::rsync_to_remote "${resolved_co2_dir%/}/" "${STEP7_OCIM_REMOTE_DIR%/}/" "${external_rsync_args[@]}"
  deploy::info "CO2 model assets staged to ${STEP7_OCIM_REMOTE_DIR}"
elif [[ -z "${ocim_dir}" && ${skip_ocim} -eq 0 ]]; then
  deploy::warn "No --co2model-src provided. If the OCIM solver files are not already present on the cluster, request them from the upstream provider before running Step 7."
fi

deploy::info "Step 7 code sync completed."
deploy::info "Suggested next steps:"
printf '1. python3 %q\n' "${PIPELINE_DIR_REMOTE:-${HPC_BASEDIR%/}/pipeline}/step7/step7_extract_ocim_cache.py"
printf '2. bash deploy/hpc_submit.sh --export OCIM_DIR=%q pipeline/step7/step7_export_jdredge.sh\n' "${STEP7_OCIM_REMOTE_DIR:-<remote_ocim_dir>}"
