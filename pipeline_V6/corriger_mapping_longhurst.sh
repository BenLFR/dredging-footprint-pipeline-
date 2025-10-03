#!/bin/bash

# Script pour corriger le mapping Longhurst ↔ YAML (à exécuter SUR Rorqual)

echo "🚀 Correction du mapping Longhurst ↔ YAML"
echo "📍 Exécution directe sur Rorqual"

# Vérifier qu'on est bien sur Rorqual
if [[ ! "$HOSTNAME" == *"rorqual"* ]]; then
    echo "⚠️  Ce script doit être exécuté sur Rorqual"
    echo "   Connectez-vous d'abord : ssh benl@rorqual.alliancecan.ca"
    exit 1
fi

# Aller dans le répertoire de travail
cd ~/R_scripts/pipeline_V6

if [ ! -f "fix_longhurst_mapping.R" ]; then
    echo "❌ Script fix_longhurst_mapping.R non trouvé"
    echo "   Assurez-vous qu'il a été transféré sur Rorqual"
    exit 1
fi

# Charger les modules nécessaires
echo "📦 Chargement des modules..."
module load StdEnv/2023 apptainer-suid/1.1 gdal

echo "🔍 Analyse des provinces Longhurst..."
apptainer exec --bind /scratch,/home ~/rocker_geospatial_step5.sif \
    Rscript fix_longhurst_mapping.R

if [ $? -eq 0 ]; then
    echo "✅ Analyse terminée avec succès"
else
    echo "❌ Échec de l'analyse"
    exit 1
fi

echo "📋 Résultats de l'analyse :"
echo "================================"
if [ -f ~/scratch/configuration/fi_parameters_corrected.yaml ]; then
    echo "📊 Aperçu du nouveau YAML :"
    head -30 ~/scratch/configuration/fi_parameters_corrected.yaml
    
    echo ""
    echo "🎯 Vérification du nouveau YAML..."
    echo "================================"
    echo "Nombre de provinces avec k_fast :"
    grep -c ":" ~/scratch/configuration/fi_parameters_corrected.yaml
    
    echo ""
    echo "📊 Statistiques attendues :"
    echo "- Provinces Longhurst sans k_fast : 0"
    echo "- Cellules avec k_used=1 (fallback) : < 5%"
    echo "- Pas de warning 'Clés YAML non utilisées'"
    
    echo ""
    echo "🔄 Remplacement du YAML original..."
    cp ~/scratch/configuration/fi_parameters_corrected.yaml ~/scratch/configuration/fi_parameters.yaml
    
    if [ $? -eq 0 ]; then
        echo "✅ YAML corrigé et prêt pour le Step 5"
    else
        echo "❌ Échec de la copie du YAML"
        exit 1
    fi
else
    echo "❌ Fichier YAML corrigé non trouvé"
    exit 1
fi

echo ""
echo "🎉 Correction terminée avec succès !"
echo "📋 Prochaines étapes :"
echo "1. Lancer le Step 5 optimisé :"
echo "   sbatch step5_merge_slurm_optimized.sh"
echo ""
echo "2. Surveiller le job :"
echo "   squeue -u \$USER"
echo "   tail -f step5_merge_opt_*.out"
echo ""
echo "3. Vérifier les résultats :"
echo "   - 'Provinces Longhurst sans k_fast : 0'"
echo "   - 'Cellules avec k_used=1 (fallback) : < 5%'"
echo "   - Pas de warning sur les clés non utilisées"
echo "   - Raster GeoTIFF créé sans être tué" 