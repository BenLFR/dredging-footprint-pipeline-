# 🚀 Pipeline Step-5 Modulaire - Documentation

## 📋 Vue d'ensemble

Le **Pipeline Step-5 Modulaire** résout définitivement le problème de mémoire (OOM) en découpant le traitement mondial en tuiles gérables. Cette approche permet de traiter des volumes de données massifs sans dépasser les limites mémoire du cluster.

## 🎯 Avantages de l'approche modulaire

| Aspect | Avant (Monolithique) | Après (Modulaire) |
|--------|---------------------|-------------------|
| **Mémoire** | > 380 GB (OOM) | ≤ 48 GB par tuile |
| **Parallélisme** | Séquentiel | Array-job (40+ nœuds) |
| **Robustesse** | Crash sur OOM | Traitement fiable |
| **Fichiers** | GeoPackage massif | Parquet/GeoTIFF compact |
| **Temps total** | ~10h + crash | ~1h (parallélisé) |

## 📁 Structure des fichiers

```
pipeline_V6/
└── step5_modulaire/
    ├── constants.R                    # Constantes partagées
    ├── step5_make_tiles.R            # Génération des tuiles mondiales
    ├── step5_tile_job.sh             # Script SLURM array-job
    ├── step5_tile_worker.R           # Traitement d'une tuile
    ├── step5_merge_tiles.R           # Fusion finale
    ├── step5_pipeline_modulaire.sh   # Orchestration complète
    └── README_STEP5_MODULAIRE.md     # Cette documentation
```

## 🔧 Prérequis

### 1. Environnement cluster
```bash
module load StdEnv/2023 apptainer
```

### 2. Fichiers requis
- `~/scratch/rocker_geospatial_step5.sif` (image Apptainer)
- `~/scratch/configuration/fi_parameters.yaml` (paramètres f_i)
- `~/scratch/configuration/ship_specs.yaml` (specs navires)
- `~/scratch/output_V6/AIS_data_core_preprocessed_V6_*flagOK.rds` (données AIS)

### 3. Répertoires
- `~/scratch/output_V6/` (sorties)
- `~/scratch/configuration/` (configurations)

## 🚀 Utilisation

### Option 1 : Pipeline complet automatisé
```bash
# Aller dans le répertoire modulaire
cd step5_modulaire

# Lancement du pipeline complet
chmod +x step5_pipeline_modulaire.sh
./step5_pipeline_modulaire.sh

# Avec nettoyage automatique des fichiers temporaires
./step5_pipeline_modulaire.sh --cleanup

# Avec génération du raster GeoTIFF (+2.6 GB RAM)
./step5_pipeline_modulaire.sh --make-tiff

# Combinaison des options
./step5_pipeline_modulaire.sh --cleanup --make-tiff

# Afficher l'aide
./step5_pipeline_modulaire.sh --help
```

### Option 2 : Étapes manuelles

#### Étape 1 : Génération des tuiles
```bash
cd step5_modulaire
apptainer exec --bind /scratch,/home --pwd $PWD ~/scratch/rocker_geospatial_step5.sif \
    Rscript step5_make_tiles.R
```

#### Étape 2 : Lancement des jobs de tuiles
```bash
cd step5_modulaire
# Compter les tuiles
n_tiles=$(ogrinfo -geom=no -q -al ~/scratch/output_V6/tiles_5000km.gpkg | grep "feature id" | wc -l)

# Lancer l'array-job
sbatch --array=1-$n_tiles step5_tile_job.sh
```

#### Étape 3 : Fusion finale
```bash
cd step5_modulaire
apptainer exec --bind /scratch,/home --pwd $PWD ~/scratch/rocker_geospatial_step5.sif \
    Rscript step5_merge_tiles.R
```

## 📊 Monitoring

### Suivi des jobs
```bash
# Voir tous les jobs Step-5
squeue -u $USER | grep step5

# Voir les logs d'une tuile spécifique
tail -f logs/step5_tile_1_*.out

# Vérifier le statut d'un array-job
scontrol show job <job_id>

# Vérifier le statut final avec sacct
sacct -j <job_id> --format=JobID,JobName,State,ExitCode,MaxRSS
```

### Vérification des résultats
```bash
# Compter les fichiers de résultats
ls -1 ~/scratch/output_V6/sar_*.parquet | wc -l

# Vérifier la taille des fichiers
ls -lh ~/scratch/output_V6/fi_*
```

## 🔍 Détails techniques

### Paramètres de tuilage
- **Taille de tuile** : 5000 × 5000 km (cohérent avec `tiles_5000km.gpkg`)
- **Nombre de tuiles** : ~14 (selon l'emprise mondiale)
- **Buffer** : 2 km autour de chaque tuile
- **Résolution finale** : 1 km²
- **Constantes partagées** : `constants.R` pour harmoniser tous les scripts

### Gestion mémoire
- **Limite par tuile** : 48 GB
- **Threads data.table** : 1 (évite la duplication)
- **Threads BLAS/OMP** : 1 (contrôle mémoire)
- **Nettoyage** : `gc()` toutes les 100 itérations

### Formats de sortie
- **Parquet** : Compact, rapide (si `arrow` disponible)
- **RDS** : Fallback universel
- **GeoTIFF** : Raster compressé (si `terra` disponible)

## 🛠️ Dépannage

### Problème : "Aucun ping de dragage dans la tuile"
**Solution** : Normal pour les tuiles océaniques vides. Le script sort proprement.

### Problème : "Fichier de tuiles manquant"
**Solution** : Relancer `step5_make_tiles.R`

### Problème : "Array-job échoué"
**Solution** : Vérifier les logs individuels dans `logs/step5_tile_*_*.err`

### Problème : "Mémoire insuffisante"
**Solution** : Réduire `--mem` dans `step5_tile_job.sh` ou augmenter la taille des tuiles dans `constants.R`.

### Problème : "Package arrow non disponible"
**Solution** : Le script utilise automatiquement RDS en fallback. Vérifier la version d'arrow si nécessaire.

## 📈 Optimisations possibles

### 1. Taille des tuiles
```r
# Dans constants.R
CELL_KM <- 3000   # Tuiles plus petites = moins de mémoire
```

### 2. Parallélisation
```bash
# Dans step5_tile_job.sh
#SBATCH --cpus-per-task=12  # Plus de CPU si disponible
```

### 3. Mémoire par tuile
```bash
# Dans step5_tile_job.sh
#SBATCH --mem=64G  # Plus de mémoire si nécessaire
```

## 🎯 Résultats attendus

### Fichiers de sortie
- `fi_grid_YYYYMMDD_HHMMSS.parquet` : Données tabulaires complètes
- `fi_grid_YYYYMMDD_HHMMSS.rds` : Données R
- `fi_1km_global_YYYYMMDD_HHMMSS.tif` : Raster GeoTIFF (optionnel, avec `--make-tiff`)

### Statistiques typiques
- **Cellules totales** : ~648 millions (36000×18000)
- **Cellules avec dragage** : ~1-5 millions
- **Cellules avec f_i > 0** : ~500k-2M
- **Taille fichier** : 2-6 GB (vs 100+ GB avant)

## 🔄 Migration depuis l'ancien pipeline

### 1. Sauvegarder l'ancien
```bash
mv step5_compute_fi_global.R step5_compute_fi_global_old.R
mv step5_compute_fi_global.sh step5_compute_fi_global_old.sh
```

### 2. Tester le nouveau
```bash
./step5_pipeline_modulaire.sh
```

### 3. Comparer les résultats
```r
# Comparaison des f_i
old <- readRDS("step5_old.rds")
new <- arrow::read_parquet("fi_grid_new.parquet")
cor(old$f_i_full, new$f_i_full, use="complete.obs")
```

## 📞 Support

En cas de problème :
1. Vérifier les logs dans `logs/`
2. Contrôler l'espace disque : `df -h ~/scratch`
3. Vérifier les modules : `module list`
4. Consulter la queue SLURM : `squeue -u $USER`

---

**✅ Le pipeline modulaire garantit un traitement fiable et efficace des données mondiales !** 