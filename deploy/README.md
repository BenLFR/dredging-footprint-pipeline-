# Scripts de déploiement GRIT

## Quick Start

### 1. Envoyer le code sur GRIT
```bash
bash deploy/sync_to_grit.sh
```

### 2. Exécuter un script R sur GRIT
```bash
bash deploy/run_on_grit.sh "scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"
```

### 3. Récupérer les résultats
```bash
# Récupérer tous les résultats
bash deploy/fetch_results.sh

# Ou récupérer un dossier spécifique
bash deploy/fetch_results.sh Resultats
bash deploy/fetch_results.sh output_V6
bash deploy/fetch_results.sh outputs_step6
```

## Configuration requise

- SSH configuré avec `~/.ssh/config_grit`
- Clé `id_ed25519_new` avec accès GRIT
- Git Bash ou WSL sur Windows

## Connexion manuelle

```bash
# Via alias court
ssh -F ~/.ssh/config_grit grit

# Via nom complet
ssh -F ~/.ssh/config_grit grit-hpc
```

## Structure synchronisée

Les scripts synchronisent automatiquement:
- `scripts_principaux/` → Scripts R principaux
- `configuration/` → Fichiers de configuration (YAML, INI, etc.)
- `submission/` → Scripts de soumission de jobs
- `pipeline_V6/pipeline_V6/` → Scripts Step 0-6 du pipeline
- `batch_windows/` → Scripts batch incluant Step 0

## Exclusions automatiques

Les fichiers suivants ne sont PAS synchronisés:
- Résultats (`Resultats/`, `output_V6/`, etc.)
- Données volumineuses (`AIS_with_lithology_clean.csv`, etc.)
- Fichiers temporaires (`.Rhistory`, `.tmp`, etc.)
- Fichiers Windows (`.bat`, `~$*`)
- Configuration Git (`.git/`)

## Running Pipeline Steps

### Step 0 Enhanced: Temporal Coverage Analysis ⭐

See detailed guide: **[STEP0_GUIDE.md](STEP0_GUIDE.md)**

**Enhanced version features:**
- Complete analysis of all candidate time windows
- Top 20 best windows ranking
- Ship × Year coverage matrix
- Detailed annual statistics

Quick start:
```bash
# 1. Sync code
bash deploy/sync_to_grit.sh

# 2. Upload AIS data
scp -F ~/.ssh/config_grit "benjamin2.csv" grit:~/scratch/AIS_data/

# 3. Run Step 0 Enhanced
ssh -F ~/.ssh/config_grit grit
cd ~/ais-pipeline/pipeline_V6
sbatch step0_window_select_grit.sh

# 4. Fetch results
bash deploy/fetch_results.sh output_V6
```

### Other Pipeline Steps

Coming soon - guides for Steps 1-6

## Notes

- `run_on_grit.sh` synchronise automatiquement avant d'exécuter
- Les données AIS doivent être copiées manuellement sur GRIT (voir [STEP0_GUIDE.md](STEP0_GUIDE.md))
- Voir [GRIT_WORKFLOW.md](GRIT_WORKFLOW.md) pour la documentation complète
- Le script sync inclut maintenant tous les fichiers Step 0-6 du pipeline
