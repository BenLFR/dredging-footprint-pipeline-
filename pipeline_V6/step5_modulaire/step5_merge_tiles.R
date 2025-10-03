#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  FUSION FINALE DES TUILES (pipeline V6, cluster Rorqual)
# Fusionne tous les fichiers sar_*.parquet en un seul fichier global
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques ------------------------------------------------------------
pkgs <- c("sf", "dplyr", "data.table", "arrow")

safe_library <- function(pkg){
  tryCatch({ 
    library(pkg, character.only = TRUE)
    cat("✅", pkg, "OK\n")
  }, error=function(e) stop("❌ Package manquant : ", pkg, "\nMessage : ", e$message))
}

# Chargement des packages
invisible(lapply(pkgs, safe_library))
cat("\n")

# Chargement des constantes partagées
this_file <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) return(normalizePath(f))
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile))
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))

cat("🔧 Fusion finale des tuiles Step 5\n")

## 1.  Recherche des fichiers à fusionner --------------------------------------
cat("📂 Recherche des fichiers sar_*.parquet...\n")
output_dir <- "~/scratch/output_V6"
sar_files <- list.files(output_dir, pattern = "sar_[0-9]+\\.parquet$", full.names = TRUE)

if(length(sar_files) == 0) {
  stop("❌ Aucun fichier sar_*.parquet trouvé dans", output_dir)
}

cat("✅", length(sar_files), "fichiers trouvés\n")

## 2.  Lecture et fusion des données -------------------------------------------
cat("🔄 Fusion des données...\n")
start_time <- Sys.time()

# Initialisation du résultat
all_data <- data.table()

# Traitement fichier par fichier pour économiser la mémoire
for(i in seq_along(sar_files)) {
  if(i %% 50 == 0) {
    cat("   Progression:", i, "/", length(sar_files), "\n")
    gc()  # Nettoyage mémoire régulier
  }
  
  file <- sar_files[i]
  
  tryCatch({
    # Lecture du fichier
    tile_data <- read_parquet(file)
    
    # Vérification que le fichier n'est pas vide
    if(nrow(tile_data) > 0) {
      # Ajout de l'identifiant de la tuile pour traçabilité
      tile_id <- as.integer(sub(".*sar_([0-9]+)\\.parquet$", "\\1", basename(file)))
      tile_data[, tile_id := tile_id]
      
      # Fusion avec les données existantes
      if(nrow(all_data) == 0) {
        all_data <- tile_data
      } else {
        all_data <- rbindlist(list(all_data, tile_data), use.names = TRUE, fill = TRUE)
      }
    }
    
  }, error = function(e) {
    cat("⚠️  Erreur lecture", basename(file), ":", e$message, "\n")
  })
}

# Optimisation finale
if(nrow(all_data) > 0) {
  setkey(all_data, grid_id)  # Clé pour optimiser les requêtes downstream
}

cat("✅ Fusion terminée :", nrow(all_data), "lignes\n")
cat("⏱️  Durée :", round(difftime(Sys.time(), start_time, units="mins"), 2), "minutes\n")

## 3.  Statistiques finales ----------------------------------------------------
cat("\n📊 STATISTIQUES FINALES :\n")
if(nrow(all_data) > 0) {
  cat("   - Total lignes :", format(nrow(all_data), big.mark=","), "\n")
  cat("   - Cellules uniques :", format(length(unique(all_data$grid_id)), big.mark=","), "\n")
  cat("   - Tuiles avec données :", format(length(unique(all_data$tile_id)), big.mark=","), "\n")
  cat("   - Distance totale :", format(sum(all_data$sum_d), scientific=FALSE, big.mark=","), "m\n")
  cat("   - SAR moyen :", format(mean(all_data$sum_dw / CELL_AREA_M2), scientific=FALSE), "m²\n")
  cat("   - SAR max :", format(max(all_data$sum_dw / CELL_AREA_M2), scientific=FALSE), "m²\n")
} else {
  cat("   - Aucune donnée à traiter\n")
}

## 4.  Sauvegarde du fichier final ---------------------------------------------
cat("\n💾 Sauvegarde du fichier final...\n")
output_file <- file.path(output_dir, "f_i_global_1km.parquet")

if(nrow(all_data) > 0) {
  # Sauvegarde en Parquet
  write_parquet(all_data, output_file)
  cat("✅ Fichier final sauvegardé :", basename(output_file), "\n")
  cat("   Taille :", format(file.size(output_file), big.mark=","), "bytes\n")
} else {
  # Création d'un fichier vide au bon format
  empty_data <- data.table(
    grid_id = integer(),
    sum_dw = numeric(),
    sum_dw_pd = numeric(),
    sum_d = numeric(),
    sum_d_pl = numeric(),
    tile_id = integer()
  )
  write_parquet(empty_data, output_file)
  cat("⚠️  Fichier final vide créé :", basename(output_file), "\n")
}

cat("\n✅ Fusion finale Step 5 terminée avec succès !\n") 