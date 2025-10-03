#!/bin/bash
#SBATCH --job-name=ais_process_V6
#SBATCH --array=1-12%8
#SBATCH --mem=6G
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/step2_process_%A_%a.out
#SBATCH --error=logs/step2_process_%A_%a.err

echo "🔄 === ÉTAPE 2: TRAITEMENT NAVIRE $SLURM_ARRAY_TASK_ID ==="
echo "Array Job ID: $SLURM_ARRAY_JOB_ID"
echo "Task ID: $SLURM_ARRAY_TASK_ID"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

# Configuration environnement pipeline
export PIPELINE_V6_ROOT=~/R_scripts/pipeline_V6
export DT_GForce=FALSE

# Configuration mémoire conservative
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Paramètres
SPLIT_JOB_ID=${1:-"LATEST"}  # ID du job split passé en paramètre

# Vérification répertoire source
if [ ! -d "~/scratch/ais_split_${SPLIT_JOB_ID}" ]; then
    echo "❌ Erreur: Répertoire source non trouvé ~/scratch/ais_split_${SPLIT_JOB_ID}"
    exit 1
fi

# Vérification nombre de navires
if [ ! -f "~/scratch/ais_split_${SPLIT_JOB_ID}/nb_navires.txt" ]; then
    echo "⚠️  Métadonnées nb_navires.txt non trouvées, détection automatique..."
    nb_navires=$(ls ~/scratch/ais_split_${SPLIT_JOB_ID}/navire_*.rds 2>/dev/null | wc -l)
else
    nb_navires=$(cat ~/scratch/ais_split_${SPLIT_JOB_ID}/nb_navires.txt)
fi

# Vérification task ID valide
if [ $SLURM_ARRAY_TASK_ID -gt $nb_navires ]; then
    echo "⚠️  Task ID $SLURM_ARRAY_TASK_ID > $nb_navires navires, arrêt normal"
    exit 0
fi

mkdir -p logs
cd ${PIPELINE_V6_ROOT}

echo "✅ Lancement traitement navire $SLURM_ARRAY_TASK_ID/$nb_navires..."
echo "📁 Source: ~/scratch/ais_split_${SPLIT_JOB_ID}/"

R --vanilla --slave -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_ARRAY_TASK_ID = '$SLURM_ARRAY_TASK_ID')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
Sys.setenv(DT_GForce = 'FALSE')
source('step2_process_navire.R')
" 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Navire $SLURM_ARRAY_TASK_ID traité avec succès: $(date)"
    
    # Affichage résultat avec format .rds
    echo "📊 RÉSUMÉ NAVIRE $SLURM_ARRAY_TASK_ID:"
    ls -lh ~/scratch/ais_split_${SPLIT_JOB_ID}/navire_*${SLURM_ARRAY_TASK_ID}_*_clean.rds 2>/dev/null || echo "⚠️  Fichier clean non trouvé"
    
else
    echo "❌ Erreur navire $SLURM_ARRAY_TASK_ID: code $exit_code"
    exit $exit_code
fi 