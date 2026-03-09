# GRIT Verification Checklist

Generated: 2026-03-09
Branch: `pub/v1.0-clean`
Purpose: Verify every open publication-readiness item on live GRIT hardware.
Run in order; earlier steps unblock later steps.

---

## Pre-flight (run locally before SSHing to GRIT)

```bash
# Push the branch so the clone test can reach it
git push origin pub/v1.0-clean
```

---

## B1 · git clone test (H7) — no pipeline data needed

```bash
cd /tmp
git clone https://github.com/BenLFR/Master-thesis-code- \
    --branch pub/v1.0-clean test_clone_pub
cd test_clone_pub
ls pipeline/step*/
ls LICENSE THIRD_PARTY_NOTICES.md config/fi_parameters.yaml
```

**Pass criteria:** clone exits 0; all listed files/directories present.

- [ ] H7 PASS / FAIL
  Notes: ___

---

## B2 · Confirm fi_parameters path + filename (C4)

```bash
ls ~/scratch/configuration/fi_parameters*.yaml
grep -n "fi_parameters\|CONFIG_DIR" \
    ~/test_clone_pub/pipeline/step5/step5_tile_worker.R | head -20
```

**Pass criteria:** file exists on GRIT AND script references a matching pattern via `CONFIG_DIR`.
If filename differs → rename `config/fi_parameters.yaml` in repo to match, push, re-test.

- [ ] C4 PASS / FAIL
  Actual filename on GRIT: ___
  Pattern in script: ___

---

## B3 · Confirm step3 YAML config path (M3)

```bash
grep -n "outlier_config\|CONFIG_DIR\|yaml" \
    ~/test_clone_pub/pipeline/step3/step3_merge.R | head -20
ls ~/scratch/configuration/outlier_config_V6.yaml
```

**Pass criteria:** script uses `CONFIG_DIR` env var; file exists in scratch.

- [ ] M3 PASS / FAIL
  Notes: ___

---

## B4 · Confirm co2model upload workflow (M1)

```bash
ls ~/scratch/co2model_vendor/ 2>/dev/null || echo "MISSING"
```

If MISSING:
```bash
# Fetch files from T. DeVries (tdevries@geog.ucsb.edu) then upload:
bash ~/test_clone_pub/deploy/upload_step7_to_cluster.sh \
    --co2model-src <local dir with .m files>
```

Then verify:
```bash
ls ~/scratch/co2model_vendor/
# Must contain: co2model.m CO2SYS.m sw_pres.m nsgmres.m mfactor.m inpaint_nans.m
```

**Pass criteria:** all 6 `.m` files present under `~/scratch/co2model_vendor/`.

- [ ] M1 PASS / FAIL
  Files found: ___

---

## B5 · renv restore test (H5)

```bash
module spider r         # find available R version
module load r/4.4.1     # or closest available
cd ~/test_clone_pub
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org')"
Rscript -e "renv::restore(lockfile='renv.lock', prompt=FALSE)"
Rscript -e "library(sf); library(terra); library(arrow);
            library(data.table); library(mclust); library(dbscan);
            cat('all OK\n')"
```

**Pass criteria:** all packages install; `all OK` printed; no missing-package errors.
If a package fails: note exact error → fix version pin in `renv.lock` → push → re-test.

- [ ] H5 PASS / FAIL
  R version loaded: ___
  Any failing packages: ___

---

## B6 · Python pip install test (H6)

```bash
module spider python
module load python/3.10   # or closest available
cd ~/test_clone_pub
pip install --user -r requirements.txt
python -c "import numpy, scipy, pyarrow; print('OK')"
```

**Pass criteria:** install exits 0; `OK` printed.
If a package fails: adjust pin in `requirements.txt` → push → re-test.

- [ ] H6 PASS / FAIL
  Python version loaded: ___
  Any failing packages: ___

---

## B7 · Real step3 dry-run (H3)

Requires: B5 passed and real preprocessed AIS data in `~/scratch/output_V6/`.

```bash
DRY_RUN=1 DRYRUN_N=50000 \
  CONFIG_DIR=~/scratch/configuration \
  OUTPUT_DIR=~/scratch/output_V6 \
  Rscript ~/test_clone_pub/pipeline/step3/step3_merge.R
ls ~/scratch/output_V6/AIS_data_core_preprocessed_V6_*.rds | tail -1
```

**Pass criteria:** exits 0; at least one `*_flagOK.rds` output file produced.

- [ ] H3 (step3) PASS / FAIL
  Output file: ___

---

## B8 · Real step5 single tile (H3)

Requires: B7 passed and step3 output exists.

```bash
CONFIG_DIR=~/scratch/configuration \
  OUTPUT_DIR=~/scratch/output_V6 \
  Rscript ~/test_clone_pub/pipeline/step5/step5_tile_worker.R 1
ls ~/scratch/output_V6/sar_001.parquet 2>/dev/null || echo "tile not produced"
```

**Pass criteria:** `sar_001.parquet` produced.

- [ ] H3 (step5) PASS / FAIL
  Notes: ___

---

## B9 · sbatch template submission (H2)

```bash
cd ~/test_clone_pub
cp config/templates/slurm/cluster_overrides.env.example \
   config/local/cluster_overrides.env
# Edit config/local/cluster_overrides.env with GRIT-specific paths, then:
source config/local/cluster_overrides.env
bash config/templates/slurm/submit_step.sh \
    pipeline/step6/step6_calculate_cri.sh
squeue -u bloe | grep step6
```

**Pass criteria:** job appears in queue (even if immediately queued/running).

- [ ] H2 PASS / FAIL
  Job ID: ___

---

## B10 · Full orchestrator run (H1) — run last

Requires: B1–B9 all passed; real data from step3 present.

```bash
cd ~/test_clone_pub
export PIPELINE_DIR=$(pwd)
export SCRATCH_DIR=~/scratch
export OUTPUT_DIR=~/scratch/output_V6
export CONFIG_DIR=~/scratch/configuration
export LOGS_DIR=~/logs
bash pipeline/run_pipeline.sh --from-step 0
squeue -u bloe
tail -f ~/logs/pipeline_run_*.txt
```

**Pass criteria:** jobs chain in SLURM; each step produces outputs in `~/scratch/output_V6/`.

- [ ] H1 PASS / FAIL
  Notes: ___

---

## Post-session actions

For each item marked PASS above:
- Update `documentation/PUBLIC_READINESS_TRACKER.md` accordingly.

For each item marked FAIL:
- Create a targeted fix commit → push → re-test the specific B-item.

Final commit message:
```
docs: mark GRIT verification results in checklist
```
