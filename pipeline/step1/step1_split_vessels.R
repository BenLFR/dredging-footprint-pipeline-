#!/usr/bin/env Rscript
# =====================================================================
# STEP 1 — AIS SPLIT BY VESSEL (pipeline V6)
# Uses the period and fleet selected by step0_core_window.R (core_window.yaml)
# =====================================================================

cat("\n[INFO]  STEP-1  |  AIS SPLIT BY VESSEL  |  start :",
    format(Sys.time()), "\n\n")

# CRITICAL R CONFIGURATION — BEFORE LOADING PACKAGES
.libPaths("~/R/library")
cat("[INFO] R configured with library:", .libPaths()[1], "\n")

suppressPackageStartupMessages({
  library(data.table)   # fast + low RAM
  library(yaml)         # read step 0 configuration
  # library(fst)        # replaced by qs (GLIBC issue)

  # Try qs with RDS fallback (see README_BELUGA.md — packages already installed)
  use_qs <- FALSE
  tryCatch({
    if (!requireNamespace("qs", quietly = TRUE))
      stop("qs not available")   # qs not available (replaced by RDS fallback)
    library(qs)
    use_qs <- TRUE
    cat("[INFO] Using QS format\n")
  }, error = function(e) {
    cat("[WARN] QS not available, falling back to RDS\n")
    use_qs <<- FALSE
  })

  library(lubridate)    # robust date parsers
  library(tools)        # for file_ext
})

# ---------------------------------------------------------------------
# 1. ── PARAMETERS (overridable via environment variables) ------------
# ---------------------------------------------------------------------
job_id        <- Sys.getenv("SLURM_JOB_ID",        unset = format(Sys.time(), "%Y%m%d%H%M%S"))
input_pattern <- Sys.getenv("AIS_INPUT_PATTERN",   unset = "~/scratch/AIS_data/*.csv")
output_dir    <- Sys.getenv("AIS_OUTPUT_DIR",      unset = file.path("~/scratch", paste0("ais_split_", job_id)))
core_config_path <- Sys.getenv("CORE_CONFIG_PATH", unset = "~/scratch/output_V6/core_window.yaml")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("[INFO]  INPUT  : ", input_pattern, "\n")
cat("[INFO]  OUTPUT : ", output_dir,     "\n")
cat("[INFO]  CONFIG : ", core_config_path, "\n\n")

# ---------------------------------------------------------------------
# 1.b ── READ STEP 0 CONFIGURATION ------------------------------------
# ---------------------------------------------------------------------
if (file.exists(core_config_path)) {
  cat("[INFO]  Reading step 0 configuration...\n")
  core_config <- read_yaml(core_config_path)

  start_year <- core_config$start_year
  end_year   <- core_config$end_year
  core_ships <- core_config$core_ships

  cat("[INFO]  Temporal window:", start_year, "-", end_year, "\n")
  cat("[INFO]  Selected vessels:", length(core_ships), "\n")
  cat("   *", paste(core_ships, collapse = ", "), "\n\n")

  # Parameter validation
  if (is.null(start_year) || is.null(end_year) || is.null(core_ships)) {
    stop("[ERROR]  Step 0 configuration incomplete in", core_config_path)
  }

  use_core_filter <- TRUE
} else {
  cat("[WARN]  Step 0 configuration not found — processing all data\n")
  use_core_filter <- FALSE
  start_year <- NULL
  end_year <- NULL
  core_ships <- NULL
}

# ---------------------------------------------------------------------
# 2. ── MMSI → VESSEL NAME MAPPING ------------------------------------
# ---------------------------------------------------------------------
# Note: Vasco Da Gama had two MMSIs: 253193000 (Luxembourg, 2013-2019) and 205744000 (Belgium, 2018-2024)
# Merging to the most recent MMSI: 205744000
# Note: Goryo 6 Ho (312062000) excluded — corrupt data
mmsi_map <- data.table(
  ssvid = as.character(c(209469000, 210138000, 245508000, 246351000,
            253193000, 205744000, 253373000, 253403000, 253422000,
            253688000, 533180137)),
  Navire = c("Fairway", "Queen Of The Netherlands", "Ham 318",
             "Vox Maxima", "Vasco Da Gama", "Vasco Da Gama", "Cristobal Colon",
             "Leiv Eiriksson", "Charles Darwin", "Congo River",
             "Inai Kenanga"),
  # Reference MMSI (most recent for Vasco Da Gama)
  ssvid_ref = as.character(c(209469000, 210138000, 245508000, 246351000,
                205744000, 205744000, 253373000, 253403000, 253422000,
                253688000, 533180137))
)
setkey(mmsi_map, ssvid)

# Type validation
stopifnot(is.character(mmsi_map$ssvid))
stopifnot(is.character(mmsi_map$ssvid_ref))

# ---------------------------------------------------------------------
# 2.b ── ALIAS → CANONICAL NAME MAPPING --------------------------------
# ---------------------------------------------------------------------
# Handle name differences between CSV and step 0 configuration
alias_map <- data.table(
  alias = c("Ham 318 Sleephopperzuiger", "HAM318",
            "Queen of the netherlands", "Queen Of The Netherlands",
            "Vasco de Gama", "Vasco Da Gama",
            "LEIV EIRIKSSONN", "Leiv Eiriksson",
            "INAI KENANGA", "Inai Kenanga",
            "Goryo 6 HO", "Goryo 6 Ho",
            "Fair Way", "Fairway",
            "VOX maxima", "Vox Maxima"),
  canonical = c("Ham 318", "Ham 318",
                "Queen Of The Netherlands", "Queen Of The Netherlands",
                "Vasco Da Gama", "Vasco Da Gama",
                "Leiv Eiriksson", "Leiv Eiriksson",
                "Inai Kenanga", "Inai Kenanga",
                "Goryo 6 Ho", "Goryo 6 Ho",
                "Fairway", "Fairway",
                "Vox Maxima", "Vox Maxima")
)
setkey(alias_map, alias)

# ---------------------------------------------------------------------
# 3. ── READ DATA (CSV or RDS) ----------------------------------------
# ---------------------------------------------------------------------
# Priority: single input file (RDS/CSV) via AIS_INPUT_FILE env var.
# Fallback: CSV glob pattern.

input_file <- Sys.getenv("AIS_INPUT_FILE", unset = "")

t_read <- system.time({
  if (input_file != "" && file.exists(input_file)) {
    cat("[INFO]  Reading input file via AIS_INPUT_FILE:", input_file, "\n")

    # Detect extension to choose the right reader
    file_ext <- tolower(tools::file_ext(input_file))

    if (file_ext == "rds") {
      ais_dt <- as.data.table(readRDS(input_file))
    } else if (file_ext == "csv") {
      ais_dt <- fread(input_file, showProgress = FALSE)
    } else {
      stop("[ERROR] Unsupported file format for AIS_INPUT_FILE: ", file_ext)
    }

  } else {
    cat("[INFO]  AIS_INPUT_FILE not set or not found. Using CSV pattern:", input_pattern, "\n")
    csv_files <- Sys.glob(input_pattern)

    if (length(csv_files) == 0) stop("[ERROR] No CSV files found for pattern: ", input_pattern)
    if (length(csv_files) > 1) cat("[WARN]  Multiple CSV files detected. Processing first only:", basename(csv_files[1]), "\n")

    cat("   * Reading:", basename(csv_files[1]), "\n")
    ais_dt <- fread(csv_files[1], showProgress = FALSE)
  }
})
cat(sprintf("[INFO]  Read complete: %s rows  |  %.1f s\n",
            format(nrow(ais_dt), big.mark = " "), t_read[3]))

# ---------------------------------------------------------------------
# 4. ── COLUMN NORMALISATION ------------------------------------------
# ---------------------------------------------------------------------
# a) lowercase names
setnames(ais_dt, tolower(names(ais_dt)))

# b) minimal rename dictionary
rename_map <- c(lon="Lon", lat="Lat", course="Course", timestamp="Timestamp",
                speed="Speed", speed_knots="Speed", seg_id="Seg_id",
                trip_id="Seg_id", navire="Navire")
common <- intersect(names(rename_map), names(ais_dt))
setnames(ais_dt, common, rename_map[common])

# c) essential coercions
num_cols <- c("Lon","Lat","Speed")
for (cl in intersect(num_cols, names(ais_dt))) set(ais_dt, j = cl, value = as.numeric(ais_dt[[cl]]))
if ("Timestamp" %chin% names(ais_dt))
  ais_dt[, Timestamp := as.POSIXct(Timestamp, tz = "UTC")]

# ---------------------------------------------------------------------
# 5. ── CREATE / VALIDATE VESSEL COLUMN --------------------------------
# ---------------------------------------------------------------------
if (!"Navire" %in% names(ais_dt)) ais_dt[, Navire := NA_character_]

# If ssvid present, fill missing vessel names from mapping
if ("ssvid" %chin% names(ais_dt)) {
  # Type conversion for ssvid compatibility
  ais_dt[, ssvid := as.character(ssvid)]
  ais_dt <- merge(ais_dt, mmsi_map, by = "ssvid", all.x = TRUE, suffixes = c("", ".map"))

  # Merge duplicate MMSIs to reference MMSI (Vasco Da Gama case)
  ais_dt[!is.na(ssvid_ref), ssvid := ssvid_ref]
  ais_dt[, ssvid_ref := NULL]  # drop temporary column

  ais_dt[is.na(Navire), Navire := Navire.map]
  ais_dt[, Navire.map := NULL]
}

# ultimate fallback: generic name
ais_dt[is.na(Navire) | Navire == "", Navire := paste0("unknown_", .I)]

# ---------------------------------------------------------------------
# 5.a ── VESSEL NAME NORMALISATION VIA ALIAS MAP ----------------------
# ---------------------------------------------------------------------
# Apply alias mapping to harmonise names with step 0
if (use_core_filter) {
  cat("[INFO]  Normalising vessel names...\n")

  tryCatch({
    # Count before normalisation
    noms_avant <- unique(ais_dt$Navire)
    cat("   * Names before normalisation:", paste(noms_avant, collapse = ", "), "\n")

    # Apply alias mapping (safe version)
    ais_dt <- merge(ais_dt, alias_map, by.x = "Navire", by.y = "alias", all.x = TRUE)

    # Replace names that have a canonical alias
    ais_dt[!is.na(canonical), Navire := canonical]

    # Drop temporary column
    if ("canonical" %in% names(ais_dt)) {
      ais_dt[, canonical := NULL]
    }

    # Count after normalisation
    noms_apres <- unique(ais_dt$Navire)
    cat("   * Names after normalisation:", paste(noms_apres, collapse = ", "), "\n")

    if (length(noms_avant) != length(noms_apres)) {
      cat("[INFO]  Normalisation:", length(noms_avant), "->", length(noms_apres), "unique names\n")
    } else {
      cat("[INFO]  No name changes required\n")
    }
  }, error = function(e) {
    cat("[ERROR]  Normalisation error:", e$message, "\n")
    cat("   * Available columns:", paste(names(ais_dt), collapse = ", "), "\n")
    cat("   * alias_map size:", nrow(alias_map), "rows\n")
    stop(e)
  })
}

# ---------------------------------------------------------------------
# 5.b ── APPLY STEP 0 FILTERS -----------------------------------------
# ---------------------------------------------------------------------
if (use_core_filter) {
  cat("[INFO]  Applying step 0 filters...\n")

  # Add year column for temporal filtering
  ais_dt[, Annee := year(Timestamp)]

  # Filter: vessels AND period
  n_before <- nrow(ais_dt)
  ais_dt <- ais_dt[Navire %in% core_ships & Annee >= start_year & Annee <= end_year]
  n_after <- nrow(ais_dt)

  cat(sprintf("[INFO]  Filter: %s -> %s rows (%.1f%% retained)\n",
              format(n_before, big.mark = " "),
              format(n_after, big.mark = " "),
              round(100 * n_after / n_before, 1)))

  # Verify all requested vessels are present
  navires_presents <- unique(ais_dt$Navire)
  navires_manquants <- setdiff(core_ships, navires_presents)

  if (length(navires_manquants) > 0) {
    cat("[WARN]  Vessels missing from window:", paste(navires_manquants, collapse = ", "), "\n")
  }

  cat("[INFO]  Filter complete\n\n")
} else {
  cat("[INFO]  No filter applied (full data processing)\n\n")
}

# ---------------------------------------------------------------------
# 6. ── SPLIT BY VESSEL -----------------------------------------------
# ---------------------------------------------------------------------
# stable order: size desc to track progress
navires <- ais_dt[, .N, by = Navire][order(-N)]
cat("[INFO]  Vessels detected:", navires[,.N], "\n\n")

meta <- navires[, `:=`(file_path = character(.N), split_time = Sys.time())]

pb <- txtProgressBar(min = 0, max = nrow(navires), style = 3)
i <- 0

for (nav in navires$Navire) {
  i <- i + 1
  dt_nav <- ais_dt[Navire == nav]

  safe_name <- gsub("[^A-Za-z0-9_-]", "_", nav)

  if (use_qs) {
    # QS format (optimal)
    out_file  <- file.path(output_dir,
                           sprintf("navire_%02d_%s.qs", i, safe_name))
    qs::qsave(dt_nav, out_file, preset = "custom",
              algorithm = "zstd",         # fast & good ratio
              preset_compression = 6)     # ~ equiv. fst compress=85
  } else {
    # RDS fallback
  out_file  <- file.path(output_dir,
                           sprintf("navire_%02d_%s.rds", i, safe_name))
    saveRDS(dt_nav, out_file, compress = "xz")
  }

  meta[Navire == nav, `:=`(file_path = out_file,
                           n_observations = nrow(dt_nav))]
  rm(dt_nav); gc(verbose = FALSE)
  setTxtProgressBar(pb, i)
}
close(pb)

# ---------------------------------------------------------------------
# 7. ── EXPORT METADATA & INTEGRITY CHECK -----------------------------
# ---------------------------------------------------------------------
meta_file <- file.path(output_dir, "navires_metadata.csv")
fwrite(meta, meta_file)

if (sum(meta$n_observations) != nrow(ais_dt))
  stop("[ERROR]  Integrity check failed: row count mismatch after split!")
cat("\n[INFO]  Integrity OK:", sum(meta$n_observations), "rows verified.\n")

# ---------------------------------------------------------------------
# 8. ── SUMMARY --------------------------------------------------------
# ---------------------------------------------------------------------
cat("\n[INFO]  SPLIT SUMMARY -----------------------------------------\n")
print(meta[, .(Navire, n_observations, file_path)])

total_size <- sum(file.info(meta$file_path)$size) / 1024^2
format_used <- if(use_qs) "qs" else "rds"
cat(sprintf("\n[INFO]  %d .%s files (%.1f MB total) written to: %s\n",
            nrow(meta), format_used, total_size, output_dir))

cat("\n[INFO]  STEP-1 complete:", format(Sys.time()), "\n")
