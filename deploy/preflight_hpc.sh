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

# Check that repo-shipped config files required for a full run are present locally.
deploy::info "Checking required local config files..."
_required_configs=(
  "config/ship_specs.yaml"
  "config/outlier_config_V6.yaml"
  "config/fi_parameters_with_freshness.yaml"
  "config/runtime_thresholds.csv"
)
_missing=0
for _f in "${_required_configs[@]}"; do
  if deploy::resolve_local_path "${_f}" >/dev/null 2>&1; then
    deploy::info "  OK: ${_f}"
  else
    deploy::warn "  MISSING: ${_f} (required for full pipeline run)"
    _missing=$((_missing + 1))
  fi
done
if [[ "${_missing}" -gt 0 ]]; then
  deploy::warn "${_missing} required config file(s) missing. Run 'git status' to check."
fi

# Remind about large external assets that cannot be shipped in the repo.
deploy::warn "Full run also requires external data assets in SCRATCH_DIR/configuration/:"
deploy::warn "  land_mask/, longhurst_v4_2010/, atwood_carbon_full/, trawling_history.rds, ocim/"
deploy::warn "  See config/README.md for download sources."

if [[ "${run_ping}" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/hpc_ping.sh" --env-file "${DEPLOY_ENV_FILE}"
fi

deploy::info "Preflight checks completed."
