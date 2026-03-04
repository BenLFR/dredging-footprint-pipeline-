function Sc = schmidt(T,G)

% Function to compute Schmidt number of a gas (G) at
% temperature T (deg C), using the data of Table A1 of 
% Wanninkhof, 1992: JGR 97,C5,p7373-7382. The data
% are stored as a matrix in the file schmidt_coeff.mat
% in a format conducive to use of the function polyval.
% The columns are: D', C, B', A, where D' = D (of original data)
% and B' = B (of original data).
% To compute schmidt number at temperature T:		
% 		Sc = D'T^3 + CT^2 + B'T + A
% The rows represent individual gases as follows:
% 	1	He
% 	2	Ne
% 	3	Ar
% 	4	O2
% 	5	CH4
% 	6	CO2
% 	7	N2
% 	8	Kr
% 	9	N2O
% 	10	Rn
% 	11	SF6
% 	12	F12
% 	13	F11
%
% USAGE: sc = schmidt(T,G), where T is temperature in deg C and G is 
% a STRING specifying the gas. T may be a vector. Valid gases are:
% 	1	He
% 	2	Ne
% 	3	Ar
% 	4	O2
% 	5	CH4
% 	6	CO2
% 	7	N2
% 	8	Kr
% 	9	N2O
% 	10	Rn
% 	11	SF6
% 	12	F12
% 	13	F11
% If G is omitted, it is assumed to be 'He'.

% Samar Khatiwala (spk@ldeo.columbia.edu)

% SPK 10/10/05: modified to accept string (instead of integer) 
%               to specify gas

if nargin<2
  G='He';
end

switch lower(G)
  case 'he'
    G=1;
  case 'ne'
    G=2;
  case 'ar'
    G=3;
  case 'o2'
    G=4;
  case 'ch4'
    G=5;
  case 'co2'
    G=6;
  case 'n2'
    G=7;
  case 'kr'
    G=8;
  case 'n2o'
    G=9;
  case 'rn'
    G=10;
  case 'sf6'
    G=11;
  case 'f12'
    G=12;
  case 'f11'
    G=13;
  otherwise
    error(['Unknown gas ' G])
end

if nargin<2, % default He
	Sc = 410.14 - 20.503*T + 0.53175*(T.^2) - 0.0060111*(T.^3);
else
	load schmidt_coeff.mat
	p = schmidt_coeff(G,:);
	Sc = polyval(p,T);
end
