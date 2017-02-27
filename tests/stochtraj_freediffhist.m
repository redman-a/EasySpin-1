function [err,data] = test(opt,olddata)
% Check that using stochtraj with free diffusion generates a proper 
% distribution of orientations

Sys.tcorr = 10*rand()*1e-9;;
Par.dt = Sys.tcorr/10;
Par.nSteps = ceil(200*Sys.tcorr/Par.dt);
Par.nTraj = 400;
Par.Omega = [  pi*(2*rand()-1); 
             2*pi*(2*rand()-1);
             2*pi*(2*rand()-1) ];

nTraj = Par.nTraj;
nSteps = Par.nSteps;

nBins = 50;

[t, R] = stochtraj(Sys,Par);

VecTraj = squeeze(R(:, 3, :, :));

bins = linspace(0, pi, nBins)';
ThetaHist = zeros(nBins, nTraj);

for iTraj = 1:nTraj
  ThetaHist(:, iTraj) = hist(squeeze(acos(VecTraj(3, iTraj, :))), bins);
end

ThetaHist = sum(ThetaHist, 2);
ThetaHist = ThetaHist/sum(ThetaHist);

BoltzDist = ones(nBins,1);
BoltzInt = sum(BoltzDist.*sin(bins));
BoltzDist = BoltzDist.*sin(bins)./BoltzInt;

%ChiSquare = sum(((ThetaHist - BoltzDist).^2)./ThetaHist)
rmsd = sqrt(sum((ThetaHist - BoltzDist).^2)/nBins);

if rmsd > 1e-2
  err = 1;
  plot(bins, ThetaHist, bins, BoltzDist)
else  
  err = 0;
end

data = [];

end