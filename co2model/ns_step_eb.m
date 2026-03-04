function [F,J,Jgas] = ns_step_eb(x,TR,M3d,V,Qgas,pco2a,co2syspar,Jem,Jtrawl,dt,dic)
  
  % metrics
  iocn = find(M3d(:)==1);
  isurf = find(M3d(:,:,1)==1);
  ns = length(isurf);
  m = length(iocn);
  Matm = 1.8e20; % number of moles of atmosphere
  rho = 1025; % density (kg/m3)
  
  % gas exchange
  [co2,R,k0,ph] = eqco2(x(1:ns),co2syspar);
  tmp = 0*M3d;
  tmp(isurf) = k0*x(m+1) - co2;
  Deltaco2 = tmp(iocn);
  Jgas = Qgas*Deltaco2; % umol/kg/yr
  
  % compute function
  M = speye(m)-dt*TR;
  Foce = M*x(1:m) - dt*Jgas - dt*Jtrawl - dic;
  Fatm = x(m+1) - dt*(Jem./Matm) + dt*(rho/Matm)*sum(Jgas.*V) - pco2a;
  F = [Foce;Fatm];
  
  % dummy variable for  Jacobian
  J = sparse(m,m);
  
  if nargout==2 % compute Jacobian
    
    % d[co2]/d[dic]
    dco2ddic = 0*M3d;
    dco2ddic(isurf) = R.*co2./x(1:ns);
    
    % d[Jgas]/d[pCatm]
    tmp = 0*M3d;
    tmp(isurf) = k0;
    dJgasdpCatm = Qgas*tmp(iocn);
    
    % d[Jgas]/d[dic]
    
    % Jacobian
    dFoceddic = M + dt*Qgas*d0(dco2ddic(iocn));
    dFocedpCatm = -dt*dJgasdpCatm;
    dFatmddic = -dt*(rho/Matm)*V.*(Qgas*dco2ddic(iocn));
    dFatmdpCatm = 1+dt*(rho/Matm)*sum(V.*dJgasdpCatm);
    
    % factor
    J = [dFoceddic dFocedpCatm;dFatmddic' dFatmdpCatm];
    %dFdx = mfactor(Jac);
    
  end
