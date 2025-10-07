function bitcrusher()
    % BITCRUSHER - Real-time bit-crusher with dithering
    % Creates a GUI for real-time audio bit-depth reduction with TPDF dithering
    
    % Clear workspace and close existing figures
    clear; clc; close all;
    
    % Audio parameters
    fs = 44100;           % Sample rate
    duration = 10;        % Duration in seconds
    t = (0:1/fs:duration-1/fs)';  % Time vector
    
    % Generate 10-second source tone (sine wave at 1 kHz, normalized to [-1, +1])
    f0 = 1000;  % Frequency in Hz
    source_audio = sin(2*pi*f0*t);
    source_audio = source_audio / max(abs(source_audio));  % Normalize to [-1, +1]
    
    % Initialize variables
    current_bit_depth = 16;  % Default bit depth
    dither_enabled = false;  % Default dither state
    quantized_audio = source_audio;  % Initialize with source
    is_playing = false;
    
    % Create main figure
    fig = uifigure('Name', 'Real-time Bit Crusher', ...
                   'Position', [100, 100, 800, 600], ...
                   'Resize', 'off');
    
    % Create UI components
    createUI(fig);
    
    % Initialize plots
    initializePlots();
    
    % Update display with initial values
    updateDisplay();
    
    % Nested functions
    function createUI(parent)
        % Bit depth slider
        uilabel(parent, 'Text', 'Bit Depth:', 'Position', [20, 550, 80, 20]);
        bit_depth_slider = uislider(parent, ...
            'Position', [100, 550, 200, 3], ...
            'Limits', [4, 24], ...
            'Value', current_bit_depth, ...
            'MajorTicks', 4:2:24, ...
            'MajorTickLabels', {'4', '6', '8', '10', '12', '14', '16', '18', '20', '22', '24'}, ...
            'ValueChangedFcn', @onBitDepthChanged);
        
        % Bit depth value display
        bit_depth_label = uilabel(parent, 'Text', sprintf('%d bits', current_bit_depth), ...
            'Position', [310, 550, 60, 20]);
        
        % Dither checkbox
        dither_checkbox = uicheckbox(parent, ...
            'Text', 'Enable TPDF Dither', ...
            'Position', [20, 520, 150, 20], ...
            'Value', dither_enabled, ...
            'ValueChangedFcn', @onDitherChanged);
        
        % Play/Stop button
        play_button = uibutton(parent, ...
            'Text', 'Play', ...
            'Position', [200, 520, 80, 30], ...
            'ButtonPushedFcn', @onPlayStop);
        
        % Store handles for later use
        setappdata(fig, 'bit_depth_slider', bit_depth_slider);
        setappdata(fig, 'bit_depth_label', bit_depth_label);
        setappdata(fig, 'dither_checkbox', dither_checkbox);
        setappdata(fig, 'play_button', play_button);
    end
    
    function initializePlots()
        % Create three uiaxes for plotting in uifigure
        ax1 = uiaxes(fig, 'Position', [20, 350, 750, 120]);
        title(ax1, 'Bit Depth and Theoretical SNR');
        xlabel(ax1, 'Time (s)');
        ylabel(ax1, 'SNR (dB)');
        grid(ax1, 'on');
        hold(ax1, 'on');
        
        ax2 = uiaxes(fig, 'Position', [20, 220, 750, 120]);
        title(ax2, 'Measured SNR (from quantized audio)');
        xlabel(ax2, 'Time (s)');
        ylabel(ax2, 'SNR (dB)');
        grid(ax2, 'on');
        hold(ax2, 'on');
        
        ax3 = uiaxes(fig, 'Position', [20, 20, 750, 190]);
        title(ax3, 'Error Spectrogram');
        xlabel(ax3, 'Time (s)');
        ylabel(ax3, 'Frequency (Hz)');
        
        setappdata(fig, 'ax1', ax1);
        setappdata(fig, 'ax2', ax2);
        setappdata(fig, 'ax3', ax3);
    end
    
    function onBitDepthChanged(src, ~)
        current_bit_depth = round(src.Value);
        updateDisplay();
    end
    
    function onDitherChanged(src, ~)
        dither_enabled = src.Value;
        updateDisplay();
    end
    
    function onPlayStop(src, ~)
        if is_playing
            % Stop playback
            if isappdata(fig, 'audio_player')
                player = getappdata(fig, 'audio_player');
                stop(player);
            end
            src.Text = 'Play';
            is_playing = false;
        else
            % Start playback
            if isappdata(fig, 'audio_player')
                player = getappdata(fig, 'audio_player');
                stop(player);
            end
            
            player = audioplayer(quantized_audio, fs);
            setappdata(fig, 'audio_player', player);
            play(player);
            src.Text = 'Stop';
            is_playing = true;
        end
    end
    
    function updateDisplay()
        % Get UI handles
        bit_depth_slider = getappdata(fig, 'bit_depth_slider');
        bit_depth_label = getappdata(fig, 'bit_depth_label');
        ax1 = getappdata(fig, 'ax1');
        ax2 = getappdata(fig, 'ax2');
        ax3 = getappdata(fig, 'ax3');
        
        % Update bit depth display
        bit_depth_label.Text = sprintf('%d bits', current_bit_depth);
        
        % Apply quantization
        quantized_audio = applyQuantization(source_audio, current_bit_depth, dither_enabled);
        
        % Calculate theoretical SNR
        theoretical_snr = 6.02 * current_bit_depth + 1.76;  % dB
        
        % Calculate measured SNR
        error_signal = source_audio - quantized_audio;
        signal_power = mean(source_audio.^2);
        error_power = mean(error_signal.^2);
        measured_snr = 10 * log10(signal_power / (error_power + eps));  % Add eps to avoid log(0)
        
        % Update plots
        updatePlots(theoretical_snr, measured_snr, error_signal, t, fs);
    end
    
    function quantized = applyQuantization(signal, bit_depth, use_dither)
        % Apply mid-tread quantization with optional TPDF dithering
        
        % Calculate quantization step
        q = 2 / (2^bit_depth - 1);
        
        if use_dither
            % Add TPDF dither: d = (rand1 - 0.5) + (rand2 - 0.5)
            dither = (rand(size(signal)) - 0.5) + (rand(size(signal)) - 0.5);
            dither = dither * q;  % Scale dither to quantization step
            signal = signal + dither;
        end
        
        % Apply mid-tread quantization
        quantized = q * round(signal / q);
        
        % Clamp to [-1, 1] range
        quantized = max(-1, min(1, quantized));
    end
    
    function updatePlots(theoretical_snr, measured_snr, error_signal, time_vec, fs)
        % Update the three plots
        
        % Get plot handles
        ax1 = getappdata(fig, 'ax1');
        ax2 = getappdata(fig, 'ax2');
        ax3 = getappdata(fig, 'ax3');
        
        % Clear plots
        cla(ax1);
        cla(ax2);
        cla(ax3);
        
        % Plot 1: Theoretical SNR (constant line)
        plot(ax1, time_vec, repmat(theoretical_snr, size(time_vec)), 'b-', 'LineWidth', 2);
        title(ax1, sprintf('Bit Depth: %d bits, Theoretical SNR: %.1f dB', current_bit_depth, theoretical_snr));
        xlabel(ax1, 'Time (s)');
        ylabel(ax1, 'SNR (dB)');
        grid(ax1, 'on');
        ylim(ax1, [0, 150]);
        
        % Plot 2: Measured SNR (constant line)
        plot(ax2, time_vec, repmat(measured_snr, size(time_vec)), 'r-', 'LineWidth', 2);
        title(ax2, sprintf('Measured SNR: %.1f dB', measured_snr));
        xlabel(ax2, 'Time (s)');
        ylabel(ax2, 'SNR (dB)');
        grid(ax2, 'on');
        ylim(ax2, [0, 150]);
        
        % Plot 3: Error spectrogram
        % Use short-time Fourier transform for spectrogram
        window_length = round(0.1 * fs);  % 100ms windows
        overlap = round(0.5 * window_length);  % 50% overlap
        nfft = 2^nextpow2(window_length);
        
        [S, F, T] = spectrogram(error_signal, window_length, overlap, nfft, fs);
        
        % Convert to dB with floor
        S_db = 20 * log10(abs(S) + eps);
        S_db = max(S_db, -80);  % Floor at -80 dB
        
        imagesc(ax3, T, F, S_db);
        title(ax3, 'Error Spectrogram (dB)');
        xlabel(ax3, 'Time (s)');
        ylabel(ax3, 'Frequency (Hz)');
        colormap(ax3, 'jet');
        axis(ax3, 'xy');
        ylim(ax3, [0, fs/2]);
        
        % Add colorbar to the right of the spectrogram
        c = colorbar(ax3);
        c.Position = [0.95, 0.03, 0.02, 0.8];
        
        % Force update
        drawnow;
    end
end