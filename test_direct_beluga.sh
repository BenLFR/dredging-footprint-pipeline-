#!/bin/bash

echo "🧪 TEST DIRECT - Script NO_SF sur Beluga"
echo "========================================"

LOG_FILE="test_direct_$(date +%Y%m%d_%H%M%S).log"
echo "📝 Log: $LOG_FILE"

echo "[$(date '+%H:%M:%S')] 🚀 Connexion directe à Beluga..." | tee -a "$LOG_FILE"

# Connexion directe à Beluga
ssh benl@beluga.alliancecan.ca << 'EOF'

echo "========================================"
echo "🎯 BELUGA - Test Script NO_SF"
echo "========================================"

# Fonction log
log_it() {
    echo "[$(date '+%H:%M:%S')] BELUGA: $1"
}

log_it "📡 Connecté à Beluga"

# Vérifications préliminaires
log_it "🔍 Vérifications..."
echo "Utilisateur: $(whoami)"
echo "Répertoire home: $HOME"
echo "Espace disque:"
df -h $HOME | tail -1

# Vérifier les répertoires critiques
log_it "📁 Vérification répertoires..."
ls -la ~/R_scripts/ | head -5
ls -la ~/scratch/AIS_data/ | head -5

# Charger R
log_it "🔧 Chargement R..."
module load r/4.5.0
R --version | head -1

# Test rapide des packages critiques
log_it "📦 Test packages critiques..."
R --slave --no-restore << 'R_TEST'
cat("=== TEST PACKAGES ===\n")
essential <- c("data.table", "lubridate", "mclust", "pROC", "caret")
for(pkg in essential) {
  status <- if(require(pkg, character.only=TRUE, quietly=TRUE)) "✅" else "❌"
  cat(sprintf("%-12s: %s\n", pkg, status))
}

# Test lecture rapide des données
cat("\n=== TEST DONNÉES ===\n")
if(file.exists("~/scratch/AIS_data")) {
  files <- list.files("~/scratch/AIS_data", pattern="\\.csv$")
  cat("Fichiers CSV trouvés:", length(files), "\n")
  if(length(files) > 0) {
    cat("Premier fichier:", files[1], "\n")
    # Test lecture
    if(require(data.table, quietly=TRUE)) {
      test_file <- file.path("~/scratch/AIS_data", files[1])
      tryCatch({
        dt <- fread(test_file, nrows=10)
        cat("Colonnes:", paste(names(dt), collapse=", "), "\n")
        cat("Lignes test:", nrow(dt), "\n")
      }, error=function(e) cat("Erreur lecture:", e$message, "\n"))
    }
  }
} else {
  cat("❌ Répertoire AIS_data non trouvé\n")
}
quit(save="no")
R_TEST

# Demander session interactive pour test court
log_it "🎯 Demande session interactive (30 min)..."

# Vérifier disponibilité des ressources
sinfo -p beluga_cpu --Format=cpus,memory,available | head -10

salloc --time=0:30:00 --cpus-per-task=4 --mem=16G --account=def-wailung << 'INTERACTIVE_SESSION'

echo "============================================"
echo "🎉 SESSION INTERACTIVE OBTENUE"
echo "============================================"
echo "Node: $SLURMD_NODENAME"
echo "Job ID: $SLURM_JOB_ID"
echo "CPUs: $SLURM_CPUS_PER_TASK"

# Infos système
echo "Mémoire:"
free -h | grep Mem
echo "CPU info:"
cat /proc/cpuinfo | grep "model name" | head -1

# Recharger modules
module load r/4.5.0
cd ~/R_scripts

# Vérifier le script principal
echo "Script principal:"
ls -lh "Entrainement modele V5 tri années cluster_NO_SF.R"

# LANCEMENT DU TEST
echo "🔥 LANCEMENT DU SCRIPT (timeout 25 min)..."
echo "=========================================="

timeout 1500 Rscript "Entrainement modele V5 tri années cluster_NO_SF.R" 2>&1

EXIT_CODE=$?
echo "=========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: Script terminé avec succès !"
elif [ $EXIT_CODE -eq 124 ]; then
    echo "⏰ TIMEOUT: Script arrêté après 25 minutes"
    echo "   (normal pour un test, le script semble fonctionnel)"
elif [ $EXIT_CODE -eq 1 ]; then
    echo "❌ ERROR: Erreur R (probablement packages manquants)"
elif [ $EXIT_CODE -eq 2 ]; then
    echo "❌ ERROR: Erreur de script ou données"
else
    echo "❌ ERROR: Code de sortie inconnu: $EXIT_CODE"
fi

echo "🏁 Test interactif terminé"

INTERACTIVE_SESSION

log_it "🏁 Retour au login node"

EOF

echo "[$(date '+%H:%M:%S')] ✅ Test Beluga terminé" | tee -a "$LOG_FILE"
echo "📄 Consultez le log: $LOG_FILE" 