#!/bin/bash
# Fetch results from the GRIT cluster
# Usage: bash deploy/fetch_results.sh [subdirectory]
# Examples:
#   bash deploy/fetch_results.sh                    # Fetch everything
#   bash deploy/fetch_results.sh Resultats          # Fetch Resultats/
#   bash deploy/fetch_results.sh output_V6          # Fetch output_V6/

set -e

# Configuration
REMOTE_HOST="grit"
REMOTE_PATH="~/ais-pipeline"
SSH_CONFIG="$HOME/.ssh/config_grit"

if [ -z "$1" ]; then
  echo "📥 Récupération de tous les résultats depuis GRIT..."

  # Fetch each results directory
  for dir in "Resultats" "output_V6" "outputs_step6"; do
    if ssh -F "$SSH_CONFIG" "$REMOTE_HOST" "[ -d $REMOTE_PATH/$dir ]" 2>/dev/null; then
      echo "   Récupération de $dir/..."
      rsync -avz --progress \
        -e "ssh -F $SSH_CONFIG" \
        "$REMOTE_HOST:$REMOTE_PATH/$dir/" \
        "./$dir/"
    fi
  done
else
  SUBDIR="$1"
  echo "📥 Récupération depuis GRIT : $SUBDIR"

  rsync -avz --progress \
    -e "ssh -F $SSH_CONFIG" \
    "$REMOTE_HOST:$REMOTE_PATH/$SUBDIR/" \
    "./$SUBDIR/"
fi

echo " Téléchargement terminé !"
echo "📍 Fichiers locaux mis à jour"
