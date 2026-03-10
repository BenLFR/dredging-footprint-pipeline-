#!/bin/bash
# Verify GRIT cluster configuration for Step 0
# Usage: bash deploy/check_grit_setup.sh

SSH_CONFIG="$HOME/.ssh/config_grit"
REMOTE="grit"

echo "=========================================="
echo " VÉRIFICATION CONFIGURATION GRIT"
echo "=========================================="
echo ""

echo "1⃣  Test connexion GRIT..."
if ssh -F "$SSH_CONFIG" "$REMOTE" "echo 'OK'" &>/dev/null; then
    echo "    Connexion réussie"
else
    echo "    Connexion échouée"
    exit 1
fi
echo ""

echo "2⃣  Vérification structure répertoires..."
ssh -F "$SSH_CONFIG" "$REMOTE" "
    echo '    Répertoires:'
    ls -ld ~/ais-pipeline/pipeline_V6 2>/dev/null && echo '       ~/ais-pipeline/pipeline_V6' || echo '       ~/ais-pipeline/pipeline_V6 manquant'
    ls -ld ~/scratch/AIS_data 2>/dev/null && echo '       ~/scratch/AIS_data' || echo '       ~/scratch/AIS_data manquant'
    ls -ld ~/scratch/output_V6 2>/dev/null && echo '       ~/scratch/output_V6' || echo '       ~/scratch/output_V6 manquant'
"
echo ""

echo "3⃣  Vérification scripts Step 0..."
ssh -F "$SSH_CONFIG" "$REMOTE" "
    echo '    Scripts:'
    if [ -f ~/ais-pipeline/pipeline_V6/step0_core_window_enhanced.R ]; then
        size=\$(stat -f%z ~/ais-pipeline/pipeline_V6/step0_core_window_enhanced.R 2>/dev/null || stat -c%s ~/ais-pipeline/pipeline_V6/step0_core_window_enhanced.R 2>/dev/null)
        echo \"       step0_core_window_enhanced.R (\${size} bytes)\"
    else
        echo '       step0_core_window_enhanced.R manquant'
    fi

    if [ -f ~/ais-pipeline/pipeline_V6/step0_window_select_grit.sh ]; then
        size=\$(stat -f%z ~/ais-pipeline/pipeline_V6/step0_window_select_grit.sh 2>/dev/null || stat -c%s ~/ais-pipeline/pipeline_V6/step0_window_select_grit.sh 2>/dev/null)
        echo \"       step0_window_select_grit.sh (\${size} bytes)\"
    else
        echo '       step0_window_select_grit.sh manquant'
    fi
"
echo ""

echo "4⃣  Vérification données AIS..."
ssh -F "$SSH_CONFIG" "$REMOTE" "
    if [ -f ~/scratch/AIS_data/benjamin2.csv ]; then
        size=\$(stat -f%z ~/scratch/AIS_data/benjamin2.csv 2>/dev/null || stat -c%s ~/scratch/AIS_data/benjamin2.csv 2>/dev/null)
        size_mb=\$((size / 1024 / 1024))
        echo \"    benjamin2.csv (\${size_mb} MB)\"
    else
        echo '    benjamin2.csv manquant'
        echo '     Utilisez: scp -F ~/.ssh/config_grit AIS_with_lithology_clean.csv grit:~/scratch/AIS_data/benjamin2.csv'
    fi
"
echo ""

echo "5⃣  Vérification R..."
ssh -F "$SSH_CONFIG" "$REMOTE" "
    if command -v R &>/dev/null; then
        R --version | head -1
        echo '    R disponible'
    else
        echo '     R non trouvé dans PATH - vérifier les modules'
    fi
"
echo ""

echo "6⃣  Vérification librairie R..."
ssh -F "$SSH_CONFIG" "$REMOTE" "
    if [ -d ~/R/library ]; then
        count=\$(ls ~/R/library 2>/dev/null | wc -l)
        echo \"    ~/R/library existe (\${count} packages)\"
    else
        echo '     ~/R/library non trouvé - créer avec: mkdir -p ~/R/library'
    fi
"
echo ""

echo "=========================================="
echo "📋 RÉSUMÉ"
echo "=========================================="
ssh -F "$SSH_CONFIG" "$REMOTE" "
    all_ok=true

    [ -f ~/ais-pipeline/pipeline_V6/step0_core_window_enhanced.R ] || all_ok=false
    [ -f ~/ais-pipeline/pipeline_V6/step0_window_select_grit.sh ] || all_ok=false
    [ -f ~/scratch/AIS_data/benjamin2.csv ] || all_ok=false
    [ -d ~/R/library ] || all_ok=false

    if \$all_ok; then
        echo ' Configuration complète - Prêt à lancer Step 0'
        echo ''
        echo 'Commandes pour lancer:'
        echo '  ssh -F ~/.ssh/config_grit grit'
        echo '  cd ~/ais-pipeline/pipeline_V6'
        echo '  sbatch step0_window_select_grit.sh'
    else
        echo '  Configuration incomplète - Voir détails ci-dessus'
    fi
"
echo ""
