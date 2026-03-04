function [F,FD,Jgas] = eqdic(dic,grid,M3d,TR,Kw,pco2atm,co2syspar)
  
  % ocean grid points
  iocn = find(M3d(:)==1);
  isurf = find(M3d(:,:,1)==1);
  m = length(iocn);
  ns = length(isurf);
  
  % gas exchange operator [yr^-1]
  Q = 0*M3d;
  Q(isurf) = Kw./grid.dzt(1);
  QQ = d0(Q(iocn));
  Qgas = QQ(:,1:ns);
  
  % equilibrium surface co2 concentration
  [co2,R,k0] = eqco2(dic(1:ns),co2syspar);
  %k0 = k0*1024.5; % mol/m^3/atm
  
  % F = d[DIC]/dt = TR*dic - JV*dic + Qgas*(Ko*pco2atm - co2)
  %F = (TR+JV)*dic + Qgas*(k0*pco2atm - co2);
  F = TR*dic + Qgas*(k0*pco2atm - co2);
  
  % air-sea gas flux
  Jgas = Qgas*(k0*pco2atm - co2);
  
  % dummy Jacobian
  FD = sparse(m,m);
  
  if nargout==2 % compute Jacobian
    
    % d[co2]/d[dic]
    dco2ddic = 0*M3d;
    dco2ddic(isurf) = R.*co2./dic(1:ns);
    
    % Jacobian
    %Jac = (TR+JV) - QQ*d0(dco2ddic(iocn));
    Jac = (TR) - QQ*d0(dco2ddic(iocn));
    
    % factor Jacobian
    FD = mfactor(Jac);
    
  end
  