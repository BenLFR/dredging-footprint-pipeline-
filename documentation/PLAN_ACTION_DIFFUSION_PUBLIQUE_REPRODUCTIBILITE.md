# Public Release and Reproducibility Action Plan

Last updated: 2026-03-09
Scope: `pub/v1.0-clean`
Current release decision: NO-GO until all blocking gates are closed

---

## 1) Objective

Bring the repository to publication-grade quality for public diffusion and L&O: Methods submission, with:
- FAIR-complete citation and archival metadata.
- Reproducible run paths on a clean environment.
- Legally compliant handling of restricted dependencies and data.
- Language and style normalization across scripts and documentation.

---

## 2) Release Gates (authoritative)

| Gate | Status | Blocking reason | Exit criterion |
|---|---|---|---|
| G1 Legal and third-party compliance | PASS | None | `LICENSE` + `THIRD_PARTY_NOTICES.md` complete and consistent |
| G2 Portable execution path | PARTIAL | Remaining hard-coded HPC assumptions in some scripts/docs | All canonical scripts run from repo-relative paths with env overrides only |
| G3 Reproducible environment | PASS | None | `renv.lock`, `requirements.txt`, container recipe, smoke checks aligned |
| G4 FAIR archive and citation | FAIL | DOI placeholders and archive checksum closure incomplete | Real DOI in `CITATION.cff`/`codemeta.json`, immutable archive manifest finalized |
| G5 Journal package readiness | PARTIAL | Documentation and traceability still uneven | Complete methods-to-code traceability and final reviewer runbook |
| G6 Language and editorial hygiene | FAIL | Mixed French/English text, emoji residue, stale comments | English-only scripts/docs/comments, no emojis, no obsolete comments |

---

## 3) Phase Plan

## Phase 1 - Language and editorial normalization (NEW BLOCKING PHASE)

Goal: enforce a clean English-only public codebase and remove non-scientific noise.

Actions:
1. Convert all user-facing docs, script headers, CLI messages, and inline comments to English.
2. Remove all emojis from repository content (docs, comments, logs, templates).
3. Remove outdated comments that no longer match current behavior.
4. Keep only comments that explain intent, assumptions, or non-obvious logic.
5. Add a simple repository check script (or CI check) that fails on:
   - non-ASCII emoji characters,
   - known outdated comment markers,
   - French-only residual text in canonical scripts/docs.

Deliverables:
- Updated scripts and docs in English.
- `documentation/EDITORIAL_STYLE_GUIDE.md` (short rules).
- CI/style check integrated in workflow.

Exit criteria:
- Zero emoji matches in tracked files.
- No stale comments found in canonical pipeline files.
- Random manual spot-check of Step0-Step7 scripts confirms English-only comments/messages.

## Phase 2 - Infrastructure de-coupling and portability hardening

Goal: remove machine-specific assumptions from canonical paths.

Actions:
1. Replace remaining absolute/user paths with repo-relative defaults + env overrides.
2. Keep SLURM files as templates (no personal home path, no host-specific exclusions by default).
3. Ensure each step has clear required variables and fail-fast messages.
4. Align `CONFIG_DIR` defaults to repository config layout.
5. Execute the dedicated `deploy/` remediation sub-plan in `documentation/DEPLOY_REMEDIATION_PLAN.md`.
6. Align public HPC assets with official best practices: login-node preparation only, scratch-first staging, explicit working directories and logs, explicit environment export, dependency-based orchestration, signal-safe cleanup, transfer verification, and post-run accounting capture.

Deliverables:
- Hardened Step3/Step7 wrappers and docs.
- `config/templates/slurm/` templates fully neutral.
- Public `deploy/` folder converted to a generic Slurm/HPC deployment pack.
- Source-backed HPC runbooks, templates, and verification hooks integrated into the public release package.

Exit criteria:
- No `/home/<user>/...` path in canonical scripts.
- No hostname-specific scheduler directives in public defaults.

## Phase 3 - FAIR closure (critical)

Goal: move from FAIR partial to FAIR complete.

Actions:
1. Reserve and then confirm final archive DOI.
2. Replace placeholders in `CITATION.cff` and `configuration/codemeta.json`.
3. Finalize `archive-manifest` checksums and immutable artifact list.
4. Ensure repository URL fields point to the correct repository scope.

Deliverables:
- Finalized citation metadata and archive manifest.
- Release note with DOI and version mapping.

Exit criteria:
- G4 switches to PASS.
- Citation metadata resolves without placeholder values.

## Phase 4 - Restricted data and external dependency transparency

Goal: keep legal clarity while preserving reproducibility.

Actions:
1. Keep non-redistributed dependencies external-only and documented.
2. Document exact access process for restricted AIS inputs and external models.
3. Provide clear contact-based access guidance where required by provider policy.
4. Maintain toy/demo path for users without restricted assets.

Deliverables:
- Updated `THIRD_PARTY_NOTICES.md` and `documentation/data_and_dependency_access.md`.
- Access statement aligned with manuscript language.

Exit criteria:
- A reviewer can identify what is restricted, what is public, and how to request access.

## Phase 5 - Reproducibility verification (clean clone + HPC evidence)

Goal: prove that claims are backed by executable evidence.

Actions:
1. Run clean-clone smoke tests from the public branch/tag.
2. Run canonical dry-run checks for key heavy steps on HPC (GRIT or equivalent cluster).
3. Archive command logs and artifact checksums as verification evidence.
4. Update readiness tracker using strict evidence only.

Deliverables:
- Verification log pack.
- Updated release verdict and tracker.

Exit criteria:
- No claim remains without test evidence.
- Reproducibility verdict is evidence-complete.

## Phase 6 - Journal submission lock

Goal: prepare final submission-grade package.

Actions:
1. Freeze version (`v1.0.0` or final agreed tag).
2. Publish final archive release with DOI.
3. Final pass on README (scope, quickstart, compute profile, citation).
4. Verify consistency between manuscript statements and repository metadata.

Exit criteria:
- Public release is citable, reproducible, and manuscript-aligned.

---

## 4) Immediate next actions (execution order)

1. Complete Phase 1 (English-only, no emoji, stale comment cleanup).
2. Close remaining portability issues from Phase 2, starting with the `deploy/` remediation plan.
3. Close G4 FAIR blockers (DOI + manifest) from Phase 3.
4. Re-run Phase 5 verification and update verdict files.
5. Execute Phase 6 freeze and release.

---

## 5) Definition of done (final)

The repository is ready for public release and L&O: Methods submission only when all are true:
1. G1 PASS
2. G2 PASS
3. G3 PASS
4. G4 PASS
5. G5 PASS
6. G6 PASS
7. Final verdict file shows GO with evidence references
