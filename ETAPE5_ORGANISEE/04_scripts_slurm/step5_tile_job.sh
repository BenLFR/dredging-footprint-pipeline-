#!/bin/bash
#SBATCH -o /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.out
#SBATCH -e /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.err
#SBATCH --account=def-wailung
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-525

module load StdEnv/2023 apptainer/1.3.5
: "${OUT_DIR:=/lustre10/scratch/$USER/output_V6}"
mkdir -p "$OUT_DIR"
export OUT_DIR
export R_PRINT_BUF_SIZE=0
export TERM=xterm-256color

TILE_ID=$SLURM_ARRAY_TASK_ID
IMG="$HOME/scratch/rocker_geospatial_step5.sif"
SCRIPT="$HOME/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/step5_tile_worker_corrected.R"
TILES_FILE="$HOME/scratch/output_V6/tiles_1000km.gpkg"

echo "🚀 $(date) – Lancement tuile $TILE_ID"
[ -f "$IMG" ] || { echo "❌ Image Apptainer manquante: $IMG"; exit 1; }
[ -f "$SCRIPT" ] || { echo "❌ Script R manquant: $SCRIPT"; exit 1; }
[ -f "$TILES_FILE" ] || { echo "❌ Fichier tuiles manquant: $TILES_FILE"; exit 1; }

apptainer exec --env OUT_DIR="$OUT_DIR" --bind /scratch,/home,/project --pwd "$PWD" "$IMG" \
Rscript "$SCRIPT" $TILE_ID
