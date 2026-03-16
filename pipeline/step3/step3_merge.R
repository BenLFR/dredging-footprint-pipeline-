#!/usr/bin/env Rscript
# ============================================================================
# STEP-3 — MERGE + CLEANING + GMM / GRID-SEARCH   (pipeline V6)
#   - Runs on a large node (>= 8 CPU, 32 GB RAM)
#   - Reassembles all *_clean.rds outputs from Step-2
#   - Completes the pipeline: isolated spikes, context percentiles, DBSCAN,
#     stop-GMM, smoothing, HMM, grid-search, final save.
# ============================================================================

# =============================================================================
# STEP 3: MERGE AND GRID SEARCH — WITH CHECKPOINTING SYSTEM
# =============================================================================

# Retrieve environment variables
split_job_id <- Sys.getenv("SPLIT_JOB_ID")
results_dir <- Sys.getenv("RESULTS_DIR")
cores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))

# DRY-RUN MODE DETECTION
is_dry <- Sys.getenv("DRY_RUN", "0") == "1"
if (is_dry) {
  cat("=== DRY-RUN MODE ACTIVE ===\n")
  cat("Reduced sample test — relaxed safeguards\n")
}

cat("=== STEP 3: MERGE AND GRID SEARCH (WITH CHECKPOINTING) ===\n")
cat("Split job:", split_job_id, "\n")
cat("Results directory:", results_dir, "\n")
cat("Cores:", cores, "\n")
cat("Start:", format(Sys.time()), "\n\n")

# Configuration des chemins (dynamique selon l'utilisateur)
home_dir <- path.expand("~")
scratch_dir <- path.expand(Sys.getenv("SCRATCH_DIR", unset = "~/scratch"))
output_dir  <- path.expand(Sys.getenv("OUTPUT_DIR",  unset = file.path(scratch_dir, "output_V6")))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Checkpointing system for fast restart
chk_dir <- file.path(output_dir, "checkpoints")
dir.create(chk_dir, showWarnings = FALSE, recursive = TRUE)

# Safety: remove corrupted checkpoint to force clean re-merge
unlink(file.path(chk_dir, "stage3A_fusion.rds"))

# REMOVE FAULTY CHECKPOINTS TO FORCE RECOMPUTATION
gmm_checkpoint <- file.path(chk_dir, "stage3C_gmm.rds")
dbscan_checkpoint <- file.path(chk_dir, "stage3B_dbscan.rds")

if (file.exists(gmm_checkpoint)) {
  cat("[INFO] Removing faulty GMM checkpoint to force recomputation\n")
  unlink(gmm_checkpoint)
}

if (file.exists(dbscan_checkpoint)) {
  cat("[INFO] Removing faulty DBSCAN checkpoint to force recomputation\n")
  unlink(dbscan_checkpoint)
}

checkpoint <- function(file, expr, force_recompute = FALSE) {
  file <- file.path(chk_dir, file)
  if (!force_recompute && file.exists(file)) {
    cat("[INFO] Reload checkpoint:", basename(file), "\n")
    obj <- readRDS(file)
    # Memory cleanup after reload
    gc()
    obj
  } else {
    cat("[INFO] Compute & save checkpoint:", basename(file), "\n")
    obj <- force(expr)
    saveRDS(obj, file, compress = "xz")
    cat("[INFO] Checkpoint saved:", basename(file), "\n")
    # Memory cleanup after save
    gc()
    obj
  }
}

# Détermination du dossier de résultats
if (results_dir != "" && dir.exists(results_dir)) {
  expected_dir <- results_dir
  cat("[INFO] Using specified directory:", expected_dir, "\n")
} else {
  cat("[INFO] Auto-detecting results directory...\n")

  possible_paths <- c(
    file.path(home_dir, "scratch", paste0("ais_results_", split_job_id)),
    file.path(home_dir, "scratch", paste0("ais_split_", split_job_id)),
    file.path(home_dir, "scratch", split_job_id)
  )

  expected_dir <- NULL
  for (path in possible_paths) {
    if (dir.exists(path)) {
      expected_dir <- path
      cat("[INFO] Directory found:", expected_dir, "\n")
      break
    } else {
      cat("   Not found:", path, "\n")
    }
  }

  if (is.null(expected_dir)) {
    stop("No results directory found")
  }
}

# Vérification des fichiers d'entrée
clean_files <- list.files(expected_dir, pattern = ".*_clean\\.rds$", full.names = TRUE)
if (length(clean_files) == 0) {
  stop("No *_clean.rds files found in ", expected_dir)
}

cat("[INFO] Input files verified:", length(clean_files), "*_clean.rds files found\n\n")

cat("\n=== STEP-3 | Merge & Modelling | start:", format(Sys.time()), "===\n\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
# CORRECTION: Ajouter les chemins sans écraser la config du bash
user_libs <- c("~/R/library")
.libPaths(unique(c(user_libs, .libPaths())))
cat("[INFO] R library paths:", paste(.libPaths(), collapse = " | "), "\n")

# DIAGNOSTIC DES PACKAGES - Vérification que tous les packages nécessaires sont disponibles
cat("\nDIAGNOSTIC — REQUIRED PACKAGES:\n")
needed <- c("glmnet", "doParallel", "pROC", "data.table", "dbscan", "mclust", "yaml", "geosphere", "lubridate", "zoo", "solitude", "depmixS4")
for (p in needed) {
  status <- if(requireNamespace(p, quietly=TRUE)) "OK" else "MISSING"
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

cat("Source:", split_dir, "\n")
cat("Output:", output_dir, "\n")
cat("Checkpoints:", chk_dir, "\n\n")

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

cat("[INFO] Packages loaded |", cores, "data.table threads\n")

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
  config_dir <- Sys.getenv("CONFIG_DIR", unset = "~/ais-pipeline/configuration")
  cfg <- yaml::read_yaml(file.path(config_dir, "outlier_config_V6.yaml"))
  
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
      cat("[WARN] YAML parameter missing:", param, "— using default:", default_config[[param]], "\n")
    }
  }
}, error = function(e) {
  cat("[WARN] YAML read error — using default values\n")
  cfg <<- default_config
})

# --------------------------------------------------------------------------
# 4. ── FUSION DES DONNÉES  -------------------------------------------------
# --------------------------------------------------------------------------
# CHECK-POINT 1: Fusion des données
ais <- checkpoint("stage3A_fusion.rds", {
cat("[INFO] Files found:", length(clean_files), "\n")
for (f in head(clean_files, 5)) cat("   •", basename(f), "\n")
if (length(clean_files) > 5) cat("   …\n")

t_read <- system.time({
  # lecture en parallèle (limite 4 workers → suffisamment IO-safe)
  ais_list <- mclapply(clean_files, readRDS, mc.cores = min(cores, 4))
  ais      <- rbindlist(ais_list, fill = TRUE)
})
rm(ais_list); gc()
cat(sprintf("[INFO] Merge: %s rows | %.1f s\n\n",
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
  # Ensure Navire is character type
  if (!is.character(ais$Navire)) {
    cat("[WARN] Converting Navire to character\n")
    ais[, Navire := as.character(Navire)]
  }
}

if ("ssvid" %in% names(ais)) {
  # Ensure ssvid is integer type
  if (!is.integer(ais$ssvid) && !is.numeric(ais$ssvid)) {
    cat("[WARN] Converting ssvid to integer\n")
    ais[, ssvid := as.integer(ssvid)]
  }
}

if ("Seg_id" %in% names(ais)) {
  # Ensure Seg_id is character type
  if (!is.character(ais$Seg_id)) {
    cat("[WARN] Converting Seg_id to character\n")
    ais[, Seg_id := as.character(Seg_id)]
  }
}

if ("Annee" %in% names(ais)) {
  # Ensure Annee is integer type
  if (!is.integer(ais$Annee) && !is.numeric(ais$Annee)) {
    cat("[WARN] Converting Annee to integer\n")
    ais[, Annee := as.integer(Annee)]
  }
}

# VÉRIFICATIONS SUPPLÉMENTAIRES CRITIQUES
cat("Additional critical checks...\n")

# 1. Vérification de la colonne is_stop (utilisée dans DBSCAN)
if (!"is_stop" %chin% names(ais)) {
  stop("Column 'is_stop' missing — verify that Step-2 completed successfully")
} else {
  cat("[INFO] Column 'is_stop' present\n")
}

# 2. Vérification des colonnes géographiques (utilisées dans DBSCAN)
geo_cols <- c("Lon", "Lat", "Course", "Speed")
missing_geo <- geo_cols[!geo_cols %chin% names(ais)]
if (length(missing_geo) > 0) {
  stop("Geographic columns missing: ", paste(missing_geo, collapse = ", "))
} else {
  cat("[INFO] Geographic columns present\n")
  # Convert to numeric to avoid type issues
  ais[, c("Lon", "Lat", "Course", "Speed") := lapply(.SD, as.numeric), .SDcols = c("Lon", "Lat", "Course", "Speed")]
  cat("[INFO] Geographic columns converted to numeric\n")
}

# 3. Vérification des doublons (Seg_id, Timestamp)
if (anyDuplicated(ais, by = c("Seg_id", "Timestamp"))) {
  warning("[WARN] Duplicates detected in (Seg_id, Timestamp) — removing...")
  ais <- unique(ais, by = c("Seg_id", "Timestamp"))
  cat("[INFO] Duplicates removed\n")
} else {
  cat("[INFO] No duplicates detected\n")
}

# 4. Vérification de la mémoire disponible
mem_usage <- object.size(ais) / 1024^3  # GB
cat(sprintf("Memory usage: %.2f GB\n", mem_usage))

if (mem_usage > 50) {
  warning("[WARN] High memory usage: ", round(mem_usage, 1), " GB")
}

cat("[INFO] Column types verified and corrected\n\n")

# --------------------------------------------------------------------------
# CONTRÔLE STRICT DES EFFECTIFS - ARRÊT EN CAS DE PROBLÈME
# --------------------------------------------------------------------------
n_total <- nrow(ais)  # Effectif initial
cat("=== STRICT SAMPLE-SIZE CHECK ===\n")
cat(sprintf("Total points at start: %d\n", n_total))

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

# DBSCAN helpers - FIX P0.2: Projection en mètres + kNNdist (évite O(n²))
to_xy_m <- function(lon, lat) {
  # Projection simple: coordonnées (lon, lat) → (x, y) en mètres
  lat0 <- mean(lat, na.rm = TRUE) * pi / 180
  x <- lon * 111320 * cos(lat0)
  y <- lat * 110574
  cbind(x, y)
}

auto_eps_m <- function(xy, k = 4) {
  # Calcul eps en mètres via kNNdist (O(n log n) au lieu de O(n²))
  # FIX: k_eff pour éviter crash si n <= k
  n <- nrow(xy)
  k_eff <- min(k, max(1, n - 1))
  d <- dbscan::kNNdist(xy, k = k_eff)
  # Seuil minimum de 200m, sinon 1% de la médiane
  pmax(200, 0.01 * median(d, na.rm = TRUE))
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
cat("Detecting isolated temporal spikes...\n")
n_before_spike <- nrow(ais)
ais[, outlier_spike := detect_spikes(Speed,
                        spike_factor = cfg$spike_factor,
                        min_iso      = cfg$min_spike_duration),
    by = Seg_id]
ais <- ais[outlier_spike == FALSE | is.na(outlier_spike)]
check_filter("Filtre Spikes", n_before_spike, nrow(ais))
ais[, outlier_spike := NULL]

# --------------------------------------------------------------------------
# 8. ── PERCENTILES CONTEXTUELS  (Step-5) - SUPPRIMÉ ------------------------
# --------------------------------------------------------------------------
# Section supprimée pour simplifier le pipeline
# Les percentiles contextuels ne sont pas utilisés dans les étapes suivantes
# (DBSCAN, GMM, Grid-search) et peuvent être retirés sans impact

# --------------------------------------------------------------------------
# 9. ── DÉTECTION DES ARRÊTS SPATIAUX (DBSCAN) ------------------------------
# --------------------------------------------------------------------------
# CHECK-POINT 2: DBSCAN terminé
ais <- checkpoint("stage3B_dbscan.rds", {
cat("Detecting spatial stops via DBSCAN...\n")

# OPTIMISATION: Protection contre les petits navires et approche plus robuste
ais[, stop_cluster := NA_integer_]

# FIX: Comptage avec filtre Lon ET Lat (évite de skip tout un navire pour 1 NA)
stop_counts <- ais[is_stop == TRUE & !is.na(Lon) & !is.na(Lat), .N, by = .(Navire, Annee)]
stop_counts <- stop_counts[N >= 4]  # Seulement les navires avec suffisamment de points

if (nrow(stop_counts) > 0) {
  cat("DBSCAN: processing", nrow(stop_counts), "vessel/year combinations\n")

  for (i in 1:nrow(stop_counts)) {
    navire <- stop_counts$Navire[i]
    annee <- stop_counts$Annee[i]

    # FIX: Sélection via .I pour assignation bulletproof (alignement garanti)
    idx <- ais[Navire == navire & Annee == annee & is_stop == TRUE &
               !is.na(Lon) & !is.na(Lat), which = TRUE]
    arr <- ais[idx]

    if (length(idx) >= 4) {
      # PROTECTION: Vérification de la variance des coordonnées
      if (var(arr$Lon, na.rm = TRUE) < 1e-8 || var(arr$Lat, na.rm = TRUE) < 1e-8) {
        cat("[WARN] Insufficient coordinate variance for", navire, annee, "— skipping\n")
        next
      }

      tryCatch({
        # FIX P0.2: Projection en mètres (cohérence métrique + eps stable)
        xy <- to_xy_m(arr$Lon, arr$Lat)

        # Protection contre les gros arrêts (échantillonnage pour eps)
        if (nrow(xy) > 5000) {
          cat("[WARN] Large stop detected for", navire, annee, "(", nrow(xy), "points) — sampling for eps\n")
          set.seed(123)
          samp_idx <- sample(nrow(xy), 5000)
          eps <- auto_eps_m(xy[samp_idx, , drop = FALSE])
        } else {
          eps <- auto_eps_m(xy)
        }

        # DBSCAN en coordonnées métriques (xy en mètres)
        cl <- dbscan(xy, eps = eps, minPts = 4)$cluster

        # Protection contre les clusters vides
        if (sum(cl > 0) == 0) {
          cat("[WARN] No cluster found for", navire, annee, "— widening eps radius\n")
          eps <- eps * 1.5
          cl <- dbscan(xy, eps = eps, minPts = 4)$cluster
        }

        # FIX: Assignation via idx (bulletproof, alignement garanti)
        ais[idx, stop_cluster := cl]
      }, error = function(e) {
        cat("[WARN] DBSCAN error for", navire, annee, ":", e$message, "\n")
      })
    }
  }
} else {
  cat("[WARN] No vessel with enough stop points for DBSCAN\n")
}

ais[, is_stop_spatial := is_stop & !is.na(stop_cluster) & stop_cluster > 0]
  
  cat("[INFO] DBSCAN complete — checkpoint saved\n")
  
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
    stop("CRITICAL: Column 'is_stop_spatial' missing after DBSCAN")
  }
  cat("[INFO] Column 'is_stop_spatial' present\n")
  
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
# FIX P0.3: Ajout by = Seg_id pour éviter les diffs inter-segments
ais[, Course_change := c(NA, abs(diff(Course))), by = Seg_id]
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
cadence[, n_min := pmin(n_max_cap, pmax(3, ceiling(p50_dt / t_seuil)))]

# 9) Join avec l'ensemble principal
ais <- merge(ais, cadence[, .(Navire, n_min, seuil_adaptatif, p50_dt, prop_long)], by = "Navire", all.x = TRUE)

# 10) Filtrage avec seuil adaptatif (parenthèses pour clarifier la logique)
cat("AIS cadence & adaptive thresholds per vessel\n")
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

  cat("GMM 'stop + K mobile' — K selection by BIC (3-5) — robust\n")

  ## 0. Préparation ----------------------------------------------------------
  idx_mobile <- which(!ais$is_stop_spatial & ais$Speed >= 0.5 & ais$Speed <= 20)

  # CORRECTION: Recalcul des quantiles après tous les filtres pour éviter le biais
  q95_acc  <- quantile(abs(ais$Accel),  .95, na.rm = TRUE);  if (!is.finite(q95_acc)  || q95_acc  == 0) q95_acc  <- 1e-6
  q95_turn <- quantile(ais$Course_change, .95, na.rm = TRUE); if (!is.finite(q95_turn) || q95_turn == 0) q95_turn <- 1e-6
  
  cat("   Quantiles recomputed after filters — Accel 95%:", round(q95_acc, 4), "| Course 95%:", round(q95_turn, 2), "deg\n")

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
    stop("Not enough complete mobile points to fit GMM (", nrow(X), " < ", min_mobile, ")")

  ## 1. Recherche du meilleur K (BIC) - ROBUSTE ------------------------------
  # CORRECTION 5: Protection contre l'overflow mémoire Mclust
  samp <- if (nrow(X) > 1e6) X[sample(nrow(X), 1e6), ] else X
  cat("   Sample for BIC:", nrow(samp), "points (of", nrow(X), ")\n")
  
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
    stop("Mclust failed for all K values — X may be too large or ill-conditioned")
  
  K <- G_choices[which.max(bic_vals)]
  
  # CORRECTION 4: Vérification de la borne basse K >= 3
  if (K < 3) stop("GMM must have at least 3 mobile components (dredge/transit)")

  cat("   K selected by BIC:", K, "mobile components\n")

  ## 2. Ajustement définitif -------------------------------------------------
  # CORRECTION 3: Protection mémoire pour l'ajustement final
  X_fit <- if (nrow(X) > 2e6) X[sample(nrow(X), 2e6), ] else X
  cat("   Sample for final fit:", nrow(X_fit), "points (of", nrow(X), ")\n")
  
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

  ## 5. Étiquettes brutes - OPTION A: Mapping robuste multi-composantes lentes
  # FIX P0: Alignement correct mobi_keep / Zord pour le score de stabilité
  # FIX P1: Séparation idle (μ<1) / slow (1≤μ<6) / transit (μ≥6)
  # Garantit que AUCUN transit n'a μ < 6 kn

  ## --- FIX P0: Aligner mobi avec Zord (mobi_keep) + max.col() rapide --- ##
  mobi_keep <- mobi[keep]  # aligne exactement les lignes avec X / Zord
  comp_hat  <- max.col(Zord, ties.method = "first")  # 1..K, cohérent avec mu / ord

  ## --- Mapping robuste des composantes (Option A corrigé) --------------- ##
  # Paramètres généraux
  dredge_range <- c(1, 3.5)           # fenêtre (kn) considérée comme dragage
  slow_ceiling <- 6                    # μ < 6 kn = jamais transit

  # 1) Identifier les composantes par plage de vitesse (FIX P1)
  idle_candidates   <- which(mu < 1)                                    # μ < 1 kn → other

  slow_candidates   <- which(mu >= 1 & mu < slow_ceiling)               # μ ∈ [1, 6) kn
  dredge_candidates <- which(mu >= dredge_range[1] & mu <= dredge_range[2])  # μ ∈ [1, 3.5] kn

  cat("   Idle components (mu < 1 kn):", paste(idle_candidates, collapse=", "), "\n")
  cat("   Slow components (1 <= mu < 6 kn):", paste(slow_candidates, collapse=", "), "\n")
  cat("   Dredging candidates [1-3.5 kn]:", paste(dredge_candidates, collapse=", "), "\n")

  # 2) Sélection robuste de la composante dragage (FIX P0: mobi_keep + comp_hat)
  if (length(dredge_candidates) > 0) {
    if (length(dredge_candidates) == 1) {
      dredge_comp <- dredge_candidates
    } else {
      # Plusieurs candidats: score de stabilité = mean(norm_course) - mean(norm_acc)
      # Le dragage a une route stable (norm_course élevé) et accélération faible
      stability_scores <- vapply(dredge_candidates, function(j) {
        m <- (comp_hat == j)
        if (sum(m) < 10) return(-Inf)
        mean(mobi_keep$norm_course[m], na.rm = TRUE) -
          mean(mobi_keep$norm_acc[m], na.rm = TRUE)
      }, numeric(1))

      # Sélection par score de stabilité, tie-breaker = plus proche de 2 kn
      best_score <- max(stability_scores, na.rm = TRUE)
      top_candidates <- dredge_candidates[stability_scores >= best_score - 0.05]
      dredge_comp <- top_candidates[which.min(abs(mu[top_candidates] - 2))]

      cat("   Stability scores:", paste(round(stability_scores, 3), collapse=", "), "\n")
    }
  } else {
    # Fallback: plus proche de 2 kn parmi toutes les composantes
    dredge_comp <- which.min(abs(mu - 2))
    cat("   [WARN] No candidate in [1-3.5 kn] — fallback to mu =", round(mu[dredge_comp], 2), "kn\n")
  }

  # 3) Les autres composantes lentes (hors dredge) → slow_maneuvers (FIX P1)
  other_slow_idx <- setdiff(slow_candidates, dredge_comp)

  # 4) Composantes transit: UNIQUEMENT μ >= 6 kn
  transit_pool <- which(mu >= slow_ceiling)

  cat("   Transit pool (mu >= 6 kn):", paste(transit_pool, collapse=", "), "\n")

  # 5) Construction des labels
  mobile_labels <- character(K)
  mobile_labels[dredge_comp] <- "dredging"

  # FIX P1: idle_candidates (μ < 1 kn) → "other"
  if (length(idle_candidates) > 0) {
    mobile_labels[idle_candidates] <- "other"
  }

  # slow_maneuvers pour les lentes hors dredging
  if (length(other_slow_idx) > 0) {
    mobile_labels[other_slow_idx] <- "slow_maneuvers"
  }

  if (length(transit_pool) >= 2) {
    # 2+ transits: loaded (plus lent) et unloaded (plus rapide)
    loaded_idx <- transit_pool[1]
    unloaded_idx <- transit_pool[length(transit_pool)]
    mobile_labels[loaded_idx] <- "loaded_transit"
    mobile_labels[unloaded_idx] <- "unloaded_transit"
    # Intermédiaires = other
    middle_transit <- setdiff(transit_pool, c(loaded_idx, unloaded_idx))
    if (length(middle_transit) > 0) mobile_labels[middle_transit] <- "other"
  } else if (length(transit_pool) == 1) {
    # 1 seul transit: unloaded_transit
    mobile_labels[transit_pool] <- "unloaded_transit"
  }
  # else: pas de transit (toutes les composantes sont lentes)

  # 6) Tout ce qui reste = "other"
  mobile_labels[mobile_labels == ""] <- "other"

  ## --- Post-mapping assertions ------------------------------------------ ##
  # ASSERTION 0 (BONUS): dredge_comp doit être unique et défini
  if (length(dredge_comp) != 1) {
    stop(sprintf("ERREUR MAPPING: dredging non-unique ou absent (dredge_comp = %s)",
                 paste(dredge_comp, collapse=", ")))
  }

  # ASSERTION 1: Aucun transit avec μ < 6 kn
  transit_labels <- c("loaded_transit", "unloaded_transit")
  for (lbl in transit_labels) {
    idx <- which(mobile_labels == lbl)
    if (length(idx) > 0 && any(mu[idx] < slow_ceiling)) {
      stop(sprintf("ERREUR MAPPING: %s assigné à μ = %.2f kn (< %.1f kn)\n  mu = %s\n  labels = %s",
                   lbl, mu[idx[mu[idx] < slow_ceiling]], slow_ceiling,
                   paste(round(mu, 2), collapse=" / "),
                   paste(mobile_labels, collapse=" → ")))
    }
  }

  # ASSERTION 2: Diagnostic dump systématique
  cat("\n   === MAPPING DIAGNOSTIC ===\n")
  mapping_dt <- data.table(comp = 1:K, mu_kn = round(mu, 2), label = mobile_labels)
  print(mapping_dt)
  cat("   ===========================\n\n")

  map <- c("stops", mobile_labels)             # longueur = K+1 (p1…p{K+1})

  cat("   Labels assigned:", paste(mobile_labels, collapse=" -> "), "\n")
  cat("   Corresponding speeds:", paste(round(mu, 2), "kn", collapse=" -> "), "\n")
  cat("   Dredging component: mu =", round(mu[dredge_comp], 2), "kn (index", dredge_comp, ")\n")

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
  # FIX P1: Utilise dredge_state pour éviter le shadowing de dredge_comp
  if ("dredging" %in% all_labels) {
    dredge_state <- which(all_labels == "dredging")  # index dans all_labels (1..n_labels)
    # Dredging ↔ transit = coût modéré
    transit_labels_cost <- setdiff(all_labels, c("stops", "dredging"))
    for (tl in transit_labels_cost) {
      tl_idx <- which(all_labels == tl)
      cost_matrix[dredge_state, tl_idx] <- 3
      cost_matrix[tl_idx, dredge_state] <- 3
    }
  }

  # Coûts vers/depuis stops (transitions rares)
  stops_state <- which(all_labels == "stops")
  cost_matrix[stops_state, ] <- 4
  cost_matrix[, stops_state] <- 4
  cost_matrix[stops_state, stops_state] <- 0

  # CORRECTION: Coût réduit pour dredging ↔ stops (plus naturel)
  if ("dredging" %in% all_labels) {
    dredge_state <- which(all_labels == "dredging")
    cost_matrix[dredge_state, stops_state] <- 3
    cost_matrix[stops_state, dredge_state] <- 3
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
  cat("   Smoothing threshold (75th percentile n_min):", round(lissage_threshold, 1), "\n")
  
  ais[, behavior_smooth :=
        smooth_transition_robust(behavior, Speed,
                                thr = lissage_threshold,
                                dredge_min = 1, dredge_max = 3.5),
      by = Seg_id]

  ais[, dredge_lisse := as.integer(behavior_smooth == "dredging")]

  ## 7. Normalisés pour le score dragage -------------------------------------
  ais[, norm_course := pmax(0, pmin(1, 1 - Course_change / q95_turn))]
  ais[, norm_acc    := pmax(0, pmin(1, abs(Accel) / q95_acc))]

  cat("[INFO] Robust GMM complete —", table(ais$behavior_smooth), "states after smoothing\n")
  
  # VÉRIFICATION DES CLASSES APRÈS GMM (pour dry-run)
  if (is_dry) {
    n_classes <- length(unique(ais$behavior_smooth))
    if (n_classes < 2) {
      stop(sprintf("ERREUR FATALE : Échantillon DRY-RUN mono-classe après GMM (%d classe) – reprenez un autre sous-ensemble", n_classes))
    }
    cat("   [INFO] Dry-run:", n_classes, "classes detected after GMM\n")
  }
  
  # CORRECTION: Sauvegarder les informations de mapping pour la suite (optimisé)
  # Utilisation d'attributs pour éviter la duplication en RAM
  # BONUS: Utilise dredge_comp (déjà validé unique) au lieu de recalculer
  attr(ais, "gmm_info") <- list(
    K = K,
    dredge_idx = dredge_comp,          # 1..K (index dans mobile_labels)
    dredge_speed = mu[dredge_comp],
    mobile_labels = mobile_labels,
    mu = mu
  )
  
  ## ═══════════════════════════════════════════════════════════════════════
  ## QA REFACTORED: QA1 (pre-smooth, hard) + QA2 (post-smooth, soft)
  ## FIX P1: Utilise dredge_comp (déjà validé) au lieu de recalculer
  ## ═══════════════════════════════════════════════════════════════════════

  dredge_col <- paste0("p", dredge_comp + 1)  # +1 car p1 = stops
  ais[, p_dredge_qa := get(dredge_col)]

  ## ─────────────────  SANITY-CHECK  ─────────────────
  # 1) Remplacer tout NA par 'unknown'
  ais[is.na(behavior_smooth), behavior_smooth := "unknown"]
  ## ───────────────────────────────────────────────────

  ## --- QA1: PRE-SMOOTH (hard check on argmax) ---
  # Sur behavior (pré-lissage), les points "dredging" DOIVENT avoir p_dredge comme argmax
  raw_dredge_mask <- ais$behavior == "dredging"
  n_raw_dredge <- sum(raw_dredge_mask, na.rm = TRUE)

  if (n_raw_dredge > 0) {
    proba_cols <- paste0("p", 1:(K+1))
    max_proba_col <- apply(ais[raw_dredge_mask, proba_cols, with=FALSE], 1, which.max)
    expected_col <- dredge_comp + 1  # +1 car p1 = stops

    n_correct <- sum(max_proba_col == expected_col, na.rm = TRUE)
    qa1_rate <- n_correct / n_raw_dredge

    if (qa1_rate >= 0.99) {
      cat(sprintf("   [INFO] QA1 (pre-smooth): %.1f%% of dredging points have p_dredge=argmax\n", 100*qa1_rate))
    } else if (qa1_rate >= 0.90) {
      cat(sprintf("   [WARN] QA1 (pre-smooth): %.1f%% only (expected >=99%%) — check mapping\n", 100*qa1_rate))
    } else {
      cat(sprintf("   [ERROR] QA1 (pre-smooth): FAIL — only %.1f%% (expected >=90%%)\n", 100*qa1_rate))
      cat("      Diagnostic: argmax distribution =", paste(names(table(max_proba_col)), table(max_proba_col), sep=":", collapse=", "), "\n")
    }
  } else {
    cat("   [WARN] QA1: No 'dredging' points pre-smoothing\n")
  }

  ## --- QA2: POST-SMOOTH (soft check on p_dredge distribution) ---
  # Sur behavior_smooth, les points "dredging" devraient avoir p_dredge élevé (médiane ≥ 0.5)
  # Mais le lissage peut re-labeler des segments, donc ce n'est qu'un warning
  smooth_dredge_mask <- ais$behavior_smooth == "dredging"
  n_smooth_dredge <- sum(smooth_dredge_mask, na.rm = TRUE)

  if (n_smooth_dredge > 0) {
    p_dredge_smooth <- ais[smooth_dredge_mask, p_dredge_qa]
    q <- quantile(p_dredge_smooth, probs = c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE)

    if (q["50%"] >= 0.5) {
      cat(sprintf("   [INFO] QA2 (post-smooth): p_dredge median = %.3f (>=0.5)\n", q["50%"]))
    } else if (q["50%"] >= 0.3) {
      cat(sprintf("   [WARN] QA2 (post-smooth): p_dredge median = %.3f (low, expected >=0.5)\n", q["50%"]))
      cat(sprintf("      Quantiles: 10%%=%.3f, 25%%=%.3f, 50%%=%.3f, 75%%=%.3f, 90%%=%.3f\n",
                  q["10%"], q["25%"], q["50%"], q["75%"], q["90%"]))
    } else {
      cat(sprintf("   [ERROR] QA2 (post-smooth): p_dredge median = %.3f (very low!)\n", q["50%"]))
      cat(sprintf("      Quantiles: 10%%=%.3f, 25%%=%.3f, 50%%=%.3f, 75%%=%.3f, 90%%=%.3f\n",
                  q["10%"], q["25%"], q["50%"], q["75%"], q["90%"]))
      cat("      [WARN] Smoothing may have over-extended dredging segments\n")
    }
  } else {
    cat("   [WARN] QA2: No 'dredging' points post-smoothing\n")
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
    cat("Grid-search (dredging score weights) — corrected to avoid data leakage\n")
    
    # CORRECTION MAJEURE: Éviter le data leakage
    # 1) Définir les blocs CV (leave-one-year-out) - GARANTIE LOYO STRICTE
    # === LOYO: 1 année = 1 fold (conformité section 2.6) ===
    cv_folds <- length(unique(ais$Annee))  # Force exactement 1 année = 1 fold
    ais[, fold := frank(Annee, ties.method="dense")]
    
    cat("   Validation croisée LOYO stricte:", cv_folds, "folds (1 année = 1 fold)\n")
    
    # 2) Retirer le label dérivé des prédicteurs (ÉVITE DATA LEAKAGE)
    # Au lieu de dredge_lisse, utiliser p_dredge (probabilité GMM) + signaux cinématiques
    # === COMPOSITE DREDGING SCORE: 5 signaux → cv.glmnet (ridge) → LOYO → Youden J ===
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
      stop("GMM mapping information missing (attribute gmm_info)")
    }
    
    dredge_idx <- gmm_info$dredge_idx
    dredge_speed <- gmm_info$dredge_speed
    gmm_k <- gmm_info$K
    
    # Créer la colonne p_dredge avec la bonne probabilité
    dredge_col <- paste0("p", dredge_idx + 1)  # +1 car p1 = stops
    if (!dredge_col %in% names(ais)) {
      stop(sprintf("Column %s missing (dredge_idx=%d)", dredge_col, dredge_idx))
    }

    ais[, p_dredge := get(dredge_col)]
    cat(sprintf("   [INFO] Dredging probability: %s (component %d, speed %.2f kn, K=%d)\n",
                dredge_col, dredge_idx, dredge_speed, gmm_k))
    
    # Prédicteurs indépendants du label final
    predictors <- ais[, .(p_dredge, norm_course, norm_acc, speed_bin, speed_norm)]
    target <- ais$behavior_smooth == "dredging"
    
    # === SÉCURITÉ: Vérification exactement 5 signaux (conformité section 2.6) ===
    stopifnot(identical(colnames(predictors), 
                        c("p_dredge", "norm_course", "norm_acc", "speed_bin", "speed_norm")))
    cat("   ✅ Vérification: Exactement 5 signaux requis pour le composite score\n")
    
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
    cat("[INFO] Non-finite values replaced with 0\n")
    
    # CORRECTION CRITIQUE: Nettoyage des NA dans target (PRÉSERVATION DES DONNÉES)
    cat("   Removing NA from target variable...\n")
    keep_lbl <- !is.na(target)
    n_before <- nrow(ais)
    n_filtered <- sum(!keep_lbl)
    
    cat(sprintf("   Points with NA in target: %d (%.2f%%)\n",
                n_filtered, 100 * n_filtered / n_before))
    
    # CONTRÔLE STRICT: Vérification qu'il ne reste plus de NA
    if (any(is.na(target[keep_lbl]))) {
      stop("ERREUR FATALE : NA détectés dans target après filtrage !")
    }
    
    # Conversion en entier 0/1 (glmnet préfère numérique) - SEULEMENT pour l'entraînement
    target_train <- as.integer(target[keep_lbl])  # 1 = dredging, 0 = non-dredging
    
    # PRÉSERVATION: Garder les indices pour réinsérer les prédictions
    train_indices <- which(keep_lbl)
    # FIX P2.3: cat() n'interprète pas %d → utiliser sprintf()
    cat(sprintf("   [INFO] Data preserved: %d training points, %d points for full prediction\n",
                length(train_indices), n_before))
    
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
    
    # FIX P2.1: Résumé long-format au lieu de table 3D (évite explosion mémoire)
    cat("   📊 Distribution des classes par année/navire (top 20):\n")
    ais_train <- ais[keep_lbl]
    ais_train[, target_tmp := target_train]
    class_summary <- ais_train[, .N, by = .(Annee, Navire, target_tmp)][order(Annee, -N)]
    print(head(class_summary, 20))
    ais_train[, target_tmp := NULL]  # nettoyage
    
    # Vérification critique des classes avant CV (sur les données d'entraînement)
    if (length(unique(target_train)) < 2) {
      stop(sprintf("ERREUR FATALE : Dataset mono-classe ! Seulement %d classe(s) détectée(s), impossible de faire une CV valide.\n   📊 Distribution: %s", 
                   length(unique(target_train)), paste(table(target_train), collapse=", ")))
    } else {
      # CORRECTION 1: Vérification des packages offline avant CV
      cat("   Vérification des packages requis...\n")
      if (!requireNamespace("glmnet", quietly = TRUE)) {
        stop("Package 'glmnet' not found — install via module or $R_LIBS_USER")
      }
      if (!requireNamespace("doParallel", quietly = TRUE)) {
        stop("Package 'doParallel' not found — install via module or $R_LIBS_USER")
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
  stop("Package 'Matrix' not found — install via module or $R_LIBS_USER")
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
      cat("   Class distribution by fold (training data):\n")
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
        
        # FIX P0.4: LOYO mono-class check
        # Train DOIT avoir 2 classes (sinon impossible de fitter)
        # Test peut être mono-classe → AUC = NA (pas stop)
        train_has_2 <- length(unique(Ytrain[complete_train])) >= 2
        test_has_2 <- length(unique(Ytest[complete_test])) >= 2

        if (!train_has_2) {
          stop(sprintf("ERREUR FATALE : Fold LOYO %d - train mono-classe (impossible de fitter)", k))
        }

        # DIAGNOSTIC: Affichage des effectifs par classe dans ce fold
        cat(sprintf("       Dredging (train/test): %d/%d, Non-dredging (train/test): %d/%d\n",
          sum(Ytrain[complete_train], na.rm = TRUE), sum(Ytest[complete_test], na.rm = TRUE),
          sum(!Ytrain[complete_train], na.rm = TRUE), sum(!Ytest[complete_test], na.rm = TRUE)))

        if (!test_has_2) {
          cat("       [WARN] Test fold is single-class — AUC = NA for this fold\n")
        }

        # Régression logistique pénalisée (Ridge) - FIT SANS NA AVEC FOLDS STRATIFIÉS
        tryCatch({
          # CORRECTION: Création de folds stratifiés pour éviter les folds mono-classe internes
          set.seed(1)

          # FIX P2.4: Fonction de stratification qui stratifie vraiment
          make_stratified_foldid <- function(y, k = 5, seed = 1) {
            set.seed(seed)
            y <- as.integer(y)
            n1 <- sum(y == 1); n0 <- sum(y == 0)
            k_eff <- min(k, n1, n0)  # évite folds vides
            if (k_eff < 2) k_eff <- 2  # minimum 2 folds
            foldid <- integer(length(y))
            foldid[y == 1] <- sample(rep(1:k_eff, length.out = n1))
            foldid[y == 0] <- sample(rep(1:k_eff, length.out = n0))
            foldid
          }
          
          # FIX P2.4: Utilisation de la vraie stratification
          foldid <- make_stratified_foldid(Ytrain[complete_train], k = 5, seed = k)

          # FIX: Garde-fou - si certains folds internes sont mono-classe, fallback deviance
          folds_ok <- all(tapply(Ytrain[complete_train], foldid,
                                 function(z) length(unique(z)) >= 2))
          measure_type <- if (folds_ok) "auc" else "deviance"
          if (!folds_ok) cat("       [WARN] Internal folds unbalanced — fallback to deviance\n")

          # CORRECTIF : foldid est déjà de la bonne longueur car créé sur Ytrain[complete_train]
          fit <- cv.glmnet(Xtrain[complete_train, ], Ytrain[complete_train],
                          family = "binomial", alpha = 0,  # Ridge
                          foldid = foldid, type.measure = measure_type,
                          parallel = FALSE)  # Évite le parallélisme imbriqué

          # Prédiction sur le fold de test SANS NA
          prob <- predict(fit, Xtest[complete_test, ], s = "lambda.min", type = "response")

          # FIX P0.4: Calcul AUC - utilise test_has_2 déjà calculé
          if (!test_has_2) {
          auc_fold[k] <- NA_real_
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
        
        # === EXPORT DES POIDS: Sauvegarde des coefficients normalisés ===
        fwrite(data.table(feature = names(weights), weight = weights),
               file.path(output_dir, "drag_score_weights.csv"))
        cat("   [INFO] Composite score weights saved to drag_score_weights.csv\n")
        
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
        optimal_threshold <- as.numeric(pROC::coords(roc_full, "best", ret = "threshold")[["threshold"]])
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
    
    cat("[INFO] Grid-search complete — honest AUC computed\n")
    list(ais = ais, best = best, auc = if(exists("valid_auc")) valid_auc else NA_real_)
  },
  force_recompute = TRUE
)

# Extraction des résultats du check-point
ais <- resGS$ais
best <- resGS$best
auc <- resGS$auc

# CORRECTION: Sauvegarde des probabilités GMM pour QA avant nettoyage
cat("[INFO] Saving GMM probabilities for quality verification...\n")

# CORRECTION: Gestion de la colonne ssvid vs MMSI
if ("ssvid" %in% names(ais)) {
  id_col <- "ssvid"
} else if ("MMSI" %in% names(ais)) {
  id_col <- "MMSI"
} else if ("Navire" %in% names(ais)) {
  id_col <- "Navire"
} else {
  warning("[WARN] No identifier column found (ssvid/MMSI/Navire) — using first column")
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

## ─────────────────  VERROU GLOBAL FINAL  ─────────────────
# Garantir qu'aucun NA ne subsiste dans behavior_smooth avant l'export
stopifnot(!anyNA(ais$behavior_smooth))
cat("✅ Verrou global: Aucun NA dans behavior_smooth - Pipeline hermétique\n")
## ─────────────────────────────────────────────────────────

# CORRECTION: Sauvegarde APRÈS la grid-search pour inclure Dragage_flag
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
