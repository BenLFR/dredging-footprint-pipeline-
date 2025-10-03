#!/bin/bash
# ====================================================================
# PIPELINE COMPLET V6 BELUGA - ORCHESTRATEUR SIMPLIFIÉ
# ====================================================================

echo "🚀 === PIPELINE V6 BELUGA - DÉMARRAGE SIMPLIFIÉ ==="
echo "Timestamp: $(date)"

# Configuration environnement
export PIPELINE_V6_ROOT=~/R_scripts/pipeline_V6
export R_LIBS=~/.local/R/4.2.1/

# Vérification répertoires
mkdir -p logs
mkdir -p ~/scratch/output
cd ${PIPELINE_V6_ROOT}

# Vérification fichiers requis
if [ ! -f "step1_split_navires.R" ]; then
    echo "❌ Erreur: Scripts R non trouvés dans $PIPELINE_V6_ROOT"
    exit 1
fi

echo "📂 Répertoire pipeline: $PIPELINE_V6_ROOT"
echo "📊 Données source: ~/scratch/benjamin2.csv"

# ---- ÉTAPE 1: FRACTIONNEMENT ----
echo "📦 Lancement Étape 1: Fractionnement..."
JOB1=$(sbatch --parsable step1_split_navires.sh)
if [ $? -eq 0 ]; then
    echo "✅ Job 1 (Split) soumis: $JOB1"
else
    echo "❌ Erreur soumission Job 1"
    exit 1
fi

# ---- ÉTAPE 2: TRAITEMENT ARRAY (MAX 12) ----
echo "🔄 Lancement Étape 2: Traitement par navire (max 12)..."
JOB2=$(sbatch --parsable --dependency=afterok:$JOB1 step2_process_array.sh $JOB1)
if [ $? -eq 0 ]; then
    echo "✅ Job 2 (Process Array) soumis: $JOB2"
else
    echo "❌ Erreur soumission Job 2"
    exit 1
fi

# ---- ÉTAPE 3: FUSION FINALE ----
echo "🏁 Lancement Étape 3: Fusion et Grid Search..."
JOB3=$(sbatch --parsable --dependency=afterok:$JOB2 step3_merge_final.sh $JOB1)
if [ $? -eq 0 ]; then
    echo "✅ Job 3 (Merge Final) soumis: $JOB3"
else
    echo "❌ Erreur soumission Job 3"
    exit 1
fi

# ---- RÉSUMÉ ----
echo ""
echo "📋 === JOBS SOUMIS ==="
echo "  1. Split:    $JOB1"
echo "  2. Process:  $JOB2 (dépend de $JOB1, array 1-12)"
echo "  3. Merge:    $JOB3 (dépend de $JOB2)"
echo ""
echo "🔍 Surveillance avec:"
echo "  squeue -u \$USER"
echo "  watch -n 5 'squeue -u \$USER'"
echo ""
echo "📁 Logs dans: $PIPELINE_V6_ROOT/logs/"
echo "📊 Résultats finaux dans: ~/scratch/output/"
echo ""
echo "⏱️ Temps estimé total: ~4-6h"
echo "🎯 Pipeline V6 lancé avec succès!"
echo ""
echo "📝 Note: Les tasks array >nb_navires s'arrêteront automatiquement" 