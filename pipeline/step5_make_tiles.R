#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  GLOBAL TILE GENERATION (pipeline V6, cluster Rorqual)
# Splits the global extent into square tiles for modular processing
# ────────────────────────────────────────────────────────────────────────────────

library(sf)

# Load shared constants
script_dir <- getwd()
source(file.path(script_dir, "constants.R"))

cat(" Génération des tuiles mondiales pour Step-5\n")

# Tiling parameters (from constants.R)
cell_km   <- CELL_KM   # taille de tuile en km
crs_eq    <- CRS_EQUIVALENT   # equivalent CRS (metres)

# Global extent in metres (EPSG:6933) - from constants.R
world_bb  <- st_as_sfc(st_bbox(c(xmin=WORLD_XMIN, ymin=WORLD_YMIN,
                                 xmax=WORLD_XMAX, ymax=WORLD_YMAX),
                               crs=st_crs(crs_eq)))

# Affichage robuste de l'emprise
bb <- st_bbox(world_bb)
cat("📐 Emprise mondiale :\n")
cat("   - X: ", format(bb["xmin"], scientific=FALSE), " à ", 
    format(bb["xmax"], scientific=FALSE), " m\n")
cat("   - Y: ", format(bb["ymin"], scientific=FALSE), " à ", 
    format(bb["ymax"], scientific=FALSE), " m\n")

# FIX: Compute exact tile count needed
# instead of letting st_make_grid truncate
nx <- ceiling((WORLD_XMAX - WORLD_XMIN) / (cell_km * 1000))   # 35
ny <- ceiling((WORLD_YMAX - WORLD_YMIN) / (cell_km * 1000))   # 18

cat(" Génération de la grille de tuiles...\n")
cat("   - Nombre de colonnes (X) :", nx, "\n")
cat("   - Nombre de lignes (Y) :", ny, "\n")
cat("   - Total attendu :", nx * ny, "tuiles\n")

# Generate grid with fixed dimensions
tiles_sf <- sf::st_make_grid(
  offset   = c(WORLD_XMIN, WORLD_YMIN),
  cellsize = cell_km * 1000,
  n        = c(nx, ny),        # ← Force exactement 35×18
  crs      = crs_eq,
  what     = "polygons"
) %>%
  sf::st_sf()

# ------------------------------------------------------------------
# New indexing: pure arithmetic order (eliminates rounding artefacts)
# ------------------------------------------------------------------
tiles_sf$tile_id <- seq_len(nx * ny)              # 1 … 630
tiles_sf$row     <- (tiles_sf$tile_id - 1) %/% nx # 0 … 17
tiles_sf$col     <- (tiles_sf$tile_id - 1) %%  nx # 0 … 34

# Check: column / row count (must be nx, ny)
n_cols <- nx
n_rows <- ny

cat("   - Colonnes générées :", n_cols, "(attendu:", nx, ")\n")
cat("   - Lignes générées :", n_rows, "(attendu:", ny, ")\n")

# ------------------------------------------------------------------

# Add tile metadata
tiles_sf$tile_size_km <- cell_km
tiles_sf$crs <- "EPSG:6933"

# Compute statistics (corrected area)
n_tiles <- nrow(tiles_sf)
surface_km2 <- n_tiles * cell_km^2
cat(" Tuiles générées :", n_tiles, "\n")
cat("   - Taille par tuile :", cell_km, "×", cell_km, "km\n")
cat("   - Surface totale :", format(surface_km2, big.mark=","), "km²\n")

# Verify all IDs are present
tile_ids <- sort(tiles_sf$tile_id)
expected_ids <- 1:n_tiles
missing_ids <- setdiff(expected_ids, tile_ids)
if(length(missing_ids) > 0) {
  cat("  IDs manquants :", paste(missing_ids, collapse=", "), "\n")
} else {
  cat(" Tous les IDs de 1 à", n_tiles, "sont présents\n")
}

# Sauvegarde avec nom dynamique
output_file <- sprintf("~/scratch/output_V6/tiles_%dkm.gpkg", cell_km)
cat(" Sauvegarde dans :", output_file, "\n")

st_write(tiles_sf, output_file, delete_dsn = TRUE, quiet = TRUE)

# Verify output file
if(file.exists(output_file)) {
  file_info <- file.info(output_file)
  cat(" Fichier créé :", basename(output_file), "\n")
  cat("   - Taille :", format(file_info$size, scientific=FALSE), "octets\n")
  cat("   - Date :", format(file_info$mtime, "%Y-%m-%d %H:%M:%S"), "\n")
} else {
  stop(" Erreur lors de la création du fichier")
}

# Display first tiles for verification
cat("\n📋 Aperçu des tuiles :\n")
print(head(tiles_sf[, c("tile_id", "tile_size_km")]))

cat("\n Prochaines étapes :\n")
cat("   1. Vérifier le nombre de tuiles : ogrinfo -ro -so", output_file, "tiles | grep 'Feature Count'\n")
cat("   2. Lancer l'array-job : sbatch --array=1-", n_tiles, " step5_tile_job.sh\n")
cat("   3. Monitorer : squeue -u $USER | grep step5_tile\n")

cat("\n Génération des tuiles terminée !\n") 
