#!/usr/bin/env Rscript

# Step 5 optimisé : Fusion des tuiles avec gestion mémoire améliorée
# Évite le problème "Killed" lors de la création du GeoTIFF

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(data.table)
  library(tidyr)
  library(rlang)
  library(tidyselect)
  library(lubridate)
  library(yaml)
  library(arrow)
  library(terra)
})

cat("✅ sf OK\n")
sf_use_s2(FALSE)

cat("✅ dplyr OK\n")
cat("✅ data.table OK\n")
cat("✅ tidyr OK\n")
cat("✅ rlang OK\n")
cat("✅ tidyselect OK\n")
cat("✅ lubridate OK\n")
cat("✅ yaml OK\n")

# — Paramètres de ligne de commande -------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
scenario <- if(length(args) > 0) args[1] else "default"

cat("🔧 Fusion finale - Scenario :", scenario, "\n")

# — Chargement des paramètres YAML --------------------------------------------
param_yaml <- "~/scratch/configuration/fi_parameters_corrected.yaml"
params_raw <- yaml::read_yaml(param_yaml)

# — inheritance helper ---------------------------------------------------------
get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit)
    s$inherit <- NULL
    modifyList(parent, s)
  } else s
}
par <- get_scenario(scenario)

# — Vérification des paramètres requis -----------------------------------------
required <- c("alpha_dep","fast_fraction","slow_k","preservation_factor","k_fast")
miss <- setdiff(required, names(par))
if(length(miss)) stop("❌ Paramètres YAML manquants : ", paste(miss, collapse=", "))

# Vérifier que k_fast n'est pas vide
if (length(par$k_fast) == 0) stop("❌ k_fast vide dans le YAML")

# — table des k régionaux ------------------------------------------------------
k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast       = unlist(par$k_fast) *
                 ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k     # a⁻¹
preserv_fact  <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)  # p_r factor

# — Diagnostics des paramètres --------------------------------------------------
msg_param <- function(nm, val) cat(sprintf("   - %-18s: %s\n", nm, val))

cat("🔧  Paramètres f_i :\n")
msg_param("alpha_dep",       alpha_dep)
msg_param("fast_fraction",   fast_frac)
msg_param("slow_k",          slow_k)
msg_param("preserv_factor",  preserv_fact)

# Stop net si un paramètre requis est NA
stopifnot(!is.na(alpha_dep),
          !is.na(fast_frac),
          !is.na(slow_k),
          !is.na(preserv_fact))

cat("✅ Tous les paramètres sont valides\n\n")

## 1.  Fusion des résultats des tuiles ------------------------------------------
cat("🔄 Fusion des résultats des tuiles...\n")

# Recherche des fichiers de résultats
sar_files <- list.files("~/scratch/output_V6/", pattern="^sar_.*\\.(parquet|rds)$", full.names=TRUE)
if(length(sar_files) == 0) stop("❌ Aucun fichier sar_* trouvé dans ~/scratch/output_V6/")

# Compter les types de fichiers
parquet_count <- sum(grepl("\\.parquet$", sar_files))
rds_count <- sum(grepl("\\.rds$", sar_files))

cat("📁 Fichiers trouvés :", length(sar_files), "(Parquet:", parquet_count, "RDS:", rds_count, ")\n")

# Chargement et fusion
sar_list <- list()
for(i in seq_along(sar_files)) {
  file <- sar_files[i]
  cat("   Chargement :", basename(file), "\n")
  
  if(grepl("\\.parquet$", file)) {
    sar_list[[i]] <- read_parquet(file)
  } else {
    sar_list[[i]] <- readRDS(file)
  }
}

cat("🔄 Assemblage des données...\n")
sar_global <- rbindlist(sar_list, fill=TRUE)
rm(sar_list)
gc()

cat("✅ Fusion terminée :", nrow(sar_global), "cellules uniques\n")

## 2.  Calcul des métriques SAR/SVR --------------------------------------------
cat("🧮 Calcul des métriques SAR/SVR...\n")

# Calcul de l'aire des cellules (1 km²)
cell_area <- 1000 * 1000  # m²

sar_global[, `:=`(
  SAR = sum_dw / cell_area,
  p_d = fifelse(sum_dw == 0, 0, sum_dw_pd / sum_dw)
)]

sar_global[, p_l := fifelse(sum_d == 0, 0, sum_d_pl / sum_d)]

sar_global[, `:=`(
  w1 = fifelse(p_d == 0, 0, pmin(0.05, p_d) / p_d),
  w2 = fifelse(p_d == 0, 0, pmax(p_d - 0.05, 0) / p_d)
)]

sar_global[, p_l_eff := w1 * p_l + w2 * p_l * alpha_dep]

# Nettoyage des colonnes temporaires
sar_global[, c("w1", "w2") := NULL]

cat("✅ Métriques calculées\n")

## 3.  Calcul p_l pondéré ------------------------------------------------------
cat("🗿 Calcul p_l pondéré...\n")

# Calcul SVR (Sediment Volume Rate)
sar_global[, SVR := SAR * p_d / 1]  # profondeur normalisée 1 m

cat("✅ p_l pondéré calculé\n")

## 4.  Provinces Longhurst ------------------------------------------------------
cat("🌊 Chargement des provinces Longhurst...\n")

get_longhurst <- function(){
    # 0️⃣ Recherche LOCALE immédiate (évite tout réseau)
    check_local <- function(){
        # candidat gpkg
        gpkg <- path.expand("~/scratch/configuration/longhurst.gpkg")
        if(file.exists(gpkg)) return(st_read(gpkg, quiet=TRUE))
        # shapefile explicite
        shp_exp <- path.expand("~/scratch/configuration/longhurst/longhurst.shp")
        if(file.exists(shp_exp)) return(st_read(shp_exp, quiet=TRUE))
        # shapefile v4_2010 (prioritaire sur Rorqual)
        shp_v4 <- path.expand("~/scratch/configuration/longhurst_v4_2010/Longhurst_world_v4_2010.shp")
        if(file.exists(shp_v4)) return(st_read(shp_v4, quiet=TRUE))
        # n'importe quel .shp
        shp_any <- list.files(path.expand("~/scratch/configuration/longhurst"),
                              pattern="\\.shp$", full.names=TRUE, recursive = TRUE)
        if(length(shp_any)) return(st_read(shp_any[1], quiet=TRUE))
        NULL
    }
    loc <- check_local(); if(!is.null(loc) && nrow(loc)) return(loc)

    # 1️⃣ Tentative WFS JSON
    wfs <- paste0("https://geo.vliz.be/geoserver/MarineRegions/wfs?",
                  "service=WFS&version=2.0.0&request=GetFeature&",
                  "typeName=MarineRegions:longhurst&outputFormat=application/json")
    ll <- try(suppressWarnings(st_read(wfs, quiet=TRUE)), silent=TRUE)
    if(!inherits(ll, "try-error") && nrow(ll)) return(ll)

    # 2️⃣ Téléchargement du ZIP puis unzip sécurisé
    tmp <- tempfile(fileext=".zip")
    url <- "https://www.marineregions.org/downloads.php?data=longhurst&format=shp"
    safe_download <- function(u, d){
        ok <- try(download.file(u, d, mode="wb", quiet=TRUE), silent=TRUE)
        if(inherits(ok, "try-error")){
            ok <- try(download.file(u, d, mode="wb", quiet=TRUE, method="curl", extra="-k -L"), silent=TRUE)
        }
        !inherits(ok, "try-error") && file.exists(d) && file.info(d)$size>1e5
    }
    if(safe_download(url, tmp)){
        unz_ok <- try(unzip(tmp, exdir = d <- tempfile()), silent=TRUE)
        if(!inherits(unz_ok, "try-error")){
            shp <- list.files(d, "\\.shp$", full.names=TRUE)[1]
            if(length(shp)) return(st_read(shp, quiet=TRUE))
        }
    }

    # 3️⃣ Dernière tentative : rechecker local (au cas où l'utilisateur copie après coup)
    loc <- check_local(); if(!is.null(loc) && nrow(loc)) return(loc)

    stop("❌ Provinces Longhurst introuvables : ni WFS, ni ZIP, ni fichier local.")
}

longhurst <- try(get_longhurst(), silent=TRUE)
if(inherits(longhurst,"try-error") || !nrow(longhurst)){
  tmp<-tempfile(fileext=".zip")
  download.file("https://www.marineregions.org/downloads.php?data=longhurst&format=shp",
                tmp, mode="wb", quiet=TRUE)
  unzip(tmp, exdir=d<-dirname(tmp))
  longhurst <- st_read(list.files(d,"\\.shp$",full.names=TRUE)[1], quiet=TRUE)
}
longhurst <- st_transform(longhurst,6933)

# Après avoir obtenu 'longhurst' et transformé en 6933, remplacer la détection desc par code
code_col <- grep("code$", names(longhurst), value = TRUE, ignore.case = TRUE)[1]
if(is.na(code_col) || code_col == "") stop("Champ code Longhurst introuvable dans le shapefile")
longhurst <- dplyr::rename(longhurst, longhurst_pr = !!sym(code_col))

# Joindre k_fast via le code
longhurst <- dplyr::left_join(longhurst, k_table, by = "longhurst_pr")

cat("✅ Provinces Longhurst chargées\n")

# — Diagnostics de couverture k_fast --------------------------------------------
prov_in_yaml  <- unique(k_table$longhurst_pr)
prov_in_data  <- unique(longhurst$longhurst_pr)

missing_yaml  <- setdiff(prov_in_data, prov_in_yaml)   # provinces sans k_fast
unused_yaml   <- setdiff(prov_in_yaml, prov_in_data)   # clés YAML jamais vues

cat("\n🔍 Couverture k_fast\n")
cat("   Provinces Longhurst sans k_fast :", length(missing_yaml), "\n")
if(length(missing_yaml))  cat("   →", paste(missing_yaml, collapse=", "), "\n")
cat("   Clés YAML non rencontrées       :", length(unused_yaml), "\n")
if(length(unused_yaml))   cat("   →", paste(unused_yaml, collapse=", "), "\n")

# Avertir sur les clés YAML non utilisées
if (length(unused_yaml)) warning("⚠️  Clés YAML non utilisées : ", paste(unused_yaml, collapse=", "))

## 5.  Jointure spatiale et calcul f_i -----------------------------------------
cat("🧮 Calcul f_i final...\n")

# Création des centroïdes des cellules pour la jointure spatiale
grid_cent <- data.table(grid_id = as.numeric(sar_global$grid_id))

# Calcul des coordonnées, en deux temps pour éviter les références internes dans data.table
grid_cent[, `:=`(
  col = (grid_id-1L) %% 36000L,
  row = (grid_id-1L) %/% 36000L
)]
grid_cent[, `:=`(
  x   = -18000000 + col*1000 + 500,
  y   =  9000000 - row*1000 - 500
)]

sf_cent <- st_as_sf(grid_cent, coords = c("x","y"), crs = 6933)

# Jointure avec Longhurst
fi_dt <- as.data.table(st_join(sf_cent, longhurst, left=TRUE))[, geometry:=NULL]

# Fusion avec les données SAR
fi_dt <- merge(fi_dt, sar_global, by="grid_id", all.x=TRUE)

# Charger le facteur de fraîcheur depuis le YAML
fresh_fact_table <- data.table(
  longhurst_pr = names(par$fresh_fact),
  fresh_fact = unlist(par$fresh_fact)
)

# Jointure avec le facteur de fraîcheur
fi_dt <- merge(fi_dt, fresh_fact_table, by="longhurst_pr", all.x=TRUE)

# Valeur par défaut si province non trouvée
fi_dt[is.na(fresh_fact), fresh_fact := 1.0]

# Calcul f_i final (en 2 étapes pour data.table)
# 1. Calcul des facteurs intermédiaires
fi_dt[, `:=`(
  k_used = coalesce(k_fast, 1.0),  # secours si province manquante
  p_l_corr = p_l_eff * fresh_fact  # Application du facteur de fraîcheur
)]

# 2. Calcul des indices f_i avec les colonnes créées
fi_dt[, `:=`(
  f_i_full = SVR * p_l_corr * preserv_fact *
             ( fast_frac * (1 - exp(-k_used)) +
               (1 - fast_frac) * (1 - exp(-slow_k)) ),
  
  # Cas conservateur : p_l_corr et tous les k sont divisés par deux
  f_i_conservative = SVR * (p_l_corr / 2) * preserv_fact *
                ( fast_frac * (1 - exp(-k_used / 2)) +
                  (1 - fast_frac) * (1 - exp(-slow_k / 2)) )
)]

cat("✅ f_i calculé\n")

# — Diagnostics sur k_used et statistiques --------------------------------------
fi_dt[, is_fallback := (k_used == 1.0 & !is.na(SVR) & SVR > 0)]
nb_fallback <- fi_dt[, sum(is_fallback, na.rm=TRUE)]
nb_active   <- fi_dt[, sum(SVR > 0, na.rm=TRUE)]

# Éviter la division par zéro
if (nb_active == 0) nb_active <- 1

cat(sprintf("   Cellules avec k_used=1 (fallback) : %d / %d  (%.1f%%)\n",
            nb_fallback, nb_active,
            100*nb_fallback/nb_active))

# Avertissement ou arrêt si trop élevé
if (nb_fallback / nb_active > 0.05) {        # seuil 5 % à ajuster
  warning("⚠️  Plus de 5 % des cellules utilisent le k_fast de secours (1.0)")
  # stop("Trop de fallback k_fast")          # si tu veux forcer la correction
}

cat(sprintf("   Part de cellules SVR==0        : %.1f %%\n",
            100*mean(fi_dt$SVR==0, na.rm=TRUE)))
cat(sprintf("   Part de cellules p_l_eff==0    : %.1f %%\n",
            100*mean(fi_dt$p_l_eff==0, na.rm=TRUE)))
cat(sprintf("   Part de cellules f_i_full==NA  : %.1f %%\n",
            100*mean(is.na(fi_dt$f_i_full))))

## 6.  Sauvegarde finale --------------------------------------------------------
cat("💾 Sauvegarde finale...\n")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Sauvegarde en Parquet (compact)
out_parquet <- sprintf("~/scratch/output_V6/fi_grid_%s.parquet", timestamp)
write_parquet(fi_dt, out_parquet)
cat("✅ Résultats sauvegardés en Parquet :", basename(out_parquet), "\n")

# Sauvegarde en RDS (complet)
out_rds <- sprintf("~/scratch/output_V6/fi_grid_%s.rds", timestamp)
saveRDS(fi_dt, out_rds)
cat("✅ Résultats sauvegardés en RDS :", basename(out_rds), "\n")

## 7.  Création du raster GeoTIFF (OPTIONNEL) ----------------------------------
# Option pour éviter le problème de mémoire
CREATE_GEOTIFF <- TRUE  # Mettre FALSE pour désactiver

if(CREATE_GEOTIFF) {
  cat("🗺️  Création du raster GeoTIFF (mode vectorisé)...\n")
  
  tryCatch({
    # Préparer les données pour le raster
    raster_data <- fi_dt[, .(grid_id, f_i_full)]
    raster_data <- raster_data[!is.na(f_i_full)]
    
    if(nrow(raster_data) > 0) {
      # Calculer les coordonnées row/col
      raster_data[, `:=`(
        col = (grid_id-1L) %% 36000L,
        row = (grid_id-1L) %/% 36000L
      )]
      
      # Créer le raster principal (une seule couche nommée)
      r <- rast(
        nrows = 18000, ncols = 36000,
        xmin = -18000000, xmax = 18000000,
        ymin = -9000000, ymax = 9000000,
        crs = "EPSG:6933"
      )
      names(r) <- "f_i_full"
      
      # Initialiser toutes les valeurs à NA
      vals <- rep(NA_real_, ncell(r))
      
      # Calculer les indices linéaires à remplir
      # index = (row) * ncol(r) + col + 1
      inds <- raster_data$row * ncol(r) + raster_data$col + 1L
      
      # Affecter les valeurs dans le raster
      vals[inds] <- raster_data$f_i_full
      
      # Injecter dans le raster
      values(r) <- vals
      
      # Sauvegarder le raster avec compression LZW (rapide et compatible QGIS)
      out_tif <- sprintf("~/scratch/output_V6/fi_grid_%s.tif", timestamp)
      writeRaster(
        r, out_tif,
        datatype = "FLT4S",
        overwrite = TRUE,
        wopt = list(
          compression = "LZW",
          tiled = TRUE,
          chunksize = c(5000, 5000)
        )
      )
      
      cat("✅ Raster GeoTIFF créé :", basename(out_tif), "\n")
      cat("📊 Statistiques raster :", nrow(raster_data), "cellules non-NA sur", ncell(r), "pixels\n")
    } else {
      cat("⚠️  Aucune donnée f_i valide pour créer le raster\n")
    }
  }, error = function(e) {
    cat("⚠️  Échec de création du raster GeoTIFF :", e$message, "\n")
    cat("   Les fichiers Parquet et RDS sont disponibles\n")
  })
} else {
  cat("⏭️  Création du raster GeoTIFF désactivée\n")
}

cat("\n🎉 Step 5 terminé avec succès !\n")
cat("📁 Fichiers créés :\n")
cat("   -", basename(out_parquet), "\n")
cat("   -", basename(out_rds), "\n")
if(CREATE_GEOTIFF) cat("   -", sprintf("fi_grid_%s.tif", timestamp), "\n") 