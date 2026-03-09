# Non-Canonical Cleanup Report (2026-03-09)

## Scope

Phase 7 cleanup target:

1. duplicate markdown artifacts (`*(1).md` style),
2. ambiguous legacy backup files,
3. non-canonical or misleading public-facing docs.

## Scan methods

Repository scans were run with filename and content patterns:

1. `*(1).md`, `copy`, `.backup`, `.bak`, `.old`
2. legacy wording checks in key docs

## Findings

1. No duplicate markdown files matching `*(1).md` were found.
2. No backup-file artifacts were found under canonical paths in this branch.
3. `README.md` was still encoded in UTF-16 and contained outdated wording.

## Actions applied

1. Rewrote `README.md` to clean ASCII/UTF-8 markdown.
2. Aligned `README.md` with:
   - current phase-7 quality gate commands,
   - cluster-neutral HPC template usage,
   - corrected AIS provenance (GFW via Stanford Center for Ocean Solutions;
     contact David Kroodsma).

## Residual risk

Legacy deployment material may still exist in `deploy/` for historical context,
but canonical execution and public guidance now reference cleaned paths and
phase-7 checks.
