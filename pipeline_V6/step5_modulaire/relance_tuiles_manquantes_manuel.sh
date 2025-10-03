#!/bin/bash
cd ~/R_scripts/pipeline_V6/step5_modulaire

echo "=== RELANCE MANUELLE DES TUILES MANQUANTES ==="

# Liste des tuiles manquantes identifiées
missing_tiles=(101 107 111 144 170 210 251 275 287 296 305 348 354 375 389 410 421 445 446 448 452 461 479 528 557 559 560 571 593 596 601 607)

echo "📋 Tuiles à traiter manuellement : ${missing_tiles[*]}"
echo "📊 Total : ${#missing_tiles[@]} tuiles"

# Traiter chaque tuile manquante manuellement
for tile in "${missing_tiles[@]}"; do
    echo "🔄 Traitement manuel tuile $tile..."
    
    # Charger les modules nécessaires
    module load StdEnv/2023 apptainer-suid/1.1 gdal
    
    # Exécuter le traitement
    apptainer exec ~/rocker_geospatial_step5.sif Rscript step5_tile_worker.R $tile
    
    # Vérifier que le fichier a été créé
    output_file="~/scratch/output_V6/sar_$(printf "%03d" $tile).parquet"
    if [ -f "$output_file" ]; then
        echo "✅ Tuile $tile traitée avec succès"
    else
        echo "❌ Échec tuile $tile"
    fi
    
    echo "---"
done

echo "✅ Traitement manuel terminé"
echo "📊 Vérification finale :"
cd ~/scratch/output_V6
echo " Fichiers sar_*.parquet : $(ls -1 sar_*.parquet 2>/dev/null | wc -l) / 648" 