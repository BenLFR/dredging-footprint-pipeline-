#!/usr/bin/env Rscript

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
.libPaths("~/.local/R/4.2.1/")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")

cat("🔄 === TEST STEP2 DIRECT ===\n")
cat("Début:", format(Sys.time()), "\n")

# Configuration anti-gforce
options(mc.cores = 1)
Sys.setenv(MC_CORES = 1)
Sys.setenv(DT_GForce = "FALSE")
Sys.setenv(OMP_NUM_THREADS = 1)

# Chargement packages
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(yaml)
  library(solitude)
  library(mclust)
  library(zoo)
})

setDTthreads(1)
cat("✅ Packages chargés - Configuration mono-thread activée\n")

# Test fichier navire
input_file <- "~/scratch/test_step1_final/navire_11_Vasco_Da_Gama.rds"

if (!file.exists(input_file)) {
  stop("❌ Fichier navire introuvable: ", input_file)
}

cat("📖 Chargement navire Vasco Da Gama...\n")
dt_nav <- readRDS(input_file)
setDT(dt_nav)
cat("✅ Données chargées:", nrow(dt_nav), "observations\n")

# Configuration outlier simple
outlier_config <- list(
  contamination_rate = 0.02,
  if_sample_size = 256,
  if_num_trees = 25,
  memory_conservative = TRUE
)

# Test Isolation Forest simple
cat("🌲 Test Isolation Forest...\n")
features <- c("Lat", "Lon")
if ("Speed" %in% names(dt_nav)) features <- c(features, "Speed")

cat("  Features utilisées:", paste(features, collapse=", "), "\n")

dt_features <- dt_nav[, ..features]
dt_features <- dt_features[complete.cases(dt_features)]

cat("  Données complètes:", nrow(dt_features), "sur", nrow(dt_nav), "\n")

if (nrow(dt_features) >= 50) {
  # Isolation Forest
  if_model <- isolationForest$new(
    sample_size = min(outlier_config$if_sample_size, nrow(dt_features)),
    num_trees = outlier_config$if_num_trees,
    seed = 42
  )
  
  cat("  🚀 Fitting Isolation Forest...\n")
  if_model$fit(dt_features)
  
  cat("  🔍 Prédiction outliers...\n")
  scores <- if_model$predict(dt_features)
  outliers <- scores$anomaly_score > quantile(scores$anomaly_score, 
                                             1 - outlier_config$contamination_rate)
  
  n_outliers <- sum(outliers)
  outlier_rate <- round(n_outliers / nrow(dt_features) * 100, 2)
  
  cat("✅ RÉSULTATS:\n")
  cat("  • Outliers détectés:", n_outliers, "(", outlier_rate, "%)\n")
  
  # Test sauvegarde
  output_file <- "~/scratch/test_step2_vasco_da_gama_clean.rds"
  dt_nav[, outlier_IF := FALSE]
  if (nrow(dt_features) == nrow(dt_nav)) {
    dt_nav[, outlier_IF := outliers]
  }
  
  cat("💾 Test sauvegarde:", output_file, "\n")
  saveRDS(dt_nav, output_file, compress = "xz")
  
  if (file.exists(output_file)) {
    file_size <- file.info(output_file)$size / 1024^2
    cat("✅ Fichier sauvé:", round(file_size, 1), "MB\n")
  }
  
} else {
  cat("❌ Pas assez de données pour IF\n")
}

cat("✅ Test step2 terminé:", format(Sys.time()), "\n")
