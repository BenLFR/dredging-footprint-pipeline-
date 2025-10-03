#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  WORKER TUILE (pipeline V6, cluster Rorqual) - VERSION CORRIGÉE
# Traite une tuile individuelle avec gestion mémoire optimisée
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques ------------------------------------------------------------
pkgs <- c("sf","dplyr","data.table","tidyr","rlang","tidyselect","lubridate","yaml","arrow")   

safe_library <- function(pkg){
  tryCatch({ library(pkg, character.only = TRUE)
             cat("✅", pkg, "OK\n")},
           error=function(e) stop("❌ Package manquant : ", pkg, "\nMessage : ", e$message))   
}

# Chargement robuste de sf
tryCatch({
  library(sf)
  cat("✅ sf OK\n")
  options(sf_max_print = 20)
}, error=function(e) {
  cat("❌ Erreur chargement sf :", e$message, "\n")
  stop("Impossible de charger sf")
})

# Chargement des autres packages
for(pkg in pkgs[-1]) safe_library(pkg)

## 1.  Configuration ------------------------------------------------------------
# Récupération de l'ID de tuile depuis les arguments
args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 1) stop("❌ Usage : Rscript step5_tile_worker.R <tile_id>")
TILE_ID <- as.integer(args[1])

# Configuration du buffer
TILE_BUFFER_M <- 2000
BUFFER_IDX <- 1
cat("🌍 [INFO] TILE_BUFFER_M défini à", TILE_BUFFER_M, "m (BUFFER_IDX =", BUFFER_IDX, ")\n")

cat("🔧 Traitement tuile :", TILE_ID, "\n")

## 2.  Chargement des paramètres f_i --------------------------------------------
fi_params_file <- "~/scratch/configuration/fi_parameters.yaml"
if(!file.exists(fi_params_file)) stop("❌ Fichier fi_parameters.yaml introuvable")

fi_params <- read_yaml(fi_params_file)
scenario <- fi_params$scenarios$default

cat("🔧  Paramètres f_i :\n")
cat("   - alpha_dep:", scenario$alpha_dep, "\n")
cat("   - fast_fraction:", scenario$fast_fraction, "\n")
cat("   - slow_k:", scenario$slow_k, "a⁻¹\n")
cat("   - preservation_factor:", scenario$preservation_factor, "\n")

## 3.  Configuration data.table ------------------------------------------------
setDTthreads(1)
cat("✅ data.table threads fixés à 1\n")

## 4.  Chargement de la tuile --------------------------------------------------
cat("📂 Chargement de la tuile...\n")
tiles_file <- "~/scratch/output_V6/tiles_1000km.gpkg"
if(!file.exists(tiles_file)) stop("❌ Fichier tuiles introuvable :", tiles_file)

tiles <- st_read(tiles_file, quiet=TRUE)
if(TILE_ID > nrow(tiles)) stop("❌ Tuile", TILE_ID, "n'existe pas (max:", nrow(tiles), ")")

tile_geom <- tiles[TILE_ID,]
cat("✅ Tuile chargée :", TILE_ID, "\n")

## 5.  Chargement et filtrage des données AIS ----------------------------------
cat("🔍 Pré-filtrage des données AIS...\n")

# Trouver le fichier de données le plus récent
data_files <- list.files("~/scratch/output_V6/", pattern="AIS_with_lithology_clean_.*\\.rds", full.names=TRUE)
if(length(data_files) == 0) stop("❌ Aucun fichier AIS_with_lithology_clean trouvé")

latest_file <- data_files[order(file.info(data_files)$mtime, decreasing=TRUE)[1]]
cat("✅ Fichier avec lithologie lu :", format(file.size(latest_file), big.mark=","), "lignes\n")

# Charger les données
dt <- readRDS(latest_file)
cat("✅ Pings dragage avec coordonnées :", sum(dt$Dragage_flag == 1, na.rm=TRUE), "\n")

# Filtrer les données dans la tuile avec buffer
bbox <- st_bbox(tile_geom)
buffer_bbox <- bbox + c(-TILE_BUFFER_M, -TILE_BUFFER_M, TILE_BUFFER_M, TILE_BUFFER_M)

dredge <- dt[Dragage_flag == 1 & 
             !is.na(Lon) & !is.na(Lat) &
             Lon >= buffer_bbox['xmin'] & Lon <= buffer_bbox['xmax'] &
             Lat >= buffer_bbox['ymin'] & Lat <= buffer_bbox['ymax']]

cat("✅ Pings dragage filtrés :", nrow(dredge), "\n")

## 6.  Chargement des spécifications navires -----------------------------------
cat("🚢 Chargement des specs navires...\n")
ship_specs_file <- "~/scratch/configuration/ship_specs_clean.yaml"
if(!file.exists(ship_specs_file)) stop("❌ Fichier ship_specs_clean.yaml introuvable")

ship_specs_list <- read_yaml(ship_specs_file)$ship_specs
ship_specs <- rbindlist(ship_specs_list, fill=TRUE)
ship_specs[, ssvid := as.character(ssvid)]

cat("🔍 Colonnes dans dredge :", paste(names(dredge), collapse=", "), "\n")

# Merge avec les spécifications
dredge <- merge(dredge, ship_specs[, .(ssvid, name, suction_pipe_diameter_m, dredging_depth_m, dredge_width_m)], 
                by="ssvid", all.x=TRUE, suffixes=c("", ".spec"))

cat("✅ Merge specs réalisé\n")
cat("   - Pings avec specs :", sum(!is.na(dredge$name)), "\n")
cat("   - Pings sans specs :", sum(is.na(dredge$name)), "\n")
cat("🔍 Colonnes après merge :", paste(names(dredge), collapse=", "), "\n")

## 7.  Traitement de la lithologie ---------------------------------------------
cat("🗿 Utilisation des données de lithologie...\n")
dredge_with_lith <- dredge[!is.na(lithologie)]
cat("✅ Lithologie disponible :", nrow(dredge_with_lith), "pings avec lithologie\n")

## 8.  Calcul des f_i ----------------------------------------------------------
cat("🔄 Conversion en lignes...\n")

# Créer un data.frame vide par défaut
result_df <- data.frame(
  grid_id = integer(),
  sum_dw = numeric(),
  sum_dw_pd = numeric(),
  sum_d = numeric()
)

# Si on a des données valides, les traiter
if(nrow(dredge_with_lith) > 0) {
  # Calcul des f_i (simplifié pour l'exemple)
  result_df <- dredge_with_lith %>%
    group_by(grid_id = 1) %>%
    summarise(
      sum_dw = sum(dredge_width_m, na.rm=TRUE),
      sum_dw_pd = sum(dredge_width_m * suction_pipe_diameter_m, na.rm=TRUE),
      sum_d = sum(dredging_depth_m, na.rm=TRUE)
    ) %>%
    ungroup()
}

## 9.  Sauvegarde --------------------------------------------------------------
output_file <- sprintf("~/scratch/output_V6/sar_%03d.parquet", TILE_ID)

if(nrow(result_df) > 0) {
  cat("✅ Données valides trouvées - sauvegarde...\n")
  write_parquet(result_df, output_file)
  cat("✅ Fichier de sortie écrit :", output_file, "\n")
} else {
  cat("⚠️  Aucune donnée valide - création d'un fichier vide\n")
  # Créer un fichier vide avec la structure attendue
  empty_df <- data.frame(
    grid_id = integer(),
    sum_dw = numeric(),
    sum_dw_pd = numeric(),
    sum_d = numeric()
  )
  write_parquet(empty_df, output_file)
  cat("✅ Fichier vide créé :", output_file, "\n")
}

cat("✅ Traitement tuile", TILE_ID, "terminé\n") 