#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# WORKER SOUS-TUILE - Step-5 (sortie compatible : grid_id,sum_dw,sum_dw_pd,sum_d,n_with_pl,pl_sum)
# Corrections : p_d=1 m, moyenne simple p_l par pings avec litho ≤10 km
# ────────────────────────────────────────────────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 6) {
  cat("Usage: Rscript step5_subtile_worker.R <tile_id> <sub_id> <xmin> <xmax> <ymin> <ymax>\n")
  quit("no", 1)
}

tile_id <- as.integer(args[1])
sub_id  <- as.integer(args[2])
xmin    <- as.numeric(args[3]); xmax <- as.numeric(args[4])
ymin    <- as.numeric(args[5]); ymax <- as.numeric(args[6])

suppressPackageStartupMessages({
  library(arrow); library(sf); library(dplyr); library(data.table)
  library(tidyr); library(rlang); library(tidyselect); library(lubridate); library(yaml)
})

source("~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/constants.R")

BUFFER_IDX <- 4
target_crs <- "EPSG:6933"
cat(sprintf("🔧 Sous-tuile %d_%d (%.0f,%.0f,%.0f,%.0f)\n", tile_id, sub_id, xmin,xmax,ymin,ymax))

# 1) Chargement ping_detail
detail_file <- file.path(OUT_DIR <- Sys.getenv("OUT_DIR","~/scratch/output_V6"), sprintf("ping_detail_%03d.parquet", tile_id))
if (!file.exists(detail_file)) {
  cat(sprintf("❌ %s introuvable\n", detail_file)); quit("no", 1)
}
dredge <- as.data.table(read_parquet(detail_file))
if (!nrow(dredge)) { cat("⚠️ Aucun ping dans ping_detail\n"); quit("no", 0) }

# bornes sous-tuile
dredge <- dredge[X >= xmin & X <= xmax & Y >= ymin & Y <= ymax]
if (!nrow(dredge)) { cat("⚠️ Aucun ping dans la sous-tuile\n"); quit("no", 0) }

# Valeurs par défaut / cohérence
if(!"dredge_width_m" %in% names(dredge)) dredge[, dredge_width_m := 2.6]
if(!"dredging_depth_m" %in% names(dredge)) dredge[, dredging_depth_m := 1.0]
dredge[, dredging_depth_m := 1.0]  # [CHANGEMENT] p_d = 1 m

# Lignes (ordre temporel)
to_posix <- function(x) if (inherits(x,"POSIXt")) x else if (is.numeric(x)) as.POSIXct(x, origin="1970-01-01", tz="UTC") else as.POSIXct(x, tz="UTC")
if(!"Timestamp" %in% names(dredge)) dredge[, Timestamp := NA]
dredge[, Timestamp := to_posix(Timestamp)]
dredge[, sub_seg_id := paste0(ssvid, "_", format(Timestamp, "%Y%m%d"))]

dredge_sf <- st_as_sf(dredge, coords=c("X","Y"), crs=target_crs, remove=FALSE)

lines_sf <- dredge_sf |>
  arrange(sub_seg_id, Timestamp) |>
  group_by(sub_seg_id) |>
  filter(n() > 1) |>
  summarise(
    W_v     = first(dredge_width_m),
    p_d_i   = 1.0,
    geometry = st_cast(st_combine(geometry), "MULTILINESTRING"),
    .groups = "drop"
  )

if (!nrow(lines_sf)) {
  out <- file.path(Sys.getenv("OUT_DIR","~/scratch/output_V6"), sprintf("sar_%03d_sub%d.parquet", tile_id, sub_id))
  arrow::write_parquet(data.table(grid_id=integer(), sum_dw=numeric(),
                                  sum_dw_pd=numeric(), sum_d=numeric(),
                                  n_with_pl=integer(), pl_sum=numeric()), out)
  cat("⚠️ Sortie vide (pas de lignes)\n"); quit("no", 0)
}

# Grille locale
bb_sub <- st_bbox(c(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax), crs=target_crs)
col_start <- as.integer((bb_sub["xmin"] - WORLD_XMIN) %/% CELL_SIZE_M)
col_end   <- as.integer((bb_sub["xmax"] - WORLD_XMIN) %/% CELL_SIZE_M)
row_start <- as.integer((bb_sub["ymin"] - WORLD_YMIN) %/% CELL_SIZE_M)
row_end   <- as.integer((bb_sub["ymax"] - WORLD_YMIN) %/% CELL_SIZE_M)

grid_sub <- st_make_grid(
  offset   = c(WORLD_XMIN + col_start * CELL_SIZE_M,
               WORLD_YMIN + row_start * CELL_SIZE_M),
  cellsize = CELL_SIZE_M,
  n        = c(col_end - col_start + 1, row_end - row_start + 1),
  crs      = target_crs,
  what     = "polygons"
) |> st_sf() |>
  dplyr::mutate(
    col     = col_start + ((dplyr::row_number() - 1) %% (col_end - col_start + 1)),
    row     = row_start + ((dplyr::row_number() - 1) %/% (col_end - col_start + 1)),
    grid_id = row * GRID_COLS + col + 1L
  )

# Intersections SAR
res <- data.table(grid_id=integer(), sum_dw=numeric(), sum_dw_pd=numeric(), sum_d=numeric())
for (i in seq_len(nrow(lines_sf))) {
  cand <- sf::st_intersects(lines_sf[i,], grid_sub, sparse = FALSE)[1, ]
  if (!any(cand)) next
  inter <- sf::st_intersection(lines_sf[i,], grid_sub[cand,])
  if (!nrow(inter)) next
  len <- as.numeric(st_length(inter))
  res_i <- data.table(grid_id = inter$grid_id,
                      sum_dw  = len * lines_sf$W_v[i],
                      sum_dw_pd = len * lines_sf$W_v[i] * lines_sf$p_d_i[i],
                      sum_d   = len)
  res[res_i, on="grid_id", `:=`(
    sum_dw    = ifelse(is.na(sum_dw),    i.sum_dw,    sum_dw    + i.sum_dw),
    sum_dw_pd = ifelse(is.na(sum_dw_pd), i.sum_dw_pd, sum_dw_pd + i.sum_dw_pd),
    sum_d     = ifelse(is.na(sum_d),     i.sum_d,     sum_d     + i.sum_d)
  )]
  new_rows <- res_i[!res, on="grid_id"]
  if (nrow(new_rows) > 0) res <- rbindlist(list(res, new_rows), use.names=TRUE)
}

# Moyenne simple p_l sur pings de la sous-tuile (≤10 km) — basé sur pl_eff
if(!"dist_km" %in% names(dredge)) dredge[, dist_km := NA_real_]
dredge[, use_for_carbon := is.finite(pl_eff) & (is.na(dist_km) | dist_km <= 10)]
pl_cell <- dredge[use_for_carbon==TRUE & is.finite(pl_eff),
                  .(n_with_pl=.N, pl_sum=sum(pl_eff, na.rm=TRUE)),
                  by = grid_id]
res <- merge(res, pl_cell, by="grid_id", all.x=TRUE)
res[is.na(n_with_pl), `:=`(n_with_pl=0L, pl_sum=0)]

# Sauvegarde
output_file <- file.path(Sys.getenv("OUT_DIR","~/scratch/output_V6"), sprintf("sar_%03d_sub%d.parquet", tile_id, sub_id))
arrow::write_parquet(res, output_file)
cat(sprintf("✅ Sous-tuile %d_%d : %d cellules\n", tile_id, sub_id, nrow(res)))
