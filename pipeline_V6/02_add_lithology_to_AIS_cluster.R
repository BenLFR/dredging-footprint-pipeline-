# ────────────────────────────────────────────────────────────────────────────────
# 02_add_lithology_to_AIS_cluster.R   –  version V6 pour Béluga
# Associe à chaque ping AIS la lithologie & pl_base du point sédimentaire le plus
# proche (< 10 km).  Le filtre BBOX reste présent : il ne garde que les sédiments
# situés dans l'enveloppe convexe (+5 km) du nuage AIS, quel que soit son étendue.
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Packages -----------------------------------------------------------------
pkgs <- c("data.table", "FNN", "geosphere")
lapply(pkgs[!pkgs %in% installed.packages()[,1]], install.packages)
invisible(lapply(pkgs, library, character.only = TRUE))

## 1.  Chemins I/O --------------------------------------------------------------
# Récupération du timestamp du dernier fichier AIS flagOK
ais_files <- list.files("~/scratch/output_V6/", 
                       pattern = "AIS_data_core_preprocessed_V6_.*_flagOK\\.rds$",
                       full.names = TRUE)
if (length(ais_files) == 0) {
  stop("❌ Aucun fichier AIS flagOK trouvé dans output_V6/")
}

# Prendre le fichier flagOK le plus récent par date de modification
file_info <- file.info(ais_files)
latest_ais <- rownames(file_info)[which.max(file_info$mtime)]
cat("📥 Utilisation du fichier :", basename(latest_ais), "\n")
cat("📅 Date de modification :", format(file_info$mtime[which.max(file_info$mtime)], "%Y-%m-%d %H:%M:%S"), "\n")

ais_path    <- latest_ais                                    # pings AIS V6 avec flags corrects
seabed_path <- "~/scratch/seabed_lithology_with_pl.csv"      # carte sédiments

# Création des noms de fichiers de sortie avec timestamp
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_clean   <- sprintf("~/scratch/output_V6/AIS_with_lithology_clean_%s.rds", timestamp)
out_rejects <- sprintf("~/scratch/output_V6/AIS_without_lithology_rejects_%s.rds", timestamp)

dist_max_km <- 10          # rayon géodésique d'appariement

## 2.  Lecture des jeux de données ---------------------------------------------
cat("📖 Lecture des données...\n")
ais_dt    <- readRDS(ais_path)       # Lecture RDS V6
seabed_dt <- fread(seabed_path)      # Carte sédiments
setnames(seabed_dt,
         c("longitude","latitude"), c("lon","lat"),
         skip_absent = TRUE)

# Vérification des colonnes requises
required_ais <- c("Lon","Lat")
required_seabed <- c("lon","lat","lithologie","pl_base")

missing_ais <- setdiff(required_ais, names(ais_dt))
missing_seabed <- setdiff(required_seabed, names(seabed_dt))

if (length(missing_ais) > 0)
  stop("❌ Colonnes manquantes dans AIS : ", paste(missing_ais, collapse=", "))
if (length(missing_seabed) > 0)
  stop("❌ Colonnes manquantes dans seabed : ", paste(missing_seabed, collapse=", "))

# Vérification des colonnes de dragage
if("Dragage_flag" %in% names(ais_dt)) {
  cat("🎯 Vérification des flags de dragage :\n")
  dragage_stats <- table(ais_dt$Dragage_flag, useNA = "always")
  cat("   - Points de dragage (flag=1) :", dragage_stats["1"], "\n")
  cat("   - Points non-dragage (flag=0) :", dragage_stats["0"], "\n")
  cat("   - Pourcentage de dragage :", round(dragage_stats["1"] / nrow(ais_dt) * 100, 2), "%\n")
} else {
  warning("⚠️  Colonne Dragage_flag manquante - vérifiez que vous utilisez le bon fichier")
}

## 3.  Filtre BBOX (accélère la recherche, reste valide monde) ------------------
cat("🔍 Application du filtre BBOX...\n")
margin <- 0.05                      # ≈ 5 km de marge partout
bb <- ais_dt[, .(xmin = min(Lon) - margin,
                 xmax = max(Lon) + margin,
                 ymin = min(Lat) - margin,
                 ymax = max(Lat) + margin)]
seabed_dt <- seabed_dt[lon >= bb$xmin & lon <= bb$xmax &
                         lat >= bb$ymin & lat <= bb$ymax]

## 4.  KD-Tree + plus proche voisin --------------------------------------------
cat("🌳 Construction KD-Tree et recherche des plus proches voisins...\n")
coords_seabed <- as.matrix(seabed_dt[, .(lon, lat)])
coords_ais    <- as.matrix(ais_dt[,  .(Lon, Lat)])
nn  <- get.knnx(coords_seabed, coords_ais, k = 1)

idx      <- nn$nn.index[,1]
dist_km  <- distHaversine(coords_ais,
                          cbind(seabed_dt$lon[idx], seabed_dt$lat[idx])) / 1000

## 5.  Affectation + filtre 10 km ----------------------------------------------
cat("📊 Affectation des lithologies et filtrage...\n")
ais_dt[, `:=`(lithologie = seabed_dt$lithologie[idx],
              pl_base    = seabed_dt$pl_base[idx],
              dist_km    = dist_km)]
keep <- ais_dt$dist_km <= dist_max_km & !is.na(ais_dt$lithologie)

## 6.  Exports ------------------------------------------------------------------
cat("💾 Sauvegarde des résultats...\n")
saveRDS(ais_dt[ keep ],  out_clean)
saveRDS(ais_dt[!keep ],  out_rejects)

message("✅  ", sum(keep)," pings gardés (",
        round(100*mean(keep),1)," %)  /  ",
        sum(!keep)," rejetés")

## 7.  Diagnostic rapide --------------------------------------------------------
cat("\n— Distribution des lithologies (pings retenus) —\n")
print(ais_dt[ keep , .N, by = lithologie ][order(-N)])

cat("\n🏁 Étape 4 terminée avec succès :", format(Sys.time()), "\n")
