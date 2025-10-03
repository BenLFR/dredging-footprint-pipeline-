#!/bin/bash

echo "📥 TÉLÉCHARGEMENT LOGS DE DÉBOGAGE"
echo "=================================="

# Créer dossier local pour les logs
mkdir -p logs_debug
cd logs_debug

echo "🔍 Recherche des logs sur Beluga..."

# Lister les fichiers de log disponibles
ssh benl@beluga.alliancecan.ca "ls -la debug*.log errors*.log *output*.log 2>/dev/null" || echo "Aucun log trouvé"

echo ""
echo "📥 Téléchargement des logs..."

# Télécharger tous les logs de debug
scp "benl@beluga.alliancecan.ca:debug*.log" . 2>/dev/null && echo "✅ Logs debug téléchargés"
scp "benl@beluga.alliancecan.ca:errors*.log" . 2>/dev/null && echo "✅ Logs erreurs téléchargés" 
scp "benl@beluga.alliancecan.ca:*output*.log" . 2>/dev/null && echo "✅ Logs output téléchargés"

echo ""
echo "📄 LOGS TÉLÉCHARGÉS DANS ./logs_debug/:"
ls -la

echo ""
echo "🔍 ANALYSE RAPIDE DES ERREURS:"
echo "=============================="

for log_file in *.log; do
    if [ -f "$log_file" ]; then
        echo ""
        echo "📋 $log_file:"
        echo "-------------"
        
        # Chercher les erreurs
        grep -i "error\|erreur\|failed\|échec" "$log_file" | head -5
        
        # Chercher les warnings
        grep -i "warning\|attention" "$log_file" | head -3
        
        # Montrer la fin du fichier
        echo "... (fin du log) ..."
        tail -3 "$log_file"
    fi
done

echo ""
echo "✅ Analyse terminée. Consultez les fichiers .log pour plus de détails." 