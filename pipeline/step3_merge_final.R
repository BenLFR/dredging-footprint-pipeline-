#!/usr/bin/env Rscript
# ============================================================================
# STEP-3  ─  MERGE  +  CLEAN  +  GMM / GRID-SEARCH   (pipeline  V6)
#   • Runs on a large node (>= 8 CPU, 32 GB RAM)
#   • Reassembles all *_clean.rds files produced by Step-2
#   • Completes the pipeline: isolated spikes, context percentiles, DBSCAN,
#     stop-GMM, smoothing, HMM, grid-search, final save.
# ============================================================================

# =============================================================================
# STEP 3: MERGE AND GRID SEARCH - WITH CHECK-POINTING SYSTEM
# =============================================================================

# Read environment variables
split_job_id <- Sys.getenv("SPLIT_JOB_ID")
results_dir <- Sys.getenv("RESULTS_DIR")
cores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))

# DRY-RUN MODE DETECTION
is_dry <- Sys.getenv("DRY_RUN", "0") == "1"
if (is_dry) {
  cat(" === MODE DRY-RUN ACTIVÉ ===\n")
  cat(" Test sur échantillon réduit - Garde-fous assouplis\n")
}

cat(" === ÉTAPE 3: FUSION ET GRID SEARCH (AVEC CHECK-POINTING) ===\n")
cat(" Job fractionnement:", split_job_id, "\n")
cat(" Dossier résultats:", results_dir, "\n")
cat("  Cores:", cores, "\n")
cat("  Début:", format(Sys.time()), "\n\n")

# Path configuration (dynamic based on home directory)
home_dir <- path.expand("~")
output_dir <- file.path(home_dir, "scratch/output_V6")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Check-pointing system for fast restarts
chk_dir <- file.path(output_dir, "checkpoints")
dir.create(chk_dir, showWarnings = FALSE, recursive = TRUE)

# Safety: remove corrupted merge checkpoint to force clean remerge
unlink(file.path(chk_dir, "stage3A_fusion.rds"))

# Remove stale checkpoints to force recomputation
gmm_checkpoint <- file.path(chk_dir, "stage3C_gmm.rds")
dbscan_checkpoint <- file.path(chk_dir, "stage3B_dbscan.rds")

if (file.exists(gmm_checkpoint)) {
  cat("  Suppression du checkpoint GMM fautif pour forcer le recalcul\n")
  unlink(gmm_checkpoint)
}

if (file.exists(dbscan_checkpoint)) {
  cat("  Suppression du checkpoint DBSCAN fautif pour forcer le recalcul\n")
  unlink(dbscan_checkpoint)
}

checkpoint <- function(file, expr, force_recompute = FALSE) {
  file <- file.path(chk_dir, file)
  if (!force_recompute && file.exists(file)) {
    cat("  Reload checkpoint:", basename(file), "\n")
    obj <- readRDS(file)
    # Memory cleanup after reload
    gc()
    obj
  } else {
    cat("Compute & save checkpoint:", basename(file), "\n")
    obj <- force(expr)
    saveRDS(obj, file, compress = "xz")
    cat("Checkpoint saved:", basename(file), "\n")
    # Memory cleanup after save
    gc()
    obj
  }
}

# Determine results directory
if (results_dir != "" && dir.exists(results_dir)) {
  expected_dir <- results_dir
  cat(" Utilisation du dossier spécifié:", expected_dir, "\n")
} else {
  cat(" Auto-détection du dossier de résultats...\n")
  
  possible_paths <- c(
    file.path(home_dir, "scratch", paste0("ais_results_", split_job_id)),
    file.path(home_dir, "scratch", paste0("ais_split_", split_job_id)),
    file.path(home_dir, "scratch", split_job_id)
  )
  
  expected_dir <- NULL
  for (path in possible_paths) {
    if (dir.exists(path)) {
      expected_dir <- path
      cat(" Dossier trouvé:", expected_dir, "\n")
      break
    } else {
      cat("    Non trouvé:", path, "\n")
    }
  }
  
  if (is.null(expected_dir)) {
    stop(" ERREUR: Aucun dossier de résultats trouvé")
  }
}

# Input file verification
clean_files <- list.files(expected_dir, pattern = ".*_clean\\.rds$", full.names = TRUE)
if (length(clean_files) == 0) {
  stop(" ERREUR: Aucun fichier *_clean.rds trouvé dans ", expected_dir)
}

cat(" Fichiers d'entrée vérifiés:", length(clean_files), "fichiers *_clean.rds trouvés\n\n")

cat("\n  STEP-3  |  Fusion & Modélisation  |  début :", format(Sys.time()), "\n\n")

# CRITICAL R CONFIGURATION - BEFORE LOADING PACKAGES
# Prepend user library path without overwriting bash config
user_libs <- c("~/R/library")
.libPaths(unique(c(user_libs, .libPaths())))
cat(" R cherchera les packages dans :", paste(.libPaths(), collapse = " | "), "\n")

# DIAGNOSTIC DES PACKAGES - Check that all required packages are available
cat("\n DIAGNOSTIC DES PACKAGES REQUIS:\n")
needed <- c("glmnet", "doParallel", "pROC", "data.table", "dbscan", "mclust", "yaml", "geosphere", "lubridate", "zoo", "solitude", "depmixS4")
for (p in needed) {
  status <- if(requireNamespace(p, quietly=TRUE)) " OK" else " MANQUANT"
  cat(sprintf("   %-12s : %s\n", p, status))
}
cat("\n")

# --------------------------------------------------------------------------
# 1. ── SLURM / ENV PARAMETERS --------------------------------------------
# --------------------------------------------------------------------------
split_id    <- split_job_id  # same ID as Step-1

# Use detection logic already defined above
split_dir <- expected_dir

# FIX: Explicit file verification before continuing
clean_files_check <- list.files(split_dir, pattern = "_clean\\.rds$", full.names = TRUE)
if (!length(clean_files_check)) {
  stop(" Aucun fichier *_clean.rds trouvé dans ", split_dir, "\n",
       "   Fichiers présents dans le répertoire:\n",
       paste("   -", list.files(split_dir, pattern = "\\.rds$"), collapse = "\n"),
       "\n   Vérifiez que l'étape 2 s'est bien terminée.")
}

cat(" Fichiers *_clean.rds trouvés:", length(clean_files_check), "\n")
for (f in head(clean_files_check, 3)) cat("   •", basename(f), "\n")
if (length(clean_files_check) > 3) cat("   ... et", length(clean_files_check) - 3, "autres\n")

# Create output directory (output_dir already defined above)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("  Source :", split_dir, "\n")
cat("  Sortie :", output_dir, "\n")
cat("  Checkpoints :", chk_dir, "\n\n")

# --------------------------------------------------------------------------
# 2. ── CHARGEMENT PACKAGES  +  CONFIG CPU ----------------------------------
# --------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(solitude)    # already loaded but required to re-read config
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

cat("  Packages chargés |", cores, "threads data.table\n")

# --------------------------------------------------------------------------
# STRICT FILTER CONTROL FUNCTION - RELAXED IN DRY-RUN
# --------------------------------------------------------------------------
# Harmonised constants to prevent inconsistencies
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
cat("  YAML chargé\n")

# Default values if YAML is incomplete
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

# Lecture du YAML avec gestion des errors
tryCatch({
  cfg <- yaml::read_yaml("~/R_scripts/configuration/outlier_config_V6.yaml")
  
  # Extract parameters from nested sections
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
  
  # Check and fill missing parameters
  for (param in names(default_config)) {
    if (is.null(cfg[[param]])) {
      cfg[[param]] <- default_config[[param]]
      cat("  Paramètre manquant dans YAML:", param, "- Utilisation valeur par défaut:", default_config[[param]], "\n")
    }
  }
}, error = function(e) {
  cat("  Erreur lecture YAML - Utilisation valeurs par défaut\n")
  cfg <<- default_config
})

# --------------------------------------------------------------------------
# 4. ── DATA MERGE  -------------------------------------------------
# --------------------------------------------------------------------------
# CHECKPOINT 1: Merge data
ais <- checkpoint("stage3A_fusion.rds", {
cat("  Fichiers trouvés :", length(clean_files), "\n")
for (f in head(clean_files, 5)) cat("   •", basename(f), "\n")
if (length(clean_files) > 5) cat("   …\n")

t_read <- system.time({
  # parallel read (capped at 4 workers - IO-safe)
  ais_list <- mclapply(clean_files, readRDS, mc.cores = min(cores, 4))
  ais      <- rbindlist(ais_list, fill = TRUE)
})
rm(ais_list); gc()
cat(sprintf("  Fusion : %s lignes | %.1f s\n\n",
            format(nrow(ais), big.mark = " "), t_read[3]))
  
  ais
})

# FIX: Define n_total immediately after merge
n_total <- nrow(ais)

# CRITICAL CHECK: abort if rows without Annee are present after merge
nb_na_year <- ais[is.na(Annee), .N]
if (nb_na_year > 0) {
  stop(nb_na_year, " lignes sans Annee après fusion – checkpoint non sauvegardé.")
}

# --------------------------------------------------------------------------
# CONFIGURABLE DRY-RUN: DRY_RUN enables it, DRYRUN_N sets sample size
# --------------------------------------------------------------------------
DRYRUN_N <- as.integer(Sys.getenv("DRYRUN_N", "0"))
if (is_dry && DRYRUN_N > 0 && nrow(ais) > DRYRUN_N) {
  set.seed(42)  # reproductible
  
  # Stratified sample by vessel to preserve representation
  ais <- ais[, .SD[sample(.N, min(.N, ceiling(DRYRUN_N * .N / n_total)))], by = Navire]
  
  cat(sprintf("🧪 Dry-run : subset de %d lignes (%.1f %% du total initial)\n",
              nrow(ais), 100 * nrow(ais) / n_total))
  
  # Update total count for diagnostics
  n_total <- nrow(ais)
}

# --------------------------------------------------------------------------
# 4b. ── COLUMN TYPE VERIFICATION AND CORRECTION ---------------------------
# --------------------------------------------------------------------------
cat("  Vérification des types de colonnes...\n")

# Critical type verification
cat(" Types des colonnes critiques:\n")
for (col in c("Navire", "ssvid", "Seg_id", "Annee")) {
  if (col %in% names(ais)) {
    cat(sprintf("   %-10s: %s\n", col, class(ais[[col]])[1]))
  }
}

# FIX: Harmonise types to prevent join errors
if ("Navire" %in% names(ais)) {
  # Ensure Vessel is character type
  if (!is.character(ais$Navire)) {
    cat("  Conversion de Navire en caractère\n")
    ais[, Navire := as.character(Navire)]
  }
}

if ("ssvid" %in% names(ais)) {
  # S'assurer que ssvid est de type entier
  if (!is.integer(ais$ssvid) && !is.numeric(ais$ssvid)) {
    cat("  Conversion de ssvid en entier\n")
    ais[, ssvid := as.integer(ssvid)]
  }
}

if ("Seg_id" %in% names(ais)) {
  # Ensure Seg_id is character type
  if (!is.character(ais$Seg_id)) {
    cat("  Conversion de Seg_id en caractère\n")
    ais[, Seg_id := as.character(Seg_id)]
  }
}

if ("Annee" %in% names(ais)) {
  # S'assurer que Annee est de type entier
  if (!is.integer(ais$Annee) && !is.numeric(ais$Annee)) {
    cat("  Conversion de Annee en entier\n")
    ais[, Annee := as.integer(Annee)]
  }
}

# ADDITIONAL CRITICAL CHECKS
cat(" Vérifications supplémentaires critiques...\n")

# 1. Verify is_stop column (required by DBSCAN)
if (!"is_stop" %chin% names(ais)) {
  stop(" Colonne 'is_stop' manquante - Vérifier que la Step-2 s'est bien terminée")
} else {
  cat(" Colonne 'is_stop' présente\n")
}

# 2. Verify geographic columns (required by DBSCAN)
geo_cols <- c("Lon", "Lat", "Course", "Speed")
missing_geo <- geo_cols[!geo_cols %chin% names(ais)]
if (length(missing_geo) > 0) {
  stop(" Colonnes géographiques manquantes: ", paste(missing_geo, collapse = ", "))
} else {
  cat(" Colonnes géographiques présentes\n")
  # Convert to numeric to avoid type errors
  ais[, c("Lon", "Lat", "Course", "Speed") := lapply(.SD, as.numeric), .SDcols = c("Lon", "Lat", "Course", "Speed")]
  cat(" Colonnes géographiques converties en numeric\n")
}

# 3. Check for duplicate (Seg_id, Timestamp)
if (anyDuplicated(ais, by = c("Seg_id", "Timestamp"))) {
  warning("  Doublons détectés dans (Seg_id, Timestamp) - Suppression...")
  ais <- unique(ais, by = c("Seg_id", "Timestamp"))
  cat(" Doublons supprimés\n")
} else {
  cat(" Aucun doublon détecté\n")
}

# 4. Check available memory
mem_usage <- object.size(ais) / 1024^3  # GB
cat(sprintf(" Utilisation mémoire: %.2f GB\n", mem_usage))

if (mem_usage > 50) {
  warning("  Utilisation mémoire élevée: ", round(mem_usage, 1), " GB")
}

cat(" Types de colonnes vérifiés et corrigés\n\n")

# --------------------------------------------------------------------------
# STRICT ROW-COUNT CONTROL - ABORT ON MISMATCH
# --------------------------------------------------------------------------
n_total <- nrow(ais)  # Effectif initial
cat(" === CONTRÔLE STRICT DES EFFECTIFS ===\n")
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
roll_MAD5 <- function(x) {                # rolling median & MAD, window 5
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

# DBSCAN helpers - FIX P0.2: Projection in metres + kNNdist (avoids O(n^2))
to_xy_m <- function(lon, lat) {
  # Simple projection: (lon, lat) -> (x, y) in metres
  lat0 <- mean(lat, na.rm = TRUE) * pi / 180
  x <- lon * 111320 * cos(lat0)
  y <- lat * 110574
  cbind(x, y)
}

auto_eps_m <- function(xy, k = 4) {
  # Compute eps in metres via kNNdist (O(n log n) instead of O(n^2))
  # FIX: k_eff to avoid crash if n <= k
  n <- nrow(xy)
  k_eff <- min(k, max(1, n - 1))
  d <- dbscan::kNNdist(xy, k = k_eff)
  # Minimum threshold 200 m, else 1% of median
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
cat("  Détection pics temporels isolés…\n")
n_before_spike <- nrow(ais)
ais[, outlier_spike := detect_spikes(Speed,
                        spike_factor = cfg$spike_factor,
                        min_iso      = cfg$min_spike_duration),
    by = Seg_id]
ais <- ais[outlier_spike == FALSE | is.na(outlier_spike)]
check_filter("Filtre Spikes", n_before_spike, nrow(ais))
ais[, outlier_spike := NULL]

# --------------------------------------------------------------------------
# 8. ── CONTEXTUAL PERCENTILES - REMOVED ------------------------
# --------------------------------------------------------------------------
# Section removed to simplify the pipeline
# Contextual percentiles are not used in subsequent steps
# (DBSCAN, GMM, Grid-search) and can be removed without impact

# --------------------------------------------------------------------------
# 9. ── SPATIAL STOP DETECTION (DBSCAN) ------------------------------
# --------------------------------------------------------------------------
# CHECKPOINT 2: DBSCAN complete
ais <- checkpoint("stage3B_dbscan.rds", {
cat("  Détection des arrêts spatiaux par DBSCAN...\n")

# OPTIMISATION: Protection contre les petits vessels et approche plus robuste
ais[, stop_cluster := NA_integer_]

# FIX: Count with Lon AND Lat filter (avoids skipping whole vessel for 1 NA)
stop_counts <- ais[is_stop == TRUE & !is.na(Lon) & !is.na(Lat), .N, by = .(Navire, Annee)]
stop_counts <- stop_counts[N >= 4]  # Seulement les navires avec suffisamment de points

if (nrow(stop_counts) > 0) {
  cat(" Traitement DBSCAN pour", nrow(stop_counts), "combinaisons navire/année\n")

  for (i in 1:nrow(stop_counts)) {
    navire <- stop_counts$Navire[i]
    annee <- stop_counts$Annee[i]

    # FIX: Selection via .I for bulletproof assignment (guaranteed alignment)
    idx <- ais[Navire == navire & Annee == annee & is_stop == TRUE &
               !is.na(Lon) & !is.na(Lat), which = TRUE]
    arr <- ais[idx]

    if (length(idx) >= 4) {
      # PROTECTION: Check de la variance des coordata
      if (var(arr$Lon, na.rm = TRUE) < 1e-8 || var(arr$Lat, na.rm = TRUE) < 1e-8) {
        cat("  Variance insuffisante pour", navire, annee, "- Skipping\n")
        next
      }

      tryCatch({
        # FIX P0.2: Projection in metres (metric consistency + stable eps)
        xy <- to_xy_m(arr$Lon, arr$Lat)

        # Protection against large stop clusters (sampling for eps)
        if (nrow(xy) > 5000) {
          cat("  Gros arrêt détecté pour", navire, annee, "(", nrow(xy), "points) - Échantillonnage pour eps\n")
          set.seed(123)
          samp_idx <- sample(nrow(xy), 5000)
          eps <- auto_eps_m(xy[samp_idx, , drop = FALSE])
        } else {
          eps <- auto_eps_m(xy)
        }

        # DBSCAN on metric coordinates (xy in metres)
        cl <- dbscan(xy, eps = eps, minPts = 4)$cluster

        # Protection contre les clusters vides
        if (sum(cl > 0) == 0) {
          cat("  Aucun cluster trouvé pour", navire, annee, "- Élargissement du rayon eps\n")
          eps <- eps * 1.5
          cl <- dbscan(xy, eps = eps, minPts = 4)$cluster
        }

        # FIX: Assignation via idx (bulletproof, arowment garanti)
        ais[idx, stop_cluster := cl]
      }, error = function(e) {
        cat("  Erreur DBSCAN pour", navire, annee, ":", e$message, "\n")
      })
    }
  }
} else {
  cat("  Aucun navire avec suffisamment de points d'arrêt pour DBSCAN\n")
}

ais[, is_stop_spatial := is_stop & !is.na(stop_cluster) & stop_cluster > 0]
  
  cat(" DBSCAN terminé - Checkpoint sauvegardé\n")
  
  # CHECK: Row counts after DBSCAN
  n_stop_spatial <- sum(ais$is_stop_spatial, na.rm = TRUE)
  cat(sprintf("[DIAGNOSTIC] Après DBSCAN (is_stop_spatial TRUE): %d points (%.2f%% du total)\n", 
              n_stop_spatial, 100 * n_stop_spatial / nrow(ais)))
  
  # Check that DBSCAN did not remove too many points
  if (n_stop_spatial < 1000) {
    warning("[ALERTE] Très peu de points d'arrêt spatiaux détectés par DBSCAN (< 1000)")
  }
  
  # CRITICAL CHECK: Verify that is_stop_spatial column was created
  if (!"is_stop_spatial" %in% names(ais)) {
    stop(" ERREUR CRITIQUE: Colonne 'is_stop_spatial' manquante après DBSCAN")
  }
  cat(" Vérification: Colonne 'is_stop_spatial' présente\n")
  
  ais
})

# --------------------------------------------------------------------------
# 10 bis. ── Calcule la cadence AIS & thresholds adaptives  -------------------
# --------------------------------------------------------------------------
#  (to be placed after DBSCAN step and BEFORE section "GMM stop + 4")

# 1) Sort by segment and timestamp to avoid negative dt_sec
setorder(ais, Seg_id, Timestamp)

# 2) Δt inter-messages en secondes
ais[, dt_sec := c(NA_real_, diff(as.numeric(Timestamp))), by = Seg_id]

# FIX 1: Compute Course_change only (Accel will be computed after filtering)
# FIX P0.3: Add by = Seg_id to avoid cross-segment diffs
ais[, Course_change := c(NA, abs(diff(Course))), by = Seg_id]
# Gestion du wrap-around pour Course_change
ais[Course_change > 180, Course_change := 360 - Course_change]
# Save robuste si trop de NA
ais[is.na(Course_change), Course_change := 0]

# 3) Calcul des statistiques de cadence par vessel
cadence <- ais[!is.na(dt_sec), .(
    p50_dt = median(dt_sec, na.rm = TRUE),      # median
    p95_dt = quantile(dt_sec, 0.95, na.rm = TRUE),  # 95e percentile
    n_obs = .N
), by = Navire]

# 4) Truncate median to avoid extreme values
cadence[, p50_dt := pmin(p50_dt, 600)]  # truncate median at 10 min

# 5) Calcul des thresholds adaptives
#    - Threshold de base : 3 × median (captures true stops)
#    - Floor: 3 min for highly active vessels
#    - Plafond : 900 s (15 min) pour les vessels normaux
#    - Special threshold for slow vessels (>50% intervals > 5 min)

cadence[, seuil_adaptatif := pmin(900, pmax(180, 3 * p50_dt))]

# 6) Detect slow vessels (>50% of intervals > 5 min)
intervalles_long <- ais[dt_sec >= 300, .N, by = Navire]
intervalles_tot <- ais[!is.na(dt_sec), .N, by = Navire]
prop_long <- merge(intervalles_long, intervalles_tot, by = "Navire", suffixes = c("_long", "_total"))
prop_long[, prop_long := N_long / N_total]

# 7) Adjust threshold for slow vessels
cadence <- merge(cadence, prop_long[, .(Navire, prop_long)], by = "Navire", all.x = TRUE)
cadence[is.na(prop_long), prop_long := 0]

# For vessels with >50% long intervals, use a higher threshold
cadence[prop_long > 0.5, threshold_adaptive := pmin(1200, 5 * p50_dt)]  # 5 x median, max 20 min

# 8) Calcul du n_min adaptive pour le lissage run-length
#    t_threshold = 30 s ~ max duration of a micro-glitch
t_threshold   <- 30                     # 30 s ~ max duration of a micro-glitch
t_seuil <- t_threshold                  # alias conserve pour compatibilite historique
n_max_cap <- 8                      # plafond pour rester rapide
cadence[, n_min := pmin(n_max_cap, pmax(3, ceiling(t_seuil / p50_dt)))]

# 9) Join avec l'ensemble principal
ais <- merge(ais, cadence[, .(Navire, n_min, seuil_adaptatif, p50_dt, prop_long)], by = "Navire", all.x = TRUE)

# 10) Filter with adaptive threshold (parentheses for clarity)
cat("  Cadence AIS & seuils adaptatifs par navire\n")
print(cadence[order(p50_dt), .(Navire, p50_dt, seuil_adaptatif, n_min, prop_long)])

# Filtrage des intervalles trop longs selon le threshold adaptive de chaque vessel
n_before_cadence <- nrow(ais)
ais <- ais[(dt_sec > 0 & dt_sec < seuil_adaptatif) | is.na(dt_sec)]
check_filter("Filtrage intervalles longs", n_before_cadence, nrow(ais))

# FIX: Recompute dt_sec AFTER filtering to avoid temporal shift
ais[, dt_sec := c(NA_real_, diff(as.numeric(Timestamp))), by = Seg_id]

# FIX: Recompute Course_change AFTER filtering to avoid bias
ais[, Course_change := c(NA, abs(diff(Course))), by = Seg_id]
# Gestion du wrap-around pour Course_change
ais[Course_change > 180, Course_change := 360 - Course_change]
# Save robuste si trop de NA
ais[is.na(Course_change), Course_change := 0]

# FIX: Compute Accel AFTER filtering large temporal gaps
# Conversion Speed en m/s pour calculer Accel en m/s²
# FIX 2: Garde-fou contre les vecteurs vides
ais[, Accel := {
  dt <- dt_sec[-1L]
  if (length(dt) == 0) {
    rep(NA_real_, .N)
  } else {
    c(NA, diff(Speed * 0.514444) / pmax(dt, 1))
  }
}, by = Seg_id]
ais[is.na(Accel), Accel := 0]

# -- Guard n_min against NA values ----------------------------------------
ais[is.na(n_min), n_min := 3]  # fallback plancher

# FINAL CHECK BEFORE GMM
cat(sprintf("[DIAGNOSTIC] Nombre de points conservés avant GMM: %d (%.2f%% du total initial)\n", 
            nrow(ais), 100 * nrow(ais) / n_total))

# Check finale critique - ASSOUPLIE EN DRY-RUN
if (is_dry) {
  # In dry-run mode, a smaller dataset is acceptable
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

  cat("  GMM « stop + K mobiles » – sélection K par BIC (3-5) - ROBUSTE\n")

  ## 0. Preparation ----------------------------------------------------------
  idx_mobile <- which(!ais$is_stop_spatial & ais$Speed >= 0.5 & ais$Speed <= 20)

  # FIX: Recompute quantiles after all filters to avoid bias
  q95_acc  <- quantile(abs(ais$Accel),  .95, na.rm = TRUE);  if (!is.finite(q95_acc)  || q95_acc  == 0) q95_acc  <- 1e-6
  q95_turn <- quantile(ais$Course_change, .95, na.rm = TRUE); if (!is.finite(q95_turn) || q95_turn == 0) q95_turn <- 1e-6
  
  cat("    Quantiles recalculés après filtres - Accel 95%:", round(q95_acc, 4), "| Course 95%:", round(q95_turn, 2), "°\n")

  mobi <- ais[idx_mobile, .(
      Speed,
      norm_acc    = pmax(0, pmin(1, abs(Accel) / q95_acc)),
      norm_course = pmax(0, pmin(1, 1 - Course_change / q95_turn))
  )]

  keep       <- complete.cases(mobi)
  X          <- as.matrix(mobi[keep])
  idx_train  <- idx_mobile[keep]

  # Threshold adaptive selon le mode (dry-run vs production)
  min_mobile <- if (is_dry) 50 else 200
  if (nrow(X) < min_mobile)
    stop("  Pas assez de points mobiles complets pour ajuster le GMM (", nrow(X), " < ", min_mobile, ")")

  ## 1. Recherche du meilleur K (BIC) - ROBUSTE ------------------------------
  # CORRECTION 5: Protection contre l'overflow memory Mclust
  samp <- if (nrow(X) > 1e6) X[sample(nrow(X), 1e6), ] else X
  cat("   Échantillon pour BIC:", nrow(samp), "points (sur", nrow(X), ")\n")
  
  G_choices <- 3:5                                   # 3 to 5 mobile components
  
  # CORRECTION CRITIQUE: Fonction helper pour extraire un scalaire BIC
  get_bic_scalar <- function(x) {
    if (is.null(x) || length(x) == 0) return(-Inf)
    max(as.numeric(x), na.rm = TRUE)
  }
  
  # FIX 1: Use vapply() which enforces numeric scalar return type
  bic_vals <- vapply(G_choices, function(g) {
    res <- tryCatch(
      Mclust(samp, G = g, modelNames = "VVV", verbose = FALSE),
      error = function(e) NULL)
    if (is.null(res)) return(-Inf)
    get_bic_scalar(res$bic)
  }, numeric(1))
  
  # FIX 2: Guard against Mclust failures
  if (all(is.infinite(bic_vals)))
    stop("  Mclust a échoué pour toutes les valeurs de K - X trop grand ou mal conditionné")
  
  K <- G_choices[which.max(bic_vals)]
  
  # FIX 4: Check de la borne basse K >= 3
  if (K < 3) stop(" Le GMM doit avoir au moins 3 composantes mobiles (dredge/transit)")
  
  cat("   ➜  K retenu par BIC :", K, "composantes mobiles\n")

  ## 2. Ajustement definedtif -------------------------------------------------
  # FIX 3: Protection memory pour l'ajustement final
  X_fit <- if (nrow(X) > 2e6) X[sample(nrow(X), 2e6), ] else X
  cat("   Échantillon pour ajustement final:", nrow(X_fit), "points (sur", nrow(X), ")\n")
  
  gmm <- Mclust(X_fit, G = K, modelNames = "VVV", verbose = FALSE)

  ## 3. Posterior probabilities -------------------------------------------
  z <- predict(gmm, X)$z                       # nrow(X) × K
  
  # FIX 3: Safe re-initialisation of p columns
  ais[, paste0("p", 1:(K+1)) := 0]             # initialise p1..p{K+1} to zero
  ais[is_stop_spatial == TRUE, p1 := 1]

  for (j in seq_len(K))
    ais[idx_train, paste0("p", j + 1) := z[, j]]

  ## 4. Sort by speed ------------------------------------------------------
  ord  <- order(gmm$parameters$mean[1, ])      # tri croissant de Speed
  mu   <- gmm$parameters$mean[1, ord]
  cat("   μ mobiles triés :", paste(round(mu, 2), collapse = " / "), "kn\n")

  Zord <- z[, ord, drop = FALSE]

  # FIX 3: Full re-initialisation before re-insertion
  ais[, paste0("p", 1:(K+1)) := 0]             # reset everything to zero
  ais[is_stop_spatial == TRUE, p1 := 1]        # restore stops
  for (j in seq_len(K))
    ais[idx_train, paste0("p", j + 1) := Zord[, j]]

  ## 5. Raw labels - OPTION A: Robust multi-component slow-speed mapping
  # FIX P0: Correct alignment of mobi_keep / Zord for stability score
  # FIX P1: Separate idle (μ<1) / slow (1≤μ<6) / transit (μ≥6)
  # Garantit que AUCUN transit n'a μ < 6 kn

  ## --- FIX P0: Arowr mobi avec Zord (mobi_keep) + max.col() rapide --- ##
  mobi_keep <- mobi[keep]  # aligne exactement les lignes avec X / Zord
  comp_hat  <- max.col(Zord, ties.method = "first")  # 1..K, consistent with mu / ord

  ## --- Robust component mapping (Option A corrected) -------------------- ##
  # General parameters
  dredge_range <- c(1, 3.5)           # speed window (kn) considered as dredging
  slow_ceiling <- 6                    # μ < 6 kn = jamais transit

  # 1) Identifier les composantes par plage de speed (FIX P1)
  idle_candidates   <- which(mu < 1)                                    # μ < 1 kn → other

  slow_candidates   <- which(mu >= 1 & mu < slow_ceiling)               # μ ∈ [1, 6) kn
  dredge_candidates <- which(mu >= dredge_range[1] & mu <= dredge_range[2])  # μ ∈ [1, 3.5] kn

  cat("    Composantes idle (μ < 1 kn):", paste(idle_candidates, collapse=", "), "\n")
  cat("    Composantes lentes (1 ≤ μ < 6 kn):", paste(slow_candidates, collapse=", "), "\n")
  cat("    Candidats dragage [1-3.5 kn]:", paste(dredge_candidates, collapse=", "), "\n")

  # 2) Robust dredging component selection (FIX P0: mobi_keep + comp_hat)
  if (length(dredge_candidates) > 0) {
    if (length(dredge_candidates) == 1) {
      dredge_comp <- dredge_candidates
    } else {
      # Multiple candidates: stability score = mean(norm_course) - mean(norm_acc)
      # Dredging has a stable course (high norm_course) and low acceleration
      stability_scores <- vapply(dredge_candidates, function(j) {
        m <- (comp_hat == j)
        if (sum(m) < 10) return(-Inf)
        mean(mobi_keep$norm_course[m], na.rm = TRUE) -
          mean(mobi_keep$norm_acc[m], na.rm = TRUE)
      }, numeric(1))

      # Selection by stability score, tie-breaker = closest to 2 kn
      best_score <- max(stability_scores, na.rm = TRUE)
      top_candidates <- dredge_candidates[stability_scores >= best_score - 0.05]
      dredge_comp <- top_candidates[which.min(abs(mu[top_candidates] - 2))]

      cat("    Scores stabilité:", paste(round(stability_scores, 3), collapse=", "), "\n")
    }
  } else {
    # Fallback: plus proche de 2 kn parmi toutes les composantes
    dredge_comp <- which.min(abs(mu - 2))
    cat("     Aucun candidat dans [1-3.5 kn], fallback vers μ =", round(mu[dredge_comp], 2), "kn\n")
  }

  # 3) Les autres composantes lentes (hors dredge) → slow_maneuvers (FIX P1)
  other_slow_idx <- setdiff(slow_candidates, dredge_comp)

  # 4) Composantes transit: UNIQUEMENT μ >= 6 kn
  transit_pool <- which(mu >= slow_ceiling)

  cat("    Pool transit (μ >= 6 kn):", paste(transit_pool, collapse=", "), "\n")

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
    # Intermediate speeds = other
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
  # ASSERTION 0 (BONUS): dredge_comp must be unique and defined
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

  # ASSERTION 2: Systematic diagnostic dump
  cat("\n   === MAPPING DIAGNOSTIC ===\n")
  mapping_dt <- data.table(comp = 1:K, mu_kn = round(mu, 2), label = mobile_labels)
  print(mapping_dt)
  cat("   ===========================\n\n")

  map <- c("stops", mobile_labels)             # longueur = K+1 (p1…p{K+1})

  cat("   🏷  Labels attribués:", paste(mobile_labels, collapse=" → "), "\n")
  cat("    Vitesses correspondantes:", paste(round(mu, 2), "kn", collapse=" → "), "\n")
  cat("    Composante dragage: μ =", round(mu[dredge_comp], 2), "kn (index", dredge_comp, ")\n")

  ais[, comp     := apply(.SD, 1, which.max), .SDcols = paste0("p", 1:(K + 1))]
  ais[, behavior := map[comp]]

  ## 6. Lissage run-length - ROBUSTE -----------------------------------------
  # FIX: Cost matrix adapted to dynamic mapping
  # Dynamic construction based on available labels
  all_labels <- c("stops", mobile_labels)
  n_labels <- length(all_labels)
  
  # Base cost matrix (high cost for improbable transitions)
  cost_matrix <- matrix(5, n_labels, n_labels, 
                       dimnames = list(all_labels, all_labels))
  
  # Specific costs
  diag(cost_matrix) <- 0  # same state = cost 0

  # Costs between mobile states (natural transitions)
  # FIX P1: Use dredge_state to avoid shadowing dredge_comp
  if ("dredging" %in% all_labels) {
    dredge_state <- which(all_labels == "dredging")  # index dans all_labels (1..n_labels)
    # Dredging ↔ transit = moderate cost
    transit_labels_cost <- setdiff(all_labels, c("stops", "dredging"))
    for (tl in transit_labels_cost) {
      tl_idx <- which(all_labels == tl)
      cost_matrix[dredge_state, tl_idx] <- 3
      cost_matrix[tl_idx, dredge_state] <- 3
    }
  }

  # Costs to/from stops (rare transitions)
  stops_state <- which(all_labels == "stops")
  cost_matrix[stops_state, ] <- 4
  cost_matrix[, stops_state] <- 4
  cost_matrix[stops_state, stops_state] <- 0

  # FIX: Reduced cost for dredging ↔ stops (more natural)
  if ("dredging" %in% all_labels) {
    dredge_state <- which(all_labels == "dredging")
    cost_matrix[dredge_state, stops_state] <- 3
    cost_matrix[stops_state, dredge_state] <- 3
  }

  # FIX 4: Safe cost function for missing labels
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

  # FIX: Threshold plus stable pour le lissage (75e percentile au lieu de median)
  lissage_threshold <- quantile(ais$n_min, 0.75, na.rm = TRUE)
  cat("    Seuil de lissage (75e percentile n_min):", round(lissage_threshold, 1), "\n")
  
  ais[, behavior_smooth :=
        smooth_transition_robust(behavior, Speed,
                                thr = lissage_threshold,
                                dredge_min = 1, dredge_max = 3.5),
      by = Seg_id]

  ais[, dredge_lisse := as.integer(behavior_smooth == "dredging")]

  ## 7. Normalised for dredging score ----------------------------------------
  ais[, norm_course := pmax(0, pmin(1, 1 - Course_change / q95_turn))]
  ais[, norm_acc    := pmax(0, pmin(1, abs(Accel) / q95_acc))]

  cat("  GMM ROBUSTE terminé –", table(ais$behavior_smooth), "états après lissage\n")
  
  # CLASS VERIFICATION AFTER GMM (for dry-run)
  if (is_dry) {
    n_classes <- length(unique(ais$behavior_smooth))
    if (n_classes < 2) {
      stop(sprintf("ERREUR FATALE : Échantillon DRY-RUN mono-classe après GMM (%d classe) – reprenez un autre sous-ensemble", n_classes))
    }
    cat("    Dry-run: ", n_classes, "classes détectées après GMM\n")
  }
  
  # FIX: Save mapping info for downstream steps (optimised)
  # Using attributes to avoid RAM duplication
  # BONUS: Uses dredge_comp (already validated unique) instead of recomputing
  attr(ais, "gmm_info") <- list(
    K = K,
    dredge_idx = dredge_comp,          # 1..K (index dans mobile_labels)
    dredge_speed = mu[dredge_comp],
    mobile_labels = mobile_labels,
    mu = mu
  )
  
  ## ═══════════════════════════════════════════════════════════════════════
  ## QA REFACTORED: QA1 (pre-smooth, hard) + QA2 (post-smooth, soft)
  ## FIX P1: Uses dredge_comp (already validated) instead of recomputing
  ## ═══════════════════════════════════════════════════════════════════════

  dredge_col <- paste0("p", dredge_comp + 1)  # +1 car p1 = stops
  ais[, p_dredge_qa := get(dredge_col)]

  ## ─────────────────  SANITY-CHECK  ─────────────────
  # 1) Replace any NA with 'unknown'
  ais[is.na(behavior_smooth), behavior_smooth := "unknown"]
  ## ───────────────────────────────────────────────────

  ## --- QA1: PRE-SMOOTH (hard check on argmax) ---
  # On behavior (pre-smoothing), 'dredging' points MUST have p_dredge as argmax
  raw_dredge_mask <- ais$behavior == "dredging"
  n_raw_dredge <- sum(raw_dredge_mask, na.rm = TRUE)

  if (n_raw_dredge > 0) {
    proba_cols <- paste0("p", 1:(K+1))
    max_proba_col <- apply(ais[raw_dredge_mask, proba_cols, with=FALSE], 1, which.max)
    expected_col <- dredge_comp + 1  # +1 car p1 = stops

    n_correct <- sum(max_proba_col == expected_col, na.rm = TRUE)
    qa1_rate <- n_correct / n_raw_dredge

    if (qa1_rate >= 0.99) {
      cat(sprintf("    QA1 (pre-smooth): %.1f%% des points dredging ont p_dredge=argmax\n", 100*qa1_rate))
    } else if (qa1_rate >= 0.90) {
      cat(sprintf("     QA1 (pre-smooth): %.1f%% seulement (attendu ≥99%%) - vérifier le mapping\n", 100*qa1_rate))
    } else {
      cat(sprintf("    QA1 (pre-smooth): ÉCHEC - seulement %.1f%% (attendu ≥90%%)\n", 100*qa1_rate))
      cat("      Diagnostic: argmax distribution =", paste(names(table(max_proba_col)), table(max_proba_col), sep=":", collapse=", "), "\n")
    }
  } else {
    cat("     QA1: Aucun point 'dredging' pré-lissage\n")
  }

  ## --- QA2: POST-SMOOTH (soft check on p_dredge distribution) ---
  # On behavior_smooth, 'dredging' points should have high p_dredge (median >= 0.5)
  # But smoothing may re-label segments, so this is only a warning
  smooth_dredge_mask <- ais$behavior_smooth == "dredging"
  n_smooth_dredge <- sum(smooth_dredge_mask, na.rm = TRUE)

  if (n_smooth_dredge > 0) {
    p_dredge_smooth <- ais[smooth_dredge_mask, p_dredge_qa]
    q <- quantile(p_dredge_smooth, probs = c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE)

    if (q["50%"] >= 0.5) {
      cat(sprintf("    QA2 (post-smooth): médiane p_dredge = %.3f (≥0.5)\n", q["50%"]))
    } else if (q["50%"] >= 0.3) {
      cat(sprintf("     QA2 (post-smooth): médiane p_dredge = %.3f (faible, attendu ≥0.5)\n", q["50%"]))
      cat(sprintf("      Quantiles: 10%%=%.3f, 25%%=%.3f, 50%%=%.3f, 75%%=%.3f, 90%%=%.3f\n",
                  q["10%"], q["25%"], q["50%"], q["75%"], q["90%"]))
    } else {
      cat(sprintf("    QA2 (post-smooth): médiane p_dredge = %.3f (très faible!)\n", q["50%"]))
      cat(sprintf("      Quantiles: 10%%=%.3f, 25%%=%.3f, 50%%=%.3f, 75%%=%.3f, 90%%=%.3f\n",
                  q["10%"], q["25%"], q["50%"], q["75%"], q["90%"]))
      cat("        Le lissage a peut-être trop étendu les segments dredging\n")
    }
  } else {
    cat("     QA2: Aucun point 'dredging' post-lissage\n")
  }
  
  ais
})

# --------------------------------------------------------------------------
# 13. ── GRID-SEARCH (dredging score weights) - FIXED TO PREVENT DATA LEAKAGE
# --------------------------------------------------------------------------
# CHECK-POINT 4: Grid-search complete
resGS <- checkpoint(
  "stage3D_gridsearch.rds",
  {
    cat("  Grid-search (poids score dragage) - CORRIGÉ POUR ÉVITER DATA LEAKAGE\n")
    
    # MAJOR FIX: Prevent data leakage
    # 1) Define CV blocks (leave-one-year-out) - STRICT LOYO GUARANTEE
    # === LOYO: 1 year = 1 fold (compliant with section 2.6) ===
    cv_folds <- length(unique(ais$Annee))  # Enforce exactly 1 year = 1 fold
    ais[, fold := frank(Annee, ties.method="dense")]
    
    cat("   Validation croisée LOYO stricte:", cv_folds, "folds (1 année = 1 fold)\n")
    
    # 2) Remove derived label from predictors (PREVENTS DATA LEAKAGE)
    # Instead of dredge_lisse, use p_dredge (GMM probability) + kinematic signals
    # === COMPOSITE DREDGING SCORE: 5 signaux → cv.glmnet (ridge) → LOYO → Youden J ===
    ais[, speed_bin := as.integer(Speed >= 1 & Speed <= 3.5)]
    ais[, speed_norm := exp(-(Speed - 2.25)^2 / (2 * 1^2))]
    
    # FIX: Replace remaining NAs in speed_bin and speed_norm
    ais[is.na(speed_bin),  speed_bin  := 0L]
    ais[is.na(speed_norm), speed_norm := 0]

    # FIX: Guard speed_norm against division by zero
    ais[!is.finite(speed_norm), speed_norm := 0]
    
    # CRITICAL FIX: Build dynamic dredging probability
    # Retrieve mapping info from GMM attributes
    gmm_info <- attr(ais, "gmm_info")
    if (is.null(gmm_info)) {
      stop(" ERREUR: Informations de mapping GMM manquantes (attribut gmm_info)")
    }
    
    dredge_idx <- gmm_info$dredge_idx
    dredge_speed <- gmm_info$dredge_speed
    gmm_k <- gmm_info$K
    
    # Create p_dredge column with the correct probability
    dredge_col <- paste0("p", dredge_idx + 1)  # +1 because p1 = stops
    if (!dredge_col %in% names(ais)) {
      stop(sprintf(" ERREUR: Colonne %s manquante (dredge_idx=%d)", dredge_col, dredge_idx))
    }
    
    ais[, p_dredge := get(dredge_col)]
    cat(sprintf("    Probabilité dragage: %s (composante %d, vitesse %.2f kn, K=%d)\n", 
                dredge_col, dredge_idx, dredge_speed, gmm_k))
    
    # Predictors independent of the final label
    predictors <- ais[, .(p_dredge, norm_course, norm_acc, speed_bin, speed_norm)]
    target <- ais$behavior_smooth == "dredging"
    
    # === SAFETY: Verify exactly 5 signals (compliant with section 2.6) ===
    stopifnot(identical(colnames(predictors), 
                        c("p_dredge", "norm_course", "norm_acc", "speed_bin", "speed_norm")))
    cat("    Vérification: Exactement 5 signaux requis pour le composite score\n")
    
    # FIX: Replace remaining NAs in speed_bin and speed_norm before conversion
    ais[is.na(speed_bin),  speed_bin  := 0L]
    ais[is.na(speed_norm), speed_norm := 0]

    # FIX: Verify all predictors are numeric
    stopifnot(all(sapply(predictors, is.numeric)))
    
    # DIAGNOSTIC: Check for non-finite values in predictors
    msg <- colSums(!is.finite(as.matrix(predictors)))
    cat("⛔ Non-finis par colonne :", paste(names(msg), msg, sep=":", collapse=", "), "\n")
    
    # FIX: Replace non-finite values with 0
    predictors <- predictors[, lapply(.SD, function(v) replace(v, !is.finite(v), 0))]
    cat(" Valeurs non-finies remplacées par 0\n")
    
    # CRITICAL FIX: Remove NAs from target (DATA PRESERVATION)
    cat("    Nettoyage des NA dans la variable cible...\n")
    keep_lbl <- !is.na(target)
    n_before <- nrow(ais)
    n_filtered <- sum(!keep_lbl)
    
    cat(sprintf("    Points avec NA dans target: %d (%.2f%%)\n", 
                n_filtered, 100 * n_filtered / n_before))
    
    # STRICT CHECK: Verify no NAs remain
    if (any(is.na(target[keep_lbl]))) {
      stop("ERREUR FATALE : NA détectés dans target après filtrage !")
    }
    
    # Convert to 0/1 integer (glmnet prefers numeric) - for training only
    target_train <- as.integer(target[keep_lbl])  # 1 = dredging, 0 = non-dredging
    
    # PRESERVATION: Keep indices to re-insert predictions
    train_indices <- which(keep_lbl)
    # FIX P2.3: cat() does not interpret %d → use sprintf()
    cat(sprintf("    Données préservées: %d points pour entraînement, %d points pour prédiction complète\n",
                length(train_indices), n_before))
    
    # FIX: Handle NA values in predictors
    # glmnet does not accept NA values
    cat("   Vérification des valeurs manquantes dans les prédicteurs...\n")
    na_counts <- colSums(is.na(predictors))
    cat("   Valeurs NA par prédicteur:", paste(names(na_counts), na_counts, sep=":", collapse=", "), "\n")
    
    # DIAGNOSTIC: Verify p_dredge mapping
    cat("   Vérification du mapping p_dredge:\n")
    cat("   Colonnes p disponibles:", paste(intersect(paste0("p",1:5), names(ais)), collapse=", "), "\n")
    cat("   Colonne p_dredge créée:", if("p_dredge" %in% names(ais)) "OUI" else "NON", "\n")
    if ("p_dredge" %in% names(ais)) {
      cat("   Valeurs p_dredge:", paste(head(ais$p_dredge, 5), collapse=", "), "\n")
    }
    
    # Option 1: Replace NAs with 0 (more conservative)
    predictors[is.na(predictors)] <- 0
    cat("   Valeurs NA remplacées par 0\n")
    
    # Option 2: Filter rows with missing values (stricter)
    # complete_cases <- complete.cases(predictors, target)
    # predictors <- predictors[complete_cases]
    # target <- target[complete_cases]
    # cat("   Rows with missing values filtered:", sum(!complete_cases), "\n")
    
    cat("   Prédicteurs utilisés:", paste(names(predictors), collapse = ", "), "\n")
    cat("   Classes cibles:", table(target), "\n")
    
    # STRICT CHECK: Class distribution
    cat("\n[DIAGNOSTIC] Effectifs par behavior_smooth :\n")
    print(table(ais$behavior_smooth, useNA = "ifany"))
    cat("Effectifs par année :\n")
    print(table(ais$Annee))
    
    # Critical check of class distribution (on training data)
    dredging_count <- sum(target_train)
    non_dredging_count <- sum(!target_train)
    
    # Adaptive thresholds based on mode (dry-run vs production)
    if (is_dry) {
      # In dry-run, accept less data but require at least 2 classes
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
    
    # FIX P2.1: Long-format summary instead of 3D table (avoids memory explosion)
    cat("    Distribution des classes par année/navire (top 20):\n")
    ais_train <- ais[keep_lbl]
    ais_train[, target_tmp := target_train]
    class_summary <- ais_train[, .N, by = .(Annee, Navire, target_tmp)][order(Annee, -N)]
    print(head(class_summary, 20))
    ais_train[, target_tmp := NULL]  # cleanup
    
    # Critical class check before CV (on training data)
    if (length(unique(target_train)) < 2) {
      stop(sprintf("ERREUR FATALE : Dataset mono-classe ! Seulement %d classe(s) détectée(s), impossible de faire une CV valide.\n    Distribution: %s", 
                   length(unique(target_train)), paste(table(target_train), collapse=", ")))
    } else {
      # FIX 1: Check des packages offline before CV
      cat("   Vérification des packages requis...\n")
      if (!requireNamespace("glmnet", quietly = TRUE)) {
        stop(" Package 'glmnet' absent - charge-le via module ou $R_LIBS_USER")
      }
      if (!requireNamespace("doParallel", quietly = TRUE)) {
        stop(" Package 'doParallel' absent - charge-le via module ou $R_LIBS_USER")
      }
        library(glmnet)
      library(doParallel)
      
      # FIX 6: glmnet parallelism without data.table conflict
      cat("   Configuration du parallélisme glmnet...\n")
      setDTthreads(1)  # Disable data.table parallelism
      Sys.setenv(OMP_NUM_THREADS = 1)  # Disable OpenMP
      registerDoParallel(cores = min(12, parallel::detectCores() - 2))
      cat("   Parallélisme configuré pour glmnet (", min(12, parallel::detectCores() - 2), " cœurs)\n")
      
      # FIX 10: on.exit() moved outside CV loop
on.exit({
  stopImplicitCluster()
  setDTthreads(0)  # Restore data.table auto-threading
  Sys.unsetenv("OMP_NUM_THREADS")
}, add = TRUE)

# TRAINING DATA PREPARATION
predictors_train <- predictors[keep_lbl, ]
ais_train <- ais[keep_lbl]

# FIX 8: Create missing columns BEFORE CV
# Reliable option: matrix computation with exact name matching
missing <- setdiff(c("p_dredge", "norm_course", "norm_acc", "speed_bin", "speed_norm"), names(predictors_train))
if (length(missing) > 0) {
  cat("   Ajout des colonnes manquantes:", paste(missing, collapse=", "), "\n")
  predictors_train[, (missing) := 0]
}

# FIX 9: Convert to sparse matrix to save memory
cat("   Conversion en matrice creuse pour économiser la mémoire...\n")
if (!requireNamespace("Matrix", quietly = TRUE)) {
  stop(" Package 'Matrix' absent - charge-le via module ou $R_LIBS_USER")
}
library(Matrix)

# FIX: Sparse matrix for all rows (not just keep_lbl)
predictors_all <- Matrix::Matrix(as.matrix(predictors), sparse = TRUE)
predictors_all <- Matrix::drop0(predictors_all)   # remove explicit zeros
cat(sprintf("   Matrice creuse globale créée: %.1f MB\n", 
            object.size(predictors_all)/1024^2))

# Sparse matrix for training data only
predictors_matrix <- predictors_all[keep_lbl, ]
predictors_matrix <- Matrix::drop0(predictors_matrix)   # remove explicit zeros
cat(sprintf("   Matrice creuse d'entraînement: %.1f MB (vs %.1f MB dense)\n", 
            object.size(predictors_matrix)/1024^2, 
            object.size(as.matrix(predictors_train))/1024^2))

auc_fold <- numeric(max(ais_train$fold))
      best_models <- list()
      
      # DIAGNOSTIC: Class distribution per fold (training data)
      cat("    Distribution des classes par fold (données d'entraînement):\n")
      fold_table <- table(target_train, ais_train$fold)
      print(fold_table)
      
      for (k in unique(ais_train$fold)) {
        cat(sprintf("     Fold %d/%d (année %d)...\n", k, max(ais_train$fold), unique(ais_train$Annee[ais_train$fold == k])))
        
        train <- ais_train$fold != k
        test <- ais_train$fold == k
        
        # FULL TRAIN/TEST FILTER - PROTECTION AGAINST NAs AND NON-FINITE VALUES
        Xtrain <- predictors_matrix[train, ]
        Ytrain <- target_train[train]
        Xtest <- predictors_matrix[test, ]
        Ytest <- target_train[test]
        
        # FIX: Local computation, no borrowing from previous iteration
        complete_train <- !is.na(Ytrain)
        complete_test <- !is.na(Ytest)
        
        # STRICT CHECK: Size after NA filtering - RELAXED IN DRY-RUN
        min_train <- if (is_dry) 20 else 100
        min_test <- if (is_dry) 5 else 10
        if (sum(complete_train, na.rm = TRUE) < min_train || sum(complete_test, na.rm = TRUE) < min_test) {
          stop(sprintf("ERREUR FATALE : Fold %d trop petit après filtrage NA (train: %d < %d, test: %d < %d)", 
                       k, sum(complete_train, na.rm = TRUE), min_train, sum(complete_test, na.rm = TRUE), min_test))
        }
        
        # FIX P0.4: LOYO mono-class check
        # Train MUST have 2 classes (otherwise fitting is impossible)
        # Test may be single-class → AUC = NA (no stop)
        train_has_2 <- length(unique(Ytrain[complete_train])) >= 2
        test_has_2 <- length(unique(Ytest[complete_test])) >= 2

        if (!train_has_2) {
          stop(sprintf("ERREUR FATALE : Fold LOYO %d - train mono-classe (impossible de fitter)", k))
        }

        # DIAGNOSTIC: Class counts per fold
        cat(sprintf("       Dredging (train/test): %d/%d, Non-dredging (train/test): %d/%d\n",
          sum(Ytrain[complete_train], na.rm = TRUE), sum(Ytest[complete_test], na.rm = TRUE),
          sum(!Ytrain[complete_train], na.rm = TRUE), sum(!Ytest[complete_test], na.rm = TRUE)))

        if (!test_has_2) {
          cat("         Test mono-classe → AUC = NA pour ce fold\n")
        }

        # Penalised logistic regression (Ridge) - fit without NAs, stratified folds
        tryCatch({
          # FIX: Create stratified folds to avoid single-class internal folds
          set.seed(1)

          # FIX P2.4: Fonction de stratification qui stratifie vraiment
          make_stratified_foldid <- function(y, k = 5, seed = 1) {
            set.seed(seed)
            y <- as.integer(y)
            n1 <- sum(y == 1); n0 <- sum(y == 0)
            k_eff <- min(k, n1, n0)  # avoid empty folds
            if (k_eff < 2) k_eff <- 2  # minimum 2 folds
            foldid <- integer(length(y))
            foldid[y == 1] <- sample(rep(1:k_eff, length.out = n1))
            foldid[y == 0] <- sample(rep(1:k_eff, length.out = n0))
            foldid
          }
          
          # FIX P2.4: Use true stratification
          foldid <- make_stratified_foldid(Ytrain[complete_train], k = 5, seed = k)

          # FIX: Guard - if some internal folds are single-class, fall back to deviance
          folds_ok <- all(tapply(Ytrain[complete_train], foldid,
                                 function(z) length(unique(z)) >= 2))
          measure_type <- if (folds_ok) "auc" else "deviance"
          if (!folds_ok) cat("         Folds internes déséquilibrés → fallback deviance\n")

          # FIX: foldid already has the correct length since it was created on Ytrain[complete_train]
          fit <- cv.glmnet(Xtrain[complete_train, ], Ytrain[complete_train],
                          family = "binomial", alpha = 0,  # Ridge
                          foldid = foldid, type.measure = measure_type,
                          parallel = FALSE)  # Avoid nested parallelism

          # Prediction on test fold WITHOUT NAs
          prob <- predict(fit, Xtest[complete_test, ], s = "lambda.min", type = "response")

          # FIX P0.4: Compute AUC - use test_has_2 already computed
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
      
      # Cross-validation results - PROTECTION AGAINST EMPTY FOLDS
      valid_auc <- auc_fold[!is.na(auc_fold)]
      
      # FIX: Guard against all folds failing
      if (all(is.na(auc_fold))) {
        stop("Tous les folds ont échoué : vérifiez la présence de valeurs non finies dans les prédicteurs.")
      }
      
      if (length(valid_auc) > 0 && length(best_models) > 0) {
        mean_auc <- mean(valid_auc)
        sd_auc <- sd(valid_auc)
        cat(sprintf("   AUC moyen CV: %.4f ± %.4f (n=%d folds)\n", mean_auc, sd_auc, length(valid_auc)))
        
        # FIX: Safe best-fold selection
        best_fold <- which.min(abs(replace(auc_fold, is.na(auc_fold), Inf) - mean_auc))
        best_model <- best_models[[as.character(best_fold)]]
        
        # Extract coefficients for the final score
        coefs <- coef(best_model, s = "lambda.min")
        coefs_named <- as.numeric(coefs)
        names(coefs_named) <- rownames(coefs)
        
        # Normalise coefficients to obtain weights
        feature_coefs <- coefs_named[-1]  # Exclude intercept
        total_weight <- sum(abs(feature_coefs))
        
        # FIX 8: More robust check for non-zero coefficients
        if (total_weight == 0 || length(feature_coefs) == 0) {
          stop("ERREUR FATALE : Régression sans poids non nuls - Vérifiez les prédicteurs")
        }
        
        weights <- abs(feature_coefs) / total_weight
        
        # === WEIGHT EXPORT: Save normalised coefficients ===
        fwrite(data.table(feature = names(weights), weight = weights),
               file.path(output_dir, "drag_score_weights.csv"))
        cat("    Poids du composite score sauvegardés dans drag_score_weights.csv\n")
        
        # Build the final score
        # FIX 8: Missing columns already added before CV
        # Prediction on **all** rows (including unlabelled ones)
        full_prob <- as.vector(predict(best_model, predictors_all, s = "lambda.min", type = "response"))
        ais[, drag_score := full_prob]
        
        # FIX: Guard for NA values in drag_score
        ais[is.na(drag_score), drag_score := 0]
        
        # Compute optimal threshold from CV (on labelled data)
        cat("   Calcul du seuil optimal...\n")
        # FIX: Probabilities restricted to calibrate threshold (labelled only)
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
        
        # Application du threshold optimal sur toutes les rows
        ais[, Dragage_flag := as.integer(drag_score >= optimal_threshold)]
        
        # Clean memory after CV
        rm(best_models, predictors_train, auc_fold, valid_auc, prob_cv, roc_full)
        gc()
        cat("   Mémoire nettoyée après CV\n")
      } else {
        stop(sprintf("ERREUR FATALE : Aucun fold valide pour la CV !\n    Diagnostic: Aucun fold valide trouvé\n    Résumé des AUC par fold: %s\n    Nombre de modèles stockés: %d\n    Vérifiez la distribution des classes par année.", 
                     paste(sprintf("%.3f", auc_fold), collapse=", "), length(best_models)))
      }
    }
    
    cat(" Grid-search terminé - AUC honnête calculé\n")
    list(ais = ais, best = best, auc = if(exists("valid_auc")) valid_auc else NA_real_)
  },
  force_recompute = TRUE
)

# Extract checkpoint results
ais <- resGS$ais
best <- resGS$best
auc <- resGS$auc

# FIX: Save GMM probabilities for QA before cleanup
cat(" Sauvegarde des probabilités GMM pour vérification qualité...\n")

# FIX: Gestion de la column ssvid vs MMSI
if ("ssvid" %in% names(ais)) {
  id_col <- "ssvid"
} else if ("MMSI" %in% names(ais)) {
  id_col <- "MMSI"
} else if ("Navire" %in% names(ais)) {
  id_col <- "Navire"
} else {
  warning("  Aucune colonne d'identifiant trouvée (ssvid/MMSI/Navire) - utilisation de la première colonne")
  id_col <- names(ais)[1]
}

# FIX 2: QA robuste - ne garder que les p* existantes (dynamique selon K)
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

  # FIX 1: Safe purge of temporary columns - DYNAMIC BASED ON GMM MAPPING
# PATCH: Keep dredge_lisse, norm_course, norm_acc, Course_change and Accel for QC
  # FIX: Remove p_dredge from tmp_cols to retain it in the final dataset

  # Retrieve GMM mapping info to identify which column to keep
  gmm_info <- attr(ais, "gmm_info")
  if (!is.null(gmm_info)) {
    dredge_idx <- gmm_info$dredge_idx
    dredge_col <- paste0("p", dredge_idx + 1)  # +1 because p1 = stops
    cat("    Conservation de la colonne dragage:", dredge_col, "\n")

    # Remove all p* columns EXCEPT p_dredge and p1 (stops)
    all_p_cols <- paste0("p", 1:(gmm_info$K + 1))
    tmp_cols <- setdiff(all_p_cols, c("p1", dredge_col))
  } else {
    # Fallback if no GMM info
    tmp_cols <- c("p2","p4","p5")
  }
  
  # Add other temporary columns (cleaned of ghost columns)
  tmp_cols <- c(tmp_cols, "speed_norm","speed_bin","comp","behavior","p_dredge_qa")

# FIX 1: Safe purge - only remove columns that actually exist
keep <- intersect(tmp_cols, names(ais))
if (length(keep)) {
  ais[, (keep) := NULL]
  cat("   Colonnes temporaires supprimées:", paste(keep, collapse=", "), "\n")
} else {
  cat("   Aucune colonne temporaire à supprimer\n")
}

# -- Remove superfluous stats columns -------------------------------------
# FIX: Safe column removal
todrop <- intersect(c("dt_sec", "p50_dt", "prop_long"), names(ais))
if (length(todrop)) {
  ais[, (todrop) := NULL]
  cat("   Colonnes de stats supprimées:", paste(todrop, collapse=", "), "\n")
} else {
  cat("   Aucune colonne de stats à supprimer\n")
}

# --------------------------------------------------------------------------
# 14. ── SAVE  --------------------------------------------------------------
# --------------------------------------------------------------------------

## ─────────────────  VERROU GLOBAL FINAL  ─────────────────
# Guarantee no NAs remain in behavior_smooth before export
stopifnot(!anyNA(ais$behavior_smooth))
cat(" Verrou global: Aucun NA dans behavior_smooth - Pipeline hermétique\n")
## ─────────────────────────────────────────────────────────

# FIX: Save AFTER grid-search to include Dragage_flag
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
saveRDS(ais, file.path(output_dir,
         paste0("AIS_data_core_preprocessed_V6_", timestamp, ".rds")),
       compress = "xz")

# Save results with the new structure
saveRDS(list(best_weights = best,
             best_auc     = if(!is.null(best$mean_auc)) best$mean_auc else NA_real_,
             auc_sd       = if(!is.null(best$sd_auc)) best$sd_auc else NA_real_,
             auc_folds    = if(!is.null(best$auc_folds)) best$auc_folds else numeric(0),  # Full AUC per fold
             n_folds      = if(!is.null(best$n_folds)) best$n_folds else 0,
             method       = if(!is.null(best$method)) best$method else "unknown",
             timestamp    = timestamp),
        file.path(output_dir,
         paste0("dragage_gridsearch_results_V6_", timestamp, ".rds")),
        compress = "xz")

cat("\n  Fichiers sauvegardés dans", output_dir, "\n")

# QA CLEANUP: Remove QA test column p_dredge_qa
if ("p_dredge_qa" %in% names(ais)) {
  ais[, p_dredge_qa := NULL]
  cat("✓ Colonne QA p_dredge_qa supprimée\n")
}

# EARLY EXIT IN DRY-RUN MODE
if (is_dry) {
  cat("\n === DRY-RUN TERMINÉ AVEC SUCCÈS ===\n")
  cat(" Test complet jusqu'au grid-search - Aucun fichier lourd sauvegardé\n")
  cat(" Pipeline prêt pour le lancement complet\n")
  cat("  Fin dry-run :", format(Sys.time()), "\n")
  quit(save = "no")
}

cat("  Fin :", format(Sys.time()), "\n")
