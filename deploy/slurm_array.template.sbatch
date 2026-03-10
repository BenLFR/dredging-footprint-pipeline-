#!/usr/bin/env bash
#SBATCH --job-name=pipeline_array
#SBATCH --output=logs/%x_%A_%a.out
#SBATCH --error=logs/%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --array=1-10

# Optional site-specific directives:
#SBATCH --partition=<partition>
#SBATCH --account=<account>

set -euo pipefail

: "${WORKDIR:?Missing WORKDIR}"
: "${ARRAY_ENTRYPOINT:?Missing ARRAY_ENTRYPOINT}"

mkdir -p "${WORKDIR}/logs"
cd "${WORKDIR}"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export TASK_ID="${SLURM_ARRAY_TASK_ID}"

bash -lc "${ARRAY_ENTRYPOINT}"
