%% ================================================================
% UncertaintyAnalysis_V3_Final
%
% AI-Driven Smart Irrigation
% V3 Uncertainty & Robustness Analysis
%
% FINAL VALIDATED VERSION
%
% The V3 solver below follows the original V3 model equations.
% Water-balance validation uses consistent units:
%
%   Storage        -> m -> converted to mm
%   Irrigation     -> mm/day -> multiplied by dt
%   Rainfall       -> mm/day -> multiplied by dt
%   ET             -> m/day -> multiplied by dt -> mm
%   Drainage       -> m/day -> multiplied by dt -> mm
%   Runoff         -> m/day -> multiplied by dt -> mm
%
% Required file:
%   01_ReducedSoilWaterModel_V3_Results.mat
%
% ================================================================

clc;
clear;
close all;

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' V3 UNCERTAINTY & ROBUSTNESS ANALYSIS - FINAL\n');
fprintf('===============================================================\n\n');

%% ================================================================
% 1. LOAD REFERENCE V3 RESULTS
% ================================================================

baselineFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(baselineFile)
    error(['Baseline file not found: ', baselineFile]);
end

D = load(baselineFile);

if isfield(D,'results')
    base = D.results;
else
    names = fieldnames(D);

    if numel(names) == 1 && isstruct(D.(names{1}))
        base = D.(names{1});
    else
        error('Could not identify the V3 results structure.');
    end
end

fprintf('Reference file loaded successfully:\n');
fprintf('%s\n\n',baselineFile);

%% ================================================================
% 2. ORIGINAL V3 CONFIGURATION
% ================================================================

dt = 0.25;
T  = 120;

N = round(T/dt) + 1;
time = (0:N-1)' * dt;

theta_r  = 0.078;
theta_s  = 0.430;
theta_FC = 0.250;
theta_WP = 0.120;

Z = [0.10; 0.20; 0.30];

theta0 = [0.20; 0.20; 0.20];

rainfall = zeros(N,1);

irrigation = zeros(N,1);
irrigation(time >= 20 & time < 60) = 8;

ET_potential = 4 * ones(N,1);

ET_fraction = [0.50; 0.30; 0.20];

kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

Kinf = 0.020;

nLayers = 3;
nScenarios = 6;

fprintf('Reference V3 configuration\n');
fprintf('---------------------------------------------------------------\n');

fprintf('Simulation time       : %.2f days\n',T);
fprintf('Time step             : %.4f day\n',dt);
fprintf('Number of layers      : %d\n',nLayers);
fprintf('Root-zone depth       : %.2f m\n\n',sum(Z));

fprintf('theta_r               : %.6f\n',theta_r);
fprintf('theta_s               : %.6f\n',theta_s);
fprintf('theta_FC              : %.6f\n',theta_FC);
fprintf('theta_WP              : %.6f\n\n',theta_WP);

fprintf('kp12                  : %.6f\n',kp12);
fprintf('kp23                  : %.6f\n',kp23);
fprintf('kp3d                  : %.6f\n',kp3d);
fprintf('Kinf                  : %.6f m/day\n\n',Kinf);

%% ================================================================
% 3. SCENARIOS
% ================================================================

scenarioName = { ...
    'A - Nominal'
    'B - Dry'
    'C - Wet'
    'D - Low drainage'
    'E - High drainage'
    'F - Combined'};

scenarioFC = [ ...
    0.250
    0.225
    0.275
    0.250
    0.250
    0.225];

scenarioWP = [ ...
    0.120
    0.108
    0.132
    0.120
    0.120
    0.132];

scenarioKp3d = [ ...
    0.20
    0.20
    0.20
    0.16
    0.24
    0.24];

%% ================================================================
% 4. PREALLOCATE
% ================================================================

thetaAll = zeros(N,nLayers,nScenarios);
storageAll = zeros(N,nScenarios);

ETactualAll = zeros(N,nLayers,nScenarios);
ETcumulativeAll = zeros(N,nScenarios);

q12All = zeros(N,nScenarios);
q23All = zeros(N,nScenarios);
q3dAll = zeros(N,nScenarios);

infiltrationAll = zeros(N,nScenarios);
runoffAll = zeros(N,nScenarios);

stressAll = zeros(N,nLayers,nScenarios);

%% Metrics

finalStorage = zeros(nScenarios,1);
actualET = zeros(nScenarios,1);
deepDrainage = zeros(nScenarios,1);

totalIrrigation = zeros(nScenarios,1);
totalRainfall = zeros(nScenarios,1);
totalInfiltration = zeros(nScenarios,1);
totalRunoff = zeros(nScenarios,1);

meanTheta = zeros(nScenarios,1);
minTheta = zeros(nScenarios,1);
maxTheta = zeros(nScenarios,1);

meanStress = zeros(nScenarios,1);
maxStress = zeros(nScenarios,1);

waterBalanceError = zeros(nScenarios,1);
intervalBalanceError = zeros(nScenarios,1);

clippingCount = zeros(nScenarios,1);

%% ================================================================
% 5. RUN SIX SCENARIOS
% ================================================================

for sc = 1:nScenarios

    theta_FC_sc = scenarioFC(sc);
    theta_WP_sc = scenarioWP(sc);
    kp3d_sc = scenarioKp3d(sc);

    fprintf('---------------------------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n', ...
        sc,nScenarios,scenarioName{sc});
    fprintf('---------------------------------------------------------------\n');

    fprintf('theta_FC = %.6f\n',theta_FC_sc);
    fprintf('theta_WP = %.6f\n',theta_WP_sc);
    fprintf('kp3d     = %.6f\n\n',kp3d_sc);

    %% Run exact V3 solver

    out = runExactV3( ...
        dt,T,...
        theta_r,...
        theta_s,...
        theta_FC_sc,...
        theta_WP_sc,...
        Z,...
        theta0,...
        rainfall,...
        irrigation,...
        ET_potential,...
        ET_fraction,...
        kp12,...
        kp23,...
        kp3d_sc,...
        Kinf);

    %% Store results

    thetaAll(:,:,sc) = out.theta;

    storageAll(:,sc) = out.storage;

    ETactualAll(:,:,sc) = out.ET_actual;

    q12All(:,sc) = out.q12;
    q23All(:,sc) = out.q23;
    q3dAll(:,sc) = out.q3d;

    infiltrationAll(:,sc) = out.infiltration;
    runoffAll(:,sc) = out.runoff;

    stressAll(:,:,sc) = out.stress;

    clippingCount(sc) = out.clippingCount;

    %% Cumulative quantities

    ETcumulativeAll(:,sc) = ...
        cumsum(sum(out.ET_actual,2)) * dt * 1000;

    %% Metrics

    finalStorage(sc) = ...
        out.storage(end) * 1000;

    actualET(sc) = ...
        ETcumulativeAll(end,sc);

    deepDrainage(sc) = ...
        sum(out.q3d) * dt * 1000;

    totalIrrigation(sc) = ...
        sum(irrigation) * dt;

    totalRainfall(sc) = ...
        sum(rainfall) * dt;

    totalInfiltration(sc) = ...
        sum(out.infiltration) * dt * 1000;

    totalRunoff(sc) = ...
        sum(out.runoff) * dt * 1000;

    meanTheta(sc) = mean(out.theta(:));

    minTheta(sc) = min(out.theta(:));

    maxTheta(sc) = max(out.theta(:));

    meanStress(sc) = mean(out.stress(:));

    maxStress(sc) = max(out.stress(:));

    %% ============================================================
    % INDEPENDENT TOTAL WATER BALANCE
    % ============================================================

    initialStorage_mm = ...
        out.storage(1) * 1000;

    finalStorage_mm = ...
        out.storage(end) * 1000;

    totalInput_mm = ...
        totalIrrigation(sc) + ...
        totalRainfall(sc);

    independentFinalStorage_mm = ...
        initialStorage_mm + ...
        totalInput_mm - ...
        actualET(sc) - ...
        deepDrainage(sc) - ...
        totalRunoff(sc);

    waterBalanceError(sc) = ...
        finalStorage_mm - ...
        independentFinalStorage_mm;

    %% ============================================================
    % INTERVAL WATER BALANCE
    % ============================================================

    tempError = zeros(N-1,1);

    for k = 1:N-1

        deltaStorage_mm = ...
            (out.storage(k+1)-out.storage(k))*1000;

        input_mm = ...
            (irrigation(k)+rainfall(k))*dt;

        ET_mm = ...
            sum(out.ET_actual(k,:))*dt*1000;

        drainage_mm = ...
            out.q3d(k)*dt*1000;

        runoff_mm = ...
            out.runoff(k)*dt*1000;

        tempError(k) = ...
            deltaStorage_mm - ...
            (input_mm - ET_mm - drainage_mm - runoff_mm);

    end

    intervalBalanceError(sc) = ...
        max(abs(tempError));

    %% Print

    fprintf('Final storage       : %.6f mm\n',finalStorage(sc));
    fprintf('Actual ET           : %.6f mm\n',actualET(sc));
    fprintf('Deep drainage       : %.6f mm\n',deepDrainage(sc));

    fprintf('Irrigation          : %.6f mm\n',totalIrrigation(sc));
    fprintf('Rainfall            : %.6f mm\n',totalRainfall(sc));
    fprintf('Infiltration        : %.6f mm\n',totalInfiltration(sc));
    fprintf('Runoff              : %.6f mm\n',totalRunoff(sc));

    fprintf('Mean theta          : %.6f\n',meanTheta(sc));
    fprintf('Min theta           : %.6f\n',minTheta(sc));
    fprintf('Max theta           : %.6f\n',maxTheta(sc));

    fprintf('Mean stress         : %.6f\n',meanStress(sc));
    fprintf('Max stress          : %.6f\n',maxStress(sc));

    fprintf('Independent WB error: %.12e mm\n', ...
        waterBalanceError(sc));

    fprintf('Max interval error  : %.12e mm\n', ...
        intervalBalanceError(sc));

    fprintf('Clipping count      : %d\n\n', ...
        clippingCount(sc));

end

%% ================================================================
% 6. BASELINE REPRODUCTION
% ================================================================

fprintf('===============================================================\n');
fprintf(' BASELINE REPRODUCTION TEST\n');
fprintf('===============================================================\n\n');

if ~isfield(base,'theta') || ...
   ~isfield(base,'S') || ...
   ~isfield(base,'ET_actual') || ...
   ~isfield(base,'q3d')

    error('Reference results do not contain expected V3 fields.');
end

referenceTheta = base.theta;

referenceStorage = sum(base.S,2);

referenceET = base.ET_actual;

referenceDrainage = base.q3d;

thetaDifference = ...
    max(abs(thetaAll(:,:,1)-referenceTheta),[],'all');

storageDifference = ...
    max(abs(storageAll(:,1)-referenceStorage),[],'all');

ETDifference = ...
    max(abs(ETactualAll(:,:,1)-referenceET),[],'all');

drainageDifference = ...
    max(abs(q3dAll(:,1)-referenceDrainage),[],'all');

fprintf('Maximum theta difference    : %.12e\n', ...
    thetaDifference);

fprintf('Maximum storage difference  : %.12e m\n', ...
    storageDifference);

fprintf('Maximum ET difference       : %.12e m/day\n', ...
    ETDifference);

fprintf('Maximum drainage difference : %.12e m/day\n\n', ...
    drainageDifference);

baselineReproduction = ...
    thetaDifference < 1e-12 && ...
    storageDifference < 1e-12 && ...
    ETDifference < 1e-12 && ...
    drainageDifference < 1e-12;

if baselineReproduction

    fprintf('PASS: theta reproduction\n');
    fprintf('PASS: storage reproduction\n');
    fprintf('PASS: ET reproduction\n');
    fprintf('PASS: drainage reproduction\n\n');

    fprintf('===============================================================\n');
    fprintf(' BASELINE REPRODUCTION: PASS\n');
    fprintf('===============================================================\n\n');

else

    fprintf('FAIL: baseline reproduction\n\n');

end

%% ================================================================
% 7. PHYSICAL VALIDATION
% ================================================================

fprintf('===============================================================\n');
fprintf(' PHYSICAL VALIDATION\n');
fprintf('===============================================================\n\n');

thetaPass = false(nScenarios,1);
storagePass = false(nScenarios,1);
waterBalancePass = false(nScenarios,1);
nonnegativeFluxPass = false(nScenarios,1);
noClippingPass = false(nScenarios,1);

tol = 1e-10;

for sc = 1:nScenarios

    %% Theta bounds

    thetaPass(sc) = ...
        minTheta(sc) >= theta_r - 1e-12 && ...
        maxTheta(sc) <= theta_s + 1e-12;

    %% Storage bounds

    Smin = theta_r .* Z;
    Smax = theta_s .* Z;

    Sphysical = ...
        thetaAll(:,:,sc) .* Z';

    lowerViolation = ...
        min(Sphysical-Smin',[],'all');

    upperViolation = ...
        max(Sphysical-Smax',[],'all');

    storagePass(sc) = ...
        lowerViolation >= -1e-12 && ...
        upperViolation <= 1e-12;

    %% Water balance

    waterBalancePass(sc) = ...
        abs(waterBalanceError(sc)) < tol && ...
        intervalBalanceError(sc) < tol;

    %% Nonnegative fluxes

    nonnegativeFluxPass(sc) = ...
        min(infiltrationAll(:,sc)) >= -1e-12 && ...
        min(runoffAll(:,sc)) >= -1e-12 && ...
        min(q12All(:,sc)) >= -1e-12 && ...
        min(q23All(:,sc)) >= -1e-12 && ...
        min(q3dAll(:,sc)) >= -1e-12 && ...
        min(ETactualAll(:,:,sc),[],'all') >= -1e-12;

    %% Clipping

    noClippingPass(sc) = ...
        clippingCount(sc) == 0;

    %% Print

    fprintf('%s : %s - theta bounds\n', ...
        scenarioName{sc},passFail(thetaPass(sc)));

    fprintf('%s : %s - storage bounds\n', ...
        scenarioName{sc},passFail(storagePass(sc)));

    fprintf('%s : %s - water balance\n', ...
        scenarioName{sc},passFail(waterBalancePass(sc)));

    fprintf('%s : %s - nonnegative fluxes\n', ...
        scenarioName{sc},passFail(nonnegativeFluxPass(sc)));

    fprintf('%s : %s - no clipping\n\n', ...
        scenarioName{sc},passFail(noClippingPass(sc)));

end

%% ================================================================
% 8. ROBUSTNESS SUMMARY
% ================================================================

fprintf('===============================================================\n');
fprintf(' ROBUSTNESS SUMMARY\n');
fprintf('===============================================================\n\n');

storageRange = ...
    max(finalStorage)-min(finalStorage);

ETRange = ...
    max(actualET)-min(actualET);

drainageRange = ...
    max(deepDrainage)-min(deepDrainage);

thetaRange = ...
    max(meanTheta)-min(meanTheta);

stressRange = ...
    max(meanStress)-min(meanStress);

[~,i1] = min(finalStorage);
[~,i2] = max(meanStress);
[~,i3] = min(actualET);
[~,i4] = max(deepDrainage);

fprintf('Final storage range : %.6f mm\n',storageRange);
fprintf('Actual ET range     : %.6f mm\n',ETRange);
fprintf('Drainage range      : %.6f mm\n',drainageRange);
fprintf('Mean theta range    : %.6f\n',thetaRange);
fprintf('Mean stress range   : %.6f\n\n',stressRange);

fprintf('Lowest final storage : %s\n',scenarioName{i1});
fprintf('Highest mean stress  : %s\n',scenarioName{i2});
fprintf('Lowest actual ET     : %s\n',scenarioName{i3});
fprintf('Highest drainage     : %s\n\n',scenarioName{i4});

%% ================================================================
% 9. SUMMARY TABLE
% ================================================================

Summary = table( ...
    scenarioName,...
    scenarioFC,...
    scenarioWP,...
    scenarioKp3d,...
    finalStorage,...
    actualET,...
    deepDrainage,...
    meanTheta,...
    minTheta,...
    maxTheta,...
    meanStress,...
    waterBalanceError,...
    clippingCount,...
    'VariableNames',{...
    'Scenario',...
    'theta_FC',...
    'theta_WP',...
    'kp3d',...
    'FinalStorage_mm',...
    'ActualET_mm',...
    'DeepDrainage_mm',...
    'MeanTheta',...
    'MinTheta',...
    'MaxTheta',...
    'MeanStress',...
    'WaterBalanceError_mm',...
    'ClippingCount'});

disp(Summary);

%% ================================================================
% 10. FINAL VALIDATION
% ================================================================

allPhysicalPass = ...
    all(thetaPass) && ...
    all(storagePass) && ...
    all(waterBalancePass) && ...
    all(nonnegativeFluxPass) && ...
    all(noClippingPass);

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' FINAL VALIDATION STATUS\n');
fprintf('===============================================================\n\n');

fprintf('Baseline reproduction : %s\n', ...
    passFail(baselineReproduction));

fprintf('Physical bounds       : %s\n', ...
    passFail(all(thetaPass) && all(storagePass)));

fprintf('Water balance         : %s\n', ...
    passFail(all(waterBalancePass)));

fprintf('Nonnegative fluxes    : %s\n', ...
    passFail(all(nonnegativeFluxPass)));

fprintf('No clipping           : %s\n\n', ...
    passFail(all(noClippingPass)));

%% ================================================================
% 11. FIGURES
% ================================================================

%% Figure 30 - Mean theta

f1 = figure('Color','w');
hold on;

for sc = 1:nScenarios
    plot(time,mean(thetaAll(:,:,sc),2),'LineWidth',1.4);
end

yline(theta_FC,'--','Field Capacity');
yline(theta_WP,'--','Wilting Point');

xlabel('Time (days)');
ylabel('Mean volumetric water content');

title('V3 Uncertainty - Mean Soil Moisture');

legend(scenarioName,'Location','best');

grid on;
box on;

saveas(f1,'30_V3_Uncertainty_Theta_Final.png');

%% Figure 31 - Storage

f2 = figure('Color','w');
hold on;

for sc = 1:nScenarios
    plot(time,storageAll(:,sc)*1000,'LineWidth',1.4);
end

xlabel('Time (days)');
ylabel('Root-zone storage (mm)');

title('V3 Uncertainty - Root-Zone Storage');

legend(scenarioName,'Location','best');

grid on;
box on;

saveas(f2,'31_V3_Uncertainty_Storage_Final.png');

%% Figure 32 - ET

f3 = figure('Color','w');
hold on;

for sc = 1:nScenarios
    plot(time,ETcumulativeAll(:,sc),'LineWidth',1.4);
end

xlabel('Time (days)');
ylabel('Cumulative actual ET (mm)');

title('V3 Uncertainty - Cumulative Actual ET');

legend(scenarioName,'Location','best');

grid on;
box on;

saveas(f3,'32_V3_Uncertainty_ET_Final.png');

%% Figure 33 - Drainage

f4 = figure('Color','w');
hold on;

for sc = 1:nScenarios
    plot(time,...
        cumsum(q3dAll(:,sc))*dt*1000,...
        'LineWidth',1.4);
end

xlabel('Time (days)');
ylabel('Cumulative deep drainage (mm)');

title('V3 Uncertainty - Cumulative Deep Drainage');

legend(scenarioName,'Location','best');

grid on;
box on;

saveas(f4,'33_V3_Uncertainty_Drainage_Final.png');

%% Figure 34 - Stress

f5 = figure('Color','w');
hold on;

for sc = 1:nScenarios
    plot(time,mean(stressAll(:,:,sc),2),'LineWidth',1.4);
end

xlabel('Time (days)');
ylabel('Mean soil-water stress');

title('V3 Uncertainty - Mean Soil-Water Stress');

legend(scenarioName,'Location','best');

grid on;
box on;

saveas(f5,'34_V3_Uncertainty_Stress_Final.png');

%% Figure 35 - Summary

f6 = figure('Color','w');

subplot(2,2,1);

bar(finalStorage);

set(gca,...
    'XTick',1:nScenarios,...
    'XTickLabel',{'A','B','C','D','E','F'});

ylabel('Final storage (mm)');
title('Final Storage');

grid on;

subplot(2,2,2);

bar(actualET);

set(gca,...
    'XTick',1:nScenarios,...
    'XTickLabel',{'A','B','C','D','E','F'});

ylabel('Actual ET (mm)');
title('Actual ET');

grid on;

subplot(2,2,3);

bar(deepDrainage);

set(gca,...
    'XTick',1:nScenarios,...
    'XTickLabel',{'A','B','C','D','E','F'});

ylabel('Deep drainage (mm)');
title('Deep Drainage');

grid on;

subplot(2,2,4);

bar(meanStress);

set(gca,...
    'XTick',1:nScenarios,...
    'XTickLabel',{'A','B','C','D','E','F'});

ylabel('Mean stress');
title('Mean Stress');

grid on;

saveas(f6,'35_V3_Uncertainty_Summary_Final.png');

%% ================================================================
% 12. SAVE RESULTS
% ================================================================

results = struct();

results.time = time;
results.dt = dt;
results.T = T;

results.theta_r = theta_r;
results.theta_s = theta_s;

results.Z = Z;
results.root_depth = sum(Z);

results.scenarioName = scenarioName;
results.scenarioFC = scenarioFC;
results.scenarioWP = scenarioWP;
results.scenarioKp3d = scenarioKp3d;

results.theta = thetaAll;
results.storage = storageAll;

results.ET_actual = ETactualAll;
results.ET_cumulative = ETcumulativeAll;

results.q12 = q12All;
results.q23 = q23All;
results.q3d = q3dAll;

results.infiltration = infiltrationAll;
results.runoff = runoffAll;

results.stress = stressAll;

results.finalStorage = finalStorage;
results.actualET = actualET;
results.deepDrainage = deepDrainage;

results.totalIrrigation = totalIrrigation;
results.totalRainfall = totalRainfall;
results.totalInfiltration = totalInfiltration;
results.totalRunoff = totalRunoff;

results.meanTheta = meanTheta;
results.minTheta = minTheta;
results.maxTheta = maxTheta;

results.meanStress = meanStress;
results.maxStress = maxStress;

results.waterBalanceError = waterBalanceError;
results.intervalBalanceError = intervalBalanceError;

results.clippingCount = clippingCount;

results.thetaPass = thetaPass;
results.storagePass = storagePass;
results.waterBalancePass = waterBalancePass;
results.nonnegativeFluxPass = nonnegativeFluxPass;
results.noClippingPass = noClippingPass;

results.baselineReproduction = baselineReproduction;
results.allPhysicalPass = allPhysicalPass;

results.summaryTable = Summary;

save( ...
    'V3_UncertaintyAnalysis_Final_Results.mat',...
    'results');

%% ================================================================
% 13. FINAL MESSAGE
% ================================================================

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' ANALYSIS COMPLETE\n');
fprintf('===============================================================\n\n');

fprintf('Baseline reproduction : %s\n', ...
    passFail(baselineReproduction));

fprintf('Physical bounds       : %s\n', ...
    passFail(all(thetaPass) && all(storagePass)));

fprintf('Water balance         : %s\n', ...
    passFail(all(waterBalancePass)));

fprintf('Nonnegative fluxes    : %s\n', ...
    passFail(all(nonnegativeFluxPass)));

fprintf('No clipping           : %s\n\n', ...
    passFail(all(noClippingPass)));

fprintf('Results saved to:\n');
fprintf('V3_UncertaintyAnalysis_Final_Results.mat\n\n');

fprintf('Figures saved:\n');
fprintf('30_V3_Uncertainty_Theta_Final.png\n');
fprintf('31_V3_Uncertainty_Storage_Final.png\n');
fprintf('32_V3_Uncertainty_ET_Final.png\n');
fprintf('33_V3_Uncertainty_Drainage_Final.png\n');
fprintf('34_V3_Uncertainty_Stress_Final.png');
fprintf('\n35_V3_Uncertainty_Summary_Final.png\n');

fprintf('\n===============================================================\n');
fprintf(' END\n');
fprintf('===============================================================\n');


%% ================================================================
% LOCAL FUNCTION
% EXACT V3 SOLVER
% ================================================================

function out = runExactV3( ...
    dt,T,...
    theta_r,...
    theta_s,...
    theta_FC,...
    theta_WP,...
    Z,...
    theta0,...
    rainfall,...
    irrigation,...
    ET_potential,...
    ET_fraction,...
    kp12,...
    kp23,...
    kp3d,...
    Kinf)

N = round(T/dt) + 1;
nLayers = numel(Z);

%% Storage

S = zeros(N,nLayers);

theta = zeros(N,nLayers);

%% Fluxes

infiltration = zeros(N,1);

runoff = zeros(N,1);

q12 = zeros(N,1);

q23 = zeros(N,1);

q3d = zeros(N,1);

ET_actual = zeros(N,nLayers);

stress = zeros(N,nLayers);

%% Storage limits

S_min = theta_r .* Z;

S_max = theta_s .* Z;

S_FC = theta_FC .* Z;

S_WP = theta_WP .* Z;

%% Initial condition

S_current = theta0 .* Z;

S(1,:) = S_current';

theta(1,:) = S_current' ./ Z';

clippingCount = 0;

%% ================================================================
% MAIN V3 LOOP
% ================================================================

for k = 1:N-1

    %% ------------------------------------------------------------
    % External water input
    % ------------------------------------------------------------

    I = irrigation(k)/1000;

    P = rainfall(k)/1000;

    water_input = I + P;

    %% ------------------------------------------------------------
    % Infiltration
    % ------------------------------------------------------------

    current_theta1 = ...
        S_current(1)/Z(1);

    remaining_capacity = ...
        S_max(1)-S_current(1);

    saturation_factor = ...
        (theta_s-current_theta1)/...
        (theta_s-theta_FC);

    saturation_factor = ...
        max(0,min(1,saturation_factor));

    infiltration_capacity = ...
        Kinf*saturation_factor;

    potential_infiltration = ...
        min(water_input,...
            infiltration_capacity);

    actual_infiltration = ...
        min(potential_infiltration,...
            remaining_capacity/dt);

    actual_infiltration = ...
        max(0,actual_infiltration);

    runoff(k) = ...
        max(0,...
        water_input-actual_infiltration);

    S_current(1) = ...
        S_current(1)+...
        actual_infiltration*dt;

    infiltration(k) = ...
        actual_infiltration;

    %% ------------------------------------------------------------
    % Soil-water stress
    % ------------------------------------------------------------

    theta_current = ...
        S_current./Z;

    current_stress = ...
        (theta_current-theta_WP)/...
        (theta_FC-theta_WP);

    current_stress = ...
        max(0,min(1,current_stress));

    stress(k,:) = ...
        current_stress';

    %% ------------------------------------------------------------
    % Actual ET
    % ------------------------------------------------------------

    ET_demand = ...
        (ET_potential(k)/1000).*...
        ET_fraction.*...
        current_stress;

    for i = 1:nLayers

        available_water = ...
            max(0,...
            S_current(i)-S_min(i));

        ET_remove = ...
            min(...
            ET_demand(i)*dt,...
            available_water);

        S_current(i) = ...
            S_current(i)-ET_remove;

        ET_actual(k,i) = ...
            ET_remove/dt;

    end

    %% ------------------------------------------------------------
    % Layer 1 -> Layer 2
    % ------------------------------------------------------------

    excess1 = ...
        max(0,...
        S_current(1)-S_FC(1));

    potential_q12 = ...
        kp12*excess1;

    max_transfer12 = ...
        S_current(1)-S_min(1);

    max_receive12 = ...
        S_max(2)-S_current(2);

    transfer12 = ...
        min(...
        potential_q12*dt,...
        max_transfer12);

    transfer12 = ...
        min(...
        transfer12,...
        max_receive12);

    transfer12 = ...
        max(0,transfer12);

    S_current(1) = ...
        S_current(1)-transfer12;

    S_current(2) = ...
        S_current(2)+transfer12;

    q12(k) = ...
        transfer12/dt;

    %% ------------------------------------------------------------
    % Layer 2 -> Layer 3
    % ------------------------------------------------------------

    excess2 = ...
        max(0,...
        S_current(2)-S_FC(2));

    potential_q23 = ...
        kp23*excess2;

    max_transfer23 = ...
        S_current(2)-S_min(2);

    max_receive23 = ...
        S_max(3)-S_current(3);

    transfer23 = ...
        min(...
        potential_q23*dt,...
        max_transfer23);

    transfer23 = ...
        min(...
        transfer23,...
        max_receive23);

    transfer23 = ...
        max(0,transfer23);

    S_current(2) = ...
        S_current(2)-transfer23;

    S_current(3) = ...
        S_current(3)+transfer23;

    q23(k) = ...
        transfer23/dt;

    %% ------------------------------------------------------------
    % Deep drainage
    % ------------------------------------------------------------

    excess3 = ...
        max(0,...
        S_current(3)-S_FC(3));

    potential_q3d = ...
        kp3d*excess3;

    max_drainage = ...
        S_current(3)-S_min(3);

    drainage = ...
        min(...
        potential_q3d*dt,...
        max_drainage);

    drainage = ...
        max(0,drainage);

    S_current(3) = ...
        S_current(3)-drainage;

    q3d(k) = ...
        drainage/dt;

    %% ------------------------------------------------------------
    % Physical bounds
    % ------------------------------------------------------------

    S_beforeBound = S_current;

    S_current = ...
        min(...
        max(S_current,S_min),...
        S_max);

    if any(abs(S_current-S_beforeBound)>1e-12)

        clippingCount = ...
            clippingCount+1;

    end

    %% ------------------------------------------------------------
    % Store
    % ------------------------------------------------------------

    S(k+1,:) = ...
        S_current';

    theta(k+1,:) = ...
        S_current'./Z';

end

%% ================================================================
% FINAL STRESS
% ================================================================

stress_final = ...
    (theta(end,:)-theta_WP)/...
    (theta_FC-theta_WP);

stress_final = ...
    max(0,min(1,stress_final));

stress(end,:) = ...
    stress_final;

%% ================================================================
% OUTPUT
% ================================================================

out.S = S;

out.theta = theta;

out.storage = sum(S,2);

out.infiltration = infiltration;

out.runoff = runoff;

out.q12 = q12;

out.q23 = q23;

out.q3d = q3d;

out.ET_actual = ET_actual;

out.stress = stress;

out.clippingCount = clippingCount;

end


%% ================================================================
% LOCAL FUNCTION
% PASS / FAIL
% ================================================================

function txt = passFail(value)

if value
    txt = 'PASS';
else
    txt = 'FAIL';
end

end