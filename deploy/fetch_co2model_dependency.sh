#!/bin/bash
# Fetch third-party CO2 model files from an upstream repository at a pinned ref.
# This script does not commit any fetched artifacts.
#
# Usage:
#   bash deploy/fetch_co2model_dependency.sh \
#     --repo https://github.com/<owner>/<repo>.git \
#     --ref <tag-or-commit> \
#     [--dest data/external/co2model_vendor]
#
# Optional env vars:
#   CO2MODEL_REPO_URL, CO2MODEL_REF, CO2MODEL_DEST

set -euo pipefail

usage() {
  cat << 'USAGE'
Usage:
  bash deploy/fetch_co2model_dependency.sh --repo <url> --ref <tag-or-commit> [--dest <dir>]

Examples:
  bash deploy/fetch_co2model_dependency.sh \
    --repo https://github.com/example/ocim-co2model.git \
    --ref 4f7d8de2b5b7a3d6f0e4f3cbf77d8f16cfb58f42

  CO2MODEL_REPO_URL=https://github.com/example/ocim-co2model.git \
  CO2MODEL_REF=v1.2.0 \
  bash deploy/fetch_co2model_dependency.sh
USAGE
}

REPO_URL="${CO2MODEL_REPO_URL:-}"
REF="${CO2MODEL_REF:-}"
DEST="${CO2MODEL_DEST:-data/external/co2model_vendor}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires a value."; usage; exit 2; }
      REPO_URL="$2"; shift 2 ;;
    --ref)
      [[ $# -ge 2 ]] || { echo "Error: --ref requires a value."; usage; exit 2; }
      REF="$2"; shift 2 ;;
    --dest)
      [[ $# -ge 2 ]] || { echo "Error: --dest requires a value."; usage; exit 2; }
      DEST="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Error: unknown option: $1"
      usage
      exit 2 ;;
  esac
done

if [[ -z "$REPO_URL" || -z "$REF" ]]; then
  echo "Error: --repo and --ref are required (or set CO2MODEL_REPO_URL / CO2MODEL_REF)."
  usage
  exit 2
fi

find_upstream_file() {
  local repo_dir="$1"
  local filename="$2"
  local candidate
  for candidate in \
    "$repo_dir/$filename" \
    "$repo_dir/co2model/$filename" \
    "$repo_dir/CO2MODEL/$filename" \
    "$repo_dir/model/$filename"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

REQUIRED_FILES=(
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

OPTIONAL_FILES=(
  sw_copy.m
  schmidt_coeff.mat
  woa09po4.mat
  woa09si.mat
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Cloning upstream CO2 model repository..."
git clone --quiet "$REPO_URL" "$TMP_DIR/repo"
git -C "$TMP_DIR/repo" checkout --quiet "$REF"
RESOLVED_COMMIT="$(git -C "$TMP_DIR/repo" rev-parse HEAD)"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mkdir -p "$DEST"

missing_count=0
copied_files=()
for f in "${REQUIRED_FILES[@]}"; do
  if src="$(find_upstream_file "$TMP_DIR/repo" "$f")"; then
    cp "$src" "$DEST/$f"
    copied_files+=("$f")
  else
    echo "Missing required file in upstream repo: $f"
    missing_count=$((missing_count + 1))
  fi
done

if [[ "$missing_count" -gt 0 ]]; then
  echo "Error: upstream source is incomplete for this workflow."
  echo "Fetched destination was left at: $DEST"
  exit 1
fi

for f in "${OPTIONAL_FILES[@]}"; do
  if src="$(find_upstream_file "$TMP_DIR/repo" "$f")"; then
    cp "$src" "$DEST/$f"
    copied_files+=("$f")
  fi
done

MANIFEST="$DEST/UPSTREAM_MANIFEST.txt"
{
  echo "source_repo=$REPO_URL"
  echo "source_ref=$REF"
  echo "resolved_commit=$RESOLVED_COMMIT"
  echo "retrieved_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "[files]"
  for f in "${copied_files[@]}"; do
    echo "$f"
  done
} > "$MANIFEST"

if command -v sha256sum >/dev/null 2>&1; then
  {
    echo ""
    echo "[sha256]"
    (
      cd "$DEST"
      sha256sum "${copied_files[@]}"
    )
  } >> "$MANIFEST"
fi

echo "CO2 model dependency fetched successfully."
echo "Destination: $DEST"
echo "Pinned commit: $RESOLVED_COMMIT"
echo "Manifest: $MANIFEST"
