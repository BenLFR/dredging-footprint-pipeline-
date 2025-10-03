# ==============================================================================
# 1. Chargement des bibliothèques nécessaires
# ==============================================================================
library(data.table)    # Manipulation efficace des données
library(lubridate)     # Gestion des dates
library(mclust)        # Modèle de mélange pour la vitesse
library(ranger)        # Modèle Random Forest
library(caret)         # Partitionnement et évaluation
library(pROC)          # AUC & courbes ROC
library(ggplot2)       # Visualisations
library(marmap)        # (optionnel) bathymétrie
library(raster)        # (optionnel) raster
library(sf)            # Données spatiales
library(dbscan)        # HDBSCAN
library(dplyr)         # Pipes
library(zoo)           # Moyenne glissante
if (!require(depmixS4)) install.packages("depmixS4")
library(depmixS4)      # HMM
if (!require(pbapply)) install.packages("pbapply")
library(pbapply)       # barre de progression (pour d'autres usages)

#  Packages additionnels éventuellement utiles
if (!require(matrixStats)) { install.packages("matrixStats"); library(matrixStats) }
if (!require(geosphere))   { install.packages("geosphere");   library(geosphere)   }

# ==============================================================================
# 1.a Fonctions de débogage
# ==============================================================================
dbg_head <- function(msg) {
  cat(sprintf("[%s] %s\n", Sys.time(), msg))
  flush.console()
}

dbg_mem_mb <- function() {
  round(sum(gc()[,2]) * 8 / 1024, 1)  # Approximation en Mo
}

dbg_time <- function() {
  format(Sys.time(), "%H:%M:%S")
}

# ======================================================================
# 1.b  CONFIG PARALLÉLISME  ─ utilise exactement les cœurs Slurm
# ======================================================================
n_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))

## Bas-niveau (OpenMP / BLAS)
Sys.setenv(OMP_NUM_THREADS      = n_threads,
           OPENBLAS_NUM_THREADS = n_threads)

## data.table
data.table::setDTthreads(n_threads)

## mclapply / pbapply
options(mc.cores = n_threads)
Sys.setenv(MC_CORES = n_threads)

## ranger – on garde la valeur dans une variable
ranger_threads <- n_threads

dbg_head(sprintf("CONFIG : %d threads alloués", n_threads))



# ==============================================================================
# 2. Chargement et fusion des fichiers AIS
# ==============================================================================
load_AIS_files <- function(directory) {
  files <- list.files(path = directory, pattern = "\\.csv$", full.names = TRUE)
  dt_list <- lapply(files, function(f) {
    dt <- fread(f, stringsAsFactors = FALSE)
    # Colonnes : Lon Lat Course Timestamp Speed Seg_id
    setnames(dt, c("Lon","Lat","Course","Timestamp","Speed","Seg_id"))
    dt[, Navire := tools::file_path_sans_ext(basename(f))]
    dt
  })
  rbindlist(dt_list)
}

ais_directory <- "~/scratch/AIS_data"
out_dir       <- "~/scratch/output"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ais_data <- load_AIS_files(ais_directory)

# ==============================================================================
# 3. Conversion du Timestamp
# ==============================================================================
ais_data[, Timestamp := as.POSIXct(Timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]
ais_data[, Annee := year(Timestamp)]

# ==============================================================================
# 3.1 Fenêtre temporelle « core »
# ==============================================================================
core_years <- 2012:2024
ais_data_core <- ais_data[Annee %in% core_years]

# ==============================================================================
# 4. Caractéristiques navires
# ==============================================================================
vessel_specs <- data.table(
  Navire = c("Cristobal Colon","Leiv Eiriksson","Ham 318 Sleephopperzuiger",
             "Fairway","Queen Of The Netherlands","Inai Kenanga",
             "Vasco Da Gama","Vox Maxima","Charles Darwin",
             "Congo River","Goryo 6 Ho"),
  Owner = c("Dredging & Maritime Management","Jan De Nul Luxembourg","Ham 318",
            "Boskalis Westminster Shipping","Boskalis Westminster Shipping","Inai Kiara",
            "Flanders Dredging Corp","Vox Maxima","Jan De Nul Luxembourg",
            "CRiver Shipping","Hyundai Engineering & Steel"),
  total_installed_power_kW = c(38364,38364,28636,27550,27634,33335,37060,31309,23600,25445,12799),
  hopper_capacity_m3       = c(46000,45458,37293,35508,35500,NA,33125,31200,30500,30000,27000),
  length_overall_m         = c(223,223,227.2,230.71,230.71,197.7,201,195,183.2,168,224),
  draught_m                = c(15.15,15.15,13.37,11.03,11.03,NA,14.6,12.25,13,9.86,12.33),
  sailing_speed_knots      = c(18,18,17.3,16.1,16.1,NA,16.5,17,14,16.6,12),
  suction_pipe_diameter_mm = c(2600,1300,1200,1200,1200,2400,1400,1300,1200,1300,60),
  dredging_depth_m         = c(155,155,70,55,83,NA,60,70,93.5,36,NA),
  IMO_number               = c(9429572,9429584,9229556,9132454,9164031,9568782,
                               9187473,9454096,9528079,9574523,8119728)
)
ais_data_core <- merge(ais_data_core, vessel_specs, by = "Navire", all.x = TRUE)

# ==============================================================================
# 5. Classification vitesse grossière
# ==============================================================================
ais_data_core[, Activity := fifelse(Speed < 0.5, "manoeuvres/arrets",
                             fifelse(Speed < 3,  "dragage_potentiel",
                             fifelse(Speed < 10, "transit_loaded",
                             fifelse(Speed < 18, "transit_unloaded","Autre"))))]

# ==============================================================================
# 6. Feature engineering
# ==============================================================================
ais_data_core[, Heure         := hour(Timestamp)]
ais_data_core[, Mois          := month(Timestamp)]
ais_data_core[, Accel         := c(NA, diff(Speed)) / c(NA, diff(as.numeric(Timestamp)))]
ais_data_core[is.na(Accel), Accel := 0]
ais_data_core[, Course_change := c(NA, abs(diff(Course)))]
ais_data_core[is.na(Course_change), Course_change := 0]

q95 <- quantile(ais_data_core$Course_change, 0.95, na.rm = TRUE)
ais_data_core[, norm_course_change := pmax(0, pmin(1, 1 - Course_change/q95))]

# ==============================================================================
# 7. GMM sur la vitesse
# ==============================================================================
speeds <- ais_data_core$Speed
mclust_model <- Mclust(speeds, G = 1:5)
posterior_probs <- mclust_model$z
ais_data_core[, paste0("p_component_", 1:ncol(posterior_probs)) := as.data.table(posterior_probs)]
ais_data_core[, comp := apply(posterior_probs, 1, which.max)]

# ==============================================================================
# 8. Lissage comportemental
# (code inchangé : smooth_behavior_transition reprend vos règles)
# ==============================================================================

## 8-a. étiquettes initiales ----------------------------------------------------
ais_data_core[, behavior := 
                fifelse(comp == 1, "stops",
                        fifelse(comp == 2, "slow_maneuvers",
                                fifelse(comp == 3, "dredging",
                                        fifelse(comp == 4, "loaded_transit",
                                                fifelse(comp == 5, "unloaded_transit", NA_character_)
                                        )
                                )
                        )
                )
]

# Convertir Lon et Lat en numérique
ais_data_core[, `:=`(
  Lon = as.numeric(Lon),
  Lat = as.numeric(Lat)
)]

## 8-b. matrice des coûts --------------------------------------------------------
transition_cost <- matrix(c(
  0, 2, 2, 2, 2,
  1, 0, 2, 3, 2,
  2, 2, 0, 2, 2,
  3, 3, 2, 0, 2,
  2, 2, 2, 2, 0
), 5, 5, byrow = TRUE,
dimnames = list(
  c("stops","slow_maneuvers","dredging",
    "loaded_transit","unloaded_transit"),
  c("stops","slow_maneuvers","dredging",
    "loaded_transit","unloaded_transit")))

## 8-c. lissage amélioré ---------------------------------------------------------
smooth_behavior_transition <- function(labels, speeds,
                                       transition_cost,
                                       threshold   = 3,
                                       dredge_min  = 1,   # kn
                                       dredge_max  = 3.5) {
  
  ## (1) run-length smoothing -----------------------------------------------
  r   <- rle(labels)
  cum <- cumsum(r$lengths)
  beg <- c(1, head(cum, -1) + 1)
  
  for (i in seq_along(r$lengths)) {
    if (r$lengths[i] < threshold) {
      vbar <- mean(speeds[beg[i]:cum[i]])
      if (vbar <= dredge_max) {
        prev_lab <- if (i > 1)               r$values[i-1] else NA
        next_lab <- if (i < length(r$values)) r$values[i+1] else NA
        c_prev   <- if (!is.na(prev_lab)) transition_cost[prev_lab , r$values[i]] else Inf
        c_next   <- if (!is.na(next_lab)) transition_cost[next_lab , r$values[i]] else Inf
        r$values[i] <- if (c_prev < c_next) prev_lab else next_lab
      }
    }
  }
  lbl <- inverse.rle(r)
  
  ## (2) cohérence vitesse / label -------------------------------------------
  bad <- which(lbl == "dredging" &
                 (speeds < dredge_min | speeds > dredge_max))
  
  if (length(bad) > 0) {
    for (j in bad) {
      prev_lab <- if (j > 1)           lbl[j-1] else NA
      next_lab <- if (j < length(lbl)) lbl[j+1] else NA
      
      cand <- if (speeds[j] < dredge_min) {
        c("slow_maneuvers","stops")
      } else {
        c("loaded_transit","unloaded_transit")
      }
      
      best_lbl  <- cand[1]; best_cost <- Inf
      for (c in cand) {
        cp <- if (!is.na(prev_lab)) transition_cost[prev_lab , c] else 0
        cn <- if (!is.na(next_lab)) transition_cost[c       , next_lab] else 0
        if (cp + cn < best_cost) {
          best_lbl  <- c
          best_cost <- cp + cn
        }
      }
      lbl[j] <- best_lbl
    }
  }
  lbl
}

## 8-d. application du lissage --------------------------------------------------
ais_data_core[, behavior_smooth :=
                smooth_behavior_transition(behavior, Speed, transition_cost),
              by = Seg_id]

## 8-e. sous-segments homogènes -------------------------------------------------
ais_data_core[, sub_seg_id := paste0(Seg_id, "_", rleid(behavior_smooth))]

# ==============================================================================
# 11. Score composite Dragage
# ==============================================================================
ais_data_core[, dredging_indicator := as.integer(behavior_smooth=="dredging")]
q95_accel <- quantile(ais_data_core$Accel, 0.95, na.rm = TRUE)
ais_data_core[, norm_accel := pmax(0, pmin(1, Accel/q95_accel))]
ais_data_core[, dragage_score := 0.5*dredging_indicator +
                                 0.25*norm_course_change +
                                 0.25*norm_accel]
ais_data_core[, Dragage := as.integer(dragage_score >= 0.5)]

# ------------------------------------------------------------------
# Sauvegardes intermédiaires
# ------------------------------------------------------------------
fwrite(ais_data_core, file.path(out_dir, "AIS_data_core_preprocessed.csv"))
saveRDS(ais_data_core, file.path(out_dir, "AIS_data_core_preprocessed.rds"))
# ─────────── DBG-2 : état mémoire avant grid-search ───────────
dbg_head("État avant grid-search")
cat("Mémoire R utilisée :", dbg_mem_mb(), "Mo\n")
cat("nrow(ais_data_core) :", nrow(ais_data_core), "\n")
flush.console()

# ======================================================================
# 12.  Grid-search poids  (optimisé + multi-threads ranger)
# ======================================================================
library(ranger)
library(pROC)

grid_w <- expand.grid(
  w1 = seq(0.10, 0.80, 0.05),
  w2 = seq(0.05, 0.80, 0.05),
  w3 = seq(0.05, 0.80, 0.05)
)[abs(rowSums(.) - 1) < 0.02, ]

cat("→", nrow(grid_w), "combinaisons de poids à tester\n")

## ----------  fonction évaluant une combinaison -----------------------
eval_weights <- function(w) {
  t0 <- proc.time()[3]

  ais_tmp <- ais_data_core[, .(
    score_tmp = w[1]*dredging_indicator +
                w[2]*norm_course_change +
                w[3]*norm_accel,
    label_tmp = Dragage,
    Annee
  )][complete.cases(score_tmp, label_tmp, Annee)]

  yrs  <- sort(unique(ais_tmp$Annee))
  aucs <- numeric(length(yrs))

  for (k in seq_along(yrs)) {
    yr    <- yrs[k]
    train <- ais_tmp[Annee != yr]
    test  <- ais_tmp[Annee == yr]

    rf <- ranger(label_tmp ~ score_tmp,
                 data          = train,
                 num.trees     = 30,
                 min.node.size = 10,
                 probability   = TRUE,
                 num.threads   = ranger_threads)   # ← multi-threads

    probs   <- predict(rf, data = test)$predictions[, "1"]
    aucs[k] <- pROC::auc(pROC::roc(test$label_tmp, probs, quiet = TRUE))
  }

  mean(aucs)
}

## ----------  boucle principale + log léger ---------------------------
DBG_PRINT_EVERY <- 20             # fréquence d'affichage
auc_results <- numeric(nrow(grid_w))

for (i in seq_len(nrow(grid_w))) {
  auc_results[i] <- eval_weights(as.numeric(grid_w[i, ]))

  if (i %% DBG_PRINT_EVERY == 0 || i == nrow(grid_w)) {
    cat(sprintf("%s  |  combo %3d / %3d  AUC=%.4f\n",
                dbg_time(), i, nrow(grid_w), auc_results[i]))
    flush.console()
  }
}

best_idx <- which.max(auc_results)
best_w   <- as.numeric(grid_w[best_idx, ])
best_auc <- auc_results[best_idx]

cat(sprintf(
  "\nMeilleurs poids : w1=%.2f  w2=%.2f  w3=%.2f   (AUC = %.3f)\n",
  best_w[1], best_w[2], best_w[3], best_auc))


# Application
ais_data_core[, dragage_score_opt := best_w[1]*dredging_indicator +
                                     best_w[2]*norm_course_change +
                                     best_w[3]*norm_accel]
ais_data_core[, Dragage_opt := as.integer(dragage_score_opt >= 0.5)]

# ------------------------------------------------------------------
# Sauvegardes finales
# ------------------------------------------------------------------
saveRDS(list(w1 = best_w[1], w2 = best_w[2], w3 = best_w[3], AUC = best_auc),
        file = file.path(out_dir, "weights_dragage_score_opt.rds"))
saveRDS(ais_data_core,
        file = file.path(out_dir, "AIS_data_core_preprocessed.rds"))
fwrite(ais_data_core,
       file = file.path(out_dir, "AIS_data_core_preprocessed.csv"))
