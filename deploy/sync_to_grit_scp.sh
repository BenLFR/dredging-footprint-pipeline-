#!/bin/bash
# Synchronise le code local vers le cluster GRIT (version SCP pour Windows)
# Usage: bash deploy/sync_to_grit_scp.sh

set -e

# Configuration
REMOTE_HOST="grit-bastion"
REMOTE_USER="${REMOTE_USER:-<cluster_user>}"
REMOTE_PATH="$HOME/ais-pipeline"
SSH_CONFIG="$HOME/.ssh/config_grit"

echo "Synchronisation vers GRIT (via SCP)..."

# Creer le repertoire distant si necessaire
ssh -F "$SSH_CONFIG" "$REMOTE_HOST" "mkdir -p $REMOTE_PATH/{scripts_principaux,configuration,submission,pipeline_V6,batch_windows,logs} $REMOTE_PATH/configuration/{land_mask,lithology}"

echo "Synchronisation des scripts principaux..."
scp -F "$SSH_CONFIG" -r scripts_principaux/*.R "$REMOTE_HOST:$REMOTE_PATH/scripts_principaux/" 2>/dev/null || echo "  Aucun fichier .R dans scripts_principaux/"

echo "Synchronisation de la configuration..."
scp -F "$SSH_CONFIG" -r configuration/*.{yaml,yml,ini} "$REMOTE_HOST:$REMOTE_PATH/configuration/" 2>/dev/null || echo "  Aucun fichier config"
scp -F "$SSH_CONFIG" -r configuration/*.R "$REMOTE_HOST:$REMOTE_PATH/configuration/" 2>/dev/null || echo "  Aucun fichier .R dans configuration/"

echo "Synchronisation land mask..."
scp -F "$SSH_CONFIG" configuration/land_mask/land_polygons.* "$REMOTE_HOST:$REMOTE_PATH/configuration/land_mask/" 2>/dev/null || echo "  Aucun land mask"

echo "Synchronisation lithology config..."
scp -F "$SSH_CONFIG" configuration/lithology/*.csv "$REMOTE_HOST:$REMOTE_PATH/configuration/lithology/" 2>/dev/null || echo "  Aucun fichier lithology"

echo "Synchronisation des scripts de submission..."
scp -F "$SSH_CONFIG" submission/*.sh "$REMOTE_HOST:$REMOTE_PATH/submission/" 2>/dev/null || echo "  Aucun fichier .sh dans submission/"

echo "Synchronisation du pipeline V6 (Step 0-6)..."
scp -F "$SSH_CONFIG" pipeline_V6/pipeline_V6/step*.R "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/" 2>/dev/null || echo "  Aucun fichier step*.R"
scp -F "$SSH_CONFIG" pipeline_V6/pipeline_V6/step*.sh "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/" 2>/dev/null || echo "  Aucun fichier step*.sh"
scp -F "$SSH_CONFIG" pipeline_V6/pipeline_V6/*.yaml "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/" 2>/dev/null || echo "  Aucun fichier yaml"

echo "Synchronisation scripts Python (prefetch HubOcean)..."
scp -F "$SSH_CONFIG" pipeline_V6/pipeline_V6/*.py "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/" 2>/dev/null || echo "  Aucun fichier .py"

echo "Synchronisation install_packages..."
scp -F "$SSH_CONFIG" pipeline_V6/install_packages_step3.slurm.sh "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/" 2>/dev/null || echo "  Aucun fichier install_packages"

echo "Synchronisation des scripts batch (Step 0)..."
scp -F "$SSH_CONFIG" batch_windows/step0_*.R "$REMOTE_HOST:$REMOTE_PATH/batch_windows/" 2>/dev/null || echo "  Aucun fichier step0 batch"

echo "Synchronisation terminee !"
echo "Fichiers sur GRIT : $REMOTE_HOST:$REMOTE_PATH/"
