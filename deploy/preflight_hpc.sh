#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
run_ping=0

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --ping)
      run_ping=1
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/preflight_hpc.sh [--env-file deploy/config.env] [--ping]

Validates required commands, deploy variables, local sync items, and optional SSH connectivity.
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_commands bash ssh rsync
deploy::require_vars HPC_HOST HPC_BASEDIR

if [[ -n "${SSH_CONFIG_FILE:-}" && ! -f "${SSH_CONFIG_FILE}" ]]; then
  deploy::usage_error "SSH_CONFIG_FILE does not exist: ${SSH_CONFIG_FILE}"
fi

if [[ -n "${SSH_KEY_PATH:-}" && ! -f "${SSH_KEY_PATH}" ]]; then
  deploy::usage_error "SSH_KEY_PATH does not exist: ${SSH_KEY_PATH}"
fi

if [[ -z "${HPC_SCRATCH:-}" ]]; then
  deploy::warn "HPC_SCRATCH is not set. Scratch-first staging is recommended for high-I/O workflows."
fi

deploy::info "Environment file: ${DEPLOY_ENV_FILE}"
deploy::info "SSH target: $(deploy::ssh_target)"
deploy::info "Remote project root: ${HPC_BASEDIR}"

if [[ -n "${HPC_SCRATCH:-}" ]]; then
  deploy::info "Remote scratch root: ${HPC_SCRATCH}"
fi

if [[ -n "${SYNC_ITEMS:-}" ]]; then
  for item in ${SYNC_ITEMS}; do
    if deploy::resolve_local_path "${item}" >/dev/null; then
      deploy::info "Sync item available: ${item}"
    else
      deploy::warn "Sync item not found locally: ${item}"
    fi
  done
fi

if [[ "${run_ping}" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/hpc_ping.sh" --env-file "${DEPLOY_ENV_FILE}"
fi

deploy::info "Preflight checks completed."
