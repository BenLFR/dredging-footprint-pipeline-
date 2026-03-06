#!/usr/bin/env Rscript
# ==============================================================================
# STEP-0 ENHANCED : Core Period Selection via Coverage Matrix (Eriksen et al., 2018 style)
# Version améliorée avec analyse complète de toutes les fenêtres candidates
# ==============================================================================

cat("\n  STEP-0 ENHANCED  |  Core Period Selection via Coverage Matrix |  start :", format(Sys.time()), "\n\n")

# ---- PACKAGES ET CONFIG ----
.libPaths("~/R/library")
suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(matrixStats)
  library(digest)
  library(yaml)
})

set.seed(42)

# ---- LOAD DATA ----
input_pattern <- Sys.getenv("AIS_INPUT_PATTERN", "~/AIS_data/benjamin3_clean.csv")
output_dir   <- Sys.getenv("AIS_OUTPUT_DIR", "~/scratch/output_V6")
cat("  INPUT  :", input_pattern, "\n")
cat("  OUTPUT :", output_dir, "\n\n")

# Input file detection logic (CSV **or** RDS)
input_file <- Sys.getenv("AIS_INPUT_FILE", "")
if (nzchar(input_file) && file.exists(input_file)) {
  cat("  File provided via AIS_INPUT_FILE :", basename(input_file), "\n\n")
} else {
csv_files <- Sys.glob(input_pattern)
  rds_pattern <- sub("\\*\\.csv$", "*.rds", input_pattern)
  rds_files <- Sys.glob(rds_pattern)
  if (length(csv_files)) {
    pref_csv <- csv_files[grep("benjamin2\\.csv$", csv_files, ignore.case = TRUE)]
    input_file <- if (length(pref_csv)) pref_csv[1] else csv_files[1]
  } else if (length(rds_files)) {
    input_file <- rds_files[1]
  } else {
    stop("No input file found (CSV or RDS).")
  }
  cat("  File detected :", basename(input_file), "\n\n")
}

# ---- LOAD FILE ---------------------------------------------------
if (grepl("\\.rds$", input_file, ignore.case = TRUE)) {
  ais_dt <- as.data.table(readRDS(input_file))
} else {
  ais_dt <- fread(input_file, showProgress = FALSE)
}

setnames(ais_dt, tolower(names(ais_dt)))
cat("", format(nrow(ais_dt), big.mark = " "), "rows loaded.\n\n")

# ---- MMSI → VESSEL NAME LOOKUP TABLE ----
# Note: Vasco Da Gama had two MMSIs: 253193000 (Luxembourg, 2013-2019) and 205744000 (Belgium, 2018-2024)
# Merged to the most recent MMSI: 205744000
# Note: Goryo 6 Ho (312062000) excluded - corrupted data
mmsi_map <- data.table(
  ssvid = c(209469000, 210138000, 245508000, 246351000,
            253193000, 205744000, 253373000, 253403000, 253422000,
            253688000, 533180137),
  Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318",
             "Vox Maxima", "Vasco Da Gama", "Vasco Da Gama", "Cristobal Colon",
             "Leiv Eiriksson", "Charles Darwin", "Congo River",
             "Inai Kenanga"),
  # Reference MMSI (most recent for Vasco Da Gama)
  ssvid_ref = c(209469000, 210138000, 245508000, 246351000,
                205744000, 205744000, 253373000, 253403000, 253422000,
                253688000, 533180137)
)
# Convert ssvid type for compatibility
mmsi_map[, ssvid := as.character(ssvid)]
mmsi_map[, ssvid_ref := as.character(ssvid_ref)]
setkey(mmsi_map, ssvid)

if ("ssvid" %in% names(ais_dt)) {
  # Convert ssvid type for compatibility
  ais_dt[, ssvid := as.character(ssvid)]
  ais_dt <- merge(ais_dt, mmsi_map, by = "ssvid", all.x = TRUE)

  # Merge multiple MMSIs to the reference MMSI (Vasco Da Gama case)
  ais_dt[!is.na(ssvid_ref), ssvid := ssvid_ref]
  ais_dt[, ssvid_ref := NULL]  # clean up temporary column

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

# ---- COVERAGE MATRIX ----
# 1. Daily coverage for each vessel-year
cover_dt <- ais_dt[, .(active_days = uniqueN(Date)), by = .(Navire, Annee)]
cover_dt[, total_days := ifelse(leap_year(Annee), 366, 365)]
cover_dt[, coverage := active_days / total_days]

# 2. Vessel × Year matrix
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

cat("Coverage matrix:", nrow(cov_mat), "vessels x", ncol(cov_mat), "years\n")

# ---- EXPORT VESSEL × YEAR MATRIX ----
# Save the full matrix for visualisation
cov_dt <- as.data.table(cov_mat, keep.rownames = "ship")
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
fwrite(cov_dt, file.path(output_dir, "coverage_matrix.csv"), row.names = FALSE)
cat("Coverage matrix exported: coverage_matrix.csv\n")

# ---- FULL ANALYSIS OF ALL CANDIDATE WINDOWS ----
min_L <- 5
all_windows <- data.table()
years <- as.numeric(colnames(cov_mat))
n <- length(years)

cat("Analysing all candidate windows (min", min_L, "years)...\n")
pb <- txtProgressBar(min = 0, max = (n - min_L + 1) * (n - min_L) / 2, style = 3)
counter <- 0

for (i in seq_len(n - min_L + 1)) {
  for (j in seq(i+min_L-1, n)) {
    subC <- cov_mat[, i:j, drop=FALSE]
    Cyears <- colMedians(subC, na.rm = TRUE)
    L   <- j-i+1
    Cbar<- median(Cyears, na.rm=TRUE)
    Cmin<- min(Cyears, na.rm=TRUE)
    CV  <- ifelse(Cbar==0, 1e9, sd(Cyears, na.rm=TRUE)/Cbar)
    S   <- L * Cbar * (Cmin^2) / (1 + CV)
    
    # Additional calculations for analysis
    navires_actifs <- sum(rowSums(subC > 0) > 0)
    couverture_totale <- mean(subC, na.rm=TRUE)
    
    all_windows <- rbind(all_windows, data.table(
      start_year = years[i],
      end_year = years[j],
      length = L,
      median_coverage = Cbar,
      min_coverage = Cmin,
      CV_coverage = CV,
      score = S,
      active_ships = navires_actifs,
      total_coverage = couverture_totale,
      years_list = list(years[i]:years[j])
    ))
    
    counter <- counter + 1
    setTxtProgressBar(pb, counter)
  }
}
close(pb)

# Sort by descending score
setorder(all_windows, -score)

cat(sprintf("%d candidate windows analysed\n", nrow(all_windows)))

# ---- OPTIMAL WINDOW ----
best <- all_windows[1]
best_window_yrs <- best$years_list[[1]]

cat(sprintf("Optimal window: %d-%d (%d years)\n", best$start_year, best$end_year, best$length))
cat(sprintf("   - Median coverage  : %.1f %%\n", 100*best$median_coverage))
cat(sprintf("   - Minimum coverage : %.1f %%\n", 100*best$min_coverage))
cat(sprintf("   - Annual CV        : %.3f\n", best$CV_coverage))
cat(sprintf("   - Score            : %.3f\n", best$score))
cat(sprintf("   - Active vessels   : %d\n", best$active_ships))

# ---- ALTERNATIVE WINDOW ANALYSIS ----
cat("\nTOP 10 CANDIDATE WINDOWS:\n")
top_10 <- all_windows[1:10]
for (i in 1:nrow(top_10)) {
  w <- top_10[i]
  cat(sprintf("   %2d. %d-%d (%d ans) | Score: %.3f | Médiane: %.1f%% | Navires: %d\n", 
              i, w$start_year, w$end_year, w$length, w$score, 
              100*w$median_coverage, w$active_ships))
}

# Margin over the 2nd-best window
if (nrow(all_windows) >= 2) {
  score_diff <- best$score - all_windows$score[2]
  score_diff_pct <- 100 * score_diff / all_windows$score[2]
  cat(sprintf("\nBest window advantage: %.3f (%.1f%%)\n", score_diff, score_diff_pct))

  if (score_diff_pct < 5) {
    cat("WARNING: Margin over the 2nd-best window is small (< 5%)\n")
  }
}

# ---- REMOVE INACTIVE (GHOST) VESSELS ----
yrs_idx <- which(years %in% best_window_yrs)
present_n <- rowSums(cov_mat[, yrs_idx, drop = FALSE] > 0)
core_ships <- names(present_n[present_n > 0])

if (length(core_ships) == 0) {
  stop("The optimal window contains no active vessels - please check the data.")
}

cat(sprintf("Active vessels in window: %d (out of %d total)\n",
            length(core_ships), nrow(cov_mat)))

if (length(core_ships) < nrow(cov_mat)) {
  inactive_ships <- setdiff(rownames(cov_mat), core_ships)
  cat("Inactive vessels excluded:", paste(inactive_ships, collapse = ", "), "\n")
}

cov_mat <- cov_mat[core_ships, , drop = FALSE]
best_ships <- core_ships

# ---- FULL EXPORT ----
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

# 1. All candidate windows
fwrite(all_windows[, -"years_list"], file.path(output_dir, "all_candidate_windows.csv"))

# 2. Top 20 windows for quick review
fwrite(all_windows[1:20, -"years_list"], file.path(output_dir, "top_20_windows.csv"))

# 3. CSV with metrics for the optimal window
core_window <- data.table(
  start_year = best$start_year,
  end_year   = best$end_year,
  length     = best$length,
  median_coverage = best$median_coverage,
  min_coverage = best$min_coverage,
  CV_coverage = best$CV_coverage,
  score = best$score,
  active_ships = best$active_ships,
  total_coverage = best$total_coverage
)
fwrite(core_window, file.path(output_dir, "best_core_window.csv"))

# 4. Full YAML with window AND vessel list
core_config <- list(
  # Time window
  start_year = best$start_year,
  end_year = best$end_year,
  length_years = best$length,

  # Coverage metrics
  median_coverage = best$median_coverage,
  min_coverage = best$min_coverage,
  cv_coverage = best$CV_coverage,
  score = best$score,
  active_ships = best$active_ships,
  total_coverage = best$total_coverage,

  # Active vessel list
  core_ships = best_ships,

  # Window years
  window_years = best_window_yrs,

  # Alternative window analysis
  total_candidates = nrow(all_windows),
  score_advantage = if(nrow(all_windows) >= 2) best$score - all_windows$score[2] else NA,
  score_advantage_pct = if(nrow(all_windows) >= 2) 100 * (best$score - all_windows$score[2]) / all_windows$score[2] else NA,

  # Metadata
  execution_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  input_file = basename(input_file),
  total_ships = length(best_ships),
  total_observations = nrow(ais_dt)
)

write_yaml(core_config, file.path(output_dir, "core_window.yaml"))

# 5. CSV with the vessel list
ships_dt <- data.table(
  ship_id = seq_along(best_ships),
  ship_name = best_ships
)
fwrite(ships_dt, file.path(output_dir, "core_ships.csv"))

# 6. Detailed markdown report
report_md <- sprintf(
  "# Rapport Core Window Enhanced (Coverage Matrix)

## 🎯 Fenêtre Optimale
- **Période :** %d–%d (%d ans)
- **Couverture médiane :** %.1f %%
- **Couverture minimale :** %.1f %%
- **CV inter-années :** %.3f
- **Score d'optimisation :** %.3f
- **Navires actifs :** %d

## 📊 Analyse des Alternatives
- **Total de fenêtres analysées :** %d
- **Avantage sur la 2ème meilleure :** %.3f (%.1f%%)

### Top 5 Fenêtres Alternatives
%s

## 🔍 Détails Techniques
- **Fenêtre minimale :** 5 ans
- **Critère d'optimisation :** L × Cbar × (Cmin²) / (1 + CV)
- **Navires exclus :** %s

## 📁 Fichiers Générés
- `all_candidate_windows.csv` : Toutes les fenêtres candidates
- `top_20_windows.csv` : Top 20 fenêtres pour analyse rapide
- `best_core_window.csv` : Métriques de la fenêtre optimale
- `core_window.yaml` : Configuration complète
- `core_ships.csv` : Liste des navires actifs

---
*Généré le %s*
", 
  best$start_year, best$end_year, best$length, 100*best$median_coverage, 
  100*best$min_coverage, best$CV_coverage, best$score, length(best_ships),
  nrow(all_windows),
  if(nrow(all_windows) >= 2) best$score - all_windows$score[2] else 0,
  if(nrow(all_windows) >= 2) 100 * (best$score - all_windows$score[2]) / all_windows$score[2] else 0,
  paste(sapply(1:min(5, nrow(all_windows)), function(i) {
    w <- all_windows[i]
    sprintf("  %d. %d-%d (%d ans) | Score: %.3f | Médiane: %.1f%%", 
            i, w$start_year, w$end_year, w$length, w$score, 100*w$median_coverage)
  }), collapse = "\n"),
  if(length(best_ships) < nrow(cov_mat)) paste(setdiff(rownames(cov_mat), best_ships), collapse = ", ") else "Aucun",
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

writeLines(report_md, file.path(output_dir, "core_window_enhanced_report.md"))

# 7. Per-year statistics for the optimal window
yearly_stats <- data.table(
  year = best_window_yrs,
  median_coverage = sapply(best_window_yrs, function(y) {
    median(cov_mat[, as.character(y)], na.rm = TRUE)
  }),
  min_coverage = sapply(best_window_yrs, function(y) {
    min(cov_mat[, as.character(y)], na.rm = TRUE)
  }),
  active_ships = sapply(best_window_yrs, function(y) {
    sum(cov_mat[, as.character(y)] > 0, na.rm = TRUE)
  })
)
fwrite(yearly_stats, file.path(output_dir, "yearly_coverage_stats.csv"))

# ---- FINAL SUMMARY ----
cat("\n  Markdown report : core_window_enhanced_report.md\n")
cat("  YAML config     : core_window.yaml\n")
cat("  Vessel list     : core_ships.csv\n")
cat("  All windows     : all_candidate_windows.csv\n")
cat("  Top 20 windows  : top_20_windows.csv\n")
cat("  Annual stats    : yearly_coverage_stats.csv\n")
cat("  Files written to", output_dir, "\n")
cat("  End:", format(Sys.time()), "\n")

cat("\nSTEP-0 ENHANCED completed successfully:", format(Sys.time()), "\n")
cat("  Selection file:", file.path(output_dir, "core_window_enhanced_report.md"), "\n")