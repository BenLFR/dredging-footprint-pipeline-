#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  CALCUL f_i GLOBAL  (pipeline V6, cluster Béluga)
# Calcule l’indice de perturbation f_i sur grille mondiale 1 km²  (EPSG 6933)
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques ------------------------------------------------------------
pkgs <- c("sf","dplyr","data.table","geosphere","tidyr",
          "rlang","tidyselect","lubridate","purrr","yaml","progressr")


safe_library <- function(pkg){
  tryCatch({ library(pkg, character.only = TRUE)
             cat("✅", pkg, "OK\n")},
           error=function(e) stop("❌ Package manquant ou non fonctionnel : ", pkg, "\nMessage : ", e$message))
}

# Chargement robuste de sf
tryCatch({
  library(sf)
  cat("✅ sf OK\n")
  options(sf_max_print = 20)
  sf::sf_use_s2(FALSE)
}, error=function(e) {
  stop("❌ Le package 'sf' ne peut pas être chargé. Vérifiez la présence des dépendances système (libgdal, libgeos, etc.) dans le conteneur.\nMessage : ", e$message)
})

# Chargement des autres packages
invisible(lapply(pkgs[pkgs != "sf"], safe_library)); cat("\n")

# ── Runtime limitation warnings ───────────────────────────────────────────────
# Loads check_ais_coverage_region(), check_vessel_size(), check_ocim_scope(),
# etc. Emits warning() (not stop()) — pipeline continues; warnings appear in
# the SLURM .out file and CI artifact.
# See documentation/LIMITATIONS.md for the full list of known failure modes.
local({
  candidates <- c(
    "scripts_principaux/pipeline_warnings.R",    # project root (local dev)
    "../scripts_principaux/pipeline_warnings.R"  # pipeline_V6/ dir (cluster)
  )
  found <- Filter(file.exists, candidates)
  if (length(found) > 0L) source(found[1L]) else
    message("[INFO] pipeline_warnings.R not found — limitation checks skipped.")
})

# ─────  PARAMÈTRES f_i  (k, alpha_dep, etc.)  ────────────────────────────────
args     <- commandArgs(trailingOnly = TRUE)
scenario <- if (length(args)) args[1] else Sys.getenv("FI_SCENARIO", "default")

param_yaml <- "~/scratch/configuration/fi_parameters.yaml"
params_raw <- yaml::read_yaml(param_yaml)

# — inheritance helper ---------------------------------------------------------
get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) {
    parent <- get_scenario(s$inherit)
    s$inherit <- NULL
    modifyList(parent, s)
  } else s
}
par <- get_scenario(scenario)

# — table des k régionaux ------------------------------------------------------
k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast       = unlist(par$k_fast) *
                 ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k     # a⁻¹
preserv_fact  <- par$preservation_factor  # p_r factor

cat("🔧  Scenario f_i :", scenario, "\n")
cat("   - alpha_dep:", alpha_dep, "\n")
cat("   - fast_fraction:", fast_frac, "\n")
cat("   - slow_k:", slow_k, "a⁻¹\n")
cat("   - preservation_factor:", preserv_fact, "\n")

# Limitation des threads BLAS/OMP pour éviter la surconsommation mémoire
Sys.setenv(OMP_NUM_THREADS = 1,
           MKL_NUM_THREADS = 1,
           OPENBLAS_NUM_THREADS = 1)

workers <- 2  # Limite la duplication mémoire (OOM)

# Parallélisation data.table et furrr
library(furrr)
data.table::setDTthreads(2)
cat("✅ data.table threads fixés à 2\n")
plan(multisession, workers = workers)
cat("✅ furrr prêt avec", workers, "workers\n")

## 1.  Lecture et fusion des fichiers d'entrée --------------------------------------------------------------
# Redéfinition des sorties

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_rds     <- sprintf("~/scratch/output_V6/global_grid_calc_%s.rds",   timestamp)
out_gpkg    <- sprintf("~/scratch/output_V6/global_fi_%s.gpkg",         timestamp)

# Cherche le fichier flagOK (étape 3)
cat("🔍 Recherche du fichier flagOK...\n")
cat("   Répertoire de recherche : ~/scratch/output_V6/\n")

flagok_files <- list.files("~/scratch/output_V6/", pattern="AIS_data_core_preprocessed_V6_.*flagOK\\.rds$", full.names=TRUE)
cat("   Fichiers trouvés :", length(flagok_files), "\n")
if(length(flagok_files) > 0) {
  cat("   Fichiers :", paste(basename(flagok_files), collapse=", "), "\n")
}

if(!length(flagok_files)) {
  cat("❌ Aucun fichier flagOK trouvé. Liste de tous les fichiers dans le répertoire :\n")
  all_files <- list.files("~/scratch/output_V6/", full.names=TRUE)
  cat("   ", paste(basename(all_files), collapse="\n    "), "\n")
  stop("❌ Fichier flagOK (étape 3) non trouvé")
}

cat("✅ Fichier flagOK sélectionné :", basename(max(flagok_files)), "\n")
dt_flagOK <- readRDS(max(flagok_files))
cat("✅ Fichier flagOK lu avec succès :", nrow(dt_flagOK), "lignes\n")

# Charger les specs navires depuis le YAML
specs_list <- yaml::read_yaml("~/scratch/configuration/ship_specs.yaml")$ship_specs
specs_dt <- rbindlist(lapply(specs_list, as.data.table), fill=TRUE)
specs_dt[, suction_pipe_diameter_m := (suction_pipe_diameter_mm/1000) * ifelse(is.na(twin_pipes), 1, twin_pipes)]
specs_dt <- specs_dt[, .(ssvid, name, suction_pipe_diameter_m, dredging_depth_m, dredge_width_m)]

# Harmoniser le nom de la colonne d'identifiant si besoin
if("mmsi" %in% names(dt_flagOK) && !"ssvid" %in% names(dt_flagOK)) setnames(dt_flagOK, "mmsi", "ssvid")

# Merge specs sur dt_flagOK
if("ssvid" %in% names(dt_flagOK)) {
  dt_flagOK <- merge(dt_flagOK, specs_dt, by = "ssvid", all.x = TRUE)
} else {
  warning("Aucune colonne ssvid ou mmsi trouvée pour joindre les specs YAML.")
}

# Vérifier la présence des specs
if(any(is.na(dt_flagOK$suction_pipe_diameter_m)))
  warning("🔶 Certains navires n'ont pas de specs YAML (ssvid manquant).")
if(any(is.na(dt_flagOK$dredging_depth_m)))
  warning("🔶 Certains navires n'ont pas de profondeur de dragage dans le YAML.")

# Fallback CSV lithologie : chemin explicite
litho_csv_path <- "~/scratch/output/AIS_with_lithology_clean.csv"

# Cherche le fichier de lithologie (étape 4)
litho_files  <- list.files("~/scratch/output_V6/", pattern="AIS_with_lithology_clean_.*\\.rds$", full.names=TRUE)
dt_litho <- NULL
if(length(litho_files)) {
  dt_litho <- readRDS(max(litho_files))
} else {
  if(file.exists(litho_csv_path)) {
    dt_litho <- fread(litho_csv_path)
    cat("⚠️  Fichier .rds de lithologie non trouvé, CSV utilisé\n")
  } else stop("❌ Ni .rds ni .csv de lithologie trouvé")
}

# Fusion uniquement sur Navire + Timestamp
cols_litho <- intersect(c("Navire","Timestamp","lithologie","pl_base","dist_km"), names(dt_litho))
dt_merge <- merge(
  dt_flagOK,
  dt_litho[, ..cols_litho],
  by = c("Navire","Timestamp"),
  all.x = TRUE
)
dt_merge[, `:=`(
  has_lithology = !is.na(pl_base),
  pl_base = fifelse(is.na(pl_base), 0, pl_base)
)]

cat("✅ Fusion réalisée : ", nrow(dt_merge), " pings, dont ", sum(dt_merge$has_lithology), " avec lithologie\n")
cat("   - Pings sans lithologie : ", sum(!dt_merge$has_lithology), "\n")

## 2.  Lecture & vérifications --------------------------------------------------
# Colonnes requises de base
req_base <- c("Navire","Timestamp","Lon","Lat",
              "Dragage_flag","pl_base")

# Vérification des colonnes de base
if(any(miss <- !req_base %in% names(dt_merge)))
  stop("❌ Colonnes manquantes : ", paste(req_base[miss], collapse=", "))

# Gestion de dredging_depth_m - valeur par défaut 1m si manquante
if(!"dredging_depth_m" %in% names(dt_merge)){
  dt_merge[, dredging_depth_m := 1.0]  # défaut 1 mètre
  cat("⚠️  Colonne dredging_depth_m manquante - valeur par défaut: 1.0 m\n")
} else {
  # Remplacer les NA par la valeur par défaut
  na_count <- sum(is.na(dt_merge$dredging_depth_m))
  if(na_count > 0){
    dt_merge[is.na(dredging_depth_m), dredging_depth_m := 1.0]
    cat("⚠️  ", na_count, " valeurs NA dans dredging_depth_m remplacées par 1.0 m\n")
  }
}

cat("✅ Pings totaux :", nrow(dt_merge), "\n")

## 3.  Sous-ensemble dragage ----------------------------------------------------
dredge_dt <- dt_merge[Dragage_flag == 1 & !is.na(Lon) & !is.na(Lat)]
if(!nrow(dredge_dt)) stop("❌ Aucun ping de dragage")

dredge_dt[, sub_seg_id := paste0(Navire, "_", format(Timestamp, "%Y%m%d"))]

# Plus besoin de valeurs par défaut pour suction_pipe_diameter_m et dredging_depth_m sauf si NA
if(any(is.na(dredge_dt$suction_pipe_diameter_m))) {
  dredge_dt[is.na(suction_pipe_diameter_m), suction_pipe_diameter_m := 0.5]
  cat("⚠️  Diamètre de pipe manquant pour certains pings - valeur par défaut: 0.5 m\n")
}
if(any(is.na(dredge_dt$dredging_depth_m))) {
  dredge_dt[is.na(dredging_depth_m), dredging_depth_m := 1.0]
  cat("⚠️  Profondeur de dragage manquante pour certains pings - valeur par défaut: 1.0 m\n")
}

# Logs de contrôle
cat("Distribution des diamètres de pipe (m):\n")
print(table(dredge_dt$suction_pipe_diameter_m))
cat("Résumé des profondeurs de dragage:\n")
print(summary(dredge_dt$dredging_depth_m))

dredge_sf <- st_as_sf(dredge_dt, coords=c("Lon","Lat"), crs=4326, remove=FALSE) %>%
  st_transform(6933) %>%
  mutate(W_v  = suction_pipe_diameter_m,
         p_d_i = dredging_depth_m)
st_agr(dredge_sf) <- "constant"
# dredge_sf$sub_seg_id <- dredge_dt$sub_seg_id   # (inutile, déjà dans dredge_dt)

cat("✅ Pings dragage :", nrow(dredge_dt), "\n")
cat("📊 Profondeur de dragage - Min:", min(dredge_dt$dredging_depth_m), 
    "Max:", max(dredge_dt$dredging_depth_m), "Moyenne:", round(mean(dredge_dt$dredging_depth_m), 2), "m\n\n")

## 4.  Conversion sf & grille 1 km ---------------------------------------------
cell_m <- 1000L

bbox_union <- st_bbox(dredge_sf) + c(-2000,-2000,2000,2000)
xmin<-bbox_union[["xmin"]]; ymin<-bbox_union[["ymin"]]
xmax<-bbox_union[["xmax"]]; ymax<-bbox_union[["ymax"]]

ncol <- as.integer(floor((xmax-xmin)/cell_m))+1L
nrow <- as.integer(floor((ymax-ymin)/cell_m))+1L

grid_sf <- st_make_grid(st_as_sfc(bbox_union), cellsize=cell_m) %>%
  st_sf(grid_id = seq_along(.), geometry = .) %>%
  mutate(cell_area = cell_m^2)
grid_coords <- st_coordinates(st_centroid(grid_sf))
grid_sf$col <- as.integer(floor((grid_coords[,1]-xmin)/cell_m))
grid_sf$row <- as.integer(floor((grid_coords[,2]-ymin)/cell_m))
grid_sf$grid_id_int <- grid_sf$col + grid_sf$row*ncol + 1L
st_agr(grid_sf) <- "constant"

# data.table helper sans géométrie
grid_dt <- as.data.table(grid_sf)[,.(grid_id,cell_area)]
setkey(grid_dt, grid_id)

cat("✅ Grille :", nrow(grid_sf), "cellules\n\n")

## 5.  Intersections optimisées -------------------------------------------------
cat("🔄 Intersections ligne/grille…\n")
cat("Début intersections :", Sys.time(), "\n")
dredge_sf$sub_seg_id <- paste0(dredge_sf$Navire,"_",format(dredge_sf$Timestamp,"%Y%m%d"))

lines_sf <- dredge_sf %>%
  group_by(sub_seg_id) %>%
  filter(n()>1) %>%
  summarise(Navire = first(Navire),
            W_v    = first(W_v),
            p_d_i  = first(p_d_i),
            geometry = st_cast(st_combine(geometry),"MULTILINESTRING"),
            .groups="drop")

start <- Sys.time()
candidates <- st_intersects(lines_sf, grid_sf, sparse=TRUE)

library(progressr)
handlers(global = TRUE)
handlers("txtprogressbar")
options(progressr.enable = TRUE, progressr.show_after = 0)

with_progress({
  intersections <- future_map2_dfr(
  seq_along(candidates), candidates,
  function(i, idx){
    if(!length(idx)) return(NULL)
    inter <- st_intersection(lines_sf[i,], grid_sf[idx,])
    if(!nrow(inter)) return(NULL)
    inter$trawled_distance <- as.numeric(st_length(inter$geometry))
    inter <- inter[inter$trawled_distance>0,]
    inter
    },
    .progress = TRUE
)
})
rm(lines_sf); invisible(gc())

cat("Fin intersections :", Sys.time(), "\n")
plan(sequential)   # Libère les workers dès que possible
invisible(gc())    # Purge les objets futures de la mémoire

if(!nrow(intersections)) stop("❌ Aucune intersection trouvée")

# Ajout pl_base par lookup (beaucoup plus rapide que sapply)
pl_lookup <- dredge_dt[, .(pl_base = first(pl_base)), by=sub_seg_id]
intersections <- merge(intersections, pl_lookup, by="sub_seg_id")

cat("✅ Intersections :", nrow(intersections), "segments  (",
    round(difftime(Sys.time(),start,units="mins"),2)," min)\n\n")

## 6.  SAR & SVR ----------------------------------------------------------------
intersections$cell_area <- grid_dt[intersections$grid_id, cell_area]

sar_grid <- intersections %>%
  st_drop_geometry() %>%
  group_by(grid_id) %>%
  summarise(
    SAR = sum(trawled_distance * W_v) / first(cell_area),
    p_d = sum(trawled_distance * W_v * p_d_i) /
          sum(trawled_distance * W_v),
    .groups="drop")

svr_grid <- sar_grid %>%
  mutate(SVR = SAR * p_d / 1) %>%      # profondeur normalisée 1 m
  select(grid_id, SVR)

## 7.  p_l pondéré --------------------------------------------------------------
setDT(intersections)
pl_grid <- intersections[, .(
  p_l = sum(pl_base * trawled_distance) /
        sum(trawled_distance)
), by = grid_id]

# Utiliser la profondeur réelle pondérée par distance
pl_grid <- merge(pl_grid,
                 sar_grid[, .(grid_id, p_d)],   # profondeur pondérée
                 by = "grid_id", all.x = TRUE)

pl_grid[, p_d := fifelse(is.na(p_d) | p_d <= 0, 1, p_d)]  # secours 1 m; pd=0 → NaN guard

# Option B depth-weighting: deep horizon capped at the 5-10 cm layer only.
# Sediment below 10 cm treated as kinetically inert on a 1-year timescale
# (beyond Holocene bioturbated layer; k < 1e-4 a-1, negligible in 365 days).
pl_grid[, `:=`(
  w1 = pmin(0.05, p_d) / p_d,
  w2 = pmin(0.05, pmax(p_d - 0.05, 0)) / p_d,  # Option B: capped at 5 cm thick
  p_l_eff = w1 * p_l + w2 * p_l * alpha_dep   # ← utilise le paramètre YAML
)]
pl_grid <- pl_grid[,.(grid_id,p_l_eff)]

pl_grid <- merge(pl_grid,
                 data.table(grid_id = grid_sf$grid_id,
                            dummy = 0), all.y=TRUE)[,dummy:=NULL]
pl_grid[is.na(p_l_eff), p_l_eff := 0]

## 8.  Provinces Longhurst ------------------------------------------------------
cat("🌊 Provinces Longhurst\n")
get_longhurst <- function(){
    wfs <- paste0("https://geo.vliz.be/geoserver/MarineRegions/wfs?",
                  "service=WFS&version=2.0.0&request=GetFeature&",
                  "typeName=MarineRegions:longhurst&outputFormat=application/json")
    suppressWarnings(st_read(wfs, quiet=TRUE))
}
longhurst <- try(get_longhurst(), silent=TRUE)
if(inherits(longhurst,"try-error") || !nrow(longhurst)){
  tmp<-tempfile(fileext=".zip")
  download.file("https://www.marineregions.org/downloads.php?data=longhurst&format=shp",
                tmp, mode="wb", quiet=TRUE)
  unzip(tmp, exdir=d<-dirname(tmp))
  longhurst <- st_read(list.files(d,"\\.shp$",full.names=TRUE)[1], quiet=TRUE)
}
longhurst <- st_transform(longhurst,6933)
desc <- grep("(descr|name|prov)", names(longhurst), value=TRUE, ignore.case=TRUE)[1]
longhurst <- rename(longhurst, longhurst_pr = !!sym(desc))

# joindre k_fast par province
longhurst <- left_join(longhurst, k_table, by = "longhurst_pr")

## 9.  Calcul f_i --------------------------------------------------------------
cat("🧮 Calcul f_i\n")
grid_calc <- grid_sf %>%
  st_join(longhurst["longhurst_pr"], left=TRUE) %>%
  left_join(svr_grid, by="grid_id")  %>%
  left_join(pl_grid, by="grid_id")   %>%
  mutate(
    SVR = coalesce(SVR, 0),
    p_l = coalesce(p_l_eff, 0),

    # "freshness" provincial factor (inchangé)
    fresh_fact = case_when(
      longhurst_pr %in% c("Arabian Sea","Eastern Arabian Sea",
                          "Peru-Chile Current") ~ 1.5,
      longhurst_pr %in% c("North Atlantic Subarctic Gyre",
                          "North Pacific Subarctic Gyre",
                          "Black Sea")          ~ 0.5,
      TRUE                                      ~ 1),
    p_l_corr = p_l * fresh_fact,

    # ----  f_i avec double-pool et k paramétrique  -----------------------------
    k_used     = coalesce(k_fast, 1.0),               # secours si province manquante
    f_i_full   = SVR * p_l_corr * preserv_fact *
                 ( fast_frac            * (1 - exp(-k_used       )) +
                   (1 - fast_frac)      * (1 - exp(-slow_k       )) ),

    f_i_reduced = SVR * p_l_corr * preserv_fact *
                 ( fast_frac            * (1 - exp(-k_used / 5   )) +
                   (1 - fast_frac)      * (1 - exp(-slow_k       )) )
  )

## 10. Durée de dragage ---------------------------------------------------------
dredge_years <- dredge_sf %>%
  st_join(grid_sf["grid_id"], left=FALSE) %>%
  mutate(Year = year(Timestamp)) %>%
  st_drop_geometry() %>%
  distinct(grid_id, Year) %>%
  count(grid_id, name="duration_years")

grid_calc <- grid_calc %>%
  left_join(dredge_years, by="grid_id") %>%
  mutate(duration_years = coalesce(duration_years,0L))

## 11.  Sauvegarde --------------------------------------------------------------
saveRDS(grid_calc, out_rds)
st_write(grid_calc, out_gpkg, layer="grid_calc_full",
         delete_layer=TRUE, quiet=TRUE, driver_options = c("SPATIAL_INDEX=NO"))

# Sauvegarde alternative : .rds au lieu de .feather
# alt_feather <- sub("\\.feather$", ".rds", out_feather)
# saveRDS(st_drop_geometry(grid_calc), alt_feather)
# cat("⚠️  Le package 'arrow' n'est plus utilisé : sauvegarde RDS à la place (", alt_feather, ")\n")

cat("\n📊 STAT FINALES\n",
    "Cellules dragage :", sum(grid_calc$SVR>0), "\n",
    "Cellules f_i >0  :", sum(grid_calc$f_i_full>0), "\n",
    "f_i moyen        :", round(mean(grid_calc$f_i_full[grid_calc$f_i_full>0]),4), "\n",
    "f_i max          :", round(max(grid_calc$f_i_full),4), "\n")

message("✅ Step-5 terminé – fichiers : ",
        basename(out_rds),", ",basename(out_gpkg))
