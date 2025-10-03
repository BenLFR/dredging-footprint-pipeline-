#!/bin/bash
# Diagnostic complet du pipeline Step5

echo "=== DIAGNOSTIC COMPLET STEP5 ==="
date
echo ""

# 1. Vérification de l'environnement
echo "🔧 ENVIRONNEMENT :"
echo "   - PWD : $(pwd)"
echo "   - USER : $USER"
echo "   - HOME : $HOME"
echo ""

# 2. Vérification des modules
echo "📦 MODULES :"
module list 2>/dev/null | grep -E "(StdEnv|apptainer|gdal)" || echo "   Aucun module pertinent chargé"
echo ""

# 3. Test ogrinfo
echo "🗺️  TEST OGRINFO :"
if command -v ogrinfo &> /dev/null; then
    echo "   ✅ ogrinfo disponible : $(ogrinfo --version | head -1)"
    
    if [ -f "$HOME/scratch/output_V6/tiles_1000km.gpkg" ]; then
        echo "   ✅ Fichier tuiles trouvé"
        n_tiles=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "feature id" | wc -l)
        echo "   📊 Nombre de tuiles détectées : $n_tiles"
        
        if [ "$n_tiles" -eq 0 ]; then
            echo "   ⚠️  Aucune tuile trouvée avec 'feature id'"
            echo "   🔍 Test avec 'OGRFeature' :"
            n_tiles2=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "OGRFeature" | wc -l)
            echo "   📊 Nombre avec 'OGRFeature' : $n_tiles2"
            
            echo "   🔍 Test avec 'FID' :"
            n_tiles3=$(ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | grep "FID" | wc -l)
            echo "   📊 Nombre avec 'FID' : $n_tiles3"
            
            echo "   🔍 Affichage des 5 premières lignes :"
            ogrinfo -geom=no -q -al "$HOME/scratch/output_V6/tiles_1000km.gpkg" | head -10
        fi
    else
        echo "   ❌ Fichier tuiles manquant : $HOME/scratch/output_V6/tiles_1000km.gpkg"
    fi
else
    echo "   ❌ ogrinfo non disponible"
fi
echo ""

# 4. Vérification des fichiers existants
echo "📁 FICHIERS EXISTANTS :"
existing_files=$(ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | wc -l)
echo "   - Fichiers sar_*.parquet : $existing_files"
echo "   - Liste des 10 premiers :"
ls ~/scratch/output_V6/sar_*.parquet 2>/dev/null | head -10 | sed 's/.*\//   /'
echo ""

# 5. Test du script de job
echo "🧪 TEST SCRIPT JOB :"
if [ -f "step5_tile_job.sh" ]; then
    echo "   ✅ Script trouvé"
    if [ -x "step5_tile_job.sh" ]; then
        echo "   ✅ Script exécutable"
    else
        echo "   ⚠️  Script non exécutable"
        chmod +x step5_tile_job.sh
        echo "   ✅ Permissions ajoutées"
    fi
    
    # Test de lancement d'un job simple
    echo "   🚀 Test de lancement d'un job simple..."
    test_job_id=$(sbatch \
        --array=1 \
        --job-name=test_step5 \
        --output=test_%A_%a.out \
        --error=test_%A_%a.err \
        --time=1:00:00 \
        --mem=1G \
        step5_tile_job.sh 2>/dev/null | grep -o '[0-9]\+' || echo "")
    
    if [ -z "$test_job_id" ]; then
        echo "   ❌ Échec du lancement du job de test"
        echo "   🔍 Vérification des logs SLURM :"
        tail -5 test_*.out 2>/dev/null || echo "   Aucun log trouvé"
    else
        echo "   ✅ Job de test lancé (ID: $test_job_id)"
        echo "   ⏳ Attente de 10 secondes..."
        sleep 10
        
        if squeue -j $test_job_id 2>/dev/null | grep -q $test_job_id; then
            echo "   ⏳ Job encore en cours"
            scancel $test_job_id
            echo "   ✅ Job annulé"
        else
            echo "   ✅ Job terminé"
            echo "   📄 Log de sortie :"
            cat test_${test_job_id}_1.out 2>/dev/null || echo "   Aucun log de sortie"
            echo "   📄 Log d'erreur :"
            cat test_${test_job_id}_1.err 2>/dev/null || echo "   Aucun log d'erreur"
        fi
    fi
else
    echo "   ❌ Script non trouvé"
fi
echo ""

# 6. Vérification des ressources SLURM
echo "💻 RESSOURCES SLURM :"
echo "   - Jobs en cours :"
squeue -u $USER 2>/dev/null | head -5 || echo "   Aucun job en cours"
echo "   - Partitions disponibles :"
sinfo 2>/dev/null | head -5 || echo "   Impossible de récupérer les partitions"
echo ""

# 7. Test manuel d'une tuile
echo "🔬 TEST MANUEL TUILE 64 :"
if [ -f "step5_tile_worker.R" ]; then
    echo "   ✅ Script worker trouvé"
    echo "   🚀 Test direct avec apptainer..."
    
    timeout 60 apptainer exec --bind /scratch,/home --pwd $PWD "$HOME/scratch/rocker_geospatial_step5.sif" \
        Rscript step5_tile_worker.R 64
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Test réussi"
        if [ -f "$HOME/scratch/output_V6/sar_064.parquet" ]; then
            echo "   ✅ Fichier de sortie créé"
        else
            echo "   ⚠️  Aucun fichier de sortie créé"
        fi
    else
        echo "   ❌ Test échoué"
    fi
else
    echo "   ❌ Script worker non trouvé"
fi

echo ""
echo "=== FIN DIAGNOSTIC ===" 