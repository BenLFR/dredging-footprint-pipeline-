#!/usr/bin/env Rscript

# CONFIGURATION R CRITIQUE - AVANT CHARGEMENT PACKAGES
.libPaths("~/.local/R/4.2.1/")
cat("✅ R configuré avec library:", .libPaths()[1], "\n")

cat("🏁 === TEST STEP3 DIRECT ===\n")
cat("Début:", format(Sys.time()), "\n")

# Configuration
cores <- 4
options(mc.cores = cores)
Sys.setenv(MC_CORES = cores)
Sys.setenv(DT_GForce = "FALSE")
Sys.setenv(OMP_NUM_THREADS = cores)

# Chargement packages
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(zoo)
  library(dbscan)
  library(mclust)
  library(depmixS4)
  library(pROC)
  library(parallel)
  library(yaml)
})

setDTthreads(cores)
cat("✅ Packages chargés -", cores, "threads\n")

# Simulation d'un environnement step3 minimal
# Au lieu d'utiliser plusieurs fichiers _clean.rds, utilisons juste notre test
test_file <- "~/scratch/test_step2_vasco_da_gama_clean.rds"

if (!file.exists(test_file)) {
  stop("❌ Fichier test step2 introuvable: ", test_file)
}

cat("📖 Chargement fichier test step2...\n")
ais <- readRDS(test_file)
setDT(ais)
cat("✅ Données chargées:", nrow(ais), "observations\n")

# Vérification structure
cat("📊 Colonnes disponibles:", paste(names(ais), collapse=", "), "\n")

# Configuration simple pour test
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

# Test des fonctions utilitaires
cat("🔧 Test fonctions utilitaires...\n")

# Fonction roll_MAD5
roll_MAD5 <- function(x) {
  med <- zoo::rollapplyr(x, 5, median, fill = NA, align = "center")
  q25 <- zoo::rollapplyr(x, 5, quantile, probs = .25, fill = NA, align = "center")
  q75 <- zoo::rollapplyr(x, 5, quantile, probs = .75, fill = NA, align = "center")
  mad <- 1.4826 * (q75 - q25)
  list(med = med, mad = mad)
}

# Test sur un échantillon
test_speeds <- ais$Speed[1:100]
test_result <- roll_MAD5(test_speeds)
cat("✅ roll_MAD5 fonctionne\n")

# Test validation physique simple
cat("⚙️ Test validation physique...\n")
if (!"Accel" %in% names(ais)) {
  if ("Seg_id" %in% names(ais)) {
    ais[, Accel := c(NA_real_, diff(Speed)), by = Seg_id]
  } else {
    ais[, Accel := c(NA_real_, diff(Speed))]
  }
}

n_before <- nrow(ais)
max_acc_kns <- cfg$max_accel_ms2 * 1.943844
ais <- ais[abs(Accel) <= max_acc_kns | is.na(Accel)]
n_after <- nrow(ais)
cat("✅ Validation physique:", n_before, "→", n_after, "observations\n")

# Test seuils adaptatifs
cat("📐 Test seuils adaptatifs...\n")
if ("Navire" %in% names(ais)) {
  q05 <- ais[Speed > 0, quantile(Speed, 0.05), by = Navire]
  ais <- merge(ais, q05[, .(Navire, seuil = pmax(.15, pmin(.8, V1)))], by = "Navire")
} else {
  ais[, seuil := quantile(Speed[Speed > 0], 0.05)]
}
ais[, is_stop := Speed <= seuil]
n_stops <- sum(ais$is_stop, na.rm = TRUE)
cat("✅ Arrêts détectés:", n_stops, "observations\n")

# Test GMM simple (si assez de données)
cat("🎯 Test GMM...\n")
move_data <- ais[is_stop == FALSE & Speed <= 20, Speed]
if (length(move_data) >= 50) {
  tryCatch({
    gmm <- Mclust(move_data, G = 1:3, verbose = FALSE)
    cat("✅ GMM réussi - K optimal:", gmm$G, "\n")
  }, error = function(e) {
    cat("⚠️ GMM échoué:", e$message, "\n")
  })
} else {
  cat("⚠️ Pas assez de données pour GMM\n")
}

# Test DBSCAN simple
cat("🗺️ Test DBSCAN...\n")
stop_coords <- ais[is_stop == TRUE & !is.na(Lon) & !is.na(Lat), .(Lon, Lat)]
if (nrow(stop_coords) >= 4) {
  tryCatch({
    eps <- 0.01 * median(dist(stop_coords[1:min(100, nrow(stop_coords))]))
    cl <- dbscan(stop_coords, eps = eps, minPts = 4)
    n_clusters <- length(unique(cl$cluster[cl$cluster > 0]))
    cat("✅ DBSCAN réussi -", n_clusters, "clusters\n")
  }, error = function(e) {
    cat("⚠️ DBSCAN échoué:", e$message, "\n")
  })
} else {
  cat("⚠️ Pas assez de coordonnées d'arrêt pour DBSCAN\n")
}

# Test sauvegarde
output_file <- "~/scratch/test_step3_result.rds"
cat("💾 Test sauvegarde:", output_file, "\n")
saveRDS(ais, output_file, compress = "xz")

if (file.exists(output_file)) {
  file_size <- file.info(output_file)$size / 1024^2
  cat("✅ Fichier sauvé:", round(file_size, 1), "MB\n")
}

cat("✅ Test step3 terminé:", format(Sys.time()), "\n")
