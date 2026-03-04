#!/bin/bash
###############################################################################
#  SLURM – CO2MODEL_BATCH : OCIM2-48L dredging perturbation (MATLAB)
###############################################################################
#SBATCH --job-name=co2model
#SBATCH --partition=emlab_nodes
#SBATCH --mem=64G
#SBATCH --cpus-per-task=4
#SBATCH --time=06:00:00
#SBATCH --chdir=/home/bloe/scratch/configuration/ocim
#SBATCH --output=/home/bloe/logs/co2model_%j.out
#SBATCH --error=/home/bloe/logs/co2model_%j.err

echo "=== CO2MODEL_BATCH (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"

cd /home/bloe/scratch/configuration/ocim || { echo "Repertoire manquant"; exit 2; }

# Pre-flight: forcing file
FORCING=$(ls -t /home/bloe/scratch/output_V6/jdredge_ocim2_48l_*.mat 2>/dev/null | head -1)
if [ -z "$FORCING" ]; then
    echo "Aucun jdredge_ocim2_48l_*.mat dans ~/scratch/output_V6/"
    echo "   Lancez d'abord Step 7"
    exit 1
fi
echo "Forcing: $FORCING"

# Pre-flight: OCIM data
for f in OCIM2_48L_CTL.mat woa09si.mat woa09po4.mat netemission.txt; do
    if [ ! -f "$f" ]; then
        echo "Fichier manquant: $f"
        exit 1
    fi
done
echo "Toutes les dependances presentes"

echo ""
echo "Lancement co2model_batch.m ..."

matlab -batch "forcing_file='$FORCING'; run('co2model_batch.m')"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "CO2MODEL termine avec succes : $(date)"
    echo "Fichiers generes :"
    ls -lh /home/bloe/scratch/output_V6/ocim_*.mat 2>/dev/null || echo "   Aucun fichier ocim trouve"
else
    echo "CO2MODEL a echoue (code $exit_code)"
    exit $exit_code
fi
