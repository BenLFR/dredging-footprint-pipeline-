# ────────────────────────────────────────────────────────────────────────────────
# SHARED CONSTANTS - Modular Step-5 Pipeline
# Global parameters used by all pipeline scripts
# ────────────────────────────────────────────────────────────────────────────────

# Tiling parameters
CELL_KM <- 1000   # Tile size in km (reduced from 5000 to 1000 to avoid OOM)
CRS_EQUIVALENT <- 6933   # Equivalent CRS (metres)

# Global extent in metres (EPSG:6933) - HARMONISED WITH STEP 3
WORLD_XMIN <- -18000000      # -180° Equal-Earth
WORLD_YMIN <- -9000000       # -90° Equal-Earth
WORLD_XMAX <-  18000000      # +180° Equal-Earth
WORLD_YMAX <-   9000000      # +90° Equal-Earth

# Grid parameters
CELL_SIZE_M <- 1000          # 1 km
CELL_AREA_M2 <- 1e6

GRID_COLS <- 36000L          # 360° * 1000 m
GRID_ROWS <- 18000L          # 180° * 1000 m

# ──────────────
# BUFFER SENSITIVITY TEST SYSTEM
# ──────────────
# List of buffers to test (in metres)
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)

# Usage: to test different buffers, set the environment variable "BUFFER_IDX"
# e.g. in the shell or SLURM job: export BUFFER_IDX=3   (for 20000 m)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "1"))
if(is.na(BUFFER_IDX) || BUFFER_IDX < 1 || BUFFER_IDX > length(BUFFER_TEST_VALUES)) {
  BUFFER_IDX <- 1  # default: first buffer in the list
}

TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]

cat(sprintf("[INFO] TILE_BUFFER_M set to %d m (BUFFER_IDX = %d)\n", TILE_BUFFER_M, BUFFER_IDX))

# Paramètres de sauvegarde
PARQUET_VERSION_MIN <- "14.0.0"  # Version minimale d'arrow pour Parquet 