#!/bin/bash
# ====================================================================
# PIPELINE COMPLET V6 BELUGA - ORCHESTRATEUR CORRIGÉ
# ====================================================================

echo "🚀 === PIPELINE V6 BELUGA - DÉMARRAGE ==="
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

# ---- ATTENTE ET DÉTECTION NOMBRE DE NAVIRES ----
echo "⏳ Attente fin Job 1 pour détecter nombre de navires..."

# Polling job status
while true; do
    job_state=$(squeue -j $JOB1 -h -o %T 2>/dev/null)
    if [ -z "$job_state" ]; then
        # Job terminé
        break
    elif [ "$job_state" = "FAILED" ] || [ "$job_state" = "CANCELLED" ]; then
        echo "❌ Job 1 échoué: $job_state"
        exit 1
    fi
    echo "📊 Job 1 status: $job_state - attente 30s..."
    sleep 30
done

# Détection nombre de navires
echo "🔍 Détection nombre de navires..."
if [ -f "~/scratch/ais_split_${JOB1}/nb_navires.txt" ]; then
    nb_navires=$(cat ~/scratch/ais_split_${JOB1}/nb_navires.txt)
else
    nb_navires=$(ls ~/scratch/ais_split_${JOB1}/navire_*.rds 2>/dev/null | wc -l)
fi

if [ $nb_navires -eq 0 ]; then
    echo "❌ Erreur: Aucun navire détecté"
    exit 1
fi

echo "📈 Nombre de navires détectés: $nb_navires"

# ---- ÉTAPE 2: TRAITEMENT ARRAY DYNAMIQUE ----
echo "🔄 Lancement Étape 2: Traitement par navire (1-$nb_navires)..."

# Création script array dynamique
cat > step2_dynamic.sh << EOF
#!/bin/bash
#SBATCH --job-name=ais_process_V6
#SBATCH --array=1-${nb_navires}%8
#SBATCH --mem=6G
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step2_process_%A_%a.out
#SBATCH --error=logs/step2_process_%A_%a.err

# Import du script principal
source step2_process_array.sh $JOB1
EOF

JOB2=$(sbatch --parsable step2_dynamic.sh)
if [ $? -eq 0 ]; then
    echo "✅ Job 2 (Process Array 1-$nb_navires) soumis: $JOB2"
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
echo "  1. Split:    $JOB1 ✅"
echo "  2. Process:  $JOB2 (array 1-$nb_navires)"
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