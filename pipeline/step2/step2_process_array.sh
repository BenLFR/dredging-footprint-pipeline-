#!/bin/bash
#SBATCH --job-name=step2_NO_CROSS
#SBATCH --array=1-10
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --time=04:00:00
#SBATCH --output=logs/step2_process_%A_%a.out
#SBATCH --error=logs/step2_process_%A_%a.err

echo "=== STEP 2: VESSEL PROCESSING $SLURM_ARRAY_TASK_ID ==="
echo "Array Job ID: $SLURM_ARRAY_JOB_ID"
echo "Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start: $(date)"

# Conservative memory configuration
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Cluster-neutral path resolution
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"
CONFIG_DIR="${CONFIG_DIR:-${SCRATCH_DIR}/configuration}"
PIPELINE_DIR="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LOGS_DIR="${LOGS_DIR:-${SCRATCH_DIR}/../logs}"

# Critical geospatial configuration
export LAND_MASK_FILE="${LAND_MASK_FILE:-${CONFIG_DIR}/land_mask/land_polygons.shp}"
export LAND_MASK_BUFFER_M="${LAND_MASK_BUFFER_M:-0}"
export LAND_NEAR_COAST_KM="${LAND_NEAR_COAST_KM:-5}"
export SCRATCH_DIR CONFIG_DIR PIPELINE_DIR

# Land mask pre-flight check
if [ -f "$LAND_MASK_FILE" ]; then
    echo "Land mask found: $(ls -lh "$LAND_MASK_FILE" | awk '{print $5}')"
else
    echo "WARNING: Land mask NOT FOUND at: $LAND_MASK_FILE"
fi

# Directories
SPLIT_JOB_ID=${SPLIT_JOB_ID:?ERROR: SPLIT_JOB_ID must be set before running this script}
mkdir -p "${LOGS_DIR}"

echo "Starting vessel processing for task $SLURM_ARRAY_TASK_ID..."
echo "PIPELINE_DIR: $PIPELINE_DIR"
echo "SCRATCH_DIR:  $SCRATCH_DIR"
echo "Source: ${SCRATCH_DIR}/ais_split_${SPLIT_JOB_ID}/"
echo "LAND_MASK_FILE: $LAND_MASK_FILE"
echo "LAND_MASK_BUFFER_M: $LAND_MASK_BUFFER_M"
echo "LAND_NEAR_COAST_KM: $LAND_NEAR_COAST_KM"

# Tiling override for vessels with global footprint (too many tiles at 5 deg)
if [[ "${SLURM_ARRAY_TASK_ID}" -eq 2 ]]; then
  export LAND_TILE_DEG=10
  export LAND_TILE_MAX_TILES=500
  echo ">>> Tiling override for task $SLURM_ARRAY_TASK_ID: LAND_TILE_DEG=$LAND_TILE_DEG, LAND_TILE_MAX_TILES=$LAND_TILE_MAX_TILES"
fi

export SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID
export SPLIT_JOB_ID=$SPLIT_JOB_ID
Rscript "${PIPELINE_DIR}/step2_process_vessel.R" 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "Vessel $SLURM_ARRAY_TASK_ID processed successfully: $(date)"
else
    echo "[ERROR] Vessel $SLURM_ARRAY_TASK_ID failed: exit code $exit_code"
    exit $exit_code
fi

# Affichage résultat
echo "VESSEL SUMMARY $SLURM_ARRAY_TASK_ID:"
ls -lh "${SCRATCH_DIR}/ais_results_${SLURM_ARRAY_JOB_ID}/"*"${SLURM_ARRAY_TASK_ID}"*_clean.rds 2>/dev/null || echo "clean file not found"