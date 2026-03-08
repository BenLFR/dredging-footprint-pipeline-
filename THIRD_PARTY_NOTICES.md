# THIRD_PARTY_NOTICES

Last updated: 2026-03-08

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
| TP-CODE-001 | `inpaint_nans` by John D'Errico | Not bundled (external dependency) | File header attribution in upstream; MATLAB File Exchange page has explicit `View License` entry | PENDING_VERIFY | Record exact upstream license/terms URL and retrieval date in release evidence pack. |
| TP-CODE-002 | CSIRO Seawater `sw_pres` and `sw_copy` terms | Not bundled (external dependency) | `sw_pres` header points to `sw_copy` terms; CSIRO license text available upstream | PENDING_VERIFY | Store explicit redistribution/permission evidence or keep external-fetch-only policy. |
| TP-CODE-003 | `mfactor` based on LINFACTOR (Timothy A. Davis) | Not bundled (external dependency) | Upstream header attribution | PENDING_VERIFY | Confirm original license and document permission basis. |
| TP-CODE-004 | MATLAB `CO2SYS` implementation | Not bundled (external dependency) | Upstream header cites Lewis and Wallace, Denis Pierrot, van Heuven | PENDING_VERIFY | Confirm redistribution terms from authoritative upstream source. |
| TP-CODE-005 | `nsgmres` by T. DeVries, based on C. T. Kelley | Not bundled (external dependency) | Upstream header attribution | PENDING_VERIFY | Confirm license/permission and archive notice text. |

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
- [ ] Resolve all `PENDING_VERIFY` items before public release.
