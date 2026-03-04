#!/usr/bin/env Rscript
# ====================================================================
# CARTE GLOBALE DE L'EMPREINTE DE DRAGAGE
# ====================================================================
# Ce script génère une carte globale de l'empreinte de dragage
# en utilisant les données de la step 5 du pipeline

# ─── VISUALISATION DE LA CARTE GLOBALE f_i ─────────────

library(terra)
library(sf)
library(ggplot2)
library(dplyr)
library(data.table)
library(viridisLite)  # Utiliser viridisLite au lieu de viridis

# 📂 1. Lire les données de grille (fichier spécifique Step 5)
library(arrow)

# Utiliser le fichier Step 5 le plus récent disponible
step5_file <- "~/scratch/output_V6/fi_grid_20250731_155047.parquet"

if(!file.exists(step5_file)) {
  stop("❌ Fichier Step 5 non trouvé: ", step5_file)
}

cat("✅ Fichier de grille Step 5 trouvé:", basename(step5_file), "\n")

fi_dt <- as.data.table(read_parquet(step5_file))

# (Optionnel) Lire les provinces Longhurst pour QC
longhurst_shp <- "~/scratch/configuration/longhurst.gpkg"      # adapte selon dispo
if(file.exists(longhurst_shp)) {
  longhurst <- st_read(longhurst_shp, quiet = TRUE)
} else {
  cat("⚠️ Fichier Longhurst non trouvé, visualisation sans contours\n")
  longhurst <- NULL
}

# 2. Convertir en sf pour visualisation
# Convertir en sf pour manip et plot
fi_dt[, col := (grid_id-1L) %% 36000L]
fi_dt[, row := (grid_id-1L) %/% 36000L]
fi_dt[, x := -18000000 + col*1000 + 500]
fi_dt[, y :=  9000000 - row*1000 - 500]
fi_sf <- st_as_sf(fi_dt, coords = c("x", "y"), crs = 6933)

# 3. Version ggplot rapide (pour publication ou carto avancée)
gg <- ggplot(fi_sf, aes(color = f_i_full, geometry = geometry)) +
  geom_sf(size = 0.07) +
  scale_color_viridis_c(trans = "log", option = "plasma") +
  labs(title = "Indice de perturbation f_i (globale, 1 km²)", color = "f_i") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "bottom")

# Ajouter les contours des provinces si disponibles
if(!is.null(longhurst)) {
  longhurst <- st_transform(longhurst, crs = 6933)
  gg <- gg + geom_sf(data = longhurst, fill = NA, color = "white", size = 0.2, inherit.aes = FALSE)
}

# (option) Exporter l'image haute résolution
ggsave("~/scratch/output_V6/fi_map_1km.png", plot = gg, width = 18, height = 9, dpi = 300)

# 4. Affichage et statistiques
print(gg)

# Statistiques sur les données
cat("\n📊 STATISTIQUES:\n")
cat("   Total grid cells:", nrow(fi_dt), "\n")
cat("   Cells avec f_i > 0:", sum(fi_dt$f_i_full > 0), "\n")
cat("   f_i moyen:", mean(fi_dt$f_i_full, na.rm = TRUE), "\n")
cat("   f_i médian:", median(fi_dt$f_i_full, na.rm = TRUE), "\n")
cat("   f_i max:", max(fi_dt$f_i_full, na.rm = TRUE), "\n")
cat("   Couverture géographique:\n")
cat("     X:", range(fi_dt$x), "\n")
cat("     Y:", range(fi_dt$y), "\n")

cat("\n✅ Carte exportée: ~/scratch/output_V6/fi_map_1km.png\n") 