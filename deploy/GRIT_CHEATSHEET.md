# GRIT Cheat Sheet (connexion + verifications pipeline)

## Connexion

Connexion via config SSH:

```bash
ssh -F ~/.ssh/config_grit grit
```

Alternative (bastion direct):

```bash
ssh -F ~/.ssh/config_grit grit-bastion
```

## Repertoires utiles sur GRIT

- Code pipeline: `/home/bloe/ais-pipeline/`
- Scripts Step: `/home/bloe/ais-pipeline/pipeline_V6/`
- Config: `/home/bloe/ais-pipeline/configuration/`
- Land mask: `/home/bloe/ais-pipeline/configuration/land_mask/`
- Outputs Step 0/1/2: `~/scratch/` (ex: `~/scratch/ais_split_JOBID/`)

## Step 0 (core window)

Lancer:

```bash
cd /home/bloe/ais-pipeline/pipeline_V6
sbatch step0_window_select_grit.sh
```

Logs:

```bash
ls -lh /home/bloe/ais-pipeline/pipeline_V6/logs/step0_window_enhanced_*.out
tail -50 /home/bloe/ais-pipeline/pipeline_V6/logs/step0_window_enhanced_<JOBID>.out
```

Verifier la config:

```bash
cat ~/scratch/output_V6/core_window.yaml | grep -A15 "core_ships:"
```

## Step 1 (split navires)

Lancer:

```bash
cd /home/bloe/ais-pipeline/pipeline_V6
sbatch step1_split_navires.sh
```

Logs:

```bash
ls -lh /home/bloe/ais-pipeline/pipeline_V6/logs/step1_split_*.out
tail -50 /home/bloe/ais-pipeline/pipeline_V6/logs/step1_split_<JOBID>.out
```

Verifier les fichiers produits:

```bash
ls -lh ~/scratch/ais_split_<JOBID>/
cat ~/scratch/ais_split_<JOBID>/navires_metadata.csv
```

## Step 2 (process navires)

Pre-requis:

```bash
ls -lh /home/bloe/ais-pipeline/pipeline_V6/step2_process*
ls -lh /home/bloe/ais-pipeline/configuration/ship_specs.yaml
ls -lh /home/bloe/ais-pipeline/configuration/outlier_config_V6.yaml
ls -lh /home/bloe/ais-pipeline/configuration/land_mask/land_polygons.*
```

Lancer:

```bash
cd /home/bloe/ais-pipeline/pipeline_V6
SPLIT_JOB_ID=<STEP1_JOBID> sbatch --array=1-10 step2_process_array.sh
```

Logs:

```bash
ls -lh /home/bloe/ais-pipeline/pipeline_V6/logs/step2_process_<JOBID>_*.out
tail -50 /home/bloe/ais-pipeline/pipeline_V6/logs/step2_process_<JOBID>_1.out
tail -50 /home/bloe/ais-pipeline/pipeline_V6/logs/step2_process_<JOBID>_1.err
```

Resultats:

```bash
ls -lh ~/scratch/ais_results_<JOBID>/
```

## Commandes utiles

Voir les jobs:

```bash
squeue -u bloe
```

Verifier un fichier:

```bash
ls -lh <chemin>
head -20 <fichier>
```
