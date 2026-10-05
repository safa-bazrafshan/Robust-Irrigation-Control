%% V3_05_MPC_UncertaintyEvaluation.m
% Robust MPC evaluation under the same six uncertainty scenarios
% used for the PPO controller.
%
% This script:
% 1. Uses the validated V3 soil-water model.
% 2. Evaluates the existing MPC formulation under six scenarios.
% 3. Uses fmincon with SQP.
% 4. Computes the same core performance and physical-validation metrics.
% 5. Saves all results and figures.
%
% Main output:
% V3_05_MPC_UncertaintyEvaluation_Results.mat
%
% Required toolbox:
% Optimization Toolbox

clear;
clc;
close all;

fprintf('============================================================\n');
fprintf(' V3_05 - MPC UNCERTAINTY EVALUATION\n');
fprintf('============================================================\n\n');

%% ============================================================
% 1. GLOBAL SETTINGS
% =============================================================

dt = 0.25;                 % day
T = 120;                   % evaluation period [day]

N = round(T/dt) + 1;
time = (0:N-1)' * dt;

% Soil hydraulic parameters
theta_r = 0.078;
theta_s = 0.430;

theta_FC_nominal = 0.250;
theta_WP_nominal = 0.120;

% Layer thicknesses [m]
Z = [0.10; 0.20; 0.30];
root_depth = sum(Z);

% Initial volumetric water content
theta0 = [0.20; 0.20; 0.20];

% Hydraulic transfer parameters
kp12 = 0.80;
kp23 = 0.50;

% Infiltration parameter
Kinf = 0.020;              % m/day

% Environmental forcing
rainfall = zeros(N,1);     % mm/day
ET_potential = 4 * ones(N,1); % mm/day

% ET distribution among layers
ET_fraction = [0.50; 0.30; 0.20];

% MPC settings
Np = 16;                   % 4-day prediction horizon
target = 0.205;

target_lower = 0.180;
target_upper = 0.230;

u_min = 0;
u_max = 12;                % mm/day

% MPC objective weights
w_tracking  = 3000;
w_irrigation = 2;
w_drainage  = 100;
w_lower     = 12000;
w_upper     = 3000;
w_terminal  = 6000;

%% ============================================================
% 2. UNCERTAINTY SCENARIOS
% =============================================================

scenario_names = { ...
    'Nominal', ...
    'Dry', ...
    'Wet', ...
    'Low drainage', ...
    'High drainage', ...
    'Combined'};

theta_FC_values = [ ...
    0.250;
    0.225;
    0.275;
    0.250;
    0.250;
    0.225];

theta_WP_values = [ ...
    0.120;
    0.108;
    0.132;
    0.120;
    0.120;
    0.132];

kp3d_values = [ ...
    0.20;
    0.20;
    0.20;
    0.16;
    0.24;
    0.24];

nScenarios = numel(scenario_names);

%% ============================================================
% 3. RESULT STORAGE
% =============================================================

results = struct();

results.scenario_names = scenario_names;
results.theta_FC = theta_FC_values;
results.theta_WP = theta_WP_values;
results.kp3d = kp3d_values;

results.time = time;

results.total_irrigation = zeros(nScenarios,1);
results.actual_ET = zeros(nScenarios,1);
results.deep_drainage = zeros(nScenarios,1);
results.runoff = zeros(nScenarios,1);
results.total_infiltration = zeros(nScenarios,1);

results.initial_storage = zeros(nScenarios,1);
results.final_storage = zeros(nScenarios,1);

results.root_RMSE = zeros(nScenarios,1);
results.time_under_stress = zeros(nScenarios,1);
results.time_above_band = zeros(nScenarios,1);
results.time_inside_target = zeros(nScenarios,1);

results.mean_theta = zeros(nScenarios,1);
results.min_theta = zeros(nScenarios,1);
results.max_theta = zeros(nScenarios,1);
results.mean_stress = zeros(nScenarios,1);

results.water_balance_error = zeros(nScenarios,1);
results.max_interval_water_balance_error = zeros(nScenarios,1);

results.validation_theta = false(nScenarios,1);
results.validation_storage = false(nScenarios,1);
results.validation_flux = false(nScenarios,1);
results.validation_irrigation = false(nScenarios,1);
results.validation_balance = false(nScenarios,1);
results.validation_overall = false(nScenarios,1);

results.irrigation = cell(nScenarios,1);
results.theta = cell(nScenarios,1);
results.theta_root = cell(nScenarios,1);
results.stress = cell(nScenarios,1);
results.ET_actual = cell(nScenarios,1);
results.q3d = cell(nScenarios,1);
results.runoff_flux = cell(nScenarios,1);
results.infiltration = cell(nScenarios,1);
results.storage = cell(nScenarios,1);

%% ============================================================
% 4. OPTIMIZATION OPTIONS
% =============================================================

options = optimoptions('fmincon', ...
    'Algorithm','sqp', ...
    'Display','none', ...
    'MaxIterations',100, ...
    'MaxFunctionEvaluations',5000, ...
    'OptimalityTolerance',1e-5, ...
    'StepTolerance',1e-6);

%% ============================================================
% 5. RUN ALL SCENARIOS
% =============================================================

for s = 1:nScenarios

    fprintf('\n------------------------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n', ...
        s, nScenarios, scenario_names{s});
    fprintf('theta_FC = %.3f\n', theta_FC_values(s));
    fprintf('theta_WP = %.3f\n', theta_WP_values(s));
    fprintf('kp3d     = %.3f\n', kp3d_values(s));
    fprintf('------------------------------------------------------------\n');

    theta_FC = theta_FC_values(s);
    theta_WP = theta_WP_values(s);
    kp3d = kp3d_values(s);

    %% --------------------------------------------------------
    % Initial state
    % ---------------------------------------------------------

    S_current = theta0 .* Z;

    S_min = theta_r .* Z;
    S_max = theta_s .* Z;
    S_FC = theta_FC .* Z;
    S_WP = theta_WP .* Z;

    initial_storage = sum(S_current);

    %% --------------------------------------------------------
    % State and flux arrays
    % ---------------------------------------------------------

    theta = zeros(N,3);
    theta_root = zeros(N,1);
    storage = zeros(N,1);
    stress = zeros(N,3);

    irrigation = zeros(N,1);
    infiltration = zeros(N,1);
    runoff_flux = zeros(N,1);

    ET_actual = zeros(N,3);
    q12 = zeros(N,1);
    q23 = zeros(N,1);
    q3d = zeros(N,1);

    theta(1,:) = (S_current ./ Z)';
    theta_root(1) = sum(S_current) / root_depth;
    storage(1) = sum(S_current);

    initial_stress = ...
        (theta(:,1) - theta_WP_nominal) ./ ...
        (theta_FC_nominal - theta_WP_nominal);

    %% --------------------------------------------------------
    % Initial MPC guess
    % ---------------------------------------------------------

    u_previous = 0;

    %% --------------------------------------------------------
    % Main simulation loop
    % ---------------------------------------------------------

    for k = 1:N-1

        % Current state
        x_current = S_current;

        % -----------------------------------------------------
        % Determine prediction horizon
        % -----------------------------------------------------

        remaining_steps = N - k;
        horizon = min(Np, remaining_steps);

        % -----------------------------------------------------
        % Initial guess
        % -----------------------------------------------------

        if k == 1
            u0 = 4 * ones(horizon,1);
        else
            u0 = repmat(u_previous,horizon,1);
        end

        u0 = min(max(u0,u_min),u_max);

        % -----------------------------------------------------
        % Optimization bounds
        % -----------------------------------------------------

        lb = u_min * ones(horizon,1);
        ub = u_max * ones(horizon,1);

        % -----------------------------------------------------
        % MPC optimization
        % -----------------------------------------------------

        objective = @(u) mpcObjective( ...
            u, ...
            x_current, ...
            horizon, ...
            dt, ...
            Z, ...
            theta_r, ...
            theta_s, ...
            theta_FC, ...
            theta_WP, ...
            kp12, ...
            kp23, ...
            kp3d, ...
            Kinf, ...
            ET_potential(k:min(k+horizon-1,N)), ...
            ET_fraction, ...
            target, ...
            target_lower, ...
            target_upper, ...
            w_tracking, ...
            w_irrigation, ...
            w_drainage, ...
            w_lower, ...
            w_upper, ...
            w_terminal);

        try

            [u_opt,~,exitflag] = fmincon( ...
                objective, ...
                u0, ...
                [],[],[],[], ...
                lb,ub, ...
                [], ...
                options);

            if exitflag <= 0 || isempty(u_opt)
                u_opt = u0;
            end

        catch

            u_opt = u0;

        end

        % Apply first action only
        u_current = u_opt(1);

        irrigation(k) = u_current;

        u_previous = u_current;

        %% ----------------------------------------------------
        % Apply exact V3 plant dynamics
        % -----------------------------------------------------

        I = irrigation(k) / 1000;
        P = rainfall(k) / 1000;

        water_input = I + P;

        % -----------------------------------------------------
        % Infiltration
        % -----------------------------------------------------

        current_theta1 = S_current(1) / Z(1);

        remaining_capacity = S_max(1) - S_current(1);

        saturation_factor = ...
            (theta_s - current_theta1) / ...
            (theta_s - theta_FC);

        saturation_factor = min(max(saturation_factor,0),1);

        infiltration_capacity = Kinf * saturation_factor;

        potential_infiltration = ...
            min(water_input,infiltration_capacity);

        actual_infiltration = ...
            min(potential_infiltration, ...
            remaining_capacity/dt);

        actual_infiltration = max(actual_infiltration,0);

        runoff = max(0, ...
            water_input - actual_infiltration);

        S_current(1) = ...
            S_current(1) + actual_infiltration*dt;

        infiltration(k) = actual_infiltration;
        runoff_flux(k) = runoff;

        %% ----------------------------------------------------
        % Soil moisture stress
        % -----------------------------------------------------

        theta_current = S_current ./ Z;

        stress_current = ...
            (theta_current - theta_WP) ./ ...
            (theta_FC - theta_WP);

        stress_current = ...
            min(max(stress_current,0),1);

        stress(k,:) = stress_current';

        %% ----------------------------------------------------
        % Actual ET
        % -----------------------------------------------------

        ET_demand = ...
            (ET_potential(k)/1000) .* ...
            ET_fraction .* ...
            stress_current;

        for i = 1:3

            available_water = ...
                max(0,S_current(i)-S_min(i));

            ET_remove = ...
                min(ET_demand(i)*dt, ...
                available_water);

            S_current(i) = ...
                S_current(i) - ET_remove;

            ET_actual(k,i) = ET_remove/dt;

        end

        %% ----------------------------------------------------
        % Layer 1 -> Layer 2
        % -----------------------------------------------------

        excess1 = ...
            max(0,S_current(1)-S_FC(1));

        potential_q12 = kp12 * excess1;

        max_transfer12 = ...
            S_current(1)-S_min(1);

        max_receive12 = ...
            S_max(2)-S_current(2);

        transfer12 = ...
            min(potential_q12*dt,max_transfer12);

        transfer12 = ...
            min(transfer12,max_receive12);

        transfer12 = max(transfer12,0);

        S_current(1) = ...
            S_current(1)-transfer12;

        S_current(2) = ...
            S_current(2)+transfer12;

        q12(k) = transfer12/dt;

        %% ----------------------------------------------------
        % Layer 2 -> Layer 3
        % -----------------------------------------------------

        excess2 = ...
            max(0,S_current(2)-S_FC(2));

        potential_q23 = kp23 * excess2;

        max_transfer23 = ...
            S_current(2)-S_min(2);

        max_receive23 = ...
            S_max(3)-S_current(3);

        transfer23 = ...
            min(potential_q23*dt,max_transfer23);

        transfer23 = ...
            min(transfer23,max_receive23);

        transfer23 = max(transfer23,0);

        S_current(2) = ...
            S_current(2)-transfer23;

        S_current(3) = ...
            S_current(3)+transfer23;

        q23(k) = transfer23/dt;

        %% ----------------------------------------------------
        % Deep drainage
        % -----------------------------------------------------

        excess3 = ...
            max(0,S_current(3)-S_FC(3));

        potential_q3d = kp3d * excess3;

        max_drainage = ...
            S_current(3)-S_min(3);

        drainage = ...
            min(potential_q3d*dt,max_drainage);

        drainage = max(drainage,0);

        S_current(3) = ...
            S_current(3)-drainage;

        q3d(k) = drainage/dt;

        %% ----------------------------------------------------
        % Final physical bounds
        % -----------------------------------------------------

        S_current = ...
            min(max(S_current,S_min),S_max);

        %% ----------------------------------------------------
        % Store state
        % -----------------------------------------------------

        theta(k+1,:) = (S_current ./ Z)';

        theta_root(k+1) = ...
            sum(S_current) / root_depth;

        storage(k+1) = sum(S_current);

    end

    %% ========================================================
    % FINAL STRESS
    % ========================================================

    for k = 1:N

        stress(k,:) = ...
            (theta(k,:) - theta_WP') ./ ...
            (theta_FC - theta_WP);

        stress(k,:) = ...
            min(max(stress(k,:),0),1);

    end

    %% ========================================================
    % METRICS
    % ========================================================

    total_irrigation = sum(irrigation)*dt;

    actual_ET_total = ...
        sum(ET_actual(:))*dt;

    deep_drainage = ...
        sum(q3d)*dt;

    total_runoff = ...
        sum(runoff_flux)*dt;

    total_infiltration = ...
        sum(infiltration)*dt;

    final_storage = storage(end);

    root_RMSE = sqrt( ...
        mean((theta_root-target).^2));

    stress_mean = mean(stress,2);

   time_under_stress = ...
    sum(stress_mean(1:end-1) < 1) * dt;

time_above_band = ...
    sum(theta_root(1:end-1) > target_upper) * dt;

time_inside_target = ...
    sum(theta_root(1:end-1) >= target_lower & ...
        theta_root(1:end-1) <= target_upper) * dt;
    mean_theta = mean(theta(:));

    min_theta = min(theta(:));

    max_theta = max(theta(:));

    mean_stress = mean(stress(:));

    %% ========================================================
    % WATER BALANCE
    % ========================================================

    initial_storage_m = initial_storage;

    cumulative_infiltration = ...
        cumsum(infiltration)*dt;

    cumulative_runoff = ...
        cumsum(runoff_flux)*dt;

    cumulative_ET = ...
        cumsum(sum(ET_actual,2))*dt;

    cumulative_drainage = ...
        cumsum(q3d)*dt;

    storage_from_balance = ...
        initial_storage_m + ...
        cumulative_infiltration - ...
        cumulative_runoff - ...
        cumulative_ET - ...
        cumulative_drainage;

    balance_error_series = ...
        storage - storage_from_balance;

    water_balance_error = ...
        balance_error_series(end);

    max_interval_error = ...
        max(abs(diff(storage) - ...
        (infiltration(1:end-1)*dt - ...
        runoff_flux(1:end-1)*dt - ...
        sum(ET_actual(1:end-1,:),2)*dt - ...
        q3d(1:end-1)*dt)));

    %% ========================================================
    % VALIDATION
    % ========================================================

    theta_ok = ...
        all(theta(:) >= theta_r - 1e-10) && ...
        all(theta(:) <= theta_s + 1e-10);

    storage_ok = ...
        all(storage >= sum(S_min) - 1e-10) && ...
        all(storage <= sum(S_max) + 1e-10);

    flux_ok = ...
        all(irrigation >= -1e-10) && ...
        all(infiltration >= -1e-10) && ...
        all(runoff_flux >= -1e-10) && ...
        all(q12 >= -1e-10) && ...
        all(q23 >= -1e-10) && ...
        all(q3d >= -1e-10) && ...
        all(ET_actual(:) >= -1e-10);

    irrigation_ok = ...
        all(irrigation <= u_max + 1e-10);

    balance_ok = ...
        abs(water_balance_error) < 1e-9 && ...
        max_interval_error < 1e-9;

    overall_ok = ...
        theta_ok && ...
        storage_ok && ...
        flux_ok && ...
        irrigation_ok && ...
        balance_ok;

    %% ========================================================
    % STORE RESULTS
    % ========================================================

    results.total_irrigation(s) = total_irrigation;
    results.actual_ET(s) = actual_ET_total*1000;
    results.deep_drainage(s) = deep_drainage*1000;
    results.runoff(s) = total_runoff*1000;
    results.total_infiltration(s) = total_infiltration*1000;

    results.initial_storage(s) = initial_storage*1000;
    results.final_storage(s) = final_storage*1000;

    results.root_RMSE(s) = root_RMSE;

    results.time_under_stress(s) = time_under_stress;
    results.time_above_band(s) = time_above_band;
    results.time_inside_target(s) = time_inside_target;

    results.mean_theta(s) = mean_theta;
    results.min_theta(s) = min_theta;
    results.max_theta(s) = max_theta;
    results.mean_stress(s) = mean_stress;

    results.water_balance_error(s) = ...
        water_balance_error*1000;

    results.max_interval_water_balance_error(s) = ...
        max_interval_error*1000;

    results.validation_theta(s) = theta_ok;
    results.validation_storage(s) = storage_ok;
    results.validation_flux(s) = flux_ok;
    results.validation_irrigation(s) = irrigation_ok;
    results.validation_balance(s) = balance_ok;
    results.validation_overall(s) = overall_ok;

    results.irrigation{s} = irrigation;
    results.theta{s} = theta;
    results.theta_root{s} = theta_root;
    results.stress{s} = stress;
    results.ET_actual{s} = sum(ET_actual,2);
    results.q3d{s} = q3d;
    results.runoff_flux{s} = runoff_flux;
    results.infiltration{s} = infiltration;
    results.storage{s} = storage;

    %% ========================================================
    % PRINT RESULTS
    % ========================================================

    fprintf('\nMPC PERFORMANCE RESULTS\n');
    fprintf('Total irrigation       = %.6f mm\n', ...
    total_irrigation);
    fprintf('Actual ET              = %.6f mm\n', ...
        actual_ET_total*1000);
    fprintf('Deep drainage          = %.6f mm\n', ...
        deep_drainage*1000);
    fprintf('Runoff                 = %.6f mm\n', ...
        total_runoff*1000);
    fprintf('Total infiltration     = %.6f mm\n', ...
        total_infiltration*1000);
    fprintf('Final storage          = %.6f mm\n', ...
        final_storage*1000);
    fprintf('Root-zone RMSE         = %.6f\n', ...
        root_RMSE);
    fprintf('Time under stress      = %.2f days\n', ...
        time_under_stress);
    fprintf('Time above target band = %.2f days\n', ...
        time_above_band);
    fprintf('Time inside target     = %.2f days\n', ...
        time_inside_target);
    fprintf('Mean theta             = %.6f\n', ...
        mean_theta);
    fprintf('Min theta              = %.6f\n', ...
        min_theta);
    fprintf('Max theta              = %.6f\n', ...
        max_theta);
    fprintf('Mean stress            = %.6f\n', ...
        mean_stress);
    fprintf('Water balance error    = %.6e mm\n', ...
        water_balance_error*1000);
    fprintf('Max interval WB error  = %.6e mm\n', ...
        max_interval_error*1000);

    fprintf('\nVALIDATION\n');
    fprintf('Theta       = %d\n', theta_ok);
    fprintf('Storage     = %d\n', storage_ok);
    fprintf('Flux        = %d\n', flux_ok);
    fprintf('Irrigation  = %d\n', irrigation_ok);
    fprintf('Balance     = %d\n', balance_ok);
    fprintf('Overall     = %d\n', overall_ok);

end

%% ============================================================
% 6. OVERALL VALIDATION
% =============================================================

overall_validation = all(results.validation_overall);

fprintf('\n============================================================\n');
fprintf(' OVERALL MPC VALIDATION: ');

if overall_validation
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('============================================================\n\n');

%% ============================================================
% 7. SUMMARY TABLE
% =============================================================

summary_table = table( ...
    scenario_names', ...
    results.total_irrigation, ...
    results.actual_ET, ...
    results.deep_drainage, ...
    results.runoff, ...
    results.final_storage, ...
    results.root_RMSE, ...
    results.time_under_stress, ...
    results.time_inside_target, ...
    results.mean_theta, ...
    results.mean_stress, ...
    results.water_balance_error, ...
    results.validation_overall, ...
    'VariableNames', { ...
    'Scenario', ...
    'Irrigation_mm', ...
    'ET_mm', ...
    'Drainage_mm', ...
    'Runoff_mm', ...
    'FinalStorage_mm', ...
    'RootRMSE', ...
    'StressTime_days', ...
    'TargetTime_days', ...
    'MeanTheta', ...
    'MeanStress', ...
    'WaterBalanceError_mm', ...
    'ValidationPASS'});

disp(summary_table);

%% ============================================================
% 8. SAVE RESULTS
% ============================================================

results.summary_table = summary_table;
results.overall_validation = overall_validation;

save('V3_05_MPC_UncertaintyEvaluation_Results.mat', ...
    'results', ...
    'summary_table');

fprintf('\nResults saved:\n');
fprintf('V3_05_MPC_UncertaintyEvaluation_Results.mat\n');

%% ============================================================
% 9. FIGURE 1 - ROOT-ZONE MOISTURE
% ============================================================

figure('Color','w','Position',[100 100 1100 650]);
hold on;

for s = 1:nScenarios
    plot(time,results.theta_root{s}, ...
        'LineWidth',1.4);
end

yline(target,'--','Target');
yline(target_lower,':','Lower bound');
yline(target_upper,':','Upper bound');

xlabel('Time (days)');
ylabel('Root-zone volumetric water content');
title('MPC Root-Zone Moisture Under Parameter Uncertainty');

legend(scenario_names,'Location','best');
grid on;
box on;

saveas(gcf,'36_V3_MPC_Uncertainty_RootZoneMoisture.png');

%% ============================================================
% 10. FIGURE 2 - IRRIGATION
% ============================================================

figure('Color','w','Position',[100 100 1100 650]);
hold on;

for s = 1:nScenarios
    plot(time,results.irrigation{s}, ...
        'LineWidth',1.4);
end

xlabel('Time (days)');
ylabel('Irrigation rate (mm/day)');
title('MPC Irrigation Actions Under Parameter Uncertainty');

legend(scenario_names,'Location','best');
grid on;
box on;

saveas(gcf,'37_V3_MPC_Uncertainty_Irrigation.png');

%% ============================================================
% 11. FIGURE 3 - PERFORMANCE SUMMARY
% ============================================================

figure('Color','w','Position',[100 100 1100 650]);

bar_data = [ ...
    results.total_irrigation, ...
    results.deep_drainage, ...
    results.root_RMSE*1000, ...
    results.time_under_stress];

bar(bar_data);

xlabel('Scenario');
ylabel('Metric value');
title('MPC Performance Across Uncertainty Scenarios');

set(gca,'XTick',1:nScenarios);
set(gca,'XTickLabel',scenario_names);

legend( ...
    'Irrigation (mm)', ...
    'Drainage (mm)', ...
    'RMSE x 1000', ...
    'Stress time (days)', ...
    'Location','best');

grid on;
box on;

saveas(gcf,'38_V3_MPC_Uncertainty_PerformanceSummary.png');

%% ============================================================
% 12. FIGURE 4 - FINAL STORAGE
% ============================================================

figure('Color','w','Position',[100 100 1000 600]);

bar(results.final_storage);

xlabel('Scenario');
ylabel('Final storage (mm)');
title('MPC Final Soil-Water Storage');

set(gca,'XTick',1:nScenarios);
set(gca,'XTickLabel',scenario_names);

grid on;
box on;

saveas(gcf,'39_V3_MPC_Uncertainty_FinalStorage.png');

%% ============================================================
% 13. FIGURE 5 - TARGET BAND TIME
% ============================================================

figure('Color','w','Position',[100 100 1000 600]);

bar([ ...
    results.time_inside_target, ...
    results.time_under_stress, ...
    results.time_above_band]);

xlabel('Scenario');
ylabel('Time (days)');
title('MPC Target-Band and Stress Performance');

set(gca,'XTick',1:nScenarios);
set(gca,'XTickLabel',scenario_names);

legend( ...
    'Inside target band', ...
    'Under stress', ...
    'Above target band', ...
    'Location','best');

grid on;
box on;

saveas(gcf,'40_V3_MPC_Uncertainty_TargetBand.png');

%% ============================================================
% 14. FINAL MESSAGE
% ============================================================

fprintf('\n============================================================\n');
fprintf(' MPC UNCERTAINTY EVALUATION COMPLETED\n');
fprintf('============================================================\n');

if overall_validation
    fprintf('All six scenarios passed physical validation.\n');
else
    fprintf('WARNING: At least one scenario failed validation.\n');
end

fprintf('\nGenerated files:\n');
fprintf('36_V3_MPC_Uncertainty_RootZoneMoisture.png\n');
fprintf('37_V3_MPC_Uncertainty_Irrigation.png\n');
fprintf('38_V3_MPC_Uncertainty_PerformanceSummary.png\n');
fprintf('39_V3_MPC_Uncertainty_FinalStorage.png\n');
fprintf('40_V3_MPC_Uncertainty_TargetBand.png\n');
fprintf('V3_05_MPC_UncertaintyEvaluation_Results.mat\n');

fprintf('\nNext step: compare Fixed vs MPC vs Robust PPO.\n');
fprintf('============================================================\n');


%% ========================================================================
% LOCAL FUNCTION 1: MPC OBJECTIVE
% ========================================================================

function J = mpcObjective( ...
    u, ...
    S0, ...
    horizon, ...
    dt, ...
    Z, ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf, ...
    ET_future, ...
    ET_fraction, ...
    target, ...
    target_lower, ...
    target_upper, ...
    w_tracking, ...
    w_irrigation, ...
    w_drainage, ...
    w_lower, ...
    w_upper, ...
    w_terminal)

    S = S0;

    J = 0;

    S_min = theta_r .* Z;
    S_max = theta_s .* Z;
    S_FC = theta_FC .* Z;
    S_WP = theta_WP .* Z;

    root_depth = sum(Z);

    for j = 1:horizon

        irrigation_m = u(j)/1000;

        %% ----------------------------------------------------
        % Infiltration
        % -----------------------------------------------------

        current_theta1 = S(1)/Z(1);

        remaining_capacity = ...
            S_max(1)-S(1);

        saturation_factor = ...
            (theta_s-current_theta1)/ ...
            (theta_s-theta_FC);

        saturation_factor = ...
            min(max(saturation_factor,0),1);

        infiltration_capacity = ...
            Kinf*saturation_factor;

        actual_infiltration = ...
            min(irrigation_m,infiltration_capacity);

        actual_infiltration = ...
            min(actual_infiltration, ...
            remaining_capacity/dt);

        actual_infiltration = ...
            max(actual_infiltration,0);

        runoff = max(0, ...
            irrigation_m-actual_infiltration);

        S(1) = S(1)+actual_infiltration*dt;

        %% ----------------------------------------------------
        % Stress
        % -----------------------------------------------------

        theta_current = S./Z;

        stress = ...
            (theta_current-theta_WP)/ ...
            (theta_FC-theta_WP);

        stress = min(max(stress,0),1);

        %% ----------------------------------------------------
        % ET
        % -----------------------------------------------------

        ET_demand = ...
            (ET_future(j)/1000).* ...
            ET_fraction.*stress;

        for i = 1:3

            available_water = ...
                max(0,S(i)-S_min(i));

            ET_remove = ...
                min(ET_demand(i)*dt, ...
                available_water);

            S(i) = S(i)-ET_remove;

        end

        %% ----------------------------------------------------
        % Layer 1 -> Layer 2
        % -----------------------------------------------------

        excess1 = ...
            max(0,S(1)-S_FC(1));

        potential_q12 = kp12*excess1;

        transfer12 = ...
            min(potential_q12*dt, ...
            S(1)-S_min(1));

        transfer12 = ...
            min(transfer12, ...
            S_max(2)-S(2));

        transfer12 = max(transfer12,0);

        S(1) = S(1)-transfer12;
        S(2) = S(2)+transfer12;

        %% ----------------------------------------------------
        % Layer 2 -> Layer 3
        % -----------------------------------------------------

        excess2 = ...
            max(0,S(2)-S_FC(2));

        potential_q23 = kp23*excess2;

        transfer23 = ...
            min(potential_q23*dt, ...
            S(2)-S_min(2));

        transfer23 = ...
            min(transfer23, ...
            S_max(3)-S(3));

        transfer23 = max(transfer23,0);

        S(2) = S(2)-transfer23;
        S(3) = S(3)+transfer23;

        %% ----------------------------------------------------
        % Deep drainage
        % -----------------------------------------------------

        excess3 = ...
            max(0,S(3)-S_FC(3));

        potential_q3d = kp3d*excess3;

        drainage = ...
            min(potential_q3d*dt, ...
            S(3)-S_min(3));

        drainage = max(drainage,0);

        S(3) = S(3)-drainage;

        %% ----------------------------------------------------
        % Physical bounds
        % -----------------------------------------------------

        S = min(max(S,S_min),S_max);

        %% ----------------------------------------------------
        % Root-zone moisture
        % -----------------------------------------------------

        theta_root = sum(S)/root_depth;

        %% ----------------------------------------------------
        % Objective
        % -----------------------------------------------------

        tracking_error = ...
            theta_root-target;

        lower_violation = ...
            max(0,target_lower-theta_root);

        upper_violation = ...
            max(0,theta_root-target_upper);

        J = J + ...
            w_tracking*tracking_error^2 + ...
            w_irrigation*u(j) + ...
            w_drainage*drainage^2 + ...
            w_lower*lower_violation^2 + ...
            w_upper*upper_violation^2;

    end

    %% --------------------------------------------------------
    % Terminal penalty
    % ---------------------------------------------------------

    theta_terminal = sum(S)/root_depth;

    terminal_error = ...
        theta_terminal-target;

    terminal_lower = ...
        max(0,target_lower-theta_terminal);

    terminal_upper = ...
        max(0,theta_terminal-target_upper);

    J = J + ...
        w_terminal*terminal_error^2 + ...
        w_lower*terminal_lower^2 + ...
        w_upper*terminal_upper^2;

end