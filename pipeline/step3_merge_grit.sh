#!/bin/bash
#SBATCH --job-name=step3_merge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --output=logs/step3_merge_%j.out
#SBATCH --error=logs/step3_merge_%j.err

echo "=== ETAPE 3: FUSION ET GRID SEARCH (GRIT) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Configuration mono-thread pour éviter les conflits
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Répertoires
PIPELINE_DIR=~/ais-pipeline/pipeline_V6
mkdir -p $PIPELINE_DIR/logs
mkdir -p ~/scratch/output_V6

cd $PIPELINE_DIR

# Variables d'environnement pour le script R
export SPLIT_JOB_ID=${SPLIT_JOB_ID:-"12990"}
export RESULTS_DIR=${RESULTS_DIR:-"$HOME/scratch/ais_results_14542"}
export SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-8}

echo "SPLIT_JOB_ID: $SPLIT_JOB_ID"
echo "RESULTS_DIR: $RESULTS_DIR"
echo "Fichiers *_clean.rds disponibles:"
ls -lh $RESULTS_DIR/*_clean.rds 2>/dev/null | tail -5

echo "Lancement step3_merge_final.R..."
Rscript step3_merge_final.R 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "Step 3 terminee avec succes: $(date)"
    echo "Fichiers generes:"
    ls -lh ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null | tail -3
else
    echo "Erreur Step 3: code $exit_code"
    exit $exit_code
fi

echo "=== FIN ETAPE 3 ==="
