#!/bin/bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --job-name=step3_v6_dryrun

export DRYRUN_N=500000
Rscript ~/R_scripts/pipeline_V6/pipeline_V6/step3_merge_final.R
