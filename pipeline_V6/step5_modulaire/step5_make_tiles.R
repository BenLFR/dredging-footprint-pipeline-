#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  GÉNÉRATION DES TUILES MONDIALES (pipeline V6, cluster Rorqual)
# Découpe l'emprise mondiale en tuiles carrées pour traitement modulaire
# ────────────────────────────────────────────────────────────────────────────────

library(sf)

# Chargement des constantes partagées
script_dir <- getwd()
source(file.path(script_dir, "constants.R"))

cat("🔧 Génération des tuiles mondiales pour Step-5\n")

# Paramètres de tuilage (depuis constants.R)
cell_km   <- CELL_KM   # taille de tuile en km
crs_eq    <- CRS_EQUIVALENT   # CRS équivalent (mètres)

# Emprise mondiale en mètres (EPSG:6933) - depuis constants.R
world_bb  <- st_as_sfc(st_bbox(c(xmin=WORLD_XMIN, ymin=WORLD_YMIN,
                                 xmax=WORLD_XMAX, ymax=WORLD_YMAX),
                               crs=crs_eq))

cat("📐 Emprise mondiale :\n")
cat("   - X: ", format(world_bb[[1]][[1]][1], scientific=FALSE), " à ", 
    format(world_bb[[1]][[1]][3], scientific=FALSE), " m\n")
cat("   - Y: ", format(world_bb[[1]][[1]][2], scientific=FALSE), " à ", 
    format(world_bb[[1]][[1]][4], scientific=FALSE), " m\n")

# Génération de la grille de tuiles
cat("🔲 Génération de la grille de tuiles...\n")
tiles_sf  <- st_make_grid(world_bb,
                          cellsize = cell_km*1000,  # conversion km → m
                          what = "polygons",
                          square = TRUE) %>%
             st_sf(tile_id = seq_along(.))

# Ajout des métadonnées de tuile
tiles_sf$tile_size_km <- cell_km
tiles_sf$crs <- "EPSG:6933"

# Calcul des statistiques
n_tiles <- nrow(tiles_sf)
cat("✅ Tuiles générées :", n_tiles, "\n")
cat("   - Taille par tuile :", cell_km, "×", cell_km, "km\n")
cat("   - Surface totale :", format(n_tiles * cell_km^2 * 1e6, scientific=FALSE), "km²\n")

# Sauvegarde
output_file <- "~/scratch/output_V6/tiles_1000km.gpkg"
cat("💾 Sauvegarde dans :", output_file, "\n")

st_write(tiles_sf, output_file, delete_dsn = TRUE, quiet = TRUE, 
         config_options = c(GPKG_ZIP="YES"))

# Vérification
if(file.exists(output_file)) {
  file_info <- file.info(output_file)
  cat("✅ Fichier créé :", basename(output_file), "\n")
  cat("   - Taille :", format(file_info$size, scientific=FALSE), "octets\n")
  cat("   - Date :", format(file_info$mtime, "%Y-%m-%d %H:%M:%S"), "\n")
} else {
  stop("❌ Erreur lors de la création du fichier")
}

# Affichage des premières tuiles pour vérification
cat("\n📋 Aperçu des tuiles :\n")
print(head(tiles_sf[, c("tile_id", "tile_size_km")]))

cat("\n🎯 Prochaines étapes :\n")
cat("   1. Vérifier le nombre de tuiles : ogrinfo -geom=no -q -al", output_file, "| grep 'feature id' | wc -l\n")
cat("   2. Lancer l'array-job : sbatch --array=1-", n_tiles, " step5_tile_job.sh\n")
cat("   3. Monitorer : squeue -u $USER | grep step5_tile\n")

cat("\n✅ Génération des tuiles terminée !\n") 