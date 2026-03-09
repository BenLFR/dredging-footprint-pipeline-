# GRIT Verification Checklist (Evidence-Based)

Date: 2026-03-09  
Branch target: `pub/v1.0-clean`

## Objective

Produce hard evidence on GRIT that pipeline claims are accurate and not based on
local-only assumptions.

## Required evidence bundle

Create one folder on GRIT for all proof artifacts:

```bash
mkdir -p ~/ais-pipeline/evidence/20260309
```

All commands below must append outputs to files in that folder.

## 1. Preflight: repository and environment

Run on GRIT login node:

```bash
cd ~/ais-pipeline
git fetch origin
git checkout pub/v1.0-clean
git pull --ff-only origin pub/v1.0-clean
git rev-parse HEAD | tee evidence/20260309/git_head.txt
which Rscript | tee evidence/20260309/rscript_path.txt
Rscript --version | tee evidence/20260309/r_version.txt
python3 --version | tee evidence/20260309/python_version.txt
```

PASS criteria:

1. Branch is `pub/v1.0-clean`.
2. Commit hash recorded.
3. R and Python versions recorded.

## 2. Canonical-path integrity check

```bash
cd ~/ais-pipeline
ls -1 pipeline/step0_core_window.R \
      pipeline/step1_split_navires.R \
      pipeline/step2_process_navire.R \
      pipeline/step3_merge_final.R \
      pipeline/step4_add_lithology.R \
      pipeline/step5_merge_tiles.R \
      pipeline/step6_calculate_cri.R \
      pipeline/step7_export_jtrawl.sh \
      step7_export_jtrawl.R \
  | tee evidence/20260309/canonical_paths.txt
```

PASS criteria:

1. All listed files exist.

## 3. Static smoke checks on GRIT

```bash
cd ~/ais-pipeline
Rscript tests/smoke_test_steps3_6_entrypoints.R \
  | tee evidence/20260309/smoke_steps3_6.txt
Rscript tests/run_testthat.R \
  | tee evidence/20260309/testthat.txt
Rscript tests/benchmark_regression_guard.R \
  | tee evidence/20260309/benchmark_guard.txt
```

PASS criteria:

1. Each command returns exit code 0.
2. Output files contain `[PASS]` markers.

## 4. Real HPC template submission test (required)

Create cluster override file:

```bash
cd ~/ais-pipeline
mkdir -p config/local
cp config/templates/slurm/cluster_overrides.env.example config/local/cluster_overrides.env
```

Edit `config/local/cluster_overrides.env` with actual GRIT values, then run:

```bash
cd ~/ais-pipeline
source config/local/cluster_overrides.env
bash config/templates/slurm/submit_step.sh pipeline/step6_calculate_cri.sh \
  | tee evidence/20260309/sbatch_step6_submit.txt
```

Record job status/logs:

```bash
squeue -u "$USER" | tee evidence/20260309/squeue_after_submit.txt
# Replace <jobid> with returned id:
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS \
  | tee evidence/20260309/sacct_step6.txt
```

PASS criteria:

1. `sbatch` accepts the job.
2. Job reaches `COMPLETED` with `ExitCode 0:0`.

## 5. Runtime path proof for steps 4-7

Submit and verify each wrapper:

```bash
cd ~/ais-pipeline
source config/local/cluster_overrides.env
bash config/templates/slurm/submit_step.sh pipeline/step4_add_lithology.sh | tee evidence/20260309/sbatch_step4_submit.txt
bash config/templates/slurm/submit_step.sh pipeline/step5_merge_slurm.sh   | tee evidence/20260309/sbatch_step5_submit.txt
bash config/templates/slurm/submit_step.sh pipeline/step6_calculate_cri.sh | tee evidence/20260309/sbatch_step6_submit_repeat.txt
bash config/templates/slurm/submit_step.sh pipeline/step7_export_jtrawl.sh | tee evidence/20260309/sbatch_step7_submit.txt
```

For each job, capture `sacct` and tail logs to evidence files.

PASS criteria:

1. All 4 wrappers submit.
2. Each job finishes with successful state.
3. Expected output files appear in `OUTPUT_DIR`.

## 6. Step3 correctness probe (t_seuil / adaptive threshold)

Run Step3 and export summary diagnostics:

```bash
cd ~/ais-pipeline
Rscript -e "x <- readLines('pipeline/step3_merge_final.R'); \
            cat(sum(grepl('t_seuil <-', x)), '\n'); \
            cat(sum(grepl('threshold_adaptive', x)), '\n'); \
            cat(sum(grepl('seuil_adaptatif', x)), '\n')" \
  | tee evidence/20260309/step3_code_tokens.txt
```

Then run real step3 job and inspect filtering metrics in logs.

PASS criteria:

1. No runtime error in Step3.
2. Filtering metrics are plausible and documented.
3. Any mismatch between `threshold_adaptive` and `seuil_adaptatif` is resolved
   or explicitly justified.

## 7. Clean clone proof on GRIT

```bash
cd ~
rm -rf ais-pipeline-fresh
git clone -b pub/v1.0-clean https://github.com/BenLFR/Master-thesis-code-.git ais-pipeline-fresh
cd ais-pipeline-fresh
Rscript tests/smoke_test_steps3_6_entrypoints.R | tee evidence_clone_smoke.txt
```

PASS criteria:

1. Real `git clone` succeeds.
2. Smoke command passes in the fresh clone.

## 8. Final signoff template

Create `evidence/20260309/SIGNOFF.md` with:

1. Date/time and operator.
2. Commit hash tested.
3. PASS/FAIL for sections 1-7.
4. Links to all evidence files.
5. Open issues and blockers.
