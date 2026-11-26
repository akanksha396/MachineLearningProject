clc; clear;

%% =====================================================================
%  regressor_allTasks.m  (FINAL — ID-based, append-safe, build-only)
%
%  Builds HRF-convolved task regressors for all 6 paper tasks: WM (2),
%  GAMBLING (3), RELATIONAL (2), LANGUAGE (2), MOTOR (1), EMOTION (2)
%  = 12 regressors per subject total.
%
%  Skipping is done PER REGRESSOR, not per subject — so adding a new
%  condition to taskSpecs later will correctly fill in just the missing
%  piece for subjects who already have some regressors built.
%
%  Plotting is handled separately by plot_regressors.m — this script
%  only builds and saves.
%
%  Requires this subject's EV data (fMRI_EV_extraction_FINAL.m) to
%  already be saved in subALL before running this script.
% =====================================================================

matFile     = '/Users/garimabargujar/Documents/Garima100/data/RestTask3T/Unrelated100_RestTask.mat';
runInfoFile = '/Users/garimabargujar/Documents/Garima100/data/tfMRI_Concat_Runs.csv';

allsubIDs = [125525]
% EDIT — just the subject(s) you want to process THIS run
TR = 0.72;

%% Load data
load(matFile);
runInfo = readtable(runInfoFile, 'ReadVariableNames', false);
runInfo.Properties.VariableNames = {'RunName','StartVol','EndVol'};
hrf = spm_hrf(TR);

%% Task/regressor definitions (unchanged from your verified version)
taskSpecs = struct([]);

taskSpecs(1).taskName  = 'WM';
taskSpecs(1).taskField = 'WM';
taskSpecs(1).regressors = { ...
    {'0bk', {'X0bk_body','X0bk_faces','X0bk_places','X0bk_tools'}}, ...
    {'2bk', {'X2bk_body','X2bk_faces','X2bk_places','X2bk_tools'}} ...
};

taskSpecs(2).taskName  = 'GAMBLING';
taskSpecs(2).taskField = 'GAM';
taskSpecs(2).regressors = { ...
    {'Win_event',  {'Win_event'}}, ...
    {'Loss_event', {'Loss_event'}}, ...
    {'Neut_event', {'Neut_event'}} ...
};

taskSpecs(3).taskName  = 'RELATIONAL';
taskSpecs(3).taskField = 'REL';
taskSpecs(3).regressors = { ...
    {'Relation', {'Relation'}}, ...
    {'Match',    {'Match'}} ...
};

taskSpecs(4).taskName  = 'LANGUAGE';
taskSpecs(4).taskField = 'LAN';
taskSpecs(4).regressors = { ...
    {'Story', {'Story'}}, ...
    {'Math',  {'Math'}} ...
};

taskSpecs(5).taskName  = 'MOTOR';
taskSpecs(5).taskField = 'MOT';
taskSpecs(5).regressors = { ...
    {'AnyMovement', {'Lh','Rh','Lf','Rf','T','Cue'}} ...
};

taskSpecs(6).taskName  = 'EMOTION';
taskSpecs(6).taskField = 'EMO';
taskSpecs(6).regressors = { ...
    {'Fear', {'Fear'}}, ...
    {'Neut', {'Neut'}} ...
};

phases = {'RL','LR'};   % RL always precedes LR in the CSV/timeline

%% Main loop — subjects x tasks x regressors
for k = 1:length(allsubIDs)
    subIDstr = num2str(allsubIDs(k));

    % --- Find this subject's slot by ID ---
    sub = [];
    for i = 1:length(subALL)
        if isfield(subALL{i}, 'ID') && strcmp(subALL{i}.ID, subIDstr)
            sub = i;
            break;
        end
    end
    if isempty(sub)
        warning('Subject %s not found in subALL — run EV extraction for this subject first. Skipping.', subIDstr);
        continue;
    end
    if ~isfield(subALL{sub}, 'EV')
        warning('Subject %s has no EV data yet — run EV extraction first. Skipping.', subIDstr);
        continue;
    end

    fprintf('\n=== Subject %s (slot %d) ===\n', subIDstr, sub);

    for t = 1:length(taskSpecs)
        taskName  = taskSpecs(t).taskName;
        taskField = taskSpecs(t).taskField;
        regSpecs  = taskSpecs(t).regressors;

        taskRows = runInfo(contains(runInfo.RunName, taskName), :);
        taskRows = sortrows(taskRows, 'StartVol');
        if isempty(taskRows)
            warning('  [skip] Task %s not found in runInfo CSV', taskName);
            continue;
        end
        anchor     = taskRows.StartVol(1);
        numVolTask = sum(taskRows.EndVol - taskRows.StartVol + 1);
        fprintf('  %s-only combined timeline length: %d volumes\n', taskName, numVolTask);

        for r = 1:length(regSpecs)
            outputName = regSpecs{r}{1};
            conditions = regSpecs{r}{2};
            fieldName = sprintf('%s_%s', taskField, outputName);

            % --- Skip THIS SPECIFIC regressor only if already built ---
            if isfield(subALL{sub}, 'regressor') && isfield(subALL{sub}.regressor, fieldName)
                fprintf('    [%s / %s] already built — skipping.\n', taskField, outputName);
                continue;
            end

            boxcar = zeros(numVolTask, 1);

            for p = 1:length(phases)
                phase = phases{p};
                runName = sprintf('tfMRI_%s_%s', taskName, phase);

                rowIdx = strcmp(runInfo.RunName, runName);
                if ~any(rowIdx)
                    warning('    Run %s not found in CSV — skipping', runName);
                    continue;
                end
                globalStart = runInfo.StartVol(rowIdx);
                localStart  = globalStart - anchor + 1;

                if ~isfield(subALL{sub}.EV, taskField) || ~isfield(subALL{sub}.EV.(taskField), phase)
                    warning('    No EVs found for %s %s — skipping', taskField, phase);
                    continue;
                end

                for c = 1:length(conditions)
                    condName = conditions{c};
                    if ~isfield(subALL{sub}.EV.(taskField).(phase), condName)
                        warning('    %s not found for %s %s — skipping', condName, taskName, phase);
                        continue;
                    end
                    evData = subALL{sub}.EV.(taskField).(phase).(condName);

                    for row = 1:size(evData,1)
                        onset    = evData(row,1);
                        duration = evData(row,2);

                        volStart = round(onset / TR) + 1 + (localStart - 1);
                        volEnd   = round((onset + duration) / TR) + 1 + (localStart - 1);
                        volStart = max(volStart, 1);
                        volEnd   = min(volEnd, numVolTask);

                        boxcar(volStart:volEnd) = 1;
                    end
                end
            end

            fprintf('    [%s / %s] unique boxcar values: %s | active time: %.1f s\n', ...
                taskField, outputName, mat2str(unique(boxcar)'), sum(boxcar)*TR);

            regressor = conv(boxcar, hrf);
            regressor = regressor(1:numVolTask);

            subALL{sub}.boxcar.(fieldName)    = boxcar;
            subALL{sub}.regressor.(fieldName) = regressor;
            fprintf('    Saved as subALL{%d}.regressor.%s\n', sub, fieldName);
        end
    end

    save(matFile, 'subALL', '-append');
    fprintf('Subject %s: all task regressors built and saved.\n', subIDstr);
end

disp(' ');
disp('Regressor run complete for all requested subjects.');