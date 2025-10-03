#!/bin/bash
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  PIPELINE MODULAIRE (pipeline V6, cluster Rorqual)
# Orchestration complète du traitement par tuiles
# ────────────────────────────────────────────────────────────────────────────────

set -e  # Arrêt en cas d'erreur

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions utilitaires
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Affichage de l'aide
show_help() {
    echo "Usage: $0 [--cleanup] [--make-tiff]"
    echo ""
    echo "Options:"
    echo "  --cleanup    Supprime les fichiers temporaires après traitement"
    echo "  --make-tiff  Génère le raster GeoTIFF (consomme +2.6 GB RAM)"
    echo "  --help       Affiche cette aide"
    echo ""
    echo "Description:"
    echo "  Pipeline Step-5 Modulaire - Traitement par tuiles pour éviter l'OOM"
}

# Vérification de l'environnement
check_environment() {
    log_info "Vérification de l'environnement..."
    
    # Vérification des modules
    if ! module list 2>/dev/null | grep -q "StdEnv/2023"; then
        log_warning "Module StdEnv/2023 non chargé - chargement automatique"
        module load StdEnv/2023
    fi
    
    if ! module list 2>/dev/null | grep -q "apptainer"; then
        log_warning "Module apptainer non chargé - chargement automatique"
        module load apptainer
    fi
    
    # Vérification des répertoires
    if [ ! -d "$HOME/scratch/output_V6" ]; then
        log_error "Répertoire $HOME/scratch/output_V6 manquant"
        exit 1
    fi
    
    if [ ! -d "$HOME/scratch/configuration" ]; then
        log_error "Répertoire $HOME/scratch/configuration manquant"
        exit 1
    fi
    
    # Vérification des fichiers requis
    if [ ! -f "$HOME/scratch/rocker_geospatial_step5.sif" ]; then
        log_error "Image Apptainer manquante : $HOME/scratch/rocker_geospatial_step5.sif"
        exit 1
    fi
    
    if [ ! -f "$HOME/scratch/configuration/fi_parameters.yaml" ]; then
        log_error "Fichier de paramètres manquant : fi_parameters.yaml"
        exit 1
    fi
    
    if [ ! -f "$HOME/scratch/configuration/ship_specs_clean.yaml" ]; then
        log_error "Fichier de specs navires manquant : ship_specs_clean.yaml"
        exit 1
    fi
    
    log_success "Environnement vérifié"
}

# Étape 1 : Génération des tuiles
generate_tiles() {
    log_info "Étape 1 : Génération des tuiles mondiales"
    
    if [ -f "$HOME/scratch/output_V6/tiles_1000km.gpkg" ]; then
        log_warning "Fichier de tuiles existant - réutilisation"
        return 0
    fi
    
    log_info "Lancement de la génération des tuiles..."
    apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript step5_make_tiles.R
    
    if [ $? -eq 0 ]; then
        log_success "Tuiles générées avec succès"
    else
        log_error "Échec de la génération des tuiles"
        exit 1
    fi
}

# Étape 2 : Lancement de l'array-job
launch_tile_jobs() {
    log_info "Étape 2 : Lancement des jobs de traitement par tuile"
    
    # Comptage du nombre de tuiles
    if ! command -v ogrinfo &> /dev/null; then
        log_error "ogrinfo non disponible - impossible de compter les tuiles"
        exit 1
    fi
    
    n_tiles=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "OGRFeature" | wc -l)
    
    if [ "$n_tiles" -eq 0 ]; then
        log_error "Aucune tuile trouvée"
        exit 1
    fi
    
    log_info "Nombre de tuiles détectées : $n_tiles"
    
    # Lancement de l'array-job
    job_id=$(sbatch --array=1-$n_tiles step5_tile_job.sh | grep -o '[0-9]\+')
    
    if [ $? -eq 0 ]; then
        log_success "Array-job lancé avec l'ID : $job_id"
        echo "$job_id" > .step5_array_job_id
    else
        log_error "Échec du lancement de l'array-job"
        exit 1
    fi
    
    # Attente de la fin des jobs avec vérification du statut
    log_info "Attente de la fin des jobs de tuiles..."
    
    # Vérification initiale pour éviter la boucle si le job est déjà terminé
    if ! squeue -j "$job_id" 2>/dev/null | grep -q "$job_id"; then
        log_warning "Job déjà terminé avant la boucle d'attente"
    else
        while squeue -j "$job_id" 2>/dev/null | grep -q "$job_id"; do
            echo -n "."
            sleep 30
        done
        echo ""
    fi
    
    # Vérification finale du statut
    job_status=$(sacct -j "$job_id" --format=State --noheader | tail -1)
    if [ "$job_status" = "COMPLETED" ]; then
        log_success "Tous les jobs de tuiles terminés avec succès"
    else
        log_warning "Jobs terminés avec statut : $job_status"
    fi
    
    # Nettoyage du fichier temporaire
    if [ -f ".step5_array_job_id" ]; then
        rm .step5_array_job_id
    fi
}

# Étape 3 : Fusion finale
merge_results() {
    log_info "Étape 3 : Fusion finale des résultats"
    
    # Vérification de la présence des fichiers de résultats
    sar_files=$(find "$HOME/scratch/output_V6/" -name "sar_*.parquet" -o -name "sar_*.rds" | wc -l)
    
    if [ "$sar_files" -eq 0 ]; then
        log_error "Aucun fichier de résultat de tuile trouvé"
        exit 1
    fi
    
    log_info "Fichiers de résultats trouvés : $sar_files"
    
    # Lancement de la fusion
    log_info "Lancement de la fusion finale..."
    if [ "${MAKE_TIFF:-false}" = "true" ]; then
        apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
            Rscript -e "Sys.setenv(MAKE_TIFF='true'); source('step5_merge_tiles.R')"
    else
        apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
            Rscript step5_merge_tiles.R
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Fusion finale terminée avec succès"
    else
        log_error "Échec de la fusion finale"
        exit 1
    fi
}

# Nettoyage des fichiers temporaires
cleanup() {
    log_info "Nettoyage des fichiers temporaires..."
    
    # Suppression des fichiers de résultats individuels (optionnel)
    if [ "${CLEANUP_TEMP:-false}" = "true" ]; then
        find "$HOME/scratch/output_V6/" -name "sar_*.parquet" -delete
        find "$HOME/scratch/output_V6/" -name "sar_*.rds" -delete
        log_success "Fichiers temporaires supprimés"
    else
        log_info "Fichiers temporaires conservés (CLEANUP_TEMP=false)"
    fi
}

# Fonction principale
main() {
    echo "🚀 Pipeline Step-5 Modulaire - Démarrage"
    echo "=========================================="
    
    # Vérification des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                export CLEANUP_TEMP=true
                log_warning "Mode nettoyage activé"
                shift
                ;;
            --make-tiff)
                export MAKE_TIFF=true
                log_warning "Génération GeoTIFF activée (+2.6 GB RAM)"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Option inconnue : $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Exécution des étapes
    check_environment
    generate_tiles
    launch_tile_jobs
    merge_results
    cleanup
    
    echo ""
    echo "🎉 Pipeline Step-5 Modulaire - Terminé avec succès !"
    echo "=================================================="
    echo ""
    echo "📁 Fichiers de sortie dans : $HOME/scratch/output_V6/"
    echo "   - fi_grid_*.parquet : Données tabulaires"
    echo "   - fi_grid_*.rds : Données R"
    echo "   - fi_1km_global_*.tif : Raster GeoTIFF (si terra disponible)"
    echo ""
    echo "📊 Pour vérifier les résultats :"
    echo "   ls -lh $HOME/scratch/output_V6/fi_*"
}

# Gestion des signaux
trap 'log_error "Interruption détectée - arrêt du pipeline"; exit 1' INT TERM

# Lancement
main "$@" 