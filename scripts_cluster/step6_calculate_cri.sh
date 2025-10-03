#!/bin/bash
#SBATCH -o /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.out
#SBATCH -e /home/%u/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/slurm-%A_%a.err
#SBATCH --job-name=step6_calculate_cri
#SBATCH --time=8:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --account=def-wailung

set -e

echo "=== ÉTAPE 6 : CALCUL DE CRI ==="
module load StdEnv/2023 apptainer-suid/1.1 gdal
: "${OUT_DIR:=/lustre10/scratch/$USER/output_V6}"
mkdir -p "$OUT_DIR"
export OUT_DIR

cd "$HOME/scratch"
mkdir -p /scratch/benl/tmp /scratch/benl/output_V6

SIF_PATH="$HOME/scratch/rocker_geospatial_step5.sif"
[ -f "$SIF_PATH" ] || { echo "❌ Image Apptainer introuvable : $SIF_PATH"; exit 1; }
echo "✅ Image trouvée : $SIF_PATH"

# ⬇️ fichier corrigé (même archive/chemin que l’original, nom changé)
SCRIPT_PATH="$HOME/scratch/ETAPE5_ORGANISEE/01_scripts_principaux/step6_calculate_cri_corrected.R"
# fallback si tu l’as aussi copié dans scratch
[ -f "$SCRIPT_PATH" ] || SCRIPT_PATH="$HOME/scratch/ETAPE5_ORGANISEE/01_scripts_principaux/step6_calculate_cri_corrected.R"
[ -f "$SCRIPT_PATH" ] || { echo "❌ Script R introuvable : $SCRIPT_PATH"; exit 1; }
echo "✅ Script R trouvé : $SCRIPT_PATH"

# Vérif f_i
FI_FILES=$(find "$HOME/scratch/output_V6/" -name "fi_grid_*.parquet" -o -name "fi_grid_*.rds" 2>/dev/null | head -5)
[ -z "$FI_FILES" ] && { echo "❌ Aucun fichier f_i trouvé, lance d’abord Step 5"; exit 1; }
echo "✅ Fichiers f_i trouvés :"; echo "$FI_FILES"

apptainer exec --env OUT_DIR="$OUT_DIR" --bind /lustre10/scratch:/scratch --bind /lustre09/project:/project --bind /home:/home "$SIF_PATH" Rscript "$SCRIPT_PATH" "/home/benl/scratch/output_V6/fi_grid_20250814_095050.parquet"

if [ $? -eq 0 ]; then
  echo "✅ Step 6 terminé avec succès !"
  ls -lh /scratch/benl/output_V6/cri_final_* 2>/dev/null || echo "   ⚠️ Aucun fichier cri_final trouvé"
else
  echo "❌ Step 6 a échoué"; exit 1
fi
