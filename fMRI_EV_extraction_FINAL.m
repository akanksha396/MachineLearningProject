clc; clear; close all;


data_path = '/Users/garimabargujar/Documents/Garima100/data/';
outFile   = '/Users/garimabargujar/Documents/Garima100/data/RestTask3T/Unrelated100_RestTask.mat';

allsubIDs = [125525];  

taskMap = containers.Map( ...
    {'EMOTION','GAMBLING','LANGUAGE','MOTOR','RELATIONAL','WM'}, ...
    {'EMO',    'GAM',     'LAN',     'MOT',  'REL',       'WM'});

taskNames = keys(taskMap);
phases = {'LR','RL'};

%% Load or initialize subALL
if exist(outFile, 'file')
    load(outFile);
else
    subALL = {};
end

%% Build a lookup of which subject IDs ALREADY have EV data stored
existingEvIDs = {};
for i = 1:length(subALL)
    if isfield(subALL{i}, 'ID') && isfield(subALL{i}, 'EV')
        existingEvIDs{end+1} = subALL{i}.ID; %#ok<SAGROW>
    end
end

for k = 1:length(allsubIDs)
    subID = allsubIDs(k);
    subIDstr = num2str(subID);

    if any(strcmp(existingEvIDs, subIDstr))
        fprintf('Subject %s already has EV data — skipping.\n', subIDstr);
        continue;
    end

    % --- Find this subject's slot by ID (created by the timeseries script) ---
    % If the timeseries script hasn't been run for this subject yet, this
    % EV script can still create a new slot for them on its own.
    sub = [];
    for i = 1:length(subALL)
        if isfield(subALL{i}, 'ID') && strcmp(subALL{i}.ID, subIDstr)
            sub = i;
            break;
        end
    end
    if isempty(sub)
        sub = length(subALL) + 1;
        subALL{sub}.ID = subIDstr;
    end

    fprintf('Subject %s (slot %d)\n', subIDstr, sub);

    for t = 1:length(taskNames)
        taskFull = taskNames{t};
        taskAbbrev = taskMap(taskFull);

        for p = 1:length(phases)
            phase = phases{p};

            evFolder = fullfile(data_path, subIDstr, 'MNINonLinear', 'Results', ...
                sprintf('tfMRI_%s_%s', taskFull, phase), 'EVs');

            if ~exist(evFolder, 'dir')
                fprintf('  [skip] %s %s — folder not found: %s\n', taskFull, phase, evFolder);
                continue;
            end

            txtFiles = dir(fullfile(evFolder, '*.txt'));
            if isempty(txtFiles)
                fprintf('  [skip] %s %s — no .txt files in EVs folder\n', taskFull, phase);
                continue;
            end

            for f = 1:length(txtFiles)
                fname = txtFiles(f).name;
                fpath = fullfile(evFolder, fname);

                [~, condName, ~] = fileparts(fname);
                condName = matlab.lang.makeValidName(condName);
                condName = [upper(condName(1)), condName(2:end)];

                try
                    data = readmatrix(fpath);
                catch
                    warning('Could not read %s — skipping', fpath);
                    continue;
                end

                subALL{sub}.EV.(taskAbbrev).(phase).(condName) = data;
                fprintf('    Stored EV.%s.%s.%s  [%d x %d]\n', taskAbbrev, phase, condName, size(data,1), size(data,2));
            end
        end
    end

    % Save after each subject, not just at the very end
    if exist(outFile, 'file')
        save(outFile, 'subALL', '-append');
    else
        save(outFile, 'subALL');
    end
    fprintf('Subject %s EV extraction complete and saved.\n\n', subIDstr);
end

disp('EV extraction run complete.');