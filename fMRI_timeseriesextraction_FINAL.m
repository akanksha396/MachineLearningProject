clc; clear all; close all;


data_path       = '/Users/garimabargujar/Documents/Garima100/data/';
allsubdata_path = '/Users/garimabargujar/Documents/Garima100/data/RestTask3T/';
atlas_path      = '/Users/garimabargujar/Documents/Garima100/atlas/';

allsubIDs = [125525];   

matFile = [allsubdata_path, 'Unrelated100_RestTask.mat'];
if exist(matFile, 'file')
    load(matFile);
else
    subALL = {};
end


existingIDs = {};
for i = 1:length(subALL)
    if isfield(subALL{i}, 'ID')
        existingIDs{end+1} = subALL{i}.ID; 
    end
end

for k = 1:length(allsubIDs)
    subID = allsubIDs(k);
    subIDstr = num2str(subID);

    % --- Skip if this subject is already fully stored ---
    if any(strcmp(existingIDs, subIDstr))
        fprintf('Subject %s already present in subALL — skipping.\n', subIDstr);
        continue;
    end

    % --- New subject: append to the NEXT available slot ---
    sub = length(subALL) + 1;
    fprintf('Processing subject %s (storing as subALL{%d})\n', subIDstr, sub);

    %% ZIP unpacking
    unzipsave = 1;
    if unzipsave == 1
        for rt = 1:2
            if rt == 1
                zipFolder = strcat(data_path, subIDstr, '_Rest3TRecommended.zip');
            else
                zipFolder = strcat(data_path, subIDstr, '_Task3TRecommended.zip');
            end

            if ~exist(zipFolder, 'file')
                error('Zip file not found: %s — download it before running this script.', zipFolder);
            end

            tempFolder = tempname;
            mkdir(tempFolder);
            checkfiles = unzip(zipFolder, tempFolder);

            if rt == 1
                gzPath = checkfiles{endsWith(checkfiles, 'rfMRI_REST_hp2000_clean_rclean_tclean.nii.gz')};
            else
                gzPath = checkfiles{endsWith(checkfiles, 'tfMRI_Concat_hp0_clean_rclean_tclean.nii.gz')};
            end

            % OS-level gunzip (MATLAB's built-in gunzip.m was corrupted on this machine)
            [gunzipStatus, gunzipOut] = system(sprintf('gunzip -k -f "%s"', gzPath));
            if gunzipStatus ~= 0
                error('System gunzip failed on %s:\n%s', gzPath, gunzipOut);
            end

            niiFile = erase(gzPath, '.gz');
            [~, name, ext] = fileparts(niiFile);
            outFile = fullfile(allsubdata_path, sprintf('%d_%s%s', subID, name, ext));
            copyfile(niiFile, outFile);

            if exist(tempFolder, 'dir')
                rmdir(tempFolder, 's');
            end
        end
    end

    subALL{sub}.ID = subIDstr;

    %% Extract Rest ROI timeseries
    disp('Extracting Rest ROI ts...')
    restniifilename = strcat(allsubdata_path, subIDstr, '_rfMRI_REST_hp2000_clean_rclean_tclean.nii');
    Vrest = spm_vol(restniifilename);
    numVolrest = length(Vrest);

    subcatlasfile = [atlas_path, 'Tian_Subcortex_S4_3T.nii'];
    subcVa = spm_vol(subcatlasfile); subcIa = spm_read_vols(subcVa);
    cortatlasfile = [atlas_path, 'Schaefer2018_100Parcels_7Networks_order_FSLMNI152_2mm.nii'];  % 100 parcels, as confirmed
    cortVa = spm_vol(cortatlasfile); cortIa = spm_read_vols(cortVa);
    cerbatlasfile = [atlas_path, 'Cer_26ROI.nii'];
    cerbVa = spm_vol(cerbatlasfile); cerbIa = spm_read_vols(cerbVa);

    numROI = 100 + 54 + 26; % 180

    roiLabel = zeros(size(subcIa));
    for roi = 1:numROI
        if roi <= 54
            mask = (subcIa == roi);
        elseif roi >= 55 && roi <= 154
            mask = (cortIa == (roi-54));
        else
            mask = (cerbIa == (roi-154));
        end
        roiLabel(mask) = roi;
    end
    roiLabelVec = roiLabel(:);
    validIdx = roiLabelVec > 0;
    roiIdxValid = roiLabelVec(validIdx);

    Mean_ROIts = zeros(numVolrest, numROI);
    for v = 1:numVolrest
        vol = spm_read_vols(Vrest(v));
        volVec = vol(:);
        Mean_ROIts(v,:) = accumarray(roiIdxValid, volVec(validIdx), [numROI,1], @(x) mean(x(isfinite(x))))';
    end

    subALL{sub}.rest.Mean_ROIts = Mean_ROIts;

    % --- VALIDATION: check the extracted data is actually usable ---
    validateROIts(Mean_ROIts, numROI, numVolrest, 'Rest', subIDstr);

    save(matFile, 'subALL', '-append');
    fprintf('  Rest extraction done and saved.\n');

    %% Extract Task ROI timeseries
    disp('Extracting Task ROI ts...')
    taskniifilename = strcat(allsubdata_path, subIDstr, '_tfMRI_Concat_hp0_clean_rclean_tclean.nii');
    Vtask = spm_vol(taskniifilename);
    numVoltask = length(Vtask);

    Mean_ROIts = zeros(numVoltask, numROI);
    for v = 1:numVoltask
        vol = spm_read_vols(Vtask(v));
        volVec = vol(:);
        Mean_ROIts(v,:) = accumarray(roiIdxValid, volVec(validIdx), [numROI,1], @(x) mean(x(isfinite(x))))';
    end

    subALL{sub}.task.Mean_ROIts = Mean_ROIts;

    % --- VALIDATION: check the extracted data is actually usable ---
    validateROIts(Mean_ROIts, numROI, numVoltask, 'Task', subIDstr);

    save(matFile, 'subALL', '-append');
    fprintf('  Task extraction done and saved.\n');

    fprintf('Subject %s complete.\n\n', subIDstr);
end

disp('Timeseries extraction run complete.');


%% ===================== LOCAL FUNCTION (must be at the end of the file) =====================
function validateROIts(Mean_ROIts, numROI, numVol, label, subIDstr)
    % Checks the extracted ROI timeseries is actually usable before trusting it.
    ok = true;

    % 1. Correct dimensions
    if ~isequal(size(Mean_ROIts), [numVol, numROI])
        warning('  [%s VALIDATION] %s: size mismatch — expected [%d x %d], got [%d x %d]', ...
            subIDstr, label, numVol, numROI, size(Mean_ROIts,1), size(Mean_ROIts,2));
        ok = false;
    end

    % 2. No ROI (column) should be ENTIRELY NaN across all volumes —
    %    that would mean that ROI had zero valid voxels the whole time,
    %    which likely signals an atlas/mask problem, not normal data.
    fullyNaNcols = find(all(isnan(Mean_ROIts), 1));
    if ~isempty(fullyNaNcols)
        warning('  [%s VALIDATION] %s: ROI(s) [%s] are entirely NaN across all volumes — check atlas alignment', ...
            subIDstr, label, mat2str(fullyNaNcols));
        ok = false;
    end

    % 3. No -Inf/Inf should remain (the isfinite() filter in averaging
    %    should have already excluded these voxel-by-voxel, but this
    %    confirms nothing slipped through)
    if any(isinf(Mean_ROIts(:)))
        warning('  [%s VALIDATION] %s: Inf/-Inf values found in final data — investigate before trusting this subject', ...
            subIDstr, label);
        ok = false;
    end

    % 4. Overall NaN rate — a FEW NaNs can be normal (e.g. an ROI with very
    %    few valid voxels on one volume), but a high rate is worth flagging
    nanRate = sum(isnan(Mean_ROIts(:))) / numel(Mean_ROIts) * 100;
    if nanRate > 1
        warning('  [%s VALIDATION] %s: %.2f%% of values are NaN — higher than expected, worth checking', ...
            subIDstr, label, nanRate);
        ok = false;
    end

    if ok
        fprintf('  [%s VALIDATION] %s: passed all checks (size OK, no fully-NaN ROIs, no Inf, NaN rate %.3f%%)\n', ...
            subIDstr, label, nanRate);
    end
end