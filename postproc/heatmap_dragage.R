#!/usr/bin/env Rscript
# Global dredging activity heat-map (0.25-degree grid)
# author: ...                       date: 2025-08

suppressPackageStartupMessages({
  library(data.table)   # fast I/O
  library(sf)           # spatial geometry
  library(ggplot2)      # plotting
  library(RColorBrewer) # colour palettes
  library(maps)         # coastline
})

## ── 1. data ─────────────────────────────────────────────────────────
ais_rds <- Sys.getenv("AIS_INPUT_RDS", "~/scratch/output_V6/AIS_data_core_preprocessed_V6_latest_flagOK.rds")
stopifnot(file.exists(ais_rds))

dt <- as.data.table(readRDS(ais_rds))[Dragage_flag == 1, .(Lon, Lat)]
cat("Pings dragage :", format(nrow(dt), big.mark = " "), "\n")

## ── 2. 0.25-degree grid and point count ──────────────────────────────
cell_deg <- 0.25                               # ≈ 25 km
world_bb <- st_as_sfc(st_bbox(c(xmin=-180,ymin=-90,xmax=180,ymax=90), crs=4326))

grid_sf  <- st_make_grid(world_bb,
                         cellsize = cell_deg,
                         what     = "polygons",
                         square   = TRUE) |>
            st_sf() |>
            st_set_agr("constant")

# count how many dredging points fall in each cell
ints          <- st_intersects(grid_sf, st_as_sf(dt, coords=c("Lon","Lat"), crs=4326))
grid_sf$n     <- lengths(ints)                  # count per cell
rob_crs       <- "+proj=robin +lon_0=0 +datum=WGS84"
grid_rob      <- st_transform(grid_sf[grid_sf$n > 0, ], rob_crs)

## ── 4. palette & breaks (log10) ────────────────────────────────────────
grid_rob$log_n <- log10(grid_rob$n)
log_breaks     <- floor(range(grid_rob$log_n))  # e.g. 0 – 4
log_breaks     <- seq(log_breaks[1], log_breaks[2])

## ── 5. plot ────────────────────────────────────────────────────────────
gg <- ggplot() +
  geom_sf(data = grid_rob, aes(fill = log_n), colour = NA) +
  # coastline: uses the 'maps' package base layer
  borders("world", colour = "grey30", fill = NA, size = .15) +
  scale_fill_distiller(
      palette = "YlOrRd", direction = 1, name = expression(log[10]~"pings"),
      breaks  = log_breaks, labels = log_breaks, trans = "identity",
      guide   = guide_colorbar(barheight = 12, barwidth = .8)) +
  coord_sf(crs = rob_crs, expand = FALSE) +
  labs(title    = "Densité mondiale des points de dragage",
       subtitle = sprintf("grille 0,25°  •  total pings : %s",
                          format(nrow(dt), big.mark = " ")),
       caption  = "Source : AIS (pipeline V6)  –  Projection : Robinson") +
  theme_minimal(base_family = "Arial") +
  theme(panel.grid     = element_blank(),
        axis.text      = element_blank(),
        axis.ticks     = element_blank(),
        legend.position= "bottom")

ggsave("heatmap_dragage_grid025_robinson.png",
       gg, width = 14, height = 7, dpi = 450)

cat("  Image écrite : heatmap_dragage_grid025_robinson.png\n")
