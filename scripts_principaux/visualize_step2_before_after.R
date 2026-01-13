#!/usr/bin/env Rscript
# =============================================================================
# VISUALISATION AVANT/APRÈS STEP 2 - PUBLICATION READY
# =============================================================================
# Crée une carte comparative avant/après nettoyage géospatial
# Style: publication-ready avec titre, coordonnées, échelle, nord

library(data.table)
library(ggplot2)
library(sf)
library(rnaturalearth)
library(ggspatial)
library(gridExtra)
library(viridis)

# =============================================================================
# CONFIGURATION
# =============================================================================
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  cat("Usage: Rscript visualize_step2_before_after.R <navire_num> <split_job_id> <process_job_id>\n")
  cat("Exemple: Rscript visualize_step2_before_after.R 8 12990 13289\n")
  quit(status = 1)
}

navire_num <- as.integer(args[1])
split_job_id <- args[2]
process_job_id <- args[3]

# Chemins des fichiers
input_dir <- sprintf("~/scratch/ais_split_%s", split_job_id)
output_dir <- sprintf("~/scratch/ais_results_%s", process_job_id)

# Trouver les fichiers
input_files <- list.files(path.expand(input_dir), pattern = "\\.rds$", full.names = TRUE)
output_files <- list.files(path.expand(output_dir), pattern = "_clean\\.rds$", full.names = TRUE)

# Sélectionner le navire
input_file <- input_files[navire_num]
output_file <- output_files[grepl(sprintf("^%02d_", navire_num), basename(output_files))]

if (length(input_file) == 0 || length(output_file) == 0) {
  stop("Fichiers introuvables pour navire ", navire_num)
}

# Extraire le nom du navire
navire_name <- gsub(".*navire_\\d+_(.+)\\.rds", "\\1", input_file)
navire_name <- gsub("_", " ", navire_name)

cat("📍 Navire sélectionné:", navire_name, "\n")
cat("📁 Fichier avant:", input_file, "\n")
cat("📁 Fichier après:", output_file, "\n")

# =============================================================================
# CHARGEMENT DES DONNÉES
# =============================================================================
cat("\n📖 Chargement des données...\n")
dt_before <- readRDS(input_file)
setDT(dt_before)
dt_before[, status := "Before"]

dt_after <- readRDS(output_file)
setDT(dt_after)
dt_after[, status := "After"]

cat(sprintf("  • Avant: %s observations\n", format(nrow(dt_before), big.mark = ",")))
cat(sprintf("  • Après: %s observations\n", format(nrow(dt_after), big.mark = ",")))
cat(sprintf("  • Supprimés: %s (%.1f%%)\n",
            format(nrow(dt_before) - nrow(dt_after), big.mark = ","),
            100 * (1 - nrow(dt_after) / nrow(dt_before))))

# =============================================================================
# IDENTIFIER LES POINTS SUPPRIMÉS
# =============================================================================
cat("\n🔍 Identification des points supprimés...\n")

# Créer une clé unique pour chaque point (timestamp + lat + lon)
dt_before[, point_key := paste(Timestamp, round(Lat, 6), round(Lon, 6), sep = "_")]
dt_after[, point_key := paste(Timestamp, round(Lat, 6), round(Lon, 6), sep = "_")]

# Identifier les points supprimés
removed_keys <- setdiff(dt_before$point_key, dt_after$point_key)
dt_removed <- dt_before[point_key %in% removed_keys]
dt_removed[, status := "Removed"]

cat(sprintf("  • Points supprimés identifiés: %s\n", format(nrow(dt_removed), big.mark = ",")))

# =============================================================================
# CALCUL DE LA BOUNDING BOX
# =============================================================================
bbox <- c(
  xmin = min(dt_before$Lon, na.rm = TRUE),
  xmax = max(dt_before$Lon, na.rm = TRUE),
  ymin = min(dt_before$Lat, na.rm = TRUE),
  ymax = max(dt_before$Lat, na.rm = TRUE)
)

# Ajouter une marge de 5%
margin <- 0.05
lon_range <- bbox["xmax"] - bbox["xmin"]
lat_range <- bbox["ymax"] - bbox["ymin"]
bbox["xmin"] <- bbox["xmin"] - lon_range * margin
bbox["xmax"] <- bbox["xmax"] + lon_range * margin
bbox["ymin"] <- bbox["ymin"] - lat_range * margin
bbox["ymax"] <- bbox["ymax"] + lat_range * margin

cat(sprintf("\n📐 Bounding box: %.2f°E-%.2f°E, %.2f°N-%.2f°N\n",
            bbox["xmin"], bbox["xmax"], bbox["ymin"], bbox["ymax"]))

# =============================================================================
# CHARGEMENT DU FOND DE CARTE
# =============================================================================
cat("\n🗺️  Chargement du fond de carte...\n")

# Charger les terres (Natural Earth)
world <- ne_countries(scale = "medium", returnclass = "sf")
land <- st_crop(world, bbox)

# Charger le masque terre haute résolution si disponible
land_mask_path <- "~/ais-pipeline/configuration/land_mask/land_polygons.shp"
if (file.exists(path.expand(land_mask_path))) {
  cat("  • Chargement masque terre haute résolution...\n")
  land_hr <- st_read(path.expand(land_mask_path), quiet = TRUE)
  land_hr <- st_crop(land_hr, bbox)
} else {
  cat("  • Masque haute résolution non trouvé, utilisation Natural Earth\n")
  land_hr <- land
}

# =============================================================================
# CRÉATION DES CARTES
# =============================================================================
cat("\n🎨 Création des cartes...\n")

# Sous-échantillonnage pour la visualisation (max 50k points par carte)
max_points <- 50000
if (nrow(dt_before) > max_points) {
  sample_idx <- sample(1:nrow(dt_before), max_points)
  dt_before_plot <- dt_before[sample_idx]
  dt_after_plot <- dt_after[sample(1:min(nrow(dt_after), max_points))]
  dt_removed_plot <- dt_removed[sample(1:min(nrow(dt_removed), max_points))]
  cat(sprintf("  • Sous-échantillonnage à %s points pour la visualisation\n",
              format(max_points, big.mark = ",")))
} else {
  dt_before_plot <- dt_before
  dt_after_plot <- dt_after
  dt_removed_plot <- dt_removed
}

# Fonction pour créer une carte
create_map <- function(data, title, subtitle, show_removed = FALSE) {
  p <- ggplot() +
    # Fond de mer
    geom_sf(data = land_hr, fill = "grey85", color = "grey60", linewidth = 0.3) +
    coord_sf(xlim = c(bbox["xmin"], bbox["xmax"]),
             ylim = c(bbox["ymin"], bbox["ymax"]),
             expand = FALSE)

  if (show_removed && nrow(dt_removed_plot) > 0) {
    # Points supprimés en rouge
    p <- p + geom_point(data = dt_removed_plot,
                       aes(x = Lon, y = Lat),
                       color = "#d62728", size = 0.5, alpha = 0.6)
  }

  # Points conservés en bleu
  if (!is.null(data) && nrow(data) > 0) {
    p <- p + geom_point(data = data,
                       aes(x = Lon, y = Lat),
                       color = "#1f77b4", size = 0.3, alpha = 0.4)
  }

  # Style publication
  p <- p +
    # Annotations géographiques
    annotation_scale(location = "bl", width_hint = 0.2,
                    text_cex = 0.8, line_width = 1) +
    annotation_north_arrow(location = "tr", which_north = "true",
                          height = unit(1, "cm"), width = unit(1, "cm"),
                          style = north_arrow_fancy_orienteering) +
    # Titre et labels
    labs(title = title,
         subtitle = subtitle,
         x = "Longitude (°E)",
         y = "Latitude (°N)") +
    # Thème
    theme_bw() +
    theme(
      plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5, color = "grey30"),
      axis.title = element_text(size = 10),
      axis.text = element_text(size = 8),
      panel.grid.major = element_line(color = "grey90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(fill = "aliceblue"),
      plot.margin = margin(10, 10, 10, 10)
    )

  return(p)
}

# Créer les trois panneaux
cat("  • Panneau (a): Avant nettoyage...\n")
p1 <- create_map(
  dt_before_plot,
  title = "(a) Before geospatial filtering",
  subtitle = sprintf("n = %s observations", format(nrow(dt_before), big.mark = ","))
)

cat("  • Panneau (b): Après nettoyage...\n")
p2 <- create_map(
  dt_after_plot,
  title = "(b) After geospatial filtering",
  subtitle = sprintf("n = %s observations", format(nrow(dt_after), big.mark = ","))
)

cat("  • Panneau (c): Points supprimés...\n")
p3 <- create_map(
  NULL,
  title = "(c) Removed points (on land / anomalies)",
  subtitle = sprintf("n = %s points removed (%.1f%%)",
                    format(nrow(dt_removed), big.mark = ","),
                    100 * nrow(dt_removed) / nrow(dt_before)),
  show_removed = TRUE
)

# =============================================================================
# ASSEMBLAGE FINAL
# =============================================================================
cat("\n📊 Assemblage de la figure finale...\n")

# Titre principal
main_title <- textGrob(
  sprintf('TSHD "%s" – Step 2: Geospatial Filtering', navire_name),
  gp = gpar(fontsize = 16, fontface = "bold")
)

subtitle <- textGrob(
  sprintf("%.2f°–%.2f°N / %.2f°–%.2f°E",
          bbox["ymin"], bbox["ymax"], bbox["xmin"], bbox["xmax"]),
  gp = gpar(fontsize = 12, col = "grey30")
)

# Assembler
output_file_plot <- sprintf("~/ais-pipeline/Resultats/step2_before_after_vessel_%02d.png",
                           navire_num)
output_file_plot <- path.expand(output_file_plot)

png(output_file_plot, width = 3600, height = 1400, res = 300)
grid.arrange(
  main_title, subtitle,
  arrangeGrob(p1, p2, p3, ncol = 3),
  ncol = 1, heights = c(0.08, 0.04, 1)
)
dev.off()

cat(sprintf("\n✅ Figure sauvegardée: %s\n", output_file_plot))

# =============================================================================
# STATISTIQUES SUPPLÉMENTAIRES
# =============================================================================
cat("\n📈 STATISTIQUES DÉTAILLÉES:\n")
cat(sprintf("  • Points d'origine: %s\n", format(nrow(dt_before), big.mark = ",")))
cat(sprintf("  • Points conservés: %s\n", format(nrow(dt_after), big.mark = ",")))
cat(sprintf("  • Points supprimés: %s (%.2f%%)\n",
            format(nrow(dt_removed), big.mark = ","),
            100 * nrow(dt_removed) / nrow(dt_before)))
cat(sprintf("  • Emprise géographique: %.1f × %.1f km\n",
            lon_range * 111, lat_range * 111))

cat("\n✅ Script terminé avec succès!\n")
