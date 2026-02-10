#!/usr/bin/env Rscript
# ────────────────────────────────────────────────────────────────────────────────
# STEP-7  ─  BRIDGE STEP-6 CRI TO OCIM2-48L Jdredge FORCING
#
# Reads:  cri_final_*.parquet  (Step-6 output, EPSG:6933 1-km grid)
#         ocim_cache.mat       (portable OCIM grid cache from MATLAB)
# Writes: jdredge_ocim2_48l_YYYYMMDD_HHMMSS.mat  (Jdredge vector for co2model.m)
#
# Units chain:
#   Step-6 C_ri [gC m-2 yr-1] -> area-weighted binning -> OCIM 2-deg flux
#   -> inject into bottom cell -> umol C kg-1 yr-1
#
# Exports both Jdredge (primary) and Jtrawl (backward-compatible alias)
# plus amplified scenarios (10x, 100x) for sensitivity analysis.
# ────────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
  library(R.matlab)
})

cat("=== STEP 7: EXPORT Jdredge FOR OCIM2-48L ===\n")
cat("Start:", format(Sys.time()), "\n\n")

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

cat(sprintf("  OCIM grid: %d x %d x %d, m=%d ocean points\n", ni, nj, nk, m))

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

# ── Section 2: Map to OCIM (i,j) — area-weighted binning ─────────────────────

cat("\n--- Section 2: Area-weighted binning onto OCIM grid ---\n")

# OCIM lon/lat are cell centers; build edges
# lon2d[i, ] is constant across i (same lon for all latitudes in column j)
# lat2d[, j] is constant across j
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

# ── Section 3: Coastal mismatch — snap-to-nearest-wet ─────────────────────────

cat("\n--- Section 3: Coastal snap-to-nearest-wet ---\n")

# Check which mapped cells are ocean at surface
dt[, is_ocean := M3d[cbind(i_ocim, j_ocim, 1L)] == 1]

n_land <- sum(!dt$is_ocean)
n_total <- nrow(dt)
flux_on_land <- sum(dt$mass_gC_yr[!dt$is_ocean], na.rm = TRUE)
cat(sprintf("  Points on OCIM land: %d / %d (%.1f%%)\n", n_land, n_total, 100 * n_land / n_total))
cat(sprintf("  Flux on land: %.4e gC/yr (%.1f%% of total)\n", flux_on_land, 100 * flux_on_land / total_input_gC))

if (n_land > 0) {
  # Build ocean cell center lookup
  ocean_ij <- which(M3d[,,1] == 1, arr.ind = TRUE)  # ni x nj surface ocean
  ocean_lon <- lon2d[ocean_ij]
  ocean_lat <- lat2d[ocean_ij]

  land_idx <- which(!dt$is_ocean)
  land_lon <- dt$lon[land_idx]
  land_lat <- dt$lat[land_idx]

  # For each land point, find nearest ocean cell (brute-force on lon/lat; ok for ~thousands)
  cat("  Snapping", length(land_idx), "land points to nearest ocean cell...\n")
  for (k in seq_along(land_idx)) {
    dlat <- ocean_lat - land_lat[k]
    dlon <- ocean_lon - land_lon[k]
    # Approximate Euclidean on lon/lat (fine for nearest-neighbor at ~2 deg)
    dist2 <- dlon^2 + dlat^2
    best <- which.min(dist2)
    dt[land_idx[k], i_ocim := ocean_ij[best, 1]]
    dt[land_idx[k], j_ocim := ocean_ij[best, 2]]
  }
  dt[, is_ocean := TRUE]  # all now mapped to ocean
  cat("  Snap complete.\n")
}

# Aggregate mass per OCIM cell
agg_cols <- "mass_gC_yr"
if (has_lower) agg_cols <- c(agg_cols, "mass_lower")
if (has_upper) agg_cols <- c(agg_cols, "mass_upper")
if (has_cons)  agg_cols <- c(agg_cols, "mass_cons")

ocim_flux <- dt[, lapply(.SD, sum, na.rm = TRUE), by = .(i_ocim, j_ocim), .SDcols = agg_cols]
cat(sprintf("  Active OCIM cells: %d\n", nrow(ocim_flux)))

# Convert mass [gC/yr] to flux [gC m-2 yr-1] using OCIM cell area
# DXT3d and DYT3d are in meters; surface area = DXT * DYT at layer 1
ocim_flux[, ocim_area_m2 := DXT3d[cbind(i_ocim, j_ocim, 1L)] * DYT3d[cbind(i_ocim, j_ocim, 1L)]]
ocim_flux[, F_gC_m2_yr := mass_gC_yr / ocim_area_m2]
if (has_lower) ocim_flux[, F_lower := mass_lower / ocim_area_m2]
if (has_upper) ocim_flux[, F_upper := mass_upper / ocim_area_m2]
if (has_cons)  ocim_flux[, F_cons  := mass_cons  / ocim_area_m2]

# ── Section 4: Inject into bottom cell ────────────────────────────────────────

cat("\n--- Section 4: Inject into bottom cell ---\n")

# For each OCIM (i,j) with flux, convert to concentration tendency in bottom layer
# J_umol = F_gC * 1e6 / (M_C * RHO * DZT_bottom)  [umol kg-1 yr-1]

ocim_flux[, k_bottom := kbot[cbind(i_ocim, j_ocim)]]

# Remove any cells where kbot == 0 (shouldn't happen for ocean, but safety)
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

# ── Section 6: QA/QC ─────────────────────────────────────────────────────────

cat("\n--- Section 6: QA/QC ---\n")

# Conservation check
# Output total: sum over all ocean cells of Jdredge * VOL * rho * M_C / 1e6
# VOL_i = DXT3d * DYT3d * DZT3d at each ocean cell
# But we only filled bottom cells, so compute only for active cells:
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

# Spot check: top-10 cells
top10 <- ocim_flux[order(-J_umol)][1:min(10, nrow(ocim_flux))]
top10[, lon_center := lon2d[cbind(i_ocim, j_ocim)]]
top10[, lat_center := lat2d[cbind(i_ocim, j_ocim)]]
cat("\n  Top-10 Jdredge cells:\n")
cat(sprintf("  %4s %8s %8s %12s %8s\n", "rank", "lon", "lat", "J_umol", "DZT_bot"))
for (r in seq_len(nrow(top10))) {
  cat(sprintf("  %4d %8.2f %8.2f %12.4e %8.1f\n",
              r, top10$lon_center[r], top10$lat_center[r], top10$J_umol[r], top10$DZT_bot[r]))
}

# Depth distribution of active cells
cat("\n  Depth distribution of active bottom cells:\n")
depth_summary <- ocim_flux[, .(n_cells = .N, mean_J = mean(J_umol)),
                           by = .(depth_bin = cut(DZT_bot, breaks = c(0, 50, 200, 500, 2000, Inf)))]
print(depth_summary)

# Coastal redistribution fraction
cat(sprintf("\n  Coastal flux redistributed: %.4e gC/yr (%.2f%% of total)\n",
            flux_on_land, 100 * flux_on_land / total_input_gC))

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
  # Metadata
  n.cells.active      = n_active,
  total.flux.gC.yr    = total_input_gC,
  conservation.error.pct = conservation_error_pct,
  timestamp.str       = timestamp,
  m                   = m,
  coastal.flux.redistributed.pct = 100 * flux_on_land / total_input_gC
)

cat(sprintf("  Written: %s (%.1f MB)\n", mat_path, file.size(mat_path) / 1e6))

cat(sprintf("\nStep 7 complete: %s\n", format(Sys.time())))
cat("=== DONE ===\n")
