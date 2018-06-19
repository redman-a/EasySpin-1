function [Events, Vary, Opt] = sequencer(Exp,Opt)
% This function creates the Event and Vary Structures

% -------------------------------------------------------------------------
% Pre-Processing
% -------------------------------------------------------------------------
Vary = [];

Opt.SinglePointDetection = false;

% Set up detection
if isfield(Exp,'DetWindow')
  % Validate Exp.DetWindow
  logmsg(1,'setting up detection window...');
  if isfield(Exp,'DetSequence')
   warning('You provided Exp.DetWindow and Exp.DetSequence. Exp.DetSequence will be ignored.')
  end
  
  % Ensure that detection window does not overlap with a pulse
  if any(Exp.DetWindow<0) && isstruct(Exp.Sequence{end})
    error('You provided Exp.DetWindow with a negative value, but the last element in Exp.Sequence is a pulse. Detection into a pulse is not possible. Please adapt your detection or append an appropriate free evolution event.')
  elseif min(Exp.DetWindow) < 0 && (abs(min(Exp.DetWindow)) > Exp.Sequence{end})
    error('Your detection window is extending beyond the last free evolution into a pulse. Please shorten detection window or adapt the length of the free evolution.')
  end
  
  % Set up Exp.DetSequence - this requires adding a detection event of
  % Exp.Sequence
  if isstruct(Exp.Sequence{end}) 
    if Exp.DetWindow(1)>0
      Exp.Sequence{end+1} = Exp.DetWindow(1);
    end
  else
    Exp.Sequence{end} = Exp.Sequence{end} + Exp.DetWindow(1);
  end
  if length(Exp.DetWindow) == 1
    % single point detection
    Opt.SinglePointDetection = true;
    Exp.Sequence{end+1} = 0;
  else
    % transient
    Exp.Sequence{end+1} = diff(Exp.DetWindow);
  end
  
  Exp.DetSequence = zeros(1,length(Exp.Sequence));
  Exp.DetSequence(end) = true;
  
elseif isfield(Exp,'DetSequence')
  % setting up detection in case of Exp.DetSequence
  logmsg(1,'setting up detection...');
  if ischar(Exp.DetSequence)
    % parsing strings
    if strcmp(Exp.DetSequence,'last')
      Exp.DetSequence = zeros(1,length(Exp.Sequence));
      Exp.DetSequence(end) = true;
    elseif strcmp(Exp.DetSequence,'all')
      Exp.DetSequence = ones(1,length(Exp.Sequence));
    else
      msg = 'The string you provided in Exp.DetSequence was not recognized';
      error(msg);
    end
  else
    if length(Exp.DetSequence) ~= 1 && length(Exp.DetSequence) ~= length(Exp.Sequence)
      error('The lengths of Exp.Sequence and Exp.DetSequence do not match. Length of Exp.DetSequence has to be 1 or the same as Exp.Sequence.')
    end
  end
  
  % identifying single point detection
  if sum(Exp.DetSequence) == 1 && ~isstruct(Exp.Sequence{Exp.DetSequence==1}) && Exp.Sequence{Exp.DetSequence==1} == 0
    Opt.SinglePointDetection = true;
  end
  
else
  % default if no detection is given:
  logmsg(1,'assuming defaults for detection...');
  Exp.DetSequence = ones(1,length(Exp.Sequence));
end

% Check if resonator is 
if isfield(Exp,'Resonator')
  logmsg(1,'validating resonator...');
  IncludeResonator = true;
  
  if ~isfield(Exp,'mwFreq')
    error('For using a resonator, the field Exp.mwFreq needs to be provided, and Exp.Frequency needs to be defined in relation to that.')
  end
  
  if ~isfield(Exp.Resonator,'nu') && ~isfield(Exp.Resonator,'TransferFunction') && ~isfield(Exp.Resonator,'nu0') && ~isfield(Exp.Resonator,'QL')
    error('In order to use a resonator either nu0 and QL or nu and TransferFunction need to be defined.')
    % Looks for frequency axis nu and transfer function
  elseif (isfield(Exp.Resonator,'nu') && ~isfield(Exp.Resonator,'TransferFunction')) || (~isfield(Exp.Resonator,'nu') && isfield(Exp.Resonator,'TransferFunction'))
    error('Either Exp.Resonator.nu or Exp.Resonator.TransferFunction is missing')
  elseif isfield(Exp.Resonator,'nu') && isfield(Exp.Resonator,'TransferFunction')
    Resonator.Arg1 = Exp.Resonator.nu;
    Resonator.Arg2 = Exp.Resonator.TransferFunction;
  elseif (isfield(Exp.Resonator,'nu0') && ~isfield(Exp.Resonator,'QL')) || (~isfield(Exp.Resonator,'nu0') && isfield(Exp.Resonator,'QL'))
    % Looks for center frequency nu0 and loaded Qualityfactor
    error('Either Exp.Resonator.nu0 or Exp.Resonator.QL is missing')
  elseif isfield(Exp.Resonator,'nu0') && isfield(Exp.Resonator,'QL')
    Resonator.Arg1 = Exp.Resonator.nu0;
    Resonator.Arg2 = Exp.Resonator.QL;
  end
  
  % if no mode for the resonator incorporation is given, 'simulate' is
  % assumed by default
  if isfield(Exp.Resonator,'Mode')
    if any(strcmp(Exp.Resonator.Mode,{'simulate' 'compensate'}))
      Resonator.Arg3 = Exp.Resonator.Mode;
    else
      error('Resonator.Mode must be ''simulate'' or ''compensate''.')
    end
  else
    Resonator.Arg3 = 'simulate';
  end
else
  IncludeResonator = false;
end

FreqShift = 0;

% get the absolute frequency shift, which is a combination of Exp.mwFreq
% (if given) and the shift of the simulation frame. this frequency shift is
% required for determining the minimum required step size.
if isfield(Exp,'mwFreq')
  FreqShift = FreqShift + Exp.mwFreq;
end

logmsg(1,'setting up simulation frame...');
if isfield(Opt,'SimFrequency')
  % user provided value fo shift of simulation frequency
  if Opt.SimFrequency == 0
    % user requested lab frame
    FreqShift = FreqShift; %#ok<ASGSL> % Do nothing
    FrameShift = false;
  else
    FreqShift = FreqShift - Opt.SimFrequency;
    FrameShift = Opt.SimFrequency;
  end
  
else
  % determine minimum frequency in the experiment definition in order to
  % guess a frequency for the frame shift
  
  if isfield(Exp,'mwFreq')
    MinFreq = Exp.mwFreq;
  else
    MinFreq = [];
  end
  
  % loop over the pulses and look for the minimum frequency there
  for iEvent = 1 : length(Exp.Sequence)
    if isstruct(Exp.Sequence{iEvent}) && isfield(Exp.Sequence{iEvent},'Frequency')
      if isempty(MinFreq)
        MinFreq = min(Exp.Sequence{iEvent}.Frequency);
      else
        MinFreq = min([MinFreq (Exp.Sequence{iEvent}.Frequency + FreqShift)]);
      end
    end
  end
   
  % Have at least 2 GHz difference to the lowest frequency (for the frame
  % shift)
  FrameShift = floor(MinFreq-2);
  % only shift down, no upshifting - if lab frame frequencies exist that
  % are < 2 GHz
  if FrameShift > 0
    FreqShift = FreqShift - FrameShift;
  end
end

if FrameShift ~= 0
  logmsg(1,'simulation frame frequency is %d GHz',FrameShift);
else
  logmsg(1,'simulating in the lab frame');
end

Opt.FrameShift = FrameShift;
Opt.FreqShift = FreqShift;

% Check if TimeStep exists and if it is sufficient or, if none provided,
% compute a new one
logmsg(1,'determining minimal required time step');
MaxFreq = FreqShift;
  for iEvent = 1 : length(Exp.Sequence)
    if isstruct(Exp.Sequence{iEvent}) && isfield(Exp.Sequence{iEvent},'Frequency')
       MaxFreq = max([(Exp.Sequence{iEvent}.Frequency + FreqShift) MaxFreq]);
    end
  end
  
Nyquist = 2*MaxFreq;
MaxTimeStep = 1/Nyquist/1000; % Time Step is in microseconds and Frequencies in GHz

% validate time step
if isfield(Exp,'TimeStep')
  if Exp.TimeStep > MaxTimeStep
    errMsg = ['Your Time Step (Exp.TimeStep) does not fullfill the Nyquist criterium for the pulses you provided. Adapt it to ' num2str(MaxTimeStep) ' or less.'];
    error(errMsg);
  end
else
  logmsg(1,'automatically assuming a suitable time step');
  Exp.TimeStep = round(MaxTimeStep/4,2,'significant');
end

logmsg(1,'the time step is %0.2e microseconds',Exp.TimeStep);

% Create an empty cell array for all the events
Events = cell(1,length(Exp.Sequence));
nEvents = length(Exp.Sequence);

% Variables for bookkeeping of pulses and free evolution events
iPulse = 0;
iDelay = 0;

% A vector to quickly identify pulses, required for the reordering if
% pulses cross during the sequence
isPulse = zeros(1,length(Events));
PulseIndices = [];

Intervals = zeros(1,length(Exp.Sequence));

% making sure that relaxation is defined globally of for all individual
% elements in Exp.Sequence
if isfield(Opt,'Relaxation')
  if length(Opt.Relaxation) ~= 1 && length(Opt.Relaxation) ~= length(Exp.Sequence)
    error('The lengths of Exp.Sequence and Opt.Relaxation do not match. Length of Opt.Relaxation has to be 1 or the same as Exp.Sequence.')
  end
end
 
% making sure that state trajectories are defined globally of for all 
% individual elements in Exp.Sequence
if isfield(Opt,'StateTrajectories')
  if length(Opt.StateTrajectories) ~= 1 && length(Opt.StateTrajectories) ~= length(Exp.Sequence)
    error('The lengths of Exp.Sequence and Opt.StateTrajectories do not match. Length of Opt.StateTrajectories has to be 1 or the same as Exp.Sequence.')
  end
end

% Setting up data structures for the pulses and events
for iEvent = 1 : nEvents
  if isstruct(Exp.Sequence{iEvent})
    iPulse = iPulse + 1;
    PulseIndices(iPulse) = iEvent; %#ok<AGROW>
    isPulse(iEvent) = true;
  else
    iDelay = iDelay + 1;
    DelayIndices(iDelay) = iEvent; %#ok<AGROW>
    isPulse(iEvent) = false; 
  end
end

nPulses = length(PulseIndices);
Pulses = cell(1,nPulses);
iPulse = 1;
% -------------------------------------------------------------------------

% -------------------------------------------------------------------------
% Create the Eventstructure
% -------------------------------------------------------------------------
logmsg(1,'parsing Exp.Sequence...');
logmsg(1,'found %d pulse(s) and %d free evolution period(s)',nPulses,iDelay);
if nPulses > 0
  logmsg(1,'computing wave forms and setting up the event structures');
else
  logmsg(1,'setting up the event structures');
end

for iEvent = 1 : length(Exp.Sequence)
  if isPulse(iEvent)
    Pulse = [];
    
    % Gets the PhaseCycle for the current Pulse, if none is provided, phase
    % cycling is switched off for this event
    if isfield(Exp,'PhaseCycle') &&  iPulse <= length(Exp.PhaseCycle) && ~isempty(Exp.PhaseCycle{iPulse})
      ThisPhaseCycle = Exp.PhaseCycle{iPulse};
      nPhaseSteps = size(ThisPhaseCycle,1);
    else
      ThisPhaseCycle = 0;
      nPhaseSteps = 1;
    end
    
    if ~isfield(Exp.Sequence{iEvent},'IQ') % Pulse.IQ is being used for userdefined IQs
      % ---------------------------------------------------------------------
      % Pulse Specific Fields
      % ---------------------------------------------------------------------
      
      % if no pulse type is provided, the default is a rectangular pulse
      if ~isfield(Exp.Sequence{iEvent},'Type')
        
        % First check for field frequency and correct it
        if ~isfield(Exp.Sequence{iEvent},'Frequency')
          % if no frequency is defined, frequency is set to 0 (Exp.mwFreq
          % will be added later)
          Exp.Sequence{iEvent}.Frequency = 0;
          Exp.Sequence{iEvent}.Type = 'rectangular';
          if ~isfield(Exp,'mwFreq')
            error('If you do not provide a frequency for the pulse, you need to give Exp.mwFreq.')
          end
        elseif length(Exp.Sequence{iEvent}.Frequency) > 1 && (Exp.Sequence{iEvent}.Frequency(2) ~= Exp.Sequence{iEvent}.Frequency(1))
          % make sure that, if a frequency was provided, it is not a frequency sweep 
          msg = ['Pulse at position ' num2str(iEvent) ' in Exp.Sequence: no Pulse.Type specified, assuming a monochromatice rectangular pulse, but the field Pulse.Frequency looks like a frequency-swept pulse.'];
          error(msg);
        end
      elseif strcmp(Exp.Sequence{iEvent}.Type,'rectangular') && ~isfield(Exp.Sequence{iEvent},'Frequency')
        Exp.Sequence{iEvent}.Frequency = 0;        
      end
      
      Pulse = Exp.Sequence{iEvent};
      
      if ~isfield(Pulse,'tp')
        msg = ['Pulse at position ' num2str(iEvent) ' in Exp.Sequence: no Pulse.tp specified. Please provide a pulse length.'];
        error(msg);
      end
      
      % Makes sure a frequency was provided
      if ~isfield(Pulse,'Frequency')
        error('The Frequency Band for Pulse in position %d in Exp.Sequence is missing.',iEvent)
      end
      
      Pulse.PhaseCycle = ThisPhaseCycle;

      % Gets the flip angle
      if isfield(Exp.Sequence{iEvent},'Flip')
        Pulse.Flip = Exp.Sequence{iEvent}.Flip;
      elseif ~isfield(Pulse,'Qcrit') && ~isfield(Pulse,'Amplitude')
        error('No Flipangle for Pulse No. %d provided.',iPulse)
      end
      
      % Gets the phase for the pulse, if none is provided, the phase is
      % assumed to be 0
      if ~isfield(Pulse,'Phase')
        Pulse.Phase = 0;
      end
      
      % Get the time step
      Pulse.TimeStep = Exp.TimeStep;
      
      Pulse.Frequency = Pulse.Frequency*1000; % GHz to MHz
      
      % Loop over the function that creates the PulseShape, as many times at
      % are necessary to calculate all wave forms for the phase cycling
      for iPCstep = 1 : nPhaseSteps
        Pulse.Phase = Pulse.Phase + Pulse.PhaseCycle(iPCstep,1);
        [t,IQ] = pulse(Pulse);
        if IncludeResonator
          % if resonator is requested, pulses are elongated due to ringing.
          % the duration of ringing is stored in an additional field
          tOrig = t(end);
          [t,IQ] = resonator(t,IQ,Exp.mwFreq,Resonator.Arg1,Resonator.Arg2,Resonator.Arg3);
          Events{iEvent}.Ringing = t(end) - tOrig;
        end
        % Shifts IQ of the pulse if necessary...
        if FreqShift ~= 0
          Opt.dt = Exp.TimeStep;
          [t, IQ] = rfmixer(t,IQ,FreqShift,'IQshift',Opt);
        end
        % ... and stores it in the event structure
        Events{iEvent}.IQ(iPCstep,:) = IQ;
      end
      
      Pulse.Frequency = Pulse.Frequency/1000; % MHz to GHz
    else
      % in case user provided their own IQ(s)
      
      % determine input format:
      if iscell(Exp.Sequence{iEvent}.IQ)
        UserIQ = Exp.Sequence{iEvent}.IQ{1};
      elseif ismatrix(Exp.Sequence{iEvent}.IQ)
        UserIQ = Exp.Sequence{iEvent}.IQ;
      else
        errMsg = ['The data structure of the userdefined IQ of pulse on position ' num2str(iEvent) ' in Exp.Sequence is not recognized.'];
        error(errMsg);
      end
      
      [d1, d2] = size(UserIQ);
      % look for phase cycle and if found, verify that the IQ contains the
      % phase cycle
      if d1 ~= nPhaseSteps && d2 ~= nPhaseSteps
        errMsg = ['The dimensionality of the IQ signal provided of the pulse on position ' num2str(iEvent) ' in Exp.Sequence  is not in agreement with the phasecycle for this pulse. For user-defined waveforms the array must contain all IQs.'];
        error(errMsg);
      elseif d2 == nPhaseSteps
        UserIQ =  UserIQ';
      end
      
      % look for the time axis Pulse.t that corresponds to Pulse.IQ
      if ~isfield(Exp.Sequence{iEvent},'t')
        errMsg = ['A userdefined IQ was used for the pulse on position ' num2str(iEvent) ' in Exp.Sequence but the time axis is missing. Please provide it through Pulse.t.' ];
        error(errMsg);
      else
        if iscell(Exp.Sequence{iEvent}.t)
          Pulse.TimeStep = Exp.Sequence{iEvent}.t{1}(2) - Exp.Sequence{iEvent}.t{1}(1);
          tIQ = Exp.Sequence{iEvent}.t{1};
        else
          Pulse.TimeStep = Exp.Sequence{iEvent}.t(2) - Exp.Sequence{iEvent}.t(1);
          tIQ = Exp.Sequence{iEvent}.t;
        end
        Pulse.userIQ.t = Exp.Sequence{iEvent}.t;
      end
                        
      % Shifts IQ of the pulse if necessary...
      for iPhaseStep = 1 : nPhaseSteps
          Opt.dt = Exp.TimeStep;
          if IncludeResonator
            % but first if resonator is requested, pulses are elongated due to ringing.
            % the duration of ringing is stored in an additional field
            tOrig = t(end);
            [tIQ,currentIQ] = resonator(t,UserIQ(iPhaseStep,:),Exp.mwFreq,Resonator.Arg1,Resonator.Arg2,Resonator.Arg3);
            Events{iEvent}.Ringing = t(end) - tOrig;
          else
            currentIQ = UserIQ(iPhaseStep,:);
          end
          [t, ShiftedUserIQ(iPhaseStep,:)] = rfmixer(tIQ,currentIQ,-Opt.FrameShift,'IQshift',Opt);
      end
      Events{iEvent}.IQ =  ShiftedUserIQ;
       
      Pulse.userIQ.IQ = Exp.Sequence{iEvent}.IQ;
      Pulse.PhaseCycle = ThisPhaseCycle;
      
    end
    
    % Specify Type in Event structure
    Events{iEvent}.type = 'pulse';
    
    % Store the time axis of the pulse in the Event structure    
    Events{iEvent}.t = t;
    
    % Store the PhaseCycle in the Event structure
    Events{iEvent}.PhaseCycle = ThisPhaseCycle;
       
    % Checks if ComplexExcitation is requested for this Pulse, if not
    % specified Complex Excitation is switched off by default - the
    % excitation operator is being built outside of sequencer
    if ~isfield(Opt,'ComplexExcitation') || isempty(Opt.ComplexExcitation)
      Events{iEvent}.ComplexExcitation = false;
    elseif length(Opt.ComplexExcitation) == 1
      Events{iEvent}.ComplexExcitation = Opt.ComplexExcitation;
    elseif iPulse <= length(Opt.ComplexExcitation)
      Events{iEvent}.ComplexExcitation = Opt.ComplexExcitation(iPulse);
    else
      Events{iEvent}.ComplexExcitation = false;
    end
    
    % Temporarily store pulse paramaters to avoid reassigning them for creating the
    % vary table
    Pulse.EventIndex = iEvent;
    Pulses{iPulse} = Pulse;
    iPulse = iPulse + 1;
    
    Intervals(iEvent) = t(end);
  else
    % ---------------------------------------------------------------------
    % Delay/Free Evolution Specific Fields
    % ---------------------------------------------------------------------
    Events{iEvent}.type = 'free evolution';
    Events{iEvent}.t = Exp.Sequence{iEvent};
    
    Intervals(iEvent) = Exp.Sequence{iEvent};
  end
  
  % -----------------------------------------------------------------------
  % General Fields
  % -----------------------------------------------------------------------
  % The following fields need to be defined for both, pulses and free
  % evolution events
  
  % Check if Relaxation is requested for Events, by default, Relaxation is
  % switched off
  if ~isfield(Opt,'Relaxation')
    Events{iEvent}.Relaxation = false;
  else
    if length(Opt.Relaxation) == 1
      Events{iEvent}.Relaxation = Opt.Relaxation;
    else
      Events{iEvent}.Relaxation = Opt.Relaxation(iEvent);
    end
  end
  
  % Check if detection is provided, if no detection is requested, detection
  % is switched off
  if ~isfield(Exp,'DetSequence') || isempty(Exp.DetSequence)
      Events{iEvent}.Detection = false;
  else
    if length(Exp.DetSequence) == 1
      Events{iEvent}.Detection = Exp.DetSequence;
    else 
      Events{iEvent}.Detection = Exp.DetSequence(iEvent);
    end   
  end
  
  % Check if Density Matrices are to be stored, if not specified, Density
  % Matrices are not stored
  if ~isfield(Opt,'StateTrajectories')
    Events{iEvent}.StateTrajectories = false;
  else
    if length(Opt.StateTrajectories) == 1
      Events{iEvent}.StateTrajectories = Opt.StateTrajectories;
    else
      Events{iEvent}.StateTrajectories = Opt.StateTrajectories(iEvent);
    end
  end
  
  % Store an empty propagation structure, will be overwritten by thyme
  Events{iEvent}.Propagation = [];
  
  % Store the time step, which will be needed in thyme to calculate time
  % axis and propagators
  Events{iEvent}.TimeStep = Exp.TimeStep;
  
  % Keep track of the frameshift
  Events{iEvent}.FrameShift = FrameShift;
  
end

% -------------------------------------------------------------------------
% Checks for overlap of pulses that are subject to ringing
% -------------------------------------------------------------------------
if IncludeResonator
  logmsg(1,'checking for pulse overlap due to ringing from resonator...');
  
  for iEvent = PulseIndices
    FollowingEvent = iEvent + 1;
    if FollowingEvent <= length(Exp.Sequence) && strcmp(Events{FollowingEvent}.type,'pulse')
      error('When using a resonator, pulses need to be separated by inter pulse delays to accomodate for ringing from the resonator.')
    elseif FollowingEvent <= length(Exp.Sequence)
      ShortenedDelay = Events{FollowingEvent}.t - Events{iEvent}.Ringing;
      if ShortenedDelay < 0
        Msg = ['Event ' num2str(FollowingEvent) ' (a delay) is too short to accomodate ringing of the preceding pulse.'];
        error(Msg);
      end
    end    
  end 
  logmsg(1,'all good!');
end

% -------------------------------------------------------------------------
% Creates the Vary structure
% -------------------------------------------------------------------------

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Switching incrementation scheme to off for now, this will be an option
% later on, and will decide on how the incremenation tables are stored. For
% the incrementationscheme only linear increments can be used, and the data
% structure can therefore be reduced
IncrementationScheme = false;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if isfield(Exp,'nPoints')
  logmsg(1,'validating indirect dimensions...');
  nDimensions = length(Exp.nPoints);
  Vary.Points = Exp.nPoints;
  
  % Layout the Incrementation data structure
  if IncrementationScheme 
    Vary.IncrementationTable = zeros(nEvents,nDimensions);
  else
    Vary.IncrementationTable = cell(1,nDimensions);
  end
  
  % This cell array will carry all the modifications that are being made to
  % a pulse in any dimension - each element corresponds to a pulse and will
  % contain the dimensions, fields and values that are to be changed 
  PulseModifications = cell(1,nPulses);
  
  % -----------------------------------------------------------------------
  % Loop over all the provided dimensions and process the input - for
  % changing delays or pulse positions, incrementation tables can be
  % created for each dimension. If pulse parameters are changed, the
  % changed pulse parameters are stored in PulseModifications. After all
  % dimensions have been checked, the values stored in Pulse
  % -----------------------------------------------------------------------
  logmsg(1,'found %d indirect dimension(s)',nDimensions);
  for iDimension = 1 : nDimensions
    logmsg(1,'parsing dimension no. %d',iDimension);
    % If it is not possible to use a predefined incrementation scheme,
    % incrementation tables are created for each individual dimension, that
    % contain all the changes to event lengths for all events in the
    % corresponding dimension. This also allows to use non-linear
    % increments
    if ~IncrementationScheme
      IncrementationTable = zeros(nEvents,Vary.Points(iDimension));
    end
    
    if nDimensions == 1
      if isfield(Exp,'Dim')
        error('You provided Exp.Dim, please always provide Dim with a number, e.g Exp.Dim1.')
      end
    end
    
    Field2Get = ['Dim' num2str(iDimension)];
    
    if ~isfield(Exp,Field2Get)
      msg = ['You requested a ' num2str(nDimensions) '-dimensional experiment, but Exp.Dim' num2str(iDimension) ' is missing.'];
      error(msg);
    end
    
    % Scans all the lines of the Dim field. Each line can contain multiple
    % events/fields 
    for iLine = 1 : size(Exp.(Field2Get),1)
      % Gets the string, that lists the events/fields that are to be
      % changed
      FullString = Exp.(Field2Get){iLine,1};
      
      % changed values are seperated with commas
      SplitStrings = regexp(FullString,',','split');
      
      % Loops over all entries in the current line
      for iModifiedEvent = 1 : length(SplitStrings)
        FieldIndex = [];      
        % modified pulses are defined through p#.Field and if a '.' is
        % found, the string is split again. Delays are ignored this way
        Strings = regexp(SplitStrings{iModifiedEvent},'\.','split');
        
        EventType = Strings{1}(1);
        EventSpecificIndex = str2double(Strings{1}(2:end));
        
        if length(Strings) == 2
          pars = regexp(Strings{2},'\(|\)','split');
          Strings{2} = pars{1};
          if length(pars) > 1          
            FieldIndex = str2double(pars{2});
          end
        end
        
        % check if user provided incrementation vector has the correct
        % length
        if (length(Strings) ~= 2 || ~strcmp(Strings{2},'IQ'))
          % determined whether user wants to modify Pulse.IQ
          if length(Strings) ~= 2 || ~strcmp(Strings{2},'Frequency') || length(Exp.(Field2Get){iLine,2}) == 1 || ~any(size(Exp.(Field2Get){iLine,2},1) == [1 Exp.nPoints(iDimension)-1])
            % determined if field was p1.Frequency
            if length(Exp.(Field2Get){iLine,2}) ~= 1 && length(Exp.(Field2Get){iLine,2}) ~= Exp.nPoints(iDimension)
              % checked for correct length
              message = ['The number of points provided for Dimension ' num2str(iDimension) ' does not match the length of the vector in the Exp.Dim structure.'];
              error(message);
            end
          end
        end
        
        % -----------------------------------------------------------------
        % Different Processing for a pulse 'p' and a free evolution
        % event/delay 'd'
        % -----------------------------------------------------------------
        switch EventType
          case 'p'         
            % Convert the index as provided in the Dimension structure to
            % an eventnumber and pulsenumber
            EventNumber = Pulses{EventSpecificIndex}.EventIndex;
            PulseNumber = EventSpecificIndex;
            
              % Gets the field that is to be modified
              if length(Strings) == 1
                message = ['You requested a pulse to be changed in Exp.' (Field2Get) ' but did not specify the field.'];
                error(message)
              end
              
              Field = Strings{2};
              
              % Catch if user defines pulse length as 't' instead of 'tp'
              if strcmp(Field,'t')
                Field = 'tp';
              end
              
              switch Field
                % If the field is 'Position', the surrounding events (which
                % have to be delays) are changed in length. This is written
                % to the incrementation table
                case 'Position'
                  SurroundingEvents = [EventNumber-1 EventNumber+1];
                  
                  if any(SurroundingEvents>nEvents) || any(SurroundingEvents>nEvents)
                    error('Moving pulses can not be the first or last event in your Exp structure.')
                  end
                  
                  % get the Increment
                  dt = Exp.(Field2Get){iLine,2};
                  
                  if ~IncrementationScheme
                    if length(dt) == 1
                      IncrementationTable(SurroundingEvents(1),:) = IncrementationTable(SurroundingEvents(1),:) + (0:Vary.Points(iDimension)-1)*dt;
                      IncrementationTable(SurroundingEvents(2),:) = IncrementationTable(SurroundingEvents(2),:) - (0:Vary.Points(iDimension)-1)*dt;
                    else
                      IncrementationTable(SurroundingEvents(1),1:end) = IncrementationTable(SurroundingEvents(1),1:end) + dt;
                      IncrementationTable(SurroundingEvents(2),1:end) = IncrementationTable(SurroundingEvents(2),1:end) - dt;
                    end
                  else
                    Vary.IncrementationTable(SurroundingEvents(1),iDimension) = Vary.IncrementationTable(SurroundingEvents(1),iDimension) + dt;
                    Vary.IncrementationTable(SurroundingEvents(2),iDimension) = Vary.IncrementationTable(SurroundingEvents(2),iDimension) - dt;
                  end
                  
                case 'IQ'
                  if isempty(PulseModifications{PulseNumber})
                    PulseModifications{PulseNumber} = {iDimension Field [] []};
                  else
                    n = size(PulseModifications{PulseNumber},1);
                    PulseModifications{PulseNumber}{n+1,1} = iDimension;
                    PulseModifications{PulseNumber}{n+1,2} = Field;
                  end
                  
                otherwise
                  % If not the position is changed it is a pulse parameter.
                  % All pulse parameters are first stored in  a seperate
                  % structure, called PulseModifications. Each dimension can
                  % add fields and values to it. Only after all dimensions
                  % have been checked for pulse modifications, the pulses can
                  % be calculated and stored in the Vary structure
                  if isempty(PulseModifications{PulseNumber})
                    PulseModifications{PulseNumber} = {iDimension Field Exp.(Field2Get){iLine,2} FieldIndex};
                  else
                    n = size(PulseModifications{PulseNumber},1);
                    PulseModifications{PulseNumber}{n+1,1} = iDimension;
                    PulseModifications{PulseNumber}{n+1,2} = Field;
                    PulseModifications{PulseNumber}{n+1,3} = Exp.(Field2Get){iLine,2};
                    PulseModifications{PulseNumber}{n+1,4} = FieldIndex;
                  end
              end
            
          case 'd'
            % If a delay is changed, the incrementation/decrementation is
            % written to the incrementation table of the corresponding
            % dimension
            EventNumber = DelayIndices(EventSpecificIndex);
            
            % Increment
            dt = Exp.(Field2Get){iLine,2};
            
            if ~IncrementationScheme
              if length(dt) == 1
                IncrementationTable(EventNumber(1),:) = IncrementationTable(EventNumber(1),:) + (0:Vary.Points(iDimension)-1)*dt;
              else
                IncrementationTable(EventNumber(1),1:end) = IncrementationTable(EventNumber(1),1:end) + dt;
              end
            else
              Vary.IncrementationTable(EventNumber(1),iDimension) = Vary.IncrementationTable(EventNumber(1),iDimension) + dt;
            end
        end
      end
    end
    
    % Stores the IncrementationTable dimension specific
    if ~IncrementationScheme && any(any(IncrementationTable))
      Vary.IncrementationTable{iDimension} = IncrementationTable;
    end
  end
  
  % -----------------------------------------------------------------------
  % The following part checks for pulse overlap and precomputes the wave
  % forms for pulses that are variied
  % -----------------------------------------------------------------------
  nDataPoints = prod(Vary.Points);
  DimensionIndices = ones(1,nDimensions);
  
  % For each data point, the originial/starting values for the pulses are
  % required
  InitialPulses = Pulses;
  
  % Each pulse that is modified will have all its waveforms stored in
  % Vary.Pulses{iPulse}. Vary.Pulses{iPulse} is a cell array with the
  % dimensionality of points in the dimension that it is being changed in.
  % If for example the pulse is changed along the first dimension the size
  % of Vary.Pulses{iPulse} is [nDim1 1 1 ...], if it is changed along the
  % second dimension [1 nDim2 1 1 ...] or if along all dimension [nDim1
  % nDim2 nDim3 nDim4 ...]
  Vary.Pulses = cell(1,nPulses);
  
  % Loop over all DataPoints/Aquisitions and check for pulse overlap and
  % compute pulse shapes if they are changed
  logmsg(1,'creating the Vary structure that contains all required wave forms and delay changes...');
  for iDataPoint = 1 : nDataPoints
    % Load starting values for pulses and event lengths
    Pulses = InitialPulses;
    EventLengths = Intervals;
    
    % ---------------------------------------------------------------------
    % First we need to loop over all pulses and check them for 
    % modifications
    % ---------------------------------------------------------------------
    for iPulse = 1 : nPulses
      % if this pulse is changed, set the values for the pulse parameters
      % accordingly
      if ~isempty(PulseModifications{iPulse})
        % Create and index for storing the pulse shapes in
        % Vary.Pules{iPulse}
        Pulses{iPulse}.ArrayIndex = ones(1,length(DimensionIndices));
        
        IQindex = 0;
        for iModification = 1 : size(PulseModifications{iPulse},1)
          if strcmp(PulseModifications{iPulse}{iModification,2},'IQ')
            IQindex = IQindex + 1;
          end
        end
        
        if ~IQindex
        
          for iModification = 1 : size(PulseModifications{iPulse},1)
            % Load Modifications
            Dimension = PulseModifications{iPulse}{iModification,1};
            Field = PulseModifications{iPulse}{iModification,2};
            Increment = PulseModifications{iPulse}{iModification,3};
            FieldIndex = PulseModifications{iPulse}{iModification,4};
            % Write modifications to pulse structure
            if length(Increment) == 1 || (strcmp(Field,'Frequency') && size(Increment,1) == 1)
              if isempty(FieldIndex)
                Pulses{iPulse}.(Field) = Pulses{iPulse}.(Field) + Increment*(DimensionIndices(Dimension)-1);
              else
                if length(Increment) == 1
                  Pulses{iPulse}.(Field)(FieldIndex) = Pulses{iPulse}.(Field)(FieldIndex) + Increment*(DimensionIndices(Dimension)-1);
                else
                  Pulses{iPulse}.(Field)(FieldIndex) = Pulses{iPulse}.(Field)(FieldIndex) + Increment(DimensionIndices(Dimension));
                end
              end
            else
              if strcmp(Field,'Frequency')
                Pulses{iPulse}.(Field) = Pulses{iPulse}.(Field) + Increment(DimensionIndices(Dimension),:);
              else
                if isempty(FieldIndex)
                  Pulses{iPulse}.(Field) = Pulses{iPulse}.(Field) + Increment(DimensionIndices(Dimension));
                else
                  Pulses{iPulse}.(Field)(FieldIndex) = Pulses{iPulse}.(Field)(FieldIndex) + Increment(DimensionIndices(Dimension));
                end
              end
            end
            % Adapt indexing according to dimension
            Pulses{iPulse}.ArrayIndex(Dimension) = DimensionIndices(Dimension);
          end
          
          % Convert array into cell for indexing
          ArrayIndex = num2cell(Pulses{iPulse}.ArrayIndex);
                  
          Pulses{iPulse}.Frequency = Pulses{iPulse}.Frequency*1000; % GHz to MHz
          
          % Compute Wave form and store it
          for iPCstep = 1 : size(Pulses{iPulse}.PhaseCycle,1)
            Pulses{iPulse}.Phase = Pulses{iPulse}.Phase+Pulses{iPulse}.PhaseCycle(iPCstep,1);
            [t,IQ] = pulse(Pulses{iPulse});
            if IncludeResonator
              % if a resonator is present, the ringing duration of each pulse
              % needs to be stored in the vary structure too
              tOrig = t(end);
              [t,IQ] = resonator(t,IQ,Exp.mwFreq,Resonator.Arg1,Resonator.Arg2,Resonator.Arg3);
              Vary.Pulses{iPulse}.Ringing(ArrayIndex{:}) = t(end) - tOrig;
            end
            if FreqShift ~= 0
              Opt.dt = Exp.TimeStep;
              [~, IQ] = rfmixer(t,IQ,FreqShift,'IQshift',Opt);
            end
            % ... and stores it in the vary structure
            Vary.Pulses{iPulse}.IQs{ArrayIndex{:}}(iPCstep,:) = IQ;
          end
          
          Vary.Pulses{iPulse}.ts{ArrayIndex{:}} = t;
          
          Pulses{iPulse}.Frequency = Pulses{iPulse}.Frequency/1000; % MHz to GHz
          
        else
           % if user wants to change p1.IQ (user provided IQ)
          
          if IQindex < size(PulseModifications{iPulse},1)
            errMsg = ['It is not possible to combine changing pulse parameters with user defined IQ, please check your Dim input for Pulse ' (num2str(iPulse)) '.'];
            error(errMsg)
          end
 
          if size(PulseModifications{iPulse},1) == 1
            Dimension = PulseModifications{iPulse}{1,1};
            IndexToLoad = DimensionIndices(Dimension);
            IndexToSave = ones(length(DimensionIndices));
            IndexToSave(Dimension) = DimensionIndices(Dimension);
            ArrayIndex = num2cell(IndexToSave);
            
            UserIQ = Pulses{iPulse}.userIQ.IQ{IndexToLoad};
            
            tIQ = Pulses{iPulse}.userIQ.t{IndexToLoad};
          else
            IndexToLoad = ones(length(DimensionIndices));
            
            for iModification = 1 : size(PulseModifications{iPulse},1)
              Dimension = PulseModifications{iPulse}{iModification,1};
              IndexToLoad(Dimension) = DimensionIndices(Dimension);
            end
            ArrayIndex = num2cell(IndexToLoad);
            
            UserIQ = Pulses{iPulse}.userIQ.IQ{ArrayIndex{:}};
            
            tIQ = Pulses{iPulse}.userIQ.t{ArrayIndex{:}};
            
          end
          
          % get phase cycle
          nPhaseSteps = size(Pulses{iPulse}.PhaseCycle,1);
          [d1, d2] = size(UserIQ);
          
          % validate phase cycle
          if d1 ~= nPhaseSteps && d2 ~= nPhaseSteps
            errMsg = ['The dimensionality of the IQ signal provided for event ' num2str(iEvent) ' is not in agreement with the phasecycle for this pulse. For user-defined waveforms the array must contain all IQs.'];
            error(errMsg);
          elseif d2 == nPhaseSteps
            UserIQ =  UserIQ';
          end      
          
          % Shifts IQ of the pulse if necessary...
          ShiftedUserIQ = [];
          for iPhaseStep = 1 : nPhaseSteps
            Opt.dt = Exp.TimeStep;
            if IncludeResonator
              % if resonator is requested, pulses are elongated due to ringing.
              % the duration of ringing is stored in an additional field
              tOrig = tIQ(end);
              [tIQ,currentIQ] = resonator(tIQ,UserIQ(iPhaseStep,:),Exp.mwFreq,Resonator.Arg1,Resonator.Arg2,Resonator.Arg3);
              Vary.Pulses{iPulse}.Ringing(ArrayIndex{:}) = tIQ(end) - tOrig;
            else
              currentIQ = UserIQ(iPhaseStep,:);
            end
            [t, ShiftedUserIQ(iPhaseStep,:)] = rfmixer(tIQ,currentIQ,-Opt.FrameShift,'IQshift',Opt);
          end
          
          Vary.Pulses{iPulse}.IQs{ArrayIndex{:}} = ShiftedUserIQ;

          Vary.Pulses{iPulse}.ts{ArrayIndex{:}} = t;
          
        end

        % Write pulse length to EventLenghts
        if IncludeResonator
          EventLengths(Pulses{iPulse}.EventIndex) = t(end) - Vary.Pulses{iPulse}.Ringing(ArrayIndex{:});
        else
          EventLengths(Pulses{iPulse}.EventIndex) = t(end);
        end
      end
    end
    
    % ---------------------------------------------------------------------
    % Now we loop over all dimensions and load the delays from the
    % IncrementationTables
    %----------------------------------------------------------------------
    
    for iDimension = 1 : nDimensions
      % Check if IncrementationTable is not empty
      if ~IncrementationScheme && ~isempty(Vary.IncrementationTable{iDimension})
        % Find Events that are modified...
        ModifiedEvents = find(Vary.IncrementationTable{iDimension}(:,DimensionIndices(iDimension)));
        % ... and change them in EventLengths
        if ~isempty(ModifiedEvents)
          for i = 1 : length(ModifiedEvents)
            EventLengths(ModifiedEvents(i)) = EventLengths(ModifiedEvents(i)) + Vary.IncrementationTable{iDimension}(ModifiedEvents(i),DimensionIndices(iDimension));
          end
        end
      elseif IncrementationScheme
        % Find Events that are modified...
          ModifiedEvents = find(Vary.IncrementationTable(:,iDimension));
          if ~isempty(ModifiedEvents)
            for i = 1 : length(ModifiedEvents)
              EventLengths(ModifiedEvents(i)) = EventLengths(ModifiedEvents(i)) + Vary.IncrementationTable(ModifiedEvents(i),iDimension)*(DimensionIndices(iDimension)-1);
            end
          end
      end
    end
     
    % Reorder Sequence and check for pulse overlap
    [NewSequence, NewEventLengths] = s_reorder_events(EventLengths,isPulse);
    
    % Check if ringing from the resonator causes pulses to overlap, after
    % they have been reorderd
    if IncludeResonator
      for iPulse = 1 : nPulses
        % get position of the current pulse in the reordered sequence
        ThisEvent = find(NewSequence == PulseIndices(iPulse));
        % Get original Event number of the following event and if...
        if ThisEvent == length(NewSequence)
          break
        end
        FollowingEvent = NewSequence(ThisEvent+1);
        if strcmp(Events{FollowingEvent}.type,'pulse')
          %...the following event is a pulse, create an error
          error('When using a resonator, pulses need to be separated by inter pulse delays to accomodate for ringing from the resonator.')
        else
          %...else the duration of the ringing is being loaded...
          if ~isempty(Vary.Pulses{iPulse})
            Ringing = Vary.Pulses{iPulse}.Ringing(ArrayIndex{:});
          else
            Ringing = Events{PulseIndices(iPulse)}.Ringing;
          end
          %...and the following delay is shortened by the correspoding
          % length
          ShortenedDelay = NewEventLengths(ThisEvent+1) - Ringing;
          if ShortenedDelay < 0
            % if the delay is to short and now becomes negative, an error
            % is returned
            Msg = ['The delay ' num2str(FollowingEvent) ' is too short to accomodate for ringing of the preceeding pulse.'];
            error(Msg);
          end
        end
      end
    end

    % Assert that if events are being moved in the sequence, the values for
    % Detection and Relaxation are the same for events that are being
    % interchanged
    for iEvent = 1 : nEvents
      if Events{NewSequence(iEvent)}.Detection ~= Events{(iEvent)}.Detection
        MessagePart1 = ['Due to a moving pulse, the events ' num2str(iEvent) ' and ' num2str(NewSequence(iEvent))];
        MessagePart2 = ' are being interchanged, but they do not have the same setting with respect to detection.';
        Message = [MessagePart1 MessagePart2];
        error(Message);
      end
      if Events{NewSequence(iEvent)}.Relaxation ~= Events{(iEvent)}.Relaxation
        MessagePart1 = ['Due to a moving pulse, the events ' num2str(iEvent) ' and ' num2str(NewSequence(iEvent))];
        MessagePart2 = ' are being interchanged, but they do not have the same setting with respect to relaxation.';
        Message = [MessagePart1 MessagePart2];
        error(Message);
      end
    end
    
    % Increment Dimension index
    for d = nDimensions:-1:1
      if DimensionIndices(d) < Vary.Points(d)
        DimensionIndices(d) = DimensionIndices(d)+1;
        break;
      else
        DimensionIndices(d) = 1;
      end
    end
    
  end 
end

logmsg(1,'pulse sequence parsed successfully!');