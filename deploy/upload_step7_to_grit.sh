#!/bin/bash
# Upload Step 7 files to GRIT cluster
# Usage:
#   bash deploy/upload_step7_to_grit.sh [--no-ocim] [--co2model-src <dir>]
#
# Uses TWO connections:
#  1) scp: uploads files to staging dir
#  2) ssh: moves files to final locations + verification

set -e

SSH_CONFIG="$HOME/.ssh/config_grit"
REMOTE="grit"

echo "=========================================="
echo "UPLOAD STEP 7 FILES TO GRIT"
echo "=========================================="
echo ""

# Collect files into staging directory
STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

echo "Preparation des fichiers..."

cp step7_export_jtrawl.R "$STAGING/"
cp step7_extract_ocim_cache.m "$STAGING/"
cp step7_extract_ocim_cache.py "$STAGING/"
cp constants.R "$STAGING/"
cp scripts_cluster/step7_export_jtrawl_grit.sh "$STAGING/"
cp pipeline_V6/audit_jdredge.py "$STAGING/"

# Precomputed oceanfrac2d.mat (small, always upload)
if [ -f "configuration/ocim/oceanfrac2d.mat" ]; then
    cp configuration/ocim/oceanfrac2d.mat "$STAGING/"
    echo "   + oceanfrac2d.mat (precomputed ocean fraction)"
else
    echo "   WARNING: configuration/ocim/oceanfrac2d.mat not found — run precompute_oceanfrac2d.py first"
fi

echo "   $(ls "$STAGING" | wc -l) fichiers ($(du -sh "$STAGING" | cut -f1))"
echo ""

# Optional:
# - upload OCIM2_48L_CTL.mat if available locally (skip with --no-ocim)
# - provide explicit CO2 model source directory with --co2model-src
SKIP_OCIM=false
CO2MODEL_SRC_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-ocim)
            SKIP_OCIM=true
            shift
            ;;
        --co2model-src)
            [[ $# -ge 2 ]] || { echo "Option --co2model-src requires a directory path"; exit 2; }
            CO2MODEL_SRC_ARG="$2"
            shift 2
            ;;
        --co2model-src=*)
            CO2MODEL_SRC_ARG="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 2
            ;;
    esac
done

OCIM_LOCAL=""
OCIM_MODEL_DIR=""
if [ "$SKIP_OCIM" = false ]; then
    for candidate in \
        "Trawling model-20250623T085752Z-1-001/Trawling model/OCIM2_48L_CTL.mat" \
        "installation/ocim/OCIM2_48L_CTL.mat" \
        "configuration/ocim/OCIM2_48L_CTL.mat" \
        "OCIM2_48L_CTL.mat"; do
        if [ -f "$candidate" ]; then
            OCIM_LOCAL="$candidate"
            break
        fi
    done
fi

if [ -n "$OCIM_LOCAL" ]; then
    OCIM_MODEL_DIR=$(dirname "$OCIM_LOCAL")
    echo "OCIM source found: $OCIM_LOCAL ($(du -h "$OCIM_LOCAL" | cut -f1))"
    echo "   Will upload to ~/scratch/configuration/ocim/"
    cp "$OCIM_LOCAL" "$STAGING/"
    # Optional support files commonly distributed with OCIM assets
    for matfile in schmidt_coeff.mat woa09po4.mat woa09si.mat; do
        if [ -f "$OCIM_MODEL_DIR/$matfile" ]; then
            cp "$OCIM_MODEL_DIR/$matfile" "$STAGING/"
        fi
    done
else
    echo "OCIM2_48L_CTL.mat skipped (use --no-ocim or already on GRIT)"
fi

# Resolve source directory for third-party CO2 model solver files.
CO2MODEL_SRC=""
if [ -n "$CO2MODEL_SRC_ARG" ]; then
    if [ -d "$CO2MODEL_SRC_ARG" ]; then
        CO2MODEL_SRC="$CO2MODEL_SRC_ARG"
    else
        echo "WARNING: --co2model-src path does not exist: $CO2MODEL_SRC_ARG"
    fi
fi

if [ -z "$CO2MODEL_SRC" ] && [ -n "${CO2MODEL_SRC_DIR:-}" ] && [ -d "$CO2MODEL_SRC_DIR" ]; then
    CO2MODEL_SRC="$CO2MODEL_SRC_DIR"
fi
if [ -z "$CO2MODEL_SRC" ] && [ -d "data/external/co2model_vendor" ]; then
    CO2MODEL_SRC="data/external/co2model_vendor"
fi
if [ -z "$CO2MODEL_SRC" ] && [ -d "data/external/co2model" ]; then
    CO2MODEL_SRC="data/external/co2model"
fi
if [ -z "$CO2MODEL_SRC" ] && [ -n "$OCIM_MODEL_DIR" ] && [ -d "$OCIM_MODEL_DIR" ]; then
    CO2MODEL_SRC="$OCIM_MODEL_DIR"
fi

CO2_REQUIRED=(
    co2model.m
    ns_step_eb.m
    CO2SYS.m
    eqco2.m
    eqdic.m
    inpaint_nans.m
    mfactor.m
    nsgmres.m
    nsnew.m
    schmidt.m
    sw_pres.m
    netemission.txt
)

if [ -n "$CO2MODEL_SRC" ]; then
    echo "CO2 model source candidate: $CO2MODEL_SRC"
    MISSING=()
    for f in "${CO2_REQUIRED[@]}"; do
        if [ -f "$CO2MODEL_SRC/$f" ]; then
            cp "$CO2MODEL_SRC/$f" "$STAGING/"
        else
            MISSING+=("$f")
        fi
    done
    if [ "${#MISSING[@]}" -gt 0 ]; then
        echo "WARNING: CO2 model source is incomplete (${#MISSING[@]} missing files):"
        for f in "${MISSING[@]}"; do
            echo "   - $f"
        done
        echo "   Use a complete source with --co2model-src or run:"
        echo "   bash deploy/fetch_co2model_dependency.sh --repo <author_repo_url> --ref <tag_or_commit>"
    else
        echo "   + MATLAB model files from $CO2MODEL_SRC"
    fi
else
    echo "WARNING: CO2 model files were not found locally."
    echo "   Run:"
    echo "   bash deploy/fetch_co2model_dependency.sh --repo <author_repo_url> --ref <tag_or_commit>"
    echo "   or pass --co2model-src <directory>"
fi
echo ""

# --- Connection 1: scp ---
echo "CONNEXION 1/2 : Upload des fichiers"
echo ""

ssh -F "$SSH_CONFIG" "$REMOTE" "mkdir -p /tmp/step7_staging"

scp -F "$SSH_CONFIG" "$STAGING"/* "$REMOTE:/tmp/step7_staging/"

echo ""
echo "   Upload termine"
echo ""

# --- Connection 2: ssh move + verify ---
echo "CONNEXION 2/2 : Mise en place + verification"
echo ""

ssh -F "$SSH_CONFIG" "$REMOTE" '
  set -e

  mkdir -p ~/scratch/configuration/ocim \
           ~/scratch/output_V6 \
           ~/ais-pipeline/pipeline_V6/logs

  # Move OCIM data files if uploaded
  OCIM_DEST=~/scratch/configuration/ocim
  mkdir -p "$OCIM_DEST"
  for matfile in OCIM2_48L_CTL.mat oceanfrac2d.mat woa09po4.mat woa09si.mat schmidt_coeff.mat; do
      if [ -f "/tmp/step7_staging/$matfile" ]; then
          mv "/tmp/step7_staging/$matfile" "$OCIM_DEST/"
          echo "$matfile -> $OCIM_DEST/"
      fi
  done
  # Move MATLAB model .m files and supporting files to ocim dir
  for f in co2model.m ns_step_eb.m CO2SYS.m eqco2.m eqdic.m inpaint_nans.m \
           mfactor.m nsgmres.m nsnew.m schmidt.m sw_pres.m netemission.txt; do
      if [ -f "/tmp/step7_staging/$f" ]; then
          mv "/tmp/step7_staging/$f" "$OCIM_DEST/"
      fi
  done

  # Move pipeline scripts (R, Python, MATLAB cache extractor, SLURM)
  mv /tmp/step7_staging/*.R /tmp/step7_staging/step7_extract_ocim_cache.m \
     /tmp/step7_staging/step7_extract_ocim_cache.py \
     /tmp/step7_staging/audit_jdredge.py \
     /tmp/step7_staging/*.sh ~/ais-pipeline/pipeline_V6/ 2>/dev/null || true
  rm -rf /tmp/step7_staging

  echo "=========================================="
  echo "VERIFICATION (sur GRIT)"
  echo "=========================================="
  echo ""
  echo "Scripts pipeline_V6:"
  ls -lh ~/ais-pipeline/pipeline_V6/step7_export_jtrawl.R 2>/dev/null || echo "  step7 R manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/step7_extract_ocim_cache.m 2>/dev/null || echo "  MATLAB cache script manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/step7_extract_ocim_cache.py 2>/dev/null || echo "  Python cache script manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/audit_jdredge.py 2>/dev/null || echo "  audit script manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/step7_export_jtrawl_grit.sh 2>/dev/null || echo "  SLURM manquant"
  ls -lh ~/ais-pipeline/pipeline_V6/constants.R 2>/dev/null || echo "  constants.R manquant"
  echo ""
  echo "OCIM data + model:"
  ls -lh ~/scratch/configuration/ocim/OCIM2_48L_CTL.mat 2>/dev/null || echo "  OCIM2_48L_CTL.mat absent"
  ls -lh ~/scratch/configuration/ocim/oceanfrac2d.mat 2>/dev/null || echo "  oceanfrac2d.mat absent (run precompute_oceanfrac2d.py locally)"
  ls -lh ~/scratch/configuration/ocim/ocim_cache.mat 2>/dev/null || echo "  ocim_cache.mat absent (run MATLAB first)"
  ls -lh ~/scratch/configuration/ocim/co2model.m 2>/dev/null || echo "  co2model.m absent"
  ls -lh ~/scratch/configuration/ocim/ns_step_eb.m 2>/dev/null || echo "  ns_step_eb.m absent"
  echo "  MATLAB model files: $(ls ~/scratch/configuration/ocim/*.m 2>/dev/null | wc -l) .m files"
'

echo ""
echo "=========================================="
echo "Upload termine !"
echo ""
echo "Etapes suivantes sur GRIT :"
echo "  1) Regenerer ocim_cache.mat (avec enrichment fields) :"
echo "     python3 ~/ais-pipeline/pipeline_V6/step7_extract_ocim_cache.py"
echo "     OR: matlab -batch \"run('step7_extract_ocim_cache.m')\""
echo "  2) Lancer Step 7 :"
echo "     sbatch step7_export_jtrawl_grit.sh"
echo "  3) Valider le resultat :"
echo "     python3 ~/ais-pipeline/pipeline_V6/audit_jdredge.py"
echo "=========================================="
