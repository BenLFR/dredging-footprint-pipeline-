#!/bin/bash
# ====================================================================
# TEST INTERACTIF ÉTAPE 1 - FRACTIONNEMENT PAR NAVIRE
# ====================================================================

echo "🚀 === TEST INTERACTIF ÉTAPE 1 ==="
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
echo "📦 Test ID simulé: TEST_12345"
mkdir -p ~/scratch/ais_split_TEST_12345

echo ""
echo "✅ Lancement script de fractionnement en mode TEST..."
echo "=================================================="

R --vanilla --slave -e "
cat('🔧 === TEST R SESSION ===\n')
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

# Chargement librairies test
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_JOB_ID = 'TEST_12345')

cat('📚 Test chargement packages...\n')
tryCatch({
  library(data.table)
  cat('✅ data.table OK\n')
}, error = function(e) cat('❌ data.table ERREUR:', e\$message, '\n'))

tryCatch({
  library(fst)
  cat('✅ fst OK\n')
}, error = function(e) cat('❌ fst ERREUR:', e\$message, '\n'))

cat('🚀 Lancement script principal...\n')
source('step1_split_navires.R')
"

echo ""
echo "📊 RÉSUMÉ TEST:"
echo "Fichiers créés dans ~/scratch/ais_split_TEST_12345/:"
ls -lh ~/scratch/ais_split_TEST_12345/ 2>/dev/null || echo "Aucun fichier créé"

echo ""
echo "✅ Test interactif terminé: $(date)" 