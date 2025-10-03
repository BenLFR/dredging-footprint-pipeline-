#!/usr/bin/env Rscript
# =====================================================================
# STEP 1 ─ FRACTIONNEMENT AIS PAR NAVIRE  (pipeline V6, cluster Béluga)
# Utilise la période et la flotte sélectionnées par step0_core_window.R (core_window.yaml)
# =====================================================================

cat("\n🚀  STEP-1  |  FRACTIONNEMENT AIS PAR NAVIRE  |  début :",
    format(Sys.time()), "\n\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
.libPaths("/home/benl/R/library")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")

suppressPackageStartupMessages({
  library(data.table)   # ultra-rapide + faible RAM
  library(yaml)         # lecture configuration step 0
  # library(fst)          # ❌ REMPLACÉ par qs (problème GLIBC)
  
  # Test qs avec fallback RDS (selon README_BELUGA.md - packages déjà installés)
  use_qs <- FALSE
  tryCatch({
    if (!requireNamespace("qs", quietly = TRUE))
      stop("qs non disponible")
    library(qs)           
    use_qs <- TRUE
    cat("✅ Utilisation du format QS\n")
  }, error = function(e) {
    cat("⚠️ QS non disponible, fallback vers RDS\n")
    use_qs <<- FALSE
  })
  
  library(lubridate)    # parsers dates robustes
  library(tools)        # pour file_ext
})

# ---------------------------------------------------------------------
# 1. ── PARAMÈTRES (adaptables via variables d'environnement) ----------
# ---------------------------------------------------------------------
job_id        <- Sys.getenv("SLURM_JOB_ID",        unset = format(Sys.time(), "%Y%m%d%H%M%S"))
input_pattern <- Sys.getenv("AIS_INPUT_PATTERN",   unset = "~/scratch/AIS_data/*.csv")
output_dir    <- Sys.getenv("AIS_OUTPUT_DIR",      unset = file.path("~/scratch", paste0("ais_split_", job_id)))
core_config_path <- Sys.getenv("CORE_CONFIG_PATH", unset = "~/scratch/output_V6/core_window.yaml")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("📁  INPUT  : ", input_pattern, "\n")
cat("📁  OUTPUT : ", output_dir,     "\n")
cat("📋  CONFIG : ", core_config_path, "\n\n")

# ---------------------------------------------------------------------
# 1.b ── LECTURE CONFIGURATION STEP 0  ----------------------------------
# ---------------------------------------------------------------------
if (file.exists(core_config_path)) {
  cat("🔍  Lecture configuration step 0...\n")
  core_config <- read_yaml(core_config_path)
  
  start_year <- core_config$start_year
  end_year   <- core_config$end_year
  core_ships <- core_config$core_ships
  
  cat("📅  Fenêtre temporelle :", start_year, "-", end_year, "\n")
  cat("🚢  Navires sélectionnés :", length(core_ships), "\n")
  cat("   •", paste(core_ships, collapse = ", "), "\n\n")
  
  # Validation des paramètres
  if (is.null(start_year) || is.null(end_year) || is.null(core_ships)) {
    stop("❌  Configuration step 0 incomplète dans", core_config_path)
  }
  
  use_core_filter <- TRUE
} else {
  cat("⚠️  Configuration step 0 non trouvée, traitement complet des données\n")
  use_core_filter <- FALSE
  start_year <- NULL
  end_year <- NULL
  core_ships <- NULL
}

# ---------------------------------------------------------------------
# 2. ── MAPPING MMSI → NOM NAVIRE  ------------------------------------
# ---------------------------------------------------------------------
# Note: Vasco Da Gama a eu deux MMSI : 253193000 (Luxembourg, 2013-2019) et 205744000 (Belgique, 2018-2024)
# On fusionne vers le MMSI le plus récent : 205744000
# Note: Goryo 6 Ho (312062000) exclu - données corrompues
mmsi_map <- data.table(
  ssvid = as.character(c(209469000, 210138000, 245508000, 246351000,
            253193000, 205744000, 253373000, 253403000, 253422000,
            253688000, 533180137)),
  Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318",
             "Vox Maxima", "Vasco Da Gama", "Vasco Da Gama", "Cristobal Colon",
             "Leiv Eiriksson", "Charles Darwin", "Congo River",
             "Inai Kenanga"),
  # MMSI de référence (le plus récent pour Vasco Da Gama)
  ssvid_ref = as.character(c(209469000, 210138000, 245508000, 246351000,
                205744000, 205744000, 253373000, 253403000, 253422000,
                253688000, 533180137))
)
setkey(mmsi_map, ssvid)

# Vérification des types
stopifnot(is.character(mmsi_map$ssvid))
stopifnot(is.character(mmsi_map$ssvid_ref))

# ---------------------------------------------------------------------
# 2.b ── MAPPING ALIAS → NOM CANONIQUE  --------------------------------
# ---------------------------------------------------------------------
# Gestion des différences de noms entre CSV et configuration step 0
alias_map <- data.table(
  alias = c("Ham 318 Sleephopperzuiger", "HAM318",
            "Queen of the netherlands", "Queen Of The Netherlands",
            "Vasco de Gama", "Vasco Da Gama",
            "LEIV EIRIKSSONN", "Leiv Eiriksson",
            "INAI KENANGA", "Inai Kenanga",
            "Goryo 6 HO", "Goryo 6 Ho",
            "Fair Way", "Fairway",
            "VOX maxima", "Vox Maxima"),
  canonical = c("Ham 318", "Ham 318",
                "Queen Of The Netherlands", "Queen Of The Netherlands", 
                "Vasco Da Gama", "Vasco Da Gama",
                "Leiv Eiriksson", "Leiv Eiriksson",
                "Inai Kenanga", "Inai Kenanga", 
                "Goryo 6 Ho", "Goryo 6 Ho",
                "Fairway", "Fairway",
                "Vox Maxima", "Vox Maxima")
)
setkey(alias_map, alias)

# ---------------------------------------------------------------------
# 3. ── LECTURE DES DONNÉES (CSV ou RDS)  ------------------------------
# ---------------------------------------------------------------------
# Priorité à un fichier d'entrée unique (RDS/CSV) via la variable d'environnement
# AIS_INPUT_FILE. Sinon, fallback vers le pattern de CSV.

input_file <- Sys.getenv("AIS_INPUT_FILE", unset = "")

t_read <- system.time({
  if (input_file != "" && file.exists(input_file)) {
    cat("🔍  Lecture du fichier d'entrée via AIS_INPUT_FILE:", input_file, "\n")
    
    # Détection de l'extension pour choisir la bonne fonction de lecture
    file_ext <- tolower(tools::file_ext(input_file))
    
    if (file_ext == "rds") {
      ais_dt <- as.data.table(readRDS(input_file))
    } else if (file_ext == "csv") {
      ais_dt <- fread(input_file, showProgress = FALSE)
    } else {
      stop("❌ Format de fichier non supporté pour AIS_INPUT_FILE : ", file_ext)
    }
    
  } else {
    cat("🔍  AIS_INPUT_FILE non fourni ou non trouvé. Utilisation du pattern CSV :", input_pattern, "\n")
    csv_files <- Sys.glob(input_pattern)
    
    if (length(csv_files) == 0) stop("❌ Aucun fichier CSV trouvé pour le pattern : ", input_pattern)
    if (length(csv_files) > 1) cat("⚠️  Plusieurs fichiers CSV détectés. Traitement du premier uniquement :", basename(csv_files[1]), "\n")
    
    cat("   • Lecture de :", basename(csv_files[1]), "\n")
    ais_dt <- fread(csv_files[1], showProgress = FALSE)
  }
})
cat(sprintf("✅  Lecture terminée : %s lignes  |  %.1f s\n",
            format(nrow(ais_dt), big.mark = " "), t_read[3]))

# ---------------------------------------------------------------------
# 4. ── NORMALISATION COLONNES  ---------------------------------------
# ---------------------------------------------------------------------
# a) noms minuscules
setnames(ais_dt, tolower(names(ais_dt)))

# b) dictionnaire de renommage minimal
rename_map <- c(lon="Lon", lat="Lat", course="Course", timestamp="Timestamp",
                speed="Speed", speed_knots="Speed", seg_id="Seg_id",
                trip_id="Seg_id", navire="Navire")
common <- intersect(names(rename_map), names(ais_dt))
setnames(ais_dt, common, rename_map[common])

# c) coercions vitales
num_cols <- c("Lon","Lat","Speed")
for (cl in intersect(num_cols, names(ais_dt))) set(ais_dt, j = cl, value = as.numeric(ais_dt[[cl]]))
if ("Timestamp" %chin% names(ais_dt))
  ais_dt[, Timestamp := as.POSIXct(Timestamp, tz = "UTC")]

# ---------------------------------------------------------------------
# 5. ── CRÉATION / VALIDATION DE LA COLONNE NAVIRE  --------------------
# ---------------------------------------------------------------------
if (!"Navire" %in% names(ais_dt)) ais_dt[, Navire := NA_character_]

# Si des ssvid sont présents, on complète les noms manquants
if ("ssvid" %chin% names(ais_dt)) {
  # Conversion du type ssvid pour compatibilité
  ais_dt[, ssvid := as.character(ssvid)]
  ais_dt <- merge(ais_dt, mmsi_map, by = "ssvid", all.x = TRUE, suffixes = c("", ".map"))
  
  # Fusion des MMSI multiples vers le MMSI de référence (cas Vasco Da Gama)
  ais_dt[!is.na(ssvid_ref), ssvid := ssvid_ref]
  ais_dt[, ssvid_ref := NULL]  # nettoyer la colonne temporaire
  
  ais_dt[is.na(Navire), Navire := Navire.map]
  ais_dt[, Navire.map := NULL]
}

# fallback ultime : nom générique
ais_dt[is.na(Navire) | Navire == "", Navire := paste0("unknown_", .GRP), by = ssvid]

# ---------------------------------------------------------------------
# 5.a ── NORMALISATION DES NOMS VIA ALIAS  ----------------------------
# ---------------------------------------------------------------------
# Application du mapping d'alias pour harmoniser les noms avec step 0
if (use_core_filter) {
  cat("🔍  Normalisation des noms de navires...\n")
  
  tryCatch({
    # Comptage avant normalisation
    noms_avant <- unique(ais_dt$Navire)
    cat("   • Noms avant normalisation :", paste(noms_avant, collapse = ", "), "\n")
    
    # Application du mapping d'alias (version sécurisée)
    ais_dt <- merge(ais_dt, alias_map, by.x = "Navire", by.y = "alias", all.x = TRUE)
    
    # Remplacer les noms qui ont un alias canonique
    ais_dt[!is.na(canonical), Navire := canonical]
    
    # Supprimer la colonne temporaire
    if ("canonical" %in% names(ais_dt)) {
      ais_dt[, canonical := NULL]
    }
    
    # Comptage après normalisation
    noms_apres <- unique(ais_dt$Navire)
    cat("   • Noms après normalisation :", paste(noms_apres, collapse = ", "), "\n")
    
    if (length(noms_avant) != length(noms_apres)) {
      cat("✅  Normalisation :", length(noms_avant), "→", length(noms_apres), "noms uniques\n")
    } else {
      cat("ℹ️  Aucun changement de noms nécessaire\n")
    }
  }, error = function(e) {
    cat("❌  Erreur lors de la normalisation :", e$message, "\n")
    cat("   • Colonnes disponibles :", paste(names(ais_dt), collapse = ", "), "\n")
    cat("   • Taille alias_map :", nrow(alias_map), "lignes\n")
    stop(e)
  })
}

# ---------------------------------------------------------------------
# 5.b ── FILTRAGE SELON CONFIGURATION STEP 0  ---------------------------
# ---------------------------------------------------------------------
if (use_core_filter) {
  cat("🔍  Application des filtres step 0...\n")
  
  # Ajout de la colonne année pour le filtrage temporel
  ais_dt[, Annee := year(Timestamp)]
  
  # Filtrage : navires ET période
  n_before <- nrow(ais_dt)
  ais_dt <- ais_dt[Navire %in% core_ships & Annee >= start_year & Annee <= end_year]
  n_after <- nrow(ais_dt)
  
  cat(sprintf("📊  Filtrage : %s → %s lignes (%.1f%% conservées)\n",
              format(n_before, big.mark = " "),
              format(n_after, big.mark = " "),
              round(100 * n_after / n_before, 1)))
  
  # Vérification que tous les navires demandés sont présents
  navires_presents <- unique(ais_dt$Navire)
  navires_manquants <- setdiff(core_ships, navires_presents)
  
  if (length(navires_manquants) > 0) {
    cat("⚠️  Navires manquants dans la fenêtre :", paste(navires_manquants, collapse = ", "), "\n")
  }
  
  cat("✅  Filtrage terminé\n\n")
} else {
  cat("ℹ️  Aucun filtre appliqué (traitement complet)\n\n")
}

# ---------------------------------------------------------------------
# 6. ── FRACTIONNEMENT PAR NAVIRE  ------------------------------------
# ---------------------------------------------------------------------
# ordre stable : size desc pour visualiser la progression
navires <- ais_dt[, .N, by = Navire][order(-N)]
cat("🚢  Navires détectés :", navires[,.N], "\n\n")

meta <- navires[, `:=`(file_path = character(.N), split_time = Sys.time())]

pb <- txtProgressBar(min = 0, max = nrow(navires), style = 3)
i <- 0

for (nav in navires$Navire) {
  i <- i + 1
  dt_nav <- ais_dt[Navire == nav]

  safe_name <- gsub("[^A-Za-z0-9_-]", "_", nav)
  
  if (use_qs) {
    # Format QS (optimal)
    out_file  <- file.path(output_dir,
                           sprintf("navire_%02d_%s.qs", i, safe_name))
    qs::qsave(dt_nav, out_file, preset = "custom",
              algorithm = "zstd",         # rapide & bon ratio
              preset_compression = 6)     # ~ équiv. fst compress=85
  } else {
    # Format RDS fallback
  out_file  <- file.path(output_dir,
                           sprintf("navire_%02d_%s.rds", i, safe_name))
    saveRDS(dt_nav, out_file, compress = "xz")
  }

  meta[Navire == nav, `:=`(file_path = out_file,
                           n_observations = nrow(dt_nav))]
  rm(dt_nav); gc(verbose = FALSE)
  setTxtProgressBar(pb, i)
}
close(pb)

# ---------------------------------------------------------------------
# 7. ── EXPORT MÉTADONNÉES & CONTRÔLE INTÉGRITÉ  ----------------------
# ---------------------------------------------------------------------
meta_file <- file.path(output_dir, "navires_metadata.csv")
fwrite(meta, meta_file)

if (sum(meta$n_observations) != nrow(ais_dt))
  stop("❌  Intégrité KO : nombre de lignes différent après split !")
cat("\n✅  Intégrité OK : ", sum(meta$n_observations), " lignes vérifiées.\n")

# ---------------------------------------------------------------------
# 8. ── RÉCAPITULATIF --------------------------------------------------
# ---------------------------------------------------------------------
cat("\n📊  RÉCAP ---------------------------------------------------------\n")
print(meta[, .(Navire, n_observations, file_path)])

total_size <- sum(file.info(meta$file_path)$size) / 1024^2
format_used <- if(use_qs) "qs" else "rds"
cat(sprintf("\n💾  %d fichiers .%s (%.1f MB cumulés) écrits dans : %s\n",
            nrow(meta), format_used, total_size, output_dir))

cat("\n🏁  STEP-1 terminé avec succès :", format(Sys.time()), "\n")
