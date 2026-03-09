#!/bin/bash
# ============================================================================
# STEP 5 - WORKER TUILE (pipeline V6, cluster GRIT)
# ============================================================================

#SBATCH --job-name=step5_tile
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-525
#SBATCH --output=logs/step5_tile_%A_%a.out
#SBATCH --error=logs/step5_tile_%A_%a.err

echo "=== ETAPE 5: TRAITEMENT TUILE $SLURM_ARRAY_TASK_ID ==="
echo "Array Job ID: $SLURM_ARRAY_JOB_ID"
echo "Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Configuration memoire conservative
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Repertoires
PIPELINE_DIR=~/ais-pipeline/pipeline_V6
mkdir -p $PIPELINE_DIR/logs
mkdir -p ~/scratch/output_V6

cd $PIPELINE_DIR

TILE_ID=${SLURM_ARRAY_TASK_ID}
SCRIPT="$PIPELINE_DIR/step5_tile_worker.R"
TILES_FILE="$HOME/scratch/output_V6/tiles_1000km.gpkg"

echo "Lancement tuile $TILE_ID"
[ -f "$SCRIPT" ] || { echo "ERREUR: Script R manquant: $SCRIPT"; exit 1; }
[ -f "$TILES_FILE" ] || { echo "ERREUR: Fichier tuiles manquant: $TILES_FILE"; exit 1; }

# Verification skip si deja traite
OUT_FILE=~/scratch/output_V6/sar_$(printf "%03d" $TILE_ID).parquet
if [ -s "$OUT_FILE" ]; then
    echo "Sortie deja presente: $OUT_FILE - SKIP"
    exit 0
fi

export LD_LIBRARY_PATH=$HOME/lib:${LD_LIBRARY_PATH:-}
export R_LIBS_USER=$HOME/R/library
/usr/bin/Rscript "$SCRIPT" "$TILE_ID" 2>&1

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "Tuile $TILE_ID traitee avec succes: $(date)"
else
    echo "ERREUR tuile $TILE_ID: code $exit_code"
    exit $exit_code
fi
