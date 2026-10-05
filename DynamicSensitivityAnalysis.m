%% ============================================================
% DynamicSensitivityAnalysis
%
% AI-Driven Smart Irrigation
%
% V3 Dynamic Parameter Sensitivity Analysis
%
% Purpose:
%   Determine how the sensitivity of the validated V3
%   soil-water model evolves with time.
%
% Important:
%   The original validated V3 model is NOT modified.
%
% Method:
%   Central finite-difference normalized sensitivity
%
%   S_p(t) =
%       (p0 / y0(t)) *
%       [y(p0+dp,t)-y(p0-dp,t)] / [2*dp]
%
% where:
%   p0 = baseline parameter
%   dp = 10% of baseline parameter
%
% Outputs:
%   1. Root-zone mean soil moisture sensitivity
%   2. Soil storage sensitivity
%   3. Actual ET sensitivity
%   4. Deep drainage sensitivity
%
% Version: Dynamic Sensitivity V1.0
%
% ============================================================

clc;
clear;
close all;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 DYNAMIC PARAMETER SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');

%% ============================================================
% 1. Load Validated V3 Results
% =============================================================

resultFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(resultFile)

    error(['\nValidated V3 result file not found:\n' ...
           '%s\n\n' ...
           'Make sure this file is in the main project folder.\n'], ...
           resultFile);

end

data = load(resultFile);

if ~isfield(data,'results')

    error(['\nThe file does not contain the expected variable: results\n']);

end

results = data.results;

fprintf('\nValidated V3 results loaded successfully.\n');

%% ============================================================
% 2. Extract Baseline Configuration
% =============================================================

time = results.time;
dt   = results.dt;
T    = results.T;

N = length(time);

theta0 = [ ...
    results.theta(1,1); ...
    results.theta(1,2); ...
    results.theta(1,3)];

theta_r  = results.theta_r;
theta_s  = results.theta_s;
theta_FC = results.theta_FC;
theta_WP = results.theta_WP;

Z = results.Z;

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

root_depth = sum(Z);

irrigation = results.irrigation;
rainfall = results.rainfall;
ET_potential = results.ET_potential;

ET_fraction = [0.50; 0.30; 0.20];

kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

Kinf = 0.020;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' BASELINE V3 CONFIGURATION\n');
fprintf('====================================================\n');

fprintf('\n');
fprintf('Simulation time       = %.2f days\n',T);
fprintf('Time step             = %.4f day\n',dt);
fprintf('Root-zone depth       = %.2f m\n',root_depth);

fprintf('\n');
fprintf('theta_r               = %.6f\n',theta_r);
fprintf('theta_s               = %.6f\n',theta_s);
fprintf('theta_FC              = %.6f\n',theta_FC);
fprintf('theta_WP              = %.6f\n',theta_WP);

fprintf('\n');
fprintf('kp12                  = %.6f\n',kp12);
fprintf('kp23                  = %.6f\n',kp23);
fprintf('kp3d                  = %.6f\n',kp3d);
fprintf('Kinf                  = %.6f m/day\n',Kinf);

%% ============================================================
% 3. Parameter Definition
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

parameterValues = [ ...
    theta_r
    theta_s
    theta_FC
    theta_WP
    kp12
    kp23
    kp3d
    Kinf];

nParameters = length(parameterNames);

%% ============================================================
% 4. Finite-Difference Perturbation
% =============================================================

perturbationFraction = 0.10;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' FINITE-DIFFERENCE DESIGN\n');
fprintf('====================================================\n');

fprintf('\nPerturbation level = +/- %.0f%%\n', ...
    perturbationFraction*100);

fprintf('\n');

%% ============================================================
% 5. Baseline Simulation
% =============================================================

fprintf('Running baseline model...\n');

baseline = runV3Model( ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf, ...
    time, ...
    dt, ...
    Z, ...
    theta0, ...
    irrigation, ...
    rainfall, ...
    ET_potential, ...
    ET_fraction);

%% ============================================================
% 6. Baseline Reproduction Check
% =============================================================

thetaDifference = ...
    max(abs(baseline.theta(:) - results.theta(:)));

storageDifference = ...
    max(abs(baseline.storage(:) - results.storage(:)));

ETDifference = ...
    max(abs(baseline.ET_actual_total(:) - ...
           results.ET_actual_total(:)));

drainageDifference = ...
    abs(sum(baseline.q3d)*dt*1000 - ...
        sum(results.q3d)*dt*1000);

fprintf('\n');
fprintf('====================================================\n');
fprintf(' BASELINE REPRODUCTION CHECK\n');
fprintf('====================================================\n');

fprintf('\nMaximum theta difference:\n');
fprintf('%.12e\n',thetaDifference);

fprintf('\nMaximum storage difference:\n');
fprintf('%.12e m\n',storageDifference);

fprintf('\nMaximum ET difference:\n');
fprintf('%.12e m/day\n',ETDifference);

fprintf('\nTotal drainage difference:\n');
fprintf('%.12e mm\n',drainageDifference);

if thetaDifference < 1e-12 && ...
   storageDifference < 1e-12 && ...
   ETDifference < 1e-12 && ...
   drainageDifference < 1e-9

    fprintf('\nBASELINE REPRODUCTION: PASS\n');

else

    error(['\nBASELINE REPRODUCTION FAILED.\n' ...
           'Do not continue with sensitivity analysis.\n']);

end

%% ============================================================
% 7. Define Output Variables
% =============================================================

rootTheta_baseline = ...
    mean(baseline.theta,2);

storage_baseline = ...
    baseline.storage;

ET_baseline = ...
    baseline.ET_actual_total;

drainage_baseline = ...
    baseline.q3d;

stress_baseline = ...
    mean(baseline.soil_stress,2);

%% ============================================================
% 8. Allocate Sensitivity Matrices
% =============================================================

% Rows    = parameters
% Columns = time

Sensitivity_RootTheta = ...
    zeros(nParameters,N);

Sensitivity_Storage = ...
    zeros(nParameters,N);

Sensitivity_ET = ...
    zeros(nParameters,N);

Sensitivity_Drainage = ...
    zeros(nParameters,N);

Sensitivity_Stress = ...
    zeros(nParameters,N);

%% ============================================================
% 9. OAT Dynamic Sensitivity Analysis
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' RUNNING DYNAMIC OAT SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');

for p = 1:nParameters

    parameterName = parameterNames{p};

    p0 = parameterValues(p);

    dp = perturbationFraction * p0;

    pPlus  = p0 + dp;
    pMinus = p0 - dp;

    fprintf('\n');
    fprintf('Parameter %d/%d: %s\n', ...
        p,nParameters,parameterName);

    fprintf('Baseline = %.8f\n',p0);
    fprintf('+10%%     = %.8f\n',pPlus);
    fprintf('-10%%     = %.8f\n',pMinus);

    %% --------------------------------------------------------
    % Parameterized values
    % ---------------------------------------------------------

    theta_r_plus  = theta_r;
    theta_s_plus  = theta_s;
    theta_FC_plus = theta_FC;
    theta_WP_plus = theta_WP;

    kp12_plus = kp12;
    kp23_plus = kp23;
    kp3d_plus = kp3d;
    Kinf_plus = Kinf;

    theta_r_minus  = theta_r;
    theta_s_minus  = theta_s;
    theta_FC_minus = theta_FC;
    theta_WP_minus = theta_WP;

    kp12_minus = kp12;
    kp23_minus = kp23;
    kp3d_minus = kp3d;
    Kinf_minus = Kinf;

    %% --------------------------------------------------------
    % Apply positive perturbation
    % ---------------------------------------------------------

    switch parameterName

        case 'theta_r'
            theta_r_plus = pPlus;

        case 'theta_s'
            theta_s_plus = pPlus;

        case 'theta_FC'
            theta_FC_plus = pPlus;

        case 'theta_WP'
            theta_WP_plus = pPlus;

        case 'kp12'
            kp12_plus = pPlus;

        case 'kp23'
            kp23_plus = pPlus;

        case 'kp3d'
            kp3d_plus = pPlus;

        case 'Kinf'
            Kinf_plus = pPlus;

    end

    %% --------------------------------------------------------
    % Apply negative perturbation
    % ---------------------------------------------------------

    switch parameterName

        case 'theta_r'
            theta_r_minus = pMinus;

        case 'theta_s'
            theta_s_minus = pMinus;

        case 'theta_FC'
            theta_FC_minus = pMinus;

        case 'theta_WP'
            theta_WP_minus = pMinus;

        case 'kp12'
            kp12_minus = pMinus;

        case 'kp23'
            kp23_minus = pMinus;

        case 'kp3d'
            kp3d_minus = pMinus;

        case 'Kinf'
            Kinf_minus = pMinus;

    end

    %% --------------------------------------------------------
    % Run positive perturbation
    % ---------------------------------------------------------

    plusModel = runV3Model( ...
        theta_r_plus, ...
        theta_s_plus, ...
        theta_FC_plus, ...
        theta_WP_plus, ...
        kp12_plus, ...
        kp23_plus, ...
        kp3d_plus, ...
        Kinf_plus, ...
        time, ...
        dt, ...
        Z, ...
        theta0, ...
        irrigation, ...
        rainfall, ...
        ET_potential, ...
        ET_fraction);

    %% --------------------------------------------------------
    % Run negative perturbation
    % ---------------------------------------------------------

    minusModel = runV3Model( ...
        theta_r_minus, ...
        theta_s_minus, ...
        theta_FC_minus, ...
        theta_WP_minus, ...
        kp12_minus, ...
        kp23_minus, ...
        kp3d_minus, ...
        Kinf_minus, ...
        time, ...
        dt, ...
        Z, ...
        theta0, ...
        irrigation, ...
        rainfall, ...
        ET_potential, ...
        ET_fraction);

    %% --------------------------------------------------------
    % Dynamic normalized sensitivity
    % ---------------------------------------------------------

    rootTheta_plus = ...
        mean(plusModel.theta,2);

    rootTheta_minus = ...
        mean(minusModel.theta,2);

    storage_plus = ...
        plusModel.storage;

    storage_minus = ...
        minusModel.storage;

    ET_plus = ...
        plusModel.ET_actual_total;

    ET_minus = ...
        minusModel.ET_actual_total;

    drainage_plus = ...
        plusModel.q3d;

    drainage_minus = ...
        minusModel.q3d;

    stress_plus = ...
        mean(plusModel.soil_stress,2);

    stress_minus = ...
        mean(minusModel.soil_stress,2);

    %% --------------------------------------------------------
    % Safe normalization
    % ---------------------------------------------------------

    denominatorTheta = ...
        max(abs(rootTheta_baseline),1e-8);

    denominatorStorage = ...
        max(abs(storage_baseline),1e-8);

    denominatorET = ...
        max(abs(ET_baseline),1e-10);

    denominatorDrainage = ...
        max(abs(drainage_baseline),1e-10);

    denominatorStress = ...
        max(abs(stress_baseline),1e-8);

    %% --------------------------------------------------------
    % Sensitivity calculation
    % ---------------------------------------------------------

    Sensitivity_RootTheta(p,:) = ...
        (p0 ./ denominatorTheta)' .* ...
        ((rootTheta_plus-rootTheta_minus)' ...
        ./ (2*dp));

    Sensitivity_Storage(p,:) = ...
        (p0 ./ denominatorStorage)' .* ...
        ((storage_plus-storage_minus)' ...
        ./ (2*dp));

    Sensitivity_ET(p,:) = ...
        (p0 ./ denominatorET)' .* ...
        ((ET_plus-ET_minus)' ...
        ./ (2*dp));

    Sensitivity_Drainage(p,:) = ...
        (p0 ./ denominatorDrainage)' .* ...
        ((drainage_plus-drainage_minus)' ...
        ./ (2*dp));

    Sensitivity_Stress(p,:) = ...
        (p0 ./ denominatorStress)' .* ...
        ((stress_plus-stress_minus)' ...
        ./ (2*dp));

    fprintf('Dynamic sensitivity calculated.\n');

end

%% ============================================================
% 10. Summary Statistics
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' DYNAMIC SENSITIVITY SUMMARY\n');
fprintf('====================================================\n');

MeanAbsSensitivity = ...
    mean(abs(Sensitivity_RootTheta),2);

MaxAbsSensitivity = ...
    max(abs(Sensitivity_RootTheta),[],2);

TimeOfMaximumSensitivity = zeros(nParameters,1);

for p = 1:nParameters

    [~,idx] = ...
        max(abs(Sensitivity_RootTheta(p,:)));

    TimeOfMaximumSensitivity(p) = ...
        time(idx);

end

fprintf('\n');
fprintf('%-12s %-15s %-15s %-15s\n', ...
    'Parameter', ...
    'Mean |S|', ...
    'Max |S|', ...
    'Time of Max');

fprintf('----------------------------------------------------\n');

for p = 1:nParameters

    fprintf('%-12s %-15.6f %-15.6f %-15.2f\n', ...
        parameterNames{p}, ...
        MeanAbsSensitivity(p), ...
        MaxAbsSensitivity(p), ...
        TimeOfMaximumSensitivity(p));

end

%% ============================================================
% 11. Dynamic Ranking
% =============================================================

[sortedScores,sortIndex] = ...
    sort(MeanAbsSensitivity,'descend');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' DYNAMIC ROOT-ZONE SENSITIVITY RANKING\n');
fprintf('====================================================\n');

for r = 1:nParameters

    idx = sortIndex(r);

    fprintf('%2d. %-12s Score = %.6f\n', ...
        r, ...
        parameterNames{idx}, ...
        sortedScores(r));

end

%% ============================================================
% 12. Figure 13 - Root-Zone Sensitivity Heatmap
% =============================================================

figure(13);

imagesc(time,1:nParameters, ...
    Sensitivity_RootTheta);

set(gca, ...
    'YTick',1:nParameters, ...
    'YTickLabel',parameterNames);

xlabel('Time [day]');
ylabel('Model Parameter');

title('Dynamic Sensitivity of Root-Zone Soil Moisture');

colorbar;

grid on;

saveas(gcf, ...
    '13_V3_DynamicSensitivity_RootTheta.png');

%% ============================================================
% 13. Figure 14 - Storage Sensitivity
% =============================================================

figure(14);

hold on;

for p = 1:nParameters

    plot(time, ...
        Sensitivity_Storage(p,:), ...
        'LineWidth',1.5);

end

hold off;

grid on;

xlabel('Time [day]');
ylabel('Normalized Sensitivity');

title('Dynamic Sensitivity of Soil Water Storage');

legend(parameterNames, ...
    'Location','best');

saveas(gcf, ...
    '14_V3_DynamicSensitivity_Storage.png');

%% ============================================================
% 14. Figure 15 - Actual ET Sensitivity
% =============================================================

figure(15);

hold on;

for p = 1:nParameters

    plot(time, ...
        Sensitivity_ET(p,:), ...
        'LineWidth',1.5);

end

hold off;

grid on;

xlabel('Time [day]');
ylabel('Normalized Sensitivity');

title('Dynamic Sensitivity of Actual Evapotranspiration');

legend(parameterNames, ...
    'Location','best');

saveas(gcf, ...
    '15_V3_DynamicSensitivity_ET.png');

%% ============================================================
% 15. Figure 16 - Deep Drainage Sensitivity
% =============================================================

figure(16);

hold on;

for p = 1:nParameters

    plot(time, ...
        Sensitivity_Drainage(p,:), ...
        'LineWidth',1.5);

end

hold off;

grid on;

xlabel('Time [day]');
ylabel('Normalized Sensitivity');

title('Dynamic Sensitivity of Deep Drainage');

legend(parameterNames, ...
    'Location','best');

saveas(gcf, ...
    '16_V3_DynamicSensitivity_Drainage.png');

%% ============================================================
% 16. Figure 17 - Dynamic Ranking
% =============================================================

figure(17);

bar(sortedScores);

grid on;

xlabel('Parameter Rank');
ylabel('Mean Absolute Sensitivity');

title('V3 Dynamic Parameter Sensitivity Ranking');

set(gca, ...
    'XTick',1:nParameters, ...
    'XTickLabel',parameterNames);

saveas(gcf, ...
    '17_V3_DynamicSensitivity_Ranking.png');

%% ============================================================
% 17. Save Results
% =============================================================

DynamicSensitivity = struct();

DynamicSensitivity.version = ...
    'V1.0';

DynamicSensitivity.method = ...
    'Central finite difference normalized sensitivity';

DynamicSensitivity.perturbationFraction = ...
    perturbationFraction;

DynamicSensitivity.time = ...
    time;

DynamicSensitivity.parameterNames = ...
    parameterNames;

DynamicSensitivity.parameterValues = ...
    parameterValues;

DynamicSensitivity.RootThetaSensitivity = ...
    Sensitivity_RootTheta;

DynamicSensitivity.StorageSensitivity = ...
    Sensitivity_Storage;

DynamicSensitivity.ETSensitivity = ...
    Sensitivity_ET;

DynamicSensitivity.DrainageSensitivity = ...
    Sensitivity_Drainage;

DynamicSensitivity.StressSensitivity = ...
    Sensitivity_Stress;

DynamicSensitivity.MeanAbsSensitivity = ...
    MeanAbsSensitivity;

DynamicSensitivity.MaxAbsSensitivity = ...
    MaxAbsSensitivity;

DynamicSensitivity.TimeOfMaximumSensitivity = ...
    TimeOfMaximumSensitivity;

DynamicSensitivity.DynamicRanking = ...
    parameterNames(sortIndex);

DynamicSensitivity.DynamicRankingScores = ...
    sortedScores;

DynamicSensitivity.baselineReproduction = struct( ...
    'thetaDifference',thetaDifference, ...
    'storageDifference',storageDifference, ...
    'ETDifference',ETDifference, ...
    'drainageDifference',drainageDifference);

save( ...
    'V3_DynamicSensitivityAnalysis_Results.mat', ...
    'DynamicSensitivity');

%% ============================================================
% 18. Final Report
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' DYNAMIC SENSITIVITY ANALYSIS COMPLETED\n');
fprintf('====================================================\n');

fprintf('\nBaseline reproduction: PASS\n');

fprintf('\nResults saved to:\n');
fprintf('V3_DynamicSensitivityAnalysis_Results.mat\n');

fprintf('\nFigures saved:\n');
fprintf('13_V3_DynamicSensitivity_RootTheta.png\n');
fprintf('14_V3_DynamicSensitivity_Storage.png\n');
fprintf('15_V3_DynamicSensitivity_ET.png\n');
fprintf('16_V3_DynamicSensitivity_Drainage.png\n');
fprintf('17_V3_DynamicSensitivity_Ranking.png\n');

fprintf('\n');
fprintf('====================================================\n');
fprintf(' END OF DYNAMIC SENSITIVITY ANALYSIS\n');
fprintf('====================================================\n');


%% ============================================================
% LOCAL FUNCTION
% V3 PARAMETERIZED SOIL-WATER MODEL
% =============================================================

function out = runV3Model( ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf, ...
    time, ...
    dt, ...
    Z, ...
    theta0, ...
    irrigation, ...
    rainfall, ...
    ET_potential, ...
    ET_fraction)

%% ------------------------------------------------------------
% Simulation dimensions
% ------------------------------------------------------------

N = length(time);

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

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
S_FC  = theta_FC .* Z;

%% ------------------------------------------------------------
% Allocate flux variables
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

    %% --------------------------------------------------------
    % External water input
    % ---------------------------------------------------------

    I = irrigation(k) / 1000;

    P = rainfall(k) / 1000;

    water_input = I + P;

    %% --------------------------------------------------------
    % Surface infiltration
    % ---------------------------------------------------------

    current_theta1 = ...
        S_current(1) / Z1;

    remaining_capacity = ...
        S_max(1) - S_current(1);

    denominator = ...
        theta_s - theta_FC;

    if abs(denominator) < 1e-12

        saturation_factor = 0;

    else

        saturation_factor = ...
            (theta_s-current_theta1) / denominator;

    end

    saturation_factor = ...
        min(max(saturation_factor,0),1);

    infiltration_capacity = ...
        Kinf * saturation_factor;

    potential_infiltration = ...
        min(water_input,infiltration_capacity);

    actual_infiltration = ...
        min(potential_infiltration, ...
            remaining_capacity/dt);

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
        actual_infiltration*dt;

    %% --------------------------------------------------------
    % Soil-water stress
    % ---------------------------------------------------------

    theta_current = ...
        S_current ./ Z;

    denominatorStress = ...
        theta_FC-theta_WP;

    if abs(denominatorStress) < 1e-12

        stress = zeros(3,1);

    else

        stress = ...
            (theta_current-theta_WP) ./ ...
            denominatorStress;

    end

    stress = ...
        min(max(stress,0),1);

    soil_stress(k,:) = ...
        stress';

    %% --------------------------------------------------------
    % Actual evapotranspiration
    % ---------------------------------------------------------

    ET_demand = ...
        (ET_potential(k)/1000) .* ...
        ET_fraction .* ...
        stress;

    for i = 1:3

        available_water = ...
            max(0,S_current(i)-S_min(i));

        ET_remove = ...
            min(ET_demand(i)*dt, ...
                available_water);

        S_current(i) = ...
            S_current(i)-ET_remove;

        ET_actual(k,i) = ...
            ET_remove/dt;

    end

    %% --------------------------------------------------------
    % Percolation Layer 1 -> Layer 2
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
        min(potential_q12*dt, ...
            max_transfer12);

    transfer12 = ...
        min(transfer12, ...
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
    % Percolation Layer 2 -> Layer 3
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
        min(potential_q23*dt, ...
            max_transfer23);

    transfer23 = ...
        min(transfer23, ...
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
    % Deep drainage
    % ---------------------------------------------------------

    excess3 = ...
        max(0,S_current(3)-S_FC(3));

    potential_q3d = ...
        kp3d * excess3;

    max_drainage = ...
        S_current(3)-S_min(3);

    drainage = ...
        min(potential_q3d*dt, ...
            max_drainage);

    drainage = ...
        max(drainage,0);

    S_current(3) = ...
        S_current(3)-drainage;

    q3d(k) = ...
        drainage/dt;

    %% --------------------------------------------------------
    % Physical bounds
    % ---------------------------------------------------------

    S_current = ...
        min(max(S_current,S_min),S_max);

    %% --------------------------------------------------------
    % Store state
    % ---------------------------------------------------------

    S(k+1,:) = ...
        S_current';

    theta(k+1,:) = ...
        (S_current ./ Z)';

end

%% ------------------------------------------------------------
% Final stress
% ------------------------------------------------------------

theta1 = theta(:,1);

theta2 = theta(:,2);

theta3 = theta(:,3);

denominatorStress = ...
    theta_FC-theta_WP;

if abs(denominatorStress) < 1e-12

    stress1 = zeros(N,1);
    stress2 = zeros(N,1);
    stress3 = zeros(N,1);

else

    stress1 = ...
        (theta1-theta_WP) ./ ...
        denominatorStress;

    stress2 = ...
        (theta2-theta_WP) ./ ...
        denominatorStress;

    stress3 = ...
        (theta3-theta_WP) ./ ...
        denominatorStress;

end

stress1 = ...
    min(max(stress1,0),1);

stress2 = ...
    min(max(stress2,0),1);

stress3 = ...
    min(max(stress3,0),1);

soil_stress = ...
    [stress1,stress2,stress3];

%% ------------------------------------------------------------
% Total actual ET
% ------------------------------------------------------------

ET_actual_total = ...
    sum(ET_actual,2);

%% ------------------------------------------------------------
% Total storage
% ------------------------------------------------------------

storage = ...
    sum(S,2);

%% ------------------------------------------------------------
% Output structure
% ------------------------------------------------------------

out = struct();

out.theta = theta;

out.S = S;

out.storage = storage;

out.ET_actual = ET_actual;

out.ET_actual_total = ET_actual_total;

out.q12 = q12;

out.q23 = q23;

out.q3d = q3d;

out.infiltration = infiltration;

out.runoff = runoff;

out.soil_stress = soil_stress;

end