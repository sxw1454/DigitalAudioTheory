%% Example Usage of Bit Crusher with Audio Input
% This script demonstrates different ways to use the bit crusher

%% Method 1: Use with a WAV file
% Load an audio file and process it
filename = 'your_audio_file.wav';  % Replace with your file
if exist(filename, 'file')
    bitcrusher_with_input(filename);
else
    fprintf('File %s not found. Using default sine wave instead.\n', filename);
    bitcrusher_with_input();  % Fall back to default
end

%% Method 2: Use with audio data loaded in MATLAB
% Load audio data first
[audio_data, fs] = audioread('your_audio_file.wav');  % Replace with your file
bitcrusher_with_input(audio_data, fs);

%% Method 3: Generate custom audio in MATLAB
% Create a more complex test signal
fs = 44100;
duration = 5;
t = (0:1/fs:duration-1/fs)';

% Create a multi-tone signal
f1 = 440;   % A4
f2 = 880;   % A5
f3 = 1320;  % E6
custom_audio = 0.3 * sin(2*pi*f1*t) + 0.2 * sin(2*pi*f2*t) + 0.1 * sin(2*pi*f3*t);
custom_audio = custom_audio / max(abs(custom_audio));  % Normalize

% Use with bit crusher
bitcrusher_with_input(custom_audio, fs);

%% Method 4: Use with recorded audio
% If you have audio recorded in MATLAB
% [recorded_audio, fs] = audiorecorder(...);  % Your recording code
% bitcrusher_with_input(recorded_audio, fs);

%% Method 5: Use with audio from other sources
% Load from different file formats
% [audio_data, fs] = audioread('song.mp3');
% bitcrusher_with_input(audio_data, fs);