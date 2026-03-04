% load model
load OCIM2_48L_CTL.mat output sol
grid = output.grid;
M3d = output.M3d;
Area3 = grid.DXT3d.*grid.DYT3d;
VOL = Area3.*grid.DZT3d;

% utility variables
spyr = 365.25*24*3600;
TR = output.TR; % all should be in yr^-1

% ocean points, surface and interior points
iocn = find(M3d(:)==1);
isurf = find(M3d(:,:,1)==1);
ideep = setdiff(iocn,isurf);
ns = length(isurf);
m = size(TR,1);

% piston velocity [m/s]
u10 = mean(output.data.u10cfc11,2);
fice = mean(output.data.ficecfc11,2);

% Schmidt number for CO2
temp = output.data.dens.tstar(1:ns);
salt = output.data.dens.sstar(1:ns);
Sc_co2 = schmidt(temp,'co2');

% gas exchange parameter
a = sol(length(sol));

% CO2 piston velocity (m/yr)
Kw = a*(1-fice).*(u10.^2).*(Sc_co2./660).^-.5;
clear output

% nutrient data
load woa09si.mat si_an LON LAT DEPTH
load woa09po4.mat po4_an
Si = interp3(LON,LAT,DEPTH,si_an,grid.XT3d,grid.YT3d,grid.ZT3d);
Po4 = interp3(LON,LAT,DEPTH,po4_an,grid.XT3d,grid.YT3d,grid.ZT3d);
for k = 1:size(M3d,3)
  si(:,:,k) = inpaint_nans(Si(:,:,k));
  po4(:,:,k) = inpaint_nans(Po4(:,:,k));
end

% co2 system parameters
co2syspar.pres = sw_pres(grid.ZT3d(isurf),grid.YT3d(isurf)); % dbar
co2syspar.si = si(isurf); % umol/kg
co2syspar.po4 = po4(isurf); % umol/kg
co2syspar.temp = temp; % deg. c
co2syspar.salt = salt; % psu

% virtual salt flux
rhobar = 1025;
sbar = VOL(isurf)'*salt(1:ns)./sum(VOL(isurf));

% specify equilibrium alkalinity
alk = 2310*salt./sbar;

% add alkalinity to co2syspar
co2syspar.alk = alk(1:ns);

% atmospheric pCO2 [uatm]
pco2atm = 280;

% use Newton's method to solve for equilibrium dic
fprintf('Solving for equilibrium dic distribution...')
tic
dic0 = zeros(m,1)+2100; % initial guess
options.atol = 5e-6; options.rtol = 1e-16; options.iprint = 1;
[dic,ierr] = nsnew(dic0,@(x)eqdic(x,grid,M3d,TR,Kw,pco2atm,co2syspar),options);
toc
[jnk,jnk2,Jco2pre] = eqdic(dic,grid,M3d,TR,Kw,pco2atm,co2syspar);
% co2 system
[co2swpre,Rpre,k0pre,pHpre] = eqco2(dic(1:ns),co2syspar);

% transient simulation with carbon emissions
f = load('netemission.txt');
year_em = f(:,1);
em_gcb = f(:,2); % umol C/yr
dt = 1;
year = [1780:2100];
Jem = zeros(length(year)+1,1);
Jem(2:length(em_gcb)+1) = em_gcb;
Jem(length(em_gcb)+2:length(year)+1) = em_gcb(length(em_gcb));
t = [0:dt:length(year)];
nt = length(t);
Jtrawl = zeros(m,nt); % 0 (no trawling simulation)

% gas exchange operator [yr^-1]
Q = 0*M3d;
Q(isurf) = Kw./grid.dzt(1);
Qgas = d0(Q(iocn));

% volume
V = grid.DXT3d(iocn).*grid.DYT3d(iocn).*grid.DZT3d(iocn);

% initial condition
DIC = zeros(m,length(t));
pco2a = zeros(1,length(t));
pH = zeros(m,length(t));
Revelle = zeros(ns,length(t));
co2_sw = zeros(ns,length(t));
co3_sw = zeros(m,length(t));
Jco2 = zeros(ns,length(t));
DIC(:,1) = dic;
pco2a(1) = pco2atm;
Jco2(:,1) = Jco2pre(1:ns);
pH(:,1) = pHpre;
co2_sw(:,1) = co2swpre;
Revelle(:,1) = Rpre;

% preconditioner for time-stepping
xi = [DIC(:,1);pco2a(1)];
[F,Jac] = ns_step_eb(xi,TR,M3d,V,Qgas,pco2a(1),co2syspar,Jem(1),Jtrawl(:,1),dt,DIC(:,1));
fprintf('Factoring preconditioner...')
tic,FM = mfactor(Jac);toc
precond = @(x)mfactor(FM,x);

% plot
figure(1)
plot(t(1),V'*Jgas(:,1)*1e-6*1025*12/1e15,'ok')
ylabel('Air-sea CO2 flux')
hold on

figure(2)
plot(t(1),pco2a(1),'ok')
ylabel('Atmospheric pCO2')
hold on

% time-step
fprintf('Transient simulation...')
c = 0;
for i = 2:nt
  c = c+1;
  
  % solve Euler backward implicit time-step
  options.atol = 2e-6; options.rtol = 1e-16; options.iprint = 1;
  xi = [DIC(:,i-1);pco2a(i-1)];
  [x2,ierr] = nsgmres(xi,@(x)ns_step_eb(x,TR,M3d,V,Qgas,...
      pco2a(i-1),co2syspar,Jem(i),Jtrawl(:,i),dt,DIC(:,i-1)),precond,options);
  DIC(:,i) = x2(1:m);
  pco2a(i) = x2(m+1);
  [F,Jac,Jgas(:,i)] = ns_step_eb(x2,TR,M3d,V,Qgas,...
      pco2a(i-1),co2syspar,Jem(i),Jtrawl(:,i),dt,DIC(:,i-1));
  
  % co2 system
  [co2,R,k0,ph] = eqco2(DIC(1:ns,i),co2syspar);
  Revelle(:,i) = R;
  pH(:,i) = ph;
  co2_sw(:,i) = co2;
  
  % plot
  figure(1)
  plot(t(i),-V'*Jgas(:,i)*1e-6*1025*12/1e15,'ok')
  drawnow
  
  figure(2)
  plot(t(i),pco2a(i),'ok')
  drawnow
  
  % save co2 fluxes
  Jco2(:,i) = Jgas(1:ns,i);
  
end

% plot labels
figure(1)
xlabel('Time (years)')
ylabel('GtC/yr')
legend('Air-sea CO2 flux','Trawling CO2 emissions')

% save also the 3-d trawling emissions and the integrated flux over time!!!

% save
save emissions_model_notrawling_1780_2100 t Jco2 Jtrawl Jem co2_sw Revelle pH DIC pco2a grid M3d
