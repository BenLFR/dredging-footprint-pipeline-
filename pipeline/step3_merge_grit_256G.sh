#!/bin/bash
#SBATCH --job-name=step3_merge_256G
#SBATCH --mem=256G
#SBATCH --cpus-per-task=16
#SBATCH --time=12:00:00
#SBATCH --output=logs/step3_merge_%j.out
#SBATCH --error=logs/step3_merge_%j.err

set -euo pipefail

echo "=== STEP 3 OPTIMIZED (256G) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

PIPELINE_DIR=~/ais-pipeline/pipeline_V6
LOGS_DIR=$PIPELINE_DIR/logs
mkdir -p $LOGS_DIR ~/scratch/output_V6

cd $PIPELINE_DIR

SPLIT_JOB_ID=${SPLIT_JOB_ID:-${1:-"12990"}}
RESULTS_DIR=${RESULTS_DIR:-~/scratch/ais_results_14542}

echo "Split Job: $SPLIT_JOB_ID"
echo "Results dir: $RESULTS_DIR"

# Checkpoints
echo "Checkpoints existants:"
ls -lh ~/scratch/output_V6/checkpoints/*.rds 2>/dev/null || echo "  Aucun"

# Verification fichiers
CLEAN_COUNT=$(ls $RESULTS_DIR/*_clean.rds 2>/dev/null | wc -l)
echo "Fichiers clean: $CLEAN_COUNT"
[ "$CLEAN_COUNT" -eq 0 ] && { echo "ERREUR: aucun fichier *_clean.rds"; exit 1; }

export SPLIT_JOB_ID RESULTS_DIR
export SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-16}
export CV_FOLDS=5

echo "Lancement R (256G, 5 folds CV)..."
Rscript step3_merge_final.R 2>&1 | tee $LOGS_DIR/step3_merge_${SLURM_JOB_ID}.log

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "Succes: $(date)"
    ls -lh ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null | tail -3
else
    echo "ERREUR: code $exit_code"
    tail -30 $LOGS_DIR/step3_merge_${SLURM_JOB_ID}.log
    exit $exit_code
fi

echo "=== FIN STEP 3 ==="
