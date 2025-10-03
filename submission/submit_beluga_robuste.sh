#!/bin/bash
#SBATCH --account=def-wailung_cpu
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=187G
#SBATCH --job-name=ais_robuste
#SBATCH --output=logs/ais_robuste_%j.out
#SBATCH --error=logs/ais_robuste_%j.err

# Chargement des modules
echo "🔧 Chargement modules R..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Création répertoire logs
mkdir -p logs

# Information job
echo "🎯 JOB ROBUSTE - Élimination fuites de données"
echo "Job ID: $SLURM_JOB_ID"
echo "Nœud: $SLURM_NODELIST"
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Mémoire: $SLURM_MEM_PER_NODE MB"
echo "Début: $(date)"

# Installation packages (si nécessaire)
echo "📦 Installation packages R..."
Rscript install_packages_beluga_fixed.R

# Exécution script principal ROBUSTE
echo "🚀 Lancement analyse robuste AIS..."
Rscript Entrainement_modele_ROBUSTE.R

echo "✅ Analyse terminée: $(date)"
echo "📊 Fichiers générés dans ~/scratch/output/"

# Résumé final
echo ""
echo "🔬 MÉTHODOLOGIE ROBUSTE APPLIQUÉE:"
echo "• GMM ré-entraîné par fold (pas de fuite temporelle)"
echo "• GLM au lieu de Random Forest (stabilité)"
echo "• Vitesse dominante (w1 ≥ 20%)"
echo "• Contrôles diagnostiques avancés" 