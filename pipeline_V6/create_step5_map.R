library(sf)
library(data.table)
library(arrow)
library(ggplot2)

# 1. Charger les résultats Step 5
f_step5 <- "~/scratch/output_V6/fi_grid_20250728_173932.parquet"
dt_step5 <- setDT(read_parquet(f_step5))

# 2. Calculer les coordonnées
GRID_COLS <- 36000L
CELL <- 1000
WORLD_XMIN <- -18000000
WORLD_YMAX <- 9000000

dt_step5[, `:=`(
  col = as.integer((grid_id-1L) %% GRID_COLS),
  row = as.integer((grid_id-1L) %/% GRID_COLS),
  x = WORLD_XMIN + col*CELL + CELL/2,
  y = WORLD_YMAX - row*CELL - CELL/2
)]

# 3. Convertir en objet spatial
sf_step5 <- st_as_sf(dt_step5, coords = c("x", "y"), crs = 6933) |>
  st_transform(4326)

# 4. Créer la carte
p <- ggplot() +
  # Fond de carte (grille simple)
  geom_sf(data = st_graticule(lat = seq(-90, 90, 30), lon = seq(-180, 180, 60)), 
          color = "gray20", size = 0.2) +
  
  # Points colorés selon f_i_full
  geom_sf(data = sf_step5, 
          aes(color = f_i_full), 
          size = 0.3, alpha = 0.7) +
  
  # Échelle de couleurs (sans viridis)
  scale_color_gradient2(
    name = "f_i",
    low = "blue", mid = "green", high = "red",
    midpoint = median(sf_step5$f_i_full, na.rm = TRUE),
    trans = "log10",
    na.value = "transparent"
  ) +
  
  # Thème
  theme_minimal() +
  theme(
    panel.background = element_rect(fill = "black"),
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank(),
    legend.position = "bottom",
    legend.key.width = unit(2, "cm"),
    plot.background = element_rect(fill = "black"),
    text = element_text(color = "white")
  ) +
  
  # Limites de la carte
  coord_sf(crs = 4326, expand = FALSE)

# 5. Sauvegarder
ggsave("~/scratch/step5_global_map.png", 
       p, width = 12, height = 8, dpi = 300, bg = "black")

cat("✅ Carte sauvegardée : ~/scratch/step5_global_map.png\n")
cat("�� Statistiques f_i :\n")
cat("   Min:", min(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Max:", max(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Médiane:", median(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Cellules > 0:", sum(dt_step5$f_i_full > 0, na.rm=TRUE), "\n")
