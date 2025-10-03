#!/bin/bash
#SBATCH --job-name=ais_training_NO_SF_FINAL
#SBATCH --account=def-wailung
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=ais_training_NO_SF_%j.out
#SBATCH --error=ais_training_NO_SF_%j.err

echo "🚀 DÉBUT DU JOB AUTOMATIQUE"
echo "Job ID: $SLURM_JOB_ID"
echo "Heure début: $(date)"
echo "Répertoire: $(pwd)"

# Charger R
module load r/4.5.0
echo "✅ Module R chargé"

# Aller au bon répertoire
cd ~/R_scripts
echo "✅ Répertoire R_scripts"

# Lancer le bon script
echo "🔥 Lancement du script NO_SF..."
Rscript "Entrainement modele V5 tri années cluster_NO_SF.R"

echo "🏁 JOB TERMINÉ à $(date)" 