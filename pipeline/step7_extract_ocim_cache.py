#!/usr/bin/env python3
"""step7_extract_ocim_cache.py — Python replacement for MATLAB script.

Extracts a portable cache from OCIM2_48L_CTL.mat for use in R.
Includes 9 spatial enrichment fields for conservative remapping:
  depth2d, oceanfrac2d, dist_to_coast2d, shelf_mask2d,
  shelf_component2d, seed_shelf_ij,
  ocean_component2d, coastal_wet_mask2d, seed_ocean_ij

The ocean connectivity fields enforce basin-aware redistribution:
  - ocean_component2d: 4-connectivity flood-fill on full wet mask (kbot>0),
    preventing diagonal leaks across isthmuses
  - coastal_wet_mask2d: ocean cells adjacent to land (4-conn), the preferred
    redistribution targets (Adcroft regrid_runoff coastal wet-point approach)
  - seed_ocean_ij: nearest coastal wet-point per land cell via KDTree

Usage on GRIT:
  python3 ~/ais-pipeline/pipeline_V6/step7_extract_ocim_cache.py

Input:  ~/scratch/configuration/ocim/OCIM2_48L_CTL.mat
Output: ~/scratch/configuration/ocim/ocim_cache.mat

Dependencies: numpy, scipy, h5py, geopandas, shapely, pyproj
"""

import os
import numpy as np
import scipy.io as sio
from scipy.spatial import cKDTree
from scipy.ndimage import label

ocim_dir = os.path.join(os.path.expanduser("~"), "scratch", "configuration", "ocim")
src_file = os.path.join(ocim_dir, "OCIM2_48L_CTL.mat")
out_file = os.path.join(ocim_dir, "ocim_cache.mat")

# Land mask shapefile for ocean-fraction computation
LAND_SHP = os.path.expanduser(
    os.environ.get("LAND_MASK_FILE",
                   "~/ais-pipeline/configuration/land_mask/land_polygons.shp")
)

assert os.path.isfile(src_file), f"OCIM source not found: {src_file}"


# ── Helper: lon/lat to 3D unit-sphere coordinates ──────────────────────────
def lonlat_to_xyz(lon, lat):
    lon_r = np.radians(lon)
    lat_r = np.radians(lat)
    return np.column_stack([
        np.cos(lat_r) * np.cos(lon_r),
        np.cos(lat_r) * np.sin(lon_r),
        np.sin(lat_r),
    ])


# ── Helper: compute ocean fraction per 2-deg cell using equal-area proj ────
def compute_oceanfrac(lon2d, lat2d, kbot, ni, nj, land_shp_path):
    """Compute ocean fraction per OCIM cell using EPSG:6933 equal-area projection.

    For cells crossing the dateline (|lon| near 180), the cell polygon is split
    into two sub-polygons before intersection.
    """
    import geopandas as gpd
    from shapely.geometry import box
    from shapely.ops import transform as shp_transform
    from pyproj import Transformer

    print("  Computing ocean fraction (equal-area EPSG:6933) ...")
    oceanfrac = np.full((ni, nj), np.nan)

    if not os.path.isfile(land_shp_path):
        print(f"  WARNING: land shapefile not found: {land_shp_path}")
        print("  Falling back to oceanfrac = 1.0 for all ocean cells")
        oceanfrac[kbot > 0] = 1.0
        oceanfrac[kbot == 0] = 0.0
        return oceanfrac

    land_gdf = gpd.read_file(land_shp_path)
    if land_gdf.crs is None or land_gdf.crs.to_epsg() != 4326:
        land_gdf = land_gdf.to_crs(epsg=4326)

    # Transformer WGS84 -> EPSG:6933 (equal-area cylindrical)
    to_ea = Transformer.from_crs("EPSG:4326", "EPSG:6933", always_xy=True)

    # Build lon/lat edges (midpoints between centers)
    ocim_lon = lon2d[0, :]  # nj values
    ocim_lat = lat2d[:, 0]  # ni values

    dlon = np.diff(ocim_lon)
    dlat = np.diff(ocim_lat)
    lon_edges = np.empty(nj + 1)
    lon_edges[0] = ocim_lon[0] - dlon[0] / 2
    lon_edges[1:-1] = (ocim_lon[:-1] + ocim_lon[1:]) / 2
    lon_edges[-1] = ocim_lon[-1] + dlon[-1] / 2
    lon_edges = np.clip(lon_edges, -180, 180)

    lat_edges = np.empty(ni + 1)
    lat_edges[0] = ocim_lat[0] - dlat[0] / 2
    lat_edges[1:-1] = (ocim_lat[:-1] + ocim_lat[1:]) / 2
    lat_edges[-1] = ocim_lat[-1] + dlat[-1] / 2
    lat_edges = np.clip(lat_edges, -90, 90)

    # Reproject land to EPSG:6933
    land_ea = land_gdf.to_crs(epsg=6933)
    land_union_ea = land_ea.union_all()

    n_ocean = int(np.sum(kbot > 0))
    done = 0
    for i in range(ni):
        for j in range(nj):
            if kbot[i, j] == 0:
                oceanfrac[i, j] = 0.0
                continue

            ymin = float(lat_edges[i])
            ymax = float(lat_edges[i + 1])
            xmin = float(lon_edges[j])
            xmax = float(lon_edges[j + 1])

            # Handle dateline crossing: if cell spans across +-180
            crosses_dateline = (xmin < -170 and xmax > 170) or (xmax - xmin > 180)

            if crosses_dateline:
                # Split into two sub-polygons: [-180, xmax] and [xmin, 180]
                cell_polys = [
                    box(-180, ymin, xmax, ymax),
                    box(xmin, ymin, 180, ymax),
                ]
            else:
                cell_polys = [box(xmin, ymin, xmax, ymax)]

            total_cell_area = 0.0
            total_land_area = 0.0
            for cpoly in cell_polys:
                # Reproject cell to equal-area
                cpoly_ea = shp_transform(lambda x, y: to_ea.transform(x, y), cpoly)
                ca = cpoly_ea.area
                total_cell_area += ca
                inter = cpoly_ea.intersection(land_union_ea)
                if not inter.is_empty:
                    total_land_area += inter.area

            if total_cell_area > 0:
                oceanfrac[i, j] = 1.0 - total_land_area / total_cell_area
            else:
                oceanfrac[i, j] = 1.0

            done += 1
            if done % 500 == 0:
                print(f"    oceanfrac: {done}/{n_ocean} ocean cells processed")

    print(f"  Ocean fraction: min={np.nanmin(oceanfrac[kbot>0]):.3f}, "
          f"median={np.nanmedian(oceanfrac[kbot>0]):.3f}, "
          f"max={np.nanmax(oceanfrac[kbot>0]):.3f}")
    return oceanfrac


# ── Main extraction ────────────────────────────────────────────────────────
print(f"Loading {src_file} ...")

def extract_and_enrich(lon2d, lat2d, M3d, DZT3d, DXT3d, DYT3d, dzt, ni, nj, nk):
    """Compute all derived fields from the raw OCIM grid."""

    # Ocean indices (1-based, column-major like MATLAB)
    iocn = np.where(M3d.ravel(order="F") == 1)[0] + 1  # 1-based
    m = len(iocn)
    print(f"Ocean points (m): {m}")

    # ── kbot: bottom wet layer index per column ────────────────────────────
    kbot = np.zeros((ni, nj), dtype=np.float64)
    for i in range(ni):
        for j in range(nj):
            col = M3d[i, j, :]
            wet = np.where(col == 1)[0]
            if len(wet) > 0:
                kbot[i, j] = wet[-1] + 1  # 1-based
    print(f"Columns with ocean bottom: {np.count_nonzero(kbot)} / {ni * nj}")

    # Authoritative ocean mask: kbot > 0
    is_ocean = (kbot > 0)

    # ── A1. depth2d: sum of DZT3d layers 1..kbot for each column [m] ──────
    print("Computing depth2d ...")
    depth2d = np.zeros((ni, nj), dtype=np.float64)
    for i in range(ni):
        for j in range(nj):
            kb = int(kbot[i, j])
            if kb > 0:
                depth2d[i, j] = np.sum(DZT3d[i, j, :kb])
    print(f"  depth2d: min={depth2d[is_ocean].min():.0f} m, "
          f"max={depth2d[is_ocean].max():.0f} m, "
          f"median={np.median(depth2d[is_ocean]):.0f} m")

    # ── A3. shelf_mask2d: boolean shelf mask (depth <= 200 m) ──────────────
    shelf_mask2d = is_ocean & (depth2d <= 200)
    print(f"Shelf cells (depth <= 200m): {np.sum(shelf_mask2d)}")

    # ── A4. dist_to_coast2d: distance to nearest land cell [km] ───────────
    print("Computing dist_to_coast2d (KDTree on unit sphere) ...")
    land_mask = ~is_ocean  # kbot == 0

    dist_to_coast2d = np.full((ni, nj), np.nan)

    if np.any(land_mask) and np.any(is_ocean):
        land_xyz = lonlat_to_xyz(lon2d[land_mask], lat2d[land_mask])
        tree_land = cKDTree(land_xyz)

        ocean_xyz = lonlat_to_xyz(lon2d[is_ocean], lat2d[is_ocean])
        chord_dist, _ = tree_land.query(ocean_xyz, k=1)
        # Convert chord distance to great-circle km
        dist_to_coast2d[is_ocean] = 2 * 6371 * np.arcsin(np.clip(chord_dist / 2, 0, 1))
    else:
        dist_to_coast2d[is_ocean] = 9999.0

    print(f"  dist_to_coast: min={np.nanmin(dist_to_coast2d[is_ocean]):.1f} km, "
          f"max={np.nanmax(dist_to_coast2d[is_ocean]):.1f} km, "
          f"median={np.nanmedian(dist_to_coast2d[is_ocean]):.1f} km")

    # ── A5. shelf_component2d: connected-component labels on shelf ─────────
    print("Computing shelf_component2d (8-connectivity + dateline wrap) ...")
    # Pad column 0 at end to handle dateline wrap
    padded = np.hstack([shelf_mask2d.astype(np.int32), shelf_mask2d[:, 0:1].astype(np.int32)])
    struct_8conn = np.ones((3, 3), dtype=np.int32)
    comp_padded, n_comp = label(padded, structure=struct_8conn)

    # Merge labels across dateline seam: if comp_padded[:, nj] != comp_padded[:, 0],
    # relabel the smaller component to the larger
    shelf_component2d = comp_padded[:, :nj].copy()
    for i in range(ni):
        lbl_left = shelf_component2d[i, 0]
        lbl_right = comp_padded[i, nj]  # the padded wrap column
        if lbl_left > 0 and lbl_right > 0 and lbl_left != lbl_right:
            # Merge: replace all occurrences of the larger label with the smaller
            old_lbl = max(lbl_left, lbl_right)
            new_lbl = min(lbl_left, lbl_right)
            shelf_component2d[shelf_component2d == old_lbl] = new_lbl

    n_unique = len(np.unique(shelf_component2d[shelf_component2d > 0]))
    print(f"  Shelf components: {n_unique} (after dateline merge)")

    # ── A5b. ocean_component2d: connected components on full wet mask ─────
    # Uses 4-connectivity (not 8) to prevent diagonal leaks across isthmuses
    print("Computing ocean_component2d (4-connectivity + dateline wrap) ...")
    struct_4conn = np.array([[0, 1, 0],
                             [1, 1, 1],
                             [0, 1, 0]], dtype=np.int32)
    padded_wet = np.hstack([is_ocean.astype(np.int32), is_ocean[:, 0:1].astype(np.int32)])
    ocomp_padded, n_ocomp = label(padded_wet, structure=struct_4conn)

    ocean_component2d = ocomp_padded[:, :nj].copy()
    for i in range(ni):
        lbl_left = ocean_component2d[i, 0]
        lbl_right = ocomp_padded[i, nj]
        if lbl_left > 0 and lbl_right > 0 and lbl_left != lbl_right:
            old_lbl = max(lbl_left, lbl_right)
            new_lbl = min(lbl_left, lbl_right)
            ocean_component2d[ocean_component2d == old_lbl] = new_lbl

    n_ocomp_unique = len(np.unique(ocean_component2d[ocean_component2d > 0]))
    print(f"  Ocean components: {n_ocomp_unique} (after dateline merge)")

    # Log component sizes (largest = world ocean)
    ocomp_labels, ocomp_counts = np.unique(
        ocean_component2d[ocean_component2d > 0], return_counts=True
    )
    sort_idx = np.argsort(-ocomp_counts)
    for rank, idx in enumerate(sort_idx[:5]):
        print(f"    Component {ocomp_labels[idx]}: {ocomp_counts[idx]} cells")
    if len(sort_idx) > 5:
        print(f"    ... and {len(sort_idx) - 5} smaller components")

    # ── A5c. coastal_wet_mask2d: ocean cells adjacent to land (4-conn) ────
    print("Computing coastal_wet_mask2d (ocean cells with land neighbor) ...")
    coastal_wet_mask2d = np.zeros((ni, nj), dtype=bool)
    for i in range(ni):
        for j in range(nj):
            if not is_ocean[i, j]:
                continue
            # 4-connectivity neighbors (N, S, E, W with dateline wrap on E/W)
            neighbors = []
            if i > 0:
                neighbors.append((i - 1, j))
            if i < ni - 1:
                neighbors.append((i + 1, j))
            neighbors.append((i, (j - 1) % nj))  # W with wrap
            neighbors.append((i, (j + 1) % nj))  # E with wrap
            for ni_, nj_ in neighbors:
                if not is_ocean[ni_, nj_]:
                    coastal_wet_mask2d[i, j] = True
                    break

    n_coastal = int(np.sum(coastal_wet_mask2d))
    n_ocean_total = int(np.sum(is_ocean))
    print(f"  Coastal wet cells: {n_coastal} / {n_ocean_total} ocean cells "
          f"({100 * n_coastal / max(n_ocean_total, 1):.1f}%)")

    # ── A5d. seed_ocean_ij: nearest coastal wet-point per land cell ───────
    print("Computing seed_ocean_ij (KDTree on coastal wet-points) ...")
    seed_ocean_i = np.zeros((ni, nj), dtype=np.float64)
    seed_ocean_j = np.zeros((ni, nj), dtype=np.float64)

    coastal_ij = np.argwhere(coastal_wet_mask2d)  # (n_coastal, 2)
    if len(coastal_ij) > 0 and np.any(land_mask):
        coastal_xyz = lonlat_to_xyz(lon2d[coastal_wet_mask2d], lat2d[coastal_wet_mask2d])
        tree_coastal = cKDTree(coastal_xyz)

        land_ij = np.argwhere(land_mask)
        land_xyz_pts = lonlat_to_xyz(lon2d[land_mask], lat2d[land_mask])
        _, coastal_idx = tree_coastal.query(land_xyz_pts, k=1)

        for k, (li, lj) in enumerate(land_ij):
            ci, cj = coastal_ij[coastal_idx[k]]
            seed_ocean_i[li, lj] = ci + 1  # 1-based for MATLAB/R
            seed_ocean_j[li, lj] = cj + 1

    n_seeded_ocean = int(np.sum(seed_ocean_i > 0))
    print(f"  Land cells with coastal wet seed: {n_seeded_ocean}")

    # Verify every land cell has a seed
    n_land = int(np.sum(land_mask))
    if n_seeded_ocean < n_land and n_coastal > 0:
        print(f"  WARNING: {n_land - n_seeded_ocean} land cells without coastal wet seed")

    # ── A6. seed_shelf_ij: nearest shelf cell for each land cell ──────────
    print("Computing seed_shelf_ij (KDTree) ...")
    seed_shelf_i = np.zeros((ni, nj), dtype=np.float64)
    seed_shelf_j = np.zeros((ni, nj), dtype=np.float64)

    shelf_ij = np.argwhere(shelf_mask2d)  # (n_shelf, 2)
    if len(shelf_ij) > 0 and np.any(land_mask):
        shelf_xyz = lonlat_to_xyz(lon2d[shelf_mask2d], lat2d[shelf_mask2d])
        tree_shelf = cKDTree(shelf_xyz)

        land_ij = np.argwhere(land_mask)
        land_xyz_pts = lonlat_to_xyz(lon2d[land_mask], lat2d[land_mask])
        _, shelf_idx = tree_shelf.query(land_xyz_pts, k=1)

        for k, (li, lj) in enumerate(land_ij):
            si, sj = shelf_ij[shelf_idx[k]]
            # Store as 1-based for MATLAB/R compatibility
            seed_shelf_i[li, lj] = si + 1
            seed_shelf_j[li, lj] = sj + 1

    n_seeded = np.sum(seed_shelf_i > 0)
    print(f"  Land cells with shelf seed: {n_seeded}")

    # ── A2. oceanfrac2d: true ocean fraction per 2-deg cell ───────────────
    # Prefer precomputed file (from scripts_principaux/precompute_oceanfrac2d.py)
    oceanfrac_precomputed = os.path.join(ocim_dir, "oceanfrac2d.mat")
    if os.path.isfile(oceanfrac_precomputed):
        print(f"Loading precomputed oceanfrac from {oceanfrac_precomputed}")
        tmp = sio.loadmat(oceanfrac_precomputed)
        oceanfrac2d = tmp["oceanfrac2d"]
        assert oceanfrac2d.shape == (ni, nj), \
            f"oceanfrac2d shape mismatch: {oceanfrac2d.shape} vs ({ni},{nj})"
    else:
        print("No precomputed oceanfrac2d.mat found — computing from scratch ...")
        print("  (requires geopandas, shapely, pyproj)")
        oceanfrac2d = compute_oceanfrac(lon2d, lat2d, kbot, ni, nj, LAND_SHP)

    return (iocn, m, kbot, depth2d, oceanfrac2d, shelf_mask2d,
            dist_to_coast2d, shelf_component2d, seed_shelf_i, seed_shelf_j,
            ocean_component2d, coastal_wet_mask2d, seed_ocean_i, seed_ocean_j)


# ── Load OCIM data ────────────────────────────────────────────────────────
try:
    S = sio.loadmat(src_file)
    grid = S["output"]["grid"][0, 0]
    M3d = S["output"]["M3d"][0, 0]

    ni, nj, nk = M3d.shape
    print(f"Grid dimensions: ni={ni}  nj={nj}  nk={nk}")

    lon2d = grid["XT3d"][0, 0][:, :, 0]
    lat2d = grid["YT3d"][0, 0][:, :, 0]
    DZT3d = grid["DZT3d"][0, 0]
    DXT3d = grid["DXT3d"][0, 0]
    DYT3d = grid["DYT3d"][0, 0]
    dzt = grid["dzt"][0, 0]

except NotImplementedError:
    # v7.3 HDF5 format
    import h5py
    with h5py.File(src_file, "r") as f:
        output = f["output"]
        grid_ref = output["grid"]
        M3d = np.array(output["M3d"]).T

        def deref(grp, name):
            ref = grp[name]
            return np.array(f[ref[0, 0]]).T if ref.shape == (1, 1) else np.array(ref).T

        lon3d = deref(grid_ref, "XT3d")
        lat3d = deref(grid_ref, "YT3d")
        DZT3d = deref(grid_ref, "DZT3d")
        DXT3d = deref(grid_ref, "DXT3d")
        DYT3d = deref(grid_ref, "DYT3d")
        dzt = deref(grid_ref, "dzt")

        lon2d = lon3d[:, :, 0]
        lat2d = lat3d[:, :, 0]
        ni, nj, nk = M3d.shape
        print(f"Grid dimensions: ni={ni}  nj={nj}  nk={nk}")

# ── Compute all enrichment fields ─────────────────────────────────────────
(iocn, m, kbot, depth2d, oceanfrac2d, shelf_mask2d,
 dist_to_coast2d, shelf_component2d, seed_shelf_i, seed_shelf_j,
 ocean_component2d, coastal_wet_mask2d, seed_ocean_i, seed_ocean_j) = \
    extract_and_enrich(lon2d, lat2d, M3d, DZT3d, DXT3d, DYT3d, dzt, ni, nj, nk)

# ── Save cache ────────────────────────────────────────────────────────────
print(f"Saving {out_file} ...")
sio.savemat(out_file, {
    # Original fields
    "lon2d": lon2d,
    "lat2d": lat2d,
    "M3d": M3d,
    "DZT3d": DZT3d,
    "DXT3d": DXT3d,
    "DYT3d": DYT3d,
    "dzt": dzt,
    "iocn": iocn.reshape(-1, 1),
    "kbot": kbot,
    "ni": np.array([[ni]]),
    "nj": np.array([[nj]]),
    "nk": np.array([[nk]]),
    "m": np.array([[m]]),
    # New spatial enrichment fields
    "depth2d": depth2d,
    "oceanfrac2d": oceanfrac2d,
    "shelf_mask2d": shelf_mask2d.astype(np.float64),
    "dist_to_coast2d": dist_to_coast2d,
    "shelf_component2d": shelf_component2d.astype(np.float64),
    "seed_shelf_i": seed_shelf_i,
    "seed_shelf_j": seed_shelf_j,
    # Ocean connectivity fields (ice-9 flood-fill)
    "ocean_component2d": ocean_component2d.astype(np.float64),
    "coastal_wet_mask2d": coastal_wet_mask2d.astype(np.float64),
    "seed_ocean_i": seed_ocean_i,
    "seed_ocean_j": seed_ocean_j,
}, do_compression=True)

size_mb = os.path.getsize(out_file) / 1e6
print(f"Done. Cache size: {size_mb:.1f} MB")
