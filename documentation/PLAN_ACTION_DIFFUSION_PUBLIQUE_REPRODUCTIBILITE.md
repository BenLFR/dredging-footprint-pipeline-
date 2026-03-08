# Plan d'action complet - Diffusion publique et reproductibilite

Date: 2026-03-08  
Source: `Audit de diffusion publique et de reproductibilite du depot Master-thesis-code-.md`

## 1) Objectif

Passer le depot de **NOT READY** a **READY FOR PUBLIC RELEASE + CITABLE ARCHIVE** en couvrant tous les points de l'audit:

1. licence et conformite juridique,
2. entrypoints/scripts casses,
3. coherences inter-etapes pipeline,
4. environnements non figes,
5. couplage infrastructure (GRIT/Beluga/home/scratch),
6. metadata/release FAIR,
7. documentation et statements article.

## 2) Regles d'execution (gates)

Le plan est execute avec des gates Go/No-Go.  
Un gate non valide bloque la publication.

1. Gate G1 (Legal): `LICENSE` + `THIRD_PARTY_NOTICES` + preuves de licences tierces.
2. Gate G2 (Run path): Steps 0-7 executables sur chemin canonique (local toy + HPC template).
3. Gate G3 (Repro env): `renv.lock` + spec Python + recette conteneur.
4. Gate G4 (FAIR): archive manifest + checksums + DOI workflow documente.
5. Gate G5 (Journal): Code/Data availability statements verifiables.

## 3) Plan par phase

### Phase 0 - Baseline et triage (J0)

But: figer l'etat reel avant correction.

Actions:
1. Creer un tableau de suivi unique des non-conformites (ID, severite, proprietaire, statut, preuve).
2. Lister les scripts canoniques et les aliases legacy (`pipeline/`, `pipeline_V6/`, `deploy/`).
3. Marquer les chemins infra specifiques a templatiser (`~/scratch`, `--nodelist`, `--account`, `~/.ssh/config_grit`).
4. Geler le referentiel "scripts valides" a partir des versions les plus recentes sur GRIT (source fournie par l'utilisateur).
5. Produire un mapping `script_grit -> emplacement_local` et marquer `obsolete` tout script concurrent plus ancien.

Livrables:
1. `documentation/PUBLIC_READINESS_TRACKER.md`
2. `documentation/CANONICAL_PATHS_AND_DEPRECATIONS.md`
3. `documentation/GRIT_SCRIPT_BASELINE_20260308.md`

Critere de sortie:
1. 100% des findings de l'audit sont traces avec un ID.
2. 100% des scripts des steps 0-7 ont une reference canonique GRIT unique.

---

### Phase 1 - Legal et licences (J0-J1) [CRITICAL]

Actions:
1. Ajouter `LICENSE` (MIT si confirme par le mainteneur).
2. Ajouter `THIRD_PARTY_NOTICES.md` couvrant au minimum:
   - `co2model/inpaint_nans.m`
   - `co2model/sw_pres.m`
   - toute autre source tierce redistribuee.
3. Analyser le manuscrit `Manuscript Paper 1 v1 - Benjamin LOEFFLER.docx` pour detecter tout composant tiers supplementaire a notifier:
   - logiciels/outils externes,
   - jeux de donnees externes,
   - cartes/fonds/figures/algorithmes tiers cites,
   - bibliotheques ou ressources dont la redistribution impose attribution.
4. Ajouter une table de tracabilite `manuscript mention -> entree THIRD_PARTY_NOTICES`.
5. Traiter les cas licence inconnue:
   - option A: recuperer texte de licence + attribution complete,
   - option B: retirer du depot public et documenter dependance externe.
6. Aligner `CITATION.cff` avec la licence effective.

Critere de sortie (Gate G1):
1. `LICENSE` present.
2. chaque fichier tiers redistribue a une base legale explicite.
3. aucun fichier tiers "orphan" sans licence.
4. les composants tiers mentionnes dans le manuscrit sont reconciles avec `THIRD_PARTY_NOTICES.md`.

---

### Phase 2 - Integrite pipeline et entrypoints (J1-J2) [CRITICAL]

Actions:
1. Prendre comme autorite les scripts de la baseline GRIT et corriger la structure locale pour s'aligner sur cette baseline.
2. Corriger wrappers vers scripts existants ou fournir les scripts manquants:
   - `pipeline/step4_add_lithology.sh` -> appel actuel `step4_add_lithology_vNext.R` (absent),
   - `pipeline/step5_merge_slurm.sh` -> appel actuel `step5_merge_tiles_optimized.R` (absent),
   - `pipeline/step6_calculate_cri.sh` -> appel actuel `step6_calculate_cri_corrected.R` (absent),
   - `pipeline/step7_export_jtrawl.sh` -> alignement chemin script R (root vs pipeline).
3. Corriger la coherence Step4 -> Step5 sur les noms de sortie:
   - Step4 produit `AIS_with_lithology_*.rds`,
   - Step5 cherche `AIS_with_lithology_clean_*.rds`.
4. Valider la logique Step3 sur `t_seuil` et verrouiller par test regression.
5. Ajouter un smoke test "happy path" incluant au minimum Steps 3-6.

Critere de sortie (Gate G2, partiel):
1. aucun wrapper ne reference de fichier absent.
2. chainage Step4->Step5 fonctionne sans renommage manuel.
3. test smoke passe sur machine propre (toy data).
4. tous les scripts executes correspondent a la baseline GRIT la plus recente.

---

### Phase 3 - Decouplage infrastructure et templates HPC (J2-J4) [HIGH]

Actions:
1. Remplacer chemins hard-codes par variables/env avec valeurs par defaut documentees:
   - `PIPELINE_DIR`, `OUTPUT_DIR`, `CONFIG_DIR`, `SCRATCH_DIR`.
2. Sortir les scripts internels de `deploy/` du chemin public principal:
   - soit deplacer en dossier prive,
   - soit conserver en templates neutres sans host/user/ssh specifiques.
3. Creer templates SLURM generiques dans `config/templates/` ou `pipeline/slurm/`.
4. Conserver les details GRIT/Beluga seulement en annexes optionnelles.

Critere de sortie:
1. plus aucune dependance obligatoire a un nom de noeud/compte specifique.
2. execution possible via variables documentees.

---

### Phase 4 - Environnements reproductibles (J3-J5) [HIGH]

Actions:
1. Generer `renv.lock` (R) et documenter `renv::restore()`.
2. Ajouter spec Python (`requirements.txt` ou `environment.yml`) pour Step7.
3. Standardiser conteneur:
   - conserver/mettre a jour `deploy/apptainer.def`,
   - documenter build + test + hash SHA256.
4. Mettre CI en coherence avec les specs figees.

Critere de sortie (Gate G3):
1. lockfile R present et utilisable.
2. dependances Python pinnees.
3. conteneur reproductible teste.

---

### Phase 5 - FAIR, archivage et metadata release (J4-J6) [HIGH]

Actions:
1. Ajouter `ARCHIVE_MANIFEST.yaml` (fichiers, tailles, checksums, provenance, DOI cible).
2. Completer `CITATION.cff` (ORCID, auteurs reels, DOI reel apres depot).
3. Ajouter/valider `configuration/codemeta.json`.
4. Finaliser `documentation/ZENODO_INTEGRATION_GUIDE.md`.
5. Remplacer placeholders DOI dans:
   - `docs/data_policy.md`,
   - statements dans `documentation/`.

Critere de sortie (Gate G4):
1. chaque output publie a une reference archivee + checksum.
2. metadata citation valides et non-placeholder.

---

### Phase 6 - Transparence methodes et limites (J5-J7) [HIGH]

Actions:
1. Ajouter/brancher warnings runtime de limites methodologiques dans pipeline.
2. Verifier `documentation/LIMITATIONS.md` et le referencer explicitement dans warnings.
3. Completer:
   - `documentation/BENCHMARKING_PROTOCOL.md`,
   - `documentation/VALIDATION_PROTOCOL.md`,
   - `documentation/UNCERTAINTY_BUDGET.md`.
4. Ajouter mapping "resultat figure/table -> script -> input -> output".

Critere de sortie:
1. chaque limite majeure de l'audit est explicite et traceable dans le code/doc.

---

### Phase 7 - CI, qualite, et decision de publication (J6-J8) [HIGH]

Actions:
1. Etendre CI:
   - tests `testthat` (failure modes),
   - extraction metriques Step3,
   - benchmark continu avec seuils regression.
2. Nettoyer clutter/non-canonical:
   - doublons `*(1).md`, fichiers legacy ambigus,
   - scripts hors chemin canonique non documentes.
3. Executer rehearsal complete:
   - clone neuf,
   - quickstart toy,
   - execution HPC template (sans donnees proprietaires).
4. Remplir checklist pre-release et rendre verdict.

Critere de sortie (Gate G5):
1. pipeline minimal reproductible prouve.
2. statements Code/Data Availability verifiables.
3. decision **GO** documentee.

## 4) Mapping exhaustif audit -> actions

### A. Top 5 bloqueurs de l'audit

1. Licence absente/ambiguite tierce -> Phase 1.
2. Entrypoints wrappers casses -> Phase 2.
3. Bugs/incoherences pipeline (Step3, Step4->5, config hors repo) -> Phase 2 + 3.
4. Reproductibilite non verrouillee (`renv`, Python, conteneur) -> Phase 4.
5. Hard-coding infra (GRIT/Beluga/scratch) -> Phase 3.

### B. Constats detailles 3.1 -> 3.10

1. 3.1 Secrets/provenance leaks -> Phase 3 + 7 (templating + nettoyage public).
2. 3.2 Donnees non redistribuables -> Phase 5 + 6 (manifests + statements + toy data).
3. 3.3 Hypotheses machine-specifiques -> Phase 3.
4. 3.4 Gaps reproducibilite -> Phase 2 + 4 + 7.
5. 3.5 Metadata manquantes -> Phase 1 + 5.
6. 3.6 Licence/reuse -> Phase 1.
7. 3.7 Incoherence manuscrit-repo -> Phase 6.
8. 3.8 Clutter/dead weight -> Phase 7.
9. 3.9 Environment/execution -> Phase 4.
10. 3.10 FAIR/archive readiness -> Phase 5.

### C. Contraintes additionnelles utilisateur (2026-03-08)

1. Revue du manuscrit pour completer `THIRD_PARTY_NOTICES.md` -> Phase 1.
2. Scripts valides = versions les plus recentes sur GRIT -> Phase 0 + Phase 2.

## 5) Ordonnancement court (execution recommandee)

1. Jour 1: Phase 0 + Phase 1 (G1 obligatoire).
2. Jour 2: Phase 2 (G2 obligatoire).
3. Jour 3-4: Phase 3 + Phase 4 (G3).
4. Jour 5-6: Phase 5 + Phase 6 (G4).
5. Jour 7-8: Phase 7 + decision Go/No-Go (G5).

## 6) Definition of done finale

Le depot est publiable seulement si toutes les conditions suivantes sont vraies:

1. `LICENSE` et conformite tierce sont closes.
2. le chemin canonique Step0->Step7 est executable sans fichier manquant.
3. les environnements R/Python/conteneur sont figes et documentes.
4. les chemins infra specifiques sont optionnels et templates.
5. metadata citation + archive FAIR sont completes avec DOI reel (apres release).
6. quickstart reproductible valide sur clone neuf.

## 7) Statut initial observe le 2026-03-08 (verification rapide)

Points confirmes a corriger en priorite:

1. `LICENSE` absent.
2. `THIRD_PARTY_NOTICES.md` absent.
3. `renv.lock` absent.
4. `requirements.txt`/`environment.yml` absents.
5. wrappers Step4/5/6 referencent des scripts absents.
6. incoherence nommage Step4->Step5 (`AIS_with_lithology_*` vs `AIS_with_lithology_clean_*`).
7. `README.md` encode en UTF-16 (a convertir UTF-8 pour diffusion GitHub standard).

Ces points correspondent aux bloqueurs CRITICAL/HIGH du rapport d'audit et
doivent etre traites avant toute publication publique.

## 8) Baseline scripts valides (source utilisateur, GRIT, recu le 2026-03-08)

Le plan doit prendre en reference la baseline detaillee dans:

`documentation/GRIT_SCRIPT_BASELINE_20260308.md`

Cette baseline est prioritaire pour arbitrer les conflits entre scripts dupliques
ou versions concurrentes presentes localement.
