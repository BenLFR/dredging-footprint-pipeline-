# Extraction des Statistiques Step 2

## Vue d'ensemble

Ce guide explique comment extraire les statistiques détaillées du Step 2 (filtrage géospatial et détection d'anomalies) pour analyser combien de points ont été supprimés à chaque étape.

## Statistiques extraites

Pour chaque navire, le script extrait:

### 1. Filtrage par étapes
- **Points initiaux**: Nombre total de points chargés
- **Filtre vitesse physique**: Points supprimés (vitesse > 1.15 × vitesse service)
- **Filtrage géospatial**: Points supprimés (terre, segments, sauts, spikes GPS)
  - Nombre d'itérations nécessaires
  - Pourcentage de suppression
- **Points finaux**: Nombre de points après tous les filtres

### 2. Détection d'anomalies (sur données finales)
- **Outliers Isolation Forest**: Nombre et pourcentage
- **Arrêts détectés**: Nombre et pourcentage

### 3. Résumé global
- Réduction totale (points supprimés)
- Pourcentage de conservation

## Utilisation

### Option 1: Script Windows (Batch)

```batch
cd "C:\Users\loeff\OneDrive\Bureau\Master thesis\Datasets\AIS Tracks\R code\Beluga"
batch_windows\extract_step2_results.bat <PROCESS_JOB_ID>
```

Exemple:
```batch
batch_windows\extract_step2_results.bat 13289
```

### Option 2: Script Bash (Git Bash ou WSL)

```bash
cd "C:\Users\loeff\OneDrive\Bureau\Master thesis\Datasets\AIS Tracks\R code\Beluga"
bash batch_windows/extract_step2_results.sh <PROCESS_JOB_ID>
```

Exemple:
```bash
bash batch_windows/extract_step2_results.sh 13289
```

### Option 3: Script R directement

Si les logs sont déjà téléchargés localement:

```bash
Rscript scripts_principaux/extract_step2_stats.R <PROCESS_JOB_ID>
```

## Où trouver le Process Job ID?

Le **Process Job ID** est l'ID du job SLURM du Step 2 (array job).

Sur GRIT:
```bash
# Voir les jobs en cours
squeue -u bloe

# Voir l'historique des jobs
sacct -u bloe --starttime 2026-01-01 --format=JobID,JobName,State,Start,End

# Chercher les jobs Step 2
sacct -u bloe --name=ais_process_V6 --format=JobID,JobName,State,Start,End
```

Le Job ID sera du format: `12345` (utilisez ce nombre pour l'extraction)

## Fichiers générés

### 1. Tableau CSV
`step2_statistics_<PROCESS_JOB_ID>.csv`

Colonnes:
- `task_id`: Numéro du navire (1, 2, 3, ...)
- `navire`: Nom du navire
- `n_initial`: Points initiaux
- `n_after_speed_filter`: Après filtre vitesse
- `n_before_geo`: Avant filtrage géospatial
- `n_after_geo`: Après filtrage géospatial
- `n_removed_geo`: Points supprimés par filtrage géospatial
- `pct_removed_geo`: % supprimés par filtrage géospatial
- `geo_iterations`: Nombre d'itérations géospatiales
- `n_outliers_IF`: Outliers détectés par Isolation Forest
- `pct_outliers_IF`: % outliers
- `n_stops`: Arrêts détectés
- `pct_stops`: % arrêts
- `n_final`: Points finaux
- `n_total_removed`: Total supprimés
- `pct_total_removed`: % total supprimés

### 2. Affichage console

Le script affiche également:
- **Statistiques globales**: Totaux pour tous les navires
- **Détail par type de filtrage**: Répartition des suppressions
- **Détail par navire**: Statistiques individuelles avec cascade de filtres

## Exemple de sortie

```
═══════════════════════════════════════════════════════════════════════════
RÉSUMÉ DES STATISTIQUES STEP 2
═══════════════════════════════════════════════════════════════════════════

📊 STATISTIQUES GLOBALES:
─────────────────────────────────────────────────────────────────────────
Nombre de navires traités: 10
Points initiaux (total):   15,234,567
Points finaux (total):     14,123,456
Points supprimés (total):  1,111,111 (7.29%)

📉 DÉTAIL PAR TYPE DE FILTRAGE:
─────────────────────────────────────────────────────────────────────────
Filtre vitesse physique:   234,567 points (1.54% du total)
Filtrage géospatial:       876,544 points (5.75% du total)
Outliers IF détectés:      423,123 points (3.00% du final)
Arrêts détectés:          1,234,567 points (8.74% du final)

═══════════════════════════════════════════════════════════════════════════
DÉTAIL PAR NAVIRE
═══════════════════════════════════════════════════════════════════════════

🚢 NAVIRE 1: Congo River
─────────────────────────────────────────────────────────────────────────
Points initiaux:           1,523,456
  - Filtre vitesse:        -23,456 (1.54%) → 1,500,000 restants
  - Filtrage géospatial:   -87,654 (5.84%) en 2 itération(s) → 1,412,346 restants

Points finaux:             1,412,346
  - Outliers IF:           42,312 (3.00%)
  - Arrêts:                123,456 (8.74%)

📉 Réduction totale:       -111,110 (7.29%)
```

## Dépannage

### Logs introuvables
Si les logs ne sont pas sur GRIT, vérifiez:
```bash
ssh -F ~/.ssh/config_grit grit
ls -lh ~/ais-pipeline/pipeline_V6/logs/step2_process_*
```

### Téléchargement manuel des logs
```bash
scp -F ~/.ssh/config_grit "grit:~/ais-pipeline/pipeline_V6/logs/step2_process_13289_*.out" "./logs/"
```

### Script R ne trouve pas les logs
Assurez-vous d'être dans le bon répertoire:
```bash
cd "C:\Users\loeff\OneDrive\Bureau\Master thesis\Datasets\AIS Tracks\R code\Beluga"
```

## Analyse des résultats

### Interpréter les statistiques

**Taux de suppression normal:**
- Filtre vitesse: 1-3% (élimine les valeurs physiquement impossibles)
- Filtrage géospatial: 3-10% (dépend de la zone d'opération)
  - Plus élevé pour les navires côtiers
  - Plus faible pour les navires hauturiers

**Taux de suppression anormal (> 20%):**
- Vérifier les visualisations Step 2
- Possibles problèmes:
  - Masque terre incorrect
  - Paramètres de filtrage trop stricts
  - Données AIS de mauvaise qualité pour ce navire

### Comparer les navires

Utilisez le fichier CSV pour:
1. Identifier les navires avec taux de suppression élevé
2. Comparer les performances du filtrage
3. Détecter des patterns par type de navire
4. Valider la cohérence du pipeline

## Prochaines étapes

Après avoir extrait les statistiques:

1. **Visualiser les résultats** (si pas déjà fait):
   ```bash
   # Sur GRIT
   Rscript visualize_step2_before_after.R 8 <SPLIT_JOB_ID> <PROCESS_JOB_ID>
   Rscript visualize_step2_zoom_land_filtering.R 8 <SPLIT_JOB_ID> <PROCESS_JOB_ID>
   ```

2. **Télécharger les visualisations**:
   ```bash
   bash deploy/fetch_results.sh Resultats
   ```

3. **Procéder au Step 3** si les résultats sont satisfaisants

## Voir aussi

- [README_BELUGA.md](README_BELUGA.md) - Vue d'ensemble du pipeline
- [GRIT_WORKFLOW.md](../deploy/GRIT_WORKFLOW.md) - Workflow complet sur GRIT
- [STEP0_GUIDE.md](../deploy/STEP0_GUIDE.md) - Guide du Step 0
