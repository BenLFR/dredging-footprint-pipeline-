#!/bin/bash
# Synchronise le code local vers le cluster GRIT
# Usage: bash deploy/sync_to_grit.sh

set -e

# Configuration
REMOTE_HOST="grit"
REMOTE_PATH="~/ais-pipeline"
SSH_CONFIG="$HOME/.ssh/config_grit"

echo "🚀 Synchronisation vers GRIT..."

# Créer le répertoire distant si nécessaire
ssh -F "$SSH_CONFIG" "$REMOTE_HOST" "mkdir -p $REMOTE_PATH"

# Synchroniser les dossiers principaux
echo "📤 Synchronisation des scripts principaux..."
rsync -avz --progress \
  -e "ssh -F $SSH_CONFIG" \
  --exclude='*.Rproj' \
  --exclude='.Rproj.user/' \
  --exclude='*.Rhistory' \
  --exclude='~$*' \
  --exclude='*.tmp' \
  scripts_principaux/ \
  "$REMOTE_HOST:$REMOTE_PATH/scripts_principaux/"

echo "📤 Synchronisation de la configuration..."
rsync -avz --progress \
  -e "ssh -F $SSH_CONFIG" \
  --exclude='*.Rproj' \
  configuration/ \
  "$REMOTE_HOST:$REMOTE_PATH/configuration/"

echo "📤 Synchronisation des scripts de submission..."
rsync -avz --progress \
  -e "ssh -F $SSH_CONFIG" \
  --exclude='*.bat' \
  submission/ \
  "$REMOTE_HOST:$REMOTE_PATH/submission/"

echo "📤 Synchronisation du pipeline V6..."
rsync -avz --progress \
  -e "ssh -F $SSH_CONFIG" \
  --exclude='*.Rproj' \
  --exclude='.Rproj.user/' \
  --include='*/' \
  --include='step*.R' \
  --include='step*.sh' \
  --include='*.yaml' \
  --include='constants.R' \
  --exclude='*' \
  pipeline_V6/pipeline_V6/ \
  "$REMOTE_HOST:$REMOTE_PATH/pipeline_V6/"

echo "📤 Synchronisation des scripts batch (Step 0)..."
rsync -avz --progress \
  -e "ssh -F $SSH_CONFIG" \
  --include='step0_*.R' \
  --exclude='*' \
  batch_windows/ \
  "$REMOTE_HOST:$REMOTE_PATH/batch_windows/"

echo "✅ Synchronisation terminée !"
echo "📍 Fichiers sur GRIT : $REMOTE_HOST:$REMOTE_PATH/"
