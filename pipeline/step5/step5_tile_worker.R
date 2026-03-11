#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5 ─ TILE WORKER (pipeline V6)
# Processes one tile (or sub-tile) of the global grid.
# Changes vs previous version:
#  - World-aligned 1 km grid (EPSG:6933), consistent with downstream steps
#  - Temporal sort before line construction (reliable distances)
#  - p_d = 1 m (TSHD default, §2.7-2.8)
#  - Pings without lithology or >10 km from seabed data EXCLUDED from p_l
#  - p_l aggregated per cell as simple mean of qualifying pings
# ────────────────────────────────────────────────────────────────────────────────

## 0. Libraries ----------------------------------------------------------------
.libPaths(c("~/R/library", .libPaths()))

pkgs_required <- c("sf", "dplyr", "data.table", "tidyr", "rlang", "tidyselect", "lubridate", "yaml")
pkgs_optional <- c("arrow")

safe_library <- function(pkg) {
  tryCatch(
    { library(pkg, character.only = TRUE); cat("[OK]", pkg, "\n"); TRUE },
    error = function(e) stop("[ERR] Missing package: ", pkg, "\n", e$message)
  )
}

optional_library <- function(pkg) {
  tryCatch(
    { library(pkg, character.only = TRUE); cat("[OK]", pkg, "\n"); TRUE },
    error = function(e) { cat("[WARN]", pkg, "unavailable - fallback to RDS\n"); FALSE }
  )
}

tryCatch({
  library(sf)
  cat("[OK] sf\n")
  options(sf_max_print = 20)
  sf::sf_use_s2(FALSE)
}, error = function(e) stop("[ERR] Cannot load 'sf':\n", e$message))

invisible(lapply(pkgs_required[pkgs_required != "sf"], safe_library))
HAS_ARROW <- optional_library("arrow")
cat("\n")

# Load shared constants
this_file <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) return(normalizePath(f))
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile))
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))

# Safety fallback if constants.R predates DEEP_HORIZON
if (!exists("DEEP_HORIZON")) {
  DEEP_HORIZON <- SURF_HORIZON
  cat("[WARN] DEEP_HORIZON absent from constants.R - fallback to", DEEP_HORIZON, "m\n")
}

# World-aligned cell snapping (EPSG:6933)
snap_cells2 <- function(DT, xcol = "X", ycol = "Y") {
  x   <- as.numeric(DT[[xcol]])
  y   <- as.numeric(DT[[ycol]])
  col <- floor((x - WORLD_XMIN) / CELL_SIZE_M)
  row <- floor((y - WORLD_YMIN) / CELL_SIZE_M)
  cx  <- WORLD_XMIN + col * CELL_SIZE_M + CELL_SIZE_M / 2
  cy  <- WORLD_YMIN + row * CELL_SIZE_M + CELL_SIZE_M / 2
  DT[, `:=`(
    col     = as.integer(col),
    row     = as.integer(row),
    x       = as.numeric(cx),
    y       = as.numeric(cy),
    grid_id = as.integer(row * GRID_COLS + col + 1L)
  )]
  DT
}

## 1. Arguments ----------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (!(length(args) %in% c(1, 6))) {
  stop(
    "Usage:\n",
    "  Rscript step5_tile_worker.R <tile_id>\n",
    "  Rscript step5_tile_worker.R <tile_id> <sub_id> <xmin> <xmax> <ymin> <ymax>"
  )
}

tile_id <- as.integer(args[1])
if (is.na(tile_id) || tile_id < 1) stop("[ERR] Invalid tile ID: ", args[1])

is_subtile <- length(args) == 6
if (is_subtile) {
  sub_id <- as.integer(args[2])
  xmin   <- as.numeric(args[3]); xmax <- as.numeric(args[4])
  ymin   <- as.numeric(args[5]); ymax <- as.numeric(args[6])
  if (anyNA(c(sub_id, xmin, xmax, ymin, ymax))) stop("[ERR] Invalid sub-tile arguments.")
  cat(sprintf("[INFO] Sub-tile %d_%d - bbox: (%.0f,%.0f)-(%.0f,%.0f)\n",
              tile_id, sub_id, xmin, ymin, xmax, ymax))
} else {
  cat("[INFO] Processing full tile:", tile_id, "\n")
}

# YAML parameters
SCRATCH_DIR <- Sys.getenv("SCRATCH_DIR", path.expand("~/scratch"))
param_yaml  <- file.path(SCRATCH_DIR, "configuration/fi_parameters_with_freshness.yaml")
params_raw  <- yaml::read_yaml(param_yaml)

get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit); s$inherit <- NULL; modifyList(parent, s)
  } else s
}
par <- get_scenario("default")

k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast = unlist(par$k_fast) *
    ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)
alpha_dep    <- par$alpha_dep
fast_frac    <- par$fast_fraction
slow_k       <- par$slow_k
preserv_fact <- ifelse(is.null(par$preservation_factor), 0.87, par$preservation_factor)

cat("[INFO] Parameters: alpha_dep=", alpha_dep,
    " fast_fraction=", fast_frac, " slow_k=", slow_k,
    " preservation_factor=", preserv_fact, "\n")

Sys.setenv(OMP_NUM_THREADS = 1, MKL_NUM_THREADS = 1, OPENBLAS_NUM_THREADS = 1)
data.table::setDTthreads(1)
cat("[OK] data.table threads = 1\n")

## 2. Work area ----------------------------------------------------------------
tiles_file <- file.path(SCRATCH_DIR, "output_V6/tiles_1000km.gpkg")
tiles      <- st_read(tiles_file, quiet = TRUE)
target_crs <- st_crs(tiles)

if (is_subtile) {
  tile_geom     <- st_as_sfc(st_bbox(c(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax), crs=target_crs))
  tile_buffered <- tile_geom
} else {
  tile_bb <- tiles[tiles$tile_id == tile_id, ]
  if (nrow(tile_bb) == 0) stop("[ERR] Tile ", tile_id, " not found in ", tiles_file)
  tile_geom     <- st_geometry(tile_bb)
  tile_buffered <- st_buffer(tile_geom, TILE_BUFFER_M)
}

## 3. Load AIS + lithology -----------------------------------------------------
output_dir       <- file.path(SCRATCH_DIR, "output_V6")
lithology_files  <- list.files(output_dir,
                               pattern = "AIS_with_lithology_.*\\.rds$",
                               full.names = TRUE)
if (!length(lithology_files)) stop("[ERR] No AIS_with_lithology_* file found in ", output_dir)

dt_lithology <- readRDS(max(lithology_files))
dredge_raw   <- dt_lithology[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
if (!nrow(dredge_raw)) {
  cat("[WARN] No dredging pings - clean exit\n")
  quit("no")
}

dredge_sf <- st_as_sf(dredge_raw, coords = c("Lon", "Lat"), crs = 4326, remove = FALSE) |>
  st_transform(target_crs)

sel       <- st_intersects(dredge_sf, tile_buffered, sparse = FALSE)[, 1]
dredge_sf <- dredge_sf[sel, ]

write_empty <- function(path) {
  empty <- data.table(grid_id = integer(), sum_dw = numeric(),
                      sum_dw_pd = numeric(), sum_d = numeric(),
                      n_with_pl = integer(), pl_sum = numeric())
  if (HAS_ARROW) arrow::write_parquet(empty, path)
  else           saveRDS(empty, sub("\\.parquet$", ".rds", path))
}

out_path <- if (is_subtile) {
  file.path(output_dir, sprintf("sar_%d_sub%d.parquet", tile_id, sub_id))
} else {
  file.path(output_dir, sprintf("sar_%03d.parquet", tile_id))
}

if (!nrow(dredge_sf)) {
  cat("[WARN] No pings in tile - writing empty file\n")
  write_empty(out_path)
  quit("no")
}

coords     <- st_coordinates(dredge_sf)
dredge_sf$X <- coords[, 1]; dredge_sf$Y <- coords[, 2]
dredge <- as.data.table(dredge_sf)
dredge[, geometry := NULL]

# Harmonise vessel identifier
id_cols <- c("ssvid", "SSVID", "mmsi", "MMSI", "vessel_id", "VESSEL_ID", "Navire")
for (cc in id_cols) {
  if (cc %in% names(dredge)) { setnames(dredge, cc, "ssvid", skip_absent=TRUE); break }
}

# Defaults / cleaning
if (!"dredging_depth_m" %in% names(dredge)) dredge[, dredging_depth_m := 1.0]
if (!"dredge_width_m"   %in% names(dredge)) dredge[, dredge_width_m   := 2.6]
if (!"pl_base"          %in% names(dredge)) dredge[, pl_base           := NA_real_]
if (!"has_lithology"    %in% names(dredge)) dredge[, has_lithology     := TRUE]
if (!"dist_km"          %in% names(dredge)) dredge[, dist_km           := NA_real_]

# p_d = 1 m (TSHD, §2.7-2.8)
dredge[, dredging_depth_m := 1.0]

# World-aligned grid snap
dredge <- snap_cells2(dredge, "X", "Y")

# Depth-weighted pl_eff at ping level (§2.7-2.8, Option B: dz2 capped at DEEP_HORIZON)
dredge[, `:=`(
  dz1 = pmin(dredging_depth_m, SURF_HORIZON),
  dz2 = pmin(pmax(0, dredging_depth_m - SURF_HORIZON), DEEP_HORIZON)
)]
dredge[, pl_eff := (pl_base * dz1 + FACTOR_DEEP * pl_base * dz2) / pmax(dredging_depth_m, 1e-6)]

# Pings eligible for carbon p_l: valid lithology + within 10 km of seabed data
dredge[, use_for_carbon := has_lithology == TRUE & is.finite(pl_eff) &
                           (is.na(dist_km) | dist_km <= 10)]

## 4. Export ping_detail (full tile only) --------------------------------------
if (!is_subtile) {
  detail_cols <- intersect(
    c("Timestamp", "Lon", "Lat", "X", "Y", "col", "row", "grid_id", "ssvid",
      "dredging_depth_m", "dredge_width_m", "pl_base", "pl_eff",
      "lithologie", "dist_km", "has_lithology", "use_for_carbon"),
    names(dredge)
  )
  detail_path <- file.path(output_dir, sprintf("ping_detail_%03d.parquet", tile_id))
  if (HAS_ARROW) arrow::write_parquet(dredge[, ..detail_cols], detail_path, compression = "zstd")
  cat("[OK] ping_detail exported\n")
}

## 5. Lines with temporal sort -------------------------------------------------
cat("[INFO] Building lines (temporal order)...\n")

to_posix <- function(x) {
  if (inherits(x, "POSIXt")) x
  else if (is.numeric(x)) as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  else as.POSIXct(x, tz = "UTC")
}
if (!"Timestamp" %in% names(dredge)) dredge[, Timestamp := NA]
dredge[, Timestamp := to_posix(Timestamp)]

dredge[, sub_seg_id := paste0(ssvid, "_", format(Timestamp, "%Y%m%d"))]

# Recompute pl_eff (redundant but defensive)
dredge[, `:=`(
  dz1 = pmin(dredging_depth_m, SURF_HORIZON),
  dz2 = pmin(pmax(0, dredging_depth_m - SURF_HORIZON), DEEP_HORIZON)
)]
dredge[, pl_eff := (pl_base * dz1 + FACTOR_DEEP * pl_base * dz2) / pmax(dredging_depth_m, 1e-6)]

dredge_sf2 <- st_as_sf(dredge, coords = c("X", "Y"), crs = target_crs, remove = FALSE)

lines_sf <- dredge_sf2 |>
  arrange(sub_seg_id, Timestamp) |>
  group_by(sub_seg_id) |>
  filter(n() > 1) |>
  summarise(
    W_v   = first(dredge_width_m),
    p_d_i = 1.0,   # p_d = 1 m (TSHD)
    geometry = st_cast(st_combine(geometry), "MULTILINESTRING"),
    .groups = "drop"
  )

if (nrow(lines_sf) == 0) {
  cat("[WARN] No valid lines - writing empty file\n")
  write_empty(out_path)
  quit("no")
}
cat("[OK] Lines created:", nrow(lines_sf), "\n")

## 6. World-aligned local grid -------------------------------------------------
cat("[INFO] Building world-aligned local grid...\n")
tile_bbox <- st_bbox(tile_buffered)

col_start <- max(0L,           as.integer((tile_bbox["xmin"] - WORLD_XMIN) %/% CELL_SIZE_M) - 1L)
col_end   <- min(GRID_COLS-1L, as.integer((tile_bbox["xmax"] - WORLD_XMIN) %/% CELL_SIZE_M) + 1L)
row_start <- max(0L,           as.integer((tile_bbox["ymin"] - WORLD_YMIN) %/% CELL_SIZE_M) - 1L)
row_end   <- min(GRID_ROWS-1L, as.integer((tile_bbox["ymax"] - WORLD_YMIN) %/% CELL_SIZE_M) + 1L)

local_grid <- st_make_grid(
  offset   = c(WORLD_XMIN + col_start * CELL_SIZE_M, WORLD_YMIN + row_start * CELL_SIZE_M),
  cellsize = CELL_SIZE_M,
  n        = c(col_end - col_start + 1, row_end - row_start + 1),
  crs      = target_crs,
  what     = "polygons"
) |> st_sf() |>
  mutate(
    col     = col_start + ((dplyr::row_number() - 1L) %% (col_end - col_start + 1L)),
    row     = row_start + ((dplyr::row_number() - 1L) %/% (col_end - col_start + 1L)),
    grid_id = row * GRID_COLS + col + 1L
  )

grid1km <- st_intersection(local_grid, tile_buffered)
cat("[OK] Local grid:", nrow(grid1km), "cells\n")

## 7. Line × grid intersections (SAR) + simple p_l mean per cell --------------
cat("[INFO] Line/grid intersections...\n")

res <- data.table(
  grid_id   = integer(),
  sum_dw    = numeric(),
  sum_dw_pd = numeric(),
  sum_d     = numeric()
)

for (i in seq_len(nrow(lines_sf))) {
  cand <- sf::st_intersects(lines_sf[i, ], grid1km, sparse = FALSE)[1, ]
  if (!any(cand)) next
  inter <- sf::st_intersection(lines_sf[i, ], grid1km[cand, ])
  if (!nrow(inter)) next
  len   <- as.numeric(st_length(inter))
  res_i <- data.table(
    grid_id   = inter$grid_id,
    sum_dw    = len * lines_sf$W_v[i],
    sum_dw_pd = len * lines_sf$W_v[i] * lines_sf$p_d_i[i],
    sum_d     = len
  )
  res[res_i, on = "grid_id", `:=`(
    sum_dw    = fifelse(is.na(sum_dw),    i.sum_dw,    sum_dw    + i.sum_dw),
    sum_dw_pd = fifelse(is.na(sum_dw_pd), i.sum_dw_pd, sum_dw_pd + i.sum_dw_pd),
    sum_d     = fifelse(is.na(sum_d),     i.sum_d,     sum_d     + i.sum_d)
  )]
  new_rows <- res_i[!res, on = "grid_id"]
  if (nrow(new_rows)) res <- rbindlist(list(res, new_rows), use.names = TRUE)
}

# Simple mean p_l per cell (pings with valid lithology within 10 km)
pl_cell <- dredge[use_for_carbon == TRUE & is.finite(pl_eff),
                  .(n_with_pl = .N, pl_sum = sum(pl_eff, na.rm = TRUE)),
                  by = grid_id]

res <- merge(res, pl_cell, by = "grid_id", all.x = TRUE)
res[is.na(n_with_pl), `:=`(n_with_pl = 0L, pl_sum = 0)]

setkey(res, grid_id)
cat("[OK] Intersections done:", nrow(res), "cells\n")

## 8. Save ---------------------------------------------------------------------
if (HAS_ARROW) {
  arrow::write_parquet(res, out_path)
  cat("[OK] Saved (Parquet):", basename(out_path), "\n")
} else {
  saveRDS(res, sub("\\.parquet$", ".rds", out_path))
  cat("[WARN] Arrow unavailable - saved as RDS\n")
}

cat(sprintf("\n[STATS] Tile %s\n  cells: %d\n  total distance: %s m\n  mean SAR: %s\n",
    if (is_subtile) sprintf("%d_%d", tile_id, sub_id) else as.character(tile_id),
    nrow(res),
    format(sum(res$sum_d), scientific = FALSE),
    format(mean(res$sum_dw / CELL_AREA_M2, na.rm = TRUE), scientific = FALSE)))

cat("[OK] Done\n")
