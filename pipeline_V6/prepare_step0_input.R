#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# SCRIPT DE PRÉPARATION : FUSION ET NETTOYAGE DES DONNÉES POUR STEP 0
# - Unifie les MMSI pour les navires avec des identifiants multiples.
# - Trie et dédoublonne les tracés pour assurer la cohérence.
# - Sauvegarde un fichier RDS propre, prêt pour Step 0.
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Configuration ------------------------------------------------------------
if (!requireNamespace("data.table", quietly = TRUE)) install.packages("data.table")
library(data.table)

# --- PARAMÈTRES ---
# Fichier d'entrée contenant les nouvelles données complètes
file_input <- "benjamin3.csv"
# Fichier de sortie qui sera utilisé par Step 0
file_output <- "AIS_data_step0_input_ready.rds"

# Définition des navires à unifier
# Ici, nous fusionnons les données du Vasco da Gama
vasco_da_gama_old_mmsi <- "253193000"
vasco_da_gama_new_mmsi <- "205744000"

cat("--- Lancement de la préparation des données pour Step 0 ---\n\n")

## 1.  Chargement des données --------------------------------------------------
cat("1. Chargement du fichier :", file_input, "\n")
if (!file.exists(file_input)) {
  stop("ERREUR : Fichier d'entrée '", file_input, "' non trouvé.")
}
dt <- fread(file_input)
cat("   ✅", nrow(dt), "lignes chargées.\n\n")

# Nettoyage des noms de colonnes (minuscules, underscores)
setnames(dt, tolower(gsub("[ .]", "_", names(dt))))
# S'assurer que l'identifiant est bien de type caractère
dt[, ssvid := as.character(ssvid)]

## 2.  Fusion cohérente du Vasco da Gama --------------------------------------
cat("2. Unification des MMSI pour le Vasco da Gama...\n")

# Compter le nombre de points avant la modification
rows_to_change <- sum(dt$ssvid == vasco_da_gama_old_mmsi)

if (rows_to_change > 0) {
  # Remplacer l'ancien MMSI par le nouveau
  dt[ssvid == vasco_da_gama_old_mmsi, ssvid := vasco_da_gama_new_mmsi]
  cat("   ✅", rows_to_change, "lignes de l'ancien MMSI (", vasco_da_gama_old_mmsi, 
      ") ont été réassignées au nouveau MMSI (", vasco_da_gama_new_mmsi, ").\n\n")
} else {
  cat("   ℹ️  Aucune ligne trouvée pour l'ancien MMSI. Aucune modification nécessaire.\n\n")
}

## 3.  Nettoyage du tracé unifié ------------------------------------------------
cat("3. Tri et dédoublonnage du tracé complet du Vasco da Gama...\n")

# Isoler toutes les données du navire
vasco_dt <- dt[ssvid == vasco_da_gama_new_mmsi]
# Isoler le reste des données
other_dt <- dt[ssvid != vasco_da_gama_new_mmsi]

if (nrow(vasco_dt) > 0) {
  # Trier le tracé complet par date
  setorder(vasco_dt, timestamp)
  
  # Supprimer les doublons stricts (même ssvid, timestamp, lat, lon)
  # Cela nettoie les éventuels chevauchements lors du changement de MMSI
  vasco_dt_clean <- unique(vasco_dt, by = c("ssvid", "timestamp", "lat", "lon"))
  
  rows_removed <- nrow(vasco_dt) - nrow(vasco_dt_clean)
  cat("   ✅ Tracé trié. ", rows_removed, "points dupliqués ont été supprimés.\n\n")
  
  # Recombiner les données nettoyées avec le reste du jeu de données
  dt_final <- rbind(other_dt, vasco_dt_clean)
  
} else {
  cat("   ℹ️  Aucune donnée pour le Vasco da Gama. Le fichier de sortie sera identique à l'entrée.\n\n")
  dt_final <- dt
}

## 4.  Sauvegarde finale --------------------------------------------------------
cat("4. Sauvegarde du fichier final prêt pour Step 0...\n")
# Trier le jeu de données final par navire et par date
setorder(dt_final, ssvid, timestamp)

saveRDS(dt_final, file_output)
cat("   ✅ Fichier sauvegardé :", file_output, "\n")
cat("      Nombre total de lignes :", nrow(dt_final), "\n\n")

cat("--- Opération terminée. Vous pouvez maintenant utiliser '", file_output, "' comme entrée pour Step 0. ---\n") 