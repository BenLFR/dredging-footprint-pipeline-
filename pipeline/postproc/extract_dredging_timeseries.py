#!/usr/bin/env python3
"""extract_dredging_timeseries.py — Extract publishable CSV from dredging_results_*.mat.

Extracts from the actual .mat layout:
  - all_pco2a   (4 × nt)  pCO2_atm per scenario
  - all_flux_GtC (4 × nt)  air-sea flux per scenario
  - t            (1 × nt)  time steps (year indices 1780+)
  - scenario_names (1 × 4) labels

Outputs:
  - dredging_timeseries.csv  (full time series)
  - Summary table to stdout

Usage:
  python3 extract_dredging_timeseries.py <dredging_results_*.mat>
  python3 extract_dredging_timeseries.py   # auto-detect latest
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
    print("=== EXTRACT DREDGING TIME SERIES ===\n")

    # Locate file
    if len(sys.argv) > 1:
        mat_path = sys.argv[1]
    else:
        ocim_dir = os.path.expanduser("~/scratch/configuration/ocim")
        mat_path = find_latest(os.path.join(ocim_dir, "dredging_results_*.mat"))
        if not mat_path:
            out_dir = os.path.expanduser("~/scratch/output_V6")
            mat_path = find_latest(os.path.join(out_dir, "dredging_results_*.mat"))
        if not mat_path:
            print("ERROR: No dredging_results_*.mat found")
            sys.exit(1)

    print(f"File: {mat_path}")
    print(f"Size: {os.path.getsize(mat_path) / 1e6:.1f} MB\n")

    mat = sio.loadmat(mat_path)

    # ── Discover variables ────────────────────────────────────────────────────

    print("--- Variables ---")
    skip = {"__header__", "__version__", "__globals__"}
    for k, v in sorted(mat.items()):
        if k in skip:
            continue
        if isinstance(v, np.ndarray):
            print(f"  {k:40s}  shape={str(v.shape):15s}  dtype={v.dtype}")

    # ── Extract time and scenario labels ──────────────────────────────────────

    print("\n--- Extracting time series ---")

    # Time vector (t or year)
    if "t" in mat:
        t_vec = mat["t"].ravel().astype(float)
        # t contains time step indices; convert to actual years (OCIM starts at 1780)
        # Check if values look like years (>1000) or indices (<1000)
        if t_vec[0] > 1000:
            years = t_vec
        else:
            years = 1780 + t_vec - 1  # 1-based index to year
        print(f"  Time vector 't': {len(years)} steps, range [{years[0]:.0f}, {years[-1]:.0f}]")
    elif "year" in mat:
        years = mat["year"].ravel().astype(float)
        print(f"  Time vector 'year': {len(years)} steps, range [{years[0]:.0f}, {years[-1]:.0f}]")
    else:
        years = np.arange(1780, 2101, dtype=float)
        print(f"  No time vector found, using default 1780-2100 ({len(years)} steps)")

    # Scenario names
    if "scenario_names" in mat:
        sn = mat["scenario_names"].ravel()
        scenario_names = [str(s).strip() for s in sn]
        print(f"  Scenarios: {scenario_names}")
    else:
        scenario_names = ["baseline", "dredge_1x", "dredge_10x", "dredge_100x"]
        print(f"  No scenario_names found, using default: {scenario_names}")

    # ── Extract pCO2 and flux matrices ────────────────────────────────────────

    # all_pco2a: (n_scenarios × nt)
    all_pco2a = None
    for name in ["all_pco2a", "pCO2atm", "pco2_all"]:
        if name in mat and mat[name].ndim == 2:
            all_pco2a = mat[name]
            # Ensure shape is (n_scenarios, nt) — transpose if needed
            if all_pco2a.shape[0] > all_pco2a.shape[1]:
                all_pco2a = all_pco2a.T
            print(f"  pCO2 matrix '{name}': shape={all_pco2a.shape}")
            break

    # all_flux_GtC: (n_scenarios × nt)
    all_flux = None
    for name in ["all_flux_GtC", "Fairsea", "flux_all"]:
        if name in mat and mat[name].ndim == 2:
            all_flux = mat[name]
            if all_flux.shape[0] > all_flux.shape[1]:
                all_flux = all_flux.T
            print(f"  Flux matrix '{name}': shape={all_flux.shape}")
            break

    if all_pco2a is None and all_flux is None:
        print("\n  ERROR: Could not find pCO2 or flux matrices.")
        print("  Looked for: all_pco2a, pCO2atm, all_flux_GtC, Fairsea")
        sys.exit(1)

    # ── Align dimensions ──────────────────────────────────────────────────────

    n_scenarios = len(scenario_names)
    nt = len(years)

    # The matrices may have a different nt than the year vector
    if all_pco2a is not None:
        nt_data = all_pco2a.shape[1]
        if nt_data != nt:
            print(f"  NOTE: pCO2 has {nt_data} time steps but year vector has {nt}")
            nt = min(nt, nt_data)
            years = years[:nt]

    if all_flux is not None:
        nt_data = all_flux.shape[1]
        if nt_data != nt:
            nt = min(nt, nt_data)
            years = years[:nt]

    # ── Forcing start index ───────────────────────────────────────────────────

    i_forcing = None
    if "i_forcing_start" in mat:
        i_forcing = int(mat["i_forcing_start"].flat[0])
        forcing_year = years[i_forcing - 1] if i_forcing <= len(years) else "?"
        print(f"  Forcing starts at index {i_forcing} (year {forcing_year})")

    # ── Build output CSV ──────────────────────────────────────────────────────

    out_dir = os.path.expanduser("~/scratch/output_V6")
    os.makedirs(out_dir, exist_ok=True)
    csv_path = os.path.join(out_dir, "dredging_timeseries.csv")

    print(f"\n--- Writing CSV: {csv_path} ---")

    # Baseline is scenario index 0
    baseline_pco2 = all_pco2a[0, :nt] if all_pco2a is not None else None
    baseline_flux = all_flux[0, :nt] if all_flux is not None else None

    header_cols = ["year", "scenario", "pCO2_uatm", "delta_pCO2_uatm",
                   "flux_GtC_yr", "delta_flux_GtC_yr", "cumulative_delta_flux_GtC"]

    rows = []
    for si, sname in enumerate(scenario_names):
        if si >= (all_pco2a.shape[0] if all_pco2a is not None else 0) and \
           si >= (all_flux.shape[0] if all_flux is not None else 0):
            continue

        pco2 = all_pco2a[si, :nt] if all_pco2a is not None and si < all_pco2a.shape[0] else None
        flux = all_flux[si, :nt] if all_flux is not None and si < all_flux.shape[0] else None

        cumsum = 0.0
        for ti in range(nt):
            row = {
                "year": int(years[ti]),
                "scenario": sname,
                "pCO2_uatm": f"{pco2[ti]:.6f}" if pco2 is not None else "",
                "delta_pCO2_uatm": "",
                "flux_GtC_yr": f"{flux[ti]:.8f}" if flux is not None else "",
                "delta_flux_GtC_yr": "",
                "cumulative_delta_flux_GtC": "",
            }

            if si > 0:  # Not baseline
                if pco2 is not None and baseline_pco2 is not None:
                    dpco2 = pco2[ti] - baseline_pco2[ti]
                    row["delta_pCO2_uatm"] = f"{dpco2:.10f}"
                if flux is not None and baseline_flux is not None:
                    dflux = flux[ti] - baseline_flux[ti]
                    row["delta_flux_GtC_yr"] = f"{dflux:.12f}"
                    cumsum += dflux
                    row["cumulative_delta_flux_GtC"] = f"{cumsum:.10f}"

            rows.append(row)

    # Write CSV
    with open(csv_path, "w") as fout:
        fout.write(",".join(header_cols) + "\n")
        for r in rows:
            fout.write(",".join(str(r[k]) for k in header_cols) + "\n")

    print(f"  Written: {csv_path}")
    print(f"  Rows: {len(rows)} ({nt} years × {n_scenarios} scenarios)")

    # ── DIC fields (if present) ───────────────────────────────────────────────

    dic_keys = [k for k in mat if k.startswith("DIC_final_")]
    if dic_keys:
        print(f"\n--- DIC Final Fields ---")
        for k in sorted(dic_keys):
            arr = mat[k].ravel()
            nz = np.count_nonzero(arr)
            print(f"  {k}: shape={mat[k].shape}, nonzero={nz}, "
                  f"range=[{np.min(arr):.4f}, {np.max(arr):.4f}]")

        # Delta DIC if both baseline and 1x exist
        if "DIC_final_baseline" in mat and "DIC_final_1x" in mat:
            dic_bl = mat["DIC_final_baseline"].ravel()
            dic_1x = mat["DIC_final_1x"].ravel()
            delta_dic = dic_1x - dic_bl
            nz_delta = np.count_nonzero(np.abs(delta_dic) > 1e-15)
            print(f"\n  ΔDIC (1× - baseline):")
            print(f"    Nonzero cells: {nz_delta}")
            print(f"    Range: [{np.min(delta_dic):.6e}, {np.max(delta_dic):.6e}] µmol/kg")
            print(f"    Mean (nonzero): {np.mean(delta_dic[np.abs(delta_dic) > 1e-15]):.6e} µmol/kg")

    # ── Summary table ─────────────────────────────────────────────────────────

    print(f"\n{'='*90}")
    print("RESULTS SUMMARY (Year 2100)")
    print(f"{'='*90}")
    print(f"  {'Scenario':20s} {'pCO2 (µatm)':>14s} {'ΔpCO2 (µatm)':>14s} "
          f"{'Δflux (GtC/yr)':>16s} {'Cumul Δflux (GtC)':>18s}")
    print(f"  {'-'*20} {'-'*14} {'-'*14} {'-'*16} {'-'*18}")

    for sname in scenario_names:
        scenario_rows = [r for r in rows if r["scenario"] == sname]
        if scenario_rows:
            last = scenario_rows[-1]
            pco2_s = last["pCO2_uatm"] or "N/A"
            dpco2_s = last["delta_pCO2_uatm"] or "-"
            dflux_s = last["delta_flux_GtC_yr"] or "-"
            cumul_s = last["cumulative_delta_flux_GtC"] or "-"
            print(f"  {sname:20s} {pco2_s:>14s} {dpco2_s:>14s} {dflux_s:>16s} {cumul_s:>18s}")

    if i_forcing is not None:
        print(f"\n  Forcing start: year {forcing_year} (index {i_forcing})")

    print(f"\n=== DONE ===")


if __name__ == "__main__":
    main()
