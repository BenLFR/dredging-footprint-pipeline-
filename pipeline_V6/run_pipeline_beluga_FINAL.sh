#!/bin/bash
# ====================================================================
# PIPELINE COMPLET V6 BELUGA - ORCHESTRATEUR FINAL CORRIGÉ
# ====================================================================

echo "🚀 === PIPELINE V6 BELUGA - DÉMARRAGE FINAL ==="
echo "Timestamp: $(date)"

# Rester dans le répertoire pipeline_V6
PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PIPELINE_DIR"
echo "📁 Répertoire actuel: $(pwd)"

# Nettoyage jobs précédents
echo "🧹 Nettoyage jobs précédents..."
scancel -u $USER 2>/dev/null || echo "Aucun job à annuler"

# Nettoyage répertoires temporaires
echo "🧹 Nettoyage répertoires temporaires..."
rm -rf ~/scratch/ais_split_* ~/scratch/ais_results_* 2>/dev/null || echo "Répertoires déjà propres"

# Vérification répertoires
mkdir -p logs
mkdir -p ~/scratch/output

# Vérification fichiers critiques CORRIGÉS
echo "🔍 Vérification des fichiers corrigés..."
if [[ ! -f "step1_split_navires_FIXED.sh" ]]; then
    echo "❌ ERREUR: step1_split_navires_FIXED.sh introuvable"
    exit 1
fi
if [[ ! -f "step2_process_array_FIXED.sh" ]]; then
    echo "❌ ERREUR: step2_process_array_FIXED.sh introuvable"
    exit 1
fi
if [[ ! -f "step3_merge_final_FIXED.sh" ]]; then
    echo "❌ ERREUR: step3_merge_final_FIXED.sh introuvable"
    exit 1
fi

echo "✅ Tous les fichiers corrigés trouvés"

# ---- ÉTAPE 1: FRACTIONNEMENT ----
echo "📦 Lancement Étape 1: Fractionnement (VERSION CORRIGÉE)..."
JOB1=$(sbatch --parsable ./step1_split_navires_FIXED.sh)
echo "✅ Job 1 (Split) soumis: $JOB1"

# ---- ÉTAPE 2: TRAITEMENT ARRAY ----
echo "🔄 Lancement Étape 2: Traitement par navire (VERSION CORRIGÉE)..."
JOB2=$(sbatch --parsable --dependency=afterok:$JOB1 ./step2_process_array_FIXED.sh $JOB1)
echo "✅ Job 2 (Process Array) soumis: $JOB2"

# ---- ÉTAPE 3: FUSION FINALE ----
echo "🏁 Lancement Étape 3: Fusion et Grid Search (VERSION CORRIGÉE)..."
JOB3=$(sbatch --parsable --dependency=afterok:$JOB2 ./step3_merge_final_FIXED.sh $JOB1)
echo "✅ Job 3 (Merge Final) soumis: $JOB3"

# ---- RÉSUMÉ ----
echo ""
echo "📋 === JOBS CORRIGÉS SOUMIS ==="
echo "  1. Split:    $JOB1 (VERSION CORRIGÉE)"
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
echo ""
echo "🔧 CORRECTION APPLIQUÉE: Chemins vers fichiers R corrigés !" 