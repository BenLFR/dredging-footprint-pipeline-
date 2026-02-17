#!/usr/bin/env python3
"""audit_jdredge.py — Audit the Jdredge forcing .mat file for OCIM2-48L.

Checks:
  - Variable inventory and shapes
  - Nonzero cell counts per scenario
  - Linear scaling between 1x/10x/100x
  - Conservation metadata
  - Spatial distribution summary

Usage:
  python3 audit_jdredge.py <jdredge_ocim2_48l_*.mat>
  python3 audit_jdredge.py   # auto-detect latest in ~/scratch/output_V6
"""

import sys
import os
import glob
import numpy as np
import scipy.io as sio

def find_latest(pattern):
    files = glob.glob(pattern)
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def main():
    print("=== AUDIT JDREDGE FORCING ===\n")

    # Locate file
    if len(sys.argv) > 1:
        mat_path = sys.argv[1]
    else:
        out_dir = os.path.expanduser("~/scratch/output_V6")
        mat_path = find_latest(os.path.join(out_dir, "jdredge_ocim2_48l_*.mat"))
        if not mat_path:
            # Also check ocim config dir
            ocim_dir = os.path.expanduser("~/scratch/configuration/ocim")
            mat_path = find_latest(os.path.join(ocim_dir, "jdredge_ocim2_48l_*.mat"))
        if not mat_path:
            print("ERROR: No jdredge_ocim2_48l_*.mat found")
            sys.exit(1)

    print(f"File: {mat_path}")
    print(f"Size: {os.path.getsize(mat_path) / 1e6:.1f} MB\n")

    mat = sio.loadmat(mat_path)

    # ── Variable inventory ────────────────────────────────────────────────────

    print("--- Variable Inventory ---")
    skip = {"__header__", "__version__", "__globals__"}
    vars_info = {}
    for k, v in sorted(mat.items()):
        if k in skip:
            continue
        if isinstance(v, np.ndarray):
            vars_info[k] = v
            print(f"  {k:40s}  shape={str(v.shape):15s}  dtype={v.dtype}")
        else:
            print(f"  {k:40s}  type={type(v).__name__}")

    # ── Jdredge analysis ──────────────────────────────────────────────────────

    print("\n--- Jdredge Scenarios ---")
    scenarios = {}
    for name in ["Jdredge", "Jdredge_10x", "Jdredge_100x",
                  "Jdredge_lower", "Jdredge_upper", "Jdredge_conservative",
                  "Jtrawl", "Jtrawl_10x", "Jtrawl_100x"]:
        if name in vars_info:
            J = vars_info[name].ravel()
            n_active = np.count_nonzero(J)
            scenarios[name] = {
                "n_active": n_active,
                "max": float(np.max(J)),
                "mean_active": float(np.mean(J[J > 0])) if n_active > 0 else 0,
                "sum": float(np.sum(J)),
            }
            print(f"  {name:35s}  active={n_active:5d}  "
                  f"max={scenarios[name]['max']:.4e}  "
                  f"mean(active)={scenarios[name]['mean_active']:.4e}")

    # ── Scaling check ─────────────────────────────────────────────────────────

    print("\n--- Linear Scaling Check ---")
    n_pass = 0
    n_fail = 0

    def check_scaling(base_name, scaled_name, factor):
        nonlocal n_pass, n_fail
        if base_name in vars_info and scaled_name in vars_info:
            base = vars_info[base_name].ravel()
            scaled = vars_info[scaled_name].ravel()
            expected = base * factor
            max_err = float(np.max(np.abs(scaled - expected)))
            if max_err < 1e-10:
                print(f"  ✅ {scaled_name} == {factor}× {base_name} (max_err={max_err:.2e})")
                n_pass += 1
            else:
                print(f"  ❌ {scaled_name} != {factor}× {base_name} (max_err={max_err:.2e})")
                n_fail += 1

    check_scaling("Jdredge", "Jdredge_10x", 10)
    check_scaling("Jdredge", "Jdredge_100x", 100)
    check_scaling("Jdredge_lower", "Jdredge_lower_10x", 10)
    check_scaling("Jdredge_lower", "Jdredge_lower_100x", 100)
    check_scaling("Jdredge_upper", "Jdredge_upper_10x", 10)
    check_scaling("Jdredge_upper", "Jdredge_upper_100x", 100)

    # Also verify Jtrawl == Jdredge (backward compat alias)
    if "Jtrawl" in vars_info and "Jdredge" in vars_info:
        diff = np.max(np.abs(vars_info["Jtrawl"].ravel() - vars_info["Jdredge"].ravel()))
        if diff < 1e-15:
            print(f"  ✅ Jtrawl == Jdredge (alias OK)")
            n_pass += 1
        else:
            print(f"  ❌ Jtrawl != Jdredge (diff={diff:.2e})")
            n_fail += 1

    # ── Metadata ──────────────────────────────────────────────────────────────

    print("\n--- Metadata ---")
    meta_keys = ["n_cells_active", "total_flux_gC_yr", "conservation_error_pct",
                 "timestamp_str", "m",
                 # New split metrics (replace old coastal_flux_redistributed_pct)
                 "land_pool_pct", "offshore_displacement_pct", "shelf_flux_pct",
                 "max_cell_share_pct", "top1pct_flux_share",
                 "delta_median_dist_coast_km", "delta_p90_dist_coast_km",
                 # Redistribution parameters
                 "redistribution_R_km", "redistribution_lambda_km",
                 "redistribution_k_max", "redistribution_alpha",
                 "redistribution_oceanfrac_floor",
                 # Redistribution quality counters (6-stage cascade)
                 "n_relax_component", "n_relax_ocean_component",
                 "n_relax_shelf", "n_expand_radius",
                 "n_connectivity_fallback", "n_absolute_fallback",
                 "n_fallback_nearest", "n_cross_basin",
                 "n_cross_shelf_component", "cross_scomp_flux_pct",
                 "mean_redist_km",
                 "conservation_error_mass_pct",
                 # Legacy (may be present in older files)
                 "coastal_flux_redistributed_pct"]
    for k in meta_keys:
        if k in mat:
            v = mat[k]
            if isinstance(v, np.ndarray) and v.size == 1:
                print(f"  {k}: {v.flat[0]}")
            elif isinstance(v, np.ndarray) and v.dtype.kind in ('U', 'S', 'O'):
                print(f"  {k}: {str(v.flat[0])}")
            else:
                print(f"  {k}: {v}")

    # ── Spatial summary ───────────────────────────────────────────────────────

    if "Jdredge" in vars_info:
        J = vars_info["Jdredge"].ravel()
        active = J[J > 0]
        if len(active) > 0:
            print("\n--- Spatial Distribution (Jdredge 1×) ---")
            print(f"  Total cells:  {len(J)}")
            print(f"  Active cells: {len(active)}")
            print(f"  Min (active): {np.min(active):.6e} µmol/kg/yr")
            print(f"  Max (active): {np.max(active):.6e} µmol/kg/yr")
            print(f"  Mean(active): {np.mean(active):.6e} µmol/kg/yr")
            print(f"  Std (active): {np.std(active):.6e} µmol/kg/yr")

            # Percentile distribution
            pcts = [10, 25, 50, 75, 90, 95, 99]
            vals = np.percentile(active, pcts)
            print("  Percentiles:")
            for p, v in zip(pcts, vals):
                print(f"    P{p:02d}: {v:.6e}")

    # ── Summary ───────────────────────────────────────────────────────────────

    print(f"\n{'='*50}")
    print(f"SUMMARY: {n_pass} PASS, {n_fail} FAIL")
    if n_fail > 0:
        print("STATUS: ❌ AUDIT FAILED")
        sys.exit(1)
    else:
        print("STATUS: ✅ ALL CHECKS PASSED")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
