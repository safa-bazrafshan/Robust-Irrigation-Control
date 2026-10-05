%% ============================================================
% V3_ParameterSensitivityAnalysis_Corrected
%
% AI-Driven Smart Irrigation
%
% Corrected One-at-a-Time Parameter Sensitivity Analysis
% for the validated V3 three-layer soil-water model.
%
% IMPORTANT:
%   The validated V3 model file is NOT modified.
%
% Main correction:
%   Drainage stored internally in the V3 model is [m].
%   For comparison and reporting it must be converted to [mm].
%
% ============================================================

clc;
clear;
close all;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 PARAMETER SENSITIVITY ANALYSIS - CORRECTED\n');
fprintf('====================================================\n');

%% ============================================================
% 1. Load Validated V3 Results
% =============================================================

resultFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(resultFile)

    error([ ...
        '\nValidated V3 result file not found:\n', ...
        '%s\n\n', ...
        'Make sure this file is in the main project folder.\n'], ...
        resultFile);

end

loadedData = load(resultFile);

if ~isfield(loadedData,'results')

    error(['The result file does not contain the expected ', ...
           '"results" structure.']);

end

baselineResults = loadedData.results;

fprintf('\nValidated V3 results loaded successfully.\n');

%% ============================================================
% 2. Extract Baseline Parameters
% =============================================================

dt = baselineResults.dt;
T  = baselineResults.T;

theta_r  = baselineResults.theta_r;
theta_s  = baselineResults.theta_s;
theta_FC = baselineResults.theta_FC;
theta_WP = baselineResults.theta_WP;

Z = baselineResults.Z;

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

theta0 = baselineResults.theta(1,:)';

Kinf = 0.020;

kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

%% ============================================================
% 3. Baseline Reference Quantities
% =============================================================

baselineTheta = baselineResults.theta;

baselineStorage = baselineResults.storage;

baselineET = baselineResults.ET_actual_total;

baselineDrainage = baselineResults.q3d;

baselineIrrigation = baselineResults.irrigation;

baselineRainfall = baselineResults.rainfall;

%% ============================================================
% 4. Correct Unit Conversion
% =============================================================
%
% Internal V3 storage and flux integrals:
%
%   storage       -> [m]
%   q3d           -> [m/day]
%   cumulative ET -> [m]
%   cumulative drainage -> [m]
%
% Reporting:
%
%   1 m = 1000 mm
%
% =============================================================

baselineFinalStorage_mm = ...
    baselineStorage(end) * 1000;

baselineActualET_mm = ...
    sum(baselineET) * dt * 1000;

baselineDeepDrainage_mm = ...
    sum(baselineDrainage) * dt * 1000;

baselineIrrigation_mm = ...
    sum(baselineIrrigation) * dt;

baselineRainfall_mm = ...
    sum(baselineRainfall) * dt;

%% ============================================================
% 5. Baseline Information
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' BASELINE V3 REFERENCE\n');
fprintf('====================================================\n');

fprintf('\n');

fprintf('theta_r  = %.6f\n',theta_r);
fprintf('theta_s  = %.6f\n',theta_s);
fprintf('theta_FC = %.6f\n',theta_FC);
fprintf('theta_WP = %.6f\n',theta_WP);

fprintf('kp12     = %.6f\n',kp12);
fprintf('kp23     = %.6f\n',kp23);
fprintf('kp3d     = %.6f\n',kp3d);
fprintf('Kinf     = %.6f m/day\n',Kinf);

fprintf('\n');

fprintf('Final storage = %.6f mm\n', ...
    baselineFinalStorage_mm);

fprintf('Actual ET     = %.6f mm\n', ...
    baselineActualET_mm);

fprintf('Deep drainage = %.6f mm\n', ...
    baselineDeepDrainage_mm);

fprintf('Irrigation    = %.6f mm\n', ...
    baselineIrrigation_mm);

fprintf('Rainfall      = %.6f mm\n', ...
    baselineRainfall_mm);

%% ============================================================
% 6. Parameter Definition
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

baselineParameters = [ ...
    theta_r
    theta_s
    theta_FC
    theta_WP
    kp12
    kp23
    kp3d
    Kinf];

perturbationFactors = ...
    [0.80 0.90 1.00 1.10 1.20];

nParameters = length(parameterNames);
nFactors = length(perturbationFactors);

%% ============================================================
% 7. Baseline Reproduction Check
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' BASELINE REPRODUCTION CHECK\n');
fprintf('====================================================\n');

baselineParamResults = runV3Model( ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf, ...
    dt, ...
    T, ...
    Z, ...
    theta0);

thetaDifference = ...
    max(abs(baselineParamResults.theta(:) - ...
    baselineResults.theta(:)));

storageDifference = ...
    max(abs(baselineParamResults.storage(:) - ...
    baselineResults.storage(:)));

ETDifference = ...
    max(abs(baselineParamResults.ET_actual_total(:) - ...
    baselineResults.ET_actual_total(:)));

drainageDifference_mm = ...
    abs( ...
    baselineParamResults.totalDrainage_mm - ...
    baselineDeepDrainage_mm);

fprintf('\n');

fprintf('Maximum theta difference:\n');
fprintf('%.12e\n',thetaDifference);

fprintf('\n');

fprintf('Maximum storage difference:\n');
fprintf('%.12e m\n',storageDifference);

fprintf('\n');

fprintf('Maximum ET difference:\n');
fprintf('%.12e m/day\n',ETDifference);

fprintf('\n');

fprintf('Total drainage difference:\n');
fprintf('%.12e mm\n',drainageDifference_mm);

thetaTolerance = 1e-12;
storageTolerance = 1e-12;
ETTolerance = 1e-12;
drainageTolerance = 1e-9;

if ...
    thetaDifference <= thetaTolerance && ...
    storageDifference <= storageTolerance && ...
    ETDifference <= ETTolerance && ...
    drainageDifference_mm <= drainageTolerance

    baselinePass = true;

else

    baselinePass = false;

end

if baselinePass

    fprintf('\n');
    fprintf('BASELINE REPRODUCTION: PASS\n');

else

    fprintf('\n');
    fprintf('BASELINE REPRODUCTION: FAIL\n');
    fprintf('\n');
    fprintf(['Do NOT interpret the sensitivity results until ', ...
             'this check is resolved.\n']);

    error('Baseline reproduction failed.');

end

%% ============================================================
% 8. Allocate Sensitivity Arrays
% =============================================================

meanTheta = zeros(nParameters,nFactors);

minimumTheta = zeros(nParameters,nFactors);

maximumTheta = zeros(nParameters,nFactors);

finalStorage = zeros(nParameters,nFactors);

actualET = zeros(nParameters,nFactors);

deepDrainage = zeros(nParameters,nFactors);

totalIrrigation = zeros(nParameters,nFactors);

waterStress = zeros(nParameters,nFactors);

%% ============================================================
% 9. Run OAT Sensitivity Analysis
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' RUNNING OAT SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');

for p = 1:nParameters

    fprintf('\n');
    fprintf('Parameter %d/%d: %s\n', ...
        p,nParameters,parameterNames{p});

    p0 = baselineParameters(p);

    fprintf('Baseline value = %.6f\n',p0);

    for f = 1:nFactors

        factor = perturbationFactors(f);

        parameterValue = p0 * factor;

        fprintf('  %3.0f%% -> value = %.6f\n', ...
            factor*100,parameterValue);

        currentParameters = baselineParameters;

        currentParameters(p) = parameterValue;

        sim = runV3Model( ...
            currentParameters(1), ...
            currentParameters(2), ...
            currentParameters(3), ...
            currentParameters(4), ...
            currentParameters(5), ...
            currentParameters(6), ...
            currentParameters(7), ...
            currentParameters(8), ...
            dt, ...
            T, ...
            Z, ...
            theta0);

        meanTheta(p,f) = ...
            mean(sim.theta(:));

        minimumTheta(p,f) = ...
            min(sim.theta(:));

        maximumTheta(p,f) = ...
            max(sim.theta(:));

        finalStorage(p,f) = ...
            sim.finalStorage_mm;

        actualET(p,f) = ...
            sim.totalET_mm;

        deepDrainage(p,f) = ...
            sim.totalDrainage_mm;

        totalIrrigation(p,f) = ...
            sim.totalIrrigation_mm;

        waterStress(p,f) = ...
            1 - mean(sim.soil_stress(:));

    end

end

%% ============================================================
% 10. Print Sensitivity Results
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' SENSITIVITY RESULTS\n');
fprintf('====================================================\n');

for p = 1:nParameters

    fprintf('\n');
    fprintf('----------------------------------------------------\n');
    fprintf('%s\n',parameterNames{p});
    fprintf('----------------------------------------------------\n');

    fprintf('%10s %18s %22s\n', ...
        'Factor', ...
        'Parameter', ...
        'Final Storage [mm]');

    for f = 1:nFactors

        fprintf('%10.0f%% %18.6f %22.6f\n', ...
            perturbationFactors(f)*100, ...
            baselineParameters(p) * perturbationFactors(f), ...
            finalStorage(p,f));

    end

end

%% ============================================================
% 11. Normalized Sensitivity Index
% =============================================================
%
% Central finite-difference normalized sensitivity:
%
%       S = (dy/y0) / (dp/p0)
%
% using the 80% and 120% points.
%
% This is a dimensionless local/global OAT elasticity estimate.
%
% =============================================================

baselineMetricVector = zeros(8,1);

baselineMetricVector(1) = ...
    mean(baselineTheta(:));

baselineMetricVector(2) = ...
    min(baselineTheta(:));

baselineMetricVector(3) = ...
    max(baselineTheta(:));

baselineMetricVector(4) = ...
    baselineFinalStorage_mm;

baselineMetricVector(5) = ...
    baselineActualET_mm;

baselineMetricVector(6) = ...
    baselineDeepDrainage_mm;

baselineMetricVector(7) = ...
    baselineIrrigation_mm;

baselineMetricVector(8) = ...
    1 - mean(baselineResults.soil_stress(:));

metricNames = { ...
    'MeanTheta'
    'MinimumTheta'
    'MaximumTheta'
    'FinalStorage'
    'ActualET'
    'DeepDrainage'
    'TotalIrrigation'
    'WaterStress'};

sensitivityMatrix = zeros(nParameters,8);

for p = 1:nParameters

    for m = 1:8

        yLow = getMetricValue( ...
            m, ...
            p, ...
            1, ...
            meanTheta, ...
            minimumTheta, ...
            maximumTheta, ...
            finalStorage, ...
            actualET, ...
            deepDrainage, ...
            totalIrrigation, ...
            waterStress);

        yHigh = getMetricValue( ...
            m, ...
            p, ...
            nFactors, ...
            meanTheta, ...
            minimumTheta, ...
            maximumTheta, ...
            finalStorage, ...
            actualET, ...
            deepDrainage, ...
            totalIrrigation, ...
            waterStress);

        y0 = baselineMetricVector(m);

        if abs(y0) > 1e-12

            sensitivityMatrix(p,m) = ...
                ((yHigh-yLow)/y0) / ...
                (perturbationFactors(end) - ...
                 perturbationFactors(1));

        else

            sensitivityMatrix(p,m) = 0;

        end

    end

end

%% ============================================================
% 12. Overall Parameter Ranking
% =============================================================

overallScore = ...
    mean(abs(sensitivityMatrix(:,1:7)),2);

[sortedScores,sortIndex] = ...
    sort(overallScore,'descend');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' OVERALL PARAMETER SENSITIVITY RANKING\n');
fprintf('====================================================\n');

for k = 1:nParameters

    fprintf('%2d. %-12s Score = %.6f\n', ...
        k, ...
        parameterNames{sortIndex(k)}, ...
        sortedScores(k));

end

%% ============================================================
% 13. Print Normalized Sensitivity Matrix
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' NORMALIZED SENSITIVITY INDEX MATRIX\n');
fprintf('====================================================\n');

fprintf('\n');

fprintf('%12s', 'Parameter');

for m = 1:8

    fprintf('%16s',metricNames{m});

end

fprintf('\n');

fprintf(['----------------------------------------------------------------', ...
         '-------------------------\n']);

for p = 1:nParameters

    fprintf('%12s',parameterNames{p});

    for m = 1:8

        fprintf('%16.5f', ...
            sensitivityMatrix(p,m));

    end

    fprintf('\n');

end

%% ============================================================
% 14. Figure 1 - Overall Ranking
% =============================================================

figure( ...
    'Name','V3 Corrected Overall Sensitivity', ...
    'Color','w');

bar(sortedScores);

grid on;

xlabel('Parameter Rank');
ylabel('Mean Absolute Sensitivity Index');

title('V3 Corrected Overall Parameter Sensitivity');

set(gca, ...
    'XTick',1:nParameters, ...
    'XTickLabel',parameterNames);

xtickangle(30);

%% ============================================================
% 15. Figure 2 - Sensitivity Heatmap
% =============================================================

figure( ...
    'Name','V3 Corrected Sensitivity Matrix', ...
    'Color','w');

imagesc(sensitivityMatrix);

colorbar;

grid on;

xlabel('Performance Metric');
ylabel('Model Parameter');

title('V3 Corrected Normalized Sensitivity Matrix');

set(gca, ...
    'XTick',1:8, ...
    'XTickLabel',metricNames, ...
    'YTick',1:nParameters, ...
    'YTickLabel',parameterNames);

xtickangle(35);

%% ============================================================
% 16. Figure 3 - Mean Soil Moisture
% =============================================================

figure( ...
    'Name','V3 Corrected Mean Soil Moisture Sensitivity', ...
    'Color','w');

hold on;

for p = 1:nParameters

    plot( ...
        perturbationFactors*100, ...
        meanTheta(p,:), ...
        '-o', ...
        'LineWidth',1.5, ...
        'MarkerSize',5);

end

grid on;

xlabel('Parameter Value [% of Baseline]');
ylabel('Mean Soil Moisture [-]');

title('Sensitivity of Mean Soil Moisture');

legend(parameterNames,'Location','best');

%% ============================================================
% 17. Figure 4 - Final Storage
% =============================================================

figure( ...
    'Name','V3 Corrected Final Storage Sensitivity', ...
    'Color','w');

hold on;

for p = 1:nParameters

    plot( ...
        perturbationFactors*100, ...
        finalStorage(p,:), ...
        '-o', ...
        'LineWidth',1.5, ...
        'MarkerSize',5);

end

grid on;

xlabel('Parameter Value [% of Baseline]');
ylabel('Final Soil Storage [mm]');

title('Sensitivity of Final Soil Storage');

legend(parameterNames,'Location','best');

%% ============================================================
% 18. Figure 5 - Actual ET
% =============================================================

figure( ...
    'Name','V3 Corrected ET Sensitivity', ...
    'Color','w');

hold on;

for p = 1:nParameters

    plot( ...
        perturbationFactors*100, ...
        actualET(p,:), ...
        '-o', ...
        'LineWidth',1.5, ...
        'MarkerSize',5);

end

grid on;

xlabel('Parameter Value [% of Baseline]');
ylabel('Total Actual ET [mm]');

title('Sensitivity of Actual Evapotranspiration');

legend(parameterNames,'Location','best');

%% ============================================================
% 19. Figure 6 - Deep Drainage
% =============================================================

figure( ...
    'Name','V3 Corrected Deep Drainage Sensitivity', ...
    'Color','w');

hold on;

for p = 1:nParameters

    plot( ...
        perturbationFactors*100, ...
        deepDrainage(p,:), ...
        '-o', ...
        'LineWidth',1.5, ...
        'MarkerSize',5);

end

grid on;

xlabel('Parameter Value [% of Baseline]');
ylabel('Total Deep Drainage [mm]');

title('Sensitivity of Deep Drainage');

legend(parameterNames,'Location','best');

%% ============================================================
% 20. Save Corrected Results
% =============================================================

SensitivityResults = struct();

SensitivityResults.version = ...
    'V3 Corrected OAT Sensitivity Analysis';

SensitivityResults.resultFile = ...
    resultFile;

SensitivityResults.dt = dt;

SensitivityResults.T = T;

SensitivityResults.parameterNames = ...
    parameterNames;

SensitivityResults.baselineParameters = ...
    baselineParameters;

SensitivityResults.perturbationFactors = ...
    perturbationFactors;

SensitivityResults.meanTheta = ...
    meanTheta;

SensitivityResults.minimumTheta = ...
    minimumTheta;

SensitivityResults.maximumTheta = ...
    maximumTheta;

SensitivityResults.finalStorage = ...
    finalStorage;

SensitivityResults.actualET = ...
    actualET;

SensitivityResults.deepDrainage = ...
    deepDrainage;

SensitivityResults.totalIrrigation = ...
    totalIrrigation;

SensitivityResults.waterStress = ...
    waterStress;

SensitivityResults.metricNames = ...
    metricNames;

SensitivityResults.baselineMetricVector = ...
    baselineMetricVector;

SensitivityResults.sensitivityMatrix = ...
    sensitivityMatrix;

SensitivityResults.overallScore = ...
    overallScore;

SensitivityResults.sortedScores = ...
    sortedScores;

SensitivityResults.sortIndex = ...
    sortIndex;

SensitivityResults.baselineReproductionPass = ...
    baselinePass;

SensitivityResults.baselineThetaDifference = ...
    thetaDifference;

SensitivityResults.baselineStorageDifference = ...
    storageDifference;

SensitivityResults.baselineETDifference = ...
    ETDifference;

SensitivityResults.baselineDrainageDifference_mm = ...
    drainageDifference_mm;

save( ...
    'V3_ParameterSensitivityAnalysis_Corrected_Results.mat', ...
    'SensitivityResults');

%% ============================================================
% 21. Save Figures
% =============================================================

saveas( ...
    figure(1), ...
    '07_V3_Sensitivity_Ranking_Corrected.png');

saveas( ...
    figure(2), ...
    '08_V3_Sensitivity_Heatmap_Corrected.png');

saveas( ...
    figure(3), ...
    '09_V3_Sensitivity_MeanTheta_Corrected.png');

saveas( ...
    figure(4), ...
    '10_V3_Sensitivity_FinalStorage_Corrected.png');

saveas( ...
    figure(5), ...
    '11_V3_Sensitivity_ET_Corrected.png');

saveas( ...
    figure(6), ...
    '12_V3_Sensitivity_Drainage_Corrected.png');

%% ============================================================
% 22. Final Summary
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' CORRECTED SENSITIVITY ANALYSIS COMPLETED\n');
fprintf('====================================================\n');

fprintf('\n');

fprintf('Baseline reproduction: PASS\n');

fprintf('Maximum theta difference:\n');
fprintf('%.12e\n',thetaDifference);

fprintf('\n');

fprintf('Maximum storage difference:\n');
fprintf('%.12e m\n',storageDifference);

fprintf('\n');

fprintf('Maximum ET difference:\n');
fprintf('%.12e m/day\n',ETDifference);

fprintf('\n');

fprintf('Total drainage difference:\n');
fprintf('%.12e mm\n',drainageDifference_mm);

fprintf('\n');

fprintf('Corrected results saved to:\n');
fprintf('V3_ParameterSensitivityAnalysis_Corrected_Results.mat\n');

fprintf('\n');

fprintf('Corrected figures saved:\n');
fprintf('07_V3_Sensitivity_Ranking_Corrected.png\n');
fprintf('08_V3_Sensitivity_Heatmap_Corrected.png\n');
fprintf('09_V3_Sensitivity_MeanTheta_Corrected.png\n');
fprintf('10_V3_Sensitivity_FinalStorage_Corrected.png\n');
fprintf('11_V3_Sensitivity_ET_Corrected.png\n');
fprintf('12_V3_Sensitivity_Drainage_Corrected.png\n');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' END\n');
fprintf('====================================================\n');


%% ============================================================
% LOCAL FUNCTION
% V3 MODEL
% =============================================================

function sim = runV3Model( ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf, ...
    dt, ...
    T, ...
    Z, ...
    theta0)

%% ------------------------------------------------------------
% Simulation settings
% ------------------------------------------------------------

N = round(T/dt) + 1;

time = (0:N-1)' * dt;

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

%% ------------------------------------------------------------
% Inputs
% ------------------------------------------------------------

irrigation = zeros(N,1);

irrigation(time >= 20 & time < 60) = 8;

rainfall = zeros(N,1);

ET_potential = 4 * ones(N,1);

ET_fraction = [0.50;0.30;0.20];

%% ------------------------------------------------------------
% Initial storage
% ------------------------------------------------------------

S0 = theta0 .* Z;

S = zeros(N,3);

theta = zeros(N,3);

S(1,:) = S0';

theta(1,:) = theta0';

%% ------------------------------------------------------------
% Storage limits
% ------------------------------------------------------------

S_min = theta_r .* Z;

S_max = theta_s .* Z;

S_FC = theta_FC .* Z;

%% ------------------------------------------------------------
% Allocate variables
% ------------------------------------------------------------

infiltration = zeros(N,1);

runoff = zeros(N,1);

q12 = zeros(N,1);

q23 = zeros(N,1);

q3d = zeros(N,1);

ET_actual = zeros(N,3);

soil_stress = zeros(N,3);

%% ------------------------------------------------------------
% Main simulation
% ------------------------------------------------------------

for k = 1:N-1

    S_current = S(k,:)';

    I = irrigation(k) / 1000;

    P = rainfall(k) / 1000;

    water_input = I + P;

    %% Surface infiltration

    current_theta1 = ...
        S_current(1) / Z1;

    remaining_capacity = ...
        S_max(1) - S_current(1);

    saturation_factor = ...
        (theta_s-current_theta1) / ...
        (theta_s-theta_FC);

    saturation_factor = ...
        min(max(saturation_factor,0),1);

    infiltration_capacity = ...
        Kinf * saturation_factor;

    potential_infiltration = ...
        min(water_input,infiltration_capacity);

    actual_infiltration = ...
        min( ...
        potential_infiltration, ...
        remaining_capacity/dt);

    actual_infiltration = ...
        max(actual_infiltration,0);

    infiltration(k) = ...
        actual_infiltration;

    surface_excess = ...
        max(0,water_input-actual_infiltration);

    runoff(k) = ...
        surface_excess;

    S_current(1) = ...
        S_current(1) + ...
        actual_infiltration*dt;

    %% Soil water stress

    theta_current = ...
        S_current ./ Z;

    stress = ...
        (theta_current-theta_WP) ./ ...
        (theta_FC-theta_WP);

    stress = ...
        min(max(stress,0),1);

    soil_stress(k,:) = ...
        stress';

    %% Actual ET

    ET_demand = ...
        (ET_potential(k)/1000) .* ...
        ET_fraction .* stress;

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

    %% Layer 1 -> Layer 2

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

    %% Layer 2 -> Layer 3

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

    %% Layer 3 -> Deep Drainage

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

    %% Final physical bounds

    S_current = ...
        min(max(S_current,S_min),S_max);

    %% Store

    S(k+1,:) = ...
        S_current';

    theta(k+1,:) = ...
        (S_current ./ Z)';

end

%% ------------------------------------------------------------
% Final stress
% ------------------------------------------------------------

soil_stress = ...
    min(max( ...
    (theta-theta_WP) ./ ...
    (theta_FC-theta_WP), ...
    0),1);

%% ------------------------------------------------------------
% Total ET
% ------------------------------------------------------------

ET_actual_total = ...
    sum(ET_actual,2);

%% ------------------------------------------------------------
% Storage
% ------------------------------------------------------------

storage = ...
    sum(S,2);

%% ------------------------------------------------------------
% Totals
% ------------------------------------------------------------

totalIrrigation_mm = ...
    sum(irrigation)*dt;

totalRainfall_mm = ...
    sum(rainfall)*dt;

totalET_mm = ...
    sum(ET_actual_total)*dt*1000;

totalDrainage_mm = ...
    sum(q3d)*dt*1000;

totalInfiltration_mm = ...
    sum(infiltration)*dt*1000;

totalRunoff_mm = ...
    sum(runoff)*dt*1000;

%% ------------------------------------------------------------
% Return structure
% ------------------------------------------------------------

sim.time = time;

sim.theta = theta;

sim.storage = storage;

sim.ET_actual_total = ...
    ET_actual_total;

sim.soil_stress = ...
    soil_stress;

sim.q3d = q3d;

sim.totalIrrigation_mm = ...
    totalIrrigation_mm;

sim.totalRainfall_mm = ...
    totalRainfall_mm;

sim.totalET_mm = ...
    totalET_mm;

sim.totalDrainage_mm = ...
    totalDrainage_mm;

sim.totalInfiltration_mm = ...
    totalInfiltration_mm;

sim.totalRunoff_mm = ...
    totalRunoff_mm;

sim.finalStorage_mm = ...
    storage(end)*1000;

end


%% ============================================================
% LOCAL FUNCTION
% Metric Extraction
% =============================================================

function value = getMetricValue( ...
    metricIndex, ...
    parameterIndex, ...
    factorIndex, ...
    meanTheta, ...
    minimumTheta, ...
    maximumTheta, ...
    finalStorage, ...
    actualET, ...
    deepDrainage, ...
    totalIrrigation, ...
    waterStress)

switch metricIndex

    case 1

        value = ...
            meanTheta(parameterIndex,factorIndex);

    case 2

        value = ...
            minimumTheta(parameterIndex,factorIndex);

    case 3

        value = ...
            maximumTheta(parameterIndex,factorIndex);

    case 4

        value = ...
            finalStorage(parameterIndex,factorIndex);

    case 5

        value = ...
            actualET(parameterIndex,factorIndex);

    case 6

        value = ...
            deepDrainage(parameterIndex,factorIndex);

    case 7

        value = ...
            totalIrrigation(parameterIndex,factorIndex);

    case 8

        value = ...
            waterStress(parameterIndex,factorIndex);

    otherwise

        error('Unknown metric index.');

end

end