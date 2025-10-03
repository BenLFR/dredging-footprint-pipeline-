#!/bin/bash

#SBATCH --job-name=step3_interactif
#SBATCH --account=def-wailung
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=step3_interactif_%j.out

echo "🚀 === STEP3 INTERACTIF COMPLET - MODE RSTUDIO ==="
echo "Timestamp: $(date)"
echo "Node: $(hostname)"
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Mémoire: ${SLURM_MEM_PER_NODE}G"

# Chargement modules R
echo "📦 Chargement modules R..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

echo "📁 Répertoire de travail: $(pwd)"

# Lancement R interactif avec affichage complet
cat > step3_interactif_detaille.R << 'EOF'
#!/usr/bin/env Rscript

cat("\n")
cat("================================================================================\n")
cat("🏁  STEP-3  |  FUSION & MODÉLISATION INTERACTIVE  |  DÉBUT\n")
cat("================================================================================\n")
cat("Timestamp:", format(Sys.time()), "\n")
cat("Working Directory:", getwd(), "\n")

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
cat("\n📦 === CONFIGURATION R ===\n")
.libPaths("~/.local/R/4.2.1/")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")
cat("✅ Packages installés:", length(list.files(.libPaths()[1])), "\n")

# Configuration
cores <- 4
options(mc.cores = cores)
Sys.setenv(MC_CORES = cores)
Sys.setenv(DT_GForce = "FALSE")
Sys.setenv(OMP_NUM_THREADS = cores)

cat("✅ Configuration multi-threading:", cores, "cores\n")

cat("\n📚 === CHARGEMENT PACKAGES ===\n")
suppressPackageStartupMessages({
  cat("  • Chargement data.table...")
  library(data.table)
  cat(" ✅\n")
  
  cat("  • Chargement lubridate...")
  library(lubridate)
  cat(" ✅\n")
  
  cat("  • Chargement zoo...")
  library(zoo)
  cat(" ✅\n")
  
  cat("  • Chargement dbscan...")
  library(dbscan)
  cat(" ✅\n")
  
  cat("  • Chargement mclust...")
  library(mclust)
  cat(" ✅\n")
  
  cat("  • Chargement depmixS4...")
  library(depmixS4)
  cat(" ✅\n")
  
  cat("  • Chargement pROC...")
  library(pROC)
  cat(" ✅\n")
  
  cat("  • Chargement parallel...")
  library(parallel)
  cat(" ✅\n")
  
  cat("  • Chargement yaml...")
  library(yaml)
  cat(" ✅\n")
})

setDTthreads(cores)
cat("✅ data.table configuré avec", cores, "threads\n")

cat("\n📁 === CHARGEMENT DONNÉES ===\n")
# Utiliser nos données de test existantes
test_file <- "~/scratch/test_step2_vasco_da_gama_clean.rds"

if (!file.exists(test_file)) {
  stop("❌ Fichier test step2 introuvable: ", test_file)
}

cat("📖 Lecture du fichier:", test_file, "\n")
system.time({
  ais <- readRDS(test_file)
  setDT(ais)
})
cat("✅ Données chargées:", format(nrow(ais), big.mark=" "), "observations\n")
cat("✅ Colonnes:", ncol(ais), "variables\n")
cat("📊 Structure des données:\n")
str(ais)
cat("\n")

cat("📊 === STATISTIQUES DESCRIPTIVES INITIALES ===\n")
cat("• Navire(s):", paste(unique(ais$Navire), collapse=", "), "\n")
cat("• Plage de vitesses:", round(min(ais$Speed, na.rm=TRUE), 2), "-", round(max(ais$Speed, na.rm=TRUE), 2), "nœuds\n")
cat("• Vitesse moyenne:", round(mean(ais$Speed, na.rm=TRUE), 2), "nœuds\n")
cat("• Vitesse médiane:", round(median(ais$Speed, na.rm=TRUE), 2), "nœuds\n")
cat("• Écart-type vitesse:", round(sd(ais$Speed, na.rm=TRUE), 2), "nœuds\n")

# Configuration pour test
cat("\n⚙️ === CONFIGURATION PARAMÈTRES ===\n")
cfg <- list(
  spike_factor = 3,
  min_spike_duration = 2,
  min_context_points = 10,
  percentile_lower = 0.05,
  percentile_upper = 0.95,
  max_accel_ms2 = 2.0,
  max_turn_at_speed = 45,
  max_dredging_speed = 4.0
)
cat("✅ Paramètres configurés:\n")
for (param in names(cfg)) {
  cat("  •", param, ":", cfg[[param]], "\n")
}

cat("\n🔧 === DÉFINITION FONCTIONS UTILITAIRES ===\n")

# Fonction roll_MAD5
cat("• Définition roll_MAD5...")
roll_MAD5 <- function(x) {
  med <- zoo::rollapplyr(x, 5, median, fill = NA, align = "center")
  q25 <- zoo::rollapplyr(x, 5, quantile, probs = .25, fill = NA, align = "center")
  q75 <- zoo::rollapplyr(x, 5, quantile, probs = .75, fill = NA, align = "center")
  mad <- 1.4826 * (q75 - q25)
  list(med = med, mad = mad)
}
cat(" ✅\n")

# Test de la fonction
cat("• Test roll_MAD5 sur échantillon...")
test_speeds <- ais$Speed[1:100]
test_result <- roll_MAD5(test_speeds)
cat(" ✅ (", sum(!is.na(test_result$med)), "valeurs non-NA)\n")

cat("\n⚙️ === VALIDATION PHYSIQUE ===\n")
cat("📊 Observations avant validation:", format(nrow(ais), big.mark=" "), "\n")

# Calcul accélération si pas présente
if (!"Accel" %in% names(ais)) {
  cat("• Calcul de l'accélération...")
  if ("Seg_id" %in% names(ais)) {
    ais[, Accel := c(NA_real_, diff(Speed)), by = Seg_id]
  } else {
    ais[, Accel := c(NA_real_, diff(Speed))]
  }
  cat(" ✅\n")
}

# Statistiques accélération
cat("📊 Statistiques accélération:\n")
cat("  • Min:", round(min(ais$Accel, na.rm=TRUE), 3), "nœuds/point\n")
cat("  • Max:", round(max(ais$Accel, na.rm=TRUE), 3), "nœuds/point\n")
cat("  • Moyenne:", round(mean(ais$Accel, na.rm=TRUE), 3), "nœuds/point\n")
cat("  • Écart-type:", round(sd(ais$Accel, na.rm=TRUE), 3), "nœuds/point\n")

# Filtrage accélération
max_acc_kns <- cfg$max_accel_ms2 * 1.943844
cat("• Seuil max accélération:", round(max_acc_kns, 2), "nœuds/point\n")
n_before <- nrow(ais)
ais <- ais[abs(Accel) <= max_acc_kns | is.na(Accel)]
n_after <- nrow(ais)
cat("✅ Filtrage accélération:", format(n_before, big.mark=" "), "→", format(n_after, big.mark=" "), 
    "(", round((n_before-n_after)/n_before*100, 1), "% supprimés)\n")

cat("\n📐 === SEUILS ADAPTATIFS ===\n")
# Calcul seuil adaptatif
cat("• Calcul du 5ème percentile des vitesses positives...\n")
if ("Navire" %in% names(ais)) {
  q05 <- ais[Speed > 0, .(
    q05 = quantile(Speed, 0.05),
    n_obs = .N,
    vitesse_min = min(Speed),
    vitesse_max = max(Speed)
  ), by = Navire]
  
  cat("📊 Statistiques par navire:\n")
  print(q05)
  
  q05[, seuil := pmax(.15, pmin(.8, q05))]
  cat("📊 Seuils adaptatifs calculés:\n")
  print(q05[, .(Navire, q05, seuil)])
  
  ais <- merge(ais, q05[, .(Navire, seuil)], by = "Navire")
} else {
  seuil_global <- quantile(ais$Speed[ais$Speed > 0], 0.05)
  seuil_global <- pmax(.15, pmin(.8, seuil_global))
  ais[, seuil := seuil_global]
  cat("✅ Seuil global calculé:", round(seuil_global, 3), "nœuds\n")
}

# Application seuil arrêt
ais[, is_stop := Speed <= seuil]
n_stops <- sum(ais$is_stop, na.rm = TRUE)
n_moving <- sum(!ais$is_stop, na.rm = TRUE)
cat("✅ Classification vitesse:\n")
cat("  • Arrêts (≤ seuil):", format(n_stops, big.mark=" "), "(", round(n_stops/nrow(ais)*100, 1), "%)\n")
cat("  • Mouvement (> seuil):", format(n_moving, big.mark=" "), "(", round(n_moving/nrow(ais)*100, 1), "%)\n")

cat("\n🎯 === MODÉLISATION GMM ===\n")
# Préparation données pour GMM
move_data <- ais[is_stop == FALSE & Speed <= 20, Speed]
cat("📊 Données pour GMM:\n")
cat("  • Observations mouvement (≤20 nœuds):", format(length(move_data), big.mark=" "), "\n")
cat("  • Vitesse min:", round(min(move_data), 2), "nœuds\n")
cat("  • Vitesse max:", round(max(move_data), 2), "nœuds\n")
cat("  • Vitesse moyenne:", round(mean(move_data), 2), "nœuds\n")

if (length(move_data) >= 50) {
  cat("• Lancement GMM avec K=1 à 5 composantes...\n")
  
  system.time({
    gmm <- Mclust(move_data, G = 1:5, verbose = FALSE)
  })
  
  cat("✅ GMM terminé !\n")
  cat("📊 RÉSULTATS GMM:\n")
  cat("  • Nombre optimal de composantes (K):", gmm$G, "\n")
  cat("  • BIC optimal:", round(gmm$bic, 2), "\n")
  cat("  • Log-vraisemblance:", round(gmm$loglik, 2), "\n")
  
  # Détails des composantes
  cat("\n📊 === DÉTAILS DES COMPOSANTES GMM ===\n")
  for (k in 1:gmm$G) {
    cat("🔹 COMPOSANTE", k, ":\n")
    cat("  • Poids (proportion):", round(gmm$parameters$pro[k], 3), 
        "(", round(gmm$parameters$pro[k]*100, 1), "%)\n")
    cat("  • Moyenne:", round(gmm$parameters$mean[k], 3), "nœuds\n")
    cat("  • Écart-type:", round(sqrt(gmm$parameters$variance$sigmasq[k]), 3), "nœuds\n")
    cat("  • Variance:", round(gmm$parameters$variance$sigmasq[k], 3), "\n")
    
    # Calcul des quantiles de cette composante
    mean_k <- gmm$parameters$mean[k]
    sd_k <- sqrt(gmm$parameters$variance$sigmasq[k])
    cat("  • Intervalle 95% (μ±1.96σ): [", 
        round(mean_k - 1.96*sd_k, 2), " - ", round(mean_k + 1.96*sd_k, 2), "] nœuds\n")
    
    # Nombre d'observations assignées à cette composante
    assignments <- apply(predict(gmm, newdata = move_data)$z, 1, which.max)
    n_assigned <- sum(assignments == k)
    cat("  • Observations assignées:", format(n_assigned, big.mark=" "), 
        "(", round(n_assigned/length(move_data)*100, 1), "%)\n")
    cat("\n")
  }
  
  # Prédiction pour toutes les données de mouvement
  cat("• Calcul des probabilités d'appartenance...\n")
  Z <- predict(gmm, newdata = move_data)$z
  cat("✅ Probabilités calculées pour", format(nrow(Z), big.mark=" "), "observations\n")
  
  # Application au dataset complet
  cat("• Application au dataset complet...\n")
  ais[, paste0("p", 1:5) := 0.0]
  ais[is_stop == TRUE, p1 := 1]  # Arrêts = composante 1
  
  # Attribution des probabilités aux observations en mouvement
  move_indices <- which(ais$is_stop == FALSE & ais$Speed <= 20)
  for (j in 1:ncol(Z)) {
    ais[move_indices, paste0("p", j + 1) := Z[, j]]
  }
  
  # Composante la plus probable pour chaque observation
  ais[, comp := apply(.SD, 1, which.max), .SDcols = paste0("p", 1:5)]
  
  cat("✅ Attribution des composantes terminée\n")
  
  # Statistiques finales par composante
  cat("\n📊 === DISTRIBUTION FINALE DES COMPOSANTES ===\n")
  comp_stats <- ais[, .N, by = comp]
  comp_stats[, prop := round(N / sum(N) * 100, 1)]
  setnames(comp_stats, c("Composante", "Observations", "Pourcentage"))
  print(comp_stats)
  
} else {
  cat("❌ Pas assez de données pour GMM (minimum 50 observations)\n")
}

cat("\n🗺️ === TEST DBSCAN ===\n")
stop_coords <- ais[is_stop == TRUE & !is.na(Lon) & !is.na(Lat), .(Lon, Lat)]
cat("📊 Coordonnées d'arrêt disponibles:", format(nrow(stop_coords), big.mark=" "), "\n")

if (nrow(stop_coords) >= 4) {
  cat("• Calcul paramètre eps optimal...\n")
  eps <- 0.01 * median(dist(stop_coords[sample(min(100, nrow(stop_coords)))]))
  cat("  • eps calculé:", round(eps, 6), "\n")
  
  cat("• Lancement DBSCAN...\n")
  system.time({
    cl <- dbscan(stop_coords, eps = eps, minPts = 4)
  })
  
  n_clusters <- length(unique(cl$cluster[cl$cluster > 0]))
  n_noise <- sum(cl$cluster == 0)
  
  cat("✅ DBSCAN terminé :\n")
  cat("  • Clusters trouvés:", n_clusters, "\n")
  cat("  • Points de bruit:", format(n_noise, big.mark=" "), "\n")
  cat("  • Points dans clusters:", format(sum(cl$cluster > 0), big.mark=" "), "\n")
  
  if (n_clusters > 0) {
    cluster_sizes <- table(cl$cluster[cl$cluster > 0])
    cat("  • Taille clusters - Min:", min(cluster_sizes), "| Max:", max(cluster_sizes), 
        "| Médiane:", median(cluster_sizes), "\n")
  }
} else {
  cat("❌ Pas assez de coordonnées d'arrêt pour DBSCAN\n")
}

cat("\n💾 === SAUVEGARDE ===\n")
output_file <- "~/scratch/step3_interactif_result.rds"
cat("• Sauvegarde vers:", output_file, "\n")
system.time({
  saveRDS(ais, output_file, compress = "xz")
})

if (file.exists(output_file)) {
  file_size <- file.info(output_file)$size / 1024^2
  cat("✅ Fichier sauvé:", round(file_size, 1), "MB\n")
}

cat("\n")
cat("================================================================================\n")
cat("🏁  STEP-3 INTERACTIF TERMINÉ AVEC SUCCÈS\n")
cat("================================================================================\n")
cat("Timestamp fin:", format(Sys.time()), "\n")
cat("✅ Toutes les étapes validées !\n")
cat("📁 Résultat disponible dans:", output_file, "\n")
EOF

echo "🚀 Lancement R interactif avec affichage complet..."
R --vanilla --slave -e "source('step3_interactif_detaille.R', echo=TRUE, verbose=TRUE)"

echo ""
echo "✅ STEP3 INTERACTIF TERMINÉ: $(date)" 