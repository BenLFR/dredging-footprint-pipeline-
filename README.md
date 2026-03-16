# Global Dredging Footprint Pipeline

[![Quality Gate](https://github.com/BenLFR/Master-thesis-code-/actions/workflows/smoke_test.yml/badge.svg)](https://github.com/BenLFR/Master-thesis-code-/actions/workflows/smoke_test.yml)

This repository estimates global seafloor swept-area ratio (SAR) and cumulative
risk index (CRI) for trailing-suction hopper dredgers (TSHDs) from AIS vessel
tracks, and provides an optional OCIM2-48L export workflow for downstream CO2
perturbation modeling.

## Quick Start (local, toy data)

```bash
git clone https://github.com/BenLFR/Master-thesis-code-.git
cd Master-thesis-code-
git checkout pub/v1.0-clean
Rscript -e "install.packages('renv', repos='https://cloud.r-project.org')"
Rscript -e "renv::consent(provided = TRUE); renv::restore(lockfile='renv.lock', prompt=FALSE)"
```

```bash
# These commands validate the public smoke surface only. They do not execute the full restricted-data AIS pipeline.
Rscript tests/run_testthat.R
Rscript tests/benchmark_regression_guard.R
Rscript tests/hpc_template_path_check.R
Rscript tests/smoke_test_steps2_5.R
```

## Pipeline Steps

| Step | Script | Description |
|---|---|---|
| 0 | `pipeline/step0_core_window.R` | Coverage matrix and core temporal window |
| 1 | `pipeline/step1_split_navires.R` | AIS split by vessel |
| 2 | `pipeline/step2_process_navire.R` | Per-vessel filtering and cleaning |
| 3 | `pipeline/step3_merge_final.R` | Merge and activity classification |
| 4 | `pipeline/step4_add_lithology.R` | Lithology join |
| 5 | `pipeline/step5_*` | Tile SAR computation and global merge |
| 6 | `pipeline/step6_calculate_cri.R` | CRI computation |
| 7 | `pipeline/step7_*` and `step7_export_jtrawl.R` | OCIM forcing export |

## Data Availability

Raw AIS tracks are restricted-access and are not redistributed in this
repository.

Source used for this study:
- Global Fishing Watch (GFW) AIS access via Stanford Center for Ocean Solutions.

For access guidance:
- Contact David Kroodsma (Global Fishing Watch).

See `data/README.md` and `docs/data_policy.md` for details.

## Optional External CO2 Dependency

The OCIM MATLAB solver code is third-party and not vendored.
See:
- `co2model/README.md`
- `THIRD_PARTY_NOTICES.md`

## Cluster-Neutral HPC Templates

Generic SLURM templates are provided in:
- `config/templates/slurm/`

Wrappers support environment overrides:
- `PIPELINE_DIR`, `SCRATCH_DIR`, `OUTPUT_DIR`, `CONFIG_DIR`, `LOGS_DIR`

## Reproducibility and FAIR Docs

- `docs/reproducibility.md`
- `documentation/PUBLIC_READINESS_TRACKER.md`
- `documentation/ZENODO_INTEGRATION_GUIDE.md`
- `ARCHIVE_MANIFEST.yaml`

## Citation and License

- Citation metadata: `CITATION.cff`
- Code license: `LICENSE` (MIT)
