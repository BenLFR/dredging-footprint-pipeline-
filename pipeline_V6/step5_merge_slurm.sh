#!/bin/bash
#SBATCH --job-name=step5_merge
#SBATCH --output=step5_merge_%j.out
#SBATCH --error=step5_merge_%j.err
#SBATCH --time=4:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --account=def-wailung

# Charger les modules
module load StdEnv/2023 apptainer-suid/1.1 gdal

# Aller dans le répertoire de travail
cd ~/R_scripts/pipeline_V6

echo "🚀 Lancement Step 5 merge avec SLURM"
echo "📁 Répertoire : $(pwd)"
echo "💾 Mémoire : 64GB"
echo "⏱️  Temps max : 4h"

# Lancer le script avec Apptainer
apptainer exec --bind /scratch,/home ~/rocker_geospatial_step5.sif \
    Rscript step5_merge_tiles.R

if [ $? -eq 0 ]; then
    echo "✅ Step 5 merge terminé avec succès"
else
    echo "❌ Step 5 merge échoué"
    exit 1
fi 