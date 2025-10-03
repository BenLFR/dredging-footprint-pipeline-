#!/bin/bash

echo "🧪 TEST INTERACTIF - Script NO_SF sur Beluga"
echo "============================================"

# Configuration
SCRIPT_NAME="Entrainement modele V5 tri années cluster_NO_SF.R"
LOG_FILE="test_interactif_$(date +%Y%m%d_%H%M%S).log"

echo "📝 Log: $LOG_FILE"

# Fonction de log
log_msg() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_msg "🚀 Début du test interactif"

# Vérifier la connectivité
log_msg "📡 Test de connexion à Beluga..."
if ! ping -c 1 beluga.alliancecan.ca &> /dev/null; then
    log_msg "❌ Beluga non accessible"
    exit 1
fi
log_msg "✅ Beluga accessible"

# Se connecter et exécuter
ssh benl@beluga.alliancecan.ca << 'EOF'

# Fonction log côté Beluga
log_beluga() {
    echo "[$(date '+%H:%M:%S')] BELUGA: $1"
}

log_beluga "📡 Connecté à Beluga avec succès"

# Vérifier les répertoires
log_beluga "📁 Vérification des répertoires..."
if [ ! -d "~/R_scripts" ]; then
    log_beluga "❌ Répertoire ~/R_scripts manquant"
    exit 1
fi

if [ ! -d "~/scratch/AIS_data" ]; then
    log_beluga "❌ Répertoire ~/scratch/AIS_data manquant"
    exit 1
fi

cd ~/R_scripts
log_beluga "📁 Répertoire actuel: $(pwd)"

# Vérifier le script
if [ ! -f "Entrainement modele V5 tri années cluster_NO_SF.R" ]; then
    log_beluga "❌ Script principal manquant"
    exit 1
fi
log_beluga "✅ Script principal trouvé"

# Charger R
log_beluga "🔧 Chargement du module R..."
module load r/4.5.0
if [ $? -ne 0 ]; then
    log_beluga "❌ Échec chargement module R"
    exit 1
fi
log_beluga "✅ Module R 4.5.0 chargé"

# Vérifier R
log_beluga "🧪 Test R..."
R --version | head -1
if [ $? -ne 0 ]; then
    log_beluga "❌ R non fonctionnel"
    exit 1
fi

# Installation des packages (rapide)
log_beluga "📦 Installation des packages critiques..."
R --slave << 'R_INSTALL'
options(repos = c(CRAN = "https://cran.rstudio.com/"))
essential_packages <- c("data.table", "lubridate", "mclust", "pROC", "caret")
for(pkg in essential_packages) {
  if(!require(pkg, character.only=TRUE, quietly=TRUE)) {
    cat("Installation:", pkg, "\n")
    install.packages(pkg, dependencies=TRUE)
  }
}
cat("✅ Packages essentiels vérifiés\n")
R_INSTALL

# Demander session interactive avec ressources réduites pour test
log_beluga "🎯 Demande de session interactive (test)..."
salloc --time=1:00:00 --cpus-per-task=4 --mem=16G --account=def-wailung << 'INTERACTIVE_TEST'

echo "🎉 Session interactive obtenue !"
echo "Node: $SLURMD_NODENAME"
echo "Job ID: $SLURM_JOB_ID"
echo "Mémoire disponible: $(free -h | grep Mem)"

# Recharger R dans la session
module load r/4.5.0

# Aller au script
cd ~/R_scripts

# Test rapide avec timeout
echo "🔥 LANCEMENT TEST (avec timeout 30 min)..."
timeout 1800 Rscript "Entrainement modele V5 tri années cluster_NO_SF.R" 2>&1

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Script terminé avec succès !"
elif [ $EXIT_CODE -eq 124 ]; then
    echo "⏰ Script arrêté par timeout (30 min)"
else
    echo "❌ Script échoué (code: $EXIT_CODE)"
fi

echo "🏁 Test interactif terminé"

INTERACTIVE_TEST

EOF

log_msg "🏁 Test interactif Beluga terminé" 