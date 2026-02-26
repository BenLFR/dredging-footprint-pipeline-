# Plan: Adapter Step 6 (CRI) pour GRIT

## Contexte

Step 5 vient de terminer (job 24812) et a produit `fi_grid_*.parquet` dans `~/scratch/output_V6/` sur grit. On doit maintenant lancer Step 6 qui calcule le carbone reminералise (C_ri = C0i x f_i x di) en utilisant les rasters Atwood.

Deux versions de step6 existent :
- `pipeline_V6/pipeline_V6/step6_calculate_cri.R` — grille 36k x 18k hardcodee, pas de constants.R
- `step6_calculate_cri_corrected.R` (racine) — utilise constants.R (34735 x 14685), caps physiques, meilleure robustesse

**On part de la version corrigee** (`step6_calculate_cri_corrected.R`) qui est la plus proche de la production.

## Fichiers a creer/modifier

### 1. Adapter `step6_calculate_cri_corrected.R` -> `pipeline_V6/step6_calculate_cri.R`

Adaptations necessaires (meme pattern que step5_merge_tiles_optimized.R) :

**a) Sourcing constants.R — utiliser le pattern `this_file()` robuste :**
```r
this_file <- function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  if (length(f)) return(normalizePath(f))
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile))
  stop("Cannot locate running script")
}
script_dir <- dirname(this_file())
source(file.path(script_dir, "constants.R"))
```
Remplace le bloc actuel (lignes 14-17) qui a un fallback hardcode `~/ais-pipeline/pipeline_V6`.

**b) Chemin carbone Atwood :**
```r
carbon_dir <- path.expand("~/scratch/configuration/atwood_carbon")
```
Remplace `/home/benl/scratch/configuration/atwood_carbon_full` (les TIFs seront uploades la).

**c) Chemin de sortie :**
```r
out_dir <- path.expand("~/scratch/output_V6")
output_prefix <- file.path(out_dir, paste0("cri_final_", timestamp))
```
Remplace `/scratch/benl/output_V6/` (qui est specifique a Beluga).

**d) GeoTIFF — correction row inversion (meme Fix E que step5) :**
La fonction `write_cri_raster` actuelle fait `g[fi_dt$grid_id] <- values` qui suppose un indexage top-down terra. Il faut utiliser le meme pattern que step5 avec inversion row :
```r
write_cri_raster <- function(values, grid_ids, filename) {
  r <- terra::rast(nrows=GRID_ROWS, ncols=GRID_COLS, crs="EPSG:6933",
                   xmin=WORLD_XMIN, xmax=WORLD_XMAX, ymin=WORLD_YMIN, ymax=WORLD_YMAX)
  vals <- rep(NA_real_, ncell(r))
  cols <- (grid_ids - 1L) %% GRID_COLS
  rows <- (grid_ids - 1L) %/% GRID_COLS
  inds <- (GRID_ROWS - 1L - rows) * GRID_COLS + cols + 1L
  vals[inds] <- values
  values(r) <- vals
  writeRaster(r, filename, datatype="FLT4S", overwrite=TRUE,
              gdal=c("COMPRESS=LZW", "TILED=YES", "BLOCKXSIZE=512", "BLOCKYSIZE=512"))
  cat("GeoTIFF ecrit :", basename(filename), "\n")
}
```

**e) Template raster — utiliser constants.R :**
Le `template_raster` pour reprojection Atwood doit utiliser GRID_ROWS/GRID_COLS/WORLD_* au lieu de 18000/36000/-18M/+18M.

**f) Terra temp dir :**
```r
tmp_terra <- file.path(path.expand("~"), "scratch/tmp_terra")
```
(deja correct dans la version corrigee)

### 2. Creer `pipeline_V6/step6_cri_slurm.sh`

Meme structure que `step5_merge_slurm_optimized.sh` :

```bash
#!/bin/bash
#SBATCH --job-name=step6_cri
#SBATCH --output=logs/step6_cri_%j.out
#SBATCH --error=logs/step6_cri_%j.err
#SBATCH --time=04:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --nodelist=hpc-05.grit.ucsb.edu

export R_LIBS_USER=~/R/library
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

PIPELINE_DIR=~/ais-pipeline/pipeline_V6
mkdir -p $PIPELINE_DIR/logs

echo "=== ETAPE 6: CALCUL CRI ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Debut: $(date)"

# Verifications
for f in $PIPELINE_DIR/step6_calculate_cri.R \
         $PIPELINE_DIR/constants.R \
         ~/scratch/configuration/atwood_carbon; do
  [ -e "$f" ] || { echo "ERREUR: manquant: $f"; exit 1; }
done

FI_COUNT=$(ls ~/scratch/output_V6/fi_grid_*.parquet 2>/dev/null | wc -l)
echo "Fichiers fi_grid trouves: $FI_COUNT"
[ "$FI_COUNT" -eq 0 ] && { echo "ERREUR: pas de fi_grid"; exit 1; }

/usr/bin/Rscript $PIPELINE_DIR/step6_calculate_cri.R 2>&1

exit_code=$?
if [ $exit_code -eq 0 ]; then
  echo "Step 6 CRI termine: $(date)"
  ls -lh ~/scratch/output_V6/cri_final_* 2>/dev/null
else
  echo "ERREUR Step 6: code $exit_code"
  exit $exit_code
fi

echo "=== ETAPE 6 CRI TERMINEE ==="
```

### 3. Uploader les rasters Atwood sur grit

Les 4 fichiers TIF sont dans `installation/atwood_carbon/` localement :
- `Mean carbon_stock.tif`
- `global_error_lower_bound.tif`
- `global_error_upper_bound.tif`
- `global_error_range.tif`

```bash
scp -F ~/.ssh/config_grit "installation/atwood_carbon/*.tif" grit:~/scratch/configuration/atwood_carbon/
```

(Creer le dossier distant d'abord : `ssh grit "mkdir -p ~/scratch/configuration/atwood_carbon"`)

## Deploiement

1. Creer le script R adapte : `pipeline_V6/step6_calculate_cri.R`
2. Creer le SLURM wrapper : `pipeline_V6/step6_cri_slurm.sh`
3. Uploader les Atwood TIFs sur grit
4. SCP les deux scripts sur grit
5. `sbatch step6_cri_slurm.sh`

## Verification

1. **Fichiers output** : `cri_final_*.parquet`, `cri_final_*.rds`, `cri_final_*.tif` dans `~/scratch/output_V6/`
2. **C_ri physiquement borne** : C_ri <= C0i pour toute cellule
3. **Nombre de cellules** : doit correspondre au fi_grid (~33583)
4. **GeoTIFF aligne** : meme emprise/resolution que fi_grid_*.tif de step5
