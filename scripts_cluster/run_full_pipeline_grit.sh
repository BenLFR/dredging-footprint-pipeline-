#!/bin/bash
# =============================================================================
# run_full_pipeline_grit.sh
# Full autonomous pipeline orchestrator — GRIT cluster (emlab_nodes partition)
#
# Usage:
#   bash run_full_pipeline_grit.sh                   # run from step 0
#   bash run_full_pipeline_grit.sh --from-step 4     # restart from step 4
#   bash run_full_pipeline_grit.sh --include-co2model
#   bash run_full_pipeline_grit.sh --from-step 4 --include-co2model
#   bash run_full_pipeline_grit.sh --from-step 2 --split-job-id <step1_jobid>
#   bash run_full_pipeline_grit.sh --from-step 3 --split-job-id <step1_jobid> \
#                                  --results-dir ~/scratch/ais_results_<step2_array_jobid>
#
# Dependency chain:
#   JOB0 (step0, 30m)
#    └─ JOB1 (step1, 30m)
#        └─ JOB_RELAY (5m — reads vessel count N, submits everything below)
#             └─ JOB2 (step2 array 1-N%20, 2h each)
#                  └─ JOB3 (step3_merge_grit_256G, 12h, 256G)
#                       └─ JOB4 (step4, 2h, 32G)
#                            └─ JOB5A (step5_make_tiles, 20m, 8G)
#                                 └─ JOB5B (step5_tile_job array 1-648%20, 12h, 16G)
#                                      └─ JOB5C (step5_merge_slurm_optimized, 6h, 128G)
#                                           └─ JOB6 (step6, 8h, 64G)
#                                                └─ JOB7 (step7, 2h, 32G)
#                                                     └─ [JOB_CO2] optional
#
# Output layout:
#   ~/scratch/output_V6/step{0,1,2,3,4,5,6,7}/   organised after each step
#   ~/logs/pipeline_run_YYYYMMDD_HHMMSS.txt        manifest of all job IDs
# =============================================================================

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
FROM_STEP=0
CO2=false
SPLIT_JOB_ID_ARG=""
RESULTS_DIR_ARG=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --from-step)
      [[ $# -ge 2 ]] || { echo "Error: --from-step requires a value"; exit 1; }
      FROM_STEP=$2; shift 2 ;;
    --include-co2model) CO2=true;    shift   ;;
    --split-job-id)
      [[ $# -ge 2 ]] || { echo "Error: --split-job-id requires a value"; exit 1; }
      SPLIT_JOB_ID_ARG=$2; shift 2 ;;
    --results-dir)
      [[ $# -ge 2 ]] || { echo "Error: --results-dir requires a value"; exit 1; }
      RESULTS_DIR_ARG=$2; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1        ;;
  esac
done

if ! [[ "$FROM_STEP" =~ ^[0-9]+$ ]]; then
  echo "Error: --from-step must be an integer in [0,8]."
  exit 1
fi
if (( FROM_STEP < 0 || FROM_STEP > 8 )); then
  echo "Error: --from-step must be in [0,8]."
  exit 1
fi
if (( FROM_STEP == 2 || FROM_STEP == 3 )) && [[ -z "$SPLIT_JOB_ID_ARG" ]]; then
  echo "Error: --split-job-id is required for --from-step 2 or 3."
  exit 1
fi
if (( FROM_STEP == 3 )) && [[ -z "$RESULTS_DIR_ARG" ]]; then
  echo "Error: --results-dir is required for --from-step 3."
  exit 1
fi
if [[ -n "$RESULTS_DIR_ARG" && ! -d "$RESULTS_DIR_ARG" ]]; then
  echo "Error: --results-dir not found: $RESULTS_DIR_ARG"
  exit 1
fi

# ── Constants ─────────────────────────────────────────────────────────────────
PIPELINE=~/ais-pipeline/pipeline_V6
SCRATCH=~/scratch/output_V6
LOGS=~/logs
PART=emlab_nodes
RUN_ID=$(date +%Y%m%d_%H%M%S)
MANIFEST=$LOGS/pipeline_run_${RUN_ID}.txt

mkdir -p "$SCRATCH/step0" "$SCRATCH/step1" "$SCRATCH/step2" "$SCRATCH/step3" \
         "$SCRATCH/step4" "$SCRATCH/step5" "$SCRATCH/step6" "$SCRATCH/step7" \
         "$SCRATCH/co2" "$LOGS"

echo "# Pipeline run ${RUN_ID}  (from step ${FROM_STEP})" | tee "$MANIFEST"
echo "# Logs: $LOGS" | tee -a "$MANIFEST"
echo "# CO2 model: $CO2" | tee -a "$MANIFEST"

# ── Initialise variables so they are always defined ───────────────────────────
JOB0=""
JOB1=""
PREV=""

# ── STEP 0: Core window selection ─────────────────────────────────────────────
if [[ $FROM_STEP -le 0 ]]; then
  JOB0=$(sbatch --parsable --partition="$PART" \
    --output="$LOGS/step0_%j.out" \
    --error="$LOGS/step0_%j.err" \
    "$PIPELINE/step0_window_select_grit.sh")
  echo "step0=$JOB0" | tee -a "$MANIFEST"

  # Collect: copy coverage outputs into step0/ subfolder
  sbatch --parsable --partition="$PART" \
    --dependency=afterok:"$JOB0" \
    --job-name=collect_step0 --mem=2G --time=00:10:00 \
    --output="$LOGS/collect_step0_%j.out" \
    --wrap="cd $SCRATCH && \
            ls -t *.yaml *.csv *.md 2>/dev/null | head -20 | \
            xargs -I{} cp -n {} step0/ 2>/dev/null || true && \
            echo 'step0 outputs organised: '\$(ls step0/ | wc -l)' files'" \
    > /dev/null

  PREV=$JOB0
fi

# ── STEP 1: Split AIS by vessel ───────────────────────────────────────────────
if [[ $FROM_STEP -le 1 ]]; then
  DEP1=${PREV:+--dependency=afterok:$PREV}
  JOB1=$(sbatch --parsable --partition="$PART" ${DEP1:-} \
    --output="$LOGS/step1_%j.out" \
    --error="$LOGS/step1_%j.err" \
    "$PIPELINE/step1_split_navires.sh")
  echo "step1=$JOB1" | tee -a "$MANIFEST"

  # Collect: symlink the split folder + copy metadata CSV
  sbatch --parsable --partition="$PART" \
    --dependency=afterok:"$JOB1" \
    --job-name=collect_step1 --mem=1G --time=00:05:00 \
    --output="$LOGS/collect_step1_%j.out" \
    --wrap="ln -sfn ${HOME}/scratch/ais_split_${JOB1} $SCRATCH/step1/split_data && \
            cp ${HOME}/scratch/ais_split_${JOB1}/navires_metadata.csv \
               $SCRATCH/step1/ 2>/dev/null || true && \
            echo 'step1 symlinked'" \
    > /dev/null

  PREV=$JOB1
fi

# ── RELAY LAUNCHER ────────────────────────────────────────────────────────────
# This short job runs after step 1. It reads the actual vessel count from
# navires_metadata.csv, then submits steps 2–7 (and optionally CO2) with the
# correct --array size and proper dependency chain. All chaining happens inside
# the relay so it executes with the real JOB2 ID available.
DEP_RELAY=${PREV:+--dependency=afterok:$PREV}
JOB_RELAY=$(sbatch --parsable --partition="$PART" ${DEP_RELAY:-} \
  --job-name=pipeline_relay --mem=1G --time=00:10:00 \
  --output="$LOGS/relay_%j.out" \
  --error="$LOGS/relay_%j.err" \
  --wrap="
set -euo pipefail

FROM_STEP=${FROM_STEP}
CO2=${CO2}
PIPELINE=${PIPELINE}
SCRATCH=${SCRATCH}
LOGS=${LOGS}
PART=${PART}
MANIFEST=${MANIFEST}
JOB1='${JOB1}'
SPLIT_JOB_ID_ARG='${SPLIT_JOB_ID_ARG}'
RESULTS_DIR_ARG='${RESULTS_DIR_ARG}'

# ── Locate the split folder ──────────────────────────────────────────────────
if [[ \$FROM_STEP -le 3 ]]; then
  if [[ -n \"\$JOB1\" ]]; then
    SPLIT_DIR=${HOME}/scratch/ais_split_\${JOB1}
  elif [[ -n \"\$SPLIT_JOB_ID_ARG\" ]]; then
    JOB1=\$SPLIT_JOB_ID_ARG
    SPLIT_DIR=${HOME}/scratch/ais_split_\${JOB1}
  else
    echo \"ERROR: missing split job id. Use --split-job-id for --from-step 2 or 3.\"
    exit 1
  fi

  if [[ ! -d \"\$SPLIT_DIR\" ]]; then
    echo \"ERROR: split directory not found: \$SPLIT_DIR\"
    exit 1
  fi
  echo \"Relay: SPLIT_DIR=\$SPLIT_DIR  JOB1=\$JOB1\"
fi

PREV=\"\"
JOB2=\"\"

# ── STEP 2: Per-vessel track processing (dynamic array size) ──────────────────
if [[ \$FROM_STEP -le 2 ]]; then
  META=\"\$SPLIT_DIR/navires_metadata.csv\"
  if [[ ! -f \"\$META\" ]]; then
    echo \"ERROR: metadata file not found: \$META\"
    exit 1
  fi
  N=\$(tail -n +2 \"\$META\" | wc -l)
  if [[ \$N -le 0 ]]; then
    echo \"ERROR: metadata has no vessels: \$META\"
    exit 1
  fi
  echo \"Step 2: submitting array 1-\${N}%20\"

  JOB2=\$(sbatch --parsable --partition=\$PART \
    --job-name=step2_array \
    --array=1-\${N}%20 \
    --output=\$LOGS/step2_%A_%a.out \
    --error=\$LOGS/step2_%A_%a.err \
    --export=ALL,SPLIT_JOB_ID=\${JOB1} \
    \$PIPELINE/step2_process_array.sh)

  echo \"step2=\$JOB2\" | tee -a \$MANIFEST
  echo \$JOB2 > \$SCRATCH/step2/job_id.txt
  PREV=\$JOB2
fi

# ── Determine RESULTS_DIR for step 3 ─────────────────────────────────────────
# Step 2 writes *_clean.rds to ~/scratch/ais_results_<JOB2>/.
# JOB2 set  → dir will be created by step 2; skip validation (not yet populated).
# JOB2 empty → --from-step 3 restart; RESULTS_DIR_ARG must point to existing dir.
RESULTS_DIR=\"\"
if [[ \$FROM_STEP -le 3 ]]; then
  if [[ -n \"\$JOB2\" ]]; then
    # Step 2 was just submitted — its output dir doesn't exist yet, skip validation
    RESULTS_DIR=${HOME}/scratch/ais_results_\${JOB2}
  elif [[ -n \"\$RESULTS_DIR_ARG\" ]]; then
    # --from-step 3 restart: step 2 already completed, validate now
    RESULTS_DIR=\${RESULTS_DIR_ARG%/}
    if [[ ! -d \"\$RESULTS_DIR\" ]]; then
      echo \"ERROR: results directory not found: \$RESULTS_DIR\"
      exit 1
    fi
    CLEAN_COUNT=\$(find \"\$RESULTS_DIR\" -maxdepth 1 -type f -name '*_clean.rds' | wc -l)
    if [[ \$CLEAN_COUNT -le 0 ]]; then
      echo \"ERROR: no *_clean.rds found in: \$RESULTS_DIR\"
      exit 1
    fi
    echo \"Relay: RESULTS_DIR=\$RESULTS_DIR (\$CLEAN_COUNT clean files)\"
  else
    echo \"ERROR: missing results directory. Use --results-dir for --from-step 3.\"
    exit 1
  fi
  echo \"Relay: RESULTS_DIR=\$RESULTS_DIR\"
fi

# ── STEP 3: Merge + GMM + DBSCAN (256G) ───────────────────────────────────────
if [[ \$FROM_STEP -le 3 ]]; then
  DEP3=\${PREV:+--dependency=afterok:\$PREV}
  JOB3=\$(sbatch --parsable --partition=\$PART \${DEP3:-} \
    --output=\$LOGS/step3_%j.out \
    --error=\$LOGS/step3_%j.err \
    --export=ALL,SPLIT_JOB_ID=\${JOB1},RESULTS_DIR=\${RESULTS_DIR} \
    \$PIPELINE/step3_merge_grit_256G.sh)
  echo \"step3=\$JOB3\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB3 \
    --job-name=collect_step3 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_step3_%j.out \
    --wrap=\"cd \$SCRATCH && \
             ls -t AIS_data_core_preprocessed_V6_*.rds \
                   dragage_gridsearch_results_V6_*.rds 2>/dev/null | head -6 | \
             xargs -I{} cp -n {} step3/ 2>/dev/null || true && \
             echo 'step3 outputs organised'\" \
    > /dev/null

  PREV=\$JOB3
fi

# ── STEP 4: Add lithology ──────────────────────────────────────────────────────
if [[ \$FROM_STEP -le 4 ]]; then
  DEP4=\${PREV:+--dependency=afterok:\$PREV}
  JOB4=\$(sbatch --parsable --partition=\$PART \${DEP4:-} \
    --output=\$LOGS/step4_%j.out \
    --error=\$LOGS/step4_%j.err \
    \$PIPELINE/step4_add_lithology_vNext.sh)
  echo \"step4=\$JOB4\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB4 \
    --job-name=collect_step4 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_step4_%j.out \
    --wrap=\"cd \$SCRATCH && \
             ls -t AIS_with_lithology_*.rds AIS_with_lithology_*.parquet \
                2>/dev/null | head -4 | \
             xargs -I{} cp -n {} step4/ 2>/dev/null || true && \
             echo 'step4 outputs organised'\" \
    > /dev/null

  PREV=\$JOB4
fi

# ── STEP 5a: Generate tile grid ────────────────────────────────────────────────
if [[ \$FROM_STEP -le 5 ]]; then
  DEP5A=\${PREV:+--dependency=afterok:\$PREV}
  JOB5A=\$(sbatch --parsable --partition=\$PART \${DEP5A:-} \
    --job-name=step5a_maketiles \
    --mem=8G --cpus-per-task=2 --time=00:20:00 \
    --output=\$LOGS/step5a_%j.out \
    --error=\$LOGS/step5a_%j.err \
    --wrap=\"cd \$PIPELINE && Rscript step5_make_tiles.R\")
  echo \"step5a=\$JOB5A\" | tee -a \$MANIFEST

  # ── STEP 5b: SAR tile array ────────────────────────────────────────────────
  JOB5B=\$(sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB5A \
    --output=\$LOGS/step5b_%A_%a.out \
    --error=\$LOGS/step5b_%A_%a.err \
    \$PIPELINE/step5_tile_job.sh)
  echo \"step5b=\$JOB5B\" | tee -a \$MANIFEST

  # ── STEP 5c: Merge tiles → fi_grid ────────────────────────────────────────
  JOB5C=\$(sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB5B \
    --output=\$LOGS/step5c_%j.out \
    --error=\$LOGS/step5c_%j.err \
    \$PIPELINE/step5_merge_slurm_optimized.sh)
  echo \"step5c=\$JOB5C\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB5C \
    --job-name=collect_step5 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_step5_%j.out \
    --wrap=\"cd \$SCRATCH && \
             cp -n tiles_1000km.gpkg step5/ 2>/dev/null || true && \
             ls -t fi_grid_*.parquet fi_grid_*.rds fi_grid_*.tif 2>/dev/null | head -6 | \
               xargs -I{} cp -n {} step5/ 2>/dev/null || true && \
             ls -t sar_*.parquet 2>/dev/null | \
               xargs -I{} cp -n {} step5/ 2>/dev/null || true && \
             echo 'step5 outputs organised'\" \
    > /dev/null

  PREV=\$JOB5C
fi

# ── STEP 6: CRI calculation ────────────────────────────────────────────────────
if [[ \$FROM_STEP -le 6 ]]; then
  DEP6=\${PREV:+--dependency=afterok:\$PREV}
  JOB6=\$(sbatch --parsable --partition=\$PART \${DEP6:-} \
    --output=\$LOGS/step6_%j.out \
    --error=\$LOGS/step6_%j.err \
    \$PIPELINE/step6_calculate_cri_grit.sh)
  echo \"step6=\$JOB6\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB6 \
    --job-name=collect_step6 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_step6_%j.out \
    --wrap=\"cd \$SCRATCH && \
             ls -t cri_final_*.parquet cri_final_*.rds 2>/dev/null | head -4 | \
             xargs -I{} cp -n {} step6/ 2>/dev/null || true && \
             echo 'step6 outputs organised'\" \
    > /dev/null

  PREV=\$JOB6
fi

# ── STEP 7: Export Jdredge for OCIM ───────────────────────────────────────────
if [[ \$FROM_STEP -le 7 ]]; then
  DEP7=\${PREV:+--dependency=afterok:\$PREV}
  JOB7=\$(sbatch --parsable --partition=\$PART \${DEP7:-} \
    --output=\$LOGS/step7_%j.out \
    --error=\$LOGS/step7_%j.err \
    \$PIPELINE/step7_export_jtrawl_grit.sh)
  echo \"step7=\$JOB7\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB7 \
    --job-name=collect_step7 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_step7_%j.out \
    --wrap=\"cd \$SCRATCH && \
             ls -t jdredge_ocim2_48l_*.mat 2>/dev/null | head -4 | \
             xargs -I{} cp -n {} step7/ 2>/dev/null || true && \
             echo 'step7 outputs organised'\" \
    > /dev/null

  PREV=\$JOB7
fi

# ── CO2 MODEL (optional) ───────────────────────────────────────────────────────
if [[ \"\$CO2\" == true && \$FROM_STEP -le 8 ]]; then
  DEP_CO2=\${PREV:+--dependency=afterok:\$PREV}
  JOB_CO2=\$(sbatch --parsable --partition=\$PART \${DEP_CO2:-} \
    --output=\$LOGS/co2model_%j.out \
    --error=\$LOGS/co2model_%j.err \
    \$PIPELINE/co2model_batch_grit.sh)
  echo \"co2model=\$JOB_CO2\" | tee -a \$MANIFEST

  sbatch --parsable --partition=\$PART \
    --dependency=afterok:\$JOB_CO2 \
    --job-name=collect_co2 --mem=2G --time=00:10:00 \
    --output=\$LOGS/collect_co2_%j.out \
    --wrap=\"cd \$SCRATCH && \
             ls -t ocim_*.mat 2>/dev/null | head -6 | \
             xargs -I{} cp -n {} co2/ 2>/dev/null || true && \
             echo 'co2 outputs organised'\" \
    > /dev/null
fi

echo 'Relay done. All jobs submitted.'
echo \"Monitor with: squeue -u ${USER}\"
echo \"Manifest: \$MANIFEST\"
")
echo "relay=$JOB_RELAY" | tee -a "$MANIFEST"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Pipeline orchestrator submitted — Run ID: ${RUN_ID}"
echo "  From step:  ${FROM_STEP}"
echo "  CO2 model:  ${CO2}"
echo "  Manifest:   ${MANIFEST}"
echo "  Monitor:    squeue -u ${USER}"
echo "  Logs:       ${LOGS}/"
echo "============================================================"
