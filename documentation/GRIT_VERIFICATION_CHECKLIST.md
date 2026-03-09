# GRIT Verification Checklist

Generated: 2026-03-09 | Updated: 2026-03-09
Branch: `pub/v1.0-clean`
Session: live GRIT verification on `hpc-05`

---

## B1 · git clone (H7)

- [x] **PASS** — verified locally (Windows). All files present: `pipeline/step0-7/`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `config/fi_parameters.yaml`.
- ⚠️ GRIT clone blocked: repo is **private**. Must go public before release. This is a release prerequisite, not a blocker for further GRIT testing.

---

## B2 · fi_parameters path (C4)

- [x] **PASS**
  - File on GRIT: `~/scratch/configuration/fi_parameters_with_freshness.yaml` ✅
  - `step5_tile_worker.R` hardcodes that exact path ✅

---

## B3 · step3 outlier_config path (M3)

- [x] **PASS** (after fix)
  - File on GRIT: `~/ais-pipeline/configuration/outlier_config_V6.yaml` ✅
  - `step3_merge.R` patched: hardcoded `~/R_scripts/configuration/` → `CONFIG_DIR` env var (default `~/ais-pipeline/configuration`) ✅
  - Fix committed: `45090fa`

---

## B4 · co2model files (M1)

- [x] **PASS**
  - All 6 `.m` files present at `~/scratch/configuration/ocim/`:
    `co2model.m`, `CO2SYS.m`, `sw_pres.m`, `nsgmres.m`, `mfactor.m`, `inpaint_nans.m` ✅

---

## B5 · R packages (H5)

- [x] **PASS**
  - No module system on `hpc-05` — R installed system-wide
  - `mclust` + `dbscan` installed to `~/R/library`
  - Verified: `R_LIBS_USER=~/R/library Rscript -e "library(sf); library(terra); library(arrow); library(data.table); library(mclust); library(dbscan); cat('all OK\n')"` → **all OK**

---

## B6 · Python packages (H6)

- [x] **PASS**
  - No module system — Python 3.12 system-wide (Debian managed)
  - Venv created at `~/venv_pipeline`
  - `numpy 2.4.3`, `scipy 1.17.1`, `pyarrow 23.0.1` installed ✅
  - `import numpy, scipy, pyarrow; print('OK')` → **OK**

---

## B7 · step3 dry-run (H3)

- [ ] **SKIP — blocked on H7 (repo private)**
  - Cannot clone pub branch on GRIT to run pub scripts
  - Mitigating evidence: `~/scratch/output_V6/AIS_data_core_preprocessed_V6_20260304_100917_flagOK.rds` exists from prior successful full pipeline run
  - Unblock: make repo public → clone → rerun

---

## B8 · step5 single tile (H3)

- [ ] **SKIP — blocked on H7 (repo private)**
  - Same blocker as B7
  - Mitigating evidence: `~/scratch/output_V6/sar_*.parquet` tiles exist from prior run

---

## B9 · sbatch template (H2)

- [ ] **SKIP — blocked on H7 (repo private)**
  - Cannot test pub branch SLURM templates without clone

---

## B10 · Full orchestrator (H1)

- [ ] **SKIP — blocked on H7 (repo private)**
  - Mitigating evidence: full pipeline run completed successfully on 2026-03-04 (outputs in `~/scratch/output_V6/`)

---

## Remaining blockers before release

| Blocker | Action |
|---------|--------|
| Repo is private (H7) | Make GitHub repo public → re-run B1 on GRIT, unblocks B7–B10 |
| Zenodo DOI placeholder | Reserve DOI on Zenodo, update `CITATION.cff` |
| ORCID placeholder in `CITATION.cff` | Add ORCID before submission |

---

## Fixes applied during this session

| Commit | Fix |
|--------|-----|
| `1c60296` | A1–A4: CITATION.cff date, nodelist, fi_parameters.yaml, THIRD_PARTY_NOTICES |
| `9d423f9` | step3 outlier_config path + config/outlier_config_V6.yaml added |
| `45090fa` | CONFIG_DIR default corrected to `~/ais-pipeline/configuration` |
| `14587b5` | step3_merge.sh replaced with 256G version (only supported config) |
