#!/usr/bin/env Rscript
# ================================================================
#  STEP-0 bis – Sélection fenêtre « cœur » (score continu)
# ================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(yaml)
  library(matrixStats)   # ← rowMedians()/rowSds()
})

## ----------  paramètres « moteur »  ----------------------------
β        <- 1      # poids de la longueur L
δ        <- 2      # poids du pire-cas (coverage min)
λ        <- 1      # pénalité CV
min_years<- 5      # longueur mini de la fenêtre
loss_max <- .15    # % maxi de pings qu’on accepte de perdre
# ---------------------------------------------------------------

# 1) lire la couverture par navire-année
cov_file <- "~/scratch/output_V6/yearly_coverage_by_ship.csv"
if (!file.exists(cov_file))
  stop("❌ Fichier de couverture introuvable : ", cov_file)

cov <- fread(cov_file)            # cols : Navire, Annee, coverage
if (!all(c("Navire","Annee","coverage") %in% names(cov)))
  stop("Le fichier doit contenir les colonnes Navire, Annee, coverage")

# 2) matrice Navire × Année
cov_mat <- dcast(cov, Navire ~ Annee,
                 value.var = "coverage", fill = NA_real_)
years <- as.integer(setdiff(names(cov_mat), "Navire"))
dens  <- as.matrix(cov_mat[, -1])
rownames(dens) <- cov_mat$Navire
nY <- length(years)

best <- list(S = -Inf)
for (i in seq_len(nY)) for (j in i:nY) {
  L <- j - i + 1
  if (L < min_years) next
  sub <- dens[, i:j, drop = FALSE]
  sub <- sub[rowSums(!is.na(sub)) > 0, , drop = FALSE]   # navires actifs
  if (!nrow(sub)) next

  Cmed <- median(rowMedians(sub, na.rm = TRUE), na.rm = TRUE)
  Cmin <- min(sub, na.rm = TRUE)
  CV   <- sd(sub, na.rm = TRUE) /
          (mean(sub, na.rm = TRUE) + 1e-9)               # coefficient variation

  S <- (L^β) * Cmed * (Cmin^δ) / (1 + λ * CV)
  if (S > best$S)
    best <- list(S = S, start = years[i], end = years[j],
                 ships = rownames(sub))
}

cat(sprintf(
  "✅ Fenêtre candidate : %d – %d | Score = %.3f | Navires = %d\n",
  best$start, best$end, best$S, length(best$ships))
)

# 3) contrôle de la perte de pings
full_log <- fread("~/scratch/AIS_data/full_table_log.csv",
                  select = c("Navire", "timestamp"))
full_log[, Annee := year(ymd_hms(timestamp, tz = "UTC"))]

keep <- full_log[Annee %between% c(best$start, best$end) &
                 Navire %chin% best$ships]
loss <- 1 - nrow(keep) / nrow(full_log)

if (loss > loss_max)
  warning(sprintf("⚠️  %.1f %% des pings seraient écartés (> %.0f %%)",
                  100 * loss, 100 * loss_max))

# 4) sauvegarde pour la suite du pipeline
core_cfg <- list(
  window   = c(best$start, best$end),
  ships    = best$ships,
  loss_pct = round(100 * loss, 2),
  score    = round(best$S, 4)
)

out_dir <- "~/scratch/output_V6"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
yaml_path <- file.path(out_dir, "core_window.yaml")
write_yaml(core_cfg, yaml_path)

cat("✅  core_window.yaml écrit :", yaml_path, "\n")
