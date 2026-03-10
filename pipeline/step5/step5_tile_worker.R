#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5 — TILE WORKER (pipeline V6)
# Methodology notes:
#  - Stable 1 km grid (EPSG:6933) consistent with subsequent steps
#  - Temporal order before linearisation (reliable distances)
#  - p_d = 1 m (TSHD) as described in §2.7-2.8  [CHANGE]
#  - Pings without lithology (or >10 km) EXCLUDED from p_l but not SAR [CHANGE]
#  - p_l aggregated at cell level via simple mean of pings with lithology [CHANGE]
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Libraries ----------------------------------------------------------------
# Add user library path
.libPaths(c("~/R/library", .libPaths()))

# Packages requis (arrow optionnel - fallback RDS)
pkgs_required <- c("sf", "dplyr", "data.table", "tidyr", "rlang", "tidyselect", "lubridate", "yaml")
pkgs_optional <- c("arrow")

safe_library <- function(pkg) {
  tryCatch(
    {
      library(pkg, character.only = TRUE)
      cat("[INFO]", pkg, "OK\n")
      TRUE
    },
    error = function(e) {
      stop("Missing package: ", pkg, "\nMessage: ", e$message)
    }
  )
}

optional_library <- function(pkg) {
  tryCatch(
    {
      library(pkg, character.only = TRUE)
      cat("[INFO]", pkg, "OK\n")
      TRUE
    },
    error = function(e) {
      cat("[WARN]", pkg, "unavailable — falling back to RDS\n")
      FALSE
    }
  )
}

# Chargement robuste de sf
tryCatch(
  {
    library(sf)
    cat("[INFO] sf OK\n")
    options(sf_max_print = 20)
    sf::sf_use_s2(FALSE)
  },
  error = function(e) {
    stop("Package 'sf' could not be loaded: ", e$message)
  }
)

invisible(lapply(pkgs_required[pkgs_required != "sf"], safe_library))
HAS_ARROW <- optional_library("arrow")
cat("\n")

# Chargement des constantes partagées
this_file <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) {
    return(normalizePath(f))
  }
  if (!is.null(sys.frame(1)$ofile)) {
    return(normalizePath(sys.frame(1)$ofile))
  }
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))

# Fallback de sécurité si constants.R ancien (sans DEEP_HORIZON)
if (!exists("DEEP_HORIZON")) {
  DEEP_HORIZON <- SURF_HORIZON  # cap to surface horizon value (5 cm)
  cat("[WARN] DEEP_HORIZON missing in constants.R — using fallback", DEEP_HORIZON, "m\n")
}

# === Grille cellule stable (EPSG:6933) ===
snap_cells2 <- function(DT, xcol = "X", ycol = "Y") {
  x <- as.numeric(DT[[xcol]])
  y <- as.numeric(DT[[ycol]])
  col <- floor((x - WORLD_XMIN) / CELL_SIZE_M)
  row <- floor((y - WORLD_YMIN) / CELL_SIZE_M)
  cx <- WORLD_XMIN + col * CELL_SIZE_M + CELL_SIZE_M / 2
  cy <- WORLD_YMIN + row * CELL_SIZE_M + CELL_SIZE_M / 2
  DT[, `:=`(
    col     = as.integer(col),
    row     = as.integer(row),
    x       = as.numeric(cx), # centre cellule
    y       = as.numeric(cy),
    grid_id = as.integer(row * GRID_COLS + col + 1L)
  )]
  DT
}

## 1.  Command-line arguments ---------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (!(length(args) %in% c(1, 6))) {
  stop(
    "Usage :\n  Rscript step5_tile_worker.R <tile_id>\n  ",
    "Rscript step5_tile_worker.R <tile_id> <sub_id> <xmin> <xmax> <ymin> <ymax>"
  )
}

tile_id <- as.integer(args[1])
if (is.na(tile_id) || tile_id < 1) stop("Invalid tile ID: ", args[1])

is_subtile <- length(args) == 6
if (is_subtile) {
  sub_id <- as.integer(args[2])
  xmin <- as.numeric(args[3])
  xmax <- as.numeric(args[4])
  ymin <- as.numeric(args[5])
  ymax <- as.numeric(args[6])
  if (anyNA(c(sub_id, xmin, xmax, ymin, ymax))) {
    stop("Invalid sub-tile arguments.")
  }
  cat(sprintf(
    "Sub-tile %d_%d — bbox: (%.0f,%.0f)-(%.0f,%.0f)\n",
    tile_id, sub_id, xmin, ymin, xmax, ymax
  ))
} else {
  cat("Processing full tile:", tile_id, "\n")
}

# Load YAML parameters
param_yaml <- "~/scratch/configuration/fi_parameters_with_freshness.yaml"
params_raw <- yaml::read_yaml(param_yaml)

get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit)
    s$inherit <- NULL
    modifyList(parent, s)
  } else {
    s
  }
}
par <- get_scenario("default")

# Regional k table (used later)
k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast = unlist(par$k_fast) *
    ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep <- par$alpha_dep
fast_frac <- par$fast_fraction
slow_k <- par$slow_k
preserv_fact <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)

cat(
  "[INFO] Parameters: alpha_dep=", alpha_dep,
  " fast_fraction=", fast_frac, " slow_k=", slow_k,
  " preservation_factor=", preserv_fact, "\n"
)

Sys.setenv(OMP_NUM_THREADS = 1, MKL_NUM_THREADS = 1, OPENBLAS_NUM_THREADS = 1)
data.table::setDTthreads(1)
cat("[INFO] data.table threads = 1\n")

## 2.  Working zone -------------------------------------------------------------
tiles_file <- "~/scratch/output_V6/tiles_1000km.gpkg"
tiles <- st_read(tiles_file, quiet = TRUE)
target_crs <- st_crs(tiles)

if (is_subtile) {
  tile_geom <- st_as_sfc(st_bbox(c(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax), crs = target_crs))
  tile_buffered <- tile_geom
} else {
  tile_bb <- tiles[tiles$tile_id == tile_id, ]
  if (nrow(tile_bb) == 0) stop("Tile ", tile_id, " not found in ", tiles_file)
  tile_geom <- st_geometry(tile_bb)
  tile_buffered <- st_buffer(tile_geom, TILE_BUFFER_M)
}

## 3.  Read AIS + lithology -----------------------------------------------------
lithology_files <- list.files("~/scratch/output_V6/",
  pattern = "AIS_with_lithology_.*\\.rds$",
  full.names = TRUE
)
if (!length(lithology_files)) {
  stop("No AIS_with_lithology_* file found.")
}

dt_lithology <- readRDS(max(lithology_files))
dredge_raw <- dt_lithology[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
if (!nrow(dredge_raw)) {
  cat("[WARN] No dredging pings — clean exit\n")
  quit("no")
}

dredge_sf <- st_as_sf(dredge_raw, coords = c("Lon", "Lat"), crs = 4326, remove = FALSE) |>
  st_transform(target_crs)

sel <- st_intersects(dredge_sf, tile_buffered, sparse = FALSE)[, 1]
dredge_sf <- dredge_sf[sel, ]
if (!nrow(dredge_sf)) {
  cat("[WARN] No pings in zone — writing empty SAR file\n")
  empty <- data.table(
    grid_id = integer(), sum_dw = numeric(),
    sum_dw_pd = numeric(), sum_d = numeric(),
    n_with_pl = integer(), pl_sum = numeric()
  )
  out <- if (is_subtile) {
    sprintf("~/scratch/output_V6/sar_%d_sub%d.parquet", tile_id, sub_id)
  } else {
    sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
  }
  arrow::write_parquet(empty, out)
  quit("no")
}

coords <- st_coordinates(dredge_sf)
dredge_sf$X <- coords[, 1]
dredge_sf$Y <- coords[, 2]
dredge <- as.data.table(dredge_sf)
dredge[, geometry := NULL]

# [CHANGEMENT] Harmonise l’identifiant navire
id_cols <- c("ssvid", "SSVID", "mmsi", "MMSI", "vessel_id", "VESSEL_ID", "Navire")
for (c in id_cols) {
  if (c %in% names(dredge)) {
    setnames(dredge, c, "ssvid", skip_absent = TRUE)
    break
  }
}

# [CHANGEMENT] Valeurs par défaut / nettoyage
if (!"dredging_depth_m" %in% names(dredge)) dredge[, dredging_depth_m := 1.0]
if (!"dredge_width_m" %in% names(dredge)) dredge[, dredge_width_m := 2.6]
if (!"pl_base" %in% names(dredge)) dredge[, pl_base := NA_real_]

# [CHANGEMENT] p_d = 1 m (TSHD) pour coller à la Méthode
dredge[, dredging_depth_m := 1.0]

# Snap sur la grille 1 km et grid_id (toujours)
dredge <- snap_cells2(dredge, "X", "Y")

# Calcul de pl_eff a partir de pl_base (AVANT utilisation)
# Thèse §2.7-2.8 : dz2 cappé à DEEP_HORIZON (max 5cm)
dredge[, `:=`(
  dz1 = pmin(dredging_depth_m, SURF_HORIZON),
  dz2 = pmin(pmax(0, dredging_depth_m - SURF_HORIZON), DEEP_HORIZON)  # CAPPED
)]
dredge[, pl_eff := (pl_base * dz1 + FACTOR_DEEP * pl_base * dz2) / pmax(dredging_depth_m, 1e-6)]

# [CHANGEMENT] Marque les pings avec litho utilisable pour le carbone (≤10 km) — basé sur pl_eff
# Protection: exclure pings sans lithologie valide (has_lithology=FALSE)
if (!"dist_km" %in% names(dredge)) dredge[, dist_km := NA_real_]
if (!"has_lithology" %in% names(dredge)) dredge[, has_lithology := TRUE]  # fallback si absent
dredge[, use_for_carbon := has_lithology == TRUE & is.finite(pl_eff) & (is.na(dist_km) | dist_km <= 10)]

## 4.  Export ping_detail (tuile entière uniquement, inchangé)
if (!is_subtile) {
  dredge[, `:=`(
    dz1 = pmin(dredging_depth_m, SURF_HORIZON),
    dz2 = pmin(pmax(0, dredging_depth_m - SURF_HORIZON), DEEP_HORIZON)  # CAPPED
  )]
  dredge[, pl_eff := (pl_base * dz1 + FACTOR_DEEP * pl_base * dz2) / pmax(dredging_depth_m, 1e-6)]
  detail_cols <- c(
    "Timestamp", "Lon", "Lat", "X", "Y", "col", "row", "grid_id", "ssvid",
    "dredging_depth_m", "dredge_width_m", "pl_base", "pl_eff", "lithologie", "dist_km",
    "has_lithology", "use_for_carbon"
  )
  arrow::write_parquet(dredge[, ..detail_cols],
    sprintf("~/scratch/output_V6/ping_detail_%03d.parquet", tile_id),
    compression = "zstd"
  )
  cat("[INFO] ping_detail exported\n")
}

## 5.  Conversion en LIGNES avec TRI TEMPOREL ----------------------------------
cat("Converting to lines (temporal order)...\n")
to_posix <- function(x) {
  if (inherits(x, "POSIXt")) {
    x
  } else if (is.numeric(x)) {
    as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  } else {
    as.POSIXct(x, tz = "UTC")
  }
}
if (!"Timestamp" %in% names(dredge)) dredge[, Timestamp := NA]
dredge[, Timestamp := to_posix(Timestamp)]

# Segment quotidien par navire (clé simple et robuste)
dredge[, sub_seg_id := paste0(ssvid, "_", format(Timestamp, "%Y%m%d"))]

# [CHANGEMENT] p_l profondeur-pondéré calculé AU NIVEAU PING (avant agrégat),
# mais la moyenne cellulaire (2.8) sera SIMPLE, pas pondérée, via use_for_carbon.
# Thèse §2.7-2.8 : dz2 cappé à DEEP_HORIZON (max 5cm)
dredge[, `:=`(
  dz1 = pmin(dredging_depth_m, SURF_HORIZON),
  dz2 = pmin(pmax(0, dredging_depth_m - SURF_HORIZON), DEEP_HORIZON)  # CAPPED
)]
dredge[, pl_eff := (pl_base * dz1 + FACTOR_DEEP * pl_base * dz2) / pmax(dredging_depth_m, 1e-6)]

dredge_sf2 <- st_as_sf(dredge, coords = c("X", "Y"), crs = target_crs, remove = FALSE)

lines_sf <- dredge_sf2 |>
  arrange(sub_seg_id, Timestamp) |> # [CHANGEMENT]
  group_by(sub_seg_id) |>
  filter(n() > 1) |>
  summarise(
    W_v = first(dredge_width_m),
    p_d_i = 1.0, # [CHANGEMENT] p_d = 1 m
    geometry = st_cast(st_combine(geometry), "MULTILINESTRING"),
    .groups = "drop"
  )

if (nrow(lines_sf) == 0) {
  cat("[WARN] No valid lines — empty output\n")
  out <- if (is_subtile) {
    sprintf("~/scratch/output_V6/sar_%d_sub%d.parquet", tile_id, sub_id)
  } else {
    sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
  }
  arrow::write_parquet(
    data.table(
      grid_id = integer(), sum_dw = numeric(), sum_dw_pd = numeric(),
      sum_d = numeric(), n_with_pl = integer(), pl_sum = numeric()
    ),
    out
  )
  quit("no")
}
cat("Lines created:", nrow(lines_sf), "\n")

## 6.  World-aligned local grid ------------------------------------------------
cat("Creating world-aligned local grid...\n")
tile_bbox <- st_bbox(tile_buffered)

col_start <- as.integer((tile_bbox["xmin"] - WORLD_XMIN) %/% CELL_SIZE_M)
col_end <- as.integer((tile_bbox["xmax"] - WORLD_XMIN) %/% CELL_SIZE_M)
row_start <- as.integer((tile_bbox["ymin"] - WORLD_YMIN) %/% CELL_SIZE_M)
row_end <- as.integer((tile_bbox["ymax"] - WORLD_YMIN) %/% CELL_SIZE_M)

col_start <- max(0, col_start - 1)
col_end <- min(GRID_COLS - 1, col_end + 1)
row_start <- max(0, row_start - 1)
row_end <- min(GRID_ROWS - 1, row_end + 1)

local_grid <- st_make_grid(
  offset = c(
    WORLD_XMIN + col_start * CELL_SIZE_M,
    WORLD_YMIN + row_start * CELL_SIZE_M
  ),
  cellsize = CELL_SIZE_M,
  n = c(col_end - col_start + 1, row_end - row_start + 1),
  crs = target_crs,
  what = "polygons"
) |>
  st_sf() |>
  mutate(
    col     = col_start + ((dplyr::row_number() - 1) %% (col_end - col_start + 1)),
    row     = row_start + ((dplyr::row_number() - 1) %/% (col_end - col_start + 1)),
    grid_id = row * GRID_COLS + col + 1L
  )

grid1km <- st_intersection(local_grid, tile_buffered)
cat("Local grid:", nrow(grid1km), "cells\n")

## 7.  Line x grid intersections (SAR) + simple p_l mean per cell -------------
cat("Line/grid intersections...\n")
res <- data.table(
  grid_id = integer(),
  sum_dw = numeric(), sum_dw_pd = numeric(),
  sum_d = numeric()
)

for (i in seq_len(nrow(lines_sf))) {
  cand <- sf::st_intersects(lines_sf[i, ], grid1km, sparse = FALSE)[1, ]
  if (!any(cand)) next
  inter <- sf::st_intersection(lines_sf[i, ], grid1km[cand, ])
  if (!nrow(inter)) next
  len <- as.numeric(st_length(inter))
  res_i <- data.table(
    grid_id   = inter$grid_id,
    sum_dw    = len * lines_sf$W_v[i],
    sum_dw_pd = len * lines_sf$W_v[i] * lines_sf$p_d_i[i], # = sum_dw (p_d=1)
    sum_d     = len
  )
  # cumuls
  res[res_i, on = "grid_id", `:=`(
    sum_dw    = ifelse(is.na(sum_dw), i.sum_dw, sum_dw + i.sum_dw),
    sum_dw_pd = ifelse(is.na(sum_dw_pd), i.sum_dw_pd, sum_dw_pd + i.sum_dw_pd),
    sum_d     = ifelse(is.na(sum_d), i.sum_d, sum_d + i.sum_d)
  )]
  new_rows <- res_i[!res, on = "grid_id"]
  if (nrow(new_rows) > 0) res <- rbindlist(list(res, new_rows), use.names = TRUE)
}

# [CHANGEMENT] Moyenne simple p_l par cellule (pings avec litho ≤10 km) — basé sur pl_eff
pl_cell <- dredge[use_for_carbon == TRUE & is.finite(pl_eff),
  .(
    n_with_pl = .N,
    pl_sum = sum(pl_eff, na.rm = TRUE)
  ),
  by = grid_id
]

# Jointure : on garde la structure attendue par la suite
res <- merge(res, pl_cell, by = "grid_id", all.x = TRUE)
res[is.na(n_with_pl), `:=`(n_with_pl = 0L, pl_sum = 0)]

setkey(res, grid_id)
cat("Intersections complete:", nrow(res), "cells touched\n")

## 8.  Sauvegarde ---------------------------------------------------------------
out <- if (is_subtile) {
  sprintf("~/scratch/output_V6/sar_%d_sub%d.parquet", tile_id, sub_id)
} else {
  sprintf("~/scratch/output_V6/sar_%03d.parquet", tile_id)
}

if (requireNamespace("arrow", quietly = TRUE) &&
  packageVersion("arrow") >= numeric_version(PARQUET_VERSION_MIN)) {
  arrow::write_parquet(res, out)
  cat("[INFO] Results saved (Parquet):", basename(out), "\n")
} else {
  saveRDS(res, sub("\\.parquet$", ".rds", out))
  cat("[WARN] Arrow absent — saving as RDS\n")
}

cat("\nTILE STATS ", if (is_subtile) sprintf("%d_%d", tile_id, sub_id) else tile_id, "\n",
  "   - Cellules :", nrow(res), "\n",
  "   - Distance totale :", format(sum(res$sum_d), scientific = FALSE), "m\n",
  "   - SAR moyen :", format(mean(res$sum_dw / CELL_AREA_M2, na.rm = TRUE), scientific = FALSE), "\n",
  sep = ""
)
cat("\nDone\n")
