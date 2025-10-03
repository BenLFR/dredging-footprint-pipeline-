#!/usr/bin/env Rscript
# Script de vérification qs vs RDS sur Beluga

cat("🔍 === VÉRIFICATION QS VS RDS ===\n")
cat("Timestamp:", format(Sys.time()), "\n\n")

# Configuration R selon README
.libPaths("~/.local/R/4.2.1/")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")

suppressPackageStartupMessages({
  library(data.table)
})

# Test des deux formats avec données réelles
cat("📊 Test avec échantillon de données...\n")

# Créer un échantillon représentatif
set.seed(42)
sample_data <- data.table(
  Lon = runif(10000, -10, 10),
  Lat = runif(10000, 40, 60), 
  Speed = rgamma(10000, 2, 2),
  Course = runif(10000, 0, 360),
  Timestamp = seq(as.POSIXct("2024-01-01"), by="30 secs", length.out=10000),
  Navire = sample(c("Test_Ship_A", "Test_Ship_B", "Test_Ship_C"), 10000, replace=TRUE)
)

cat("  Données test:", nrow(sample_data), "lignes,", ncol(sample_data), "colonnes\n")
cat("  Taille mémoire:", format(object.size(sample_data), units="MB"), "\n\n")

# Test QS (si disponible)
use_qs <- FALSE
qs_file <- tempfile(fileext = ".qs")
qs_time <- qs_size <- NA

tryCatch({
  if (requireNamespace("qs", quietly = TRUE)) {
    library(qs)
    
    # Test écriture QS
    time_qs_write <- system.time({
      qs::qsave(sample_data, qs_file, preset = "custom",
                algorithm = "zstd", preset_compression = 6)
    })
    
    # Test lecture QS  
    time_qs_read <- system.time({
      data_qs <- qs::qread(qs_file, as.data.table = TRUE)
    })
    
    qs_size <- file.size(qs_file) / 1024^2  # MB
    use_qs <- TRUE
    
    cat("✅ QS disponible et fonctionnel:\n")
    cat("  Écriture:", sprintf("%.2f s", time_qs_write[3]), "\n")
    cat("  Lecture:", sprintf("%.2f s", time_qs_read[3]), "\n") 
    cat("  Taille fichier:", sprintf("%.2f MB", qs_size), "\n")
    cat("  Intégrité:", if(identical(sample_data, data_qs)) "✅ OK" else "❌ ERREUR", "\n\n")
    
    rm(data_qs)
  } else {
    stop("qs non disponible")
  }
}, error = function(e) {
  cat("❌ QS non disponible:", e$message, "\n\n")
})

# Test RDS (toujours disponible)
rds_file <- tempfile(fileext = ".rds")

time_rds_write <- system.time({
  saveRDS(sample_data, rds_file, compress = "xz")
})

time_rds_read <- system.time({
  data_rds <- readRDS(rds_file)
  setDT(data_rds)
})

rds_size <- file.size(rds_file) / 1024^2  # MB

cat("✅ RDS (fallback):\n")
cat("  Écriture:", sprintf("%.2f s", time_rds_write[3]), "\n")
cat("  Lecture:", sprintf("%.2f s", time_rds_read[3]), "\n")
cat("  Taille fichier:", sprintf("%.2f MB", rds_size), "\n")
cat("  Intégrité:", if(identical(sample_data, data_rds)) "✅ OK" else "❌ ERREUR", "\n\n")

# Comparaison
cat("📈 COMPARAISON:\n")
if (use_qs) {
  cat("  QS vs RDS taille:", sprintf("%.1fx", rds_size/qs_size), "plus gros pour RDS\n")
  cat("  QS vs RDS écriture:", sprintf("%.1fx", time_rds_write[3]/time_qs_write[3]), "plus lent pour RDS\n")
  cat("  QS vs RDS lecture:", sprintf("%.1fx", time_rds_read[3]/time_qs_read[3]), "plus lent pour RDS\n")
} else {
  cat("  ⚠️ QS non disponible, utilisation RDS uniquement\n")
}

# Projection sur dataset réel
cat("\n🚀 PROJECTION DATASET RÉEL (10.4M lignes):\n")
ratio <- 10432017 / 10000
if (use_qs) {
  cat("  Taille estimée QS:", sprintf("%.0f MB", qs_size * ratio), "\n")
}
cat("  Taille estimée RDS:", sprintf("%.0f MB", rds_size * ratio), "\n")

# Nettoyage
unlink(c(qs_file, rds_file))
rm(sample_data, data_rds)
gc()

cat("\n✅ Test terminé\n") 