#!/bin/bash
###############################################################################
#  SLURM – STEP 6 : Calcul du Carbone Reminéralise (Cri)
#  Cluster-agnostic version
###############################################################################
#SBATCH --job-name=step6_cri
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=08:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

echo "=== STEP 6 : CALCUL DE CRI (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# R setup
export R_LIBS_USER=~/R/library

# Repertoire par defaut: racine du depot (parent du dossier pipeline/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Repertoires utiles (override possible via env vars)
PIPELINE_DIR="${PIPELINE_DIR:-$DEFAULT_PIPELINE_DIR}"
LOGS_DIR="${LOGS_DIR:-$PIPELINE_DIR/logs}"
SCRATCH_DIR="${SCRATCH_DIR:-~/scratch}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRATCH_DIR/output_V6}"
CONFIG_DIR="${CONFIG_DIR:-$SCRATCH_DIR/configuration}"

mkdir -p "$LOGS_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$SCRATCH_DIR/tmp_terra"

cd "$PIPELINE_DIR" || { echo "❌ Repertoire manquant: $PIPELINE_DIR"; exit 2; }

echo "✅ Repertoire courant: $(pwd)"
echo "✅ R library path: $R_LIBS_USER"
echo ""
LIMITATIONS_DOC="${LIMITATIONS_DOC:-$PIPELINE_DIR/documentation/LIMITATIONS.md}"
echo "METHODO WARNING: known limitations apply to CRI estimates."
if [ -f "$LIMITATIONS_DOC" ]; then
    echo "See: $LIMITATIONS_DOC"
else
    echo "Limitations document not found: $LIMITATIONS_DOC"
fi

# Pre-flight: verifier les rasters carbone Atwood
CARBON_DIR="${CARBON_DIR:-$CONFIG_DIR/atwood_carbon_full}"
if [ ! -d "$CARBON_DIR" ] || [ -z "$(ls "$CARBON_DIR"/*.tif 2>/dev/null)" ]; then
    echo "❌ Rasters carbone manquants dans $CARBON_DIR"
    echo "   Lancez d'abord le script d'upload Step 6 adapte a votre cluster."
    exit 1
fi
echo "✅ Rasters carbone: $(ls "$CARBON_DIR"/*.tif | wc -l) fichiers TIF"

# Pre-flight: verifier les fichiers f_i (output de Step 5)
FI_FILES=$(find "$OUTPUT_DIR/" -name "fi_grid_*.parquet" -o -name "fi_grid_*.rds" 2>/dev/null | head -5)
if [ -z "$FI_FILES" ]; then
    echo "❌ Aucun fichier f_i trouve dans $OUTPUT_DIR/"
    echo "   Lancez d'abord Step 5"
    exit 1
fi
echo "✅ Fichiers f_i trouves:"
echo "$FI_FILES"

# Pre-flight: verifier constants.R (plusieurs emplacements possibles)
CONSTANTS_PATH=""
for cand in "constants.R" "pipeline/constants.R"; do
    if [ -f "$cand" ]; then
        CONSTANTS_PATH="$cand"
        break
    fi
done
if [ -z "$CONSTANTS_PATH" ]; then
    echo "❌ constants.R manquant dans $(pwd) (et pipeline/constants.R absent)"
    exit 1
fi
echo "✅ constants.R present: $CONSTANTS_PATH"

echo ""
echo "🔄 Lancement script Step 6 ..."

SCRIPT_PATH=""
for cand in \
    "step6_calculate_cri_corrected.R" \
    "pipeline/step6_calculate_cri.R"; do
    if [ -f "$cand" ]; then
        SCRIPT_PATH="$cand"
        break
    fi
done

if [ -z "$SCRIPT_PATH" ]; then
    echo "❌ Aucun script Step 6 trouve."
    echo "Candidats testes:"
    echo "  - step6_calculate_cri_corrected.R"
    echo "  - pipeline/step6_calculate_cri.R"
    exit 1
fi

echo "Script selectionne: $SCRIPT_PATH"
Rscript --vanilla "$SCRIPT_PATH"

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
    echo "✅ STEP 6 termine avec succes : $(date)"
    echo "📄 Fichiers generes :"
    ls -lh "$OUTPUT_DIR"/cri_final_* 2>/dev/null || echo "   ⚠️ Aucun fichier cri_final trouve"
else
    echo "❌ STEP 6 a echoue (code $exit_code)"
    exit $exit_code
fi
