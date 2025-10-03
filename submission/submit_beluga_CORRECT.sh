#!/bin/bash
#SBATCH --account=def-wailung  # COMPTE CORRECT !
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --job-name=ais_training_v5_no_sf
#SBATCH --output=ais_training_no_sf_%j.out
#SBATCH --error=ais_training_no_sf_%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=benl@beluga.alliancecan.ca

module load r/4.5.0

echo "Job ID: $SLURM_JOB_ID"
echo "Début du job: $(date)"
echo "Version: Script SANS package sf"
echo "Compte: def-wailung"

mkdir -p ~/scratch/AIS_data
mkdir -p ~/scratch/output

echo "Vérification des données AIS..."
if [ ! -d "$HOME/scratch/AIS_data" ] || [ -z "$(ls -A $HOME/scratch/AIS_data)" ]; then
    echo "ATTENTION: Données AIS manquantes"
    exit 1
else
    echo "✓ Données AIS trouvées"
    ls -la ~/scratch/AIS_data/
fi

echo "Démarrage de l'analyse AIS..."
Rscript "Entrainement modele V5 tri années cluster_NO_SF.R"

if [ $? -eq 0 ]; then
    echo "✅ Script R terminé avec succès"
    ls -la ~/scratch/output/
else
    echo "❌ Erreur lors de l'exécution"
    exit 1
fi

echo "Fin du job: $(date)" 