#!/bin/bash
# Script de monitoring avancé pour Step5

echo "=== MONITORING AVANCÉ STEP5 ==="
date
echo ""

# Configuration
TOTAL_TILES=648
OUTPUT_DIR="$HOME/scratch/output_V6"

# 1. État des jobs
echo "📋 ÉTAT DES JOBS :"
jobs_running=$(squeue -u $USER | grep step5 | grep "RUNNING" | wc -l)
jobs_pending=$(squeue -u $USER | grep step5 | grep "PENDING" | wc -l)
jobs_total=$(squeue -u $USER | grep step5 | wc -l)

echo "   Jobs en cours : $jobs_running"
echo "   Jobs en attente : $jobs_pending"
echo "   Total jobs actifs : $jobs_total"
echo ""

# 2. Progression des fichiers
echo "📊 PROGRESSION DES FICHIERS :"
existing_files=$(ls $OUTPUT_DIR/sar_*.parquet 2>/dev/null | wc -l)
percentage=$(echo "scale=1; $existing_files * 100 / $TOTAL_TILES" | bc 2>/dev/null || echo "0")

echo "   Fichiers générés : $existing_files/$TOTAL_TILES ($percentage%)"
echo "   Derniers fichiers créés :"
ls -t $OUTPUT_DIR/sar_*.parquet 2>/dev/null | head -5 | sed 's/.*sar_\([0-9]*\)\.parquet/sar_\1.parquet/' | tr '\n' ' '
echo ""
echo ""

# 3. Recommandations
echo "💡 RECOMMANDATIONS :"
if [ $existing_files -eq $TOTAL_TILES ]; then
    echo "   ✅ Toutes les tuiles sont complétées !"
    echo "   🎯 Lancez la fusion finale"
elif [ $jobs_total -eq 0 ]; then
    echo "   ⚠️  Aucun job actif - utilisez ./relance_intelligente.sh"
else
    echo "   🔄 Jobs en cours - surveillez la progression"
fi

echo ""
echo "=== FIN MONITORING ===" 