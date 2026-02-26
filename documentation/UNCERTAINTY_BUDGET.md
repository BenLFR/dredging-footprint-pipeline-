# Uncertainty Budget

## GUM Reference

This analysis follows the Guide to the Expression of Uncertainty in Measurement
(GUM, JCGM 100:2008). Uncertainty is propagated via Monte Carlo simulation
(500 iterations, 3 independent error sources), consistent with GUM Supplement 1
(JCGM 101:2008) for non-linear models.

## Sources of uncertainty

| Source | Component affected | Magnitude (1σ) | Method | Contribution to C_ri variance (%) |
|--------|-------------------|----------------|--------|------------------------------------|
| AIS position error | Cell grid assignment (SVR numerator) | ±30 m (1σ Gaussian) | Monte Carlo | [fill from mc_results_summary.parquet] |
| Dredging classification error | f_i numerator (Dragage_flag) | Bernoulli flip prob = 1 − LOYO_AUC | Monte Carlo | [fill from mc_results] |
| fi parameter uncertainty | f_i, C_ri (all terms) | ±10% CV per parameter (Gaussian) | Monte Carlo | [fill from mc_results] |
| Land mask boundary errors | Cell ocean fraction denominator | ±1 grid cell (~1 km) | Not quantified | — |
| dbSEABED coverage gaps | H_index / p_l interpolation | Varies by region | Not quantified | — |
| Carbon stock uncertainty (Atwood) | C0i (C_ri numerator) | Lower/upper rasters from Atwood et al. | Propagated via C_ri_lower/C_ri_upper | — |

## Parameters perturbed in Monte Carlo

From `fi_parameters.yaml` (default scenario), perturbed as `param × N(1, 0.10)`:

| Parameter | Default value | Units | Role in f_i formula |
|-----------|--------------|-------|---------------------|
| `alpha_dep` | 0.25 | dimensionless | Deep-layer labile carbon multiplier |
| `fast_fraction` | 0.30 | dimensionless | Fraction of C in fast-cycling pool |
| `slow_k` | 0.05 | a⁻¹ | Slow-pool mineralisation rate |
| `preservation_factor` | 0.87 | dimensionless | p_r from Sala et al. (2021) |
| `k_fast_multiplier` | 1.00 | dimensionless | Scales all provincial k_fast values |

## f_i formula (Step 5)

```
f_i = SVR × p_l_corr × preservation_factor ×
      [ fast_fraction × (1 − exp(−k_fast)) +
        (1 − fast_fraction) × (1 − exp(−slow_k)) ]

C_ri = C0i × f_i × di
```

Where:
- `SVR` = Swept Volume Ratio (= SAR × p_d / 1 m normalised depth)
- `p_l_corr` = weighted penetrability (alpha_dep applies to the deep horizon)
- `C0i` = benthic carbon stock (Atwood et al. 2024, gC m⁻²)
- `di` = depletion factor (1.0 unless trawling history file provided)

## Results

*Fill in after running the full Monte Carlo (500 iterations):*

```
# After submit_monte_carlo.sh completes, run:
Rscript -e "
  library(data.table, arrow)
  dt <- arrow::read_parquet('output_V6/uncertainty/mc_results_summary.parquet')
  cat('Global median C_ri 95% CI width:',
      median(dt\$C_ri_p975 - dt\$C_ri_p025, na.rm=TRUE), '\n')
  cat('Relative CI width (median cell):',
      median((dt\$C_ri_p975 - dt\$C_ri_p025) / dt\$C_ri_mean, na.rm=TRUE) * 100, '%\n')
"
```

Expected result: ~20–40% relative 95% CI width (combining all three sources).
The dominant source is expected to be fi parameter uncertainty (k_fast and fast_fraction
are the most influential per the OAT sensitivity analysis in SENSITIVITY_TORNADO).

## Final 95% CI estimate (to complete after running MC)

```
C_ri 95% CI: [p025] – [p975]  (relative width: X%)
```

## Recommendations for manuscript

**Methods section**: "Uncertainty in C_ri estimates was quantified by Monte Carlo
simulation (n = 500 iterations) propagating three independent sources of error:
AIS position uncertainty (±30 m, 1σ), dredging classification error proportional
to (1 − AUC) from the leave-one-year-out cross-validation, and model parameter
uncertainty (±10% coefficient of variation applied to each of five parameters in
Equation [X]). All analyses follow GUM (JCGM 100:2008)."

**Results section**: "The combined 95% uncertainty interval for global C_ri was
[X]–[Y] Tg C a⁻¹, representing a relative width of [Z]%. The largest contributor
was [parameter], responsible for [N]% of total variance."

## References

- JCGM 100:2008. Evaluation of measurement data — Guide to the Expression of
  Uncertainty in Measurement (GUM). BIPM, IEC, IFCC, ILAC, ISO, IUPAC, IUPAP,
  OIML.
- JCGM 101:2008. GUM Supplement 1 — Propagation of distributions using a
  Monte Carlo method.
- Atwood et al. (2024). Seafloor carbon stocks and uncertainty bounds. [cite full ref]
- Sala et al. (2021). Protecting the global ocean for biodiversity, food and climate.
  *Nature* 592, 397–402.
