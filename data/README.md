# Data Acquisition Guide

This pipeline requires several external datasets. **None of the raw data files
are included in this repository** due to licensing restrictions or file size.
This document explains how to obtain each input.

---

## Required inputs per step

| Step | Input file(s) | Format | Size |
|------|--------------|--------|------|
| step0 | AIS track data | CSV / Parquet | ~50 GB/year |
| step1–3 | AIS track data | CSV / Parquet | — |
| step4 | dbSEABED lithology grid | GeoTIFF | ~2 GB |
| step5 | Land mask shapefile | SHP | ~200 MB |
| step5 | Longhurst provinces | SHP | ~5 MB |
| step5 | C₀ carbon stock raster (Atwood et al.) | GeoTIFF | ~500 MB |
| step6 | C₀ raster (same as above) | GeoTIFF | — |
| step7/co2model (external) | OCIM2-48L transport matrix | .mat | ~8 GB |
| step7/co2model (external) | WOA09 nutrients | .mat | ~500 MB |

Place all real data in `data/external/` (gitignored).

---

## 1. AIS vessel tracking data

**Source**: Exact Earth (commercial) or Global Fishing Watch (GFW, free for
research with application).

- **Exact Earth**: https://www.exactearth.com — requires data purchase agreement.
  Raw CSV exports include: MMSI, timestamp, lat, lon, speed, course, vessel_type.
- **GFW**: https://globalfishingwatch.org/data-download/ — free academic access
  via application. Provides daily AIS CSVs.

**Cannot be redistributed.** The availability statement for L&O:Methods should
read: *"AIS data were obtained from Exact Earth under a data use agreement and
cannot be shared publicly. Requests may be directed to Exact Earth Ltd."*

Expected schema (minimum columns):
```
MMSI, timestamp (ISO 8601), latitude, longitude, speed_knots, vessel_type
```

---

## 2. dbSEABED seafloor lithology

**Source**: HubOcean STAC API (free, open access).

Use the prefetch script included in this repo:
```bash
python pipeline_V6/pipeline_V6/prefetch_hubocean_stac.py \
  --output data/external/dbseabed_lithology.tif
```
Or download manually from: https://hub.ocean.digital/stac

---

## 3. OCIM2-48L ocean transport matrix

**Source**: T. DeVries lab, UC Santa Barbara.

- Zenodo record (if published): https://zenodo.org/record/XXXXXXX
- Or request directly: tdevries@geog.ucsb.edu

Required files:
- `OCIM2_48L_CTL.mat` (~8 GB) — baseline circulation
- `schmidt_coeff.mat` — Schmidt number coefficients
- `woa09po4.mat` / `woa09si.mat` — World Ocean Atlas 2009 nutrients

Place in `data/external/ocim/`.

---

## 3b. CO2 model source code (external dependency)

The MATLAB OCIM CO2 solver code is third-party material and is not redistributed
in this repository.

Current acquisition path:
- request the OCIM code package by email to `tdevries@geog.ucsb.edu`
  (consistent with Atwood data availability wording).

```bash
# after receiving files, place them here
mkdir -p data/external/co2model_vendor
```

Use `data/external/co2model_vendor/` as `--co2model-src` when running:

```bash
bash deploy/upload_step7_to_grit.sh --co2model-src data/external/co2model_vendor
```

---

## 4. C₀ carbon stock raster (Atwood et al. 2020)

**Source**: Zenodo (open access).

```bash
wget https://zenodo.org/record/3772915/files/Cstocks_Tot_0_30cm_mangroves.tif
# or use the DOI: 10.5281/zenodo.3772915
```

Place as `data/external/C0_carbon_stock.tif`.

---

## 5. Longhurst provinces shapefile

**Source**: VLIZ Marine Regions (free).

Download: https://www.marineregions.org/downloads.php
File: `longhurst_v4_2010.zip`

Place in `data/external/longhurst_v4_2010/`.

---

## 6. Land mask shapefile

**Source**: GSHHS (Global Self-consistent Hierarchical High-resolution Shorelines)

Download: https://www.ngdc.noaa.gov/mgg/shorelines/
Or use the included `configuration/land_mask/` directory if present.

---

## 7. Toy dataset (`data/toy/`)

A synthetic single-vessel, 30-day AIS dataset (~500 rows) is provided for
pipeline testing without access to restricted data.

Generate with:
```bash
Rscript data/toy/generate_toy_data.R
# Outputs: data/toy/toy_ais.csv
```

The toy data uses a realistic TSHD motion profile (alternating dredging passes
and transit) within the North Sea (51–54°N, 2–6°E).

---

## Data availability statement (L&O:Methods template)

> The AIS vessel tracking data used in this study were obtained from Exact Earth
> Ltd under a data use agreement and are not publicly available. The processed
> swept-area ratio grid (f_i) and cumulative risk index (C_ri) rasters are
> available on Zenodo (DOI: 10.5281/zenodo.XXXXXXX). All analysis code is
> available at https://github.com/BenLFR/Master-thesis-code- under the MIT
> licence. All other input datasets (dbSEABED, OCIM2-48L, Atwood C₀ raster,
> Longhurst provinces) are publicly available from the sources listed above.
