#!/bin/bash
# quick sanity-check: constants  •  YAML  •  worker on tile 1
# run:  chmod +x test_constants.sh && ./test_constants.sh
set -e

ROOT=$HOME/scratch/pipeline_V6/step5_modulaire
IMG=$HOME/scratch/rocker_geospatial_step5.sif

module load StdEnv/2023 apptainer       # make sure both are in PATH
cd "$ROOT"

echo -e "\n🧪 1 / 3  Loading constants …"
apptainer exec --bind /scratch,/home --pwd "$PWD" "$IMG" \
  Rscript --vanilla -e "
    source('$ROOT/constants.R')
    cat('   CELL_SIZE_M   =', CELL_SIZE_M ,'\n')
    cat('   TILE_BUFFER_M =', TILE_BUFFER_M,'\n')
  "

echo -e "\n🧪 2 / 3  Parsing ship_specs_clean.yaml …"
apptainer exec --bind /scratch,/home --pwd "$PWD" "$IMG" \
  Rscript --vanilla -e "
    specs <- yaml::read_yaml('~/scratch/configuration/ship_specs_clean.yaml')\$ship_specs
    if (length(specs)) {
      cat('   ✅  parsed', length(specs), 'ships\n')
    } else {
      cat('   ❌  YAML empty or unreadable\n')
    }
  "

echo -e "\n🧪 3 / 3  Running worker on tile 1 …"
apptainer exec --bind /scratch,/home --pwd "$PWD" "$IMG" \
  Rscript --vanilla "$ROOT/step5_tile_worker.R" 1 