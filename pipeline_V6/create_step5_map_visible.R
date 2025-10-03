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

# 4. Créer la carte avec fond blanc et points plus visibles
p <- ggplot() +
  # Fond blanc
  theme_minimal() +
  theme(
    panel.background = element_rect(fill = "white"),
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank(),
    legend.position = "bottom",
    legend.key.width = unit(2, "cm"),
    plot.background = element_rect(fill = "white")
  ) +
  
  # Points colorés selon f_i_full (plus gros et plus opaques)
  geom_sf(data = sf_step5, 
          aes(color = f_i_full), 
          size = 0.8, alpha = 0.9) +
  
  # Échelle de couleurs plus contrastée
  scale_color_gradient2(
    name = "f_i",
    low = "darkblue", mid = "green", high = "red",
    midpoint = median(sf_step5$f_i_full, na.rm = TRUE),
    na.value = "transparent"
  ) +
  
  # Limites de la carte
  coord_sf(crs = 4326, expand = FALSE)

# 5. Sauvegarder
ggsave("~/scratch/step5_global_map_visible.png", 
       p, width = 12, height = 8, dpi = 300, bg = "white")

cat("✅ Carte visible sauvegardée : ~/scratch/step5_global_map_visible.png\n")
cat("�� Statistiques f_i :\n")
cat("   Min:", min(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Max:", max(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Médiane:", median(dt_step5$f_i_full, na.rm=TRUE), "\n")
cat("   Cellules > 0:", sum(dt_step5$f_i_full > 0, na.rm=TRUE), "\n")
