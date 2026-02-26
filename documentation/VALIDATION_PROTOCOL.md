# Validation Protocol

## Two validation pathways

The dredging footprint pipeline is validated via two complementary pathways that
target different aspects of model performance.

---

### Pathway 1: Independent AIS data (`validate_with_independent_data.R`)

**Script**: `tests/validate_with_independent_data.R`

Three sections, in order of expected data availability:

#### Section A — Hold-out temporal split (always available)

The final year of the AIS dataset is withheld from model training and used as an
independent test period. Per-vessel dredging intensity (mean `Dragage_flag` or
`behavior_smooth == "dredging"`) is computed for training years and for the hold-out
year. The correlation and RMSE between both periods are reported.

**Input**: `AIS_data_core_preprocessed_V6_*_flagOK.rds` (step3 output)
**Metric**: Pearson r, Spearman r, RMSE (per-vessel intensity), top-20% spatial overlap

#### Section B — Global Fishing Watch hook (requires API key)

If `GFW_API_KEY` is set in the environment, the script queries the GFW v3 API for
apparent fishing hours by vessels using the `dredge_fish` gear type, aggregated to
0.1° grid. The pipeline `f_i` output is aggregated to the same grid and Spearman
correlation is computed.

**Input**: GFW API response + `fi_grid_*.parquet`
**To enable**: `export GFW_API_KEY=your_key_here`
**Note**: GFW fishing hours include non-dredging fishing vessels; perfect correlation
is not expected. The goal is to verify that the spatial hot-spots broadly agree.

#### Section C — Alternative AIS source (Copernicus/EMSA)

If `AIS_SAMPLE_PATH` is set, the script loads an independent AIS dataset (CSV or RDS)
from a different provider (e.g., Copernicus Marine Service, EMSA SafeSeaNet) and
computes a speed-threshold proxy for dredging intensity. This is then correlated
with the pipeline `f_i` output at 1° resolution.

**To enable**: `export AIS_SAMPLE_PATH=/path/to/alternative_ais.rds`
**Required columns**: `Latitude`, `Longitude`, `speed_knots`
**Speed threshold**: vessels with `speed_knots < 4.0` classified as dredging

---

### Pathway 2: Synthetic ground truth (`synthetic_validation.R`)

**Script**: `scripts_principaux/synthetic_validation.R`

Creates 5 virtual TSHD vessels with fully known kinematics, generates synthetic AIS
pings, runs the f_i formula on the synthetic tracks, and compares recovered f_i to the
analytical ground truth.

#### Virtual vessel specifications

| Vessel | Sweep width (m) | Speed (kn) | Hours dredging/day | Region |
|--------|----------------|------------|-------------------|--------|
| V001 | 20 | 2.0 | 16 | North Sea |
| V002 | 15 | 1.5 | 12 | Persian Gulf |
| V003 | 25 | 2.5 | 20 | South China Sea |
| V004 | 18 | 1.8 | 14 | Bay of Biscay |
| V005 | 22 | 2.2 | 18 | Gulf of Mexico |

#### Ground truth formula

```
known_SAR  = (dredge_width_m × distance_dredged_m) / cell_area_m2
known_f_i  = known_SAR × preservation_factor ×
             [fast_fraction × (1 − exp(−k_fast)) +
              (1 − fast_fraction) × (1 − exp(−slow_k))]
```

Where cell_area_m2 = 1,000,000 (1 km² grid), and parameters are the defaults from
`fi_parameters.yaml`. Penetrability `p_l_corr = 1.0` (uniform synthetic substrate).

#### Pass criterion

| Level | Criterion |
|-------|-----------|
| Cell-level | \|recovered_f_i − known_f_i\| / known_f_i < **15%** |
| Vessel-level | ≥ **80%** of cells pass the cell-level criterion |
| Overall | ≥ **4/5** vessels pass the vessel-level criterion |

---

## Expected performance thresholds

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Pearson r (temporal holdout) | > 0.70 | Dredging patterns should be temporally stable |
| Spearman r (temporal holdout) | > 0.65 | Rank-based; more robust to spatial outliers |
| Spearman r (vs GFW) | > 0.40 | AIS vs fishing effort are different datasets/activities |
| Synthetic recovery error | < 15% per cell | Accounts for grid discretisation + AIS ping density |
| Synthetic pass rate | ≥ 80% of cells | Allows for edge-cell discretisation artefacts |
| Spatial overlap (top 20%) | > 50% | Hot-spot consistency across methods |

---

## How to run

### Pathway 1 (independent data)
```bash
# Section A only (hold-out split — no external data needed)
Rscript tests/validate_with_independent_data.R

# With GFW API
GFW_API_KEY=your_key Rscript tests/validate_with_independent_data.R

# With alternative AIS file
AIS_SAMPLE_PATH=/path/to/sample.rds Rscript tests/validate_with_independent_data.R
```

### Pathway 2 (synthetic ground truth)
```bash
Rscript scripts_principaux/synthetic_validation.R
```

### Results
Both scripts save results to `output_V6/validation/`:
- `independent_validation_results.csv` (Pathway 1)
- `synthetic_test_results.txt` (Pathway 2, human-readable)
- `synthetic_test_details.csv` (Pathway 2, per-cell errors)

---

## How to cite validation in the manuscript

> "Pipeline performance was assessed using two complementary validation pathways.
> First, a temporal hold-out approach withheld the final year of the AIS dataset
> (year X) as an independent test period; the Spearman correlation between training-
> period and hold-out dredging intensities was ρ = [value] (n = [N] vessels).
> Second, a synthetic ground-truth experiment with 5 virtual dredgers of known
> swept area confirmed that the pipeline recovers f_i within ±15% for [N]/5 vessels
> (cell-level pass rate: [Y]%). Where available, pipeline hot-spots were additionally
> compared against Global Fishing Watch dredge-vessel fishing hours (Spearman ρ = [Z];
> Kroodsma et al. 2018)."

---

## Limitations of this validation approach

- **No independent ground truth labels**: AIS-based dredging classification cannot
  be compared against physical seabed surveys at the global scale. Validation is
  therefore indirect (temporal consistency + synthetic recovery).

- **Temporal stability ≠ accuracy**: A high temporal hold-out correlation confirms
  that the method is consistent across years, but does not verify absolute calibration
  against measured disturbance rates.

- **GFW label mismatch**: GFW fishing hours classify vessels by gear type, which may
  include clamshell dredges and drag dredges not captured by the TSHD-focused pipeline.
  Partial overlap is expected and acceptable.

- **Synthetic test scope**: Synthetic pings use simplified uniform substrates
  (p_l_corr = 1) and open-water boxes. Recovery may degrade in heterogeneous substrate
  regions or near the coast where the land mask clips cells.

- **AIS dark targets and small vessels**: Vessels without AIS transponders (< 300 GT
  in non-SOLAS waters, illegal dredgers) are not captured by any AIS-based validation.
  The method fundamentally represents a lower bound on dredging activity.

---

## References

- Kroodsma, D.A. et al. (2018). Tracking the global footprint of fisheries.
  *Science* 359(6378), 904–908. https://doi.org/10.1126/science.aao5646
- Global Fishing Watch API: https://globalfishingwatch.org/our-apis/
