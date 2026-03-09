# Public Readiness Tracker

Date de creation: 2026-03-08  
Plan de reference: `documentation/PLAN_ACTION_DIFFUSION_PUBLIQUE_REPRODUCTIBILITE.md`

## Statut global

- [x] Gate G1 (Legal) valide
- [ ] Gate G2 (Run path) valide
- [x] Gate G3 (Repro env) valide
- [ ] Gate G4 (FAIR) valide
- [x] Gate G5 (Journal) valide

## Phase 0 - Baseline et triage

- [ ] Creer la liste unique des findings avec IDs
- [x] Cartographier chemins canoniques vs legacy
- [ ] Identifier tous les hard-codes infra
- [x] Integrer la baseline scripts GRIT (`documentation/GRIT_SCRIPT_BASELINE_20260308.md`)
- [x] Produire mapping `script_grit -> chemin_local` pour les steps 0-7

## Phase 1 - Legal et licences

- [x] Ajouter `LICENSE`
- [x] Ajouter `THIRD_PARTY_NOTICES.md`
- [x] Relire `Manuscript Paper 1 v1 - Benjamin LOEFFLER.docx` pour extraire les composants tiers a notifier
- [x] Ajouter la table de tracabilite `manuscript mention -> THIRD_PARTY_NOTICES`
- [x] Regulariser `co2model/inpaint_nans.m` (retire du bundle public; dependance externe)
- [x] Regulariser `co2model/sw_pres.m` (retire du bundle public; dependance externe)
- [x] Aligner `CITATION.cff` avec licence effective

## Phase 2 - Integrite pipeline et entrypoints

- [x] Verifier que les scripts appeles correspondent a la baseline GRIT la plus recente
- [x] Corriger `pipeline/step4_add_lithology.sh`
- [x] Corriger `pipeline/step5_merge_slurm.sh`
- [x] Corriger `pipeline/step6_calculate_cri.sh`
- [x] Corriger `pipeline/step7_export_jtrawl.sh` (chemin script)
- [x] Aligner Step4->Step5 sur pattern fichier lithology
- [x] Verifier/couvrir la logique `t_seuil` dans Step3
- [x] Ajouter smoke test Steps 3-6

## Phase 3 - Decouplage infra et templates

- [x] Introduire variables env (`PIPELINE_DIR`, `OUTPUT_DIR`, `CONFIG_DIR`, `SCRATCH_DIR`)
- [x] Remplacer infos GRIT/Beluga hard-codees par templates (wrappers Step4-7)
- [x] Isoler `deploy/` interne ou neutraliser en templates publics (co2model: fetch externe + upload parametre)
- [x] Ajouter templates SLURM generiques

## Phase 4 - Environnements reproductibles

- [x] Generer `renv.lock`
- [x] Ajouter spec Python (`requirements.txt` ou `environment.yml`)
- [x] Verifier/mettre a jour `deploy/apptainer.def`
- [x] Documenter build, test, SHA256 conteneur
- [x] Aligner CI sur ces specs

## Phase 5 - FAIR et archivage

- [x] Ajouter `ARCHIVE_MANIFEST.yaml`
- [x] Completer `configuration/codemeta.json`
- [x] Finaliser `documentation/ZENODO_INTEGRATION_GUIDE.md`
- [ ] Remplacer placeholders DOI quand release publiee
- [ ] Verifier checksums des outputs archives

## Phase 6 - Methodes, limites, transparence

- [x] Brancher warnings runtime de limites dans pipeline
- [x] Verifier liens vers `documentation/LIMITATIONS.md`
- [x] Finaliser protocoles benchmark/validation/uncertainty
- [x] Ajouter mapping "resultat -> script -> input -> output"

## Phase 7 - CI et release decision

- [x] Etendre CI (testthat + benchmark continu + seuils regression)
- [x] Nettoyer doublons/non-canonical (`*(1).md`, legacy ambigu)
- [ ] Tester clone neuf (quickstart toy)
- [ ] Tester chemin HPC template (sans donnees proprietaires)
- [x] Produire verdict Go/No-Go documente

## Journal d'avancement

| Date | Item | Statut | Commentaire |
|---|---|---|---|
| 2026-03-08 | Plan initial cree | DONE | Plan + tracker ajoutes dans `documentation/` |
| 2026-03-08 | Contrainte manuscrit + baseline GRIT integrees | DONE | Plan mis a jour avec revue manuscrit en Phase 1 et baseline GRIT comme reference autoritative |
| 2026-03-08 | Revue manuscrit Paper 1 effectuee pour notices tiers | DONE | `THIRD_PARTY_NOTICES.md` cree avec table de tracabilite manuscrit -> notices |
| 2026-03-08 | LICENSE MIT ajoute + alignement citation confirme | DONE | `LICENSE` cree, `CITATION.cff` deja `license: MIT`, notices de regularisation ajoutees |
| 2026-03-08 | Baseline canonique scripts mappee | DONE | `documentation/CANONICAL_PATHS_AND_DEPRECATIONS.md` ajoute avec mapping baseline GRIT -> chemins locaux |
| 2026-03-08 | Correctifs critiques wrappers Step4/5/6/7 | DONE | resolution robuste des scripts + correction chainage Step4->Step5 + fallback constants Step7 |
| 2026-03-08 | Step5 wrapper + checks Step3/Steps3-6 ajoutes | DONE | `pipeline/step5_merge_slurm.sh` corrige, test `tests/smoke_test_steps3_6_entrypoints.R` ajoute et passe |
| 2026-03-08 | Decouplage infra demarre (partiel) | IN_PROGRESS | `PIPELINE_DIR` / `LOGS_DIR` / `SCRATCH_DIR` parametrables dans wrappers Step4-7 |
| 2026-03-08 | CO2 model de-vendore + workflow externe ajoute | DONE | fichiers `co2model/*` tiers retires du git; workflow `--co2model-src` pour upload Step7 |
| 2026-03-08 | Source OCIM precisee (pas de repo GitHub public confirme) | DONE | docs/notices alignees sur acces par demande email a TD (`tdevries@geog.ucsb.edu`) |
| 2026-03-08 | Phase 3 cloturee sur wrappers Step4-7 | DONE | suppression hard-codes cluster + ajout `OUTPUT_DIR`/`CONFIG_DIR` + templates `config/templates/slurm/` |
| 2026-03-09 | Phase 4 completee (specs R/Python + conteneur + CI) | DONE | `renv.lock` + `requirements.txt` + `deploy/apptainer.def` + `docs/reproducibility.md`; CI smoke alignee sur R `4.4.1` et cache renv |
| 2026-03-09 | Phase 5 engagee (manifeste + codemeta + guide Zenodo) | DONE | ajout de `ARCHIVE_MANIFEST.yaml`, `configuration/codemeta.json`, `.zenodo.json`, `documentation/ZENODO_INTEGRATION_GUIDE.md`; placeholders DOI conserves jusqu'a release |
| 2026-03-09 | Provenance AIS corrigee (GFW/Stanford) | DONE | `docs/data_policy.md`, `data/README.md`, `documentation/LIMITATIONS.md`, `ARCHIVE_MANIFEST.yaml` alignes sur la source utilisateur et contact David Kroodsma |
| 2026-03-09 | Phase 6 completee (limites + protocoles + tracabilite) | DONE | warnings runtime Step3-7 + `documentation/LIMITATIONS.md`, `BENCHMARKING_PROTOCOL.md`, `VALIDATION_PROTOCOL.md`, `UNCERTAINTY_BUDGET.md`, `RESULT_TRACEABILITY_MATRIX.md` |
| 2026-03-09 | CI phase 7 etendue | DONE | workflow `smoke_test.yml` etendu avec `testthat`, benchmark guard et test HPC template statique |
| 2026-03-09 | Rehearsal clone neuf + HPC template completes | DONE | validation en copie propre via `tests/run_testthat.R`, `tests/benchmark_regression_guard.R`, `tests/hpc_template_path_check.R`, `tests/smoke_test_steps2_5.R` |
| 2026-03-09 | Verdict release rendu | DONE | `documentation/RELEASE_VERDICT_20260309.md`: **NO-GO** tant que DOI/checksums FAIR ne sont pas finalises |
| 2026-03-09 | Tracker recale en mode evidence-based strict | DONE | G2 reouvert en attente de preuves runtime GRIT; tests clone-neuf/HPC marques pending tant que non verifies sur GRIT |
| 2026-03-09 | Checklist GRIT + flags confidence ajoutes | DONE | `documentation/GRIT_VERIFICATION_CHECKLIST_20260309.md` et `documentation/GRIT_AUDIT_FLAGS_BY_CONFIDENCE_20260309.md` |
