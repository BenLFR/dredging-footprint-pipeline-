#!/usr/bin/env bash
#SBATCH --job-name=pipeline_signal_safe
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G

set -euo pipefail

: "${WORKDIR:?Missing WORKDIR}"
: "${ENTRYPOINT:?Missing ENTRYPOINT}"

cleanup() {
  printf '[INFO] Cleanup hook triggered for job %s\n' "${SLURM_JOB_ID:-unknown}" >&2
}

on_term() {
  printf '[WARN] Termination signal received for job %s\n' "${SLURM_JOB_ID:-unknown}" >&2
  cleanup
  exit 143
}

trap on_term TERM INT
trap cleanup EXIT

mkdir -p "${WORKDIR}/logs"
cd "${WORKDIR}"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"

bash -lc "${ENTRYPOINT}"
