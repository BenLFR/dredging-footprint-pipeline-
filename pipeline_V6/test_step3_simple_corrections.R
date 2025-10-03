#!/usr/bin/env Rscript
# Test simple des corrections step3

cat("🧪 Test simple des corrections step3\n")

# Configuration R
.libPaths("~/.local/R/4.2.1/")

# Test avec le SPLIT_JOB_ID réel
split_id <- "20250623055849"

# Test de la logique corrigée
split_dir_standard <- file.path("~/scratch", paste0("ais_split_", split_id))

cat("🔍 Test répertoire:", split_dir_standard, "\n")
cat("   Existe:", dir.exists(split_dir_standard), "\n")

if (dir.exists(split_dir_standard)) {
  clean_files <- list.files(split_dir_standard, pattern = "_clean\\.rds$", full.names = TRUE)
  cat("✅ Fichiers trouvés:", length(clean_files), "\n")
  
  if (length(clean_files) > 0) {
    cat("   Premier fichier:", basename(clean_files[1]), "\n")
    
    # Test de chargement
    test_data <- readRDS(clean_files[1])
    cat("✅ Chargement réussi:", nrow(test_data), "lignes\n")
    
    # Test de fusion avec 3 fichiers
    if (length(clean_files) >= 3) {
      cat("\n🧪 Test de fusion avec 3 fichiers...\n")
      test_list <- lapply(clean_files[1:3], readRDS)
      test_merged <- data.table::rbindlist(test_list, fill = TRUE)
      cat("✅ Fusion test réussie:", nrow(test_merged), "lignes\n")
      
      # Test des corrections de types
      cat("\n🔧 Test des corrections de types...\n")
      
      if ("Navire" %in% names(test_merged)) {
        if (!is.character(test_merged$Navire)) {
          cat("⚠️  Conversion de Navire en caractère\n")
          test_merged[, Navire := as.character(Navire)]
        }
        cat("✅ Navire:", class(test_merged$Navire), "\n")
      }
      
      if ("ssvid" %in% names(test_merged)) {
        if (!is.integer(test_merged$ssvid) && !is.numeric(test_merged$ssvid)) {
          cat("⚠️  Conversion de ssvid en entier\n")
          test_merged[, ssvid := as.integer(ssvid)]
        }
        cat("✅ ssvid:", class(test_merged$ssvid), "\n")
      }
      
      cat("✅ Test des corrections terminé\n")
    }
  }
} else {
  cat("❌ Répertoire non trouvé\n")
}

cat(" Test terminé\n") 