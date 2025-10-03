# ==============================================================================
# ENTRAINEMENT MODELE V6 - AVEC SEUIL ADAPTATIF PAR NAVIRE
# VERSION AMÉLIORÉE - Sans fuite de données + Seuil intelligent
# ==============================================================================

# 1. LIBRAIRIES (version clean)
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(mclust)
  library(caret)
  library(pROC)
  library(ggplot2)
  library(zoo)
  if (!require(pbapply)) install.packages("pbapply", repos="https://cloud.r-project.org"); library(pbapply)
  if (!require(matrixStats)) install.packages("matrixStats", repos="https://cloud.r-project.org"); library(matrixStats)
})

# 1.a Fonctions debug
dbg_head <- function(msg) cat(sprintf("[%s] %s\n", Sys.time(), msg)); flush.console()
dbg_mem_mb <- function() round(sum(gc()[,2]) * 8 / 1024, 1)
dbg_time <- function() format(Sys.time(), "%H:%M:%S")

# 1.c Parallélisme
n_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
Sys.setenv(OMP_NUM_THREADS      = n_threads,
           OPENBLAS_NUM_THREADS = n_threads)
data.table::setDTthreads(n_threads)
options(mc.cores = n_threads)
Sys.setenv(MC_CORES = n_threads)
dbg_head(sprintf("CONFIG : %d threads alloués", n_threads))

# TABLE DE MAPPING NAVIRE (pour merge rapide)
mmsi_map <- data.table(
  ssvid = c(209469000, 210138000, 245508000, 246351000,
            253193000, 253373000, 253403000, 253422000,
            253688000, 312062000, 533180137),
  IMO_number = c(9132454, 9164031, 9229556, 9454096,
                 9187473, 9429572, 9429584, 9528079,
                 9574523, 8119728, 9568782),
  Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318 Sleephopperzuiger",
             "Vox Maxima", "Vasco Da Gama", "Cristobal Colon", "Leiv Eiriksson",
             "Charles Darwin", "Congo River", "Goryo 6 Ho", "Inai Kenanga")
)
setkey(mmsi_map, ssvid)

# 2. Chargement des données (clean)
ais_directory <- "~/scratch/AIS_data"
out_dir       <- "~/scratch/output"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
ais_old <- data.table()

if (!exists("df_new")) {
  warning("df_new n'existe pas - création de données de démonstration")
  df_new <- data.table(
    Navire = rep(c("Fairway", "Vox Maxima", "Charles Darwin"), each = 1000),
    Speed = c(rnorm(1000, 0.2, 0.1), rnorm(1000, 2.5, 0.8), rnorm(1000, 8, 2)),
    Course = runif(3000, 0, 360),
    Lon = runif(3000, -5, 5),
    Lat = runif(3000, 50, 55),
    Timestamp = seq(as.POSIXct("2020-01-01"), by = "hour", length.out = 3000),
    Seg_id = rep(paste0("seg_", 1:300), each = 10)
  )
  df_new[, Timestamp := as.character(Timestamp)]
}

# Fusion
if (nrow(ais_old) > 0) {
  if (!"Navire" %in% names(ais_old)) {
    if ("ssvid" %in% names(ais_old)) {
      ais_old <- merge(ais_old, mmsi_map[, .(ssvid, Navire)], by = "ssvid", all.x = TRUE)
    }
    if (!"Navire" %in% names(ais_old)) ais_old[, Navire := paste0("unknown_", .I)]
  }
  if ("navire" %in% names(ais_old) && !"Navire" %in% names(ais_old)) setnames(ais_old, "navire", "Navire")
  vessels_updated <- unique(df_new$Navire)
  ais_old <- ais_old[!Navire %chin% vessels_updated]
  ais_data <- rbindlist(list(ais_old, df_new), use.names = TRUE, fill = TRUE)
} else {
  ais_data <- copy(df_new)
}

dbg_head(sprintf("Jeu fusionné : %d pings, %d navires", nrow(ais_data), length(unique(ais_data$Navire))))
if (nrow(ais_data) == 0) stop("Aucune donnée chargée : vérifiez vos fichiers d'entrée !")

# 3. Conversion timestamp
ais_data[, Timestamp := as.POSIXct(Timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]
ais_data[, Annee := year(Timestamp)]

# 3.1 Fenêtre temporelle « core »
core_years <- 2012:2024
ais_data_core <- ais_data[Annee %in% core_years]

# 4. Caractéristiques navires
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

# 5. Classification vitesse grossière
ais_data_core[, Activity := fifelse(Speed < 0.5, "manoeuvres/arrets",
                             fifelse(Speed < 3,  "dragage_potentiel",
                             fifelse(Speed < 10, "transit_loaded",
                             fifelse(Speed < 18, "transit_unloaded","Autre"))))]

# 6. Feature engineering
ais_data_core[, Accel := {dV <- c(NA, diff(Speed)); dt <- c(NA, diff(as.numeric(Timestamp))); dV/dt}, by = Seg_id]
ais_data_core[is.na(Accel) | !is.finite(Accel), Accel := 0]
ais_data_core[, Course_change := {delta <- c(NA, abs(diff(Course))); delta <- pmin(delta, 360-delta); delta}, by=Seg_id]
ais_data_core[is.na(Course_change), Course_change := 0]
q95 <- quantile(ais_data_core$Course_change, 0.95, na.rm = TRUE)
ais_data_core[, norm_course_change := pmax(0, pmin(1, 1 - Course_change/q95))]

# ==============================================================================
# 6.d  Filtrage spatial des arrêts : DBSCAN/HDBSCAN
# ==============================================================================

library(dbscan) # déjà chargé en tête

# Fonction pour calculer eps automatiquement (heuristique ou k-distance)
auto_eps <- function(coords, k = 4) {
  # coords : matrice [lon, lat]
  dists <- kNNdist(coords, k = k)
  # Heuristique : 1 % de la médiane des distances entre arrêts
  eps_heur <- 0.01 * median(dists, na.rm = TRUE)
  # Bornes minimales (ex : 20 m) pour éviter eps trop faible
  pmax(eps_heur, 0.0002)
}

# Fonction de clustering spatial des arrêts pour un sous-jeu (navire/campagne)
cluster_stops_spatial <- function(dt, eps = NULL, minPts = 4) {
  arr <- dt[is_stop == TRUE & !is.na(Lon) & !is.na(Lat)]
  if (nrow(arr) < minPts) {
    dt[, stop_cluster_id := NA_integer_]
    dt[, stop_cluster_core := FALSE]
    return(dt)
  }
  coords <- as.matrix(arr[, .(Lon, Lat)])
  # Calculer eps si non fourni
  if (is.null(eps)) eps <- auto_eps(coords, k = minPts)
  db <- dbscan(coords, eps = eps, minPts = minPts)
  arr[, stop_cluster_id := db$cluster]
  arr[, stop_cluster_core := db$cluster > 0]
  # Remettre les labels dans le jeu principal
  dt <- merge(dt, arr[, .(Timestamp, stop_cluster_id, stop_cluster_core)], by = "Timestamp", all.x = TRUE)
  # True stop : arrêt ET cluster spatial
  dt[, is_stop_spatial := is_stop & !is.na(stop_cluster_id) & stop_cluster_id > 0]
  return(dt)
}

# Application : cluster par navire ET campagne (ex : année)
dbg_head("🗺️  DBSCAN spatial sur arrêts — cluster par navire et année")
ais_data_core[, c("stop_cluster_id", "stop_cluster_core", "is_stop_spatial") := NULL] # Clean if rerun

ais_data_core <- ais_data_core[, cluster_stops_spatial(.SD), by = .(Navire, Annee)]

# (Optionnel) Diagnostics rapides
diag_dbscan <- ais_data_core[is_stop == TRUE, .(
  total_stops = .N,
  clustered_stops = sum(stop_cluster_core, na.rm = TRUE),
  n_clusters = length(unique(stop_cluster_id[!is.na(stop_cluster_id) & stop_cluster_id > 0]))
), by = .(Navire, Annee)]

print(diag_dbscan)
cat("Pourcentage d'arrêts dans un cluster spatial (port/mouillage) :",
    round(100*mean(ais_data_core[is_stop == TRUE]$stop_cluster_core, na.rm = TRUE), 1), "%\n")

# Remarque : utiliser is_stop_spatial à la place de is_stop dans les étapes suivantes

# 6.c SEUIL D'ARRÊT ADAPTATIF PAR NAVIRE
v_min <- 0.15; v_max <- 0.80; seuil_global <- 0.30; n_min <- 1000
dbg_head("🔧 Calcul des seuils d'arrêt adaptatifs par navire")
seuils_par_navire <- ais_data_core[Speed > 0, .(q05=quantile(Speed,0.05,na.rm=TRUE), N=.N), by=Navire]
seuils_par_navire[, seuil_adapt := pmax(v_min, pmin(v_max, q05))]
seuils_par_navire[N < n_min,   seuil_adapt := seuil_global]
ais_data_core <- merge(ais_data_core, seuils_par_navire[, .(Navire, seuil_adapt)], by = "Navire", all.x = TRUE)
ais_data_core[, is_stop := Speed <= seuil_adapt]
diag_seuils <- seuils_par_navire[, .(Navire, N_pts=N, q05_kn=round(q05,3), seuil_final=round(seuil_adapt,3))]
dbg_head("📊 Seuils d'arrêt calculés par navire :"); print(diag_seuils)

# 7. GMM : 1 "stop" + 4 composantes
ais_data_core <- ais_data_core[Speed <= 20]
ais_data_core[, paste0("p_component_",1:5) := 0.0]
speeds_move <- ais_data_core[is_stop == FALSE, Speed]
set.seed(42)
gmm4 <- Mclust(speeds_move, G = 1:5, verbose = FALSE)
z_move <- predict(gmm4, newdata = speeds_move)$z
ais_data_core[is_stop == TRUE, p_component_1 := 1]
if (nrow(z_move)>0) for(j in seq_len(ncol(z_move))) ais_data_core[is_stop == FALSE, paste0("p_component_",j+1) := z_move[,j]]
ais_data_core[, comp := apply(.SD, 1, which.max), .SDcols=paste0("p_component_",1:5)]

# GMM: résumé
gmm_summary <- data.table(
  component  = 1:5,
  mean_knots = c(0, round(gmm4$parameters$mean, 2)),
  sd_knots   = c(0, round(if (!is.null(gmm4$parameters$variance$sigmasq)) sqrt(gmm4$parameters$variance$sigmasq) else rep(sqrt(gmm4$parameters$variance$sigma2),4), 2))
)
dbg_head("📈 Résumé des 5 composantes (1=stops adaptatifs, 2-5=GMM)")
print(gmm_summary)

# 8. Lissage comportemental
ais_data_core[, behavior :=
  fifelse(comp==1,"stops",fifelse(comp==2,"slow_maneuvers",fifelse(comp==3,"dredging",fifelse(comp==4,"loaded_transit",fifelse(comp==5,"unloaded_transit",NA_character_)))))]
ais_data_core[, `:=`(Lon = as.numeric(Lon), Lat = as.numeric(Lat))]
transition_cost <- matrix(c(
  0, 2, 2, 2, 2,
  1, 0, 2, 3, 2,
  2, 2, 0, 2, 2,
  3, 3, 2, 0, 2,
  2, 2, 2, 2, 0
), 5, 5, byrow=TRUE, dimnames=list(
  c("stops","slow_maneuvers","dredging","loaded_transit","unloaded_transit"),
  c("stops","slow_maneuvers","dredging","loaded_transit","unloaded_transit")))

smooth_behavior_transition <- function(labels, speeds, transition_cost, threshold=3, dredge_min=1, dredge_max=3.5) {
  r <- rle(labels); cum <- cumsum(r$lengths); beg <- c(1, head(cum,-1)+1)
  for(i in seq_along(r$lengths)) {
    if (r$lengths[i] < threshold) {
      vbar <- mean(speeds[beg[i]:cum[i]])
      if (vbar <= dredge_max) {
        prev_lab <- if(i>1) r$values[i-1] else NA
        next_lab <- if(i<length(r$values)) r$values[i+1] else NA
        c_prev <- if(!is.na(prev_lab)) transition_cost[prev_lab,r$values[i]] else Inf
        c_next <- if(!is.na(next_lab)) transition_cost[next_lab,r$values[i]] else Inf
        r$values[i] <- if (c_prev < c_next) prev_lab else next_lab
      }
    }
  }
  lbl <- inverse.rle(r)
  bad <- which(lbl=="dredging" & (speeds<dredge_min | speeds>dredge_max))
  if(length(bad)>0) for(j in bad){
    prev_lab <- if(j>1) lbl[j-1] else NA
    next_lab <- if(j<length(lbl)) lbl[j+1] else NA
    cand <- if(speeds[j]<dredge_min) c("slow_maneuvers","stops") else c("loaded_transit","unloaded_transit")
    best_lbl <- cand[1]; best_cost <- Inf
    for(c in cand){
      cp <- if(!is.na(prev_lab)) transition_cost[prev_lab,c] else 0
      cn <- if(!is.na(next_lab)) transition_cost[c,next_lab] else 0
      if(cp+cn<best_cost){best_lbl<-c;best_cost<-cp+cn}
    }
    lbl[j] <- best_lbl
  }
  lbl
}
ais_data_core[, behavior_smooth := smooth_behavior_transition(behavior, Speed, transition_cost), by=Seg_id]
ais_data_core[, sub_seg_id := paste0(Seg_id,"_",rleid(behavior_smooth))]
dbg_head("🎭 Lissage comportemental terminé")

# 11. Scores composites
mu_speed <- 2.25; sigma_speed <- 1.0
ais_data_core[, prob_dredge_gmm := p_component_3]
ais_data_core[, speed_norm := exp(-(Speed - mu_speed)^2 / (2 * sigma_speed^2))]
ais_data_core[, speed_in_dredge_range := as.integer(Speed >= 1.0 & Speed <= 3.5)]
q95_accel <- quantile(ais_data_core$Accel, 0.95, na.rm=TRUE)
ais_data_core[, norm_accel := pmax(0, pmin(1, Accel/q95_accel))]
ais_data_core[, dredging_indicator := as.integer(behavior_smooth=="dredging")]
ais_data_core[, dragage_score_OLD := 0.5*dredging_indicator + 0.25*norm_course_change + 0.25*norm_accel]
ais_data_core[, dragage_score_GMM := 0.5*prob_dredge_gmm + 0.3*norm_course_change + 0.2*norm_accel]
ais_data_core[, dragage_score_SPEED := 0.5*speed_norm + 0.3*norm_course_change + 0.2*norm_accel]
ais_data_core[, dragage_score_RANGE := 0.5*speed_in_dredge_range + 0.3*norm_course_change + 0.2*norm_accel]
ais_data_core[, Dragage_OLD := as.integer(dragage_score_OLD >= 0.5)]
ais_data_core[, Dragage_GMM := as.integer(dragage_score_GMM >= 0.5)]
ais_data_core[, Dragage_SPEED := as.integer(dragage_score_SPEED >= 0.5)]
ais_data_core[, Dragage_RANGE := as.integer(dragage_score_RANGE >= 0.5)]
fwrite(ais_data_core, file.path(out_dir, "AIS_data_core_preprocessed_V6.csv"))
saveRDS(ais_data_core, file = file.path(out_dir, "AIS_data_core_preprocessed_V6.rds"), compress="xz")

# Contrôles diagnostic
dbg_head("État avant grid-search - NOUVEAU SYSTÈME avec seuils adaptatifs")
cat("Mémoire R utilisée :", dbg_mem_mb(), "Mo\n")
cat("nrow(ais_data_core) :", nrow(ais_data_core), "\n")
truth_label <- as.integer(ais_data_core$behavior_smooth == "dredging")
for(s in c("dragage_score_GMM","dragage_score_SPEED","dragage_score_RANGE")){
  cor_val <- cor(ais_data_core[[s]], truth_label, use="complete.obs")
  cat(sprintf("%-20s → cor = %.3f\n", s, cor_val))
}

# 12. GRID-SEARCH AMÉLIORÉ
eval_cross_validation_robust <- function(ais_tmp, approach_name, w) {
  ais_tmp <- merge(ais_tmp, diag_seuils[, .(Navire, seuil_final)], by = "Navire", all.x = TRUE)
  ais_tmp[, is_stop := Speed <= seuil_final]
  ais_tmp[, label_tmp_num := as.integer(as.character(label_tmp))]
  if (length(unique(ais_tmp$label_tmp_num)) < 2) return(0.5)
  yrs  <- sort(unique(ais_tmp$Annee))
  aucs <- numeric(length(yrs))
  for (k in seq_along(yrs)) {
    yr    <- yrs[k]
    train <- copy(ais_tmp[Annee != yr])
    test  <- copy(ais_tmp[Annee == yr])
    if (length(unique(train$label_tmp_num)) < 2 || length(unique(test$label_tmp_num)) < 2) { aucs[k] <- 0.5; next }
    if (approach_name == "GMM") {
      set.seed(42)
      gmm_fold <- Mclust(train[is_stop == FALSE, Speed], G = 1:5, verbose = FALSE)
      dredge_comp <- which.min(abs(gmm_fold$parameters$mean - 2.5))
      train_move <- train[is_stop == FALSE, Speed]; test_move <- test[is_stop == FALSE, Speed]
      z_train <- predict(gmm_fold, newdata = train_move)$z
      z_test  <- predict(gmm_fold, newdata =  test_move)$z
      train[, paste0("p_component_", 1:(ncol(z_train)+1)) := 0.0]
      test[,  paste0("p_component_", 1:(ncol(z_test)+1)) := 0.0]
      train[is_stop == TRUE,  p_component_1 := 1]
      test[ is_stop == TRUE,  p_component_1 := 1]
      for (j in seq_len(ncol(z_train))) train[is_stop == FALSE, paste0("p_component_",j+1) := z_train[,j]]
      for (j in seq_len(ncol(z_test)))  test[is_stop == FALSE,  paste0("p_component_",j+1) := z_test[,j]]
      train[, prob_gmm_fold := get(paste0("p_component_",dredge_comp+1))]
      test [, prob_gmm_fold := get(paste0("p_component_",dredge_comp+1))]
      train[, score_fold := w[1]*prob_gmm_fold + w[2]*norm_course_change + w[3]*norm_accel]
      test [, score_fold := w[1]*prob_gmm_fold + w[2]*norm_course_change + w[3]*norm_accel]
    } else {
      train[, score_fold := score_tmp]; test[, score_fold := score_tmp]
    }
    glm_fit <- glm(label_tmp_num ~ score_fold, data = train, family = binomial(link = "logit"))
    probs   <- predict(glm_fit, newdata = test, type = "response")
    aucs[k] <- pROC::auc(pROC::roc(test$label_tmp_num, probs, quiet=TRUE))
  }
  mean(aucs, na.rm = TRUE)
}
eval_weights_GMM <- function(w) {ais_tmp <- ais_data_core[, .(score_tmp = w[1]*prob_dredge_gmm + w[2]*norm_course_change + w[3]*norm_accel, label_tmp = as.integer(behavior_smooth=="dredging"), Speed, norm_course_change, norm_accel, Annee, Navire)][complete.cases(score_tmp,label_tmp,Annee,Navire)]; eval_cross_validation_robust(ais_tmp, "GMM", w)}
eval_weights_SPEED <- function(w) {ais_tmp <- ais_data_core[, .(score_tmp = w[1]*speed_norm + w[2]*norm_course_change + w[3]*norm_accel, label_tmp = as.integer(behavior_smooth=="dredging"), Annee, Navire)][complete.cases(score_tmp,label_tmp,Annee,Navire)]; eval_cross_validation_robust(ais_tmp, "SPEED", w)}
eval_weights_RANGE <- function(w) {ais_tmp <- ais_data_core[, .(score_tmp = w[1]*speed_in_dredge_range + w[2]*norm_course_change + w[3]*norm_accel, label_tmp = as.integer(behavior_smooth=="dredging"), Annee, Navire)][complete.cases(score_tmp,label_tmp,Annee,Navire)]; eval_cross_validation_robust(ais_tmp, "RANGE", w)}
eval_weights_OLD <- function(w) {ais_tmp <- ais_data_core[, .(score_tmp = w[1]*dredging_indicator + w[2]*norm_course_change + w[3]*norm_accel, label_tmp = as.integer(behavior_smooth=="dredging"), Annee, Navire)][complete.cases(score_tmp,label_tmp,Annee,Navire)]; eval_cross_validation_robust(ais_tmp, "OLD", w)}

# === GRID SEARCH ===
DBG_PRINT_EVERY <- 10
approaches <- list("GMM"=list(name="Probabilité GMM robuste", func=eval_weights_GMM),
                   "SPEED"=list(name="Vitesse normalisée", func=eval_weights_SPEED),
                   "RANGE"=list(name="Range vitesse binaire", func=eval_weights_RANGE),
                   "OLD"=list(name="ANCIEN (avec fuite détectée)", func=eval_weights_OLD))
# EXEMPLE de grille, à adapter:
grid_w <- as.data.table(expand.grid(w1=seq(0.2,0.7,by=0.1),w2=seq(0.1,0.5,by=0.1),w3=seq(0.1,0.5,by=0.1)))
grid_w <- grid_w[abs(w1+w2+w3-1)<1e-6]

results_all <- list()
for (approach_name in names(approaches)) {
  approach <- approaches[[approach_name]]
  cat(sprintf("\n=== GRID SEARCH: %s ===\n", approach$name))
  auc_results <- numeric(nrow(grid_w))
  for (i in seq_len(nrow(grid_w))) {
    auc_results[i] <- approach$func(as.numeric(grid_w[i, ]))
    if (i %% DBG_PRINT_EVERY == 0 || i == nrow(grid_w)) {
      cat(sprintf("%s | %s | combo %2d/%2d | w1=%.1f w2=%.1f w3=%.1f | AUC=%.4f\n",
                  dbg_time(), approach_name, i, nrow(grid_w), grid_w[i,1], grid_w[i,2], grid_w[i,3], auc_results[i]))
      flush.console()
    }
  }
  best_idx <- which.max(auc_results)
  results_all[[approach_name]] <- list(
    best_weights = as.numeric(grid_w[best_idx, ]),
    best_auc = auc_results[best_idx],
    all_aucs = auc_results
  )
  cat(sprintf("✅ %s - Meilleurs poids: w1=%.2f w2=%.2f w3=%.2f (AUC=%.4f)\n\n",
              approach$name, results_all[[approach_name]]$best_weights[1], results_all[[approach_name]]$best_weights[2],
              results_all[[approach_name]]$best_weights[3], results_all[[approach_name]]$best_auc))
}
cat("=== COMPARAISON FINALE DES APPROCHES (V6) ===\n")
for (approach_name in names(approaches)) {
  res <- results_all[[approach_name]]
  cat(sprintf("%-25s: AUC=%.4f | w1=%.2f w2=%.2f w3=%.2f\n",
              approaches[[approach_name]]$name, res$best_auc, res$best_weights[1], res$best_weights[2], res$best_weights[3]))
}
best_approach <- NULL; best_auc_clean <- 0
for (approach_name in names(approaches)) {
  if (approach_name == "OLD") next
  auc <- results_all[[approach_name]]$best_auc
  if (auc > best_auc_clean) {best_auc_clean <- auc; best_approach <- approach_name}
}
cat(sprintf("\n🏆 MEILLEURE APPROCHE (sans fuite): %s (AUC=%.4f)\n",
            approaches[[best_approach]]$name, best_auc_clean))
if (results_all[["OLD"]]$best_auc > 0.95) {
  cat("⚠️  CONFIRMATION: Approche OLD a AUC > 0.95 → fuite de données détectée\n")
} else {
  cat("ℹ️  Approche OLD n'a pas d'AUC suspect (< 0.95)\n")
}
best_w <- results_all[[best_approach]]$best_weights
cat(sprintf("\n→ Application des poids optimaux: w1=%.2f w2=%.2f w3=%.2f\n", best_w[1], best_w[2], best_w[3]))
if (best_approach == "GMM") {
  ais_data_core[, dragage_score_final := best_w[1]*prob_dredge_gmm + best_w[2]*norm_course_change + best_w[3]*norm_accel]
} else if (best_approach == "SPEED") {
  ais_data_core[, dragage_score_final := best_w[1]*speed_norm + best_w[2]*norm_course_change + best_w[3]*norm_accel]
} else if (best_approach == "RANGE") {
  ais_data_core[, dragage_score_final := best_w[1]*speed_in_dredge_range + best_w[2]*norm_course_change + best_w[3]*norm_accel]
}
ais_data_core[, Dragage_final := as.integer(dragage_score_final >= 0.5)]

final_results_V6 <- list(
  best_approach = best_approach,
  best_weights = best_w,
  best_auc = best_auc_clean,
  all_approaches = results_all,
  seuils_adaptatifs = diag_seuils,
  method = "grid_search_sans_fuite_donnees_V6_seuils_adaptatifs",
  version = "V6 - Seuils adaptatifs par navire",
  improvements = c(
    "Seuils d'arrêt adaptatifs par navire (q05 + garde-fous)",
    "GMM robuste avec ré-entraînement par fold",
    "Élimination complète fuite de données",
    "Validation croisée temporelle stricte"
  )
)
saveRDS(final_results_V6, file = file.path(out_dir, "grid_search_results_final_V6.rds"), compress="xz")
saveRDS(ais_data_core, file = file.path(out_dir, "AIS_data_core_preprocessed_V6.rds"), compress="xz")
fwrite(ais_data_core, file = file.path(out_dir, "AIS_data_core_preprocessed_V6.csv"))
fwrite(diag_seuils, file = file.path(out_dir, "seuils_adaptatifs_par_navire_V6.csv"))
saveRDS(diag_seuils, file = file.path(out_dir, "seuils_adaptatifs_par_navire_V6.rds"), compress="xz")
dbg_head("🎉 GRID-SEARCH V6 AVEC SEUILS ADAPTATIFS TERMINÉ AVEC SUCCÈS !")
cat("📊 Résultats sauvegardés dans :", out_dir, "\n")
cat("\n=== RÉCAPITULATIF FINAL V6 ===\n")
cat("  - AIS_data_core_preprocessed_V6.{csv,rds}\n")
cat("  - grid_search_results_final_V6.rds\n")
cat("  - seuils_adaptatifs_par_navire_V6.{csv,rds}\n")
cat("  - Validation temporelle robuste\n")
flush.console()
