#!/bin/bash
###############################################################################
#  SLURM – CO2 MODEL WITH DREDGING FORCING (OCIM2-48L)
#  Runs baseline + 1x/10x/100x dredging scenarios
###############################################################################
#SBATCH --job-name=co2model_dredge
#SBATCH --mem=32G
#SBATCH --cpus-per-task=2
#SBATCH --time=16:00:00
#SBATCH --chdir=/home/bloe/scratch/configuration/ocim
#SBATCH --output=/home/bloe/logs/co2model_%j.out
#SBATCH --error=/home/bloe/logs/co2model_%j.err

echo "=== CO2 MODEL DREDGE (job $SLURM_JOB_ID) ==="
echo "Node:  $SLURMD_NODENAME"
echo "Debut: $(date)"
echo ""

# MATLAB path (GRIT-specific)
export PATH=/home/matlab/current/bin:${PATH}

# Working directory
OCIM_DIR=~/scratch/configuration/ocim
cd "$OCIM_DIR" || { echo "Repertoire manquant: $OCIM_DIR"; exit 2; }
echo "Repertoire: $(pwd)"

# Pre-flight checks
echo ""
echo "--- Pre-flight ---"

if ! which matlab >/dev/null 2>&1; then
    echo "ERREUR: matlab non trouve dans PATH"
    exit 1
fi
echo "MATLAB: $(which matlab)"

for f in OCIM2_48L_CTL.mat woa09po4.mat woa09si.mat schmidt_coeff.mat \
         co2model_dredge.m d0.m co2model.m ns_step_eb.m eqdic.m eqco2.m \
         CO2SYS.m nsnew.m nsgmres.m mfactor.m schmidt.m sw_pres.m \
         inpaint_nans.m netemission.txt; do
    if [ -f "$f" ]; then
        echo "  OK: $f ($(du -h "$f" | cut -f1))"
    else
        echo "  MANQUANT: $f"
    fi
done

JDREDGE=$(ls -t jdredge_ocim2_48l_*.mat 2>/dev/null | head -1)
if [ -z "$JDREDGE" ]; then
    echo "ERREUR: Aucun fichier jdredge_ocim2_48l_*.mat trouve"
    echo "  Lancez d'abord Step 7"
    exit 1
fi
echo "  Jdredge: $JDREDGE ($(du -h "$JDREDGE" | cut -f1))"

echo ""
echo "--- Lancement co2model_dredge.m ---"
echo ""

matlab -nodesktop -nodisplay -nosplash -batch "run('co2model_dredge.m')"

exit_code=$?
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "CO2 MODEL termine avec succes : $(date)"
    echo "Fichiers generes :"
    ls -lh dredging_results_*.mat 2>/dev/null || echo "   Aucun fichier resultat trouve"
else
    echo "CO2 MODEL a echoue (code $exit_code)"
    exit $exit_code
fi
