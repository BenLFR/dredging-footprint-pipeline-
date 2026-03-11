#!/usr/bin/env Rscript
# ============================================================================
# compare_scenarios.R
# Loads three fi_grid parquet files (default / conservative / upper_bound
# scenarios from fi_parameters_with_freshness.yaml), computes per-cell % differences, and
# frames the three scenarios as parameter uncertainty bounds.
#
# Outputs:
#   output_V6/scenario_comparison_map.png     — viridis map of % spread
#   output_V6/scenario_comparison_totals.csv  — global totals per scenario
#
# Usage:
#   Rscript analysis/compare_scenarios.R
#
# Notes:
#   - Expects files matching fi_grid_*_default.parquet (or fi_grid_default_*,
#     etc.) in OUTPUT_DIR (default: output_V6/). Pattern detection is flexible.
#   - Uses only grid coords + f_i_full + C_ri columns to minimise memory.
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(sf)
})

if (!requireNamespace("arrow", quietly = TRUE))
  stop("Package 'arrow' required: install.packages('arrow')")
library(arrow)

get_env_path <- function(var, default) {
  value <- Sys.getenv(var, unset = "")
  if (nzchar(value)) value else default
}

output_root <- get_env_path("OUTPUT_DIR", "output_V6")

# ── 1. Locate parquet files per scenario ─────────────────────────────────────
search_dirs <- unique(c(
  output_root,
  "output_V6",
  "GeoTIFF_Step5"
))

find_scenario_file <- function(scenario_tag, dirs) {
  for (d in dirs) {
    if (!dir.exists(d)) next
    candidates <- list.files(d, pattern = "\\.parquet$", full.names = TRUE)
    # Match files tagged with scenario name
    matched <- candidates[grepl(scenario_tag, basename(candidates), ignore.case = TRUE)]
    if (length(matched) > 0) {
      return(matched[which.max(file.info(matched)$mtime)])
    }
  }
  NULL
}

file_default     <- find_scenario_file("default",     search_dirs)
file_conservative <- find_scenario_file("conservative", search_dirs)
file_upper       <- find_scenario_file("upper",        search_dirs)

# If no scenario-tagged files exist, fall back to all fi_grid_*.parquet,
# sorted by modification time and pick the 3 most distinct ones
if (is.null(file_default)) {
  cat("No scenario-tagged fi_grid parquets found. Using the 3 most recent fi_grid files.\n")
  all_parquets <- character(0)
  for (d in search_dirs) {
    if (dir.exists(d)) {
      found <- list.files(d, pattern = "^fi_grid_.*\\.parquet$", full.names = TRUE)
      all_parquets <- c(all_parquets, found)
    }
  }
  if (length(all_parquets) < 1) stop("No fi_grid_*.parquet files found.")
  all_parquets <- all_parquets[order(file.info(all_parquets)$mtime, decreasing = TRUE)]
  file_default      <- all_parquets[1]
  file_conservative <- if (length(all_parquets) >= 2) all_parquets[2] else all_parquets[1]
  file_upper        <- if (length(all_parquets) >= 3) all_parquets[3] else all_parquets[1]
  cat("  default:      ", basename(file_default), "\n")
  cat("  conservative: ", basename(file_conservative), "\n")
  cat("  upper_bound:  ", basename(file_upper), "\n")
}

# ── 2. Load, keeping only essential columns ───────────────────────────────────
load_fi <- function(path, label) {
  cat("Loading", label, ":", basename(path), "\n")
  dt <- setDT(read_parquet(path))
  # Retain grid identifier and fi / C_ri columns
  keep <- intersect(names(dt), c("grid_id", "col", "row", "x", "y",
                                  "f_i_full", "f_i_reduced", "C_ri", "C_ri_conservative"))
  if (length(keep) == 0) stop("No expected columns found in ", path)
  dt <- dt[, ..keep]
  setnames(dt, setdiff(names(dt), c("grid_id", "col", "row", "x", "y")),
           paste0(setdiff(names(dt), c("grid_id", "col", "row", "x", "y")), "_", label))
  dt
}

dt_default     <- load_fi(file_default,      "default")
dt_conservative <- load_fi(file_conservative, "conservative")
dt_upper       <- load_fi(file_upper,         "upper")

# ── 3. Merge on grid_id (or col/row) ─────────────────────────────────────────
id_col <- if ("grid_id" %in% names(dt_default)) "grid_id" else "col"

dt <- merge(dt_default, dt_conservative, by = id_col, all = FALSE)
dt <- merge(dt,         dt_upper,        by = id_col, all = FALSE)

cat(sprintf("Merged grid: %d cells common to all three scenarios\n", nrow(dt)))

# ── 4. Compute % differences ──────────────────────────────────────────────────
# Use f_i_full if available; else f_i_reduced; else C_ri
main_col <- if ("f_i_full_default" %in% names(dt)) "f_i_full" else
            if ("f_i_reduced_default" %in% names(dt)) "f_i_reduced" else "C_ri"

col_def  <- paste0(main_col, "_default")
col_cons <- paste0(main_col, "_conservative")
col_up   <- paste0(main_col, "_upper")

eps <- 1e-12  # avoid division by zero
dt[, pct_diff_conservative := (get(col_def) - get(col_cons)) / (get(col_def) + eps) * 100]
dt[, pct_diff_upper         := (get(col_up)  - get(col_def)) / (get(col_def) + eps) * 100]
dt[, range_pct              := pct_diff_upper - (-pct_diff_conservative)]

# ── 5. Global totals table ────────────────────────────────────────────────────
totals <- data.table(
  scenario  = c("default", "conservative", "upper_bound"),
  total_fi  = c(sum(dt[[col_def]],  na.rm = TRUE),
                sum(dt[[col_cons]], na.rm = TRUE),
                sum(dt[[col_up]],   na.rm = TRUE)),
  n_cells_nonzero = c(sum(dt[[col_def]]  > 0, na.rm = TRUE),
                      sum(dt[[col_cons]] > 0, na.rm = TRUE),
                      sum(dt[[col_up]]   > 0, na.rm = TRUE))
)
totals[, pct_vs_default := (total_fi - total_fi[scenario == "default"]) /
                            total_fi[scenario == "default"] * 100]

cat("\n=== Global Totals ===\n")
print(totals)

dir.create(output_root, showWarnings = FALSE, recursive = TRUE)
totals_csv <- file.path(output_root, "scenario_comparison_totals.csv")
fwrite(totals, totals_csv)
cat("Saved:", totals_csv, "\n")

# ── 6. Reconstruct lon/lat for mapping ───────────────────────────────────────
# EPSG:6933 to WGS84: use x/y if present, else reconstruct from grid_id
if ("x" %in% names(dt) && "y" %in% names(dt)) {
  pts <- st_as_sf(dt[, .(x, y, pct_diff_upper, range_pct)],
                  coords = c("x", "y"), crs = 6933)
  pts_wgs84 <- st_transform(pts, 4326)
  coords <- st_coordinates(pts_wgs84)
  dt[, lon := coords[, 1]]
  dt[, lat := coords[, 2]]
} else {
  # Reconstruct from col/row or grid_id using constants.R values
  WORLD_XMIN <- -17367530.45
  WORLD_YMAX <-  7342699.72
  CELL_SIZE_M <- 1000
  GRID_COLS   <- 34735L
  if ("grid_id" %in% names(dt)) {
    dt[, col_idx := (grid_id - 1L) %% GRID_COLS]
    dt[, row_idx := (grid_id - 1L) %/% GRID_COLS]
  } else {
    dt[, col_idx := col]
    dt[, row_idx := row]
  }
  dt[, x_m := WORLD_XMIN + col_idx * CELL_SIZE_M + CELL_SIZE_M / 2]
  dt[, y_m := WORLD_YMAX - row_idx * CELL_SIZE_M - CELL_SIZE_M / 2]

  pts <- st_as_sf(dt[, .(x_m, y_m, pct_diff_upper, range_pct)],
                  coords = c("x_m", "y_m"), crs = 6933)
  pts_wgs84 <- st_transform(pts, 4326)
  coords <- st_coordinates(pts_wgs84)
  dt[, lon := coords[, 1]]
  dt[, lat := coords[, 2]]
}

# ── 7. Map: % spread (upper_bound vs default) ─────────────────────────────────
world <- tryCatch(
  rnaturalearth::ne_countries(scale = "small", returnclass = "sf"),
  error = function(e) {
    cat("rnaturalearth not available — map will have no land outline\n")
    NULL
  }
)

# Downsample for plotting (max 500k points for speed)
plot_dt <- dt[!is.na(lon) & !is.na(lat) & get(col_def) > 0]
if (nrow(plot_dt) > 500000) {
  plot_dt <- plot_dt[sample(.N, 500000)]
}

p <- ggplot() +
  geom_point(data = plot_dt,
             aes(x = lon, y = lat, color = pct_diff_upper),
             size = 0.3, alpha = 0.7) +
  scale_color_viridis_c(
    name = "% above\ndefault",
    limits = c(0, quantile(plot_dt$pct_diff_upper, 0.99, na.rm = TRUE)),
    oob = scales::squish
  ) +
  {if (!is.null(world)) geom_sf(data = world, fill = "grey85", color = "grey60",
                                  size = 0.2, inherit.aes = FALSE)} +
  coord_sf(xlim = c(-180, 180), ylim = c(-90, 90), expand = FALSE) +
  labs(
    title = "fi Scenario Spread: Upper Bound vs Default",
    subtitle = sprintf("n = %d cells | Scenarios: default / conservative / upper_bound",
                       nrow(plot_dt)),
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")

map_png <- file.path(output_root, "scenario_comparison_map.png")
ggsave(map_png, p,
       width = 12, height = 6, dpi = 150)
cat("Saved:", map_png, "\n")

cat("\nDone. Summary of uncertainty spread:\n")
cat(sprintf("  Conservative scenario: %.1f%% below default (global total)\n",
            abs(totals[scenario == "conservative", pct_vs_default])))
cat(sprintf("  Upper-bound scenario:  +%.1f%% above default (global total)\n",
            totals[scenario == "upper_bound", pct_vs_default]))
