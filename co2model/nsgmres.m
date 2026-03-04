function [sol, ierr, dfdx, it_hist, x_hist] = nsgmres(x,f,fpre,options)
% NSGMRES  Newton-Krylov-Armijo nonlinear solver
%
% Compute Newton dir with gmres using optional preconditioner
%
% T. DeVries July 2012
%
% Based on nsold by C. T. Kelley, April 1, 2003.
%
% function [sol, ierr, dfdx, it_hist, x_hist] = nsgmres(x,f,fpre,options)
%
% inputs:
%        initial iterate = x
%        function = f (2nd output argument is Jacobian)
%        preconditioner = fpre (returns m = A\x where A is preconditioner
%        for Jacobian)
%        options = structure with optimization options (see below)
%
% output:
%    sol = solution
%    it_hist = array of iteration history, useful for tables and plots
%              The two columns are the residual norm and number of step size
%              reductions done in the line search.
%
%        ierr = 0 upon successful termination
%        ierr = 1 if after maxit iterations the termination criterion is not
%               satisfied
%        ierr = 2 failure in the line search. The iteration is terminated if
%               too many steplength reductions are taken.
%
%    x_hist = matrix of the entire interation history.
%             The columns are the nonlinear iterates. This is useful for
%             making movies, for example, but can consume way too much
%             storage. This is an OPTIONAL argument. Storage is only
%             allocated if x_hist is in the output argument list.

% set the iteration parameters.
iprint = 0;
iplot = 0;
maxarm = 10;
maxit = 100;
maxgm = 20;
tolgm = 1e-2;
atol = 1e-8;
rtol = 1e-8;
if( ~isempty(options) )
    if( isfield(options,'iprint') ); iprint = options.iprint; end
    if( isfield(options,'iplot') );  iplot  = options.iplot; end
    if( isfield(options,'maxarm') ); maxarm = options.maxarm; end
    if( isfield(options,'maxit') );  maxit  = options.maxit; end
    if( isfield(options,'atol') );   atol   = options.atol; end
    if( isfield(options,'rtol') );   rtol   = options.rtol; end
    if( isfield(options,'maxgm') );  maxgm  = options.maxgm; end
    if( isfield(options,'tolgm') );  tolgm  = options.tolgm; end
end

% initialize flags and counters
ierr = 0;
itc = 0;
if nargout == 5
    x_hist = x;
end

% evaluate f at the initial iterate and compute the stop tolerance
[f0,dfdx] = feval(f,x);
fnrm = norm(f0);
stop_tol = atol+rtol*fnrm;
x0 = 0*x;

% check display options
if iprint == 1
  fprintf('Newton-Krylov-Armijo solver with GMRES \n')
  fprintf('Iteration \t ||F(x_k)|| \t Steps \t GM res. \t GM iter.\n')
  fprintf('%4d \t\t %12.4e \t %4d \t %4d \t\t %4d \n',[itc,fnrm,0,0,0])
end

%
% MAIN ITERATION LOOP
%
while(fnrm > stop_tol & itc < maxit)
  
  % iteration counter
  itc = itc+1;
  
  % evaluate function and Jacobian
  [fv,dfdx] = feval(f,x);
  
  % compute the Newton direction
  [dir,gmflag,relres,igmres] = gmres(dfdx,-f0,maxgm,tolgm,1,fpre,[],x0);
  %x0 = dir;
  
  % previous solution
  xold = x; fold = f0;
  
  % line search along Newton direction
  [step,iarm,x,f0,armflag] = armijo(dir,x,f0,f,maxarm);
  
  % if the line search fails you're dead.
  if armflag == 1  
    if iprint==1
      disp('Complete Armijo failure.');
    end
    sol = xold;
    ierr = 2;
    return
  end
  fnrm = norm(f0);
  
  % save and display iteraton history
  if nargout == 5, x_hist = [x_hist,x]; end
  it_hist(itc,:) = [itc fnrm iarm];
  if iprint == 1
    fprintf('%4d \t\t %12.4e \t %4d \t %12.4e \t %4d \n',...
	[itc,fnrm,iarm,relres,igmres(2)])
  end
  
end
sol = x;

% on failure, set the error flag
if fnrm > stop_tol
  ierr = 1;
end

function [step,iarm,xp,fp,armflag] = armijo(dir,x,f0,f,maxarm)
iarm = 0;
sigma1 = .5;
alpha = 1.d-4;
armflag = 0;
xp = x;
fp = f0; 
%
xold = x;
lambda = 1; lamm = 1; lamc = lambda; iarm = 0;
step = lambda*dir;
xt = x + step;
ft = feval(f,xt);
nft = norm(ft);
nf0 = norm(f0);
ff0 = nf0*nf0;
ffc = nft*nft;
ffm = nft*nft;
while nft >= (1 - alpha*lambda) * nf0
    
    %   Apply the three point parabolic model.
    if iarm == 0
        lambda = sigma1*lambda;
    else
        lambda = parab3p(lamc, lamm, ff0, ffc, ffm);
    end
    
    % Update x; keep the books on lambda.
    step = lambda*dir;
    xt = x + step;
    lamm = lamc;
    lamc = lambda;
    
    % Keep the books on the function norms.
    ft = feval(f,xt);
    nft = norm(ft);
    ffm = ffc;
    ffc = nft*nft;
    iarm = iarm+1;
    if iarm > maxarm
        disp(' Armijo failure, too many reductions ');
        armflag = 1;
        sol = xold;
        return;
    end
end

xp = xt;
fp = ft;


function lambdap = parab3p(lambdac, lambdam, ff0, ffc, ffm)
% Apply three-point safeguarded parabolic model for a line search.
%
% C. T. Kelley, April 1, 2003
%
% This code comes with no guarantee or warranty of any kind.
%
% function lambdap = parab3p(lambdac, lambdam, ff0, ffc, ffm)
%
% input:
%       lambdac = current steplength
%       lambdam = previous steplength
%       ff0 = value of \| F(x_c) \|^2
%       ffc = value of \| F(x_c + \lambdac d) \|^2
%       ffm = value of \| F(x_c + \lambdam d) \|^2
%
% output:
%       lambdap = new value of lambda given parabolic model
%
% internal parameters:
%       sigma0 = .1, sigma1 = .5, safeguarding bounds for the linesearch
%

% Set internal parameters.
sigma0 = .1; sigma1 = .5;

% Compute coefficients of interpolation polynomial.
%
% p(lambda) = ff0 + (c1 lambda + c2 lambda^2)/d1
%
% d1 = (lambdac - lambdam)*lambdac*lambdam < 0
%      so, if c2 > 0 we have negative curvature and default to
%      lambdap = sigam1 * lambda.
c2 = lambdam*(ffc-ff0)-lambdac*(ffm-ff0);
if c2 >= 0
    lambdap = sigma1*lambdac; return
end
c1 = lambdac*lambdac*(ffm-ff0)-lambdam*lambdam*(ffc-ff0);
lambdap = -c1*.5/c2;
if lambdap < sigma0*lambdac
  lambdap = sigma0*lambdac;
end
if lambdap > sigma1*lambdac
  lambdap = sigma1*lambdac;
end

