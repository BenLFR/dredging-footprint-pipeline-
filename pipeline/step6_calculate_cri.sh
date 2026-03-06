#!/bin/bash
###############################################################################
#  SLURM – STEP 6 : Calcul du Carbone Reminéralise (Cri)
#  Version GRIT-adapted
###############################################################################
#SBATCH --job-name=step6_cri
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=08:00:00
#SBATCH --chdir=$HOME/ais-pipeline/pipeline_V6
#SBATCH --output=$HOME/logs/step6_cri_%j.out
#SBATCH --error=$HOME/logs/step6_cri_%j.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== STEP 6 : CALCUL DE CRI (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# R setup (GRIT: no module system on compute nodes, R in PATH directly)
export R_LIBS_USER=~/R/library

# Repertoires utiles
mkdir -p ~/ais-pipeline/pipeline_V6/logs
mkdir -p ~/scratch/output_V6
mkdir -p ~/scratch/tmp_terra

cd ~/ais-pipeline/pipeline_V6 || { echo "Repertoire manquant"; exit 2; }

echo "✅ Repertoire courant: $(pwd)"
echo "✅ R library path: $R_LIBS_USER"

# Pre-flight: verifier les rasters carbone Atwood
CARBON_DIR=~/scratch/configuration/atwood_carbon_full
if [ ! -d "$CARBON_DIR" ] || [ -z "$(ls "$CARBON_DIR"/*.tif 2>/dev/null)" ]; then
    echo "❌ Rasters carbone manquants dans $CARBON_DIR"
    echo "   Lancez d'abord: bash deploy/upload_step6_to_grit.sh"
    exit 1
fi
echo "✅ Rasters carbone: $(ls "$CARBON_DIR"/*.tif | wc -l) fichiers TIF"

# Pre-flight: verifier les fichiers f_i (output de Step 5)
FI_FILES=$(find ~/scratch/output_V6/ -name "fi_grid_*.parquet" -o -name "fi_grid_*.rds" 2>/dev/null | head -5)
if [ -z "$FI_FILES" ]; then
    echo "❌ Aucun fichier f_i trouve dans ~/scratch/output_V6/"
    echo "   Lancez d'abord Step 5"
    exit 1
fi
echo "✅ Fichiers f_i trouves:"
echo "$FI_FILES"

# Pre-flight: verifier constants.R
if [ ! -f constants.R ]; then
    echo "❌ constants.R manquant dans $(pwd)"
    exit 1
fi
echo "✅ constants.R present"

echo ""
echo "Lancement step6_calculate_cri_corrected.R ..."

Rscript --vanilla -e "
  .libPaths('~/R/library')
  source('step6_calculate_cri_corrected.R')
"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ STEP 6 termine avec succes : $(date)"
    echo "Fichiers generes :"
    ls -lh ~/scratch/output_V6/cri_final_* 2>/dev/null || echo "   Aucun fichier cri_final trouve"
else
    echo "❌ STEP 6 a echoue (code $exit_code)"
    exit $exit_code
fi
