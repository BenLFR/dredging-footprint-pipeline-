#!/bin/bash
#SBATCH --account=def-wailung_cpu
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --job-name=fix_r_packages
#SBATCH --output=logs/fix_r_packages_%j.out
#SBATCH --error=logs/fix_r_packages_%j.err

echo "🔧 NETTOYAGE ET RÉINSTALLATION PACKAGES R"
echo "========================================"
echo "Job ID: $SLURM_JOB_ID"
echo "Début: $(date)"

# Chargement modules R 4.2.1
echo "📦 Chargement R 4.2.1..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Vérification version
echo "Version R:"
R --version | head -1

# Création répertoire logs
mkdir -p logs

# Nettoyage complet library R
echo "🧹 Nettoyage library R existante..."
rm -rf ~/R/library/*
mkdir -p ~/R/library

# Configuration .Rprofile
echo "⚙️  Configuration .Rprofile..."
cat > ~/.Rprofile << 'EOF'
# Configuration R pour Beluga
.libPaths("~/R/library")
options(repos = c(CRAN = "https://cloud.r-project.org"))
options(timeout = 300)
cat("✅ R configuré avec library:", .libPaths()[1], "\n")
EOF

# Installation packages essentiels un par un
echo "📦 Installation packages essentiels..."

R --slave -e '
cat("=== INSTALLATION PACKAGES R 4.2.1 ===\n")
.libPaths("~/R/library")
options(repos = c(CRAN = "https://cloud.r-project.org"))

packages <- c("data.table", "lubridate", "mclust", "pROC", "dplyr", "caret", "ggplot2")

for (pkg in packages) {
  cat("Installation", pkg, "...\n")
  tryCatch({
    install.packages(pkg, lib = "~/R/library", dependencies = TRUE)
    library(pkg, character.only = TRUE, lib.loc = "~/R/library")
    cat("✅", pkg, "installé et testé\n")
  }, error = function(e) {
    cat("❌ Erreur", pkg, ":", e$message, "\n")
  })
}

cat("\n=== VÉRIFICATION FINALE ===\n")
installed <- installed.packages(lib.loc = "~/R/library")
cat("Packages installés:", nrow(installed), "\n")
print(installed[, c("Package", "Version")])
'

echo "✅ Installation terminée: $(date)"
echo "📋 Vérification finale..."

# Test rapide chargement
R --slave -e '
.libPaths("~/R/library")
tryCatch({
  library(data.table)
  library(mclust)
  library(pROC)
  cat("🎉 PACKAGES R FONCTIONNELS !\n")
}, error = function(e) {
  cat("❌ Problème persistant:", e$message, "\n")
})
'

echo "🏁 Script terminé: $(date)" 