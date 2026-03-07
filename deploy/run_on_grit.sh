#!/bin/bash
# Execute an R script on the GRIT cluster
# Usage: bash deploy/run_on_grit.sh "scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"

set -e

# Configuration
REMOTE_HOST="grit"
REMOTE_PATH="~/ais-pipeline"
SSH_CONFIG="$HOME/.ssh/config_grit"

if [ -z "$1" ]; then
  echo " Usage: $0 <script_path>"
  echo "   Exemple: $0 scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"
  exit 1
fi

SCRIPT_PATH="$1"
echo " Exécution sur GRIT : $SCRIPT_PATH"

# Sync first
echo "📤 Synchronisation du code..."
bash deploy/sync_to_grit.sh

# Run the script
echo "⚙  Exécution de $SCRIPT_PATH..."
ssh -F "$SSH_CONFIG" "$REMOTE_HOST" "cd $REMOTE_PATH && Rscript $SCRIPT_PATH"

echo " Exécution terminée !"
