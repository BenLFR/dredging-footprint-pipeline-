#!/bin/bash
#SBATCH --job-name=core_period_cov
#SBATCH --mem=8G
#SBATCH --cpus-per-task=8
#SBATCH --time=00:45:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/core_cov_%j.out
#SBATCH --error=logs/core_cov_%j.err

echo "📊 STEP-0 | Core Period Selection | $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"

# ──────────────  MODULES & ENV  ───────────────
module purge
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK

# ──────────────  PARAMÉTRAGE  ────────────────
export AIS_INPUT_PATTERN="${1:-~/scratch/AIS_data/*.csv}"
export AIS_OUTPUT_DIR="${2:-~/scratch/output_V6}"

# ──────────────  LOGS & SCRIPTS  ─────────────
mkdir -p logs
SCRIPT=~/R_scripts/pipeline_V6/step0_core_window.R

if [ ! -f "$SCRIPT" ]; then
    echo "❌ Script introuvable : $SCRIPT"
    exit 1
fi

echo "ℹ️  Pattern : $AIS_INPUT_PATTERN"
echo "ℹ️  Output  : $AIS_OUTPUT_DIR"
echo "ℹ️  Script  : $SCRIPT"

# ──────────────  LANCEMENT  ────────────────
echo "✅ Lancement de la sélection core window..."
Rscript --vanilla "$SCRIPT"
exit_code=$?

# ──────────────  FIN / BILAN  ──────────────
if [ $exit_code -eq 0 ]; then
    echo "✅ Terminé sans erreur : $(date)"
    echo "📄 Rapports dans $AIS_OUTPUT_DIR"
else
    echo "❌ Échec (code $exit_code) : $(date)"
fi

exit $exit_code
