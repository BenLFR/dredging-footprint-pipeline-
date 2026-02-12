% co2model_dredge.m — OCIM2-48L carbon model with dredging forcing
%
% Memory-optimized: only keeps scalar time series (pCO2, flux),
% not the full 3-D DIC fields at every time step.
%
% Performance-optimized:
%   - Jgas computed directly from converged solution (no redundant ns_step_eb)
%   - Dredging scenarios start from 2012 (AIS data era), not 1780
%   - Looser GMRES tolerance for amplified scenarios (10x, 100x)
%
% Runs 4 scenarios sequentially:
%   1) Baseline (no dredging) — full 1780-2100
%   2) Jdredge 1x   — starts from baseline state at 2012
%   3) Jdredge 10x  — starts from baseline state at 2012
%   4) Jdredge 100x — starts from baseline state at 2012
%
% Usage:
%   matlab -nodesktop -nodisplay -nosplash -batch "run('co2model_dredge.m')"
%
% Input:  OCIM2_48L_CTL.mat, woa09si.mat, woa09po4.mat, schmidt_coeff.mat,
%         netemission.txt, jdredge_ocim2_48l_*.mat (from Step 7)
% Output: dredging_results_<timestamp>.mat

fprintf('=== CO2 MODEL WITH DREDGING FORCING ===\n');
fprintf('Start: %s\n\n', datestr(now));
tic_total = tic;

% ── Load OCIM model ──────────────────────────────────────────────────────────
fprintf('Loading OCIM2_48L_CTL.mat ...\n');
load OCIM2_48L_CTL.mat output sol
grid = output.grid;
M3d = output.M3d;

iocn = find(M3d(:)==1);
isurf = find(M3d(:,:,1)==1);
ns = length(isurf);
m = size(output.TR,1);
fprintf('  Ocean points: m=%d, surface=%d\n', m, ns);

TR = output.TR;

% Gas exchange setup
u10 = mean(output.data.u10cfc11,2);
fice = mean(output.data.ficecfc11,2);
temp = output.data.dens.tstar(1:ns);
salt = output.data.dens.sstar(1:ns);
Sc_co2 = schmidt(temp,'co2');
a = sol(length(sol));
Kw = a*(1-fice).*(u10.^2).*(Sc_co2./660).^-.5;
clear output sol  % free ~1 GB

% ── Load Jdredge forcing ─────────────────────────────────────────────────────
fprintf('\nLoading Jdredge forcing ...\n');
jdredge_files = dir('jdredge_ocim2_48l_*.mat');
assert(~isempty(jdredge_files), 'No jdredge_ocim2_48l_*.mat found.');
[~, idx] = max([jdredge_files.datenum]);
jdredge_path = fullfile(jdredge_files(idx).folder, jdredge_files(idx).name);
fprintf('  File: %s\n', jdredge_path);

jd = load(jdredge_path);
Jdredge_1x   = jd.Jdredge;
Jdredge_10x  = jd.Jdredge_10x;
Jdredge_100x = jd.Jdredge_100x;
clear jd
fprintf('  Jdredge 1x:   %d active cells, max=%.4e umol/kg/yr\n', ...
        sum(Jdredge_1x > 0), max(Jdredge_1x));

% ── Nutrients ─────────────────────────────────────────────────────────────────
fprintf('Loading nutrients ...\n');
load woa09si.mat si_an LON LAT DEPTH
load woa09po4.mat po4_an
Si = interp3(LON,LAT,DEPTH,si_an,grid.XT3d,grid.YT3d,grid.ZT3d);
Po4 = interp3(LON,LAT,DEPTH,po4_an,grid.XT3d,grid.YT3d,grid.ZT3d);
clear si_an po4_an LON LAT DEPTH
for k = 1:size(M3d,3)
  si(:,:,k) = inpaint_nans(Si(:,:,k));
  po4(:,:,k) = inpaint_nans(Po4(:,:,k));
end
clear Si Po4

% ── CO2 system parameters ────────────────────────────────────────────────────
co2syspar.pres = sw_pres(grid.ZT3d(isurf),grid.YT3d(isurf));
co2syspar.si = si(isurf);
co2syspar.po4 = po4(isurf);
co2syspar.temp = temp;
co2syspar.salt = salt;
clear si po4

rhobar = 1025;
sbar = (grid.DXT3d(isurf).*grid.DYT3d(isurf).*grid.DZT3d(isurf))'*salt(1:ns) ...
       ./sum(grid.DXT3d(isurf).*grid.DYT3d(isurf).*grid.DZT3d(isurf));
alk = 2310*salt./sbar;
co2syspar.alk = alk(1:ns);
pco2atm = 280;

% ── Gas exchange operator ─────────────────────────────────────────────────────
Q = 0*M3d;
Q(isurf) = Kw./grid.dzt(1);
Qgas = d0(Q(iocn));
clear Q
V = grid.DXT3d(iocn).*grid.DYT3d(iocn).*grid.DZT3d(iocn);

% ── Solve equilibrium DIC ─────────────────────────────────────────────────────
fprintf('\nSolving for equilibrium DIC distribution ...\n');
tic_eq = tic;
dic0 = zeros(m,1)+2100;
options.atol = 5e-6; options.rtol = 1e-16; options.iprint = 1;
[dic,ierr] = nsnew(dic0,@(x)eqdic(x,grid,M3d,TR,Kw,pco2atm,co2syspar),options);
fprintf('  Equilibrium solve: %.1f s (ierr=%d)\n', toc(tic_eq), ierr);

% ── Time stepping setup ──────────────────────────────────────────────────────
f = load('netemission.txt');
year_em = f(:,1);
em_gcb = f(:,2);
dt = 1;
year = 1780:2100;
Jem = zeros(length(year)+1,1);
Jem(2:length(em_gcb)+1) = em_gcb;
Jem(length(em_gcb)+2:length(year)+1) = em_gcb(length(em_gcb));
t = 0:dt:length(year);
nt = length(t);
clear f year_em em_gcb

% Dredging forcing start index: year 2012 = index 233 in year array
% t(1)=0 -> year 1780, t(233) -> year 2012
i_forcing_start = 233;
fprintf('  Dredging forcing starts at year %d (time index %d)\n', ...
        year(i_forcing_start), i_forcing_start);

% Preconditioner (shared across all scenarios)
fprintf('Factoring preconditioner ...\n');
tic_pre = tic;
xi = [dic;pco2atm];
[~,Jac] = ns_step_eb(xi,TR,M3d,V,Qgas,pco2atm,co2syspar,Jem(1),zeros(m,1),dt,dic);
FM = mfactor(Jac);
precond = @(x)mfactor(FM,x);
clear Jac
fprintf('  Preconditioner: %.1f s\n', toc(tic_pre));

% ── Validate surface mapping assumption (Opt 1 prerequisite) ─────────────────
assert(isequal(iocn(1:ns), isurf), 'Mapping surface iocn/isurf inattendu');
fprintf('  Surface mapping iocn(1:ns)==isurf validated.\n');

% ── Run scenarios sequentially (memory-efficient) ────────────────────────────
scenario_names = {'baseline', 'dredge_1x', 'dredge_10x', 'dredge_100x'};
scenario_forcing = {zeros(m,1), Jdredge_1x, Jdredge_10x, Jdredge_100x};
n_scenarios = length(scenario_names);

% Only store scalar time series per scenario
all_pco2a = zeros(n_scenarios, nt);
all_flux_GtC = zeros(n_scenarios, nt);

% Also save final DIC snapshot for baseline and 1x only
DIC_final_baseline = [];
DIC_final_1x = [];

% Baseline state at 2012, saved during baseline run for dredging scenarios
DIC_at_2012 = [];
pco2a_at_2012 = [];

for s = 1:n_scenarios
  fprintf('\n=== Scenario %d/%d: %s ===\n', s, n_scenarios, scenario_names{s});
  tic_scen = tic;

  Jforcing = scenario_forcing{s};

  % ── Opt 3: Looser GMRES tolerance for amplified scenarios ──────────────
  if s <= 2  % baseline and 1x
    options_gm.atol = 2e-6;
  else       % 10x and 100x
    options_gm.atol = 5e-5;
  end
  options_gm.rtol = 1e-16; options_gm.iprint = 0;

  % ── Opt 2: Dredging scenarios start from baseline state at 2012 ────────
  if s == 1
    % Baseline: run full 1780-2100
    i_start = 2;
    DIC_prev = dic;
    pco2a_prev = pco2atm;
    all_pco2a(s,1) = pco2atm;
    all_flux_GtC(s,1) = 0;
  else
    % Dredging scenarios: copy baseline 1780-2011, start from 2012
    i_start = i_forcing_start + 1;
    all_pco2a(s, 1:i_forcing_start) = all_pco2a(1, 1:i_forcing_start);
    all_flux_GtC(s, 1:i_forcing_start) = all_flux_GtC(1, 1:i_forcing_start);
    DIC_prev = DIC_at_2012;
    pco2a_prev = pco2a_at_2012;
    fprintf('  Starting from baseline state at year %d (steps %d-%d = %d steps)\n', ...
            year(i_forcing_start), i_start, nt, nt - i_start + 1);
  end

  for i = i_start:nt
    xi = [DIC_prev; pco2a_prev];
    [x2,ierr_gm] = nsgmres(xi,...
        @(x)ns_step_eb(x,TR,M3d,V,Qgas,pco2a_prev,co2syspar,Jem(i),Jforcing,dt,DIC_prev),...
        precond, options_gm);

    DIC_curr = x2(1:m);
    pco2a_curr = x2(m+1);

    % ── Opt 1: Compute Jgas directly (no redundant ns_step_eb call) ──────
    [co2_conv,~,k0_conv] = eqco2(DIC_curr(1:ns), co2syspar);
    Deltaco2 = zeros(m,1);
    Deltaco2(1:ns) = k0_conv * pco2a_curr - co2_conv;
    Jgas_i = Qgas * Deltaco2;

    all_pco2a(s,i) = pco2a_curr;
    all_flux_GtC(s,i) = -V'*Jgas_i*1e-6*rhobar*12/1e15;

    % Shift for next step
    DIC_prev = DIC_curr;
    pco2a_prev = pco2a_curr;

    % Save baseline state at 2012 for dredging scenario initialization
    if s == 1 && i == i_forcing_start
      DIC_at_2012 = DIC_curr;
      pco2a_at_2012 = pco2a_curr;
      fprintf('  Saved baseline state at year %d for dredging scenarios\n', ...
              year(i_forcing_start));
    end

    if mod(i,50) == 0
      fprintf('  year %d/%d  pCO2atm=%.2f\n', ...
              year(min(i,length(year))), year(end), pco2a_curr);
    end
  end

  % Save final DIC snapshot for selected scenarios
  if s == 1
    DIC_final_baseline = DIC_curr;
  elseif s == 2
    DIC_final_1x = DIC_curr;
  end

  fprintf('  Done in %.1f s. Final pCO2atm=%.2f uatm\n', toc(tic_scen), pco2a_curr);
end

% Free forcing vectors and temporary state
clear Jdredge_1x Jdredge_10x Jdredge_100x scenario_forcing
clear DIC_prev DIC_curr Jgas_i x2 xi
clear DIC_at_2012 pco2a_at_2012 co2_conv k0_conv Deltaco2

% ── Results summary ───────────────────────────────────────────────────────────
fprintf('\n=== RESULTS SUMMARY ===\n');

for s = 2:n_scenarios
  dpco2 = all_pco2a(s,:) - all_pco2a(1,:);
  dflux = all_flux_GtC(s,:) - all_flux_GtC(1,:);
  [max_dpco2, max_idx] = max(abs(dpco2));
  fprintf('\n%s vs baseline:\n', scenario_names{s});
  fprintf('  Delta pCO2atm (2100): %.6f uatm\n', dpco2(end));
  fprintf('  Delta air-sea flux (2100): %.6f GtC/yr\n', dflux(end));
  fprintf('  Max |Delta pCO2atm|: %.6f uatm (year %d)\n', max_dpco2, year(min(max_idx,length(year))));
  fprintf('  Years 1780-2011 identical to baseline: %s\n', ...
          mat2str(all(dpco2(1:i_forcing_start)==0) && all(dflux(1:i_forcing_start)==0)));
end

% ── Save results ──────────────────────────────────────────────────────────────
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
out_file = sprintf('dredging_results_%s.mat', timestamp);
fprintf('\nSaving %s ...\n', out_file);

save(out_file, 'year', 't', 'scenario_names', ...
     'all_pco2a', 'all_flux_GtC', ...
     'DIC_final_baseline', 'DIC_final_1x', ...
     'iocn', 'isurf', 'i_forcing_start', '-v7');

finfo = dir(out_file);
fprintf('  Saved: %s (%.1f MB)\n', out_file, finfo.bytes/1e6);
fprintf('\nTotal runtime: %.1f min\n', toc(tic_total)/60);
fprintf('=== DONE ===\n');
