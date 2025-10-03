#!/bin/bash
#SBATCH --account=def-wailung_cpu
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --job-name=test_corrections
#SBATCH --output=logs/test_corrections_%j.out
#SBATCH --error=logs/test_corrections_%j.err

# Chargement des modules
echo "🔧 Chargement modules R..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Création répertoire logs
mkdir -p logs

# Information job
echo "🧪 TEST CORRECTIONS ROBUSTES"
echo "Job ID: $SLURM_JOB_ID"
echo "Début: $(date)"

# Installation packages si nécessaire
echo "📦 Installation packages R..."
Rscript install_packages_beluga_fixed.R

# Test principal
echo "🔬 Lancement tests validation..."
Rscript test_beluga_corrections.R

echo "✅ Tests terminés: $(date)" 