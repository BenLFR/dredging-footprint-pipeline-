#!/bin/bash
#SBATCH --job-name=step3_merge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

echo "=== ETAPE 3: FUSION ET GRID SEARCH (GRIT) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Configuration memoire
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Repertoires
PIPELINE_DIR=~/ais-pipeline/pipeline_V6
LOGS_DIR=$PIPELINE_DIR/logs

mkdir -p $LOGS_DIR
mkdir -p ~/scratch/output_V6

cd $PIPELINE_DIR

# Parametres: SPLIT_JOB_ID et RESULTS_DIR depuis environnement ou arguments
SPLIT_JOB_ID=${SPLIT_JOB_ID:-${1:-"12990"}}
RESULTS_DIR=${RESULTS_DIR:-~/scratch/ais_results_14542}

echo "Job fractionnement reference: $SPLIT_JOB_ID"
echo "Dossier resultats Step 2: $RESULTS_DIR"

# Verification fichiers d'entree
echo ""
echo "Verification des fichiers *_clean.rds:"
CLEAN_COUNT=$(ls $RESULTS_DIR/*_clean.rds 2>/dev/null | wc -l)
echo "  Fichiers trouves: $CLEAN_COUNT"

if [ "$CLEAN_COUNT" -eq 0 ]; then
    echo "ERREUR: Aucun fichier *_clean.rds dans $RESULTS_DIR"
    exit 1
fi

ls -lh $RESULTS_DIR/*_clean.rds | head -5
if [ "$CLEAN_COUNT" -gt 5 ]; then
    echo "  ... et $(($CLEAN_COUNT - 5)) autres"
fi

# Verification fichier R
echo ""
echo "Verification fichier R: $(ls -la step3_merge_final.R 2>/dev/null | awk '{print $NF}' || echo 'FICHIER MANQUANT')"

echo ""
echo "Lancement fusion et grid search..."

# Export des variables pour le script R
export SPLIT_JOB_ID
export RESULTS_DIR
export SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-8}

Rscript step3_merge_final.R 2>&1

exit_code=$?

# Deplacer les logs
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" $LOGS_DIR/
fi
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" $LOGS_DIR/
fi

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "Fusion et grid search termines avec succes: $(date)"

    echo ""
    echo "=== RESUME FINAL ==="
    echo "Fichiers generes dans ~/scratch/output_V6/:"
    ls -lh ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null | tail -3 || echo "  Fichier de donnees fusionnees non trouve"
    ls -lh ~/scratch/output_V6/dragage_gridsearch_results_V6_*.rds 2>/dev/null | tail -3 || echo "  Resultats grid search non trouves"
else
    echo ""
    echo "ERREUR lors de la fusion: code $exit_code"
    exit $exit_code
fi

echo ""
echo "=== ETAPE 3 TERMINEE ==="
