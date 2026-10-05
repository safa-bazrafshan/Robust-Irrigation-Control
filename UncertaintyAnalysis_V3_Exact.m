%% ================================================================
% UncertaintyAnalysis_V3_Exact.m
%
% AI-Driven Smart Irrigation
%
% Exact uncertainty / robustness analysis of Reduced Soil Water
% Model V3.
%
% The reference solver is reproduced exactly from:
% 01_ReducedSoilWaterModel_V3
%
% IMPORTANT:
%   The original V3 result file stores all variables inside
%   a structure named "results".
%
%   This script therefore reads:
%       results.time
%       results.dt
%       results.theta
%       results.S
%       results.ET_actual
%       results.q3d
%       etc.
%
% Existing V3 files are NOT overwritten.
%% ================================================================

clc;
clear;
close all;

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' V3 UNCERTAINTY & ROBUSTNESS ANALYSIS - EXACT SOLVER\n');
fprintf('===============================================================\n\n');

%% ================================================================
% 1. Load original V3 results
% ================================================================

baseFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(baseFile)

    error(['File not found: ',baseFile,newline,...
        'Run 01_ReducedSoilWaterModel_V3 first.']);

end

loaded = load(baseFile);

if ~isfield(loaded,'results')

    error(['The file ',baseFile,...
        ' does not contain the expected "results" structure.']);

end

ref = loaded.results;

fprintf('Reference file loaded successfully:\n');
fprintf('%s\n\n',baseFile);

%% ================================================================
% 2. Read reference V3 data
% ================================================================

time = ref.time(:);
dt   = ref.dt;
T    = ref.T;

N = length(time);

theta_ref = ref.theta;
S_ref     = ref.S;

theta_r  = ref.theta_r;
theta_s  = ref.theta_s;
theta_FC = ref.theta_FC;
theta_WP = ref.theta_WP;

Z = ref.Z(:);

nLayers = length(Z);

if nLayers ~= 3

    error('The current script requires exactly 3 soil layers.');

end

Z1 = Z(1);
Z2 = Z(2);
Z3 = Z(3);

root_depth = sum(Z);

irrigation  = ref.irrigation(:);
rainfall    = ref.rainfall(:);

ET_potential = ref.ET_potential(:);

ET_fraction = [0.50;0.30;0.20];

kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

Kinf = 0.020;

%% ================================================================
% 3. Reference outputs
% ================================================================

ET_ref = ref.ET_actual_total(:);

q3d_ref = ref.q3d(:);

storage_ref = ref.storage(:);

fprintf('Reference V3 configuration\n');
fprintf('---------------------------------------------------------------\n');

fprintf('Simulation time       : %.2f days\n',T);
fprintf('Time step             : %.4f day\n',dt);

fprintf('Number of layers      : %d\n',nLayers);

fprintf('Root-zone depth       : %.2f m\n',root_depth);

fprintf('\ntheta_r               : %.6f\n',theta_r);
fprintf('theta_s               : %.6f\n',theta_s);
fprintf('theta_FC              : %.6f\n',theta_FC);
fprintf('theta_WP              : %.6f\n',theta_WP);

fprintf('\nkp12                  : %.6f\n',kp12);
fprintf('kp23                  : %.6f\n',kp23);
fprintf('kp3d                  : %.6f\n',kp3d);
fprintf('Kinf                  : %.6f m/day\n',Kinf);

fprintf('\n');

%% ================================================================
% 4. Initial condition
% ================================================================

theta0 = theta_ref(1,:)';

S0 = theta0 .* Z;

%% ================================================================
% 5. Define uncertainty scenarios
% ================================================================
%
% A: Nominal
% B: Dry
% C: Wet
% D: Low drainage
% E: High drainage
% F: Combined
%
% NOTE:
% theta_r, theta_s, kp12, kp23 and Kinf remain identical to V3.
%
% Only theta_FC, theta_WP and kp3d are perturbed here.

scenarioNames = { ...
    'A - Nominal'
    'B - Dry'
    'C - Wet'
    'D - Low drainage'
    'E - High drainage'
    'F - Combined'};

nScenarios = length(scenarioNames);

scenarioThetaFC = [ ...
    theta_FC
    0.90*theta_FC
    1.10*theta_FC
    theta_FC
    theta_FC
    0.90*theta_FC];

scenarioThetaWP = [ ...
    theta_WP
    0.90*theta_WP
    1.10*theta_WP
    theta_WP
    theta_WP
    1.10*theta_WP];

scenarioKp3d = [ ...
    kp3d
    kp3d
    kp3d
    0.80*kp3d
    1.20*kp3d
    1.20*kp3d];

%% ================================================================
% 6. Preallocate scenario results
% ================================================================

thetaAll = zeros(N,3,nScenarios);

SAll = zeros(N,3,nScenarios);

storageAll = zeros(N,nScenarios);

soilStressAll = zeros(N,3,nScenarios);

ETactualAll = zeros(N,3,nScenarios);

ETtotalAll = zeros(N,nScenarios);

q12All = zeros(N,nScenarios);

q23All = zeros(N,nScenarios);

q3dAll = zeros(N,nScenarios);

infiltrationAll = zeros(N,nScenarios);

runoffAll = zeros(N,nScenarios);

cumulativeETAll = zeros(N,nScenarios);

cumulativeDrainageAll = zeros(N,nScenarios);

cumulativeIrrigationAll = zeros(N,nScenarios);

cumulativeRainfallAll = zeros(N,nScenarios);

cumulativeInfiltrationAll = zeros(N,nScenarios);

cumulativeRunoffAll = zeros(N,nScenarios);

waterBalanceStorageAll = zeros(N,nScenarios);

waterBalanceErrorAll = zeros(N,nScenarios);

intervalBalanceErrorAll = zeros(N-1,nScenarios);

%% Summary variables

finalStorage = zeros(nScenarios,1);

totalET = zeros(nScenarios,1);

totalDrainage = zeros(nScenarios,1);

totalIrrigation = zeros(nScenarios,1);

totalRainfall = zeros(nScenarios,1);

totalInfiltration = zeros(nScenarios,1);

totalRunoff = zeros(nScenarios,1);

meanTheta = zeros(nScenarios,1);

minTheta = zeros(nScenarios,1);

maxTheta = zeros(nScenarios,1);

meanStress = zeros(nScenarios,1);

maxStress = zeros(nScenarios,1);

independentBalanceError = zeros(nScenarios,1);

maxIntervalBalanceError = zeros(nScenarios,1);

clippingCount = zeros(nScenarios,1);

%% ================================================================
% 7. Run scenarios
% ================================================================

for s = 1:nScenarios

    fprintf('\n');
    fprintf('---------------------------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n',s,nScenarios,scenarioNames{s});
    fprintf('---------------------------------------------------------------\n');

    theta_FC_s = scenarioThetaFC(s);

    theta_WP_s = scenarioThetaWP(s);

    kp3d_s = scenarioKp3d(s);

    fprintf('theta_FC = %.6f\n',theta_FC_s);
    fprintf('theta_WP = %.6f\n',theta_WP_s);
    fprintf('kp3d     = %.6f\n',kp3d_s);

    %% ------------------------------------------------------------
    % Storage limits
    %% ------------------------------------------------------------

    S_min = theta_r .* Z;

    S_max = theta_s .* Z;

    S_FC = theta_FC_s .* Z;

    S_WP = theta_WP_s .* Z;

    %% ------------------------------------------------------------
    % Allocate scenario variables
    %% ------------------------------------------------------------

    S = zeros(N,3);

    theta = zeros(N,3);

    infiltration = zeros(N,1);

    runoff = zeros(N,1);

    q12 = zeros(N,1);

    q23 = zeros(N,1);

    q3d = zeros(N,1);

    ET_actual = zeros(N,3);

    soil_stress = zeros(N,3);

    %% ------------------------------------------------------------
    % Initial state
    %% ------------------------------------------------------------

    S(1,:) = S0';

    theta(1,:) = theta0';

    %% ============================================================
    % EXACT V3 SOLVER
    % ============================================================

    for k = 1:N-1

        % ---------------------------------------------------------
        % Current storage
        % ---------------------------------------------------------

        S_current = S(k,:)';

        % ---------------------------------------------------------
        % External water input
        % ---------------------------------------------------------

        I = irrigation(k) / 1000;

        P = rainfall(k) / 1000;

        water_input = I + P;

        % ---------------------------------------------------------
        % 1. Surface infiltration
        % ---------------------------------------------------------

        current_theta1 = ...
            S_current(1) / Z1;

        remaining_capacity = ...
            S_max(1) - S_current(1);

        saturation_factor = ...
            (theta_s - current_theta1) / ...
            (theta_s - theta_FC_s);

        saturation_factor = ...
            min(max(saturation_factor,0),1);

        infiltration_capacity = ...
            Kinf * saturation_factor;

        potential_infiltration = ...
            min(water_input,infiltration_capacity);

        actual_infiltration = ...
            min(potential_infiltration / 1, ...
                remaining_capacity / dt);

        actual_infiltration = ...
            max(actual_infiltration,0);

        surface_excess = ...
            max(0,water_input-actual_infiltration);

        infiltration(k) = actual_infiltration;

        runoff(k) = surface_excess;

        S_current(1) = ...
            S_current(1) + ...
            actual_infiltration*dt;

        % ---------------------------------------------------------
        % 2. Calculate soil water stress
        % ---------------------------------------------------------

        theta_current = ...
            S_current ./ Z;

        stress = ...
            (theta_current-theta_WP_s) ./ ...
            (theta_FC_s-theta_WP_s);

        stress = ...
            min(max(stress,0),1);

        soil_stress(k,:) = stress';

        % ---------------------------------------------------------
        % 3. Actual evapotranspiration
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

        % ---------------------------------------------------------
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
            min(potential_q12*dt, ...
                max_transfer12);

        transfer12 = ...
            min(transfer12,max_receive12);

        transfer12 = ...
            max(transfer12,0);

        S_current(1) = ...
            S_current(1)-transfer12;

        S_current(2) = ...
            S_current(2)+transfer12;

        q12(k) = ...
            transfer12/dt;

        % ---------------------------------------------------------
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
            min(potential_q23*dt, ...
                max_transfer23);

        transfer23 = ...
            min(transfer23,max_receive23);

        transfer23 = ...
            max(transfer23,0);

        S_current(2) = ...
            S_current(2)-transfer23;

        S_current(3) = ...
            S_current(3)+transfer23;

        q23(k) = ...
            transfer23/dt;

        % ---------------------------------------------------------
        % 6. Deep drainage from Layer 3
        % ---------------------------------------------------------

        excess3 = ...
            max(0,S_current(3)-S_FC(3));

        potential_q3d = ...
            kp3d_s * excess3;

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

        % ---------------------------------------------------------
        % 7. Final physical bounds
        % ---------------------------------------------------------

        S_before_bounds = S_current;

        S_current = ...
            min(max(S_current,S_min),S_max);

        boundChange = ...
            abs(S_current-S_before_bounds);

        clippingCount(s) = ...
            clippingCount(s) + ...
            sum(boundChange > 1e-12);

        % ---------------------------------------------------------
        % 8. Store new state
        % ---------------------------------------------------------

        S(k+1,:) = S_current';

        theta(k+1,:) = ...
            (S_current ./ Z)';

    end

    %% ============================================================
    % 8. Final stress values
    % ============================================================

    theta1 = theta(:,1);

    theta2 = theta(:,2);

    theta3 = theta(:,3);

    stress1 = ...
        (theta1-theta_WP_s) ./ ...
        (theta_FC_s-theta_WP_s);

    stress2 = ...
        (theta2-theta_WP_s) ./ ...
        (theta_FC_s-theta_WP_s);

    stress3 = ...
        (theta3-theta_WP_s) ./ ...
        (theta_FC_s-theta_WP_s);

    stress1 = min(max(stress1,0),1);

    stress2 = min(max(stress2,0),1);

    stress3 = min(max(stress3,0),1);

    soil_stress = ...
        [stress1,stress2,stress3];

    %% ============================================================
    % 9. Actual ET
    % ============================================================

    ET_actual_total = ...
        sum(ET_actual,2);

    %% ============================================================
    % 10. Soil water storage
    % ============================================================

    storage = ...
        S(:,1) + S(:,2) + S(:,3);

    %% ============================================================
    % 11. Cumulative fluxes
    % ============================================================

    cum_irrigation = ...
        cumsum(irrigation) * dt / 1000;

    cum_rainfall = ...
        cumsum(rainfall) * dt / 1000;

    cum_infiltration = ...
        cumsum(infiltration) * dt;

    cum_runoff = ...
        cumsum(runoff) * dt;

    cum_ET = ...
        cumsum(ET_actual_total) * dt;

    cum_q3d = ...
        cumsum(q3d) * dt;

    %% ============================================================
    % 12. Water balance
    % ============================================================

    initial_storage = storage(1);

    water_balance_storage = ...
        initial_storage ...
        + cum_infiltration ...
        - cum_runoff ...
        - cum_ET ...
        - cum_q3d;

    water_balance_error = ...
        storage-water_balance_storage;

    %% ============================================================
    % 13. Independent total water balance
    % ============================================================

    total_I = ...
        sum(irrigation)*dt/1000;

    total_P = ...
        sum(rainfall)*dt/1000;

    total_Inf = ...
        sum(infiltration)*dt;

    total_RO = ...
        sum(runoff)*dt;

    total_ET_s = ...
        sum(ET_actual_total)*dt;

    total_Drain_s = ...
        sum(q3d)*dt;

    independent_error = ...
        storage(end) - ...
        (initial_storage ...
        + total_Inf ...
        - total_RO ...
        - total_ET_s ...
        - total_Drain_s);

    %% ============================================================
    % 14. Interval water balance
    % ============================================================

    interval_error = zeros(N-1,1);

    for k = 1:N-1

        storage_change = ...
            storage(k+1)-storage(k);

        expected_change = ...
            infiltration(k)*dt ...
            - runoff(k)*dt ...
            - ET_actual_total(k)*dt ...
            - q3d(k)*dt;

        interval_error(k) = ...
            storage_change-expected_change;

    end

    %% ============================================================
    % 15. Store scenario results
    % ============================================================

    thetaAll(:,:,s) = theta;

    SAll(:,:,s) = S;

    storageAll(:,s) = storage;

    soilStressAll(:,:,s) = soil_stress;

    ETactualAll(:,:,s) = ET_actual;

    ETtotalAll(:,s) = ET_actual_total;

    q12All(:,s) = q12;

    q23All(:,s) = q23;

    q3dAll(:,s) = q3d;

    infiltrationAll(:,s) = infiltration;

    runoffAll(:,s) = runoff;

    cumulativeETAll(:,s) = ...
        cum_ET*1000;

    cumulativeDrainageAll(:,s) = ...
        cum_q3d*1000;

    cumulativeIrrigationAll(:,s) = ...
        cum_irrigation*1000;

    cumulativeRainfallAll(:,s) = ...
        cum_rainfall*1000;

    cumulativeInfiltrationAll(:,s) = ...
        cum_infiltration*1000;

    cumulativeRunoffAll(:,s) = ...
        cum_runoff*1000;

    waterBalanceStorageAll(:,s) = ...
        water_balance_storage;

    waterBalanceErrorAll(:,s) = ...
        water_balance_error;

    intervalBalanceErrorAll(:,s) = ...
        interval_error;

    %% ============================================================
    % 16. Summary
    % ============================================================

    finalStorage(s) = storage(end);

    totalET(s) = ...
        total_ET_s*1000;

    totalDrainage(s) = ...
        total_Drain_s*1000;

    totalIrrigation(s) = ...
        total_I*1000;

    totalRainfall(s) = ...
        total_P*1000;

    totalInfiltration(s) = ...
        total_Inf*1000;

    totalRunoff(s) = ...
        total_RO*1000;

    meanTheta(s) = ...
        mean(theta(:));

    minTheta(s) = ...
        min(theta(:));

    maxTheta(s) = ...
        max(theta(:));

    meanStress(s) = ...
        mean(soil_stress(:));

    maxStress(s) = ...
        max(soil_stress(:));

    independentBalanceError(s) = ...
        independent_error*1000;

    maxIntervalBalanceError(s) = ...
        max(abs(interval_error))*1000;

    %% ============================================================
    % 17. Console report
    % ============================================================

    fprintf('\n');

    fprintf('Final storage       : %.6f mm\n', ...
        finalStorage(s)*1000);

    fprintf('Actual ET           : %.6f mm\n', ...
        totalET(s));

    fprintf('Deep drainage       : %.6f mm\n', ...
        totalDrainage(s));

    fprintf('Irrigation          : %.6f mm\n', ...
        totalIrrigation(s));

    fprintf('Rainfall            : %.6f mm\n', ...
        totalRainfall(s));

    fprintf('Infiltration        : %.6f mm\n', ...
        totalInfiltration(s));

    fprintf('Runoff              : %.6f mm\n', ...
        totalRunoff(s));

    fprintf('Mean theta          : %.6f\n', ...
        meanTheta(s));

    fprintf('Min theta           : %.6f\n', ...
        minTheta(s));

    fprintf('Max theta           : %.6f\n', ...
        maxTheta(s));

    fprintf('Mean stress         : %.6f\n', ...
        meanStress(s));

    fprintf('Max stress          : %.6f\n', ...
        maxStress(s));

    fprintf('Independent WB error: %.6e mm\n', ...
        independentBalanceError(s));

    fprintf('Max interval error  : %.6e mm\n', ...
        maxIntervalBalanceError(s));

    fprintf('Clipping count      : %d\n', ...
        clippingCount(s));

end

%% ================================================================
% 18. BASELINE REPRODUCTION TEST
% ================================================================

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' BASELINE REPRODUCTION TEST\n');
fprintf('===============================================================\n\n');

thetaDiff = ...
    max(abs(thetaAll(:,:,1)-theta_ref),[],'all');

storageDiff = ...
    max(abs(storageAll(:,1)-storage_ref));

ETDiff = ...
    max(abs(ETtotalAll(:,1)-ET_ref));

drainageDiff = ...
    max(abs(q3dAll(:,1)-q3d_ref));

fprintf('Maximum theta difference    : %.12e\n',thetaDiff);

fprintf('Maximum storage difference  : %.12e m\n',storageDiff);

fprintf('Maximum ET difference       : %.12e m/day\n',ETDiff);

fprintf('Maximum drainage difference : %.12e m/day\n',drainageDiff);

fprintf('\n');

tol = 1e-12;

thetaPass = thetaDiff <= tol;

storagePass = storageDiff <= tol;

ETPass = ETDiff <= tol;

drainagePass = drainageDiff <= tol;

if thetaPass
    fprintf('PASS: theta reproduction\n');
else
    fprintf('FAIL: theta reproduction\n');
end

if storagePass
    fprintf('PASS: storage reproduction\n');
else
    fprintf('FAIL: storage reproduction\n');
end

if ETPass
    fprintf('PASS: ET reproduction\n');
else
    fprintf('FAIL: ET reproduction\n');
end

if drainagePass
    fprintf('PASS: drainage reproduction\n');
else
    fprintf('FAIL: drainage reproduction\n');
end

baselineReproductionPASS = ...
    thetaPass && ...
    storagePass && ...
    ETPass && ...
    drainagePass;

fprintf('\n');

if baselineReproductionPASS

    fprintf('===============================================================\n');
    fprintf(' BASELINE REPRODUCTION: PASS\n');
    fprintf('===============================================================\n');

else

    fprintf('===============================================================\n');
    fprintf(' BASELINE REPRODUCTION: FAIL\n');
    fprintf('===============================================================\n');

    fprintf('\n');
    fprintf('STOP: Uncertainty results must not yet be interpreted.\n');
    fprintf('The uncertainty solver must first reproduce V3 exactly.\n');

end

%% ================================================================
% 19. Physical validation
% ================================================================

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' PHYSICAL VALIDATION\n');
fprintf('===============================================================\n\n');

boundsPass = true;

balancePass = true;

fluxPass = true;

clippingPass = true;

for s = 1:nScenarios

    th = thetaAll(:,:,s);

    if min(th(:)) < theta_r-tol || ...
       max(th(:)) > theta_s+tol

        boundsPass = false;

        fprintf('%s : FAIL - theta bounds\n', ...
            scenarioNames{s});

    else

        fprintf('%s : PASS - theta bounds\n', ...
            scenarioNames{s});

    end

    if max(abs(waterBalanceErrorAll(:,s))) > tol

        balancePass = false;

        fprintf('%s : FAIL - water balance\n', ...
            scenarioNames{s});

    else

        fprintf('%s : PASS - water balance\n', ...
            scenarioNames{s});

    end

    fluxVector = [ ...
        q12All(:,s)
        q23All(:,s)
        q3dAll(:,s)
        infiltrationAll(:,s)
        runoffAll(:,s)];

    if min(fluxVector) < -tol

        fluxPass = false;

        fprintf('%s : FAIL - negative flux\n', ...
            scenarioNames{s});

    else

        fprintf('%s : PASS - nonnegative fluxes\n', ...
            scenarioNames{s});

    end

    if clippingCount(s) ~= 0

        clippingPass = false;

        fprintf('%s : WARNING - clipping count = %d\n', ...
            scenarioNames{s}, ...
            clippingCount(s));

    else

        fprintf('%s : PASS - no clipping\n', ...
            scenarioNames{s});

    end

end

%% ================================================================
% 20. Robustness summary
% ================================================================

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' ROBUSTNESS SUMMARY\n');
fprintf('===============================================================\n\n');

storageRange = ...
    (max(finalStorage)-min(finalStorage))*1000;

ETRange = ...
    max(totalET)-min(totalET);

drainageRange = ...
    max(totalDrainage)-min(totalDrainage);

thetaRange = ...
    max(meanTheta)-min(meanTheta);

stressRange = ...
    max(meanStress)-min(meanStress);

fprintf('Final storage range : %.6f mm\n',storageRange);

fprintf('Actual ET range     : %.6f mm\n',ETRange);

fprintf('Drainage range      : %.6f mm\n',drainageRange);

fprintf('Mean theta range    : %.6f\n',thetaRange);

fprintf('Mean stress range   : %.6f\n',stressRange);

[~,idxLowestStorage] = min(finalStorage);

[~,idxHighestStress] = max(meanStress);

[~,idxLowestET] = min(totalET);

[~,idxHighestDrainage] = max(totalDrainage);

fprintf('\n');

fprintf('Lowest final storage : %s\n', ...
    scenarioNames{idxLowestStorage});

fprintf('Highest mean stress  : %s\n', ...
    scenarioNames{idxHighestStress});

fprintf('Lowest actual ET     : %s\n', ...
    scenarioNames{idxLowestET});

fprintf('Highest drainage     : %s\n', ...
    scenarioNames{idxHighestDrainage});

%% ================================================================
% 21. Summary table
% ================================================================

Scenario = scenarioNames;

SummaryTable = table( ...
    Scenario, ...
    scenarioThetaFC, ...
    scenarioThetaWP, ...
    scenarioKp3d, ...
    finalStorage*1000, ...
    totalET, ...
    totalDrainage, ...
    meanTheta, ...
    minTheta, ...
    maxTheta, ...
    meanStress, ...
    independentBalanceError, ...
    clippingCount, ...
    'VariableNames',{ ...
    'Scenario'
    'theta_FC'
    'theta_WP'
    'kp3d'
    'FinalStorage_mm'
    'ActualET_mm'
    'DeepDrainage_mm'
    'MeanTheta'
    'MinTheta'
    'MaxTheta'
    'MeanStress'
    'WaterBalanceError_mm'
    'ClippingCount'});

fprintf('\n');
disp(SummaryTable);

%% ================================================================
% 22. Figure - Soil moisture
% ================================================================

figure( ...
    'Name','V3 Uncertainty - Soil Moisture', ...
    'Color','w');

for i = 1:3

    subplot(3,1,i);

    hold on;

    for s = 1:nScenarios

        plot( ...
            time, ...
            thetaAll(:,i,s), ...
            'LineWidth',1.2);

    end

    yline(theta_WP,'--','Wilting Point');

    yline(theta_FC,'--','Field Capacity');

    grid on;

    xlabel('Time [day]');

    ylabel(['\theta_',num2str(i)]);

    title(['Layer ',num2str(i)]);

    if i == 1

        legend( ...
            scenarioNames, ...
            'Location','best');

    end

end

saveas( ...
    gcf, ...
    '30_V3_Uncertainty_Theta_Exact.png');

%% ================================================================
% 23. Figure - Total storage
% ================================================================

figure( ...
    'Name','V3 Uncertainty - Storage', ...
    'Color','w');

hold on;

for s = 1:nScenarios

    plot( ...
        time, ...
        storageAll(:,s)*1000, ...
        'LineWidth',1.4);

end

grid on;

xlabel('Time [day]');

ylabel('Total Soil Water Storage [mm]');

title('V3 Uncertainty - Total Soil Water Storage');

legend( ...
    scenarioNames, ...
    'Location','best');

saveas( ...
    gcf, ...
    '31_V3_Uncertainty_Storage_Exact.png');

%% ================================================================
% 24. Figure - Actual ET
% ================================================================

figure( ...
    'Name','V3 Uncertainty - ET', ...
    'Color','w');

hold on;

for s = 1:nScenarios

    plot( ...
        time, ...
        cumulativeETAll(:,s), ...
        'LineWidth',1.4);

end

grid on;

xlabel('Time [day]');

ylabel('Cumulative Actual ET [mm]');

title('V3 Uncertainty - Cumulative Actual ET');

legend( ...
    scenarioNames, ...
    'Location','best');

saveas( ...
    gcf, ...
    '32_V3_Uncertainty_ET_Exact.png');

%% ================================================================
% 25. Figure - Deep drainage
% ================================================================

figure( ...
    'Name','V3 Uncertainty - Drainage', ...
    'Color','w');

hold on;

for s = 1:nScenarios

    plot( ...
        time, ...
        cumulativeDrainageAll(:,s), ...
        'LineWidth',1.4);

end

grid on;

xlabel('Time [day]');

ylabel('Cumulative Deep Drainage [mm]');

title('V3 Uncertainty - Cumulative Deep Drainage');

legend( ...
    scenarioNames, ...
    'Location','best');

saveas( ...
    gcf, ...
    '33_V3_Uncertainty_Drainage_Exact.png');

%% ================================================================
% 26. Figure - Water stress
% ================================================================

figure( ...
    'Name','V3 Uncertainty - Water Stress', ...
    'Color','w');

hold on;

for s = 1:nScenarios

    meanStressTime = ...
        mean(soilStressAll(:,:,s),2);

    plot( ...
        time, ...
        meanStressTime, ...
        'LineWidth',1.4);

end

grid on;

xlabel('Time [day]');

ylabel('Mean Water Stress');

title('V3 Uncertainty - Mean Soil Water Stress');

legend( ...
    scenarioNames, ...
    'Location','best');

ylim([0 1.05]);

saveas( ...
    gcf, ...
    '34_V3_Uncertainty_Stress_Exact.png');

%% ================================================================
% 27. Figure - Performance summary
% ================================================================

figure( ...
    'Name','V3 Uncertainty - Summary', ...
    'Color','w');

subplot(2,2,1);

bar(finalStorage*1000);

grid on;

ylabel('Final Storage [mm]');

title('Final Storage');

set(gca, ...
    'XTick',1:nScenarios, ...
    'XTickLabel',{'A','B','C','D','E','F'});

subplot(2,2,2);

bar(totalET);

grid on;

ylabel('Actual ET [mm]');

title('Actual ET');

set(gca, ...
    'XTick',1:nScenarios, ...
    'XTickLabel',{'A','B','C','D','E','F'});

subplot(2,2,3);

bar(totalDrainage);

grid on;

ylabel('Deep Drainage [mm]');

title('Deep Drainage');

set(gca, ...
    'XTick',1:nScenarios, ...
    'XTickLabel',{'A','B','C','D','E','F'});

subplot(2,2,4);

bar(meanStress);

grid on;

ylabel('Mean Stress');

title('Mean Water Stress');

set(gca, ...
    'XTick',1:nScenarios, ...
    'XTickLabel',{'A','B','C','D','E','F'});

saveas( ...
    gcf, ...
    '35_V3_Uncertainty_Summary_Exact.png');

%% ================================================================
% 28. Save results
% ================================================================

ResultsFile = ...
    'V3_UncertaintyAnalysis_Exact_Results.mat';

save( ...
    ResultsFile, ...
    'time', ...
    'dt', ...
    'T', ...
    'Z', ...
    'root_depth', ...
    'theta_r', ...
    'theta_s', ...
    'theta_FC', ...
    'theta_WP', ...
    'theta0', ...
    'kp12', ...
    'kp23', ...
    'kp3d', ...
    'Kinf', ...
    'ET_fraction', ...
    'irrigation', ...
    'rainfall', ...
    'ET_potential', ...
    'scenarioNames', ...
    'scenarioThetaFC', ...
    'scenarioThetaWP', ...
    'scenarioKp3d', ...
    'thetaAll', ...
    'SAll', ...
    'storageAll', ...
    'soilStressAll', ...
    'ETactualAll', ...
    'ETtotalAll', ...
    'q12All', ...
    'q23All', ...
    'q3dAll', ...
    'infiltrationAll', ...
    'runoffAll', ...
    'cumulativeETAll', ...
    'cumulativeDrainageAll', ...
    'cumulativeIrrigationAll', ...
    'cumulativeRainfallAll', ...
    'cumulativeInfiltrationAll', ...
    'cumulativeRunoffAll', ...
    'waterBalanceStorageAll', ...
    'waterBalanceErrorAll', ...
    'intervalBalanceErrorAll', ...
    'finalStorage', ...
    'totalET', ...
    'totalDrainage', ...
    'totalIrrigation', ...
    'totalRainfall', ...
    'totalInfiltration', ...
    'totalRunoff', ...
    'meanTheta', ...
    'minTheta', ...
    'maxTheta', ...
    'meanStress', ...
    'maxStress', ...
    'independentBalanceError', ...
    'maxIntervalBalanceError', ...
    'clippingCount', ...
    'thetaDiff', ...
    'storageDiff', ...
    'ETDiff', ...
    'drainageDiff', ...
    'baselineReproductionPASS', ...
    'boundsPass', ...
    'balancePass', ...
    'fluxPass', ...
    'clippingPass');

%% ================================================================
% 29. Final report
% ================================================================

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' ANALYSIS COMPLETE\n');
fprintf('===============================================================\n\n');

fprintf('Baseline reproduction : ');

if baselineReproductionPASS
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Physical bounds       : ');

if boundsPass
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Water balance         : ');

if balancePass
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Nonnegative fluxes    : ');

if fluxPass
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('No clipping           : ');

if clippingPass
    fprintf('PASS\n');
else
    fprintf('WARNING\n');
end

fprintf('\nResults saved to:\n');
fprintf('%s\n',ResultsFile);

fprintf('\nFigures saved:\n');
fprintf('30_V3_Uncertainty_Theta_Exact.png\n');
fprintf('31_V3_Uncertainty_Storage_Exact.png\n');
fprintf('32_V3_Uncertainty_ET_Exact.png\n');
fprintf('33_V3_Uncertainty_Drainage_Exact.png\n');
fprintf('34_V3_Uncertainty_Stress_Exact.png\n');
fprintf('35_V3_Uncertainty_Summary_Exact.png\n');

fprintf('\n');
fprintf('===============================================================\n');
fprintf(' END\n');
fprintf('===============================================================\n');