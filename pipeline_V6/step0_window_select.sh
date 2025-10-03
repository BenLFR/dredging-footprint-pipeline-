#!/bin/bash
###############################################################################
#  SLURM – STEP 0bis : Sélection de la fenêtre temporelle optimale
###############################################################################
#SBATCH --job-name=ais_window_V6
#SBATCH --mem=6G
#SBATCH --cpus-per-task=2
#SBATCH --time=00:20:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step0_window_%j.out
#SBATCH --error=logs/step0_window_%j.err

echo "🔍 === STEP 0bis : FENÊTRE OPTIMALE (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Début: $(date)"

# Modules / librairies R
module load StdEnv/2020  gcc/9.3.0  r/4.2.1
export R_LIBS=/home/benl/R/library

# Répertoires utiles
mkdir -p logs
cd  ~/R_scripts/pipeline_V6   || { echo "❌ Répertoire manquant"; exit 2; }

echo "✅  Répertoire courant: $(pwd)"
echo "✅  Lancement step0_core_window.R ..."

# Appel de l’interpréteur R
Rscript --vanilla step0_core_window.R
exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "✅  STEP 0bis terminé avec succès : $(date)"
    echo "📄  Fichier de sélection : ~/scratch/output_V6/core_window_report.md"
else
    echo "❌  STEP 0bis a échoué (code $exit_code)"
fi
