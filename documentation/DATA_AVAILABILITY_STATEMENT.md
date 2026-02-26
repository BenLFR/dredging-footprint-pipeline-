# Data Availability Statement

*For inclusion in the manuscript submitted to Limnology and Oceanography: Methods.*

---

## Variant A — All open access (preferred)

The complete pipeline code, configuration files, and documentation are freely
available at GitHub (https://github.com/BenLFR/Master-thesis-code-) and archived
on Zenodo (DOI: 10.5281/zenodo.PLACEHOLDER; LOEFFLER, 2026). Processed gridded
output products (dredging intensity grid `fi_grid`, carbon release index grid
`C_ri_grid`, and OCIM-ready Jdredge flux maps) are archived at [Zenodo dataset DOI
or EDI repository URL — TODO].

Raw AIS data were obtained from [DATA PROVIDER — e.g., Spire Maritime / exactEarth /
Marine Cadastre] under [licence type — e.g., research licence number XXXXX]. The raw
AIS data cannot be publicly redistributed; access requests should be directed to
[PROVIDER URL]. The pipeline can be run on alternative AIS sources (e.g., Copernicus
Marine Service AIS, EMSA SafeSeaNet) following the instructions in
`documentation/VALIDATION_PROTOCOL.md`.

Seabed lithology data were obtained from the dbSEABED database via the HubOcean
STAC API. Carbon stock rasters are from Atwood et al. (2024) and are available at
[Atwood et al. data repository URL].

---

## Variant B — Partially embargoed (use if raw AIS redistribution is restricted)

Processed gridded outputs (SAR, dredging intensity fi_grid, carbon release index
C_ri_grid, OCIM Jdredge flux) are openly available at Zenodo (DOI:
10.5281/zenodo.PLACEHOLDER; LOEFFLER, 2026). The full pipeline code is available at
https://github.com/BenLFR/Master-thesis-code-.

Raw AIS data used in this study are subject to a [12-month / ongoing] embargo by
[PROVIDER] and cannot be shared. However, the code pipeline has been designed to
accept any AIS dataset following the input schema described in `documentation/README_PIPELINE_BELUGA.md`,
and synthetic validation confirms f_i recovery within ±15% on alternative AIS sources
(see `scripts_principaux/synthetic_validation.R`).

---

## Pre-submission checklist

- [ ] Deposit code to Zenodo and replace `PLACEHOLDER` DOI in:
      - `CITATION.cff`
      - `configuration/codemeta.json`
      - This document (both variants above)
- [ ] Archive `fi_grid_*.parquet` and `C_ri_grid_*.parquet` to Zenodo or EDI
- [ ] Confirm AIS data provider's redistribution policy
- [ ] Select Variant A or B above; delete the other variant
- [ ] Fill in all `[TODO]` placeholders above
- [ ] Verify all DOI links resolve before submission
- [ ] Cross-check with journal's Data Sharing Policy
      (Wiley/L&O:Methods: https://aslopubs.onlinelibrary.wiley.com/hub/journal/19415590/homepage/author-guidelines)

---

## References relevant to data sources

- Atwood, T.B. et al. (2024). Global distribution of seafloor sediment carbon stocks.
  *[Journal]* [DOI — fill in].
- Kroodsma, D.A. et al. (2018). Tracking the global footprint of fisheries.
  *Science* 359(6378), 904–908. https://doi.org/10.1126/science.aao5646
- Mitchell, A. et al. (20XX). dbSEABED: a database of seafloor sediment properties.
  [cite appropriately].
