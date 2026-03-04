# Step 2 – Reduce On‑land False Positives (notes)

## Defaults (safe starting point)
- `LAND_ONLAND_ERODE_M=-100`
- `MIN_SEG_DT_SEC=60`
- `MIN_SEG_DIST_M=250`
- `SF_CHUNK=100000`
- `LAND_MASK_BUFFER_M=0`
- `LAND_NEAR_COAST_KM=2`

## How to tune
- If **on_land still too high**: increase erosion magnitude (e.g. `-150`).
- If **on_land too low** (missing true land hits): reduce erosion (e.g. `-50`).
- If **crosses_land too high**: increase `MIN_SEG_DIST_M` or `MIN_SEG_DT_SEC`.
- If **crosses_land too low**: decrease those thresholds slightly.

## Run example
```bash
export LAND_ONLAND_ERODE_M=-100
export MIN_SEG_DT_SEC=60
export MIN_SEG_DIST_M=250
export SF_CHUNK=100000
SPLIT_JOB_ID=12990 sbatch --array=9 step2_process_array.sh
```

## Before/after log lines to capture
Paste these from the Step 2 log:
- `on_land (static)`
- `crosses_land`
- `speed_jump`, `long_jump`, `spike`
- `Filtres géospatiaux : ...`

