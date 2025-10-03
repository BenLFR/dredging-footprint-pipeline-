#!/bin/bash
# ────────────────────────────────────────────────────────────────────────────────
# TEST FUSION - Pipeline Step-5 Modulaire
# Valide la fusion avec quelques tuiles témoins
# ────────────────────────────────────────────────────────────────────────────────

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🧪 Test Fusion - Pipeline Step-5 Modulaire"
echo "==========================================="

# Création du dossier de test
test_dir="$HOME/scratch/test_fusion_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$test_dir"
cd "$test_dir"

log_info "Dossier de test créé : $test_dir"

# Vérification des fichiers de tuiles existants
sar_files=($(ls -1 ~/scratch/output_V6/sar_*.parquet 2>/dev/null || ls -1 ~/scratch/output_V6/sar_*.rds 2>/dev/null))

if [ ${#sar_files[@]} -eq 0 ]; then
    log_error "Aucun fichier de tuile trouvé dans ~/scratch/output_V6/"
    echo "   Lancez d'abord quelques tuiles avec : sbatch --array=1-2 step5_tile_job.sh"
    exit 1
fi

# Sélection des 2 premiers fichiers pour le test
test_files=("${sar_files[@]:0:2}")
log_info "Fichiers de test sélectionnés :"
for file in "${test_files[@]}"; do
    echo "   - $(basename "$file") ($(ls -lh "$file" | awk '{print $5}'))"
    cp "$file" .
done

# Copie des fichiers de configuration nécessaires
if [ -f "$HOME/scratch/configuration/fi_parameters.yaml" ]; then
    cp "$HOME/scratch/configuration/fi_parameters.yaml" .
    log_success "Paramètres f_i copiés"
else
    log_error "Fichier de paramètres manquant"
    exit 1
fi

if [ -f "$HOME/scratch/configuration/ship_specs.yaml" ]; then
    cp "$HOME/scratch/configuration/ship_specs.yaml" .
    log_success "Specs navires copiés"
else
    log_error "Fichier de specs navires manquant"
    exit 1
fi

# Copie des scripts nécessaires
cp "$SCRIPT_DIR/constants.R" .
cp "$SCRIPT_DIR/step5_merge_tiles.R" .

# Test de fusion
log_info "Lancement du test de fusion..."
start_time=$(date +%s)

apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
    Rscript step5_merge_tiles.R

fusion_status=$?
end_time=$(date +%s)
duration=$((end_time - start_time))

if [ $fusion_status -eq 0 ]; then
    log_success "Fusion testée avec succès"
    echo "   - Durée : ${duration} secondes"
    
    # Vérification des fichiers de sortie
    output_files=($(ls -1 fi_* 2>/dev/null || true))
    if [ ${#output_files[@]} -gt 0 ]; then
        log_success "Fichiers de sortie créés :"
        for file in "${output_files[@]}"; do
            echo "   - $(basename "$file") ($(ls -lh "$file" | awk '{print $5}'))"
        done
        
        # Test de lecture rapide
        log_info "Test de lecture des résultats..."
        apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
            Rscript -e "
            if(requireNamespace('arrow', quietly=TRUE)) {
                fi_data <- arrow::read_parquet('${output_files[0]}')
                cat('✅ Lecture OK :', nrow(fi_data), 'lignes\n')
                cat('   - Colonnes :', paste(names(fi_data), collapse=', '), '\n')
                cat('   - f_i range :', range(fi_data\$f_i_full, na.rm=TRUE), '\n')
            } else {
                fi_data <- readRDS('${output_files[0]}')
                cat('✅ Lecture RDS OK :', nrow(fi_data), 'lignes\n')
            }
            "
    else
        log_error "Aucun fichier de sortie créé"
        exit 1
    fi
else
    log_error "Échec de la fusion"
    echo "   - Vérifier les logs pour plus de détails"
    exit 1
fi

# Nettoyage
if [ "${CLEANUP_TEST:-false}" = "true" ]; then
    log_info "Nettoyage du dossier de test..."
    cd "$SCRIPT_DIR"
    rm -rf "$test_dir"
    log_success "Dossier de test supprimé"
else
    echo ""
    echo "📁 Dossier de test conservé : $test_dir"
    echo "   - Pour nettoyer : export CLEANUP_TEST=true && ./test_fusion.sh"
fi

echo ""
echo "🎯 Résumé du test de fusion :"
echo "============================="
echo "✅ Fichiers de test : ${#test_files[@]}"
echo "✅ Fusion : OK (${duration}s)"
echo "✅ Fichiers de sortie : ${#output_files[@]}"
echo "✅ Lecture des résultats : OK"

echo ""
echo "🚀 Le pipeline de fusion est prêt pour la production !"
echo "   - Lancement complet : ./step5_pipeline_modulaire.sh"
echo "   - Avec GeoTIFF : ./step5_pipeline_modulaire.sh --make-tiff" 