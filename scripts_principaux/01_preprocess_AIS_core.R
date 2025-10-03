# ==============================================================================
# 1. Chargement des bibliothèques nécessaires
# ============================================================================
library(data.table)    # Manipulation efficace des données
library(lubridate)     # Gestion des dates
library(mclust)        # Modèle de mélange pour la vitesse
library(ranger)        # Modèle Random Forest
library(caret)         # Partitionnement et évaluation
library(pROC)          # Calcul de l'AUC et courbes ROC
library(ggplot2)       # Visualisations graphiques
library(marmap)        # (Optionnel) Bathymétrie
library(raster)        # (Optionnel) Manipulation de raster
library(sf)            # Données spatiales
library(dbscan)        # Clustering spatial avec HDBSCAN
library(dplyr)         # Analyse via pipe
library(zoo)           # Lissage temporel (moyenne glissante)
if (!require(depmixS4)) install.packages("depmixS4")
library(depmixS4)      # Modèles à états cachés (HMM)
if (!require(pbapply)) install.packages("pbapply")
library(pbapply)       # Pour suivre la progression de la grid search

# Vérification et installation des packages nécessaires
if (!require(matrixStats)) {
  install.packages("matrixStats")
  library(matrixStats)
}

# ==============================================================================
# 2. Chargement et fusion des fichiers AIS
# ============================================================================
load_AIS_files <- function(directory) {
  files <- list.files(path = directory, pattern = "\\.csv$", full.names = TRUE)
  dt_list <- lapply(files, function(f) {
    dt <- fread(f, stringsAsFactors = FALSE)
    # Chaque fichier doit avoir les colonnes (dans cet ordre) : Lon, Lat, Course, Timestamp, Speed, Seg_id
    setnames(dt, c("Lon", "Lat", "Course", "Timestamp", "Speed", "Seg_id"))
    dt[, Navire := tools::file_path_sans_ext(basename(f))]
    return(dt)
  })
  rbindlist(dt_list)
}

ais_directory <- "C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/Track data"
ais_data <- load_AIS_files(ais_directory)

# ==============================================================================
# 3. Conversion du Timestamp
# ============================================================================
ais_data[, Timestamp := as.POSIXct(Timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]
ais_data[, Annee := year(Timestamp)]

library(geosphere)   # for distHaversine

## -----------------------------------------------------------------
## 3.1.1  JOUR ACTIF = n_msg ≥ max(20 ; 0,4 × mediane pings/jour)
## -----------------------------------------------------------------
ais_data[, date := as.Date(Timestamp)]
setorder(ais_data, Navire, Timestamp)

# distance en km entre deux pings consécutifs (optionnel)
ais_data[, dist_km := c(0, distHaversine(
  matrix(c(Lon[-.N], Lat[-.N]), ncol = 2),
  matrix(c(Lon[-1 ], Lat[-1 ]), ncol = 2)) / 1000),
  by = Navire]

## 3.1.1-a  médiane de pings / jour pour chaque navire -----------------
med_pings <- ais_data[, .N, by = .(Navire, date)
][, .(med_pings_jour = median(N)), by = Navire]

## 3.1.1-b  résumé quotidien ------------------------------------------
daily <- ais_data[, .(
  n_msg   = .N,
  km_day  = sum(dist_km, na.rm = TRUE)
), by = .(Navire, date)]

daily <- merge(daily, med_pings, by = "Navire", all.x = TRUE)

# règle : actif ⇔ n_msg ≥ max(20 ; 0.4 × médiane)
daily[, active_day :=
        n_msg >= pmax(20, 0.4 * med_pings_jour)]

daily[, year := year(date)]

## -----------------------------------------------------------------
## 3.1.2  MATRICE COUVERTURE « jours actifs » -------------------------
##         – valeurs ∈ [0,1] = part des jours actifs / an
## -----------------------------------------------------------------
cov_mat <- dcast(
  daily[, .(cov = mean(active_day)), by = .(Navire, year)],
  Navire ~ year,
  value.var = "cov",
  fill = NA_real_)

dens <- as.matrix(cov_mat[, -1])      # on enlève la colonne Navire


## 3.1.3 SCORE EACH CONTIGUOUS WINDOW --------------------------------
years_num <- as.integer(colnames(dens))
n_years   <- length(years_num)
best      <- list(score = -Inf)

for (start in seq_len(n_years)) {
  for (end in start:n_years) {
    len <- end - start + 1
    if (len < 10) next              #  ➜  ≥ 10 ans seulement
    #      (remplace l'ancien 5)
    cols <- start:end
    yrs  <- years_num[cols]
    
    sub <- dens[, cols, drop = FALSE]
    sub <- sub[rowSums(is.na(sub)) == 0, , drop = FALSE]
    if (!nrow(sub)) next
    
    Cvals      <- matrixStats::rowMedians(sub)
    window_med <- median(Cvals)
    window_min <- min(Cvals)
    window_cv  <- sd(Cvals) / window_med
    
    S <- len * window_med * window_min^2 / (1 + window_cv)
    if (S > best$score)
      best <- list(score = S, yrs = yrs, vessels = rownames(sub))
  }
}


core_years <- best$yrs

message(sprintf("✅  Fenêtre optimale = %s – %s  (score %.3f)",
                min(core_years), max(core_years), best$score))

## 3.1.4  SUBSET THE AIS STREAM ------------------------------------
ais_data_core <- ais_data[year(Timestamp) %in% core_years &
                            Navire %in% best$vessels]


# ==============================================================================
# 4. Fusion des caractéristiques des navires (vessel_specs)
# ============================================================================
vessel_specs <- data.table(
  Navire = c("Cristobal Colon", "Leiv Eiriksson", "Ham 318 Sleephopperzuiger",
             "Fairway", "Queen Of The Netherlands", "Inai Kenanga",
             "Vasco Da Gama", "Vox Maxima", "Charles Darwin", "Congo River", "Goryo 6 Ho"),
  Owner = c("Dredging & Maritime Management", "Jan De Nul Luxembourg", "Ham 318",
            "Boskalis Westminster Shipping", "Boskalis Westminster Shipping", "Inai Kiara",
            "Flanders Dredging Corp", "Vox Maxima", "Jan De Nul Luxembourg", "CRiver Shipping", "Hyundai Engineering & Steel"),
  total_installed_power_kW = c(38364, 38364, 28636, 27550, 27634, 33335, 37060, 31309, 23600, 25445, 12799),
  hopper_capacity_m3       = c(46000, 45458, 37293, 35508, 35500, NA, 33125, 31200, 30500, 30000, 27000),
  length_overall_m         = c(223, 223, 227.2, 230.71, 230.71, 197.7, 201, 195, 183.2, 168, 224),
  draught_m                = c(15.15, 15.15, 13.37, 11.03, 11.03, NA, 14.6, 12.25, 13, 9.86, 12.33),
  sailing_speed_knots      = c(18, 18, 17.3, 16.1, 16.1, NA, 16.5, 17, 14, 16.6, 12),
  suction_pipe_diameter_mm = c(2600, 1300, 1200, 1200, 1200, 2400, 1400, 1300, 1200, 1300, 60),
  dredging_depth_m         = c(155, 155, 70, 55, 83, NA, 60, 70, 93.5, 36, NA),
  IMO_number               = c(9429572, 9429584, 9229556, 9132454, 9164031, 9568782, 9187473, 9454096, 9528079, 9574523, 8119728)
)

# Fusion uniquement sur le jeu core
ais_data_core <- merge(ais_data_core, vessel_specs, by = "Navire", all.x = TRUE)

# ==============================================================================
# 5. Classification initiale par vitesse (fenêtre core)
# ============================================================================
ais_data_core[, Activity := fifelse(Speed < 0.5, "manoeuvres/arrets",
                                    fifelse(Speed >= 0.5 & Speed < 3, "dragage_potentiel",
                                            fifelse(Speed >= 3 & Speed < 10, "transit_loaded",
                                                    fifelse(Speed >= 10 & Speed < 18, "transit_unloaded", "Autre"))))]

# ==============================================================================
# 6. Feature Engineering (heures, mois, accélération, changement de cap)
# ============================================================================
ais_data_core[, Heure := hour(Timestamp)]
ais_data_core[, Mois := month(Timestamp)]
ais_data_core[, Accel := c(NA, diff(Speed)) / c(NA, diff(as.numeric(Timestamp)))]
ais_data_core[is.na(Accel), Accel := 0]
ais_data_core[, Course_change := c(NA, abs(diff(Course)))]
ais_data_core[is.na(Course_change), Course_change := 0]

# Créer la variable norm_course_change
q95 <- quantile(ais_data_core$Course_change, 0.95, na.rm = TRUE)
ais_data_core[, norm_course_change := 1 - (Course_change / q95)]
ais_data_core[norm_course_change < 0, norm_course_change := 0]
ais_data_core[norm_course_change > 1, norm_course_change := 1]

# ==============================================================================
# 7. Extraction des composantes de vitesse (skew‐normal par navire)
# ==============================================================================

## 7.0 Choix du moteur de mélange
use_skew <- requireNamespace("mixsmsn", quietly = TRUE)
if (use_skew) {
  library(mixsmsn)
  message("→ mixsmsn disponible : utilisation de sms.mix (skew‐normal) par navire")
} else {
  library(mclust)
  message("→ mixsmsn absent : fallback sur GMM gaussien (mclust) par navire")
}

## 7.1 Fonction de fit
fit_speed_mix <- function(v, g_range = 2:5) {
  if (length(unique(v)) < 10) return(NULL)
  if (use_skew) {
    best   <- NULL; best_bic <- -Inf
    for (k in g_range) {
      mod <- mixsmsn::smsn.mix(v, k = k,
                               family  = "Skew.normal",
                               calc.im = FALSE, verb = FALSE)
      if (mod$bic > best_bic) { best <- mod; best_bic <- mod$bic }
    }
    list(mu   = best$mu,
         post = best$post.prob)
  } else {
    mod <- mclust::Mclust(v, G = g_range, modelNames = "V")
    list(mu   = mod$parameters$mean,
         post = mod$z)
  }
}

## 7.2 Application navire‐par‐navire
ais_data_core[, c("Speed_std","comp_std","p_dredge") := {
  mix <- fit_speed_mix(Speed)
  if (is.null(mix)) {
    list(NA_real_, NA_integer_, NA_real_)
  } else {
    mu_vec     <- mix$mu
    post       <- mix$post
    k_transit  <- which.max(mu_vec)
    mu_transit <- mu_vec[k_transit]
    ord_mu     <- order(mu_vec)
    k_dredge   <- ord_mu[ceiling(length(mu_vec)/2)]
    comp_id    <- apply(post, 1, which.max)
    p_dredge   <- post[, k_dredge]
    list(Speed / mu_transit, comp_id, p_dredge)
  }
}, by = Navire]


# ==============================================================================
# 8. Attribution initiale & lissages (sur Speed_std) – version « run-length » avec
#    contrainte de cohérence vitesse ↔ comportement, exprimée cette fois-ci en
#    nœuds grâce à la vitesse de transit μ_transit propre au navire
# ==============================================================================

## 8-0.  vitesse de transit par navire  -----------------------------------------
##       (μ_transit = moyenne de la composante "transit" ; ici on l'estime
##        simplement par la médiane de Speed / Speed_std pour chaque navire)
ais_data_core[
  , mu_transit := median(Speed / Speed_std, na.rm = TRUE),
  by = Navire]

## 8-1.  étiquette brute issue de la composante majoritaire ---------------------
ais_data_core[, behavior := fifelse(comp_std == 1, "stops",
                                    fifelse(comp_std == 2, "slow_maneuvers",
                                            fifelse(comp_std == 3, "dredging",
                                                    fifelse(comp_std == 4, "loaded_transit",
                                                            fifelse(comp_std == 5,
                                                                    "unloaded_transit",
                                                                    NA_character_)))))]
print(table(ais_data_core$behavior, useNA = "ifany"))

## 8-2.  matrice des coûts de transition ---------------------------------------
transition_cost <- matrix(
  c(0,2,2,2,2,
    1,0,2,3,2,
    2,2,0,2,2,
    3,3,2,0,2,
    2,2,2,2,0),
  nrow = 5, byrow = TRUE,
  dimnames = list(
    c("stops","slow_maneuvers","dredging",
      "loaded_transit","unloaded_transit"),
    c("stops","slow_maneuvers","dredging",
      "loaded_transit","unloaded_transit"))
)

## 8-3.  fonction de lissage « run-length » ------------------------------------
smooth_behavior_transition <- function(labels, speed_kn, tc,
                                       threshold   = 3,
                                       dredge_min  = 1,   # [kn]
                                       dredge_max  = 3.5) {
  
  ## (1) smoothing de runs trop courts
  rle_lab <- rle(labels)
  cumlen  <- cumsum(rle_lab$lengths)
  starts  <- c(1, head(cumlen, -1) + 1)
  
  for (i in seq_along(rle_lab$lengths)) {
    if (rle_lab$lengths[i] < threshold) {
      vmean <- mean(speed_kn[starts[i]:cumlen[i]], na.rm = TRUE)
      if (vmean <= dredge_max) {                   # on ne corrige que les faibles vitesses
        prev <- if (i > 1)                rle_lab$values[i-1] else NA
        next <- if (i < length(rle_lab$values)) rle_lab$values[i+1] else NA
        c_prev <- if (!is.na(prev)) tc[prev , rle_lab$values[i]] else Inf
        c_next <- if (!is.na(next)) tc[next , rle_lab$values[i]] else Inf
        rle_lab$values[i] <- if (c_prev < c_next) prev else next
      }
    }
  }
  lbl <- inverse.rle(rle_lab)
  
  ## (2) cohérence vitesse vs label  -------------------------------------------
  bad <- which(lbl == "dredging" &
                 (speed_kn < dredge_min | speed_kn > dredge_max))
  
  if (length(bad)) {
    for (j in bad) {
      prev <- if (j > 1)           lbl[j-1] else NA
      next <- if (j < length(lbl)) lbl[j+1] else NA
      
      cand <- if (speed_kn[j] < dredge_min) {
        c("slow_maneuvers","stops")
      } else {
        c("loaded_transit","unloaded_transit")
      }
      
      best     <- cand[1]; best_cost <- Inf
      for (c in cand) {
        cp <- if (!is.na(prev)) tc[prev , c ] else 0
        cn <- if (!is.na(next)) tc[c    , next] else 0
        if (cp + cn < best_cost) {
          best      <- c
          best_cost <- cp + cn
        }
      }
      lbl[j] <- best
    }
  }
  lbl
}

## 8-4.  application du lissage (par segment) -----------------------------------
##       – on travaille sur la vitesse en nœuds : speed_kn = Speed_std × μ_transit
ais_data_core[
  , speed_kn := Speed_std * mu_transit]

ais_data_core[
  , behavior_smooth :=
    smooth_behavior_transition(behavior, speed_kn, transition_cost),
  by = Seg_id]

## 8-5.  sous-segments homogènes -------------------------------------------------
ais_data_core[
  , sub_seg_id := paste0(Seg_id, "_", rleid(behavior_smooth))]

## 8.6 (Optionnel) Lissage HMM sur Speed_std
library(depmixS4)
hmm_smoother <- function(spd_std, n_states = 5) {
  keep <- !is.na(spd_std)
  v    <- spd_std[keep]
  if (length(v) < 20) return(rep(NA_integer_, length(spd_std)))
  d    <- data.frame(spd = v)
  mod  <- depmix(spd ~ 1, data = d, nstates = n_states, family = gaussian())
  set.seed(123); fit <- tryCatch(fit(mod, verbose = FALSE), error = function(e) NULL)
  if (is.null(fit)) return(rep(NA_integer_, length(spd_std)))
  states <- posterior(fit, type="viterbi")$state
  out <- rep(NA_integer_, length(spd_std)); out[keep] <- states; out
}

ais_data_core[, hmm_state := hmm_smoother(Speed_std), by = Navire]
state_speed <- ais_data_core[!is.na(hmm_state),
                             .(mean_spd = mean(Speed_std)), by = hmm_state][order(mean_spd)]
map_states <- setNames(
  c("stops","slow_maneuvers","dredging","loaded_transit","unloaded_transit"),
  state_speed$hmm_state
)
ais_data_core[, behavior_hmm := map_states[as.character(hmm_state)]]
ais_data_core[, sub_seg_id_hmm := paste0(Seg_id, "_", rleid(behavior_hmm)), by = Seg_id]

cat("\n*** MATRICE DE CONFUSION Heuristique vs HMM ***\n")
print(table(heuristique = ais_data_core$behavior_smooth,
            HMM         = ais_data_core$behavior_hmm), zero.print = ".")


# ==============================================================================
# 9. (zones, cycles, etc. sur ais_data_core)
# ==============================================================================
# ... (identique mais en remplaçant ais_data par ais_data_core)

# ==============================================================================
# 11. Calcul du Score Composite pour Dragage (mise à jour)
# ============================================================================
ais_data_core[, dredging_indicator := as.integer(behavior_smooth=="dredging")]
q95_accel <- quantile(ais_data_core$Accel,0.95,na.rm=TRUE)
ais_data_core[, norm_accel := Accel/q95_accel]
ais_data_core[norm_accel>1, norm_accel:=1]
ais_data_core[norm_accel<0, norm_accel:=0]
ais_data_core[, dragage_score := 0.5*dredging_indicator +
                0.25*norm_course_change +
                0.25*norm_accel]
seuil_score <- 0.5
ais_data_core[, Dragage := as.integer(dragage_score>=seuil_score)]
print(summary(ais_data_core$dragage_score))

# Nombre de points dragage par navire
print(ais_data_core[Dragage==1, .N, by=Navire])

# ==============================================================================
# 12. Grid-search pour optimiser les poids du score composite (w1,w2,w3)
#    -----------------------------------------------------------------
#    - w1 : dredging_indicator
#    - w2 : norm_course_change
#    - w3 : norm_accel
# ==============================================================================

library(pbapply)     # barre de progression
library(ranger)      # Random-Forest (évaluation rapide)
library(pROC)        # AUC

# ------------------------------------------------------------------
# 12.1 Grille de poids : pas de 0,05 – somme ≈ 1 (tolérance 0,02)
# ------------------------------------------------------------------
grid_w <- expand.grid(
  w1 = seq(0.10, 0.80, by = 0.05),
  w2 = seq(0.05, 0.80, by = 0.05),
  w3 = seq(0.05, 0.80, by = 0.05)
)

grid_w <- grid_w[abs(rowSums(grid_w) - 1) < 0.02, ]
cat("→", nrow(grid_w), "combinaisons de poids à tester\n")

# ------------------------------------------------------------------
# 12.2  Fonction d'évaluation – version sûre (sans NA)
# ------------------------------------------------------------------
eval_weights <- function(w) {
  
  # 1. score provisoire
  ais_tmp <- copy(ais_data_core)
  ais_tmp[, score_tmp := w[1]*dredging_indicator +
            w[2]*norm_course_change +
            w[3]*norm_accel]
  
  # 2. étiquette binaire – NA si score_tmp manquant
  ais_tmp[, label_tmp := fifelse(!is.na(score_tmp), 
                                 as.integer(score_tmp >= 0.5), 
                                 NA_integer_)]
  
  # 3. on enlève toutes les lignes incomplètes AVANT le leave-one-year-out
  ais_tmp <- ais_tmp[complete.cases(score_tmp, label_tmp, Annee)]
  
  years <- sort(unique(ais_tmp$Annee))
  auc_by_year <- numeric(length(years))
  
  # 4. validation « leave-one-year-out »
  for (k in seq_along(years)) {
    test_year  <- years[k]
    train      <- ais_tmp[Annee != test_year]
    test       <- ais_tmp[Annee == test_year]
    
    # ranger a besoin d'une factor sans NA
    train[, label_tmp := factor(label_tmp)]
    test [, label_tmp := factor(label_tmp)]
    
    rf <- ranger(label_tmp ~ score_tmp,
                 data = train,
                 num.trees = 30,
                 min.node.size = 10,
                 probability = TRUE)
    
    probs <- predict(rf, data = test)$predictions[, "1"]
    roc_obj <- pROC::roc(test$label_tmp, probs, levels = c("0", "1"), quiet = TRUE)
    auc_by_year[k] <- pROC::auc(roc_obj)
  }
  
  # moyenne des AUC sur toutes les années
  mean(auc_by_year, na.rm = TRUE)
}


# ------------------------------------------------------------------
# 12.3 Grid-search avec pbapply (version séquentielle)
# ------------------------------------------------------------------
cat("Début de la grid-search...\n")
auc_results <- sapply(
  1:nrow(grid_w),
  function(i) {
    if (i %% 50 == 0) cat("Progression:", i, "/", nrow(grid_w), "\n")
    eval_weights(as.numeric(grid_w[i, ]))
  }
)

best_idx <- which.max(auc_results)
best_w   <- as.numeric(grid_w[best_idx, ])
best_auc <- auc_results[best_idx]

cat(sprintf("\nMeilleurs poids trouvés : w1 = %.2f, w2 = %.2f, w3 = %.2f  (AUC = %.3f)\n",
            best_w[1], best_w[2], best_w[3], best_auc))

# ------------------------------------------------------------------
# 12.4 Application des poids optimaux au jeu core
# ------------------------------------------------------------------
ais_data_core[, dragage_score_opt :=
                best_w[1]*dredging_indicator +
                best_w[2]*norm_course_change +
                best_w[3]*norm_accel]

ais_data_core[, Dragage_opt := as.integer(dragage_score_opt >= 0.5)]

# Vous pouvez maintenant comparer Dragage_opt au label précédent
cat("\nComparaison rapide :\n")
print(table(Initial = ais_data_core$Dragage,
            Optimisé = ais_data_core$Dragage_opt))

# ------------------------------------------------------------------
# (optionnel) conserver les poids et l'AUC dans un objet
# ------------------------------------------------------------------
opt_weights <- list(w1 = best_w[1], w2 = best_w[2], w3 = best_w[3], AUC = best_auc)
saveRDS(opt_weights, "weights_dragage_score_opt.rds")


# Sauvegardes
saveRDS(ais_data_core,file="AIS_data_core_preprocessed.rds")
write.csv(ais_data_core,file="C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/AIS_data_core_preprocessed.csv",row.names=FALSE)
