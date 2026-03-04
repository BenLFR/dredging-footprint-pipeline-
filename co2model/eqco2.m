function [co2,R,k0,pH,OmegaAr] = eqco2(dic,arg1)
  
  % unpack parameters for co2 system chemistry
  alk = arg1.alk;
  salt = arg1.salt;
  temp = arg1.temp;
  pres = arg1.pres;
  si = arg1.si;
  po4 = arg1.po4;
  
  % co2 system
  a = CO2SYS(alk,dic,1,2,salt,temp,temp,pres,pres,si,po4,1,4,1);
  
  % concentration of co2 in umol/kg
  co2 = a(:,8);
  
  % Revelle factor
  R = a(:,14);
  
  % co2 solubility k0 
  pco2 = a(:,4); % uatm
  k0 = co2./pco2; % mol/kg/atm
  
  % pH (pH units)
  pH = a(:,3);
  
  % aragonite saturation state
  OmegaAr = a(:,16);
