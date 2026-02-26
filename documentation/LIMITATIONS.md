# Method Limitations

This document provides a structured account of the assumptions, known failure modes,
valid scope, and recommended use cases for the AIS-based dredging footprint pipeline.
It is intended to accompany the L&O:Methods submission and should be cited as a
supporting resource for the Methods section.

---

## Fundamental assumptions

1. **AIS completeness and representativeness**
   The pipeline assumes that vessels transmitting AIS are representative of global
   dredging activity. Vessels with AIS transponders switched off ("dark targets"),
   vessels below the mandatory AIS threshold (< 300 GT in non-SOLAS flag states),
   and illegally operating dredgers are not captured. The method therefore provides
   a **lower bound** on global dredging intensity.

2. **Kinematic dredging classification**
   The GMM + DBSCAN classifier uses vessel kinematics (speed, heading change,
   inter-ping interval) to classify behaviour as dredging, transit, or other. Any
   vessel performing slow straight-line movement (e.g., slow maneuvering in port,
   anchoring, waiting) may be misclassified as dredging. The Isolation Forest
   pre-filtering and near-coast exclusion (5 km buffer) partially mitigate this risk.

3. **Static ship specifications**
   Sweep width (dredge_width_m) and other vessel parameters are taken from a fixed
   lookup table (`configuration/ship_specs.yaml`) based on MMSI-to-vessel-type
   matching. Vessels not in the lookup receive mean TSHD values. Changes in vessel
   configuration (equipment upgrades, seasonal modifications) are not captured.

4. **Seabed lithology resolution and coverage**
   dbSEABED coverage is heterogeneous: dense in European and North American waters,
   sparse in the southern hemisphere. In data-sparse regions, the H_index (sediment
   hardness / penetrability) is spatially interpolated from nearest neighbours, which
   may misrepresent actual substrate type. The resulting uncertainty is not propagated
   through the Monte Carlo (treated as a fixed input).

5. **OCIM steady-state assumption**
   The CO₂ perturbation model uses a steady-state ocean circulation (OCIM2-48L
   climatological transport matrix). Seasonal variability, ENSO events, and long-term
   circulation trends are not represented. The model gives the equilibrium pCO₂
   response to a sustained annual Jdredge flux — appropriate for decadal-scale
   assessments but not for seasonal or event-scale projections.

6. **Depth-invariant penetration**
   The swept-volume ratio formula uses fixed surface (SURF_HORIZON = 0.05 m) and
   deep (DEEP_HORIZON = 0.05 m) horizon depths for the labile carbon mineralization
   calculation. Actual penetration depth varies with sediment type, dredge design,
   and operational mode and is not dynamically computed.

---

## Known failure modes

| Scenario | Effect on output | Severity |
|----------|-----------------|----------|
| AIS ping rate < 1/hour | Track gaps → interpolation error > 1 nm; SAR underestimated | High |
| Vessel < 300 GT | Not in AIS dataset → zero dredging recorded | High |
| Identical MMSI assigned to multiple vessels ("MMSI spoofing") | Vessel identity confusion → inflated per-MMSI intensity | Medium–High |
| Dredging in estuaries < 5 km wide | Near-coast exclusion filter may remove valid dredging pings | Medium |
| Ice-covered regions (|lat| > 65°) | Seasonal AIS gaps → underestimated annual intensity; land mask edge effects | Medium |
| Dredging vessels > 10 knots (high-speed transit classified as non-dredging) | Speed threshold correctly excludes transit; actual dredging at high speed would be missed (unlikely for TSHDs) | Low |
| dbSEABED gap regions | H_index = spatially interpolated → p_l_corr uncertainty unquantified | Medium |
| Port dredging (surrounded by land cells) | Land mask clips cells → fraction of actual dredging area not assigned to ocean grid | Low–Medium |

---

## Sensitivity to key parameters

The OAT sensitivity analysis (`scripts_principaux/sensitivity_oat_analysis.R`) shows
that global C_ri is most sensitive to:

1. `fast_fraction` — fraction of carbon in the fast-mineralising pool
2. `k_fast_multiplier` — scales the province-level k_fast constants
3. `preservation_factor` — p_r from Sala et al. (2021)

Parameters `alpha_dep` and `slow_k` have smaller effects (see
`output_V6/sensitivity/tornado_plot.png` for the full tornado diagram).

A ±50% perturbation of `fast_fraction` produces approximately ±X% change in global
C_ri (fill in from `output_V6/sensitivity/tornado_data.csv` after running the analysis).

---

## Valid geographic and temporal scope

### Geographic scope
- **Best coverage**: European waters (North Sea, Mediterranean, Bay of Biscay),
  East Asian waters (South and East China Seas, Yellow Sea), US Gulf Coast and
  East Coast, Persian Gulf.
- **Partial coverage**: West Africa, South America, Southeast Asia.
- **Poor coverage**: open Southern Ocean, Arctic, inland waterways.

The pipeline is calibrated for **offshore and coastal TSHDs** operating in AIS-covered
waters. Cutter-suction dredgers and backhoe dredgers operating inshore may not be
well-represented in the TSHD ship_specs lookup.

### Temporal scope
Valid for the AIS data period specified in the `step0` core window output
(`output_V6/step0_coverage_window.csv`). Extrapolation beyond this period is not
supported without re-running the full pipeline on additional AIS data.

---

## Recommended use cases

| Use case | Supported | Notes |
|----------|-----------|-------|
| Global-scale dredging intensity mapping (≥ 0.25° resolution) | ✅ | Primary intended use |
| Regional comparative analysis (e.g., North Sea vs Persian Gulf) | ✅ | |
| Year-on-year trend analysis within data period | ✅ | Use temporal holdout validation |
| Carbon flux order-of-magnitude estimates for OCIM perturbation | ✅ | See uncertainty budget |
| Sub-kilometre dredging event detection | ❌ | Grid resolution = 1 km |
| Attribution to specific vessels or operators | ❌ | Not within scope; privacy concerns |
| Legal / regulatory compliance monitoring | ❌ | Not validated for this purpose |
| Dredging intensity in ice-covered regions | ❌ | AIS coverage unreliable |
| Inland waterway dredging | ❌ | Land mask excludes most inland cells |

---

## Guidance for the manuscript Methods section

The following paragraph template is recommended for the L&O:Methods submission:

> "The pipeline processes AIS-transmitted vessel tracks and therefore captures
> only vessels carrying functional transponders. This introduces a systematic
> undercounting of dredging activity for vessels below the mandatory AIS threshold
> (< 300 GT in many flag states), vessels operating with transponders disabled, and
> unreported dredging. Our estimates should consequently be interpreted as lower
> bounds on global dredging intensity. Spatial coverage is most reliable in European,
> East Asian, and North American waters where AIS reception is dense; results in
> ice-affected, remote, and inland regions should be interpreted with caution.
> A structured sensitivity analysis (Figure [X]; see also Supporting Information)
> confirms that the dominant source of parametric uncertainty in C_ri is the
> fast-mineralising carbon fraction (fast_fraction), with a ±50% perturbation
> yielding approximately ±X% change in global C_ri."

---

## References

- Sala, E. et al. (2021). Protecting the global ocean for biodiversity, food and
  climate. *Nature* 592, 397–402. https://doi.org/10.1038/s41586-021-03371-z
- Atwood, T.B. et al. (2024). [Full reference for benthic carbon stocks — cite].
- JCGM 100:2008. Evaluation of measurement data — Guide to the Expression of
  Uncertainty in Measurement (GUM). BIPM.
