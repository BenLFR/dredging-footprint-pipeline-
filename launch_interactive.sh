#!/bin/bash

echo "🚀 LANCEMENT AUTOMATIQUE EN MODE INTERACTIF"
echo "=========================================="

# 1. Se connecter à Beluga
ssh benl@beluga.alliancecan.ca << 'BELUGA_COMMANDS'

echo "📡 Connecté à Beluga"

# 2. Aller au bon répertoire  
cd ~/R_scripts
echo "📁 Répertoire: $(pwd)"

# 3. Charger R
module load r/4.5.0
echo "✅ Module R chargé"

# 4. Installer tous les packages manquants
echo "🔧 Installation des packages manquants..."
Rscript ~/install_all_packages.R

# 5. Demander une session interactive
echo "🎯 Demande de session interactive..."
salloc --time=4:00:00 --cpus-per-task=8 --mem=24G --account=def-wailung << 'INTERACTIVE_SESSION'

echo "🎉 Session interactive obtenue !"
echo "Node: $SLURMD_NODENAME"
echo "Job ID: $SLURM_JOB_ID"

# Charger R dans la session interactive
module load r/4.5.0

# Aller au bon répertoire
cd ~/R_scripts

# Lancer le BON script (NO_SF)
echo "🔥 Lancement du script NO_SF en mode interactif..."
Rscript "Entrainement modele V5 tri années cluster_NO_SF.R"

echo "🏁 Script terminé !"

INTERACTIVE_SESSION

BELUGA_COMMANDS

echo "✅ Processus terminé" 