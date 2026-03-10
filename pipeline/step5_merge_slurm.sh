#!/bin/bash
# ============================================================================
# STEP 5 - FUSION TUILES SAR -> fi_grid (pipeline V6, cluster-agnostic)
# ============================================================================

#SBATCH --job-name=step5_merge
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --time=06:00:00
#SBATCH --mem=128G
#SBATCH --cpus-per-task=8

# R packages installes dans ~/R/library
export R_LIBS_USER=~/R/library

echo "=== ETAPE 5: FUSION DES TUILES SAR ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Configuration memoire conservative
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

# Repertoire par defaut: racine du depot (parent du dossier pipeline/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Repertoires (override possible via env vars)
PIPELINE_DIR="${PIPELINE_DIR:-$DEFAULT_PIPELINE_DIR}"
SCRATCH_DIR="${SCRATCH_DIR:-~/scratch}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRATCH_DIR/output_V6}"
CONFIG_DIR="${CONFIG_DIR:-$SCRATCH_DIR/configuration}"
LOGS_DIR="${LOGS_DIR:-$PIPELINE_DIR/logs}"
mkdir -p "$LOGS_DIR"

cd "$PIPELINE_DIR" || { echo "ERREUR: Repertoire pipeline introuvable: $PIPELINE_DIR"; exit 2; }

# Runtime transparency notice (non-blocking)
LIMITATIONS_DOC="${LIMITATIONS_DOC:-$PIPELINE_DIR/documentation/LIMITATIONS.md}"
echo ""
echo "METHODO WARNING: known study limitations apply to fi outputs."
if [ -f "$LIMITATIONS_DOC" ]; then
  echo "See: $LIMITATIONS_DOC"
else
  echo "Limitations document not found: $LIMITATIONS_DOC"
fi

# GeoTIFF active par defaut (mettre false pour desactiver)
export MAKE_TIFF="${MAKE_TIFF:-TRUE}"
echo "Generation GeoTIFF: $MAKE_TIFF"

# Verification tuiles SAR
SAR_COUNT=$(ls "$OUTPUT_DIR"/sar_*.parquet 2>/dev/null | wc -l)
echo "Tuiles SAR trouvees: $SAR_COUNT"

if [ "$SAR_COUNT" -eq 0 ]; then
  echo "ERREUR: Aucune tuile SAR trouvee dans $OUTPUT_DIR/"
  exit 1
fi

# Verification fichiers requis
for f in "$CONFIG_DIR/fi_parameters_with_freshness.yaml" \
         "$OUTPUT_DIR/tiles_1000km.gpkg"; do
  if [ ! -f "$f" ]; then
    echo "ERREUR: Fichier requis manquant: $f"
    exit 1
  fi
done

# Verification Longhurst
LONGHURST_FOUND=0
for d in "$CONFIG_DIR/longhurst_v4_2010/Longhurst_world_v4_2010.shp" \
         "$CONFIG_DIR/longhurst/longhurst.shp" \
         "$CONFIG_DIR/longhurst.gpkg"; do
  if [ -f "$d" ]; then
    echo "Longhurst trouve: $d"
    LONGHURST_FOUND=1
    break
  fi
done
if [ "$LONGHURST_FOUND" -eq 0 ]; then
  echo "ATTENTION: Aucun shapefile Longhurst trouve localement (tentative WFS au runtime)"
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
  echo "ERREUR: constants.R manquant (candidats testes: $PIPELINE_DIR/constants.R ; $PIPELINE_DIR/pipeline/constants.R)"
  exit 1
fi
echo "constants.R: $CONSTANTS_PATH"

SCRIPT_PATH=""
for cand in \
  "$PIPELINE_DIR/step5_merge_tiles_optimized.R" \
  "$PIPELINE_DIR/pipeline_V6/step5_merge_tiles_optimized.R" \
  "$PIPELINE_DIR/pipeline/step5_merge_tiles.R"; do
  if [ -f "$cand" ]; then
    SCRIPT_PATH="$cand"
    break
  fi
done
if [ -z "$SCRIPT_PATH" ]; then
  echo "ERREUR: Aucun script merge Step 5 trouve."
  echo "Candidats testes:"
  echo "  - $PIPELINE_DIR/step5_merge_tiles_optimized.R"
  echo "  - $PIPELINE_DIR/pipeline_V6/step5_merge_tiles_optimized.R"
  echo "  - $PIPELINE_DIR/pipeline/step5_merge_tiles.R"
  exit 1
fi
echo "Script R selectionne: $SCRIPT_PATH"

# Lancement
/usr/bin/Rscript "$SCRIPT_PATH" 2>&1

exit_code=$?

# Deplacer les logs vers LOGS_DIR (si generes dans le repertoire courant)
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" ]; then
  mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out" "$LOGS_DIR"/
fi
if [ -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" ]; then
  mv "${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err" "$LOGS_DIR"/
fi

if [ $exit_code -eq 0 ]; then
  echo ""
  echo "Step 5 merge termine avec succes: $(date)"
  echo "Fichiers generes:"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.parquet 2>/dev/null || echo "  (aucun parquet)"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.rds 2>/dev/null || echo "  (aucun rds)"
  ls -lh "$OUTPUT_DIR"/fi_grid_*.tif 2>/dev/null || echo "  (aucun tif)"
else
  echo "ERREUR Step 5 merge: code $exit_code"
  exit $exit_code
fi

echo "=== ETAPE 5 FUSION TERMINEE ==="
