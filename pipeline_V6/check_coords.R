library(arrow)
library(data.table)

f  <- Sys.glob("~/scratch/output_V6/fi_grid_*.parquet")[1]
dt <- as.data.table(read_parquet(f, col_select = c("grid_id","k_used")))

GRID_COLS  <- 36000L
CELL       <- 1000
WORLD_XMIN <- -18000000
WORLD_YMAX <-  9000000

dt[, `:=`(col = as.integer((grid_id-1L) %% GRID_COLS),
          row = as.integer((grid_id-1L) %/% GRID_COLS))]
dt[, `:=`(x = WORLD_XMIN + col*CELL + CELL/2,
          y = WORLD_YMAX - row*CELL - CELL/2)]

cat("X range :", range(dt$x), "\n")
cat("Y range :", range(dt$y), "\n")
cat("Coord OK :", all(dt$y <= 9e6 & dt$y >= -9e6), "\n")
cat("Fallback k_used=1.0 :", round(mean(dt$k_used==1)*100,1), "%\n")
