#!/bin/bash
# ============================================================================
# STEP 4 vNext - Ajout lithologie via HubOcean/dbSEABED
#
# FIX #1: Le dossier logs/ doit exister AVANT sbatch
# Usage:
#   mkdir -p ~/ais-pipeline/pipeline_V6/logs && sbatch step4_add_lithology.sh
# ============================================================================

#SBATCH --job-name=step4_lithology
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Note: output/error dans le repertoire courant, puis deplace dans logs/
# Ceci evite l'erreur si logs/ n'existe pas au moment du sbatch

echo "=== ETAPE 4: AJOUT LITHOLOGIE (HubOcean/dbSEABED) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Configuration memoire conservative
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Repertoires
PIPELINE_DIR=~/ais-pipeline/pipeline_V6
LOGS_DIR=$PIPELINE_DIR/logs

mkdir -p $LOGS_DIR

cd $PIPELINE_DIR

# Verification pre-requis: cache HubOcean
CACHE_DIR=~/scratch/hubocean_cache
if [ ! -d "$CACHE_DIR" ]; then
    echo "ERROR: HubOcean cache not found: $CACHE_DIR"
    echo "Executez d'abord sur login node: python prefetch_hubocean_stac.py"
    exit 1
fi

echo ""
echo "Cache HubOcean trouve:"
# Check both subdirectory structure (new) and flat structure (old)
echo "  texture:"
ls -lh $CACHE_DIR/texture/*.tif 2>/dev/null || ls -lh $CACHE_DIR/texture__*.tif 2>/dev/null || echo "    (none)"
echo "  hard_soft:"
ls -lh $CACHE_DIR/hard_soft/*.tif 2>/dev/null || ls -lh $CACHE_DIR/hard_soft__*.tif 2>/dev/null || echo "    (none)"
echo "  rock:"
ls -lh $CACHE_DIR/rock/*.tif 2>/dev/null || ls -lh $CACHE_DIR/rock__*.tif 2>/dev/null || echo "    (none)"

# Verification fichier AIS Step 3
AIS_DIR=~/scratch/output_V6
echo ""
echo "Fichiers AIS disponibles:"
ls -lh $AIS_DIR/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null || echo "  ERROR: No AIS file found"

# Espace disque
echo ""
echo "Espace disque disponible:"
df -h ~/scratch

echo ""
echo "Lancement Step 4..."

Rscript step4_add_lithology.R 2>&1

exit_code=$?

# Deplacer les logs dans le bon dossier
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" $LOGS_DIR/
fi
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" ]; then
    mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" $LOGS_DIR/
fi

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "Step 4 terminee avec succes: $(date)"

    echo ""
    echo "=== RESUME FINAL ==="
    ls -lh $AIS_DIR/AIS_with_lithology_*.rds 2>/dev/null | tail -5

    # Statistiques du fichier le plus recent
    latest_file=$(ls -t $AIS_DIR/AIS_with_lithology_*.rds 2>/dev/null | head -n 1)
    if [ -n "$latest_file" ]; then
        echo ""
        echo "Fichier de sortie: $(basename $latest_file)"
        echo "Taille: $(du -h $latest_file | cut -f1)"
    fi
else
    echo ""
    echo "ERROR Step 4: code $exit_code"
    exit $exit_code
fi

echo ""
echo "=== ETAPE 4 TERMINEE ==="
