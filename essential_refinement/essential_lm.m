function [R,t, exitflag] = essential_lm(R, t, x1, x2)

exitflag      = 0;
lambda_0      = 1e-2;               % initial damping parameter value
lambda        = lambda_0;			% Marquardt: init'l lambda
epsilon_1     = 1e-6;
epsilon_2     = 1e-6;	% convergence tolerance for parameters
epsilon_3     = 1e-5;	% convergence tolerance for Chi-square
epsilon_4     = 1e-2;	            % determines acceptance of a L-M step
max_iter      = 10;
iterations    = 0;
hZ            = quaternion.rotationmatrix(R).e;% initial quaternion
p             = [zeros(3,1); t];
y_dat         = zeros(size(x1,2),1);% data points we would like to fit (e.g. zero sampson error)
lambda_UP_fac = 11;
lambda_DN_fac =  9;	% factor for decreasing lambda
prnt          = 1;
stop          = 0;
Npnt          = size(x1,2);
Npar          = 6;
weight_sq     = ones(Npnt,1);

func = @(param) sampson_wrapper(param, hZ, x1, x2);
[alpha,beta,X2,~,~] = lm_matx(func,p,y_dat);
if (max(abs(beta)) < epsilon_1)
    fprintf('Initial guess is extremely close to optimal; epsilon_1 = %e\n', epsilon_1);
    stop = 1;
end
X2_old = X2;
% gradient descent iterations
while ~stop && iterations < max_iter
    iterations = iterations + 1;
    
    delta_p = ( alpha + lambda*diag(diag(alpha)) ) \ beta;	% Marquardt
    p_try = p + delta_p;                                    % update the [idx] elements
    delta_y = y_dat - feval(func,p_try);                    % residual error using a_try
    X2_try = delta_y' * ( delta_y .* weight_sq );           % Chi-squared error criteria
    rho = (X2 - X2_try) / ( 2*delta_p' * (lambda * delta_p + beta) ); % Nielsen
    if (rho > epsilon_4)		% it IS significantly better
        X2_old = X2;
        
        hZ = param2quaternion(p(1:3), hZ);
        p = p_try(:);			% accept p_try
        p(1:3) = zeros(3,1);
        
        func = @(param) sampson_wrapper(param, hZ, x1, x2);
        [alpha,beta,X2,~,~] = lm_matx(func,p,y_dat);
        % decrease lambda ==> Gauss-Newton method
        lambda = max(lambda/lambda_DN_fac,1.e-7);		% Levenberg
    else					% it IS NOT better
        X2 = X2_old;			% do not accept a_try
        % increase lambda  ==> gradient descent method
        lambda = min(lambda*lambda_UP_fac,1.e7);		% Levenberg
    end
    
    if ( prnt > 1 )
        fprintf('>%3d | chi_sq=%10.3e | lambda=%8.1e \n', iterations,X2,lambda );
        fprintf('    param:  ');
        for pn=1:Npar
            fprintf(' %10.3e', p(pn) );
        end
        fprintf('\n');
        fprintf('    dp/p :  ');
        for pn=1:Npar
            fprintf(' %10.3e', delta_p(pn) / p(pn) );
        end
        fprintf('\n');
    end
    
    if max(abs(delta_p./p)) < epsilon_2  &&  iterations > 2
        %fprintf(' **** Convergence in Parameters **** \n')
        %fprintf(' **** epsilon_2 = %e\n', epsilon_2);
        exitflag = 1;
        stop = 1;
    end
    if X2/Npnt < epsilon_3  &&  iterations > 2
        %fprintf(' **** Convergence in Chi-square  **** \n')
        %fprintf(' **** epsilon_3 = %e\n', epsilon_3);
        exitflag = 1;
        stop = 1;
    end
    if max(abs(beta)) < epsilon_1  &&  iterations > 2
        %fprintf(' **** Convergence in r.h.s. ("beta")  **** \n')
        %fprintf(' **** epsilon_1 = %e\n', epsilon_1);
        exitflag = 1;
        stop = 1;
    end
    if iterations == max_iter
        %disp(' !! Maximum Number of Iterations Reached Without Convergence !!')
        exitflag = 0;
        stop = 1;
    end
    
end					% --- End of Main Loop

R = quaternion(hZ).RotationMatrix;
t = p(4:6);

end

function val = sampson_wrapper(p, h0, x1, x2)

% extract rotation and translation parameters
v = p(1:3);
t = p(4:6);

hZ = param2quaternion(v, h0);

% compute sampson error value
val = sampson(hZ, t, x1, x2);
end

function dydp = lm_dydp(func,p,y)
% dydp = lm_dydp(func,t,p,y,{dp},{c})
%
% Numerical partial derivatives (Jacobian) dy/dp for use with lm.m
% Requires n or 2n function evaluations, n = number of nonzero values of dp
% -------- INPUT VARIABLES ---------
% func = function of independent variables, 't', and parameters, 'p',
%        returning the simulated model: y_hat = func(t,p,c)
% t  = m-vector of independent variables (used as arg to func)
% p  = n-vector of current parameter values
% y  = func(t,p,c) n-vector initialised by user before each call to lm_dydp
% dp = fractional increment of p for numerical derivatives
%      dp(j)>0 central differences calculated
%      dp(j)<0 one sided differences calculated
%      dp(j)=0 sets corresponding partials to zero; i.e. holds p(j) fixed
%      Default:  0.001;
% c  = optional vector of constants passed to y_hat = func(t,p,c)
%---------- OUTPUT VARIABLES -------
% dydp = Jacobian Matrix dydp(i,j)=dy(i)/dp(j)	i=1:n; j=1:m

%   Henri Gavin, Dept. Civil & Environ. Engineering, Duke Univ. November 2005
%   modified from: ftp://fly.cnuce.cnr.it/pub/software/octave/leasqr/
%   Press, et al., Numerical Recipes, Cambridge Univ. Press, 1992, Chapter 15.


m=length(y);			% number of data points
n=length(p);			% number of parameters

if nargin < 5
    dp = 0.001*ones(1,n);
end

ps=p; dydp=zeros(m,n); del=zeros(n,1);         % initialize Jacobian to Zero

for j=1:n                       % loop over all parameters
    
    del(j) = dp(j) * (1+abs(p(j)));  % parameter perturbation
    p(j)   = ps(j) + del(j);	      % perturb parameter p(j)
    
    if del(j) ~= 0
        y1=feval(func,p);
        
        if (dp(j) < 0)		% backwards difference
            dydp(:,j) = (y1-y)./del(j);
        else			% central difference, additional func call
            p(j) = ps(j) - del(j);
            dydp(:,j) = (y1-feval(func,p)) ./ (2 .* del(j));
        end
    end
    
    p(j)=ps(j);		% restore p(j)
    
end
end

% endfunction # ------------------------------------------------------ LM_DYDP

function [alpha,beta,Chi_sq,y_hat,dydp] = lm_matx(func,p,y_dat)
% [alpha,beta,Chi_sq,y_hat,dydp] = lm_matx(func,t,p,y_dat,weight_sq,{da},{c})
%
% Evaluate the linearized fitting matrix, alpha, and vector beta,
% and calculate the Chi-squared error function, Chi_sq
% Used by Levenberg-Marquard algorithm, lm.m
% -------- INPUT VARIABLES ---------
% func  = function ofpn independent variables, p, and m parameters, p,
%         returning the simulated model: y_hat = func(t,p,c)
% t     = m-vectors or matrix of independent variables (used as arg to func)
% p     = n-vector of current parameter values
% y_dat = n-vector of data to be fit by func(t,p,c)
% weight_sq = square of the weighting vector for least squares fit ...
%	    inverse of the standard measurement errors
% dp = fractional increment of 'p' for numerical derivatives
%      dp(j)>0 central differences calculated
%      dp(j)<0 one sided differences calculated
%      dp(j)=0 sets corresponding partials to zero; i.e. holds p(j) fixed
%      Default:  0.001;
% c  = optional vector of constants passed to y_hat = func(t,p,c)
%---------- OUTPUT VARIABLES -------
% alpha	= linearized Hessian matrix (inverse of covariance matrix)
% beta  = linearized fitting vector
% Chi_sq = 2*Chi squared criteria: weighted sum of the squared residuals WSSR
% y_hat = model evaluated with parameters 'p'

%   Henri Gavin, Dept. Civil & Environ. Engineering, Duke Univ. November 2005
%   modified from: ftp://fly.cnuce.cnr.it/pub/software/octave/leasqr/
%   Press, et al., Numerical Recipes, Cambridge Univ. Press, 1992, Chapter 15.

Npnt = length(y_dat);	% number of data points
Npar = length(p);		% number of parameters

weight_sq = ones(Npnt,1);

y_hat = feval(func,p);	    % evaluate model using parameters 'p'
delta_y = y_dat - y_hat;	% residual error between model and data
dydp = lm_dydp(func,p,y_hat);
alpha = dydp' * ( dydp .* ( weight_sq * ones(1,Npar) ) );
beta  = dydp' * ( weight_sq .* delta_y );

Chi_sq = delta_y' * ( delta_y .* weight_sq ); 	% Chi-squared error criteria

% endfunction  # ------------------------------------------------------ LM_MATX

end
