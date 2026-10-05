%% V3_02_ParameterSensitivityAnalysis
% One-at-a-Time (OAT) parameter sensitivity analysis
% for the validated V3 reduced-order 3-layer soil-water model.
%
% IMPORTANT:
% This script reproduces the original V3 solver logic.
% New MATLAB files must start with a letter.

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================================\n');
fprintf(' V3 PARAMETER SENSITIVITY ANALYSIS\n');
fprintf('============================================================\n\n');

%% ============================================================
% 1. LOAD VALIDATED V3 BASELINE
% =============================================================

baselineFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(baselineFile)
    error('Baseline file not found: %s', baselineFile);
end

D = load(baselineFile);

if isfield(D,'results')
    base = D.results;
else
    base = D;
end

fprintf('Baseline file loaded successfully.\n');

%% ============================================================
% 2. READ VARIABLES ACTUALLY STORED IN BASELINE
% =============================================================

time      = base.time;
dt        = base.dt;
T         = base.T;

theta     = base.theta;

theta_r   = base.theta_r;
theta_s   = base.theta_s;
theta_FC  = base.theta_FC;
theta_WP  = base.theta_WP;

Z         = base.Z;

%% ============================================================
% 3. DEFINE ORIGINAL V3 PARAMETERS NOT STORED IN RESULTS
% ============================================================

% Initial condition is taken directly from the first saved state.
theta0 = theta(1,:)';

% Original V3 ET distribution.
ET_fraction = [0.50; 0.30; 0.20];

% Original V3 transfer / drainage parameters.
kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

% Original V3 infiltration parameter.
Kinf = 0.020;

%% ============================================================
% 4. ORIGINAL V3 EXTERNAL INPUTS
% ============================================================

N = length(time);

rainfall = zeros(N,1);

irrigation = zeros(N,1);
irrigation(time >= 20 & time < 60) = 8;

ET_potential = 4 * ones(N,1);

%% ============================================================
% 5. BASELINE SOLUTION FROM THE ORIGINAL V3 MODEL
% ============================================================

baseRun = runV3Model( ...
    time, dt, T, ...
    theta0, ...
    theta_r, theta_s, theta_FC, theta_WP, ...
    Z, ...
    rainfall, irrigation, ET_potential, ...
    ET_fraction, ...
    kp12, kp23, kp3d, Kinf);

%% ============================================================
% 6. BASELINE REPRODUCTION CHECK
% ============================================================

maxThetaDiff = max(abs(baseRun.theta(:) - base.theta(:)));

if isfield(base,'storage')
    maxStorageDiff = max(abs(baseRun.storage(:) - base.storage(:)));
else
    baseStorage = sum(base.theta .* Z',2);
    maxStorageDiff = max(abs(baseRun.storage(:) - baseStorage(:)));
end

if isfield(base,'ET_actual_total')
    maxETDiff = max(abs( ...
        baseRun.ET_actual_total(:) - ...
        base.ET_actual_total(:)));
else
    maxETDiff = NaN;
end

if isfield(base,'cumulative_drainage')
    baseDrainage = base.cumulative_drainage(end);
else
    baseDrainage = sum(baseRun.q3d) * dt;
end

baseRunDrainage = sum(baseRun.q3d) * dt;

drainageDiff = abs(baseRunDrainage - baseDrainage);

fprintf('\n');
fprintf('------------------------------------------------------------\n');
fprintf(' BASELINE REPRODUCTION CHECK\n');
fprintf('------------------------------------------------------------\n');

fprintf('Max theta difference      = %.16g\n',maxThetaDiff);
fprintf('Max storage difference    = %.16g\n',maxStorageDiff);

if ~isnan(maxETDiff)
    fprintf('Max ET difference          = %.16g\n',maxETDiff);
end

fprintf('Total drainage difference = %.16g mm\n', ...
    drainageDiff * 1000);

tol = 1e-10;

baselinePASS = ...
    maxThetaDiff <= tol && ...
    maxStorageDiff <= tol && ...
    (isnan(maxETDiff) || maxETDiff <= tol) && ...
    drainageDiff <= tol;

if baselinePASS
    fprintf('\nBASELINE REPRODUCTION: PASS\n');
else
    fprintf('\nBASELINE REPRODUCTION: FAIL\n');
    error(['The sensitivity solver does not reproduce the validated ', ...
           'V3 baseline. Stop before sensitivity analysis.']);
end

%% ============================================================
% 7. PARAMETERS FOR OAT ANALYSIS
% ============================================================

parameterNames = { ...
    'theta_r'
    'theta_s'
    'theta_FC'
    'theta_WP'
    'kp12'
    'kp23'
    'kp3d'
    'Kinf'
    };

parameterValues = [ ...
    theta_r
    theta_s
    theta_FC
    theta_WP
    kp12
    kp23
    kp3d
    Kinf
    ];

scaleFactors = [0.80 0.90 1.00 1.10 1.20];

nParameters = length(parameterNames);
nLevels     = length(scaleFactors);

%% ============================================================
% 8. PREALLOCATE RESULTS
% ============================================================

meanTheta      = zeros(nParameters,nLevels);
minTheta       = zeros(nParameters,nLevels);
maxTheta       = zeros(nParameters,nLevels);

finalStorage   = zeros(nParameters,nLevels);

actualET       = zeros(nParameters,nLevels);
deepDrainage   = zeros(nParameters,nLevels);

meanStress     = zeros(nParameters,nLevels);
waterStress    = zeros(nParameters,nLevels);

%% ============================================================
% 9. OAT SENSITIVITY ANALYSIS
% ============================================================

fprintf('\n');
fprintf('------------------------------------------------------------\n');
fprintf(' RUNNING OAT SENSITIVITY ANALYSIS\n');
fprintf('------------------------------------------------------------\n');

for p = 1:nParameters

    fprintf('\nParameter %d/%d: %s\n', ...
        p,nParameters,parameterNames{p});

    for s = 1:nLevels

        scale = scaleFactors(s);

        % Start from original V3 parameter set.
        tr  = theta_r;
        ts  = theta_s;
        tfc = theta_FC;
        twp = theta_WP;

        k12 = kp12;
        k23 = kp23;
        k3d = kp3d;

        kinf = Kinf;

        % Perturb only the selected parameter.
        switch parameterNames{p}

            case 'theta_r'
                tr = theta_r * scale;

            case 'theta_s'
                ts = theta_s * scale;

            case 'theta_FC'
                tfc = theta_FC * scale;

            case 'theta_WP'
                twp = theta_WP * scale;

            case 'kp12'
                k12 = kp12 * scale;

            case 'kp23'
                k23 = kp23 * scale;

            case 'kp3d'
                k3d = kp3d * scale;

            case 'Kinf'
                kinf = Kinf * scale;

        end

        % Physical consistency check.
        if ~(tr < twp && twp < tfc && tfc < ts)
            error(['Invalid parameter combination for %s at ', ...
                   'scale %.2f.'], ...
                   parameterNames{p},scale);
        end

        % Run exact V3 model.
        out = runV3Model( ...
            time, dt, T, ...
            theta0, ...
            tr, ts, tfc, twp, ...
            Z, ...
            rainfall, irrigation, ET_potential, ...
            ET_fraction, ...
            k12, k23, k3d, kinf);

        %% Store metrics

        meanTheta(p,s) = mean(out.theta(:));

        minTheta(p,s) = min(out.theta(:));

        maxTheta(p,s) = max(out.theta(:));

        finalStorage(p,s) = out.storage(end);

        actualET(p,s) = sum(out.ET_actual_total) * dt;

        deepDrainage(p,s) = sum(out.q3d) * dt;

        meanStress(p,s) = mean(out.soil_stress(:));

        waterStress(p,s) = ...
            mean(max(0,1-out.soil_stress(:)));

    end
end

fprintf('\nSensitivity analysis completed successfully.\n');

%% ============================================================
% 10. CONVERT FLUX RESULTS TO mm
% ============================================================

actualET_mm     = actualET * 1000;
deepDrainage_mm = deepDrainage * 1000;
finalStorage_mm = finalStorage * 1000;

%% ============================================================
% 11. NORMALIZED SENSITIVITY
% ============================================================

% Metrics:
% 1 = Mean theta
% 2 = Minimum theta
% 3 = Maximum theta
% 4 = Final storage
% 5 = Actual ET
% 6 = Deep drainage
% 7 = Mean water stress

normalizedSensitivity = zeros(nParameters,7);

for p = 1:nParameters

    x = parameterValues(p);

    % Relative parameter perturbation.
    dx = scaleFactors - 1;

    % Metric values.
    y1 = meanTheta(p,:);
    y2 = minTheta(p,:);
    y3 = maxTheta(p,:);
    y4 = finalStorage_mm(p,:);
    y5 = actualET_mm(p,:);
    y6 = deepDrainage_mm(p,:);
    y7 = waterStress(p,:);

    % Baseline values.
    y10 = y1(3);
    y20 = y2(3);
    y30 = y3(3);
    y40 = y4(3);
    y50 = y5(3);
    y60 = y6(3);
    y70 = y7(3);

    % Dimensionless local sensitivity:
    %
    % S = (relative change in output) /
    %     (relative change in parameter)

    normalizedSensitivity(p,1) = ...
        mean((y1-y10)./y10 ./ dx, 'omitnan');

    normalizedSensitivity(p,2) = ...
        mean((y2-y20)./y20 ./ dx, 'omitnan');

    normalizedSensitivity(p,3) = ...
        mean((y3-y30)./y30 ./ dx, 'omitnan');

    normalizedSensitivity(p,4) = ...
        mean((y4-y40)./y40 ./ dx, 'omitnan');

    normalizedSensitivity(p,5) = ...
        mean((y5-y50)./y50 ./ dx, 'omitnan');

    normalizedSensitivity(p,6) = ...
        mean((y6-y60)./y60 ./ dx, 'omitnan');

    normalizedSensitivity(p,7) = ...
        mean((y7-y70)./y70 ./ dx, 'omitnan');

end

%% ============================================================
% 12. OVERALL SENSITIVITY SCORE
% ============================================================

sensitivityScore = mean(abs(normalizedSensitivity),2);

[sensitivityScoreSorted,rankingIndex] = ...
    sort(sensitivityScore,'descend');

rankingNames = parameterNames(rankingIndex);

%% ============================================================
% 13. DISPLAY RESULTS
% ============================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' SENSITIVITY RANKING\n');
fprintf('============================================================\n');

for r = 1:nParameters

    idx = rankingIndex(r);

    fprintf('%d. %-12s Score = %.6f\n', ...
        r,parameterNames{idx},sensitivityScore(idx));

end

fprintf('\n');

%% ============================================================
% 14. DISPLAY NORMALIZED SENSITIVITY MATRIX
% ============================================================

fprintf('============================================================\n');
fprintf(' NORMALIZED SENSITIVITY MATRIX\n');
fprintf('============================================================\n\n');

fprintf('%12s %12s %12s %12s %12s %12s %12s %12s\n', ...
    'Parameter', ...
    'MeanTheta', ...
    'MinTheta', ...
    'MaxTheta', ...
    'FinalStor', ...
    'ActualET', ...
    'Drainage', ...
    'WaterStress');

for p = 1:nParameters

    fprintf('%12s ',parameterNames{p});

    fprintf('%12.5f ',normalizedSensitivity(p,:));

    fprintf('\n');

end

%% ============================================================
% 15. BASELINE VALUES
% ============================================================

baselineMeanTheta = baseRun.theta;
baselineStorage = baseRun.storage;

baselineActualET = sum(baseRun.ET_actual_total) * dt;
baselineDrainage = sum(baseRun.q3d) * dt * 1000;

fprintf('\n');
fprintf('============================================================\n');
fprintf(' BASELINE METRICS\n');
fprintf('============================================================\n');

fprintf('Mean theta       = %.6f\n', ...
    mean(baselineMeanTheta(:)));

fprintf('Min theta        = %.6f\n', ...
    min(baselineMeanTheta(:)));

fprintf('Max theta        = %.6f\n', ...
    max(baselineMeanTheta(:)));

fprintf('Final storage    = %.6f mm\n', ...
    baselineStorage(end)*1000);

fprintf('Actual ET        = %.6f mm\n', ...
    baselineActualET*1000);

fprintf('Deep drainage    = %.6f mm\n', ...
    baselineDrainage);

%% ============================================================
% 16. SAVE RESULTS
% ============================================================

results = struct();

results.parameterNames = parameterNames;
results.parameterValues = parameterValues;
results.scaleFactors = scaleFactors;

results.meanTheta = meanTheta;
results.minTheta = minTheta;
results.maxTheta = maxTheta;

results.finalStorage_mm = finalStorage_mm;

results.actualET_mm = actualET_mm;
results.deepDrainage_mm = deepDrainage_mm;

results.meanStress = meanStress;
results.waterStress = waterStress;

results.normalizedSensitivity = normalizedSensitivity;

results.sensitivityScore = sensitivityScore;

results.rankingIndex = rankingIndex;
results.rankingNames = rankingNames;
results.sensitivityScoreSorted = sensitivityScoreSorted;

results.baselineMeanTheta = mean(baselineMeanTheta(:));
results.baselineMinTheta = min(baselineMeanTheta(:));
results.baselineMaxTheta = max(baselineMeanTheta(:));

results.baselineFinalStorage_mm = ...
    baselineStorage(end)*1000;

results.baselineActualET_mm = baselineActualET*1000;

results.baselineDeepDrainage_mm = baselineDrainage;

results.baselineMaxThetaDiff = maxThetaDiff;
results.baselineMaxStorageDiff = maxStorageDiff;
results.baselineMaxETDiff = maxETDiff;
results.baselineDrainageDiff = drainageDiff;

results.baselineReproductionPASS = baselinePASS;

save('V3_02_ParameterSensitivityAnalysis_Results.mat', ...
    'results');

fprintf('\nResults saved:\n');
fprintf('V3_02_ParameterSensitivityAnalysis_Results.mat\n');

%% ============================================================
% 17. FIGURE 1 — SENSITIVITY RANKING
% ============================================================

figure;

bar(sensitivityScoreSorted);

set(gca, ...
    'XTick',1:nParameters, ...
    'XTickLabel',rankingNames);

xlabel('Parameter');
ylabel('Overall Sensitivity Score');

title('V3 Parameter Sensitivity Ranking');

grid on;

xtickangle(45);

saveas(gcf, ...
    '07_V3_Sensitivity_Ranking_Corrected.png');

%% ============================================================
% 18. FIGURE 2 — SENSITIVITY HEATMAP
% ============================================================

figure;

imagesc(normalizedSensitivity);

colorbar;

set(gca, ...
    'XTick',1:7, ...
    'XTickLabel',{ ...
    'Mean Theta', ...
    'Min Theta', ...
    'Max Theta', ...
    'Final Storage', ...
    'Actual ET', ...
    'Deep Drainage', ...
    'Water Stress'}, ...
    'YTick',1:nParameters, ...
    'YTickLabel',parameterNames);

xlabel('Output Metric');
ylabel('Parameter');

title('Normalized Parameter Sensitivity');

xtickangle(45);

saveas(gcf, ...
    '08_V3_Sensitivity_Heatmap_Corrected.png');

%% ============================================================
% 19. FIGURE 3 — MEAN THETA
% ============================================================

figure;

hold on;

for p = 1:nParameters

    plot(scaleFactors*100, ...
        meanTheta(p,:), ...
        '-o', ...
        'DisplayName',parameterNames{p});

end

xlabel('Parameter Value (% of Baseline)');
ylabel('Mean Volumetric Water Content');

title('Sensitivity of Mean Soil Moisture');

legend('Location','best');

grid on;

saveas(gcf, ...
    '09_V3_Sensitivity_MeanTheta_Corrected.png');

%% ============================================================
% 20. FIGURE 4 — FINAL STORAGE
% ============================================================

figure;

hold on;

for p = 1:nParameters

    plot(scaleFactors*100, ...
        finalStorage_mm(p,:), ...
        '-o', ...
        'DisplayName',parameterNames{p});

end

xlabel('Parameter Value (% of Baseline)');
ylabel('Final Storage (mm)');

title('Sensitivity of Final Soil-Water Storage');

legend('Location','best');

grid on;

saveas(gcf, ...
    '10_V3_Sensitivity_FinalStorage_Corrected.png');

%% ============================================================
% 21. FIGURE 5 — ACTUAL ET
% ============================================================

figure;

hold on;

for p = 1:nParameters

    plot(scaleFactors*100, ...
        actualET_mm(p,:), ...
        '-o', ...
        'DisplayName',parameterNames{p});

end

xlabel('Parameter Value (% of Baseline)');
ylabel('Actual ET (mm)');

title('Sensitivity of Actual Evapotranspiration');

legend('Location','best');

grid on;

saveas(gcf, ...
    '11_V3_Sensitivity_ET_Corrected.png');

%% ============================================================
% 22. FIGURE 6 — DEEP DRAINAGE
% ============================================================

figure;

hold on;

for p = 1:nParameters

    plot(scaleFactors*100, ...
        deepDrainage_mm(p,:), ...
        '-o', ...
        'DisplayName',parameterNames{p});

end

xlabel('Parameter Value (% of Baseline)');
ylabel('Deep Drainage (mm)');

title('Sensitivity of Deep Drainage');

legend('Location','best');

grid on;

saveas(gcf, ...
    '12_V3_Sensitivity_Drainage_Corrected.png');

%% ============================================================
% 23. FINAL MESSAGE
% ============================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' SENSITIVITY ANALYSIS FINISHED\n');
fprintf('============================================================\n');

fprintf('\nBaseline reproduction: PASS\n');

fprintf('\nTop three sensitive parameters:\n');

for r = 1:3

    fprintf('%d. %s\n', ...
        r,rankingNames{r});

end

fprintf('\nAll figures saved successfully.\n');

%% ============================================================
% LOCAL FUNCTION — EXACT V3 SOLVER
% ============================================================

function out = runV3Model( ...
    time, dt, T, ...
    theta0, ...
    theta_r, theta_s, theta_FC, theta_WP, ...
    Z, ...
    rainfall, irrigation, ET_potential, ...
    ET_fraction, ...
    kp12, kp23, kp3d, Kinf)

%% ------------------------------------------------------------
% Model dimensions
% ------------------------------------------------------------

N = length(time);

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

%% ------------------------------------------------------------
% Initial storage
% ------------------------------------------------------------

S_current = theta0 .* Z;

%% ------------------------------------------------------------
% Storage limits
% ------------------------------------------------------------

S_min = theta_r .* Z;
S_max = theta_s .* Z;
S_FC  = theta_FC .* Z;
S_WP  = theta_WP .* Z;

%% ------------------------------------------------------------
% Preallocation
% ------------------------------------------------------------

theta = zeros(N,3);

soil_stress = zeros(N,3);

ET_actual = zeros(N,3);

q12 = zeros(N,1);
q23 = zeros(N,1);
q3d = zeros(N,1);

infiltration = zeros(N,1);
runoff = zeros(N,1);

storage = zeros(N,1);

%% ------------------------------------------------------------
% Initial state
% ------------------------------------------------------------

theta(1,:) = (S_current ./ Z)';

storage(1) = sum(S_current);

%% ------------------------------------------------------------
% Main simulation loop
% ------------------------------------------------------------

for k = 1:N-1

    %% External water input

    I = irrigation(k) / 1000;

    P = rainfall(k) / 1000;

    water_input = I + P;

    %% --------------------------------------------------------
    % Infiltration
    % --------------------------------------------------------

    current_theta1 = S_current(1) / Z1;

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

    runoff(k) = ...
        max(0,water_input-actual_infiltration);

    infiltration(k) = actual_infiltration;

    S_current(1) = ...
        S_current(1) + actual_infiltration*dt;

    %% --------------------------------------------------------
    % Soil water stress
    % --------------------------------------------------------

    theta_current = S_current ./ Z;

    stress = ...
        (theta_current-theta_WP) ./ ...
        (theta_FC-theta_WP);

    stress = ...
        min(max(stress,0),1);

    soil_stress(k,:) = stress';

    %% --------------------------------------------------------
    % Evapotranspiration
    % --------------------------------------------------------

    ET_demand = ...
        (ET_potential(k)/1000) .* ...
        ET_fraction .* ...
        stress;

    for i = 1:3

        available_water = ...
            max(0,S_current(i)-S_min(i));

        ET_remove = ...
            min(ET_demand(i)*dt,available_water);

        S_current(i) = ...
            S_current(i)-ET_remove;

        ET_actual(k,i) = ...
            ET_remove/dt;

    end

    %% --------------------------------------------------------
    % Layer 1 -> Layer 2
    % --------------------------------------------------------

    excess1 = ...
        max(0,S_current(1)-S_FC(1));

    potential_q12 = ...
        kp12 * excess1;

    max_transfer12 = ...
        S_current(1)-S_min(1);

    max_receive12 = ...
        S_max(2)-S_current(2);

    transfer12 = ...
        min(potential_q12*dt,max_transfer12);

    transfer12 = ...
        min(transfer12,max_receive12);

    transfer12 = ...
        max(transfer12,0);

    S_current(1) = ...
        S_current(1)-transfer12;

    S_current(2) = ...
        S_current(2)+transfer12;

    q12(k) = transfer12/dt;

    %% --------------------------------------------------------
    % Layer 2 -> Layer 3
    % --------------------------------------------------------

    excess2 = ...
        max(0,S_current(2)-S_FC(2));

    potential_q23 = ...
        kp23 * excess2;

    max_transfer23 = ...
        S_current(2)-S_min(2);

    max_receive23 = ...
        S_max(3)-S_current(3);

    transfer23 = ...
        min(potential_q23*dt,max_transfer23);

    transfer23 = ...
        min(transfer23,max_receive23);

    transfer23 = ...
        max(transfer23,0);

    S_current(2) = ...
        S_current(2)-transfer23;

    S_current(3) = ...
        S_current(3)+transfer23;

    q23(k) = transfer23/dt;

    %% --------------------------------------------------------
    % Deep drainage
    % --------------------------------------------------------

    excess3 = ...
        max(0,S_current(3)-S_FC(3));

    potential_q3d = ...
        kp3d * excess3;

    max_drainage = ...
        S_current(3)-S_min(3);

    drainage = ...
        min(potential_q3d*dt,max_drainage);

    drainage = ...
        max(drainage,0);

    S_current(3) = ...
        S_current(3)-drainage;

    q3d(k) = drainage/dt;

    %% --------------------------------------------------------
    % Physical bounds
    % --------------------------------------------------------

    S_current = ...
        min(max(S_current,S_min),S_max);

    %% --------------------------------------------------------
    % Store state
    % --------------------------------------------------------

    theta(k+1,:) = ...
        (S_current ./ Z)';

    storage(k+1) = ...
        sum(S_current);

end

%% ------------------------------------------------------------
% Final stress calculation
% ------------------------------------------------------------

soil_stress = ...
    (theta-theta_WP') ./ ...
    (theta_FC'-theta_WP');

soil_stress = ...
    min(max(soil_stress,0),1);

%% ------------------------------------------------------------
% Total ET
% ------------------------------------------------------------

ET_actual_total = ...
    sum(ET_actual,2);

%% ------------------------------------------------------------
% Output structure
% ------------------------------------------------------------

out.time = time;

out.dt = dt;

out.T = T;

out.theta = theta;

out.storage = storage;

out.soil_stress = soil_stress;

out.ET_actual = ET_actual;

out.ET_actual_total = ET_actual_total;

out.q12 = q12;

out.q23 = q23;

out.q3d = q3d;

out.infiltration = infiltration;

out.runoff = runoff;

end