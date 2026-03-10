% step7_extract_ocim_cache.m — One-shot MATLAB script
% Extracts a portable cache from OCIM2_48L_CTL.mat for use in R.
% Includes 6 spatial enrichment fields for conservative remapping:
%   depth2d, oceanfrac2d, dist_to_coast2d, shelf_mask2d,
%   shelf_component2d, seed_shelf_ij
%
% Run once on GRIT:
%   matlab -batch "run('step7_extract_ocim_cache.m')"
%
% Input:  ~/scratch/configuration/ocim/OCIM2_48L_CTL.mat
% Output: ~/scratch/configuration/ocim/ocim_cache.mat
%
% Note: oceanfrac2d requires the Python script (geopandas + equal-area
% projection). If running MATLAB-only, set OCEANFRAC_MAT to a precomputed
% file, or the script will fall back to oceanfrac=1 for all ocean cells.

%% Paths
ocim_dir  = fullfile(getenv('HOME'), 'scratch', 'configuration', 'ocim');
src_file  = fullfile(ocim_dir, 'OCIM2_48L_CTL.mat');
out_file  = fullfile(ocim_dir, 'ocim_cache.mat');

% Optional precomputed ocean fraction from Python
oceanfrac_file = fullfile(ocim_dir, 'oceanfrac2d.mat');

assert(exist(src_file, 'file') == 2, 'OCIM source not found: %s', src_file);

%% Load
fprintf('Loading %s ...\n', src_file);
S = load(src_file);

grid = S.output.grid;
M3d  = S.output.M3d;

[ni, nj, nk] = size(M3d);
fprintf('Grid dimensions: ni=%d  nj=%d  nk=%d\n', ni, nj, nk);

%% Extract 2-D and 3-D fields
lon2d  = grid.XT3d(:,:,1);
lat2d  = grid.YT3d(:,:,1);
DZT3d  = grid.DZT3d;
DXT3d  = grid.DXT3d;
DYT3d  = grid.DYT3d;
dzt    = grid.dzt;  % 1-D layer thicknesses (nk x 1), used in co2model.m:91

%% Ocean indices
iocn = find(M3d(:) == 1);
m    = length(iocn);
fprintf('Ocean points (m): %d\n', m);

%% Bottom wet layer index per column (kbot)
kbot = zeros(ni, nj);
for i = 1:ni
    for j = 1:nj
        col_mask = squeeze(M3d(i, j, :));
        k = find(col_mask == 1, 1, 'last');
        if ~isempty(k)
            kbot(i, j) = k;
        end
    end
end
fprintf('Columns with ocean bottom: %d / %d\n', nnz(kbot), ni*nj);

% Authoritative ocean mask
is_ocean = (kbot > 0);

%% A1. depth2d: sum of DZT3d layers 1..kbot for each column [m]
fprintf('Computing depth2d ...\n');
depth2d = zeros(ni, nj);
for i = 1:ni
    for j = 1:nj
        kb = kbot(i, j);
        if kb > 0
            depth2d(i, j) = sum(DZT3d(i, j, 1:kb));
        end
    end
end
fprintf('  depth2d: min=%.0f m, max=%.0f m\n', ...
    min(depth2d(is_ocean)), max(depth2d(is_ocean)));

%% A3. shelf_mask2d: boolean shelf mask (depth <= 200 m)
shelf_mask2d = is_ocean & (depth2d <= 200);
fprintf('Shelf cells (depth <= 200m): %d\n', nnz(shelf_mask2d));

%% A4. dist_to_coast2d: distance to nearest land cell [km]
fprintf('Computing dist_to_coast2d ...\n');
dist_to_coast2d = nan(ni, nj);

land_mask = ~is_ocean;

% Convert to 3D unit-sphere coordinates for KD-tree-like search
% MATLAB knnsearch supports this
lon_rad = deg2rad(lon2d);
lat_rad = deg2rad(lat2d);
xyz_x = cos(lat_rad) .* cos(lon_rad);
xyz_y = cos(lat_rad) .* sin(lon_rad);
xyz_z = sin(lat_rad);

land_idx = find(land_mask);
ocean_idx = find(is_ocean);

land_xyz = [xyz_x(land_idx), xyz_y(land_idx), xyz_z(land_idx)];
ocean_xyz = [xyz_x(ocean_idx), xyz_y(ocean_idx), xyz_z(ocean_idx)];

if ~isempty(land_xyz) && ~isempty(ocean_xyz)
    [~, chord_dist] = knnsearch(land_xyz, ocean_xyz, 'K', 1);
    % Convert chord to great-circle km
    gc_km = 2 * 6371 * asin(min(chord_dist / 2, 1));
    dist_to_coast2d(ocean_idx) = gc_km;
end

fprintf('  dist_to_coast: min=%.1f km, max=%.1f km\n', ...
    min(dist_to_coast2d(is_ocean)), max(dist_to_coast2d(is_ocean)));

%% A5. shelf_component2d: connected-component labels on shelf (8-connectivity + dateline wrap)
fprintf('Computing shelf_component2d ...\n');

% Pad column 1 at the end for dateline wrap
padded = [double(shelf_mask2d), double(shelf_mask2d(:, 1))];
CC = bwconncomp(padded, 8);
comp_padded = labelmatrix(CC);

% Extract original columns
shelf_component2d = comp_padded(:, 1:nj);

% Merge labels at dateline seam
for i = 1:ni
    lbl_left = shelf_component2d(i, 1);
    lbl_right = comp_padded(i, nj + 1);
    if lbl_left > 0 && lbl_right > 0 && lbl_left ~= lbl_right
        old_lbl = max(lbl_left, lbl_right);
        new_lbl = min(lbl_left, lbl_right);
        shelf_component2d(shelf_component2d == old_lbl) = new_lbl;
    end
end

n_unique = length(unique(shelf_component2d(shelf_component2d > 0)));
fprintf('  Shelf components: %d (after dateline merge)\n', n_unique);

%% A6. seed_shelf_ij: nearest shelf cell for each land cell
fprintf('Computing seed_shelf_ij ...\n');
seed_shelf_i = zeros(ni, nj);
seed_shelf_j = zeros(ni, nj);

shelf_idx_linear = find(shelf_mask2d);
[shelf_rows, shelf_cols] = ind2sub([ni, nj], shelf_idx_linear);

if ~isempty(shelf_idx_linear) && any(land_mask(:))
    shelf_xyz = [xyz_x(shelf_idx_linear), xyz_y(shelf_idx_linear), xyz_z(shelf_idx_linear)];

    land_idx_linear = find(land_mask);
    land_xyz_pts = [xyz_x(land_idx_linear), xyz_y(land_idx_linear), xyz_z(land_idx_linear)];

    [nearest_shelf, ~] = knnsearch(shelf_xyz, land_xyz_pts, 'K', 1);

    for k = 1:length(land_idx_linear)
        [li, lj] = ind2sub([ni, nj], land_idx_linear(k));
        seed_shelf_i(li, lj) = shelf_rows(nearest_shelf(k));  % 1-based already in MATLAB
        seed_shelf_j(li, lj) = shelf_cols(nearest_shelf(k));
    end
end

fprintf('  Land cells with shelf seed: %d\n', nnz(seed_shelf_i));

%% A2. oceanfrac2d: true ocean fraction per cell
% Prefer precomputed from Python (requires geopandas + equal-area proj)
if exist(oceanfrac_file, 'file') == 2
    fprintf('Loading precomputed oceanfrac from %s\n', oceanfrac_file);
    tmp = load(oceanfrac_file, 'oceanfrac2d');
    oceanfrac2d = tmp.oceanfrac2d;
else
    fprintf('  WARNING: No precomputed oceanfrac2d.mat found.\n');
    fprintf('  Falling back to oceanfrac=1.0 for all ocean cells.\n');
    fprintf('  Run step7_extract_ocim_cache.py first for accurate ocean fractions.\n');
    oceanfrac2d = zeros(ni, nj);
    oceanfrac2d(is_ocean) = 1.0;
end

%% Save cache
fprintf('Saving %s ...\n', out_file);
save(out_file, ...
    'lon2d', 'lat2d', 'M3d', 'DZT3d', 'DXT3d', 'DYT3d', ...
    'dzt', 'iocn', 'kbot', 'ni', 'nj', 'nk', 'm', ...
    'depth2d', 'oceanfrac2d', 'shelf_mask2d', ...
    'dist_to_coast2d', 'shelf_component2d', ...
    'seed_shelf_i', 'seed_shelf_j', ...
    '-v7');

fprintf('Done. Cache size: %.1f MB\n', dir(out_file).bytes / 1e6);
