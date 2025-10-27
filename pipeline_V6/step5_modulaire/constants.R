# ────────────────────────────────────────────────────────────────────────────────
# CONSTANTES PARTAGÉES - Pipeline Step-5 Modulaire
# Grille mondiale 1 km Equal-Earth EPSG:6933
# ────────────────────────────────────────────────────────────────────────────────

# Emprise mondiale en mètres (EPSG:6933) – conforme Atwood et Step 3
WORLD_XMIN <- -17367530.45
WORLD_XMAX <-  17367530.45
WORLD_YMIN <- -7342699.72
WORLD_YMAX <-  7342699.72

# Paramètres de grille 1 km
CELL_SIZE_M    <- 1000
CELL_AREA_M2   <- CELL_SIZE_M * CELL_SIZE_M
GRID_COLS      <- as.integer((WORLD_XMAX - WORLD_XMIN) / CELL_SIZE_M)   # 34735
GRID_ROWS      <- as.integer((WORLD_YMAX - WORLD_YMIN) / CELL_SIZE_M)   # 14685
NCOLS          <- GRID_COLS
NROWS          <- GRID_ROWS

# Buffers pour tuiles (test multi-runs SLURM)
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "4"))
if(is.na(BUFFER_IDX) || BUFFER_IDX < 1 || BUFFER_IDX > length(BUFFER_TEST_VALUES)) BUFFER_IDX <- 1
TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]
cat(sprintf("INFO: TILE_BUFFER_M = %d m (BUFFER_IDX = %d)\n", TILE_BUFFER_M, BUFFER_IDX))
TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]

# Version arrow minimale (modifie selon ta stack logicielle)
PARQUET_VERSION_MIN <- "14.0.0"

# Paramètres pour la génération des tuiles
CELL_KM <- 1000  # Taille des tuiles en km
CRS_EQUIVALENT <- "EPSG:6933"  # CRS Equal-Earth

# Paramètres pour le calcul de la lithologie effective
SURF_HORIZON <- 0.05          # 5 cm (horizon de surface)
FACTOR_DEEP  <- 0.3           # Facteur de pondération couche profonde

# === Grille cellule (EPSG:6933, alignée monde) ===
GRID_X0 <- WORLD_XMIN
GRID_Y0 <- WORLD_YMIN
GRID_DX <- CELL_SIZE_M
GRID_DY <- CELL_SIZE_M
