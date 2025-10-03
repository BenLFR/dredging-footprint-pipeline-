#!/bin/bash
# ====================================================================
# PIPELINE COMPLET V6 BELUGA - ORCHESTRATEUR CORRIGÉ
# ====================================================================

echo "🚀 === PIPELINE V6 BELUGA - DÉMARRAGE ==="
echo "Timestamp: $(date)"

# Rester dans le répertoire pipeline_V6
PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PIPELINE_DIR"
echo "📁 Répertoire actuel: $(pwd)"

# Vérification répertoires
mkdir -p logs
mkdir -p ~/R_scripts/temp/navires_split
mkdir -p ~/R_scripts/temp/navire_results  
mkdir -p ~/R_scripts/temp/final_results
mkdir -p ~/scratch/output

# Vérification fichiers critiques
echo "🔍 Vérification des fichiers..."
if [[ ! -f "step1_split_navires.sh" ]]; then
    echo "❌ ERREUR: step1_split_navires.sh introuvable"
    exit 1
fi
if [[ ! -f "step2_process_array.sh" ]]; then
    echo "❌ ERREUR: step2_process_array.sh introuvable"
    exit 1
fi
if [[ ! -f "step3_merge_final.sh" ]]; then
    echo "❌ ERREUR: step3_merge_final.sh introuvable"
    exit 1
fi

echo "✅ Tous les fichiers trouvés"

# ---- ÉTAPE 1: FRACTIONNEMENT ----
echo "📦 Lancement Étape 1: Fractionnement..."
JOB1=$(sbatch --parsable ./step1_split_navires.sh)
echo "✅ Job 1 (Split) soumis: $JOB1"

# ---- ÉTAPE 2: TRAITEMENT ARRAY ----
echo "🔄 Lancement Étape 2: Traitement par navire..."
JOB2=$(sbatch --parsable --dependency=afterok:$JOB1 ./step2_process_array.sh $JOB1)
echo "✅ Job 2 (Process Array) soumis: $JOB2"

# ---- ÉTAPE 3: FUSION FINALE ----
echo "🏁 Lancement Étape 3: Fusion et Grid Search..."
JOB3=$(sbatch --parsable --dependency=afterok:$JOB2 ./step3_merge_final.sh $JOB1)
echo "✅ Job 3 (Merge Final) soumis: $JOB3"

# ---- RÉSUMÉ ----
echo ""
echo "📋 === JOBS SOUMIS ==="
echo "  1. Split:    $JOB1"
echo "  2. Process:  $JOB2 (dépend de $JOB1)"
echo "  3. Merge:    $JOB3 (dépend de $JOB2)"
echo ""
echo "🔍 Surveillance avec:"
echo "  squeue -u \$USER"
echo "  watch -n 5 'squeue -u \$USER'"
echo ""
echo "📁 Logs dans: $(pwd)/logs/"
echo ""
echo "⏱️ Temps estimé total: ~4-6h"
echo "🎯 Résultats finaux dans: ~/scratch/output/" 