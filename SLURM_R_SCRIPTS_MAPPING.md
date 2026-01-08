# 📋 Mapping Scripts SLURM → Scripts R
## Pipeline Complet (Steps 0 à 6)

**Date**: 2026-01-08
**Organisation**: Par étape du pipeline (0-6)

---

## 🔍 STEP 0 : Sélection de la fenêtre temporelle

### **Script SLURM** : `step0_window_select.sh`
- **Localisation**: `pipeline_V6/step0_window_select.sh`
- **Ressources**: 6 GB RAM, 2 CPUs, 20 min
- **Script R associé**: `step0_core_window.R`
- **Chemin R**: `~/R_scripts/pipeline_V6/step0_core_window.R`

```bash
#SBATCH --job-name=ais_window_V6
#SBATCH --mem=6G
#SBATCH --cpus-per-task=2
#SBATCH --time=00:20:00

# Appel R
Rscript --vanilla step0_core_window.R
```

### **Autres Scripts R de Step 0**
| Script R | Type | Description |
|----------|------|-------------|
| `step0_core_window.R` | ✅ **Principal** | Sélection fenêtre optimale |
| `step0_core_window_enhanced.R` | 🔧 Dev | Version améliorée |
| `step0_core_window_enhanced_FIXED.R` | 🔧 Dev | Version corrigée |
| `step0_core_window_enhanced_WORKING.R` | 🔧 Dev | Version de travail |
| `step0_coverage_analysis.R` | 📊 Analyse | Analyse de couverture |
| `step0_window_selectV1.R` | 🗄️ Archive | Version 1 |

### **Scripts SLURM alternatifs**
- `step0_window_select_enhanced.sh` - Version améliorée
- `step0_coverage.sh` - Analyse de couverture
- `step0_coverage_analysis.sh` - Analyse détaillée

---

## 📦 STEP 1 : Fractionnement par navire

### **Script SLURM** : `step1_split_navires.sh`
- **Localisation**: `pipeline_V6/step1_split_navires.sh`
- **Ressources**: 8 GB RAM, 4 CPUs, 30 min
- **Script R associé**: `step1_split_navires.R`
- **Chemin R**: `~/R_scripts/pipeline_V6/step1_split_navires.R`

```bash
#SBATCH --job-name=ais_split_V6
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00

# Appel R
Rscript --vanilla step1_split_navires.R
```

### **Scripts R de Step 1**
| Script R | Type | Description |
|----------|------|-------------|
| `step1_split_navires.R` | ✅ **Principal** | Fractionnement par navire (11 navires) |

### **Scripts SLURM alternatifs**
- `step1_split_navires_FIXED.sh` - Version corrigée avec gestion d'erreurs

**Sortie**:
- Crée 11 fichiers `.rds` : `navire_01_Charles_Darwin.rds`, etc.
- Fichier metadata : `navires_metadata.csv`

---

## 🔄 STEP 2 : Traitement par navire (Array Job)

### **Script SLURM** : `step2_process_array.sh`
- **Localisation**: `pipeline_V6/step2_process_array.sh`
- **Ressources**: 6 GB RAM, 4 CPUs, 2h
- **Array**: `--array=1-12%8` (max 8 jobs simultanés)
- **Script R associé**: `step2_process_navire.R`
- **Chemin R**: `~/R_scripts/pipeline_V6/step2_process_navire.R`

```bash
#SBATCH --job-name=ais_process_V6
#SBATCH --array=1-12%8
#SBATCH --mem=6G
#SBATCH --cpus-per-task=4
#SBATCH --time=02:00:00

# Appel R (embedded)
R --vanilla --slave -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_ARRAY_TASK_ID = '$SLURM_ARRAY_TASK_ID')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
source('step2_process_navire.R')
"
```

### **Scripts R de Step 2**
| Script R | Type | Description |
|----------|------|-------------|
| `step2_process_navire.R` | ✅ **Principal** | Traitement + Isolation Forest + détection arrêts |

### **Scripts SLURM alternatifs**
- `step2_process_array_FIXED.sh` - Version corrigée (gestion mémoire)
- `test_step2_simple.sh` - Script de test

**Traitement**:
- Outlier detection (Isolation Forest: `contamination_rate: 0.03`)
- Calcul : `delta_t`, `Course_change`, `Accel`
- Détection arrêts : `is_stop` (64.53% pour Charles Darwin)
- Ajout colonne : `Annee` (extraction année)

**Sortie**:
- Fichiers nettoyés : `navire_*_clean.rds` (14 colonnes vs 9 originales)

---

## 🏁 STEP 3 : Fusion et Grid Search

### **Script SLURM** : `step3_merge_final.sh`
- **Localisation**: `pipeline_V6/step3_merge_final.sh`
- **Ressources**: 64 GB RAM, 16 CPUs, 4h
- **Script R associé**: `step3_merge_final.R`
- **Chemin R**: `~/R_scripts/pipeline_V6/step3_merge_final.R`

```bash
#SBATCH --job-name=ais_merge_V6_adaptatif
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --time=04:00:00

# Appel R (embedded)
R --vanilla --slave -e "
.libPaths('~/.local/R/4.2.1/')
Sys.setenv(SLURM_JOB_ID = '$SLURM_JOB_ID')
Sys.setenv(SPLIT_JOB_ID = '$SPLIT_JOB_ID')
source('step3_merge_final.R')
"
```

### **Scripts R de Step 3**
| Script R | Type | Description |
|----------|------|-------------|
| `step3_merge_final.R` | ✅ **Principal** | Fusion + GMM + DBSCAN + HMM + Grid Search (1527 lignes) |
| `step3_interactif_detaille.R` | 🔧 Dev | Version interactive |

### **Scripts SLURM alternatifs**
- `step3_merge_final_CORRIGE.sh` - Version corrigée
- `step3_merge_final_FIXED.sh` - Corrections supplémentaires
- `step3_merge_final_OPTIMIZED.sh` - Version optimisée
- `step3_interactif_complet.sh` - Version interactive

**Algorithmes** (dans `step3_merge_final.R`):
1. **Isolation Forest** : Détection outliers
2. **DBSCAN** : Clustering arrêts spatiaux (`eps`, `minPts`)
3. **GMM (Gaussian Mixture Model)** : Classification comportements
4. **HMM (Hidden Markov Model)** : Lissage trajectoires
5. **Grid Search** : Optimisation poids (`w_speed`, `w_accel`, etc.)
6. **LOYO CV** : Leave-One-Year-Out cross-validation
   - Nombre de folds = nombre d'années
   - Métrique : **AUC** (Area Under Curve)

**Sortie**:
- `AIS_data_core_preprocessed_V6_*.rds` - Données fusionnées avec `Dragage_flag`
- `dragage_gridsearch_results_V6_*.rds` - Résultats grid search
  - `best_weights` : Poids optimaux
  - `best_auc` : AUC moyen
  - `auc_sd` : Écart-type AUC
  - `auc_folds` : AUC par fold

---

## 🌍 STEP 4 : Ajout de la lithologie

### **Script SLURM** : `step4_add_lithology.sh`
- **Localisation**: `pipeline_V6/step4_add_lithology.sh`
- **Ressources**: 64 GB RAM, 8 CPUs, 4h
- **Script R associé**: `02_add_lithology_to_AIS_cluster.R`
- **Chemin R**: `~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/02_add_lithology_to_AIS_cluster.R`

```bash
#SBATCH --job-name=ais_lithology_monde
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00

# Conversion RDS → CSV
apptainer exec "$IMG" R --vanilla --slave -e "
  dt <- readRDS(rds)
  fwrite(dt, csv)
"

# Appel R pour lithologie
cd ~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires
apptainer exec "$IMG" R --vanilla --slave -e "
  source('02_add_lithology_to_AIS_cluster.R')
"

# Conversion CSV → RDS
apptainer exec "$IMG" R --vanilla --slave -e "
  dt <- fread(f)
  saveRDS(dt, '$OUT_RDS')
"
```

### **Scripts R de Step 4**
| Script R | Type | Description |
|----------|------|-------------|
| `02_add_lithology_to_AIS_cluster.R` | ✅ **Principal** | Enrichissement lithologie mondiale |

**Colonnes ajoutées**:
- `lithologie` : Type de substrat
- `pl_base` : Probabilité de labilité de base
- `dist_km` : Distance à la côte

**Sortie**:
- `AIS_with_lithology_clean_*.rds` - Données enrichies

---

## ⚡ STEP 5 : Calcul de l'intensité de pêche (f_i)

### 🚨 **Approche 1 : Globale (Obsolète - OOM)**

#### **Script SLURM** : `step5_compute_fi_global.sh`
- **Localisation**: `scripts_cluster/step5_compute_fi_global.sh`
- **Ressources**: 64 GB RAM, 8 CPUs, 12h
- **Script R associé**: `step5_compute_fi_global.R`
- **Chemin R**: `$HOME/R_scripts/step5_compute_fi_global.R`
- **⚠️ Statut** : ❌ **OBSOLÈTE** (Risque OOM > 380 GB)

```bash
#SBATCH --job-name=step5_fi_global
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00

SCRIPT_PATH="$HOME/R_scripts/step5_compute_fi_global.R"
apptainer exec $HOME/scratch/rocker_geospatial_4.5.0.sif Rscript "$SCRIPT_PATH"
```

### **Scripts R de Step 5 (Approche globale)**
| Script R | Type | Description | Statut |
|----------|------|-------------|--------|
| `step5_compute_fi_global.R` | 🗄️ Archive | Calcul f_i monolithique (274 lignes) | ❌ Obsolète |

---

### ✅ **Approche 2 : Modulaire par tuiles (RECOMMANDÉ)**

#### **Version Production** : `ETAPE5_ORGANISEE/04_scripts_slurm/step5_tile_job.sh`

**Script SLURM** : `step5_tile_job.sh` (ETAPE5)
- **Localisation**: `ETAPE5_ORGANISEE/04_scripts_slurm/step5_tile_job.sh`
- **Ressources**: 64 GB RAM, 4 CPUs, 12h
- **Array**: `--array=1-525` (525 tuiles de 1000 km)
- **Script R associé**: `step5_tile_worker_corrected.R`
- **Chemin R**: `$HOME/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/step5_tile_worker_corrected.R`
- **✅ Statut** : **PRODUCTION READY** (10 corrections majeures)

```bash
#SBATCH --account=def-wailung
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-525

TILE_ID=$SLURM_ARRAY_TASK_ID
SCRIPT="$HOME/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/step5_tile_worker_corrected.R"

apptainer exec --bind /scratch,/home,/project "$IMG" \
  Rscript "$SCRIPT" $TILE_ID
```

#### **Version Développement** : `pipeline_V6/step5_modulaire/step5_tile_job.sh`

**Script SLURM** : `step5_tile_job.sh` (pipeline_V6)
- **Localisation**: `pipeline_V6/step5_modulaire/step5_tile_job.sh`
- **Ressources**: 16 GB RAM, 2 CPUs, 12h
- **Array**: `--array=1-648` (648 tuiles)
- **Script R associé**: `step5_tile_worker.R`
- **Chemin R**: `$HOME/scratch/pipeline_V6/step5_modulaire/step5_tile_worker.R`
- **⚠️ Statut** : 🟡 **DEV** (non corrigé)

```bash
#SBATCH --time=12:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#SBATCH --array=1-648

TILE_ID=$SLURM_ARRAY_TASK_ID
SCRIPT="$HOME/scratch/pipeline_V6/step5_modulaire/step5_tile_worker.R"

apptainer exec --bind /scratch,/home --pwd $PWD "$IMG" \
  stdbuf -oL -eL Rscript "$SCRIPT" $TILE_ID
```

### **Scripts R de Step 5 (Approche modulaire)**

#### **Production (ETAPE5_ORGANISEE)** ✅
| Script R | Type | Lignes | Description | Statut |
|----------|------|--------|-------------|--------|
| `step5_tile_worker_corrected.R` | ✅ **Worker** | 337 | Traitement d'une tuile (10 corrections) | **FINAL** |
| `step5_subtile_worker_corrected.R` | ✅ **Sub-worker** | ~150 | Sous-tuiles (optimisation mémoire extrême) | **FINAL** |
| `step5_merge_tiles_optimized_corrected.R` | ✅ **Fusion** | 194 | Fusion finale SAR → f_i | **FINAL** |

#### **Développement (pipeline_V6/step5_modulaire)** 🟡
| Script R | Type | Lignes | Description | Statut |
|----------|------|--------|-------------|--------|
| `step5_tile_worker.R` | 🟡 Worker | ~400 | Version non corrigée | Obsolète |
| `step5_tile_worker_fixed.R` | 🟡 Worker | ~200 | Version intermédiaire | Obsolète |
| `step5_make_tiles.R` | 🔧 Setup | ~100 | Génération grille tuiles 1000km | Valide |
| `step5_merge_tiles.R` | 🟡 Fusion | ~150 | Fusion basique | Obsolète |
| `constants.R` | 📋 Config | 42 | **Constantes partagées** | ✅ **CRITIQUE** |
| `diagnostic_etape5_complet.R` | 📊 Diag | ~200 | Diagnostic complet | Utilitaire |
| `diagnostic_tuiles_coords.R` | 📊 Diag | ~150 | Diagnostic coordonnées | Utilitaire |

### **Autres Scripts R (pipeline_V6)** 🗄️
| Script R | Type | Description | Statut |
|----------|------|-------------|--------|
| `step5_merge_tiles.R` | 🗄️ Archive | Fusion monolithique | Obsolète |
| `step5_merge_tiles_optimized.R` | 🗄️ Archive | Fusion optimisée | Obsolète |

### **Scripts SLURM alternatifs (Step 5)**
- `step5_merge_slurm.sh` - Fusion SLURM basique (obsolète)
- `step5_merge_slurm_optimized.sh` - Fusion optimisée (obsolète)
- `step5_subtile_worker.sh` - Worker sous-tuiles (ETAPE5)

---

### 📊 **Paramètres f_i** (fichier YAML)

**Configuration** : `configuration/fi_parameters.yaml`

```yaml
scenarios:
  default:
    alpha_dep: 0.25           # Atténuation profondeur
    fast_fraction: 0.3        # Fraction pool rapide
    slow_k: 0.05              # Taux reminéralisation lent
    preservation_factor: 0.87 # Facteur préservation
    k_fast: {56 régions}      # Taux rapides par province Longhurst

  conservative:
    inherit: default
    k_fast_multiplier: 0.5    # Réduit k_fast de 50%
    slow_k: 0.025

  upper_bound:
    inherit: default
    alpha_dep: 1.0
    fast_fraction: 1.0
    slow_k: 0.0
```

**Régions Longhurst** : 56 provinces avec k_fast spécifiques
- Exemple : `ALSK: 0.275`, `CARB: 16.8`, `MEDI: 12.3`

---

### 🔑 **Fichier Critique** : `constants.R`

**Localisation** : `pipeline_V6/step5_modulaire/constants.R`

**⚠️ IMPORTANT** : Ce fichier doit être copié dans `ETAPE5_ORGANISEE/02_scripts_modulaires/` !

```r
# Paramètres de tuilage
CELL_KM <- 1000              # Taille tuile (1000 km)
CRS_EQUIVALENT <- 6933       # EPSG:6933 (mètres)

# Emprise mondiale (EPSG:6933)
WORLD_XMIN <- -18000000
WORLD_YMIN <- -9000000
WORLD_XMAX <- 18000000
WORLD_YMAX <- 9000000

# Grille
CELL_SIZE_M <- 1000          # 1 km
CELL_AREA_M2 <- 1e6          # 1 km²
GRID_COLS <- 36000           # Colonnes grille mondiale
GRID_ROWS <- 18000           # Lignes grille mondiale

# Test buffers
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "1"))
TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]
```

**Utilisation** : Sourced par tous les scripts Step 5 modulaires

---

### 📈 **Pipeline Step 5 Modulaire Complet**

**Orchestrateur** : `step5_pipeline_modulaire.sh`

```bash
# 1. Génération des tuiles
apptainer exec Rscript step5_make_tiles.R
  → Crée tiles_1000km.gpkg (525 tuiles)

# 2. Lancement array job
sbatch --array=1-525 step5_tile_job.sh
  → Chaque job exécute step5_tile_worker_corrected.R
  → Produit sar_001.parquet, sar_002.parquet, ..., sar_525.parquet

# 3. Fusion finale
apptainer exec Rscript step5_merge_tiles_optimized_corrected.R
  → Fusionne tous les SAR
  → Calcule f_i par cellule
  → Produit fi_grid_*.parquet
```

**Sortie Step 5** :
- `sar_*.parquet` (525 fichiers) - Résultats par tuile (SAR = Sediment At Risk)
- `fi_grid_*.parquet` - Grille f_i complète (tabulaire)
- `fi_grid_*.rds` - Format R
- `fi_1km_global_*.tif` - Raster GeoTIFF (optionnel)

**Calcul f_i** :
```
f_i = SVR × p_l_corr × p_r × [0.3(1-e^(-k_fast)) + 0.7(1-e^(-0.05))]
où :
  SVR = SAR × p_d  (p_d=1 pour TSHD)
  p_l_corr = p_l × freshness_factor
  p_r = preservation_factor
```

---

## 📊 STEP 6 : Calcul du CRI (Carbon Remineralized Index)

### **Script SLURM** : `step6_calculate_cri.sh`
- **Localisation**: `scripts_cluster/step6_calculate_cri.sh`
- **Ressources**: 64 GB RAM, 4 CPUs, 8h
- **Script R associé**: `step6_calculate_cri_corrected.R`
- **Chemin R**: `$HOME/scratch/ETAPE5_ORGANISEE/01_scripts_principaux/step6_calculate_cri_corrected.R`

```bash
#SBATCH --job-name=step6_calculate_cri
#SBATCH --time=8:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4

SCRIPT_PATH="$HOME/scratch/ETAPE5_ORGANISEE/01_scripts_principaux/step6_calculate_cri_corrected.R"

apptainer exec --bind /scratch,/home,/project "$SIF_PATH" \
  Rscript "$SCRIPT_PATH" "/home/benl/scratch/output_V6/fi_grid_*.parquet"
```

### **Scripts R de Step 6**
| Script R | Type | Lignes | Description | Statut |
|----------|------|--------|-------------|--------|
| `step6_calculate_cri_corrected.R` | ✅ **Principal** | 135 | Calcul C_ri avec caps et bornes | **FINAL** |
| `step6_calculate_cri.R` | 🗄️ Archive | ~120 | Version pipeline_V6 | Obsolète |

**Entrées** :
- `fi_grid_*.parquet` (Step 5) - Grille f_i
- Rasters C0i (Atwood) - Stocks de carbone initial
- `trawling_history.rds` - Historique chalutage (facteur di)

**Calcul C_ri** :
```r
# Facteur de déplétion
di = fifelse(years_trawled > 10, 0.272, 1.0)

# Carbone reminéralisé (avec caps)
C_ri = pmin(C0i × f_i_full × di, C0i)
C_ri_lower = pmin(C0i_lower × f_i_full × di, C0i_lower)
C_ri_upper = pmin(C0i_upper × f_i_full × di, C0i_upper)
C_ri_conservative = pmin(C0i × f_i_conservative × di, C0i)
```

**Sortie** :
- `cri_final_*.rds` - Données tabulaires
- `cri_final_*.parquet` - Format Arrow
- `cri_final_*.tif` - Raster GeoTIFF (scénario default)
- `cri_final_*_lower.tif` - Borne inférieure
- `cri_final_*_upper.tif` - Borne supérieure

**Colonnes** :
- `grid_id`, `x`, `y`, `col`, `row`
- `f_i_full`, `f_i_conservative`
- `C0i`, `C0i_lower`, `C0i_upper` (Atwood)
- `di` (facteur déplétion)
- `C_ri`, `C_ri_lower`, `C_ri_upper`, `C_ri_conservative`

---

## 📊 RÉSUMÉ : Flux de données

```
STEP 0: step0_window_select.sh → step0_core_window.R
   ↓ core_window_report.md, best_core_window.csv

STEP 1: step1_split_navires.sh → step1_split_navires.R
   ↓ navire_01_*.rds, navire_02_*.rds, ... (11 navires)

STEP 2: step2_process_array.sh (array 1-12) → step2_process_navire.R
   ↓ navire_*_clean.rds (14 colonnes avec is_stop, Annee, outlier_IF)

STEP 3: step3_merge_final.sh → step3_merge_final.R
   ↓ AIS_data_core_preprocessed_V6_*_flagOK.rds (avec Dragage_flag)
   ↓ dragage_gridsearch_results_V6_*.rds (AUC, poids optimaux)

STEP 4: step4_add_lithology.sh → 02_add_lithology_to_AIS_cluster.R
   ↓ AIS_with_lithology_clean_*.rds (avec lithologie, pl_base)

STEP 5: step5_tile_job.sh (array 1-525) → step5_tile_worker_corrected.R
   ↓ sar_*.parquet (525 tuiles)
   → step5_merge_tiles_optimized_corrected.R
   ↓ fi_grid_*.parquet (grille f_i mondiale 1km)

STEP 6: step6_calculate_cri.sh → step6_calculate_cri_corrected.R
   ↓ cri_final_*.parquet (C_ri avec bornes)
   ↓ cri_final_*.tif (raster GeoTIFF)
```

---

## 🎯 FICHIERS FINAUX À UTILISER (Production)

### **ETAPE5_ORGANISEE/** ✅ **RECOMMANDÉ**

```
ETAPE5_ORGANISEE/
├── 01_scripts_principaux/
│   ├── step5_merge_tiles_optimized_corrected.R    ✅ FINAL
│   └── step6_calculate_cri_corrected.R            ✅ FINAL
│
├── 02_scripts_modulaires/
│   ├── constants.R                                ❌ MANQUANT (à copier)
│   ├── step5_tile_worker_corrected.R              ✅ FINAL
│   ├── step5_subtile_worker_corrected.R           ✅ FINAL
│   └── 02_add_lithology_to_AIS_cluster.R          ✅ FINAL
│
└── 04_scripts_slurm/
    ├── step5_tile_job.sh                          ✅ FINAL
    └── step5_subtile_worker.sh                    ✅ FINAL
```

### **pipeline_V6/** 🟡 **Développement**

```
pipeline_V6/
├── step0_core_window.R                            ✅ Valide
├── step1_split_navires.R                          ✅ Valide
├── step2_process_navire.R                         ✅ Valide
├── step3_merge_final.R                            ✅ Valide (1527 lignes)
├── step5_modulaire/
│   ├── constants.R                                ✅ CRITIQUE (à copier)
│   ├── step5_make_tiles.R                         ✅ Valide
│   ├── step5_tile_worker.R                        🟡 Dev (non corrigé)
│   └── step5_tile_worker_fixed.R                  🟡 Dev
│
└── step0_window_select.sh → step4_add_lithology.sh  ✅ Valides
```

### **scripts_cluster/** 🗄️ **Archive (Obsolète)**

```
scripts_cluster/
├── step5_compute_fi_global.R                      ❌ Obsolète (OOM)
├── step5_compute_fi_global.sh                     ❌ Obsolète
└── step6_calculate_cri.sh                         🔄 Redirige vers ETAPE5
```

---

## ⚠️ ACTIONS REQUISES

### 1. **Copier `constants.R`** ❗ URGENT
```bash
cp pipeline_V6/step5_modulaire/constants.R \
   ETAPE5_ORGANISEE/02_scripts_modulaires/
```
**Raison** : Tous les scripts `*_corrected.R` le sourcent !

### 2. **Utiliser les scripts ETAPE5_ORGANISEE** ✅
- Pour Step 5 : `ETAPE5_ORGANISEE/04_scripts_slurm/step5_tile_job.sh`
- Pour Step 6 : Utiliser `step6_calculate_cri_corrected.R`

### 3. **Ignorer les versions obsolètes** ❌
- `step5_compute_fi_global.R` (monolithique)
- `step5_tile_worker.R` (non corrigé)
- `step5_merge_tiles.R` (basique)

---

## 📈 STATISTIQUES

### **Lignes de code R**
- **Step 3** : 1527 lignes (`step3_merge_final.R`)
- **Step 5 worker** : 337 lignes (`step5_tile_worker_corrected.R`)
- **Step 5 global** : 274 lignes (`step5_compute_fi_global.R` - obsolète)
- **Step 6** : 135 lignes (`step6_calculate_cri_corrected.R`)

### **Fichiers par type**
- **Scripts SLURM** : ~30 fichiers (.sh)
- **Scripts R** : ~40 fichiers (.R)
- **Versions finales** : 8 scripts (ETAPE5_ORGANISEE)
- **Configuration** : 7 fichiers YAML (fi_parameters_*)

### **Ressources typiques**
- **Steps 0-2** : 6-8 GB RAM, 2-4 CPUs
- **Step 3** : 64 GB RAM, 16 CPUs (fusion + grid search)
- **Step 4-6** : 64 GB RAM, 4-8 CPUs
- **Step 5 modulaire** : 16-64 GB RAM par tuile

### **Temps d'exécution estimé**
- **Step 0** : ~3 min
- **Step 1** : ~3 min
- **Step 2** : ~3-6 min (array parallèle)
- **Step 3** : ~4h (grid search)
- **Step 4** : ~2-4h
- **Step 5** : ~1h (parallélisé, 525 tuiles) vs 10h+ (monolithique)
- **Step 6** : ~30 min

**Total pipeline** : ~6-10 heures

---

## 🔗 DOCUMENTATION ASSOCIÉE

### **READMEs**
- `pipeline_V6/README_ETAPES_0_1_2.md` - Steps 0-2 détaillés
- `pipeline_V6/step5_modulaire/README_STEP5_MODULAIRE.md` - Step 5 complet
- `pipeline_V6/step5_modulaire/CORRECTIFS_APPLIQUES.md` - 10 corrections

### **Configuration**
- `configuration/fi_parameters.yaml` - Paramètres f_i (3 scénarios)
- `configuration/outlier_config_V6.yaml` - Isolation Forest (Step 2)

### **Autres analyses**
- `LO_METHODS_GAP_ANALYSIS.md` - Analyse lacunes pour publication

---

**Document créé** : 2026-01-08
**Auteur** : Claude (analyse automatisée)
**But** : Cartographie complète SLURM ↔ R pour navigation pipeline
