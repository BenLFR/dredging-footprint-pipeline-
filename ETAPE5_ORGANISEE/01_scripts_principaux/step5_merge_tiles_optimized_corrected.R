#!/usr/bin/env Rscript
# Step 5 optimisé : Fusion des tuiles -> grille f_i
# Corrections majeures :
#  - Grille & canevas identiques à constants.R (6933)
#  - p_l issu de moyenne simple (n_with_pl/pl_sum) si dispo (sinon fallback)
#  - PAS de double pondération profondeur (w1/w2 supprimés)  [CHANGEMENT]
#  - SVR = SAR * p_d ; ici p_d=1 en amont => SVR= SAR           [CHANGEMENT]
#  - f_i = SVR * p_l_corr * p_r * [0.3(1-e^-k) + 0.7(1-e^-0.05)]  [CHANGEMENT]
#  - CAP f_i ∈ [0,1]                                               [CHANGEMENT]

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(data.table); library(tidyr)
  library(rlang); library(tidyselect); library(lubridate); library(yaml)
  library(arrow); library(terra)
})

source("~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/constants.R")
sf_use_s2(FALSE)

args <- commandArgs(trailingOnly = TRUE)
scenario <- if(length(args) > 0) args[1] else "default"
cat("🔧 Fusion finale - Scenario :", scenario, "\n")

param_yaml <- "~/scratch/configuration/fi_parameters.yaml"
params_raw <- yaml::read_yaml(param_yaml)
get_scenario <- function(name) {
  s <- params_raw$scenarios[[name]]
  if (!is.null(s$inherit)) { parent <- get_scenario(s$inherit); s$inherit <- NULL; modifyList(parent, s) } else s
}
par <- get_scenario(scenario)

required <- c("alpha_dep","fast_fraction","slow_k","preservation_factor","k_fast")
miss <- setdiff(required, names(par))
if(length(miss)) stop("❌ Paramètres YAML manquants : ", paste(miss, collapse=", "))

k_table <- data.frame(
  longhurst_pr = names(par$k_fast),
  k_fast       = unlist(par$k_fast) *
                 ifelse(is.null(par$k_fast_multiplier), 1, par$k_fast_multiplier)
)

alpha_dep     <- par$alpha_dep
fast_frac     <- par$fast_fraction
slow_k        <- par$slow_k
preserv_fact  <- ifelse(is.null(par$preservation_factor), 0.272, par$preservation_factor)

cat("🔧  Paramètres f_i :\n")
cat("   - alpha_dep:", alpha_dep, "\n")
cat("   - fast_fraction:", fast_frac, "\n")
cat("   - slow_k:", slow_k, "a⁻¹\n")
cat("   - preservation_factor:", preserv_fact, "\n\n")

## 1) Fusion des tuiles SAR ----------------------------------------------------
sar_files <- list.files("~/scratch/output_V6/", pattern="^sar_.*\\.(parquet|rds)$", full.names=TRUE)
if(length(sar_files) == 0) stop("❌ Aucun fichier sar_* trouvé dans ~/scratch/output_V6/")

sar_list <- vector("list", length(sar_files))
for(i in seq_along(sar_files)) {
  file <- sar_files[i]
  cat("   Chargement :", basename(file), "\n")
  sar_list[[i]] <- if (grepl("\\.parquet$", file)) read_parquet(file) else readRDS(file)
}
sar_global <- rbindlist(sar_list, fill=TRUE); rm(sar_list); gc()
setDT(sar_global)

# [CHANGEMENT] Calcul SAR / p_l (moyenne simple si disponible, pl_eff agrégé)
sar_global[, SAR := sum_dw / CELL_AREA_M2]
if ("n_with_pl" %in% names(sar_global) && "pl_sum" %in% names(sar_global)) {
  sar_global[, p_l := fifelse(n_with_pl > 0, pl_sum / n_with_pl, NA_real_)]
} else {
  # Fallback : si ancienne structure
  if (all(c("sum_d_pl","sum_d") %in% names(sar_global))) {
    sar_global[, p_l := fifelse(sum_d > 0, sum_d_pl/sum_d, NA_real_)]
  } else {
    sar_global[, p_l := NA_real_]
  }
}

# p_d (moyenne pondérée) — mais Step-5 fixe p_d=1 → SVR = SAR
sar_global[, p_d := fifelse(sum_dw == 0, 0, sum_dw_pd/sum_dw)]
sar_global[, SVR := SAR]   # ici p_d=1 ⇒ SVR= SAR

## 2) Longhurst (si besoin) et correction fraîcheur sur p_l --------------------
# NOTE : si tu as déjà "fresh_fact" par cellule, on l’applique ; sinon 1.0
if(!"fresh_fact" %in% names(sar_global)) sar_global[, fresh_fact := 1.0]


## 3) k régional et f_i (30/70) + CAP -----------------------------------------
# Ici on suppose que l’affectation Longhurst arrive plus loin dans ton pipeline,
# ou que k est constant par défaut si province manquante.
if(!"longhurst_pr" %in% names(sar_global)) sar_global[, longhurst_pr := NA_character_]
sar_global <- merge(sar_global, k_table, by="longhurst_pr", all.x=TRUE)
# --- §2.9: depth-weighted lability + provincial freshness ---
if (!"p_d" %in% names(sar_global)) sar_global[, p_d := 1.0]

sar_global[, `:=`(
  dz1 = pmin(p_d, 0.05),            # 0–5 cm
  dz2 = pmax(p_d - 0.05, 0)         # >5 cm
)]

sar_global[, p_l_eff := fifelse(
  p_d > 0,
  (dz1 * p_l + dz2 * (alpha_dep * p_l)) / p_d,
  NA_real_
)]

if (!"fresh_fact" %in% names(sar_global)) {
  sar_global[, fresh_fact := 1.0]
  fh <- ifelse(is.null(par$freshness$factor_high), 1.5, par$freshness$factor_high)
  fl <- ifelse(is.null(par$freshness$factor_low),  0.5, par$freshness$factor_low)
  he <- if (is.null(par$freshness$high_export)) character(0) else par$freshness$high_export
  lo <- if (is.null(par$freshness$low_export))  character(0) else par$freshness$low_export
  sar_global[longhurst_pr %in% he, fresh_fact := fh]
  sar_global[longhurst_pr %in% lo, fresh_fact := fl]
}

sar_global[, p_l_corr := pmin(pmax(p_l_eff * fresh_fact, 0), 1)]
sar_global[is.na(k_fast), k_fast := median(k_table$k_fast, na.rm=TRUE)]  # fallback robuste

source("/home/benl/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/_pl_freshness_block.R")
t <- 1
sar_global[, f_i_full := SVR * p_l_corr * preserv_fact *
             (fast_frac * (1 - exp(-k_fast * t)) + (1 - fast_frac) * (1 - exp(-slow_k * t)))]
sar_global[, f_i_full := pmin(pmax(f_i_full, 0), 1)]   # [CHANGEMENT] CAP

# Scénario conservateur (k / 2 et p_l_corr / 2 si souhaité)
sar_global[, f_i_conservative := SVR * (p_l_corr/2) * preserv_fact *
             (fast_frac * (1 - exp(-(k_fast/2) * t)) + (1 - fast_frac) * (1 - exp(-(slow_k/2) * t)))]
sar_global[, f_i_conservative := pmin(pmax(f_i_conservative, 0), 1)]

source("/home/benl/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/_fi_sanity_block.R")
## 4) Sauvegarde f_i_grid -------------------------------------------------------
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_path  <- file.path("~/scratch/output_V6", paste0("fi_grid_", timestamp, ".parquet"))
arrow::write_parquet(sar_global[, .(grid_id, SAR, SVR, p_l, p_l_eff, p_l_corr, fresh_fact, longhurst_pr, k_fast,
                                    f_i_full, f_i_conservative, p_d,
                                    col = as.integer((grid_id-1L) %% GRID_COLS),
                                    row = as.integer((grid_id-1L) %/% GRID_COLS))],
                     out_path)
cat("✅ fi_grid sauvegardé :", basename(out_path), "\n")
