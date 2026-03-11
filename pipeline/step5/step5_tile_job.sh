#!/bin/bash
#SBATCH --job-name=step5b_tile
#SBATCH --time=12:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=2
#SBATCH --array=1-525%20
# Uncomment and set the partition for your cluster:
# #SBATCH --partition=emlab_nodes,grit_nodes
#SBATCH --output=logs/step5b_%A_%a.out
#SBATCH --error=logs/step5b_%A_%a.err

export R_LIBS_USER=~/R/library
export LD_LIBRARY_PATH=$HOME/lib:${LD_LIBRARY_PATH:-}

TILE_ID=$SLURM_ARRAY_TASK_ID
PIPELINE_DIR="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"
SCRIPT="$PIPELINE_DIR/step5_tile_worker.R"
TILES_FILE="$SCRATCH_DIR/output_V6/tiles_1000km.gpkg"

echo "$(date) -- Starting tile $TILE_ID on $(hostname)"

mkdir -p "$PIPELINE_DIR/logs"

if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: R script not found: $SCRIPT"
  exit 1
fi
if [ ! -f "$TILES_FILE" ]; then
  echo "ERROR: Tiles file not found: $TILES_FILE"
  exit 1
fi

Rscript "$SCRIPT" "$TILE_ID"

if [ $? -eq 0 ]; then
  echo "$(date) -- Tile $TILE_ID completed successfully"
else
  echo "$(date) -- Tile $TILE_ID FAILED"
  exit 1
fi
