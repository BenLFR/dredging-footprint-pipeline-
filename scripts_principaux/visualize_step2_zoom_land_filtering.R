#!/usr/bin/env Rscript
# =============================================================================
# VISUALISATION ZOOMÉE - FILTRAGE TERRE vs MER - PUBLICATION READY
# =============================================================================
# Crée des cartes zoomées sur des zones côtières montrant :
# - Points conservés (bleu foncé)
# - Points supprimés (rouge)
# - Fond de carte terre/mer bien visible

library(data.table)
library(ggplot2)
library(sf)
library(ggspatial)
library(gridExtra)
library(grid)

# Désactiver s2 pour éviter les erreurs de géométrie sphérique
sf_use_s2(FALSE)

# Fonction pour créer une flèche nord simple
north_arrow_simple <- function(x, y, size = 0.02) {
  list(
    annotate("segment", x = x, xend = x, y = y, yend = y + size,
             arrow = arrow(length = unit(0.3, "cm"), type = "closed"),
             color = "black", linewidth = 1),
    annotate("text", x = x, y = y + size + size*0.3, label = "N",
             fontface = "bold", size = 5)
  )
}

# =============================================================================
# CONFIGURATION
# =============================================================================
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  cat("Usage: Rscript visualize_step2_zoom_land_filtering.R <navire_num> <split_job_id> <process_job_id>\n")
  cat("Exemple: Rscript visualize_step2_zoom_land_filtering.R 8 12990 13289\n")
  quit(status = 1)
}

navire_num <- as.integer(args[1])
split_job_id <- args[2]
process_job_id <- args[3]

# Chemins des fichiers
input_dir <- sprintf("~/scratch/ais_split_%s", split_job_id)
output_dir <- sprintf("~/scratch/ais_results_%s", process_job_id)

# =============================================================================
# CHARGEMENT DES DONNÉES
# =============================================================================
cat("📖 Chargement des données...\n")

# Trouver les fichiers
input_files <- list.files(path.expand(input_dir), pattern = "\\.rds$", full.names = TRUE)
output_files <- list.files(path.expand(output_dir), pattern = "_clean\\.rds$", full.names = TRUE)

input_file <- input_files[navire_num]
output_file <- output_files[grepl(sprintf("^%02d_", navire_num), basename(output_files))]

if (length(input_file) == 0 || length(output_file) == 0) {
  stop("❌ Fichiers introuvables pour navire ", navire_num)
}

# Extraire le nom du navire
navire_name <- gsub(".*navire_\\d+_(.+)\\.rds", "\\1", input_file)
navire_name <- gsub("_", " ", navire_name)

cat("📍 Navire:", navire_name, "\n")
cat("📁 Avant:", basename(input_file), "\n")
cat("📁 Après:", basename(output_file), "\n\n")

# Charger les données
dt_before <- readRDS(input_file)
setDT(dt_before)

dt_after <- readRDS(output_file)
setDT(dt_after)

cat(sprintf("  • Avant: %s observations\n", format(nrow(dt_before), big.mark = ",")))
cat(sprintf("  • Après: %s observations\n", format(nrow(dt_after), big.mark = ",")))
cat(sprintf("  • Supprimés: %s (%.1f%%)\n\n",
            format(nrow(dt_before) - nrow(dt_after), big.mark = ","),
            100 * (1 - nrow(dt_after) / nrow(dt_before))))

# =============================================================================
# IDENTIFIER LES POINTS SUPPRIMÉS
# =============================================================================
cat("🔍 Identification des points supprimés...\n")

# Créer une clé unique
dt_before[, point_key := paste(Timestamp, round(Lat, 6), round(Lon, 6), sep = "_")]
dt_after[, point_key := paste(Timestamp, round(Lat, 6), round(Lon, 6), sep = "_")]

# Points supprimés
removed_keys <- setdiff(dt_before$point_key, dt_after$point_key)
dt_removed <- dt_before[point_key %in% removed_keys]
dt_kept <- dt_before[point_key %in% dt_after$point_key]

cat(sprintf("  • Points conservés: %s\n", format(nrow(dt_kept), big.mark = ",")))
cat(sprintf("  • Points supprimés: %s\n", format(nrow(dt_removed), big.mark = ",")))

# =============================================================================
# CHARGER LE MASQUE TERRE POUR IDENTIFIER LES TYPES DE FILTRAGE
# =============================================================================
cat("\n🌍 Chargement du masque terre pour classification...\n")
land_mask_path <- "~/ais-pipeline/configuration/land_mask/land_polygons.shp"
land_mask_path_exp <- path.expand(land_mask_path)

if (!file.exists(land_mask_path_exp)) {
  stop("❌ Masque terre introuvable: ", land_mask_path_exp)
}

land_polygons <- st_read(land_mask_path_exp, quiet = TRUE)
cat(sprintf("  • Masque chargé: %s polygones\n", format(nrow(land_polygons), big.mark = ",")))

# =============================================================================
# CLASSIFIER LES POINTS SUPPRIMÉS PAR TYPE
# =============================================================================
cat("\n🔍 Classification des points supprimés par type...\n")

# Fonction haversine
haversine_nm <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  c <- 2 * atan2(sqrt(a), sqrt(1 - a))
  (r * c) / 1852
}

# Initialiser la colonne de type
dt_removed[, removal_type := "unknown"]
dt_kept[, removal_type := "kept"]

if (nrow(dt_removed) > 0) {
  # 1. Identifier les points sur terre
  cat("  • Vérification points sur terre...\n")
  pts_sf <- st_as_sf(dt_removed, coords = c("Lon", "Lat"), crs = 4326, remove = FALSE)

  # Créer bbox élargie
  bbox_all <- st_bbox(pts_sf)
  bbox_buffer <- 0.5  # degrés
  bbox_exp <- bbox_all + c(-bbox_buffer, -bbox_buffer, bbox_buffer, bbox_buffer)

  # Cropper le masque terre
  land_crop <- tryCatch({
    st_crop(land_polygons, bbox_exp)
  }, error = function(e) {
    land_polygons
  })

  # Tester intersection
  on_land <- lengths(st_intersects(pts_sf, land_crop)) > 0
  dt_removed[on_land == TRUE, removal_type := "on_land"]

  cat(sprintf("    → %s points sur terre\n", format(sum(on_land), big.mark = ",")))

  # 2. Identifier les spikes GPS (sauts > 1nm avec retour < 0.3nm)
  cat("  • Vérification spikes GPS...\n")
  setorder(dt_removed, Timestamp)
  dt_removed[, `:=`(
    dist_prev = haversine_nm(shift(Lat), shift(Lon), Lat, Lon),
    dist_next = haversine_nm(Lat, Lon, shift(Lat, type = "lead"), shift(Lon, type = "lead"))
  )]
  dt_removed[, dist_prev_next := haversine_nm(shift(Lat), shift(Lon),
                                              shift(Lat, type = "lead"),
                                              shift(Lon, type = "lead"))]

  is_spike <- dt_removed$dist_prev > 1 & dt_removed$dist_next > 1 & dt_removed$dist_prev_next < 0.3
  is_spike[is.na(is_spike)] <- FALSE
  dt_removed[is_spike == TRUE & removal_type == "unknown", removal_type := "spike"]

  cat(sprintf("    → %s spikes GPS\n", format(sum(is_spike, na.rm = TRUE), big.mark = ",")))

  # 3. Le reste = segments traversant la terre
  n_crosses <- sum(dt_removed$removal_type == "unknown")
  dt_removed[removal_type == "unknown", removal_type := "crosses_land"]

  cat(sprintf("    → %s segments traversant terre\n", format(n_crosses, big.mark = ",")))

  # Nettoyer colonnes temporaires
  dt_removed[, c("dist_prev", "dist_next", "dist_prev_next") := NULL]
}

cat("\n📊 Résumé par type:\n")
summary_types <- rbind(
  dt_kept[, .(type = "kept", n = .N)],
  dt_removed[, .N, by = removal_type][, .(type = removal_type, n = N)]
)
for (i in 1:nrow(summary_types)) {
  cat(sprintf("  • %s: %s\n", summary_types[i]$type, format(summary_types[i]$n, big.mark = ",")))
}

# =============================================================================
# TROUVER LES ZONES AVEC LE PLUS DE POINTS SUPPRIMÉS (ZONES CÔTIÈRES)
# =============================================================================
cat("🗺️  Identification des zones côtières avec filtrage...\n")

if (nrow(dt_removed) == 0) {
  stop("❌ Aucun point supprimé à visualiser!")
}

# Créer une grille pour compter les points supprimés
grid_size <- 0.5  # degrés (environ 50 km)
dt_removed[, `:=`(
  lon_bin = floor(Lon / grid_size) * grid_size,
  lat_bin = floor(Lat / grid_size) * grid_size
)]

# Compter les points par cellule
grid_counts <- dt_removed[, .(n_removed = .N), by = .(lon_bin, lat_bin)]
setorder(grid_counts, -n_removed)

cat(sprintf("  • Top 3 zones avec le plus de points supprimés:\n"))
for (i in 1:min(3, nrow(grid_counts))) {
  cat(sprintf("    %d. Lon: %.2f°, Lat: %.2f° - %s points\n",
              i, grid_counts[i]$lon_bin, grid_counts[i]$lat_bin,
              format(grid_counts[i]$n_removed, big.mark = ",")))
}

# Sélectionner les 3 zones les plus intéressantes
n_zones <- min(3, nrow(grid_counts))
zones <- grid_counts[1:n_zones]

cat("\n✅ Masque terre déjà chargé, prêt pour visualisation\n")

# =============================================================================
# FONCTION DE CRÉATION DE CARTE ZOOMÉE
# =============================================================================
create_zoom_map <- function(zone_idx, lon_center, lat_center, zoom_size = 0.3) {

  # Définir la bbox zoomée (environ 30-35 km de côté)
  bbox_zoom <- c(
    xmin = lon_center - zoom_size,
    xmax = lon_center + zoom_size,
    ymin = lat_center - zoom_size,
    ymax = lat_center + zoom_size
  )

  cat(sprintf("\n📍 Zone %d: %.2f°E, %.2f°N (zoom: %.1f km)\n",
              zone_idx, lon_center, lat_center, zoom_size * 111))

  # Cropper le fond de carte
  land_crop <- tryCatch({
    st_crop(land_polygons, bbox_zoom)
  }, error = function(e) {
    # Si le crop échoue, utiliser un buffer autour de la zone
    bbox_sf <- st_as_sfc(st_bbox(bbox_zoom, crs = 4326))
    st_intersection(land_polygons, bbox_sf)
  })

  # Filtrer les points dans cette zone
  dt_kept_zone <- dt_kept[Lon >= bbox_zoom["xmin"] & Lon <= bbox_zoom["xmax"] &
                          Lat >= bbox_zoom["ymin"] & Lat <= bbox_zoom["ymax"]]

  dt_removed_zone <- dt_removed[Lon >= bbox_zoom["xmin"] & Lon <= bbox_zoom["xmax"] &
                                Lat >= bbox_zoom["ymin"] & Lat <= bbox_zoom["ymax"]]

  cat(sprintf("  • Points conservés: %s\n", format(nrow(dt_kept_zone), big.mark = ",")))
  cat(sprintf("  • Points supprimés: %s\n", format(nrow(dt_removed_zone), big.mark = ",")))

  # Sous-échantillonner si trop de points (pour la lisibilité)
  max_points <- 5000
  if (nrow(dt_kept_zone) > max_points) {
    dt_kept_zone <- dt_kept_zone[sample(.N, max_points)]
  }
  if (nrow(dt_removed_zone) > max_points) {
    dt_removed_zone <- dt_removed_zone[sample(.N, max_points)]
  }

  # Créer la carte
  p <- ggplot() +
    # Fond de mer (bleu très clair)
    theme(panel.background = element_rect(fill = "#e6f2ff")) +

    # Terre (beige/gris clair)
    geom_sf(data = land_crop, fill = "#f5f5dc", color = "#8b7355", linewidth = 0.5) +

    # Coordonnées
    coord_sf(xlim = c(bbox_zoom["xmin"], bbox_zoom["xmax"]),
             ylim = c(bbox_zoom["ymin"], bbox_zoom["ymax"]),
             expand = FALSE)

  # Points conservés (bleu marine, dessous)
  if (nrow(dt_kept_zone) > 0) {
    p <- p + geom_point(data = dt_kept_zone,
                       aes(x = Lon, y = Lat),
                       color = "#1f4788", size = 0.8, alpha = 0.5,
                       shape = 16)
  }

  # Points supprimés - DIFFÉRENCIÉS PAR TYPE
  if (nrow(dt_removed_zone) > 0) {
    # Compter par type
    type_counts <- dt_removed_zone[, .N, by = removal_type]
    cat(sprintf("  • Types: %s\n", paste(sprintf("%s=%d", type_counts$removal_type, type_counts$N), collapse = ", ")))

    # 1. Points sur terre (rouge vif)
    dt_on_land <- dt_removed_zone[removal_type == "on_land"]
    if (nrow(dt_on_land) > 0) {
      p <- p + geom_point(data = dt_on_land,
                         aes(x = Lon, y = Lat),
                         color = "#d62728", size = 1.5, alpha = 0.9,
                         shape = 16)
    }

    # 2. Segments traversant terre (orange)
    dt_crosses <- dt_removed_zone[removal_type == "crosses_land"]
    if (nrow(dt_crosses) > 0) {
      p <- p + geom_point(data = dt_crosses,
                         aes(x = Lon, y = Lat),
                         color = "#ff7f0e", size = 1.3, alpha = 0.8,
                         shape = 16)
    }

    # 3. Spikes GPS (jaune/or)
    dt_spikes <- dt_removed_zone[removal_type == "spike"]
    if (nrow(dt_spikes) > 0) {
      p <- p + geom_point(data = dt_spikes,
                         aes(x = Lon, y = Lat),
                         color = "#ffd700", size = 1.2, alpha = 0.8,
                         shape = 17)  # Triangle pour différencier
    }
  }

  # Annotations
  p <- p +
    annotation_scale(location = "bl", width_hint = 0.25,
                    text_cex = 1, line_width = 1.2,
                    style = "ticks") +
    north_arrow_simple(x = bbox_zoom["xmax"] - 0.02,
                      y = bbox_zoom["ymax"] - 0.02,
                      size = 0.015) +

    # Légende manuelle (4 catégories)
    annotate("rect", xmin = bbox_zoom["xmin"] + 0.015,
             xmax = bbox_zoom["xmin"] + 0.095,
             ymin = bbox_zoom["ymax"] - 0.10,
             ymax = bbox_zoom["ymax"] - 0.015,
             fill = "white", color = "black", linewidth = 0.6, alpha = 0.9) +

    # Kept (bleu)
    annotate("point",
             x = bbox_zoom["xmin"] + 0.025,
             y = bbox_zoom["ymax"] - 0.03,
             color = "#1f4788", size = 2.5, shape = 16) +
    annotate("text",
             x = bbox_zoom["xmin"] + 0.032,
             y = bbox_zoom["ymax"] - 0.03,
             label = "Kept", hjust = 0, size = 2.8, fontface = "bold") +

    # On land (rouge)
    annotate("point",
             x = bbox_zoom["xmin"] + 0.025,
             y = bbox_zoom["ymax"] - 0.045,
             color = "#d62728", size = 3, shape = 16) +
    annotate("text",
             x = bbox_zoom["xmin"] + 0.032,
             y = bbox_zoom["ymax"] - 0.045,
             label = "On land", hjust = 0, size = 2.8, fontface = "bold") +

    # Crosses land (orange)
    annotate("point",
             x = bbox_zoom["xmin"] + 0.025,
             y = bbox_zoom["ymax"] - 0.065,
             color = "#ff7f0e", size = 2.8, shape = 16) +
    annotate("text",
             x = bbox_zoom["xmin"] + 0.032,
             y = bbox_zoom["ymax"] - 0.065,
             label = "Crosses land", hjust = 0, size = 2.8, fontface = "bold") +

    # Spike GPS (jaune)
    annotate("point",
             x = bbox_zoom["xmin"] + 0.025,
             y = bbox_zoom["ymax"] - 0.085,
             color = "#ffd700", size = 2.8, shape = 17) +
    annotate("text",
             x = bbox_zoom["xmin"] + 0.032,
             y = bbox_zoom["ymax"] - 0.085,
             label = "GPS spike", hjust = 0, size = 2.8, fontface = "bold") +

    # Titre et labels
    labs(
      title = sprintf("Zone %d: Geospatial Filtering Detail", zone_idx),
      subtitle = sprintf("%.3f°–%.3f°E / %.3f°–%.3f°N",
                        bbox_zoom["xmin"], bbox_zoom["xmax"],
                        bbox_zoom["ymin"], bbox_zoom["ymax"]),
      x = "Longitude (°E)",
      y = "Latitude (°N)"
    ) +

    # Thème
    theme_bw() +
    theme(
      plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5, color = "grey30"),
      axis.title = element_text(size = 11, face = "bold"),
      axis.text = element_text(size = 9),
      panel.grid.major = element_line(color = "grey80", linewidth = 0.3, linetype = "dotted"),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(color = "black", linewidth = 1),
      plot.margin = margin(10, 10, 10, 10)
    )

  return(p)
}

# =============================================================================
# CRÉER LES CARTES ZOOMÉES POUR LES ZONES SÉLECTIONNÉES
# =============================================================================
cat("\n🎨 Création des cartes zoomées...\n")

plots_list <- list()

for (i in 1:n_zones) {
  lon_c <- zones[i]$lon_bin + grid_size/2
  lat_c <- zones[i]$lat_bin + grid_size/2

  plots_list[[i]] <- create_zoom_map(i, lon_c, lat_c, zoom_size = 0.15)
}

# =============================================================================
# SAUVEGARDER LES FIGURES
# =============================================================================
cat("\n💾 Sauvegarde des figures...\n")

output_dir_plot <- "~/ais-pipeline/Resultats"
dir.create(path.expand(output_dir_plot), recursive = TRUE, showWarnings = FALSE)

# Figure combinée avec les 3 zones
if (n_zones >= 3) {
  output_file_combined <- sprintf("%s/step2_zoom_land_filtering_vessel_%02d_3zones.png",
                                  output_dir_plot, navire_num)
  output_file_combined <- path.expand(output_file_combined)

  png(output_file_combined, width = 4500, height = 1500, res = 300)
  grid.arrange(
    grobs = plots_list[1:3],
    ncol = 3,
    top = textGrob(sprintf('TSHD "%s" – Step 2: Land & Anomaly Filtering (Zoomed Views)',
                          navire_name),
                   gp = gpar(fontsize = 16, fontface = "bold"))
  )
  dev.off()

  cat(sprintf("  ✅ Figure 3 zones: %s\n", output_file_combined))
}

# Figures individuelles haute résolution
for (i in 1:n_zones) {
  output_file_single <- sprintf("%s/step2_zoom_land_filtering_vessel_%02d_zone%d.png",
                               output_dir_plot, navire_num, i)
  output_file_single <- path.expand(output_file_single)

  png(output_file_single, width = 2000, height = 2000, res = 300)
  print(plots_list[[i]])
  dev.off()

  cat(sprintf("  ✅ Zone %d: %s\n", i, output_file_single))
}

# =============================================================================
# RÉSUMÉ
# =============================================================================
cat("\n" %+% strrep("=", 70) %+% "\n")
cat("📊 RÉSUMÉ\n")
cat(strrep("=", 70) %+% "\n")
cat(sprintf("Navire: %s\n", navire_name))
cat(sprintf("Points d'origine: %s\n", format(nrow(dt_before), big.mark = ",")))
cat(sprintf("Points conservés: %s (%.1f%%)\n",
            format(nrow(dt_kept), big.mark = ","),
            100 * nrow(dt_kept) / nrow(dt_before)))
cat(sprintf("Points supprimés: %s (%.1f%%)\n",
            format(nrow(dt_removed), big.mark = ","),
            100 * nrow(dt_removed) / nrow(dt_before)))
cat(sprintf("\nZones visualisées: %d\n", n_zones))
cat(sprintf("Figures créées: %d\n", n_zones + 1))
cat("\n✅ Visualisation terminée avec succès!\n")
