#!/usr/bin/env bash
# Generic local orchestrator for a remote Slurm pipeline deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

env_file=""
from_step=0
include_co2=0
split_job_id_arg=""
results_dir_arg=""
step2_array_arg=""
step2_array_concurrency="${STEP2_ARRAY_CONCURRENCY:-20}"

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"
      shift 2
      ;;
    --from-step)
      [[ $# -ge 2 ]] || deploy::usage_error "--from-step requires a value"
      from_step="$2"
      shift 2
      ;;
    --include-co2model)
      include_co2=1
      shift
      ;;
    --split-job-id)
      [[ $# -ge 2 ]] || deploy::usage_error "--split-job-id requires a value"
      split_job_id_arg="$2"
      shift 2
      ;;
    --results-dir)
      [[ $# -ge 2 ]] || deploy::usage_error "--results-dir requires a value"
      results_dir_arg="$2"
      shift 2
      ;;
    --step2-array)
      [[ $# -ge 2 ]] || deploy::usage_error "--step2-array requires a value"
      step2_array_arg="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/run_full_pipeline.sh [options]

Options:
  --env-file PATH
  --from-step N
  --include-co2model
  --split-job-id JOB_ID
  --results-dir REMOTE_PATH
  --step2-array SPEC

This submits the public pipeline wrappers to a remote Slurm cluster through deploy/hpc_submit.sh.
EOF
      exit 0
      ;;
    *)
      deploy::usage_error "Unknown option: $1"
      ;;
  esac
done

if ! [[ "${from_step}" =~ ^[0-9]+$ ]]; then
  deploy::usage_error "--from-step must be an integer"
fi

if (( from_step < 0 || from_step > 8 )); then
  deploy::usage_error "--from-step must be between 0 and 8"
fi

if (( (from_step == 2 || from_step == 3) )) && [[ -z "${split_job_id_arg}" ]]; then
  deploy::usage_error "--split-job-id is required for --from-step 2 or 3"
fi

if (( from_step == 3 )) && [[ -z "${results_dir_arg}" ]]; then
  deploy::usage_error "--results-dir is required for --from-step 3"
fi

deploy::load_env "${env_file}"
deploy::require_vars HPC_HOST HPC_BASEDIR

PIPELINE_DIR_REMOTE="${PIPELINE_DIR_REMOTE:-${HPC_BASEDIR%/}/pipeline}"
PIPELINE_WORK_ROOT_REMOTE="${PIPELINE_WORK_ROOT_REMOTE:-${HPC_SCRATCH:-}}"
REMOTE_LOG_DIR="${REMOTE_LOG_DIR:-${HPC_BASEDIR%/}/logs}"

STEP0_SCRIPT="${STEP0_SCRIPT:-pipeline/step0_window_select.sh}"
STEP1_SCRIPT="${STEP1_SCRIPT:-pipeline/step1_split_navires.sh}"
STEP2_SCRIPT="${STEP2_SCRIPT:-pipeline/step2_process_array.sh}"
STEP3_SCRIPT="${STEP3_SCRIPT:-pipeline/step3_merge_final.sh}"
STEP4_SCRIPT="${STEP4_SCRIPT:-pipeline/step4_add_lithology.sh}"
STEP5B_SCRIPT="${STEP5B_SCRIPT:-pipeline/step5_tile_job.sh}"
STEP5C_SCRIPT="${STEP5C_SCRIPT:-pipeline/step5_merge_slurm.sh}"
STEP6_SCRIPT="${STEP6_SCRIPT:-pipeline/step6_calculate_cri.sh}"
STEP7_SCRIPT="${STEP7_SCRIPT:-pipeline/step7_export_jtrawl.sh}"
CO2_SCRIPT="${CO2_SCRIPT:-}"

mkdir -p "${DEPLOY_REPO_ROOT}/deploy/reports"
run_id="$(date +%Y%m%d_%H%M%S)"
manifest_path="${DEPLOY_REPO_ROOT}/deploy/reports/pipeline_run_${run_id}.txt"

{
  printf '# Local deploy manifest\n'
  printf 'run_id=%s\n' "${run_id}"
  printf 'from_step=%s\n' "${from_step}"
  printf 'include_co2model=%s\n' "${include_co2}"
  printf 'ssh_target=%s\n' "$(deploy::ssh_target)"
  printf 'project_root=%s\n' "${HPC_BASEDIR}"
  printf 'pipeline_dir_remote=%s\n' "${PIPELINE_DIR_REMOTE}"
  printf 'pipeline_work_root_remote=%s\n' "${PIPELINE_WORK_ROOT_REMOTE:-unset}"
} > "${manifest_path}"

record_job() {
  local step_name="$1"
  local job_id="$2"
  printf '%s=%s\n' "${step_name}" "${job_id}" | tee -a "${manifest_path}"
}

submit_job() {
  local output
  output="$("$@" 2>&1)"
  printf '%s\n' "${output}" >&2
  printf '%s\n' "${output}" | tail -n 1 | tr -d '\r'
}

submit_remote_script() {
  local script_path="$1"
  shift

  submit_job bash "${SCRIPT_DIR}/hpc_submit.sh" --env-file "${DEPLOY_ENV_FILE}" --log-dir "${REMOTE_LOG_DIR}" "$@" "${script_path}"
}

submit_remote_wrap() {
  local wrap_command="$1"
  shift

  submit_job bash "${SCRIPT_DIR}/hpc_submit.sh" --env-file "${DEPLOY_ENV_FILE}" --log-dir "${REMOTE_LOG_DIR}" "$@" --wrap "${wrap_command}"
}

get_split_dir_remote() {
  local job_id="$1"
  [[ -n "${PIPELINE_WORK_ROOT_REMOTE}" ]] || deploy::usage_error "PIPELINE_WORK_ROOT_REMOTE or HPC_SCRATCH must be set to resolve split directories"
  printf '%s/ais_split_%s\n' "${PIPELINE_WORK_ROOT_REMOTE%/}" "${job_id}"
}

get_results_dir_remote() {
  local job_id="$1"
  [[ -n "${PIPELINE_WORK_ROOT_REMOTE}" ]] || deploy::usage_error "PIPELINE_WORK_ROOT_REMOTE or HPC_SCRATCH must be set to resolve results directories"
  printf '%s/ais_results_%s\n' "${PIPELINE_WORK_ROOT_REMOTE%/}" "${job_id}"
}

compute_step2_array_spec() {
  local split_job_id="$1"
  local split_dir_remote meta_remote remote_code count

  if [[ -n "${step2_array_arg}" ]]; then
    printf '%s\n' "${step2_array_arg}"
    return 0
  fi

  split_dir_remote="$(get_split_dir_remote "${split_job_id}")"
  meta_remote="${split_dir_remote%/}/navires_metadata.csv"

  remote_code=$(cat <<EOF
set -euo pipefail
META=$(printf '%q' "${meta_remote}")
if [[ ! -f "\${META}" ]]; then
  echo "Metadata file not found: \${META}" >&2
  exit 1
fi
tail -n +2 "\${META}" | wc -l
EOF
)

  count="$(deploy::run_remote_shell "${remote_code}" | tail -n 1 | tr -d '[:space:]')"

  if ! [[ "${count}" =~ ^[0-9]+$ ]] || (( count <= 0 )); then
    deploy::usage_error "Unable to derive a valid Step 2 array size from ${meta_remote}"
  fi

  printf '1-%s%%%s\n' "${count}" "${step2_array_concurrency}"
}

job0=""
job1=""
job2=""
prev_job=""

if (( from_step <= 0 )); then
  job0="$(submit_remote_script "${STEP0_SCRIPT}")"
  record_job step0 "${job0}"
  prev_job="${job0}"
fi

if (( from_step <= 1 )); then
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job1="$(submit_remote_script "${STEP1_SCRIPT}" "${dep_args[@]}")"
  record_job step1 "${job1}"
  prev_job="${job1}"
fi

if (( from_step <= 2 )); then
  step2_split_job_id="${job1:-${split_job_id_arg}}"
  [[ -n "${step2_split_job_id}" ]] || deploy::usage_error "Missing split job ID for Step 2"
  step2_array_spec="$(compute_step2_array_spec "${step2_split_job_id}")"
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job2="$(submit_remote_script "${STEP2_SCRIPT}" "${dep_args[@]}" --array "${step2_array_spec}" --export "SPLIT_JOB_ID=${step2_split_job_id}")"
  record_job step2 "${job2}"
  prev_job="${job2}"
fi

if (( from_step <= 3 )); then
  step3_split_job_id="${job1:-${split_job_id_arg}}"
  [[ -n "${step3_split_job_id}" ]] || deploy::usage_error "Missing split job ID for Step 3"

  if [[ -n "${results_dir_arg}" ]]; then
    step3_results_dir="$(deploy::remote_path "${results_dir_arg}")"
  else
    [[ -n "${job2}" ]] || deploy::usage_error "Missing Step 2 job ID or --results-dir for Step 3"
    step3_results_dir="$(get_results_dir_remote "${job2}")"
  fi

  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job3="$(submit_remote_script "${STEP3_SCRIPT}" "${dep_args[@]}" --export "SPLIT_JOB_ID=${step3_split_job_id}" --export "RESULTS_DIR=${step3_results_dir}")"
  record_job step3 "${job3}"
  prev_job="${job3}"
fi

if (( from_step <= 4 )); then
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job4="$(submit_remote_script "${STEP4_SCRIPT}" "${dep_args[@]}")"
  record_job step4 "${job4}"
  prev_job="${job4}"
fi

if (( from_step <= 5 )); then
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  step5a_wrap="cd $(printf '%q' "${PIPELINE_DIR_REMOTE}") && Rscript step5_make_tiles.R"
  job5a="$(submit_remote_wrap "${step5a_wrap}" "${dep_args[@]}" --job-name step5_make_tiles)"
  record_job step5a "${job5a}"

  job5b="$(submit_remote_script "${STEP5B_SCRIPT}" --dependency "afterok:${job5a}")"
  record_job step5b "${job5b}"

  job5c="$(submit_remote_script "${STEP5C_SCRIPT}" --dependency "afterok:${job5b}")"
  record_job step5c "${job5c}"
  prev_job="${job5c}"
fi

if (( from_step <= 6 )); then
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job6="$(submit_remote_script "${STEP6_SCRIPT}" "${dep_args[@]}")"
  record_job step6 "${job6}"
  prev_job="${job6}"
fi

if (( from_step <= 7 )); then
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job7="$(submit_remote_script "${STEP7_SCRIPT}" "${dep_args[@]}")"
  record_job step7 "${job7}"
  prev_job="${job7}"
fi

if (( include_co2 == 1 )); then
  [[ -n "${CO2_SCRIPT}" ]] || deploy::usage_error "--include-co2model requires CO2_SCRIPT to be set in deploy/config.env or the environment"
  dep_args=()
  [[ -n "${prev_job}" ]] && dep_args=(--dependency "afterok:${prev_job}")
  job_co2="$(submit_remote_script "${CO2_SCRIPT}" "${dep_args[@]}")"
  record_job co2model "${job_co2}"
fi

deploy::info "Pipeline orchestration manifest: ${manifest_path}"
