#!/bin/bash

#SBATCH --job-name=test_qs_step1
#SBATCH --account=def-wailung
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --output=test_qs_step1_%j.out

echo "🚀 === TEST QS PACKAGE + ÉTAPE 1 ==="
echo "Timestamp: $(date)"
echo "Node: $(hostname)"

# Chargement modules R
echo "📦 Chargement modules R..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/   # CHEMIN FIXE selon README

echo "📁 Répertoire de travail: $(pwd)"
echo "🔧 R_LIBS configuré: $R_LIBS"

# Vérification fichiers
echo "✅ Vérification fichiers:"
ls -la ~/R_scripts/pipeline_V6/step1_split_navires.R
ls -la ~/benjamin2.csv

echo "🔍 Contenu répertoire actuel:"
ls -la ~/R_scripts/pipeline_V6/

# Test ID simulé
TEST_ID="TEST_QS_$(date +%Y%m%d_%H%M%S)"
echo "📦 Test ID simulé: $TEST_ID"

echo ""
echo "✅ Lancement script de fractionnement avec QS..."
echo "=================================================="

# Test R avec packages DÉJÀ INSTALLÉS (selon README)
cat > test_qs_simple.R << 'EOF'
#!/usr/bin/env Rscript
cat("🔧 === TEST R SESSION QS ===\n")
cat("Répertoire R:", getwd(), "\n")
cat("Configuration R_LIBS:", Sys.getenv("R_LIBS"), "\n")

# Forcer le bon chemin des librairies (selon README_BELUGA.md)
.libPaths("~/.local/R/4.2.1/")
cat("Chemin libPaths configuré:", paste(.libPaths(), collapse=" "), "\n")

# Test fichiers
if (file.exists("~/R_scripts/pipeline_V6/step1_split_navires.R")) {
  cat("✅ Fichier step1_split_navires.R trouvé\n")
} else {
  cat("❌ Fichier step1_split_navires.R manquant\n")
  quit(status=1)
}

if (file.exists("~/benjamin2.csv")) {
  cat("✅ Fichier benjamin2.csv trouvé\n")
} else {
  cat("❌ Fichier benjamin2.csv manquant\n")
  quit(status=1)
}

# Vérification packages DÉJÀ INSTALLÉS (selon README : 218+ packages)
cat("📦 Vérification packages installés dans ~/.local/R/4.2.1/:\n")
installed_pkgs <- installed.packages(lib.loc = "~/.local/R/4.2.1/")[,"Package"]
cat("  Total packages:", length(installed_pkgs), "\n")

# Packages critiques selon README_BELUGA.md
key_packages <- c("data.table", "lubridate", "solitude", "mclust", "dbscan", "depmixS4", "yaml", "zoo")
all_present <- TRUE
for (pkg in key_packages) {
  if (pkg %in% installed_pkgs) {
    cat("  ✅", pkg, "trouvé\n")
  } else {
    cat("  ❌", pkg, "MANQUANT\n")
    all_present <- FALSE
  }
}

if (!all_present) {
  cat("❌ Packages critiques manquants ! Vérifiez l'installation selon README\n")
  quit(status=1)
}

# Test chargement packages critiques
cat("📚 Test chargement packages...\n")
tryCatch({
  suppressPackageStartupMessages(library(data.table, lib.loc = "~/.local/R/4.2.1/"))
  cat("✅ data.table OK\n")
}, error = function(e) {
  cat("❌ data.table ERREUR:", e$message, "\n")
  quit(status=1)
})

tryCatch({
  suppressPackageStartupMessages(library(lubridate, lib.loc = "~/.local/R/4.2.1/"))
  cat("✅ lubridate OK\n")
}, error = function(e) {
  cat("❌ lubridate ERREUR:", e$message, "\n")
})

# Test qs ou fallback RDS
cat("🔧 Test qs (ou fallback RDS)...\n")
use_qs <- FALSE
if ("qs" %in% installed_pkgs) {
  tryCatch({
    suppressPackageStartupMessages(library(qs, lib.loc = "~/.local/R/4.2.1/"))
    
    # Test simple qs
    test_data <- data.table::data.table(x = 1:10, y = letters[1:10])
    temp_file <- tempfile(fileext = ".qs")
    qs::qsave(test_data, temp_file)
    test_read <- qs::qread(temp_file)
    if (identical(test_data, test_read)) {
      cat("✅ qs fonctionne parfaitement\n")
      use_qs <- TRUE
    }
    unlink(temp_file)
  }, error = function(e) {
    cat("❌ qs ERREUR:", e$message, "\n")
  })
}

if (!use_qs) {
  cat("🔄 Test fallback RDS...\n")
  tryCatch({
    test_data <- data.table::data.table(x = 1:10, y = letters[1:10])
    temp_file <- tempfile(fileext = ".rds")
    saveRDS(test_data, temp_file, compress = "xz")
    test_read <- readRDS(temp_file)
    if (identical(test_data, test_read)) {
      cat("✅ RDS fallback fonctionne\n")
    }
    unlink(temp_file)
  }, error = function(e) {
    cat("❌ RDS fallback ERREUR:", e$message, "\n")
  })
}

cat("🚀 Configuration validée - prêt pour step1\n")
EOF

Rscript test_qs_simple.R

# Si le test qs passe, on lance le script principal
if [ $? -eq 0 ]; then
    echo "✅ Test qs réussi, lancement du script principal..."
    
    # Configuration environnement pour test limité
    export AIS_INPUT_PATTERN="~/benjamin2.csv"
    export AIS_OUTPUT_DIR="~/scratch/ais_split_$TEST_ID"
    export SLURM_JOB_ID="$TEST_ID"
    
    # Lancement avec timeout de sécurité
    timeout 10m Rscript ~/R_scripts/pipeline_V6/step1_split_navires.R
    
    echo ""
    echo "📊 RÉSUMÉ TEST:"
    if [ -d "~/scratch/ais_split_$TEST_ID" ]; then
        echo "Fichiers créés dans ~/scratch/ais_split_$TEST_ID/:"
        ls -la ~/scratch/ais_split_$TEST_ID/
    else
        echo "❌ Dossier de sortie non créé"
    fi
else
    echo "❌ Test qs échoué, abandon"
fi

echo ""
echo "✅ Test avec qs terminé: $(date)" 