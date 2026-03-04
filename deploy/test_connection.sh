#!/bin/bash
# Test de connexion au cluster GRIT
# Usage: bash deploy/test_connection.sh

set -e

SSH_CONFIG="$HOME/.ssh/config_grit"

echo "🔍 Test de connexion GRIT..."
echo ""

echo "1️⃣  Test connexion bastion (ssh.grit.ucsb.edu)..."
if ssh -F "$SSH_CONFIG" grit-bastion "echo 'Bastion OK'" 2>/dev/null; then
  echo "   ✅ Bastion accessible"
else
  echo "   ❌ Bastion inaccessible"
  exit 1
fi

echo ""
echo "2️⃣  Test connexion HPC (hpc.grit.ucsb.edu via ProxyJump)..."
if ssh -F "$SSH_CONFIG" grit "echo 'HPC OK'" 2>/dev/null; then
  echo "   ✅ HPC accessible"
else
  echo "   ❌ HPC inaccessible"
  exit 1
fi

echo ""
echo "3️⃣  Informations système GRIT..."
ssh -F "$SSH_CONFIG" grit "hostname && whoami && pwd"

echo ""
echo "4️⃣  Version R sur GRIT..."
ssh -F "$SSH_CONFIG" grit "Rscript --version | head -1"

echo ""
echo "✅ Tous les tests ont réussi !"
echo "🚀 Vous pouvez maintenant utiliser les scripts de déploiement."
