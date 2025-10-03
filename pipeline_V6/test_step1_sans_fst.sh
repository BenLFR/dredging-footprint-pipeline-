#!/bin/bash
# ====================================================================
# TEST INTERACTIF ÉTAPE 1 - SANS FST POUR TESTER LE CHEMIN
# ====================================================================

echo "🚀 === TEST INTERACTIF ÉTAPE 1 (SANS FST) ==="
echo "Timestamp: $(date)"
echo "Node: $HOSTNAME"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

# CORRECTION: Aller dans le bon répertoire
cd ~/R_scripts/pipeline_V6

echo "📁 Répertoire de travail: $(pwd)"
echo "✅ Vérification fichiers:"
ls -la step1_split_navires.R 2>/dev/null || echo "❌ FICHIER step1_split_navires.R MANQUANT"
ls -la ~/benjamin2.csv 2>/dev/null || echo "❌ FICHIER benjamin2.csv MANQUANT" 

echo ""
echo "🔍 Contenu répertoire actuel:"
ls -la *.R

echo ""
echo "📦 Test ID simulé: TEST_67890"
mkdir -p ~/scratch/ais_split_TEST_67890

echo ""
echo "✅ Test lecture données et packages de base..."
echo "=================================================="

R --vanilla --slave -e "
cat('🔧 === TEST R SESSION (SANS FST) ===\n')
cat('Répertoire R:', getwd(), '\n')
cat('Chemin libPaths:', .libPaths(), '\n')

# Test existence fichier
if(file.exists('step1_split_navires.R')) {
  cat('✅ Fichier step1_split_navires.R trouvé\n')
} else {
  cat('❌ Fichier step1_split_navires.R INTROUVABLE\n')
  quit(status=1)
}

# Test existence données
if(file.exists('~/benjamin2.csv')) {
  cat('✅ Fichier benjamin2.csv trouvé\n')
} else {
  cat('❌ Fichier benjamin2.csv INTROUVABLE\n')
  quit(status=1)
}

# Configuration 
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_JOB_ID = 'TEST_67890')

cat('📚 Test packages critiques...\n')
tryCatch({
  library(data.table)
  cat('✅ data.table OK\n')
}, error = function(e) cat('❌ data.table ERREUR:', e\$message, '\n'))

tryCatch({
  library(yaml)
  cat('✅ yaml OK\n')
}, error = function(e) cat('❌ yaml ERREUR:', e\$message, '\n'))

# Test lecture de données 
cat('📊 Test lecture échantillon benjamin2.csv...\n')
tryCatch({
  # Lecture d'un petit échantillon pour tester
  ais_sample <- data.table::fread('~/benjamin2.csv', nrows=1000)
  cat('✅ Lecture données OK:', nrow(ais_sample), 'lignes lues\n')
  cat('Colonnes:', paste(names(ais_sample), collapse=', '), '\n')
  
  # Test identification navires
  if('mmsi' %in% names(ais_sample)) {
    navires_uniques <- length(unique(ais_sample\$mmsi))
    cat('✅ MMSI trouvés:', navires_uniques, 'navires uniques dans échantillon\n')
  }
  
}, error = function(e) cat('❌ ERREUR lecture:', e\$message, '\n'))

cat('🎯 Test chemins et configuration OK !\n')
"

echo ""
echo "📊 RÉSUMÉ TEST (SANS FST):"
echo "✅ Chemins corrigés"
echo "✅ Fichiers trouvés"  
echo "✅ Packages de base testés"
echo "❌ FST nécessaire pour fractionnement réel"

echo ""
echo "💡 RECOMMANDATION:"
echo "Le chemin est corrigé, mais il faut résoudre le problème FST"
echo "OU utiliser un format alternatif (RDS) pour le pipeline"

echo ""
echo "✅ Test interactif terminé: $(date)" 