#!/bin/bash
#SBATCH --account=def-wailung_cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --job-name=fix_packages_working
#SBATCH --output=logs/fix_packages_working_%j.out
#SBATCH --error=logs/fix_packages_working_%j.err

echo "🔧 RÉINSTALLATION PACKAGES R AVEC MÉTHODE FONCTIONNELLE"
echo "======================================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Début: $(date)"

# Chargement modules R 4.2.1
echo "📦 Chargement R 4.2.1..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Vérification version
echo "Version R:"
R --version | head -1

# Création répertoire logs
mkdir -p logs

echo "🔍 Vérification état actuel des packages..."
Rscript check_packages_status.R

echo "🔧 Réinstallation avec méthode fonctionnelle..."
Rscript install_packages_beluga_fixed.R

echo "✅ Vérification finale..."
Rscript check_packages_status.R

echo "🏁 Script terminé: $(date)" 