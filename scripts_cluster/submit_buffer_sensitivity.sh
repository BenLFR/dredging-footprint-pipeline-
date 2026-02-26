#!/bin/bash
# ============================================================================
# submit_buffer_sensitivity.sh
# SLURM array job: test 5 tile buffer sizes from BUFFER_TEST_VALUES in
# constants.R and run step5 for each, tagging output by buffer size.
#
# BUFFER_TEST_VALUES (from constants.R): c(2000, 10000, 20000, 50000, 100000)
#   BUFFER_IDX 1 → 2000 m
#   BUFFER_IDX 2 → 10000 m
#   BUFFER_IDX 3 → 20000 m  (default, BUFFER_IDX=4 in constants.R → 50000)
#   BUFFER_IDX 4 → 50000 m  (production default)
#   BUFFER_IDX 5 → 100000 m
#
# Usage (GRIT cluster — R requires --partition=emlab_nodes):
#   cd ~/ais-pipeline/pipeline_V6
#   sbatch --partition=emlab_nodes scripts_cluster/submit_buffer_sensitivity.sh
# ============================================================================
#SBATCH --job-name=buf_sensitivity
#SBATCH --array=1-5
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/buffer_sensitivity_%A_%a.out
#SBATCH --error=/home/bloe/logs/buffer_sensitivity_%A_%a.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== BUFFER SENSITIVITY (job $SLURM_ARRAY_JOB_ID, task $SLURM_ARRAY_TASK_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# Buffer values matching BUFFER_TEST_VALUES in constants.R
BUFFER_VALUES=(2000 10000 20000 50000 100000)
BUFFER_IDX=$SLURM_ARRAY_TASK_ID
export BUFFER_IDX

BUFFER_KM=${BUFFER_VALUES[$((SLURM_ARRAY_TASK_ID - 1))]}
echo "BUFFER_IDX=$BUFFER_IDX  →  TILE_BUFFER_M=$BUFFER_KM m"

# Output tag: distinguish fi_grid outputs by buffer size
export FI_OUTPUT_TAG="buf${BUFFER_KM}m"

# R setup (GRIT: R in PATH, no module system on emlab_nodes)
export R_LIBS_USER=~/R/library
mkdir -p ~/logs
mkdir -p ~/scratch/output_V6

PIPELINE_DIR=~/ais-pipeline/pipeline_V6
cd "$PIPELINE_DIR" || { echo "Pipeline dir missing"; exit 2; }

echo "Running step5_tile_worker for all tiles with BUFFER_IDX=$BUFFER_IDX..."

# Run the full step5 merge-and-compute pipeline with this buffer setting
# The tile worker reads BUFFER_IDX from environment (via constants.R)
Rscript --vanilla -e "
  .libPaths('~/R/library')
  Sys.setenv(BUFFER_IDX = '$BUFFER_IDX')
  source('step5_modulaire/constants.R')
  cat('TILE_BUFFER_M set to:', TILE_BUFFER_M, '\n')
  # Tag output files with buffer size
  Sys.setenv(FI_OUTPUT_TAG = 'buf${BUFFER_KM}m')
  source('step5_compute_fi_global.R')
"

exit_code=$?
echo "Exit code: $exit_code"
if [ $exit_code -eq 0 ]; then
  echo "Buffer $BUFFER_KM m: COMPLETE at $(date)"
else
  echo "Buffer $BUFFER_KM m: FAILED (code $exit_code)"
  exit $exit_code
fi

# ── After all 5 tasks complete, compare results ──────────────────────────────
# Run manually after the array finishes:
#   Rscript scripts_principaux/compare_scenarios.R
