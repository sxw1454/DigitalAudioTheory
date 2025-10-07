function bitcrusher_with_input(audio_input, fs_input)
    % BITCRUSHER_WITH_INPUT - Real-time bit-crusher with custom audio input
    % 
    % Usage:
    %   bitcrusher_with_input()                    % Use default sine wave
    %   bitcrusher_with_input(audio_data, fs)      % Use custom audio
    %   bitcrusher_with_input('filename.wav')      % Load from file
    
    % Clear workspace and close existing figures
    clear; clc; close all;
    
    % Handle different input types
    if nargin == 0
        % Default: generate sine wave
        fs = 44100;
        duration = 10;
        t = (0:1/fs:duration-1/fs)';
        f0 = 1000;
        source_audio = sin(2*pi*f0*t);
        source_audio = source_audio / max(abs(source_audio));
    elseif nargin == 1 && ischar(audio_input)
        % Load from file
        [source_audio, fs] = audioread(audio_input);
        % Convert to mono if stereo
        if size(source_audio, 2) > 1
            source_audio = mean(source_audio, 2);
        end
        % Normalize to [-1, 1]
        source_audio = source_audio / max(abs(source_audio));
    elseif nargin == 2
        % Use provided audio data
        source_audio = audio_input;
        fs = fs_input;
        % Convert to mono if stereo
        if size(source_audio, 2) > 1
            source_audio = mean(source_audio, 2);
        end
        % Normalize to [-1, 1]
        source_audio = source_audio / max(abs(source_audio));
    else
        error('Invalid input arguments. Use: bitcrusher_with_input(), bitcrusher_with_input(audio, fs), or bitcrusher_with_input(filename)');
    end
    
    % Ensure we have enough audio (pad with zeros if needed)
    min_duration = 1; % minimum 1 second
    if length(source_audio) < min_duration * fs
        source_audio = [source_audio; zeros(min_duration * fs - length(source_audio), 1)];
    end
    
    % Limit to 10 seconds max for performance
    max_samples = 10 * fs;
    if length(source_audio) > max_samples
        source_audio = source_audio(1:max_samples);
    end
    
    % Create time vector
    t = (0:1/fs:length(source_audio)/fs-1/fs)';
    
    % Initialize variables
    current_bit_depth = 16;
    dither_enabled = false;
    quantized_audio = source_audio;
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
    
    % Nested functions (same as before)
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
        % Create three subplots
        ax1 = subplot(3,1,1, 'Parent', fig);
        title('Bit Depth and Theoretical SNR');
        xlabel('Time (s)');
        ylabel('SNR (dB)');
        grid on;
        hold on;
        
        ax2 = subplot(3,1,2, 'Parent', fig);
        title('Measured SNR (from quantized audio)');
        xlabel('Time (s)');
        ylabel('SNR (dB)');
        grid on;
        hold on;
        
        ax3 = subplot(3,1,3, 'Parent', fig);
        title('Error Spectrogram');
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        colorbar;
        
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
            if isappdata(fig, 'audio_player')
                player = getappdata(fig, 'audio_player');
                stop(player);
            end
            src.Text = 'Play';
            is_playing = false;
        else
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
        bit_depth_slider = getappdata(fig, 'bit_depth_slider');
        bit_depth_label = getappdata(fig, 'bit_depth_label');
        ax1 = getappdata(fig, 'ax1');
        ax2 = getappdata(fig, 'ax2');
        ax3 = getappdata(fig, 'ax3');
        
        bit_depth_label.Text = sprintf('%d bits', current_bit_depth);
        
        quantized_audio = applyQuantization(source_audio, current_bit_depth, dither_enabled);
        
        theoretical_snr = 6.02 * current_bit_depth + 1.76;
        
        error_signal = source_audio - quantized_audio;
        signal_power = mean(source_audio.^2);
        error_power = mean(error_signal.^2);
        measured_snr = 10 * log10(signal_power / (error_power + eps));
        
        updatePlots(theoretical_snr, measured_snr, error_signal, t, fs);
    end
    
    function quantized = applyQuantization(signal, bit_depth, use_dither)
        q = 2 / (2^bit_depth - 1);
        
        if use_dither
            dither = (rand(size(signal)) - 0.5) + (rand(size(signal)) - 0.5);
            dither = dither * q;
            signal = signal + dither;
        end
        
        quantized = q * round(signal / q);
        quantized = max(-1, min(1, quantized));
    end
    
    function updatePlots(theoretical_snr, measured_snr, error_signal, time_vec, fs)
        ax1 = getappdata(fig, 'ax1');
        ax2 = getappdata(fig, 'ax2');
        ax3 = getappdata(fig, 'ax3');
        
        cla(ax1);
        cla(ax2);
        cla(ax3);
        
        plot(ax1, time_vec, repmat(theoretical_snr, size(time_vec)), 'b-', 'LineWidth', 2);
        title(ax1, sprintf('Bit Depth: %d bits, Theoretical SNR: %.1f dB', current_bit_depth, theoretical_snr));
        xlabel(ax1, 'Time (s)');
        ylabel(ax1, 'SNR (dB)');
        grid(ax1, 'on');
        ylim(ax1, [0, 150]);
        
        plot(ax2, time_vec, repmat(measured_snr, size(time_vec)), 'r-', 'LineWidth', 2);
        title(ax2, sprintf('Measured SNR: %.1f dB', measured_snr));
        xlabel(ax2, 'Time (s)');
        ylabel(ax2, 'SNR (dB)');
        grid(ax2, 'on');
        ylim(ax2, [0, 150]);
        
        window_length = round(0.1 * fs);
        overlap = round(0.5 * window_length);
        nfft = 2^nextpow2(window_length);
        
        [S, F, T] = spectrogram(error_signal, window_length, overlap, nfft, fs);
        S_db = 20 * log10(abs(S) + eps);
        S_db = max(S_db, -80);
        
        imagesc(ax3, T, F, S_db);
        title(ax3, 'Error Spectrogram (dB)');
        xlabel(ax3, 'Time (s)');
        ylabel(ax3, 'Frequency (Hz)');
        colorbar(ax3);
        colormap(ax3, 'jet');
        axis(ax3, 'xy');
        ylim(ax3, [0, fs/2]);
        
        drawnow;
    end
end