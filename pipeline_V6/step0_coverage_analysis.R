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

csv_files <- Sys.glob(input_pattern)
if (length(csv_files) == 0) stop("❌  Aucun CSV trouvé.")
benjamin_file <- csv_files[grep("benjamin2\\.csv$", csv_files, ignore.case = TRUE)]
if (length(benjamin_file) == 0) stop("❌  Fichier benjamin2.csv non trouvé")
cat("🔍  Fichier à traiter :", basename(benjamin_file), "\n\n")

ais_dt <- fread(benjamin_file, showProgress = FALSE)
setnames(ais_dt, tolower(names(ais_dt)))

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

cat("✅ Matrice couverture :", nrow(cov_mat), "navires ×", ncol(cov_mat), "années\n")

# ---- SELECTION FENÊTRE OPTIMALE ----
min_L <- 5
best <- list(score = -Inf)
years <- as.numeric(colnames(cov_mat))
n <- length(years)

for (i in seq_len(n)) {
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

cat(sprintf("🎯 Fenêtre optimale : %d-%d (%d ans)\n", best$start, best$end, best$length))
cat(sprintf("   • Couverture médiane : %.1f %%\n", 100*best$Cbar))
cat(sprintf("   • Couverture minimale : %.1f %%\n", 100*best$Cmin))
cat(sprintf("   • CV annuel           : %.3f\n", best$CV))
cat(sprintf("   • Score               : %.3f\n", best$score))

# ---- EXPORT ----
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

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

# ---- Markdown Report (rapide) ----
report_md <- sprintf(
  "# Rapport Core Window (Coverage Matrix)\n
- **Fenêtre optimale :** %d–%d (%d ans)\n
- **Couverture médiane :** %.1f %%\n
- **Pire année         :** %.1f %%\n
- **CV inter-années    :** %.3f\n
- **Score             :** %.3f\n
", best$start, best$end, best$length, 100*best$Cbar, 100*best$Cmin, best$CV, best$score)
writeLines(report_md, file.path(output_dir, "core_window_report.md"))

cat("📄  Résumé markdown : core_window_report.md\n")
cat("💾  Fichiers dans", output_dir, "\n")
cat("⏱️  Fin :", format(Sys.time()), "\n")

# Optional: enrichissement des messages AIS avec accélération, changement de cap, heure, mois
# (partie dynamique à ajouter si besoin : cf. Chen et al., 2022)
