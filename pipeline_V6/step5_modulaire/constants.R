# ────────────────────────────────────────────────────────────────────────────────
# CONSTANTES PARTAGÉES - Pipeline Step-5 Modulaire
# Paramètres globaux utilisés par tous les scripts du pipeline
# ────────────────────────────────────────────────────────────────────────────────

# Paramètres de tuilage
CELL_KM <- 1000   # Taille de tuile en km (réduit de 5000 à 1000 pour éviter OOM)
CRS_EQUIVALENT <- 6933   # CRS équivalent (mètres)

# Emprise mondiale en mètres (EPSG:6933) - COHÉRENT entre tous les scripts
WORLD_XMIN <- -18000000
WORLD_YMIN <- -9000000
WORLD_XMAX <- 18000000
WORLD_YMAX <- 9000000

# Paramètres de grille
CELL_SIZE_M <- 1000  # Taille de cellule en mètres (1 km)
CELL_AREA_M2 <- 1e6  # Surface de cellule en m²

# Paramètres de calcul global_grid_id
GRID_COLS <- 36000  # Nombre de colonnes de la grille mondiale
GRID_ROWS <- 18000  # Nombre de lignes de la grille mondiale

# ──────────────
# SYSTÈME DE TEST DE BUFFERS
# ──────────────
# Liste des buffers à tester (en mètres)
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)

# Utilisation : pour tester différents buffers, définir une variable d'environnement "BUFFER_IDX"
# Ex: dans le shell ou job SLURM → export BUFFER_IDX=3   (pour 20000 m)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "1"))
if(is.na(BUFFER_IDX) || BUFFER_IDX < 1 || BUFFER_IDX > length(BUFFER_TEST_VALUES)) {
  BUFFER_IDX <- 1  # défaut: 1er buffer de la liste
}

TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]

cat(sprintf("🌍 [INFO] TILE_BUFFER_M défini à %d m (BUFFER_IDX = %d)\n", TILE_BUFFER_M, BUFFER_IDX))

# Paramètres de sauvegarde
PARQUET_VERSION_MIN <- "14.0.0"  # Version minimale d'arrow pour Parquet 