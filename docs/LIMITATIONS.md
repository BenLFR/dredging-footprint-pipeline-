# Methodological Limitations

This document lists the main known limitations of the pipeline and how they
affect interpretation.

## 1. Data access and representativeness

1. Raw AIS tracks used in production were obtained through restricted Global
   Fishing Watch access and cannot be redistributed.
2. Reproducibility on public data requires either synthetic toy data or an
   alternate AIS provider with potentially different coverage quality.
3. AIS quality is not globally uniform (satellite revisit, coastal reception,
   missing pings), which can bias inferred activity intensity.

## 2. Activity inference assumptions (Steps 2-3)

1. Dredging activity is inferred from movement features, not direct gear
   telemetry.
2. Classification depends on thresholding, GMM, and DBSCAN settings.
3. Vessel metadata harmonization (e.g., identifier fields, specs matching) can
   introduce classification uncertainty when source fields are missing.

## 3. SAR and CRI model assumptions (Steps 5-6)

1. SAR estimates rely on vessel-spec parameters from `config/ship_specs.yaml`.
2. Spatial aggregation and grid resolution smooth local heterogeneity.
3. CRI depends on the selected organic carbon baseline raster and depletion
   model assumptions.
4. Lithology assignment quality depends on external seabed products and spatial
   overlap quality.

## 4. CO2 perturbation step (Step 7 + external MATLAB code)

1. The OCIM MATLAB solver code is third-party and not vendored in this
   repository.
2. Reproduction of the final CO2 perturbation stage requires external code and
   data provided by upstream authors.
3. Differences in OCIM package version or local MATLAB environment can modify
   numeric results.

## 5. Computational and operational limits

1. Full global runs require HPC resources (memory, walltime, storage).
2. Some wrappers include fail-safe fallbacks for missing inputs; this can
   preserve execution but should be reviewed for scientific interpretation.
3. Pipeline outputs should not be interpreted as direct causal estimates without
   uncertainty analysis and independent validation.

## 6. Runtime warning policy

Wrappers for Steps 3-7 print a non-blocking warning that points to this file.
The warning is informational and does not stop execution.

## 7. Recommended reporting language

When publishing results, report at minimum:

1. AIS data source and access constraints.
2. Key classification parameters used for Step 3.
3. Carbon baseline source and depletion assumptions.
4. Whether the external OCIM CO2 step was run and with which dependency bundle.
