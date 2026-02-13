#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-7  ─  BRIDGE STEP-6 CRI TO OCIM2-48L Jdredge FORCING
#
# Reads:  cri_final_*.parquet  (Step-6 output, EPSG:6933 1-km grid)
#         ocim_cache.mat       (portable OCIM grid cache with spatial enrichment)
# Writes: jdredge_ocim2_48l_YYYYMMDD_HHMMSS.mat  (Jdredge vector for co2model.m)
#
# Units chain:
#   Step-6 C_ri [gC m-2 yr-1] -> FRACAREA-normalized binning -> OCIM 2-deg flux
#   -> shelf-anchored kNN redistribution -> bottom-cell injection -> umol C kg-1 yr-1
#
# Exports both Jdredge (primary) and Jtrawl (backward-compatible alias)
# plus amplified scenarios (10x, 100x) for sensitivity analysis.
#
# Implements:
#   M1: Ocean-fraction-aware normalization (FRACAREA)
#   M3: Shelf-anchored kNN redistribution with Gaussian distance weighting
#   M2: Mass-fix for double-precision residual
#   Anti-artifact locks (6 hard assertions before bottom-cell injection)
# ────────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
  library(R.matlab)
})

cat("=== STEP 7: EXPORT Jdredge FOR OCIM2-48L ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ── Redistribution parameters (saved to .mat metadata) ────────────────────────
R_KM        <- 200    # search radius [km]
LAMBDA_KM   <- 100    # Gaussian kernel scale [km]
K_MAX       <- 16L    # max neighbors
ALPHA       <- 1      # ocean-fraction exponent
OCEANFRAC_FLOOR <- 0.05  # cells below this are "effectively land"

# ── Anti-artifact lock thresholds ─────────────────────────────────────────────
LOCK1_MASS_TOL       <- 1e-6    # max relative mass conservation error
LOCK3_SHELF_FLOOR    <- 0.50    # min fraction of flux on shelf
LOCK4_HOTSPOT_CAP    <- 0.10    # max fraction in single cell
LOCK5_MEAN_DIST_CAP  <- 300     # max mean redistribution distance [km]
LOCK6_DENSITY_RATIO  <- 1e4     # max/median density ratio
OFFSHORE_DELTA_KM    <- 50      # threshold for "offshore displacement"

# ── Section 0: Preflight ─────────────────────────────────────────────────────

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
if (length(script_dir) == 0 || script_dir == "") script_dir <- "~/ais-pipeline/pipeline_V6"
source(file.path(script_dir, "constants.R"))

OUT_DIR   <- path.expand(Sys.getenv("OUT_DIR", "~/scratch/output_V6"))
OCIM_DIR  <- path.expand(Sys.getenv("OCIM_DIR", "~/scratch/configuration/ocim"))

# Physical constants
M_C  <- 12.011   # molar mass of carbon [g/mol]
RHO  <- 1025     # seawater density [kg/m3]

# --- Load Step-6 CRI ---
cri_files <- list.files(OUT_DIR, pattern = "^cri_final_.*\\.parquet$", full.names = TRUE)
if (length(cri_files) == 0) stop("No cri_final_*.parquet found in ", OUT_DIR)
cri_path <- cri_files[which.max(file.info(cri_files)$mtime)]
cat("Step-6 file:", basename(cri_path), "\n")

dt <- as.data.table(arrow::read_parquet(cri_path))

# Validate required columns
req_cols <- c("grid_id", "x", "y", "C_ri")
missing <- setdiff(req_cols, names(dt))
if (length(missing) > 0) stop("Missing columns: ", paste(missing, collapse = ", "))

stopifnot(all(dt$C_ri >= 0))
stopifnot(!any(duplicated(dt$grid_id)))
cat("  rows:", nrow(dt), " C_ri range: [", min(dt$C_ri), ",", max(dt$C_ri), "] gC/m2/yr\n")

# --- Load OCIM cache ---
ocim_cache_path <- file.path(OCIM_DIR, "ocim_cache.mat")
if (!file.exists(ocim_cache_path)) stop("ocim_cache.mat not found at ", ocim_cache_path)

cat("Loading OCIM cache:", ocim_cache_path, "\n")
ocim <- R.matlab::readMat(ocim_cache_path)

lon2d <- ocim$lon2d   # ni x nj
lat2d <- ocim$lat2d
M3d   <- ocim$M3d     # ni x nj x nk
DZT3d <- ocim$DZT3d
DXT3d <- ocim$DXT3d
DYT3d <- ocim$DYT3d
iocn  <- as.integer(ocim$iocn)  # m x 1
kbot  <- ocim$kbot    # ni x nj
ni    <- as.integer(ocim$ni)
nj    <- as.integer(ocim$nj)
nk    <- as.integer(ocim$nk)
m     <- length(iocn)

# New enrichment fields
depth2d          <- ocim$depth2d
oceanfrac2d      <- ocim$oceanfrac2d
shelf.mask2d     <- ocim$shelf.mask2d
dist.to.coast2d  <- ocim$dist.to.coast2d
shelf.component2d <- ocim$shelf.component2d
seed.shelf.i     <- ocim$seed.shelf.i
seed.shelf.j     <- ocim$seed.shelf.j

cat(sprintf("  OCIM grid: %d x %d x %d, m=%d ocean points\n", ni, nj, nk, m))
cat(sprintf("  Enrichment fields: depth2d, oceanfrac2d, shelf_mask2d, dist_to_coast2d,\n"))
cat(sprintf("    shelf_component2d, seed_shelf_ij loaded\n"))

# ── Haversine helper (vectorized) ─────────────────────────────────────────────
haversine_km <- function(lon1, lat1, lon2, lat2) {
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  2 * 6371 * asin(pmin(sqrt(a), 1))
}

# ── Section 1: Reproject EPSG:6933 -> WGS84 (lon/lat) ────────────────────────

cat("\n--- Section 1: Reproject to WGS84 ---\n")

pts_sf <- sf::st_as_sf(dt, coords = c("x", "y"), crs = 6933)
pts_wgs <- sf::st_transform(pts_sf, 4326)
coords_wgs <- sf::st_coordinates(pts_wgs)

dt[, lon := coords_wgs[, 1]]
dt[, lat := coords_wgs[, 2]]

cat(sprintf("  lon range: [%.2f, %.2f]  lat range: [%.2f, %.2f]\n",
            min(dt$lon), max(dt$lon), min(dt$lat), max(dt$lat)))

rm(pts_sf, pts_wgs, coords_wgs)

# ── Section 2: Map to OCIM (i,j) — FRACAREA-normalized binning (M1) ──────────

cat("\n--- Section 2: FRACAREA-normalized binning onto OCIM grid ---\n")

# OCIM lon/lat are cell centers; build edges
ocim_lon <- lon2d[1, ]  # nj values
ocim_lat <- lat2d[, 1]  # ni values

# Sort to ensure monotonic
lon_order <- order(ocim_lon)
lat_order <- order(ocim_lat)
ocim_lon_sorted <- ocim_lon[lon_order]
ocim_lat_sorted <- ocim_lat[lat_order]

# Build edges (midpoints between centers, extend at boundaries)
lon_edges <- c(ocim_lon_sorted[1] - diff(ocim_lon_sorted[1:2]) / 2,
               (ocim_lon_sorted[-length(ocim_lon_sorted)] + ocim_lon_sorted[-1]) / 2,
               ocim_lon_sorted[length(ocim_lon_sorted)] + diff(ocim_lon_sorted[(length(ocim_lon_sorted)-1):length(ocim_lon_sorted)]) / 2)

lat_edges <- c(ocim_lat_sorted[1] - diff(ocim_lat_sorted[1:2]) / 2,
               (ocim_lat_sorted[-length(ocim_lat_sorted)] + ocim_lat_sorted[-1]) / 2,
               ocim_lat_sorted[length(ocim_lat_sorted)] + diff(ocim_lat_sorted[(length(ocim_lat_sorted)-1):length(ocim_lat_sorted)]) / 2)

# Clamp edges
lon_edges <- pmax(pmin(lon_edges, 180), -180)
lat_edges <- pmax(pmin(lat_edges, 90), -90)

# Map each Step-6 point to sorted OCIM indices
dt[, j_sorted := findInterval(lon, lon_edges, rightmost.closed = TRUE)]
dt[, i_sorted := findInterval(lat, lat_edges, rightmost.closed = TRUE)]

# Clamp to valid range
dt[, j_sorted := pmin(pmax(j_sorted, 1L), nj)]
dt[, i_sorted := pmin(pmax(i_sorted, 1L), ni)]

# Map back from sorted indices to original OCIM indices
dt[, j_ocim := lon_order[j_sorted]]
dt[, i_ocim := lat_order[i_sorted]]

# Mass per 1-km cell [gC/yr]
dt[, mass_gC_yr := C_ri * CELL_AREA_M2]

# Uncertainty bounds
has_lower <- "C_ri_lower" %in% names(dt)
has_upper <- "C_ri_upper" %in% names(dt)
has_cons  <- "C_ri_conservative" %in% names(dt)
if (has_lower) dt[, mass_lower := C_ri_lower * CELL_AREA_M2]
if (has_upper) dt[, mass_upper := C_ri_upper * CELL_AREA_M2]
if (has_cons)  dt[, mass_cons  := C_ri_conservative * CELL_AREA_M2]

total_input_gC <- sum(dt$mass_gC_yr, na.rm = TRUE)
cat(sprintf("  Total input mass: %.4e gC/yr\n", total_input_gC))

# Aggregate mass per OCIM cell
agg_cols <- "mass_gC_yr"
if (has_lower) agg_cols <- c(agg_cols, "mass_lower")
if (has_upper) agg_cols <- c(agg_cols, "mass_upper")
if (has_cons)  agg_cols <- c(agg_cols, "mass_cons")

ocim_flux <- dt[, lapply(.SD, sum, na.rm = TRUE), by = .(i_ocim, j_ocim), .SDcols = agg_cols]
cat(sprintf("  Active OCIM cells after binning: %d\n", nrow(ocim_flux)))

# OCIM cell area
ocim_flux[, ocim_area_m2 := DXT3d[cbind(i_ocim, j_ocim, 1L)] * DYT3d[cbind(i_ocim, j_ocim, 1L)]]

# Ocean fraction from cache
ocim_flux[, oceanfrac := oceanfrac2d[cbind(i_ocim, j_ocim)]]

# Authoritative ocean mask: kbot > 0
ocim_flux[, is_ocean := kbot[cbind(i_ocim, j_ocim)] > 0]

# Cells with oceanfrac < OCEANFRAC_FLOOR are "effectively land" -> will be redistributed
ocim_flux[, effectively_land := (!is_ocean) | (oceanfrac < OCEANFRAC_FLOOR)]

# FRACAREA normalization (only for ocean cells that are NOT effectively land)
ocim_flux[effectively_land == FALSE,
          F_gC_m2_yr := mass_gC_yr / (ocim_area_m2 * oceanfrac)]

n_eff_land <- sum(ocim_flux$effectively_land)
flux_eff_land <- sum(ocim_flux$mass_gC_yr[ocim_flux$effectively_land], na.rm = TRUE)
cat(sprintf("  Effectively-land cells: %d (flux: %.4e gC/yr, %.1f%% of total)\n",
            n_eff_land, flux_eff_land, 100 * flux_eff_land / total_input_gC))

# ── Section 3: Shelf-anchored kNN redistribution (M3) ────────────────────────

cat("\n--- Section 3: Shelf-anchored kNN redistribution ---\n")
cat(sprintf("  Parameters: R_km=%d, lambda_km=%d, k_max=%d, alpha=%d\n",
            R_KM, LAMBDA_KM, K_MAX, ALPHA))

# Identify pools
land_pool_mask  <- ocim_flux$effectively_land
ocean_pool_mask <- !land_pool_mask

n_land_pool <- sum(land_pool_mask)
cat(sprintf("  Land pool: %d cells, Ocean pool: %d cells\n",
            n_land_pool, sum(ocean_pool_mask)))

# Redistribution counters
n_relax_component <- 0L
n_relax_shelf     <- 0L
n_fallback_nearest <- 0L
n_cross_basin     <- 0L  # for Lock 2
redist_distances  <- numeric(0)  # for Lock 5 + metrics

if (n_land_pool > 0) {
  # Pre-build ocean-pool lookup tables
  ocean_idx  <- which(ocean_pool_mask)
  ocean_i    <- ocim_flux$i_ocim[ocean_idx]
  ocean_j    <- ocim_flux$j_ocim[ocean_idx]
  ocean_lon  <- lon2d[cbind(ocean_i, ocean_j)]
  ocean_lat  <- lat2d[cbind(ocean_i, ocean_j)]
  ocean_shelf <- as.logical(shelf.mask2d[cbind(ocean_i, ocean_j)])
  ocean_comp  <- shelf.component2d[cbind(ocean_i, ocean_j)]
  ocean_ofrac <- oceanfrac2d[cbind(ocean_i, ocean_j)]
  ocean_dist_coast <- dist.to.coast2d[cbind(ocean_i, ocean_j)]

  # Accumulator for mass added to ocean cells
  added_mass <- rep(0, length(ocean_idx))
  if (has_lower) added_mass_lower <- rep(0, length(ocean_idx))
  if (has_upper) added_mass_upper <- rep(0, length(ocean_idx))
  if (has_cons)  added_mass_cons  <- rep(0, length(ocean_idx))

  land_indices <- which(land_pool_mask)
  cat(sprintf("  Redistributing %d land-pool cells ...\n", length(land_indices)))

  for (k in seq_along(land_indices)) {
    li <- land_indices[k]
    d0_i <- ocim_flux$i_ocim[li]
    d0_j <- ocim_flux$j_ocim[li]
    d0_lon <- lon2d[d0_i, d0_j]
    d0_lat <- lat2d[d0_i, d0_j]
    d0_mass <- ocim_flux$mass_gC_yr[li]

    if (d0_mass == 0) next

    # Get coastal seed for this land cell
    seed_i <- as.integer(seed.shelf.i[d0_i, d0_j])
    seed_j <- as.integer(seed.shelf.j[d0_i, d0_j])

    # Component of this land cell via its seed
    target_comp <- 0
    if (seed_i > 0 && seed_j > 0) {
      target_comp <- shelf.component2d[seed_i, seed_j]
    }

    # Compute distances from d0 to all ocean-pool cells
    dists <- haversine_km(d0_lon, d0_lat, ocean_lon, ocean_lat)

    # Stage 1: same shelf component within R_km
    cand <- which(ocean_shelf & (ocean_comp == target_comp) & (dists <= R_KM))

    # Stage 2: relax component -> all shelf within R_km
    if (length(cand) == 0) {
      cand <- which(ocean_shelf & (dists <= R_KM))
      if (length(cand) > 0) n_relax_component <- n_relax_component + 1L
    }

    # Stage 3: relax shelf -> all ocean within 2*R_km
    if (length(cand) == 0) {
      cand <- which(dists <= 2 * R_KM)
      if (length(cand) > 0) n_relax_shelf <- n_relax_shelf + 1L
    }

    # Stage 4: fallback to single nearest ocean cell
    if (length(cand) == 0) {
      cand <- which.min(dists)
      n_fallback_nearest <- n_fallback_nearest + 1L
    }

    # Gaussian distance weighting * ocean-fraction
    w <- (pmax(ocean_ofrac[cand], 0.01)^ALPHA) *
         exp(-(dists[cand] / LAMBDA_KM)^2)

    # Take top k_max by weight
    if (length(cand) > K_MAX) {
      top_k <- order(w, decreasing = TRUE)[1:K_MAX]
      cand <- cand[top_k]
      w <- w[top_k]
    }

    # Normalize
    w <- w / sum(w)

    # Check for cross-basin transfer (Lock 2 prep)
    if (target_comp > 0) {
      recipient_comps <- ocean_comp[cand]
      if (any(recipient_comps > 0 & recipient_comps != target_comp & dists[cand] > 2 * R_KM)) {
        n_cross_basin <- n_cross_basin + 1L
      }
    }

    # Track redistribution distances (flux-weighted)
    redist_distances <- c(redist_distances, sum(w * dists[cand]))

    # Distribute mass
    added_mass[cand] <- added_mass[cand] + w * d0_mass
    if (has_lower) added_mass_lower[cand] <- added_mass_lower[cand] + w * ocim_flux$mass_lower[li]
    if (has_upper) added_mass_upper[cand] <- added_mass_upper[cand] + w * ocim_flux$mass_upper[li]
    if (has_cons)  added_mass_cons[cand]  <- added_mass_cons[cand]  + w * ocim_flux$mass_cons[li]

    if (k %% 500 == 0) cat(sprintf("    %d / %d land cells processed\n", k, length(land_indices)))
  }

  # Apply redistributed mass to ocean pool
  ocim_flux[ocean_idx, mass_gC_yr := mass_gC_yr + added_mass]
  if (has_lower) ocim_flux[ocean_idx, mass_lower := mass_lower + added_mass_lower]
  if (has_upper) ocim_flux[ocean_idx, mass_upper := mass_upper + added_mass_upper]
  if (has_cons)  ocim_flux[ocean_idx, mass_cons  := mass_cons  + added_mass_cons]

  # Remove land-pool cells from flux table
  ocim_flux <- ocim_flux[!land_pool_mask]

  # Recompute FRACAREA-normalized flux for ocean cells that received mass
  ocim_flux[, F_gC_m2_yr := mass_gC_yr / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  if (has_lower) ocim_flux[, F_lower := mass_lower / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  if (has_upper) ocim_flux[, F_upper := mass_upper / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  if (has_cons)  ocim_flux[, F_cons  := mass_cons  / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]

  cat(sprintf("  Redistribution complete.\n"))
  cat(sprintf("  n_relax_component: %d\n", n_relax_component))
  cat(sprintf("  n_relax_shelf:     %d\n", n_relax_shelf))
  cat(sprintf("  n_fallback_nearest: %d\n", n_fallback_nearest))
  cat(sprintf("  n_cross_basin:     %d\n", n_cross_basin))
  if (length(redist_distances) > 0) {
    mean_redist_km <- mean(redist_distances)
    cat(sprintf("  Mean redistribution distance: %.1f km\n", mean_redist_km))
  } else {
    mean_redist_km <- 0
  }

} else {
  cat("  No land-pool cells — skipping redistribution.\n")
  # Still need FRACAREA normalization for uncertainty bounds
  if (has_lower) ocim_flux[, F_lower := mass_lower / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  if (has_upper) ocim_flux[, F_upper := mass_upper / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  if (has_cons)  ocim_flux[, F_cons  := mass_cons  / (ocim_area_m2 * pmax(oceanfrac, OCEANFRAC_FLOOR))]
  mean_redist_km <- 0
}

cat(sprintf("  Active OCIM cells after redistribution: %d\n", nrow(ocim_flux)))

# ── Mass-fix (M2): correct double-precision residual ──────────────────────────

cat("\n--- Mass-fix (M2) ---\n")
sum_after <- sum(ocim_flux$mass_gC_yr, na.rm = TRUE)
residual_gC <- total_input_gC - sum_after
cat(sprintf("  Residual before fix: %.4e gC/yr (%.2e relative)\n",
            residual_gC, abs(residual_gC) / total_input_gC))

if (sum_after > 0) {
  scale_factor <- total_input_gC / sum_after
  ocim_flux[, mass_gC_yr := mass_gC_yr * scale_factor]
  ocim_flux[, F_gC_m2_yr := F_gC_m2_yr * scale_factor]
  if (has_lower) { ocim_flux[, mass_lower := mass_lower * scale_factor]; ocim_flux[, F_lower := F_lower * scale_factor] }
  if (has_upper) { ocim_flux[, mass_upper := mass_upper * scale_factor]; ocim_flux[, F_upper := F_upper * scale_factor] }
  if (has_cons)  { ocim_flux[, mass_cons  := mass_cons  * scale_factor]; ocim_flux[, F_cons  := F_cons  * scale_factor] }
}

sum_after_fix <- sum(ocim_flux$mass_gC_yr, na.rm = TRUE)
cat(sprintf("  After fix: relative error = %.2e\n", abs(1 - sum_after_fix / total_input_gC)))

# ── Anti-artifact locks (Step G) ──────────────────────────────────────────────

cat("\n--- Anti-artifact locks ---\n")

# Lock 1: Mass conservation
lock1_err <- abs(1 - sum(ocim_flux$mass_gC_yr, na.rm = TRUE) / total_input_gC)
cat(sprintf("  LOCK1 mass conservation: %.2e (threshold: %.2e) %s\n",
            lock1_err, LOCK1_MASS_TOL, if (lock1_err <= LOCK1_MASS_TOL) "PASS" else "FAIL"))
if (lock1_err > LOCK1_MASS_TOL) stop(sprintf("LOCK1 FAIL: mass conservation error %.2e > %.2e", lock1_err, LOCK1_MASS_TOL))

# Lock 2: No cross-basin transfer
cat(sprintf("  LOCK2 cross-basin transfers: %d %s\n",
            n_cross_basin, if (n_cross_basin == 0) "PASS" else "FAIL"))
if (n_cross_basin > 0) stop(sprintf("LOCK2 FAIL: %d cross-basin transfers detected", n_cross_basin))

# Lock 3: Shelf fraction floor
ocim_flux[, on_shelf := as.logical(shelf.mask2d[cbind(i_ocim, j_ocim)])]
shelf_frac <- sum(ocim_flux$mass_gC_yr[ocim_flux$on_shelf], na.rm = TRUE) / sum(ocim_flux$mass_gC_yr, na.rm = TRUE)
cat(sprintf("  LOCK3 shelf fraction: %.1f%% (threshold: %.0f%%) %s\n",
            100 * shelf_frac, 100 * LOCK3_SHELF_FLOOR, if (shelf_frac >= LOCK3_SHELF_FLOOR) "PASS" else "FAIL"))
if (shelf_frac < LOCK3_SHELF_FLOOR) stop(sprintf("LOCK3 FAIL: shelf fraction %.1f%% < %.0f%%", 100 * shelf_frac, 100 * LOCK3_SHELF_FLOOR))

# Lock 4: Hotspot cap
max_share <- max(ocim_flux$mass_gC_yr, na.rm = TRUE) / sum(ocim_flux$mass_gC_yr, na.rm = TRUE)
cat(sprintf("  LOCK4 max cell share: %.2f%% (threshold: %.0f%%) %s\n",
            100 * max_share, 100 * LOCK4_HOTSPOT_CAP, if (max_share <= LOCK4_HOTSPOT_CAP) "PASS" else "FAIL"))
if (max_share > LOCK4_HOTSPOT_CAP) stop(sprintf("LOCK4 FAIL: single cell holds %.1f%% of total flux", 100 * max_share))

# Lock 5: Mean redistribution distance cap
cat(sprintf("  LOCK5 mean redist distance: %.0f km (threshold: %d km) %s\n",
            mean_redist_km, LOCK5_MEAN_DIST_CAP, if (mean_redist_km <= LOCK5_MEAN_DIST_CAP) "PASS" else "FAIL"))
if (mean_redist_km > LOCK5_MEAN_DIST_CAP) stop(sprintf("LOCK5 FAIL: mean redistribution distance %.0f km > %d km", mean_redist_km, LOCK5_MEAN_DIST_CAP))

# Lock 6: Ocean-fraction density cap
positive_flux <- ocim_flux$F_gC_m2_yr[ocim_flux$F_gC_m2_yr > 0]
if (length(positive_flux) > 1) {
  max_density_ratio <- max(positive_flux) / median(positive_flux)
} else {
  max_density_ratio <- 1
}
cat(sprintf("  LOCK6 max/median density ratio: %.0f (threshold: %.0f) %s\n",
            max_density_ratio, LOCK6_DENSITY_RATIO,
            if (max_density_ratio <= LOCK6_DENSITY_RATIO) "PASS" else "FAIL"))
if (max_density_ratio > LOCK6_DENSITY_RATIO) stop(sprintf("LOCK6 FAIL: max/median density ratio %.0f > %.0f", max_density_ratio, LOCK6_DENSITY_RATIO))

cat("  All locks PASSED.\n")

# ── Section 4: Inject into bottom cell ────────────────────────────────────────

cat("\n--- Section 4: Inject into bottom cell ---\n")

# For each OCIM (i,j) with flux, convert to concentration tendency in bottom layer
# J_umol = F_gC * 1e6 / (M_C * RHO * DZT_bottom)  [umol kg-1 yr-1]

ocim_flux[, k_bottom := kbot[cbind(i_ocim, j_ocim)]]

# Remove any cells where kbot == 0 (shouldn't happen after redistribution, but safety)
bad_kbot <- ocim_flux[k_bottom == 0]
if (nrow(bad_kbot) > 0) {
  cat(sprintf("  WARNING: %d cells with kbot=0 (dropping)\n", nrow(bad_kbot)))
  ocim_flux <- ocim_flux[k_bottom > 0]
}

ocim_flux[, DZT_bot := DZT3d[cbind(i_ocim, j_ocim, k_bottom)]]
ocim_flux[, J_umol := F_gC_m2_yr * 1e6 / (M_C * RHO * DZT_bot)]
if (has_lower) ocim_flux[, J_lower := F_lower * 1e6 / (M_C * RHO * DZT_bot)]
if (has_upper) ocim_flux[, J_upper := F_upper * 1e6 / (M_C * RHO * DZT_bot)]
if (has_cons)  ocim_flux[, J_cons  := F_cons  * 1e6 / (M_C * RHO * DZT_bot)]

cat(sprintf("  Bottom cell depths: min=%.0f m, median=%.0f m, max=%.0f m\n",
            min(ocim_flux$DZT_bot), median(ocim_flux$DZT_bot), max(ocim_flux$DZT_bot)))

# Compute linear index into M3d for each (i,j,kbot)
# MATLAB uses column-major: idx = i + (j-1)*ni + (k-1)*ni*nj
ocim_flux[, linear_idx := i_ocim + (j_ocim - 1L) * ni + (k_bottom - 1L) * ni * nj]

# Map linear index to iocn position (vector index in Jdredge)
iocn_map <- data.table(linear_idx = iocn, vec_pos = seq_along(iocn))
ocim_flux <- merge(ocim_flux, iocn_map, by = "linear_idx", all.x = TRUE)

unmatched <- sum(is.na(ocim_flux$vec_pos))
if (unmatched > 0) {
  cat(sprintf("  WARNING: %d bottom cells not in iocn (dropping)\n", unmatched))
  ocim_flux <- ocim_flux[!is.na(vec_pos)]
}

# ── Section 5: Build Jdredge vector ──────────────────────────────────────────

cat("\n--- Section 5: Build Jdredge vector ---\n")

Jdredge <- rep(0, m)
Jdredge[ocim_flux$vec_pos] <- ocim_flux$J_umol

Jdredge_lower <- rep(0, m)
Jdredge_upper <- rep(0, m)
Jdredge_conservative <- rep(0, m)

if (has_lower) Jdredge_lower[ocim_flux$vec_pos] <- ocim_flux$J_lower
if (has_upper) Jdredge_upper[ocim_flux$vec_pos] <- ocim_flux$J_upper
if (has_cons)  Jdredge_conservative[ocim_flux$vec_pos] <- ocim_flux$J_cons

n_active <- sum(Jdredge > 0)
cat(sprintf("  Jdredge length: %d (m)\n", m))
cat(sprintf("  Active cells: %d\n", n_active))
cat(sprintf("  Jdredge > 0 summary:\n"))
print(summary(Jdredge[Jdredge > 0]))

# ── Section 5b: Amplified scenarios for sensitivity analysis ─────────────────

cat("\n--- Section 5b: Amplified scenarios (10x, 100x) ---\n")

Jdredge_10x  <- Jdredge * 10
Jdredge_100x <- Jdredge * 100

Jdredge_lower_10x  <- Jdredge_lower * 10
Jdredge_lower_100x <- Jdredge_lower * 100
Jdredge_upper_10x  <- Jdredge_upper * 10
Jdredge_upper_100x <- Jdredge_upper * 100
Jdredge_conservative_10x  <- Jdredge_conservative * 10
Jdredge_conservative_100x <- Jdredge_conservative * 100

cat(sprintf("  Jdredge_10x  max: %.4e umol/kg/yr\n", max(Jdredge_10x)))
cat(sprintf("  Jdredge_100x max: %.4e umol/kg/yr\n", max(Jdredge_100x)))

# ── Section 6: QA/QC — Split metrics + enhanced diagnostics ──────────────────

cat("\n--- Section 6: QA/QC ---\n")

# Conservation check (round-trip: J_umol * VOL * rho * M_C / 1e6 -> gC/yr)
VOL_active  <- DXT3d[cbind(ocim_flux$i_ocim, ocim_flux$j_ocim, ocim_flux$k_bottom)] *
               DYT3d[cbind(ocim_flux$i_ocim, ocim_flux$j_ocim, ocim_flux$k_bottom)] *
               ocim_flux$DZT_bot

total_output_gC <- sum(ocim_flux$J_umol * VOL_active * RHO * M_C / 1e6, na.rm = TRUE)

conservation_error_pct <- abs(total_input_gC - total_output_gC) / total_input_gC * 100
cat(sprintf("  Input  total: %.6e gC/yr\n", total_input_gC))
cat(sprintf("  Output total: %.6e gC/yr\n", total_output_gC))
cat(sprintf("  Conservation error: %.4f%%\n", conservation_error_pct))

if (conservation_error_pct > 1) {
  cat("  WARNING: Conservation error exceeds 1%!\n")
} else {
  cat("  OK: Conservation within 1% tolerance.\n")
}

# --- Split metrics ---

# 1. land_pool_pct: fraction of input mass that was on OCIM land
land_pool_pct <- 100 * flux_eff_land / total_input_gC
cat(sprintf("\n  land_pool_pct: %.2f%%\n", land_pool_pct))

# 2. offshore_displacement_pct: fraction of redistributed mass displaced >50 km offshore
# For each redistributed cell, check distance shift vs seed baseline
offshore_displacement_pct <- 0
if (n_land_pool > 0 && length(redist_distances) > 0) {
  # Approximate: use mean redistribution distance as proxy
  # Detailed tracking would require per-transfer baseline, which is complex in R
  # We use a simpler approach: check recipient cells' dist_to_coast vs overall pattern
  ocim_flux[, dist_coast := dist.to.coast2d[cbind(i_ocim, j_ocim)]]

  # Recipients that are far from coast (>50km further than median shelf dist)
  shelf_median_dist <- median(dist.to.coast2d[shelf.mask2d > 0], na.rm = TRUE)
  offshore_mask <- ocim_flux$dist_coast > (shelf_median_dist + OFFSHORE_DELTA_KM)
  offshore_flux <- sum(ocim_flux$mass_gC_yr[offshore_mask], na.rm = TRUE)
  offshore_displacement_pct <- 100 * offshore_flux / total_input_gC
  cat(sprintf("  offshore_displacement_pct: %.2f%%\n", offshore_displacement_pct))
} else {
  cat("  offshore_displacement_pct: 0.00% (no redistribution)\n")
}

# 3. shelf_flux_pct
shelf_flux_pct <- 100 * shelf_frac
cat(sprintf("  shelf_flux_pct: %.2f%%\n", shelf_flux_pct))

# 4. max_cell_share_pct
max_cell_share_pct <- 100 * max_share
cat(sprintf("  max_cell_share_pct: %.2f%%\n", max_cell_share_pct))

# 5. top1pct_flux_share
n_top1pct <- max(1L, as.integer(ceiling(nrow(ocim_flux) * 0.01)))
top1pct_mass <- sum(sort(ocim_flux$mass_gC_yr, decreasing = TRUE)[1:n_top1pct])
top1pct_flux_share <- 100 * top1pct_mass / total_input_gC
cat(sprintf("  top1pct_flux_share: %.2f%%\n", top1pct_flux_share))

# 6. delta_median_dist_coast_km & delta_p90
ocim_flux[, dist_coast := dist.to.coast2d[cbind(i_ocim, j_ocim)]]
if (nrow(ocim_flux) > 0) {
  # Flux-weighted quantiles
  ord <- order(ocim_flux$dist_coast)
  cum_flux <- cumsum(ocim_flux$mass_gC_yr[ord]) / sum(ocim_flux$mass_gC_yr)
  delta_median_dist_coast_km <- ocim_flux$dist_coast[ord[which.min(abs(cum_flux - 0.5))]]
  delta_p90_dist_coast_km    <- ocim_flux$dist_coast[ord[which.min(abs(cum_flux - 0.9))]]
} else {
  delta_median_dist_coast_km <- 0
  delta_p90_dist_coast_km    <- 0
}
cat(sprintf("  delta_median_dist_coast_km: %.1f\n", delta_median_dist_coast_km))
cat(sprintf("  delta_p90_dist_coast_km: %.1f\n", delta_p90_dist_coast_km))

# Spot check: top-10 cells with enhanced columns
top10 <- ocim_flux[order(-J_umol)][1:min(10, nrow(ocim_flux))]
top10[, lon_center := lon2d[cbind(i_ocim, j_ocim)]]
top10[, lat_center := lat2d[cbind(i_ocim, j_ocim)]]
top10[, of := oceanfrac2d[cbind(i_ocim, j_ocim)]]
top10[, d2c := dist.to.coast2d[cbind(i_ocim, j_ocim)]]
cat("\n  Top-10 Jdredge cells:\n")
cat(sprintf("  %4s %8s %8s %12s %8s %8s %8s\n", "rank", "lon", "lat", "J_umol", "DZT_bot", "oceanfr", "d2coast"))
for (r in seq_len(nrow(top10))) {
  cat(sprintf("  %4d %8.2f %8.2f %12.4e %8.1f %8.3f %8.1f\n",
              r, top10$lon_center[r], top10$lat_center[r], top10$J_umol[r],
              top10$DZT_bot[r], top10$of[r], top10$d2c[r]))
}

# Depth distribution of active cells
cat("\n  Depth distribution of active bottom cells:\n")
depth_summary <- ocim_flux[, .(n_cells = .N, mean_J = mean(J_umol)),
                           by = .(depth_bin = cut(DZT_bot, breaks = c(0, 50, 200, 500, 2000, Inf)))]
print(depth_summary)

# ── Section 7: Export .mat ────────────────────────────────────────────────────

cat("\n--- Section 7: Export .mat ---\n")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
mat_filename <- sprintf("jdredge_ocim2_48l_%s.mat", timestamp)
mat_path <- file.path(OUT_DIR, mat_filename)

R.matlab::writeMat(
  mat_path,
  # Primary dredging forcing
  Jdredge              = matrix(Jdredge, ncol = 1),
  Jdredge.lower        = matrix(Jdredge_lower, ncol = 1),
  Jdredge.upper        = matrix(Jdredge_upper, ncol = 1),
  Jdredge.conservative = matrix(Jdredge_conservative, ncol = 1),
  # Amplified scenarios
  Jdredge.10x          = matrix(Jdredge_10x, ncol = 1),
  Jdredge.100x         = matrix(Jdredge_100x, ncol = 1),
  Jdredge.lower.10x    = matrix(Jdredge_lower_10x, ncol = 1),
  Jdredge.lower.100x   = matrix(Jdredge_lower_100x, ncol = 1),
  Jdredge.upper.10x    = matrix(Jdredge_upper_10x, ncol = 1),
  Jdredge.upper.100x   = matrix(Jdredge_upper_100x, ncol = 1),
  Jdredge.conservative.10x  = matrix(Jdredge_conservative_10x, ncol = 1),
  Jdredge.conservative.100x = matrix(Jdredge_conservative_100x, ncol = 1),
  # Backward-compatible aliases for co2model.m
  Jtrawl               = matrix(Jdredge, ncol = 1),
  Jtrawl.lower         = matrix(Jdredge_lower, ncol = 1),
  Jtrawl.upper         = matrix(Jdredge_upper, ncol = 1),
  Jtrawl.conservative  = matrix(Jdredge_conservative, ncol = 1),
  Jtrawl.10x           = matrix(Jdredge_10x, ncol = 1),
  Jtrawl.100x          = matrix(Jdredge_100x, ncol = 1),
  # Metadata — core
  n.cells.active      = n_active,
  total.flux.gC.yr    = total_input_gC,
  conservation.error.pct = conservation_error_pct,
  timestamp.str       = timestamp,
  m                   = m,
  # Metadata — split metrics (replaces old coastal.flux.redistributed.pct)
  land.pool.pct                = land_pool_pct,
  offshore.displacement.pct    = offshore_displacement_pct,
  shelf.flux.pct               = shelf_flux_pct,
  max.cell.share.pct           = max_cell_share_pct,
  top1pct.flux.share           = top1pct_flux_share,
  delta.median.dist.coast.km   = delta_median_dist_coast_km,
  delta.p90.dist.coast.km      = delta_p90_dist_coast_km,
  # Metadata — redistribution parameters
  redistribution.R.km          = R_KM,
  redistribution.lambda.km     = LAMBDA_KM,
  redistribution.k.max         = K_MAX,
  redistribution.alpha         = ALPHA,
  redistribution.oceanfrac.floor = OCEANFRAC_FLOOR,
  # Metadata — redistribution quality counters
  n.relax.component            = n_relax_component,
  n.relax.shelf                = n_relax_shelf,
  n.fallback.nearest           = n_fallback_nearest,
  mean.redist.km               = mean_redist_km
)

cat(sprintf("  Written: %s (%.1f MB)\n", mat_path, file.size(mat_path) / 1e6))

cat(sprintf("\nStep 7 complete: %s\n", format(Sys.time())))
cat("=== DONE ===\n")
