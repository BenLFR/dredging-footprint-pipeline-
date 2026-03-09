#!/bin/bash
###############################################################################
#  SLURM – STEP 7 : Export Jtrawl for OCIM2-48L
#  Version GRIT-adapted
###############################################################################
#SBATCH --job-name=step7_jdredge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=2
#SBATCH --time=02:00:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/step7_jdredge_%j.out
#SBATCH --error=/home/bloe/logs/step7_jdredge_%j.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== STEP 7 : EXPORT Jtrawl (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# R setup
export R_LIBS_USER=~/R/library

# Repertoires utiles
mkdir -p ~/ais-pipeline/pipeline_V6/logs
mkdir -p ~/scratch/output_V6

cd ~/ais-pipeline/pipeline_V6 || { echo "Repertoire manquant"; exit 2; }

echo "Repertoire courant: $(pwd)"
echo "R library path: $R_LIBS_USER"

# Pre-flight: ocim_cache.mat
OCIM_CACHE=~/scratch/configuration/ocim/ocim_cache.mat
if [ ! -f "$OCIM_CACHE" ]; then
    echo "ocim_cache.mat manquant: $OCIM_CACHE"
    echo "   Lancez d'abord: matlab -batch \"run('step7_extract_ocim_cache.m')\""
    exit 1
fi
echo "ocim_cache.mat: $(ls -lh "$OCIM_CACHE" | awk '{print $5}')"

# Pre-flight: cri_final_*.parquet
CRI_FILES=$(find ~/scratch/output_V6/ -name "cri_final_*.parquet" 2>/dev/null | head -5)
if [ -z "$CRI_FILES" ]; then
    echo "Aucun fichier cri_final_*.parquet dans ~/scratch/output_V6/"
    echo "   Lancez d'abord Step 6"
    exit 1
fi
echo "Fichiers cri_final trouves:"
echo "$CRI_FILES"

# Pre-flight: constants.R
if [ ! -f constants.R ]; then
    echo "constants.R manquant dans $(pwd)"
    exit 1
fi
echo "constants.R present"

# Pre-flight: R.matlab package
Rscript --vanilla -e "if (!requireNamespace('R.matlab', quietly=TRUE)) stop('R.matlab not installed')" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "R.matlab package missing. Installing..."
    Rscript --vanilla -e ".libPaths('~/R/library'); install.packages('R.matlab', repos='https://cloud.r-project.org', lib='~/R/library')"
fi

echo ""
echo "Lancement step7_export_jdredge.R ..."

Rscript --vanilla -e "
  .libPaths('~/R/library')
  source('step7_export_jdredge.R')
"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "STEP 7 termine avec succes : $(date)"
    echo "Fichiers generes :"
    ls -lh ~/scratch/output_V6/jdredge_ocim2_48l_* 2>/dev/null || echo "   Aucun fichier jdredge trouve"
else
    echo "STEP 7 a echoue (code $exit_code)"
    exit $exit_code
fi
