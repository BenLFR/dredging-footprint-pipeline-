#!/bin/bash
###############################################################################
#  SLURM – STEP 6 : Calcul du Carbone Reminéralise (Cri)
#  Version GRIT-adapted
###############################################################################
#SBATCH --job-name=step6_cri
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=08:00:00
#SBATCH --chdir=/home/bloe/ais-pipeline/pipeline_V6
#SBATCH --output=/home/bloe/logs/step6_cri_%j.out
#SBATCH --error=/home/bloe/logs/step6_cri_%j.err
#SBATCH --exclude=hpc-08.grit.ucsb.edu

echo "=== STEP 6 : CALCUL DE CRI (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

# R setup (GRIT: no module system on compute nodes, R in PATH directly)
export R_LIBS_USER=~/R/library

# Repertoires utiles (override possible via env vars)
PIPELINE_DIR="${PIPELINE_DIR:-~/ais-pipeline/pipeline_V6}"
LOGS_DIR="${LOGS_DIR:-$PIPELINE_DIR/logs}"
SCRATCH_DIR="${SCRATCH_DIR:-~/scratch}"

mkdir -p "$LOGS_DIR"
mkdir -p "$SCRATCH_DIR/output_V6"
mkdir -p "$SCRATCH_DIR/tmp_terra"

cd "$PIPELINE_DIR" || { echo "❌ Repertoire manquant: $PIPELINE_DIR"; exit 2; }

echo "✅ Repertoire courant: $(pwd)"
echo "✅ R library path: $R_LIBS_USER"

# Pre-flight: verifier les rasters carbone Atwood
CARBON_DIR="${CARBON_DIR:-$SCRATCH_DIR/configuration/atwood_carbon_full}"
if [ ! -d "$CARBON_DIR" ] || [ -z "$(ls "$CARBON_DIR"/*.tif 2>/dev/null)" ]; then
    echo "❌ Rasters carbone manquants dans $CARBON_DIR"
    echo "   Lancez d'abord: bash deploy/upload_step6_to_grit.sh"
    exit 1
fi
echo "✅ Rasters carbone: $(ls "$CARBON_DIR"/*.tif | wc -l) fichiers TIF"

# Pre-flight: verifier les fichiers f_i (output de Step 5)
FI_FILES=$(find "$SCRATCH_DIR/output_V6/" -name "fi_grid_*.parquet" -o -name "fi_grid_*.rds" 2>/dev/null | head -5)
if [ -z "$FI_FILES" ]; then
    echo "❌ Aucun fichier f_i trouve dans $SCRATCH_DIR/output_V6/"
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
echo "🔄 Lancement script Step 6 (baseline GRIT prioritaire)..."

SCRIPT_PATH=""
for cand in \
    "step6_calculate_cri_corrected.R" \
    "pipeline/step6_calculate_cri.R" \
    "ORGANISATION_BELUGA/pipeline_study/step6_cri/step6_calculate_cri_corrected.R"; do
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
    echo "  - ORGANISATION_BELUGA/pipeline_study/step6_cri/step6_calculate_cri_corrected.R"
    exit 1
fi

echo "Script selectionne: $SCRIPT_PATH"
Rscript --vanilla "$SCRIPT_PATH"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ STEP 6 termine avec succes : $(date)"
    echo "📄 Fichiers generes :"
    ls -lh "$SCRATCH_DIR/output_V6"/cri_final_* 2>/dev/null || echo "   ⚠️ Aucun fichier cri_final trouve"
else
    echo "❌ STEP 6 a echoue (code $exit_code)"
    exit $exit_code
fi
