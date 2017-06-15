% evolve  Time domain evolution of density matrix
%
%   td = evolve(Sigma,Det,Ham,n,dt);
%   td = evolve(Sigma,Det,Ham,n,dt,IncScheme);
%   td = evolve(Sigma,Det,Ham,n,dt,IncScheme,Mix);
%
%   Evolves the density matrix Sigma under the Hamiltonian Ham with time
%   step dt n-1 times and detects using Det after each step. Hermitian
%   input matrices are assumed. td(1) is the value obtained by detecting
%   Sigma without evolution.
%
%   IncScheme determines the incrementation scheme and can be one of the
%   following (up to four sweep periods, up to two dimensions)
%
%     [1]           simple FID, 3p-ESEEM, echo transient, DEFENCE
%     [1 1]         2p-ESEEM, CP, 3p and 4p RIDME
%     [1 -1]        3p-DEER, 4p-DEER, PEANUT, 5p RIDME
%     [1 1 -1 -1]   SIFTER
%     [1 -1 -1 1]   7p-DEER
%     [1 -1 1 -1]
%
%     [1 2]         3p-ESEEM echo transient, HYSCORE, DONUT-HYSCORE
%     [1 2 1]       2D 3p-ESEEM
%     [1 1 2]       2p-ESEEM etc. with echo transient
%     [1 -1 2]      3p-DEER, 4p-DEER etc. with echo transient
%     [1 2 2 1]     2D CP
%     [1 2 -2 1]    2D PEANUT
%     [1 1 -1 -1 2] SIFTER with echo transient
%     [1 -1 -1 1 2] 7p-DEER with echo transient
%
%   [1] is the default. For an explanation of the format, see the
%   documentation.
%
%   Mix is a cell array containing the propagators of the mixing
%   block(s), for experiments with more than 1 sweep period.
%
%   td is a vector/matrix of the signal with t1 along dimension 1
%   and t2 along dimension 2.



function [t, Signal, Sigma, DensityMatrices, Events] = evolve(Sigma,Ham0,Det,Events,Relaxation)

if (nargin==0), help(mfilename); return; end

% if (nargout<1), error('Not enough output arguments.'); end
if (nargout>5), error('Too many output arguments.'); end
if (nargin<4) || (nargin>5), error('Wrong number of input arguments!'); end

%move this this into Events?
% if (nargin<6), IncScheme = 1; end
% if (nargin<7), Mix = {}; end
%
% if any(mod(n,1)~=0) || any(n<=0)
%     error('n, the number of points (4th argument), must be a positive integer.');
% end

method = 'stepwise';

nEvents = length(Events);

Liouville = 1;

% questions:
% - how should I make the time axis, the first point should be t =
% 0 with the initial state matrix, right?
% - we have to look into the normalization for the Detection operators. +
% or - Detection operators need to divided by two before normalizations are
% computed. what should the normalization be for transition selective
% operators or for detecting populations

switch method
  
  case 'stepwise'
    
    nDet = numel(Det);
    normsDet = zeros(1,nDet);
    
    ttotal = 0;
    firstDetection = 1;
    startTrace = 2;
    
    Ham0 = Ham0*2*pi;
    
    for iEvent = 1 : nEvents
      
      currentEvent = Events{iEvent};
      
      if length(currentEvent.t) == 1
        dt = currentEvent.t;
        tvector = [0 currentEvent.t];
      else
        dt = currentEvent.t(2) - currentEvent.t(1);
        tvector = currentEvent.t;
      end

      if currentEvent.Detection == 1
        currentSignal = zeros(nDet,length(currentEvent.t));
        n = size(Sigma,1);
        
        for iDet = 1:length(Det)
          
          Det{iDet} = reshape(Det{iDet}.',1,n^2);
          normsDet(iDet) = Det{iDet}*Det{iDet}';
          %           normsDet(kk) = 1;
          Density = Sigma(:);
          %           normsDet(kk) = sum(sum(Det{kk}.*Det{kk}));
          %           currentSignal(kk,1) = sum(sum(Det{kk}.*Sigma.'))/normsDet(kk);
          currentSignal(iDet,1) = Det{iDet}*Density/normsDet(iDet);
        end
        
      else
        currentSignal=[];
      end
            
      if currentEvent.storeDensityMatrix == 1
        DensityMatrices=cell(1,length(currentEvent.t));
        DensityMatrices{1}=Sigma;
      else
        DensityMatrices = [];
      end
      
      if Liouville == 1
        n = size(Sigma,1);
        SigmaVector = reshape(Sigma,n*n,1);
        Gamma = Relaxation.Gamma;
        equilibriumState = reshape(Relaxation.equilibriumState,n*n,1);
      end
      
      switch currentEvent.type
        case 'pulse'
          
          %----------------------------------------------------------------
          % convert the IQ wave form into a binary form, so that it
          % is possible to use a propagator look up table
          %----------------------------------------------------------------

          rMax = max(abs(real(currentEvent.IQ(:)))); % max(abs(real....(:)))
          iMax = max(abs(imag(currentEvent.IQ(:))));
          
          if rMax > iMax
            MaxWave = rMax;
          else
            MaxWave = iMax;
          end
          
          vertRes = 1024;
          
          scale = 2*2*2*pi*MaxWave/vertRes; 
          % one factor 2 is required because of linearly polarized irradiation
          % the other because of the digitization of the wave
          
          tvector(1) = 0;
          tvector(2:length(currentEvent.t)+1) = currentEvent.t+dt;
          
          realArbitrary = real(currentEvent.IQ)/MaxWave;
          realBinary = floor(vertRes*(realArbitrary+1)/2);
          realBinary(realBinary == vertRes) = vertRes-1;
          
          if currentEvent.ComplexExcitation == 1
            imagArbitrary = imag(currentEvent.IQ)/MaxWave;
            imagBinary = floor(vertRes*(imagArbitrary+1)/2);
            imagBinary(imagBinary==vertRes) = vertRes-1;
          end
          
          % to check if wave form is reconstructed correctly --------
          %                                 figure(1)
          %                                 clf
          %                                 plot(currentEvent.t,realBinary)
          % %
          %                                 figure(2)
          %                                 clf
          %                                 hold on
          %                                 plot(currentEvent.t,real(currentEvent.IQ))
          % %                                 plot(currentEvent.t,(realBinary-res/2)*scale)
          %                                 title('Real')
          %
          %                                 figure(3)
          %                                 clf
          %                                 hold on
          % %                                 plot(currentEvent.t,imag(currentEvent.IQ))
          % %                                 plot(currentEvent.t,(imagBinary-res/2)*scale)
          %                                 title('Imaginary')
          
          %----------------------------------------------------------------
          
          
          
          % setup of an initial state, a loop state and weighting factor
          % for phase cycling, if requested
          
          nPhaseCycle = size(currentEvent.PhaseCycle,1);
          
          if nPhaseCycle>1
            initialState = Sigma;
            loopState = zeros(size(Sigma));
            PCnorm = sum(abs(currentEvent.PhaseCycle(:,2)));
          end
          
          %----------------------------------------------------------------
          % Propagation Starts Here
          %----------------------------------------------------------------
          
          if Liouville == 0
            
            % Calculation or Loading, if possible, of Propagators
            if currentEvent.ComplexExcitation == 0
              if ~isempty(currentEvent.propagators) && isfield(currentEvent.propagators,'UTable')
                UTable = currentEvent.propagators.UTable;
              else
                UTable = cell(1,vertRes);
                
                for iRes = 0:vertRes-1
                  Ham1 = scale*(iRes-vertRes/2)*currentEvent.xOp;
                  Ham = Ham0+Ham1;
                  U = expm_fastc(-1i*Ham*dt);
                  UTable{iRes+1} = U;
                end
                
                Events{iEvent}.propagators.UTable = UTable;
              end
              
            end
            
            % Loops over the Phasecycles
            for iPhaseCycle = 1 : nPhaseCycle
              
              % Propagation for one waveform
              for iWavePoint = 1 : length(realBinary)
                if currentEvent.ComplexExcitation == 0
                  % Load propagators if Complex Excitation is off
                  U = UTable{realBinary(iPhaseCycle,iWavePoint)+1};
                else % For active Complex Excitation Propagators need to be recalculated
                  Ham1 = scale*(realBinary(iPhaseCycle,iWavePoint)-vertRes/2)*real(currentEvent.xOp)+scale*(imagBinary(iPhaseCycle,iWavePoint)-vertRes/2)*imag(currentEvent.xOp);
                  Ham =  Ham0+Ham1;
                  U = expm_fastc(-1i*Ham*dt);
                end
                
                Sigma = U*Sigma*U';
                
                % Computes Expectation Values if requested
                if currentEvent.Detection == 1
                  for iDet = 1:nDet
                    Density =  Sigma(:);
                    currentSignal(iDet,iWavePoint+1) = Det{iDet}*Density/normsDet(iDet);
                    %                   currentSignal(j,k+1) = sum(sum(Det{j}.*Sigma.'))/normsDet(j);
                  end
                end
                
                % Store Density Matrices if requested
                if currentEvent.storeDensityMatrix == 1
                  DensityMatrices{iWavePoint+1} = Sigma;
                end
                
              end
              
              % Combine Results from current phase cycle with previous ones
              if nPhaseCycle > 1
                PCweight = currentEvent.PhaseCycle(iPhaseCycle,2)/PCnorm;
                loopState = loopState+PCweight*Sigma;
                if currentEvent.Detection == 1
                  if iPhaseCycle ~= 1
                    PCSigma = PCSigma+PCweight*currentSignal;
                  else
                    PCSigma = PCweight*currentSignal;
                  end
                end
                if iPhaseCycle ~= nPhaseCycle
                  Sigma = initialState;
                end
              end
              
            end
            
          else % Propagation in Liouville space
            
            
            % Calculation or Loading, if possible, of Liouvillians and 
            % steady state density operator solutions
            if ~isempty(currentEvent.propagators) && isfield(currentEvent.propagators,'LTable')
              LTable = currentEvent.propagators.LTable;
              SigmassTable = currentEvent.propagators.SigmassTable;
            else
              SigmassTable = cell(1,vertRes);
              LTable = cell(1,vertRes);
              
              for ivertRes = 0:vertRes-1
                Ham1 = scale*(ivertRes-vertRes/2)*currentEvent.xOp;
                Ham = Ham0 + Ham1;
                HamSuOp = kron(eye(n,n),Ham)-kron(Ham.',eye(n,n));
                L = -1i*HamSuOp-Gamma;
                SigmaSS = Gamma*equilibriumState; % steady state solutions for the denisty matrices
                SigmaSS = -L\SigmaSS;
                SigmassTable{ivertRes+1} = SigmaSS;
                L = expm_fastc(L*dt); %calculations of the Liouvillians
                LTable{ivertRes+1} = L;
              end
              
              Events{iEvent}.propagators.LTable = LTable;
              Events{iEvent}.propagators.SigmassTable = SigmassTable;
              
            end
            
            % Loops over the Phasecycles
            for iPhaseCycle = 1 : nPhaseCycle
              
              % Propagation for one waveform
              for iWavePoint = 1:length(realBinary)
                if currentEvent.ComplexExcitation == 0
                  % Load Liouvillians if Complex Excitation is off
                  L=LTable{realBinary(iPhaseCycle,iWavePoint)+1};
                  SigmaSS=SigmassTable{realBinary(iPhaseCycle,iWavePoint)+1};
                else
                  % if complex excitation is requested, usage of tables
                  % is not feasible, and Liouvillians and state state
                  % density matrices are computed for each time step
                  Ham1 = scale*(realBinary(iPhaseCycle,iWavePoint)-vertRes/2)*real(currentEvent.xOp)+scale*(imagBinary(iPhaseCycle,iWavePoint)-vertRes/2)*imag(currentEvent.xOp);
                  Ham = Ham0+Ham1;
                  HamSuOp = kron(eye(n,n),Ham)-kron(Ham.',eye(n,n));
                  L = -1i*HamSuOp-Gamma;
                  SigmaSS = Gamma*equilibriumState;  
                  SigmaSS = -L\SigmaSS;
                  L = expm_fastc(L*dt);
                end
                
                SigmaVector = SigmaSS+L*(SigmaVector-SigmaSS);
                
                Sigma = reshape(SigmaVector,n,n);
                
                % Computes Expectation Values if requested
                if currentEvent.Detection == 1
                  for iDet = 1:nDet
                    Density = Sigma(:);
                    currentSignal(iDet,iWavePoint+1) = Det{iDet}*Density/normsDet(iDet);
                    %                   currentSignal(j,k+1)=sum(sum(Det{j}.*Sigma.'))/normsDet(j);
                  end
                end
                
                % Store Density Matrices if requested
                if currentEvent.storeDensityMatrix == 1
                  DensityMatrices{iWavePoint+1}=Sigma;
                end
              end
              

              % Combine Results from current phase cycle with previous ones              
              if nPhaseCycle > 1
                PCweight = currentEvent.PhaseCycle(iPhaseCycle,2)/PCnorm;
                loopState = loopState+PCweight*Sigma;
                if currentEvent.Detection == 1
                  if iPhaseCycle ~= 1
                    PCSigma = PCSigma+PCweight*currentSignal;
                  else
                    PCSigma = PCweight*currentSignal;
                  end
                end
                if iPhaseCycle ~= nPhaseCycle
                  Sigma = initialState;
                end
              end
            end
            
          end
          
          % After Propagation and if PhaseCycling was active, the results
          % from phase cycling are returned
          if nPhaseCycle > 1
            Sigma = loopState;
            if currentEvent.Detection == 1
              currentSignal = PCSigma;
            end
          end
          
        case 'free evolution'        
          
          if Liouville == 0
            % If Detection is off during evolution, the entire evolution
            % can be propagated in one step
            if currentEvent.Detection == 1
              U = expm_fastc(-1i*Ham0*dt);
            else
              dt = currentEvent.t(end);
              tvector = [0 dt];
              U = expm_fastc(-1i*Ham0*dt);
            end
            
            % Propagation starts here
            for itvector=2:length(tvector)
              
              Sigma=U*Sigma*U';
              
              if currentEvent.Detection == 1
                for iDet = 1:nDet
                  Density = Sigma(:);
                  currentSignal(iDet,itvector) = Det{iDet}*Density/normsDet(iDet);
                  %               currentSignal(j,k)=sum(sum(Det{j}.*Sigma.'))/normsDet(j);
                end
              end
              
              if currentEvent.storeDensityMatrix == 1
                DensityMatrices{itvector}=Sigma;
              end
              
            end
            
          else % Propagate in Liouville space
            
            % Computation of Superoperator and Steady State density matrix
            HamSuOp = kron(eye(n,n),Ham0)-kron(Ham0.',eye(n,n));
            L = -1i*HamSuOp-Gamma;
            SigmaSS = Gamma*equilibriumState;
            SigmaSS = -L\SigmaSS;
            
            % If Detection is off during evolution, the entire evolution
            % can be propagated in one step
            if currentEvent.Detection == 1
              L = expm_fastc(L*dt);
            else
              dt = currentEvent.t(end);
              tvector = [0 dt];
              
              L = expm_fastc(L*dt);
            end
            
            % Propagation
            for itvector = 2:length(tvector)
              SigmaVector = SigmaSS+L*(SigmaVector-SigmaSS);
              Sigma = reshape(SigmaVector,n,n);
              
              if currentEvent.Detection == 1
                for iDet = 1:nDet
                  Density = Sigma(:);
                  currentSignal(iDet,itvector) = Det{iDet}*Density/normsDet(iDet);
                  %                 currentSignal(j,k)=sum(sum(Det{j}.*Sigma.'))/normsDet(j);
                end
              end
              
              if currentEvent.storeDensityMatrix == 1
                DensityMatrices{itvector} = Sigma;
              end
            end
            
            
          end
          
      end
      
      % This combines the signals and time axes from all detected event
      if firstDetection && ~isempty(currentSignal)
        
        % store first point of the first signal
        Signal(:,1) = currentSignal(:,1);
        t(1,1) = ttotal;
        
        % now add all the others timepoints
        nSignal = size(currentSignal,2);
        endTrace = startTrace+nSignal-2;
        Signal(:,startTrace:endTrace) = currentSignal(:,2:end);
        t(1,startTrace:endTrace) = tvector(2:end)+ttotal;
        startTrace = endTrace+1;
        firstDetection = 0;
        
      elseif ~isempty(currentSignal)
        % adding other signals, this confusing index is necessary in
        % order to avoid double counting last point of a signal and the
        % first point of the succiding signal
        nSignal = size(currentSignal,2);
        endTrace = startTrace+nSignal-2;
        Signal(:,startTrace:endTrace) = currentSignal(:,2:end);
        t(1,startTrace:endTrace) = tvector(2:end)+ttotal;
        startTrace = endTrace+1;
      end
      
      % Update Total Time, necessary to keep correct timings  if events are
      % not detected
      ttotal = ttotal + tvector(end);
      
    end
    
  case 'incrementation scheme'
    
    
    
    % IncScheme check
    %------------------------------------------------------------
    if (length(IncScheme)>1) && (nargin<7),
      error('The requested IncScheme requires mixing propagators, but none are provided!');
    end
    if any((abs(IncScheme)~=1) & (abs(IncScheme)~=2))
      error('IncScheme can contain only 1, -1, 2, and -2.');
    end
    
    nEvolutionPeriods = numel(IncScheme);
    nDimensions = max(abs(IncScheme));
    
    % Parameter parsing
    %------------------------------------------------------------
    if ~iscell(Det)
      Det = {Det};
    end
    nDetectors = numel(Det);
    
    if ~iscell(Mix)
      Mix = {Mix};
    end
    nMixingBlocks = numel(Mix);
    
    if (nMixingBlocks~=nEvolutionPeriods-1),
      error('Number of mixing propagators not correct! %d are needed.',nEvolutionPeriods-1);
    end
    N = size(Sigma,1);
    
    if (nDimensions==1)
      for iDet = 1:nDetectors
        Signal{iDet} = zeros(n,1);
      end
      if iscell(Ham0), Ham0 = Ham0{1}; end
    else
      if numel(dt)==1, dt = [dt dt]; end
      if numel(n)==1, n = [n n]; end
      for iDet = 1:nDetectors
        Signal{iDet} = zeros(n);
      end
    end
    if nDetectors==1
      Signal = Signal{1};
    end
    
    % Transform all operators to Hamiltonian eigenbasis (eigenbases)
    %---------------------------------------------------------------
    if ~iscell(Ham0)
      
      if nnz(Ham0)==nnz(diag(Ham0)) % Check if Hamiltonian is already diagonal
        E = diag(Ham0);
        Density = Sigma;
        Detector = Det;
      else
        % Diagonalize Hamiltonian
        [Vecs,E] = eig(Ham0); % MHz, E doesn't have to be sorted
        E = real(diag(E));
        % Transform all other matrices to Hamiltonian eigenbasis
        Density = Vecs'*Sigma*Vecs;
        for iMix = 1:nMixingBlocks
          Mix{iMix} = Vecs'*Mix{iMix}*Vecs;
        end
        for iDet = 1:nDetectors
          Detector{iDet} = Vecs'*Det{iDet}*Vecs;
        end
      end
      
      % Define free evolution propagators
      if (nDimensions==1)
        diagU = exp(-2i*pi*dt*E);
      else
        diagUX = exp(-2i*pi*dt(1)*E);
        diagUY = exp(-2i*pi*dt(2)*E);
      end
      
    else
      
      % Check if Hamiltonians are already diagonal
      if (nnz(Ham0{1})==nnz(diag(Ham0{1})) && nnz(Ham0{1})==nnz(diag(Ham0{1})))
        Ex = Ham0{1};
        Ey = Ham0{2};
        Density = Sigma;
        Detector = Det;
      else
        
        % Diagonalize Hamiltonians
        [Vecs{1},Ex] = eig(Ham0{1});
        [Vecs{2},Ey] = eig(Ham0{2});
        
        % Transform all other matrices to Hamiltonian eigenbasis
        d = abs(IncScheme);
        Density = Vecs{d(1)}'*Sigma*Vecs{d(1)};
        for iMix = 1:nMixingBlocks
          Mix{iMix} = Vecs{d(iMix+1)}'*Mix{iMix}*Vecs{d(iMix)};
        end
        for iDet = 1:nDetectors
          Detector{iDet} = Vecs{d(end)}'*Det{iDet}*Vecs{d(end)};
        end
        
      end
      
      % Define free evolution propagators
      diagUX = exp((-2i*pi*dt(1))*real(diag(Ex)));
      diagUY = exp((-2i*pi*dt(2))*real(diag(Ey)));
      
    end
    
    % Time-domain evolution, IncScheme switchyard
    %------------------------------------------------------------
    % The following implementations in the propagator eigenframes
    % (giving diagonal propagators) make use of the following simplifications
    % of the matrix multiplications associated with the propagations:
    %
    %   U*Density*U'   = (diagU*diagU').*Density
    %   U*Propagator*U = (diagU*diagU.').*Propagator
    %   (U^-1)*Propagator*U = U'*Propagator*U = (conj(diagU)*diagU.').*Propagator
    %   U*Propagator*(U^-1) = U*Propagator*U' = (diagU*diagU').*Propagator
    %
    % where U are diagonal matrices and diagU are vectors of eigenvalues.
    
    % Pre-reshape for trace calculation
    for iDet = 1:nDetectors
      Detector{iDet} = reshape(Detector{iDet}.',1,N^2);
    end
    if nDetectors==1
      Detector = Detector{1};
    end
    
    if isequal(IncScheme,1) % IncScheme [1]
      FinalDensity = Density(:);
      U_ = diagU*diagU';
      U_ = U_(:);
      for ix = 1:n
        % Compute trace(Detector*FinalDensity)
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity;
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity;
          end
        end
        FinalDensity = U_.*FinalDensity; % equivalent to U*FinalDensity*U'
      end
      
    elseif isequal(IncScheme,[1 1]) % IncScheme [1 1]
      UU_ = diagU*diagU.';
      % It is not necessary to evolve the initial density matrix.
      % Only the mixing propagator needs to be evolved.
      Mix1 = Mix{1};
      for ix = 1:n
        % Compute density right before Detection
        FinalDensity = Mix1*Density*Mix1';
        % Compute trace(Detector*FinalDensity)
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity(:);
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity(:);
          end
        end
        Mix1 = UU_.*Mix1; % equivalent to U*Mix1*U
      end
      
    elseif isequal(IncScheme,[1 -1]) % IncScheme [1 -1]
      %   % Pre-propagate mixing propagator to end of second period (= start of
      %   % experiment)
      %   MixX = diag(diagU.^n)*Mix{1};
      MixX =Mix{1};
      UtU_ = conj(diagU)*diagU.';
      for ix = 1:n
        FinalDensity = MixX*Density*MixX';
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity(:);
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity(:);
          end
        end
        MixX = UtU_.*MixX; % equivalent to U^-1*MixX*U
      end
      
    elseif isequal(IncScheme,[1 2]) % IncScheme [1 2]
      UX_ = diagUX*diagUX';
      UY_ = diagUY*diagUY';
      UY_ = reshape(UY_,N^2,1);
      Mix1 = Mix{1};
      for ix = 1:n(1)
        FinalDensity = reshape(Mix1*Density*Mix1',N^2,1);
        for iy = 1:n(2)
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity;
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity;
            end
          end
          FinalDensity = UY_.*FinalDensity; % equivalent to UY*Density*UY';
        end
        Density = UX_.*Density; % equivalent to UX*Density*UX';
      end
      
    elseif isequal(IncScheme,[1 1 2]) % IncScheme [1 1 2]
      UUX_ = diagUX*diagUX.';
      UY_ = diagUY*diagUY';
      Mix1 = Mix{1};
      Mix2 = Mix{2};
      for ix = 1:n(1)
        M = Mix2*Mix1;
        FinalDensity = M*Density*M';
        for iy = 1:n(2)
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          FinalDensity = UY_.*FinalDensity; % equivalent to UY*FinalDensity*UY'
        end
        Mix1 = UUX_.*Mix1; % equivalent to UX*Mix1*UX
      end
      
    elseif isequal(IncScheme,[1 -1 2]) % IncScheme [1 -1 2]
      UtUX_ = conj(diagUX)*diagUX.';
      UY_ = diagUY*diagUY';
      %   % Pre-propagate mixing propagator to end of second period (= start of
      %   % experiment)
      %   MixX = diag(diagUX.^n(1))*Mix{1};
      MixX = Mix{1};
      Mix2 = Mix{2};
      for ix = 1:n(1)
        M = Mix2*MixX;
        FinalDensity = M*Density*M';
        for iy = 1:n(2)
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          FinalDensity = UY_.*FinalDensity; % equivalent to UY*FinalDensity*UY'
        end
        MixX = UtUX_.*MixX; % equivalent to U^-1*MixX*U
      end
      
    elseif isequal(IncScheme,[1 2 1]) % IncScheme [1 2 1]
      Mix1 = Mix{1};
      Mix2 = Mix{2};
      UUX_ = diagUX*diagUX.';
      UY = diag(diagUY);
      for iy = 1:n(2)
        MixY = Mix2*Mix1;
        MixYadj = MixY';
        for ix = 1:n(1)
          FinalDensity = MixY*Density*MixYadj;
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          MixY = UUX_.*MixY; % equivalent to UX*MixY*UX
        end
        Mix1 = UY*Mix1;
      end
      
    elseif isequal(IncScheme,[1 2 2 1]) % IncScheme [1 2 2 1]
      Mix1 = Mix{1};
      Mix2 = Mix{2};
      Mix3 = Mix{3};
      UUX_ = diagUX*diagUX.';
      UUY_ = diagUY*diagUY.';
      for iy = 1:n(2)
        MixY = Mix3*Mix2*Mix1;
        MixYadj = MixY';
        for ix = 1:n(1)
          FinalDensity = MixY*Density*MixYadj;
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          MixY = UUX_.*MixY; % equivalent to UX*MixY*UX
        end
        Mix2 = UUY_.*Mix2; % equivalent to UY*Mix2*UY
      end
      
    elseif isequal(IncScheme,[1 2 -2 1]) % IncScheme [1 2 -2 1]
      Mix1 = Mix{1};
      %   Mix2 = diag(diagUY.^n(2))*Mix{2}; % pre-propagate to endpoint of third delay
      Mix2 = Mix{2};
      Mix3 = Mix{3};
      UUX_ = diagUX*diagUX.';
      UtUY_ = conj(diagUY)*diagUY.';
      for iy = 1:n(2)
        MixY = Mix3*Mix2*Mix1;
        MixYadj = MixY';
        for ix = 1:n(1)
          FinalDensity = MixY*Density*MixYadj;
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          MixY = UUX_.*MixY; % equivalent to UX*MixY*UX
        end
        Mix2 = UtUY_.*Mix2; % equivalent to UY'*Mix2*UY
      end
      
    elseif isequal(IncScheme,[1 -1 1 -1]) % IncScheme [1 -1 1 -1]
      %   Mix1X = diag(diagU.^n)*Mix{1}; % pre-propagate to endpoint of second delay
      Mix1X = Mix{1};
      Mix2 = Mix{2};
      %   Mix3X = diag(diagU.^n)*Mix{3}; % pre-propagate to endpoint of fourth delay
      Mix3X = Mix{3};
      UtU_ = conj(diagU)*diagU.'; % propagator for Mix1 and Mix3 (add before, remove after)
      for ix = 1:n
        MixX = Mix3X*Mix2*Mix1X;
        FinalDensity = MixX*Density*MixX';
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity(:);
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity(:);
          end
        end
        Mix1X = UtU_.*Mix1X; % equivalent to U'*Mix1X*U
        Mix3X = UtU_.*Mix3X; % equivalent to U'*Mix3X*U
      end
      
    elseif isequal(IncScheme,[1 1 -1 -1]) % IncScheme [1 1 -1 -1]
      Mix1 = Mix{1};
      %   Mix2X = diag(diagU.^n)*Mix{2}; % pre-propagate to endpoint of third delay
      %   Mix3X = diag(diagU.^n)*Mix{3}; % pre-propagate to endpoint of fourth delay
      Mix2X = Mix{2};
      Mix3X = Mix{3};
      UU1_ = diagU*diagU.'; % propagator for Mix1 (add before and after)
      UU3_ = conj(diagU*diagU.'); % propagator for Mix3 (remove before and after)
      for ix = 1:n
        MixX = Mix3X*Mix2X*Mix1;
        FinalDensity = MixX*Density*MixX';
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity(:);
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity(:);
          end
        end
        Mix1 = UU1_.*Mix1; % equivalent to U*Mix1*U
        Mix3X = UU3_.*Mix3X; % equivalent to U'*Mix3X*U'
      end
      
    elseif isequal(IncScheme,[1 1 -1 -1 2]) % IncScheme [1 1 -1 -1 2]
      Mix1 = Mix{1};
      %   Mix2X = diag(diagUX.^n(1))*Mix{2}; % pre-propagate to endpoint of third delay
      %   Mix3X = diag(diagUX.^n(1))*Mix{3}; % pre-propagate to endpoint of fourth delay
      Mix2X = Mix{2};
      Mix3X = Mix{3};
      Mix4 = Mix{4};
      UU1_ = diagUX*diagUX.'; % propagator for Mix1 (add before and after)
      UU3_ = conj(diagUX*diagUX.'); % propagator for Mix3 (remove before and after)
      UY_ = diagUY*diagUY';
      for ix = 1:n(1)
        MixX = Mix4*Mix3X*Mix2X*Mix1;
        FinalDensity = MixX*Density*MixX';
        for iy = 1:n(2)
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          FinalDensity = UY_.*FinalDensity; % equivalent to UY*FinalDensity*UY'
        end
        Mix1 = UU1_.*Mix1; % equivalent to U*Mix1*U
        Mix3X = UU3_.*Mix3X; % equivalent to U'*Mix3X*U'
      end
      
    elseif isequal(IncScheme,[1 -1 -1 1]) % IncScheme [1 -1 -1 1]
      %   Mix1X = diag(diagU.^n)*Mix{1}; % pre-propagate to endpoint of second delay
      Mix1X = Mix{1};
      Mix2 = Mix{2};
      %   Mix3X = Mix{3}*diag(diagU.^n); % forward-propagate to endpoint of fourth delay
      Mix3X = Mix{3};
      UtU1_ = conj(diagU)*diagU.'; % propagator for Mix1 (add before, remove after)
      UtU3_ = diagU*diagU'; % propagator for Mix3 (remove before, add after)
      for ix = 1:n
        MixX = Mix3X*Mix2*Mix1X;
        FinalDensity = MixX*Density*MixX';
        if nDetectors==1
          Signal(ix) = Detector*FinalDensity(:);
        else
          for iDet = 1:nDetectors
            Signal{iDet}(ix) = Detector{iDet}*FinalDensity(:);
          end
        end
        Mix1X = UtU1_.*Mix1X; % equivalent to U'*Mix1X*U
        Mix3X = UtU3_.*Mix3X; % equivalent to U*Mix3X*U'
      end
      
    elseif isequal(IncScheme,[1 -1 -1 1 2]) % IncScheme [1 -1 -1 1 2]
      %   Mix1X = diag(diagUX.^n(1))*Mix{1}; % pre-propagate to endpoint of second delay
      Mix1X = Mix{1};
      Mix2 = Mix{2};
      %   Mix3X = Mix{3}*diag(diagUX.^n(1)); % forward-propagate to endpoint of fourth delay
      Mix3X = Mix{3};
      Mix4 = Mix{4};
      UtU1_ = conj(diagUX)*diagUX.'; % propagator for Mix1 (add before, remove after)
      UtU3_ = diagUX*diagUX'; % propagator for Mix3 (remove before, add after)
      UY_ = diagUY*diagUY';
      for ix = 1:n(1)
        MixX = Mix4*Mix3X*Mix2*Mix1X;
        FinalDensity = MixX*Density*MixX';
        for iy = 1:n(2)
          if nDetectors==1
            Signal(ix,iy) = Detector*FinalDensity(:);
          else
            for iDet = 1:nDetectors
              Signal{iDet}(ix,iy) = Detector{iDet}*FinalDensity(:);
            end
          end
          FinalDensity = UY_.*FinalDensity; % equivalent to UY*FinalDensity*UY'
        end
        Mix1X = UtU1_.*Mix1X; % equivalent to U'*Mix1X*U
        Mix3X = UtU3_.*Mix3X; % equivalent to U*Mix3X*U'
      end
      
    else
      error('Unsupported incrementation scheme!');
    end
    
    return
end
