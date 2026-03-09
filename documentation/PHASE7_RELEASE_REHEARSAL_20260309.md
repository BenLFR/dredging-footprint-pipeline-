# Phase 7 Release Rehearsal (2026-03-09)

## Goal

Execute the phase-7 validation set:

1. CI-quality checks (testthat + benchmark regression guard),
2. clean-checkout quickstart on toy data,
3. HPC template path validation without proprietary data.

## Local worktree validation (pub/v1.0-clean)

Executed successfully:

1. `Rscript tests/run_testthat.R`
2. `Rscript tests/benchmark_regression_guard.R`
3. `Rscript tests/hpc_template_path_check.R`
4. `Rscript tests/smoke_test_steps2_5.R`
5. `Rscript tests/smoke_test_steps3_6_entrypoints.R`

Observed results:

1. testthat suite: PASS
2. benchmark guard: PASS (`entrypoints_smoke` runtime below threshold)
3. HPC template path check: PASS
4. toy smoke (steps 2-5): PASS
5. entrypoint smoke (steps 3-6): PASS

## Clean-checkout rehearsal

Direct local `git clone` failed on this Windows environment due Git-for-Windows
runtime error (`couldn't create signal pipe, Win32 error 5`).  
Fallback used: fresh filesystem copy of the worktree without `.git` metadata.

Executed in clean copy:

1. `Rscript tests/run_testthat.R`
2. `Rscript tests/benchmark_regression_guard.R`
3. `Rscript tests/hpc_template_path_check.R`
4. `Rscript tests/smoke_test_steps2_5.R`

All checks passed.

## HPC template rehearsal details

Because `bash` runtime is unavailable in this environment, runtime `sbatch`
submission could not be executed directly.  
Static validation was enforced through:

1. `tests/hpc_template_path_check.R`
2. testthat checks in `tests/testthat/test_phase7_quality.R`

These checks confirm:

1. required template files exist,
2. expected `SBATCH_*` override hooks are present,
3. no hard-coded cluster host/user tokens in template files.

## Conclusion

Phase-7 rehearsal checks pass for code integrity and documentation consistency.
Final release readiness still depends on FAIR closure items documented in
`documentation/RELEASE_VERDICT_20260309.md`.

Strict evidence note:

1. This rehearsal is not sufficient to close G2 without GRIT runtime proof.
2. Use `documentation/GRIT_VERIFICATION_CHECKLIST_20260309.md` as the required
   closure protocol.
