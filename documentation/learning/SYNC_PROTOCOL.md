# Sync Protocol

This protocol keeps the local learning docs and NotebookLM aligned without
turning NotebookLM into the only memory of the system.

## Core rule

Local markdown first. NotebookLM second.

## Machine-readable state

Automation should prefer:
- `documentation/learning/state/registry.json`
- `documentation/learning/state/ingest_log.jsonl`

The markdown files remain the human-readable mirror.

Recommended invariant for new wrapper-generated entries:
- one record = one source = one target notebook.

Legacy or hand-seeded records may still be multi-source or multi-notebook;
`sync-pending` replays those as batch cross-products and stores detailed outcomes
in `sync_results[]`.

## Resource states

| State | Meaning | Required local record |
|-------|---------|-----------------------|
| NEW | Resource exists but has not been classified yet | log entry |
| INDEXED | Registers and concepts identified | log entry plus registry update |
| INGESTED | Added to target notebook | log entry with target notebook |
| PROMOTED | Stable teaching note added to Core Curriculum | log entry plus note path |
| SYNC_PENDING | Needs future sync because tooling failed or was skipped | reason and next attempt |
| FAILED | Sync attempted and failed | failure reason and fallback |

## Standard workflow

### 1. Classify

For any new resource, decide:
- what it is,
- which registers it touches,
- whether it is critical, useful, or peripheral,
- which notebook should receive it.

### 2. Update local records first

Before any external sync:
- add an entry to `RESOURCE_INGEST_LOG.md`,
- add or update the JSONL entry in `state/ingest_log.jsonl`,
- create or update the affected concepts in `LEARNING_REGISTRY.md`,
- mirror those concept changes in `state/registry.json`,
- record any missing prerequisites.

### 3. Ingest to NotebookLM

Use `notebooklm-py` or a future wrapper to add the source to the target
notebook. Keep the connector surface minimal and explicit:
- ingest one source,
- query one notebook,
- export one grounded answer,
- promote one stable teaching note.

Avoid free-form ad hoc automation from multiple agents at once.

### 4. Wait when grounding matters

If a source-grounded query or promotion depends on processed source content, use the
wrapper's native wait flow before proceeding.

### 5. Query and distill

After ingestion, query NotebookLM to extract:
- plain-language explanation,
- technical explanation,
- project-specific relevance,
- prerequisite concepts,
- citation anchors.

Write the distilled result back to local markdown if it is worth keeping.

### 6. Derived note logging

If `query --save-note` produces a reusable local note, log it immediately as a
derived resource so it enters the same governance loop as ingested sources.

### 7. Promotion checklist

A note may be promoted to `NBLM-10-Core-Curriculum` only if all checks pass:
- grounded in named sources,
- no secrets or private identifiers,
- not tied to a transient debugging incident,
- still valid beyond the current session,
- understandable without excessive repo-local context.

### 8. Promote stable notes

If a note becomes a reusable explainer:
- save it locally first,
- link it from `LEARNING_REGISTRY.md`,
- log it,
- validate the promotion checklist,
- then promote it to `NBLM-10-Core-Curriculum`.

### 8b. Optional Obsidian open step

If the user wants immediate review in Obsidian, the wrapper may open the saved
or promoted note after success via:

- `--open-in-obsidian`
- `--obsidian-method auto|uri|cli`
- `--obsidian-vault`
- `--obsidian-vault-root`
- `--obsidian-bin`

Supported layouts:

- repo-root vault:
  the repository root itself is the Obsidian vault, so `--open-in-obsidian` is
  usually enough
- separate vault:
  pass both `--obsidian-vault` and `--obsidian-vault-root` so the wrapper can
  translate the saved note path into a vault-relative path

Recommended practice:

- use `auto` first
- use `cli` only when the official Obsidian CLI is preferred explicitly
- keep local markdown as the source of truth even when Obsidian is used as the
  reading layer

### 9. Close the loop

At the end of a session, one of these should have happened:
- the registry improved,
- the ingest log improved,
- a stable note was promoted,
- or a `SYNC_PENDING` item was recorded.

## Query rules for agents

Before answering a substantial technical question, the agent should:
- identify the relevant registers,
- check `LEARNING_REGISTRY.md`,
- use the existing curriculum pack first when enough,
- query NotebookLM only when an external source-grounded answer is needed,
- use `status --healthcheck` when importability is not enough and auth/connectivity needs confirmation,
- adapt the explanation to one level above the current mastery level.

## What not to sync

Do not push these by default:
- raw stack traces,
- temporary debug transcripts,
- incomplete scratch notes,
- duplicated copies of repo files,
- anything containing secrets or personal data.

## Encoding rule

All wrapper-managed files should be written as UTF-8 without BOM.

## Minimal review cadence

- Daily: update the registry after meaningful work.
- Weekly: review `SYNC_PENDING` items.
- Monthly: prune temporary notebooks and promote only stable material.