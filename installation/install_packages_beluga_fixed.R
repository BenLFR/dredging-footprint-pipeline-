# ==============================================================================
# Installation AUTOMATIQUE des packages R pour Beluga (version finale)
# ==============================================================================

cat("🔧 INSTALLATION AUTOMATIQUE DES PACKAGES R\n")
cat("==========================================\n")

# Détecter la version de R
r_version <- paste(R.version$major, R.version$minor, sep=".")
cat("📋 Version R détectée:", r_version, "\n")

# Configuration adaptée pour Beluga
options(repos = c(CRAN = "https://cran.rstudio.com/"))
options(timeout = 600)
options(download.file.method = "auto")

# Créer répertoire personnel pour packages
personal_lib <- file.path(Sys.getenv("HOME"), "R", paste0("x86_64-pc-linux-gnu-library/", substr(r_version,1,3)))
dir.create(personal_lib, recursive = TRUE, showWarnings = FALSE)

# Configurer les chemins
.libPaths(c(personal_lib, .libPaths()))
cat("📦 Répertoire packages:", personal_lib, "\n")

# Liste complète des packages nécessaires avec leurs dépendances
essential_packages <- c(
  "data.table",
  "lubridate", 
  "mclust",
  "pROC",
  "caret",
  "ggplot2",
  "dbscan",
  "dplyr",
  "zoo",
  "depmixS4",
  "pbapply",
  "matrixStats",
  "geosphere"
)

# Fonction d'installation robuste
install_safe <- function(pkg) {
  cat("📦 Installation de", pkg, "...\n")
  
  # Vérifier si déjà installé
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("✅", pkg, "déjà installé\n")
    return(TRUE)
  }
  
  # Installation avec gestion d'erreurs
  tryCatch({
    install.packages(pkg, 
                     lib = personal_lib,
                     dependencies = c("Depends", "Imports"),
                     repos = "https://cran.rstudio.com/",
                     quiet = FALSE,
                     type = "source")
    
    # Test de chargement
    if (require(pkg, character.only = TRUE, lib.loc = personal_lib, quietly = TRUE)) {
      cat("✅", pkg, "installé avec succès\n")
      return(TRUE)
    } else {
      cat("❌", pkg, "installation échouée - test de chargement\n")
      return(FALSE)
    }
  }, error = function(e) {
    cat("❌", pkg, "erreur:", as.character(e), "\n")
    return(FALSE)
  })
}

# Installation des packages essentiels
cat("\n🚀 INSTALLATION DES PACKAGES ESSENTIELS\n")
cat("=======================================\n")

success_count <- 0
for (pkg in essential_packages) {
  if (install_safe(pkg)) {
    success_count <- success_count + 1
  }
  Sys.sleep(1)  # Pause entre installations
}

# Résumé final
cat("\n📊 RÉSUMÉ INSTALLATION\n")
cat("=====================\n")
cat("Packages installés:", success_count, "/", length(essential_packages), "\n")

if (success_count == length(essential_packages)) {
  cat("🎉 INSTALLATION COMPLÈTE RÉUSSIE !\n")
} else {
  cat("⚠️  Installation partielle -", length(essential_packages) - success_count, "packages échoués\n")
}

# Test fonctionnel final
cat("\n🧪 TEST FONCTIONNEL FINAL\n")
cat("=========================\n")
tryCatch({
  library(data.table, lib.loc = personal_lib)
  library(mclust, lib.loc = personal_lib)
  
  # Test simple
  dt_test <- data.table(x = 1:5, y = rnorm(5))
  gmm_test <- Mclust(rnorm(20), G = 2, verbose = FALSE)
  
  cat("🎉 PACKAGES FONCTIONNELS !\n")
}, error = function(e) {
  cat("❌ ERREUR TEST FONCTIONNEL:", as.character(e), "\n")
})

# Sauvegarder configuration
rprofile_content <- paste0(
  '# Configuration R pour Beluga\n',
  '.libPaths(c("', personal_lib, '", .libPaths()))\n',
  'options(repos = c(CRAN = "https://cran.rstudio.com/"))\n'
)
writeLines(rprofile_content, file.path(Sys.getenv("HOME"), ".Rprofile"))

cat("\n🏁 INSTALLATION TERMINÉE !\n") 