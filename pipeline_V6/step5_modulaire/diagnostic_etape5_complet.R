#!/usr/bin/env Rscript
# Diagnostic complet de l'étape 5 - Problème de lancement

library(sf)
library(data.table)
library(yaml)

cat('=== DIAGNOSTIC COMPLET ÉTAPE 5 ===\n')
cat('Date:', format(Sys.time(), '%Y-%m-%d %H:%M:%S'), '\n\n')

# 1. Vérification des données d'entrée
cat('📁 1. VÉRIFICATION DES DONNÉES D\'ENTRÉE\n')
cat('=====================================\n')

# Trouver le fichier de données le plus récent
data_files <- list.files('~/scratch/output_V6/', pattern='AIS_with_lithology_clean_.*\\.rds', full.names=TRUE)
if(length(data_files) == 0) {
    stop("❌ Aucun fichier AIS_with_lithology_clean trouvé")
}
latest_file <- data_files[order(file.info(data_files)$mtime, decreasing=TRUE)[1]]
cat('✅ Fichier de données :', basename(latest_file), '\n')
cat('📊 Taille :', round(file.size(latest_file)/1024/1024, 1), 'MB\n')

# Charger les données
cat('📖 Chargement des données...\n')
dt <- readRDS(latest_file)
cat('✅ Données chargées :', nrow(dt), 'lignes\n')
cat('📋 Colonnes disponibles :', paste(names(dt), collapse=', '), '\n')

# Vérifier les colonnes essentielles
required_cols <- c('Lon', 'Lat', 'Dragage_flag', 'ssvid')
missing_cols <- setdiff(required_cols, names(dt))
if(length(missing_cols) > 0) {
    cat('❌ Colonnes manquantes :', paste(missing_cols, collapse=', '), '\n')
} else {
    cat('✅ Toutes les colonnes requises présentes\n')
}

# Statistiques des données
cat('\n📊 Statistiques des données :\n')
cat('   - Pings dragage (Dragage_flag=1) :', sum(dt$Dragage_flag == 1, na.rm=TRUE), '\n')
cat('   - Pings avec coordonnées :', sum(!is.na(dt$Lon) & !is.na(dt$Lat)), '\n')
cat('   - Navires uniques :', length(unique(dt$ssvid)), '\n')
cat('   - Plage longitude :', range(dt$Lon, na.rm=TRUE), '\n')
cat('   - Plage latitude :', range(dt$Lat, na.rm=TRUE), '\n')

# 2. Vérification des tuiles
cat('\n🗺️ 2. VÉRIFICATION DES TUILES\n')
cat('============================\n')

tiles_path <- '~/scratch/output_V6/tiles_1000km.gpkg'
if(!file.exists(tiles_path)) {
    stop("❌ Fichier de tuiles manquant :", tiles_path)
}

tiles <- st_read(tiles_path, quiet=TRUE)
cat('✅ Tuiles chargées :', nrow(tiles), 'tuiles\n')
cat('📋 CRS :', st_crs(tiles)$input, '\n')

# Vérifier la projection
if(st_crs(tiles)$input != "EPSG:6933") {
    cat('⚠️  Attention : CRS différent de EPSG:6933\n')
}

# 3. Test de quelques tuiles spécifiques
cat('\n🧪 3. TEST DE TUILES SPÉCIFIQUES\n')
cat('===============================\n')

# Tuiles qui ont échoué dans le diagnostic précédent
test_tiles <- c(1, 64, 306, 307, 342, 343)

for(tile_id in test_tiles) {
    cat('\n--- Test tuile', tile_id, '---\n')
    
    if(tile_id > nrow(tiles)) {
        cat('❌ Tuile', tile_id, 'n\'existe pas (max:', nrow(tiles), ')\n')
        next
    }
    
    # Bounding box de la tuile
    tile_bb <- tiles[tile_id,]
    bbox <- st_bbox(tile_bb)
    cat('📐 Bbox tuile :', paste(round(bbox, 0), collapse=' '), '\n')
    
    # Buffer de 50km
    buffer_m <- 50000
    buf_bbox <- bbox + c(-buffer_m, -buffer_m, buffer_m, buffer_m)
    cat('📐 Bbox avec buffer 50km :', paste(round(buf_bbox, 0), collapse=' '), '\n')
    
    # Filtrer les données dans cette zone
    in_tile <- dt[!is.na(Lon) & !is.na(Lat) & 
                  Lon >= buf_bbox['xmin'] & Lon <= buf_bbox['xmax'] & 
                  Lat >= buf_bbox['ymin'] & Lat <= buf_bbox['ymax']]
    
    cat('📍 Pings dans la zone :', nrow(in_tile), '\n')
    
    if(nrow(in_tile) > 0) {
        dredge_in_tile <- in_tile[Dragage_flag == 1]
        cat('🚢 Pings dragage dans la zone :', nrow(dredge_in_tile), '\n')
        
        if(nrow(dredge_in_tile) > 0) {
            cat('✅ Tuile', tile_id, 'contient du dragage\n')
        } else {
            cat('⚠️  Tuile', tile_id, 'pas de dragage\n')
        }
    } else {
        cat('❌ Tuile', tile_id, 'aucun ping\n')
    }
}

# 4. Vérification des fichiers de configuration
cat('\n⚙️ 4. VÉRIFICATION DES FICHIERS DE CONFIGURATION\n')
cat('==============================================\n')

# Paramètres f_i
fi_params_path <- '~/scratch/configuration/fi_parameters.yaml'
if(file.exists(fi_params_path)) {
    cat('✅ Fichier fi_parameters.yaml trouvé\n')
    fi_params <- read_yaml(fi_params_path)
    cat('📋 Paramètres :', paste(names(fi_params), collapse=', '), '\n')
} else {
    cat('❌ Fichier fi_parameters.yaml manquant\n')
}

# Specs navires
ship_specs_path <- '~/scratch/configuration/ship_specs_clean.yaml'
if(file.exists(ship_specs_path)) {
    cat('✅ Fichier ship_specs_clean.yaml trouvé\n')
    ship_specs <- read_yaml(ship_specs_path)
    cat('📋 Nombre de navires :', length(ship_specs$ship_specs), '\n')
} else {
    cat('❌ Fichier ship_specs_clean.yaml manquant\n')
}

# 5. Test du script worker
cat('\n🔧 5. TEST DU SCRIPT WORKER\n')
cat('==========================\n')

worker_script <- 'step5_tile_worker.R'
if(file.exists(worker_script)) {
    cat('✅ Script worker trouvé\n')
    
    # Lire les premières lignes pour vérifier
    worker_lines <- readLines(worker_script, n=20)
    cat('📄 Premières lignes du script :\n')
    cat(paste('   ', worker_lines, collapse='\n'), '\n')
} else {
    cat('❌ Script worker manquant\n')
}

# 6. Vérification des fichiers existants
cat('\n📁 6. VÉRIFICATION DES FICHIERS EXISTANTS\n')
cat('========================================\n')

existing_files <- list.files('~/scratch/output_V6/', pattern='sar_.*\\.parquet', full.names=TRUE)
cat('📊 Fichiers sar_*.parquet existants :', length(existing_files), '\n')

if(length(existing_files) > 0) {
    cat('📅 Dates des 5 derniers fichiers :\n')
    file_info <- file.info(existing_files)
    recent_files <- existing_files[order(file_info$mtime, decreasing=TRUE)[1:5]]
    for(f in recent_files) {
        cat('   ', basename(f), ':', format(file_info[f,]$mtime, '%Y-%m-%d %H:%M:%S'), '\n')
    }
}

# 7. Recommandations
cat('\n💡 7. RECOMMANDATIONS\n')
cat('===================\n')

cat('🔍 Problèmes identifiés :\n')
cat('   1. Les jobs SLURM échouent en 53 secondes\n')
cat('   2. Aucun log SLURM n\'est créé\n')
cat('   3. Le compte SLURM peut être incorrect\n')
cat('   4. Les ressources demandées peuvent être trop élevées\n\n')

cat('🚀 Solutions proposées :\n')
cat('   1. Vérifier le compte SLURM : sacctmgr show user $USER\n')
cat('   2. Réduire les ressources : --mem=16G --cpus-per-task=2\n')
cat('   3. Tester avec une seule tuile : sbatch --array=1 step5_tile_job.sh\n')
cat('   4. Vérifier les logs : squeue -j <job_id>\n')

cat('\n=== FIN DIAGNOSTIC ===\n') 