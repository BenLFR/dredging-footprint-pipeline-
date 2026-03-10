#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
remote_command=""

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --command)
      [[ $# -ge 2 ]] || deploy::usage_error "--command requires a value"
      remote_command="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/hpc_ping.sh [--env-file deploy/config.env] [--command "hostname"]

Runs a lightweight connectivity and scheduler-availability check on the remote cluster.
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
deploy::require_vars HPC_HOST

if [[ -z "${remote_command}" ]]; then
  remote_command=$'hostname\nwhoami\npwd\nif command -v sbatch >/dev/null 2>&1; then sbatch --version | head -n 1; else echo "sbatch=missing"; fi\nif command -v sacct >/dev/null 2>&1; then echo "sacct=available"; else echo "sacct=missing"; fi\nif [ -n "${SCRATCH:-}" ]; then echo "remote_scratch=${SCRATCH}"; fi'
fi

deploy::info "Pinging $(deploy::ssh_target)"
deploy::run_remote_shell "${remote_command}"
