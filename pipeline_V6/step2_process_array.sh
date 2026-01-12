#!/bin/bash
#SBATCH --job-name=ais_process_V6
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00
#SBATCH --output=logs/step2_process_%A_%a.out
#SBATCH --error=logs/step2_process_%A_%a.err

###############################################################################
# 0) Charger l’environnement
###############################################################################
export R_LIBS_USER=~/R/library
export LAND_MASK_FILE=~/ais-pipeline/configuration/land_mask/land_polygons.shp

###############################################################################
# 1) ID du job Step-1 ( **sans préfixe** )
###############################################################################
SPLIT_JOB_ID=${SPLIT_JOB_ID:?SPLIT_JOB_ID non défini}

###############################################################################
# 2) Taille automatique de l’array
###############################################################################
META=~/scratch/ais_split_${SPLIT_JOB_ID}/navires_metadata.csv
if [[ ! -f $META ]]; then
  echo "Erreur : $META introuvable"; exit 1
fi
N_SHIPS=$(( $(wc -l < "$META") - 1 ))      # -1 pour l'en-tête

###############################################################################
# 3) Hash de la version du script R (optionnel)
###############################################################################
SCRIPT_HASH=$(md5sum step2_process_navire.R | cut -d' ' -f1)

###############################################################################
# 4) Lancement du traitement pour le navire courant
###############################################################################
cd ~/ais-pipeline/pipeline_V6

echo "🚀 === ÉTAPE 2: TRAITEMENT NAVIRE ${SLURM_ARRAY_TASK_ID} ==="
echo "Job ID: ${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
echo "Node: $SLURMD_NODENAME"
echo "Début: $(date)"
echo "📦 Job fractionnement référence: $SPLIT_JOB_ID"
echo "✅ Répertoire de travail: $(pwd)"
echo "✅ Vérification fichier R: $(ls -la step2_process_navire.R 2>/dev/null || echo 'FICHIER MANQUANT')"

echo "✅ Lancement traitement navire ${SLURM_ARRAY_TASK_ID}..."
R --vanilla --slave -e "
.libPaths('~/R/library')
Sys.setenv(SLURM_ARRAY_TASK_ID = '${SLURM_ARRAY_TASK_ID}')
Sys.setenv(SLURM_ARRAY_JOB_ID = '${SLURM_ARRAY_JOB_ID}')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
source('step2_process_navire.R')
" 2>&1

echo "✅ Étape 2 terminée: $(date)"
echo "📁 Résultats sauvés dans: ~/scratch/ais_results_${SLURM_ARRAY_JOB_ID}/" 