#!/bin/bash
#SBATCH --job-name=ais_split_V6
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00

#SBATCH --output=logs/step1_split_%j.out
#SBATCH --error=logs/step1_split_%j.err

# Configuration R GRIT
module load R

echo "🚀 === ÉTAPE 1: FRACTIONNEMENT PAR NAVIRE ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"

# Configuration R Beluga

export R_LIBS_USER=~/R/library
export AIS_INPUT_FILE=~/scratch/AIS_data/benjamin3_clean.csv

# Création répertoires
mkdir -p ~/scratch/ais_split_${SLURM_JOB_ID}
mkdir -p logs

# CORRECTION: Rester dans le bon répertoire
cd ~/scratch/pipeline_V6

echo "✅ Répertoire de travail: $(pwd)"
echo "✅ Vérification fichier R: $(ls -la step1_split_navires.R 2>/dev/null || echo 'FICHIER MANQUANT')"

echo "✅ Lancement script de fractionnement..."
Rscript --vanilla -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_JOB_ID = '$SLURM_JOB_ID')
source('step1_split_navires.R')
" 2>&1

echo "✅ Étape 1 terminée: $(date)"
echo "📁 Fichiers sauvés dans: ~/scratch/ais_split_${SLURM_JOB_ID}/"

# Affichage résumé
echo "📊 RÉSUMÉ FRACTIONNEMENT:"
ls -lh ~/scratch/ais_split_${SLURM_JOB_ID}/ | grep ".fst"
wc -l ~/scratch/ais_split_${SLURM_JOB_ID}/*.fst 2>/dev/null || echo "Erreur: aucun fichier .fst trouvé" 