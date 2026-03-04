#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-6  ─  CALCUL DU CARBONE REMINÉRALISÉ (Cri)
# Corrigé pour produire aussi les bornes inf/sup et robuste sur les coordonnées
# Version optimisée avec gestion mémoire et robustesse améliorée
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques et Paramètres ----------------------------------------------
pkgs <- c("sf","dplyr","data.table","terra","lubridate")
invisible(sapply(pkgs, function(pkg) suppressPackageStartupMessages(library(pkg, character.only=TRUE))))

# Configuration Terra pour éviter les problèmes de mémoire
terraOptions(tempdir = "/scratch/benl/tmp")  # Dossiers lourds dans /scratch

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

# 🔧 Correction : Ajout des colonnes x/y si absentes
if (!("x" %in% names(fi_dt) && "y" %in% names(fi_dt))) {
  if ("col" %in% names(fi_dt) && "row" %in% names(fi_dt)) {
    fi_dt[, x := -18000000 + col*1000 + 500]
    fi_dt[, y :=  9000000 - row*1000 - 500]
    cat("✅ Coordonnées x/y reconstruites à partir de col/row.\n")
  } else if ("grid_id" %in% names(fi_dt)) {
    fi_dt[, col := (grid_id-1L) %% 36000L]
    fi_dt[, row := (grid_id-1L) %/% 36000L]
    fi_dt[, x := -18000000 + col*1000 + 500]
    fi_dt[, y :=  9000000 - row*1000 - 500]
    cat("✅ Coordonnées x/y reconstruites à partir de grid_id.\n")
  } else {
    stop("❌ Impossible de retrouver les coordonnées : ni x/y ni col/row ni grid_id dans fi_dt.")
  }
}

# 🔧 Vérification de la contiguïté des grid_id
stopifnot(all(fi_dt$grid_id >= 1 & fi_dt$grid_id <= 18000*36000))
cat("✅ Vérification grid_id : contiguïté OK.\n")

coords <- fi_dt[, .(x, y)]

## 2.  Charger le stock de carbone (C0i) et les incertitudes ------------------------------------------
cat("🔄 2. Chargement du stock de carbone (C0i) et des incertitudes...\n")
carbon_dir <- path.expand("/home/benl/")

# Charger tous les fichiers TIF de carbone
carbon_files <- list.files(carbon_dir, pattern = "\\.tif$", full.names = TRUE)
cat("📁 Fichiers TIF trouvés:", length(carbon_files), "\n")
cat("   ", paste(basename(carbon_files), collapse=", "), "\n")

if(length(carbon_files) == 0) {
  stop("❌ Aucun fichier TIF de stock de carbone trouvé dans", carbon_dir, 
       "\n   Veuillez y téléverser les données d'Atwood & al.")
}

# Charger les rasters de carbone
carbon_rasters <- list()
for(file in carbon_files) {
  name <- tools::file_path_sans_ext(basename(file))
  name_clean <- tolower(gsub(" ", "_", name)) # ex: "Mean carbon_stock" -> "mean_carbon_stock"
  carbon_rasters[[name_clean]] <- terra::rast(file)
  cat("✔️ Raster chargé :", basename(file), "->", name_clean, "\n")
}

# 🔧 Optimisation : reprojection une seule fois si nécessaire
template_raster <- terra::rast(nrows=18000, ncols=36000, crs="EPSG:6933",
                              xmin=-18000000, xmax=18000000, ymin=-9000000, ymax=9000000)

for(name in names(carbon_rasters)) {
  # Vérifier si la projection correspond
  if (!terra::compareGeom(carbon_rasters[[name]], template_raster, stopOnError = FALSE)) {
    cat("🔄 Reprojection du raster", name, "vers EPSG:6933...\n")
    carbon_rasters[[name]] <- terra::project(carbon_rasters[[name]], template_raster)
  }
}

# Extraction des valeurs pour chaque cellule
for(name in names(carbon_rasters)) {
  col_name <- paste0("C0i_", name)
  fi_dt[[col_name]] <- terra::extract(carbon_rasters[[name]], coords, ID=FALSE)[[1]]
  fi_dt[is.na(get(col_name)), (col_name) := 0] # Remplacer les NA par 0
  cat("✅", col_name, "extrait pour", sum(fi_dt[[col_name]] > 0), "cellules.\n")
}

# Détermination de la couche centrale et min/max
if("C0i_mean_carbon_stock" %in% names(fi_dt)) {
  fi_dt$C0i <- fi_dt$C0i_mean_carbon_stock
} else {
  stop("❌ Pas de raster 'Mean carbon_stock' trouvé. Vérifiez le nom du fichier !")
}
if("C0i_global_error_lower_bound" %in% names(fi_dt)) {
  fi_dt$C0i_lower <- fi_dt$C0i_global_error_lower_bound
} else {
  cat("⚠️ Pas de raster 'global_error_lower_bound' trouvé. Pas de Cri_lower.\n")
}
if("C0i_global_error_upper_bound" %in% names(fi_dt)) {
  fi_dt$C0i_upper <- fi_dt$C0i_global_error_upper_bound
} else {
  cat("⚠️ Pas de raster 'global_error_upper_bound' trouvé. Pas de Cri_upper.\n")
}
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
  trawling_dt <- readRDS(trawling_history_path)
  setDT(trawling_dt)
  
  # 🔧 Correction : utilisation de fifelse au lieu de ifelse avec argument na
  if ("years_trawled" %in% names(trawling_dt)) {
  fi_dt <- merge(fi_dt, trawling_dt[, .(grid_id, years_trawled)], by = "grid_id", all.x = TRUE)
    fi_dt[, di := fifelse(is.na(years_trawled), 1.0,
                          fifelse(years_trawled > 10, 0.272, 1.0))]
  } else {
    fi_dt[, di := 1.0]
  }
  cat("✅ Facteur de déplétion (di) calculé.\n")
}

## 4.  Calcul final de Cri --------------------------------------------------------
cat("🔄 4. Calcul du carbone reminéralisé (Cri)...\n")
fi_dt[, C_ri := C0i * f_i_full * di]
fi_dt[, C_ri_conservative := C0i * f_i_conservative * di]
if("C0i_lower" %in% names(fi_dt)) {
  fi_dt[, C_ri_lower := C0i_lower * f_i_full * di]
}
if("C0i_upper" %in% names(fi_dt)) {
  fi_dt[, C_ri_upper := C0i_upper * f_i_full * di]
}
cat("✅ Calcul de Cri (central et incertitudes) terminé.\n")

## 5.  Sauvegarde finale ----------------------------------------------------------
cat("💾 5. Sauvegarde finale...\n")
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_prefix <- file.path(path.expand("/scratch/benl/output_V6/"), paste0("cri_final_", timestamp))

# Sauvegarde des données complètes
out_rds <- paste0(output_prefix, ".rds")
saveRDS(fi_dt, out_rds)
cat("✔️ Données complètes sauvegardées en RDS:", basename(out_rds), "\n")
if(requireNamespace("arrow", quietly = TRUE)) {
  out_parquet <- paste0(output_prefix, ".parquet")
  arrow::write_parquet(fi_dt, out_parquet)
  cat("✔️ Données complètes sauvegardées en Parquet:", basename(out_parquet), "\n")
}

# 🔧 Fonction optimisée pour l'écriture des rasters par blocs
write_cri_raster <- function(values, filename) {
  cat("🗺️  Création du raster :", basename(filename), "\n")
  g <- rast(nrows = 18000, ncols = 36000,
            xmin = -18000000, xmax = 18000000,
            ymin =  -9000000, ymax =   9000000,
            crs  = "EPSG:6933")
  g[] <- NA_real_
  g[fi_dt$grid_id] <- values
  writeRaster(g, filename, datatype = "FLT4S", overwrite = TRUE,
              gdal = c("COMPRESS=LZW", "TILED=YES"))
  cat("✅ Raster sauvegardé :", basename(filename), "\n")
}

# Sauvegarde du raster GeoTIFF (central, lower, upper)
cat("🗺️  Création des rasters GeoTIFF...\n")

# Raster principal (central)
write_cri_raster(fi_dt$C_ri, paste0(output_prefix, ".tif"))

# Raster min (lower)
if("C_ri_lower" %in% names(fi_dt)) {
  write_cri_raster(fi_dt$C_ri_lower, paste0(output_prefix, "_lower.tif"))
}

# Raster max (upper)
if("C_ri_upper" %in% names(fi_dt)) {
  write_cri_raster(fi_dt$C_ri_upper, paste0(output_prefix, "_upper.tif"))
}

cat("\n🎉 Terminé !\n") 
