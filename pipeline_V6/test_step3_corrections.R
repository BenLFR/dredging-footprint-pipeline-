#!/usr/bin/env Rscript
# Test des corrections step3 avec vérification des types de colonnes

cat("🧪 Test des corrections step3 avec vérification des types\n")

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
    
    # Test de chargement et vérification des types
    test_data <- readRDS(clean_files[1])
    cat("✅ Chargement réussi:", nrow(test_data), "lignes\n")
    
    # Vérification des types de colonnes
    cat("\n📊 Types des colonnes:\n")
    for (col in names(test_data)) {
      cat(sprintf("   %-15s: %s\n", col, class(test_data[[col]])[1]))
    }
    
    # Vérification spécifique de Navire et ssvid
    if ("Navire" %in% names(test_data)) {
      cat("\n🔍 Colonne Navire:\n")
      cat("   Type:", class(test_data$Navire), "\n")
      cat("   Valeurs uniques:", paste(unique(test_data$Navire), collapse = ", "), "\n")
    }
    
    if ("ssvid" %in% names(test_data)) {
      cat("\n🔍 Colonne ssvid:\n")
      cat("   Type:", class(test_data$ssvid), "\n")
      cat("   Valeurs uniques:", paste(unique(test_data$ssvid), collapse = ", "), "\n")
    }
    
    # Test de fusion avec plusieurs fichiers
    if (length(clean_files) >= 3) {
      cat("\n🧪 Test de fusion avec 3 fichiers...\n")
      test_list <- lapply(clean_files[1:3], readRDS)
      test_merged <- data.table::rbindlist(test_list, fill = TRUE)
      cat("✅ Fusion test réussie:", nrow(test_merged), "lignes\n")
      
      # Vérification des types après fusion
      cat("\n📊 Types après fusion:\n")
      for (col in names(test_merged)) {
        cat(sprintf("   %-15s: %s\n", col, class(test_merged[[col]])[1]))
      }
    }
  }
} else {
  cat("❌ Répertoire non trouvé\n")
} 