#!/bin/bash
# ────────────────────────────────────────────────────────────────────────────────
# TEST TUILE TÉMOIN - Pipeline Step-5 Modulaire
# Valide le fonctionnement avec une seule tuile avant le lancement complet
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

echo "🧪 Test Tuile Témoin - Pipeline Step-5 Modulaire"
echo "=================================================="

# Vérification de l'environnement
log_info "Vérification de l'environnement..."

# Modules
if ! module list 2>/dev/null | grep -q "StdEnv/2023"; then
    module load StdEnv/2023
fi
if ! module list 2>/dev/null | grep -q "apptainer"; then
    module load apptainer
fi

# Fichiers requis
if [ ! -f "$HOME/scratch/rocker_geospatial_step5.sif" ]; then
    log_error "Image Apptainer manquante"
    exit 1
fi

if [ ! -f "$HOME/scratch/configuration/fi_parameters.yaml" ]; then
    log_error "Fichier de paramètres manquant"
    exit 1
fi

if [ ! -f "$HOME/scratch/configuration/ship_specs.yaml" ]; then
    log_error "Fichier de specs navires manquant"
    exit 1
fi

log_success "Environnement vérifié"

# Étape 1 : Génération des tuiles (si nécessaire)
if [ ! -f "$HOME/scratch/output_V6/tiles_5000km.gpkg" ]; then
    log_info "Génération des tuiles..."
    apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript step5_make_tiles.R
    log_success "Tuiles générées"
else
    log_info "Fichier de tuiles existant - réutilisation"
fi

# Étape 2 : Test d'une tuile témoin
log_info "Test de la tuile témoin (ID: 12 - zone dense)..."
job_id=$(sbatch --array=12-12 step5_tile_job.sh | grep -o '[0-9]\+')

if [ $? -eq 0 ]; then
    log_success "Job témoin lancé avec l'ID : $job_id"
else
    log_error "Échec du lancement du job témoin"
    exit 1
fi

# Attente et monitoring
log_info "Monitoring du job témoin..."
echo "   - Vérifier avec : squeue -j $job_id"
echo "   - Logs en temps réel : tail -f logs/step5_tile_12_*.out"
echo "   - Statut final : sacct -j $job_id --format=JobID,State,MaxRSS,Elapsed"

# Attente de la fin
while squeue -j "$job_id" 2>/dev/null | grep -q "$job_id"; do
    echo -n "."
    sleep 30
done
echo ""

# Vérification du résultat
job_status=$(sacct -j "$job_id" --format=State --noheader | tail -1)
max_rss=$(sacct -j "$job_id" --format=MaxRSS --noheader | tail -1)

if [ "$job_status" = "COMPLETED" ]; then
    log_success "Job témoin terminé avec succès"
    echo "   - Statut : $job_status"
    echo "   - Mémoire max : $max_rss"
    
    # Vérification du fichier de sortie
    if [ -f "$HOME/scratch/output_V6/sar_012.parquet" ] || [ -f "$HOME/scratch/output_V6/sar_012.rds" ]; then
        log_success "Fichier de sortie créé"
        echo "   - Taille : $(ls -lh $HOME/scratch/output_V6/sar_012.* 2>/dev/null | awk '{print $5}')"
    else
        log_error "Fichier de sortie manquant"
        exit 1
    fi
else
    log_error "Job témoin échoué avec statut : $job_status"
    echo "   - Vérifier les logs : tail -20 logs/step5_tile_12_*.err"
    exit 1
fi

# Étape 3 : Test de fusion (optionnel)
read -p "🧪 Tester la fusion avec cette tuile ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Test de fusion..."
    
    # Création d'un dossier de test
    test_dir="$HOME/scratch/test_fusion_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$test_dir"
    
    # Copie du fichier de résultat
    if [ -f "$HOME/scratch/output_V6/sar_012.parquet" ]; then
        cp "$HOME/scratch/output_V6/sar_012.parquet" "$test_dir/"
    elif [ -f "$HOME/scratch/output_V6/sar_012.rds" ]; then
        cp "$HOME/scratch/output_V6/sar_012.rds" "$test_dir/"
    fi
    
    # Test de fusion
    cd "$test_dir"
    apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript "$SCRIPT_DIR/step5_merge_tiles.R"
    
    if [ $? -eq 0 ]; then
        log_success "Fusion testée avec succès"
        echo "   - Fichiers créés : $(ls -1 fi_* 2>/dev/null | wc -l)"
    else
        log_error "Échec de la fusion"
    fi
    
    cd "$SCRIPT_DIR"
fi

echo ""
echo "🎯 Résumé du test :"
echo "==================="
echo "✅ Environnement : OK"
echo "✅ Génération tuiles : OK"
echo "✅ Tuile témoin : $job_status"
echo "✅ Mémoire max : $max_rss"
echo "✅ Fichier sortie : OK"

if [ "$job_status" = "COMPLETED" ]; then
    echo ""
    echo "🚀 Le pipeline est prêt pour la production !"
    echo "   - Lancement complet : ./step5_pipeline_modulaire.sh"
    echo "   - Avec nettoyage : ./step5_pipeline_modulaire.sh --cleanup"
    echo "   - Avec GeoTIFF : ./step5_pipeline_modulaire.sh --make-tiff"
else
    echo ""
    echo "❌ Des problèmes ont été détectés. Vérifiez les logs avant de continuer."
fi 