#!/bin/bash
#SBATCH --job-name=test_step2
#SBATCH --account=def-wailung
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --output=test_step2_%j.out

echo "🚀 === TEST STEP2 NAVIRE INDIVIDUEL ==="
echo "Timestamp: $(date)"
echo "Node: $SLURMD_NODENAME"

echo "📦 Chargement modules R..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

echo "📁 Répertoire de travail: $(pwd)"
echo "🚀 Lancement test step2 direct..."

R --vanilla --slave -e "
.libPaths(c('~/.local/R/4.2.1/', .libPaths()))
cat('✅ R configuré avec library:', .libPaths()[1], '\n')
cat('✅ R configuré avec library:', .libPaths()[2], '\n')

cat('\n🔄 === TEST STEP2 DIRECT ===\n')
cat('Début:', format(Sys.time()), '\n')

# Charger packages
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(yaml)
  library(solitude)  # Isolation Forest
  library(mclust)
  library(zoo)
})

cat('✅ Packages chargés - Configuration mono-thread activée\n')

# Charger données
input_file <- '~/scratch/test_step1_final/navire_01_Charles_Darwin.rds'
cat('📖 Chargement navire Charles Darwin...\n')
dt_nav <- readRDS(input_file)
cat('✅ Données chargées:', nrow(dt_nav), 'observations\n')

# Test Isolation Forest
cat('🌲 Test Isolation Forest...\n')
cat('  Features utilisées: Lat, Lon, Speed\n')
cat('  Données complètes:', sum(complete.cases(dt_nav[, .(Lat, Lon, Speed)])), 'sur', nrow(dt_nav), '\n')

cat('  🚀 Fitting Isolation Forest...\n')
iso_forest <- solitude::isolationForest$new(
  sample_size = 512,
  num_trees = 50,
  replace = FALSE
)
iso_forest$fit(dt_nav[, .(Lat, Lon, Speed)])

cat('  🔍 Prédiction outliers...\n')
dt_nav[, is_outlier := iso_forest$predict(dt_nav[, .(Lat, Lon, Speed)])$anomaly_score > 0.5]

# Résultats
n_outliers <- sum(dt_nav$is_outlier)
cat('✅ RÉSULTATS:\n')
cat('  • Outliers détectés:', n_outliers, '(', round(n_outliers/nrow(dt_nav)*100, 2), '%)\n')

# Sauvegarde
output_file <- '~/scratch/test_step2_charles_darwin_clean.rds'
cat('💾 Test sauvegarde:', output_file, '\n')
saveRDS(dt_nav, output_file)
cat('✅ Fichier sauvé:', round(file.size(output_file)/1024/1024, 1), 'MB\n')

cat('✅ Test step2 terminé:', format(Sys.time()), '\n')
cat('✅ Test step2 terminé:', date(), '\n')
" 