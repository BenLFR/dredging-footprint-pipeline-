#!/usr/bin/env Rscript
# ============================================================================
# validate_with_independent_data.R
# Three-pathway validation framework for the dredging footprint pipeline.
#
# Section A: Hold-out temporal split (last year as hold-out)
# Section B: Global Fishing Watch API hook (requires GFW_API_KEY env var)
# Section C: Alternative AIS source (requires AIS_SAMPLE_PATH env var)
#
# Metrics: Pearson r, Spearman r, RMSE, spatial overlap of top-20% cells
#
# Output: output_V6/validation/independent_validation_results.csv
#
# Usage:
#   Rscript tests/validate_with_independent_data.R
#   GFW_API_KEY=yourkey Rscript tests/validate_with_independent_data.R
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(stats)
})

dir.create("output_V6/validation", showWarnings = FALSE, recursive = TRUE)

results <- data.table(
  section        = character(),
  method         = character(),
  pearson_r      = numeric(),
  spearman_r     = numeric(),
  rmse           = numeric(),
  spatial_overlap_top20pct = numeric(),
  n_cells        = integer(),
  note           = character()
)

log_result <- function(section, method, pr, sr, rmse_val, overlap, n, note = "") {
  cat(sprintf("[%s | %s] r=%.3f, rho=%.3f, RMSE=%.4f, overlap=%.1f%% (n=%d)\n",
              section, method, pr, sr, rmse_val, overlap * 100, n))
  if (nchar(note) > 0) cat(sprintf("  Note: %s\n", note))
  results <<- rbind(results, data.table(
    section = section, method = method,
    pearson_r = round(pr, 4), spearman_r = round(sr, 4),
    rmse = round(rmse_val, 6), spatial_overlap_top20pct = round(overlap, 4),
    n_cells = n, note = note
  ))
}

spatial_overlap_20pct <- function(x, y) {
  # Fraction of top-20% cells in x that are also top-20% in y
  cutoff_x <- quantile(x, 0.80, na.rm = TRUE)
  cutoff_y <- quantile(y, 0.80, na.rm = TRUE)
  top_x <- which(x >= cutoff_x)
  top_y <- which(y >= cutoff_y)
  if (length(top_x) == 0) return(NA_real_)
  length(intersect(top_x, top_y)) / length(top_x)
}

# ── Locate step3 output ───────────────────────────────────────────────────────
find_core_rds <- function() {
  dirs <- c("output_V6",
            file.path(path.expand("~"), "scratch", "output_V6"),
            "scripts_cluster")
  for (d in dirs) {
    if (!dir.exists(d)) next
    found <- list.files(d, pattern = "^AIS_data_core_preprocessed_V6_.*\\.rds$",
                        full.names = TRUE)
    if (length(found) > 0) return(found[which.max(file.info(found)$mtime)])
  }
  NULL
}

find_fi_parquet <- function() {
  dirs <- c("output_V6",
            file.path(path.expand("~"), "scratch", "output_V6"))
  for (d in dirs) {
    if (!dir.exists(d)) next
    found <- list.files(d, pattern = "^fi_grid_.*\\.parquet$", full.names = TRUE)
    if (length(found) > 0) return(found[which.max(file.info(found)$mtime)])
  }
  NULL
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION A: Hold-out temporal split
# Use the last available year as hold-out; compare to full-period prediction.
# ─────────────────────────────────────────────────────────────────────────────
cat("\n=== Section A: Hold-out temporal split ===\n")

core_path <- find_core_rds()
fi_path   <- find_fi_parquet()

if (!is.null(core_path) && !is.null(fi_path)) {
  tryCatch({
    cat("Loading step3 output:", basename(core_path), "\n")
    ais <- setDT(readRDS(core_path))

    if (!("Timestamp" %in% names(ais))) {
      cat("No Timestamp column — skipping temporal split.\n")
    } else {
      ais[, year := as.integer(format(as.POSIXct(Timestamp), "%Y"))]
      years <- sort(unique(ais$year))
      holdout_year <- max(years, na.rm = TRUE)
      train_years  <- years[years < holdout_year]

      cat(sprintf("Hold-out year: %d | Training years: %s\n",
                  holdout_year, paste(train_years, collapse = ", ")))

      ais_train   <- ais[year %in% train_years]
      ais_holdout <- ais[year == holdout_year]

      # Dredging intensity proxy: fraction of pings classified as dredging per MMSI
      if ("Dragage_flag" %in% names(ais)) {
        flag_col <- "Dragage_flag"
      } else if ("behavior_smooth" %in% names(ais)) {
        ais[, Dragage_flag := as.integer(behavior_smooth == "dredging")]
        flag_col <- "Dragage_flag"
      } else {
        stop("No dredging flag column.")
      }

      train_intensity   <- ais_train[,   .(fi_train   = mean(get(flag_col), na.rm=TRUE)), by = ssvid]
      holdout_intensity <- ais_holdout[, .(fi_holdout = mean(get(flag_col), na.rm=TRUE)), by = ssvid]
      comp <- merge(train_intensity, holdout_intensity, by = "ssvid")

      if (nrow(comp) >= 3) {
        pr      <- cor(comp$fi_train, comp$fi_holdout, use = "complete.obs", method = "pearson")
        sr      <- cor(comp$fi_train, comp$fi_holdout, use = "complete.obs", method = "spearman")
        rmse_v  <- sqrt(mean((comp$fi_train - comp$fi_holdout)^2, na.rm = TRUE))
        overlap <- spatial_overlap_20pct(comp$fi_train, comp$fi_holdout)
        log_result("A", "temporal_holdout", pr, sr, rmse_v, overlap, nrow(comp),
                   sprintf("holdout=%d, train=%s", holdout_year, paste(train_years, collapse="+")))
      } else {
        cat("Insufficient vessels for holdout comparison (n < 3).\n")
      }
    }
  }, error = function(e) {
    cat("Section A error:", conditionMessage(e), "\n")
    log_result("A", "temporal_holdout", NA, NA, NA, NA, 0, conditionMessage(e))
  })
} else {
  cat("No step3 output or fi_grid found — Section A skipped.\n")
  log_result("A", "temporal_holdout", NA, NA, NA, NA, 0, "input files not found")
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION B: Global Fishing Watch API hook
# Requires environment variable GFW_API_KEY to be set.
# Downloads fishing effort for same vessels/period and correlates with fi.
# ─────────────────────────────────────────────────────────────────────────────
cat("\n=== Section B: Global Fishing Watch API ===\n")

gfw_key <- Sys.getenv("GFW_API_KEY")
if (nchar(gfw_key) == 0) {
  cat("GFW_API_KEY not set — Section B skipped.\n")
  cat("To enable: set GFW_API_KEY=your_api_key before running this script.\n")
  cat("Request a key at: https://globalfishingwatch.org/our-apis/\n")
  log_result("B", "gfw_fishing_hours", NA, NA, NA, NA, 0,
             "GFW_API_KEY not set — skipped")
} else if (!requireNamespace("httr", quietly = TRUE)) {
  cat("Package 'httr' not available — install with: install.packages('httr')\n")
  log_result("B", "gfw_fishing_hours", NA, NA, NA, NA, 0,
             "httr not installed — skipped")
} else {
  tryCatch({
    library(httr)
    cat("GFW_API_KEY found. Querying GFW fishing hours API...\n")
    # GFW v3 API: apparent fishing hours on a 0.1° grid
    # Docs: https://globalfishingwatch.org/our-apis/documentation
    # The endpoint below queries annual fishing hours for geartype=dredge
    gfw_url <- paste0(
      "https://gateway.api.globalfishingwatch.org/v3/4wings/report",
      "?datasets[0]=public-global-fishing-effort:latest",
      "&filters[0][field]=geartype&filters[0][values][0]=dredge_fish",
      "&date-range=2020-01-01,2021-01-01",
      "&spatial-resolution=LOW",    # 0.1° grid
      "&temporal-resolution=YEARLY"
    )
    resp <- GET(gfw_url, add_headers(Authorization = paste("Bearer", gfw_key)))
    if (status_code(resp) == 200) {
      gfw_data <- content(resp, as = "parsed")
      cat(sprintf("GFW response: %d entries\n", length(gfw_data$entries)))
      # TODO: parse gfw_data into a data.table and correlate with fi_grid
      # This requires matching 0.1° GFW grid to 1 km pipeline grid via spatial join.
      log_result("B", "gfw_fishing_hours", NA, NA, NA, NA,
                 length(gfw_data$entries),
                 "GFW data retrieved — spatial correlation not yet implemented. Implement grid join.")
    } else {
      cat(sprintf("GFW API error: %d — %s\n", status_code(resp), content(resp, "text")))
      log_result("B", "gfw_fishing_hours", NA, NA, NA, NA, 0,
                 sprintf("GFW API error %d", status_code(resp)))
    }
  }, error = function(e) {
    cat("Section B error:", conditionMessage(e), "\n")
    log_result("B", "gfw_fishing_hours", NA, NA, NA, NA, 0, conditionMessage(e))
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION C: Alternative AIS source (Copernicus / EMSA)
# Requires AIS_SAMPLE_PATH env var pointing to a local AIS CSV/RDS file.
# Compares f_i distribution from this alternative source to the pipeline output.
# ─────────────────────────────────────────────────────────────────────────────
cat("\n=== Section C: Alternative AIS source ===\n")

ais_sample_path <- Sys.getenv("AIS_SAMPLE_PATH")
if (nchar(ais_sample_path) == 0) {
  cat("AIS_SAMPLE_PATH not set — Section C skipped.\n")
  cat("To enable: set AIS_SAMPLE_PATH=/path/to/alternative_ais_sample.rds\n")
  cat("  (e.g., from Copernicus Marine Service or EMSA SafeSeaNet)\n")
  log_result("C", "alternative_ais_source", NA, NA, NA, NA, 0,
             "AIS_SAMPLE_PATH not set — skipped")
} else if (!file.exists(ais_sample_path)) {
  cat(sprintf("AIS_SAMPLE_PATH file not found: %s\n", ais_sample_path))
  log_result("C", "alternative_ais_source", NA, NA, NA, NA, 0,
             paste("File not found:", ais_sample_path))
} else {
  tryCatch({
    cat("Loading alternative AIS:", basename(ais_sample_path), "\n")
    ext <- tools::file_ext(ais_sample_path)
    ais_alt <- if (ext == "rds") {
      setDT(readRDS(ais_sample_path))
    } else if (ext == "csv") {
      fread(ais_sample_path)
    } else {
      stop(sprintf("Unsupported file format: .%s (expected .rds or .csv)", ext))
    }
    cat(sprintf("Loaded: %d rows\n", nrow(ais_alt)))

    # Compute dredging intensity proxy: fraction of time slow per 1° cell
    req_cols <- c("Latitude", "Longitude", "speed_knots")
    if (!all(req_cols %in% names(ais_alt))) {
      stop(paste("Missing columns:", paste(setdiff(req_cols, names(ais_alt)), collapse=", ")))
    }

    DREDGE_SPEED_KN <- 4.0
    ais_alt[, lon_1deg := floor(Longitude)]
    ais_alt[, lat_1deg := floor(Latitude)]
    ais_alt[, is_dredging := as.integer(speed_knots < DREDGE_SPEED_KN)]

    alt_grid <- ais_alt[, .(fi_alt = mean(is_dredging, na.rm = TRUE),
                             n_pings = .N), by = .(lon_1deg, lat_1deg)]

    # Load pipeline fi_grid and aggregate to 1° cells
    if (!is.null(fi_path)) {
      fi_dt <- if (requireNamespace("arrow", quietly = TRUE)) {
        setDT(arrow::read_parquet(fi_path))
      } else setDT(readRDS(sub("\\.parquet$", ".rds", fi_path)))

      if ("lon" %in% names(fi_dt) && "lat" %in% names(fi_dt) &&
          "f_i_full" %in% names(fi_dt)) {
        fi_dt[, lon_1deg := floor(lon)]
        fi_dt[, lat_1deg := floor(lat)]
        fi_1deg <- fi_dt[, .(fi_pipeline = mean(f_i_full, na.rm = TRUE)),
                         by = .(lon_1deg, lat_1deg)]

        comp <- merge(alt_grid, fi_1deg, by = c("lon_1deg", "lat_1deg"))
        if (nrow(comp) >= 5) {
          pr      <- cor(comp$fi_alt, comp$fi_pipeline, method = "pearson",
                         use = "complete.obs")
          sr      <- cor(comp$fi_alt, comp$fi_pipeline, method = "spearman",
                         use = "complete.obs")
          rmse_v  <- sqrt(mean((comp$fi_alt - comp$fi_pipeline)^2, na.rm = TRUE))
          overlap <- spatial_overlap_20pct(comp$fi_alt, comp$fi_pipeline)
          log_result("C", "alternative_ais_source", pr, sr, rmse_v, overlap,
                     nrow(comp), basename(ais_sample_path))
        } else {
          log_result("C", "alternative_ais_source", NA, NA, NA, NA, nrow(comp),
                     "Insufficient overlap cells for correlation")
        }
      } else {
        log_result("C", "alternative_ais_source", NA, NA, NA, NA, 0,
                   "fi_grid missing lon/lat/f_i_full columns")
      }
    } else {
      log_result("C", "alternative_ais_source", NA, NA, NA, NA, 0,
                 "fi_grid not found")
    }
  }, error = function(e) {
    cat("Section C error:", conditionMessage(e), "\n")
    log_result("C", "alternative_ais_source", NA, NA, NA, NA, 0, conditionMessage(e))
  })
}

# ── Save results ──────────────────────────────────────────────────────────────
out_path <- "output_V6/validation/independent_validation_results.csv"
fwrite(results, out_path)
cat(sprintf("\nSaved: %s\n", out_path))
cat("\n=== Validation Summary ===\n")
print(results[, .(section, method, pearson_r, spearman_r, rmse,
                  spatial_overlap_top20pct, n_cells)])
