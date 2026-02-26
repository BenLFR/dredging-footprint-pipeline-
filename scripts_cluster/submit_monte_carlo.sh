#!/bin/bash
# ============================================================================
# submit_monte_carlo.sh
# SLURM array: 10 batches × 50 iterations = 500 Monte Carlo iterations.
# After all batches complete, a merge job computes per-cell summary stats.
#
# Usage (GRIT cluster — R requires --partition=emlab_nodes):
#   cd ~/ais-pipeline/pipeline_V6
#
#   # Step 1: Submit the MC array
#   ARRAY_JOB_ID=$(sbatch --parsable --partition=emlab_nodes \
#                    scripts_cluster/submit_monte_carlo.sh)
#   echo "MC array job: $ARRAY_JOB_ID"
#
#   # Step 2: Submit merge as a dependent job (runs after ALL array tasks finish)
#   sbatch --partition=emlab_nodes \
#          --dependency=afterok:$ARRAY_JOB_ID \
#          --job-name=mc_merge --mem=16G --time=0:30:00 \
#          --chdir=/home/bloe/ais-pipeline/pipeline_V6 \
#          --output=/home/bloe/logs/mc_merge_%j.out \
#          --exclude=hpc-08.grit.ucsb.edu \
#          --wrap="export R_LIBS_USER=~/R/library; \
#                  Rscript --vanilla scripts_principaux/mc_merge_results.R"
# ============================================================================
#SBATCH --job-name=mc_uncertainty
#SBATCH --array=1-10
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/mc_%A_%a.out
#SBATCH --error=/home/bloe/logs/mc_%A_%a.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== MONTE CARLO UNCERTAINTY (job $SLURM_ARRAY_JOB_ID, batch $SLURM_ARRAY_TASK_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"
echo "Iterations: $(( ($SLURM_ARRAY_TASK_ID-1)*50+1 )) – $(( $SLURM_ARRAY_TASK_ID*50 ))"

export R_LIBS_USER=~/R/library
mkdir -p ~/logs
mkdir -p ~/scratch/output_V6/uncertainty

# Run MC batch — pass BATCH_ID as command-line arg so commandArgs() picks it up
Rscript --vanilla scripts_principaux/monte_carlo_uncertainty.R \
        $SLURM_ARRAY_TASK_ID

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo "✅ Batch $SLURM_ARRAY_TASK_ID complete: $(date)"
    ls -lh ~/scratch/output_V6/uncertainty/mc_batch_$(printf '%02d' $SLURM_ARRAY_TASK_ID).parquet \
       2>/dev/null || ls -lh output_V6/uncertainty/mc_batch_*.parquet 2>/dev/null | tail -1
else
    echo "❌ Batch $SLURM_ARRAY_TASK_ID failed (code $exit_code)"
    exit $exit_code
fi

# ── Inline merge script (written to disk for the dependent job) ───────────────
# This script is generated here and called by the merge job above.
cat > scripts_principaux/mc_merge_results.R << 'RSCRIPT_EOF'
#!/usr/bin/env Rscript
# mc_merge_results.R
# Merges all mc_batch_*.parquet files from output_V6/uncertainty/
# and computes per-cell summary statistics across 500 MC iterations.
#
# Output: output_V6/uncertainty/mc_results_summary.parquet
#   Columns: cell_id, grid_id, fi_mean, fi_sd, fi_p025, fi_p975,
#             C_ri_mean, C_ri_sd, C_ri_p025, C_ri_p975

suppressPackageStartupMessages(library(data.table))

search_dirs <- c("output_V6/uncertainty",
                 file.path(path.expand("~"), "scratch", "output_V6", "uncertainty"))

batch_files <- character(0)
for (d in search_dirs) {
  if (dir.exists(d)) {
    found_pq  <- list.files(d, pattern = "^mc_batch_[0-9]+\\.parquet$", full.names = TRUE)
    found_rds <- list.files(d, pattern = "^mc_batch_[0-9]+\\.rds$",     full.names = TRUE)
    batch_files <- c(batch_files, found_pq, found_rds)
  }
}
batch_files <- unique(batch_files)
if (length(batch_files) == 0) stop("No mc_batch_*.parquet/rds found.")

cat(sprintf("Merging %d batch files...\n", length(batch_files)))
all_mc <- rbindlist(lapply(batch_files, function(f) {
  if (grepl("\\.parquet$", f) && requireNamespace("arrow", quietly = TRUE)) {
    setDT(arrow::read_parquet(f))
  } else {
    setDT(readRDS(f))
  }
}), fill = TRUE)

cat(sprintf("Loaded %d rows | %d unique cells | %d iterations\n",
            nrow(all_mc), uniqueN(all_mc$cell_id), uniqueN(all_mc$iteration)))

# Compute per-cell summary
summary_dt <- all_mc[, .(
  fi_mean   = mean(fi_value,   na.rm = TRUE),
  fi_sd     = sd(fi_value,     na.rm = TRUE),
  fi_p025   = quantile(fi_value,   0.025, na.rm = TRUE),
  fi_p975   = quantile(fi_value,   0.975, na.rm = TRUE),
  C_ri_mean = mean(C_ri_value, na.rm = TRUE),
  C_ri_sd   = sd(C_ri_value,   na.rm = TRUE),
  C_ri_p025 = quantile(C_ri_value, 0.025, na.rm = TRUE),
  C_ri_p975 = quantile(C_ri_value, 0.975, na.rm = TRUE),
  n_iter    = .N
), by = .(cell_id, grid_id)]

cat(sprintf("Summary: %d cells\n", nrow(summary_dt)))
cat(sprintf("C_ri 95%% CI width (median): %.4f\n",
            median(summary_dt$C_ri_p975 - summary_dt$C_ri_p025, na.rm = TRUE)))

out_dir <- "output_V6/uncertainty"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

if (requireNamespace("arrow", quietly = TRUE)) {
  out_path <- file.path(out_dir, "mc_results_summary.parquet")
  arrow::write_parquet(summary_dt, out_path)
} else {
  out_path <- file.path(out_dir, "mc_results_summary.rds")
  saveRDS(summary_dt, out_path)
}
cat("Saved:", out_path, "\n")
RSCRIPT_EOF

chmod +x scripts_principaux/mc_merge_results.R
echo "mc_merge_results.R written for dependent merge job."
