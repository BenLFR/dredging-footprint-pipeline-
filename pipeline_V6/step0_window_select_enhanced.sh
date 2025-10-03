#!/bin/bash
###############################################################################
#  SLURM – STEP 0bis ENHANCED : Sélection de la fenêtre temporelle optimale
#  Version améliorée avec analyse complète de toutes les fenêtres candidates
###############################################################################
#SBATCH --job-name=ais_window_V6_enhanced
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step0_window_enhanced_%j.out
#SBATCH --error=logs/step0_window_enhanced_%j.err

echo "🔍 === STEP 0bis ENHANCED : FENÊTRE OPTIMALE (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Début: $(date)"

# Modules / librairies R
module --force purge
module load StdEnv/2023
module load r/4.3.1
export R_LIBS=~/R/4.3

# Répertoires utiles
mkdir -p logs
cd ~/R_scripts/pipeline_V6 || { echo "❌ Répertoire manquant"; exit 2; }

echo "✅  Répertoire courant: $(pwd)"
echo "✅  Lancement step0_core_window_enhanced.R ..."

# Appel de l'interpréteur R
Rscript --vanilla step0_core_window_enhanced.R
exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "✅  STEP 0bis ENHANCED terminé avec succès : $(date)"
    echo "📄  Fichier de sélection : ~/scratch/output_V6/core_window_report.md"
    echo "📊  Analyse complète : ~/scratch/output_V6/all_windows_analysis.csv"
    echo "🏆  Top 20 fenêtres : ~/scratch/output_V6/top_20_windows.csv"
    echo "📈  Statistiques annuelles : ~/scratch/output_V6/annual_statistics.csv"
else
    echo "❌  STEP 0bis ENHANCED a échoué (code $exit_code)"
fi 