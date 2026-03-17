#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
workdir=""
wrap_command=""
script_path=""
remote_log_dir=""
declare -a script_args=()
declare -a sbatch_args=()
declare -a export_items=()

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --chdir)
      [[ $# -ge 2 ]] || deploy::usage_error "--chdir requires a path"
      workdir="$2"
      shift 2
      ;;
    --log-dir)
      [[ $# -ge 2 ]] || deploy::usage_error "--log-dir requires a path"
      remote_log_dir="$2"
      shift 2
      ;;
    --wrap)
      [[ $# -ge 2 ]] || deploy::usage_error "--wrap requires a command"
      wrap_command="$2"
      shift 2
      ;;
    --array|--dependency|--job-name|--partition|--account|--qos|--time|--mem|--cpus-per-task|--output|--error)
      [[ $# -ge 2 ]] || deploy::usage_error "$1 requires a value"
      sbatch_args+=("$1" "$2")
      shift 2
      ;;
    --export)
      [[ $# -ge 2 ]] || deploy::usage_error "--export requires NAME=VALUE"
      export_items+=("$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/hpc_submit.sh [options] <remote_script> [script args...]
       bash deploy/hpc_submit.sh [options] --wrap "bash -lc 'echo hello'"

Options:
  --env-file PATH
  --chdir PATH
  --log-dir PATH
  --wrap COMMAND
  --array SPEC
  --dependency SPEC
  --job-name NAME
  --partition NAME
  --account NAME
  --qos NAME
  --time HH:MM:SS
  --mem SIZE
  --cpus-per-task N
  --output PATH
  --error PATH
  --export NAME=VALUE
EOF
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      deploy::usage_error "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

deploy::load_env "${env_file}"
if ! deploy::is_local_mode; then
  deploy::require_commands ssh
  deploy::require_vars HPC_HOST HPC_BASEDIR
else
  deploy::require_vars HPC_BASEDIR
fi

if [[ -n "${SLURM_PARTITION:-}" ]]; then
  sbatch_args+=(--partition "${SLURM_PARTITION}")
fi

if [[ -n "${SLURM_ACCOUNT:-}" ]]; then
  sbatch_args+=(--account "${SLURM_ACCOUNT}")
fi

if [[ -n "${SLURM_QOS:-}" ]]; then
  sbatch_args+=(--qos "${SLURM_QOS}")
fi

if [[ $# -gt 0 ]]; then
  script_path="$1"
  shift
  script_args=("$@")
fi

if [[ -n "${wrap_command}" && -n "${script_path}" ]]; then
  deploy::usage_error "Use either a script path or --wrap, not both"
fi

if [[ -z "${wrap_command}" && -z "${script_path}" ]]; then
  deploy::usage_error "Missing remote script path or --wrap command"
fi

if [[ -z "${workdir}" ]]; then
  workdir="${HPC_BASEDIR}"
fi

if [[ -z "${remote_log_dir}" ]]; then
  remote_log_dir="${REMOTE_LOG_DIR:-${HPC_BASEDIR%/}/logs}"
fi

has_output=0
has_error=0
arg_index=0
while (( arg_index < ${#sbatch_args[@]} )); do
  case "${sbatch_args[arg_index]}" in
    --output)
      has_output=1
      ;;
    --error)
      has_error=1
      ;;
  esac
  ((arg_index+=1))
done

if (( has_output == 0 )); then
  sbatch_args+=(--output "${remote_log_dir%/}/%x_%j.out")
fi

if (( has_error == 0 )); then
  sbatch_args+=(--error "${remote_log_dir%/}/%x_%j.err")
fi

export_spec="${SBATCH_EXPORT:-ALL}"
if (( ${#export_items[@]} > 0 )); then
  export_spec="$(deploy::join_by_comma "${export_spec}" "${export_items[@]}")"
fi

sbatch_cmd=(sbatch --parsable --chdir "${workdir}" --export "${export_spec}")
sbatch_cmd+=("${sbatch_args[@]}")

if [[ -n "${wrap_command}" ]]; then
  sbatch_cmd+=(--wrap "${wrap_command}")
else
  remote_script="$(deploy::remote_path "${script_path}")"
  sbatch_cmd+=("${remote_script}")
  if (( ${#script_args[@]} > 0 )); then
    sbatch_cmd+=("${script_args[@]}")
  fi
fi

remote_shell="mkdir -p $(printf '%q' "${remote_log_dir}") $(printf '%q' "${workdir}") && $(deploy::quote_args "${sbatch_cmd[@]}")"

deploy::info "Submitting to $(deploy::ssh_target)"
job_id="$(deploy::run_remote_shell "${remote_shell}")"
printf '%s\n' "${job_id}"
