#!/bin/bash
###############################################################################
#  SLURM – STEP 0bis ENHANCED : Optimal time window selection
#  Version GRIT-adapted
###############################################################################
#SBATCH --job-name=ais_window_V6_enhanced
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --output=logs/step0_window_enhanced_%j.out
#SBATCH --error=logs/step0_window_enhanced_%j.err

echo "=== STEP 0bis ENHANCED : FENETRE OPTIMALE (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Début: $(date)"

# Modules / librairies R (GRIT configuration)
module load R
export R_LIBS_USER=~/R/library

# Working directories
mkdir -p logs
cd ~/ais-pipeline/pipeline_V6 || { echo "Repertoire manquant"; exit 2; }

echo "  Repertoire courant: $(pwd)"
echo "  R library path: $R_LIBS_USER"
echo "  Lancement step0_core_window_enhanced.R ..."

# Launch R interpreter with .libPaths override
Rscript --vanilla -e "
  .libPaths('~/R/library')
  source('step0_core_window_enhanced.R')
"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "  STEP 0bis ENHANCED completed successfully: $(date)"
    echo "  Selection file      : ~/scratch/output_V6/core_window_report.md"
    echo "  Full analysis       : ~/scratch/output_V6/all_windows_analysis.csv"
    echo "  Top 20 windows      : ~/scratch/output_V6/top_20_windows.csv"
    echo "  Annual statistics   : ~/scratch/output_V6/annual_statistics.csv"
    echo "  Coverage matrix     : ~/scratch/output_V6/coverage_matrix.csv"
else
    echo "  STEP 0bis ENHANCED failed (code $exit_code)"
fi
