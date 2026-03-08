#!/bin/bash
# Generic SLURM submit helper.
#
# Usage:
#   source config/local/cluster_overrides.env
#   bash config/templates/slurm/submit_step.sh pipeline/step6_calculate_cri.sh

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

sbatch "${SBATCH_ARGS[@]}" "$SCRIPT_PATH" "$@"
