#!/usr/bin/env bash
# =============================================================================
# run_full_pipeline.sh — Pipeline orchestrator (local SSH or on-cluster relay)
#
# Works in two modes automatically:
#   - From your local machine : SSHes into the cluster to submit jobs
#   - From the cluster itself : submits sbatch directly via a relay job
#
# Usage:
#   bash deploy/run_full_pipeline.sh --env-file deploy/config.grit.env
#   bash deploy/run_full_pipeline.sh --env-file deploy/config.grit.env --from-step 4
#   bash deploy/run_full_pipeline.sh --env-file deploy/config.grit.env --include-co2model
#   bash deploy/run_full_pipeline.sh --env-file deploy/config.grit.env \
#       --from-step 2 --split-job-id <step1_jobid>
#
# Dependency chain:
#   JOB0 (step0)
#    └─ JOB1 (step1)
#        └─ JOB_RELAY (reads vessel count N, submits everything below)
#             └─ JOB2 (step2 array 1-N%20)
#                  └─ JOB3 (step3 merge)
#                       └─ JOB4 (step4 lithology)
#                            └─ JOB5A (step5 make tiles)
#                                 └─ JOB5B (step5 tile array)
#                                      └─ JOB5C (step5 merge tiles)
#                                           └─ JOB6 (step6 CRI)
#                                                └─ JOB7 (step7 Jdredge)
#                                                     └─ [JOB_CO2] optional
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_common.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
env_file=""
from_step=0
include_co2=0
split_job_id_arg=""
results_dir_arg=""

while (($# > 0)); do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || deploy::usage_error "--env-file requires a path"
      env_file="$2"; shift 2 ;;
    --from-step)
      [[ $# -ge 2 ]] || deploy::usage_error "--from-step requires a value"
      from_step="$2"; shift 2 ;;
    --include-co2model)
      include_co2=1; shift ;;
    --split-job-id)
      [[ $# -ge 2 ]] || deploy::usage_error "--split-job-id requires a value"
      split_job_id_arg="$2"; shift 2 ;;
    --results-dir)
      [[ $# -ge 2 ]] || deploy::usage_error "--results-dir requires a value"
      results_dir_arg="$2"; shift 2 ;;
    --help|-h)
      cat <<'EOF'
Usage: bash deploy/run_full_pipeline.sh [options]

Options:
  --env-file PATH           Load cluster config from PATH (required)
  --from-step N             Resume from step N (0-8)
  --include-co2model        Also submit the CO2 model after step 7
  --split-job-id JOB_ID     Required when --from-step 2 or 3
  --results-dir PATH        Required when --from-step 3

Run from your local machine (SSH mode) or directly on the cluster (relay mode).
EOF
      exit 0 ;;
    *)
      deploy::usage_error "Unknown option: $1" ;;
  esac
done

if ! [[ "${from_step}" =~ ^[0-9]+$ ]] || (( from_step < 0 || from_step > 8 )); then
  deploy::usage_error "--from-step must be an integer between 0 and 8"
fi

if (( from_step == 2 || from_step == 3 )) && [[ -z "${split_job_id_arg}" ]]; then
  deploy::usage_error "--split-job-id is required for --from-step 2 or 3"
fi

if (( from_step == 3 )) && [[ -z "${results_dir_arg}" ]]; then
  deploy::usage_error "--results-dir is required for --from-step 3"
fi

# ── Load config ───────────────────────────────────────────────────────────────
deploy::load_env "${env_file}"

if deploy::is_local_mode; then
  deploy::require_vars HPC_BASEDIR
else
  deploy::require_commands ssh
  deploy::require_vars HPC_HOST HPC_BASEDIR
fi

# ── Resolve runtime paths ─────────────────────────────────────────────────────
PIPELINE_DIR_REMOTE="${PIPELINE_DIR_REMOTE:-${HPC_BASEDIR%/}/pipeline}"
PIPELINE_WORK_ROOT_REMOTE="${PIPELINE_WORK_ROOT_REMOTE:-${HPC_SCRATCH:-}}"
LOG_DIR="${REMOTE_LOG_DIR:-${HPC_BASEDIR%/}/logs}"

RUNTIME_PIPELINE_DIR="${PIPELINE_DIR:-${PIPELINE_DIR_REMOTE}}"
RUNTIME_SCRATCH_DIR="${SCRATCH_DIR:-${PIPELINE_WORK_ROOT_REMOTE}}"
RUNTIME_CONFIG_DIR="${CONFIG_DIR:-${RUNTIME_SCRATCH_DIR}/configuration}"
RUNTIME_OUTPUT_DIR="${OUTPUT_DIR:-${RUNTIME_SCRATCH_DIR}/output_V6}"
RUNTIME_AIS_INPUT_FILE="${AIS_INPUT_FILE:-${RUNTIME_SCRATCH_DIR}/AIS_data/ais_filtered.csv}"
RUNTIME_PARTITION="${SLURM_PARTITION:-emlab_nodes}"
RUNTIME_ACCOUNT="${SLURM_ACCOUNT:-}"
STEP2_CONCURRENCY="${STEP2_ARRAY_CONCURRENCY:-20}"
CO2_SCRIPT="${CO2_SCRIPT:-}"

COMMON_EXPORTS="PIPELINE_DIR=${RUNTIME_PIPELINE_DIR},SCRATCH_DIR=${RUNTIME_SCRATCH_DIR},CONFIG_DIR=${RUNTIME_CONFIG_DIR},OUTPUT_DIR=${RUNTIME_OUTPUT_DIR},AIS_INPUT_FILE=${RUNTIME_AIS_INPUT_FILE}"

# ── Script paths (subdirectory layout) ───────────────────────────────────────
STEP0_SCRIPT="${STEP0_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step0/step0_window_select.sh}"
STEP1_SCRIPT="${STEP1_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step1/step1_split_vessels.sh}"
STEP2_SCRIPT="${STEP2_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step2/step2_process_array.sh}"
STEP3_SCRIPT="${STEP3_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step3/step3_merge.sh}"
STEP4_SCRIPT="${STEP4_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step4/step4_add_lithology.sh}"
STEP5A_R="${RUNTIME_PIPELINE_DIR}/step5/step5_make_tiles.R"
STEP5B_SCRIPT="${STEP5B_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step5/step5_tile_job.sh}"
STEP5C_SCRIPT="${STEP5C_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step5/step5_merge_slurm.sh}"
STEP6_SCRIPT="${STEP6_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step6/step6_calculate_cri.sh}"
STEP7_SCRIPT="${STEP7_SCRIPT:-${RUNTIME_PIPELINE_DIR}/step7/step7_export_jdredge.sh}"

# ── Manifest ──────────────────────────────────────────────────────────────────
run_id="$(date +%Y%m%d_%H%M%S)"
manifest_path="${HPC_BASEDIR}/logs/pipeline_run_${run_id}.txt"

deploy::run_remote_shell "mkdir -p $(printf '%q' "${LOG_DIR}")"

record_job() {
  printf '%s=%s\n' "$1" "$2"
  deploy::run_remote_shell "printf '%s=%s\n' $(printf '%q' "$1") $(printf '%q' "$2") >> $(printf '%q' "${manifest_path}")"
}

# ── Submit helper (works in both local and SSH mode) ──────────────────────────
submit_remote() {
  # submit_remote [sbatch args...] SCRIPT
  # Returns the job ID printed by sbatch --parsable
  local shell_code
  local account_arg=""
  [[ -n "${RUNTIME_ACCOUNT}" ]] && account_arg="--account ${RUNTIME_ACCOUNT}"

  shell_code="sbatch --parsable --partition=${RUNTIME_PARTITION} ${account_arg} \
    --output=$(printf '%q' "${LOG_DIR}/%x_%j.out") \
    --error=$(printf '%q' "${LOG_DIR}/%x_%j.err") \
    $(printf '%q ' "$@")"

  deploy::run_remote_shell "${shell_code}" | tail -n1 | tr -d '[:space:]'
}

# ── STEP 0 ────────────────────────────────────────────────────────────────────
job0=""
job1=""
prev=""

if (( from_step <= 0 )); then
  job0="$(submit_remote --export "ALL,${COMMON_EXPORTS}" "${STEP0_SCRIPT}")"
  record_job step0 "${job0}"
  prev="${job0}"
fi

# ── STEP 1 ────────────────────────────────────────────────────────────────────
if (( from_step <= 1 )); then
  dep_arg="${prev:+--dependency=afterok:${prev}}"
  job1="$(submit_remote ${dep_arg:-} --export "ALL,${COMMON_EXPORTS}" "${STEP1_SCRIPT}")"
  record_job step1 "${job1}"
  prev="${job1}"
fi

# ── RELAY JOB (submits steps 2-7 after step1 finishes) ───────────────────────
#
# The relay is a bash script written to disk and submitted as a SLURM job.
# It runs ON the cluster after step1, reads navires_metadata.csv, and
# submits steps 2-7 with proper afterok dependency chains.
# This avoids trying to read the metadata before step1 has run.

relay_script="${LOG_DIR}/relay_${run_id}.sh"

deploy::run_remote_shell "cat > $(printf '%q' "${relay_script}") << 'RELAY_EOF'
#!/bin/bash
set -euo pipefail

FROM_STEP=${from_step}
CO2=${include_co2}
PIPELINE_DIR=${RUNTIME_PIPELINE_DIR}
SCRATCH_DIR=${RUNTIME_SCRATCH_DIR}
LOG_DIR=${LOG_DIR}
MANIFEST=${manifest_path}
PART=${RUNTIME_PARTITION}
ACCOUNT=${RUNTIME_ACCOUNT}
CONCURRENCY=${STEP2_CONCURRENCY}
STEP2_SCRIPT=${STEP2_SCRIPT}
STEP3_SCRIPT=${STEP3_SCRIPT}
STEP4_SCRIPT=${STEP4_SCRIPT}
STEP5A_R=${STEP5A_R}
STEP5B_SCRIPT=${STEP5B_SCRIPT}
STEP5C_SCRIPT=${STEP5C_SCRIPT}
STEP6_SCRIPT=${STEP6_SCRIPT}
STEP7_SCRIPT=${STEP7_SCRIPT}
CO2_SCRIPT=${CO2_SCRIPT}
JOB1=${job1}
SPLIT_JOB_ID_ARG=${split_job_id_arg}
RESULTS_DIR_ARG=${results_dir_arg}
COMMON_EXPORTS=${COMMON_EXPORTS}

ACCOUNT_ARG=\${ACCOUNT:+--account \$ACCOUNT}

submit() {
  sbatch --parsable --partition=\"\$PART\" \${ACCOUNT_ARG:-} \\
    --output=\"\${LOG_DIR}/%x_%j.out\" \\
    --error=\"\${LOG_DIR}/%x_%j.err\" \\
    \"\$@\" | tail -n1 | tr -d '[:space:]'
}

log() { printf '%s=%s\n' \"\$1\" \"\$2\" | tee -a \"\$MANIFEST\"; }

# ── Locate split directory ────────────────────────────────────────────────────
EFFECTIVE_JOB1=\"\${JOB1:-\$SPLIT_JOB_ID_ARG}\"
[[ -n \"\$EFFECTIVE_JOB1\" ]] || { echo \"[ERROR] No step1 job ID available\"; exit 1; }
SPLIT_DIR=\"\${SCRATCH_DIR}/ais_split_\${EFFECTIVE_JOB1}\"

PREV=\"\"
JOB2=\"\"

# ── STEP 2: per-vessel array ──────────────────────────────────────────────────
if (( FROM_STEP <= 2 )); then
  META=\"\${SPLIT_DIR}/navires_metadata.csv\"
  [[ -f \"\$META\" ]] || { echo \"[ERROR] Metadata not found: \$META\"; exit 1; }
  N=\$(tail -n +2 \"\$META\" | wc -l | tr -d ' ')
  (( N > 0 )) || { echo \"[ERROR] No vessels in metadata\"; exit 1; }
  echo \"[INFO] Vessel count: \$N — submitting array 1-\${N}%\${CONCURRENCY}\"

  JOB2=\$(submit --array \"1-\${N}%\${CONCURRENCY}\" \\
    --export \"ALL,\${COMMON_EXPORTS},SPLIT_JOB_ID=\${EFFECTIVE_JOB1}\" \\
    \"\$STEP2_SCRIPT\")
  log step2 \"\$JOB2\"
  PREV=\"\$JOB2\"
fi

# ── STEP 3: merge ─────────────────────────────────────────────────────────────
if (( FROM_STEP <= 3 )); then
  if [[ -n \"\$JOB2\" ]]; then
    RESULTS_DIR=\"\${SCRATCH_DIR}/ais_results_\${JOB2}\"
  else
    RESULTS_DIR=\"\${RESULTS_DIR_ARG}\"
    [[ -d \"\$RESULTS_DIR\" ]] || { echo \"[ERROR] Results dir not found: \$RESULTS_DIR\"; exit 1; }
  fi

  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB3=\$(submit \${DEP:-} \\
    --export \"ALL,\${COMMON_EXPORTS},SPLIT_JOB_ID=\${EFFECTIVE_JOB1},RESULTS_DIR=\${RESULTS_DIR}\" \\
    \"\$STEP3_SCRIPT\")
  log step3 \"\$JOB3\"
  PREV=\"\$JOB3\"
fi

# ── STEP 4: lithology ─────────────────────────────────────────────────────────
if (( FROM_STEP <= 4 )); then
  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB4=\$(submit \${DEP:-} --export \"ALL,\${COMMON_EXPORTS}\" \"\$STEP4_SCRIPT\")
  log step4 \"\$JOB4\"
  PREV=\"\$JOB4\"
fi

# ── STEP 5a: make tiles ───────────────────────────────────────────────────────
if (( FROM_STEP <= 5 )); then
  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB5A=\$(submit \${DEP:-} --job-name step5_make_tiles \\
    --mem=8G --cpus-per-task=2 --time=00:30:00 \\
    --export \"ALL,\${COMMON_EXPORTS}\" \\
    --wrap \"Rscript \${STEP5A_R}\")
  log step5a \"\$JOB5A\"

  # ── STEP 5b: tile workers ─────────────────────────────────────────────────
  JOB5B=\$(submit --dependency=afterok:\$JOB5A \\
    --export \"ALL,\${COMMON_EXPORTS}\" \"\$STEP5B_SCRIPT\")
  log step5b \"\$JOB5B\"

  # ── STEP 5c: merge tiles ──────────────────────────────────────────────────
  JOB5C=\$(submit --dependency=afterok:\$JOB5B \\
    --export \"ALL,\${COMMON_EXPORTS}\" \"\$STEP5C_SCRIPT\")
  log step5c \"\$JOB5C\"
  PREV=\"\$JOB5C\"
fi

# ── STEP 6: CRI ───────────────────────────────────────────────────────────────
if (( FROM_STEP <= 6 )); then
  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB6=\$(submit \${DEP:-} --export \"ALL,\${COMMON_EXPORTS}\" \"\$STEP6_SCRIPT\")
  log step6 \"\$JOB6\"
  PREV=\"\$JOB6\"
fi

# ── STEP 7: export Jdredge ────────────────────────────────────────────────────
if (( FROM_STEP <= 7 )); then
  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB7=\$(submit \${DEP:-} --export \"ALL,\${COMMON_EXPORTS}\" \"\$STEP7_SCRIPT\")
  log step7 \"\$JOB7\"
  PREV=\"\$JOB7\"
fi

# ── CO2 model (optional) ──────────────────────────────────────────────────────
if (( CO2 == 1 )) && [[ -n \"\${CO2_SCRIPT}\" ]]; then
  DEP=\${PREV:+--dependency=afterok:\$PREV}
  JOB_CO2=\$(submit \${DEP:-} \"\$CO2_SCRIPT\")
  log co2model \"\$JOB_CO2\"
fi

echo \"[INFO] Relay done. All steps submitted. Monitor: squeue -u \$USER\"
echo \"[INFO] Manifest: \$MANIFEST\"
RELAY_EOF
chmod +x $(printf '%q' "${relay_script}")"

# ── Submit relay job ──────────────────────────────────────────────────────────
dep_relay="${prev:+--dependency=afterok:${prev}}"
job_relay="$(submit_remote ${dep_relay:-} \
  --job-name pipeline_relay --mem=512M --time=00:30:00 \
  "${relay_script}")"
record_job relay "${job_relay}"

# ── Summary ───────────────────────────────────────────────────────────────────
deploy::info "============================================================"
deploy::info "  Pipeline submitted — Run ID: ${run_id}"
deploy::info "  From step:    ${from_step}"
deploy::info "  CO2 model:    ${include_co2}"
deploy::info "  Relay job:    ${job_relay}"
deploy::info "  Manifest:     ${manifest_path}"
deploy::info "  Monitor:      squeue -u ${HPC_USER:-\$USER}"
deploy::info "  Logs:         ${LOG_DIR}/"
deploy::info "============================================================"
