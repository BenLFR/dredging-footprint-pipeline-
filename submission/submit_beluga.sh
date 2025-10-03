#!/bin/bash
#SBATCH --account=def-wailung  # Compte correct pour benl
#SBATCH --time=12:00:00        # 12 heures maximum
#SBATCH --cpus-per-task=16     # 16 cœurs CPU (plus de puissance)
#SBATCH --mem=64G              # 64 GB de mémoire (plus de RAM)
#SBATCH --job-name=ais_training_no_sf
#SBATCH --output=ais_training_no_sf_%j.out
#SBATCH --error=ais_training_no_sf_%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=benl@beluga.alliancecan.ca

# Chargement du module R (version disponible sur Beluga)
module load r/4.5.0

# Affichage des informations du job
echo "Job ID: $SLURM_JOB_ID"
echo "Nombre de CPUs: $SLURM_CPUS_PER_TASK"
echo "Mémoire allouée: $SLURM_MEM_PER_NODE MB"
echo "Nœud: $SLURM_NODELIST"
echo "Début du job: $(date)"
echo "Version: Script SANS package sf (contournement problème installation)"
echo "Utilisateur: $USER"
echo "Email notifications: benl@beluga.alliancecan.ca"
echo "Configuration: 16 CPUs, 64GB RAM, 12h max"

# Vérification des données AIS
echo "Vérification des données AIS..."
if [ -d ~/scratch/AIS_data ] && [ "$(ls -A ~/scratch/AIS_data)" ]; then
    echo "✓ Données AIS trouvées dans ~/scratch/AIS_data/"
    ls -la ~/scratch/AIS_data/
else
    echo "❌ ERREUR: Aucune donnée AIS trouvée dans ~/scratch/AIS_data/"
    echo "Veuillez transférer vos fichiers CSV avant de relancer le job"
    exit 1
fi

# Création du répertoire de sortie
mkdir -p ~/scratch/output

# Exécution du script R (version sans sf)
echo "Démarrage de l'analyse AIS (version sans sf)..."
echo "Script: Entrainement modele V5 tri années cluster_NO_SF.R"
echo "Grid-search avec 148 combinaisons de poids..."
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