# GRIT Audit Flags by Confidence

Date: 2026-03-09  
Scope: `pub/v1.0-clean`

This file lists claims that may be overstated until verified on GRIT.

## Confidence scale

1. `LOW`: claim likely incomplete or unproven without GRIT runtime evidence.
2. `MEDIUM`: claim partly supported, but important gaps remain.
3. `HIGH`: claim is well supported by available evidence.

## Flags

## F1

Claim: `Gate G2 (Run path) valide`.  
Confidence: `LOW`  
Reason: evidence is mostly local/static; no complete GRIT runtime proof bundle.

## F2

Claim: HPC template path is validated for execution.  
Confidence: `LOW`  
Reason: static checks passed, but `sbatch` execution on GRIT not evidenced.

## F3

Claim: phase-7 smoke represents real pipeline execution for steps 2-5.  
Confidence: `LOW`  
Reason: `tests/smoke_test_steps2_5.R` is a mock test, not canonical script run.

## F4

Claim: Step3 adaptive-threshold logic is scientifically validated.  
Confidence: `LOW`  
Reason: code uses both `threshold_adaptive` and `seuil_adaptatif`; behavior
needs runtime validation on GRIT datasets.

## F5

Claim: clone-neuf rehearsal fully validated.  
Confidence: `MEDIUM-LOW`  
Reason: local environment used filesystem-copy fallback; real `git clone` on
GRIT still required.

## F6

Claim: benchmark guard provides continuous regression protection.  
Confidence: `MEDIUM`  
Reason: guard exists, but currently tracks only one lightweight metric.

## F7

Claim: release verdict reflects fully evidence-based gate states.  
Confidence: `MEDIUM`  
Reason: G4 is correctly failing, but G2 should remain pending until GRIT proof.

## Action

Use `documentation/GRIT_VERIFICATION_CHECKLIST_20260309.md` to resolve all
`LOW`/`MEDIUM-LOW` flags with hard evidence files.
