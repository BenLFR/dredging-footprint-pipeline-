# Release Verdict (2026-03-09)

## Gate status snapshot

| Gate | Definition | Status | Evidence |
|---|---|---|---|
| G1 | Legal compliance | PASS | `LICENSE`, `THIRD_PARTY_NOTICES.md`, provenance corrections |
| G2 | Canonical run path | PASS | wrappers fixed + smoke checks (`tests/smoke_test_steps2_5.R`, `tests/smoke_test_steps3_6_entrypoints.R`) |
| G3 | Repro environments | PASS | `renv.lock`, `requirements.txt`, `deploy/apptainer.def`, CI alignment |
| G4 | FAIR archive readiness | FAIL (pending) | DOI placeholders still present; archived output checksums not finalized |
| G5 | Release decision documented | PASS | this verdict + phase-7 rehearsal report |

## Blocking items for full public citable release

1. Replace DOI placeholders with minted Zenodo DOI values in all metadata/docs.
2. Finalize archive checksums for published output artifacts.

## Decision

**NO-GO** for final public citable release as of 2026-03-09.

## Conditional readiness

**GO** for pre-release code sharing on branch `pub/v1.0-clean` for technical
review, with explicit note that FAIR release closure (G4) is pending.
