#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-5  ─  CALCUL f_i GLOBAL  (pipeline V6, cluster Béluga)
# Calcule l’indice de perturbation f_i sur grille mondiale 1 km²  (EPSG 6933)
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Bibliothèques ------------------------------------------------------------
pkgs <- c("sf","dplyr","data.table","geosphere","tidyr",
          "rlang","tidyselect","lubridate","arrow","purrr")

safe_library <- function(pkg){
  tryCatch({ library(pkg, character.only = TRUE)
             cat("✅", pkg, "OK\n")},
           error=function(e) stop("❌ Package manquant ou non fonctionnel : ", pkg, "\nMessage : ", e$message))
}

# Chargement robuste de sf
tryCatch({
  library(sf)
  cat("✅ sf OK\n")
}, error=function(e) {
  stop("❌ Le package 'sf' ne peut pas être chargé. Vérifiez la présence des dépendances système (libgdal, libgeos, etc.) dans le conteneur.\nMessage : ", e$message)
})

# Chargement des autres packages
invisible(lapply(pkgs[pkgs != "sf"], safe_library)); cat("\n")

## 1.  Lecture et fusion des fichiers d'entrée --------------------------------------------------------------
# Cherche le fichier flagOK (étape 3)
flagok_files <- list.files("~/scratch/output_V6/", pattern="AIS_data_core_preprocessed_V6_.*flagOK\\.rds$", full.names=TRUE)
# Cherche le fichier de lithologie (étape 4)
litho_files  <- list.files("~/scratch/output_V6/", pattern="AIS_with_lithology_clean_.*\\.rds$", full.names=TRUE)

if(!length(flagok_files)) stop("❌ Fichier flagOK (étape 3) non trouvé")
if(!length(litho_files)) stop("❌ Fichier lithologie (étape 4) non trouvé")

dt_flagOK <- readRDS(max(flagok_files))
dt_litho  <- readRDS(max(litho_files))

# Fusionner, en gardant toutes les lignes de flagOK et ajoutant lithologie si dispo
merge_cols <- intersect(c("Navire", "Timestamp", "Lon", "Lat"), names(dt_litho))
dt_merge <- merge(
  dt_flagOK,
  dt_litho[, c(merge_cols, "lithologie", "pl_base", "dist_km"), with=FALSE],
  by = merge_cols,
  all.x = TRUE
)
dt_merge[, has_lithology := !is.na(pl_base)]

cat("✅ Fusion réalisée : ", nrow(dt_merge), " pings, dont ", sum(dt_merge$has_lithology), " avec lithologie\n")

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
dredge_dt <- dt_merge[Dragage_flag == 1 &
                      !is.na(Lon) & !is.na(Lat)]
if(!nrow(dredge_dt)) stop("❌ Aucun ping de dragage")

# Vérification que dredging_depth_m est défini pour tous les points de dragage
if(any(is.na(dredge_dt$dredging_depth_m))){
  na_count <- sum(is.na(dredge_dt$dredging_depth_m))
  dredge_dt[is.na(dredging_depth_m), dredging_depth_m := 1.0]
  cat("⚠️  ", na_count, " points de dragage avec dredging_depth_m NA - valeur par défaut: 1.0 m\n")
}

if(!"suction_pipe_diameter_m" %in% names(dredge_dt)){
  dredge_dt[, suction_pipe_diameter_m := 0.5]     # défaut 50 cm
}
setkey(dredge_dt, Navire, Timestamp)
cat("✅ Pings dragage :", nrow(dredge_dt), "\n")
cat("📊 Profondeur de dragage - Min:", min(dredge_dt$dredging_depth_m), 
    "Max:", max(dredge_dt$dredging_depth_m), "Moyenne:", round(mean(dredge_dt$dredging_depth_m), 2), "m\n\n")

## 4.  Conversion sf & grille 1 km ---------------------------------------------
cell_m <- 1000L

dredge_sf <- st_as_sf(dredge_dt, coords=c("Lon","Lat"), crs=4326,
                      remove=FALSE) |>
  st_transform(6933) |>
  mutate(W_v  = suction_pipe_diameter_m,
         p_d_i = dredging_depth_m)                   # profondeur en m
st_agr(dredge_sf) <- "constant"

bbox_union <- st_bbox(dredge_sf) + c(-2000,-2000,2000,2000)
xmin<-bbox_union[["xmin"]]; ymin<-bbox_union[["ymin"]]
xmax<-bbox_union[["xmax"]]; ymax<-bbox_union[["ymax"]]

ncol <- as.integer(floor((xmax-xmin)/cell_m))+1L
nrow <- as.integer(floor((ymax-ymin)/cell_m))+1L

grid_sf <- st_make_grid(st_as_sfc(bbox_union), cellsize=cell_m) |>
  st_sf(grid_id = seq_along(.), geometry = _) |>
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
dredge_sf$sub_seg_id <- paste0(dredge_sf$Navire,"_",format(dredge_sf$Timestamp,"%Y%m%d"))

lines_sf <- dredge_sf |>
  group_by(sub_seg_id) |>
  filter(n()>1) |>
  summarise(Navire = first(Navire),
            W_v    = first(W_v),
            p_d_i  = first(p_d_i),
            geometry = st_cast(st_combine(geometry),"MULTILINESTRING"),
            .groups="drop")

start <- Sys.time()
candidates <- st_intersects(lines_sf, grid_sf, sparse=TRUE)

intersections <- purrr::map2_dfr(
  seq_along(candidates), candidates,
  function(i, idx){
    if(!length(idx)) return(NULL)
    inter <- st_intersection(lines_sf[i,], grid_sf[idx,])
    if(!nrow(inter)) return(NULL)
    inter$trawled_distance <- as.numeric(st_length(inter$geometry))
    inter <- inter[inter$trawled_distance>0,]
    inter
  }
)

if(!nrow(intersections)) stop("❌ Aucune intersection trouvée")

# Ajout pl_base par lookup (beaucoup plus rapide que sapply)
pl_lookup <- dredge_dt[, .(pl_base = first(pl_base)), by=sub_seg_id]
intersections <- merge(intersections, pl_lookup, by="sub_seg_id")

cat("✅ Intersections :", nrow(intersections), "segments  (",
    round(difftime(Sys.time(),start,units="mins"),2)," min)\n\n")

## 6.  SAR & SVR ----------------------------------------------------------------
intersections$cell_area <- grid_dt[intersections$grid_id, cell_area]

sar_grid <- intersections |>
  st_drop_geometry() |>
  group_by(grid_id) |>
  summarise(
    SAR = sum(trawled_distance * W_v) / first(cell_area),
    p_d = sum(trawled_distance * W_v * p_d_i) /
          sum(trawled_distance * W_v),
    .groups="drop")

svr_grid <- sar_grid |>
  mutate(SVR = SAR * p_d / 1) |>      # profondeur normalisée 1 m
  select(grid_id, SVR)

## 7.  p_l pondéré --------------------------------------------------------------
setDT(intersections)
pl_grid <- intersections[, .(
  p_l = sum(pl_base * trawled_distance) /
        sum(trawled_distance)
), by = grid_id]

pd_i <- 1        # m
alpha_dep <- 0.25
pl_grid[, `:=`(
  w1 = pmin(0.05, pd_i)/pd_i,
  w2 = 1 - pmin(0.05, pd_i)/pd_i,
  p_l_eff = (pmin(0.05, pd_i)/pd_i)*p_l + (1 - pmin(0.05, pd_i)/pd_i)*p_l*alpha_dep
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

## 9.  Calcul f_i --------------------------------------------------------------
cat("🧮 Calcul f_i\n")
grid_calc <- grid_sf |>
  st_join(longhurst["longhurst_pr"], left=TRUE) |>
  left_join(svr_grid, by="grid_id")  |>
  left_join(pl_grid, by="grid_id")   |>
  mutate(
    SVR   = coalesce(SVR,0),
    p_l   = coalesce(p_l_eff,0),
    fresh_fact = case_when(
      longhurst_pr %in% c("Arabian Sea","Eastern Arabian Sea","Peru-Chile Current") ~ 1.5,
      longhurst_pr %in% c("North Atlantic Subarctic Gyre","North Pacific Subarctic Gyre","Black Sea") ~ 0.5,
      TRUE ~ 1),
    p_l_corr   = p_l * fresh_fact,
    f_i_full   = SVR * p_l_corr * 0.87 *
                 (0.3*(1-exp(-4.76)) + 0.7*(1-exp(-0.05))),
    f_i_reduced= SVR * p_l_corr * 0.87 *
                 (0.3*(1-exp(-4.76/5)) + 0.7*(1-exp(-0.05)))
  )

## 10. Durée de dragage ---------------------------------------------------------
dredge_years <- dredge_sf |>
  st_join(grid_sf["grid_id"], left=FALSE) |>
  mutate(Year = year(Timestamp)) |>
  st_drop_geometry() |>
  distinct(grid_id, Year) |>
  count(grid_id, name="duration_years")

grid_calc <- grid_calc |>
  left_join(dredge_years, by="grid_id") |>
  mutate(duration_years = coalesce(duration_years,0L))

## 11.  Sauvegarde --------------------------------------------------------------
saveRDS(grid_calc, out_rds)
st_write(grid_calc, out_gpkg, layer="grid_calc_full",
         delete_layer=TRUE, quiet=TRUE)
if (requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_feather(st_drop_geometry(grid_calc), out_feather)
  cat("✅ Fichier feather écrit avec arrow\n")
} else {
  alt_feather <- sub("\\.feather$", ".rds", out_feather)
  saveRDS(st_drop_geometry(grid_calc), alt_feather)
  cat("⚠️  Package 'arrow' non disponible : sauvegarde RDS à la place (", alt_feather, ")\n")
}

cat("\n📊 STAT FINALES\n",
    "Cellules dragage :", sum(grid_calc$SVR>0), "\n",
    "Cellules f_i >0  :", sum(grid_calc$f_i_full>0), "\n",
    "f_i moyen        :", round(mean(grid_calc$f_i_full[grid_calc$f_i_full>0]),4), "\n",
    "f_i max          :", round(max(grid_calc$f_i_full),4), "\n")

message("✅ Step-5 terminé – fichiers : ",
        basename(out_rds),", ",basename(out_gpkg),", ",basename(out_feather))
