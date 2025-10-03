#!/bin/bash
#SBATCH --job-name=ais_lithology_monde
#SBATCH --mem=64G
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --account=def-wailung
#SBATCH -o /home/%u/scratch/logs/step4_lithology_monde_%j.out
#SBATCH -e /home/%u/scratch/logs/step4_lithology_monde_%j.err

set -euo pipefail

module load StdEnv/2023 apptainer/1.3.5 || module load apptainer/1.3.5
IMG=~/scratch/rocker_geospatial_step5.sif; [ -f "$IMG" ] || IMG=~/scratch/images/rocker_geospatial_step5.sif

R4=~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires/02_add_lithology_to_AIS_cluster.R
RDS=~/scratch/output/AIS_data_core_preprocessed_V6_20250726_130813_flagOK.rds
CSV_IN=~/scratch/output/AIS_data_core_preprocessed.csv
CSV_OUT=~/scratch/output/AIS_with_lithology_clean.csv

echo "🏁 === ÉTAPE 4: AJOUT LITHOLOGIE (MONDE) ==="; date

# 1) Si le RDS step3 existe, le convertir au CSV attendu par le script R
apptainer exec --bind /scratch,/home,/project "$IMG" R --vanilla --slave -e "
  library(data.table)
  rds <- '$RDS'; csv <- '$CSV_IN'
  if (file.exists(rds)) {
    dt <- readRDS(rds)
    # Harmoniser colonnes Lon/Lat si besoin
    if (!('Lon' %in% names(dt)) && any(tolower(names(dt))=='lon'))
      setnames(dt, which(tolower(names(dt))=='lon'), 'Lon')
    if (!('Lat' %in% names(dt)) && any(tolower(names(dt))=='lat'))
      setnames(dt, which(tolower(names(dt))=='lat'), 'Lat')
    fwrite(dt, csv)
    cat('Source AIS:', basename(rds), '\\n')
  } else {
    cat('Avertissement: RDS step3 non trouvé, le script R lira', '$CSV_IN', 's i existant\\n')
  }
"

# 2) Lancer le script R d’origine (lit CSV_IN, produit CSV_OUT)
cd ~/scratch/ETAPE5_ORGANISEE/02_scripts_modulaires
apptainer exec --bind /scratch,/home,/project "$IMG" R --vanilla --slave -e "source('02_add_lithology_to_AIS_cluster.R')"

# 3) Convertir la sortie CSV en RDS pour la step5 (dans output_V6)
ts=$(date +%Y%m%d_%H%M%S)
OUT_RDS=~/scratch/output_V6/AIS_with_lithology_clean_${ts}.rds
apptainer exec --bind /scratch,/home,/project "$IMG" R --vanilla --slave -e "
  library(data.table)
  f <- '$CSV_OUT'
  if (!file.exists(f)) stop('Sortie introuvable: ', f)
  dt <- fread(f)
  saveRDS(dt, '$OUT_RDS')
  cat('RDS écrit:', '$OUT_RDS', '\\n')
  if ('Dragage_flag' %in% names(dt)) print(table(dt\$Dragage_flag, useNA='ifany'))
"

echo "✅ Terminé"; date
