function ok = test(opt)

% Read Adani spectrometer files

BaseDir = 'eprfiles/adani/';

Files{1} = 'pyrelen-2mT5mmAugstaak300sek.dat';


for iFile = 1:numel(Files)
  thisFile = Files{iFile};
  if (opt.Display)
    disp(thisFile);
  end
  clear data pars;
  thisFileName = [BaseDir thisFile];
 
  data = eprload(thisFileName);
  [x,data] = eprload(thisFileName);
  [x,data,pars] = eprload(thisFileName);
  
  readerr(iFile) = false;
  if ~iscell(data)
    if any(isnan(data(:)))
      readerr(iFile) = true;
      disp([  '   ' Files(iFile).name]);
    end
  end
  if (opt.Display)
    plot(x,data);
    pause
  end
end

ok = ~readerr;
