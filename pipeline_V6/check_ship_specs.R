#!/usr/bin/env Rscript

# Charger les packages nécessaires
library(data.table)
library(yaml)

cat("�� VÉRIFICATION DE L'INTÉGRATION DES SPÉCIFICATIONS NAVIRES\n")
cat("========================================================\n\n")

# 1. Lire le fichier de spécifications
spec_file <- "~/R_scripts/configuration/ship_specs.yaml"
if (!file.exists(spec_file)) {
  stop("❌ Fichier ship_specs.yaml introuvable: ", spec_file)
}

spec_list <- yaml::read_yaml(spec_file)$ship_specs
ship_specs <- rbindlist(spec_list, fill = TRUE)
setnames(ship_specs, "service_speed_kn", "Service_speed")
setkey(ship_specs, ssvid)

cat("�� SPÉCIFICATIONS NAVIRES (ship_specs.yaml):\n")
print(ship_specs[, .(ssvid, name, Service_speed, dredge_width_m, dredging_depth_m)])
cat("\n")

# 2. Vérifier un fichier nettoyé (Charles Darwin)
results_dir <- "~/scratch/ais_results_57238400"
clean_file <- file.path(results_dir, "01_Charles_Darwin_clean.rds")

if (!file.exists(clean_file)) {
  cat("⚠️ Fichier nettoyé non trouvé: ", clean_file, "\n")
  cat("   Vérifiez que l'étape 2 s'est bien terminée\n")
  quit(status = 1)
}

cat("�� LECTURE DU FICHIER NETTOYÉ: ", basename(clean_file), "\n")
data <- readRDS(clean_file)
setDT(data)

cat("📊 INFORMATIONS GÉNÉRALES:\n")
cat("   • Nombre de lignes:", nrow(data), "\n")
cat("   • Nombre de colonnes:", ncol(data), "\n")
cat("   • Navire:", unique(data$Navire), "\n")
cat("   • SSVID:", unique(data$ssvid), "\n\n")

# 3. Vérifier les colonnes de spécifications
spec_cols <- c("Service_speed", "dredge_width_m", "dredging_depth_m")
cat("🔍 VÉRIFICATION DES COLONNES DE SPÉCIFICATIONS:\n")
for (col in spec_cols) {
  if (col %in% names(data)) {
    unique_vals <- unique(data[[col]])
    cat(sprintf("   ✅ %-20s: présent - valeurs: %s\n", col, paste(unique_vals, collapse=", ")))
  } else {
    cat(sprintf("   ❌ %-20s: MANQUANT\n", col))
  }
}

# 4. Comparer avec les spécifications attendues
if ("ssvid" %in% names(data)) {
  ssvid_data <- unique(data$ssvid)
  cat("\n🔍 COMPARAISON AVEC LES SPÉCIFICATIONS ATTENDUES:\n")
  
  # Trouver les spécifications correspondantes
  expected_specs <- ship_specs[ssvid == ssvid_data]
  
  if (nrow(expected_specs) > 0) {
    cat("   SSVID trouvé dans ship_specs.yaml:\n")
    cat(sprintf("   • Service_speed attendu: %.1f kn\n", expected_specs$Service_speed))
    cat(sprintf("   • Dredge_width attendu: %.1f m\n", expected_specs$dredge_width_m))
    cat(sprintf("   • Dredging_depth attendu: %.1f m\n", expected_specs$dredging_depth_m))
    
    # Vérifier la cohérence
    if ("Service_speed" %in% names(data)) {
      actual_speed <- unique(data$Service_speed)
      if (abs(actual_speed - expected_specs$Service_speed) < 0.1) {
        cat("   ✅ Service_speed cohérent\n")
      } else {
        cat(sprintf("   ⚠️ Service_speed incohérent: %.1f vs %.1f kn\n", 
                   actual_speed, expected_specs$Service_speed))
      }
    }
  } else {
    cat("   ❌ SSVID non trouvé dans ship_specs.yaml\n")
  }
}

# 5. Vérifier l'utilisation des spécifications
cat("\n�� VÉRIFICATION DE L'UTILISATION DES SPÉCIFICATIONS:\n")

# Vérifier si le filtre de vitesse a été appliqué
if ("Service_speed" %in% names(data)) {
  speed_limit <- unique(data$Service_speed) * 1.15
  max_speed <- max(data$Speed, na.rm = TRUE)
  cat(sprintf("   • Vitesse max observée: %.1f kn\n", max_speed))
  cat(sprintf("   • Limite de vitesse (1.15 × service): %.1f kn\n", speed_limit))
  
  if (max_speed <= speed_limit) {
    cat("   ✅ Filtre de vitesse appliqué correctement\n")
  } else {
    cat("   ⚠️ Vitesses supérieures à la limite détectées\n")
  }
}

# 6. Statistiques générales
cat("\n📊 STATISTIQUES GÉNÉRALES:\n")
cat("   • Vitesse moyenne:", round(mean(data$Speed, na.rm = TRUE), 2), "kn\n")
cat("   • Vitesse médiane:", round(median(data$Speed, na.rm = TRUE), 2), "kn\n")
cat("   • Vitesse max:", round(max(data$Speed, na.rm = TRUE), 2), "kn\n")
cat("   • Vitesse min:", round(min(data$Speed, na.rm = TRUE), 2), "kn\n")

cat("\n✅ VÉRIFICATION TERMINÉE\n")
