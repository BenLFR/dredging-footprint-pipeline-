# Uncertainty Budget

Purpose: document major uncertainty sources, propagation strategy, and reporting
requirements for SAR, CRI, and optional CO2 outputs.

## 1. Major uncertainty components

1. AIS observation uncertainty:
   - missing pings, irregular revisit frequency, position noise.
2. Activity classification uncertainty:
   - thresholds and clustering decisions in Steps 2-3.
3. Vessel-parameter uncertainty:
   - beam width and operational assumptions in `config/ship_specs.yaml`.
4. Environmental layer uncertainty:
   - carbon baseline raster and lithology assignment quality.
5. Model structure uncertainty:
   - simplifications in SAR and CRI formulations.
6. External model uncertainty (optional CO2 step):
   - OCIM solver configuration and forcing assumptions.

## 2. Propagation approach

Recommended workflow:

1. Define distributions for key uncertain parameters.
2. Run Monte Carlo or Latin Hypercube sampling.
3. Recompute target outputs (`fi`, `cri`, optional CO2 diagnostics) per sample.
4. Aggregate median, 5th percentile, 95th percentile, and coefficient of
   variation per grid cell.

## 3. Minimum publishable outputs

For each primary map product:

1. central estimate map,
2. lower bound map (e.g., p05),
3. upper bound map (e.g., p95),
4. metadata note stating sampled parameters and sample count.

## 4. Practical default settings

1. Pilot uncertainty run: 100 samples.
2. Release-grade uncertainty run: 1000+ samples.
3. Fixed random seed and logged git commit hash for each uncertainty campaign.

## 5. Reporting requirements

1. List all uncertain parameters and distributions.
2. Report spatial summary of uncertainty (global median CV, high-uncertainty
   hotspots).
3. State whether CO2 uncertainty includes OCIM structural uncertainty or only
   input perturbations.
