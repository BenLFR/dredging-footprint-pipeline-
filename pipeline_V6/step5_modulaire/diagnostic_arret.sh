#!/bin/bash
# Script de diagnostic pour identifier pourquoi Step5 s'est arrêté

echo "=== DIAGNOSTIC ARRÊT STEP5 ==="
date
echo ""

# 1. Vérification des fichiers générés
echo "📊 FICHIERS GÉNÉRÉS :"
total_files=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | wc -l)
echo "   Total : $total_files/648 tuiles"
echo "   Pourcentage : $(echo "scale=1; $total_files * 100 / 648" | bc)%"
echo ""

# 2. Vérification de l'espace disque
echo "💾 ESPACE DISQUE :"
df -h ~/scratch | grep scratch
echo "   Taille output_V6 : $(du -sh ~/scratch/output_V6/ 2>/dev/null | cut -f1)"
echo ""

# 3. Vérification des logs d'erreur
echo "🚨 LOGS D'ERREUR :"
echo "   Derniers logs SLURM :"
ls -la slurm-*.out 2>/dev/null | tail -5
echo ""

# 4. Vérification des jobs récents
echo "📋 JOBS RÉCENTS :"
sacct -u benl --starttime=2025-07-20 | grep step5 | tail -10
echo ""

# 5. Identification des tuiles manquantes
echo "🔍 TUILES MANQUANTES :"
existing_tiles=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | sed 's/.*sar_\([0-9]*\)\.parquet/\1/' | sort -n)
missing_tiles=""
for i in $(seq 1 648); do
    if ! echo "$existing_tiles" | grep -q "^$i$"; then
        missing_tiles="$missing_tiles $i"
    fi
done
echo "   Tuiles manquantes : $missing_tiles"
echo ""

# 6. Test d'une tuile manquante
if [ ! -z "$missing_tiles" ]; then
    first_missing=$(echo $missing_tiles | awk '{print $1}')
    echo "🧪 TEST TUILE MANQUANTE $first_missing :"
    echo "   Lancement test..."
    timeout 300 apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript step5_tile_worker.R $first_missing
    if [ $? -eq 0 ]; then
        echo "   ✅ Test réussi"
    else
        echo "   ❌ Test échoué"
    fi
fi

echo "=== FIN DIAGNOSTIC ===" 