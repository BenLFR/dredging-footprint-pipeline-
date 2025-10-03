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

# ==============================================================================
# 3.1 Identification de la période de recouvrement maximal (>= 90 % des navires)
# ============================================================================
# D’après vos résultats, les années 2014 à 2022 couvrent au minimum 91,7 % des navires
core_years <- 2012:2024

# On crée le sous‑jeu de données limité à cette fenêtre
ais_data_core <- ais_data[Annee %in% core_years]

# Vous pouvez vérifier rapidement la couverture
table(ais_data_core$Annee) / length(unique(ais_data$Navire))

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
# 7. Extraction des composantes de vitesse avec mclust
# ============================================================================
speeds <- ais_data_core$Speed
mclust_model <- Mclust(speeds, G = 1:5)

# Moyennes et écarts-types
component_means <- mclust_model$parameters$mean
cat("Moyennes des composantes :", component_means, "\n")
component_sd <- sqrt(mclust_model$parameters$variance$sigmasq)
cat("Ecart-types des composantes :", component_sd, "\n")

# Probabilités a posteriori
posterior_probs <- mclust_model$z
for(i in 1:ncol(posterior_probs)){
  col_name <- paste0("p_component_", i)
  ais_data_core[[col_name]] <- posterior_probs[, i]
}
ais_data_core[, max_prob := apply(posterior_probs, 1, max)]
ais_data_core[, second_max_prob := apply(posterior_probs, 1, function(x) sort(x, decreasing = TRUE)[2])]
ais_data_core[, margin_prob := max_prob - second_max_prob]
ais_data_core[, comp := apply(posterior_probs, 1, which.max)]

# ==============================================================================
# 8. Attribution initiale des comportements et lissage contraint
#    -----------------------------------------------------------
#    • étiquettes brutes issues du GMM
#    • lissage des runs courts via une matrice de coûts
#    • cohérence vitesse-comportement imposée :
#        – dredging     ∈ [1 ; 3.5] kn
#        – < 1 kn  → slow_maneuvers / stops
#        – > 3.5 kn → loaded / unloaded transit
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
  if (length(bad)) {
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

# Sauvegardes
saveRDS(ais_data_core,file="AIS_data_core_preprocessed.rds")
write.csv(ais_data_core,file="C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/AIS_data_core_preprocessed.csv",row.names=FALSE)

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
# 12.2  Fonction d’évaluation – version sûre (sans NA)
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
    
    # ranger a besoin d’une factor sans NA
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
# 12.3 Grid-search avec pbapply
# ------------------------------------------------------------------
auc_results <- pbsapply(
  1:nrow(grid_w),
  function(i) eval_weights(as.numeric(grid_w[i, ])),
  cl = NULL
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
# (optionnel) conserver les poids et l’AUC dans un objet
# ------------------------------------------------------------------
opt_weights <- list(w1 = best_w[1], w2 = best_w[2], w3 = best_w[3], AUC = best_auc)
saveRDS(opt_weights, "weights_dragage_score_opt.rds")


# Sauvegardes
saveRDS(ais_data_core,file="AIS_data_core_preprocessed.rds")
write.csv(ais_data_core,file="C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/AIS_data_core_preprocessed.csv",row.names=FALSE)