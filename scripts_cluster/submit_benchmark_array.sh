#!/bin/bash
# ============================================================================
# submit_benchmark_array.sh
# SLURM job: run benchmark_vs_baseline.R on the full step3 dataset.
# Single job (not array) — methods are sequential within one R session.
#
# Usage (GRIT cluster — R requires --partition=emlab_nodes):
#   cd ~/ais-pipeline/pipeline_V6
#   sbatch --partition=emlab_nodes scripts_cluster/submit_benchmark_array.sh
# ============================================================================
#SBATCH --job-name=benchmarking
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/benchmarking_%j.out
#SBATCH --error=/home/bloe/logs/benchmarking_%j.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== BENCHMARKING (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# R setup (GRIT: R in PATH directly on emlab_nodes, no module system)
export R_LIBS_USER=~/R/library

mkdir -p ~/logs
mkdir -p ~/scratch/output_V6

echo "R library: $R_LIBS_USER"
echo "Working dir: $(pwd)"

# Pre-flight: verify step3 output exists
CORE_FILE=$(ls ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*_flagOK.rds 2>/dev/null | sort | tail -1)
if [ -z "$CORE_FILE" ]; then
    echo "❌ No AIS_data_core_preprocessed_V6_*_flagOK.rds in ~/scratch/output_V6/"
    echo "   Run step3_merge_final.R first."
    exit 1
fi
echo "Step3 input: $(basename $CORE_FILE)"

echo ""
echo "Running benchmark_vs_baseline.R..."

# Pass CORE_FILE as CLI arg so commandArgs(trailingOnly=TRUE) picks it up
Rscript --vanilla scripts_principaux/benchmark_vs_baseline.R "$CORE_FILE"

exit_code=$?
echo "Exit code: $exit_code"
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ Benchmarking complete: $(date)"
    echo "Outputs:"
    ls -lh ~/scratch/output_V6/benchmarking_results.csv 2>/dev/null || \
      ls -lh output_V6/benchmarking_results.csv 2>/dev/null || \
      echo "  ⚠️ benchmarking_results.csv not found"
    ls -lh output_V6/benchmarking_comparison.png 2>/dev/null || true
else
    echo "❌ Benchmarking failed (code $exit_code)"
    exit $exit_code
fi
