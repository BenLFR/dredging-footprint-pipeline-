#!/bin/bash
# =============================================================================
# EXTRACTION DES RESULTATS STEP 2
# =============================================================================
# Telecharge les logs depuis GRIT et extrait les statistiques

set -e

if [ -z "$1" ]; then
    echo "Usage: bash extract_step2_results.sh <process_job_id> [split_job_id]"
    echo "Exemple: bash extract_step2_results.sh 13289 12990"
    exit 1
fi

PROCESS_JOB_ID=$1
SPLIT_JOB_ID=$2

echo "============================================================================"
echo "EXTRACTION DES STATISTIQUES STEP 2"
echo "============================================================================"
echo ""
echo "Process Job ID: $PROCESS_JOB_ID"
if [ -n "$SPLIT_JOB_ID" ]; then
    echo "Split Job ID: $SPLIT_JOB_ID"
fi
echo ""

# Creer le dossier logs s'il n'existe pas
mkdir -p logs

# Telecharger les logs depuis GRIT
echo "============================================================================"
echo "ETAPE 1: Telechargement des logs depuis GRIT"
echo "============================================================================"
echo ""

scp -F ~/.ssh/config_grit "grit:~/ais-pipeline/pipeline_V6/logs/step2_process_${PROCESS_JOB_ID}_*.out" "logs/" || {
    echo ""
    echo "[ERREUR] Echec du telechargement des logs"
    echo "Verifiez:"
    echo "  1. Votre connexion SSH a GRIT"
    echo "  2. Que le Job ID est correct"
    echo "  3. Que les logs existent sur GRIT"
    exit 1
}

echo ""
echo "[OK] Logs telecharges avec succes"
echo ""

# Extraire les statistiques
echo "============================================================================"
echo "ETAPE 2: Extraction des statistiques"
echo "============================================================================"
echo ""

if [ -n "$SPLIT_JOB_ID" ]; then
    Rscript scripts_principaux/extract_step2_stats.R "$PROCESS_JOB_ID" "$SPLIT_JOB_ID"
else
    Rscript scripts_principaux/extract_step2_stats.R "$PROCESS_JOB_ID"
fi

echo ""
echo "============================================================================"
echo "EXTRACTION TERMINEE"
echo "============================================================================"
echo ""
echo "Fichiers generes:"
echo "  - step2_statistics_${PROCESS_JOB_ID}.csv"
echo ""
