#!/bin/bash
# Script de relance intelligente - ne traite que les tuiles manquantes

echo "=== RELANCE INTELLIGENTE STEP5 ==="
date
echo ""

# Configuration
TOTAL_TILES=648
OUTPUT_DIR="$HOME/scratch/output_V6"
SCRIPT_DIR="$HOME/scratch/pipeline_V6/step5_modulaire"

# Vérification de l'environnement
if [ ! -d "$SCRIPT_DIR" ]; then
    echo "❌ Répertoire $SCRIPT_DIR manquant"
    exit 1
fi

cd "$SCRIPT_DIR"

# 1. Identification des tuiles manquantes
echo "🔍 IDENTIFICATION DES TUILES MANQUANTES :"
missing_tiles=""
for i in $(seq 1 $TOTAL_TILES); do
    tile_file="$OUTPUT_DIR/sar_$(printf "%03d" $i).parquet"
    if [ ! -f "$tile_file" ]; then
        missing_tiles="$missing_tiles $i"
    fi
done

n_missing=$(echo $missing_tiles | wc -w)
existing_files=$(ls $OUTPUT_DIR/sar_*.parquet 2>/dev/null | wc -l)

echo "   Tuiles complétées : $existing_files/$TOTAL_TILES"
echo "   Tuiles manquantes : $n_missing"
echo ""

if [ $n_missing -eq 0 ]; then
    echo "✅ Toutes les tuiles sont complétées !"
    echo "🎯 Lancez la fusion finale :"
    echo "   apptainer exec --bind /scratch,/home --pwd \$PWD \"\$HOME/scratch/rocker_geospatial_step5.sif\" Rscript step5_merge_tiles.R"
    exit 0
fi

# 2. Affichage des tuiles manquantes
echo "📋 TUILES MANQUANTES :"
if [ $n_missing -le 20 ]; then
    echo "   $(echo $missing_tiles | tr ' ' '\n' | tr '\n' ' ')"
else
    echo "   Premières 10 : $(echo $missing_tiles | tr ' ' '\n' | head -10 | tr '\n' ' ')..."
    echo "   Dernières 10 : $(echo $missing_tiles | tr ' ' '\n' | tail -10 | tr '\n' ' ')"
fi
echo ""

# 3. Préparation du lancement
echo "🚀 PRÉPARATION DU LANCEMENT :"

# Si peu de tuiles manquantes, les lister explicitement
if [ $n_missing -le 100 ]; then
    array_list=$(echo $missing_tiles | tr ' ' ',')
    echo "   Lancement array job avec tuiles spécifiques : $array_list"
    echo ""
    echo "   Commande à exécuter :"
    echo "   sbatch --array=$array_list step5_tile_job.sh"
    echo ""
    
    read -p "   Voulez-vous lancer maintenant ? (y/N) : " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Lancement en cours..."
        job_id=$(sbatch --array=$array_list step5_tile_job.sh | grep -o '[0-9]\+')
        echo "   ✅ Job lancé avec l'ID : $job_id"
    else
        echo "   ❌ Lancement annulé"
    fi
else
    # Trop de tuiles manquantes, utiliser une approche différente
    echo "   ⚠️  Trop de tuiles manquantes ($n_missing) pour un array job"
    echo "   💡 Utilisez le script de relance par lots :"
    echo "      ./relance_par_lots.sh"
fi

echo ""
echo "=== FIN RELANCE INTELLIGENTE ===" 