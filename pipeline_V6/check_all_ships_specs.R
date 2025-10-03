#!/usr/bin/env Rscript

library(data.table)
library(yaml)

cat("�� VÉRIFICATION COMPLÈTE DES SPÉCIFICATIONS NAVIRES\n")
cat("==================================================\n\n")

# Lire les spécifications
spec_file <- "~/R_scripts/configuration/ship_specs.yaml"
spec_list <- yaml::read_yaml(spec_file)$ship_specs
ship_specs <- rbindlist(spec_list, fill = TRUE)
setnames(ship_specs, "service_speed_kn", "Service_speed")

# Dossier des résultats
results_dir <- "~/scratch/ais_results_57238590"
clean_files <- list.files(results_dir, pattern = "*_clean.rds", full.names = TRUE)

cat("📁 Fichiers nettoyés trouvés:", length(clean_files), "\n\n")

# Vérifier chaque navire
for (file in clean_files) {
  cat("🔍 Vérification:", basename(file), "\n")
  
  data <- readRDS(file)
  setDT(data)
  
  ssvid_data <- unique(data$ssvid)
  navire_name <- unique(data$Navire)
  
  # Trouver les spécifications correspondantes
  expected_specs <- ship_specs[ssvid == ssvid_data]
  
  if (nrow(expected_specs) > 0) {
    cat(sprintf("   ✅ %s (SSVID: %d)\n", navire_name, ssvid_data))
    cat(sprintf("      • Service_speed: %.1f kn\n", expected_specs$Service_speed))
    cat(sprintf("      • Dredge_width: %.1f m\n", expected_specs$dredge_width_m))
    cat(sprintf("      • Dredging_depth: %.1f m\n", expected_specs$dredging_depth_m))
    
    # Vérifier la présence des colonnes
    spec_cols <- c("Service_speed", "dredge_width_m", "dredging_depth_m")
    missing_cols <- spec_cols[!spec_cols %in% names(data)]
    
    if (length(missing_cols) == 0) {
      cat("      ✅ Toutes les colonnes de spécifications présentes\n")
      
      # Vérifier la cohérence des valeurs
      if ("Service_speed" %in% names(data)) {
        actual_speed <- unique(data$Service_speed)
        if (abs(actual_speed - expected_specs$Service_speed) < 0.1) {
          cat("      ✅ Service_speed cohérent\n")
        } else {
          cat(sprintf("      ⚠️ Service_speed incohérent: %.1f vs %.1f kn\n", 
                     actual_speed, expected_specs$Service_speed))
        }
      }
    } else {
      cat(sprintf("      ❌ Colonnes manquantes: %s\n", paste(missing_cols, collapse=", ")))
    }
  } else {
    cat(sprintf("   ❌ %s (SSVID: %d) - Non trouvé dans ship_specs.yaml\n", navire_name, ssvid_data))
  }
  cat("\n")
}

cat("✅ VÉRIFICATION COMPLÈTE TERMINÉE\n")
