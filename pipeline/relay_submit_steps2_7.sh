#!/usr/bin/env bash
###############################################################################
#  RELAY JOB — submit steps 2-7 after step 1 completes
#
#  This script is submitted as a SLURM job (--dependency=afterok:STEP1_JOB).
#  It runs on the cluster, reads navires_metadata.csv to determine the vessel
#  count, then submits steps 2-7 with proper afterok dependency chains.
#
#  Environment variables expected (forwarded from orchestrator via --export):
#    PIPELINE_DIR        — path to pipeline/ directory on cluster
#    SCRATCH_DIR         — path to scratch/
#    CONFIG_DIR          — path to configuration/
#    OUTPUT_DIR          — path to output directory
#    AIS_INPUT_FILE      — path to AIS CSV
#    SPLIT_JOB_ID        — SLURM job ID of step 1 (for locating ais_split_*)
#    SLURM_PARTITION     — partition to use for submitted jobs
#    STEP2_ARRAY_CONCURRENCY — max concurrent step2 tasks (default: 20)
###############################################################################
#SBATCH --job-name=relay_submit
#SBATCH --mem=512M
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00

set -euo pipefail

echo "=== RELAY: submit steps 2-7 (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Start: $(date)"

PIPELINE_DIR="${PIPELINE_DIR:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/pipeline}"
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"
CONFIG_DIR="${CONFIG_DIR:-${SCRATCH_DIR}/configuration}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRATCH_DIR}/output_V6}"
AIS_INPUT_FILE="${AIS_INPUT_FILE:-${SCRATCH_DIR}/AIS_data/ais_filtered.csv}"
SPLIT_JOB_ID="${SPLIT_JOB_ID:?SPLIT_JOB_ID must be set}"
SLURM_PARTITION="${SLURM_PARTITION:-emlab_nodes}"
CONCURRENCY="${STEP2_ARRAY_CONCURRENCY:-20}"
LOG_DIR="$(dirname "${PIPELINE_DIR}")/logs"
mkdir -p "${LOG_DIR}"

COMMON_EXPORTS="PIPELINE_DIR=${PIPELINE_DIR},SCRATCH_DIR=${SCRATCH_DIR},CONFIG_DIR=${CONFIG_DIR},OUTPUT_DIR=${OUTPUT_DIR},AIS_INPUT_FILE=${AIS_INPUT_FILE}"

# ---------------------------------------------------------------------------
# Determine step2 array size from navires_metadata.csv
# ---------------------------------------------------------------------------
SPLIT_DIR="${SCRATCH_DIR}/ais_split_${SPLIT_JOB_ID}"
META="${SPLIT_DIR}/navires_metadata.csv"

if [[ ! -f "${META}" ]]; then
  echo "[ERROR] Metadata not found: ${META}" >&2
  exit 1
fi

COUNT=$(tail -n +2 "${META}" | wc -l | tr -d ' ')
if ! [[ "${COUNT}" =~ ^[0-9]+$ ]] || (( COUNT <= 0 )); then
  echo "[ERROR] Invalid vessel count from metadata: ${COUNT}" >&2
  exit 1
fi

ARRAY_SPEC="1-${COUNT}%${CONCURRENCY}"
RESULTS_DIR="${SCRATCH_DIR}/ais_results_${SPLIT_JOB_ID}"

echo "[INFO] Vessel count: ${COUNT}"
echo "[INFO] Array spec:   ${ARRAY_SPEC}"
echo "[INFO] Results dir:  ${RESULTS_DIR}"

submit() {
  sbatch --parsable --partition="${SLURM_PARTITION}" \
    --output="${LOG_DIR}/%x_%j.out" \
    --error="${LOG_DIR}/%x_%j.err" \
    "$@"
}

# ---------------------------------------------------------------------------
# Step 2 — per-vessel array
# ---------------------------------------------------------------------------
JOB2=$(submit \
  --array "${ARRAY_SPEC}" \
  --export "ALL,${COMMON_EXPORTS},SPLIT_JOB_ID=${SPLIT_JOB_ID}" \
  "${PIPELINE_DIR}/step2/step2_process_array.sh")
echo "step2=${JOB2}"

# ---------------------------------------------------------------------------
# Step 3 — merge
# ---------------------------------------------------------------------------
JOB3=$(submit \
  --dependency "afterok:${JOB2}" \
  --export "ALL,${COMMON_EXPORTS},SPLIT_JOB_ID=${SPLIT_JOB_ID},RESULTS_DIR=${RESULTS_DIR}" \
  "${PIPELINE_DIR}/step3/step3_merge.sh")
echo "step3=${JOB3}"

# ---------------------------------------------------------------------------
# Step 4 — lithology
# ---------------------------------------------------------------------------
JOB4=$(submit \
  --dependency "afterok:${JOB3}" \
  --export "ALL,${COMMON_EXPORTS}" \
  "${PIPELINE_DIR}/step4/step4_add_lithology.sh")
echo "step4=${JOB4}"

# ---------------------------------------------------------------------------
# Step 5a — make tiles
# ---------------------------------------------------------------------------
JOB5A=$(submit \
  --dependency "afterok:${JOB4}" \
  --job-name step5_make_tiles \
  --mem=8G --cpus-per-task=2 --time=00:30:00 \
  --export "ALL,${COMMON_EXPORTS}" \
  --wrap "Rscript ${PIPELINE_DIR}/step5/step5_make_tiles.R")
echo "step5a=${JOB5A}"

# ---------------------------------------------------------------------------
# Step 5b — tile workers
# ---------------------------------------------------------------------------
JOB5B=$(submit \
  --dependency "afterok:${JOB5A}" \
  --export "ALL,${COMMON_EXPORTS}" \
  "${PIPELINE_DIR}/step5/step5_tile_job.sh")
echo "step5b=${JOB5B}"

# ---------------------------------------------------------------------------
# Step 5c — merge tiles
# ---------------------------------------------------------------------------
JOB5C=$(submit \
  --dependency "afterok:${JOB5B}" \
  --export "ALL,${COMMON_EXPORTS}" \
  "${PIPELINE_DIR}/step5/step5_merge_slurm.sh")
echo "step5c=${JOB5C}"

# ---------------------------------------------------------------------------
# Step 6 — CRI
# ---------------------------------------------------------------------------
JOB6=$(submit \
  --dependency "afterok:${JOB5C}" \
  --export "ALL,${COMMON_EXPORTS}" \
  "${PIPELINE_DIR}/step6/step6_calculate_cri.sh")
echo "step6=${JOB6}"

# ---------------------------------------------------------------------------
# Step 7 — export Jdredge
# ---------------------------------------------------------------------------
JOB7=$(submit \
  --dependency "afterok:${JOB6}" \
  --export "ALL,${COMMON_EXPORTS}" \
  "${PIPELINE_DIR}/step7/step7_export_jdredge.sh")
echo "step7=${JOB7}"

echo "=== RELAY complete: $(date) ==="
echo "All steps 2-7 submitted with dependency chains."
