# Data Availability Statement

*For inclusion in the manuscript submitted to Limnology and Oceanography: Methods.*
*Select Variant A or Variant B and delete the other before submission.*
*Replace every `PLACEHOLDER` / `[TODO]` with the real value before submitting.*

---

## Three Mandatory Archives

Wiley / L&O:Methods requires **three distinct, immutable, version-pinned archives**.
A bare GitHub URL is insufficient — a Zenodo version DOI is required for each
citable deposit (concept DOIs resolve to the latest version and are not stable).

| Archive | Content | Deposit type | Identifier |
|---------|---------|-------------|------------|
| **Archive 1** | Pipeline code (exact version used to produce paper figures) | Zenodo software record | version DOI: `10.5281/zenodo.PLACEHOLDER_CODE` |
| **Archive 2** | Processed gridded outputs (`fi_grid`, `C_ri_grid`, `mc_results_summary`) | Zenodo dataset record (separate from code) | version DOI: `10.5281/zenodo.PLACEHOLDER_DATA` |
| **Archive 3** | Raw AIS data | Cannot be shared — provider contact given | N/A |

> **Important**: always cite the **version DOI** (e.g., `10.5281/zenodo.1234567`),
> not the concept DOI (e.g., `10.5281/zenodo.1234000`). The concept DOI resolves
> to the latest version and will not point to the exact code/data used in the paper.
> Zenodo shows both on each deposit page.

---

## Variant A — All open access (preferred)

The pipeline source code, configuration files, SLURM wrappers, and documentation are
available at GitHub (https://github.com/BenLFR/Master-thesis-code-) and archived at
Zenodo as a software record (Archive 1, DOI: `10.5281/zenodo.PLACEHOLDER_CODE`;
LOEFFLER, 2026). **Use the version DOI, not the concept DOI**, to ensure reviewers
access the exact version used to produce the figures.

Processed gridded output products — dredging intensity grid (`fi_grid_*.parquet`),
carbon release index grid (`C_ri_grid_*.parquet`), and Monte Carlo uncertainty summary
(`mc_results_summary.parquet`) — are archived as a separate Zenodo dataset record
(Archive 2, DOI: `10.5281/zenodo.PLACEHOLDER_DATA`; LOEFFLER, 2026). These derived
outputs are sufficient to reproduce all paper figures without re-running the full
pipeline.

Raw Automatic Identification System (AIS) data were obtained from [DATA PROVIDER —
e.g., Spire Maritime / exactEarth / Marine Cadastre] under [licence type — e.g.,
research licence XXXXX] (Archive 3). Raw AIS data cannot be publicly redistributed;
access requests should be directed to [PROVIDER URL]. The pipeline is compatible with
alternative AIS sources (e.g., Copernicus Marine Service AIS, EMSA SafeSeaNet)
following the instructions in `documentation/VALIDATION_PROTOCOL.md`.

Seabed lithology was obtained from the dbSEABED database via the HubOcean STAC API
(publicly accessible). Carbon stock rasters are from Atwood et al. (2024), available
at [Atwood et al. data repository — TODO fill DOI].

A containerised environment (Apptainer image SHA256: `[TODO — run sha256sum deploy/pipeline_v1.0.0.sif
and paste here]`) ensures that all R 4.3, Python 3.10, and MATLAB dependencies are
pinned to the exact versions used in this study. Build instructions are in
`deploy/apptainer.def`.

---

## Variant B — Partially embargoed (use if raw AIS cannot be shared and paper figures require it)

Processed gridded outputs — dredging intensity grid (`fi_grid_*.parquet`), carbon
release index grid (`C_ri_grid_*.parquet`), and Monte Carlo uncertainty summary
(`mc_results_summary.parquet`) — are openly available at Zenodo (Archive 2, DOI:
`10.5281/zenodo.PLACEHOLDER_DATA`; LOEFFLER, 2026). These derived outputs are
sufficient to reproduce all paper figures without access to the raw AIS data.

The full pipeline source code is archived at Zenodo (Archive 1, DOI:
`10.5281/zenodo.PLACEHOLDER_CODE`; LOEFFLER, 2026) and mirrored on GitHub
(https://github.com/BenLFR/Master-thesis-code-). **Use the version DOI.**

Raw AIS data are subject to a [12-month / ongoing] embargo by [PROVIDER] (Archive 3)
and cannot be shared. The pipeline accepts any AIS dataset following the input schema
in `documentation/README_PIPELINE_BELUGA.md`. Synthetic validation confirms f_i
recovery within ±15% on alternative AIS sources (see
`scripts_principaux/synthetic_validation.R` and `output_V6/validation/synthetic_test_results.txt`).

---

## Pre-submission Checklist (machine-checkable)

Run this grep before final submission — it must return zero hits:

```bash
grep -r "PLACEHOLDER" CITATION.cff configuration/codemeta.json documentation/DATA_AVAILABILITY_STATEMENT.md
# Expected output: nothing (zero lines)
```

- [ ] **No PLACEHOLDER strings** in `CITATION.cff`, `configuration/codemeta.json`,
      or this document (Variant A or B)
- [ ] **Version DOI** (not concept DOI) is used for both Archive 1 and Archive 2
      (check: version DOI ends in the specific record number, e.g. `zenodo.14123456`,
      whereas the concept DOI ends in a different number; Zenodo labels both on the deposit page)
- [ ] **Archive 2 deposit** contains:
      - `fi_grid_*.parquet` (dredging intensity output from step 5)
      - `C_ri_grid_*.parquet` (carbon release index output from step 6)
      - `mc_results_summary.parquet` (Monte Carlo uncertainty from step 4 of Phase 4)
- [ ] **Apptainer SHA256** recorded in `documentation/ZENODO_INTEGRATION_GUIDE.md`
      (`sha256sum deploy/pipeline_v1.0.0.sif >> documentation/ZENODO_INTEGRATION_GUIDE.md`)
- [ ] **AIS provider** name, licence number, and contact URL filled in (both variants)
- [ ] **Atwood et al. (2024)** DOI filled in (References section below)
- [ ] Selected one variant (A or B) and deleted the other
- [ ] Verified all DOI links resolve in a browser before submission
- [ ] Cross-checked with Wiley / L&O:Methods Data Sharing Policy:
      https://aslopubs.onlinelibrary.wiley.com/hub/journal/19415590/homepage/author-guidelines

---

## How to Mint the Two Zenodo DOIs

### Archive 1 — Code (software record)

```bash
# 1. Tag the release
git tag -a v1.0.0 -m "L&O:Methods submission release"
git push origin v1.0.0

# 2. On GitHub: Releases → Draft a new release → select v1.0.0
#    Title: "Dredging Footprint Pipeline v1.0.0"
#    Description: copy abstract from CITATION.cff

# 3. Zenodo (linked to this repo) auto-creates the deposit and mints the DOI.
#    Navigate to zenodo.org, find the deposit, copy the VERSION DOI.

# 4. Replace PLACEHOLDER_CODE in CITATION.cff, codemeta.json, and this file:
sed -i 's/PLACEHOLDER_CODE/REAL_ZENODO_ID/g' \
  CITATION.cff configuration/codemeta.json \
  documentation/DATA_AVAILABILITY_STATEMENT.md
```

### Archive 2 — Processed data (dataset record)

```bash
# Create a NEW, SEPARATE Zenodo deposit (do not add data files to the code deposit).
# Upload: fi_grid_*.parquet, C_ri_grid_*.parquet, mc_results_summary.parquet
# License: Creative Commons Attribution 4.0 (CC-BY 4.0) for data
# Copy the VERSION DOI and replace PLACEHOLDER_DATA:
sed -i 's/PLACEHOLDER_DATA/REAL_DATASET_ZENODO_ID/g' \
  documentation/DATA_AVAILABILITY_STATEMENT.md
```

See `documentation/ZENODO_INTEGRATION_GUIDE.md` for the complete step-by-step guide.

---

## References Relevant to Data Sources

- Atwood, T.B. et al. (2024). Global distribution of seafloor sediment carbon stocks.
  *[Journal]* DOI: [TODO — fill in].
- Kroodsma, D.A. et al. (2018). Tracking the global footprint of fisheries.
  *Science* 359(6378), 904–908. https://doi.org/10.1126/science.aao5646
- Mitchell, A. et al. (20XX). dbSEABED: a database of seafloor sediment properties.
  [Cite appropriately when confirmed.]
- JCGM 100:2008. *Evaluation of measurement data — Guide to the Expression of
  Uncertainty in Measurement* (GUM). BIPM. https://www.bipm.org/en/publications/guides/gum
