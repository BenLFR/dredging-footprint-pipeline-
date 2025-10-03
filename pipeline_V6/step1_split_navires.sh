#!/bin/bash
#SBATCH --job-name=ais_split_V6
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step1_split_%j.out
#SBATCH --error=logs/step1_split_%j.err

echo "🚀 === ÉTAPE 1: FRACTIONNEMENT PAR NAVIRE ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

# Variables d'environnement
export CORE_CONFIG_PATH=${CORE_CONFIG_PATH:-"~/scratch/output_V6/core_window.yaml"}
export AIS_INPUT_FILE=${AIS_INPUT_FILE:-"~/AIS_data/benjamin3_clean.csv"}

# Création répertoires
mkdir -p logs

cd ~/R_scripts/pipeline_V6

echo "✅ Lancement script de fractionnement..."
echo "📋 Configuration: $CORE_CONFIG_PATH"
echo "�� Input: $AIS_INPUT_FILE"

Rscript --vanilla step1_split_navires.R

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Étape 1 terminée avec succès: $(date)"
    echo "📁 Fichiers sauvés dans le dossier de sortie configuré"
else
    echo "❌ Étape 1 échouée (code $exit_code): $(date)"
    exit $exit_code
fi

# Affichage résumé
echo "📊 RÉSUMÉ FRACTIONNEMENT:"
ls -lh ~/scratch/ais_split_${SLURM_JOB_ID}/ | grep ".rds"
echo "Nombre de fichiers .rds générés: $(ls ~/scratch/ais_split_${SLURM_JOB_ID}/*.rds 2>/dev/null | wc -l)" 