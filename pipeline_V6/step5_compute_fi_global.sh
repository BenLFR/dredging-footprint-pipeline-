#!/bin/bash
#SBATCH --job-name=step5_fi_global
#SBATCH --output=logs/step5_fi_global_%j.out
#SBATCH --error=logs/step5_fi_global_%j.err
#SBATCH --cpus-per-task=4
#SBATCH --mem=256G
#SBATCH --time=12:00:00

SCRIPT_PATH="$HOME/R_scripts/step5_compute_fi_global.R"
IMG="$HOME/scratch/rocker_geospatial_furrr.sif"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ Script non trouvé : $SCRIPT_PATH"
    exit 1
fi

module load apptainer

echo "🚀 Exécution du script R : $SCRIPT_PATH"

apptainer exec "$IMG" Rscript "$SCRIPT_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Étape 5 terminée avec succès !"
else
    echo "❌ Étape 5 échouée !"
    exit 1
fi