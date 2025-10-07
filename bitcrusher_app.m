function bitcrusher_app
% bitcrusher_app
% Single-file MATLAB app: real-time bit-crusher with TPDF dither option,
% live plots (theoretical SNR, measured SNR, error spectrum), and playback.

  %-----------------------
  % Configuration / Source
  %-----------------------
  sampleRateHz = 44100;
  durationSeconds = 10.0;
  timeSeconds = (0:1/sampleRateHz:durationSeconds - 1/sampleRateHz).';

  % Construct a simple musical-ish test signal (normalized to [-1, +1])
  base = 0.7*sin(2*pi*220*timeSeconds) + 0.5*sin(2*pi*440*timeSeconds) ...
       + 0.3*sin(2*pi*660*timeSeconds) + 0.2*sin(2*pi*880*timeSeconds);
  % Gentle amplitude envelope for nicer playback
  env = 0.5*(1 - cos(2*pi*(0:length(timeSeconds)-1).'/(length(timeSeconds)-1)));
  sourceSignal = base .* env;
  sourceSignal = sourceSignal ./ max(1e-12, max(abs(sourceSignal)));

  %-----------------------
  % App State (shared)
  %-----------------------
  state.sampleRateHz = sampleRateHz;
  state.timeSeconds = timeSeconds;
  state.sourceSignal = sourceSignal;
  state.numBits = 16;                % default
  state.isDitherEnabled = false;     % default
  state.currentQuantizedBuffer = [];
  state.measuredSnrDb = NaN;
  state.player = [];
  state.debounceTimer = [];          % timer for debouncing heavy recompute

  %-----------------------
  % UI Creation
  %-----------------------
  fig = uifigure('Name','Bit Crusher','Position',[100 100 980 720]);
  movegui(fig, 'center');

  % Controls
  bitsLabel = uilabel(fig, 'Text','Bit depth (4–24):', 'Position',[30 680 120 22]);

  bitsSlider = uislider(fig, ...
    'Limits',[4 24], ...
    'Value', state.numBits, ...
    'MajorTicks', 4:1:24, ...
    'MinorTicks', [], ...
    'Position',[160 690 520 3]);
  
  bitsValueLabel = uilabel(fig, 'Text', sprintf('%d', state.numBits), ...
    'HorizontalAlignment','left', 'Position',[690 680 50 22]);

  ditherCheckbox = uicheckbox(fig, 'Text','TPDF Dither', ...
    'Value', state.isDitherEnabled, 'Position',[760 680 120 22]);

  playToggle = uitogglebutton(fig, 'Text','Play', 'Position',[880 680 70 24]);

  % Axes: Top (theoretical SNR text), Middle (measured SNR text), Bottom (error spectrum)
  axTop = uiaxes(fig, 'Position',[60 510 860 140]);
  axMid = uiaxes(fig, 'Position',[60 340 860 140]);
  axBot = uiaxes(fig, 'Position',[60 60 860 260]);

  % Pre-style top & middle axes as text panels
  configureTextPanelAxes(axTop);
  configureTextPanelAxes(axMid);
  topText = text(axTop, 0.5, 0.5, '', 'HorizontalAlignment','center', 'FontSize',16);
  midText = text(axMid, 0.5, 0.5, '', 'HorizontalAlignment','center', 'FontSize',16);

  % Bottom axis styling (error spectrum)
  title(axBot, 'Quantization Error Spectrum (Welch PSD)');
  xlabel(axBot, 'Frequency (Hz)'); ylabel(axBot, 'Magnitude (dB)');
  grid(axBot, 'on');
  hold(axBot, 'on');
  errorLine = plot(axBot, NaN, NaN, 'LineWidth', 1.2);
  
  % Fix axis limits for responsiveness (adjust as desired)
  xlim(axBot, [0 state.sampleRateHz/2]);
  ylim(axBot, [-140 0]);

  % Install callbacks & debounce timer
  bitsSlider.ValueChangingFcn = @(src,evt) onBitsValueChanging(evt);
  bitsSlider.ValueChangedFcn  = @(src,evt) onBitsValueChanged();
  ditherCheckbox.ValueChangedFcn = @(src,evt) onDitherToggled();
  playToggle.ValueChangedFcn = @(src,evt) onPlayToggled();

  state.debounceTimer = timer('ExecutionMode','singleShot', ...
                              'StartDelay',0.15, ...
                              'TimerFcn',@(~,~) heavyRecomputeAndRefresh());

  % Ensure cleanup when app closes
  fig.CloseRequestFcn = @(src,evt) onCloseRequest();

  % Initial compute + draw
  updateTopPanelText();
  heavyRecomputeAndRefresh();

  % Keep state accessible in figure appdata
  setappdata(fig, 'state', state);

  %========================
  % Nested helper functions
  %========================
  function s = getState()
    s = getappdata(fig, 'state');
  end

  function setState(s)
    setappdata(fig, 'state', s);
  end

  function configureTextPanelAxes(ax)
    ax.XLim = [0 1]; ax.YLim = [0 1];
    ax.XTick = []; ax.YTick = [];
    ax.Box = 'on';
  end

  function onBitsValueChanging(evt)
    % Update displayed integer bits and theoretical SNR as the slider moves.
    s = getState();
    s.numBits = max(4, min(24, round(evt.Value)));
    setState(s);
    bitsSlider.Value = s.numBits; % snap visually
    bitsValueLabel.Text = sprintf('%d', s.numBits);
    updateTopPanelText();

    % Light debounce for heavy recompute
    restartDebounceTimer();
  end

  function onBitsValueChanged()
    % Commit integer value and do heavy recompute now
    s = getState();
    s.numBits = max(4, min(24, round(bitsSlider.Value)));
    setState(s);
    bitsSlider.Value = s.numBits;
    bitsValueLabel.Text = sprintf('%d', s.numBits);
    updateTopPanelText();
    heavyRecomputeAndRefresh();
  end

  function onDitherToggled()
    s = getState();
    s.isDitherEnabled = logical(ditherCheckbox.Value);
    setState(s);
    heavyRecomputeAndRefresh();

    % If currently playing, rebuild and restart playback to reflect new buffer
    s = getState();
    if ~isempty(s.player) && isvalid(s.player)
      if strcmp(get(s.player,'Running'), 'on')
        stop(s.player);
        startPlayback();
      end
    end
  end

  function onPlayToggled()
    s = getState();
    if playToggle.Value
      playToggle.Text = 'Stop';
      startPlayback();
    else
      playToggle.Text = 'Play';
      if ~isempty(s.player) && isvalid(s.player)
        stop(s.player);
      end
    end
  end

  function startPlayback()
    s = getState();
    % Ensure we have a current quantized buffer
    if isempty(s.currentQuantizedBuffer)
      [xq, ~] = quantizeSignal(s.sourceSignal, s.numBits, s.isDitherEnabled);
      s.currentQuantizedBuffer = xq;
      [measuredDb, ~] = computeMeasuredSnrDb(s.sourceSignal, xq);
      s.measuredSnrDb = measuredDb;
      setState(s);
      updateMiddlePanelText();
      updateBottomSpectrum();
    end

    % Build audioplayer and start
    if ~isempty(s.player) && isvalid(s.player)
      try, stop(s.player); catch, end
    end
    player = audioplayer(s.currentQuantizedBuffer, s.sampleRateHz);
    player.StopFcn = @(~,~) onPlaybackStopped();
    s.player = player;
    setState(s);
    play(player);
  end

  function onPlaybackStopped()
    % Reset toggle text/state when playback ends
    if isvalid(fig)
      playToggle.Value = false;
      playToggle.Text = 'Play';
    end
  end

  function restartDebounceTimer()
    s = getState();
    try
      if strcmp(s.debounceTimer.Running, 'on')
        stop(s.debounceTimer);
      end
      start(s.debounceTimer);
    catch
      % Timer may not be initialized yet or figure closing; ignore
    end
  end

  function updateTopPanelText()
    s = getState();
    theoryDb = theoreticalSnrDb(s.numBits);
    topText.String = sprintf('Bit depth: %d bits  |  Theoretical SNR: %.2f dB', ...
                             s.numBits, theoryDb);
  end

  function updateMiddlePanelText()
    s = getState();
    if isfinite(s.measuredSnrDb)
      midText.String = sprintf('Measured SNR: %.2f dB', s.measuredSnrDb);
    else
      midText.String = 'Measured SNR: Inf dB';
    end
  end

  function updateBottomSpectrum()
    s = getState();
    if isempty(s.currentQuantizedBuffer)
      set(errorLine, 'XData', NaN, 'YData', NaN);
      return;
    end
    errSignal = s.sourceSignal - s.currentQuantizedBuffer;

    % Welch PSD for error spectrum
    windowLength = 2048;
    overlapLength = round(0.5 * windowLength);
    nFft = 4096;
    [pxx, fHz] = pwelch(errSignal, hamming(windowLength,'periodic'), ...
                        overlapLength, nFft, s.sampleRateHz);
    pxxDb = 10*log10(pxx + 1e-20);

    set(errorLine, 'XData', fHz, 'YData', pxxDb);
    xlim(axBot, [0 s.sampleRateHz/2]);
    % Keep fixed Y limits as configured in UI creation
  end

  function heavyRecomputeAndRefresh()
    s = getState();
    [xq, ~] = quantizeSignal(s.sourceSignal, s.numBits, s.isDitherEnabled);
    s.currentQuantizedBuffer = xq;
    [measuredDb, ~] = computeMeasuredSnrDb(s.sourceSignal, xq);
    s.measuredSnrDb = measuredDb;
    setState(s);

    updateMiddlePanelText();
    updateBottomSpectrum();

    % If currently playing, restart with new buffer to reflect current settings
    s = getState();
    if ~isempty(s.player) && isvalid(s.player)
      if strcmp(get(s.player,'Running'), 'on')
        stop(s.player);
        startPlayback();
      end
    end
  end

  function onCloseRequest()
    % Cleanup resources
    s = getState();
    try
      if ~isempty(s.player) && isvalid(s.player)
        stop(s.player);
        delete(s.player);
      end
    catch
    end
    try
      if ~isempty(s.debounceTimer) && isvalid(s.debounceTimer)
        stop(s.debounceTimer);
        delete(s.debounceTimer);
      end
    catch
    end
    delete(fig);
  end

  %-----------------------
  % DSP helpers
  %-----------------------
  function [xQuantized, qStep] = quantizeSignal(x, numBits, enableDither)
    % Mid-tread uniform quantizer: y = q * round(x / q), q = 2 / 2^N
    qStep = 2 / (2^numBits);
    if enableDither
      ditherNoise = ((rand(size(x)) - 0.5) + (rand(size(x)) - 0.5)) * qStep; % TPDF
      xWork = x + ditherNoise;
    else
      xWork = x;
    end
    xQuantized = qStep * round(xWork / qStep);
    xQuantized = max(-1, min(1, xQuantized));
  end

  function snrDb = theoreticalSnrDb(numBits)
    % Ideal full-scale sine quantization SNR
    snrDb = 6.02 * numBits + 1.76;
  end

  function [measuredDb, errRms] = computeMeasuredSnrDb(x, xq)
    err = x - xq;
    xRms = sqrt(mean(x.^2));
    errRms = sqrt(mean(err.^2));
    if errRms <= eps
      measuredDb = Inf;
    else
      measuredDb = 20 * log10(xRms / errRms);
    end
  end
end
