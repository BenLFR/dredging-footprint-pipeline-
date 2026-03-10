# Deploy Folder Remediation Plan

Last updated: 2026-03-10
Scope: `deploy/` on branch `pub/v1.0-clean`
Status: planning baseline

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

The public repository should provide:
- generic Slurm templates,
- generic SSH/rsync workflow patterns,
- explicit environment variables,
- fail-fast scripts,
- English-only documentation and comments.

---

## 2) Release rules for `deploy/`

1. Public `deploy/` content must target a generic Slurm cluster, not GRIT as a hard-coded site.
2. Site-specific values must come from environment variables or a non-versioned local config file.
3. No real SSH key name, SSH config path, hostname, username, or absolute personal path may remain in tracked `deploy/` files.
4. Documentation examples must use placeholders such as `<HPC_HOST>` or environment variables such as `${HPC_HOST}`.
5. Comments, messages, and docs must be English-only, with no emoji and no stale operational notes.

## 2.1) Official HPC best-practice additions

The public `deploy/` folder should also encode the following HPC practices, based on official scheduler, container, storage, and transfer documentation reviewed on 2026-03-10:

1. Login nodes are for environment preparation, compilation, lightweight preprocessing, and job submission only. Production compute must run through batch or interactive allocations.
2. Production runs and temporary high-I/O data should stage to site scratch storage via environment variables such as `SCRATCH`, not via hard-coded home-directory paths. Scratch must be treated as purgeable temporary storage.
3. Public Slurm templates must set an explicit working directory and explicit stdout/stderr destinations. They must not rely on implicit file movement or the caller's shell state.
4. Environment propagation must be explicit. Public submit wrappers should define how variables are exported into jobs instead of depending on hidden shell inheritance.
5. Job arrays and job dependencies should be first-class public templates for embarrassingly parallel steps and step chaining.
6. Worker jobs must not poll the scheduler aggressively. Any orchestration must avoid repeated `squeue`, `sbatch`, or similar calls from many tasks.
7. Deploy assets should capture job provenance and accounting after execution, including job IDs, states, exit codes, elapsed time, memory, and CPU allocation.
8. Public batch templates should support signal trapping or cleanup hooks so cancellation and timeout handling are not silent failure modes.
9. Containers must be built from definition files, documented, and configured with explicit bind paths. Runtime assets should not be installed under `/home` or temporary bind-prone locations inside the image.
10. Transfer wrappers should use `rsync`-style archive semantics, provide a dry-run mode, and offer optional checksum-based validation for high-value transfers.
11. Every public deploy workflow should include a small smoke-test path before production execution.

---

## 3) Workstreams

## Workstream A - Remove infrastructure identifiers

Goal: eliminate public exposure of site-specific operational details.

Files in scope:
- `deploy/README.md`
- `deploy/GRIT_WORKFLOW.md`
- `deploy/GRIT_CHEATSHEET.md`
- `deploy/SETUP.md`
- `deploy/STEP0_GUIDE.md`
- `deploy/UPLOAD_AND_RUN_STEP0.md`
- `deploy/check_grit_setup.sh`
- `deploy/fetch_results.sh`
- `deploy/run_on_grit.sh`
- `deploy/sync_to_grit.sh`
- `deploy/sync_to_grit_scp.sh`
- `deploy/test_connection.sh`
- `deploy/upload_postproc_to_grit.sh`
- `deploy/upload_step6_to_grit.sh`
- `deploy/upload_step7_to_grit.sh`
- `deploy/upload_step7_to_cluster.sh`

Required actions:
1. Replace hard-coded GRIT hostnames, users, and remote paths with variables such as `HPC_HOST`, `HPC_USER`, `HPC_BASEDIR`, `HPC_SCRATCH`, `SSH_CONFIG_FILE`, and `SSH_KEY_PATH`.
2. Remove any real SSH key filename from examples and replace it with generic placeholders.
3. Remove personal local paths, including Windows workstation paths and machine-name references.
4. Replace cluster-specific wording with site-neutral wording unless the file is explicitly marked private and removed from the public branch.

Exit criteria:
- `rg -n "grit|beluga|/home/|C:/Users|OneDrive|id_ed25519|id_rsa|config_grit" deploy` returns no release-blocking hit in public files.

## Workstream B - Convert scripts into generic templates

Goal: make deploy scripts reusable on any Slurm cluster with explicit configuration.

Files in scope:
- `deploy/check_grit_setup.sh`
- `deploy/fetch_results.sh`
- `deploy/run_on_grit.sh`
- `deploy/sync_to_grit.sh`
- `deploy/sync_to_grit_scp.sh`
- `deploy/test_connection.sh`
- `deploy/upload_postproc_to_grit.sh`
- `deploy/upload_step6_to_grit.sh`
- `deploy/upload_step7_to_grit.sh`
- `deploy/upload_step7_to_cluster.sh`
- `deploy/run_full_pipeline.sh`

Required actions:
1. Standardize shell safety with `set -euo pipefail`.
2. Introduce a shared configuration contract:
   - `HPC_HOST`
   - `HPC_USER`
   - `HPC_BASEDIR`
   - `HPC_SCRATCH`
   - `SLURM_PARTITION`
   - `SLURM_ACCOUNT`
   - `SSH_CONFIG_FILE` or `RSYNC_RSH`
3. Add fail-fast checks for required variables.
4. Ensure no script assumes a fixed remote directory layout unless set by variables.
5. Rename or rewrite GRIT-specific wrappers so their public role is clearly generic.
6. Use explicit working-directory, log-path, and output-path handling in public submit wrappers.
7. Prefer Slurm arrays and dependencies over ad hoc orchestration or scheduler-polling loops.

Deliverables:
- `deploy/config.example.env`
- `deploy/hpc_sync.sh`
- `deploy/hpc_submit.sh`
- `deploy/hpc_fetch.sh`
- `deploy/hpc_ping.sh`
- optional compatibility wrappers that only call the new generic scripts

Exit criteria:
- all public deploy scripts run with placeholder-driven configuration only,
- no public script requires editing hard-coded values before use.

## Workstream C - Rewrite documentation as public runbooks

Goal: keep useful deployment guidance without publishing private operational practice.

Files in scope:
- `deploy/README.md`
- `deploy/GRIT_WORKFLOW.md`
- `deploy/GRIT_CHEATSHEET.md`
- `deploy/SETUP.md`
- `deploy/STEP0_GUIDE.md`
- `deploy/STEP2_ONLAND_TUNING.md`
- `deploy/UPLOAD_AND_RUN_STEP0.md`

Required actions:
1. Rewrite all docs in English-only public style.
2. Replace GRIT-specific instructions with generic Slurm instructions.
3. Move cluster-private notes out of the public branch, or replace them with a short statement that site-specific notes are intentionally excluded.
4. Add one short table of variables that users must adapt for their site.
5. Remove obsolete or misleading comments and examples.
6. Document login-node vs compute-node responsibilities.
7. Document scratch staging, purge risk, and required stage-out behavior.
8. Document a smoke-test workflow that must be run before production submissions.

Target documentation set:
- `deploy/README.md` as the main public entry point
- `deploy/HPC_WORKFLOW_GENERIC.md` for generic cluster execution
- `deploy/SETUP_GENERIC.md` for prerequisites and smoke tests
- `deploy/STEP0_GUIDE.md` only if it can be kept generic and data-policy compliant

Exit criteria:
- the deploy documentation is understandable without knowing GRIT,
- no public doc leaks personal or institutional operational details.

## Workstream D - Harden the container and scheduler templates

Goal: keep the portable execution layer reproducible and reviewable.

Files in scope:
- `deploy/apptainer.def`
- `config/templates/slurm/submit_step.sh`
- new public Slurm template files under `deploy/` or `config/templates/slurm/`

Required actions:
1. Pin base images and document tested versions where missing.
2. Ensure container instructions reference repository-managed lockfiles only.
3. Provide a minimal generic Slurm template with commented optional fields for partition and account.
4. Remove any scheduler directive that encodes a personal or site-private default.
5. Provide dedicated public templates for arrays, dependencies, and signal-safe jobs.
6. Make bind-path configuration explicit through `APPTAINER_BINDPATH`, CLI flags, or documented wrapper variables.
7. Add container help and usage metadata where missing.

Exit criteria:
- public scheduler templates are neutral,
- container build instructions are deterministic enough for reviewer reruns.

## Workstream E - Verification and release gating

Goal: prove that the sanitized `deploy/` folder matches the public-release standard.

Required actions:
1. Add a lightweight audit script or CI check for forbidden patterns in `deploy/`.
2. Run a manual review of all changed files after templating.
3. Update the public readiness tracker with a dedicated `deploy/` status line.
4. Record any intentionally retained cluster-specific term and justify it explicitly.
5. Add a grep-based check that public worker scripts do not query the scheduler in tight loops.
6. Archive `sacct` outputs or equivalent scheduler accounting summaries as reproducibility evidence.

Verification checks:
- forbidden-pattern grep on `deploy/`
- shell syntax check on all `deploy/*.sh`
- manual spot-check that docs are English-only and placeholder-based

Exit criteria:
- `deploy/` no longer blocks public release,
- deploy-specific findings are closed in the readiness tracker.

## Workstream F - Operational safeguards and provenance

Goal: turn `deploy/` into a reliable job-lifecycle toolkit rather than a collection of one-off launchers.

Required actions:
1. Add `deploy/preflight_hpc.sh` to validate required variables, destination directories, local prerequisites, and scratch targets before any sync or submit step.
2. Add a public pattern for preparing the runtime environment on a login node before submission, then launching the batch job with an explicit export policy.
3. Add `deploy/capture_sacct.sh` to collect scheduler accounting fields after completion, at minimum `JobID`, `State`, `ExitCode`, `Elapsed`, `AllocCPUS`, and `MaxRSS` where available.
4. Add a documented stage-out and scratch-cleanup pattern so temporary files do not silently remain in purgeable storage.
5. Add a smoke-test submission path for toy data or a reduced-size run before production-scale submission.
6. Add a transfer policy that distinguishes:
   - dry-run sync,
   - production sync,
   - optional checksum-validated sync for release-critical files.

Deliverables:
- `deploy/preflight_hpc.sh`
- `deploy/capture_sacct.sh`
- `deploy/cleanup_scratch.sh` or an equivalent documented stage-out script
- `deploy/TRANSFER_POLICY.md`
- `deploy/HPC_OPERATIONS_CHECKLIST.md`

Exit criteria:
- the public deploy layer supports preflight, submit, monitor, collect, and clean up as explicit stages,
- release evidence includes scheduler accounting and transfer verification outputs.

---

## 4) File-by-file priority

### Priority 0 - Immediate blockers

- `deploy/README.md`
- `deploy/GRIT_WORKFLOW.md`
- `deploy/STEP0_GUIDE.md`
- `deploy/UPLOAD_AND_RUN_STEP0.md`
- `deploy/check_grit_setup.sh`
- `deploy/run_on_grit.sh`
- `deploy/sync_to_grit.sh`
- `deploy/fetch_results.sh`
- `deploy/upload_step7_to_grit.sh`

Action: rewrite or template first, before any public release candidate.

### Priority 1 - Core deploy scripts and docs

- `deploy/sync_to_grit_scp.sh`
- `deploy/test_connection.sh`
- `deploy/upload_postproc_to_grit.sh`
- `deploy/upload_step6_to_grit.sh`
- `deploy/upload_step7_to_cluster.sh`
- `deploy/SETUP.md`
- `deploy/GRIT_CHEATSHEET.md`
- `deploy/STEP2_ONLAND_TUNING.md`

Action: convert to generic wrappers or fold into the new generic toolset.

### Priority 2 - Portable infrastructure assets

- `deploy/apptainer.def`
- `config/templates/slurm/submit_step.sh`
- `deploy/run_full_pipeline.sh`

Action: harden, neutralize defaults, and document expected variables.

---

## 5) Target end-state for `deploy/`

Minimum public structure:
- `deploy/README.md`
- `deploy/config.example.env`
- `deploy/preflight_hpc.sh`
- `deploy/hpc_ping.sh`
- `deploy/hpc_sync.sh`
- `deploy/hpc_submit.sh`
- `deploy/hpc_fetch.sh`
- `deploy/capture_sacct.sh`
- `deploy/cleanup_scratch.sh`
- `deploy/HPC_WORKFLOW_GENERIC.md`
- `deploy/SETUP_GENERIC.md`
- `deploy/HPC_OPERATIONS_CHECKLIST.md`
- `deploy/TRANSFER_POLICY.md`
- `deploy/apptainer.def`
- `deploy/slurm_job.template.sbatch`
- `deploy/slurm_array.template.sbatch`
- `deploy/slurm_signal_safe.template.sbatch`

Files to deprecate, rewrite, or remove from the public branch:
- GRIT-only guides that cannot be made generic
- one-off upload wrappers that duplicate the new generic scripts
- any file that still exists only to document a personal workflow

---

## 6) Sequence of execution

1. Audit and mark every `deploy/` file as keep, rewrite, replace, or remove.
2. Create the shared variable contract and `config.example.env`.
3. Add the preflight, transfer, provenance, and cleanup building blocks required by the public HPC lifecycle.
4. Replace GRIT-specific shell scripts with generic wrappers.
5. Rewrite the public docs around the generic workflow.
6. Harden `apptainer.def` and Slurm templates.
7. Add forbidden-pattern, scheduler-query, and shell syntax checks.
8. Run smoke tests, transfer dry-runs, and accounting capture on the public workflow.
9. Update the master readiness tracker and close the `deploy/` blocker.

---

## 7) Definition of done

The `deploy/` folder is considered corrected only when all are true:
1. No real infrastructure identifier remains in tracked public deploy files.
2. Public scripts are driven by environment variables or documented CLI arguments.
3. Public docs describe a generic Slurm workflow, not a private GRIT workflow.
4. The container and scheduler templates are neutral and reviewer-usable.
5. The folder includes preflight, stage, submit, fetch, provenance, and cleanup guidance as explicit public steps.
6. The folder passes grep-based sanitation checks, shell syntax checks, scheduler-query checks, and manual English-only review.

---

## 8) Reference basis used for this plan update

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
- rsync manual: https://download.samba.org/pub/rsync/rsync.1
