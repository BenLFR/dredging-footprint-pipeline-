#!/bin/bash
# Upload Step 6 files to GRIT cluster
# Usage: bash deploy/upload_step6_to_grit.sh
#
# Uses TWO connections:
#  1) scp: uploads all 7 files to a staging dir (with progress bars)
#  2) ssh: moves files to final locations + verification
#
# That's 2x password+2FA, but you get visible progress for the ~3.8 GB transfer.

set -e

SSH_CONFIG="$HOME/.ssh/config_grit"
REMOTE="grit"

echo "=========================================="
echo "📤 UPLOAD STEP 6 FILES TO GRIT"
echo "=========================================="
echo ""

# Collect all files into a flat staging directory
STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

echo "📦 Preparation des fichiers..."

CARBON_DIR="installation/atwood_carbon"
if [ ! -d "$CARBON_DIR" ]; then
    echo "   ❌ Repertoire local $CARBON_DIR introuvable"
    echo "   Lancez ce script depuis la racine du projet"
    exit 1
fi
cp "$CARBON_DIR"/*.tif "$STAGING/"
cp step6_calculate_cri_corrected.R "$STAGING/"
cp constants.R "$STAGING/"
cp scripts_cluster/step6_calculate_cri_grit.sh "$STAGING/"

echo "   $(ls "$STAGING" | wc -l) fichiers ($(du -sh "$STAGING" | cut -f1))"
echo ""

# --- Connection 1: scp all files to remote staging (with progress bars) ------
echo "🔑 CONNEXION 1/2 : Upload des fichiers (avec barres de progression)"
echo ""

ssh -F "$SSH_CONFIG" "$REMOTE" "mkdir -p /tmp/step6_staging"

echo ""
echo "📤 Transfert de 3.8 GB... (barres de progression par fichier)"
echo ""

scp -F "$SSH_CONFIG" "$STAGING"/* "$REMOTE:/tmp/step6_staging/"

echo ""
echo "   ✅ Upload termine"
echo ""

# --- Connection 2: move files to final locations + verify --------------------
echo "🔑 CONNEXION 2/2 : Mise en place + verification"
echo ""

ssh -F "$SSH_CONFIG" "$REMOTE" '
  set -e

  mkdir -p ~/scratch/configuration/atwood_carbon_full \
           ~/scratch/output_V6 \
           ~/scratch/tmp_terra \
           ~/ais-pipeline/pipeline_V6/logs

  mv /tmp/step6_staging/*.tif ~/scratch/configuration/atwood_carbon_full/
  mv /tmp/step6_staging/*.R /tmp/step6_staging/*.sh ~/ais-pipeline/pipeline_V6/
  rm -rf /tmp/step6_staging

  echo "=========================================="
  echo "🔍 VERIFICATION (sur GRIT)"
  echo "=========================================="
  echo ""
  echo "Rasters carbone:"
  ls -lh ~/scratch/configuration/atwood_carbon_full/*.tif 2>/dev/null || echo "  ❌ Aucun TIF"
  echo ""
  echo "Scripts pipeline_V6:"
  ls -lh ~/ais-pipeline/pipeline_V6/step6_calculate_cri_corrected.R 2>/dev/null || echo "  ❌ step6 R manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/step6_calculate_cri_grit.sh 2>/dev/null || echo "  ❌ SLURM manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/constants.R 2>/dev/null || echo "  ❌ constants.R manquant"
'

echo ""
echo "=========================================="
echo "✅ Upload termine !"
echo ""
echo "Pour lancer Step 6 sur GRIT :"
echo "  ssh -F ~/.ssh/config_grit grit"
echo "  cd ~/ais-pipeline/pipeline_V6"
echo "  sbatch step6_calculate_cri_grit.sh"
echo "=========================================="
