#!/bin/bash
#SBATCH --job-name=step5_merge_opt
#SBATCH --output=step5_merge_opt_%j.out
#SBATCH --error=step5_merge_opt_%j.err
#SBATCH --time=6:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=2
#SBATCH --account=def-wailung

# Charger les modules
module load StdEnv/2023 apptainer-suid/1.1 gdal

# Aller dans le répertoire de travail
cd ~/R_scripts/pipeline_V6

echo "🚀 Lancement Step 5 merge OPTIMISÉ avec SLURM"
echo "📁 Répertoire : $(pwd)"
echo "💾 Mémoire : 32GB (optimisée)"
echo "⏱️  Temps max : 6h"
echo "🎯 Scénario : default"
echo "🔧 Version : optimisée (gestion mémoire GeoTIFF)"

# Vérifier si MAKE_TIFF est défini
if [ "${MAKE_TIFF:-false}" = "true" ]; then
    echo "🗺️  Génération GeoTIFF activée"
    export MAKE_TIFF=true
else
    echo "📊 Génération GeoTIFF désactivée (par défaut)"
    export MAKE_TIFF=false
fi

# Lancer le script optimisé avec Apptainer
apptainer exec --bind /scratch,/home ~/rocker_geospatial_step5.sif \
    Rscript -e "Sys.setenv(MAKE_TIFF='${MAKE_TIFF}'); source('step5_merge_tiles_optimized.R')"

if [ $? -eq 0 ]; then
    echo "✅ Step 5 merge optimisé terminé avec succès"
    echo "📊 Vérification des fichiers créés :"
    ls -la ~/scratch/output_V6/fi_grid_*.parquet 2>/dev/null || echo "   ⚠️  Parquet non trouvé"
    ls -la ~/scratch/output_V6/fi_grid_*.rds 2>/dev/null || echo "   ⚠️  RDS non trouvé"
    ls -la ~/scratch/output_V6/fi_grid_*.tif 2>/dev/null || echo "   ⚠️  GeoTIFF non trouvé"
else
    echo "❌ Step 5 merge optimisé échoué"
    exit 1
fi 