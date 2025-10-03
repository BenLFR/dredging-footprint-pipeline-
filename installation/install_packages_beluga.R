# ==============================================================================
# Installation des packages R nécessaires pour Beluga
# ==============================================================================

cat("Installation des packages R pour l'analyse AIS...\n")

# Configuration pour l'installation sur Beluga
options(repos = c(CRAN = "https://cloud.r-project.org/"))

# Liste des packages essentiels
essential_packages <- c(
  "data.table",
  "lubridate", 
  "mclust",
  "ranger",
  "caret",
  "pROC",
  "ggplot2",
  "sf",
  "dbscan",
  "dplyr",
  "zoo",
  "depmixS4",
  "pbapply",
  "geosphere",
  "matrixStats"
)

# Packages optionnels
optional_packages <- c(
  "marmap",
  "raster",
  "mixsmsn"
)

# Fonction d'installation sécurisée
install_safe <- function(pkg) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("Installation de", pkg, "...\n")
    tryCatch({
      install.packages(pkg, dependencies = TRUE, quiet = FALSE)
      library(pkg, character.only = TRUE)
      cat("✓", pkg, "installé avec succès\n")
      return(TRUE)
    }, error = function(e) {
      cat("✗ Erreur avec", pkg, ":", e$message, "\n")
      return(FALSE)
    })
  } else {
    cat("✓", pkg, "déjà installé\n")
    return(TRUE)
  }
}

# Installation des packages essentiels
cat("\n=== INSTALLATION DES PACKAGES ESSENTIELS ===\n")
essential_success <- sapply(essential_packages, install_safe)

# Installation des packages optionnels
cat("\n=== INSTALLATION DES PACKAGES OPTIONNELS ===\n")
optional_success <- sapply(optional_packages, function(pkg) {
  tryCatch({
    install_safe(pkg)
  }, error = function(e) {
    cat("⚠ Package optionnel", pkg, "non installé:", e$message, "\n")
    return(FALSE)
  })
})

# Résumé
cat("\n=== RÉSUMÉ DE L'INSTALLATION ===\n")
cat("Packages essentiels installés:", sum(essential_success), "/", length(essential_packages), "\n")
cat("Packages optionnels installés:", sum(optional_success), "/", length(optional_packages), "\n")

if (all(essential_success)) {
  cat("✓ Tous les packages essentiels sont installés. Vous pouvez exécuter le script principal.\n")
} else {
  cat("✗ Certains packages essentiels manquent. Vérifiez les erreurs ci-dessus.\n")
  failed_packages <- essential_packages[!essential_success]
  cat("Packages manquants:", paste(failed_packages, collapse = ", "), "\n")
}

# Test rapide
cat("\n=== TEST RAPIDE ===\n")
tryCatch({
  library(data.table)
  library(lubridate)
  library(mclust)
  dt_test <- data.table(x = 1:5, y = Sys.time() + 1:5)
  dt_test[, hour := hour(y)]
  cat("✓ Test des fonctions de base réussi\n")
}, error = function(e) {
  cat("✗ Erreur dans le test:", e$message, "\n")
})

cat("\nInstallation terminée !\n") 