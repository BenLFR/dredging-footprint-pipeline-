#!/bin/bash

echo "🐛 DÉBOGAGE DÉTAILLÉ - Script NO_SF sur Beluga"
echo "=============================================="

LOG_FILE="debug_$(date +%Y%m%d_%H%M%S).log"
ERROR_FILE="errors_$(date +%Y%m%d_%H%M%S).log"

echo "📝 Log principal: $LOG_FILE"
echo "🚨 Log erreurs: $ERROR_FILE"

# Connexion à Beluga avec débogage avancé
ssh benl@beluga.alliancecan.ca << 'EOF'

echo "========================================"
echo "🐛 BELUGA - DÉBOGAGE SCRIPT NO_SF"
echo "========================================"

DEBUG_LOG="debug_beluga_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="errors_beluga_$(date +%Y%m%d_%H%M%S).log"

log_debug() {
    echo "[$(date '+%H:%M:%S')] DEBUG: $1" | tee -a "$DEBUG_LOG"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG"
}

log_debug "📡 Connexion Beluga réussie"
log_debug "🏠 Répertoire home: $HOME"
log_debug "👤 Utilisateur: $(whoami)"

# Chargement des modules
log_debug "🔧 Chargement modules..."
module load r/4.5.0
if [ $? -ne 0 ]; then
    log_error "Échec chargement module R"
    exit 1
fi

# Vérification environnement R
log_debug "🧪 Test environnement R..."
R --version | head -3

# Demander session interactive pour débogage
log_debug "🎯 Demande session interactive (débogage - 2h)..."
salloc --time=2:00:00 --cpus-per-task=8 --mem=32G --account=def-wailung << 'DEBUG_SESSION'

echo "============================================"
echo "🐛 SESSION DÉBOGAGE INTERACTIVE"
echo "============================================"
echo "Node: $SLURMD_NODENAME"
echo "Job ID: $SLURM_JOB_ID"
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Mémoire: $(free -h | grep Mem | awk '{print $2}')"

# Recharger R
module load r/4.5.0
cd ~/R_scripts

# Créer un script de test segmenté
cat > test_segments.R << 'R_SCRIPT'
#!/usr/bin/env Rscript

# ==============================================================================
# SCRIPT DE DÉBOGAGE SEGMENTÉ
# ==============================================================================

cat("🚀 DÉBUT DU DÉBOGAGE SEGMENTÉ\n")
cat("============================\n")

# Fonction de débogage
debug_section <- function(section_name, code_block) {
  cat(sprintf("\n📍 SECTION: %s\n", section_name))
  cat(sprintf("⏰ Début: %s\n", Sys.time()))
  
  tryCatch({
    result <- code_block()
    cat(sprintf("✅ %s - SUCCESS\n", section_name))
    return(result)
  }, error = function(e) {
    cat(sprintf("❌ %s - ERROR: %s\n", section_name, e$message))
    cat(sprintf("📍 Trace: %s\n", paste(traceback(), collapse = "\n")))
    stop(sprintf("Erreur dans %s: %s", section_name, e$message))
  }, warning = function(w) {
    cat(sprintf("⚠️  %s - WARNING: %s\n", section_name, w$message))
  })
}

# SECTION 1: Chargement des packages
debug_section("CHARGEMENT PACKAGES", {
  cat("Chargement data.table...\n")
  library(data.table)
  cat("Chargement lubridate...\n")
  library(lubridate)
  cat("Chargement mclust...\n")
  library(mclust)
  cat("Chargement caret...\n")
  library(caret)
  cat("Chargement pROC...\n")
  library(pROC)
  cat("Chargement ggplot2...\n")
  library(ggplot2)
  cat("Chargement dbscan...\n")
  library(dbscan)
  cat("Chargement dplyr...\n")
  library(dplyr)
  cat("Chargement zoo...\n")
  library(zoo)
  
  # Packages optionnels
  if (!require(depmixS4, quietly=TRUE)) {
    install.packages("depmixS4")
    library(depmixS4)
  }
  if (!require(pbapply, quietly=TRUE)) {
    install.packages("pbapply") 
    library(pbapply)
  }
  if (!require(matrixStats, quietly=TRUE)) {
    install.packages("matrixStats")
    library(matrixStats)
  }
  if (!require(geosphere, quietly=TRUE)) {
    install.packages("geosphere")
    library(geosphere)
  }
  
  cat("✅ Tous les packages chargés\n")
})

# SECTION 2: Configuration parallélisme
debug_section("CONFIGURATION PARALLÉLISME", {
  n_threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
  cat("Threads disponibles:", n_threads, "\n")
  
  Sys.setenv(OMP_NUM_THREADS = n_threads,
             OPENBLAS_NUM_THREADS = n_threads)
  data.table::setDTthreads(n_threads)
  options(mc.cores = n_threads)
  
  cat("✅ Parallélisme configuré\n")
})

# SECTION 3: Tables de mapping
debug_section("TABLES MAPPING", {
  mmsi_map <- data.table(
    ssvid = c(209469000, 210138000, 245508000, 246351000,
              253193000, 253373000, 253403000, 253422000,
              253688000, 312062000, 533180137),
    
    IMO_number = c(9132454, 9164031, 9229556, 9454096,
                   9187473, 9429572, 9429584, 9528079,
                   9574523, 8119728, 9568782),
    
    Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318 Sleephopperzuiger",
               "Vox Maxima", "Vasco Da Gama", "Cristobal Colon",
               "Leiv Eiriksson", "Charles Darwin", "Congo River",
               "Goryo 6 Ho", "Inai Kenanga")
  )
  setkey(mmsi_map, ssvid)
  cat("Mapping créé:", nrow(mmsi_map), "navires\n")
})

# SECTION 4: Fonctions de chargement
debug_section("FONCTIONS CHARGEMENT", {
  load_AIS_files <- function(directory) {
    files <- list.files(path = directory, pattern = "\\.csv$", full.names = TRUE)
    cat("Fichiers trouvés:", length(files), "\n")
    
    dt_list <- lapply(files, function(f) {
      cat("Lecture:", basename(f), "... ")
      dt <- fread(f, stringsAsFactors = FALSE)
      setnames(dt, c("Lon","Lat","Course","Timestamp","Speed","Seg_id"))
      dt[, Navire := tools::file_path_sans_ext(basename(f))]
      cat("OK (", nrow(dt), "lignes)\n")
      dt
    })
    
    result <- rbindlist(dt_list)
    cat("Total fusionné:", nrow(result), "lignes\n")
    return(result)
  }
  cat("✅ Fonction load_AIS_files définie\n")
})

# SECTION 5: Chargement données
debug_section("CHARGEMENT DONNÉES", {
  ais_directory <- "~/scratch/AIS_data"
  out_dir <- "~/scratch/output"
  
  # Vérifier répertoires
  if (!dir.exists(ais_directory)) {
    stop("Répertoire AIS_data inexistant: ", ais_directory)
  }
  
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  cat("Répertoires vérifiés\n")
  
  # Charger données
  ais_data <- load_AIS_files(ais_directory)
  cat("Données chargées:", nrow(ais_data), "lignes,", length(unique(ais_data$Navire)), "navires\n")
  
  # Conversion timestamp
  ais_data[, Timestamp := as.POSIXct(Timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]
  ais_data[, Annee := year(Timestamp)]
  
  # Fenêtre temporelle
  core_years <- 2012:2024
  ais_data_core <- ais_data[Annee %in% core_years]
  cat("Données core:", nrow(ais_data_core), "lignes\n")
  
  # Nettoyer mémoire
  rm(ais_data)
  gc()
  
  return(ais_data_core)
})

# SECTION 6: Test GMM simple
debug_section("TEST GMM SIMPLE", {
  if (exists("ais_data_core") && nrow(ais_data_core) > 1000) {
    # Test GMM sur échantillon
    sample_speeds <- sample(ais_data_core$Speed, min(10000, nrow(ais_data_core)))
    sample_speeds <- sample_speeds[sample_speeds >= 0.3 & sample_speeds <= 20]
    
    cat("Test GMM sur", length(sample_speeds), "vitesses\n")
    
    if (length(sample_speeds) > 100) {
      gmm_test <- Mclust(sample_speeds, G = 2:5, verbose = FALSE)
      cat("GMM réussi - composantes:", gmm_test$G, "\n")
      cat("Moyennes:", round(gmm_test$parameters$mean, 2), "\n")
    }
  }
  cat("✅ Test GMM terminé\n")
})

cat("\n🏁 DÉBOGAGE SEGMENTÉ TERMINÉ\n")
cat("Mémoire finale:", round(sum(gc()[,2]) * 8 / 1024, 1), "Mo\n")

R_SCRIPT

# Lancer le test segmenté
echo "🔥 LANCEMENT TEST SEGMENTÉ..."
echo "==============================="

Rscript test_segments.R 2>&1 | tee debug_output.log

EXIT_CODE=${PIPESTATUS[0]}

echo "==============================="
echo "📊 RÉSULTAT DU TEST:"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ SUCCESS: Test segmenté réussi!"
    echo "🚀 Le script peut probablement tourner en entier"
else
    echo "❌ ERROR: Échec du test segmenté (exit code: $EXIT_CODE)"
    echo "🔍 Voir debug_output.log pour les détails"
fi

# Si le test segmenté réussit, tenter le script complet
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "🎯 LANCEMENT SCRIPT COMPLET (timeout 90 min)..."
    echo "=============================================="
    
    timeout 5400 Rscript "Entrainement modele V5 tri années cluster_NO_SF.R" 2>&1 | tee full_script_output.log
    
    FULL_EXIT_CODE=${PIPESTATUS[0]}
    
    echo "=============================================="
    if [ $FULL_EXIT_CODE -eq 0 ]; then
        echo "🎉 SUCCESS COMPLET: Script terminé avec succès!"
    elif [ $FULL_EXIT_CODE -eq 124 ]; then
        echo "⏰ TIMEOUT: Script arrêté après 90 minutes"
        echo "   Mais il a probablement progressé - voir full_script_output.log"
    else
        echo "❌ ERROR: Script complet échoué (exit code: $FULL_EXIT_CODE)"
        echo "   Voir full_script_output.log pour les détails"
    fi
fi

echo ""
echo "📄 FICHIERS DE LOG CRÉÉS:"
echo "- debug_output.log (test segmenté)"
echo "- full_script_output.log (script complet)"

echo "🏁 Session de débogage terminée"

DEBUG_SESSION

EOF

echo "✅ Script de débogage terminé"
echo "📄 Logs disponibles sur Beluga dans ~/"
</rewritten_file> 