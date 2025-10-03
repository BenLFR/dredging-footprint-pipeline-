#!/bin/bash
#SBATCH --job-name=step5_fi_global
#SBATCH --output=logs/step5_fi_global_%j.out
#SBATCH --error=logs/step5_fi_global_%j.err
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00

SCRIPT_PATH="$HOME/R_scripts/step5_compute_fi_global.R"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ Script non trouvé : $SCRIPT_PATH"
    exit 1
fi

module load apptainer

apptainer exec $HOME/scratch/rocker_geospatial_4.5.0.sif Rscript "$SCRIPT_PATH"