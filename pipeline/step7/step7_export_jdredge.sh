#!/bin/bash
###############################################################################
#  SLURM — STEP 7: Export Jtrawl for OCIM2-48L
###############################################################################
#SBATCH --job-name=step7_jdredge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=2
#SBATCH --time=02:00:00
# --chdir: set via HPC_PIPELINE_DIR env var or adjust to your cluster path
#SBATCH --output=logs/step7_jdredge_%j.out
#SBATCH --error=logs/step7_jdredge_%j.err
# #SBATCH --exclude=<node>  # uncomment to exclude a specific node

echo "=== STEP 7: EXPORT Jtrawl (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Start: $(date)"

# R setup
export R_LIBS_USER=~/R/library

# Directories
PIPELINE_DIR=${HPC_PIPELINE_DIR:-~/ais-pipeline/pipeline_V6}
mkdir -p "$PIPELINE_DIR/logs"
mkdir -p ~/scratch/output_V6

cd "$PIPELINE_DIR" || { echo "ERROR: pipeline directory not found"; exit 2; }

echo "Working directory: $(pwd)"
echo "R library path: $R_LIBS_USER"

# Pre-flight: ocim_cache.mat
OCIM_CACHE=~/scratch/configuration/ocim/ocim_cache.mat
if [ ! -f "$OCIM_CACHE" ]; then
    echo "ERROR: ocim_cache.mat missing: $OCIM_CACHE"
    echo "   Run first: matlab -batch \"run('step7_extract_ocim_cache.m')\""
    exit 1
fi
echo "ocim_cache.mat: $(ls -lh "$OCIM_CACHE" | awk '{print $5}')"

# Pre-flight: cri_final_*.parquet
CRI_FILES=$(find ~/scratch/output_V6/ -name "cri_final_*.parquet" 2>/dev/null | head -5)
if [ -z "$CRI_FILES" ]; then
    echo "ERROR: No cri_final_*.parquet files in ~/scratch/output_V6/"
    echo "   Run Step 6 first"
    exit 1
fi
echo "cri_final files found:"
echo "$CRI_FILES"

# Pre-flight: constants.R
if [ ! -f constants.R ]; then
    echo "ERROR: constants.R missing in $(pwd)"
    exit 1
fi
echo "constants.R present"

# Pre-flight: R.matlab package
Rscript --vanilla -e "if (!requireNamespace('R.matlab', quietly=TRUE)) stop('R.matlab not installed')" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "R.matlab package missing. Installing..."
    Rscript --vanilla -e ".libPaths('~/R/library'); install.packages('R.matlab', repos='https://cloud.r-project.org', lib='~/R/library')"
fi

echo ""
echo "Running step7_export_jdredge.R ..."

Rscript --vanilla -e "
  .libPaths('~/R/library')
  source('step7_export_jdredge.R')
"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "STEP 7 complete: $(date)"
    echo "Files generated:"
    ls -lh ~/scratch/output_V6/jdredge_ocim2_48l_* 2>/dev/null || echo "   No jdredge files found"
else
    echo "ERROR: STEP 7 failed (code $exit_code)"
    exit $exit_code
fi
