#!/usr/bin/env Rscript
# ==============================================================================
# STEP-0 : Core Period Selection via Coverage Matrix (Eriksen et al., 2018 style)
# ==============================================================================

cat("\n📊  STEP-0  |  Core Period Selection via Coverage Matrix |  début :", format(Sys.time()), "\n\n")

# ---- PACKAGES ET CONFIG ----
.libPaths("~/.local/R/4.2.1/")
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(matrixStats)
  library(digest)
  library(yaml)
})

set.seed(42)

# ---- CHARGEMENT DONNÉES ----
input_pattern <- Sys.getenv("AIS_INPUT_PATTERN", "~/scratch/AIS_data/*.csv")
output_dir   <- Sys.getenv("AIS_OUTPUT_DIR", "~/scratch/output_V6")
cat("📁  INPUT  :", input_pattern, "\n")
cat("📁  OUTPUT :", output_dir, "\n\n")

# Nouvelle logique de détection du fichier d'entrée (CSV **ou** RDS)
input_file <- Sys.getenv("AIS_INPUT_FILE", "")

if (nzchar(input_file) && file.exists(input_file)) {
  cat("🔍  Fichier fourni par AIS_INPUT_FILE :", basename(input_file), "\n\n")

} else {
  csv_files <- Sys.glob(input_pattern)
  rds_pattern <- sub("\\*\\.csv$", "*.rds", input_pattern)
  rds_files <- Sys.glob(rds_pattern)

  if (length(csv_files)) {
    # Priorité au CSV benjamin2 si présent
    pref_csv <- csv_files[grep("benjamin2\\.csv$", csv_files, ignore.case = TRUE)]
    input_file <- if (length(pref_csv)) pref_csv[1] else csv_files[1]
  } else if (length(rds_files)) {
    input_file <- rds_files[1]
  } else {
    stop("❌  Aucun fichier d'entrée trouvé (CSV ou RDS).")
  }
  cat("🔍  Fichier détecté :", basename(input_file), "\n\n")
}

# ---- CHARGEMENT DU FICHIER ---------------------------------------------------
if (grepl("\\.rds$", input_file, ignore.case = TRUE)) {
  ais_dt <- as.data.table(readRDS(input_file))
} else {
  ais_dt <- fread(input_file, showProgress = FALSE)
}

setnames(ais_dt, tolower(names(ais_dt)))
cat("✅", format(nrow(ais_dt), big.mark = " "), "lignes chargées.\n\n")

# ---- TABLE CORRESPONDANCE MMSI → NAVIRE ----
mmsi_map <- data.table(
  ssvid = c(209469000, 210138000, 245508000, 246351000,
            253193000, 253373000, 253403000, 253422000,
            253688000, 312062000, 533180137),
  Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318",
             "Vox Maxima", "Vasco Da Gama", "Cristobal Colon",
             "Leiv Eiriksson", "Charles Darwin", "Congo River",
             "Goryo 6 Ho", "Inai Kenanga")
)
setkey(mmsi_map, ssvid)

if ("ssvid" %in% names(ais_dt)) {
  ais_dt <- merge(ais_dt, mmsi_map, by = "ssvid", all.x = TRUE)
  ais_dt[is.na(Navire), Navire := paste0("unknown_", ssvid)]
} else if ("navire" %in% names(ais_dt)) {
  setnames(ais_dt, "navire", "Navire")
} else {
  ais_dt[, Navire := "benjamin2"]
}

# ---- PREP TEMPS ----
ais_dt[, Timestamp := as.POSIXct(get("timestamp"), tz = "UTC")]
ais_dt[, Date := as.Date(Timestamp)]
ais_dt[, Annee := year(Timestamp)]

# ---- MATRICE COUVERTURE ----
# 1. Couverture journalière pour chaque navire-année
cover_dt <- ais_dt[, .(active_days = uniqueN(Date)), by = .(Navire, Annee)]
cover_dt[, total_days := ifelse(leap_year(Annee), 366, 365)]
cover_dt[, coverage := active_days / total_days]

# 2. Matrice Navire × Année
navires <- sort(unique(cover_dt$Navire))
annees  <- sort(unique(cover_dt$Annee))
cov_mat <- matrix(0, nrow = length(navires), ncol = length(annees),
                  dimnames = list(navires, annees))
for (i in seq_along(navires)) {
  for (j in seq_along(annees)) {
    v <- cover_dt[Navire == navires[i] & Annee == annees[j], coverage]
    if (length(v)) cov_mat[i, j] <- v
  }
}

cat("✅ Matrice couverture :", nrow(cov_mat), "navires ×", ncol(cov_mat), "années\n")

# ---- SELECTION FENÊTRE OPTIMALE ----
min_L <- 5
best <- list(score = -Inf)
years <- as.numeric(colnames(cov_mat))
n <- length(years)

for (i in seq_len(n - min_L + 1)) {
  for (j in seq(i+min_L-1, n)) {   # fenetre [i..j], min 5 ans
    subC <- cov_mat[, i:j, drop=FALSE]
    Cyears <- colMedians(subC, na.rm = TRUE)   # médiane de chaque année
    L   <- j-i+1
    Cbar<- median(Cyears, na.rm=TRUE)
    Cmin<- min(Cyears, na.rm=TRUE)
    CV  <- ifelse(Cbar==0, 1e9, sd(Cyears, na.rm=TRUE)/Cbar)
    S   <- L * Cbar * (Cmin^2) / (1 + CV)
    if (!is.na(S) && S > best$score) {
      best <- list(
        score = S,
        start = years[i],
        end   = years[j],
        length= L,
        Cbar  = Cbar,
        Cmin  = Cmin,
        CV    = CV,
        window_yrs = years[i]:years[j]
      )
    }
  }
}

cat(sprintf("🎯 Fenêtre optimale : %d-%d (%d ans)\n", best$start, best$end, best$length))
cat(sprintf("   • Couverture médiane : %.1f %%\n", 100*best$Cbar))
cat(sprintf("   • Couverture minimale : %.1f %%\n", 100*best$Cmin))
cat(sprintf("   • CV annuel           : %.3f\n", best$CV))
cat(sprintf("   • Score               : %.3f\n", best$score))

# ---- SUPPRESSION DES NAVIRES FANTÔMES  --------------------------------
# Éliminer les navires qui n'ont aucun ping dans la fenêtre optimale
yrs_idx <- which(years %in% best$window_yrs)  # colonnes de la fenêtre
present_n <- rowSums(cov_mat[, yrs_idx, drop = FALSE] > 0)  # nb d'années actives
core_ships <- names(present_n[present_n > 0])  # garde seulement >0

if (length(core_ships) == 0) {
  stop("❌ La fenêtre optimale ne contient finalement aucun navire actif – à vérifier.")
}

cat(sprintf("🔍  Navires actifs dans la fenêtre : %d (sur %d total)\n", 
            length(core_ships), nrow(cov_mat)))

if (length(core_ships) < nrow(cov_mat)) {
  inactive_ships <- setdiff(rownames(cov_mat), core_ships)
  cat("⚠️  Navires inactifs exclus :", paste(inactive_ships, collapse = ", "), "\n")
}

# Conserve seulement les navires actifs pour la suite
cov_mat <- cov_mat[core_ships, , drop = FALSE]
best$ships <- core_ships

# ---- EXPORT ----
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

# 1. CSV avec les métriques de la fenêtre
core_window <- data.table(
  start_year = best$start,
  end_year   = best$end,
  length     = best$length,
  median_coverage = best$Cbar,
  min_coverage = best$Cmin,
  CV_coverage = best$CV,
  score = best$score
)
fwrite(core_window, file.path(output_dir, "best_core_window.csv"))

# 2. YAML complet avec fenêtre ET liste des navires
core_config <- list(
  # Fenêtre temporelle
  start_year = best$start,
  end_year = best$end,
  length_years = best$length,
  
  # Métriques de couverture
  median_coverage = best$Cbar,
  min_coverage = best$Cmin,
  cv_coverage = best$CV,
  score = best$score,
  
  # Liste des navires actifs dans la fenêtre optimale
  core_ships = best$ships,
  
  # Années de la fenêtre
  window_years = best$window_yrs,
  
  # Métadonnées
  execution_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  input_file = basename(input_file),
  total_ships = length(best$ships),
  total_observations = nrow(ais_dt)
)

write_yaml(core_config, file.path(output_dir, "core_window.yaml"))

# 3. CSV avec la liste des navires (pour compatibilité)
ships_dt <- data.table(
  ship_id = seq_along(best$ships),
  ship_name = best$ships
)
fwrite(ships_dt, file.path(output_dir, "core_ships.csv"))

# ---- Markdown Report (rapide) ----
report_md <- sprintf(
  "# Rapport Core Window (Coverage Matrix)\n
- **Fenêtre optimale :** %d–%d (%d ans)\n
- **Couverture médiane :** %.1f %%\n
- **Pire année         :** %.1f %%\n
- **CV inter-années    :** %.3f\n
- **Score             :** %.3f\n
- **Navires actifs     :** %d\n
", best$start, best$end, best$length, 100*best$Cbar, 100*best$Cmin, best$CV, best$score, length(best$ships))
writeLines(report_md, file.path(output_dir, "core_window_report.md"))

cat("📄  Résumé markdown : core_window_report.md\n")
cat("📋  Configuration YAML : core_window.yaml\n")
cat("🚢  Liste navires : core_ships.csv\n")
cat("💾  Fichiers dans", output_dir, "\n")
cat("⏱️  Fin :", format(Sys.time()), "\n")

# Optional: enrichissement des messages AIS avec accélération, changement de cap, heure, mois
# (partie dynamique à ajouter si besoin : cf. Chen et al., 2022)
