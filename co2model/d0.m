function D = d0(x)
% D0  Create sparse diagonal matrix from vector x.
%   D = d0(x) returns spdiags(x(:), 0, n, n) where n = length(x).
  n = length(x);
  D = spdiags(x(:), 0, n, n);
end
