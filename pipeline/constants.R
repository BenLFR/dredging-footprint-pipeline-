# ────────────────────────────────────────────────────────────────────────────────
# SHARED CONSTANTS — Step-5 modular pipeline
# Global 1 km Equal-Earth grid EPSG:6933
# ────────────────────────────────────────────────────────────────────────────────

# World extent in metres (EPSG:6933) — consistent with Atwood et al. and Step 3
WORLD_XMIN <- -17367530.45
WORLD_XMAX <-  17367530.45
WORLD_YMIN <- -7342699.72
WORLD_YMAX <-  7342699.72

# 1 km grid parameters
CELL_SIZE_M    <- 1000
CELL_AREA_M2   <- CELL_SIZE_M * CELL_SIZE_M
GRID_COLS      <- as.integer((WORLD_XMAX - WORLD_XMIN) / CELL_SIZE_M)   # 34735
GRID_ROWS      <- as.integer((WORLD_YMAX - WORLD_YMIN) / CELL_SIZE_M)   # 14685
NCOLS          <- GRID_COLS
NROWS          <- GRID_ROWS

# Buffers for tiles (multi-run SLURM sensitivity test)
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "4"))
if(is.na(BUFFER_IDX) || BUFFER_IDX < 1 || BUFFER_IDX > length(BUFFER_TEST_VALUES)) BUFFER_IDX <- 1
TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]
cat(sprintf("[INFO] TILE_BUFFER_M set to %d m (BUFFER_IDX = %d)\n", TILE_BUFFER_M, BUFFER_IDX))

# Version arrow minimale (modifie selon ta stack logicielle)
PARQUET_VERSION_MIN <- "14.0.0"

# Tile generation parameters
CELL_KM <- 1000  # Tile size in km
CRS_EQUIVALENT <- "EPSG:6933"  # Equal-Earth CRS

# Parameters for effective lithology factor (thesis §2.7-2.8)
SURF_HORIZON <- 0.05          # 5 cm (surface horizon)
DEEP_HORIZON <- 0.05          # 5 cm max (deep horizon — capped)
FACTOR_DEEP  <- 0.3           # Deep layer weighting factor
