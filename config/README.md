# Configuration Files

## `ship_specs.yaml`

Technical specifications for the 10 TSHDs (trailing-suction hopper dredgers)
used to compute the swept-area ratio (SAR).

Key fields per vessel:

| Field | Unit | Description |
|-------|------|-------------|
| `ssvid` | — | Vessel MMSI identifier |
| `dredge_width_m` | m | Drag-head beam width — `W_v` in the SAR formula |
| `dredging_depth_m` | m | Maximum dredging depth |
| `service_speed_kn` | kn | Service speed (used for speed-filter calibration) |
| `hopper_capacity_m3` | m³ | Hopper volume |
| `imo` | — | IMO vessel number |

These parameters feed directly into the SAR formula (step 5):

```
SAR_i = (dredge_width_m × distance_dredging_m) / cell_area_m2
```

All values were extracted from:

> IHS Markit, *International Dredging Directory 2021*, p. 33.
> URL: https://cdn.ihsmarkit.com/www/pdf/1220/International-Dredging-Directory-2021.pdf

Vessel technical specifications (beam width, dredging depth, hopper capacity,
installed power) are factual data and are not copyrightable as such.
The IDD 2021 is cited as the bibliographic source per TP-DATA-007 in
`THIRD_PARTY_NOTICES.md`.

Used by: step 1 (vessel filtering), step 2 (speed calibration), step 5b (SAR computation).

---

## `outlier_config_V6.yaml`

Controls per-vessel filtering in step 2 and global outlier removal in step 3:

- **Isolation Forest** (`contamination_rate`, `if_num_trees`): anomaly detection
  on (speed, turn_rate) feature space
- `speed_margin_pct`: fractional tolerance above `service_speed_kn` before a
  point is considered a physics outlier
- DBSCAN parameters (`eps_km`, `min_pts`): spatial cluster filtering in step 3

Used by: step 2, step 3.

---

## `fi_parameters_with_freshness.yaml`

Scenario-based biogeochemical parameters for the f_i and C_ri computation.

Contains three scenarios: `default`, `conservative`, `upper_bound`.

Key parameters:

| Parameter | Description |
|-----------|-------------|
| `k_fast` | Province-scale remineralisation rate (yr⁻¹), keyed by Longhurst basin |
| `alpha_dep` | Fraction of disturbed OC entering fast pool |
| `fast_fraction` | Fast-pool size fraction |
| `slow_k` | Slow-pool decay rate (yr⁻¹) |
| `preservation_factor` (`p_r`) | Fraction of disturbed OC that resettles in-cell (Sala et al. 2021) |
| `depletion_factor` (`d_i`) | OC stock depletion after >10 yr chronic trawling (Atwood et al. 2023) |
| `fresh_fact` | Province-scale freshness multiplier keyed by Longhurst ProvCode |

Copy to your cluster as `~/scratch/configuration/fi_parameters_with_freshness.yaml`
before running step 5.

Used by: step 5b (tile worker), step 5c (merge).

---

## `outlier_config.yaml` (deprecated)

Superseded by `outlier_config_V6.yaml`. Retained in history only. Do not use.
