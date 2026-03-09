#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(mclust)
})

get_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  hit <- grep(paste0("^", file_arg), args, value = TRUE)
  if (!length(hit)) stop("Unable to resolve script path from commandArgs().")
  normalizePath(sub(file_arg, "", hit[[1]]), winslash = "/", mustWork = TRUE)
}

script_dir <- dirname(get_script_path())
repo_root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(repo_root)

toy_csv <- file.path(repo_root, "data", "toy", "toy_ais.csv")
scratch <- tempfile("smoke_steps2_5_")
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)

on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

log <- function(msg) cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))

log("Generating toy AIS data...")
status <- system2("Rscript", args = "data/toy/generate_toy_data.R")
if (status != 0L) stop("generate_toy_data.R failed.")
if (!file.exists(toy_csv)) stop("toy_ais.csv not found.")

dt <- fread(toy_csv)
if (!nrow(dt)) stop("toy_ais.csv is empty.")
log(sprintf("Toy data rows: %d", nrow(dt)))

# Step2 mock
vessel_file <- file.path(scratch, "vessel_123456789.rds")
dt[, datetime := as.POSIXct(timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
dt[, MMSI := mmsi]
setorder(dt, datetime)
saveRDS(dt, vessel_file)

clean <- dt[speed_knots >= 0 & speed_knots <= 15]
clean[, dredging_candidate := speed_knots < 4.5]
clean_file <- file.path(scratch, "vessel_123456789_clean.rds")
saveRDS(clean, clean_file)
if (!file.exists(clean_file)) stop("Step2 mock failed to produce clean RDS.")
log(sprintf("Step2 mock rows kept: %d", nrow(clean)))

# Step3 mock
fit <- tryCatch(
  Mclust(clean$speed_knots, G = 2, verbose = FALSE),
  error = function(e) NULL
)
if (!is.null(fit)) {
  clean[, Dragage_flag := as.integer(fit$classification == which.min(fit$parameters$mean))]
} else {
  clean[, Dragage_flag := as.integer(speed_knots < 4.5)]
}
merged_file <- file.path(scratch, "merged.rds")
saveRDS(clean, merged_file)
if (!file.exists(merged_file)) stop("Step3 mock failed to produce merged RDS.")
log(sprintf("Step3 dredging rows: %d", sum(clean$Dragage_flag, na.rm = TRUE)))

# Step5 mock
fi_file <- file.path(scratch, "fi_grid_test.rds")
dredge <- clean[Dragage_flag == 1L]
if (!nrow(dredge)) {
  fi <- data.table(lon = numeric(0), lat = numeric(0), fi = numeric(0))
} else {
  beam_m <- 12.0
  cell_m2 <- (0.5 * 111320)^2
  setorder(dredge, datetime)
  dredge[, lon_bin := round(longitude / 0.5) * 0.5]
  dredge[, lat_bin := round(latitude / 0.5) * 0.5]
  dredge[, dist_m := c(0, sqrt(diff(longitude)^2 + diff(latitude)^2) * 111320)]
  fi <- dredge[
    ,
    .(fi = sum(beam_m * dist_m, na.rm = TRUE) / cell_m2),
    by = .(lon = lon_bin, lat = lat_bin)
  ]
}

saveRDS(fi, fi_file)
if (!file.exists(fi_file)) stop("Step5 mock failed to produce fi output.")
fi_check <- readRDS(fi_file)
stopifnot(all(c("lon", "lat", "fi") %in% names(fi_check)))

log(sprintf("Step5 fi rows: %d", nrow(fi_check)))
cat("[PASS] smoke_test_steps2_5.R\n")
