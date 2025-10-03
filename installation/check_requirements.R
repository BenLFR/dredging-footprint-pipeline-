# ==============================================================================
# Script de vérification et installation des prérequis
# ==============================================================================

cat("Vérification des packages requis...\n")

# Liste des packages nécessaires
required_packages <- c(
  "data.table",
  "lubridate", 
  "mclust",
  "ranger",
  "caret",
  "pROC",
  "ggplot2",
  "marmap",
  "raster",
  "sf",
  "dbscan",
  "dplyr",
  "zoo",
  "depmixS4",
  "pbapply",
  "geosphere",
  "matrixStats",
  "mixsmsn"  # optionnel
)

# Fonction pour installer les packages manquants
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("Installation de", pkg, "...\n")
    install.packages(pkg, dependencies = TRUE)
    library(pkg, character.only = TRUE)
    cat("✓", pkg, "installé avec succès\n")
  } else {
    cat("✓", pkg, "déjà installé\n")
  }
}

# Installation des packages
for (pkg in required_packages) {
  tryCatch({
    install_if_missing(pkg)
  }, error = function(e) {
    if (pkg == "mixsmsn") {
      cat("⚠ mixsmsn optionnel - continuera avec mclust\n")
    } else {
      cat("✗ Erreur avec", pkg, ":", e$message, "\n")
    }
  })
}

cat("\nVérification terminée !\n")
cat("Vous pouvez maintenant exécuter vos scripts principaux.\n") 