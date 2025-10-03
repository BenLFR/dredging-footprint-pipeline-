#!/bin/bash
#SBATCH --job-name=heatmap_world_kde
#SBATCH --output=heatmap_world_kde_%j.out
#SBATCH --error=heatmap_world_kde_%j.err
#SBATCH --time=4:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --account=def-wailung

# ────────────────────────────────────────────────────────────────────────────────
# HEATMAP MONDIALE KDE - DRAGAGE MARIN
# Script SLURM pour générer la heatmap mondiale de densité de pings dragage
# ────────────────────────────────────────────────────────────────────────────────

set -e  # Arrêter en cas d'erreur

echo "=== LANCEMENT HEATMAP MONDIALE KDE ==="
echo "📅 $(date)"
echo "📁 Répertoire : $(pwd)"
echo ""

# Charger les modules nécessaires
echo "🔄 Chargement des modules..."
module load StdEnv/2023 apptainer-suid/1.1
echo "✅ Modules chargés"

# Aller dans le répertoire scratch
cd ~/scratch

# Vérifier l'espace disque
echo "💾 Espace disque disponible :"
df -h ~/scratch

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
SCRIPT_PATH="/home/benl/scratch/scripts_principaux/heatmap_dragage_world_kde.R"
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
echo "🚀 Lancement de la génération de heatmap..."
echo ""

# Exécuter le script R dans le conteneur Apptainer
apptainer exec \
    --bind /scratch,/home "$SIF_PATH" \
    Rscript "$SCRIPT_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Heatmap générée avec succès !"
    echo "📁 Fichier créé :"
    ls -lh dragage_heatmap_world_kde.png 2>/dev/null || echo "   Fichier non trouvé"
    
    # Vérifier la taille de l'image
    if [[ -f "dragage_heatmap_world_kde.png" ]]; then
        echo "📊 Taille de l'image : $(ls -lh dragage_heatmap_world_kde.png | awk '{print $5}')"
        echo "🎨 Résolution : $(file dragage_heatmap_world_kde.png | grep -o '[0-9]*x[0-9]*')"
    fi
else
    echo ""
    echo "❌ Erreur lors de la génération de la heatmap"
    exit 1
fi

echo ""
echo "📅 $(date)"
echo "🎉 Heatmap mondiale terminée !" 