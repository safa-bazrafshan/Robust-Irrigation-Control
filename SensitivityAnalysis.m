%% ============================================================
% 02_V3_SensitivityAnalysis
%
% Sensitivity Analysis Preparation for V3 Soil-Water Model
%
% Purpose:
%   Identify the physical parameters used by the validated V3
%   soil-water model and prepare a one-at-a-time sensitivity
%   analysis framework.
%
% IMPORTANT:
%   This script does NOT modify the validated V3 model.
%
%   Before performing scientific sensitivity analysis, the
%   parameter structure must be explicitly available.
%
% ============================================================

clc;
clear;
close all;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 PARAMETER SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');

%% ============================================================
% 1. Result File
% =============================================================

resultFile = ...
    '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(resultFile)

    error([ ...
        '\nResult file not found:\n', ...
        '%s\n\n', ...
        'Place the validated V3 result file in the main ', ...
        'AI_Smart_Irrigation folder.\n'], ...
        resultFile);

end

%% ============================================================
% 2. Inspect MAT-File
% =============================================================

fprintf('\n');
fprintf('Loading V3 result file...\n');
fprintf('%s\n', resultFile);

fileInfo = whos('-file', resultFile);

fprintf('\n');
fprintf('Variables stored in V3 result file:\n');
fprintf('----------------------------------------------------\n');

for k = 1:length(fileInfo)

    fprintf('%-30s %s\n', ...
        fileInfo(k).name, ...
        fileInfo(k).class);

end

%% ============================================================
% 3. Load Results
% =============================================================

data = load(resultFile);

variableNames = fieldnames(data);

fprintf('\n');
fprintf('Top-level variables detected:\n');
fprintf('----------------------------------------------------\n');

for k = 1:length(variableNames)

    name = variableNames{k};

    value = data.(name);

    fprintf('\nVariable: %s\n', name);

    if isstruct(value)

        fprintf('Type: STRUCT\n');

        fields = fieldnames(value);

        fprintf('Fields:\n');

        for j = 1:length(fields)

            fieldName = fields{j};

            fieldValue = value.(fieldName);

            fprintf('   %-30s ', fieldName);

            if isnumeric(fieldValue)

                fprintf( ...
                    'numeric [%s]\n', ...
                    mat2str(size(fieldValue)));

            elseif ischar(fieldValue)

                fprintf('char\n');

            elseif isstring(fieldValue)

                fprintf('string\n');

            elseif islogical(fieldValue)

                fprintf( ...
                    'logical [%s]\n', ...
                    mat2str(size(fieldValue)));

            else

                fprintf('%s\n', ...
                    class(fieldValue));

            end

        end

    elseif isnumeric(value)

        fprintf( ...
            'Type: numeric [%s]\n', ...
            mat2str(size(value)));

    else

        fprintf('Type: %s\n', ...
            class(value));

    end

end

%% ============================================================
% 4. Search for Parameter Containers
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SEARCHING FOR MODEL PARAMETERS\n');
fprintf('====================================================\n');

parameterCandidates = {};

for k = 1:length(variableNames)

    name = variableNames{k};

    value = data.(name);

    if isstruct(value)

        fields = fieldnames(value);

        for j = 1:length(fields)

            fieldName = fields{j};

            fieldValue = value.(fieldName);

            if isnumeric(fieldValue) && ...
                    isscalar(fieldValue)

                parameterCandidates{end+1,1} = ...
                    [name, '.', fieldName];

            end

        end

    elseif isnumeric(value) && ...
            isscalar(value)

        parameterCandidates{end+1,1} = name;

    end

end

fprintf('\n');
fprintf('Scalar numeric parameters detected:\n');
fprintf('----------------------------------------------------\n');

if isempty(parameterCandidates)

    fprintf('NONE\n');

else

    for k = 1:length(parameterCandidates)

        fprintf('%3d. %s\n', ...
            k, ...
            parameterCandidates{k});

    end

end

%% ============================================================
% 5. Known Physical Parameter Keywords
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' PHYSICAL PARAMETER CANDIDATE SEARCH\n');
fprintf('====================================================\n');

keywords = { ...
    'theta_r', ...
    'theta_s', ...
    'theta_fc', ...
    'theta_wp', ...
    'theta_field', ...
    'ks', ...
    'K_s', ...
    'k12', ...
    'k23', ...
    'kd', ...
    'drainage', ...
    'conductivity', ...
    'ET', ...
    'evapotranspiration', ...
    'root', ...
    'layer'};

physicalCandidates = {};

for k = 1:length(parameterCandidates)

    candidate = parameterCandidates{k};

    candidateLower = lower(candidate);

    matched = false;

    for j = 1:length(keywords)

        keywordLower = lower(keywords{j});

        if contains(candidateLower, keywordLower)

            matched = true;

            break;

        end

    end

    if matched

        physicalCandidates{end+1,1} = ...
            candidate;

    end

end

fprintf('\n');

if isempty(physicalCandidates)

    fprintf('No obvious physical parameters were detected.\n');

else

    fprintf('Potential physical parameters:\n');
    fprintf('----------------------------------------------------\n');

    for k = 1:length(physicalCandidates)

        fprintf('%3d. %s\n', ...
            k, ...
            physicalCandidates{k});

    end

end

%% ============================================================
% 6. Sensitivity Analysis Design
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SENSITIVITY ANALYSIS DESIGN\n');
fprintf('====================================================\n');

fprintf('\n');
fprintf('The following analysis structure will be used:\n\n');

fprintf('Baseline parameter:\n');
fprintf('       p0\n\n');

fprintf('Perturbed values:\n');
fprintf('       0.80 p0\n');
fprintf('       0.90 p0\n');
fprintf('       1.00 p0\n');
fprintf('       1.10 p0\n');
fprintf('       1.20 p0\n\n');

fprintf('For each parameter we will evaluate:\n\n');

fprintf('1. Mean soil moisture\n');
fprintf('2. Minimum soil moisture\n');
fprintf('3. Maximum soil moisture\n');
fprintf('4. Final soil storage\n');
fprintf('5. Actual ET\n');
fprintf('6. Deep drainage\n');
fprintf('7. Total irrigation\n');
fprintf('8. Water stress\n\n');

%% ============================================================
% 7. Scientific Warning
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' IMPORTANT SCIENTIFIC CHECK\n');
fprintf('====================================================\n');

fprintf('\n');

if isempty(physicalCandidates)

    fprintf([ ...
        'The V3 result file does not expose the physical ', ...
        'model parameters as scalar variables/fields.\n\n', ...
        'Therefore the actual sensitivity simulations ', ...
        'cannot be performed safely yet.\n\n', ...
        'Do NOT modify the validated V3 model automatically.\n']);

else

    fprintf([ ...
        'Potential physical parameters were detected.\n\n', ...
        'However, detection alone is NOT sufficient to ', ...
        'perturb them safely.\n\n', ...
        'The V3 model source must be checked to determine ', ...
        'which parameters directly affect the state equations.\n']);

end

%% ============================================================
% 8. Save Parameter Inventory
% =============================================================

SensitivityInventory = struct();

SensitivityInventory.resultFile = ...
    resultFile;

SensitivityInventory.allVariables = ...
    variableNames;

SensitivityInventory.scalarNumericParameters = ...
    parameterCandidates;

SensitivityInventory.physicalCandidates = ...
    physicalCandidates;

SensitivityInventory.perturbationFactors = ...
    [0.80 0.90 1.00 1.10 1.20];

SensitivityInventory.metrics = { ...
    'MeanSoilMoisture'
    'MinimumSoilMoisture'
    'MaximumSoilMoisture'
    'FinalStorage'
    'ActualET'
    'DeepDrainage'
    'TotalIrrigation'
    'WaterStress'};

save( ...
    '02_V3_SensitivityAnalysis_Inventory.mat', ...
    'SensitivityInventory');

fprintf('\n');
fprintf('Parameter inventory saved to:\n');
fprintf('02_V3_SensitivityAnalysis_Inventory.mat\n');

%% ============================================================
% 9. Final Message
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SENSITIVITY ANALYSIS PREPARATION COMPLETE\n');
fprintf('====================================================\n');

fprintf('\n');
fprintf('No V3 model parameters were modified.\n');

fprintf('The validated V3 model remains unchanged.\n');

fprintf('\n');
fprintf('NEXT STEP:\n');
fprintf('Identify the actual physical parameters in the V3\n');
fprintf('state equations before running perturbation experiments.\n');

fprintf('\n');