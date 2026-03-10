#!/bin/bash
# Generic SLURM submit helper.
#
# Usage:
# source config/local/cluster_overrides.env
# bash config/templates/slurm/submit_step.sh pipeline/step6_calculate_cri.sh

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash config/templates/slurm/submit_step.sh <script.sh> [extra sbatch args...]"
  exit 2
fi

SCRIPT_PATH="$1"
shift

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: script not found: $SCRIPT_PATH"
  exit 2
fi

SBATCH_ARGS=()

if [ -n "${SBATCH_JOB_NAME:-}" ]; then SBATCH_ARGS+=(--job-name "$SBATCH_JOB_NAME"); fi
if [ -n "${SBATCH_TIME:-}" ]; then SBATCH_ARGS+=(--time "$SBATCH_TIME"); fi
if [ -n "${SBATCH_MEM:-}" ]; then SBATCH_ARGS+=(--mem "$SBATCH_MEM"); fi
if [ -n "${SBATCH_CPUS_PER_TASK:-}" ]; then SBATCH_ARGS+=(--cpus-per-task "$SBATCH_CPUS_PER_TASK"); fi
if [ -n "${SBATCH_ARRAY:-}" ]; then SBATCH_ARGS+=(--array "$SBATCH_ARRAY"); fi
if [ -n "${SBATCH_DEPENDENCY:-}" ]; then SBATCH_ARGS+=(--dependency "$SBATCH_DEPENDENCY"); fi
if [ -n "${SBATCH_CHDIR:-}" ]; then SBATCH_ARGS+=(--chdir "$SBATCH_CHDIR"); fi
if [ -n "${SBATCH_OUTPUT:-}" ]; then SBATCH_ARGS+=(--output "$SBATCH_OUTPUT"); fi
if [ -n "${SBATCH_ERROR:-}" ]; then SBATCH_ARGS+=(--error "$SBATCH_ERROR"); fi
if [ -n "${SBATCH_EXPORT:-}" ]; then SBATCH_ARGS+=(--export "$SBATCH_EXPORT"); fi
if [ -n "${SBATCH_PARTITION:-}" ]; then SBATCH_ARGS+=(--partition "$SBATCH_PARTITION"); fi
if [ -n "${SBATCH_ACCOUNT:-}" ]; then SBATCH_ARGS+=(--account "$SBATCH_ACCOUNT"); fi
if [ -n "${SBATCH_QOS:-}" ]; then SBATCH_ARGS+=(--qos "$SBATCH_QOS"); fi
if [ -n "${SBATCH_CONSTRAINT:-}" ]; then SBATCH_ARGS+=(--constraint "$SBATCH_CONSTRAINT"); fi
if [ -n "${SBATCH_EXCLUDE:-}" ]; then SBATCH_ARGS+=(--exclude "$SBATCH_EXCLUDE"); fi
if [ -n "${SBATCH_NODELIST:-}" ]; then SBATCH_ARGS+=(--nodelist "$SBATCH_NODELIST"); fi

echo "Submitting: $SCRIPT_PATH"
if [ ${#SBATCH_ARGS[@]} -gt 0 ]; then
  echo "With cluster overrides: ${SBATCH_ARGS[*]}"
fi

JOB_ID=$(sbatch --parsable "${SBATCH_ARGS[@]}" "$SCRIPT_PATH" "$@")
echo "Submitted job: $JOB_ID"
