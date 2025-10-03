#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-6  ─  CALCUL DU CARBONE REMINÉRALISÉ (Cri)
# Fusionne la fraction f_i avec les stocks de carbone (C0i) et le facteur de déplétion (di)
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques et Paramètres ----------------------------------------------
pkgs <- c("sf","dplyr","data.table","terra","lubridate")
invisible(sapply(pkgs, function(pkg) suppressPackageStartupMessages(library(pkg, character.only=TRUE))))

cat("--- Étape 6 : Calcul de Cri ---\n")

# Argument: chemin vers le fichier fi_grid de l'étape 5
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  # Si aucun argument, rechercher le plus récent
  cat("ℹ️  Aucun fichier f_i spécifié. Recherche du plus récent...\n")
  fi_files <- list.files("~/scratch/output_V6/", pattern="^fi_grid_.*\\.(parquet|rds)$", full.names=TRUE)
  if(length(fi_files) == 0) stop("❌ Aucun fichier f_i trouvé dans ~/scratch/output_V6/")
  fi_path <- fi_files[which.max(file.info(fi_files)$mtime)]
} else {
  fi_path <- args[1]
}
cat("✔️ Fichier f_i utilisé :", basename(fi_path), "\n")

## 1.  Charger les données f_i ----------------------------------------------------
cat("🔄 1. Chargement des données f_i...\n")
if (grepl("\\.parquet$", fi_path)) {
  if(!requireNamespace("arrow", quietly=TRUE)) stop("❌ Le package 'arrow' est requis pour lire les fichiers Parquet.")
  fi_dt <- arrow::read_parquet(fi_path)
} else {
  fi_dt <- readRDS(fi_path)
}
setDT(fi_dt)
cat("✅", nrow(fi_dt), "cellules chargées.\n")

## 2.  Charger le stock de carbone (C0i) ------------------------------------------
cat("🔄 2. Chargement du stock de carbone (C0i)...\n")
carbon_dir <- path.expand("~/scratch/configuration/atwood_carbon/")
carbon_tifs <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)

if(length(carbon_tifs) == 0) {
  stop("❌ Aucun fichier TIF de stock de carbone trouvé dans", carbon_dir, 
       "\n   Veuillez y téléverser les données d'Atwood & al.")
}

# On suppose qu'un seul TIF est le bon, ou qu'ils peuvent être mosaiqués.
# Pour l'instant, on prend le premier.
carbon_rast <- terra::rast(carbon_tifs[1])
cat("✔️ Raster de carbone chargé :", basename(carbon_tifs[1]), "\n")

# Extraire les valeurs de C0i pour chaque cellule f_i
# On utilise les colonnes 'x' et 'y' déjà calculées dans le fichier f_i
coords <- fi_dt[, .(x, y)]
fi_dt$C0i <- terra::extract(carbon_rast, coords, ID=FALSE)[[1]]
fi_dt[is.na(C0i), C0i := 0] # Remplacer les NA par 0

cat("✅ Stock de carbone (C0i) extrait pour", sum(fi_dt$C0i > 0), "cellules.\n")

## 3.  Calculer le facteur de déplétion (di) --------------------------------------
cat("🔄 3. Calcul du facteur de déplétion (di)...\n")
trawling_history_path <- path.expand("~/scratch/configuration/trawling_history.rds")

if (!file.exists(trawling_history_path)) {
  cat("⚠️  Fichier d'historique de chalutage introuvable à :", trawling_history_path, "\n")
  cat("   Application d'un facteur de déplétion (di) par défaut de 1.0\n")
  fi_dt[, di := 1.0]
} else {
  cat("✔️ Fichier d'historique de chalutage trouvé.\n")
  # PLACEHOLDER: Le code ci-dessous est un exemple.
  # Vous devez l'adapter à la structure de votre fichier.
  # On suppose un fichier RDS avec les colonnes "grid_id" et "years_trawled".
  trawling_dt <- readRDS(trawling_history_path)
  setDT(trawling_dt)
  
  # Fusionner avec les données fi
  fi_dt <- merge(fi_dt, trawling_dt[, .(grid_id, years_trawled)], by = "grid_id", all.x = TRUE)
  
  # Calculer di selon la méthodologie
  fi_dt[, di := ifelse(years_trawled > 10, 0.272, 1.0, na = 1.0)]
  cat("✅ Facteur de déplétion (di) calculé.\n")
}

## 4.  Calcul final de Cri --------------------------------------------------------
cat("🔄 4. Calcul du carbone reminéralisé (Cri)...\n")

# C_ri = C_0i * f_i * d_i
fi_dt[, C_ri := C0i * f_i_full * di]

# Calcul du cas conservateur également
fi_dt[, C_ri_conservative := C0i * f_i_conservative * di]

cat("✅ Calcul de Cri terminé.\n")

## 5.  Sauvegarde finale ----------------------------------------------------------
cat("💾 5. Sauvegarde finale...\n")
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_prefix <- file.path(path.expand("~/scratch/output_V6/"), paste0("cri_final_", timestamp))

# Sauvegarde des données complètes
out_rds <- paste0(output_prefix, ".rds")
saveRDS(fi_dt, out_rds)
cat("✔️ Données complètes sauvegardées en RDS:", basename(out_rds), "\n")

if(requireNamespace("arrow", quietly = TRUE)) {
  out_parquet <- paste0(output_prefix, ".parquet")
  arrow::write_parquet(fi_dt, out_parquet)
  cat("✔️ Données complètes sauvegardées en Parquet:", basename(out_parquet), "\n")
}

# Sauvegarde du raster GeoTIFF
cat("🗺️  Création du raster GeoTIFF...\n")
g <- terra::rast(nrows=18000, ncols=36000, crs="EPSG:6933",
                 xmin=-18000000, xmax=18000000, ymin=-9000000, ymax=9000000)

g[fi_dt$grid_id] <- fi_dt$C_ri
out_tiff <- paste0(output_prefix, ".tif")
terra::writeRaster(g, out_tiff, datatype="FLT4S", overwrite=TRUE,
                   gdal=c("COMPRESS=LZW", "TILED=YES"))
cat("✔️ Raster GeoTIFF sauvegardé :", basename(out_tiff), "\n")

cat("\n🎉 Terminé !\n") 