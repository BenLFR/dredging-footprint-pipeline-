#!/bin/bash
###############################################################################
#  SLURM — STEP 6: Remineralised Carbon calculation (Cri)
###############################################################################
#SBATCH --job-name=step6_cri
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=08:00:00
# --chdir: set via HPC_PIPELINE_DIR env var or adjust to your cluster path
#SBATCH --output=logs/step6_cri_%j.out
#SBATCH --error=logs/step6_cri_%j.err
# #SBATCH --exclude=<node>  # uncomment to exclude a specific node

echo "=== STEP 6: CRI CALCULATION (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Start: $(date)"

# R setup (GRIT: no module system on compute nodes, R in PATH directly)
export R_LIBS_USER=~/R/library

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="${HPC_PIPELINE_DIR:-${SCRIPT_DIR}}"
SCRATCH_DIR="${SCRATCH_DIR:-${HOME}/scratch}"
mkdir -p "${SCRATCH_DIR}/output_V6"
mkdir -p "${SCRATCH_DIR}/tmp_terra"
mkdir -p "${SCRATCH_DIR}/logs"

cd "$PIPELINE_DIR" || { echo "ERROR: pipeline directory not found"; exit 2; }

echo "Working directory: $(pwd)"
echo "R library path: $R_LIBS_USER"

# Pre-flight: check Atwood carbon rasters
CARBON_DIR="${CARBON_DIR:-${SCRATCH_DIR}/configuration/atwood_carbon_full}"
if [ ! -d "$CARBON_DIR" ] || [ -z "$(ls "$CARBON_DIR"/*.tif 2>/dev/null)" ]; then
    echo "ERROR: Carbon rasters missing in $CARBON_DIR"
    echo "   Run first: bash deploy/upload_step6_assets.sh"
    exit 1
fi
echo "Carbon rasters: $(ls "$CARBON_DIR"/*.tif | wc -l) TIF files"

# Pre-flight: check f_i files (output from Step 5)
FI_FILES=$(find "${SCRATCH_DIR}/output_V6/" -name "fi_grid_*.parquet" -o -name "fi_grid_*.rds" 2>/dev/null | head -5)
if [ -z "$FI_FILES" ]; then
    echo "ERROR: No f_i files found in ${SCRATCH_DIR}/output_V6/"
    echo "   Run Step 5 first"
    exit 1
fi
echo "f_i files found:"
echo "$FI_FILES"

# Pre-flight: check constants.R
if [ ! -f constants.R ]; then
    echo "ERROR: constants.R missing in $(pwd)"
    exit 1
fi
echo "constants.R present"

echo ""
echo "Running step6_calculate_cri.R ..."

Rscript --vanilla -e "
  .libPaths('~/R/library')
  source('step6_calculate_cri.R')
"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "STEP 6 complete: $(date)"
    echo "Files generated:"
    ls -lh "${SCRATCH_DIR}/output_V6"/cri_final_* 2>/dev/null || echo "   [WARN] No cri_final files found"
else
    echo "ERROR: STEP 6 failed (code $exit_code)"
    exit $exit_code
fi
