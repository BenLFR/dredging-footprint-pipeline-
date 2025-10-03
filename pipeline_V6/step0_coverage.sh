#!/bin/bash
#SBATCH --job-name=ais_coverage_V6
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --time=02:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step0_coverage_%j.out
#SBATCH --error=logs/step0_coverage_%j.err

echo "📊 === ÉTAPE 0: ANALYSE COUVERTURE TEMPORELLE ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node  : $SLURMD_NODENAME"
echo "Début : $(date)"

# ---- Chargement environnement R Beluga ----
module load StdEnv/2020  gcc/9.3.0  r/4.2.1
export R_LIBS=~/.local/R/4.2.1/
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK

# ---- Répertoires ----
export AIS_INPUT_PATTERN=~/scratch/AIS_data/benjamin2.csv
export AIS_OUTPUT_DIR=~/scratch/output_V6

mkdir -p logs

cd ~/R_scripts/pipeline_V6   # <-- adapte si besoin

echo "✅ Lancement analyse couverture..."
Rscript step0_coverage_analysis.R

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Analyse couverture terminée: $(date)"
    if [[ -f "$AIS_OUTPUT_DIR/core_window.yaml" ]]; then
        echo "📄 core_window.yaml disponible : $AIS_OUTPUT_DIR/core_window.yaml"
    else
        echo "⚠️  core_window.yaml MANQUANT !"
    fi
else
    echo "❌ Erreur Step 0, code $exit_code"
fi 