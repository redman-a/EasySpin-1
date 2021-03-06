function ok = test(opt)

% Check derivative against explicit expression

x0 = 3; fwhm = 2;
x = linspace(-3,6,100);
y = gaussian(x,x0,fwhm,0);

gam = fwhm/sqrt(2*log(2));
xi = (x-x0)/gam;
y0 = sqrt(2/pi)/gam*exp(-2*xi.^2);

if opt.Display
  plot(x,y0,x,y,'r',x,y0./y);
  legend('explicit','gaussian()');
  legend boxoff
end

ok = areequal(y,y0,1e-10,'rel');
