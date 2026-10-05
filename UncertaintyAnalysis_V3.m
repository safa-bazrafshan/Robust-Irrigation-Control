%% ================================================================
%  V3 UNCERTAINTY & ROBUSTNESS ANALYSIS - FINAL
%  AI-Driven Smart Irrigation Control
%
%  Purpose:
%  Evaluate the validated V3 soil-water model under
%  physically meaningful parameter uncertainty.
%
%  IMPORTANT:
%  This script reproduces the validated V3 numerical formulation.
%  Scenario A MUST reproduce the original V3 baseline before
%  uncertainty results are accepted.
%
%  Parameters under uncertainty:
%       theta_FC
%       theta_WP
%       kp3d
%
%  Scenarios:
%       A - Nominal
%       B - Dry soil
%       C - Wet soil
%       D - Low drainage
%       E - High drainage
%       F - Combined uncertainty
%
%  Output:
%       V3_UncertaintyAnalysis_Final_Results.mat
%
%  Figures:
%       18_V3_Uncertainty_Scenarios_Final.png
%       19_V3_Uncertainty_Theta_Final.png
%       20_V3_Uncertainty_Storage_Final.png
%       21_V3_Uncertainty_ET_Final.png
%       22_V3_Uncertainty_Drainage_Final.png
%       23_V3_Uncertainty_Summary_Final.png
% ================================================================

clear;
clc;
close all;

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 UNCERTAINTY & ROBUSTNESS ANALYSIS - FINAL\n');
fprintf('====================================================\n\n');


%% ================================================================
% 1. LOAD VALIDATED V3 BASELINE
% ================================================================

baselineFile = '01_ReducedSoilWaterModel_V3_Results.mat';

fprintf('Loading validated V3 baseline...\n');

if ~isfile(baselineFile)
    error(['Baseline file not found: ', baselineFile]);
end

data = load(baselineFile);

if ~isfield(data,'results')
    error('Baseline file does not contain variable "results".');
end

base = data.results;

fprintf('Baseline loaded successfully.\n\n');


%% ================================================================
% 2. EXTRACT BASELINE CONFIGURATION
% ================================================================

t  = base.time(:);
dt = base.dt;
T  = base.T;

theta0 = base.theta(1,:);

theta_r  = base.theta_r;
theta_s  = base.theta_s;
theta_FC = base.theta_FC;
theta_WP = base.theta_WP;

Z = base.Z(:);

nTime   = length(t);
nLayers = length(Z);

kp12 = 0.8;
kp23 = 0.5;
kp3d = 0.2;

Kinf = 0.02;

ETfractions = [0.5 0.3 0.2];


%% ================================================================
% 3. EXTRACT INPUTS
% ================================================================

irrigation = base.irrigation(:);
rainfall   = base.rainfall(:);

ETpotential_raw = base.ET_potential;

if size(ETpotential_raw,2) > 1

    % The validated V3 ET potential is a scalar time series.
    % If the stored variable is replicated across layers,
    % use the first column only.

    ETpotential = ETpotential_raw(:,1);

else

    ETpotential = ETpotential_raw(:);

end

if length(irrigation) ~= nTime
    error('Irrigation vector length does not match simulation time.');
end

if length(rainfall) ~= nTime
    error('Rainfall vector length does not match simulation time.');
end

if length(ETpotential) ~= nTime
    error('ET potential vector length does not match simulation time.');
end


%% ================================================================
% 4. BASELINE REFERENCE VALUES
% ================================================================

baselineFinalStorage = base.storage(end) * 1000;

baselineActualET = ...
    base.cumulative_ET(end) * 1000;

baselineDrainage = ...
    base.cumulative_drainage(end) * 1000;

baselineIrrigation = ...
    base.cumulative_irrigation(end) * 1000;

baselineRainfall = ...
    base.cumulative_rainfall(end) * 1000;


fprintf('====================================================\n');
fprintf(' BASELINE CONFIGURATION\n');
fprintf('====================================================\n\n');

fprintf('Simulation time       = %.2f days\n',T);
fprintf('Time step             = %.4f day\n',dt);
fprintf('Number of layers      = %d\n',nLayers);
fprintf('Root-zone depth       = %.2f m\n\n',sum(Z));

fprintf('theta_r               = %.6f\n',theta_r);
fprintf('theta_s               = %.6f\n',theta_s);
fprintf('theta_FC              = %.6f\n',theta_FC);
fprintf('theta_WP              = %.6f\n\n',theta_WP);

fprintf('kp12                  = %.6f\n',kp12);
fprintf('kp23                  = %.6f\n',kp23);
fprintf('kp3d                  = %.6f\n',kp3d);
fprintf('Kinf                  = %.6f m/day\n\n',Kinf);

fprintf('Baseline final storage = %.6f mm\n', ...
    baselineFinalStorage);

fprintf('Baseline actual ET     = %.6f mm\n', ...
    baselineActualET);

fprintf('Baseline drainage      = %.6f mm\n', ...
    baselineDrainage);

fprintf('Baseline irrigation    = %.6f mm\n', ...
    baselineIrrigation);

fprintf('Baseline rainfall      = %.6f mm\n\n', ...
    baselineRainfall);


%% ================================================================
% 5. DEFINE UNCERTAINTY SCENARIOS
% ================================================================

fprintf('====================================================\n');
fprintf(' UNCERTAINTY SCENARIO DESIGN\n');
fprintf('====================================================\n\n');

scenarioNames = { ...
    'A - Nominal', ...
    'B - Dry soil', ...
    'C - Wet soil', ...
    'D - Low drainage', ...
    'E - High drainage', ...
    'F - Combined uncertainty'};

nScenarios = length(scenarioNames);

scenario.theta_FC = zeros(nScenarios,1);
scenario.theta_WP = zeros(nScenarios,1);
scenario.kp3d     = zeros(nScenarios,1);


% Scenario A
scenario.theta_FC(1) = theta_FC;
scenario.theta_WP(1) = theta_WP;
scenario.kp3d(1)     = kp3d;


% Scenario B
scenario.theta_FC(2) = 0.90 * theta_FC;
scenario.theta_WP(2) = 0.90 * theta_WP;
scenario.kp3d(2)     = kp3d;


% Scenario C
scenario.theta_FC(3) = 1.10 * theta_FC;
scenario.theta_WP(3) = 1.10 * theta_WP;
scenario.kp3d(3)     = kp3d;


% Scenario D
scenario.theta_FC(4) = theta_FC;
scenario.theta_WP(4) = theta_WP;
scenario.kp3d(4)     = 0.80 * kp3d;


% Scenario E
scenario.theta_FC(5) = theta_FC;
scenario.theta_WP(5) = theta_WP;
scenario.kp3d(5)     = 1.20 * kp3d;


% Scenario F
scenario.theta_FC(6) = 0.90 * theta_FC;
scenario.theta_WP(6) = 1.10 * theta_WP;
scenario.kp3d(6)     = 1.20 * kp3d;


for sc = 1:nScenarios

    fprintf('%s\n',scenarioNames{sc});
    fprintf('   theta_FC = %.6f\n', ...
        scenario.theta_FC(sc));

    fprintf('   theta_WP = %.6f\n', ...
        scenario.theta_WP(sc));

    fprintf('   kp3d     = %.6f\n\n', ...
        scenario.kp3d(sc));

end


%% ================================================================
% 6. PREALLOCATE RESULTS
% ================================================================

thetaAll = zeros(nTime,nLayers,nScenarios);

storageAll = zeros(nTime,nScenarios);

ETtotalAll = zeros(nTime,nScenarios);

drainageAll = zeros(nTime,nScenarios);

irrigationAll = zeros(nTime,nScenarios);

rainfallAll = zeros(nTime,nScenarios);

waterStressAll = zeros(nTime,nScenarios);

balanceErrorAll = zeros(nTime,nScenarios);

intervalBalanceErrorAll = zeros(nTime,nScenarios);

clippingCount = zeros(nScenarios,1);

meanTheta = zeros(nScenarios,1);
minTheta = zeros(nScenarios,1);
maxTheta = zeros(nScenarios,1);

finalStorage = zeros(nScenarios,1);

actualET = zeros(nScenarios,1);

deepDrainage = zeros(nScenarios,1);

totalIrrigation = zeros(nScenarios,1);

totalRainfall = zeros(nScenarios,1);

waterStress = zeros(nScenarios,1);

waterBalanceError = zeros(nScenarios,1);

maxIntervalBalanceError = zeros(nScenarios,1);


%% ================================================================
% 7. RUN UNCERTAINTY SCENARIOS
% ================================================================

fprintf('====================================================\n');
fprintf(' RUNNING UNCERTAINTY SCENARIOS\n');
fprintf('====================================================\n\n');


for sc = 1:nScenarios

    fprintf('----------------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n', ...
        sc,nScenarios,scenarioNames{sc});
    fprintf('----------------------------------------------------\n');

    p.theta_r  = theta_r;
    p.theta_s  = theta_s;
    p.theta_FC = scenario.theta_FC(sc);
    p.theta_WP = scenario.theta_WP(sc);

    p.kp12 = kp12;
    p.kp23 = kp23;
    p.kp3d = scenario.kp3d(sc);

    p.Kinf = Kinf;

    fprintf('theta_FC = %.6f\n',p.theta_FC);
    fprintf('theta_WP = %.6f\n',p.theta_WP);
    fprintf('kp3d     = %.6f\n\n',p.kp3d);


    %% ------------------------------------------------------------
    % 7.1 INITIAL CONDITIONS
    % ------------------------------------------------------------

    theta = zeros(nTime,nLayers);

    storage = zeros(nTime,1);

    ETactual = zeros(nTime,nLayers);

    stressHistory = zeros(nTime,nLayers);

    infiltration = zeros(nTime-1,1);

    runoff = zeros(nTime-1,1);

    q12 = zeros(nTime-1,1);

    q23 = zeros(nTime-1,1);

    q3d = zeros(nTime-1,1);


    theta(1,:) = theta0;

    storage(1) = ...
        sum(theta(1,:) .* Z');


    %% ------------------------------------------------------------
    % 7.2 TIME INTEGRATION
    % ------------------------------------------------------------

    for k = 1:nTime-1

        th = theta(k,:);

        S = th .* Z';


        % --------------------------------------------------------
        % Soil-water stress
        % --------------------------------------------------------

        denominator = ...
            p.theta_FC - p.theta_WP;

        if denominator <= 0
            error('theta_FC must be greater than theta_WP.');
        end

        stress = max( ...
            0, ...
            min(1, ...
            (th-p.theta_WP) ./ denominator));


        stressHistory(k,:) = stress;


        % --------------------------------------------------------
        % Actual evapotranspiration
        %
        % ETpotential is mm/day.
        % Convert to m/day.
        % --------------------------------------------------------

        ETp_m = ETpotential(k) / 1000;

        ETdemand = ...
            ETp_m .* ETfractions .* stress;


        % Limit ET by water available above residual water content
        for j = 1:nLayers

            availableET = ...
                max(0, ...
                S(j) - p.theta_r*Z(j));

            maxETrate = ...
                availableET / dt;

            ETactual(k,j) = ...
                min(ETdemand(j),maxETrate);

        end


        % --------------------------------------------------------
        % External water input
        %
        % Irrigation and rainfall are mm/day.
        % Convert to m/day.
        % --------------------------------------------------------

        inputRate = ...
            (irrigation(k)+rainfall(k))/1000;


        % --------------------------------------------------------
        % Surface infiltration capacity
        % --------------------------------------------------------

        capacityDenominator = ...
            p.theta_s - p.theta_FC;

        if capacityDenominator <= 0
            error('theta_s must be greater than theta_FC.');
        end

        capacityFactor = ...
            (p.theta_s-th(1)) / ...
            capacityDenominator;

        capacityFactor = ...
            max(0,min(1,capacityFactor));


        infiltrationCapacity = ...
            p.Kinf * capacityFactor;


        actualInfiltration = ...
            min(inputRate,infiltrationCapacity);


        % Limit by available saturation capacity of layer 1
        availableSaturation1 = ...
            max(0, ...
            (p.theta_s-th(1))*Z(1));

        maxInfiltrationRate = ...
            availableSaturation1 / dt;


        actualInfiltration = ...
            min(actualInfiltration,maxInfiltrationRate);


        infiltration(k) = actualInfiltration;


        runoff(k) = ...
            max(0,inputRate-actualInfiltration);


        % --------------------------------------------------------
        % Layer 1 -> Layer 2
        % --------------------------------------------------------

        excess1 = ...
            max(0, ...
            S(1)-p.theta_FC*Z(1));

        q12Potential = ...
            p.kp12 * excess1;

        transfer12 = ...
            q12Potential * dt;

        available12 = ...
            max(0,S(1)-p.theta_r*Z(1));

        receivingCapacity2 = ...
            max(0,(p.theta_s-th(2))*Z(2));

        transfer12 = min( ...
            transfer12, ...
            available12);

        transfer12 = min( ...
            transfer12, ...
            receivingCapacity2);

        q12(k) = max(0,transfer12);


        % --------------------------------------------------------
        % Layer 2 -> Layer 3
        % --------------------------------------------------------

        excess2 = ...
            max(0, ...
            S(2)-p.theta_FC*Z(2));

        q23Potential = ...
            p.kp23 * excess2;

        transfer23 = ...
            q23Potential * dt;

        available23 = ...
            max(0,S(2)-p.theta_r*Z(2));

        receivingCapacity3 = ...
            max(0,(p.theta_s-th(3))*Z(3));

        transfer23 = min( ...
            transfer23, ...
            available23);

        transfer23 = min( ...
            transfer23, ...
            receivingCapacity3);

        q23(k) = max(0,transfer23);


        % --------------------------------------------------------
        % Layer 3 -> Deep drainage
        % --------------------------------------------------------

        excess3 = ...
            max(0, ...
            S(3)-p.theta_FC*Z(3));

        q3dPotential = ...
            p.kp3d * excess3;

        transfer3d = ...
            q3dPotential * dt;

        available3d = ...
            max(0,S(3)-p.theta_r*Z(3));

        transfer3d = ...
            min(transfer3d,available3d);

        q3d(k) = max(0,transfer3d);


        % --------------------------------------------------------
        % Layer water balance
        % --------------------------------------------------------

        dS1 = ...
            infiltration(k)*dt ...
            - ETactual(k,1)*dt ...
            - q12(k);

        dS2 = ...
            q12(k) ...
            - ETactual(k,2)*dt ...
            - q23(k);

        dS3 = ...
            q23(k) ...
            - ETactual(k,3)*dt ...
            - q3d(k);


        Snew = ...
            S + [dS1 dS2 dS3];


        % --------------------------------------------------------
        % Physical storage bounds
        % --------------------------------------------------------

        lowerStorage = ...
            p.theta_r .* Z';

        upperStorage = ...
            p.theta_s .* Z';


        Sbounded = ...
            max(Snew,lowerStorage);

        Sbounded = ...
            min(Sbounded,upperStorage);


        if any(abs(Sbounded-Snew) > 1e-12)

            clippingCount(sc) = ...
                clippingCount(sc) + 1;

        end


        % --------------------------------------------------------
        % Updated theta
        % --------------------------------------------------------

        theta(k+1,:) = ...
            Sbounded ./ Z';


        storage(k+1) = ...
            sum(Sbounded);


    end


    %% ------------------------------------------------------------
    % 7.3 FINAL STATE STRESS
    % ------------------------------------------------------------

    denominator = ...
        p.theta_FC-p.theta_WP;

    stressFinal = ...
        max(0,min(1, ...
        (theta(end,:)-p.theta_WP) ./ denominator));

    stressHistory(end,:) = stressFinal;


    % IMPORTANT:
    % There is no additional time interval after t(end).
    % Therefore ET at the final state is zero.

    ETactual(end,:) = 0;


    %% ------------------------------------------------------------
    % 7.4 STORE DYNAMIC RESULTS
    % ------------------------------------------------------------

    thetaAll(:,:,sc) = theta;

    storageAll(:,sc) = storage;


    % Cumulative ET [mm]
    ETtotalAll(:,sc) = ...
        cumsum(sum(ETactual,2) .* dt) * 1000;


    % Cumulative drainage [mm]
    drainageAll(:,sc) = ...
        [0; cumsum(q3d)] * 1000;


    % Cumulative irrigation [mm]
    cumulativeIrrigation = zeros(nTime,1);

    cumulativeIrrigation(2:end) = ...
        cumsum(irrigation(1:end-1) .* dt);

    irrigationAll(:,sc) = ...
        cumulativeIrrigation;


    % Cumulative rainfall [mm]
    cumulativeRainfall = zeros(nTime,1);

    cumulativeRainfall(2:end) = ...
        cumsum(rainfall(1:end-1) .* dt);

    rainfallAll(:,sc) = ...
        cumulativeRainfall;


    % Water stress
    waterStressAll(:,sc) = ...
        1 - mean(stressHistory,2);


    %% ------------------------------------------------------------
    % 7.5 PERFORMANCE METRICS
    % ------------------------------------------------------------

    meanTheta(sc) = ...
        mean(theta(:));

    minTheta(sc) = ...
        min(theta(:));

    maxTheta(sc) = ...
        max(theta(:));


    finalStorage(sc) = ...
        storage(end) * 1000;

    actualET(sc) = ...
        ETtotalAll(end,sc);

    deepDrainage(sc) = ...
        drainageAll(end,sc);


    totalIrrigation(sc) = ...
        cumulativeIrrigation(end);

    totalRainfall(sc) = ...
        cumulativeRainfall(end);


    waterStress(sc) = ...
        mean(waterStressAll(:,sc));


    %% ------------------------------------------------------------
    % 7.6 INDEPENDENT WATER BALANCE
    % ------------------------------------------------------------

    initialStorage = ...
        storage(1)*1000;

    finalStorageValue = ...
        storage(end)*1000;


    totalInput = ...
        totalIrrigation(sc) + ...
        totalRainfall(sc);


    totalRunoff = ...
        sum(runoff)*1000;


    totalLoss = ...
        actualET(sc) + ...
        deepDrainage(sc) + ...
        totalRunoff;


    independentFinalStorage = ...
        initialStorage + ...
        totalInput - ...
        totalLoss;


    waterBalanceError(sc) = ...
        finalStorageValue - ...
        independentFinalStorage;


    %% ------------------------------------------------------------
    % 7.7 INTERVAL WATER BALANCE
    % ------------------------------------------------------------

    intervalError = zeros(nTime,1);


    for k = 1:nTime-1

        deltaStorage = ...
            (storage(k+1)-storage(k))*1000;


        inputStep = ...
            (irrigation(k)+rainfall(k))*dt;


        ETstep = ...
            sum(ETactual(k,:))*dt*1000;


        drainageStep = ...
            q3d(k)*1000;


        runoffStep = ...
            runoff(k)*1000;


        intervalError(k+1) = ...
            deltaStorage - ...
            (inputStep ...
            - ETstep ...
            - drainageStep ...
            - runoffStep);

    end


    intervalBalanceErrorAll(:,sc) = ...
        intervalError;


    maxIntervalBalanceError(sc) = ...
        max(abs(intervalError));


    %% ------------------------------------------------------------
    % 7.8 REPORT SCENARIO
    % ------------------------------------------------------------

    fprintf('Final storage       = %.6f mm\n', ...
        finalStorage(sc));

    fprintf('Actual ET           = %.6f mm\n', ...
        actualET(sc));

    fprintf('Deep drainage       = %.6f mm\n', ...
        deepDrainage(sc));

    fprintf('Total irrigation    = %.6f mm\n', ...
        totalIrrigation(sc));

    fprintf('Total rainfall      = %.6f mm\n', ...
        totalRainfall(sc));

    fprintf('Water stress        = %.6f\n', ...
        waterStress(sc));

    fprintf('Balance error       = %.12f mm\n', ...
        waterBalanceError(sc));

    fprintf('Interval max error  = %.12f mm\n', ...
        maxIntervalBalanceError(sc));

    fprintf('Clipping events     = %d\n\n', ...
        clippingCount(sc));


end


%% ================================================================
% 8. BASELINE REPRODUCTION TEST
% ================================================================

fprintf('====================================================\n');
fprintf(' BASELINE REPRODUCTION TEST\n');
fprintf('====================================================\n\n');


nominalTheta = ...
    thetaAll(:,:,1);

nominalStorage = ...
    storageAll(:,1);

nominalET = ...
    ETtotalAll(:,1);

nominalDrainage = ...
    drainageAll(:,1);


thetaDifference = ...
    max(abs(nominalTheta(:)-base.theta(:)));

storageDifference = ...
    max(abs(nominalStorage(:)-base.storage(:)));


baselineET = ...
    base.cumulative_ET(:)*1000;

baselineDrainage = ...
    base.cumulative_drainage(:)*1000;


ETDifference = ...
    max(abs(nominalET-baselineET));


drainageDifference = ...
    max(abs(nominalDrainage-baselineDrainage));


fprintf('Maximum theta difference   = %.12e\n', ...
    thetaDifference);

fprintf('Maximum storage difference = %.12e m\n', ...
    storageDifference);

fprintf('Maximum ET difference      = %.12e mm\n', ...
    ETDifference);

fprintf('Maximum drainage difference = %.12e mm\n\n', ...
    drainageDifference);


thetaTolerance = 1e-12;
storageTolerance = 1e-12;
ETTolerance = 1e-9;
drainageTolerance = 1e-9;


baselineReproduction = ...
    thetaDifference <= thetaTolerance && ...
    storageDifference <= storageTolerance && ...
    ETDifference <= ETTolerance && ...
    drainageDifference <= drainageTolerance;


if baselineReproduction

    fprintf('BASELINE REPRODUCTION: PASS\n\n');

else

    fprintf('BASELINE REPRODUCTION: FAIL\n\n');

end


%% ================================================================
% 9. GLOBAL WATER-BALANCE VALIDATION
% ================================================================

maxBalanceError = ...
    max(abs(waterBalanceError));

globalMaxIntervalError = ...
    max(maxIntervalBalanceError);


fprintf('====================================================\n');
fprintf(' WATER BALANCE VALIDATION\n');
fprintf('====================================================\n\n');

fprintf('Maximum independent balance error:\n');
fprintf('%.12e mm\n\n',maxBalanceError);

fprintf('Maximum interval balance error:\n');
fprintf('%.12e mm\n\n',globalMaxIntervalError);


if maxBalanceError < 1e-8

    fprintf('INDEPENDENT WATER BALANCE: PASS\n\n');

else

    fprintf('INDEPENDENT WATER BALANCE: FAIL\n\n');

end


if globalMaxIntervalError < 1e-8

    fprintf('INTERVAL WATER BALANCE: PASS\n\n');

else

    fprintf('INTERVAL WATER BALANCE: FAIL\n\n');

end


%% ================================================================
% 10. PHYSICAL-BOUND VALIDATION
% ================================================================

globalMinTheta = min(thetaAll(:));
globalMaxTheta = max(thetaAll(:));

fprintf('====================================================\n');
fprintf(' PHYSICAL BOUND VALIDATION\n');
fprintf('====================================================\n\n');

fprintf('Global minimum theta = %.12f\n', ...
    globalMinTheta);

fprintf('Global maximum theta = %.12f\n\n', ...
    globalMaxTheta);


boundsPass = ...
    globalMinTheta >= theta_r - 1e-12 && ...
    globalMaxTheta <= theta_s + 1e-12;


if boundsPass

    fprintf('THETA BOUNDS: PASS\n\n');

else

    fprintf('THETA BOUNDS: FAIL\n\n');

end


%% ================================================================
% 11. ROBUSTNESS METRICS
% ================================================================

thetaRange = ...
    maxTheta-minTheta;

storageRange = ...
    max(finalStorage)-min(finalStorage);

ETRange = ...
    max(actualET)-min(actualET);

drainageRange = ...
    max(deepDrainage)-min(deepDrainage);

stressRange = ...
    max(waterStress)-min(waterStress);


fprintf('====================================================\n');
fprintf(' ROBUSTNESS SUMMARY\n');
fprintf('====================================================\n\n');

fprintf('Soil moisture range:\n');
fprintf('%.6f\n\n',thetaRange);

fprintf('Final storage range:\n');
fprintf('%.6f mm\n\n',storageRange);

fprintf('Actual ET range:\n');
fprintf('%.6f mm\n\n',ETRange);

fprintf('Drainage range:\n');
fprintf('%.6f mm\n\n',drainageRange);

fprintf('Water stress range:\n');
fprintf('%.6f\n\n',stressRange);


%% ================================================================
% 12. WORST-CASE IDENTIFICATION
% ================================================================

[~,idxMinStorage] = ...
    min(finalStorage);

[~,idxMaxStress] = ...
    max(waterStress);

[~,idxMinET] = ...
    min(actualET);

[~,idxMaxDrainage] = ...
    max(deepDrainage);


fprintf('====================================================\n');
fprintf(' WORST-CASE IDENTIFICATION\n');
fprintf('====================================================\n\n');

fprintf('Lowest final storage:\n');
fprintf('%s\n\n', ...
    scenarioNames{idxMinStorage});

fprintf('Highest water stress:\n');
fprintf('%s\n\n', ...
    scenarioNames{idxMaxStress});

fprintf('Lowest actual ET:\n');
fprintf('%s\n\n', ...
    scenarioNames{idxMinET});

fprintf('Highest deep drainage:\n');
fprintf('%s\n\n', ...
    scenarioNames{idxMaxDrainage});


%% ================================================================
% 13. FIGURE 18 - UNCERTAINTY SCENARIOS
% ================================================================

figure( ...
    'Name','V3 Uncertainty Scenarios Final', ...
    'Color','w');

plot( ...
    1:nScenarios, ...
    scenario.theta_FC, ...
    '-o', ...
    'LineWidth',1.5);

hold on;

plot( ...
    1:nScenarios, ...
    scenario.theta_WP, ...
    '-s', ...
    'LineWidth',1.5);

plot( ...
    1:nScenarios, ...
    scenario.kp3d, ...
    '-^', ...
    'LineWidth',1.5);

grid on;

xlabel('Uncertainty Scenario');
ylabel('Parameter Value');

title('V3 Uncertainty Scenario Parameter Space');

legend( ...
    '\theta_{FC}', ...
    '\theta_{WP}', ...
    'k_{p3d}', ...
    'Location','best');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);

saveas( ...
    gcf, ...
    '18_V3_Uncertainty_Scenarios_Final.png');


%% ================================================================
% 14. FIGURE 19 - ROOT-LAYER SOIL MOISTURE
% ================================================================

figure( ...
    'Name','V3 Uncertainty Soil Moisture Final', ...
    'Color','w');

for sc = 1:nScenarios

    plot( ...
        t, ...
        thetaAll(:,1,sc), ...
        'LineWidth',1.2);

    hold on;

end

yline( ...
    theta_FC, ...
    '--', ...
    'LineWidth',1.0);

yline( ...
    theta_WP, ...
    ':', ...
    'LineWidth',1.0);

grid on;

xlabel('Time [days]');
ylabel('Root-Layer Soil Moisture \theta');

title( ...
    'Root-Layer Soil Moisture Under Parameter Uncertainty');

legend( ...
    [scenarioNames, ...
    {'Baseline \theta_{FC}', ...
     'Baseline \theta_{WP}'}], ...
    'Location','best');

saveas( ...
    gcf, ...
    '19_V3_Uncertainty_Theta_Final.png');


%% ================================================================
% 15. FIGURE 20 - FINAL STORAGE
% ================================================================

figure( ...
    'Name','V3 Uncertainty Storage Final', ...
    'Color','w');

bar(finalStorage);

grid on;

xlabel('Uncertainty Scenario');
ylabel('Final Storage [mm]');

title('Final Soil Water Storage Under Uncertainty');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);

saveas( ...
    gcf, ...
    '20_V3_Uncertainty_Storage_Final.png');


%% ================================================================
% 16. FIGURE 21 - ACTUAL ET
% ================================================================

figure( ...
    'Name','V3 Uncertainty ET Final', ...
    'Color','w');

bar(actualET);

grid on;

xlabel('Uncertainty Scenario');
ylabel('Actual ET [mm]');

title('Actual Evapotranspiration Under Parameter Uncertainty');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);

saveas( ...
    gcf, ...
    '21_V3_Uncertainty_ET_Final.png');


%% ================================================================
% 17. FIGURE 22 - DEEP DRAINAGE
% ================================================================

figure( ...
    'Name','V3 Uncertainty Drainage Final', ...
    'Color','w');

bar(deepDrainage);

grid on;

xlabel('Uncertainty Scenario');
ylabel('Deep Drainage [mm]');

title('Deep Drainage Under Parameter Uncertainty');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);

saveas( ...
    gcf, ...
    '22_V3_Uncertainty_Drainage_Final.png');


%% ================================================================
% 18. FIGURE 23 - ROBUSTNESS SUMMARY
% ================================================================

figure( ...
    'Name','V3 Uncertainty Robustness Summary Final', ...
    'Color','w');

subplot(2,2,1);

bar(finalStorage);

grid on;

xlabel('Scenario');
ylabel('Final Storage [mm]');
title('Final Storage');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);


subplot(2,2,2);

bar(actualET);

grid on;

xlabel('Scenario');
ylabel('Actual ET [mm]');
title('Actual ET');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);


subplot(2,2,3);

bar(deepDrainage);

grid on;

xlabel('Scenario');
ylabel('Drainage [mm]');
title('Deep Drainage');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);


subplot(2,2,4);

bar(waterStress);

grid on;

xlabel('Scenario');
ylabel('Water Stress');
title('Water Stress');

xticks(1:nScenarios);
xticklabels(scenarioNames);
xtickangle(30);


saveas( ...
    gcf, ...
    '23_V3_Uncertainty_Summary_Final.png');


%% ================================================================
% 19. SAVE RESULTS
% ================================================================

uncertaintyResults = struct();

uncertaintyResults.version = ...
    'V3 Final Uncertainty Analysis';

uncertaintyResults.time = t;
uncertaintyResults.dt = dt;

uncertaintyResults.scenarioNames = ...
    scenarioNames;

uncertaintyResults.scenario = ...
    scenario;


% Dynamic results
uncertaintyResults.theta = ...
    thetaAll;

uncertaintyResults.storage = ...
    storageAll;

uncertaintyResults.ET_total = ...
    ETtotalAll;

uncertaintyResults.drainage = ...
    drainageAll;

uncertaintyResults.irrigation = ...
    irrigationAll;

uncertaintyResults.rainfall = ...
    rainfallAll;

uncertaintyResults.waterStressTimeSeries = ...
    waterStressAll;

uncertaintyResults.balanceErrorTimeSeries = ...
    balanceErrorAll;

uncertaintyResults.intervalBalanceErrorTimeSeries = ...
    intervalBalanceErrorAll;


% Summary metrics
uncertaintyResults.meanTheta = meanTheta;
uncertaintyResults.minTheta = minTheta;
uncertaintyResults.maxTheta = maxTheta;

uncertaintyResults.finalStorage = finalStorage;

uncertaintyResults.actualET = actualET;

uncertaintyResults.deepDrainage = deepDrainage;

uncertaintyResults.totalIrrigation = totalIrrigation;

uncertaintyResults.totalRainfall = totalRainfall;

uncertaintyResults.waterStress = waterStress;


% Validation
uncertaintyResults.waterBalanceError = ...
    waterBalanceError;

uncertaintyResults.maxBalanceError = ...
    maxBalanceError;

uncertaintyResults.maxIntervalBalanceError = ...
    globalMaxIntervalError;

uncertaintyResults.baselineReproduction = ...
    baselineReproduction;

uncertaintyResults.thetaDifference = ...
    thetaDifference;

uncertaintyResults.storageDifference = ...
    storageDifference;

uncertaintyResults.ETDifference = ...
    ETDifference;

uncertaintyResults.drainageDifference = ...
    drainageDifference;

uncertaintyResults.clippingCount = ...
    clippingCount;

uncertaintyResults.thetaBoundsPass = ...
    boundsPass;


% Robustness
uncertaintyResults.thetaRange = thetaRange;

uncertaintyResults.storageRange = storageRange;

uncertaintyResults.ETRange = ETRange;

uncertaintyResults.drainageRange = drainageRange;

uncertaintyResults.stressRange = stressRange;


% Worst cases
uncertaintyResults.worstCase.lowestFinalStorage = ...
    idxMinStorage;

uncertaintyResults.worstCase.highestWaterStress = ...
    idxMaxStress;

uncertaintyResults.worstCase.lowestActualET = ...
    idxMinET;

uncertaintyResults.worstCase.highestDeepDrainage = ...
    idxMaxDrainage;


save( ...
    'V3_UncertaintyAnalysis_Final_Results.mat', ...
    'uncertaintyResults');


%% ================================================================
% 20. FINAL REPORT
% ================================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 UNCERTAINTY ANALYSIS - FINAL REPORT\n');
fprintf('====================================================\n\n');

fprintf('Scenarios evaluated: %d\n\n',nScenarios);


fprintf('Baseline reproduction:\n');

if baselineReproduction
    fprintf('PASS\n\n');
else
    fprintf('FAIL\n\n');
end


fprintf('Independent water balance:\n');

if maxBalanceError < 1e-8
    fprintf('PASS\n\n');
else
    fprintf('FAIL\n\n');
end


fprintf('Interval water balance:\n');

if globalMaxIntervalError < 1e-8
    fprintf('PASS\n\n');
else
    fprintf('FAIL\n\n');
end


fprintf('Physical theta bounds:\n');

if boundsPass
    fprintf('PASS\n\n');
else
    fprintf('FAIL\n\n');
end


fprintf('Robustness ranges:\n');
fprintf('----------------------------------------\n');

fprintf('Final storage range : %.6f mm\n', ...
    storageRange);

fprintf('Actual ET range     : %.6f mm\n', ...
    ETRange);

fprintf('Drainage range      : %.6f mm\n', ...
    drainageRange);

fprintf('Water stress range  : %.6f\n\n', ...
    stressRange);


fprintf('Worst cases:\n');
fprintf('----------------------------------------\n');

fprintf('Lowest final storage : %s\n', ...
    scenarioNames{idxMinStorage});

fprintf('Highest water stress : %s\n', ...
    scenarioNames{idxMaxStress});

fprintf('Lowest actual ET     : %s\n', ...
    scenarioNames{idxMinET});

fprintf('Highest drainage     : %s\n\n', ...
    scenarioNames{idxMaxDrainage});


fprintf('Clipping events:\n');
fprintf('----------------------------------------\n');

for sc = 1:nScenarios

    fprintf('%-25s %d\n', ...
        scenarioNames{sc}, ...
        clippingCount(sc));

end


fprintf('\nFigures saved:\n');
fprintf('18_V3_Uncertainty_Scenarios_Final.png\n');
fprintf('19_V3_Uncertainty_Theta_Final.png\n');
fprintf('20_V3_Uncertainty_Storage_Final.png\n');
fprintf('21_V3_Uncertainty_ET_Final.png\n');
fprintf('22_V3_Uncertainty_Drainage_Final.png\n');
fprintf('23_V3_Uncertainty_Summary_Final.png\n\n');

fprintf('Results saved to:\n');
fprintf('V3_UncertaintyAnalysis_Final_Results.mat\n\n');

fprintf('====================================================\n');
fprintf(' END\n');
fprintf('====================================================\n');