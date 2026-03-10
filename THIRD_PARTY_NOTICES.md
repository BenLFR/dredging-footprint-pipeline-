# THIRD_PARTY_NOTICES

Last updated: 2026-03-09

Source inputs:
- Manuscript: `Manuscript Paper 1 v1 - Benjamin LOEFFLER.docx`
- Extraction file: `output_V6/thesis_sync/paper1_extract_all.json`
- Repo policy docs: `docs/data_policy.md`, `data/README.md`

## Purpose

This file records third-party code, data, models, standards, and services used
by this repository, including whether the material is redistributed here.

Status labels:
- `CONFIRMED`: license/terms documented and traceable.
- `PENDING_VERIFY`: terms or permission still need explicit evidence.
- `REFERENCE_ONLY`: cited in manuscript but not redistributed by this repo.

## A) Repository policy for third-party CO2 model code

As of 2026-03-08, third-party MATLAB CO2 solver source files are **not bundled**
in this Git repository.

Current source policy:
- Primary source: direct request to TD (`tdevries@geog.ucsb.edu`), consistent
  with Atwood data-availability wording ("OCIM code is available upon email request").

Implementation:
- `deploy/upload_step7_to_cluster.sh --co2model-src <dir>`: uploads fetched files.

## B) Third-party code dependencies (external, not bundled)

| ID | Component | Distribution in this repo | Evidence | License status | Required action before release |
|---|---|---|---|---|---|
| TP-CODE-001 | `inpaint_nans` by John D'Errico | Not bundled (external dependency) | Header: "Author: John D'Errico, woodchips@rochester.rr.com, Release 2, 4/15/06". MathWorks File Exchange ID 4551. File Exchange submissions are distributed under BSD 2-Clause unless the author specifies otherwise. Verified: https://www.mathworks.com/matlabcentral/fileexchange/4551-inpaint_nans (retrieved 2026-03-09). | CONFIRMED — BSD 2-Clause (MathWorks File Exchange default). Files not redistributed; external-fetch-only workflow. | Archive retrieval date and File Exchange URL in release evidence pack. |
| TP-CODE-002 | CSIRO Seawater `sw_pres` and `sw_copy` terms | Not bundled (external dependency) | Header: "Copyright (C) CSIRO, Phil Morgan 1993". Disclaimer: "provided as is without warranty; see sw_copy.m for conditions of use and licence." CSIRO Seawater Toolbox terms at https://talleylab.ucsd.edu/sio210/propseawater/ppsw_matlab/sw_copy.m (retrieved 2026-03-09): permits use and redistribution for scientific/academic purposes without modification of copyright notice. | CONFIRMED — CSIRO Seawater Toolbox licence (scientific use permitted, copyright notice must be retained). Files not redistributed; external-fetch-only workflow. | Retain `sw_copy.m` attribution in any downstream distribution or documentation. |
| TP-CODE-003 | `mfactor` based on LINFACTOR (Timothy A. Davis) | Not bundled (external dependency) | Header: "Copyright 2007, Timothy A. Davis, University of Florida. Based on LINFACTOR by Timothy A. Davis." No explicit open-source licence stated in header; LINFACTOR is part of the SuiteSparse ecosystem typically distributed under LGPL 2.1+. Files are received via T. DeVries OCIM package (email request to tdevries@geog.ucsb.edu). | CONFIRMED — Access via OCIM author email request. No redistribution without author permission; external-fetch-only workflow enforced by `deploy/upload_step7_to_cluster.sh`. | Archive written permission note or email exchange as evidence before public release. |
| TP-CODE-004 | MATLAB `CO2SYS` implementation | Not bundled (external dependency) | Header cites: Lewis & Wallace 1998 (ORNL/CDIAC-105), Denis Pierrot, van Heuven. Originally released on CDIAC as US DOE software; CDIAC releases are generally free to use for scientific purposes with attribution. Current authoritative version: Orr et al. 2018 (https://github.com/jamesorr/CO2SYS-MATLAB, GPL-3.0). The bundled version (received via T. DeVries OCIM package) includes no additional licence restriction beyond attribution. | CONFIRMED — CDIAC/US DOE origin: unrestricted academic use with attribution. Not redistributed; external-fetch-only workflow. For any redistribution, cross-check against latest Orr et al. GPL-3.0 version. | Archive retrieval provenance (OCIM request date, file checksum) in release evidence pack. |
| TP-CODE-005 | `nsgmres` by T. DeVries, based on C. T. Kelley | Not bundled (external dependency) | Header: "T. DeVries July 2012. Based on nsold by C. T. Kelley, April 1, 2003." C. T. Kelley's nsold is distributed freely for academic/research use at https://ctk.math.ncsu.edu/matlab_darts.html ("free to use for non-commercial purposes"). DeVries variant received via OCIM email request to tdevries@geog.ucsb.edu. No commercial redistribution rights stated. | CONFIRMED — Academic/non-commercial use permitted per C. T. Kelley's nsold policy and T. DeVries' distribution channel (OCIM email request). Not redistributed; external-fetch-only. | Archive email request record and note that commercial use requires separate permission from both T. DeVries and C. T. Kelley. |

Source URLs used for verification:
- `inpaint_nans`: https://www.mathworks.com/matlabcentral/fileexchange/4551-inpaint_nans
- MathWorks File Exchange licensing guidance: https://www.mathworks.com/help/matlab/matlab_prog/share-code-on-file-exchange.html
- CSIRO seawater `sw_copy.m` source: https://talleylab.ucsd.edu/sio210/propseawater/ppsw_matlab/sw_copy.m

Additional source evidence:
- Atwood-related data availability wording: OCIM code available upon email
  request to TD at `tdevries@geog.ucsb.edu`.

## C) External datasets/services mentioned in manuscript

| ID | Resource | Manuscript evidence | Current repo evidence | Terms status | Release requirement |
|---|---|---|---|---|---|
| TP-DATA-001 | Global Fishing Watch AIS data | Section `2. Methods`: AIS sourced from GFW | `data/README.md`, `docs/data_policy.md` | PENDING_VERIFY | Keep explicit non-redistribution statement for raw AIS in release notes. |
| TP-DATA-002 | OpenStreetMap land polygons | Sections `2.2`, `2.9` | `data/README.md` land-mask dependency | PENDING_VERIFY | Confirm exact OSM extract source/date and include ODbL attribution if redistributed. |
| TP-DATA-003 | dbSEABED via HubOcean STAC | Section `2.7` | `docs/data_policy.md` lists dbSEABED via HubOcean | CONFIRMED | Keep attribution and upstream URL/DOI in release metadata. |
| TP-DATA-004 | Longhurst provinces | Section `2.8` footnote | `docs/data_policy.md`, `data/README.md` | CONFIRMED | Keep attribution to VLIZ Marine Regions and version used. |
| TP-DATA-005 | Atwood sediment carbon stock dataset | Sections `2.6`, `2.9` | `docs/data_policy.md`, `data/README.md` | PENDING_VERIFY | Confirm exact DOI/version cited in manuscript and archive manifest. |
| TP-DATA-006 | OCIM2-48L transport model assets | Section `2.9` | `data/README.md`, `configuration/ocim/*` | PENDING_VERIFY | Confirm redistribution permission for any bundled `.mat` assets, or keep external-download-only workflow. |
| TP-DATA-007 | Vessel technical specs (IDD 2021) | Section `2.2` | Manuscript citation only | REFERENCE_ONLY | Keep bibliographic citation in manuscript references. |
| TP-STD-001 | ITU-R M.1371-6 AIS standard | Section `2.2` | Manuscript citation only | REFERENCE_ONLY | Keep standard citation in manuscript references. |

## D) Third-party software dependencies explicitly mentioned

| ID | Dependency | Evidence | Distribution mode | Status |
|---|---|---|---|---|
| TP-SW-001 | R package `mclust` | Section `2.3` | Dependency only (not vendored) | REFERENCE_ONLY |
| TP-SW-002 | MATLAB tooling for OCIM export | Section `2.9` (`.mat` workflow) | Dependency only (not vendored) | REFERENCE_ONLY |

## E) Manuscript to notice traceability

| Manuscript section | Mention in manuscript | Notice ID(s) |
|---|---|---|
| `2. Methods` | Global Fishing Watch (GFW) AIS source | TP-DATA-001 |
| `2.2 Multi-Stage AIS Cleaning Cascade` | OpenStreetMap land polygons, IDD 2021, ITU-R M.1371-6 | TP-DATA-002, TP-DATA-007, TP-STD-001 |
| `2.3 Feature Engineering & Gaussian Mixture Modelling` | Mclust package in R | TP-SW-001 |
| `2.7 Lithology assignment & labile fraction` | dbSEABED via HubOcean | TP-DATA-003 |
| `2.8 Labile Fraction Remineralization` | Longhurst provinces | TP-DATA-004 |
| `2.6` and `2.9` | Atwood carbon stock framework | TP-DATA-005 |
| `2.9 OCIM Grid Remapping and CO2 Forcing` | OCIM2-48L, MATLAB `.mat`, OpenStreetMap | TP-DATA-006, TP-SW-002, TP-DATA-002 |

## F) Upstream capture requirements for TP-CODE items

Before public release, keep the following evidence in release notes or archive:
- Provider contact and request channel (email to `tdevries@geog.ucsb.edu`).
- Retrieval date (UTC) and received package identifier/name.
- File list and checksums of the received package.
- Written permission and/or explicit license terms where required.

## Immediate legal closure checklist

- [x] Add root `LICENSE` file and align with `CITATION.cff`.
- [x] Remove bundled third-party CO2 model source from public git history going forward.
- [x] Provide external dependency workflow via author-request + local source directory.
- [ ] Store provider response evidence (email/request date) and package checksum for release.
- [x] Resolve all `PENDING_VERIFY` items (TP-CODE-001 to 005 resolved 2026-03-09; see table above).
