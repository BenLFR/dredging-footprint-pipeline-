#!/usr/bin/env Rscript
# =============================================================================
# EXTRACTION DES STATISTIQUES STEP 2
# =============================================================================
# Extrait les statistiques de filtrage pour chaque navire depuis les logs

library(data.table)
library(stringr)

# =============================================================================
# PARAMÈTRES
# =============================================================================
args <- commandArgs(trailingOnly = TRUE)

# Mode auto: scanner tous les logs disponibles
mode_auto <- length(args) == 0 || args[1] == "auto"

if (!mode_auto && length(args) < 1) {
  cat("Usage:\n")
  cat("  Rscript extract_step2_stats.R auto              # Scanner tous les logs\n")
  cat("  Rscript extract_step2_stats.R <job_ids...>      # Job IDs spécifiques\n")
  cat("\nExemples:\n")
  cat("  Rscript extract_step2_stats.R auto\n")
  cat("  Rscript extract_step2_stats.R 13266 13289\n")
  quit(status = 1)
}

cat("📊 EXTRACTION STATISTIQUES STEP 2\n")
cat("═══════════════════════════════════════\n")

if (mode_auto) {
  cat("Mode: AUTO (scanner tous les logs)\n")
  process_job_ids <- NULL
} else {
  process_job_ids <- args
  cat("Mode: MANUEL\n")
  cat("Process Job IDs:", paste(process_job_ids, collapse = ", "), "\n")
}
cat("\n")

# =============================================================================
# FONCTION D'EXTRACTION DEPUIS UN LOG
# =============================================================================
extract_stats_from_log <- function(log_file) {
  if (!file.exists(log_file)) {
    return(NULL)
  }

  lines <- readLines(log_file, warn = FALSE)

  # Initialiser les résultats
  stats <- list(
    navire = NA_character_,
    n_initial = NA_integer_,
    n_after_speed_filter = NA_integer_,
    n_before_geo = NA_integer_,
    n_after_geo = NA_integer_,
    n_removed_geo = NA_integer_,
    pct_removed_geo = NA_real_,
    geo_iterations = NA_integer_,
    n_outliers_IF = NA_integer_,
    pct_outliers_IF = NA_real_,
    n_stops = NA_integer_,
    pct_stops = NA_real_,
    n_final = NA_integer_
  )

  # Extraire le nom du navire
  navire_line <- grep("🚢 Navire sélectionné:", lines, value = TRUE)
  if (length(navire_line) > 0) {
    stats$navire <- sub(".*🚢 Navire sélectionné: ", "", navire_line[1])
    stats$navire <- trimws(stats$navire)
  }

  # Extraire données chargées (initial)
  data_line <- grep("✅ Données chargées:", lines, value = TRUE)
  if (length(data_line) > 0) {
    n <- as.integer(gsub("[^0-9]", "", str_extract(data_line[1], "[0-9,]+ observations")))
    stats$n_initial <- n
  }

  # Extraire filtre vitesse physique
  speed_line <- grep("✅ Filtre vitesse physique", lines, value = TRUE)
  if (length(speed_line) > 0) {
    # Format: "12345 → 12000 lignes"
    matches <- str_match(speed_line[1], "(\\d+) → (\\d+) lignes")
    if (!is.na(matches[1,2])) {
      stats$n_after_speed_filter <- as.integer(matches[1,3])
    }
  }

  # Extraire filtrage géospatial
  geo_line <- grep("✅ Filtres géospatiaux", lines, value = TRUE)
  if (length(geo_line) > 0) {
    # Format: "1234 lignes supprimées en 2 itération(s) (12.34 %)"
    matches <- str_match(geo_line[1], "(\\d+) lignes supprimées en (\\d+) itération.*\\(([0-9.]+) %\\)")
    if (!is.na(matches[1,2])) {
      stats$n_removed_geo <- as.integer(matches[1,2])
      stats$geo_iterations <- as.integer(matches[1,3])
      stats$pct_removed_geo <- as.numeric(matches[1,4])
    }
  }

  # Calculer n_before_geo et n_after_geo
  if (!is.na(stats$n_after_speed_filter) && !is.na(stats$n_removed_geo)) {
    stats$n_before_geo <- stats$n_after_speed_filter
    stats$n_after_geo <- stats$n_before_geo - stats$n_removed_geo
  }

  # Extraire résultats navire (section finale)
  result_section <- grep("📊 RÉSULTATS NAVIRE:", lines)
  if (length(result_section) > 0) {
    idx <- result_section[1]
    section_lines <- lines[idx:min(idx + 10, length(lines))]

    # Observations totales
    obs_line <- grep("Observations totales:", section_lines, value = TRUE)
    if (length(obs_line) > 0) {
      n <- as.integer(gsub("[^0-9]", "", obs_line[1]))
      stats$n_final <- n
    }

    # Outliers IF
    outlier_line <- grep("Outliers détectés:", section_lines, value = TRUE)
    if (length(outlier_line) > 0) {
      # Format: "1234 ( 12.34 %)"
      matches <- str_match(outlier_line[1], "(\\d+).*\\(\\s*([0-9.]+)\\s*%")
      if (!is.na(matches[1,2])) {
        stats$n_outliers_IF <- as.integer(matches[1,2])
        stats$pct_outliers_IF <- as.numeric(matches[1,3])
      }
    }

    # Arrêts
    stop_line <- grep("Arrêts détectés:", section_lines, value = TRUE)
    if (length(stop_line) > 0) {
      # Format: "1234 ( 12.34 %)"
      matches <- str_match(stop_line[1], "(\\d+).*\\(\\s*([0-9.]+)\\s*%")
      if (!is.na(matches[1,2])) {
        stats$n_stops <- as.integer(matches[1,2])
        stats$pct_stops <- as.numeric(matches[1,3])
      }
    }
  }

  return(stats)
}

# =============================================================================
# RECHERCHE DES LOGS
# =============================================================================
if (mode_auto) {
  # Scanner tous les logs step2_process_*.out disponibles
  local_logs <- Sys.glob("logs/step2_process_*.out")

  if (length(local_logs) == 0) {
    local_logs <- Sys.glob("pipeline_V6/logs/step2_process_*.out")
  }

  if (length(local_logs) == 0) {
    cat("⚠️ Aucun log Step 2 trouvé.\n")
    cat("Télécharger depuis GRIT avec:\n")
    cat("  scp -F ~/.ssh/config_grit 'grit:~/ais-pipeline/pipeline_V6/logs/step2_process_*.out' ./logs/\n")
    quit(status = 1)
  }

  cat(sprintf("📁 %d fichiers de log trouvés (mode AUTO)\n", length(local_logs)))

} else {
  # Mode manuel: chercher les logs pour les job IDs spécifiés
  local_logs <- c()
  for (job_id in process_job_ids) {
    pattern <- sprintf("logs/step2_process_%s_*.out", job_id)
    logs <- Sys.glob(pattern)

    if (length(logs) == 0) {
      logs <- Sys.glob(file.path("pipeline_V6", pattern))
    }

    if (length(logs) == 0) {
      cat(sprintf("⚠️ Aucun log trouvé pour Job %s\n", job_id))
    } else {
      cat(sprintf("📁 %d logs trouvés pour Job %s\n", length(logs), job_id))
      local_logs <- c(local_logs, logs)
    }
  }

  if (length(local_logs) == 0) {
    cat("\n⚠️ Aucun log trouvé. Télécharger depuis GRIT avec:\n")
    for (job_id in process_job_ids) {
      cat(sprintf("  scp -F ~/.ssh/config_grit 'grit:~/ais-pipeline/pipeline_V6/logs/step2_process_%s_*.out' ./logs/\n", job_id))
    }
    quit(status = 1)
  }
}

cat(sprintf("\n📁 Total: %d fichiers de log à traiter\n\n", length(local_logs)))

# =============================================================================
# EXTRACTION DES STATISTIQUES
# =============================================================================
cat("🔍 Extraction des statistiques...\n")

all_stats <- list()

for (log_file in local_logs) {
  # Extraire le job ID et le task ID depuis le nom de fichier
  # Format: step2_process_<JOB_ID>_<TASK_ID>.out
  filename <- basename(log_file)
  matches <- str_match(filename, "step2_process_(\\d+)_(\\d+)\\.out")

  if (is.na(matches[1,1])) {
    cat(sprintf("  ⚠️ Format de fichier non reconnu: %s\n", filename))
    next
  }

  job_id <- as.integer(matches[1,2])
  task_id <- as.integer(matches[1,3])

  cat(sprintf("  • Traitement Job %d, Task %d...\n", job_id, task_id))

  stats <- extract_stats_from_log(log_file)

  if (!is.null(stats)) {
    stats$task_id <- task_id
    stats$job_id <- job_id
    stats$log_file <- filename
    stats$log_mtime <- file.info(log_file)$mtime
    all_stats[[length(all_stats) + 1]] <- stats
  }
}

# Convertir en data.table
dt_stats <- rbindlist(all_stats, fill = TRUE)

# Déduplication: garder le log le plus récent pour chaque task_id
if (nrow(dt_stats) > 0) {
  cat("\n🔧 Déduplication des tasks (garder les logs les plus récents)...\n")
  setorder(dt_stats, task_id, -log_mtime)
  dt_stats_dedup <- dt_stats[, .SD[1], by = task_id]

  n_duplicates <- nrow(dt_stats) - nrow(dt_stats_dedup)
  if (n_duplicates > 0) {
    cat(sprintf("  • %d logs en doublon supprimés\n", n_duplicates))

    # Afficher les doublons remplacés
    duplicates <- dt_stats[!dt_stats_dedup, on = .(task_id, job_id, log_file)]
    if (nrow(duplicates) > 0) {
      for (i in 1:nrow(duplicates)) {
        dup <- duplicates[i]
        replacement <- dt_stats_dedup[task_id == dup$task_id]
        cat(sprintf("    Task %d: Job %d remplacé par Job %d\n",
                    dup$task_id, dup$job_id, replacement$job_id))
      }
    }
  }

  dt_stats <- dt_stats_dedup
  rm(dt_stats_dedup)
}

# Trier par task_id
setorder(dt_stats, task_id)

# Ajouter colonnes calculées
dt_stats[, `:=`(
  pct_speed_removed = round(100 * (n_initial - n_after_speed_filter) / n_initial, 2),
  pct_total_removed = round(100 * (n_initial - n_final) / n_initial, 2),
  n_total_removed = n_initial - n_final
)]

cat("\n✅ Extraction terminée!\n\n")

# =============================================================================
# AFFICHAGE DES RÉSULTATS
# =============================================================================
cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("RÉSUMÉ DES STATISTIQUES STEP 2\n")
cat("═══════════════════════════════════════════════════════════════════════════\n\n")

# Statistiques globales
cat("📊 STATISTIQUES GLOBALES:\n")
cat("─────────────────────────────────────────────────────────────────────────\n")
cat(sprintf("Nombre de navires traités: %d\n", nrow(dt_stats)))
cat(sprintf("Points initiaux (total):   %s\n", format(sum(dt_stats$n_initial, na.rm = TRUE), big.mark = ",")))
cat(sprintf("Points finaux (total):     %s\n", format(sum(dt_stats$n_final, na.rm = TRUE), big.mark = ",")))
cat(sprintf("Points supprimés (total):  %s (%.2f%%)\n\n",
            format(sum(dt_stats$n_total_removed, na.rm = TRUE), big.mark = ","),
            100 * sum(dt_stats$n_total_removed, na.rm = TRUE) / sum(dt_stats$n_initial, na.rm = TRUE)))

cat("📉 DÉTAIL PAR TYPE DE FILTRAGE:\n")
cat("─────────────────────────────────────────────────────────────────────────\n")
cat(sprintf("Filtre vitesse physique:   %s points (%.2f%% du total)\n",
            format(sum(dt_stats$n_initial - dt_stats$n_after_speed_filter, na.rm = TRUE), big.mark = ","),
            100 * sum(dt_stats$n_initial - dt_stats$n_after_speed_filter, na.rm = TRUE) / sum(dt_stats$n_initial, na.rm = TRUE)))
cat(sprintf("Filtrage géospatial:       %s points (%.2f%% du total)\n",
            format(sum(dt_stats$n_removed_geo, na.rm = TRUE), big.mark = ","),
            100 * sum(dt_stats$n_removed_geo, na.rm = TRUE) / sum(dt_stats$n_initial, na.rm = TRUE)))
cat(sprintf("Outliers IF détectés:      %s points (%.2f%% du final)\n",
            format(sum(dt_stats$n_outliers_IF, na.rm = TRUE), big.mark = ","),
            100 * sum(dt_stats$n_outliers_IF, na.rm = TRUE) / sum(dt_stats$n_final, na.rm = TRUE)))
cat(sprintf("Arrêts détectés:           %s points (%.2f%% du final)\n\n",
            format(sum(dt_stats$n_stops, na.rm = TRUE), big.mark = ","),
            100 * sum(dt_stats$n_stops, na.rm = TRUE) / sum(dt_stats$n_final, na.rm = TRUE)))

cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("DÉTAIL PAR NAVIRE\n")
cat("═══════════════════════════════════════════════════════════════════════════\n\n")

# Afficher détails par navire
for (i in 1:nrow(dt_stats)) {
  row <- dt_stats[i]

  cat(sprintf("🚢 NAVIRE %d: %s\n", row$task_id, row$navire))
  cat("─────────────────────────────────────────────────────────────────────────\n")

  cat(sprintf("Points initiaux:           %s\n", format(row$n_initial, big.mark = ",")))

  if (!is.na(row$n_after_speed_filter)) {
    removed_speed <- row$n_initial - row$n_after_speed_filter
    cat(sprintf("  - Filtre vitesse:        -%s (%.2f%%) → %s restants\n",
                format(removed_speed, big.mark = ","),
                row$pct_speed_removed,
                format(row$n_after_speed_filter, big.mark = ",")))
  }

  if (!is.na(row$n_removed_geo)) {
    cat(sprintf("  - Filtrage géospatial:   -%s (%.2f%%) en %d itération(s) → %s restants\n",
                format(row$n_removed_geo, big.mark = ","),
                row$pct_removed_geo,
                row$geo_iterations,
                format(row$n_after_geo, big.mark = ",")))
  }

  cat(sprintf("\nPoints finaux:             %s\n", format(row$n_final, big.mark = ",")))
  cat(sprintf("  - Outliers IF:           %s (%.2f%%)\n",
              format(row$n_outliers_IF, big.mark = ","),
              row$pct_outliers_IF))
  cat(sprintf("  - Arrêts:                %s (%.2f%%)\n",
              format(row$n_stops, big.mark = ","),
              row$pct_stops))

  cat(sprintf("\n📉 Réduction totale:       -%s (%.2f%%)\n",
              format(row$n_total_removed, big.mark = ","),
              row$pct_total_removed))
  cat("\n")
}

# =============================================================================
# SAUVEGARDE DU TABLEAU
# =============================================================================
# Générer le nom de fichier basé sur les job IDs utilisés
if (mode_auto) {
  unique_jobs <- sort(unique(dt_stats$job_id))
  job_ids_str <- paste(unique_jobs, collapse = "_")
  output_file <- sprintf("step2_statistics_jobs_%s.csv", job_ids_str)
} else {
  job_ids_str <- paste(process_job_ids, collapse = "_")
  output_file <- sprintf("step2_statistics_%s.csv", job_ids_str)
}

fwrite(dt_stats, output_file)

cat("═══════════════════════════════════════════════════════════════════════════\n")
cat(sprintf("💾 Tableau sauvegardé: %s\n", output_file))
cat(sprintf("💾 Jobs inclus: %s\n", paste(sort(unique(dt_stats$job_id)), collapse = ", ")))
cat("═══════════════════════════════════════════════════════════════════════════\n")
