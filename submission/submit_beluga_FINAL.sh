#!/bin/bash
#SBATCH --account=def-benl  # Compte Beluga de benl
#SBATCH --time=04:00:00     # 4 heures maximum
#SBATCH --cpus-per-task=8   # 8 cœurs CPU
#SBATCH --mem=32G           # 32 GB de mémoire
#SBATCH --job-name=ais_training_v5_no_sf
#SBATCH --output=ais_training_no_sf_%j.out
#SBATCH --error=ais_training_no_sf_%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=benl@beluga.alliancecan.ca

# Chargement du module R
module load r/4.5.0

# Affichage des informations du job
echo "Job ID: $SLURM_JOB_ID"
echo "Nombre de CPUs: $SLURM_CPUS_PER_TASK"
echo "Mémoire allouée: $SLURM_MEM_PER_NODE MB"
echo "Nœud: $SLURM_NODELIST"
echo "Début du job: $(date)"
echo "Version: Script SANS package sf (contournement problème installation)"
echo "Utilisateur: benl"
echo "Email notifications: benl@beluga.alliancecan.ca"

# Création des répertoires nécessaires
mkdir -p ~/scratch/AIS_data
mkdir -p ~/scratch/output

# Vérification de l'existence des données
echo "Vérification des données AIS..."
if [ ! -d "$HOME/scratch/AIS_data" ] || [ -z "$(ls -A $HOME/scratch/AIS_data)" ]; then
    echo "ATTENTION: Le répertoire ~/scratch/AIS_data est vide ou n'existe pas"
    echo "Assurez-vous d'avoir copié vos données AIS dans ce répertoire"
    exit 1
else
    echo "✓ Données AIS trouvées dans ~/scratch/AIS_data/"
    ls -la ~/scratch/AIS_data/
fi

# Exécution du script R (VERSION SANS SF)
echo "Démarrage de l'analyse AIS (version sans sf)..."
echo "Script: Entrainement modele V5 tri années cluster_NO_SF.R"
Rscript "Entrainement modele V5 tri années cluster_NO_SF.R"

# Vérification du succès
if [ $? -eq 0 ]; then
    echo "✅ Script R terminé avec succès"
    echo "Résultats disponibles dans ~/scratch/output/"
    ls -la ~/scratch/output/
else
    echo "❌ Erreur lors de l'exécution du script R"
    exit 1
fi

echo "Fin du job: $(date)" 