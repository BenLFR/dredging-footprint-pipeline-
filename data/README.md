# Data Acquisition Guide

This pipeline requires several external datasets. None of the raw source data
files are included in this repository due to access restrictions or file size.
This document explains how to obtain each input.

---

## Required inputs per step

| Step | Input file(s) | Format | Size (approx.) |
|------|---------------|--------|----------------|
| step0–3 | AIS vessel tracking data | CSV / Parquet | ~50 GB/year |
| step2 | Land mask shapefile | SHP | ~500 MB |
| step4 | dbSEABED lithology grid | via HubOcean STAC API | variable |
| step5 | Longhurst provinces shapefile | SHP | ~5 MB |
| step6 | Atwood et al. sediment carbon stock rasters | GeoTIFF (multi-band) | ~1 GB |
| step7/co2model | OCIM2-48L transport matrix + WOA09 nutrients | .mat | ~8 GB total |

Place all real data in `data/external/` (gitignored).

---

## 1. AIS vessel tracking data

Source used in this project: Global Fishing Watch (GFW) AIS data, accessed via
the Stanford Center for Ocean Solutions collaboration channel.

- Data are restricted access and cannot be redistributed from this repository.
- For replication access, contact Global Fishing Watch via:
  https://globalfishingwatch.org/data-download/

Expected column schema (GFW standard):

```
ssvid          — vessel identifier (GFW format, equivalent to MMSI)
timestamp      — ISO 8601 UTC string (e.g. "2020-06-01T12:00:00Z")
lat            — WGS84 latitude (decimal degrees)
lon            — WGS84 longitude (decimal degrees)
speed          — speed over ground (knots)
course         — course over ground (degrees)
seg_id         — GFW segment identifier
```

---

## 2. Land mask shapefile

Source: OpenStreetMap land polygons
(https://osmdata.openstreetmap.de/data/land-polygons.html)

Download the "split" version for large-area processing:
```
land-polygons-split-4326.zip
```

Extract `land_polygons.shp` and place in `configuration/land_mask/`.

The pipeline reads it via the `LAND_MASK_FILE` environment variable
(default: `~/ais-pipeline/configuration/land_mask/land_polygons.shp`).

---

## 3. dbSEABED seafloor lithology

Source: HubOcean STAC API (free, open access).

Use the prefetch script:
```bash
python pipeline/step4/prefetch_hubocean_stac.py \
  --output data/external/dbseabed_lithology.tif
```

Or browse manually at: https://hub.ocean.digital/stac

---

## 4. Atwood et al. sediment carbon stock rasters (step6 input)

Source: Atwood T.B. et al. (2020) "Global patterns in marine sediment carbon
stocks." *Frontiers in Marine Science*, doi: 10.3389/fmars.2020.00165

Dataset: Figshare doi: 10.6084/m9.figshare.11956356
Direct: https://figshare.com/articles/dataset/Global_marine_sedimentary_carbon_stock/11956356

Download the GeoTIFF files (1 km resolution, 1 m depth, units: Mg C km⁻²).
The pipeline (step6) expects a directory containing `.tif` files with bands:
- `Mean carbon_stock`
- `global_error_lower_bound`
- `global_error_upper_bound`

Place the `.tif` files in `~/scratch/configuration/atwood_carbon_full/` on the
cluster, or set the `CARBON_DIR` environment variable to point to the directory.

---

## 5. Longhurst provinces shapefile

Source: VLIZ Marine Regions (free).
Download: https://www.marineregions.org/downloads.php
File: `longhurst_v4_2010.zip`

Place extracted files in `configuration/longhurst_v4_2010/`.

---

## 6. OCIM2-48L ocean transport matrix

Source: T. DeVries lab, UC Santa Barbara.
Request by email: tdevries@geog.ucsb.edu
(consistent with Atwood et al. 2020 data availability wording)

Required files (place in `data/external/ocim/` or `~/scratch/configuration/ocim/`):
- `OCIM2_48L_CTL.mat` — baseline circulation matrix
- `schmidt_coeff.mat` — Schmidt number coefficients
- `woa09po4.mat` / `woa09si.mat` — World Ocean Atlas 2009 nutrients

## 6b. CO2 model source code (external, not bundled)

Request the MATLAB OCIM CO2 solver package by email from T. DeVries
(`tdevries@geog.ucsb.edu`), then upload to the cluster:

```bash
bash deploy/upload_step7_to_cluster.sh --co2model-src /path/to/received/package
```

---

## 7. Toy dataset (`data/toy/`)

A synthetic single-vessel 30-day AIS dataset (~500 rows) is provided for
pipeline smoke testing without access to the restricted GFW data.

Generate with:
```bash
Rscript data/toy/generate_toy_data.R
# output: data/toy/toy_ais.csv
```

The toy data simulates a realistic TSHD motion profile (alternating dredging
passes and transit legs) in the North Sea (51.5–53.5°N, 2–6°E).

Note: the toy dataset uses simplified column names for testing only. The real
GFW pipeline input uses `ssvid` (not `mmsi`) as the vessel identifier.

---

## Data availability statement (L&O Methods template)

> The AIS vessel tracking data used in this study were obtained from Global
> Fishing Watch (GFW) via the Stanford Center for Ocean Solutions and are not
> publicly available. Requests for access should be directed to GFW
> (globalfishingwatch.org/data-download/). The processed swept-area ratio grid
> and cumulative risk index rasters are available on Zenodo
> (DOI: 10.5281/zenodo.XXXXXXX). All analysis code is available at
> https://github.com/BenLFR/dredging-footprint-pipeline under the MIT licence.
> All other input datasets (dbSEABED via HubOcean, OCIM2-48L, Atwood et al.
> sediment carbon stocks, Longhurst provinces, OSM land polygons) are publicly
> available from the sources listed in `data/README.md`.
