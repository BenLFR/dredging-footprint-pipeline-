#!/bin/bash
# Exécute un script R sur le cluster GRIT
# Usage: bash deploy/run_on_grit.sh "scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"

set -e

# Configuration
REMOTE_HOST="grit"
REMOTE_PATH="~/ais-pipeline"
SSH_CONFIG="$HOME/.ssh/config_grit"

if [ -z "$1" ]; then
  echo "❌ Usage: $0 <script_path>"
  echo "   Exemple: $0 scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"
  exit 1
fi

SCRIPT_PATH="$1"
echo "🚀 Exécution sur GRIT : $SCRIPT_PATH"

# Synchroniser d'abord
echo "📤 Synchronisation du code..."
bash deploy/sync_to_grit.sh

# Exécuter le script
echo "⚙️  Exécution de $SCRIPT_PATH..."
ssh -F "$SSH_CONFIG" "$REMOTE_HOST" "cd $REMOTE_PATH && Rscript $SCRIPT_PATH"

echo "✅ Exécution terminée !"
