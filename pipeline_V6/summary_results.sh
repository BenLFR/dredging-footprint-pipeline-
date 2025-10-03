#!/bin/bash

echo "📊 === RÉSUMÉ DES RÉSULTATS ÉTAPE 2 ==="
echo "Date: $(date)"
echo ""

# Définir le chemin absolu du dossier
RESULT_DIR="/home/benl/scratch/test_step1_final"

# Vérifier si le dossier existe
if [ ! -d "$RESULT_DIR" ]; then
    echo "❌ Dossier $RESULT_DIR non trouvé"
    exit 1
fi

# Créer un fichier temporaire pour stocker les résultats
TEMP_FILE=$(mktemp)

# Analyser chaque fichier clean.rds
for file in "$RESULT_DIR"/*_clean.rds; do
    if [ -f "$file" ]; then
        # Extraire le nom du navire du nom de fichier
        navire=$(basename "$file" | sed 's/navire_[0-9]*_\(.*\)_clean.rds/\1/')
        
        # Analyser le fichier avec R
        R --vanilla --slave -e "
        dt <- readRDS('$file')
        cat('$navire\t', nrow(dt), '\t', 
            sum(dt\$outlier_IF, na.rm=TRUE), '\t',
            round(100 * sum(dt\$outlier_IF, na.rm=TRUE) / nrow(dt), 2), '%\n')
        " >> "$TEMP_FILE"
    fi
done

# Afficher les résultats en tableau
echo "🚢 NAVIRE                    | OBSERVATIONS | OUTLIERS | % OUTLIERS"
echo "------------------------------------------------------------"
while IFS=$'\t' read -r navire obs outliers pct; do
    printf "%-25s | %11d | %8d | %8.2f%%\n" "$navire" "$obs" "$outliers" "$pct"
done < "$TEMP_FILE"

# Nettoyer
rm "$TEMP_FILE"

echo ""
echo "✅ Résumé terminé"
