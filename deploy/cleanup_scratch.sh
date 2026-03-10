#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
dry_run=0
remove_after_stage=0
declare -a stage_specs=()
declare -a remove_items=()

resolve_scratch_path() {
  local requested_path="$1"

  if [[ "${requested_path}" = /* ]] || [[ "${requested_path}" == ~* ]]; then
    printf '%s\n' "${requested_path}"
  else
    printf '%s/%s\n' "${HPC_SCRATCH%/}" "${requested_path}"
  fi
}

resolve_stage_out_dest() {
  local requested_path="$1"

  if [[ "${requested_path}" = /* ]] || [[ "${requested_path}" == ~* ]]; then
    printf '%s\n' "${requested_path}"
  else
    printf '%s/%s\n' "${HPC_BASEDIR%/}" "${requested_path}"
  fi
}

ensure_under_scratch() {
  local target_path="$1"

  case "${target_path}" in
    "${HPC_SCRATCH%/}"|"${HPC_SCRATCH%/}/"*)
      ;;
    *)
      deploy::usage_error "Cleanup target must stay under HPC_SCRATCH: ${target_path}"
      ;;
  esac
}

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
    --remove-after-stage)
      remove_after_stage=1
      shift
      ;;
    --stage-out)
      [[ $# -ge 2 ]] || deploy::usage_error "--stage-out requires SOURCE:DEST or SOURCE"
      stage_specs+=("$2")
      shift 2
      ;;
    --remove)
      [[ $# -ge 2 ]] || deploy::usage_error "--remove requires a path"
      remove_items+=("$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/cleanup_scratch.sh [options]

Options:
  --env-file PATH
  --dry-run
  --remove-after-stage
  --stage-out SOURCE[:DEST]
  --remove PATH

SOURCE is resolved under HPC_SCRATCH unless absolute.
DEST is resolved under HPC_BASEDIR unless absolute.

Examples:
  bash deploy/cleanup_scratch.sh --dry-run --stage-out output_V6:output_V6
  bash deploy/cleanup_scratch.sh --stage-out logs:logs --remove-after-stage
  bash deploy/cleanup_scratch.sh --remove scratch_run_tmp
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_commands ssh
deploy::require_vars HPC_HOST HPC_BASEDIR HPC_SCRATCH

if (( ${#stage_specs[@]} == 0 )) && [[ -n "${SCRATCH_STAGE_OUT_ITEMS:-}" ]]; then
  for item in ${SCRATCH_STAGE_OUT_ITEMS}; do
    stage_specs+=("${item}")
  done
fi

if (( ${#remove_items[@]} == 0 )) && [[ -n "${SCRATCH_CLEANUP_ITEMS:-}" ]]; then
  for item in ${SCRATCH_CLEANUP_ITEMS}; do
    remove_items+=("${item}")
  done
fi

if (( ${#stage_specs[@]} == 0 && ${#remove_items[@]} == 0 )); then
  deploy::usage_error "Nothing to do. Provide --stage-out and/or --remove."
fi

stage_out_item() {
  local spec="$1"
  local source_spec="$spec"
  local dest_spec=""
  local source_path=""
  local dest_path=""
  local dest_parent=""
  local rsync_dry_run=""
  local remote_shell=""

  if [[ "${spec}" == *:* ]]; then
    source_spec="${spec%%:*}"
    dest_spec="${spec#*:}"
  else
    dest_spec="$(basename "${spec%/}")"
  fi

  source_path="$(resolve_scratch_path "${source_spec}")"
  dest_path="$(resolve_stage_out_dest "${dest_spec}")"
  dest_parent="$(dirname "${dest_path}")"

  ensure_under_scratch "${source_path}"

  if (( dry_run == 1 )); then
    rsync_dry_run=" --dry-run"
  fi

  deploy::info "Stage-out ${source_path} -> ${dest_path}"

  remote_shell="if [[ -d $(printf '%q' "${source_path}") ]]; then "
  remote_shell+="mkdir -p $(printf '%q' "${dest_path}") && "
  remote_shell+="rsync -a --human-readable --itemize-changes${rsync_dry_run} "
  remote_shell+="$(printf '%q' "${source_path%/}/") $(printf '%q' "${dest_path%/}/"); "
  remote_shell+="elif [[ -e $(printf '%q' "${source_path}") ]]; then "
  remote_shell+="mkdir -p $(printf '%q' "${dest_parent}") && "
  remote_shell+="rsync -a --human-readable --itemize-changes${rsync_dry_run} "
  remote_shell+="$(printf '%q' "${source_path}") $(printf '%q' "${dest_path}"); "
  remote_shell+="else echo $(printf '%q' "Missing scratch path: ${source_path}") >&2; exit 1; fi"

  deploy::run_remote_shell "${remote_shell}"

  if (( remove_after_stage == 1 )); then
    remove_items+=("${source_path}")
  fi
}

remove_remote_item() {
  local requested_path="$1"
  local target_path=""
  local remote_shell=""

  target_path="$(resolve_scratch_path "${requested_path}")"
  ensure_under_scratch "${target_path}"

  if (( dry_run == 1 )); then
    deploy::info "Dry run: would remove ${target_path}"
    return 0
  fi

  deploy::info "Removing ${target_path}"
  remote_shell="if [[ -e $(printf '%q' "${target_path}") || -L $(printf '%q' "${target_path}") ]]; then "
  remote_shell+="rm -rf -- $(printf '%q' "${target_path}"); "
  remote_shell+="else echo $(printf '%q' "Skipping missing cleanup target: ${target_path}") >&2; fi"
  deploy::run_remote_shell "${remote_shell}"
}

for spec in "${stage_specs[@]}"; do
  stage_out_item "${spec}"
done

for item in "${remove_items[@]}"; do
  remove_remote_item "${item}"
done

deploy::info "Scratch cleanup workflow completed."