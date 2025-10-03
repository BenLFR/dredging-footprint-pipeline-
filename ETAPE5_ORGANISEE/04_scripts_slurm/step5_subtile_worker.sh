#!/bin/bash
#SBATCH -o /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.out
#SBATCH -e /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.err
#SBATCH --job-name=step5_subtile
#SBATCH --time=02:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --account=def-wailung
#SBATCH --array=1-1000%50

: "${OUT_DIR:=/lustre10/scratch/$USER/output_V6}"; mkdir -p "$OUT_DIR"; export OUT_DIR
module load StdEnv/2023 apptainer/1.3.5
: "${OUT_DIR:=/lustre10/scratch/$USER/output_V6}"
mkdir -p "$OUT_DIR"
export OUT_DIR

# Manifest (sans guillemets pour ~)
MANIFEST_FILE="${SUBTASKS_FILE:-$HOME/scratch/subtasks_manifest.csv}"
[ -f "$MANIFEST_FILE" ] || { echo "❌ Manifest $MANIFEST_FILE introuvable"; exit 1; }

LINE_NUM=$SLURM_ARRAY_TASK_ID
LINE=$(sed -n "${LINE_NUM}p" "$MANIFEST_FILE")
[ -z "$LINE" ] && { echo "❌ Ligne $LINE_NUM absente du manifest"; exit 1; }

IFS=',' read -r tile_id sub_id xmin xmax ymin ymax n_pings_est total_pings divisions <<< "$LINE"
out="${OUT_DIR}/sar_${tile_id}_sub${sub_id}.parquet"
if [ -s "$out" ]; then
  echo "⏭️  Sortie déjà présente: $out — skip"; exit 0
fi

cd ~/scratch
apptainer exec --env OUT_DIR="$OUT_DIR" --env OUT_DIR="$OUT_DIR" --bind /scratch,/home,/project --writable-tmpfs ~/scratch/rocker_geospatial_step5.sif \
  Rscript ~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/step5_subtile_worker_corrected.R \
  "$tile_id" "$sub_id" "$xmin" "$xmax" "$ymin" "$ymax"

echo "✅ Sous-tuile ${tile_id}_${sub_id} terminée"
