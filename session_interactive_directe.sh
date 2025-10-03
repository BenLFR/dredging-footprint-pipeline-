#!/bin/bash

echo "🎯 SESSION INTERACTIVE DIRECTE - Beluga"
echo "======================================"

# Configuration
SCRIPT_NAME="Entrainement modele V5 tri années cluster_NO_SF.R"
LOG_FILE="session_directe_$(date +%Y%m%d_%H%M%S).log"

echo "📝 Logs sauvegardés dans: $LOG_FILE"
echo "🕐 Temps: 4h | CPUs: 8 | RAM: 24G"
echo ""
echo "🚀 Lancement de la session interactive..."
echo "⏳ Attente d'allocation des ressources..."
echo ""

# Lancer session interactive avec script automatique
salloc --time=4:00:00 --cpus-per-task=8 --mem=24G --account=def-wailung bash -c "
    echo '🎉 Session interactive obtenue !'
    echo 'Node: \$SLURMD_NODENAME'
    echo 'Job ID: \$SLURM_JOB_ID'
    echo 'CPUs: \$SLURM_CPUS_PER_TASK'
    echo 'Mémoire: \$(free -h | grep Mem | awk \"{print \\\$2}\")'
    echo ''
    
    # Charger R
    echo '🔧 Chargement du module R...'
    module load r/4.5.0
    
    # Aller au répertoire
    cd ~/R_scripts
    echo '📁 Répertoire: \$(pwd)'
    
    # Vérifier le script
    if [ ! -f \"$SCRIPT_NAME\" ]; then
        echo '❌ Script non trouvé: $SCRIPT_NAME'
        exit 1
    fi
    
    echo '✅ Script trouvé'
    echo ''
    echo '🔥 LANCEMENT DU SCRIPT AVEC LOGS EN DIRECT'
    echo '=========================================='
    echo ''
    
    # Lancer avec logs en direct ET sauvegarde
    Rscript \"$SCRIPT_NAME\" 2>&1 | tee ~/$LOG_FILE
    
    EXIT_CODE=\${PIPESTATUS[0]}
    echo ''
    echo '=========================================='
    if [ \$EXIT_CODE -eq 0 ]; then
        echo '✅ Script terminé avec SUCCÈS !'
    else
        echo '❌ Script échoué (code: '\$EXIT_CODE')'
    fi
    echo '📝 Logs complets dans: ~/$LOG_FILE'
    echo '🏁 Session terminée'
"

echo ""
echo "🏁 Session interactive terminée" 