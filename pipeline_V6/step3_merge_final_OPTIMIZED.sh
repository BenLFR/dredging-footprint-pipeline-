#!/bin/bash
#SBATCH --job-name=ais_merge_V6_optimized
#SBATCH --mem=256G
#SBATCH --cpus-per-task=16
#SBATCH --time=12:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step3_merge_%j.out
#SBATCH --error=logs/step3_merge_%j.err

set -euo pipefail  # Arrêt au premier souci

echo "🔒 === ÉTAPE 3 OPTIMIZED: FUSION ET GRID SEARCH (AVEC VERROU NA) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Debut: $(date)"
echo "Memoire allouee: 256 GB (OPTIMISÉE)"
echo "CPU: 16 cores"
echo "Temps maximum: 12 heures (OPTIMISÉ)"

# Configuration R Beluga
module --force purge
module load StdEnv/2023
module load r/4.3.1
export R_LIBS=~/R/4.3
export R_LIBS_USER=~/R/4.3

# Recuperation arguments
SPLIT_JOB_ID=$1
RESULTS_DIR=${2:-}  # Sécurisé contre "unbound variable"

# Vérification des arguments obligatoires
[ -z "$SPLIT_JOB_ID" ] && { echo "Usage : $0 <split_id> [results_dir]"; exit 1; }

echo "Job fractionnement reference: $SPLIT_JOB_ID"
if [ -n "$RESULTS_DIR" ]; then
    echo "Dossier de resultats specifie: $RESULTS_DIR"
else
    echo "Dossier de resultats: auto-detection"
fi

# VÉRIFICATION DU PATCH NA DÉFINITIF
echo "🔍 Vérification du patch NA définitif..."
if [ ! -f ~/R_scripts/pipeline_V6/step3_merge_final.R ]; then
    echo "❌ ERREUR: Script step3_merge_final.R non trouvé"
    exit 1
fi

grep -qiE "SANITY.*CHECK" ~/R_scripts/pipeline_V6/step3_merge_final.R || { echo "❌ ERREUR: Patch SANITY-CHECK manquant"; exit 1; }

grep -qiE "VERROU.*GLOBAL" ~/R_scripts/pipeline_V6/step3_merge_final.R || { echo "❌ ERREUR: Patch VERROU GLOBAL manquant"; exit 1; }

    echo "✅ Patch NA définitif détecté"
    echo "✅ Verrou global détecté"

# SUPPRESSION DU CHECKPOINT FAUTIF
echo "🗑️  Suppression du checkpoint fautif..."
if [ -e ~/scratch/output_V6/checkpoints/stage3C_gmm.rds ]; then
    rm ~/scratch/output_V6/checkpoints/stage3C_gmm.rds
    echo "✅ Checkpoint fautif supprimé"
else
    echo "ℹ️  Checkpoint fautif absent"
fi

# VÉRIFICATION DES CHECKPOINTS VALIDES
echo "🔍 Vérification des checkpoints valides..."
if [ -f ~/scratch/output_V6/checkpoints/stage3A_fusion.rds ]; then
    echo "✅ Checkpoint fusion présent (sera réutilisé)"
    ls -lh ~/scratch/output_V6/checkpoints/stage3A_fusion.rds
else
    echo "❌ Checkpoint fusion manquant"
fi

if [ -f ~/scratch/output_V6/checkpoints/stage3B_dbscan.rds ]; then
    echo "✅ Checkpoint DBSCAN présent (sera réutilisé)"
    ls -lh ~/scratch/output_V6/checkpoints/stage3B_dbscan.rds
else
    echo "❌ Checkpoint DBSCAN manquant"
fi

# Estimation du temps de reprise
echo "⏱️  Estimation du temps de reprise..."
echo "   • Fusion: ~15 min (checkpoint réutilisé)"
echo "   • DBSCAN: ~20 min (checkpoint réutilisé)"
echo "   • GMM + Grid-search: ~60 min (recalculé avec 5 folds)"
echo "   • Total estimé: ~60 min au lieu de 5h"

# Determination du dossier de resultats
if [ -n "$RESULTS_DIR" ] && [ -d "$RESULTS_DIR" ]; then
    EXPECTED_DIR="$RESULTS_DIR"
    echo "Utilisation du dossier specifie: $EXPECTED_DIR"
elif [ -n "$RESULTS_DIR" ] && [ ! -d "$RESULTS_DIR" ]; then
    echo "ERREUR: Dossier specifie '$RESULTS_DIR' non trouve"
    exit 1
else
    echo "Auto-detection du dossier de resultats..."
    
    POSSIBLE_PATHS=(
        "/home/benl/scratch/ais_results_${SPLIT_JOB_ID}"
        "/home/benl/scratch/ais_split_${SPLIT_JOB_ID}"
        "/home/benl/scratch/${SPLIT_JOB_ID}"
    )
    
    EXPECTED_DIR=""
    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -d "$path" ]; then
            EXPECTED_DIR="$path"
            echo "Dossier trouve: $EXPECTED_DIR"
            break
        else
            echo "   Non trouve: $path"
        fi
    done
    
    if [ -z "$EXPECTED_DIR" ]; then
        echo "ERREUR: Aucun dossier de resultats trouve"
        echo "   Chemins testes:"
        for path in "${POSSIBLE_PATHS[@]}"; do
            echo "   - $path"
        done
        exit 1
    fi
fi

# Verification des fichiers d'entree (comptage robuste)
echo "Verification des fichiers d'entree..."
CLEAN_FILES_COUNT=$(find "$EXPECTED_DIR" -maxdepth 1 -name "*_clean.rds" | wc -l)
if [ "$CLEAN_FILES_COUNT" -eq 0 ]; then
    echo "ERREUR: Aucun fichier *_clean.rds trouve dans $EXPECTED_DIR"
    exit 1
fi

echo "Fichiers d'entree verifies: $CLEAN_FILES_COUNT fichiers *_clean.rds trouves"

# Creation repertoires
mkdir -p /home/benl/scratch/output_V6
mkdir -p logs

cd ~/R_scripts/pipeline_V6

echo "Repertoire de travail: $(pwd)"
echo "Verification fichier R: $(ls -la step3_merge_final.R 2>/dev/null || echo 'FICHIER MANQUANT')"

# Nettoyage memoire systeme avant lancement
echo "Nettoyage memoire systeme..."
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

echo "🚀 Lancement fusion et grid search optimise (AVEC VERROU NA ET 256G RAM)..."
R --vanilla --slave -e "
# Configuration des chemins de bibliothèques R
user_libs <- c('~/R/4.3')
.libPaths(unique(c(user_libs, .libPaths())))
cat('✅ R cherchera les packages dans :', paste(.libPaths(), collapse = ' | '), '\n')

# OPTIMISATION: Réduction des folds pour éviter les problèmes de mémoire
Sys.setenv(CV_FOLDS = '5')  # 5 folds au lieu de 10
cat('🎯 Configuration optimisée: 5 folds de validation croisée\n')

Sys.setenv(SLURM_JOB_ID = '$SLURM_JOB_ID')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
Sys.setenv(RESULTS_DIR = '$EXPECTED_DIR')
Sys.setenv(SLURM_CPUS_PER_TASK = '16')
source('step3_merge_final.R')
" 2>&1 | tee logs/step3_merge_${SLURM_JOB_ID}.log

exit_code=$?

# CORRECTION: Vérification explicite du code de sortie R
if [ $exit_code -ne 0 ]; then
    echo "❌ ERREUR: Le script R s'est terminé avec le code $exit_code"
    echo "📋 Dernières lignes du log R:"
    tail -20 logs/step3_merge_${SLURM_JOB_ID}.log
    echo ""
    echo "🔍 Recherche d'erreurs critiques dans le log:"
    grep -i "erreur fatale\|stop\|fatal\|execution halted" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucune erreur fatale trouvée"
    exit $exit_code
fi

if [ $exit_code -eq 0 ]; then
    echo "✅ Fusion et grid search termines avec succes: $(date)"
    
    echo "=== RESUME FINAL ==="
    echo "Fichiers generes dans /home/benl/scratch/output_V6/:"
    find /home/benl/scratch/output_V6/ -name "AIS_data_core_preprocessed_V6_*.rds" -ls 2>/dev/null | head -3 || echo "Fichier de donnees fusionnees non trouve"
    find /home/benl/scratch/output_V6/ -name "dragage_gridsearch_results_V6_*.rds" -ls 2>/dev/null | head -3 || echo "Resultats grid search non trouves"
    find /home/benl/scratch/output_V6/ -name "GMM_probabilities_QA.rds" -ls 2>/dev/null | head -3 || echo "Fichier QA GMM non trouve"
    
    echo ""
    echo "🎯 FICHIERS ATTENDUS APRÈS SUCCÈS :"
    echo "  • AIS_data_core_preprocessed_V6_*.rds"
    echo "  • dragage_gridsearch_results_V6_*.rds"
    echo "  • GMM_probabilities_QA.rds"
    
    echo ""
    echo "=== VÉRIFICATION DES CONTRÔLES STRICTS ==="
    echo "Extraction des diagnostics de filtrage depuis les logs..."
    if [ -f "logs/step3_merge_${SLURM_JOB_ID}.log" ]; then
        echo "📊 Diagnostics de filtrage:"
        grep -A 5 "\[DIAGNOSTIC\]" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucun diagnostic de filtrage trouvé"
        echo ""
        echo "🎯 Distribution des classes:"
        grep -A 10 "Effectifs par behavior_smooth" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucune information de distribution trouvée"
        echo ""
        echo "🔄 Validation croisée:"
        grep -A 5 "AUC moyen CV" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucune information de CV trouvée"
        echo ""
        echo "🔒 Vérification du verrou NA:"
        grep -i "verrou global\|sanity-check\|unknown" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucune information de verrou trouvée"
        echo ""
        echo "⚠️ Alertes et erreurs:"
        grep -i "alerte\|erreur\|warning" logs/step3_merge_${SLURM_JOB_ID}.log | tail -10 || echo "   Aucune alerte ou erreur trouvée"
    else
        echo "   Log complet non disponible"
    fi
else
    echo "Erreur lors de la fusion: code $exit_code"
    echo "Logs d'erreur disponibles dans:"
    echo "   - logs/step3_merge_${SLURM_JOB_ID}.out"
    echo "   - logs/step3_merge_${SLURM_JOB_ID}.err"
    echo "   - logs/step3_merge_${SLURM_JOB_ID}.log"
    
    echo ""
    echo "=== DIAGNOSTIC D'ERREUR ==="
    if [ -f "logs/step3_merge_${SLURM_JOB_ID}.log" ]; then
        echo "Dernières lignes du log:"
        tail -20 logs/step3_merge_${SLURM_JOB_ID}.log
        echo ""
        echo "Recherche d'erreurs critiques:"
        grep -i "erreur fatale\|stop\|fatal" logs/step3_merge_${SLURM_JOB_ID}.log || echo "   Aucune erreur fatale trouvée"
    fi
    exit $exit_code
fi

echo "✅ ÉTAPE 3 OPTIMIZED AVEC VERROU NA ET 256G RAM TERMINÉE !" 