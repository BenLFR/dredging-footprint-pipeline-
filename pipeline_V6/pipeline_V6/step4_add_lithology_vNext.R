# ────────────────────────────────────────────────────────────────────────────────
# STEP-4 vNext+4  ─  AJOUT LITHOLOGIE via HubOcean/dbSEABED (pipeline V6)
#
# VERSION: dbSEABED-compliant avec extraction par cellule unique + pl_base continu
#
# Corrections majeures vs vNext+2:
#   - NAflag=-99 au chargement raster (no-data dbSEABED propre)
#   - EXTRACTION PAR CELLULE UNIQUE: N_cells << N_pings -> gain perf majeur
#   - Type-specific normalization: membership 0-100, hardsoft signed [-1,+1]
#   - Hard-bottom index H = pmax(rock_prob, hard_prob) pour blending continu
#   - QC par cellule unique (non biaise par densite AIS)
#   - terraOptions optimisees pour HPC
#
# Refs: USGS dbSEABED docs, rspatial.github.io/terra
# ────────────────────────────────────────────────────────────────────────────────

## 0.  Packages -----------------------------------------------------------------
pkgs <- c("data.table", "terra")

safe_library <- function(pkg) {
  tryCatch(
    {
      library(pkg, character.only = TRUE)
      cat("  Package", pkg, "charge\n")
    },
    error = function(e) {
      stop(
        "Package '", pkg, "' manquant: ", e$message,
        "\n   Chargez le module R approprie ou installez le package"
      )
    }
  )
}

cat("Chargement des packages...\n")
invisible(sapply(pkgs, safe_library))
cat("Tous les packages charges avec succes\n\n")

## 0.5 Configuration terra pour HPC ---------------------------------------------
tmp_terra <- file.path(path.expand("~"), "scratch/tmp_terra")
dir.create(tmp_terra, showWarnings = FALSE, recursive = TRUE)
terraOptions(memfrac = 0.8, tempdir = tmp_terra, progress = 0)
cat("terraOptions: memfrac=0.8, tempdir=", tmp_terra, "\n\n")

## 1.  Chemins I/O --------------------------------------------------------------
home_dir <- path.expand("~")
cache_dir <- file.path(home_dir, "scratch/hubocean_cache")
output_dir <- file.path(home_dir, "scratch/output_V6")
config_dir <- file.path(home_dir, "ais-pipeline/configuration/lithology")

# Verification cache HubOcean
if (!dir.exists(cache_dir)) {
  stop(
    "Cache HubOcean non trouve: ", cache_dir,
    "\nExecutez d'abord: python prefetch_hubocean_stac.py"
  )
}

# Detection rasters (support subdirectory structure)
find_rasters_in_subdir <- function(subdir) {
  subdir_path <- file.path(cache_dir, subdir)
  if (!dir.exists(subdir_path)) {
    pattern <- paste0("^", subdir, "__.*\\.(tif|tiff)$")
    files <- list.files(cache_dir,
      pattern = pattern,
      full.names = TRUE, ignore.case = TRUE
    )
    return(files)
  }
  list.files(subdir_path,
    pattern = "\\.(tif|tiff)$",
    full.names = TRUE, ignore.case = TRUE
  )
}

find_single_raster_in_subdir <- function(subdir) {
  files <- find_rasters_in_subdir(subdir)
  if (length(files) == 0) {
    return(NULL)
  }
  files[which.max(file.mtime(files))]
}

## 2.  Chargement rasters -------------------------------------------------------
cat("Detection des rasters dbSEABED...\n")

tex_files <- find_rasters_in_subdir("texture")
cat("  texture files: ", length(tex_files), " trouve(s)\n")

# Detection par nom de fichier (HubOcean: mud, snd, gvl)
mud_f <- tex_files[grepl("mud|silt|clay", basename(tex_files), ignore.case = TRUE)]
sand_f <- tex_files[grepl("sand|snd", basename(tex_files), ignore.case = TRUE)]
gravel_f <- tex_files[grepl("gravel|gvl|coarse", basename(tex_files), ignore.case = TRUE)]

# Construction stack texture
# P1: choisir les fichiers les plus recents (pas [1])
pick_latest <- function(x) x[which.max(file.mtime(x))]

if (length(mud_f) > 0 && length(sand_f) > 0 && length(gravel_f) > 0) {
  cat("  -> Mode: fichiers separes (mud/sand/gravel)\n")
  r_texture <- rast(c(pick_latest(mud_f), pick_latest(sand_f), pick_latest(gravel_f)))
  names(r_texture) <- c("mud", "sand", "gravel")
} else if (length(tex_files) > 0) {
  cat("  -> Mode: fichier(s) combine(s)\n")
  r_texture <- rast(tex_files)
} else {
  stop("Aucun raster texture trouve dans ", cache_dir)
}

# --- PATCH P0-1: renommer les bandes texture de facon robuste ---
nm <- names(r_texture)
if (!all(c("mud", "sand", "gravel") %in% nm)) {
  cat("  [P0-1] Renommage bandes texture...\n")
  mud_idx <- grep("mud|silt|clay", nm, ignore.case = TRUE)
  sand_idx <- grep("sand|snd", nm, ignore.case = TRUE)
  gravel_idx <- grep("gravel|gvl|coarse", nm, ignore.case = TRUE)

  # fallback si patterns absents et 3 bandes -> assume ordre 1:3
  if (length(mud_idx) == 0 && length(sand_idx) == 0 && length(gravel_idx) == 0 && nlyr(r_texture) >= 3) {
    names(r_texture)[1:3] <- c("mud", "sand", "gravel")
    cat("    -> fallback ordre 1:3 = mud/sand/gravel\n")
  } else {
    if (length(mud_idx) > 0) names(r_texture)[mud_idx[1]] <- "mud"
    if (length(sand_idx) > 0) names(r_texture)[sand_idx[1]] <- "sand"
    if (length(gravel_idx) > 0) names(r_texture)[gravel_idx[1]] <- "gravel"
    cat("    -> pattern match: ", paste(names(r_texture), collapse = ", "), "\n")
  }
}

cat(
  "  texture stack: ", nlyr(r_texture), " bande(s), res=",
  paste(round(res(r_texture), 4), collapse = "x"), "\n"
)
cat("  noms bandes: ", paste(names(r_texture), collapse = ", "), "\n")

# Hard/soft et Rock (optionnels)
hardsoft_path <- find_single_raster_in_subdir("hard_soft")
r_hardsoft <- if (!is.null(hardsoft_path)) rast(hardsoft_path) else NULL

rock_path <- find_single_raster_in_subdir("rock")
r_rock <- if (!is.null(rock_path)) rast(rock_path) else NULL

if (!is.null(r_hardsoft)) cat("  hard_soft: loaded\n")
if (!is.null(r_rock)) cat("  rock: loaded\n")

# --- PATCH P0-2: aligner hard_soft/rock sur la grille texture ---
ref <- r_texture[[1]]

align_to_ref <- function(r, ref, name) {
  if (is.null(r)) {
    return(NULL)
  }
  if (!compareGeom(r, ref, stopOnError = FALSE)) {
    cat("  [P0-2] ", name, ": resample -> grille texture (method=near)\n")
    r <- resample(r, ref, method = "near") # near pour indices/membership
  } else {
    cat("  [P0-2] ", name, ": geometrie OK\n")
  }
  r
}

r_hardsoft <- align_to_ref(r_hardsoft, ref, "hard_soft")
r_rock <- align_to_ref(r_rock, ref, "rock")
rm(ref)

## 2.5 Construction STACK UNIQUE (optimisation perf) ----------------------------
cat("\nConstruction stack unifie pour extraction unique...\n")

r_stack <- r_texture
layer_names <- names(r_texture)

if (!is.null(r_hardsoft)) {
  r_stack <- c(r_stack, r_hardsoft)
  layer_names <- c(layer_names, "hardness")
}
if (!is.null(r_rock)) {
  r_stack <- c(r_stack, r_rock)
  layer_names <- c(layer_names, "rock")
}
names(r_stack) <- layer_names

# PATCH vNext+3: NAflag dbSEABED (evite de propager -99 partout)
try(NAflag(r_stack) <- -99, silent = TRUE)

cat("  Stack final: ", nlyr(r_stack), " couches (", paste(layer_names, collapse = ", "), ")\n")
cat("  NAflag set to -99 for dbSEABED no-data handling\n")

## 3.  Detection fichier AIS Step 3 ---------------------------------------------
ais_files <- list.files(output_dir,
  pattern = "AIS_data_core_preprocessed_V6_.*\\.rds$",
  full.names = TRUE
)
if (length(ais_files) == 0) {
  stop("Aucun fichier AIS trouve dans ", output_dir)
}
# PATCH P0: fichier le plus recent par mtime (pas max lexicographique)
ais_path <- ais_files[which.max(file.mtime(ais_files))]

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_file <- file.path(output_dir, sprintf("AIS_with_lithology_%s.rds", timestamp))

cat("\nFichier AIS source: ", basename(ais_path), "\n")
cat("Sortie prevue:      ", basename(out_file), "\n\n")

## 4.  Table de correspondance lithologie -> pl_base ----------------------------
pl_lookup_file <- file.path(config_dir, "pl_lookup_v1.csv")

if (file.exists(pl_lookup_file)) {
  cat("Chargement pl_base_lookup depuis: ", basename(pl_lookup_file), "\n")
  pl_base_lookup <- fread(pl_lookup_file)
} else {
  cat("Utilisation pl_base_lookup par defaut (hardcode)\n")
  pl_base_lookup <- data.table(
    lithologie_canon = c(
      "mud", "sandy_mud", "muddy_sand", "sand",
      "gravelly_sand", "sandy_gravel", "gravel",
      "rock", "hard_bottom", "mixed", "unknown"
    ),
    pl_base = c(
      0.92, # mud - haute penetration
      0.85, # sandy_mud
      0.70, # muddy_sand
      0.55, # sand - penetration moyenne
      0.45, # gravelly_sand
      0.35, # sandy_gravel
      0.25, # gravel - basse penetration
      0.05, # rock - tres faible
      0.10, # hard_bottom
      0.50, # mixed - moyenne
      0.50 # unknown - defaut
    )
  )
}
setkey(pl_base_lookup, lithologie_canon)

## 5.  Fonctions utilitaires dbSEABED -------------------------------------------

# Normalisation membership 0-100 -> 0-1 (rock, mud, sand, gravel)
norm_membership_0_100 <- function(x) {
  n_nodata <- sum(x <= -90, na.rm = TRUE)
  x[x <= -90] <- NA_real_

  # Si valeurs > 1, echelle 0-100 -> diviser par 100
  if (any(x > 1, na.rm = TRUE)) {
    x <- x / 100
  }

  # Clamp 0-1
  x <- pmin(pmax(x, 0), 1)
  attr(x, "n_nodata") <- n_nodata
  x
}

# Normalisation hard_soft signe (-1 to +1) -> garde tel quel
norm_hardsoft_signed <- function(x) {
  x[x <= -90] <- NA_real_
  # Clamp -1 to +1 (garde le signe pour QA)
  pmin(pmax(x, -1), 1)
}

# Conversion hard_soft signe -> probabilite 0-1
# -1 (soft) -> 0, +1 (hard) -> 1
hardsoft_to_prob <- function(x_signed) {
  ifelse(is.na(x_signed), NA_real_, pmin(pmax((x_signed + 1) / 2, 0), 1))
}

# Closure texture (mud+sand+gravel -> sum=1) pour classification
close_texture <- function(mud, sand, gravel) {
  tot <- mud + sand + gravel
  ok <- !is.na(tot) & tot > 0

  mudC <- sandC <- gravelC <- rep(NA_real_, length(tot))
  mudC[ok] <- mud[ok] / tot[ok]
  sandC[ok] <- sand[ok] / tot[ok]
  gravelC[ok] <- gravel[ok] / tot[ok]

  list(mud = mudC, sand = sandC, gravel = gravelC)
}

## 6.  Classification lithologie (dbSEABED-compliant) ---------------------------
# Utilise Hard-bottom index H = pmax(rock, hardness)
# Rock confirme seulement si H > 0.7 ET texture non meuble

canon_litho_v2 <- function(mud, sand, gravel, hard, rock) {
  n <- length(mud)

  # Hard-bottom index continu
  H <- pmax(rock, hard, na.rm = TRUE)
  H[!is.finite(H)] <- NA_real_

  # Masques
  has_frac <- !(is.na(mud) & is.na(sand) & is.na(gravel))
  has_H <- !is.na(H)

  # Copies avec NA->0 pour comparaisons
  mud2 <- fifelse(is.na(mud), 0, mud)
  sand2 <- fifelse(is.na(sand), 0, sand)
  gravel2 <- fifelse(is.na(gravel), 0, gravel)
  H2 <- fifelse(is.na(H), 0, H)
  rock2 <- fifelse(is.na(rock), 0, rock)

  result <- rep("unknown", n)

  # 1. Rock CONFIRME (criteres stricts dbSEABED)
  # H > 0.7 ET (rock > 0.6 OU hardness > 0.7) ET texture non meuble
  texture_not_soft <- (mud2 < 0.3) & (sand2 < 0.5)
  rock_confirmed <- has_H & H2 > 0.7 & rock2 > 0.5 & texture_not_soft
  result[rock_confirmed] <- "rock"

  # 2. Hard bottom (H eleve mais rock pas dominant)
  idx_hard <- result == "unknown" & has_H & H2 > 0.75 & rock2 < 0.5
  result[idx_hard] <- "hard_bottom"

  # 3. Classification par fractions texture
  to_classify <- result == "unknown" & has_frac

  if (any(to_classify)) {
    # Gravel dominant (>50%)
    idx <- to_classify & gravel2 > 0.5
    result[idx] <- "gravel"

    idx <- to_classify & result == "unknown" & gravel2 > 0.3 & sand2 > mud2
    result[idx] <- "sandy_gravel"

    idx <- to_classify & result == "unknown" & gravel2 > 0.3 & mud2 >= sand2
    result[idx] <- "gravel"

    # Gravel modere (15-30%)
    idx <- to_classify & result == "unknown" & gravel2 > 0.15 & sand2 > mud2
    result[idx] <- "gravelly_sand"

    idx <- to_classify & result == "unknown" & gravel2 > 0.15 & mud2 >= sand2
    result[idx] <- "mixed"

    # Mud dominant (>70%)
    idx <- to_classify & result == "unknown" & mud2 > 0.7
    result[idx] <- "mud"

    # Sand dominant (>70%)
    idx <- to_classify & result == "unknown" & sand2 > 0.7
    result[idx] <- "sand"

    # Melanges mud-sand
    idx <- to_classify & result == "unknown" & mud2 > 0.4 & sand2 > 0.2 & mud2 > sand2
    result[idx] <- "sandy_mud"

    idx <- to_classify & result == "unknown" & sand2 > 0.4 & mud2 > 0.2 & sand2 > mud2
    result[idx] <- "muddy_sand"

    # Reste: classification par maximum
    idx <- to_classify & result == "unknown" & (mud2 + sand2 + gravel2) > 0
    result[idx & mud2 >= sand2 & mud2 >= gravel2] <- "mud"
    result[idx & sand2 > mud2 & sand2 >= gravel2] <- "sand"
    result[idx & gravel2 > mud2 & gravel2 > sand2] <- "gravel"
  }

  list(litho = result, H = H)
}

## 7.  Lecture des donnees AIS --------------------------------------------------
cat("Lecture des donnees AIS...\n")
ais_dt <- readRDS(ais_path)
setDT(ais_dt)

n_ais <- nrow(ais_dt)
cat("  Pings AIS charges: ", format(n_ais, big.mark = " "), "\n")

if (!all(c("Lon", "Lat") %in% names(ais_dt))) {
  stop("Colonnes Lon/Lat manquantes dans les donnees AIS")
}

## 8. EXTRACTION ULTRA-OPTIMISEE (cellule unique -> remap pings) ----------------
# vNext+3: Extrait une seule fois par cellule raster, puis remap sur tous les pings
# Gain de perf majeur sur AIS denses (N_cells << N_pings)

cat("\nExtraction raster par cellule unique (dedup spatial)...\n")

# 8.1 Calcul du cell_id pour chaque ping (chunke, RAM-safe)
ais_dt[, cell_id := NA_integer_]

chunk_size <- 2e6
n_chunks <- ceiling(n_ais / chunk_size)
idx_list <- split(seq_len(n_ais), ceiling(seq_len(n_ais) / chunk_size))

for (k in seq_along(idx_list)) {
  ii <- idx_list[[k]]
  cat("  cell_id chunk ", k, "/", n_chunks, " (", length(ii), " pings)... ")

  xy <- as.matrix(ais_dt[ii, .(Lon, Lat)])
  ais_dt[ii, cell_id := cellFromXY(r_stack[[1]], xy)]

  rm(xy)
  gc(verbose = FALSE)
  cat("OK\n")
}

# 8.2 Liste des cellules uniques (beaucoup plus petit que n_ais)
# PATCH P1: pas de sort() -> gain perf sur gros datasets
cells_unique <- unique(ais_dt$cell_id)
cells_unique <- cells_unique[!is.na(cells_unique)]

n_cells <- length(cells_unique)
cat(
  "  Cellules uniques a extraire: ", format(n_cells, big.mark = " "),
  " (vs ", format(n_ais, big.mark = " "), " pings)\n"
)
cat("  Ratio compression: ", round(n_ais / n_cells, 1), "x\n")

if (n_cells == 0) stop("Aucune cellule raster associee aux pings (verifier extent/CRS).")

# 8.3 Extraction des valeurs raster UNE SEULE FOIS par cellule (chunke)
cell_chunk <- 1e6 # ajustable
n_cell_chunks <- ceiling(n_cells / cell_chunk)
cell_idx_list <- split(seq_len(n_cells), ceiling(seq_len(n_cells) / cell_chunk))

cell_vals_list <- vector("list", length(cell_idx_list))

for (k in seq_along(cell_idx_list)) {
  jj <- cell_idx_list[[k]]
  cell_ids_k <- cells_unique[jj]

  cat("  extract cellules ", k, "/", n_cell_chunks, " (", length(cell_ids_k), " cells)... ")

  xy_cell <- xyFromCell(r_stack[[1]], cell_ids_k)
  v <- extract(r_stack, xy_cell, method = "simple")
  # P0-1 fallback: remove ID column if present (terra version compatibility)
  if ("ID" %in% names(v)) v$ID <- NULL

  # Securise type + colonne cell_id
  cell_dt_k <- data.table(cell_id = cell_ids_k)
  cell_dt_k <- cbind(cell_dt_k, as.data.table(v))

  cell_vals_list[[k]] <- cell_dt_k

  rm(cell_ids_k, xy_cell, v, cell_dt_k)
  gc(verbose = FALSE)
  cat("OK\n")
}

cell_vals <- rbindlist(cell_vals_list, use.names = TRUE, fill = TRUE)
rm(cell_vals_list)
gc(verbose = FALSE)

cat("  Valeurs extraites pour ", nrow(cell_vals), " cellules uniques\n")

# 8.4 Remapping cell_id -> valeurs raster (JOIN data.table, ROBUSTE)
# PATCH P0: rename + mget au lieu de get(paste0("i.",x)) fragile en NSE
setkey(cell_vals, cell_id)

# Renommer les colonnes de cell_vals vers les colonnes AIS cibles
rename_map <- c(
  mud = "frac_mud", sand = "frac_sand", gravel = "frac_gravel",
  hardness = "hardness", rock = "rock"
)
present <- intersect(names(rename_map), names(cell_vals))
if (length(present) > 0) {
  setnames(cell_vals, old = present, new = rename_map[present])
  cat("  Colonnes renommees: ", paste(present, "->", rename_map[present], collapse = ", "), "\n")
}

# Pre-allouer les colonnes AIS
ais_dt[, `:=`(
  frac_mud = NA_real_,
  frac_sand = NA_real_,
  frac_gravel = NA_real_,
  hardness = NA_real_,
  rock = NA_real_
)]

# Update join en bloc (robuste)
cols <- intersect(
  setdiff(names(cell_vals), "cell_id"),
  c("frac_mud", "frac_sand", "frac_gravel", "hardness", "rock")
)

cat("  Remapping ", length(cols), " colonnes sur ", format(n_ais, big.mark = " "), " pings... ")
ais_dt[cell_vals, (cols) := mget(paste0("i.", cols)), on = "cell_id"]
cat("OK\n")

# P0 sanity: si on a des cell_id, on doit recuperer au moins qq valeurs non-NA
n_mapped <- ais_dt[
  !is.na(cell_id),
  sum(!is.na(frac_mud) | !is.na(frac_sand) | !is.na(frac_gravel) |
    !is.na(rock) | !is.na(hardness))
]
if (n_mapped == 0L) stop("[P0] Remap a echoue: 0 valeurs mappees (check join / i.*)")
cat("  Sanity check: ", format(n_mapped, big.mark = " "), " pings avec au moins 1 valeur mappee\n")

rm(cell_vals)
gc(verbose = FALSE)

cat("Extraction terminee: valeurs remappees sur tous les pings.\n")

## 9.  QC echelle dbSEABED (CRITIQUE) -------------------------------------------
cat("\n--- QC ECHELLE dbSEABED (avant normalisation) ---\n")

qc_scale <- function(x, name) {
  # P1: QC missingness reel (NA) en plus du -99
  n_na <- sum(is.na(x))
  n_neg99 <- sum(x <= -90, na.rm = TRUE) # utile si NAflag n'a pas ete applique
  n_gt1 <- sum(x > 1, na.rm = TRUE)
  n_gt10 <- sum(x > 10, na.rm = TRUE)
  rng <- range(x, na.rm = TRUE)
  cat(sprintf(
    "  %s: range=[%.2f, %.2f], n_NA=%d, n_nodata(-99)=%d, n_gt1=%d, n_gt10=%d\n",
    name, rng[1], rng[2], n_na, n_neg99, n_gt1, n_gt10
  ))
  invisible(NULL)
}

qc_rock <- qc_scale(ais_dt$rock, "rock")
qc_hard <- qc_scale(ais_dt$hardness, "hardness")
qc_mud <- qc_scale(ais_dt$frac_mud, "frac_mud")
qc_sand <- qc_scale(ais_dt$frac_sand, "frac_sand")
qc_grav <- qc_scale(ais_dt$frac_gravel, "frac_gravel")

## 10. Normalisation dbSEABED (TYPE-SPECIFIC) -----------------------------------
cat("\nNormalisation dbSEABED (type-specific)...\n")

# Rock et texture: membership 0-100 -> probability 0-1
ais_dt[, rock_prob := norm_membership_0_100(rock)]
ais_dt[, frac_mud := norm_membership_0_100(frac_mud)]
ais_dt[, frac_sand := norm_membership_0_100(frac_sand)]
ais_dt[, frac_gravel := norm_membership_0_100(frac_gravel)]

# Hardness: index signe -1..+1 -> probability 0-1
# CRITIQUE: hardness est sur [-1,+1], pas [0,100]!
ais_dt[, hard_soft_signed := norm_hardsoft_signed(hardness)]
ais_dt[, hard_prob := hardsoft_to_prob(hard_soft_signed)]

# Diagnostic post-normalisation
cat(
  "  rock_prob:     median=", round(median(ais_dt$rock_prob, na.rm = TRUE), 3),
  " p90=", round(quantile(ais_dt$rock_prob, 0.90, na.rm = TRUE), 3),
  " p99=", round(quantile(ais_dt$rock_prob, 0.99, na.rm = TRUE), 3), "\n"
)
cat(
  "  hard_prob:     median=", round(median(ais_dt$hard_prob, na.rm = TRUE), 3),
  " p90=", round(quantile(ais_dt$hard_prob, 0.90, na.rm = TRUE), 3),
  " p99=", round(quantile(ais_dt$hard_prob, 0.99, na.rm = TRUE), 3), "\n"
)
cat(
  "  frac_mud:      median=", round(median(ais_dt$frac_mud, na.rm = TRUE), 3),
  " p99=", round(quantile(ais_dt$frac_mud, 0.99, na.rm = TRUE), 3), "\n"
)

# Correlation check (should be high since hardness ~ 2*rock/100 - 1)
cor_rock_hard_raw <- cor(ais_dt$rock, ais_dt$hardness, use = "pairwise.complete.obs")
cat("  Corr raw rock~hardness: ", round(cor_rock_hard_raw, 3), " (expected ~1 = redundant)\n")

## 11. Classification lithologie ------------------------------------------------
cat("\nClassification lithologique (dbSEABED-compliant v2)...\n")

litho_result <- canon_litho_v2(
  mud = ais_dt$frac_mud,
  sand = ais_dt$frac_sand,
  gravel = ais_dt$frac_gravel,
  hard = ais_dt$hard_prob,
  rock = ais_dt$rock_prob
)

ais_dt[, lithologie_canon := litho_result$litho]
ais_dt[, H_index := litho_result$H] # Hard-bottom index continu

# Stats classification
n_rock <- sum(ais_dt$lithologie_canon == "rock")
cat(
  "  Rock confirme (strict): ", format(n_rock, big.mark = " "), " points (",
  round(100 * n_rock / n_ais, 1), "%)\n"
)

# Flag is_hardrock (SANS gravel - sediment meuble grossier)
ais_dt[, is_hardrock := lithologie_canon %in% c("rock", "hard_bottom")]

## 12. Calcul pl_base CONTINU (blend H_index) -----------------------------------
cat("\nCalcul pl_base continu (blend H_index x texture)...\n")

# pl_texture basee sur classification discrete
ais_dt[pl_base_lookup, pl_texture := i.pl_base, on = "lithologie_canon"]
ais_dt[is.na(pl_texture), pl_texture := 0.50]

# Blend continu avec H_index (PATCH P0 vNext+4: threshold + rescaling)
# pl_base = (1 - H_blend) * pl_texture + H_blend * pl_hard
# H_blend n'agit que si H_index > H0 (seuil d'activation hard-bottom)
# Evite de penaliser les fonds moyennement durs

pl_hard <- 0.05
H0 <- 0.70 # seuil d'activation: blend only above this threshold
ais_dt[, H_blend := fifelse(
  is.na(H_index), 0,
  pmax(0, (pmin(H_index, 1) - H0) / (1 - H0))
)]
ais_dt[, pl_base := (1 - H_blend) * pl_texture + H_blend * pl_hard]

cat(
  "  H_blend: median=", round(median(ais_dt$H_blend, na.rm = TRUE), 3),
  " p90=", round(quantile(ais_dt$H_blend, 0.90, na.rm = TRUE), 3),
  " p99=", round(quantile(ais_dt$H_blend, 0.99, na.rm = TRUE), 3), "\n"
)

# --- PATCH P1: Cell-based QC on pl_base (non biaise par densite AIS) ---
qc_pl_cells <- ais_dt[!is.na(cell_id),
  .(pl_med = median(pl_base, na.rm = TRUE)),
  by = cell_id
]
cat(
  "  pl_base (by cell): median=", round(median(qc_pl_cells$pl_med, na.rm = TRUE), 3),
  " p90=", round(quantile(qc_pl_cells$pl_med, 0.90, na.rm = TRUE), 3), "\n"
)
rm(qc_pl_cells)
gc(verbose = FALSE)

# --- PATCH P1: Verification CODA texture sum ---
tex_sum <- ais_dt[, frac_mud + frac_sand + frac_gravel]
cat(
  "  texture sum: median=", round(median(tex_sum, na.rm = TRUE), 3),
  " p01=", round(quantile(tex_sum, 0.01, na.rm = TRUE), 3),
  " p99=", round(quantile(tex_sum, 0.99, na.rm = TRUE), 3), "\n"
)
rm(tex_sum)

# Cleanup
ais_dt[, c("pl_texture", "H_blend") := NULL]

## 13. Flags et compatibilite ---------------------------------------------------
ais_dt[, has_lithology := !is.na(frac_mud) | !is.na(frac_sand) | !is.na(frac_gravel) |
  !is.na(hard_prob) | !is.na(rock_prob)]
ais_dt[, lithologie := lithologie_canon]

# --- PATCH P0-3: conserver les valeurs brutes pour QA ---
ais_dt[, rock_raw := rock]
ais_dt[, hardness_raw := hardness]

# Rename for backward compatibility
ais_dt[, rock := rock_prob]
ais_dt[, hardness := hard_prob]

# Attributs metadata
attr(ais_dt, "crs") <- "+proj=longlat +datum=WGS84"
attr(ais_dt, "lithology_source") <- "HubOcean/dbSEABED"
attr(ais_dt, "lithology_version") <- timestamp
attr(ais_dt, "pipeline_version") <- "vNext+4"

## 14. Export -------------------------------------------------------------------
cat("\nSauvegarde des resultats...\n")
saveRDS(ais_dt, out_file)

n_with_litho <- sum(ais_dt$has_lithology)
pct_with <- round(100 * n_with_litho / n_ais, 1)

cat("  ", format(n_with_litho, big.mark = " "), " pings avec lithologie (", pct_with, " %)\n")
cat("  ", format(n_ais - n_with_litho, big.mark = " "), " pings sans lithologie\n")

## 15. Diagnostic ---------------------------------------------------------------
cat("\n--- Distribution des lithologies ---\n")
litho_dist <- ais_dt[, .N, by = lithologie_canon][order(-N)]
litho_dist[, pct := round(100 * N / sum(N), 1)]
print(litho_dist)

cat("\n--- Distribution pl_base ---\n")
cat("  Min:    ", round(min(ais_dt$pl_base, na.rm = TRUE), 3), "\n")
cat("  Q1:     ", round(quantile(ais_dt$pl_base, 0.25, na.rm = TRUE), 3), "\n")
cat("  Median: ", round(median(ais_dt$pl_base, na.rm = TRUE), 3), "\n")
cat("  Mean:   ", round(mean(ais_dt$pl_base, na.rm = TRUE), 3), "\n")
cat("  Q3:     ", round(quantile(ais_dt$pl_base, 0.75, na.rm = TRUE), 3), "\n")
cat("  Max:    ", round(max(ais_dt$pl_base, na.rm = TRUE), 3), "\n")

cat("\n--- Distribution H_index ---\n")
cat("  Median: ", round(median(ais_dt$H_index, na.rm = TRUE), 3), "\n")
cat("  P90:    ", round(quantile(ais_dt$H_index, 0.90, na.rm = TRUE), 3), "\n")
cat("  P99:    ", round(quantile(ais_dt$H_index, 0.99, na.rm = TRUE), 3), "\n")

cat("\n--- Distribution is_hardrock ---\n")
hardrock_dist <- ais_dt[, .N, by = is_hardrock]
hardrock_dist[, pct := round(100 * N / sum(N), 1)]
print(hardrock_dist)

## 15.5 QC par cellule raster (non biaise par densite AIS) ----------------------
cat("\n--- QC PAR CELLULE UNIQUE (non biaise) ---\n")

# cell_id deja calcule dans section 8 (extraction par cellule unique)

# Stats par cellule unique
qc_cells <- ais_dt[!is.na(cell_id),
  .(
    rock_med = median(rock_prob, na.rm = TRUE),
    rock_p90 = quantile(rock_prob, 0.90, na.rm = TRUE),
    hard_med = median(hard_prob, na.rm = TRUE),
    n_pings = .N
  ),
  by = cell_id
]

n_unique_cells <- nrow(qc_cells)
cat("  Cellules uniques:  ", format(n_unique_cells, big.mark = " "), "\n")
cat("  Pings/cellule med: ", round(median(qc_cells$n_pings), 1), "\n")
cat("  rock_prob (by cell):\n")
cat(
  "    median=", round(median(qc_cells$rock_med, na.rm = TRUE), 3),
  " p90=", round(quantile(qc_cells$rock_med, 0.90, na.rm = TRUE), 3),
  " p99=", round(quantile(qc_cells$rock_med, 0.99, na.rm = TRUE), 3), "\n"
)

# % cellules avec rock_med > 0.7 (vraiment rocheuses)
pct_cells_rocky <- round(100 * sum(qc_cells$rock_med > 0.7, na.rm = TRUE) / n_unique_cells, 1)
cat("  Cellules rock>0.7: ", pct_cells_rocky, "% (target: <15-25%)\n")

rm(qc_cells)
gc(verbose = FALSE)

## 16. Validation dbSEABED-compliance -------------------------------------------
cat("\n--- VALIDATION dbSEABED-COMPLIANCE ---\n")

pct_rock <- litho_dist[lithologie_canon == "rock", pct]
if (length(pct_rock) == 0) pct_rock <- 0

median_pl <- median(ais_dt$pl_base, na.rm = TRUE)

# Correlation rock_prob <-> hard_prob (positive attendue, likely ~1 = redundant)
cor_rock_hard <- cor(ais_dt$rock_prob, ais_dt$hard_prob, use = "pairwise.complete.obs")

# Rock rarement associe a mud > 0.6
n_rock_total <- sum(ais_dt$lithologie_canon == "rock", na.rm = TRUE)
if (n_rock_total > 0) {
  rock_with_high_mud <- sum(ais_dt$lithologie_canon == "rock" & ais_dt$frac_mud > 0.6, na.rm = TRUE)
  pct_rock_high_mud <- round(100 * rock_with_high_mud / n_rock_total, 1)
} else {
  pct_rock_high_mud <- 0
}

cat("  Rock % (by ping):     ", pct_rock, "% (target: <15-25%)\n")
cat("  Rock % (by cell):     ", pct_cells_rocky, "% (unbiased estimate)\n")
cat("  Median pl_base:       ", round(median_pl, 3), " (target: 0.4-0.6)\n")
cat("  Corr rock_prob~hard:  ", round(cor_rock_hard, 3), " (expected ~1 = redundant)\n")
cat("  Rock+high mud:        ", pct_rock_high_mud, "% (target: <5%)\n")

# Verdict (use cell-based rock % for unbiased assessment)
pass_count <- 0
if (pct_cells_rocky < 25) pass_count <- pass_count + 1
if (median_pl >= 0.35 && median_pl <= 0.65) pass_count <- pass_count + 1
if (!is.na(cor_rock_hard) && cor_rock_hard > 0) pass_count <- pass_count + 1
if (pct_rock_high_mud < 5) pass_count <- pass_count + 1

if (pass_count >= 3) {
  cat("\n  [OK] Pipeline dbSEABED-compliant (", pass_count, "/4 criteres)\n")
} else {
  cat("\n  [WARN] Verifier calibration (", pass_count, "/4 criteres)\n")
}

## 17. Cleanup terra temp -------------------------------------------------------
tmpFiles(remove = TRUE)

cat("\nEtape 4 vNext+4 terminee avec succes: ", format(Sys.time()), "\n")
cat("Fichier de sortie: ", out_file, "\n")
cat("Taille: ", round(file.size(out_file) / 1e6, 1), " MB\n")
