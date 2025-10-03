#!/usr/bin/env Rscript
# ============================================================================
# STEP-3  ─  FUSION  +  NETTOYAGE  +  GMM / GRID-SEARCH   (pipeline  V6)
#   • S'exécute sur un gros nœud (≥ 8 CPU, 32 Go RAM)
#   • Ré-assemble tous les *_clean.rds produits à Step-2
#   • Termine le pipeline : pics isolés, context percentiles, DBSCAN,
#     stop-GMM, lissage, HMM, grid-search, sauvegarde finale.
# ============================================================================

# =============================================================================
# STEP 3: FUSION ET GRID SEARCH - AVEC SYSTÈME DE CHECK-POINTING
# =============================================================================

# Récupération des variables d'environnement
split_job_id <- Sys.getenv("SPLIT_JOB_ID")
results_dir <- Sys.getenv("RESULTS_DIR")
cores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))

# DÉTECTION DU MODE DRY-RUN
is_dry <- Sys.getenv("DRY_RUN", "0") == "1"
if (is_dry) {
  cat("⚡ === MODE DRY-RUN ACTIVÉ ===\n")
  cat("📝 Test sur échantillon réduit - Garde-fous assouplis\n")
}

cat("🚀 === ÉTAPE 3: FUSION ET GRID SEARCH (AVEC CHECK-POINTING) ===\n")
cat("📦 Job fractionnement:", split_job_id, "\n")
cat("📁 Dossier résultats:", results_dir, "\n")
cat("🖥️  Cores:", cores, "\n")
cat("⏱️  Début:", format(Sys.time()), "\n\n")

# Configuration des chemins
output_dir <- "/home/benl/scratch/output_V6"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Système de check-pointing pour reprise rapide
chk_dir <- file.path(output_dir, "checkpoints")
dir.create(chk_dir, showWarnings = FALSE, recursive = TRUE)

# SÉCURISATION : suppression du checkpoint pollué pour forcer la refusion propre
unlink(file.path(chk_dir, "stage3A_fusion.rds"))

# SUPPRESSION DES CHECKPOINTS FAUTIFS POUR FORCER LE RECALCUL
gmm_checkpoint <- file.path(chk_dir, "stage3C_gmm.rds")
dbscan_checkpoint <- file.path(chk_dir, "stage3B_dbscan.rds")

if (file.exists(gmm_checkpoint)) {
  cat("🗑️  Suppression du checkpoint GMM fautif pour forcer le recalcul\n")
  unlink(gmm_checkpoint)
}

if (file.exists(dbscan_checkpoint)) {
  cat("🗑️  Suppression du checkpoint DBSCAN fautif pour forcer le recalcul\n")
  unlink(dbscan_checkpoint)
}

checkpoint <- function(file, expr, force_recompute = FALSE) {
  file <- file.path(chk_dir, file)
  if (!force_recompute && file.exists(file)) {
    cat("🔄  Reload checkpoint:", basename(file), "\n")
    obj <- readRDS(file)
    # Nettoyage mémoire après rechargement
    gc()
    obj
  } else {
    cat("⚙️  Compute & save checkpoint:", basename(file), "\n")
    obj <- force(expr)
    saveRDS(obj, file, compress = "xz")
    cat("✅ Checkpoint sauvegardé:", basename(file), "\n")
    # Nettoyage mémoire après sauvegarde
    gc()
    obj
  }
}

# Détermination du dossier de résultats
if (results_dir != "" && dir.exists(results_dir)) {
  expected_dir <- results_dir
  cat("✅ Utilisation du dossier spécifié:", expected_dir, "\n")
} else {
  cat("🔍 Auto-détection du dossier de résultats...\n")
  
  possible_paths <- c(
    paste0("/home/benl/scratch/ais_results_", split_job_id),
    paste0("/home/benl/scratch/ais_split_", split_job_id),
    paste0("/home/benl/scratch/", split_job_id)
  )
  
  expected_dir <- NULL
  for (path in possible_paths) {
    if (dir.exists(path)) {
      expected_dir <- path
      cat("✅ Dossier trouvé:", expected_dir, "\n")
      break
    } else {
      cat("   ❌ Non trouvé:", path, "\n")
    }
  }
  
  if (is.null(expected_dir)) {
    stop("❌ ERREUR: Aucun dossier de résultats trouvé")
  }
}

# Vérification des fichiers d'entrée
clean_files <- list.files(expected_dir, pattern = ".*_clean\\.rds$", full.names = TRUE)
if (length(clean_files) == 0) {
  stop("❌ ERREUR: Aucun fichier *_clean.rds trouvé dans ", expected_dir)
}

cat("✅ Fichiers d'entrée vérifiés:", length(clean_files), "fichiers *_clean.rds trouvés\n\n")

cat("\n🏁  STEP-3  |  Fusion & Modélisation  |  début :", format(Sys.time()), "\n\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
# CORRECTION: Ajouter les chemins sans écraser la config du bash
user_libs <- c("/home/benl/R/library", "~/.local/R/4.2.1")
.libPaths(unique(c(user_libs, .libPaths())))
cat("✅ R cherchera les packages dans :", paste(.libPaths(), collapse = " | "), "\n")

# DIAGNOSTIC DES PACKAGES - Vérification que tous les packages nécessaires sont disponibles
cat("\n🔍 DIAGNOSTIC DES PACKAGES REQUIS:\n")
needed <- c("glmnet", "doParallel", "pROC", "data.table", "dbscan", "mclust", "yaml", "geosphere", "lubridate", "zoo", "solitude", "depmixS4")
for (p in needed) {
  status <- if(requireNamespace(p, quietly=TRUE)) "✅ OK" else "❌ MANQUANT"
  cat(sprintf("   %-12s : %s\n", p, status))
}
cat("\n")

# --------------------------------------------------------------------------
# 1. ── PARAMÈTRES SLURM / ENV --------------------------------------------
# --------------------------------------------------------------------------
split_id    <- split_job_id  # même ID que la Step-1

# Utilisation de la logique de détection déjà définie plus haut
split_dir <- expected_dir

# CORRECTION: Vérification explicite des fichiers avant de continuer
clean_files_check <- list.files(split_dir, pattern = "_clean\\.rds$", full.names = TRUE)
if (!length(clean_files_check)) {
  stop("❌ Aucun fichier *_clean.rds trouvé dans ", split_dir, "\n",
       "   Fichiers présents dans le répertoire:\n",
       paste("   -", list.files(split_dir, pattern = "\\.rds$"), collapse = "\n"),
       "\n   Vérifiez que l'étape 2 s'est bien terminée.")
}

cat("✅ Fichiers *_clean.rds trouvés:", length(clean_files_check), "\n")
for (f in head(clean_files_check, 3)) cat("   •", basename(f), "\n")
if (length(clean_files_check) > 3) cat("   ... et", length(clean_files_check) - 3, "autres\n")

# Création du répertoire de sortie (output_dir déjà défini plus haut)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("💾  Source :", split_dir, "\n")
cat("💾  Sortie :", output_dir, "\n")
cat("💾  Checkpoints :", chk_dir, "\n\n")

# --------------------------------------------------------------------------
# 2. ── CHARGEMENT PACKAGES  +  CONFIG CPU ----------------------------------
# --------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(solitude)    # déjà utilisé mais requis pour re-charger config
  library(zoo)         # rolling
  library(dbscan)
  library(mclust)
  library(depmixS4)
  library(pROC)
  library(parallel)
  library(yaml)
  library(geosphere)
})

setDTthreads(cores)
options(datatable.optimize = 3)
options(mc.cores = cores)
Sys.setenv(OMP_NUM_THREADS      = cores,
           OPENBLAS_NUM_THREADS = cores)

cat("✅  Packages chargés |", cores, "threads data.table\n")

# --------------------------------------------------------------------------
# FONCTION DE CONTRÔLE STRICT DES FILTRES - ASSOUPLIE EN DRY-RUN
# --------------------------------------------------------------------------
# Constantes harmonisées pour éviter les incohérences
MIN_LEFT_DRY <- 1000
MIN_LEFT_PROD <- 20000

check_filter <- function(step_name, n_before, n_after, 
                        max_frac = if (is_dry) 0.90 else 0.25, 
                        min_left = if (is_dry) MIN_LEFT_DRY else MIN_LEFT_PROD, 
                        fatal = TRUE) {
  n_removed <- n_before - n_after
  frac_removed <- if (n_before == 0) 0 else n_removed / n_before
  
  cat(sprintf("[DIAGNOSTIC] %s : %d points supprimés (%.2f%%), %d restants\n", 
              step_name, n_removed, 100*frac_removed, n_after))
  
  if (fatal) {
    if (frac_removed > max_frac) {
      stop(sprintf("ERREUR FATALE : %s a supprimé %.1f%% des points (>%.0f%%). Vérifiez vos paramètres ou données !", 
                   step_name, 100*frac_removed, 100*max_frac))
    }
    if (n_after < min_left) {
      stop(sprintf("ERREUR FATALE : Il ne reste que %d points après '%s' (<%d), pipeline arrêtée.", 
                   n_after, step_name, min_left))
    }
  } else {
    if (frac_removed > max_frac) {
      warning(sprintf("[ALERTE] %s a supprimé %.1f%% des points (>%.0f%%) !", 
                   step_name, 100*frac_removed, 100*max_frac))
    }
    if (n_after < min_left) {
      warning(sprintf("[ALERTE] Il ne reste que %d points après '%s' (<%d) !", 
                   n_after, step_name, min_left))
    }
  }
}

# --------------------------------------------------------------------------
# 3. ── CONFIGURATION  ------------------------------------------------------
# --------------------------------------------------------------------------
cat("✅  YAML chargé\n")

# Valeurs par défaut si le YAML est incomplet
default_config <- list(
  contamination_rate = 0.02,
  if_num_trees = 25,
  if_sample_size = 256,
  spike_factor = 5,
  min_spike_duration = 2,
  percentile_lower = 0.05,
  percentile_upper = 0.95,
  min_context_points = 200,
  max_accel_ms2 = 0.3,
  max_turn_at_speed = 30,
  max_dredging_speed = 4
)

# Lecture du YAML avec gestion des erreurs
tryCatch({
  cfg <- yaml::read_yaml("~/R_scripts/configuration/outlier_config_V6.yaml")
  
  # Extraction des paramètres depuis les sections imbriquées
  if (!is.null(cfg$isolation_forest)) {
    cfg$contamination_rate <- cfg$isolation_forest$contamination_rate
    cfg$if_num_trees <- cfg$isolation_forest$num_trees
    cfg$if_sample_size <- cfg$isolation_forest$sample_size
  }
  
  if (!is.null(cfg$temporal_spikes)) {
    cfg$spike_factor <- cfg$temporal_spikes$spike_factor
    cfg$min_spike_duration <- cfg$temporal_spikes$min_duration
  }
  
  if (!is.null(cfg$contextual)) {
    cfg$percentile_lower <- cfg$contextual$percentile_lower
    cfg$percentile_upper <- cfg$contextual$percentile_upper
    cfg$min_context_points <- cfg$contextual$min_context_points
  }
  
  if (!is.null(cfg$physics)) {
    cfg$max_accel_ms2 <- cfg$physics$max_acceleration_ms2
    cfg$max_turn_at_speed <- cfg$physics$max_turn_at_speed
    cfg$max_dredging_speed <- cfg$physics$max_dredging_speed
  }
  
  # Vérification et complétion des paramètres manquants
  for (param in names(default_config)) {
    if (is.null(cfg[[param]])) {
      cfg[[param]] <- default_config[[param]]
      cat("⚠️  Paramètre manquant dans YAML:", param, "- Utilisation valeur par défaut:", default_config[[param]], "\n")
    }
  }
}, error = function(e) {
  cat("⚠️  Erreur lecture YAML - Utilisation valeurs par défaut\n")
  cfg <- default_config
})

# --------------------------------------------------------------------------
# 4. ── FUSION DES DONNÉES  -------------------------------------------------
# --------------------------------------------------------------------------
# CHECK-POINT 1: Fusion des données
ais <- checkpoint("stage3A_fusion.rds", {
cat("🔍  Fichiers trouvés :", length(clean_files), "\n")
for (f in head(clean_files, 5)) cat("   •", basename(f), "\n")
if (length(clean_files) > 5) cat("   …\n")

t_read <- system.time({
  # lecture en parallèle (limite 4 workers → suffisamment IO-safe)
  ais_list <- mclapply(clean_files, readRDS, mc.cores = min(cores, 4))
  ais      <- rbindlist(ais_list, fill = TRUE)
})
rm(ais_list); gc()
cat(sprintf("✅  Fusion : %s lignes | %.1f s\n\n",
            format(nrow(ais), big.mark = " "), t_read[3]))
  
  ais
})

# CORRECTIF : Définir n_total juste après la fusion
n_total <- nrow(ais)

# CONTRÔLE CRITIQUE : arrêt immédiat si des lignes sans Annee sont présentes après la fusion
nb_na_year <- ais[is.na(Annee), .N]
if (nb_na_year > 0) {
  stop(nb_na_year, " lignes sans Annee après fusion – checkpoint non sauvegardé.")
}

# --------------------------------------------------------------------------
# DRY-RUN PARAMÉTRABLE : DRY_RUN active, DRYRUN_N fixe la taille
# --------------------------------------------------------------------------
DRYRUN_N <- as.integer(Sys.getenv("DRYRUN_N", "0"))
if (is_dry && DRYRUN_N > 0 && nrow(ais) > DRYRUN_N) {
  set.seed(42)  # reproductible
  
  # Échantillonnage stratifié par navire pour garder la représentation
  ais <- ais[, .SD[sample(.N, min(.N, ceiling(DRYRUN_N * .N / n_total)))], by = Navire]
  
  cat(sprintf("🧪 Dry-run : subset de %d lignes (%.1f %% du total initial)\n",
              nrow(ais), 100 * nrow(ais) / n_total))
  
  # Mise à jour du total pour les diagnostics
  n_total <- nrow(ais)
}

# --------------------------------------------------------------------------
# 4 bis. ── VÉRIFICATION ET CORRECTION DES TYPES DE COLONNES ----------------
# --------------------------------------------------------------------------
cat("🔧  Vérification des types de colonnes...\n")

# Vérification des types critiques
cat(" Types des colonnes critiques:\n")
for (col in c("Navire", "ssvid", "Seg_id", "Annee")) {
  if (col %in% names(ais)) {
    cat(sprintf("   %-10s: %s\n", col, class(ais[[col]])[1]))
  }
}

# CORRECTION: Harmonisation des types pour éviter les erreurs de jointure
if ("Navire" %in% names(ais)) {
  # S'assurer que Navire est de type caractère
  if (!is.character(ais$Navire)) {
    cat("⚠️  Conversion de Navire en caractère\n")
    ais[, Navire := as.character(Navire)]
  }
}

if ("ssvid" %in% names(ais)) {
  # S'assurer que ssvid est de type entier
  if (!is.integer(ais$ssvid) && !is.numeric(ais$ssvid)) {
    cat("⚠️  Conversion de ssvid en entier\n")
    ais[, ssvid := as.integer(ssvid)]
  }
}

if ("Seg_id" %in% names(ais)) {
  # S'assurer que Seg_id est de type caractère
  if (!is.character(ais$Seg_id)) {
    cat("⚠️  Conversion de Seg_id en caractère\n")
    ais[, Seg_id := as.character(Seg_id)]
  }
}

if ("Annee" %in% names(ais)) {
  # S'assurer que Annee est de type entier
  if (!is.integer(ais$Annee) && !is.numeric(ais$Annee)) {
    cat("⚠️  Conversion de Annee en entier\n")
    ais[, Annee := as.integer(Annee)]
  }
}

# VÉRIFICATIONS SUPPLÉMENTAIRES CRITIQUES
cat("🔍 Vérifications supplémentaires critiques...\n")

# 1. Vérification de la colonne is_stop (utilisée dans DBSCAN)
if (!"is_stop" %chin% names(ais)) {
  stop("❌ Colonne 'is_stop' manquante - Vérifier que la Step-2 s'est bien terminée")
} else {
  cat("✅ Colonne 'is_stop' présente\n")
}

# 2. Vérification des colonnes géographiques (utilisées dans DBSCAN)
geo_cols <- c("Lon", "Lat", "Course", "Speed")
missing_geo <- geo_cols[!geo_cols %chin% names(ais)]
if (length(missing_geo) > 0) {
  stop("❌ Colonnes géographiques manquantes: ", paste(missing_geo, collapse = ", "))
} else {
  cat("✅ Colonnes géographiques présentes\n")
  # Conversion en numeric pour éviter les problèmes
  ais[, c("Lon", "Lat", "Course", "Speed") := lapply(.SD, as.numeric), .SDcols = c("Lon", "Lat", "Course", "Speed")]
  cat("✅ Colonnes géographiques converties en numeric\n")
}

# 3. Vérification des doublons (Seg_id, Timestamp)
if (anyDuplicated(ais, by = c("Seg_id", "Timestamp"))) {
  warning("⚠️  Doublons détectés dans (Seg_id, Timestamp) - Suppression...")
  ais <- unique(ais, by = c("Seg_id", "Timestamp"))
  cat("✅ Doublons supprimés\n")
} else {
  cat("✅ Aucun doublon détecté\n")
}

# 4. Vérification de la mémoire disponible
mem_usage <- object.size(ais) / 1024^3  # GB
cat(sprintf("📊 Utilisation mémoire: %.2f GB\n", mem_usage))

if (mem_usage > 50) {
  warning("⚠️  Utilisation mémoire élevée: ", round(mem_usage, 1), " GB")
}

cat("✅ Types de colonnes vérifiés et corrigés\n\n")

# --------------------------------------------------------------------------
# CONTRÔLE STRICT DES EFFECTIFS - ARRÊT EN CAS DE PROBLÈME
# --------------------------------------------------------------------------
n_total <- nrow(ais)  # Effectif initial
cat("📊 === CONTRÔLE STRICT DES EFFECTIFS ===\n")
cat(sprintf("📈 Nombre de points au début: %d\n", n_total))

# --------------------------------------------------------------------------
# 5. ── SUPPRIMER DIRECTEMENT LES outliers_IF -------------------------------
# --------------------------------------------------------------------------
n_before_outlier <- nrow(ais)
if ("outlier_IF" %chin% names(ais)) {
  ais <- ais[outlier_IF == FALSE | is.na(outlier_IF)]
  check_filter("Isolation Forest", n_before_outlier, nrow(ais))
} else {
  cat("[DIAGNOSTIC] Isolation Forest: Aucun filtre appliqué (colonne absente)\n")
}

# --------------------------------------------------------------------------
# 6. ── FONCTIONS UTILITAIRES (reprise du V6 complet) -----------------------
# --------------------------------------------------------------------------
roll_MAD5 <- function(x) {                # médians & MAD fenêtrées 5
  med <- zoo::rollapplyr(x, 5, median, fill = NA, align = "center")
  q25 <- zoo::rollapplyr(x, 5, quantile, probs = .25, fill = NA, align = "center")
  q75 <- zoo::rollapplyr(x, 5, quantile, probs = .75, fill = NA, align = "center")
  mad <- 1.4826 * (q75 - q25)
  list(med = med, mad = mad)
}

detect_spikes <- function(speed, spike_factor = 5, min_iso = 2) {
  r   <- roll_MAD5(speed)
  dev <- abs(speed - r$med)
  cand <- !is.na(r$mad) & r$mad > 0 & dev > spike_factor * r$mad

  for (idx in which(cand)) {
    rng <- max(1, idx - min_iso):min(length(speed), idx + min_iso)
    if (sum(abs(speed[rng] - speed[idx]) < r$mad[idx], na.rm = TRUE) > min_iso)
      cand[idx] <- FALSE
  }
  cand              # retour implicite (plus de `return()`)
}

# DBSCAN helper
auto_eps <- function(coords, k = 4) {
  # CORRECTION: Utilisation de distances métriques au lieu de degrés
  # Calcul des distances haversine en mètres
  geo_dist <- geosphere::distm(coords, fun = geosphere::distHaversine)
  d <- apply(geo_dist, 1, function(x) sort(x)[k+1])  # k+1 car la première distance est 0 (point lui-même)
  # Seuil minimum de 200m, sinon 1% de la médiane
  eps_m <- pmax(200, 0.01 * median(d, na.rm = TRUE))
  # CORRECTION CRITIQUE: Conversion mètres → degrés pour dbscan()
  eps_deg <- eps_m / 111000  # 1° ≈ 111 km à la latitude moyenne
  eps_deg
}

# Lissage transition comportement (idem Step-2 script)
smooth_transition <- function(lbl, spd, cost, thr = 3,
                              dredge_min = 1, dredge_max = 3.5) {
  rle_lbl <- rle(lbl); cum <- cumsum(rle_lbl$lengths); beg <- c(1, head(cum, -1) + 1)
  for (i in seq_along(rle_lbl$lengths)) {
    if (rle_lbl$lengths[i] < thr) {
      vbar <- mean(spd[beg[i]:cum[i]])
      if (vbar <= dredge_max) {
        prev <- if (i > 1) rle_lbl$values[i - 1] else NA
        next_val <- if (i < length(rle_lbl$values)) rle_lbl$values[i + 1] else NA
        c_prev <- if (!is.na(prev)) cost[prev, rle_lbl$values[i]] else Inf
        c_next <- if (!is.na(next_val)) cost[next_val, rle_lbl$values[i]] else Inf
        rle_lbl$values[i] <- if (c_prev < c_next) prev else next_val
      }
    }
  }
  inverse.rle(rle_lbl)
}

# --------------------------------------------------------------------------
# 7. ── PICS TEMPORELS  (Step-4 du pipeline) -------------------------------
# --------------------------------------------------------------------------
cat("⏱️  Détection pics temporels isolés…\n")
n_before_spike <- nrow(ais)
ais[, outlier_spike := detect_spikes(Speed,
                        spike_factor = cfg$spike_factor,
                        min_iso      = cfg$min_spike_duration),
    by = Seg_id]
ais <- ais[outlier_spike == FALSE | is.na(outlier_spike)]
check_filter("Filtre Spikes", n_before_spike, nrow(ais))
ais[, outlier_spike := NULL]

# --------------------------------------------------------------------------
# 8. ── PERCENTILES CONTEXTUELS  (Step-5) -----------------------------------
# --------------------------------------------------------------------------
cat("📐  Filtrage contextuel…\n")

# Définition des contextes opérationnels
ais[, context_op := fifelse(Speed < 1,  "arret_mouillage",
                     fifelse(Speed < 4, "operation_dragage",
                     fifelse(Speed < 8, "manoeuvre_lente", "transit_rapide")))]

# Helper pour quantile hors-NA
get_q <- function(v, p) if (all(is.na(v))) NA_real_ else quantile(v, p, na.rm = TRUE)

# CORRECTION: Harmonisation explicite des types avant la jointure
cat("🔧  Harmonisation des types pour la jointure des percentiles...\n")
if ("Navire" %in% names(ais) && !is.character(ais$Navire)) {
  cat("⚠️  Conversion de Navire en caractère dans la table principale\n")
  ais[, Navire := as.character(Navire)]
}

# Calcul des percentiles par contexte (léger, keyby pour jointure rapide)
percentiles <- ais[ , .(
    low = if (.N < cfg$min_context_points) NA_real_ else get_q(Speed, cfg$percentile_lower),
    hi  = if (.N < cfg$min_context_points) NA_real_ else get_q(Speed, cfg$percentile_upper)
), keyby = .(Navire, context_op)]

# CORRECTION: Harmonisation des types dans la table percentiles
if ("Navire" %in% names(percentiles) && !is.character(percentiles$Navire)) {
  cat("⚠️  Conversion de Navire en caractère dans la table percentiles\n")
  percentiles[, Navire := as.character(Navire)]
}

# CORRECTION: Jointure explicite avec vérification des types
cat("🔧  Vérification des types avant jointure:\n")
cat("   Table principale - Navire:", class(ais$Navire), "\n")
cat("   Table percentiles - Navire:", class(percentiles$Navire), "\n")

# Jointure explicite avec on = pour éviter les ambiguïtés
ais <- percentiles[ais, on = .(Navire, context_op)]
ais[, context_op := as.character(context_op)]

# Filtrage + suppression en une passe
n_before_percentile <- nrow(ais)
ais <- ais[(is.na(low) | Speed >= low) &
           (is.na(hi)  | Speed <= hi)][ , c("low","hi") := NULL]
check_filter("Percentiles contextuels", n_before_percentile, nrow(ais))

# Avertir si certains groupes sont trop petits
if (anyNA(percentiles$low))
  warning("Certaines combinaisons (Navire, contexte) ont < ",
          cfg$min_context_points, " points – percentiles ignorés.")

# --------------------------------------------------------------------------
# 9. ── DÉTECTION DES ARRÊTS SPATIAUX (DBSCAN) ------------------------------
# --------------------------------------------------------------------------
# CHECK-POINT 2: DBSCAN terminé
ais <- checkpoint("stage3B_dbscan.rds", {
cat("🔍  Détection des arrêts spatiaux par DBSCAN...\n")

# OPTIMISATION: Protection contre les petits navires et approche plus robuste
ais[, stop_cluster := NA_integer_]

# Comptage des points d'arrêt par navire/année pour éviter les traitements inutiles
stop_counts <- ais[is_stop == TRUE & !is.na(Lon), .N, by = .(Navire, Annee)]
stop_counts <- stop_counts[N >= 4]  # Seulement les navires avec suffisamment de points

if (nrow(stop_counts) > 0) {
  cat("📊 Traitement DBSCAN pour", nrow(stop_counts), "combinaisons navire/année\n")
  
  for (i in 1:nrow(stop_counts)) {
    navire <- stop_counts$Navire[i]
    annee <- stop_counts$Annee[i]
    
    # Sous-ensemble pour ce navire/année
    subset_data <- ais[Navire == navire & Annee == annee]
    arr <- subset_data[is_stop == TRUE & !is.na(Lon)]
    
    if (nrow(arr) >= 4) tryCatch({
      # PROTECTION: Vérification de la validité des coordonnées
      if (any(is.na(arr$Lon)) || any(is.na(arr$Lat))) {
        cat("⚠️  Coordonnées manquantes pour", navire, annee, "- Skipping\n")
        return()
      }
      
      # PROTECTION: Vérification de la variance des coordonnées
      if (var(arr$Lon, na.rm = TRUE) < 1e-8 || var(arr$Lat, na.rm = TRUE) < 1e-8) {
        cat("⚠️  Variance insuffisante pour", navire, annee, "- Skipping\n")
        return()
      }
      
      # CORRECTION: Protection contre les gros arrêts (O(n²) avec geosphere::distm)
      if (nrow(arr) > 5000) {
        cat("⚠️  Gros arrêt détecté pour", navire, annee, "(", nrow(arr), "points) - Échantillonnage pour eps\n")
        set.seed(123)  # Reproductibilité
        arr_sample <- arr[sample(.N, 5000)]
        # CORRECTION: Calculer eps sur l'échantillon, mais appliquer dbscan sur tous les points
        eps <- auto_eps(as.matrix(arr_sample[, .(Lon, Lat)]))
        cl <- dbscan(arr[, .(Lon, Lat)], eps = eps, minPts = 4)$cluster
      } else {
        # Cas normal : calcul direct
   eps <- auto_eps(as.matrix(arr[, .(Lon, Lat)]))
      cl <- dbscan(arr[, .(Lon, Lat)], eps = eps, minPts = 4)$cluster
      }
      
      # CORRECTION 4: Protection contre les clusters vides
      if (sum(cl > 0) == 0) {
        cat("⚠️  Aucun cluster trouvé pour", navire, annee, "- Élargissement du rayon eps\n")
        eps <- eps * 1.5
        cl <- dbscan(arr[, .(Lon, Lat)], eps = eps, minPts = 4)$cluster
      }
      
      # Affectation vectorisée (maintenant cohérente)
        ais[Navire == navire & Annee == annee & is_stop == TRUE & !is.na(Lon), stop_cluster := cl]
      }, error = function(e) {
        cat("⚠️  Erreur DBSCAN pour", navire, annee, ":", e$message, "\n")
      })
  }
} else {
  cat("⚠️  Aucun navire avec suffisamment de points d'arrêt pour DBSCAN\n")
}

ais[, is_stop_spatial := is_stop & !is.na(stop_cluster) & stop_cluster > 0]
  
  cat("✅ DBSCAN terminé - Checkpoint sauvegardé\n")
  
  # CONTRÔLE: Effectifs après DBSCAN
  n_stop_spatial <- sum(ais$is_stop_spatial, na.rm = TRUE)
  cat(sprintf("[DIAGNOSTIC] Après DBSCAN (is_stop_spatial TRUE): %d points (%.2f%% du total)\n", 
              n_stop_spatial, 100 * n_stop_spatial / nrow(ais)))
  
  # Vérification que DBSCAN n'a pas supprimé trop de points
  if (n_stop_spatial < 1000) {
    warning("[ALERTE] Très peu de points d'arrêt spatiaux détectés par DBSCAN (< 1000)")
  }
  
  # VÉRIFICATION CRITIQUE: S'assurer que is_stop_spatial est bien créée
  if (!"is_stop_spatial" %in% names(ais)) {
    stop("❌ ERREUR CRITIQUE: Colonne 'is_stop_spatial' manquante après DBSCAN")
  }
  cat("✅ Vérification: Colonne 'is_stop_spatial' présente\n")
  
  ais
})

# --------------------------------------------------------------------------
# 10 bis. ── Calcule la cadence AIS & seuils adaptatifs  -------------------
# --------------------------------------------------------------------------
#  (à placer après l'étape DBSCAN et AVANT la section "GMM stop + 4")

# 1) Tri par segment et timestamp pour éviter les dt_sec négatifs
setorder(ais, Seg_id, Timestamp)

# 2) Δt inter-messages en secondes
ais[, dt_sec := c(NA_real_, diff(as.numeric(Timestamp))), by = Seg_id]

# CORRECTION 1: Calcul de Course_change seulement (Accel sera calculé après filtrage)
ais[, Course_change := c(NA, abs(diff(Course)))] # wrap-around 360°
# Gestion du wrap-around pour Course_change
ais[Course_change > 180, Course_change := 360 - Course_change]
# Sauvegarde robuste si trop de NA
ais[is.na(Course_change), Course_change := 0]

# 3) Calcul des statistiques de cadence par navire
cadence <- ais[!is.na(dt_sec), .(
    p50_dt = median(dt_sec, na.rm = TRUE),      # médiane
    p95_dt = quantile(dt_sec, 0.95, na.rm = TRUE),  # 95e percentile
    n_obs = .N
), by = Navire]

# 4) Troncature de la médiane pour éviter les cas extrêmes
cadence[, p50_dt := pmin(p50_dt, 600)]  # on tronque la médiane à 10 min

# 5) Calcul des seuils adaptatifs
#    - Seuil de base : 3 × médiane (capture les vraies pauses)
#    - Plancher : 180 s (3 min) pour les navires très actifs
#    - Plafond : 900 s (15 min) pour les navires normaux
#    - Seuil spécial pour navires très lents (> 50% d'intervalles > 5 min)

cadence[, seuil_adaptatif := pmin(900, pmax(180, 3 * p50_dt))]

# 6) Détection des navires très lents (plus de 50% d'intervalles > 5 min)
intervalles_long <- ais[dt_sec >= 300, .N, by = Navire]
intervalles_tot <- ais[!is.na(dt_sec), .N, by = Navire]
prop_long <- merge(intervalles_long, intervalles_tot, by = "Navire", suffixes = c("_long", "_total"))
prop_long[, prop_long := N_long / N_total]

# 7) Ajustement du seuil pour les navires très lents
cadence <- merge(cadence, prop_long[, .(Navire, prop_long)], by = "Navire", all.x = TRUE)
cadence[is.na(prop_long), prop_long := 0]

# Pour les navires avec > 50% d'intervalles longs, utiliser un seuil plus élevé
cadence[prop_long > 0.5, seuil_adaptatif := pmin(1200, 5 * p50_dt)]  # 5 × médiane, max 20 min

# 8) Calcul du n_min adaptatif pour le lissage run-length
#    t_seuil = 30 s ≈ durée max d'un micro-glitch
t_seuil   <- 30                     # 30 s ≈ durée max d'un micro-glitch
n_max_cap <- 8                      # plafond pour rester rapide
cadence[, n_min := pmin(n_max_cap, pmax(3, ceiling(t_seuil / p50_dt)))]

# 9) Join avec l'ensemble principal
ais <- merge(ais, cadence[, .(Navire, n_min, seuil_adaptatif, p50_dt, prop_long)], by = "Navire", all.x = TRUE)

# 10) Filtrage avec seuil adaptatif (parenthèses pour clarifier la logique)
cat("🔧  Cadence AIS & seuils adaptatifs par navire\n")
print(cadence[order(p50_dt), .(Navire, p50_dt, seuil_adaptatif, n_min, prop_long)])

# Filtrage des intervalles trop longs selon le seuil adaptatif de chaque navire
n_before_cadence <- nrow(ais)
ais <- ais[(dt_sec > 0 & dt_sec < seuil_adaptatif) | is.na(dt_sec)]
check_filter("Filtrage intervalles longs", n_before_cadence, nrow(ais))

# CORRECTION: Recalcul de dt_sec APRÈS le filtrage pour éviter le décalage temporel
ais[, dt_sec := c(NA_real_, diff(as.numeric(Timestamp))), by = Seg_id]

# CORRECTION: Recalcul de Course_change APRÈS le filtrage pour éviter le biais
ais[, Course_change := c(NA, abs(diff(Course))), by = Seg_id]
# Gestion du wrap-around pour Course_change
ais[Course_change > 180, Course_change := 360 - Course_change]
# Sauvegarde robuste si trop de NA
ais[is.na(Course_change), Course_change := 0]

# CORRECTION: Calcul de Accel APRÈS le filtrage des grands trous temporels
# Conversion Speed en m/s pour calculer Accel en m/s²
# CORRECTION 2: Garde-fou contre les vecteurs vides
ais[, Accel := {
  dt <- dt_sec[-1L]
  if (length(dt) == 0) {
    rep(NA_real_, .N)
  } else {
    c(NA, diff(Speed * 0.514444) / pmax(dt, 1))
  }
}, by = Seg_id]
ais[is.na(Accel), Accel := 0]

# -- Sécurise n_min pour les cas NA ----------------------------------------
ais[is.na(n_min), n_min := 3]  # fallback plancher

# CONTRÔLE FINAL AVANT GMM
cat(sprintf("[DIAGNOSTIC] Nombre de points conservés avant GMM: %d (%.2f%% du total initial)\n", 
            nrow(ais), 100 * nrow(ais) / n_total))

# Vérification finale critique - ASSOUPLIE EN DRY-RUN
if (is_dry) {
  # En dry-run, on tolère un dataset plus petit
  if (nrow(ais) < 5000) {
    stop(sprintf("ERREUR FATALE : Il ne reste que %d points avant GMM (< 5000), échantillon trop petit pour le dry-run.", nrow(ais)))
  }
} else {
  if (nrow(ais) < 20000) {
    stop(sprintf("ERREUR FATALE : Il ne reste que %d points avant GMM (< 20000), pipeline arrêtée.", nrow(ais)))
  }
}

cat("\n[DIAGNOSTIC] Distribution du dataset juste avant le GMM :\n")
print(table(ais$Navire))
cat("Total points restants :", nrow(ais), "\n")

# --------------------------------------------------------------------------
# 11. ── GMM  « stop + K mobiles »  (K choisi par BIC entre 3 et 5) - ROBUSTE
# --------------------------------------------------------------------------
ais <- checkpoint("stage3C_gmm.rds", {

  cat("🔧  GMM « stop + K mobiles » – sélection K par BIC (3-5) - ROBUSTE\n")

  ## 0. Préparation ----------------------------------------------------------
  idx_mobile <- which(!ais$is_stop_spatial & ais$Speed >= 0.5 & ais$Speed <= 20)

  # CORRECTION: Recalcul des quantiles après tous les filtres pour éviter le biais
  q95_acc  <- quantile(abs(ais$Accel),  .95, na.rm = TRUE);  if (!is.finite(q95_acc)  || q95_acc  == 0) q95_acc  <- 1e-6
  q95_turn <- quantile(ais$Course_change, .95, na.rm = TRUE); if (!is.finite(q95_turn) || q95_turn == 0) q95_turn <- 1e-6
  
  cat("   📊 Quantiles recalculés après filtres - Accel 95%:", round(q95_acc, 4), "| Course 95%:", round(q95_turn, 2), "°\n")

  mobi <- ais[idx_mobile, .(
      Speed,
      norm_acc    = pmax(0, pmin(1, abs(Accel) / q95_acc)),
      norm_course = pmax(0, pmin(1, 1 - Course_change / q95_turn))
  )]

  keep       <- complete.cases(mobi)
  X          <- as.matrix(mobi[keep])
  idx_train  <- idx_mobile[keep]

  # Seuil adaptatif selon le mode (dry-run vs production)
  min_mobile <- if (is_dry) 50 else 200
  if (nrow(X) < min_mobile)
    stop("❌  Pas assez de points mobiles complets pour ajuster le GMM (", nrow(X), " < ", min_mobile, ")")

  ## 1. Recherche du meilleur K (BIC) - ROBUSTE ------------------------------
  # CORRECTION 5: Protection contre l'overflow mémoire Mclust
  samp <- if (nrow(X) > 1e6) X[sample(nrow(X), 1e6), ] else X
  cat("   Échantillon pour BIC:", nrow(samp), "points (sur", nrow(X), ")\n")
  
  G_choices <- 3:5                                   # 3 à 5 composantes mobiles
  
  # CORRECTION CRITIQUE: Fonction helper pour extraire un scalaire BIC
  get_bic_scalar <- function(x) {
    if (is.null(x) || length(x) == 0) return(-Inf)
    max(as.numeric(x), na.rm = TRUE)
  }
  
  # CORRECTION 1: Utiliser vapply() qui force un scalaire numérique dès le départ
  bic_vals <- vapply(G_choices, function(g) {
    res <- tryCatch(
      Mclust(samp, G = g, modelNames = "VVV", verbose = FALSE),
      error = function(e) NULL)
    if (is.null(res)) return(-Inf)
    get_bic_scalar(res$bic)
  }, numeric(1))
  
  # CORRECTION 2: Protection contre les échecs Mclust
  if (all(is.infinite(bic_vals)))
    stop("❌  Mclust a échoué pour toutes les valeurs de K - X trop grand ou mal conditionné")
  
  K <- G_choices[which.max(bic_vals)]
  
  # CORRECTION 4: Vérification de la borne basse K >= 3
  if (K < 3) stop("❌ Le GMM doit avoir au moins 3 composantes mobiles (dredge/transit)")
  
  cat("   ➜  K retenu par BIC :", K, "composantes mobiles\n")

  ## 2. Ajustement définitif -------------------------------------------------
  # CORRECTION 3: Protection mémoire pour l'ajustement final
  X_fit <- if (nrow(X) > 2e6) X[sample(nrow(X), 2e6), ] else X
  cat("   Échantillon pour ajustement final:", nrow(X_fit), "points (sur", nrow(X), ")\n")
  
  gmm <- Mclust(X_fit, G = K, modelNames = "VVV", verbose = FALSE)

  ## 3. Probabilités a posteriori -------------------------------------------
  z <- predict(gmm, X)$z                       # nrow(X) × K
  
  # CORRECTION 3: Ré-initialisation sûre des colonnes p
  ais[, paste0("p", 1:(K+1)) := 0]             # crée p1…p{K+1} et remet à zéro
  ais[is_stop_spatial == TRUE, p1 := 1]

  for (j in seq_len(K))
    ais[idx_train, paste0("p", j + 1) := z[, j]]

  ## 4. Réordonnance par vitesse --------------------------------------------
  ord  <- order(gmm$parameters$mean[1, ])      # tri croissant de Speed
  mu   <- gmm$parameters$mean[1, ord]
  cat("   μ mobiles triés :", paste(round(mu, 2), collapse = " / "), "kn\n")

  Zord <- z[, ord, drop = FALSE]
  
  # CORRECTION 3: Ré-initialisation complète avant ré-insertion
  ais[, paste0("p", 1:(K+1)) := 0]             # remet tout à zéro
  ais[is_stop_spatial == TRUE, p1 := 1]        # remet les stops
  for (j in seq_len(K))
    ais[idx_train, paste0("p", j + 1) := Zord[, j]]

  ## 5. Étiquettes brutes - CORRECTION: Mapping dynamique basé sur la vitesse ---
  # CORRECTION CRITIQUE: Attribution dynamique des labels selon la vitesse
  # μ mobiles triés : 1.72 / 7.82 / 12.55 kn → dredging / loaded_transit / unloaded_transit
  
  if (K == 3) {
    # Pour K=3: la plus lente = dredging, médiane = loaded_transit, plus rapide = unloaded_transit
    mobile_labels <- c("dredging", "loaded_transit", "unloaded_transit")
  } else if (K == 4) {
    # Pour K=4: ajouter slow_maneuvers
    mobile_labels <- c("slow_maneuvers", "dredging", "loaded_transit", "unloaded_transit")
  } else if (K == 5) {
    # Pour K=5: ajouter une composante supplémentaire
    mobile_labels <- c("slow_maneuvers", "dredging", "loaded_transit", "unloaded_transit", "fast_transit")
    } else {
    stop(sprintf("❌ K inattendu (%d): prévoir la table des labels pour K=%d", K, K))
  }
  
  # Tronquer si nécessaire
  mobile_labels <- mobile_labels[seq_len(K)]
  map <- c("stops", mobile_labels)             # longueur = K+1 (p1…p{K+1})
  
  cat("   🏷️  Labels attribués par vitesse:", paste(mobile_labels, collapse=" → "), "\n")
  cat("   📊 Vitesses correspondantes:", paste(round(mu, 2), "kn", collapse=" → "), "\n")

  ais[, comp     := apply(.SD, 1, which.max), .SDcols = paste0("p", 1:(K + 1))]
  ais[, behavior := map[comp]]

  ## 6. Lissage run-length - ROBUSTE -----------------------------------------
  # CORRECTION: Matrice de coût adaptée au mapping dynamique
  # Construction dynamique selon les labels disponibles
  all_labels <- c("stops", mobile_labels)
  n_labels <- length(all_labels)
  
  # Matrice de coût de base (coût élevé pour transitions improbables)
  cost_matrix <- matrix(5, n_labels, n_labels, 
                       dimnames = list(all_labels, all_labels))
  
  # Coûts spécifiques
  diag(cost_matrix) <- 0  # même état = coût 0
  
  # Coûts entre états mobiles (transitions naturelles)
  if ("dredging" %in% all_labels) {
    dredge_idx <- which(all_labels == "dredging")
    # Dredging ↔ transit = coût modéré
    transit_labels <- setdiff(all_labels, c("stops", "dredging"))
    for (tl in transit_labels) {
      tl_idx <- which(all_labels == tl)
      cost_matrix[dredge_idx, tl_idx] <- 3
      cost_matrix[tl_idx, dredge_idx] <- 3
    }
  }
  
  # Coûts vers/depuis stops (transitions rares)
  stops_idx <- which(all_labels == "stops")
  cost_matrix[stops_idx, ] <- 4
  cost_matrix[, stops_idx] <- 4
  cost_matrix[stops_idx, stops_idx] <- 0
  
  # CORRECTION: Coût réduit pour dredging ↔ stops (plus naturel)
  if ("dredging" %in% all_labels) {
    dredge_idx <- which(all_labels == "dredging")
    cost_matrix[dredge_idx, stops_idx] <- 3
    cost_matrix[stops_idx, dredge_idx] <- 3
  }

  # CORRECTION 4: Fonction de coût sécurisée pour les labels manquants
  safe_cost <- function(a, b) {
    if (!a %in% rownames(cost_matrix) || !b %in% colnames(cost_matrix)) return(Inf)
    cost_matrix[a, b]
  }

  # Version robuste de smooth_transition
  smooth_transition_robust <- function(lbl, spd, thr, dredge_min, dredge_max) {
    rle_lbl <- rle(lbl); cum <- cumsum(rle_lbl$lengths); beg <- c(1, head(cum, -1) + 1)
    for (i in seq_along(rle_lbl$lengths)) {
      if (rle_lbl$lengths[i] < thr) {
        vbar <- mean(spd[beg[i]:cum[i]])
        if (vbar <= dredge_max) {
          prev <- if (i > 1) rle_lbl$values[i - 1] else NA
          next_val <- if (i < length(rle_lbl$values)) rle_lbl$values[i + 1] else NA
          c_prev <- if (!is.na(prev)) safe_cost(prev, rle_lbl$values[i]) else Inf
          c_next <- if (!is.na(next_val)) safe_cost(next_val, rle_lbl$values[i]) else Inf
          rle_lbl$values[i] <- if (c_prev < c_next) prev else next_val
        }
      }
    }
    inverse.rle(rle_lbl)
  }

  # CORRECTION: Seuil plus stable pour le lissage (75e percentile au lieu de médiane)
  lissage_threshold <- quantile(ais$n_min, 0.75, na.rm = TRUE)
  cat("   🎯 Seuil de lissage (75e percentile n_min):", round(lissage_threshold, 1), "\n")
  
  ais[, behavior_smooth :=
        smooth_transition_robust(behavior, Speed,
                                thr = lissage_threshold,
                                dredge_min = 1, dredge_max = 3.5),
      by = Seg_id]

  ais[, dredge_lisse := as.integer(behavior_smooth == "dredging")]

  ## 7. Normalisés pour le score dragage -------------------------------------
  ais[, norm_course := pmax(0, pmin(1, 1 - Course_change / q95_turn))]
  ais[, norm_acc    := pmax(0, pmin(1, abs(Accel) / q95_acc))]

  cat("✅  GMM ROBUSTE terminé –", table(ais$behavior_smooth), "états après lissage\n")
  
  # VÉRIFICATION DES CLASSES APRÈS GMM (pour dry-run)
  if (is_dry) {
    n_classes <- length(unique(ais$behavior_smooth))
    if (n_classes < 2) {
      stop(sprintf("ERREUR FATALE : Échantillon DRY-RUN mono-classe après GMM (%d classe) – reprenez un autre sous-ensemble", n_classes))
    }
    cat("   ✅ Dry-run: ", n_classes, "classes détectées après GMM\n")
  }
  
  # CORRECTION: Sauvegarder les informations de mapping pour la suite (optimisé)
  # Utilisation d'attributs pour éviter la duplication en RAM
  attr(ais, "gmm_info") <- list(
    K = K,
    dredge_idx = which(mobile_labels == "dredging"),
    dredge_speed = mu[which(mobile_labels == "dredging")],
    mobile_labels = mobile_labels,
    mu = mu
  )
  
  # VÉRIFICATION QA: Confirmer que p_dredge maximise bien la proba quand behavior_smooth == "dredging"
  dredge_idx <- which(mobile_labels == "dredging")
  dredge_col <- paste0("p", dredge_idx + 1)
  ais[, p_dredge_qa := get(dredge_col)]
  
  # Test de cohérence
  dredge_points <- ais$behavior_smooth == "dredging"
  if (sum(dredge_points) > 0) {
    proba_cols <- paste0("p", 1:(K+1))
    max_proba_col <- apply(ais[dredge_points, proba_cols, with=FALSE], 1, which.max)
    correct_mapping <- all(max_proba_col == (dredge_idx + 1))
    
    if (correct_mapping) {
      cat("   ✅ QA: p_dredge maximise bien la probabilité pour les points 'dredging'\n")
    } else {
      cat("   ⚠️  QA: Incohérence détectée dans le mapping p_dredge\n")
    }
  }
  
  ais
})

# --------------------------------------------------------------------------
# 13. ── GRID-SEARCH (poids score dragage) - CORRIGÉ POUR ÉVITER DATA LEAKAGE
# --------------------------------------------------------------------------
# CHECK-POINT 4: Grid-search terminé
resGS <- checkpoint(
  "stage3D_gridsearch.rds",
  {
    cat("🔍  Grid-search (poids score dragage) - CORRIGÉ POUR ÉVITER DATA LEAKAGE\n")
    
    # CORRECTION MAJEURE: Éviter le data leakage
    # 1) Définir les blocs CV (leave-one-year-out)
    ais[, fold := frank(Annee, ties.method="dense")]
    cat("   Validation croisée par année:", length(unique(ais$fold)), "folds\n")
    
    # 2) Retirer le label dérivé des prédicteurs (ÉVITE DATA LEAKAGE)
    # Au lieu de dredge_lisse, utiliser p_dredge (probabilité GMM) + signaux cinématiques
    ais[, speed_bin := as.integer(Speed >= 1 & Speed <= 3.5)]
    ais[, speed_norm := exp(-(Speed - 2.25)^2 / (2 * 1^2))]
    
    # CORRECTIF : Remplacer les NA restants dans speed_bin et speed_norm
    ais[is.na(speed_bin),  speed_bin  := 0L]
    ais[is.na(speed_norm), speed_norm := 0]
    
    # CORRECTION: Sécurisation de speed_norm contre les divisions par zéro
    ais[!is.finite(speed_norm), speed_norm := 0]
    
    # CORRECTION CRITIQUE: Création de la probabilité de dragage dynamique
    # Récupérer les informations de mapping depuis les attributs GMM
    gmm_info <- attr(ais, "gmm_info")
    if (is.null(gmm_info)) {
      stop("❌ ERREUR: Informations de mapping GMM manquantes (attribut gmm_info)")
    }
    
    dredge_idx <- gmm_info$dredge_idx
    dredge_speed <- gmm_info$dredge_speed
    gmm_k <- gmm_info$K
    
    # Créer la colonne p_dredge avec la bonne probabilité
    dredge_col <- paste0("p", dredge_idx + 1)  # +1 car p1 = stops
    if (!dredge_col %in% names(ais)) {
      stop(sprintf("❌ ERREUR: Colonne %s manquante (dredge_idx=%d)", dredge_col, dredge_idx))
    }
    
    ais[, p_dredge := get(dredge_col)]
    cat(sprintf("   ✅ Probabilité dragage: %s (composante %d, vitesse %.2f kn, K=%d)\n", 
                dredge_col, dredge_idx, dredge_speed, gmm_k))
    
    # Prédicteurs indépendants du label final
    predictors <- ais[, .(p_dredge, norm_course, norm_acc, speed_bin, speed_norm)]
    target <- ais$behavior_smooth == "dredging"
    
    # CORRECTIF : Remplacer les NA restants dans speed_bin et speed_norm avant conversion
    ais[is.na(speed_bin),  speed_bin  := 0L]
    ais[is.na(speed_norm), speed_norm := 0]
    
    # CORRECTIF : Vérification que tous les prédicteurs sont numériques
    stopifnot(all(sapply(predictors, is.numeric)))
    
    # DIAGNOSTIC: Vérification des valeurs non-finies dans les prédicteurs
    msg <- colSums(!is.finite(as.matrix(predictors)))
    cat("⛔ Non-finis par colonne :", paste(names(msg), msg, sep=":", collapse=", "), "\n")
    
    # CORRECTION: Remplacement des valeurs non-finies par 0
    predictors <- predictors[, lapply(.SD, function(v) replace(v, !is.finite(v), 0))]
    cat("✅ Valeurs non-finies remplacées par 0\n")
    
    # CORRECTION CRITIQUE: Nettoyage des NA dans target (PRÉSERVATION DES DONNÉES)
    cat("   🔍 Nettoyage des NA dans la variable cible...\n")
    keep_lbl <- !is.na(target)
    n_before <- nrow(ais)
    n_filtered <- sum(!keep_lbl)
    
    cat(sprintf("   📊 Points avec NA dans target: %d (%.2f%%)\n", 
                n_filtered, 100 * n_filtered / n_before))
    
    # CONTRÔLE STRICT: Vérification qu'il ne reste plus de NA
    if (any(is.na(target[keep_lbl]))) {
      stop("ERREUR FATALE : NA détectés dans target après filtrage !")
    }
    
    # Conversion en entier 0/1 (glmnet préfère numérique) - SEULEMENT pour l'entraînement
    target_train <- as.integer(target[keep_lbl])  # 1 = dredging, 0 = non-dredging
    
    # PRÉSERVATION: Garder les indices pour réinsérer les prédictions
    train_indices <- which(keep_lbl)
    cat("   ✅ Données préservées: %d points pour entraînement, %d points pour prédiction complète\n", 
        length(train_indices), n_before)
    
    # CORRECTION: Gestion des valeurs NA dans les prédicteurs
    # glmnet n'accepte pas les valeurs NA
    cat("   Vérification des valeurs manquantes dans les prédicteurs...\n")
    na_counts <- colSums(is.na(predictors))
    cat("   Valeurs NA par prédicteur:", paste(names(na_counts), na_counts, sep=":", collapse=", "), "\n")
    
    # DIAGNOSTIC: Vérification du mapping p_dredge
    cat("   Vérification du mapping p_dredge:\n")
    cat("   Colonnes p disponibles:", paste(intersect(paste0("p",1:5), names(ais)), collapse=", "), "\n")
    cat("   Colonne p_dredge créée:", if("p_dredge" %in% names(ais)) "OUI" else "NON", "\n")
    if ("p_dredge" %in% names(ais)) {
      cat("   Valeurs p_dredge:", paste(head(ais$p_dredge, 5), collapse=", "), "\n")
    }
    
    # Option 1: Remplacer les NA par 0 (plus conservateur)
    predictors[is.na(predictors)] <- 0
    cat("   Valeurs NA remplacées par 0\n")
    
    # Option 2: Filtrer les lignes avec des valeurs manquantes (plus strict)
    # complete_cases <- complete.cases(predictors, target)
    # predictors <- predictors[complete_cases]
    # target <- target[complete_cases]
    # cat("   Lignes avec valeurs manquantes filtrées:", sum(!complete_cases), "\n")
    
    cat("   Prédicteurs utilisés:", paste(names(predictors), collapse = ", "), "\n")
    cat("   Classes cibles:", table(target), "\n")
    
    # CONTRÔLE STRICT DE LA DISTRIBUTION DES CLASSES
    cat("\n[DIAGNOSTIC] Effectifs par behavior_smooth :\n")
    print(table(ais$behavior_smooth, useNA = "ifany"))
    cat("Effectifs par année :\n")
    print(table(ais$Annee))
    
    # Vérification critique de la distribution des classes (sur les données d'entraînement)
    dredging_count <- sum(target_train)
    non_dredging_count <- sum(!target_train)
    
    # Seuils adaptatifs selon le mode (dry-run vs production)
    if (is_dry) {
      # En dry-run, on tolère moins de données mais il faut au moins 2 classes
      if (dredging_count < 10) {
        stop(sprintf("ERREUR FATALE : Seulement %d points 'dredging' détectés (< 10), échantillon trop déséquilibré pour le dry-run !", dredging_count))
      }
      if (non_dredging_count < 50) {
        stop(sprintf("ERREUR FATALE : Seulement %d points 'non-dredging' détectés (< 50), échantillon trop déséquilibré pour le dry-run !", non_dredging_count))
      }
    } else {
      if (dredging_count < 100) {
        stop(sprintf("ERREUR FATALE : Seulement %d points 'dredging' détectés (< 100), impossible de faire une CV valide !", dredging_count))
      }
      if (non_dredging_count < 1000) {
        stop(sprintf("ERREUR FATALE : Seulement %d points 'non-dredging' détectés (< 1000), impossible de faire une CV valide !", non_dredging_count))
      }
    }
    
    # DIAGNOSTIC DÉTAILLÉ: Distribution des classes par année/navire (données d'entraînement)
    cat("   📊 Distribution détaillée des classes par année/navire (données d'entraînement):\n")
    ais_train <- ais[keep_lbl]
    class_distribution <- table(target_train, ais_train$Annee, ais_train$Navire)
    print(class_distribution)
    
    # Vérification critique des classes avant CV (sur les données d'entraînement)
    if (length(unique(target_train)) < 2) {
      stop(sprintf("ERREUR FATALE : Dataset mono-classe ! Seulement %d classe(s) détectée(s), impossible de faire une CV valide.\n   📊 Distribution: %s", 
                   length(unique(target_train)), paste(table(target_train), collapse=", ")))
    } else {
      # CORRECTION 1: Vérification des packages offline avant CV
      cat("   Vérification des packages requis...\n")
      if (!requireNamespace("glmnet", quietly = TRUE)) {
        stop("❌ Package 'glmnet' absent - charge-le via module ou $R_LIBS_USER")
      }
      if (!requireNamespace("doParallel", quietly = TRUE)) {
        stop("❌ Package 'doParallel' absent - charge-le via module ou $R_LIBS_USER")
      }
      library(glmnet)
      library(doParallel)
      
      # CORRECTION 6: Parallélisme glmnet sans conflit data.table
      cat("   Configuration du parallélisme glmnet...\n")
      setDTthreads(1)  # Désactive le parallélisme data.table
      Sys.setenv(OMP_NUM_THREADS = 1)  # Désactive OpenMP
      registerDoParallel(cores = min(12, parallel::detectCores() - 2))
      cat("   Parallélisme configuré pour glmnet (", min(12, parallel::detectCores() - 2), " cœurs)\n")
      
      # CORRECTIF 10 : on.exit() déplacé hors de la boucle CV
on.exit({
  stopImplicitCluster()
  setDTthreads(0)  # Remet data.table en mode auto
  Sys.unsetenv("OMP_NUM_THREADS")
}, add = TRUE)

# PRÉPARATION DES DONNÉES D'ENTRAÎNEMENT
predictors_train <- predictors[keep_lbl, ]
ais_train <- ais[keep_lbl]

# CORRECTIF 8 : Création des colonnes manquantes AVANT la CV
# Option fiable : calcul matriciel avec correspondance exacte des noms
missing <- setdiff(c("p_dredge", "norm_course", "norm_acc", "speed_bin", "speed_norm"), names(predictors_train))
if (length(missing) > 0) {
  cat("   Ajout des colonnes manquantes:", paste(missing, collapse=", "), "\n")
  predictors_train[, (missing) := 0]
}

# CORRECTIF 9 : Conversion en matrice creuse pour économiser la mémoire
cat("   Conversion en matrice creuse pour économiser la mémoire...\n")
if (!requireNamespace("Matrix", quietly = TRUE)) {
  stop("❌ Package 'Matrix' absent - charge-le via module ou $R_LIBS_USER")
}
library(Matrix)

# CORRECTIF : Matrice creuse pour toutes les lignes (pas seulement keep_lbl)
predictors_all <- Matrix::Matrix(as.matrix(predictors), sparse = TRUE)
predictors_all <- Matrix::drop0(predictors_all)   # supprime les zéros explicites
cat(sprintf("   Matrice creuse globale créée: %.1f MB\n", 
            object.size(predictors_all)/1024^2))

# Matrice creuse pour les données d'entraînement seulement
predictors_matrix <- predictors_all[keep_lbl, ]
predictors_matrix <- Matrix::drop0(predictors_matrix)   # supprime les zéros explicites
cat(sprintf("   Matrice creuse d'entraînement: %.1f MB (vs %.1f MB dense)\n", 
            object.size(predictors_matrix)/1024^2, 
            object.size(as.matrix(predictors_train))/1024^2))

auc_fold <- numeric(max(ais_train$fold))
      best_models <- list()
      
      # DIAGNOSTIC: Affichage de la distribution des classes par fold (données d'entraînement)
      cat("   📊 Distribution des classes par fold (données d'entraînement):\n")
      fold_table <- table(target_train, ais_train$fold)
      print(fold_table)
      
      for (k in unique(ais_train$fold)) {
        cat(sprintf("     Fold %d/%d (année %d)...\n", k, max(ais_train$fold), unique(ais_train$Annee[ais_train$fold == k])))
        
        train <- ais_train$fold != k
        test <- ais_train$fold == k
        
        # FILTRAGE COMPLET POUR TRAIN/TEST - PROTECTION CONTRE LES NA ET NON-FINIS
        Xtrain <- predictors_matrix[train, ]
        Ytrain <- target_train[train]
        Xtest <- predictors_matrix[test, ]
        Ytest <- target_train[test]
        
        # CORRECTIF : Calcul local, aucun emprunt à l'itération précédente
        complete_train <- !is.na(Ytrain)
        complete_test <- !is.na(Ytest)
        
        # CONTRÔLE STRICT: Vérification de la taille après filtrage NA - ASSOUPLI EN DRY-RUN
        min_train <- if (is_dry) 20 else 100
        min_test <- if (is_dry) 5 else 10
        if (sum(complete_train, na.rm = TRUE) < min_train || sum(complete_test, na.rm = TRUE) < min_test) {
          stop(sprintf("ERREUR FATALE : Fold %d trop petit après filtrage NA (train: %d < %d, test: %d < %d)", 
                       k, sum(complete_train, na.rm = TRUE), min_train, sum(complete_test, na.rm = TRUE), min_test))
        }
        
        # CONTRÔLE STRICT: Vérification des classes suffisantes
        if (length(unique(Ytrain[complete_train])) < 2 || length(unique(Ytest[complete_test])) < 2) {
          stop(sprintf("ERREUR FATALE : Fold %d mono-classe ! Train: %d classes, Test: %d classes", 
                       k, length(unique(Ytrain[complete_train])), length(unique(Ytest[complete_test]))))
        }
        
        # DIAGNOSTIC: Affichage des effectifs par classe dans ce fold
        cat(sprintf("       Dredging (train/test): %d/%d, Non-dredging (train/test): %d/%d\n",
          sum(Ytrain[complete_train], na.rm = TRUE), sum(Ytest[complete_test], na.rm = TRUE),
          sum(!Ytrain[complete_train], na.rm = TRUE), sum(!Ytest[complete_test], na.rm = TRUE)))
        
        # Régression logistique pénalisée (Ridge) - FIT SANS NA AVEC FOLDS STRATIFIÉS
        tryCatch({
          # CORRECTION: Création de folds stratifiés pour éviter les folds mono-classe internes
          set.seed(1)
          
          # CORRECTION: Fonction simple pour créer des folds sans caret
          create_simple_folds <- function(y, k = 5) {
            # Création de folds stratifiés simples
            n <- length(y)
            fold_sizes <- rep(n %/% k, k)
            remainder <- n %% k
            if (remainder > 0) {
              fold_sizes[1:remainder] <- fold_sizes[1:remainder] + 1
            }
            
            # Répartition stratifiée
            foldid <- rep(1:k, fold_sizes[1:k])
            if (length(foldid) < n) {
              foldid <- c(foldid, rep(k, n - length(foldid)))
            }
            
            # Mélange aléatoire dans chaque fold
            for (i in 1:k) {
              idx <- which(foldid == i)
              foldid[idx] <- sample(foldid[idx])
            }
            
            foldid
          }
          
          # CORRECTION: Boucle de sécurité avec compteur pour éviter l'infini
          tries <- 0
          max_tries <- 20
          repeat {
            # CORRECTIF : foldid créé sur les données déjà filtrées (complete_train)
            foldid <- create_simple_folds(Ytrain[complete_train], k = 5)
            all_ok <- all(tapply(Ytrain[complete_train], foldid, function(z) length(unique(z)) >= 2))
            tries <- tries + 1
            
            if (all_ok || tries >= max_tries) break
          }
          
          if (tries >= max_tries) {
            cat("       ⚠️  Impossible de créer des folds stratifiés après", max_tries, "tentatives\n")
            cat("       📊 Distribution des classes:", table(Ytrain[complete_train]), "\n")
          }
          
          # CORRECTIF : foldid est déjà de la bonne longueur car créé sur Ytrain[complete_train]
          fit <- cv.glmnet(Xtrain[complete_train, ], Ytrain[complete_train],
                          family = "binomial", alpha = 0,  # Ridge
                          foldid = foldid, type.measure = "auc",
                          parallel = FALSE)  # Évite le parallélisme imbriqué
          
          # Prédiction sur le fold de test SANS NA
          prob <- predict(fit, Xtest[complete_test, ], s = "lambda.min", type = "response")
          
          # Calcul AUC sur le fold de test - PROTECTION CONTRE MONO-CLASSE
          if (length(unique(Ytest[complete_test])) < 2) {
            auc_fold[k] <- NA
            cat("       Test set mono-classe (pas d'AUC)\n")
          } else {
            roc_test <- pROC::roc(Ytest[complete_test], prob, quiet = TRUE)
          auc_fold[k] <- as.numeric(pROC::auc(roc_test))
          }
          
          best_models[[as.character(k)]] <- fit
          cat(sprintf("       AUC fold %d: %.4f\n", k, auc_fold[k]))
          
        }, error = function(e) {
          cat(sprintf("       Erreur fold %d: %s\n", k, e$message))
          auc_fold[k] <- NA
        })
      }
      
      # Résultats de la validation croisée - PROTECTION CONTRE FOLDS VIDES
      valid_auc <- auc_fold[!is.na(auc_fold)]
      
      # CORRECTION: Protection contre l'échec de tous les folds
      if (all(is.na(auc_fold))) {
        stop("Tous les folds ont échoué : vérifiez la présence de valeurs non finies dans les prédicteurs.")
      }
      
      if (length(valid_auc) > 0 && length(best_models) > 0) {
        mean_auc <- mean(valid_auc)
        sd_auc <- sd(valid_auc)
        cat(sprintf("   AUC moyen CV: %.4f ± %.4f (n=%d folds)\n", mean_auc, sd_auc, length(valid_auc)))
        
        # CORRECTIF : Sécurisation de la sélection du meilleur fold
        best_fold <- which.min(abs(replace(auc_fold, is.na(auc_fold), Inf) - mean_auc))
        best_model <- best_models[[as.character(best_fold)]]
        
        # Extraction des coefficients pour le score final
        coefs <- coef(best_model, s = "lambda.min")
        coefs_named <- as.numeric(coefs)
        names(coefs_named) <- rownames(coefs)
        
        # Normalisation des coefficients pour obtenir des poids
        feature_coefs <- coefs_named[-1]  # Exclure l'intercept
        total_weight <- sum(abs(feature_coefs))
        
        # CORRECTIF 8 : Vérification plus robuste des coefficients non nuls
        if (total_weight == 0 || length(feature_coefs) == 0) {
          stop("ERREUR FATALE : Régression sans poids non nuls - Vérifiez les prédicteurs")
        }
        
        weights <- abs(feature_coefs) / total_weight
        
        # Création du score final
        # CORRECTIF 8 : Les colonnes manquantes ont déjà été ajoutées avant la CV
        # Prédiction sur **toutes** les lignes (y compris celles sans label)
        full_prob <- as.vector(predict(best_model, predictors_all, s = "lambda.min", type = "response"))
        ais[, drag_score := full_prob]
        
        # CORRECTION: Garde-fou pour les valeurs NA dans drag_score
        ais[is.na(drag_score), drag_score := 0]
        
        # Calcul du seuil optimal depuis la CV (sur les données labellisées)
        cat("   Calcul du seuil optimal...\n")
        # CORRECTIF : Probas restreintes pour calibrer le seuil (labellisées seulement)
        prob_cv <- full_prob[keep_lbl]   # garde l'indexation correcte
        roc_full <- pROC::roc(target_train, prob_cv, quiet = TRUE)
        optimal_threshold <- pROC::coords(roc_full, "best", ret = "threshold")
        best <- list(
          weights = weights,
          features = names(weights),
          mean_auc = mean_auc,
          sd_auc = sd_auc,
          auc_folds = auc_fold,
          n_folds = length(valid_auc),
          method = "Ridge_CV",
          optimal_threshold = optimal_threshold
        )
        cat(sprintf("   Seuil optimal: %.3f\n", optimal_threshold))
        
        # Application du seuil optimal sur toutes les lignes
        ais[, Dragage_flag := as.integer(drag_score >= optimal_threshold)]
        
        # Nettoyage de la mémoire après CV
        rm(best_models, predictors_train, auc_fold, valid_auc, prob_cv, roc_full)
        gc()
        cat("   Mémoire nettoyée après CV\n")
      } else {
        stop(sprintf("ERREUR FATALE : Aucun fold valide pour la CV !\n   🔍 Diagnostic: Aucun fold valide trouvé\n   📊 Résumé des AUC par fold: %s\n   📊 Nombre de modèles stockés: %d\n   📊 Vérifiez la distribution des classes par année.", 
                     paste(sprintf("%.3f", auc_fold), collapse=", "), length(best_models)))
      }
    }
    
    cat("✅ Grid-search terminé - AUC honnête calculé\n")
    list(ais = ais, best = best, auc = if(exists("valid_auc")) valid_auc else NA_real_)
  },
  force_recompute = TRUE
)

# Extraction des résultats du check-point
ais <- resGS$ais
best <- resGS$best
auc <- resGS$auc

# CORRECTION: Sauvegarde des probabilités GMM pour QA avant nettoyage
cat("💾 Sauvegarde des probabilités GMM pour vérification qualité...\n")

# CORRECTION: Gestion de la colonne ssvid vs MMSI
if ("ssvid" %in% names(ais)) {
  id_col <- "ssvid"
} else if ("MMSI" %in% names(ais)) {
  id_col <- "MMSI"
} else if ("Navire" %in% names(ais)) {
  id_col <- "Navire"
} else {
  warning("⚠️  Aucune colonne d'identifiant trouvée (ssvid/MMSI/Navire) - utilisation de la première colonne")
  id_col <- names(ais)[1]
}

# CORRECTION 2: QA robuste - ne garder que les p* existantes (dynamique selon K)
gmm_info <- attr(ais, "gmm_info")
if (!is.null(gmm_info)) {
  qa_p <- intersect(paste0("p", 1:(gmm_info$K + 1)), names(ais))
} else {
  qa_p <- intersect(paste0("p",1:5), names(ais))
}
gmm_qa_data <- ais[, c(id_col, "Timestamp", qa_p,
                       "behavior_smooth","drag_score","Dragage_flag"), with = FALSE]
setnames(gmm_qa_data, id_col, "id")

saveRDS(gmm_qa_data, file.path(output_dir, "GMM_probabilities_QA.rds"), compress = "xz")
cat("   Probabilités GMM sauvegardées dans GMM_probabilities_QA.rds (colonnes p:", paste(qa_p, collapse=", "), ")\n")

  # CORRECTION 1: Purge sécurisée des colonnes temporaires - DYNAMIQUE SELON LE MAPPING GMM
# PATCH: Conserve dredge_lisse, norm_course, norm_acc, Course_change et Accel pour QC
  # CORRECTION: Retire p_dredge de tmp_cols pour le conserver dans le dataset final
  
  # Récupérer les informations de mapping GMM pour identifier la colonne à conserver
  gmm_info <- attr(ais, "gmm_info")
  if (!is.null(gmm_info)) {
    dredge_idx <- gmm_info$dredge_idx
    dredge_col <- paste0("p", dredge_idx + 1)  # +1 car p1 = stops
    cat("   🎯 Conservation de la colonne dragage:", dredge_col, "\n")
    
    # Supprimer toutes les colonnes p* SAUF p_dredge et p1 (stops)
    all_p_cols <- paste0("p", 1:(gmm_info$K + 1))
    tmp_cols <- setdiff(all_p_cols, c("p1", dredge_col))
  } else {
    # Fallback si pas d'info GMM
    tmp_cols <- c("p2","p4","p5")
  }
  
  # Ajouter les autres colonnes temporaires (nettoyées des colonnes fantômes)
  tmp_cols <- c(tmp_cols, "speed_norm","speed_bin","comp","behavior","p_dredge_qa")

# CORRECTION 1: Purge sécurisée - ne supprime que les colonnes existantes
keep <- intersect(tmp_cols, names(ais))
if (length(keep)) {
  ais[, (keep) := NULL]
  cat("   Colonnes temporaires supprimées:", paste(keep, collapse=", "), "\n")
} else {
  cat("   Aucune colonne temporaire à supprimer\n")
}

# -- Nettoyage des colonnes de stats superflues ----------------------------
# CORRECTION: Suppression sécurisée des colonnes
todrop <- intersect(c("dt_sec", "p50_dt", "prop_long"), names(ais))
if (length(todrop)) {
  ais[, (todrop) := NULL]
  cat("   Colonnes de stats supprimées:", paste(todrop, collapse=", "), "\n")
} else {
  cat("   Aucune colonne de stats à supprimer\n")
}

# --------------------------------------------------------------------------
# 14. ── SAUVEGARDE  --------------------------------------------------------
# --------------------------------------------------------------------------
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
saveRDS(ais, file.path(output_dir,
         paste0("AIS_data_core_preprocessed_V6_", timestamp, ".rds")),
       compress = "xz")

# Sauvegarde des résultats avec la nouvelle structure
saveRDS(list(best_weights = best,
             best_auc     = if(!is.null(best$mean_auc)) best$mean_auc else NA_real_,
             auc_sd       = if(!is.null(best$sd_auc)) best$sd_auc else NA_real_,
             auc_folds    = if(!is.null(best$auc_folds)) best$auc_folds else numeric(0),  # CORRECTION: AUC complets par fold
             n_folds      = if(!is.null(best$n_folds)) best$n_folds else 0,
             method       = if(!is.null(best$method)) best$method else "unknown",
             timestamp    = timestamp),
        file.path(output_dir,
         paste0("dragage_gridsearch_results_V6_", timestamp, ".rds")),
        compress = "xz")

cat("\n💾  Fichiers sauvegardés dans", output_dir, "\n")

# NETTOYAGE QA: Suppression de la colonne de test p_dredge_qa
if ("p_dredge_qa" %in% names(ais)) {
  ais[, p_dredge_qa := NULL]
  cat("✓ Colonne QA p_dredge_qa supprimée\n")
}

# SORTIE ANTICIPÉE EN MODE DRY-RUN
if (is_dry) {
  cat("\n✅ === DRY-RUN TERMINÉ AVEC SUCCÈS ===\n")
  cat("📝 Test complet jusqu'au grid-search - Aucun fichier lourd sauvegardé\n")
  cat("🎯 Pipeline prêt pour le lancement complet\n")
  cat("⏱️  Fin dry-run :", format(Sys.time()), "\n")
  quit(save = "no")
}

cat("⏱️  Fin :", format(Sys.time()), "\n")
