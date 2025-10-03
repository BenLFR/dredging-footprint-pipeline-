#!/usr/bin/env Rscript

cat("🔧 INSTALLATION COMPLÈTE DE TOUS LES PACKAGES\n")
cat("==========================================\n")

# Configuration
options(repos = c(CRAN = "https://cran.rstudio.com/"))
options(timeout = 600)
personal_lib <- "~/R/library"

# LISTE COMPLÈTE des packages nécessaires
all_packages <- c(
  "data.table", "lubridate", "mclust", "pROC", "caret", 
  "ggplot2", "lattice", "foreach", "ModelMetrics", 
  "plyr", "reshape2", "nlme", "BradleyTerry2", "e1071",
  "dbscan", "dplyr", "zoo", "depmixS4", "pbapply", 
  "matrixStats", "geosphere", "ranger", "randomForest",
  "class", "kernlab", "nnet", "proxy", "ipred"
)

cat("📦 Packages à installer:", length(all_packages), "\n")

# Installation forcée
for (pkg in all_packages) {
  cat("⬇️ ", pkg, "... ")
  tryCatch({
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      install.packages(pkg, 
                       lib = personal_lib,
                       dependencies = TRUE,
                       repos = "https://cran.rstudio.com/")
    }
    library(pkg, character.only = TRUE)
    cat("✅\n")
  }, error = function(e) {
    cat("❌ ERREUR:", as.character(e), "\n")
  })
}

cat("\n🧪 TEST FINAL DE TOUS LES PACKAGES\n")
for (pkg in all_packages) {
  cat(pkg, ": ")
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("✅\n")
  } else {
    cat("❌\n")
  }
}

cat("🏁 Installation terminée !\n") 