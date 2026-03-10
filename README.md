# Global Dredging Footprint Pipeline

[![Quality Gate](https://github.com/BenLFR/dredging-footprint-pipeline-/actions/workflows/smoke_test.yml/badge.svg)](https://github.com/BenLFR/dredging-footprint-pipeline-/actions/workflows/smoke_test.yml)

This repository estimates global seafloor swept-area ratio (SAR) and cumulative
risk index (CRI) for trailing-suction hopper dredgers (TSHDs) from AIS vessel
tracks, and provides an optional OCIM2-48L export workflow for downstream CO2
perturbation modeling.

## Quick Start (local, toy data)

```bash
git clone https://github.com/BenLFR/dredging-footprint-pipeline-.git
cd dredging-footprint-pipeline-
git checkout pub/v1.0-clean
```

```bash
Rscript tests/run_testthat.R
Rscript tests/benchmark_regression_guard.R
Rscript tests/hpc_template_path_check.R
Rscript tests/smoke_test_steps2_5.R
```

## Pipeline Steps

| Step | Script | Description |
|------|--------|-------------|
| 0 | `pipeline/step0/step0_core_window.R` | Coverage matrix and core temporal window |
| 1 | `pipeline/step1/step1_split_vessels.R` | AIS split by vessel (MMSI) |
| 2 | `pipeline/step2/step2_process_vessel.R` | Per-vessel filtering and cleaning |
| 3 | `pipeline/step3/step3_merge.R` | Merge and activity classification (GMM + DBSCAN) |
| 4 | `pipeline/step4/step4_add_lithology.R` | Lithology join (dbSEABED) |
| 5 | `pipeline/step5/step5_*.R` | Tile SAR computation and global merge |
| 6 | `pipeline/step6/step6_calculate_cri.R` | CRI computation |
| 7 | `pipeline/step7/step7_export_jdredge.R` | OCIM2-48L forcing export |

See `docs/architecture.md` for full data-flow diagram, formulas, and I/O table.

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
See `data/README.md` (section 6b) and `THIRD_PARTY_NOTICES.md`.

## Cluster-Neutral HPC Deployment

Generic SLURM helper scripts and templates are provided in `deploy/`:
- `deploy/hpc_submit.sh` — generic `sbatch` wrapper with cluster overrides
- `deploy/config.example.env` — path and scheduler override variables
- `deploy/HPC_WORKFLOW_GENERIC.md` — step-by-step HPC deployment guide

Wrappers support environment overrides:
`PIPELINE_DIR`, `SCRATCH_DIR`, `OUTPUT_DIR`, `CONFIG_DIR`, `LOGS_DIR`

## Reproducibility and FAIR Docs

- `docs/reproducibility.md`
- `docs/ZENODO_INTEGRATION_GUIDE.md`
- `ARCHIVE_MANIFEST.yaml`

## Citation and License

- Citation metadata: `CITATION.cff` and `codemeta.json`
- Code license: `LICENSE` (MIT)
