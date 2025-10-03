#!/bin/bash
#SBATCH --job-name=heatmap_simple
#SBATCH --output=heatmap_simple_%j.out
#SBATCH --error=heatmap_simple_%j.err
#SBATCH --time=2:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#SBATCH --account=def-wailung

# ────────────────────────────────────────────────────────────────────────────────
# HEATMAP MONDIALE SIMPLIFIÉE - DRAGAGE MARIN
# Version utilisant seulement les packages disponibles dans le conteneur
# ────────────────────────────────────────────────────────────────────────────────

set -e  # Arrêter en cas d'erreur

echo "=== LANCEMENT HEATMAP SIMPLIFIÉE ==="
echo "📅 $(date)"
echo "📁 Répertoire : $(pwd)"
echo ""

# Charger les modules nécessaires
echo "🔄 Chargement des modules..."
module load StdEnv/2023 apptainer-suid/1.1
echo "✅ Modules chargés"

# Aller dans le répertoire scratch
cd ~/scratch

# Vérifier que l'image Apptainer existe
echo "🔍 Recherche de l'image Apptainer..."
SIF_PATH="/home/benl/scratch/rocker_geospatial_step5.sif"
if [[ ! -f "$SIF_PATH" ]]; then
    echo "❌ Image Apptainer introuvable : $SIF_PATH"
    exit 1
fi

echo "✅ Image trouvée : $SIF_PATH"

# Vérifier que le script R existe
echo "🔍 Vérification du script R..."
SCRIPT_PATH="/home/benl/scratch/scripts_principaux/heatmap_dragage_world_kde_simple.R"
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "❌ Script R introuvable : $SCRIPT_PATH"
    exit 1
fi

echo "✅ Script R trouvé : $SCRIPT_PATH"

# Vérifier que les données AIS existent
echo "🔍 Vérification des données AIS..."
AIS_PATH="/home/benl/scratch/output_V6/AIS_data_core_preprocessed_V6_20250726_130813_flagOK.rds"
if [[ ! -f "$AIS_PATH" ]]; then
    echo "❌ Données AIS introuvables : $AIS_PATH"
    echo "   Fichiers disponibles dans output_V6 :"
    ls -la ~/scratch/output_V6/ 2>/dev/null || echo "   Répertoire vide ou inexistant"
    exit 1
fi

echo "✅ Données AIS trouvées : $AIS_PATH"
echo "📊 Taille du fichier : $(ls -lh "$AIS_PATH" | awk '{print $5}')"

echo ""
echo "🚀 Lancement de la génération de heatmap simplifiée..."
echo ""

# Exécuter le script R dans le conteneur Apptainer
apptainer exec \
    --bind /scratch,/home "$SIF_PATH" \
    Rscript "$SCRIPT_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Heatmap simplifiée générée avec succès !"
    echo "📁 Fichier créé :"
    ls -lh dragage_heatmap_world_simple.png 2>/dev/null || echo "   Fichier non trouvé"
    
    # Vérifier la taille de l'image
    if [[ -f "dragage_heatmap_world_simple.png" ]]; then
        echo "📊 Taille de l'image : $(ls -lh dragage_heatmap_world_simple.png | awk '{print $5}')"
        echo "🎨 Résolution : $(file dragage_heatmap_world_simple.png | grep -o '[0-9]*x[0-9]*')"
    fi
else
    echo ""
    echo "❌ Erreur lors de la génération de la heatmap"
    exit 1
fi

echo ""
echo "📅 $(date)"
echo "🎉 Heatmap simplifiée terminée !" 