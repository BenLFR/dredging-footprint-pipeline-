# Zenodo Integration Guide

Step-by-step instructions to connect this repository to Zenodo, mint a DOI,
and populate the Data Availability Statement for the L&O:Methods submission.

---

## 1. Enable the Zenodo ↔ GitHub integration

1. Go to [zenodo.org](https://zenodo.org) and log in (or create a free account)
2. Click your user icon → **Linked accounts** → **GitHub**
3. Authorise Zenodo to access your GitHub account
4. In the **GitHub repositories** list, find `BenLFR/Master-thesis-code-`
5. Toggle it **ON**

Zenodo will now auto-create a new deposit record every time you publish a GitHub
Release. The DOI is minted at the time of release publication.

---

## 2. Prepare a clean release

Before tagging, ensure the repository is in a clean state:

```bash
# Confirm no large files are tracked (>50 MB should be in .gitignore)
git status
git lfs ls-files   # if using LFS

# Make sure CITATION.cff and codemeta.json are committed
git add CITATION.cff configuration/codemeta.json
git commit -m "reproducibility: pre-release CITATION and codemeta update"

# Tag the release
git tag -a v1.0.0 -m "Initial L&O:Methods submission release"
git push origin main
git push origin v1.0.0
```

Then on GitHub:
1. Go to **Releases** → **Draft a new release**
2. Select tag `v1.0.0`
3. Title: `Dredging Footprint Pipeline v1.0.0`
4. Description: copy the `abstract` field from `CITATION.cff`
5. Click **Publish release**

---

## 3. Zenodo mints the DOI automatically

After you publish the GitHub release, Zenodo creates the deposit record within a few
minutes. You will see it at: `https://zenodo.org/account/settings/github/`

The DOI will be in the format: `10.5281/zenodo.XXXXXXX`

**Important**: the DOI is minted as a "concept DOI" (always resolving to the latest
version) and a "version DOI" (pinned to v1.0.0). Use the **version DOI** in the
manuscript for reproducibility.

---

## 4. Update CITATION.cff and codemeta.json

Replace `PLACEHOLDER` everywhere with the real Zenodo DOI:

```bash
# On Linux/Mac
sed -i 's/zenodo\.PLACEHOLDER/zenodo.XXXXXXX/g' \
    CITATION.cff configuration/codemeta.json documentation/DATA_AVAILABILITY_STATEMENT.md

# On Windows (PowerShell)
(Get-Content CITATION.cff) -replace 'zenodo\.PLACEHOLDER','zenodo.XXXXXXX' |
    Set-Content CITATION.cff
(Get-Content configuration/codemeta.json) -replace 'zenodo\.PLACEHOLDER','zenodo.XXXXXXX' |
    Set-Content configuration/codemeta.json

git add CITATION.cff configuration/codemeta.json documentation/DATA_AVAILABILITY_STATEMENT.md
git commit -m "reproducibility: add Zenodo DOI 10.5281/zenodo.XXXXXXX"
git push origin main
```

---

## 5. Update the Data Availability Statement

1. Open `documentation/DATA_AVAILABILITY_STATEMENT.md`
2. Replace all `PLACEHOLDER` DOI occurrences with the real Zenodo DOI
3. Fill in any remaining `[TODO]` fields (AIS provider, EDI archive URL, etc.)
4. Choose Variant A or B; delete the other
5. Copy the final statement into the manuscript

---

## 6. Archive large outputs separately (recommended)

The main code deposit on Zenodo should be lightweight (< 1 GB). Large output files
should go in a separate Zenodo **dataset** record:

Recommended files for the dataset deposit:
- `fi_grid_*.parquet` — global dredging intensity grid
- `C_ri_grid_*.parquet` — carbon release index grid
- `output_V6/uncertainty/mc_results_summary.parquet` — MC uncertainty results
- `output_V6/sensitivity/tornado_data.csv` — sensitivity analysis results

Upload these manually at https://zenodo.org/deposit/new (Dataset type).
Link the two records using the Zenodo "Related identifiers" field.

---

## Zenodo deposit checklist

Before submitting the manuscript, verify:

- [ ] `CITATION.cff` present and complete (no placeholder strings)
- [ ] `configuration/codemeta.json` present and valid JSON
- [ ] `README.md` or equivalent top-level description present
- [ ] Real Zenodo DOI replaces `PLACEHOLDER` in all three files
- [ ] License file (`LICENSE` or `LICENSE.md`) present in repo root
- [ ] Large data files (> 50 MB) listed in `.gitignore` and deposited separately
- [ ] Zenodo record metadata matches `CITATION.cff` (title, authors, keywords)
- [ ] "Related identifiers" links code deposit ↔ dataset deposit ↔ manuscript DOI
- [ ] ORCID registered and linked to Zenodo account for author credit

---

## Estimated timeline

| Task | Time |
|------|------|
| Zenodo ↔ GitHub link setup | 10 minutes |
| DOI minting after release publication | Immediate (automated) |
| Zenodo curation review | Not required for standard community deposits |
| ORCID registration (if not done) | 5 minutes at orcid.org |
| Updating all files with real DOI | 10 minutes |
| Separate dataset deposit | 30 minutes (upload + metadata) |

---

## Useful links

- Zenodo: https://zenodo.org
- ORCID registration: https://orcid.org/register
- GitHub ↔ Zenodo guide: https://docs.github.com/en/repositories/archiving-a-github-repository/referencing-and-citing-content
- CITATION.cff validator: https://github.com/citation-file-format/cffconvert
- CodeMeta validator: https://codemeta.github.io/codemeta-generator/
- L&O:Methods author guidelines: https://aslopubs.onlinelibrary.wiley.com/hub/journal/19415590/homepage/author-guidelines
