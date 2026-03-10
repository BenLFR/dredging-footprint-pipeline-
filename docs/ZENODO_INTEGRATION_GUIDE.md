# Zenodo Integration Guide

This guide describes the release workflow used to mint a citable DOI and update
repository metadata consistently.

## 1. Preconditions

1. Branch `pub/v1.0-clean` is up to date.
2. `ARCHIVE_MANIFEST.yaml` exists and lists release artifacts.
3. `CITATION.cff` and `codemeta.json` are present.
4. Files with placeholder DOI values are known:
   - `CITATION.cff`
   - `codemeta.json`
   - `docs/data_policy.md`
   - `ARCHIVE_MANIFEST.yaml`
   - `README.md` (if DOI placeholder is present)

## 2. Connect GitHub to Zenodo (one-time)

1. Log in to Zenodo (`https://zenodo.org`).
2. Go to `Account -> GitHub`.
3. Enable the repository `BenLFR/dredging-footprint-pipeline-`.

## 3. Prepare release metadata in Git

1. Ensure `.zenodo.json` is filled with release metadata.
2. Verify author names and affiliations.
3. Confirm license matches `LICENSE` and `CITATION.cff`.
4. Commit metadata updates before creating the GitHub release tag.

## 4. Create release on GitHub

1. Create annotated tag:

```bash
git checkout pub/v1.0-clean
git pull origin pub/v1.0-clean
git tag -a v1.0.0 -m "Public release v1.0.0"
git push origin v1.0.0
```

2. Open GitHub Releases and publish release `v1.0.0`.

Zenodo will archive this tag automatically and mint:

- a concept DOI (stable across versions),
- a version DOI (specific to `v1.0.0`).

## 5. Replace placeholders with real DOI

After Zenodo minting completes:

1. Copy the minted DOI(s).
2. Replace `10.5281/zenodo.XXXXXXX` in:
   - `CITATION.cff` (`doi:`),
   - `codemeta.json` (`identifier`, `citation`),
   - `docs/data_policy.md`,
   - `ARCHIVE_MANIFEST.yaml` (`zenodo_*` fields).
3. If ORCID is available, add it in `CITATION.cff`.

Commit and push the metadata finalization:

```bash
git checkout pub/v1.0-clean
git add CITATION.cff codemeta.json docs/data_policy.md ARCHIVE_MANIFEST.yaml
git commit -m "Finalize DOI metadata after Zenodo release v1.0.0"
git push origin pub/v1.0-clean
```

## 6. Verify archive integrity

1. Download Zenodo release files.
2. Compute SHA256 checksums.
3. Compare against `ARCHIVE_MANIFEST.yaml`.
4. Store generated checksum file in release notes or `docs/`.

Example:

```bash
sha256sum <downloaded_file>
```

## 7. Final FAIR checklist

1. DOI in `CITATION.cff` is real and resolves.
2. DOI in `docs/data_policy.md` is real and resolves.
3. `codemeta.json` is valid JSON and DOI-aligned.
4. `ARCHIVE_MANIFEST.yaml` includes final checksums and DOI values.
5. Release notes are updated with DOI and checksum values.
