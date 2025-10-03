#!/usr/bin/env Rscript
# ====================================================================
# ÉTAPE 2: TRAITEMENT NAVIRE INDIVIDUEL (ARRAY JOB)
# ====================================================================

cat("🔄 === TRAITEMENT NAVIRE INDIVIDUEL ===\n")
cat("Début:", format(Sys.time()), "\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
.libPaths("~/R/4.3")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")

# ---- CONFIGURATION ANTI-GFORCE ----
options(mc.cores = 1)
Sys.setenv(MC_CORES = 1)
Sys.setenv(DT_GForce = "FALSE")  # CRITIQUE: désactive gforce
Sys.setenv(OMP_NUM_THREADS = 1)

# ---- CHARGEMENT PACKAGES ----
suppressPackageStartupMessages({
  library(data.table)
  
  # Test qs avec fallback (comme step1)
  use_qs <- FALSE
  tryCatch({
    if (requireNamespace("qs", quietly = TRUE)) {
      library(qs)
      use_qs <- TRUE
      cat("✅ Package qs disponible\n")
    }
  }, error = function(e) {
    cat("⚠️ Package qs non disponible - fallback RDS\n")
  })
  
  library(lubridate)
  library(yaml)
  library(solitude)   # Isolation Forest
  library(mclust)     # GMM
  library(zoo)        # rollmean
})

# Configuration data.table conservative
setDTthreads(1)  # Mono-thread obligatoire
options(datatable.optimize = 1)

cat("✅ Packages chargés - Configuration mono-thread activée\n")

# ---- PARAMÈTRES ENVIRONNEMENT ----
task_id <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID"))
split_job_id <- Sys.getenv("SPLIT_JOB_ID")

cat("📋 Task ID:", task_id, "\n")
cat("📋 Split Job ID:", split_job_id, "\n")

# ---- CHEMINS FICHIERS ----
split_dir <- file.path("~/scratch", paste0("ais_split_", split_job_id))
metadata_file <- file.path(split_dir, "navires_metadata.csv")

if (!file.exists(metadata_file)) {
  stop("❌ Métadonnées introuvables: ", metadata_file)
}

# Lecture métadonnées
metadata <- fread(metadata_file)
cat("📊 Métadonnées chargées:", nrow(metadata), "navires\n")

if (task_id > nrow(metadata)) {
  stop("❌ Task ID ", task_id, " > nombre navires ", nrow(metadata))
}

# ---- SÉLECTION NAVIRE ----
navire_info <- metadata[task_id]
input_file <- navire_info$file_path
navire_name <- navire_info$Navire

cat("🚢 Navire sélectionné:", navire_name, "\n")
cat("📁 Fichier input:", input_file, "\n")

if (!file.exists(input_file)) {
  stop("❌ Fichier navire introuvable: ", input_file)
}

# ---- CHARGEMENT DONNÉES NAVIRE ----
cat("📖 Chargement données navire...\n")
system.time({
  # Détection automatique du format (qs ou rds)
  if (grepl("\\.qs$", input_file)) {
    # Format QS
    dt_nav <- qs::qread(input_file, as.data.table = TRUE)
    cat("✅ Format QS détecté et chargé\n")
  } else if (grepl("\\.rds$", input_file)) {
    # Format RDS
    dt_nav <- readRDS(input_file)
    setDT(dt_nav)  # S'assurer que c'est un data.table
    cat("✅ Format RDS détecté et chargé\n")
  } else {
    stop("❌ Format de fichier non reconnu: ", input_file)
  }
})

# Harmoniser le type de ssvid (character partout)
if ("ssvid" %in% names(dt_nav)) dt_nav[, ssvid := as.character(ssvid)]

cat("✅ Données chargées:", nrow(dt_nav), "observations\n")

# ------------------------------------------------------------------
# LECTURE DES SPÉCIFICATIONS NAVIRES
# ------------------------------------------------------------------
spec_file <- "~/R_scripts/configuration/ship_specs.yaml"
if (!file.exists(spec_file))
  stop("❌ ship_specs.yaml introuvable : ", spec_file)

spec_list  <- yaml::read_yaml(spec_file)$ship_specs
ship_specs <- rbindlist(spec_list, fill = TRUE)

## --- correctif BEGIN ------------------------------------------------
# 1) harmoniser le type
ship_specs[, ssvid := as.character(ssvid)]

# 2) garder la première ligne de chaque ssvid (élimine les doublons)
#    unique(..., by="ssvid") fonctionne à partir de data.table 1.14.4 ;
#    sinon .SD[1] est universel.
ship_specs <- ship_specs[, .SD[1], by = ssvid]
## --- correctif END --------------------------------------------------

# mise en forme
setnames(ship_specs, "service_speed_kn", "Service_speed")
setkey(ship_specs, ssvid)

# (2) Conversion explicite juste après la fusion
if ("ssvid" %chin% names(dt_nav)) {
  # (SUPPRIMÉ) dt_nav[, ssvid := as.integer(ssvid)]
  dt_nav <- merge(dt_nav, ship_specs[, .(ssvid, Service_speed, dredge_width_m, dredging_depth_m)],
                  by = "ssvid", all.x = TRUE)
  dt_nav[, Service_speed := as.numeric(Service_speed)]
  # CORRECTION: S'assurer que les specs sont numériques
  dt_nav[, `:=`(dredge_width_m = as.numeric(dredge_width_m),
                dredging_depth_m = as.numeric(dredging_depth_m))]
  # CORRECTION: Fixer la clé pour accélérer les opérations
  setkey(dt_nav, ssvid)
} else {
  warning("Colonne ssvid manquante : fusion specs impossible")
}

# (4) Warning si Service_speed totalement manquante
if (!"Service_speed" %chin% names(dt_nav) || all(is.na(dt_nav$Service_speed))) {
  warning("Aucune vitesse de service pour ", navire_name)
}

# -----------------------------------------------------------------
# FILTRE PHYSIQUE VITESSE MAXI (service_speed × 1.15)
# -----------------------------------------------------------------
if ("Service_speed" %chin% names(dt_nav)) {
  dt_nav[, speed_limit := Service_speed * 1.15]
  n_before <- nrow(dt_nav)
  dt_nav   <- dt_nav[is.na(speed_limit) | Speed <= speed_limit]
  n_after  <- nrow(dt_nav)
  cat(sprintf("✅ Filtre vitesse physique : %d → %d lignes (%.2f %% conservées)\n",
              n_before, n_after, 100 * n_after / n_before))
  dt_nav[, speed_limit := NULL]
  # (3) CONSERVATION des spécifications pour l'étape 3
  # dt_nav[, Service_speed := NULL]  # CONSERVÉ pour l'étape 3
}

# (1) Calcul des dérivées juste avant l'Isolation Forest
setorder(dt_nav, Timestamp)
dt_nav[, delta_t       := c(NA_real_, diff(as.numeric(Timestamp)))]
dt_nav[, Course_change := c(NA_real_, abs(diff(Course)))]
dt_nav[Course_change > 180, Course_change := 360 - Course_change]
dt_nav[, Accel         := c(NA_real_, diff(Speed))]

# ---- CHARGEMENT CONFIGURATION ----
config_file <- "~/R_scripts/configuration/outlier_config_V6.yaml"
if (file.exists(config_file)) {
  config <- yaml.load_file(config_file)
  # Utiliser les paramètres de la section isolation_forest
  outlier_config <- list(
    contamination_rate = config$isolation_forest$contamination_rate,
    if_sample_size = config$isolation_forest$sample_size,
    if_num_trees = config$isolation_forest$num_trees,
    memory_conservative = TRUE
  )
  cat("✅ Configuration chargée:", config_file, "\n")
} else {
  # Configuration par défaut ultra-conservative
  outlier_config <- list(
    contamination_rate = 0.02,
    if_sample_size = 256,
    if_num_trees = 25,
    memory_conservative = TRUE
  )
  cat("⚠️ Configuration par défaut appliquée\n")
}

cat("🔧 Paramètres IF: contamination =", outlier_config$contamination_rate, 
    "| trees =", outlier_config$if_num_trees, "\n")

# ---- FONCTIONS ISOLATION FOREST OPTIMISÉES ----
detect_outliers_IF_optimized <- function(dt, config) {
  cat("  🌲 Début Isolation Forest...\n")
  
  # Préparation features (basique pour un navire)
 features <- c("Lat", "Lon") 
  if ("delta_t" %in% names(dt)) features <- c(features, "delta_t")
  if ("Speed" %in% names(dt)) features <- c(features, "Speed")
  
  # Extraction données numériques
  dt_features <- dt[, ..features]
  dt_features <- dt_features[complete.cases(dt_features)]
  
  if (nrow(dt_features) < 50) {
    cat("  ⚠️ Trop peu de données (", nrow(dt_features), ") - pas d'IF\n")
    return(rep(FALSE, nrow(dt)))
  }
  
  # Isolation Forest avec paramètres conservateurs
  if_model <- isolationForest$new(
    sample_size = min(config$if_sample_size, nrow(dt_features)),
    num_trees = config$if_num_trees,
    seed = 42
  )
  
  if_model$fit(dt_features)
  
  # Prédiction
  scores <- if_model$predict(dt_features)
  outliers <- scores$anomaly_score > quantile(scores$anomaly_score, 
                                             1 - config$contamination_rate)
  
  # Alignement avec données originales
  result <- rep(FALSE, nrow(dt))
  if (nrow(dt_features) == nrow(dt)) {
    result <- outliers
  } else {
    # Cas où il y a des NA - alignement par index
    complete_idx <- which(complete.cases(dt[, ..features]))
    result[complete_idx] <- outliers
  }
  
  cat("  ✅ IF terminé:", sum(result), "outliers sur", nrow(dt), "points\n")
  return(result)
}

# ---- TRAITEMENT PRINCIPAL ----
cat("🚀 Début traitement Isolation Forest...\n")
system.time({
  dt_nav[, outlier_IF := detect_outliers_IF_optimized(dt_nav, outlier_config)]
})

# ---- CRÉATION DE LA COLONNE is_stop (NÉCESSAIRE POUR STEP 3) ----
cat("🛑 Création de la colonne is_stop...\n")

# Tri par timestamp pour calculs temporels
setorder(dt_nav, Timestamp)

# delta_t déjà calculé plus haut, pas besoin de le recalculer

# Détection des arrêts basée sur la vitesse et les intervalles temporels
# Un arrêt = vitesse < 1 nœud OU intervalle > 5 minutes
dt_nav[, is_stop := (Speed < 1) | (delta_t > 300)]

# Nettoyage des valeurs NA
dt_nav[is.na(is_stop), is_stop := FALSE]

cat("✅ Colonne is_stop créée:", sum(dt_nav$is_stop), "arrêts détectés\n")

# ---- CRÉATION DE COLONNES SUPPLÉMENTAIRES (UTILES POUR STEP 3) ----
cat("🔧 Création de colonnes supplémentaires...\n")

# Ajout de l'année
dt_nav[, Annee := year(Timestamp)]

# Course_change et Accel déjà calculés plus haut, pas besoin de les recalculer

cat("✅ Colonnes supplémentaires créées (Annee, Course_change, Accel)\n")

# ---- STATISTIQUES ----
n_outliers <- sum(dt_nav$outlier_IF)
outlier_rate <- round(n_outliers / nrow(dt_nav) * 100, 2)
n_stops <- sum(dt_nav$is_stop)
stop_rate <- round(n_stops / nrow(dt_nav) * 100, 2)

cat("📊 RÉSULTATS NAVIRE:", navire_name, "\n")
cat("  • Observations totales:", nrow(dt_nav), "\n")
cat("  • Outliers détectés:", n_outliers, "(", outlier_rate, "%)\n")
cat("  • Arrêts détectés:", n_stops, "(", stop_rate, "%)\n")

# ---- SAUVEGARDE ----
# Utiliser le dossier de sortie défini dans le script bash
output_dir <- file.path("~/scratch", paste0("ais_results_", Sys.getenv("SLURM_ARRAY_JOB_ID")))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Nom du fichier de sortie
safe_name <- gsub("[^A-Za-z0-9_-]", "_", navire_name)
output_file <- file.path(output_dir, sprintf("%02d_%s_clean.rds", task_id, safe_name))

cat("💾 Sauvegarde:", output_file, "\n")

system.time({
  saveRDS(dt_nav, output_file, compress = "xz")
})

# ---- NETTOYAGE MÉMOIRE ----
if (exists("if_model")) rm(if_model)
rm(dt_nav)
gc()

cat("✅ Navire", navire_name, "traité avec succès:", format(Sys.time()), "\n")
cat("📁 Résultat:", output_file, "\n") 