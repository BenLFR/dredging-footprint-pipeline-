library(sf)
library(data.table)

cat('=== DIAGNOSTIC COMPLET DES TUILES AVEC DRAGAGE ===\n')

# Chemins
tiles_path <- '~/scratch/output_V6/tiles_1000km.gpkg'
output_csv <- '~/scratch/output_V6/tuiles_dragage_bbox.csv'
output_png <- '~/scratch/output_V6/tuiles_dragage_map.png'

# Charger les données (utiliser le fichier le plus récent avec lithologie)
data_files <- list.files('~/scratch/output_V6/', pattern='AIS_with_lithology_clean_.*\\.rds', full.names=TRUE)
if(length(data_files) == 0) {
    stop("❌ Aucun fichier AIS_with_lithology_clean trouvé")
}
latest_file <- data_files[order(file.info(data_files)$mtime, decreasing=TRUE)[1]]
cat('📁 Utilisation du fichier le plus récent :', basename(latest_file), '\n')
dt <- readRDS(latest_file)
tiles <- st_read(tiles_path, quiet=TRUE)

# Trouver les pings de dragage
dredge <- dt[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
cat('Total pings dragage avec coordonnées:', nrow(dredge), '\n')
cat('Plage Lon dragage:', range(dredge$Lon), '\n')
cat('Plage Lat dragage:', range(dredge$Lat), '\n')

# Convertir en sf pour test spatial
dredge_sf <- st_as_sf(dredge, coords=c('Lon','Lat'), crs=4326)

# Tester toutes les tuiles avec différents buffers
buffers <- c(2000, 50000, 100000)  # 2km, 50km, 100km

for(buffer_m in buffers) {
    cat('\n--- Test avec buffer de', buffer_m/1000, 'km ---\n')
    
    tiles_with_dredge <- c()
    total_pings_found <- 0
    
    for(i in 1:nrow(tiles)) {
        tile_bb <- tiles[i,]
        buf_bb <- st_as_sfc(st_bbox(tile_bb) + c(-buffer_m,-buffer_m,buffer_m,buffer_m))
        buf_bbox <- st_bbox(buf_bb)
        
        in_tile <- dredge[Lon >= buf_bbox['xmin'] & Lon <= buf_bbox['xmax'] & 
                         Lat >= buf_bbox['ymin'] & Lat <= buf_bbox['ymax']]
        
        if(nrow(in_tile) > 0) {
            tiles_with_dredge <- c(tiles_with_dredge, i)
            total_pings_found <- total_pings_found + nrow(in_tile)
        }
    }
    
    cat('Tuiles avec dragage:', length(tiles_with_dredge), '/', nrow(tiles), 
        '(', round(100*length(tiles_with_dredge)/nrow(tiles), 1), '%)\n')
    cat('Total pings capturés:', total_pings_found, '\n')
    
    if(length(tiles_with_dredge) > 0) {
        cat('Premières tuiles avec dragage:', paste(head(tiles_with_dredge), collapse=', '), '\n')
        cat('Dernières tuiles avec dragage:', paste(tail(tiles_with_dredge), collapse=', '), '\n')
        
        # Si on trouve des tuiles, on les analyse en détail
        if(buffer_m == 50000) {  # On garde les résultats du buffer 50km
            drag_tiles <- tiles_with_dredge
        }
    }
}

# Analyse détaillée des tuiles avec dragage
if(exists('drag_tiles') && length(drag_tiles) > 0) {
    cat('\n--- ANALYSE DÉTAILLÉE DES TUILES AVEC DRAGAGE ---\n')
    
    cat('\n1. Bounding box de chaque tuile (projection actuelle) ---\n')
    for(i in drag_tiles) {
        bb <- st_bbox(tiles[i,])
        cat(sprintf("Tuile %d : xmin=%.1f  ymin=%.1f  xmax=%.1f  ymax=%.1f (mètres)\n", 
            i, bb$xmin, bb$ymin, bb$xmax, bb$ymax))
    }
    
    cat('\n2. Coordonnées géographiques (degrés) ---\n')
    tiles_ll <- st_transform(tiles[drag_tiles,], 4326)
    for(j in 1:length(drag_tiles)) {
        i <- drag_tiles[j]
        bb <- st_bbox(tiles_ll[j,])
        cat(sprintf("Tuile %d : lon_min=%.4f lat_min=%.4f  lon_max=%.4f lat_max=%.4f\n",
            i, bb$xmin, bb$ymin, bb$xmax, bb$ymax))
    }
    
    cat('\n3. Sauvegarde CSV des coordonnées géographiques ---\n')
    df_bbox <- data.frame(
        tile_id = drag_tiles,
        lon_min = sapply(1:length(drag_tiles), function(j) st_bbox(tiles_ll[j,])$xmin),
        lat_min = sapply(1:length(drag_tiles), function(j) st_bbox(tiles_ll[j,])$ymin),
        lon_max = sapply(1:length(drag_tiles), function(j) st_bbox(tiles_ll[j,])$xmax),
        lat_max = sapply(1:length(drag_tiles), function(j) st_bbox(tiles_ll[j,])$ymax)
    )
    write.csv(df_bbox, file=output_csv, row.names=FALSE)
    cat('CSV exporté :', output_csv, '\n')
    
    cat('\n4. Génération d\'une image PNG de la grille ---\n')
    png(output_png, width=1200, height=600)
    plot(st_geometry(tiles), border='grey', lwd=0.7, main='Tuiles avec dragage détecté')
    plot(st_geometry(tiles[drag_tiles,]), border='red', col=rgb(1,0,0,0.2), lwd=3, add=TRUE)
    text(st_coordinates(st_centroid(tiles[drag_tiles,])), labels=drag_tiles, col='blue', cex=1.2, pos=3)
    dev.off()
    cat('PNG exporté :', output_png, '\n')
    
    # Test spécifique de quelques tuiles
    cat('\n5. Test détaillé de quelques tuiles ---\n')
    test_tiles <- head(drag_tiles, 5)  # Premières 5 tuiles avec dragage
    
    for(tile_id in test_tiles) {
        tile_bb <- tiles[tile_id,]
        buf_bb <- st_as_sfc(st_bbox(tile_bb) + c(-50000,-50000,50000,50000))
        buf_bbox <- st_bbox(buf_bb)
        
        in_tile <- dredge[Lon >= buf_bbox['xmin'] & Lon <= buf_bbox['xmax'] & 
                         Lat >= buf_bbox['ymin'] & Lat <= buf_bbox['ymax']]
        
        cat('Tuile', tile_id, ':', nrow(in_tile), 'pings dragage\n')
        if(nrow(in_tile) > 0) {
            cat('  Coordonnées:', range(in_tile$Lon), range(in_tile$Lat), '\n')
        }
    }
    
} else {
    cat('\n❌ AUCUNE TUILE NE CONTIENT DE DRAGAGE !\n')
    cat('Vérifiez les données de dragage dans le fichier flagOK.\n')
}

cat('\n=== FIN DU DIAGNOSTIC ===\n') 