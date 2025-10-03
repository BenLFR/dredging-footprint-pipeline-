#!/bin/bash
# Vérification finale et lancement de la fusion

cd ~/R_scripts/pipeline_V6/step5_modulaire

echo "=== VÉRIFICATION FINALE STEP5 ==="
date
echo ""

# 1. Comptage des fichiers
echo "📊 FICHIERS GÉNÉRÉS :"
total_files=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | wc -l)
echo "   Total : $total_files fichiers"
echo ""

# 2. Liste des tuiles avec dragage
echo "🗺️  TUILES AVEC DRAGAGE :"
ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | sed 's/.*sar_\([0-9]*\)\.parquet/\1/' | sort -n | tr '\n' ' '
echo ""
echo ""

# 3. Vérification de la taille des fichiers
echo "📏 TAILLE DES FICHIERS :"
ls -lah ~/scratch/output_V6/sar_*.parquet 2>/dev/null | head -10
echo ""

# 4. Test de lecture d'un fichier
echo "🧪 TEST DE LECTURE :"
first_file=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | head -1)
if [ ! -z "$first_file" ]; then
    echo "   Test lecture : $first_file"
    apptainer exec --bind /scratch,/home --pwd $PWD ~/rocker_geospatial_step5.sif \
        Rscript -e "library(arrow); x <- read_parquet('$first_file'); cat('Lignes:', nrow(x), 'Colonnes:', ncol(x), '\n')"
else
    echo "   ❌ Aucun fichier trouvé"
fi
echo ""

# 5. Lancement de la fusion
echo "🔄 LANCEMENT DE LA FUSION :"
if [ $total_files -gt 0 ]; then
    echo "   Lancement step5_merge_tiles.R..."
    apptainer exec --bind /scratch,/home --pwd $PWD ~/rocker_geospatial_step5.sif \
        Rscript step5_merge_tiles.R
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Fusion terminée avec succès"
        echo "   Fichier final : ~/scratch/output_V6/f_i_global_1km.parquet"
    else
        echo "   ❌ Erreur lors de la fusion"
    fi
else
    echo "   ⚠️  Aucun fichier à fusionner"
fi

echo ""
echo "=== FIN VÉRIFICATION ===" 