#!/bin/bash
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  PIPELINE MODULAIRE (pipeline V6, cluster Rorqual)
# Orchestration complète du traitement par tuiles
# ────────────────────────────────────────────────────────────────────────────────

set -e  # Arrêt en cas d'erreur

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP5_MODULAIRE_DIR="$SCRIPT_DIR/step5_modulaire"
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
    
    if ! module list 2>/dev/null | grep -q "gdal"; then
        log_warning "Module gdal non chargé - chargement automatique"
        module load gdal
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
    apptainer exec --bind /scratch,/home "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript "$STEP5_MODULAIRE_DIR/step5_make_tiles.R"
    
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
        log_warning "ogrinfo non disponible - utilisation de la valeur par défaut (648)"
        n_tiles=648
    else
        n_tiles=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "feature id" | wc -l)
        if [ "$n_tiles" -eq 0 ]; then
            log_warning "ogrinfo n'a pas trouvé de tuiles - utilisation de la valeur par défaut (648)"
            n_tiles=648
        fi
    fi
    
    if [ "$n_tiles" -eq 0 ]; then
        log_error "Aucune tuile trouvée"
        exit 1
    fi
    
    log_info "Nombre de tuiles détectées : $n_tiles"
    
    # Détection des tuiles déjà traitées (reprise incrémentale)
    log_info "Vérification des tuiles déjà traitées..."
    missing_tiles=""
    completed_count=0
    
    for i in $(seq 1 $n_tiles); do
        output_file="$HOME/scratch/output_V6/sar_$(printf "%03d" $i).parquet"
        if [ -f "$output_file" ]; then
            ((completed_count++))
        else
            missing_tiles="$missing_tiles $i"
        fi
    done
    
    log_info "Tuiles déjà complétées : $completed_count/$n_tiles"
    
    if [ -z "$missing_tiles" ]; then
        log_success "Toutes les tuiles sont déjà traitées !"
        return 0
    fi
    
    # Création de la liste des tuiles manquantes pour SLURM
    missing_array=$(echo $missing_tiles | tr ' ' ',')
    log_info "Tuiles à traiter : $missing_array"
    
    # Vérification que le script de job existe
    if [ ! -f "$STEP5_MODULAIRE_DIR/step5_tile_job.sh" ]; then
        log_error "Script de job introuvable : $STEP5_MODULAIRE_DIR/step5_tile_job.sh"
        exit 1
    fi
    
    log_info "Script de job trouvé : $STEP5_MODULAIRE_DIR/step5_tile_job.sh"
    
    # Vérification des permissions
    if [ ! -x "$STEP5_MODULAIRE_DIR/step5_tile_job.sh" ]; then
        log_warning "Script non exécutable, ajout des permissions..."
        chmod +x "$STEP5_MODULAIRE_DIR/step5_tile_job.sh"
    fi
    
    # Test de lancement d'un job simple pour vérifier que tout fonctionne
    log_info "Test de lancement d'un job simple..."
    test_job_id=$(sbatch \
        --chdir="$SCRIPT_DIR" \
        --array=1 \
        --job-name=test_step5 \
        --output=/dev/null \
        --error=/dev/null \
        --time=1:00:00 \
        --mem=1G \
        "$STEP5_MODULAIRE_DIR/step5_tile_job.sh" 2>/dev/null | grep -o '[0-9]\+' || echo "")
    
    if [ -z "$test_job_id" ]; then
        log_error "Échec du test de lancement - vérifiez la configuration SLURM"
        exit 1
    else
        log_success "Test de lancement réussi (job ID: $test_job_id)"
        # Annuler le job de test
        scancel $test_job_id 2>/dev/null || true
    fi
    
    # Lancement array SLURM classique sur toutes les tuiles manquantes
    log_info "Lancement array SLURM classique sur toutes les tuiles manquantes"
    job_id=$(sbatch \
        --chdir="$SCRIPT_DIR" \
        --array=$missing_array \
        "$STEP5_MODULAIRE_DIR/step5_tile_job.sh" | grep -o '[0-9]\+')
    echo "$job_id" > .step5_array_job_id
    
    if [ $? -eq 0 ]; then
        log_success "Array-job lancé avec l'ID : $job_id"
        echo "$job_id" > .step5_array_job_id
    else
        log_error "Échec du lancement de l'array-job"
        exit 1
    fi
    
    # Attente de la fin des jobs
    log_info "Attente de la fin des jobs de tuiles..."
    while squeue -j "$job_id" 2>/dev/null | grep -q "$job_id"; do
        echo -n "."
        sleep 30
    done
    echo ""
    rm .step5_array_job_id
    
    log_success "Tous les jobs de tuiles terminés"
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
    apptainer exec --bind /scratch,/home "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript "$SCRIPT_DIR/step5_merge_tiles.R"
    
    if [ $? -eq 0 ]; then
        log_success "Fusion finale terminée avec succès"
    else
        log_error "Échec de la fusion finale"
        exit 1
    fi
}

# Diagnostic de l'état du pipeline
diagnostic() {
    log_info "Diagnostic de l'état du pipeline..."
    
    # Comptage des tuiles totales
    if command -v ogrinfo &> /dev/null; then
        if [ -f "$HOME/scratch/output_V6/tiles_1000km.gpkg" ]; then
            n_tiles=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "feature id" | wc -l)
            if [ "$n_tiles" -eq 0 ]; then
                log_warning "ogrinfo n'a pas trouvé de tuiles - utilisation de la valeur par défaut (648)"
                n_tiles=648
            fi
        else
            log_warning "Fichier tiles_1000km.gpkg non trouvé - utilisation de la valeur par défaut (648)"
            n_tiles=648
        fi
    else
        log_warning "ogrinfo non disponible - utilisation de la valeur par défaut (648)"
        n_tiles=648
    fi
    
    # Comptage des fichiers de sortie
    completed_files=$(find "$HOME/scratch/output_V6/" -name "sar_*.parquet" -o -name "sar_*.rds" | wc -l)
    
    # Calcul du pourcentage
    if [ "$n_tiles" -gt 0 ]; then
        percentage=$(echo "scale=1; $completed_files * 100 / $n_tiles" | bc 2>/dev/null || echo "N/A")
    else
        percentage="N/A"
    fi
    
    log_info "État du pipeline :"
    log_info "   - Tuiles totales : $n_tiles"
    log_info "   - Tuiles complétées : $completed_files"
    log_info "   - Progression : $percentage%"
    
    # Liste des tuiles manquantes (si moins de 20)
    missing_count=$((n_tiles - completed_files))
    if [ "$missing_count" -gt 0 ] && [ "$missing_count" -le 20 ]; then
        log_info "   - Tuiles manquantes :"
        for i in $(seq 1 $n_tiles); do
            output_file="$HOME/scratch/output_V6/sar_$(printf "%03d" $i).parquet"
            if [ ! -f "$output_file" ]; then
                echo "     Tuile $i"
            fi
        done
    elif [ "$missing_count" -gt 20 ]; then
        log_info "   - Tuiles manquantes : $missing_count (trop nombreuses pour lister)"
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
    if [ "$1" = "--cleanup" ]; then
        export CLEANUP_TEMP=true
        log_warning "Mode nettoyage activé"
    elif [ "$1" = "--diagnostic" ]; then
        check_environment
        diagnostic
        exit 0
    fi
    
    # Exécution des étapes
    check_environment
    diagnostic  # Diagnostic avant lancement
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