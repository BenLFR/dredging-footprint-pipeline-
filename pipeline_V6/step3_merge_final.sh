#!/bin/bash
#SBATCH --job-name=ais_merge_V6_adaptatif
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --time=04:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step3_merge_%j.out
#SBATCH --error=logs/step3_merge_%j.err

echo "🚀 === ÉTAPE 3: FUSION ET GRID SEARCH ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

# Récupération JOB_ID étape 1
SPLIT_JOB_ID=${1:-"test_step1_final"}
echo "📦 Job fractionnement référence: $SPLIT_JOB_ID"

# Création répertoires
mkdir -p ~/scratch/output_V6
mkdir -p logs

# CORRECTION: Rester dans le bon répertoire
cd ~/R_scripts/pipeline_V6

echo "✅ Répertoire de travail: $(pwd)"
echo "✅ Vérification fichier R: $(ls -la step3_merge_final.R 2>/dev/null || echo 'FICHIER MANQUANT')"

echo "✅ Lancement fusion et grid search..."
R --vanilla --slave -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_JOB_ID = '$SLURM_JOB_ID')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
Sys.setenv(SLURM_CPUS_PER_TASK = '16')
source('step3_merge_final.R')
" 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Fusion et grid search terminés avec succès: $(date)"
    
    # Résumé final
    echo "📊 === RÉSUMÉ FINAL ==="
    echo "Fichiers générés dans ~/scratch/output_V6/:"
    ls -lh ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*.rds 2>/dev/null || echo "❌ Fichier de données fusionnées non trouvé"
    ls -lh ~/scratch/output_V6/dragage_gridsearch_results_V6_*.rds 2>/dev/null || echo "❌ Résultats grid search non trouvés"
else
    echo "❌ Erreur lors de la fusion: code $exit_code"
    exit $exit_code
fi

echo "🎉 ÉTAPE 3 TERMINÉE !" 