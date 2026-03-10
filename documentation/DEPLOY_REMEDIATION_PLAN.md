# Deploy Folder Remediation Plan

Last updated: 2026-03-10
Scope: `deploy/` on branch `pub/v1.0-clean`
Status: completed for the public release surface

---

## 1) Objective

Turn `deploy/` into a publication-safe, generic HPC deployment pack.

The public repository must not expose:

- real hostnames,
- real usernames,
- personal workstation paths,
- SSH key filenames,
- site-private operational notes,
- comments or examples that only make sense on one cluster.

The public repository must provide:

- generic Slurm templates,
- generic SSH and `rsync` workflow patterns,
- explicit environment variables,
- fail-fast scripts,
- English-only documentation and comments,
- an explicit preflight, transfer, submit, fetch, provenance, and cleanup path.

---

## 2) Delivered public surface

Public entry points now retained in `deploy/`:

- `config.example.env`
- `preflight_hpc.sh`
- `hpc_ping.sh`
- `hpc_sync.sh`
- `hpc_submit.sh`
- `hpc_fetch.sh`
- `capture_sacct.sh`
- `cleanup_scratch.sh`
- `run_full_pipeline.sh`
- `upload_postproc_assets.sh`
- `upload_step6_assets.sh`
- `upload_step7_assets.sh`

Public documentation now retained in `deploy/`:

- `README.md`
- `SETUP_GENERIC.md`
- `HPC_WORKFLOW_GENERIC.md`
- `TRANSFER_POLICY.md`
- `HPC_OPERATIONS_CHECKLIST.md`
- `STEP0_GUIDE.md`
- `STEP2_ONLAND_TUNING.md`

Public scheduler and container assets now retained in `deploy/`:

- `apptainer.def`
- `slurm_job.template.sbatch`
- `slurm_array.template.sbatch`
- `slurm_signal_safe.template.sbatch`

---

## 3) Legacy surface removed

Site-specific aliases, duplicate transition notes, and compatibility-only
wrappers were removed from the public branch because they no longer add value to
the public interface.

The deploy surface is now generic by filename and by content.

---

## 4) HPC best-practice closure

The public `deploy/` folder now encodes the following practices:

1. Login nodes are used for setup, transfer, checks, and submission only.
2. Scratch-first staging is explicit via `HPC_SCRATCH`.
3. Slurm submission uses explicit working directories, stdout, stderr, and
   export policy.
4. Job arrays and dependencies are exposed through public templates and submit
   options.
5. Scheduler accounting capture is explicit through `capture_sacct.sh`.
6. Scratch stage-out and cleanup are explicit through `cleanup_scratch.sh`.
7. Transfer preview and checksum-validated modes are documented in
   `TRANSFER_POLICY.md`.
8. The operational run lifecycle is documented in
   `HPC_OPERATIONS_CHECKLIST.md`.

---

## 5) Verification completed

Static verification completed for the public deploy surface:

1. Forbidden-content sanitation grep on `deploy/`: passed.
2. Forbidden legacy filenames in `deploy/`: removed.
3. English-only runbook rewrite for retained `deploy/` docs: completed.
4. Dedicated static deploy audit added: `tests/deploy_sanitation_check.py`.
5. CI shell syntax checks added for `deploy/*.sh` and
   `config/templates/slurm/submit_step.sh`.

Remaining verification intentionally tracked elsewhere:

- live cluster execution evidence belongs to Phase 5 of the master public
  readiness plan,
- site-specific smoke tests remain cluster-dependent and are not encoded in the
  public branch itself.

---

## 6) Closure decision

The `deploy/` blocker is closed for the public release branch.

Remaining portability work for Gate G2 is now outside `deploy/`, primarily in
the canonical `pipeline/`, `postproc/`, and related reviewer-facing scripts.

---

## 7) Reference basis used for this plan update

Official sources reviewed on 2026-03-10:

- Slurm `sbatch`: https://slurm.schedmd.com/sbatch.html
- Slurm job arrays: https://slurm.schedmd.com/job_array.html
- Slurm accounting with `sacct`: https://slurm.schedmd.com/sacct.html
- Slurm signal handling notes in `scancel`: https://slurm.schedmd.com/scancel.html
- Apptainer definition file guidance: https://apptainer.org/user-docs/3.4/definition_files.html
- Apptainer bind path guidance: https://apptainer.org/docs/user/1.1/bind_paths_and_mounts.html
- NERSC login-node and resource-usage policy: https://docs.nersc.gov/policies/resource-usage/
- NERSC scratch policy: https://docs.nersc.gov/filesystems/perlmutter-scratch/
- NERSC job best practices: https://docs.nersc.gov/jobs/best-practices/
- Alliance Canada META-Farm guidance: https://docs.alliancecan.ca/wiki/META%3A_A_package_for_job_farming
- `rsync` manual: https://download.samba.org/pub/rsync/rsync.1