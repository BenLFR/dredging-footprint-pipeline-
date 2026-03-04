# Configuration Files

## `outlier_config.yaml`
Controls step 2 per-vessel filtering parameters:
- `IF_threshold`: intensity-fraction threshold for dredging flag
- Speed filter bounds (min/max knots)
- Land-crossing tolerance (metres)
- DBSCAN parameters (eps, minPts) used in step 3

## `ship_specs.yaml`
Specifications for the 10 TSHD (trailing suction hopper dredger) vessel types
used to compute the swept-area ratio (SAR):
- `beam_m`: trailing-arm beam width (m)
- `hopper_m3`: hopper volume (m³)
- `speed_knots`: typical dredging speed
- `vessel_class`: size class (small / medium / large)

These parameters feed directly into the SAR formula in step 5:
```
SAR = (beam × distance_dredging) / cell_area
```

All values were sourced from publicly available vessel registry data
and literature (Van Rijn, 1993; Kenny et al., 2003).
