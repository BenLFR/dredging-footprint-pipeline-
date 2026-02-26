---
name: pipeline-curriculum
description: >
  Scrapes the dredging footprint pipeline repo and produces a NotebookLM-ready
  curriculum pack: CURRICULUM_MASTER.md (all concepts, step-by-step fiches),
  CONCEPT_GRAPH.md (dependency graph + recommended learning order),
  SOURCE_WISHLIST.md (PDFs/URLs to import into NotebookLM per concept cluster).
  Covers software concepts (R, Python, MATLAB, HPC/SLURM, geospatial) and
  domain concepts (AIS, TSHD, GMM, DBSCAN, OCIM, SAR, CRI, seabed lithology,
  marine biogeochemistry, benthic carbon cycling).
  Trigger: "curriculum", "notebooklm pack", "study pack", "pipeline-curriculum",
  "/pipeline-curriculum".
---

# pipeline-curriculum

Generate a NotebookLM-ready curriculum pack from the dredging footprint pipeline
repository. The pack covers every pipeline step (0–7) plus the OCIM CO₂ model,
extracting both software and domain concepts. Output goes to
`output_V6/notebooklm_pack/` per project conventions (CLAUDE.md: pipeline outputs
→ `output_V6/`).

---

## Inputs

Parse the user's command to determine:

- **scope**: `all` (default), or a comma-separated list of step numbers
  (e.g., `2,3,5`) to limit extraction to specific steps
- **depth**: `standard` (default) or `deep` — `deep` adds extra oral exam
  questions, failure-mode analysis, and sensitivity notes per concept
- **format**: `notebooklm` (default, long-form Markdown per concept) or
  `anki` (tab-separated Q&A lines for Anki import appended at end of
  CURRICULUM_MASTER.md)

---

## Phase 0 — Repo Snapshot (pre-injection)

Before reading any files, establish the repo state by running:

```
Tracked pipeline files:
!`git ls-files pipeline_V6/pipeline_V6/ scripts_cluster/ scripts_principaux/ configuration/ | head -300`
```

Also read the CLAUDE.md to confirm directory conventions, then:

1. Note the current git branch and last commit hash (via `git log -1 --oneline`)
2. List files in `output_V6/notebooklm_pack/` if it already exists (to avoid
   overwriting without warning)
3. If the output directory already contains files from a previous run, inform
   the user and proceed (overwrite is acceptable — git tracks the source code,
   not the generated pack)

---

## Phase 1 — Read Authoritative Files Per Step

Read the files listed below using the Read tool. For each file:
- Note the actual file path (some may not exist if a step was never run locally;
  skip missing files gracefully and log them in a "Missing files" section at the
  end of CURRICULUM_MASTER.md)
- Focus on: algorithm choices, parameter values, data structures, package calls,
  SLURM directives, and any comment blocks that explain *why* a decision was made

### Step 0 — Core Window Selection

Primary files:
- `pipeline_V6/pipeline_V6/step0_core_window_enhanced.R`
- `pipeline_V6/pipeline_V6/step0_window_select_grit.sh`
- `pipeline_V6/pipeline_V6/step0_window_select.sh`

Look for: temporal window logic, coverage matrix structure, vessel-day thresholds,
how the "core window" concept handles gaps in AIS coverage.

### Step 1 — Split AIS Data by Vessel

Primary files:
- `pipeline_V6/pipeline_V6/step1_split_navires.R`
- `pipeline_V6/pipeline_V6/step1_split_navires.sh`

Look for: MMSI splitting strategy, output file format (parquet/rds per vessel),
memory management, how vessel identity is established from raw AIS.

### Step 2 — Per-Vessel Track Processing & Filtering

Primary files:
- `pipeline_V6/pipeline_V6/step2_process_navire.R`
- `pipeline_V6/pipeline_V6/step2_process_array.sh`
- `configuration/outlier_config_V6.yaml`
- `scripts_principaux/visualize_step2_zoom_land_filtering.R`

Look for: Isolation Forest parameters (contamination rate, n_estimators),
speed/acceleration filters, near-coast exclusion radius, land-crossing detection,
delta-t outlier logic, YAML config structure and how parameters are loaded,
what "flagOK" means in the output.

### Step 3 — Merge Vessels, GMM, DBSCAN Clustering

Primary files:
- `pipeline_V6/pipeline_V6/step3_merge_final.R`
- `pipeline_V6/pipeline_V6/step3_merge_final_grit.sh`

Look for: how per-vessel parquet files are assembled into the global dataset,
GMM component number selection (BIC/AIC), what features feed the GMM
(speed, heading change, delta-t), how DBSCAN eps and minPts are chosen,
how clusters map to dredging vs transit behaviour, mclust package usage,
output schema (columns produced).

### Step 4 — Add Lithology from dbSEABED

Primary files:
- `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.R`
- `pipeline_V6/pipeline_V6/step4_add_lithology_vNext.sh`
- `pipeline_V6/pipeline_V6/prefetch_hubocean_stac.py`
- `pipeline_V6/pipeline_V6/download_dbseabed_raw.py`
- `configuration/ship_specs.yaml`

Look for: how dbSEABED tiles are fetched via HubOcean STAC API, spatial join
strategy (nearest-neighbour vs polygon intersection), which lithology columns
are retained (grain size, substrate type), how H_index (hard-bottom) is derived,
ship_specs.yaml structure (hopper volume, beam, sweep width), how vessel specs
feed into penetrability calculations.

### Step 5 — Compute Fishing/Dredging Intensity (fi) on Global Grid

Primary files (read all):
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_make_tiles.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_tile_worker.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_tile_job.sh`
- `pipeline_V6/pipeline_V6/step5_modulaire/step5_merge_tiles.R`
- `pipeline_V6/pipeline_V6/step5_modulaire/constants.R`
- `pipeline_V6/step5_merge_tiles_optimized.R`
- `constants.R`
- `scripts_principaux/diagnostic_step5_hotspots.R`
- `scripts_principaux/diagnostic_step5_projection.R`

Look for: global grid resolution (0.25° or 0.05°?), EPSG:6933 equal-area
projection rationale, how SAR (Swept Area Ratio) is computed per cell
(swept area / cell area), tiling strategy to avoid OOM (how many tiles, overlap),
how land cells are masked, how ocean fraction is computed and applied,
basin-level k_fast assignment, what `fi` actually represents numerically,
output raster format (GeoTIFF / parquet).

### Step 6 — Calculate CRI (Cumulative Risk Index)

Primary files:
- `pipeline_V6/pipeline_V6/step6_calculate_cri.R`
- `scripts_cluster/step6_calculate_cri_grit.sh`
- `pipeline_V6/pipeline_V6/check_step6_for_ocim.R`

Look for: CRI formula definition, how pl_base (penetrability endmembers from
Sala et al.) and H_index combine, seabed vulnerability weighting, how CRI
relates to SAR, output dimensions (same grid as step5?), what check_step6
validates before passing to step7.

### Step 7 — Export Jdredge for OCIM

Primary files:
- `scripts_cluster/step7_export_jtrawl_grit.sh`
- `step7_extract_ocim_cache.py`
- `step7_extract_ocim_cache.m`
- `scripts_cluster/run_step7_diagnostics.sh`
- `scripts_cluster/step7_check_inputs.sh`

Look for: how the 0.25° SAR/CRI raster is remapped onto the OCIM2-48L 3D grid
(91×180×48 depth layers), conservative remapping algorithm (area-weighted),
ocean-fraction conservation constraint, shelf redistribution logic (K_MAX
parameter), how Jdredge units are set (mol C m⁻³ s⁻¹ or similar), what
the OCIM cache `.mat` contains, how amplified scenarios (10x, 100x) are
produced, what diagnostics verify conservation.

### CO₂ Model & Post-processing

Primary files:
- `Trawling model-20250623T085752Z-1-001/Trawling model/co2model.m`
- `Trawling model-20250623T085752Z-1-001/Trawling model/co2model_dredge.m`
- `scripts_cluster/co2model_batch_grit.sh`
- `pipeline_V6/postproc_atwood_style.py`
- `pipeline_V6/extract_dredging_timeseries.py`

Look for: OCIM2-48L structure (what the steady-state transport matrix T
represents), how Jdredge is injected as a perturbation, GMRES solver settings
(tolerance, max iterations), how DIC perturbation propagates to pCO₂ / air-sea
flux (CO2SYS), Atwood et al. carbon stock normalization, temporal integration
window (2012 start, why?), what netemission.txt contains, output variables
(ΔpCO₂, ΔDIC, net emission time series).

### Configuration & Constants

Primary files:
- `constants.R`
- `configuration/outlier_config_V6.yaml`
- `configuration/ship_specs.yaml`

Look for: all global constants (grid resolution, CRS, basin definitions,
k_fast values per basin), YAML parameter hierarchy, how ship specs
(beam, sweep width, speed range) encode prior knowledge about TSHD vessels.

---

## Phase 2 — Concept Extraction Per Step

For each step, produce concept fiches. Each fiche must contain all sections
below. **Do not skip sections** — if information is not in the code, write
"Not explicitly defined in code — inferred from context" and explain the
inference.

### Fiche template

```
### [CONCEPT NAME]
**Type**: Software | Domain | Both
**Step(s)**: e.g., Step 2, Step 7
**One-line definition**: ...

**Why it's here**: What problem does this concept solve in the pipeline?
What would go wrong without it?

**Code evidence**: `file_path:line_range` — quote the key line(s) or function call.
If the line number is uncertain, cite the function name and describe its location.

**Prerequisites**: List 2–5 concepts that must be understood first.

**Domain / physical meaning**: For domain concepts, explain the physical or
biogeochemical reality this concept represents. What does it mean in the ocean?

**For software concepts**: Describe the algorithm, its time/space complexity if
relevant, and which R/Python/MATLAB package implements it.

**Oral exam points** (3–5 bullet points that a thesis defence examiner might ask):
- ...
- ...
- ...

**Failure modes**: What goes wrong in practice? What does a bug look like?
What parameter values break the method?

**Repo exercise**: One concrete thing the reader can do with the actual code to
deepen understanding (e.g., "Change contamination_rate to 0.10 in
outlier_config_V6.yaml and re-run step 2 on vessel 009 — compare the before/after
maps generated by visualize_step2_zoom_land_filtering.R").
```

### Mandatory concept checklist (safety net)

All concepts below **must** appear as named fiches in CURRICULUM_MASTER.md.
If a concept is not found in the code, still produce a fiche explaining the
concept and noting it is implicit or assumed rather than explicitly coded.

**Software / Engineering:**
1. AIS data format & preprocessing (MMSI, ping rate, temporal gaps)
2. TSHD vessel specifications (beam, hopper volume, sweep width)
3. Isolation Forest (anomaly detection, contamination parameter)
4. Gaussian Mixture Model / GMM (mclust, BIC model selection)
5. DBSCAN (density-based clustering, eps, minPts, noise label)
6. Equal-Earth projection EPSG:6933 (equal-area, why not WGS84)
7. Tiled spatial operations (OOM avoidance strategy)
8. SLURM array jobs (embarrassingly parallel, `--array`, `$SLURM_ARRAY_TASK_ID`)
9. data.table (in-memory columnar operations, `:=`, `.SD`, keys)
10. terra / sf (raster vs vector, CRS transforms, rasterize)
11. Parquet format (columnar storage, why vs CSV/RDS for large AIS data)
12. Conservative remapping (area-weighted regridding, mass conservation)
13. GMRES solver (iterative linear algebra, preconditioning, convergence)
14. HubOcean STAC API (spatial tiling, COG GeoTIFF, Python requests)

**Domain — Physical Oceanography / Biogeochemistry:**
15. OCIM2-48L (Ocean Circulation Inverse Model, transport matrix T, 91×180×48)
16. Jdredge (carbon perturbation flux, units, sign convention)
17. SAR — Swept Area Ratio (definition, per-cell computation, interpretation)
18. CRI — Cumulative Risk Index (formula, inputs, ecological meaning)
19. pl_base / penetrability (Sala et al. endmembers, Hard vs Soft seabed)
20. Seabed lithology (dbSEABED dataset, grain size, substrate classification)
21. H_index (hard-bottom fraction, how derived, role in CRI)
22. k_fast (basin-level carbon cycling rate, units, spatial assignment)
23. Benthic carbon stocks (Atwood et al. 2024, gC m⁻², normalization approach)
24. Ocean-fraction conservation (why coastal cells need correction)
25. Shelf redistribution (K_MAX depth layers, why surface-only injection fails)
26. DIC perturbation & air-sea CO₂ flux (CO2SYS, Henry's law, pCO₂ anomaly)
27. Atwood-style post-processing (what "net emission" means in this context)

---

## Phase 3 — Curriculum Synthesis

After extracting all fiches, produce two synthesis artefacts:

### 3a — Dependency graph (for CONCEPT_GRAPH.md)

Build a directed graph where an edge A → B means "A must be understood before B".
Represent the graph as:
1. A Mermaid flowchart block (```mermaid graph TD```) — one edge per line
2. A plain-text adjacency list for NotebookLM (which does not render Mermaid)
3. A **topologically sorted learning path** in three tiers:

**Tier 1 — Foundations** (no prerequisites from this repo)
- AIS data format, parquet, SLURM basics, equal-area projections, data.table/terra/sf

**Tier 2 — Pipeline core** (prereqs are Tier 1 concepts)
- Isolation Forest → GMM → DBSCAN → SAR → CRI flow
- Lithology join, penetrability, H_index
- Tiling strategy, conservative remapping

**Tier 3 — Advanced / edge cases** (prereqs span Tiers 1+2)
- OCIM2-48L structure, Jdredge injection, GMRES, DIC perturbation
- Ocean-fraction correction, shelf redistribution, Atwood post-processing
- Amplified scenarios, mass conservation diagnostics

### 3b — Centrality ranking

Rank the top-10 concepts by "risk of misunderstanding × novelty × exam
centrality". For each, write a one-sentence justification. These become the
first 10 fiches in CURRICULUM_MASTER.md (reorder the list by rank, not step
order).

---

## Phase 4 — Emit Output Files

Create the directory if it does not exist:
```
output_V6/notebooklm_pack/
```

Write exactly three files using the Write tool:

### File 1: `output_V6/notebooklm_pack/CURRICULUM_MASTER.md`

Structure:
```markdown
# Dredging Footprint Pipeline — Curriculum Master Pack
<!-- Generated by /pipeline-curriculum on YYYY-MM-DD -->
<!-- Git commit: <hash> | Branch: <branch> -->

## How to use this document
[3-sentence guide for importing into NotebookLM and generating study guides]

## Priority concepts (top-10 by exam centrality)
[Ranked list with one-sentence justification each]

---

## Step 0 — Core Window Selection
### [concept fiches for Step 0]

## Step 1 — Split AIS Data by Vessel
### [concept fiches for Step 1]

## Step 2 — Per-Vessel Track Processing & Filtering
### [concept fiches for Step 2]

## Step 3 — Merge Vessels, GMM, DBSCAN
### [concept fiches for Step 3]

## Step 4 — Lithology Join (dbSEABED)
### [concept fiches for Step 4]

## Step 5 — Compute SAR on Global Grid
### [concept fiches for Step 5]

## Step 6 — CRI Calculation
### [concept fiches for Step 6]

## Step 7 — Export Jdredge for OCIM
### [concept fiches for Step 7]

## CO₂ Model & Post-processing (MATLAB + Python)
### [concept fiches for CO2 model]

## Configuration & Constants
### [concept fiches for shared config]

---

## Missing files log
[List any files from the manifest that were not found, with skip reason]

## Concept checklist coverage
[Table: concept name | Found in code | Fiche section]
```

Include the full fiche (all 8 sections) for every concept. Do not abbreviate.
Target length: 3,000–8,000 words total. If the document would exceed 8,000
words, split per-step content into `output_V6/notebooklm_pack/modules/stepN.md`
and replace the step section with a one-paragraph summary + link.

### File 2: `output_V6/notebooklm_pack/CONCEPT_GRAPH.md`

Structure:
```markdown
# Concept Dependency Graph

## Mermaid diagram
[mermaid graph TD block — one edge per prereq relationship]

## Plain-text adjacency list
[For NotebookLM: "A requires B, C" lines]

## Topologically sorted learning path
### Tier 1 — Foundations
### Tier 2 — Pipeline core
### Tier 3 — Advanced / edge cases

## Top-10 priority concepts
[Ranked list with justification]
```

### File 3: `output_V6/notebooklm_pack/SOURCE_WISHLIST.md`

For each concept cluster, list 3–6 external sources that would enrich
NotebookLM when added alongside this pack. Format:

```markdown
# Source Wishlist for NotebookLM

## AIS Data & Preprocessing
| Source | Type | Why add it | URL / DOI |
|--------|------|------------|-----------|
| ...    | PDF  | ...        | ...       |

## Machine Learning (GMM, DBSCAN, Isolation Forest)
...

## Spatial Analysis & Projections
...

## Marine Biogeochemistry & OCIM
...

## Benthic Carbon & Seabed Ecology
...

## HPC / SLURM / R on clusters
...
```

Prioritise: open-access PDFs, official package vignettes, key papers cited
in the code comments or thesis. Do not invent DOIs — if uncertain, write
"Search: [title + author + year]" instead of a URL.

---

## Safety Rules

- **Skip**: `.env`, `secrets/`, `*.mat` binary data (read text `.m` files
  only), `data/`, `renv/library/`, `__pycache__/`, `.git/`, `*.rds > 10MB`,
  `*.parquet > 10MB`
- **Never expose**: credentials, API keys, tokens, personal data
- **Code evidence**: cite as `file:approximate_line` or `file: function_name()`.
  Never invent line numbers — if unsure, omit the line number and name the
  function or variable instead
- **No invented parameters**: if a parameter is not in the code, say so
  explicitly — do not fill gaps with plausible-sounding values
- **If total output > 8,000 words**: split step sections to
  `output_V6/notebooklm_pack/modules/stepN.md` and add an index table to
  CURRICULUM_MASTER.md linking to each module

---

## Output Summary (print after writing files)

After writing all files, print to the user:

```
✓ Curriculum pack written to output_V6/notebooklm_pack/
  CURRICULUM_MASTER.md  — N concepts across 9 steps + CO₂ model
  CONCEPT_GRAPH.md      — dependency graph + learning path
  SOURCE_WISHLIST.md    — external sources per concept cluster

Missing files: [list or "none"]
Concept checklist: N/27 mandatory concepts found in code

Next steps:
  1. Import CURRICULUM_MASTER.md into NotebookLM as a source
  2. Test with: "Explain SAR and how it differs from CRI"
  3. Test with: "What is OCIM2-48L and how does Jdredge feed into it?"
  4. For flashcards: use the Anki section at the bottom (if --format=anki)
```

---

## Project-Specific Context

This skill is designed exclusively for the **Dredging Footprint Pipeline**
master thesis (Benjamin LOEFFLER):
- Pipeline steps 0–7 + OCIM CO₂ model
- Primary language: R (pipeline) + Python (data fetch, postproc) + MATLAB (CO₂ model)
- HPC clusters: Beluga (Alliance Canada) and GRIT (emlab_nodes partition)
- Key output: global dredging intensity raster + Jdredge carbon flux for OCIM
- Outputs must go to `output_V6/notebooklm_pack/` (CLAUDE.md convention)
- Git branch: `feature/step2-extraction-visualization` (current)
