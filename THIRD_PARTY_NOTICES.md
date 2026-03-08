# THIRD_PARTY_NOTICES

Last updated: 2026-03-08  
Source inputs:
- Manuscript: `Manuscript Paper 1 v1 - Benjamin LOEFFLER.docx`
- Extraction file: `output_V6/thesis_sync/paper1_extract_all.json`
- Repo policy docs: `docs/data_policy.md`, `data/README.md`

## Purpose

This file records third-party code, data, models, standards, and services used
or redistributed by this repository. It is intended to support public release,
citation, and legal review.

Status labels:
- `CONFIRMED`: license/terms are documented in repo docs and traceable.
- `PENDING_VERIFY`: mention exists, but upstream license/redistribution terms
  must be verified before public release.
- `REFERENCE_ONLY`: cited in manuscript but not redistributed in this repo.

## A) Bundled third-party code in repository

| ID | Component | Local path(s) | Evidence | License status | Required action before release |
|---|---|---|---|---|---|
| TP-CODE-001 | `inpaint_nans` by John D'Errico | `co2model/inpaint_nans.m` | Header contains `Author: John D'Errico`; MATLAB File Exchange page has explicit `View License` entry | PENDING_VERIFY | Capture exact upstream license text from the file-exchange license page and store URL + retrieval date. If not captured, remove from public bundle. |
| TP-CODE-002 | CSIRO Seawater `sw_pres` + license file | `co2model/sw_pres.m`, `co2model/sw_copy.m` | `sw_copy.m` retrieved and now present; includes full CSIRO licence terms | CONFIRMED | Keep attribution + full terms. For public release, treat as restrictive third-party licence: obtain explicit redistribution permission or move to external dependency download. |
| TP-CODE-003 | `mfactor` based on LINFACTOR (Timothy A. Davis) | `co2model/mfactor.m` | Header: `based on LINFACTOR`, `Copyright 2007` | PENDING_VERIFY | Confirm original license and include notice text. |
| TP-CODE-004 | MATLAB `CO2SYS` implementation | `co2model/CO2SYS.m` | Header cites Lewis and Wallace, Denis Pierrot, van Heuven | PENDING_VERIFY | Confirm redistribution terms from upstream distribution and include explicit license notice. |
| TP-CODE-005 | `nsgmres` by T. DeVries, based on C. T. Kelley | `co2model/nsgmres.m` | Header contains attribution | PENDING_VERIFY | Confirm license/permission and add notice text if redistributed. |

Source URLs used for TP-CODE-001 and TP-CODE-002:
- `inpaint_nans` page: https://www.mathworks.com/matlabcentral/fileexchange/4551-inpaint_nans
- MathWorks File Exchange licensing guidance: https://www.mathworks.com/help/matlab/matlab_prog/share-code-on-file-exchange.html
- CSIRO seawater `sw_copy.m` source (retrieved 2026-03-08): https://talleylab.ucsd.edu/sio210/propseawater/ppsw_matlab/sw_copy.m

Key legal note from `sw_copy.m`:
- licence is non-transferable and non-exclusive;
- copying is granted for the licensee's computing activity;
- distribution/transfer restrictions apply.

## B) External datasets/services mentioned in manuscript

| ID | Resource | Manuscript evidence | Current repo evidence | Terms status | Release requirement |
|---|---|---|---|---|---|
| TP-DATA-001 | Global Fishing Watch AIS data | Section `2. Methods`: AIS sourced from GFW | `data/README.md`, `docs/data_policy.md` mention GFW/ExactEarth alternatives | PENDING_VERIFY | Add final provider terms and explicit non-redistribution statement for raw AIS in release notes. |
| TP-DATA-002 | OpenStreetMap land polygons | Sections `2.2`, `2.9` mention OSM-derived land mask | `data/README.md` land-mask dependency | PENDING_VERIFY | Confirm exact OSM extract source/date and include ODbL attribution in public docs if distributed. |
| TP-DATA-003 | dbSEABED via HubOcean STAC | Section `2.7` | `docs/data_policy.md` lists dbSEABED via HubOcean | CONFIRMED | Keep attribution and upstream URL/DOI in final release metadata. |
| TP-DATA-004 | Longhurst provinces | Section `2.8` footnote | `docs/data_policy.md`, `data/README.md` | CONFIRMED | Keep attribution to VLIZ Marine Regions and version used. |
| TP-DATA-005 | Atwood sediment carbon stock dataset | Sections `2.6`, `2.9` | `docs/data_policy.md`, `data/README.md` (DOI placeholder and 10.5281/zenodo.3772915 mention) | PENDING_VERIFY | Confirm exact DOI/version cited in manuscript and archive manifest. |
| TP-DATA-006 | OCIM2-48L transport model assets | Section `2.9` | `data/README.md`, `configuration/ocim/*`, `Trawling model-*/OCIM2_48L_CTL.mat` | PENDING_VERIFY | Confirm redistribution permission for bundled `.mat` assets, or move to external download step. |
| TP-DATA-007 | Vessel technical specs (IDD 2021) | Section `2.2` | Mention in manuscript only | REFERENCE_ONLY | Keep bibliographic citation in manuscript references. |
| TP-STD-001 | ITU-R M.1371-6 AIS standard | Section `2.2` | Mention in manuscript only | REFERENCE_ONLY | Keep standard citation in manuscript references. |

## C) Third-party software dependencies explicitly mentioned

| ID | Dependency | Evidence | Distribution mode | Status |
|---|---|---|---|---|
| TP-SW-001 | R package `mclust` | Section `2.3`: "We used the Mclust package in R" | Dependency only (not vendored) | REFERENCE_ONLY |
| TP-SW-002 | MATLAB runtime/tooling for OCIM export | Section `2.9`: MATLAB `.mat` workflow | Dependency only (not vendored) | REFERENCE_ONLY |

## D) Manuscript to notice traceability

| Manuscript section | Mention in manuscript | Notice ID(s) |
|---|---|---|
| `2. Methods` | Global Fishing Watch (GFW) AIS source | TP-DATA-001 |
| `2.2 Multi-Stage AIS Cleaning Cascade` | OpenStreetMap land polygons, IDD 2021, ITU-R M.1371-6 | TP-DATA-002, TP-DATA-007, TP-STD-001 |
| `2.3 Feature Engineering & Gaussian Mixture Modelling` | Mclust package in R | TP-SW-001 |
| `2.7 Lithology assignment & labile fraction` | dbSEABED via HubOcean | TP-DATA-003 |
| `2.8 Labile Fraction Remineralization` | Longhurst provinces | TP-DATA-004 |
| `2.6` and `2.9` | Atwood carbon stock framework | TP-DATA-005 |
| `2.9 OCIM Grid Remapping and CO2 Forcing` | OCIM2-48L, MATLAB `.mat`, OpenStreetMap | TP-DATA-006, TP-SW-002, TP-DATA-002 |

## E) Draft regularization text (for legal closure)

These are draft texts to finalize once upstream license terms are verified.

### E.1 `inpaint_nans.m` (TP-CODE-001)

Proposed notice text:

> This repository includes `inpaint_nans.m`, authored by John D'Errico
> (Release 2, 2006-04-15). Source: `[SOURCE_URL]`, accessed `[ACCESS_DATE]`.
> Redistribution and use are subject to the original upstream license:
> `[LICENSE_NAME / LICENSE_URL]`. No warranty is provided by the original
> author; see upstream terms.

Minimum evidence to store in repo before switching to `CONFIRMED`:
- Upstream URL where the file was obtained.
- License text or explicit redistribution terms from upstream.
- Access date and version/release identifier.

### E.2 `sw_pres.m` (TP-CODE-002)

Proposed notice text:

> This repository includes `sw_pres.m` from the CSIRO Seawater library
> (Phil Morgan, 1993). The file header states:
> "See the file `sw_copy.m` for conditions of use and licence."
> Source: `[SOURCE_URL]`, accessed `[ACCESS_DATE]`.
> Redistribution and use follow the original CSIRO Seawater license terms
> documented in `sw_copy.m` (or official equivalent license page):
> `[LICENSE_URL]`.

Minimum evidence to store in repo before switching to `CONFIRMED`:
- Copy of `sw_copy.m` (or authoritative equivalent terms) in repo.
- Source URL and retrieval date for the seawater package.
- Confirmation that redistribution in this repository is allowed.

Current status update (2026-03-08):
- `sw_copy.m` is now present at `co2model/sw_copy.m`.
- Remaining blocker is explicit confirmation of redistribution rights for public release.

## Immediate legal closure checklist

- [x] Add root `LICENSE` file and align with `CITATION.cff`.
- [ ] Keep this notice file synced with manuscript and code updates.
- [ ] Resolve all `PENDING_VERIFY` items before public release.
- [ ] If any bundled third-party code/data cannot be redistributed, remove it
      from git and replace with scripted download instructions.
