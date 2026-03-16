#!/bin/bash
# ============================================================================
# STEP 5 - FUSION TILES SAR -> fi_grid (pipeline V6, cluster-agnostic)
# ============================================================================

#SBATCH --job-name=step5_merge
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --time=06:00:00
#SBATCH --mem=128G
#SBATCH --cpus-per-task=8

# R packages installes in ~/R/library
export R_LIBS_USER=~/R/library
export LD_LIBRARY_PATH=$HOME/lib:${LD_LIBRARY_PATH:-}

echo "=== STEP 5: FUSION THE TILES SAR ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Start: $(date)"

# Configuration memory conservative
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Directory par default: racine of depot (parent of directory pipeline/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Directories (override possible via env vars)
PIPELINE_DIR="${PIPELINE_DIR:-$DEFAULT_PIPELINE_DIR}"
SCRATCH_DIR="${SCRATCH_DIR:-~/scratch}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRATCH_DIR/output_V6}"
CONFIG_DIR="${CONFIG_DIR:-$SCRATCH_DIR/configuration}"
LOGS_DIR="${LOGS_DIR:-$PIPELINE_DIR/logs}"
mkdir -p "$LOGS_DIR"

cd "$PIPELINE_DIR" || { echo "ERROR: Directory pipeline introuvable: $PIPELINE_DIR"; exit 2; }

# Runtime transparency notice (not-blocking)
LIMITATIONS_DOC="${LIMITATIONS_DOC:-$PIPELINE_DIR/documentation/LIMITATIONS.md}"
echo ""
echo "METHODO WARNING: known study limitations apply to fi outputs."
if [ -f "$LIMITATIONS_DOC" ]; then
  echo "See: $LIMITATIONS_DOC"
else
  echo "Limitations document not found: $LIMITATIONS_DOC"
fi

# GeoTIFF active par default (mettre false for desactiver)
export MAKE_TIFF="${MAKE_TIFF:-TRUE}"
echo "Generation GeoTIFF: $MAKE_TIFF"

# Verification tiles SAR
SAR_COUNT=$(ls "$OUTPUT_DIR"/sar_*.parquet 2>/dev/null | wc -l)
echo "Tiles SAR found: $SAR_COUNT"

if [ "$SAR_COUNT" -eq 0 ]; then
  echo "ERROR: No tile SAR found in $OUTPUT_DIR/"
  exit 1
fi

# Verification files required
for f in "$CONFIG_DIR/fi_parameters_with_freshness.yaml" \
         "$OUTPUT_DIR/tiles_1000km.gpkg"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: File required missing: $f"
    exit 1
  fi
done

# Verification Longhurst
LONGHURST_FOUND=0
for d in "$CONFIG_DIR/longhurst_v4_2010/Longhurst_world_v4_2010.shp" \
         "$CONFIG_DIR/longhurst/longhurst.shp" \
         "$CONFIG_DIR/longhurst.gpkg"; do
  if [ -f "$d" ]; then
    echo "Longhurst found: $d"
    LONGHURST_FOUND=1
    break
  fi
done
if [ "$LONGHURST_FOUND" -eq 0 ]; then
  echo "ATTENTION: No shapefile Longhurst found localement (tentative WFS to runtime)"
fi

# Verification constants.R
CONSTANTS_PATH=""
for cand in "$PIPELINE_DIR/constants.R" "$PIPELINE_DIR/pipeline/constants.R"; do
  if [ -f "$cand" ]; then
    CONSTANTS_PATH="$cand"
    break
  fi
done
if [ -z "$CONSTANTS_PATH" ]; then
  echo "ERROR: constants.R missing (candidates testes: $PIPELINE_DIR/constants.R ; $PIPELINE_DIR/pipeline/constants.R)"
  exit 1
fi
echo "constants.R: $CONSTANTS_PATH"

SCRIPT_PATH=""
for cand in \
  "$SCRIPT_DIR/step5_merge_tiles.R" \
  "$PIPELINE_DIR/step5/step5_merge_tiles.R" \
  "$PIPELINE_DIR/step5_merge_tiles_optimized.R"; do
  if [ -f "$cand" ]; then
    SCRIPT_PATH="$cand"
    break
  fi
done
if [ -z "$SCRIPT_PATH" ]; then
  echo "ERROR: No script merge Step 5 found."
  echo "candidates testes:"
  echo " - $SCRIPT_DIR/step5_merge_tiles.R"
  echo " - $PIPELINE_DIR/step5/step5_merge_tiles.R"
  echo " - $PIPELINE_DIR/step5_merge_tiles_optimized.R"
  exit 1
fi
echo "Script R selectionne: $SCRIPT_PATH"

# Run
/usr/bin/Rscript "$SCRIPT_PATH" 2>&1

exit_code=$?

# Deplacer the logs to LOGS_DIR (si generes in the directory courant)
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" ]; then
  mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" "$LOGS_DIR"/
fi
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" ]; then
  mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" "$LOGS_DIR"/
fi

if [ $exit_code -eq 0 ]; then
  echo ""
  echo "Step 5 merge completed successfully: $(date)"
  echo "Files generes:"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.parquet 2>/dev/null || echo " (no parquet)"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.rds 2>/dev/null || echo " (no rds)"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.tif 2>/dev/null || echo " (no tif)"
else
  echo "ERROR Step 5 merge: code $exit_code"
  exit $exit_code
fi

echo "=== STEP 5 FUSION COMPLETED ==="
