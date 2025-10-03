#!/bin/bash
#SBATCH --job-name=ais_lithology_monde
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step4_lithology_monde_%j.out
#SBATCH --error=logs/step4_lithology_monde_%j.err

echo "🏁 === ÉTAPE 4: AJOUT LITHOLOGIE (MONDE) ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

# Installation des packages si nécessaire
R --vanilla --slave -e "
if (!require('FNN')) install.packages('FNN', repos='https://cloud.r-project.org/')
if (!require('geosphere')) install.packages('geosphere', repos='https://cloud.r-project.org/')
if (!require('data.table')) install.packages('data.table', repos='https://cloud.r-project.org/')
"

# Configuration haute performance
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8

mkdir -p logs

cd ~/R_scripts

echo "✅ Lancement ajout lithologie clean (monde)..."
echo "📁 Source: ~/scratch/output_V6/"

# Vérification de l'espace disque disponible
echo "💾 Espace disque disponible:"
df -h ~/scratch

R --vanilla --slave -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_CPUS_PER_TASK = '8')
source('02_add_lithology_to_AIS_cluster.R')
" 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Ajout lithologie clean (monde) terminé avec succès: $(date)"
    
    # Résumé final
    echo "📊 === RÉSUMÉ FINAL ==="
    ls -lh ~/scratch/output_V6/AIS_with_lithology_clean* 2>/dev/null || echo "Fichiers de sortie non trouvés"
    
    # Vérification de la taille du fichier
    latest_file=$(ls -t ~/scratch/output_V6/AIS_with_lithology_clean*.rds | head -n 1)
    if [ -n "$latest_file" ]; then
        echo "📦 Taille du fichier de sortie: $(du -h $latest_file | cut -f1)"
        echo "📊 Nombre de lignes: $(R --vanilla --slave -e "nrow(readRDS('$latest_file'))")"
    fi
    
else
    echo "❌ Erreur lors de l'ajout lithologie (monde): code $exit_code"
    exit $exit_code
fi

echo "🎉 ÉTAPE 4 (MONDE) TERMINÉE !"
