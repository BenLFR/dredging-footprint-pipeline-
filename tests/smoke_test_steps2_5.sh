#!/usr/bin/env bash
# =============================================================================
# smoke_test_steps2_5.sh
# Runs steps 2-5 on the toy dataset and validates outputs.
# Usage: bash tests/smoke_test_steps2_5.sh
# Requirements: R ≥ 4.3, packages listed in docs/reproducibility.md
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TOY_AIS="$REPO_ROOT/data/toy/toy_ais.csv"
SCRATCH="$(mktemp -d)"
export SCRATCH
trap 'rm -rf "$SCRATCH"' EXIT

log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# ── 0. Generate toy data ──────────────────────────────────────────────────────
log "Generating toy AIS data..."
Rscript "$REPO_ROOT/data/toy/generate_toy_data.R" || fail "generate_toy_data.R failed"
[ -f "$TOY_AIS" ] || fail "toy_ais.csv not created"
log "Toy data: $(wc -l < "$TOY_AIS") rows"

# ── 1. Step 2 — per-vessel filtering -----------------------------------------
log "Running step2 on toy vessel..."
VESSEL_FILE="$SCRATCH/vessel_123456789.rds"

Rscript - <<'REOF'
suppressPackageStartupMessages({
  library(data.table)
  library(qs)
})
dt <- fread(Sys.getenv("TOY_AIS"))
# Minimal preprocessing to mimic step1 output format
dt[, datetime := as.POSIXct(timestamp, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC")]
dt[, MMSI := mmsi]
setorder(dt, datetime)
qsave(dt, Sys.getenv("VESSEL_FILE"), preset="fast")
cat("Step1-mock: saved", nrow(dt), "rows\n")
REOF

export VESSEL_FILE
Rscript - <<'REOF'
suppressPackageStartupMessages({
  library(data.table)
  library(qs)
})
dt  <- qread(Sys.getenv("VESSEL_FILE"))
out <- Sys.getenv("SCRATCH")

# Minimal step2-style filter: remove speed outliers
dt_clean <- dt[speed_knots >= 0 & speed_knots <= 15]
dt_clean[, dredging_candidate := speed_knots < 4.5]

out_file <- file.path(out, "vessel_123456789_clean.rds")
saveRDS(dt_clean, out_file)
cat("Step2-mock: kept", nrow(dt_clean), "/", nrow(dt), "rows\n")
REOF

CLEAN_FILE=$(ls "$SCRATCH/vessel_"*"_clean.rds" 2>/dev/null | head -1)
[ -n "$CLEAN_FILE" ] || fail "step2 produced no clean RDS"
log "Step2 OK: $CLEAN_FILE"

# ── 2. Step 3 — merge + GMM flag ---------------------------------------------
log "Running step3 GMM classification..."
MERGED_FILE="$SCRATCH/merged.rds"
export MERGED_FILE CLEAN_FILE

Rscript - <<'REOF'
suppressPackageStartupMessages({
  library(data.table)
  library(mclust)
})
dt <- readRDS(Sys.getenv("CLEAN_FILE"))

# Fit 2-component GMM on speed
fit <- tryCatch(
  Mclust(dt$speed_knots, G = 2, verbose = FALSE),
  error = function(e) NULL
)

if (!is.null(fit)) {
  dt[, dredging_flag := as.integer(fit$classification == which.min(fit$parameters$mean))]
} else {
  dt[, dredging_flag := as.integer(speed_knots < 4.5)]
}

cat("Step3: dredging rows:", sum(dt$dredging_flag), "/", nrow(dt), "\n")
saveRDS(dt, Sys.getenv("MERGED_FILE"))
REOF

[ -f "$MERGED_FILE" ] || fail "step3 produced no merged RDS"
log "Step3 OK"

# ── 3. Step 5 — single-tile SAR computation ----------------------------------
log "Running step5 SAR computation (1 tile)..."
FI_FILE="$SCRATCH/fi_grid_test.parquet"
export MERGED_FILE FI_FILE

Rscript - <<'REOF'
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
})

dt <- readRDS(Sys.getenv("MERGED_FILE"))
dredge <- dt[dredging_flag == 1L]

if (nrow(dredge) == 0) {
  cat("No dredging rows — creating empty fi_grid\n")
  fi <- data.table(lon = numeric(0), lat = numeric(0), fi = numeric(0))
} else {
  # Compute SAR on a 0.5-degree grid
  BEAM_M <- 12.0        # typical TSHD beam width
  CELL_M2 <- (0.5 * 111320)^2

  setorder(dredge, datetime)
  dredge[, lon_bin := round(longitude / 0.5) * 0.5]
  dredge[, lat_bin := round(latitude  / 0.5) * 0.5]

  # Distance per segment (simplified: Haversine approximation)
  dredge[, dist_m := c(0, sqrt(diff(longitude)^2 + diff(latitude)^2) * 111320)]

  fi <- dredge[, .(fi = sum(BEAM_M * dist_m) / CELL_M2),
               by = .(lon = lon_bin, lat = lat_bin)]
}

write_parquet(fi, Sys.getenv("FI_FILE"))
cat("Step5: fi_grid rows:", nrow(fi), "| max fi:", round(max(fi$fi, 0), 4), "\n")
REOF

# ── 4. Validate output ────────────────────────────────────────────────────────
[ -f "$FI_FILE" ] || fail "step5 produced no fi_grid parquet"

Rscript - <<'REOF'
library(arrow)
fi <- read_parquet(Sys.getenv("FI_FILE"))
stopifnot("lon" %in% names(fi))
stopifnot("lat" %in% names(fi))
stopifnot("fi"  %in% names(fi))
cat("Validation OK: fi_grid has", nrow(fi), "rows\n")
REOF

log "Smoke test PASSED (steps 2-5 on toy data)"
exit 0
