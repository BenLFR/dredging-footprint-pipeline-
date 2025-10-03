#!/bin/bash
#SBATCH --job-name=test_glmnet
#SBATCH --mem=2G
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --account=def-wailung
#SBATCH --output=logs/test_glmnet_%j.out
#SBATCH --error=logs/test_glmnet_%j.err

echo "=== TEST GLMNET DANS CONTEXTE SLURM ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "Debut: $(date)"

# Configuration R Beluga
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=/home/benl/R/library
export R_LIBS_USER=/home/benl/R/library

# Test de chargement de glmnet
echo "Test de chargement de glmnet..."
R --slave -e "
# Configuration des chemins de bibliothèques R
user_libs <- c('/home/benl/R/library', '~/.local/R/4.2.1')
.libPaths(unique(c(user_libs, .libPaths())))
cat('✅ R cherchera les packages dans :', paste(.libPaths(), collapse = ' | '), '\\n')

# Test de chargement
tryCatch({
    library(glmnet)
    cat('✅ glmnet chargé avec succès\\n')
    cat('Version glmnet:', packageVersion('glmnet'), '\\n')
}, error = function(e) {
    cat('❌ Erreur lors du chargement de glmnet:', e$message, '\\n')
})

# Test de chargement des autres packages
packages <- c('doParallel', 'geosphere', 'mclust', 'pROC', 'data.table')
for(pkg in packages) {
    tryCatch({
        library(pkg, character.only = TRUE)
        cat('✅', pkg, 'chargé\\n')
    }, error = function(e) {
        cat('❌ Erreur avec', pkg, ':', e$message, '\\n')
    })
}
"

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "✅ Test réussi : tous les packages sont disponibles"
else
    echo "❌ Test échoué : certains packages manquent"
fi

echo "Fin du test: $(date)" 