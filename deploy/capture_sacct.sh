#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
output_file=""
declare -a job_ids=()

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || deploy::usage_error "--output requires a path"
      output_file="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/capture_sacct.sh [--env-file deploy/config.env] [--output reports.tsv] <job_id> [job_id...]

Captures Slurm accounting data for completed jobs and stores it locally as TSV.
EOF
      exit 0
      ;;
    *)
      job_ids+=("$1")
      shift
      ;;
  esac
done

deploy::load_env "${env_file}"
deploy::require_commands ssh
deploy::require_vars HPC_HOST

if (( ${#job_ids[@]} == 0 )); then
  deploy::usage_error "At least one job ID is required"
fi

if [[ -z "${output_file}" ]]; then
  mkdir -p "${DEPLOY_REPO_ROOT}/deploy/reports"
  output_file="${DEPLOY_REPO_ROOT}/deploy/reports/sacct_$(date +%Y%m%d_%H%M%S).tsv"
fi

job_spec="$(deploy::join_by_comma "${job_ids[@]}")"
printf 'JobID\tJobName\tState\tExitCode\tElapsed\tAllocCPUS\tMaxRSS\n' > "${output_file}"
deploy::run_remote_shell "sacct -j $(printf '%q' "${job_spec}") --format=JobID,JobName%40,State,ExitCode,Elapsed,AllocCPUS,MaxRSS -P --noheader" | tr '|' '\t' >> "${output_file}"

deploy::info "Wrote accounting summary to ${output_file}"
