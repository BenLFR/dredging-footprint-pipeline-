# ==============================================================================
# Script de vérification du statut des packages sur Beluga
# ==============================================================================

cat("=== VÉRIFICATION DES PACKAGES R SUR BELUGA ===\n")

# Packages essentiels
essential_packages <- c(
  "data.table", "lubridate", "mclust", "ranger", "caret", 
  "pROC", "ggplot2", "sf", "dbscan", "dplyr", "zoo", 
  "depmixS4", "pbapply", "geosphere", "matrixStats"
)

# Packages optionnels
optional_packages <- c("marmap", "raster", "mixsmsn")

# Fonction de vérification
check_package <- function(pkg) {
  tryCatch({
    library(pkg, character.only = TRUE, quietly = TRUE)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

# Vérification des packages essentiels
cat("\n=== PACKAGES ESSENTIELS ===\n")
essential_status <- sapply(essential_packages, function(pkg) {
  status <- check_package(pkg)
  if (status) {
    cat("✓", pkg, "\n")
  } else {
    cat("✗", pkg, "MANQUANT\n")
  }
  return(status)
})

# Vérification des packages optionnels
cat("\n=== PACKAGES OPTIONNELS ===\n")
optional_status <- sapply(optional_packages, function(pkg) {
  status <- check_package(pkg)
  if (status) {
    cat("✓", pkg, "\n")
  } else {
    cat("⚠", pkg, "manquant (non critique)\n")
  }
  return(status)
})

# Résumé
cat("\n=== RÉSUMÉ ===\n")
essential_ok <- sum(essential_status)
essential_total <- length(essential_packages)
optional_ok <- sum(optional_status)
optional_total <- length(optional_packages)

cat("Packages essentiels:", essential_ok, "/", essential_total, "\n")
cat("Packages optionnels:", optional_ok, "/", optional_total, "\n")

if (essential_ok == essential_total) {
  cat("✅ TOUS LES PACKAGES ESSENTIELS SONT INSTALLÉS\n")
  cat("   Vous pouvez exécuter votre script principal.\n")
} else {
  missing_essential <- essential_packages[!essential_status]
  cat("❌ PACKAGES ESSENTIELS MANQUANTS:\n")
  for (pkg in missing_essential) {
    cat("   -", pkg, "\n")
  }
  cat("\n   Réinstallez avec: Rscript install_packages_beluga_fixed.R\n")
}

if (optional_ok < optional_total) {
  missing_optional <- optional_packages[!optional_status]
  cat("\n⚠️  PACKAGES OPTIONNELS MANQUANTS (non critiques):\n")
  for (pkg in missing_optional) {
    cat("   -", pkg, "\n")
  }
}

cat("\n=== INFORMATIONS SYSTÈME ===\n")
cat("Version R:", R.version.string, "\n")
cat("Répertoires des packages:\n")
for (path in .libPaths()) {
  cat("  -", path, "\n")
} 