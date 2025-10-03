#!/bin/bash

#SBATCH --job-name=test_step3
#SBATCH --account=def-wailung
#SBATCH --time=1:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --output=test_step3_%j.out

echo "🚀 === TEST STEP3 MERGE FINAL ==="
echo "Timestamp: $(date)"
echo "Node: $SLURMD_NODENAME"
echo "📦 Chargement modules R..."

# Configuration R
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

echo "📁 Répertoire de travail: $(pwd)"
echo "🚀 Lancement test step3 direct..."

# Exécution du script
R --vanilla --slave -e "
.libPaths(c('~/.local/R/4.2.1/', .libPaths()))
cat('✅ R configuré avec library:', .libPaths()[1], '\n')
cat('🔄 === TEST STEP3 DIRECT ===\n')
cat('Début:', format(Sys.time()), '\n')

# Configuration
input_dir <- '~/scratch/test_step1_final'  # Répertoire contenant les fichiers .qs
output_dir <- '~/scratch/test_step3_final'

# Créer le répertoire de sortie si nécessaire
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Exécution
source('step3_merge_final.R')

cat('✅ Test step3 terminé:', format(Sys.time()), '\n')
" 