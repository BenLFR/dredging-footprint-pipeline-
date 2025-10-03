#!/bin/bash
#SBATCH --account=def-wailung_cpu
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --job-name=test_fix_packages
#SBATCH --output=logs/test_fix_%j.out
#SBATCH --error=logs/test_fix_%j.err

echo "🧪 TEST PACKAGES APRÈS CORRECTION"
echo "================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Début: $(date)"

# Chargement modules R 4.2.1
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Création répertoire logs
mkdir -p logs

# Exécution test
echo "🔬 Lancement test packages..."
Rscript test_after_fix.R

echo "✅ Test terminé: $(date)" 