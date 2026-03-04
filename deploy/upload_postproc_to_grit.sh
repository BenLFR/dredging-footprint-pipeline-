#!/bin/bash
# Upload OCIM post-processing pipeline to GRIT
# Usage: bash deploy/upload_postproc_to_grit.sh
#
# Robust single-auth upload: bundle files locally, stream once via SSH,
# unpack remotely, then move to final destinations.

set -euo pipefail

SSH_CONFIG="$HOME/.ssh/config_grit"
REMOTE="grit"
REMOTE_HOME="/home/bloe"
REMOTE_PIPELINE_DIR="$REMOTE_HOME/ais-pipeline/pipeline_V6"
REMOTE_ROOT_DIR="$REMOTE_HOME/ais-pipeline"

echo "=========================================="
echo "UPLOAD OCIM POSTPROC TO GRIT (1 AUTH)"
echo "=========================================="
echo ""

# Check local files exist
for f in pipeline_V6/postproc_atwood_style.py \
         pipeline_V6/requirements_postproc_atwood.txt \
         postproc_atwood_style.sbatch; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f not found (run from project root)"
        exit 1
    fi
done

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/pipeline_V6"
cp pipeline_V6/postproc_atwood_style.py "$STAGING/pipeline_V6/"
cp pipeline_V6/requirements_postproc_atwood.txt "$STAGING/pipeline_V6/"
cp postproc_atwood_style.sbatch "$STAGING/"

echo "Local fingerprints:"
sha256sum pipeline_V6/postproc_atwood_style.py
sha256sum pipeline_V6/requirements_postproc_atwood.txt
sha256sum postproc_atwood_style.sbatch
echo ""

echo "Streaming bundle to GRIT (single password + 2FA prompt)..."
tar -C "$STAGING" -czf - . | ssh -F "$SSH_CONFIG" "$REMOTE" "
    set -euo pipefail
    mkdir -p '$REMOTE_PIPELINE_DIR' '$REMOTE_ROOT_DIR' '$REMOTE_HOME/logs' '$REMOTE_HOME/scratch/output_V6'

    TMP_DIR=\"/tmp/postproc_upload_\$\$\"
    mkdir -p \"\$TMP_DIR\"
    tar -xzf - -C \"\$TMP_DIR\"

    mv \"\$TMP_DIR/pipeline_V6/postproc_atwood_style.py\" '$REMOTE_PIPELINE_DIR/'
    mv \"\$TMP_DIR/pipeline_V6/requirements_postproc_atwood.txt\" '$REMOTE_PIPELINE_DIR/'
    mv \"\$TMP_DIR/postproc_atwood_style.sbatch\" '$REMOTE_ROOT_DIR/'

    rm -rf \"\$TMP_DIR\"

    echo 'Verification on GRIT:'
    ls -lh '$REMOTE_PIPELINE_DIR/postproc_atwood_style.py'
    ls -lh '$REMOTE_PIPELINE_DIR/requirements_postproc_atwood.txt'
    ls -lh '$REMOTE_ROOT_DIR/postproc_atwood_style.sbatch'

    echo ''
    echo 'Remote fingerprints:'
    sha256sum '$REMOTE_PIPELINE_DIR/postproc_atwood_style.py'
    sha256sum '$REMOTE_PIPELINE_DIR/requirements_postproc_atwood.txt'
    sha256sum '$REMOTE_ROOT_DIR/postproc_atwood_style.sbatch'

    echo ''
    echo 'Content checks:'
    grep -n '_safe_to_netcdf' '$REMOTE_PIPELINE_DIR/postproc_atwood_style.py' || true
    grep -n 'command -v module' '$REMOTE_ROOT_DIR/postproc_atwood_style.sbatch' || true
"

echo ""
echo "=========================================="
echo "Done. To run on GRIT:"
echo "  ssh -F ~/.ssh/config_grit grit"
echo "  cd ~/ais-pipeline"
echo "  sbatch postproc_atwood_style.sbatch"
echo "  squeue -u bloe"
echo "=========================================="
