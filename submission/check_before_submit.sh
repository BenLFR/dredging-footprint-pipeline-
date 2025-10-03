#!/bin/bash
# ==============================================================================
# Script de vérification avant soumission sur Beluga
# ==============================================================================

echo "=== VÉRIFICATION AVANT SOUMISSION SUR BELUGA ==="
echo "Date: $(date)"
echo "Utilisateur: $(whoami)"
echo "Nœud: $(hostname)"
echo ""

# Vérification 1: Module R
echo "1. Vérification du module R..."
if module load r/4.3.0 2>/dev/null; then
    echo "✓ Module R chargé avec succès"
    R_VERSION=$(R --version | head -1)
    echo "  Version: $R_VERSION"
else
    echo "✗ Erreur: Impossible de charger le module R"
    exit 1
fi

# Vérification 2: Répertoires
echo ""
echo "2. Vérification des répertoires..."
if [ -d "$HOME/scratch/AIS_data" ]; then
    AIS_FILES=$(ls -1 "$HOME/scratch/AIS_data"/*.csv 2>/dev/null | wc -l)
    echo "✓ Répertoire AIS_data existe avec $AIS_FILES fichiers CSV"
    if [ $AIS_FILES -eq 0 ]; then
        echo "⚠ ATTENTION: Aucun fichier CSV trouvé dans ~/scratch/AIS_data/"
    fi
else
    echo "✗ Répertoire ~/scratch/AIS_data n'existe pas"
    echo "  Créez-le avec: mkdir -p ~/scratch/AIS_data"
fi

if [ -d "$HOME/scratch/output" ]; then
    echo "✓ Répertoire output existe"
else
    echo "⚠ Répertoire ~/scratch/output n'existe pas (sera créé automatiquement)"
fi

# Vérification 3: Scripts R
echo ""
echo "3. Vérification des scripts..."
SCRIPT_NAME="Entrainement modele V5 tri années cluster.R"
if [ -f "$SCRIPT_NAME" ]; then
    echo "✓ Script principal trouvé: $SCRIPT_NAME"
    SCRIPT_SIZE=$(wc -l < "$SCRIPT_NAME")
    echo "  Taille: $SCRIPT_SIZE lignes"
else
    echo "✗ Script principal manquant: $SCRIPT_NAME"
    exit 1
fi

if [ -f "submit_beluga.sh" ]; then
    echo "✓ Script SLURM trouvé: submit_beluga.sh"
else
    echo "✗ Script SLURM manquant: submit_beluga.sh"
    exit 1
fi

# Vérification 4: Packages R essentiels
echo ""
echo "4. Vérification des packages R essentiels..."
ESSENTIAL_PACKAGES=("data.table" "lubridate" "mclust" "ranger" "pROC")
MISSING_PACKAGES=()

for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
    if Rscript -e "library($pkg)" >/dev/null 2>&1; then
        echo "✓ $pkg"
    else
        echo "✗ $pkg manquant"
        MISSING_PACKAGES+=($pkg)
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "⚠ Packages manquants: ${MISSING_PACKAGES[*]}"
    echo "  Exécutez d'abord: Rscript install_packages_beluga.R"
fi

# Vérification 5: Configuration SLURM
echo ""
echo "5. Vérification de la configuration SLURM..."
if grep -q "def-benl" submit_beluga.sh; then
    echo "⚠ N'oubliez pas de remplacer 'def-benl' par votre vrai compte"
fi

if grep -q "votre.email@example.com" submit_beluga.sh; then
    echo "⚠ N'oubliez pas de remplacer l'email par le vôtre"
fi

# Vérification 6: Espace disque
echo ""
echo "6. Vérification de l'espace disque..."
SCRATCH_USAGE=$(df -h "$HOME/scratch" | tail -1 | awk '{print $5}' | sed 's/%//')
echo "Utilisation de ~/scratch: ${SCRATCH_USAGE}%"
if [ $SCRATCH_USAGE -gt 80 ]; then
    echo "⚠ ATTENTION: Espace disque faible dans ~/scratch"
fi

# Résumé final
echo ""
echo "=== RÉSUMÉ ==="
if [ ${#MISSING_PACKAGES[@]} -eq 0 ] && [ -f "$SCRIPT_NAME" ] && [ -f "submit_beluga.sh" ]; then
    echo "✓ Prêt pour la soumission !"
    echo ""
    echo "Pour soumettre le job:"
    echo "  sbatch submit_beluga.sh"
    echo ""
    echo "Pour surveiller:"
    echo "  squeue -u $(whoami)"
else
    echo "✗ Des problèmes doivent être résolus avant la soumission"
    exit 1
fi

echo "Fin de la vérification: $(date)" 