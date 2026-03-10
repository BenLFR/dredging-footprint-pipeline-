#!/bin/bash
#SBATCH --job-name=ais_split_V6
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00

#SBATCH --output=logs/step1_split_%j.out
#SBATCH --error=logs/step1_split_%j.err

# Configuration R GRIT
module load R

echo "=== STEP 1: SPLIT AIS BY VESSEL ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Start: $(date)"

# Configuration R Beluga

export R_LIBS_USER=~/R/library
# AIS_INPUT_FILE must be set in the submission environment — do not hardcode here

# Create directories
mkdir -p ~/scratch/ais_split_${SLURM_JOB_ID}
mkdir -p logs

# Change to pipeline working directory
cd ~/ais-pipeline/pipeline_V6 || { echo "ERROR: pipeline directory not found"; exit 1; }

echo "  Working directory: $(pwd)"
echo "  Checking R script: $(ls -la step1_split_vessels.R 2>/dev/null || echo 'FILE NOT FOUND')"

echo "  Launching split script..."
Rscript --vanilla -e "
.libPaths(Sys.getenv('R_LIBS_USER', '~/R/library'))
Sys.setenv(SLURM_JOB_ID = '$SLURM_JOB_ID')
source('step1_split_vessels.R')
" 2>&1

echo "  Step 1 complete: $(date)"
echo "  Files saved to: ~/scratch/ais_split_${SLURM_JOB_ID}/"

# Display summary
echo "  SPLIT SUMMARY:"
# Note: format may be .qs or .rds depending on package availability
ls -lh ~/scratch/ais_split_${SLURM_JOB_ID}/ | grep -E "\.(qs|rds|fst)$"
wc -l ~/scratch/ais_split_${SLURM_JOB_ID}/*.fst 2>/dev/null || echo "No .fst files found"
