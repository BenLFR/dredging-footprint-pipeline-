#!/bin/bash
#SBATCH --job-name=step3_merge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

echo "=== STEP 3: FUSION ET GRID SEARCH (GRIT) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start: $(date)"

# Memory configuration
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="${PIPELINE_DIR:-$SCRIPT_DIR}"
SCRATCH_DIR="${SCRATCH_DIR:-${HOME}/scratch}"
LOGS_DIR="${LOGS_DIR:-${SCRATCH_DIR}/logs}"

mkdir -p "$LOGS_DIR"
mkdir -p "${SCRATCH_DIR}/output_V6"

cd "$PIPELINE_DIR"

# Runtime transparency notice (not-blocking)
LIMITATIONS_DOC=${LIMITATIONS_DOC:-$PIPELINE_DIR/../documentation/LIMITATIONS.md}
echo ""
echo "METHODO WARNING: known study limitations apply to merged and classified tracks."
if [ -f "$LIMITATIONS_DOC" ]; then
    echo "See: $LIMITATIONS_DOC"
else
    echo "Limitations document not found: $LIMITATIONS_DOC"
fi

# Parameters: SPLIT_JOB_ID and RESULTS_DIR from environment or arguments
SPLIT_JOB_ID=${SPLIT_JOB_ID:-${1:-"12990"}}
RESULTS_DIR=${RESULTS_DIR:-${SCRATCH_DIR}/ais_results_${SPLIT_JOB_ID}}

echo "Job fractionnement reference: $SPLIT_JOB_ID"
echo "Directory results Step 2: $RESULTS_DIR"

# Input file verification
echo ""
echo "Verification the files *_clean.rds:"
CLEAN_COUNT=$(ls $RESULTS_DIR/*_clean.rds 2>/dev/null | wc -l)
echo " Files found: $CLEAN_COUNT"

if [ "$CLEAN_COUNT" -eq 0 ]; then
    echo "ERROR: No file *_clean.rds in $RESULTS_DIR"
    exit 1
fi

ls -lh $RESULTS_DIR/*_clean.rds | head -5
if [ "$CLEAN_COUNT" -gt 5 ]; then
    echo " ... et $(($CLEAN_COUNT - 5)) other"
fi

# R script verification
echo ""
echo "Verification file R: $(ls -the step3_merge_final.R 2>/dev/null | awk '{print $NF}' || echo 'FILE MISSING')"

echo ""
echo "Run fusion et grid search..."

# Export variables for the R script
export SPLIT_JOB_ID
export RESULTS_DIR
export SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-8}

Rscript step3_merge_final.R 2>&1

exit_code=$?

# Move logs
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" $LOGS_DIR/
fi
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" $LOGS_DIR/
fi

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "Fusion et grid search completed successfully: $(date)"

    echo ""
    echo "=== SUMMARY FINAL ==="
    echo "Files generes in ${SCRATCH_DIR}/output_V6/:"
    ls -lh "${SCRATCH_DIR}/output_V6"/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null | tail -3 || echo " File of data fusionnees not found"
    ls -lh "${SCRATCH_DIR}/output_V6"/dragage_gridsearch_results_V6_*.rds 2>/dev/null | tail -3 || echo " Results grid search not found"
else
    echo ""
    echo "ERROR lors of the fusion: code $exit_code"
    exit $exit_code
fi

echo ""
echo "=== STEP 3 COMPLETED ==="
