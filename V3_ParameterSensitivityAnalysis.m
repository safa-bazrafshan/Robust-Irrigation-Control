%% ============================================================
% V3_ParameterSensitivityAnalysis
%
% AI-Driven Smart Irrigation
%
% One-at-a-Time (OAT) Sensitivity Analysis
% of the Validated V3 Soil-Water Model
%
% IMPORTANT:
%   The original V3 model is NOT modified.
%
%   This script reproduces the V3 equations using a parameter
%   structure and perturbs one parameter at a time.
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
% 1. Load Validated V3 Results
% =============================================================

resultFile = ...
    '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(resultFile)

    error(['Result file not found: ', resultFile]);

end

loadedData = load(resultFile);

if ~isfield(loadedData,'results')

    error('The MAT-file does not contain the variable "results".');

end

baselineResults = loadedData.results;

fprintf('\n');
fprintf('Baseline V3 results loaded successfully.\n');

%% ============================================================
% 2. Baseline V3 Parameters
% =============================================================

params.theta_r  = 0.078;
params.theta_s  = 0.430;
params.theta_FC = 0.250;
params.theta_WP = 0.120;

params.Z1 = 0.10;
params.Z2 = 0.20;
params.Z3 = 0.30;

params.kp12 = 0.80;
params.kp23 = 0.50;
params.kp3d = 0.20;

params.Kinf = 0.020;

params.ET_fraction = [0.50; 0.30; 0.20];

params.dt = 0.25;
params.T  = 120;

%% ============================================================
% 3. Environmental Inputs
% =============================================================

N = round(params.T / params.dt) + 1;

time = (0:N-1)' * params.dt;

rainfall = zeros(N,1);

irrigation = zeros(N,1);

irrigation(time >= 20 & time < 60) = 8;

ET_potential = 4 * ones(N,1);

%% ============================================================
% 4. Parameters Selected for Sensitivity Analysis
% =============================================================

parameterNames = { ...
    'theta_r'
    'theta_s'
    'theta_FC'
    'theta_WP'
    'kp12'
    'kp23'
    'kp3d'
    'Kinf'};

parameterLabels = { ...
    '\theta_r'
    '\theta_s'
    '\theta_{FC}'
    '\theta_{WP}'
    'k_{p12}'
    'k_{p23}'
    'k_{p3d}'
    'K_{inf}'};

numParameters = length(parameterNames);

%% ============================================================
% 5. Perturbation Levels
% =============================================================

perturbationFactors = [ ...
    0.80
    0.90
    1.00
    1.10
    1.20];

numLevels = length(perturbationFactors);

%% ============================================================
% 6. Define Output Metrics
% =============================================================

metricNames = { ...
    'MeanTheta'
    'MinimumTheta'
    'MaximumTheta'
    'FinalStorage'
    'ActualET'
    'DeepDrainage'
    'WaterStress'};

metricLabels = { ...
    'Mean Soil Moisture'
    'Minimum Soil Moisture'
    'Maximum Soil Moisture'
    'Final Soil Storage'
    'Actual ET'
    'Deep Drainage'
    'Water Stress'};

numMetrics = length(metricNames);

%% ============================================================
% 7. Baseline Simulation Using Parameterized Model
% =============================================================

fprintf('\n');
fprintf('Running parameterized baseline model...\n');

baseline = runParameterizedV3( ...
    params, ...
    time, ...
    irrigation, ...
    rainfall, ...
    ET_potential);

%% ============================================================
% 8. Compare Parameterized Baseline with Saved V3
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' BASELINE REPRODUCTION CHECK\n');
fprintf('====================================================\n');

thetaDifference = max( ...
    abs(baseline.theta(:) - baselineResults.theta(:)));

storageDifference = max( ...
    abs(baseline.storage(:) - baselineResults.storage(:)));

ETDifference = max( ...
    abs(baseline.ET_actual_total(:) - ...
    baselineResults.ET_actual_total(:)));

drainageDifference = abs( ...
    sum(baseline.q3d) * params.dt * 1000 - ...
    baselineResults.cumulative_drainage(end));

fprintf('\n');

fprintf('Maximum theta difference:\n');
fprintf('%.12e\n', thetaDifference);

fprintf('\n');

fprintf('Maximum storage difference:\n');
fprintf('%.12e m\n', storageDifference);

fprintf('\n');

fprintf('Maximum ET difference:\n');
fprintf('%.12e m/day\n', ETDifference);

fprintf('\n');

fprintf('Total drainage difference:\n');
fprintf('%.12e mm\n', drainageDifference);

if thetaDifference < 1e-10 && ...
        storageDifference < 1e-10

    fprintf('\n');
    fprintf('BASELINE REPRODUCTION: PASS\n');

else

    fprintf('\n');
    fprintf('BASELINE REPRODUCTION: CHECK REQUIRED\n');

end

%% ============================================================
% 9. Allocate Sensitivity Results
% =============================================================

metricValues = zeros( ...
    numParameters, ...
    numLevels, ...
    numMetrics);

parameterValues = zeros( ...
    numParameters, ...
    numLevels);

%% ============================================================
% 10. Run OAT Sensitivity Analysis
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' RUNNING OAT SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');

for p = 1:numParameters

    parameterName = parameterNames{p};

    baselineValue = params.(parameterName);

    fprintf('\n');
    fprintf('Parameter %d/%d: %s\n', ...
        p, ...
        numParameters, ...
        parameterName);

    fprintf('Baseline value = %.6f\n', ...
        baselineValue);

    for j = 1:numLevels

        factor = perturbationFactors(j);

        testParams = params;

        testValue = baselineValue * factor;

        testParams.(parameterName) = testValue;

        %% ----------------------------------------------------
        % Physical consistency check
        % -----------------------------------------------------

        if testParams.theta_r >= ...
                testParams.theta_WP

            error([ ...
                'Invalid parameter combination: ', ...
                'theta_r >= theta_WP']);

        end

        if testParams.theta_WP >= ...
                testParams.theta_FC

            error([ ...
                'Invalid parameter combination: ', ...
                'theta_WP >= theta_FC']);

        end

        if testParams.theta_FC >= ...
                testParams.theta_s

            error([ ...
                'Invalid parameter combination: ', ...
                'theta_FC >= theta_s']);

        end

        %% ----------------------------------------------------
        % Run Model
        % -----------------------------------------------------

        simulation = runParameterizedV3( ...
            testParams, ...
            time, ...
            irrigation, ...
            rainfall, ...
            ET_potential);

        parameterValues(p,j) = testValue;

        %% ----------------------------------------------------
        % Calculate Metrics
        % -----------------------------------------------------

        thetaAll = simulation.theta(:);

        metricValues(p,j,1) = ...
            mean(thetaAll);

        metricValues(p,j,2) = ...
            min(thetaAll);

        metricValues(p,j,3) = ...
            max(thetaAll);

        metricValues(p,j,4) = ...
            simulation.storage(end) * 1000;

        metricValues(p,j,5) = ...
            sum(simulation.ET_actual_total) * ...
            testParams.dt * 1000;

        metricValues(p,j,6) = ...
            sum(simulation.q3d) * ...
            testParams.dt * 1000;

        metricValues(p,j,7) = ...
            sum(1 - simulation.soil_stress(:)) / ...
            numel(simulation.soil_stress);

        fprintf( ...
            '  %.0f%% -> value = %.6f\n', ...
            factor * 100, ...
            testValue);

    end

end

%% ============================================================
% 11. Display Sensitivity Results
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SENSITIVITY RESULTS\n');
fprintf('====================================================\n');

for p = 1:numParameters

    fprintf('\n');
    fprintf('----------------------------------------------------\n');
    fprintf('%s\n', parameterNames{p});
    fprintf('----------------------------------------------------\n');

    fprintf( ...
        '%12s %18s %18s\n', ...
        'Factor', ...
        'Parameter', ...
        'Final Storage [mm]');

    for j = 1:numLevels

        fprintf( ...
            '%11.0f%% %18.6f %18.6f\n', ...
            perturbationFactors(j)*100, ...
            parameterValues(p,j), ...
            metricValues(p,j,4));

    end

end

%% ============================================================
% 12. Normalized Local Sensitivity Indices
% =============================================================

% Sensitivity is calculated using the central perturbation:
%
% SI = (Y_plus - Y_minus) / (2*Y0)
%      --------------------------------
%          (p_plus - p_minus)/(2*p0)
%
% For our symmetric perturbation:
%
% p_minus = 0.90 p0
% p_plus  = 1.10 p0
%
% therefore:
%
% SI = (Y_plus - Y_minus) / (0.20*Y0)

SI = zeros(numParameters,numMetrics);

for p = 1:numParameters

    for m = 1:numMetrics

        Y_minus = metricValues(p,2,m);
        Y0      = metricValues(p,3,m);
        Y_plus  = metricValues(p,4,m);

        p0 = parameterValues(p,3);

        p_minus = parameterValues(p,2);
        p_plus  = parameterValues(p,4);

        deltaY = Y_plus - Y_minus;
        deltaP = p_plus - p_minus;

        if abs(Y0) > 1e-12

            SI(p,m) = ...
                (deltaY / Y0) / ...
                (deltaP / p0);

        else

            SI(p,m) = NaN;

        end

    end

end

%% ============================================================
% 13. Absolute Sensitivity Score
% =============================================================

absoluteSI = abs(SI);

overallSensitivity = mean( ...
    absoluteSI, ...
    2, ...
    'omitnan');

%% ============================================================
% 14. Display Sensitivity Ranking
% =============================================================

[sortedSensitivity,sortIndex] = ...
    sort(overallSensitivity,'descend');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' OVERALL PARAMETER SENSITIVITY RANKING\n');
fprintf('====================================================\n');

fprintf('\n');

for r = 1:numParameters

    idx = sortIndex(r);

    fprintf( ...
        '%2d. %-12s  Score = %.6f\n', ...
        r, ...
        parameterNames{idx}, ...
        sortedSensitivity(r));

end

%% ============================================================
% 15. Display Sensitivity Matrix
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' NORMALIZED SENSITIVITY INDEX MATRIX\n');
fprintf('====================================================\n');

fprintf('\n');

fprintf('%14s', 'Parameter');

for m = 1:numMetrics

    fprintf('%16s', metricNames{m});

end

fprintf('\n');

fprintf('%s\n', ...
    repmat('-',1,14 + 16*numMetrics));

for p = 1:numParameters

    fprintf('%14s', parameterNames{p});

    for m = 1:numMetrics

        fprintf( ...
            '%16.5f', ...
            SI(p,m));

    end

    fprintf('\n');

end

%% ============================================================
% 16. Figure 1 - Overall Sensitivity Ranking
% =============================================================

figure(1);

bar(sortedSensitivity);

set(gca, ...
    'XTick',1:numParameters, ...
    'XTickLabel',parameterNames);

xlabel('Model Parameter');

ylabel('Mean Absolute Sensitivity Index');

title('V3 Overall Parameter Sensitivity');

grid on;

xtickangle(45);

%% ============================================================
% 17. Figure 2 - Sensitivity Heatmap
% =============================================================

figure(2);

imagesc(SI);

colorbar;

xlabel('Performance Metric');

ylabel('Model Parameter');

title('Normalized Sensitivity Matrix');

set(gca, ...
    'XTick',1:numMetrics, ...
    'XTickLabel',metricNames);

set(gca, ...
    'YTick',1:numParameters, ...
    'YTickLabel',parameterNames);

xtickangle(45);

%% ============================================================
% 18. Figure 3 - Soil Moisture Sensitivity
% =============================================================

figure(3);

hold on;

for p = 1:numParameters

    plot( ...
        perturbationFactors * 100, ...
        squeeze(metricValues(p,:,1)), ...
        '-o', ...
        'LineWidth',1.5);

end

xlabel('Parameter Value [% of Baseline]');

ylabel('Mean Soil Moisture [-]');

title('Sensitivity of Mean Soil Moisture');

legend(parameterNames, ...
    'Location','best');

grid on;

hold off;

%% ============================================================
% 19. Figure 4 - Final Storage Sensitivity
% =============================================================

figure(4);

hold on;

for p = 1:numParameters

    plot( ...
        perturbationFactors * 100, ...
        squeeze(metricValues(p,:,4)), ...
        '-o', ...
        'LineWidth',1.5);

end

xlabel('Parameter Value [% of Baseline]');

ylabel('Final Soil Storage [mm]');

title('Sensitivity of Final Soil Storage');

legend(parameterNames, ...
    'Location','best');

grid on;

hold off;

%% ============================================================
% 20. Figure 5 - ET Sensitivity
% =============================================================

figure(5);

hold on;

for p = 1:numParameters

    plot( ...
        perturbationFactors * 100, ...
        squeeze(metricValues(p,:,5)), ...
        '-o', ...
        'LineWidth',1.5);

end

xlabel('Parameter Value [% of Baseline]');

ylabel('Total Actual ET [mm]');

title('Sensitivity of Actual Evapotranspiration');

legend(parameterNames, ...
    'Location','best');

grid on;

hold off;

%% ============================================================
% 21. Figure 6 - Drainage Sensitivity
% =============================================================

figure(6);

hold on;

for p = 1:numParameters

    plot( ...
        perturbationFactors * 100, ...
        squeeze(metricValues(p,:,6)), ...
        '-o', ...
        'LineWidth',1.5);

end

xlabel('Parameter Value [% of Baseline]');

ylabel('Total Deep Drainage [mm]');

title('Sensitivity of Deep Drainage');

legend(parameterNames, ...
    'Location','best');

grid on;

hold off;

%% ============================================================
% 22. Save Figures
% =============================================================

saveas( ...
    figure(1), ...
    '07_V3_Sensitivity_Ranking.png');

saveas( ...
    figure(2), ...
    '08_V3_Sensitivity_Heatmap.png');

saveas( ...
    figure(3), ...
    '09_V3_Sensitivity_MeanTheta.png');

saveas( ...
    figure(4), ...
    '10_V3_Sensitivity_FinalStorage.png');

saveas( ...
    figure(5), ...
    '11_V3_Sensitivity_ET.png');

saveas( ...
    figure(6), ...
    '12_V3_Sensitivity_Drainage.png');

%% ============================================================
% 23. Prepare Results Structure
% =============================================================

sensitivityResults = struct();

sensitivityResults.version = ...
    'V3 OAT Sensitivity Analysis';

sensitivityResults.parameterNames = ...
    parameterNames;

sensitivityResults.parameterLabels = ...
    parameterLabels;

sensitivityResults.baselineParameters = ...
    params;

sensitivityResults.perturbationFactors = ...
    perturbationFactors;

sensitivityResults.parameterValues = ...
    parameterValues;

sensitivityResults.metricNames = ...
    metricNames;

sensitivityResults.metricLabels = ...
    metricLabels;

sensitivityResults.metricValues = ...
    metricValues;

sensitivityResults.sensitivityIndex = ...
    SI;

sensitivityResults.absoluteSensitivity = ...
    absoluteSI;

sensitivityResults.overallSensitivity = ...
    overallSensitivity;

sensitivityResults.ranking = ...
    sortIndex;

sensitivityResults.sortedSensitivity = ...
    sortedSensitivity;

%% ============================================================
% 24. Save Numerical Results
% =============================================================

save( ...
    'V3_ParameterSensitivityAnalysis_Results.mat', ...
    'sensitivityResults');

%% ============================================================
% 25. Final Summary
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SENSITIVITY ANALYSIS COMPLETED\n');
fprintf('====================================================\n');

fprintf('\n');

fprintf('Parameters analyzed: %d\n', ...
    numParameters);

fprintf('Perturbation levels: %d\n', ...
    numLevels);

fprintf('\n');

fprintf('Top sensitivity parameters:\n');

for r = 1:min(5,numParameters)

    idx = sortIndex(r);

    fprintf( ...
        '%d. %s   (Score = %.6f)\n', ...
        r, ...
        parameterNames{idx}, ...
        sortedSensitivity(r));

end

fprintf('\n');

fprintf('Results saved to:\n');
fprintf('V3_ParameterSensitivityAnalysis_Results.mat\n');

fprintf('\n');

fprintf('Figures saved:\n');
fprintf('07_V3_Sensitivity_Ranking.png\n');
fprintf('08_V3_Sensitivity_Heatmap.png\n');
fprintf('09_V3_Sensitivity_MeanTheta.png\n');
fprintf('10_V3_Sensitivity_FinalStorage.png\n');
fprintf('11_V3_Sensitivity_ET.png\n');
fprintf('12_V3_Sensitivity_Drainage.png\n');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' NEXT STEP: INTERPRET SENSITIVITY RESULTS\n');
fprintf('====================================================\n');


%% ============================================================
% LOCAL FUNCTION
% Parameterized V3 Soil-Water Model
% =============================================================

function results = runParameterizedV3( ...
    params, ...
    time, ...
    irrigation, ...
    rainfall, ...
    ET_potential)

%% ------------------------------------------------------------
% Simulation Settings
% -------------------------------------------------------------

dt = params.dt;

T = params.T;

N = length(time);

%% ------------------------------------------------------------
% Soil Parameters
% -------------------------------------------------------------

theta_r  = params.theta_r;
theta_s  = params.theta_s;
theta_FC = params.theta_FC;
theta_WP = params.theta_WP;

%% ------------------------------------------------------------
% Layer Geometry
% -------------------------------------------------------------

Z1 = params.Z1;
Z2 = params.Z2;
Z3 = params.Z3;

Z = [Z1; Z2; Z3];

%% ------------------------------------------------------------
% Initial Conditions
% -------------------------------------------------------------

theta0 = [0.20; 0.20; 0.20];

S0 = theta0 .* Z;

%% ------------------------------------------------------------
% Transfer Parameters
% -------------------------------------------------------------

kp12 = params.kp12;
kp23 = params.kp23;
kp3d = params.kp3d;

%% ------------------------------------------------------------
% Infiltration
% -------------------------------------------------------------

Kinf = params.Kinf;

%% ------------------------------------------------------------
% ET Distribution
% -------------------------------------------------------------

ET_fraction = params.ET_fraction;

%% ------------------------------------------------------------
% Storage Limits
% -------------------------------------------------------------

S_min = theta_r .* Z;

S_max = theta_s .* Z;

S_FC = theta_FC .* Z;

S_WP = theta_WP .* Z;

%% ------------------------------------------------------------
% Allocate States
% -------------------------------------------------------------

S = zeros(N,3);

theta = zeros(N,3);

S(1,:) = S0';

theta(1,:) = theta0';

%% ------------------------------------------------------------
% Allocate Fluxes
% -------------------------------------------------------------

infiltration = zeros(N,1);

runoff = zeros(N,1);

q12 = zeros(N,1);

q23 = zeros(N,1);

q3d = zeros(N,1);

ET_actual = zeros(N,3);

soil_stress = zeros(N,3);

%% ============================================================
% Main Simulation Loop
% =============================================================

for k = 1:N-1

    %% --------------------------------------------------------
    % Current Storage
    % ---------------------------------------------------------

    S_current = S(k,:)';

    %% --------------------------------------------------------
    % External Water Input
    % ---------------------------------------------------------

    I = irrigation(k) / 1000;

    P = rainfall(k) / 1000;

    water_input = I + P;

    %% --------------------------------------------------------
    % 1. Surface Infiltration
    % ---------------------------------------------------------

    current_theta1 = ...
        S_current(1) / Z1;

    remaining_capacity = ...
        S_max(1) - S_current(1);

    saturation_factor = ...
        (theta_s - current_theta1) / ...
        (theta_s - theta_FC);

    saturation_factor = ...
        min(max(saturation_factor,0),1);

    infiltration_capacity = ...
        Kinf * saturation_factor;

    potential_infiltration = ...
        min(water_input,infiltration_capacity);

    actual_infiltration = ...
        min( ...
        potential_infiltration, ...
        remaining_capacity / dt);

    actual_infiltration = ...
        max(actual_infiltration,0);

    surface_excess = ...
        max(0,water_input-actual_infiltration);

    infiltration(k) = ...
        actual_infiltration;

    runoff(k) = ...
        surface_excess;

    S_current(1) = ...
        S_current(1) + ...
        actual_infiltration * dt;

    %% --------------------------------------------------------
    % 2. Soil Water Stress
    % ---------------------------------------------------------

    theta_current = ...
        S_current ./ Z;

    stress = ...
        (theta_current-theta_WP) ./ ...
        (theta_FC-theta_WP);

    stress = ...
        min(max(stress,0),1);

    soil_stress(k,:) = stress';

    %% --------------------------------------------------------
    % 3. Actual Evapotranspiration
    % ---------------------------------------------------------

    ET_demand = ...
        (ET_potential(k)/1000) .* ...
        ET_fraction .* ...
        stress;

    for i = 1:3

        available_water = ...
            max(0,S_current(i)-S_min(i));

        ET_remove = ...
            min( ...
            ET_demand(i)*dt, ...
            available_water);

        S_current(i) = ...
            S_current(i)-ET_remove;

        ET_actual(k,i) = ...
            ET_remove/dt;

    end

    %% --------------------------------------------------------
    % 4. Percolation: Layer 1 -> Layer 2
    % ---------------------------------------------------------

    excess1 = ...
        max(0,S_current(1)-S_FC(1));

    potential_q12 = ...
        kp12 * excess1;

    max_transfer12 = ...
        S_current(1)-S_min(1);

    max_receive12 = ...
        S_max(2)-S_current(2);

    transfer12 = ...
        min( ...
        potential_q12*dt, ...
        max_transfer12);

    transfer12 = ...
        min( ...
        transfer12, ...
        max_receive12);

    transfer12 = ...
        max(transfer12,0);

    S_current(1) = ...
        S_current(1)-transfer12;

    S_current(2) = ...
        S_current(2)+transfer12;

    q12(k) = ...
        transfer12/dt;

    %% --------------------------------------------------------
    % 5. Percolation: Layer 2 -> Layer 3
    % ---------------------------------------------------------

    excess2 = ...
        max(0,S_current(2)-S_FC(2));

    potential_q23 = ...
        kp23 * excess2;

    max_transfer23 = ...
        S_current(2)-S_min(2);

    max_receive23 = ...
        S_max(3)-S_current(3);

    transfer23 = ...
        min( ...
        potential_q23*dt, ...
        max_transfer23);

    transfer23 = ...
        min( ...
        transfer23, ...
        max_receive23);

    transfer23 = ...
        max(transfer23,0);

    S_current(2) = ...
        S_current(2)-transfer23;

    S_current(3) = ...
        S_current(3)+transfer23;

    q23(k) = ...
        transfer23/dt;

    %% --------------------------------------------------------
    % 6. Deep Drainage from Layer 3
    % ---------------------------------------------------------

    excess3 = ...
        max(0,S_current(3)-S_FC(3));

    potential_q3d = ...
        kp3d * excess3;

    max_drainage = ...
        S_current(3)-S_min(3);

    drainage = ...
        min( ...
        potential_q3d*dt, ...
        max_drainage);

    drainage = ...
        max(drainage,0);

    S_current(3) = ...
        S_current(3)-drainage;

    q3d(k) = ...
        drainage/dt;

    %% --------------------------------------------------------
    % 7. Final Physical Bounds
    % ---------------------------------------------------------

    S_current = ...
        min( ...
        max(S_current,S_min), ...
        S_max);

    %% --------------------------------------------------------
    % 8. Store New State
    % ---------------------------------------------------------

    S(k+1,:) = ...
        S_current';

    theta(k+1,:) = ...
        (S_current ./ Z)';

end

%% ============================================================
% Final Soil Stress
% =============================================================

theta1 = theta(:,1);

theta2 = theta(:,2);

theta3 = theta(:,3);

stress1 = ...
    (theta1-theta_WP) ./ ...
    (theta_FC-theta_WP);

stress2 = ...
    (theta2-theta_WP) ./ ...
    (theta_FC-theta_WP);

stress3 = ...
    (theta3-theta_WP) ./ ...
    (theta_FC-theta_WP);

stress1 = ...
    min(max(stress1,0),1);

stress2 = ...
    min(max(stress2,0),1);

stress3 = ...
    min(max(stress3,0),1);

soil_stress = ...
    [stress1,stress2,stress3];

%% ============================================================
% Actual ET
% =============================================================

ET_actual_total = ...
    sum(ET_actual,2);

%% ============================================================
% Total Storage [m]
% =============================================================

storage = ...
    sum(S,2);

%% ============================================================
% Return Results
% =============================================================

results.time = time;

results.theta = theta;

results.storage = storage;

results.infiltration = infiltration;

results.runoff = runoff;

results.q12 = q12;

results.q23 = q23;

results.q3d = q3d;

results.ET_actual = ET_actual;

results.ET_actual_total = ...
    ET_actual_total;

results.soil_stress = ...
    soil_stress;

end