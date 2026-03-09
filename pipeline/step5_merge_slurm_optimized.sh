#!/bin/bash
# ============================================================================
# STEP 5 - FUSION TUILES SAR -> fi_grid (pipeline V6, cluster GRIT)
# ============================================================================

#SBATCH --job-name=step5_merge
#SBATCH --output=logs/step5_merge_%j.out
#SBATCH --error=logs/step5_merge_%j.err
#SBATCH --time=06:00:00
#SBATCH --mem=128G
#SBATCH --cpus-per-task=8
#SBATCH --nodelist=hpc-05.grit.ucsb.edu

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

# Repertoires
PIPELINE_DIR=~/ais-pipeline/pipeline_V6
LOGS_DIR=$PIPELINE_DIR/logs
mkdir -p $LOGS_DIR

cd $PIPELINE_DIR

# GeoTIFF active par defaut (mettre false pour desactiver)
export MAKE_TIFF="${MAKE_TIFF:-TRUE}"
echo "Generation GeoTIFF: $MAKE_TIFF"

# Verification tuiles SAR
SAR_COUNT=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | wc -l)
echo "Tuiles SAR trouvees: $SAR_COUNT"

if [ "$SAR_COUNT" -eq 0 ]; then
  echo "ERREUR: Aucune tuile SAR trouvee dans ~/scratch/output_V6/"
  exit 1
fi

# Verification fichiers requis
for f in ~/scratch/configuration/fi_parameters_with_freshness.yaml \
         ~/scratch/output_V6/tiles_1000km.gpkg; do
  if [ ! -f "$f" ]; then
    echo "ERREUR: Fichier requis manquant: $f"
    exit 1
  fi
done

# Verification Longhurst
LONGHURST_FOUND=0
for d in ~/scratch/configuration/longhurst_v4_2010/Longhurst_world_v4_2010.shp \
         ~/scratch/configuration/longhurst/longhurst.shp \
         ~/scratch/configuration/longhurst.gpkg; do
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
if [ ! -f "$PIPELINE_DIR/constants.R" ]; then
  echo "ERREUR: constants.R manquant dans $PIPELINE_DIR"
  exit 1
fi

SCRIPT_PATH="$PIPELINE_DIR/step5_merge_tiles_optimized.R"
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "ERREUR: Script R non trouve: $SCRIPT_PATH"
  exit 1
fi
echo "Script R: $SCRIPT_PATH"

# Fix: libproj.so.22 not in default path; symlink ~/lib/libproj.so.22 -> libproj.so.25
export LD_LIBRARY_PATH=$HOME/lib:${LD_LIBRARY_PATH:-}

# Lancement
/usr/bin/Rscript "$SCRIPT_PATH" 2>&1

exit_code=$?

if [ $exit_code -eq 0 ]; then
  echo ""
  echo "Step 5 merge termine avec succes: $(date)"
  echo "Fichiers generes:"
  ls -lh ~/scratch/output_V6/fi_grid_*.parquet 2>/dev/null || echo "  (aucun parquet)"
  ls -lh ~/scratch/output_V6/fi_grid_*.rds 2>/dev/null || echo "  (aucun rds)"
  ls -lh ~/scratch/output_V6/fi_grid_*.tif 2>/dev/null || echo "  (aucun tif)"
else
  echo "ERREUR Step 5 merge: code $exit_code"
  exit $exit_code
fi

echo "=== ETAPE 5 FUSION TERMINEE ==="
