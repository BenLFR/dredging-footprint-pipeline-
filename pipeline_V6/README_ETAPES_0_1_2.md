# Guide d'Exécution des Étapes 0, 1 et 2 du Pipeline

## Sommaire
- [Étape 0 : Sélection de la fenêtre cœur](#etape-0--selection-de-la-fenetre-coeur)
- [Étape 1 : Split des Navires](#etape-1--split-des-navires)
- [Étape 2 : Traitement des Navires](#etape-2--traitement-des-navires)

---

## Étape 0 : Sélection de la fenêtre cœur

### 1. Prérequis

```bash
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1
```

### 2. Lancement (SLURM)

Utilisez le script batch dédié :

```bash
cd ~/R_scripts/pipeline_V6
sbatch step0_window_select.sh
```

Ce script :
- détecte automatiquement les fichiers d'entrée (par défaut `~/scratch/AIS_data/*.csv`)
- écrit les résultats dans `~/scratch/output_V6/`
- génère tous les fichiers nécessaires pour la suite du pipeline

**Variables d'environnement optionnelles** :
- `AIS_INPUT_PATTERN` : pattern des fichiers CSV (défaut : `~/scratch/AIS_data/*.csv`)
- `AIS_OUTPUT_DIR` : dossier de sortie (défaut : `~/scratch/output_V6`)

Exemple :
```bash
sbatch --export=AIS_INPUT_PATTERN="~/scratch/AIS_data/benjamin2.csv",AIS_OUTPUT_DIR="~/scratch/output_V6" step0_window_select.sh
```

### 3. Résultats attendus

Dans `~/scratch/output_V6/` :
- `core_window_report.md` : résumé markdown de la fenêtre cœur
- `best_core_window.csv` : fenêtre optimale (années, score, couverture)
- `pings_per_year.png` : graphique volume annuel
- `coverage_params.yaml` : paramètres utilisés

Exemple de log :
```
🎯 Fenêtre optimale : 2015-2024 (10 ans)
   • Couverture médiane : 98.4 %
   • Couverture minimale : 93.4 %
   • CV annuel           : 0.025
   • Score               : 8.374
```

### 4. Dépannage
- Vérifiez les logs dans `~/R_scripts/pipeline_V6/logs/`
- En cas d'erreur "subscript out of bounds", assurez-vous d'utiliser la dernière version du script R
- Les fichiers de sortie sont nécessaires pour paramétrer les étapes suivantes (fenêtre cœur, navires sélectionnés)

---

## Étape 1 : Split des Navires

### Prérequis

### Configuration R sur Beluga
```bash
# Chargement des modules nécessaires
module load StdEnv/2020 gcc/9.3.0 r/4.2.1

# Configuration de la bibliothèque R personnelle
export R_LIBS=~/.local/R/4.2.1/
```

### Structure des répertoires
```
~/R_scripts/
├── pipeline_V6/
│   ├── step1_split_navires.R
│   └── step2_process_navire.R
└── configuration/
    └── outlier_config_V6.yaml
```

### 1. Préparation

> **Note importante :**
> Par défaut, le script traite uniquement `benjamin2.csv` (pattern `~/scratch/AIS_data/benjamin2.csv`).
> Si plusieurs fichiers sont trouvés, le script s'arrête avec une erreur.
> Pour traiter un autre fichier, lancez :
> ```bash
> sbatch --export=AIS_INPUT_PATTERN="/chemin/vers/autre.csv" step1_split_navires.sh
> ```

```bash
# Création du répertoire de sortie
mkdir -p ~/scratch/test_step1_final
```

### 2. Exécution
```bash
# Configuration des variables d'environnement
export SPLIT_JOB_ID=test_step1_final
export AIS_INPUT_PATTERN="~/scratch/AIS_data/benjamin2.csv"  # Spécification du fichier d'entrée

# Lancement avec timeout de 2h
timeout 2h Rscript ~/R_scripts/pipeline_V6/step1_split_navires.R
```

### 3. Vérification Étape 1
```bash
# Vérifier les fichiers générés
ls -la ~/scratch/ais_split_20250623055849/

# Vérifier le contenu du répertoire
# Doit contenir :
# - navires_metadata.csv (1.4 KB)
# - navire_01_Charles_Darwin.rds (~9.9 MB)
# - navire_02_Ham_318_Sleephopperzuiger.rds (~9.2 MB)
# - ... (11 fichiers au total)

# Vérifier la taille totale
du -sh ~/scratch/ais_split_20250623055849/
# Doit être environ 65.3 MB
```

### 4. Résultats attendus
L'étape 1 va :
- Lire le fichier benjamin2.csv (environ 10.4M lignes)
- Détecter 11 navires différents
- Créer un fichier RDS par navire avec le format : `navire_XX_Nom_Navire.rds`
- Générer un fichier de métadonnées `navires_metadata.csv`

Exemple de sortie attendue :
```
✅  Lecture terminée : 10 432 017 lignes  |  29.2 s
🚢  Navires détectés : 11 

📊  RÉCAP ---------------------------------------------------------
                       Navire n_observations
 1:            Charles Darwin        1434653
 2: Ham 318 Sleephopperzuiger        1311228
 3:            Leiv Eiriksson        1222900
 4:  Queen Of The Netherlands        1080409
 5:                   Fairway        1057785
 6:                Goryo 6 Ho         954488
 7:           Cristobal Colon         905946
 8:               Congo River         832988
 9:              Inai Kenanga         803229
10:                Vox Maxima         639077
11:             Vasco Da Gama         189314

💾  11 fichiers .rds (65.3 MB cumulés) écrits dans : ~/scratch/ais_split_20250623055849
🏁  STEP-1 terminé avec succès : 2025-06-23 06:01:30
```

## Étape 2 : Traitement des Navires

### 1. Préparation
```bash
# Utiliser le SPLIT_JOB_ID généré automatiquement (timestamp)
export SPLIT_JOB_ID=20250623055849
export OUTPUT_DIR=~/scratch/ais_processed_20250623055849
mkdir -p ~/scratch/ais_processed_20250623055849
```

### 2. Configuration YAML
Le fichier `~/R_scripts/configuration/outlier_config_V6.yaml` doit contenir :
```yaml
isolation_forest:
  contamination_rate: 0.03
  sample_size: 512
  num_trees: 50
```

### 3. Exécution
```bash
# Lancer le traitement en parallèle pour tous les navires
sbatch --array=1-11 ~/R_scripts/pipeline_V6/step2_process_array_FIXED.sh 20250623055849
```

### 4. Surveillance Étape 2
```bash
# Surveiller l'état des jobs en temps réel
squeue -u $USER

# Exemple de sortie attendue :
#          JOBID     USER      ACCOUNT           NAME  ST  TIME_LEFT NODES CPUS TRES_PER_N MIN_MEM NODELIST (REASON)
#     56701853_1     benl def-wailung_ ais_process_V6   R    1:58:30     1    4        N/A      6G bc11243 (None)
#     56701853_2     benl def-wailung_ ais_process_V6   R    1:58:31     1    4        N/A      6G bc11223 (None)
#     ...
#     56701853_11     benl def-wailung_ ais_process_V6   R    1:58:47     1    4        N/A      6G bc11202 (None)

# Surveiller la génération des fichiers en temps réel
watch -n 10 'ls -lh ~/scratch/ais_split_20250623055849/*_clean.rds 2>/dev/null | wc -l'

# Ou pour voir les fichiers générés au fur et à mesure :
watch -n 10 'ls -lh ~/scratch/ais_split_20250623055849/*_clean.rds'
```

### 5. Vérification Étape 2
```bash
# Vérifier que tous les fichiers ont été générés
ls -lh ~/scratch/ais_split_20250623055849/*_clean.rds

# Compter le nombre de fichiers générés
ls ~/scratch/ais_split_20250623055849/*_clean.rds 2>/dev/null | wc -l
# Doit retourner : 11

# Vérifier les tailles des fichiers nettoyés
# Exemple de sortie attendue :
# -rw-r-----. 1 benl benl 9.5M Jun 23 06:07 navire_01_Charles_Darwin_clean.rds
# -rw-r-----. 1 benl benl 8.9M Jun 23 06:07 navire_02_Ham_318_Sleephopperzuiger_clean.rds
# -rw-r-----. 1 benl benl 7.3M Jun 23 06:07 navire_03_Leiv_Eiriksson_clean.rds
# -rw-r-----. 1 benl benl 7.4M Jun 23 06:07 navire_04_Queen_Of_The_Netherlands_clean.rds
# -rw-r-----. 1 benl benl 7.3M Jun 23 06:07 navire_05_Fairway_clean.rds
# -rw-r-----. 1 benl benl 5.0M Jun 23 06:06 navire_06_Goryo_6_Ho_clean.rds
# -rw-r-----. 1 benl benl 5.0M Jun 23 06:06 navire_07_Cristobal_Colon_clean.rds
# -rw-r-----. 1 benl benl 4.9M Jun 23 06:06 navire_08_Congo_River_clean.rds
# -rw-r-----. 1 benl benl 4.9M Jun 23 06:06 navire_09_Inai_Kenanga_clean.rds
# -rw-r-----. 1 benl benl 4.5M Jun 23 06:06 navire_10_Vox_Maxima_clean.rds
# -rw-r-----. 1 benl benl 1.3M Jun 23 06:09 navire_11_Vasco_Da_Gama_clean.rds
```

### 6. Résultats attendus
L'étape 2 va :
- Traiter chaque navire en parallèle (11 tâches)
- Détecter les outliers avec Isolation Forest
- Créer les colonnes suivantes dans chaque fichier `*_clean.rds` :
  - `outlier_IF` : détection d'outliers (logical)
  - `delta_t` : intervalles temporels entre observations (numeric)
  - `is_stop` : détection des arrêts (logical) - **CRITIQUE pour l'étape 3**
  - `Annee` : année extraite du timestamp (numeric) - **CRITIQUE pour l'étape 3**
  - `Course_change` : changements de cap (numeric)
  - `Accel` : accélération (numeric)
- Temps de traitement : ~3-6 minutes au total

### 7. Vérification du contenu des fichiers nettoyés
```bash
# Charger les modules R
module load r/4.2.1 gcc/9.3.0

# Créer un script de vérification
cat > check_clean_files.R << 'EOF'
#!/usr/bin/env Rscript

# Lire un fichier nettoyé pour vérification
data <- readRDS("~/scratch/ais_split_20250623055849/navire_01_Charles_Darwin_clean.rds")

cat("📊 INFORMATIONS GÉNÉRALES:\n")
cat("   • Nombre de lignes:", nrow(data), "\n")
cat("   • Nombre de colonnes:", ncol(data), "\n")
cat("   • Type d'objet:", class(data), "\n\n")

cat(" COLONNES PRÉSENTES:\n")
for (i in seq_along(names(data))) {
  cat(sprintf("   %2d. %-20s (%s)\n", i, names(data)[i], class(data[[i]])[1]))
}

# Vérification des colonnes critiques pour l'étape 3
critical_cols <- c("Navire", "ssvid", "Seg_id", "Annee", "is_stop", "Lon", "Lat", "Course", "Speed")
cat("\n🔍 VÉRIFICATION DES COLONNES CRITIQUES:\n")
for (col in critical_cols) {
  if (col %in% names(data)) {
    cat(sprintf("   ✅ %-15s: présent (%s)\n", col, class(data[[col]])[1]))
  } else {
    cat(sprintf("   ❌ %-15s: MANQUANT\n", col))
  }
}

# Statistiques de la colonne is_stop
if ("is_stop" %in% names(data)) {
  stop_counts <- table(data$is_stop, useNA = "ifany")
  cat("\n🛑 ANALYSE DE LA COLONNE 'is_stop':\n")
  for (val in names(stop_counts)) {
    cat(sprintf("      %-10s: %d\n", val, stop_counts[val]))
  }
  cat("   Taux d'arrêts:", round(sum(data$is_stop) / nrow(data) * 100, 2), "%\n")
}

# Statistiques de la colonne Annee
if ("Annee" %in% names(data)) {
  year_counts <- table(data$Annee, useNA = "ifany")
  cat("\n📅 ANALYSE DE LA COLONNE 'Annee':\n")
  for (year in names(year_counts)) {
    cat(sprintf("      %-10s: %d\n", year, year_counts[year]))
  }
}
EOF

# Exécuter la vérification
Rscript check_clean_files.R
```

**Résultats observés pour Charles Darwin :**
- ✅ **14 colonnes** au total (vs 9 colonnes originales)
- ✅ **Toutes les colonnes critiques** présentes pour l'étape 3
- ✅ **is_stop** : 64.53% d'arrêts détectés (925,834 arrêts sur 1,434,653 observations)
- ✅ **Annee** : données de 2013 à 2024 (12 années)
- ✅ **Nouvelles colonnes** : `delta_t`, `Course_change`, `Accel`, `outlier_IF`

## Étape 3 : Fusion Finale (Prêt pour lancement)

### 1. Lancement
```bash
# Lancer la fusion finale avec le SPLIT_JOB_ID correct
sbatch ~/R_scripts/pipeline_V6/step3_merge_final.sh 20250623055849
```

### 2. Surveillance Étape 3
```bash
# Vérifier l'état du job
squeue -u $USER

# Exemple de sortie attendue :
#          JOBID     USER      ACCOUNT           NAME  ST  TIME_LEFT NODES CPUS TRES_PER_N MIN_MEM NODELIST (REASON)
#       56701892     benl def-wailung_   ais_merge_V6  PD    4:00:00     1   16        N/A     64G  (Priority)
```

## Procédure de Vérification Complète

### Checklist de Validation
```bash
# 1. Vérifier que l'étape 1 s'est bien terminée
echo "=== VÉRIFICATION ÉTAPE 1 ==="
ls -la ~/scratch/ais_split_20250623055849/ | grep -E "(navire_|metadata)"
echo "Nombre de fichiers navire : $(ls ~/scratch/ais_split_20250623055849/navire_*.rds 2>/dev/null | wc -l)"
echo "Fichier metadata présent : $(ls ~/scratch/ais_split_20250623055849/navires_metadata.csv 2>/dev/null | wc -l)"

# 2. Vérifier que l'étape 2 s'est bien terminée
echo "=== VÉRIFICATION ÉTAPE 2 ==="
echo "Nombre de fichiers nettoyés : $(ls ~/scratch/ais_split_20250623055849/*_clean.rds 2>/dev/null | wc -l)"
echo "Taille totale des fichiers nettoyés : $(du -sh ~/scratch/ais_split_20250623055849/*_clean.rds 2>/dev/null | tail -1)"

# 3. Vérifier l'état des jobs
echo "=== ÉTAT DES JOBS ==="
squeue -u $USER

# 4. Vérifier les logs d'erreur (si nécessaire)
echo "=== LOGS D'ERREUR ==="
ls -la ~/R_scripts/pipeline_V6/logs/ 2>/dev/null || echo "Aucun log d'erreur trouvé"
```

### Indicateurs de Succès
- ✅ **Étape 1** : 11 fichiers `.rds` + 1 fichier `metadata.csv`
- ✅ **Étape 2** : 11 fichiers `*_clean.rds` générés avec 14 colonnes chacun
- ✅ **Colonnes critiques** : `is_stop` et `Annee` présentes
- ✅ **Temps** : Étape 1 (~3 min), Étape 2 (~3-6 min)
- ✅ **Mémoire** : Pas d'erreur de mémoire
- ✅ **Jobs** : Tous les jobs terminés avec succès

## Dépannage

### Problèmes courants

1. **Erreur "columns not found"**
   - Vérifier que les colonnes sont bien `Lat`/`Lon` (majuscule initiale)
   - Le script a été corrigé pour utiliser la bonne casse

2. **Erreur de paramètres YAML**
   - Vérifier que le fichier YAML contient la section `isolation_forest`
   - S'assurer que le fichier se termine par un retour à la ligne

3. **Erreur de chemins**
   - Vérifier que `SPLIT_JOB_ID` est correctement défini
   - S'assurer que les fichiers sont dans le bon répertoire avec le préfixe `ais_split_`

4. **Job en attente (PD)**
   - Vérifier les ressources demandées
   - Attendre que les nœuds soient disponibles
   - Vérifier la priorité du job

5. **Colonnes manquantes dans les fichiers nettoyés**
   - Vérifier que l'étape 2 s'est bien terminée
   - Relancer l'étape 2 avec le bon SPLIT_JOB_ID
   - Vérifier les logs de l'étape 2 pour des erreurs

### Logs et diagnostics
- Les logs indiquent le nombre d'observations traitées
- Le taux d'outliers est affiché à la fin du traitement
- Les temps d'exécution sont mesurés pour chaque étape
- Les nouvelles colonnes créées sont listées

## Notes importantes

1. **Mémoire**
   - L'étape 1 peut nécessiter beaucoup de mémoire
   - L'étape 2 est optimisée pour la mémoire avec des paramètres conservateurs

2. **Performance**
   - Le traitement est mono-thread pour éviter les problèmes de mémoire
   - Les paramètres IF sont optimisés pour Beluga

3. **Sauvegarde**
   - Les fichiers de sortie sont compressés avec xz
   - Les fichiers originaux sont préservés 

4. **Surveillance**
   - Utiliser `squeue -u $USER` pour surveiller les jobs
   - Utiliser `watch` pour surveiller la génération des fichiers
   - Vérifier les logs en cas d'erreur

5. **Colonnes critiques pour l'étape 3**
   - `is_stop` : détection des arrêts (64.53% pour Charles Darwin)
   - `Annee` : année extraite du timestamp (2013-2024)
   - Ces colonnes sont **obligatoires** pour le bon fonctionnement de l'étape 3 

**Note : la sortie de l'étape 0 (fenêtre cœur, navires) peut être utilisée pour filtrer les données en entrée de l'étape 1 si besoin de reproductibilité stricte.** 