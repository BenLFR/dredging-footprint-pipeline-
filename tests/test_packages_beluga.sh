#!/bin/bash

echo "🔍 RECHERCHE ET TEST AUTOMATIQUE DES PACKAGES R"
echo "=============================================="

# Trouver le module R disponible
echo "📦 Recherche du module R..."
module avail r/ 2>&1 | head -10

# Essayer différentes versions de R
for r_version in "r/4.4.0" "r/4.3.1" "r/4.3.0" "r/4.2.2" "r/4.1.3"; do
    echo "🧪 Test du module $r_version..."
    if module load $r_version 2>/dev/null; then
        echo "✅ Module $r_version trouvé et chargé"
        R_MODULE=$r_version
        break
    fi
done

if [ -z "$R_MODULE" ]; then
    echo "❌ Aucun module R trouvé, utilisation de R par défaut"
    R_MODULE=""
fi

# Créer un script R de test des packages
cat > /tmp/test_packages.R << 'EOF'
# Test automatique des packages essentiels
packages_needed <- c("data.table", "lubridate", "mclust", "pROC", "caret", 
                     "ggplot2", "dbscan", "dplyr", "zoo", "depmixS4", 
                     "pbapply", "matrixStats", "geosphere")

missing_packages <- c()
cat("🧪 TEST DES PACKAGES ESSENTIELS\n")
cat("===============================\n")

for(pkg in packages_needed) {
  cat(pkg, ": ")
  if(require(pkg, character.only=TRUE, quietly=TRUE)) {
    cat("OK\n")
  } else {
    cat("MANQUANT\n")
    missing_packages <- c(missing_packages, pkg)
  }
}

if(length(missing_packages) > 0) {
  cat("\n❌ PACKAGES MANQUANTS:", paste(missing_packages, collapse=", "), "\n")
  quit(status=1)
} else {
  cat("\n✅ TOUS LES PACKAGES SONT INSTALLÉS !\n")
  quit(status=0)
}
EOF

# Tester les packages
echo "🧪 Test des packages..."
if [ ! -z "$R_MODULE" ]; then
    module load $R_MODULE
fi

if Rscript /tmp/test_packages.R; then
    echo "✅ Tous les packages sont installés !"
    PACKAGES_OK=true
else
    echo "❌ Des packages manquent, installation nécessaire"
    PACKAGES_OK=false
fi

# Installation si nécessaire
if [ "$PACKAGES_OK" = false ]; then
    echo "📦 INSTALLATION DES PACKAGES MANQUANTS..."
    cd ~/Beluga
    Rscript installation/install_packages_beluga_fixed.R
    
    # Re-test après installation
    echo "🔄 Re-test après installation..."
    if Rscript /tmp/test_packages.R; then
        echo "✅ Installation réussie !"
        PACKAGES_OK=true
    else
        echo "❌ Problème d'installation persistant"
        exit 1
    fi
fi

# Nettoyage
rm -f /tmp/test_packages.R

# Lancement du job si tout est OK
if [ "$PACKAGES_OK" = true ]; then
    echo "🚀 LANCEMENT DU JOB..."
    cd ~/Beluga
    sbatch submission/submit_beluga_NO_SF.sh
    echo "✅ Job soumis ! Vérifiez avec: squeue -u $USER"
else
    echo "❌ Impossible de lancer le job - packages manquants"
    exit 1
fi

echo "🏁 SCRIPT TERMINÉ" 