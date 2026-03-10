#!/usr/bin/env bash
#SBATCH --job-name=pipeline_step
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G

# Optional site-specific directives:
#SBATCH --partition=<partition>
#SBATCH --account=<account>

set -euo pipefail

: "${WORKDIR:?Missing WORKDIR}"
: "${ENTRYPOINT:?Missing ENTRYPOINT}"

mkdir -p "${WORKDIR}/logs"
cd "${WORKDIR}"

# Adapt module and container setup for your site.
# module purge
# module load apptainer

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"

bash -lc "${ENTRYPOINT}"
