#!/usr/bin/env Rscript

cat("🔧 Installation de caret et ses dépendances...\n")

# Configuration
options(repos = c(CRAN = "https://cran.rstudio.com/"))
personal_lib <- "~/R/library"

# Installer caret et toutes ses dépendances
packages_needed <- c(
  "caret", "ggplot2", "lattice", "foreach", "ModelMetrics", 
  "plyr", "reshape2", "nlme", "BradleyTerry2", "e1071",
  "dbscan", "dplyr", "zoo", "depmixS4", "pbapply", 
  "matrixStats", "geosphere"
)

for (pkg in packages_needed) {
  cat("📦 Installation de", pkg, "...\n")
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    tryCatch({
      install.packages(pkg, 
                       lib = personal_lib,
                       dependencies = TRUE,
                       repos = "https://cran.rstudio.com/")
      cat("✅", pkg, "installé\n")
    }, error = function(e) {
      cat("❌", pkg, "erreur:", as.character(e), "\n")
    })
  } else {
    cat("✅", pkg, "déjà installé\n")
  }
}

cat("🏁 Installation terminée !\n") 