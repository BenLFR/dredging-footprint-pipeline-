# Learning Operating System

This directory is the local control plane for AI-assisted learning in this
project.

Use it to keep a persistent record of:
- what must be understood to operate the pipeline,
- what is already partially understood,
- which resources have been ingested,
- which resources belong in NotebookLM,
- what still needs to be learned next.

## Source hierarchy

1. Local markdown in `documentation/learning/` is the human-readable source of
   truth for learning state, routing rules, and sync history.
2. `documentation/learning/state/` is the machine-readable state layer for
   scripts and wrappers.
3. `output_V6/notebooklm_pack/` is the seeded curriculum pack already generated
   from the repo and should be treated as canonical project curriculum content.
4. NotebookLM is the external resource hub for source-grounded querying and
   teaching material, not the only persistent memory.

## Core files

- `LEARNING_REGISTRY.md`: concepts, mastery levels, gaps, next actions.
- `RESOURCE_INGEST_LOG.md`: human-readable ingest history.
- `NOTEBOOKLM_INDEX.md`: notebook taxonomy and routing rules.
- `SYNC_PROTOCOL.md`: how local docs and NotebookLM stay aligned.
- `CHATGPT_CUSTOM_INSTRUCTIONS.md`: copy-ready text for ChatGPT/Codex.

## Schema

Scripts should read the state files first and treat markdown as the readable
mirror.

Recommended invariant for new wrapper-generated records:
- one record = one source = one target notebook.

Legacy or seeded records may still contain multiple sources or notebooks; the
wrapper replays those as batch cross-products and stores the detailed outcomes in
`sync_results[]`.

### `documentation/learning/state/registry.json`

Top-level fields:
- `schema_version`
- `updated_at`
- `mastery_scale`
- `registers[]`
- `concepts[]`

Each concept entry should carry at least:
- `id`
- `register`
- `concept`
- `level`
- `importance`
- `status`
- `linked_sources[]`
- `next_action`

### `documentation/learning/state/ingest_log.jsonl`

One JSON object per line.

Each ingest record should carry at least:
- `resource_id`
- `title`
- `status`
- `operation`
- `type`
- `source_path`
- `source_url`
- `target_notebook`
- `registers[]`
- `concepts[]`
- `created_at`
- `last_synced_at`
- `sync_attempts`
- `source_hash`
- `source_version`
- `notebooklm_source_id`
- `notebooklm_notebook_id`
- `notes`
- `sync_results[]`

## Agent roles

- Claude/Codex: local execution, repo reading, patching, registry updates,
  ingest classification.
- ChatGPT: plain-language explanation, scientific writing support, structured
  teaching, gap spotting.
- Gemini/NotebookLM: source-grounded answers over imported papers, notes,
  scripts, and guidelines.

## Standard loop

1. Add or receive a new resource.
2. Log it in `RESOURCE_INGEST_LOG.md` and `state/ingest_log.jsonl`.
3. Update or create the affected concepts in `LEARNING_REGISTRY.md` and
   `state/registry.json`.
4. Route the resource to a target notebook using `NOTEBOOKLM_INDEX.md`.
5. If a query produces a reusable local note, save it and log it as a derived
   note before deciding on promotion.
6. If a stable teaching note emerges, promote it to NotebookLM Core Curriculum.
7. If sync cannot be done now, mark the resource `SYNC_PENDING` and continue
   locally.

## Obsidian integration

The NotebookLM wrapper can optionally open a saved or promoted note in Obsidian
after success.

Two vault layouts are supported:

- repo-root vault:
  use the repository root itself as the Obsidian vault and open notes with
  `--open-in-obsidian`
- separate vault:
  keep the vault elsewhere and pass both `--obsidian-vault` and
  `--obsidian-vault-root` so the wrapper can derive a vault-relative path

Examples:

```bash
python tools/notebooklm_sync.py query \
  --notebook "NBLM-10-Core-Curriculum" \
  --question "Explain alpha_dep simply" \
  --save-note documentation/learning/notes/software-code/analysis-tests/alpha_dep.md \
  --open-in-obsidian
```

```bash
python tools/promote_teaching_note.py \
  --path documentation/learning/notes/software-code/analysis-tests/2026-03-12_analysis-tests-concept-guide.md \
  --wait \
  --open-in-obsidian \
  --obsidian-method cli \
  --obsidian-vault "KnowledgeVault" \
  --obsidian-vault-root "C:\\Users\\loeff\\Obsidian\\KnowledgeVault"
```

## Existing seed materials

The current NotebookLM-ready curriculum pack already lives in:
- `output_V6/notebooklm_pack/CURRICULUM_MASTER.md`
- `output_V6/notebooklm_pack/CONCEPT_GRAPH.md`
- `output_V6/notebooklm_pack/SOURCE_WISHLIST.md`

These three files should be the first project artifacts imported into the
NotebookLM notebooks defined in `NOTEBOOKLM_INDEX.md`.