# ────────────────────────────────────────────────────────────────────────────────
# join_ais_lithology_clean.R   –  version *monde entier* pour Béluga
# Associe à chaque ping AIS la lithologie & pl_base du point sédimentaire le plus
# proche (< 10 km).  Le filtre BBOX reste présent : il ne garde que les sédiments
# situés dans l’enveloppe convexe (+5 km) du nuage AIS, quel que soit son étendue.
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Packages -----------------------------------------------------------------
pkgs <- c("data.table", "FNN", "geosphere")
lapply(pkgs[!pkgs %in% installed.packages()[,1]], install.packages)
invisible(lapply(pkgs, library, character.only = TRUE))

## 1.  Chemins I/O --------------------------------------------------------------
ais_path    <- "~/scratch/output/AIS_data_core_preprocessed.csv"   # pings AIS monde
seabed_path <- "~/scratch/seabed_lithology_with_pl.csv"            # carte sédiments

out_clean   <- "~/scratch/output/AIS_with_lithology_clean.csv"
out_rejects <- "~/scratch/output/AIS_without_lithology_rejects.csv"

dist_max_km <- 10          # rayon géodésique d’appariement

## 2.  Lecture des jeux de données ---------------------------------------------
ais_dt    <- fread(ais_path)       # attend Lon, Lat (° déc.)
seabed_dt <- fread(seabed_path)    # attend lon, lat, lithologie, pl_base
setnames(seabed_dt,
         c("longitude","latitude"), c("lon","lat"),
         skip_absent = TRUE)

stopifnot(all(c("Lon","Lat")                 %in% names(ais_dt)),
          all(c("lon","lat","lithologie",
                "pl_base")                  %in% names(seabed_dt)))

## 3.  Filtre BBOX (accélère la recherche, reste valide monde) ------------------
margin <- 0.05                      # ≈ 5 km de marge partout
bb <- ais_dt[, .(xmin = min(Lon) - margin,
                 xmax = max(Lon) + margin,
                 ymin = min(Lat) - margin,
                 ymax = max(Lat) + margin)]
seabed_dt <- seabed_dt[lon >= bb$xmin & lon <= bb$xmax &
                         lat >= bb$ymin & lat <= bb$ymax]

## 4.  KD-Tree + plus proche voisin --------------------------------------------
coords_seabed <- as.matrix(seabed_dt[, .(lon, lat)])
coords_ais    <- as.matrix(ais_dt[,  .(Lon, Lat)])
nn  <- get.knnx(coords_seabed, coords_ais, k = 1)

idx      <- nn$nn.index[,1]
dist_km  <- distHaversine(coords_ais,
                          cbind(seabed_dt$lon[idx], seabed_dt$lat[idx])) / 1000

## 5.  Affectation + filtre 10 km ----------------------------------------------
ais_dt[, `:=`(lithologie = seabed_dt$lithologie[idx],
              pl_base    = seabed_dt$pl_base[idx],
              dist_km    = dist_km)]
keep <- ais_dt$dist_km <= dist_max_km & !is.na(ais_dt$lithologie)

## 6.  Exports ------------------------------------------------------------------
fwrite(ais_dt[ keep ],  out_clean)
fwrite(ais_dt[!keep ],  out_rejects)

message("✅  ", sum(keep)," pings gardés (",
        round(100*mean(keep),1)," %)  /  ",
        sum(!keep)," rejetés")

## 7.  Diagnostic rapide --------------------------------------------------------
cat("\n— Distribution des lithologies (pings retenus) —\n")
print(ais_dt[ keep , .N, by = lithologie ][order(-N)])
