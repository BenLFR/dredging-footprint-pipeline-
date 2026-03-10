#!/bin/bash
#SBATCH --account=def-wailung
#SBATCH --time=12:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#SBATCH --array=1-648
#SBATCH --output=slurm-%A_%a.out
#SBATCH --error=slurm-%A_%a.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=benl@example.com

# Configuration
module load StdEnv/2023 apptainer gdal
export R_PRINT_BUF_SIZE=0
export PYTHONUNBUFFERED=1
export TERM=xterm-256color

# Variables d'environnement
TILE_ID=$SLURM_ARRAY_TASK_ID
IMG="$HOME/scratch/rocker_geospatial_step5.sif"
SCRIPT="$HOME/scratch/pipeline_V6/step5_modulaire/step5_tile_worker.R"
TILES_FILE="$HOME/scratch/output_V6/tiles_1000km.gpkg"

# Pre-flight checks
echo " $(date) – Lancement tuile $TILE_ID"
echo "   - Image : $(basename $IMG)"
echo "   - Script : $(basename $SCRIPT)"
echo "   - Fichier tuiles : $(basename $TILES_FILE)"

# Verify required files
if [ ! -f "$IMG" ]; then
    echo " Image Apptainer manquante : $IMG"
    exit 1
fi

if [ ! -f "$SCRIPT" ]; then
    echo " Script R manquant : $SCRIPT"
    exit 1
fi

if [ ! -f "$TILES_FILE" ]; then
    echo " Fichier tuiles manquant : $TILES_FILE"
    exit 1
fi

# Create log directory if needed
mkdir -p logs

# Lancement du traitement
echo " Début traitement tuile $TILE_ID"
apptainer exec --bind /scratch,/home --pwd $PWD "$IMG" stdbuf -oL -eL Rscript "$SCRIPT" $TILE_ID

# Check exit status
if [ $? -eq 0 ]; then
    echo " Tuile $TILE_ID terminée avec succès"
else
    echo " Tuile $TILE_ID échouée"
    exit 1
fi 
