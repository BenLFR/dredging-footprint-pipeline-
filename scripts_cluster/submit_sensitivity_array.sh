#!/bin/bash
# ============================================================================
# submit_sensitivity_array.sh
# SLURM array job: run sensitivity_oat_analysis.R for all 55 task IDs
# (5 parameters × 11 perturbation levels, defined in sensitivity_manifest.csv).
#
# Usage (GRIT cluster — R requires --partition=emlab_nodes):
#   cd ~/ais-pipeline/pipeline_V6
#   ARRAY_JOB_ID=$(sbatch --parsable --partition=emlab_nodes \
#                    scripts_cluster/submit_sensitivity_array.sh)
#
#   # After all 55 tasks finish, generate tornado plot:
#   sbatch --partition=emlab_nodes --dependency=afterok:$ARRAY_JOB_ID \
#          --job-name=oat_tornado --mem=4G --time=0:10:00 \
#          --chdir=/home/bloe/ais-pipeline/pipeline_V6 \
#          --output=/home/bloe/logs/tornado_%j.out \
#          --wrap="export R_LIBS_USER=~/R/library; \
#                  Rscript --vanilla scripts_principaux/plot_sensitivity_tornado.R"
# ============================================================================
#SBATCH --job-name=oat_sensitivity
#SBATCH --array=1-55
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=0:30:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/sensitivity_%A_%a.out
#SBATCH --error=/home/bloe/logs/sensitivity_%A_%a.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== OAT SENSITIVITY (job $SLURM_ARRAY_JOB_ID, task $SLURM_ARRAY_TASK_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

export R_LIBS_USER=~/R/library
mkdir -p ~/logs
mkdir -p ~/scratch/output_V6/sensitivity

# Verify manifest exists (--chdir already set CWD)
if [ ! -f configuration/sensitivity_manifest.csv ]; then
    echo "❌ configuration/sensitivity_manifest.csv not found in $(pwd)"
    exit 1
fi

# Print which parameter this task covers
PARAM=$(awk -F',' -v tid=$SLURM_ARRAY_TASK_ID \
        'NR>1 && $1==tid {print $2, $3, $4}' \
        configuration/sensitivity_manifest.csv)
echo "Task $SLURM_ARRAY_TASK_ID: $PARAM"

# Run OAT analysis — pass TASK_ID as command-line arg so commandArgs() picks it up
Rscript --vanilla scripts_principaux/sensitivity_oat_analysis.R \
        $SLURM_ARRAY_TASK_ID

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "✅ Task $SLURM_ARRAY_TASK_ID complete: $(date)"
    ls -lh ~/scratch/output_V6/sensitivity/oat_results.csv 2>/dev/null || \
      ls -lh output_V6/sensitivity/oat_results.csv 2>/dev/null || true
else
    echo "❌ Task $SLURM_ARRAY_TASK_ID failed (code $exit_code)"
    exit $exit_code
fi
