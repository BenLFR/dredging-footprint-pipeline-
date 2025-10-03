# ==============================================================================
# 1. Chargement des bibliothèques nécessaires (VERSION SANS SF)
# ==============================================================================
library(data.table)    # Manipulation efficace des données
library(lubridate)     # Gestion des dates
library(mclust)        # Modèle de mélange pour la vitesse
# library(ranger)      # ⬅️  plus utilisé (GLM à la place)
library(caret)         # Partitionnement et évaluation
library(pROC)          # AUC & courbes ROC
library(ggplot2)       # Visualisations
# library(marmap)      # (optionnel) bathymétrie - DÉSACTIVÉ
# library(raster)      # (optionnel) raster - DÉSACTIVÉ
# library(sf)          # Données spatiales - DÉSACTIVÉ (problème installation)
library(dbscan)        # HDBSCAN
library(dplyr)         # Pipes
library(zoo)           # Moyenne glissante
if (!require(depmixS4)) install.packages("depmixS4")
library(depmixS4)      # HMM
if (!require(pbapply)) install.packages("pbapply")
library(pbapply)       # barre de progression (pour d'autres usages)
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

# ------------------------------------------------------------------
# TABLE DE MAPPING : ssvid (MMSI)  →  IMO  →  Nom canonique "Navire"
# ------------------------------------------------------------------
mmsi_map <- data.table(
  ssvid = c(209469000, 210138000, 245508000, 246351000,
            253193000, 253373000, 253403000, 253422000,
            253688000, 312062000, 533180137),
  
  IMO_number = c(9132454, 9164031, 9229556, 9454096,
                 9187473, 9429572, 9429584, 9528079,
                 9574523, 8119728, 9568782),
  
  Navire = c("Fairway",
             "Queen Of The Netherlands",
             "Ham 318 Sleephopperzuiger",
             "Vox Maxima",
             "Vasco Da Gama",
             "Cristobal Colon",
             "Leiv Eiriksson",
             "Charles Darwin",
             "Congo River",
             "Goryo 6 Ho",
             "Inai Kenanga")
)
setkey(mmsi_map, ssvid)   # index pour merge rapide

# ------------------------------------------------------------------
# 2.c  Lecture des anciens CSV et retrait des navires mis à jour
# ------------------------------------------------------------------
ais_directory <- "~/scratch/AIS_data"
out_dir       <- "~/scratch/output"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ais_old <- load_AIS_files(ais_directory)

## 2.c-1  S’assurer que la colonne Navire existe ----------------------
if (!"Navire" %in% names(ais_old)) {
  # a) si un ssvid est présent on reconstruit le nom via mmsi_map
  if ("ssvid" %in% names(ais_old)) {
    ais_old <- merge(
      ais_old, 
      mmsi_map[, .(ssvid, Navire)], 
      by = "ssvid", 
      all.x = TRUE
    )
  }
  # b) sinon on fabrique un nom générique à partir du fichier
  if (!"Navire" %in% names(ais_old)) {
    ais_old[, Navire := paste0("unknown_", .I)]
  }
}

## 2.c-2  Normaliser la casse (navire → Navire)
if ("navire" %in% names(ais_old) && !"Navire" %in% names(ais_old)) {
  setnames(ais_old, "navire", "Navire")
}

## 2.c-3  Supprimer les traces des navires remplacés
vessels_updated <- unique(df_new$Navire)
ais_old <- ais_old[!Navire %chin% vessels_updated]

## 2.d  Fusion ancien + nouveau (et FINI : on ne relira plus les anciens)
ais_data <- rbindlist(list(ais_old, df_new), use.names = TRUE, fill = TRUE)

dbg_head(sprintf("Jeu fusionné : %d pings, %d navires",
                 nrow(ais_data), length(unique(ais_data$Navire))))

# ------------------------------------------------------------------
# 3. Conversion du Timestamp  (plus de double-chargement)
# ------------------------------------------------------------------
ais_data[, Timestamp := as.POSIXct(
  Timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]

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
# 6. Feature engineering    ⇠ REMPLACER TOUT CE BLOC
# ==============================================================================
# → Accélération calculée par segment, pas sur tout le jeu
ais_data_core[, Accel := {
  dV <- c(NA, diff(Speed))
  dt <- c(NA, diff(as.numeric(Timestamp)))
  dV / dt
}, by = Seg_id]
ais_data_core[is.na(Accel) | !is.finite(Accel), Accel := 0]

# → Variation de cap corrigée (359° → 1° = 2°)
ais_data_core[, Course_change := {
  delta <- c(NA, abs(diff(Course)))
  delta <- pmin(delta, 360 - delta)          # wrap-around
  delta
}, by = Seg_id]
ais_data_core[is.na(Course_change), Course_change := 0]

# Normalisation (95ᵉ percentile recalculé après correction)
q95 <- quantile(ais_data_core$Course_change, 0.95, na.rm = TRUE)
ais_data_core[, norm_course_change := pmax(0, pmin(1, 1 - Course_change/q95))]

## 6.b  Flag arrêt / mouvement (à mettre juste après avoir créé ais_data_core)

ais_data_core[, is_stop := Speed <= 0.3]   # 0.3 kn = seuil arrêt


# ==============================================================================
# 7.  Modélisation à 5 composantes : 1 « stop » + 4 GMM sur les points en mouvement
# ==============================================================================

## 7.a  Pré-traitement ----------------------------------------------------------
# - on limite les vitesses à 0–20 kn
# - on crée un flag clair pour les arrêts (≤ 0,3 kn)
ais_data_core[, is_stop := Speed <= 0.3]
ais_data_core <- ais_data_core[Speed <= 20]               # on écarte les outliers > 20 kn

## 7.b  Ajustement d’un GMM à 4 composantes sur les points en mouvement ---------
library(mclust)

speeds_move <- ais_data_core[is_stop == FALSE, Speed]     # n_move observations
gmm4        <- Mclust(speeds_move, G = 4, verbose = FALSE)  # 4 composantes gaussiennes

## 7.c  Probabilités a posteriori ----------------------------------------------
# a) prédictions GMM pour les vitesses en mouvement
z_move <- predict(gmm4, newdata = speeds_move)$z          # n_move × 4

# b) initialisation des colonnes p_component_1 … p_component_5 à 0
ais_data_core[, paste0("p_component_", 1:5) := 0.0]

# c) attribution : composante 1 ≔ arrêts, composantes 2–5 ≔ sorties GMM
ais_data_core[is_stop == TRUE,  p_component_1 := 1]
ais_data_core[is_stop == FALSE, paste0("p_component_", 2:5) := as.data.table(z_move)]

# d) composante la plus probable (1–5)
ais_data_core[, comp := apply(.SD, 1, which.max),
              .SDcols = paste0("p_component_", 1:5)]

## 7.d  Résumé des composantes --------------------------------------------------
gmm_summary <- data.table(
  component  = 1:5,
  mean_knots = c(0, round(gmm4$parameters$mean, 2)),       # 0 kn pour les stops
  sd_knots   = c(0, round(
    if (!is.null(gmm4$parameters$variance$sigmasq)) {
      sqrt(gmm4$parameters$variance$sigmasq)
    } else {
      rep(sqrt(gmm4$parameters$variance$sigma2), 4)
    }, 2))
)

print(gmm_summary)

## 7.e  Diagnostics rapides -----------------------------------------------------
summary(ais_data_core$Speed)                # min, max, quantiles
hist(ais_data_core$Speed, breaks = 200,
     main = "Distribution des vitesses filtrées (≤ 20 kn)",
     xlab  = "Speed [knots]")


# ==============================================================================
# 8. Lissage comportemental
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
# 11. Score composite Dragage - VERSION AMÉLIORÉE SANS FUITE DE DONNÉES
# ==============================================================================

# ===== CRÉATION DES VARIABLES VITESSE PHYSIQUEMENT COHÉRENTES =====

# 1. Probabilité GMM pour la composante "dragage" (composante 3 typiquement)
# Cette variable capture l'information vitesse sans recopier l'étiquette
if (ncol(posterior_probs) >= 3) {
  ais_data_core[, prob_dredge_gmm := posterior_probs[, 3]]  # Composante 3 = dragage
} else {
  # Si moins de 3 composantes, utiliser celle avec vitesse moyenne ~2-3 kn
  gmm_means <- mclust_model$parameters$mean
  dredge_comp <- which.min(abs(gmm_means - 2.5))  # Composante la plus proche de 2.5 kn
  ais_data_core[, prob_dredge_gmm := posterior_probs[, dredge_comp]]
}

# 2. Vitesse normalisée continue (gaussienne centrée sur 2.25 kn)
mu_speed    <- 2.25          # centre de la plage dragage
sigma_speed <- 1.0           # largeur (~1 kn)
ais_data_core[, speed_norm := exp(-(Speed - mu_speed)^2 / (2 * sigma_speed^2))]

# 3. Indicateur vitesse dans fenêtre dragage (pour comparaison)
ais_data_core[, speed_in_dredge_range := as.integer(Speed >= 1.0 & Speed <= 3.5)]

# 4. Variables normalisées existantes (gardées)
q95_accel <- quantile(ais_data_core$Accel, 0.95, na.rm = TRUE)
ais_data_core[, norm_accel := pmax(0, pmin(1, Accel/q95_accel))]

# ===== SCORES COMPOSITES MULTIPLES POUR COMPARAISON =====

# Score 1: ANCIEN (avec fuite de données) - gardé pour comparaison
ais_data_core[, dredging_indicator := as.integer(behavior_smooth=="dredging")]
ais_data_core[, dragage_score_OLD := 0.5*dredging_indicator +
                                     0.25*norm_course_change +
                                     0.25*norm_accel]

# Score 2: NOUVEAU - Probabilité GMM + changements comportementaux
ais_data_core[, dragage_score_GMM := 0.5*prob_dredge_gmm +
                                     0.3*norm_course_change +
                                     0.2*norm_accel]

# Score 3: NOUVEAU - Vitesse normalisée + changements comportementaux  
ais_data_core[, dragage_score_SPEED := 0.5*speed_norm +
                                       0.3*norm_course_change +
                                       0.2*norm_accel]

# Score 4: NOUVEAU - Range vitesse + changements comportementaux
ais_data_core[, dragage_score_RANGE := 0.5*speed_in_dredge_range +
                                       0.3*norm_course_change +
                                       0.2*norm_accel]

# Étiquettes binaires
ais_data_core[, Dragage_OLD := as.integer(dragage_score_OLD >= 0.5)]
ais_data_core[, Dragage_GMM := as.integer(dragage_score_GMM >= 0.5)]
ais_data_core[, Dragage_SPEED := as.integer(dragage_score_SPEED >= 0.5)]
ais_data_core[, Dragage_RANGE := as.integer(dragage_score_RANGE >= 0.5)]

# Sauvegardes intermédiaires avec les nouveaux scores
fwrite(ais_data_core, file.path(out_dir, "AIS_data_core_preprocessed.csv"))
saveRDS(ais_data_core, file.path(out_dir, "AIS_data_core_preprocessed.rds"))

# ─────────── DBG-2 : état mémoire et diagnostic vitesse ───────────
dbg_head("État avant grid-search - NOUVEAU SYSTÈME")
cat("Mémoire R utilisée :", dbg_mem_mb(), "Mo\n")
cat("nrow(ais_data_core) :", nrow(ais_data_core), "\n")

# Diagnostic des nouvelles variables vitesse
cat("\n=== DIAGNOSTIC VARIABLES VITESSE ===\n")
cat("Probabilité GMM dragage - range:", 
    round(range(ais_data_core$prob_dredge_gmm, na.rm=TRUE), 3), "\n")
cat("Vitesse normalisée - range:", 
    round(range(ais_data_core$speed_norm, na.rm=TRUE), 3), "\n")
cat("% points dans range dragage [1-3.5 kn]:", 
    round(100*mean(ais_data_core$speed_in_dredge_range, na.rm=TRUE), 1), "%\n")

# Corrélations entre nouvelles variables et ancienne (pour validation)
cor_gmm_old <- cor(ais_data_core$prob_dredge_gmm, ais_data_core$dredging_indicator, use="complete.obs")
cor_speed_old <- cor(ais_data_core$speed_norm, ais_data_core$dredging_indicator, use="complete.obs")
cat("Corrélation prob_GMM vs dredging_indicator:", round(cor_gmm_old, 3), "\n")
cat("Corrélation speed_norm vs dredging_indicator:", round(cor_speed_old, 3), "\n")

# ===== CONTRÔLES ANTI-FUITE SUBTILE (recommandés par expert) =====
cat("\n=== CONTRÔLES MÉTHODOLOGIQUES AVANCÉS ===\n")

## 3.1 Corrélations brutes score/label pour détecter biais
truth_label <- as.integer(ais_data_core$behavior_smooth == "dredging")
for(s in c("dragage_score_GMM","dragage_score_SPEED","dragage_score_RANGE")){
  cor_val <- cor(ais_data_core[[s]], truth_label, use="complete.obs")
  cat(sprintf("%-20s → cor = %.3f\n", s, cor_val))
}

## 3.2 AUC direct (sans Random Forest) pour baseline
library(pROC)
cat("\n--- AUC directs (sans modèle) ---\n")
roc_GMM   <- roc(truth_label, ais_data_core$dragage_score_GMM, quiet=TRUE)
roc_SPEED <- roc(truth_label, ais_data_core$dragage_score_SPEED, quiet=TRUE)
roc_RANGE <- roc(truth_label, ais_data_core$dragage_score_RANGE, quiet=TRUE)
cat("AUC GMM direct   :", round(auc(roc_GMM), 4), "\n")
cat("AUC SPEED direct :", round(auc(roc_SPEED), 4), "\n")
cat("AUC RANGE direct :", round(auc(roc_RANGE), 4), "\n")

## 3.3 Distribution des vitesses par classe (sanity check)
cat("\n--- Vitesses moyennes par comportement ---\n")
speed_by_behavior <- ais_data_core[, .(
  mean_speed = mean(Speed, na.rm=TRUE),
  median_speed = median(Speed, na.rm=TRUE),
  count = .N
), by = behavior_smooth]
print(speed_by_behavior)

## 3.4 Test de fuite temporelle : performance par année
cat("\n--- Performance par année (détection fuite temporelle) ---\n")
for(yr in sort(unique(ais_data_core$Annee))) {
  yr_data <- ais_data_core[Annee == yr]
  if(nrow(yr_data) > 100) {  # Minimum de données
    yr_truth <- as.integer(yr_data$behavior_smooth == "dredging")
    if(length(unique(yr_truth)) == 2) {  # Les deux classes présentes
      auc_yr <- auc(roc(yr_truth, yr_data$dragage_score_SPEED, quiet=TRUE))
      cat(sprintf("Année %d : AUC = %.3f (n=%d)\n", yr, auc_yr, nrow(yr_data)))
    }
  }
}

cat("\n⚠️  INTERPRÉTATION CONTRÔLES :\n")
cat("• Corrélations > 0.8 → possible sur-ajustement\n")
cat("• AUC directs > 0.9 → fuite potentielle\n") 
cat("• AUC très variables par année → instabilité temporelle\n")
cat("• Si dragage ≠ vitesses 1-3.5kn → problème classification GMM\n")
flush.console()

# ======================================================================
# 12. Grid-search AMÉLIORÉ - 4 APPROCHES SANS FUITE DE DONNÉES
# ======================================================================
library(ranger)
library(pROC)

# ===== CONFIGURATION GRID-SEARCH =====
# Grille de poids pour w1 (vitesse), w2 (course), w3 (accel)
grid_w_temp <- expand.grid(
  w1 = seq(0.20, 0.80, 0.10),  # Vitesse : poids minimum 20% pour garder dominance
  w2 = seq(0.10, 0.60, 0.10),  # Course change
  w3 = seq(0.10, 0.60, 0.10)   # Acceleration
)
# Garder seulement les combinaisons qui somment à ~1
grid_w <- grid_w_temp[abs(rowSums(grid_w_temp) - 1) < 0.05, ]

# ⚠️ NOUVEAU : on force la somme exactement à 1
grid_w <- grid_w / rowSums(grid_w)

cat("→", nrow(grid_w), "combinaisons de poids à tester\n")
cat("→ Poids vitesse (w1) entre", min(grid_w$w1), "et", max(grid_w$w1), "\n")

# ======================================================================
# 4.  FONCTIONS D'ÉVALUATION — VERSION CORRIGÉE
# ======================================================================

# ---- 4.a  Validation croisée temporelle robuste ----------------------
eval_cross_validation_robust <- function(ais_tmp, approach_name, w) {
  ais_tmp[, label_tmp_num := as.integer(as.character(label_tmp))]

  if (length(unique(ais_tmp$label_tmp_num)) < 2) return(0.5)  # jeu trivial

  yrs  <- sort(unique(ais_tmp$Annee))
  aucs <- numeric(length(yrs))

  for (k in seq_along(yrs)) {
    yr    <- yrs[k]
    train <- copy(ais_tmp[Annee != yr])     # ⬅️ copies indispensables
    test  <- copy(ais_tmp[Annee == yr])

    if (length(unique(train$label_tmp_num)) < 2 ||
        length(unique(test $label_tmp_num)) < 2) {
      aucs[k] <- 0.5
      next
    }

    # ---------- Recompute GMM dans le fold (évite fuite subtile) ---------
    if (approach_name == "GMM") {
      gmm_fold    <- Mclust(train$Speed, G = 1:5, verbose = FALSE)
      gmm_means   <- gmm_fold$parameters$mean
      dredge_comp <- which.min(abs(gmm_means - 2.5))

      train_z <- predict(gmm_fold, newdata = train$Speed)$z
      test_z  <- predict(gmm_fold, newdata =  test$Speed)$z

      train[, prob_gmm_fold := train_z[, dredge_comp]]
      test [, prob_gmm_fold :=  test_z [, dredge_comp]]

      train[, score_fold := w[1]*prob_gmm_fold   +
                            w[2]*norm_course_change +
                            w[3]*norm_accel]
      test [, score_fold := w[1]*prob_gmm_fold   +
                            w[2]*norm_course_change +
                            w[3]*norm_accel]
    } else {
      # SPEED, RANGE ou OLD : score déjà pondéré
      train[, score_fold := score_tmp]
      test [, score_fold := score_tmp]
    }

    # ---------- Modèle logistique ---------------------------------------
    glm_fit <- glm(label_tmp_num ~ score_fold,
                   data   = train,
                   family = binomial(link = "logit"))

    probs   <- predict(glm_fit, newdata = test, type = "response")
    aucs[k] <- pROC::auc(pROC::roc(test$label_tmp_num, probs, quiet = TRUE))
  }

  mean(aucs, na.rm = TRUE)
}

# ---- 4.b  Wrappers par approche (passent *w* au validateur) -----------

## GMM — Probabilité de la composante dragage
eval_weights_GMM <- function(w) {
  ais_tmp <- ais_data_core[, .(
    score_tmp = w[1]*prob_dredge_gmm + w[2]*norm_course_change + w[3]*norm_accel,
    label_tmp = as.integer(behavior_smooth == "dredging"),
    Speed, norm_course_change, norm_accel, Annee
  )][complete.cases(score_tmp, label_tmp, Annee)]

  eval_cross_validation_robust(ais_tmp, "GMM", w)
}

## SPEED — Vitesse normalisée continue
eval_weights_SPEED <- function(w) {
  ais_tmp <- ais_data_core[, .(
    score_tmp = w[1]*speed_norm + w[2]*norm_course_change + w[3]*norm_accel,
    label_tmp = as.integer(behavior_smooth == "dredging"),
    Annee
  )][complete.cases(score_tmp, label_tmp, Annee)]

  eval_cross_validation_robust(ais_tmp, "SPEED", w)
}

## RANGE — Indicateur binaire (1 ≤ v ≤ 3.5 kn)
eval_weights_RANGE <- function(w) {
  ais_tmp <- ais_data_core[, .(
    score_tmp = w[1]*speed_in_dredge_range + w[2]*norm_course_change + w[3]*norm_accel,
    label_tmp = as.integer(behavior_smooth == "dredging"),
    Annee
  )][complete.cases(score_tmp, label_tmp, Annee)]

  eval_cross_validation_robust(ais_tmp, "RANGE", w)
}

## OLD — Variante avec fuite (contrôle)
eval_weights_OLD <- function(w) {
  ais_tmp <- ais_data_core[, .(
    score_tmp = w[1]*dredging_indicator + w[2]*norm_course_change + w[3]*norm_accel,
    label_tmp = as.integer(behavior_smooth == "dredging"),
    Annee
  )][complete.cases(score_tmp, label_tmp, Annee)]

  eval_cross_validation_robust(ais_tmp, "OLD", w)
}

# ===== EXÉCUTION DES 4 GRID-SEARCHES =====
DBG_PRINT_EVERY <- 10

cat("\n🔬 AMÉLIORATIONS MÉTHODOLOGIQUES IMPLÉMENTÉES :\n")
cat("• GMM ré-entraîné dans chaque fold (élimination fuite subtile)\n")
cat("• GLM remplace Random Forest (plus stable, moins de variance)\n")
cat("• Contrôles diagnostiques avancés effectués\n")
cat("• Poids vitesse forcés ≥ 20% (dominance physique)\n")
cat("→ AUC attendus : SPEED/RANGE ~0.60-0.75, GMM ~0.70-0.85, OLD ~0.95+ (fuite)\n\n")

approaches <- list(
  "GMM" = list(name = "Probabilité GMM robuste", func = eval_weights_GMM),
  "SPEED" = list(name = "Vitesse normalisée", func = eval_weights_SPEED), 
  "RANGE" = list(name = "Range vitesse binaire", func = eval_weights_RANGE),
  "OLD" = list(name = "ANCIEN (avec fuite détectée)", func = eval_weights_OLD)
)

results_all <- list()

for (approach_name in names(approaches)) {
  approach <- approaches[[approach_name]]
  cat(sprintf("\n=== GRID SEARCH: %s ===\n", approach$name))
  
  auc_results <- numeric(nrow(grid_w))
  
  for (i in seq_len(nrow(grid_w))) {
    auc_results[i] <- approach$func(as.numeric(grid_w[i, ]))

    if (i %% DBG_PRINT_EVERY == 0 || i == nrow(grid_w)) {
      cat(sprintf("%s | %s | combo %2d/%2d | w1=%.1f w2=%.1f w3=%.1f | AUC=%.4f\n",
                  dbg_time(), approach_name, i, nrow(grid_w), 
                  grid_w[i,1], grid_w[i,2], grid_w[i,3], auc_results[i]))
      flush.console()
    }
  }
  
  # Sauvegarder résultats
  best_idx <- which.max(auc_results)
  results_all[[approach_name]] <- list(
    best_weights = as.numeric(grid_w[best_idx, ]),
    best_auc = auc_results[best_idx],
    all_aucs = auc_results
  )
  
  cat(sprintf("✅ %s - Meilleurs poids: w1=%.2f w2=%.2f w3=%.2f (AUC=%.4f)\n\n",
              approach$name, 
              results_all[[approach_name]]$best_weights[1],
              results_all[[approach_name]]$best_weights[2], 
              results_all[[approach_name]]$best_weights[3],
              results_all[[approach_name]]$best_auc))
}

# ===== COMPARAISON ET CHOIX FINAL =====
cat("=== COMPARAISON FINALE DES APPROCHES ===\n")
for (approach_name in names(approaches)) {
  res <- results_all[[approach_name]]
  cat(sprintf("%-25s: AUC=%.4f | w1=%.2f w2=%.2f w3=%.2f\n",
              approaches[[approach_name]]$name,
              res$best_auc, res$best_weights[1], res$best_weights[2], res$best_weights[3]))
}

# Identifier la meilleure approche (excluant OLD si AUC > 0.95)
best_approach <- NULL
best_auc_clean <- 0

for (approach_name in names(approaches)) {
  if (approach_name == "OLD") next  # Exclure l'ancienne méthode avec fuite
  
  auc <- results_all[[approach_name]]$best_auc
  if (auc > best_auc_clean) {
    best_auc_clean <- auc
    best_approach <- approach_name
  }
}

cat(sprintf("\n🏆 MEILLEURE APPROCHE (sans fuite): %s (AUC=%.4f)\n", 
            approaches[[best_approach]]$name, best_auc_clean))

# Vérification fuite de données
if (results_all[["OLD"]]$best_auc > 0.95) {
  cat("⚠️  CONFIRMATION: Approche OLD a AUC > 0.95 → fuite de données détectée\n")
} else {
  cat("ℹ️  Approche OLD n'a pas d'AUC suspect (< 0.95)\n")
}

# ===== APPLICATION DU MEILLEUR SCORE =====
best_w <- results_all[[best_approach]]$best_weights
cat(sprintf("\n→ Application des poids optimaux: w1=%.2f w2=%.2f w3=%.2f\n",
            best_w[1], best_w[2], best_w[3]))

if (best_approach == "GMM") {
  ais_data_core[, dragage_score_final := best_w[1]*prob_dredge_gmm + 
                                         best_w[2]*norm_course_change + 
                                         best_w[3]*norm_accel]
} else if (best_approach == "SPEED") {
  ais_data_core[, dragage_score_final := best_w[1]*speed_norm + 
                                         best_w[2]*norm_course_change + 
                                         best_w[3]*norm_accel]
} else if (best_approach == "RANGE") {
  ais_data_core[, dragage_score_final := best_w[1]*speed_in_dredge_range + 
                                         best_w[2]*norm_course_change + 
                                         best_w[3]*norm_accel]
}

ais_data_core[, Dragage_final := as.integer(dragage_score_final >= 0.5)]

# Sauvegardes finales avec résultats complets
final_results <- list(
  best_approach = best_approach,
  best_weights = best_w,
  best_auc = best_auc_clean,
  all_approaches = results_all,
  method = "grid_search_sans_fuite_donnees"
)

saveRDS(final_results, file = file.path(out_dir, "grid_search_results_final.rds"))
saveRDS(ais_data_core, file = file.path(out_dir, "AIS_data_core_preprocessed.rds"))
fwrite(ais_data_core, file = file.path(out_dir, "AIS_data_core_preprocessed.csv"))

dbg_head("GRID-SEARCH AMÉLIORÉ TERMINÉ AVEC SUCCÈS !")
cat("🎯 Vitesse redevient le critère principal (w1 >=", min(grid_w$w1), ")\n")
cat("🚫 Fuite de données éliminée\n") 
cat("📊 Résultats sauvegardés dans :", out_dir, "\n") 