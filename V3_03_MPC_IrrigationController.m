%% V3_03_MPC_IrrigationController
% Revised nonlinear MPC controller for the validated V3 soil-water model
%
% Main objective:
%   - Track the desired root-zone moisture
%   - Avoid water stress
%   - Reduce irrigation water
%   - Limit deep drainage
%
% The V3 plant dynamics are preserved.
%
% Required:
%   Optimization Toolbox (fmincon)

clear;
clc;
close all;

fprintf('============================================================\n');
fprintf(' V3 MPC IRRIGATION CONTROLLER - FINAL REVISED VERSION\n');
fprintf('============================================================\n\n');

%% ============================================================
% 1. CHECK FMINCON
% ============================================================

if exist('fmincon','file') ~= 2
    error(['fmincon was not found. This script requires ', ...
           'Optimization Toolbox.']);
end

fprintf('fmincon detected successfully.\n');

%% ============================================================
% 2. LOAD VALIDATED V3 BASELINE
% ============================================================

baselineFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(baselineFile)
    error('Baseline file "%s" was not found.',baselineFile);
end

D = load(baselineFile);

if isfield(D,'results')
    base = D.results;
else
    base = D;
end

fprintf('Validated V3 baseline loaded successfully.\n');

%% ============================================================
% 3. MODEL PARAMETERS
% ============================================================

dt = 0.25;
T  = 120;

N = round(T/dt) + 1;

time = (0:N-1)' * dt;

theta_r  = 0.078;
theta_s  = 0.430;
theta_FC = 0.250;
theta_WP = 0.120;

Z = [0.10; 0.20; 0.30];

root_depth = sum(Z);

% Exact V3 initial state
theta0 = base.theta(1,:)';

S0 = theta0 .* Z;

%% ============================================================
% 4. CONTROL TARGET
% ============================================================

theta_target = 0.205;

theta_lower = 0.180;
theta_upper = 0.230;

u_min = 0;
u_max = 12;

%% ============================================================
% 5. ENVIRONMENT
% ============================================================

rainfall = zeros(N,1);

ET_potential = 4 * ones(N,1);

ET_fraction = [0.50; 0.30; 0.20];

%% ============================================================
% 6. SOIL FLOW PARAMETERS
% ============================================================

kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;

Kinf = 0.020;

%% ============================================================
% 7. MPC SETTINGS
% ============================================================

Np = 16;

% Main objective weights
w_tracking = 3000;
w_irrigation = 2.0;
w_drainage = 100;

% Band penalties
w_lower = 12000;
w_upper = 3000;

% Terminal tracking
w_terminal = 6000;

% Initial guess
u_previous = 3 * ones(Np,1);

fprintf('\n------------------------------------------------------------\n');
fprintf(' MPC SETTINGS\n');
fprintf('------------------------------------------------------------\n');

fprintf('Prediction horizon       = %d steps (%.2f days)\n', ...
    Np,Np*dt);

fprintf('Target root theta        = %.3f\n',theta_target);

fprintf('Target band              = [%.3f, %.3f]\n', ...
    theta_lower,theta_upper);

fprintf('Irrigation limits        = [%.1f, %.1f] mm/day\n', ...
    u_min,u_max);

fprintf('\nObjective weights:\n');
fprintf('w_tracking              = %.1f\n',w_tracking);
fprintf('w_irrigation            = %.1f\n',w_irrigation);
fprintf('w_drainage              = %.1f\n',w_drainage);
fprintf('w_lower                 = %.1f\n',w_lower);
fprintf('w_upper                 = %.1f\n',w_upper);
fprintf('w_terminal              = %.1f\n',w_terminal);

%% ============================================================
% 8. STORAGE LIMITS
% ============================================================

S_min = theta_r  .* Z;
S_max = theta_s  .* Z;
S_FC  = theta_FC .* Z;
S_WP  = theta_WP .* Z;

%% ============================================================
% 9. PREALLOCATE MPC VARIABLES
% ============================================================

theta_mpc = zeros(N,3);

S_mpc = zeros(N,3);

root_theta_mpc = zeros(N,1);

irrigation_mpc = zeros(N,1);

ET_actual_mpc = zeros(N,3);

ET_total_mpc = zeros(N,1);

q12_mpc = zeros(N,1);

q23_mpc = zeros(N,1);

q3d_mpc = zeros(N,1);

infiltration_mpc = zeros(N,1);

runoff_mpc = zeros(N,1);

soil_stress_mpc = zeros(N,3);

%% ============================================================
% 10. INITIAL CONDITION
% ============================================================

S_mpc(1,:) = S0';

theta_mpc(1,:) = theta0';

root_theta_mpc(1) = sum(S0) / root_depth;

%% ============================================================
% 11. MPC OPTIONS
% ============================================================

options = optimoptions('fmincon', ...
    'Algorithm','sqp', ...
    'Display','off', ...
    'MaxIterations',60, ...
    'OptimalityTolerance',1e-5, ...
    'StepTolerance',1e-5);

%% ============================================================
% 12. CLOSED-LOOP MPC
% ============================================================

fprintf('\n------------------------------------------------------------\n');
fprintf(' STARTING CLOSED-LOOP MPC SIMULATION\n');
fprintf('------------------------------------------------------------\n');

for k = 1:N-1

    x_current = S_mpc(k,:)';

    ET_now = ET_potential(k);

    P_now = rainfall(k);

    %% --------------------------------------------------------
    % MPC objective
    %% --------------------------------------------------------

    objective = @(u) mpcObjective( ...
        u, ...
        x_current, ...
        ET_now, ...
        P_now, ...
        dt, ...
        Np, ...
        theta_target, ...
        theta_lower, ...
        theta_upper, ...
        w_tracking, ...
        w_irrigation, ...
        w_drainage, ...
        w_lower, ...
        w_upper, ...
        w_terminal, ...
        theta_r, ...
        theta_s, ...
        theta_FC, ...
        theta_WP, ...
        Z, ...
        ET_fraction, ...
        kp12, ...
        kp23, ...
        kp3d, ...
        Kinf);

    %% --------------------------------------------------------
    % Constraints
    %% --------------------------------------------------------

    lb = u_min * ones(Np,1);

    ub = u_max * ones(Np,1);

    %% --------------------------------------------------------
    % Solve optimization
    %% --------------------------------------------------------

    try

        [u_opt,~,exitflag] = fmincon( ...
            objective, ...
            u_previous, ...
            [],[],[],[], ...
            lb, ...
            ub, ...
            [], ...
            options);

        if exitflag <= 0

            u_opt = u_previous;

        end

    catch

        u_opt = u_previous;

    end

    %% --------------------------------------------------------
    % Apply only first action
    %% --------------------------------------------------------

    u_apply = u_opt(1);

    u_apply = min(max(u_apply,u_min),u_max);

    irrigation_mpc(k) = u_apply;

    %% --------------------------------------------------------
    % Propagate actual plant
    %% --------------------------------------------------------

    [S_next,theta_next,ET_layer,q12,q23,q3d, ...
        infiltration,runoff,stress] = ...
        soilStepV3( ...
        x_current, ...
        u_apply, ...
        P_now, ...
        ET_now, ...
        dt, ...
        theta_r, ...
        theta_s, ...
        theta_FC, ...
        theta_WP, ...
        Z, ...
        ET_fraction, ...
        kp12, ...
        kp23, ...
        kp3d, ...
        Kinf);

    %% --------------------------------------------------------
    % Store state
    %% --------------------------------------------------------

    S_mpc(k+1,:) = S_next';

    theta_mpc(k+1,:) = theta_next';

    root_theta_mpc(k+1) = ...
        sum(S_next) / root_depth;

    %% --------------------------------------------------------
    % Store fluxes
    %% --------------------------------------------------------

    ET_actual_mpc(k,:) = ET_layer';

    ET_total_mpc(k) = sum(ET_layer);

    q12_mpc(k) = q12;

    q23_mpc(k) = q23;

    q3d_mpc(k) = q3d;

    infiltration_mpc(k) = infiltration;

    runoff_mpc(k) = runoff;

    soil_stress_mpc(k,:) = stress';

    %% --------------------------------------------------------
    % Warm start next optimization
    %% --------------------------------------------------------

    u_previous = [u_opt(2:end);u_opt(end)];

    %% --------------------------------------------------------
    % Progress display
    %% --------------------------------------------------------

    if k == 1 || mod(k,40) == 0 || k == N-1

        fprintf( ...
            'Day %6.2f | Irrigation = %7.3f mm/day | Root theta = %.4f\n', ...
            time(k+1), ...
            u_apply, ...
            root_theta_mpc(k+1));

    end

end

%% ============================================================
% 13. FINAL SAMPLE
% ============================================================
% No plant propagation occurs at k = N.
% Therefore the last flux sample must be zero.
% This prevents artificial extra water from entering totals.

irrigation_mpc(N) = 0;

ET_actual_mpc(N,:) = 0;

ET_total_mpc(N) = 0;

q12_mpc(N) = 0;

q23_mpc(N) = 0;

q3d_mpc(N) = 0;

infiltration_mpc(N) = 0;

runoff_mpc(N) = 0;

soil_stress_mpc(N,:) = ...
    soil_stress_mpc(N-1,:);

%% ============================================================
% 14. MPC PERFORMANCE METRICS
% ============================================================

total_irrigation_mpc = ...
    sum(irrigation_mpc) * dt;

total_ET_mpc = ...
    sum(ET_total_mpc) * dt * 1000;

total_drainage_mpc = ...
    sum(q3d_mpc) * dt * 1000;

total_runoff_mpc = ...
    sum(runoff_mpc) * dt * 1000;

total_infiltration_mpc = ...
    sum(infiltration_mpc) * dt * 1000;

final_storage_mpc = ...
    sum(S_mpc(end,:)) * 1000;

%% Root-zone performance

root_error = ...
    root_theta_mpc - theta_target;

root_RMSE = ...
    sqrt(mean(root_error.^2));

time_under_stress = ...
    sum(root_theta_mpc < theta_lower) * dt;

time_above_band = ...
    sum(root_theta_mpc > theta_upper) * dt;

time_inside_band = ...
    T - time_under_stress - time_above_band;

mean_theta_mpc = ...
    mean(mean(theta_mpc,2));

min_theta_mpc = ...
    min(theta_mpc(:));

max_theta_mpc = ...
    max(theta_mpc(:));

mean_stress_mpc = ...
    mean(soil_stress_mpc(:));

%% Water-use efficiency

if total_irrigation_mpc > 0

    WUE_mpc = ...
        total_ET_mpc / total_irrigation_mpc;

else

    WUE_mpc = NaN;

end

%% ============================================================
% 15. WATER BALANCE
% ============================================================

initial_storage_m = ...
    sum(S0);

final_storage_m = ...
    sum(S_mpc(end,:));

total_input_m = ...
    total_irrigation_mpc / 1000;

total_loss_m = ...
    total_ET_mpc / 1000 + ...
    total_drainage_mpc / 1000 + ...
    total_runoff_mpc / 1000;

water_balance_error = ...
    initial_storage_m + ...
    total_input_m - ...
    final_storage_m - ...
    total_loss_m;

%% ============================================================
% 16. PRINT MPC RESULTS
% ============================================================

fprintf('\n============================================================\n');
fprintf(' MPC PERFORMANCE RESULTS\n');
fprintf('============================================================\n');

fprintf('Total irrigation       = %.6f mm\n', ...
    total_irrigation_mpc);

fprintf('Actual ET              = %.6f mm\n', ...
    total_ET_mpc);

fprintf('Deep drainage          = %.6f mm\n', ...
    total_drainage_mpc);

fprintf('Runoff                 = %.6f mm\n', ...
    total_runoff_mpc);

fprintf('Total infiltration     = %.6f mm\n', ...
    total_infiltration_mpc);

fprintf('Final storage          = %.6f mm\n', ...
    final_storage_mpc);

fprintf('Root-zone RMSE         = %.6f\n', ...
    root_RMSE);

fprintf('Time under stress      = %.2f days\n', ...
    time_under_stress);

fprintf('Time above target band = %.2f days\n', ...
    time_above_band);

fprintf('Time inside target     = %.2f days\n', ...
    time_inside_band);

fprintf('Mean theta             = %.6f\n', ...
    mean_theta_mpc);

fprintf('Min theta              = %.6f\n', ...
    min_theta_mpc);

fprintf('Max theta              = %.6f\n', ...
    max_theta_mpc);

fprintf('Mean stress            = %.6f\n', ...
    mean_stress_mpc);

fprintf('Water-use efficiency   = %.6f\n', ...
    WUE_mpc);

fprintf('Water balance error    = %.6e m\n', ...
    water_balance_error);

%% ============================================================
% 17. FIXED-IRRIGATION BASELINE
% ============================================================

fprintf('\n------------------------------------------------------------\n');
fprintf(' RUNNING FIXED-IRRIGATION BASELINE\n');
fprintf('------------------------------------------------------------\n');

theta_fixed = base.theta;

S_fixed = base.storage;

root_theta_fixed = ...
    (theta_fixed(:,1)*Z(1) + ...
     theta_fixed(:,2)*Z(2) + ...
     theta_fixed(:,3)*Z(3)) / root_depth;

if isfield(base,'irrigation')

    irrigation_fixed = base.irrigation;

else

    irrigation_fixed = zeros(N,1);

    irrigation_fixed(time >= 20 & time < 60) = 8;

end

if isfield(base,'ET_actual')

    ET_fixed_layer = base.ET_actual;

else

    ET_fixed_layer = zeros(N,3);

end

ET_fixed_total = ...
    sum(ET_fixed_layer,2);

if isfield(base,'q3d')

    q3d_fixed = base.q3d;

else

    q3d_fixed = zeros(N,1);

end

if isfield(base,'runoff')

    runoff_fixed = base.runoff;

else

    runoff_fixed = zeros(N,1);

end

total_irrigation_fixed = ...
    sum(irrigation_fixed) * dt;

total_ET_fixed = ...
    sum(ET_fixed_total) * dt * 1000;

total_drainage_fixed = ...
    sum(q3d_fixed) * dt * 1000;

total_runoff_fixed = ...
    sum(runoff_fixed) * dt * 1000;

final_storage_fixed = ...
    sum(S_fixed(end,:)) * 1000;

root_error_fixed = ...
    root_theta_fixed - theta_target;

root_RMSE_fixed = ...
    sqrt(mean(root_error_fixed.^2));

time_stress_fixed = ...
    sum(root_theta_fixed < theta_lower) * dt;

%% ============================================================
% 18. COMPARISON
% ============================================================

irrigation_reduction = ...
    100 * (total_irrigation_fixed - total_irrigation_mpc) / ...
    max(total_irrigation_fixed,eps);

drainage_reduction = ...
    100 * (total_drainage_fixed - total_drainage_mpc) / ...
    max(total_drainage_fixed,eps);

RMSE_improvement = ...
    100 * (root_RMSE_fixed - root_RMSE) / ...
    max(root_RMSE_fixed,eps);

stress_improvement = ...
    100 * (time_stress_fixed - time_under_stress) / ...
    max(time_stress_fixed,eps);

fprintf('\n============================================================\n');
fprintf(' MPC VS FIXED-IRRIGATION BASELINE\n');
fprintf('============================================================\n');

fprintf('\n                         Fixed        MPC\n');
fprintf('------------------------------------------------------------\n');

fprintf('Irrigation (mm)       %10.3f  %12.3f\n', ...
    total_irrigation_fixed, ...
    total_irrigation_mpc);

fprintf('Actual ET (mm)        %10.3f  %12.3f\n', ...
    total_ET_fixed, ...
    total_ET_mpc);

fprintf('Drainage (mm)         %10.3f  %12.3f\n', ...
    total_drainage_fixed, ...
    total_drainage_mpc);

fprintf('Final storage (mm)    %10.3f  %12.3f\n', ...
    final_storage_fixed, ...
    final_storage_mpc);

fprintf('Root RMSE              %10.6f  %12.6f\n', ...
    root_RMSE_fixed, ...
    root_RMSE);

fprintf('Stress time (days)     %10.2f  %12.2f\n', ...
    time_stress_fixed, ...
    time_under_stress);

fprintf('\n------------------------------------------------------------\n');
fprintf(' RELATIVE PERFORMANCE\n');
fprintf('------------------------------------------------------------\n');

fprintf('Irrigation reduction = %8.2f %%\n', ...
    irrigation_reduction);

fprintf('Drainage reduction   = %8.2f %%\n', ...
    drainage_reduction);

fprintf('RMSE improvement     = %8.2f %%\n', ...
    RMSE_improvement);

fprintf('Stress-time change   = %8.2f %%\n', ...
    stress_improvement);

%% ============================================================
% 19. MPC VALIDATION
% ============================================================

fprintf('\n------------------------------------------------------------\n');
fprintf(' MPC VALIDATION\n');
fprintf('------------------------------------------------------------\n');

theta_lower_matrix = ...
    theta_r * ones(size(theta_mpc));

theta_upper_matrix = ...
    theta_s * ones(size(theta_mpc));

theta_bounds_pass = ...
    all(theta_mpc(:) >= theta_r - 1e-12) && ...
    all(theta_mpc(:) <= theta_s + 1e-12);

storage_lower_matrix = ...
    ones(N,1) * S_min';

storage_upper_matrix = ...
    ones(N,1) * S_max';

storage_bounds_pass = ...
    all(S_mpc(:) >= storage_lower_matrix(:) - 1e-12) && ...
    all(S_mpc(:) <= storage_upper_matrix(:) + 1e-12);

flux_pass = ...
    all(irrigation_mpc >= -1e-12) && ...
    all(infiltration_mpc >= -1e-12) && ...
    all(runoff_mpc >= -1e-12) && ...
    all(q12_mpc >= -1e-12) && ...
    all(q23_mpc >= -1e-12) && ...
    all(q3d_mpc >= -1e-12);

water_balance_pass = ...
    abs(water_balance_error) < 1e-9;

irrigation_constraint_pass = ...
    all(irrigation_mpc >= u_min - 1e-10) && ...
    all(irrigation_mpc <= u_max + 1e-10);

fprintf('Theta bounds          : %s\n', ...
    passFail(theta_bounds_pass));

fprintf('Storage bounds        : %s\n', ...
    passFail(storage_bounds_pass));

fprintf('Nonnegative fluxes    : %s\n', ...
    passFail(flux_pass));

fprintf('Water balance         : %s\n', ...
    passFail(water_balance_pass));

fprintf('Irrigation constraints: %s\n', ...
    passFail(irrigation_constraint_pass));

all_validation_pass = ...
    theta_bounds_pass && ...
    storage_bounds_pass && ...
    flux_pass && ...
    water_balance_pass && ...
    irrigation_constraint_pass;

%% ============================================================
% 20. FIGURE 13 - ROOT-ZONE MOISTURE
% ============================================================

figure;

plot(time,root_theta_mpc,'LineWidth',1.5);
hold on;

plot(time,theta_target*ones(size(time)), ...
    '--','LineWidth',1.2);

plot(time,theta_lower*ones(size(time)), ...
    ':','LineWidth',1.2);

plot(time,theta_upper*ones(size(time)), ...
    ':','LineWidth',1.2);

xlabel('Time (days)');

ylabel('Root-zone volumetric water content');

title('MPC Root-Zone Moisture Regulation');

legend( ...
    'MPC', ...
    'Target', ...
    'Lower bound', ...
    'Upper bound', ...
    'Location','best');

grid on;

saveas(gcf, ...
    '13_V3_MPC_RootZoneMoisture_Final.png');

%% ============================================================
% 21. FIGURE 14 - IRRIGATION
% ============================================================

figure;

stairs(time,irrigation_mpc,'LineWidth',1.4);

xlabel('Time (days)');

ylabel('Irrigation rate (mm/day)');

title('MPC Irrigation Command');

grid on;

saveas(gcf, ...
    '14_V3_MPC_Irrigation_Final.png');

%% ============================================================
% 22. FIGURE 15 - THREE SOIL LAYERS
% ============================================================

figure;

plot(time,theta_mpc(:,1),'LineWidth',1.3);
hold on;

plot(time,theta_mpc(:,2),'LineWidth',1.3);

plot(time,theta_mpc(:,3),'LineWidth',1.3);

yline(theta_FC,'--','Field Capacity');

yline(theta_WP,':','Wilting Point');

xlabel('Time (days)');

ylabel('Volumetric water content');

title('MPC Soil Moisture in Three Layers');

legend( ...
    'Layer 1', ...
    'Layer 2', ...
    'Layer 3', ...
    'Location','best');

grid on;

saveas(gcf, ...
    '15_V3_MPC_LayerMoisture_Final.png');

%% ============================================================
% 23. FIGURE 16 - ET AND DRAINAGE
% ============================================================

figure;

plot(time,ET_total_mpc*1000,'LineWidth',1.4);
hold on;

plot(time,q3d_mpc*1000,'LineWidth',1.4);

xlabel('Time (days)');

ylabel('Flux (mm/day)');

title('MPC Evapotranspiration and Deep Drainage');

legend( ...
    'Actual ET', ...
    'Deep drainage', ...
    'Location','best');

grid on;

saveas(gcf, ...
    '16_V3_MPC_ET_Drainage_Final.png');

%% ============================================================
% 24. FIGURE 17 - MPC VS FIXED
% ============================================================

figure;

plot(time,root_theta_fixed,'LineWidth',1.3);
hold on;

plot(time,root_theta_mpc,'LineWidth',1.5);

plot(time,theta_target*ones(size(time)), ...
    '--','LineWidth',1.1);

xlabel('Time (days)');

ylabel('Root-zone volumetric water content');

title('MPC vs Fixed Irrigation');

legend( ...
    'Fixed irrigation', ...
    'MPC', ...
    'Target', ...
    'Location','best');

grid on;

saveas(gcf, ...
    '17_V3_MPC_vs_Fixed_Moisture_Final.png');

%% ============================================================
% 25. FIGURE 18 - PERFORMANCE COMPARISON
% ============================================================

figure;

metrics = [ ...
    total_irrigation_fixed, total_irrigation_mpc;
    total_drainage_fixed, total_drainage_mpc;
    root_RMSE_fixed*1000, root_RMSE*1000;
    time_stress_fixed, time_under_stress];

bar(metrics);

xlabel('Performance metric');

ylabel('Value');

title('Fixed Irrigation vs MPC');

xticklabels({ ...
    'Irrigation (mm)', ...
    'Drainage (mm)', ...
    'RMSE x1000', ...
    'Stress time (days)'});

legend( ...
    'Fixed', ...
    'MPC', ...
    'Location','best');

grid on;

saveas(gcf, ...
    '18_V3_MPC_Performance_Final.png');

%% ============================================================
% 26. SAVE RESULTS
% ============================================================

MPCResults = struct();

MPCResults.time = time;

MPCResults.theta = theta_mpc;

MPCResults.storage = S_mpc;

MPCResults.root_theta = root_theta_mpc;

MPCResults.irrigation = irrigation_mpc;

MPCResults.ET_actual = ET_actual_mpc;

MPCResults.ET_total = ET_total_mpc;

MPCResults.q12 = q12_mpc;

MPCResults.q23 = q23_mpc;

MPCResults.q3d = q3d_mpc;

MPCResults.infiltration = infiltration_mpc;

MPCResults.runoff = runoff_mpc;

MPCResults.soil_stress = soil_stress_mpc;

%% Controller settings

MPCResults.settings.dt = dt;

MPCResults.settings.Np = Np;

MPCResults.settings.theta_target = theta_target;

MPCResults.settings.theta_lower = theta_lower;

MPCResults.settings.theta_upper = theta_upper;

MPCResults.settings.u_min = u_min;

MPCResults.settings.u_max = u_max;

MPCResults.settings.w_tracking = w_tracking;

MPCResults.settings.w_irrigation = w_irrigation;

MPCResults.settings.w_drainage = w_drainage;

MPCResults.settings.w_lower = w_lower;

MPCResults.settings.w_upper = w_upper;

MPCResults.settings.w_terminal = w_terminal;

%% MPC metrics

MPCResults.metrics.total_irrigation_mm = ...
    total_irrigation_mpc;

MPCResults.metrics.actual_ET_mm = ...
    total_ET_mpc;

MPCResults.metrics.deep_drainage_mm = ...
    total_drainage_mpc;

MPCResults.metrics.runoff_mm = ...
    total_runoff_mpc;

MPCResults.metrics.total_infiltration_mm = ...
    total_infiltration_mpc;

MPCResults.metrics.final_storage_mm = ...
    final_storage_mpc;

MPCResults.metrics.root_RMSE = ...
    root_RMSE;

MPCResults.metrics.time_under_stress_days = ...
    time_under_stress;

MPCResults.metrics.time_above_band_days = ...
    time_above_band;

MPCResults.metrics.time_inside_band_days = ...
    time_inside_band;

MPCResults.metrics.mean_theta = ...
    mean_theta_mpc;

MPCResults.metrics.min_theta = ...
    min_theta_mpc;

MPCResults.metrics.max_theta = ...
    max_theta_mpc;

MPCResults.metrics.mean_stress = ...
    mean_stress_mpc;

MPCResults.metrics.WUE = ...
    WUE_mpc;

MPCResults.metrics.water_balance_error_m = ...
    water_balance_error;

%% Fixed baseline metrics

MPCResults.fixed_baseline.total_irrigation_mm = ...
    total_irrigation_fixed;

MPCResults.fixed_baseline.actual_ET_mm = ...
    total_ET_fixed;

MPCResults.fixed_baseline.deep_drainage_mm = ...
    total_drainage_fixed;

MPCResults.fixed_baseline.runoff_mm = ...
    total_runoff_fixed;

MPCResults.fixed_baseline.final_storage_mm = ...
    final_storage_fixed;

MPCResults.fixed_baseline.root_RMSE = ...
    root_RMSE_fixed;

MPCResults.fixed_baseline.time_under_stress_days = ...
    time_stress_fixed;

%% Comparison

MPCResults.comparison.irrigation_reduction_percent = ...
    irrigation_reduction;

MPCResults.comparison.drainage_reduction_percent = ...
    drainage_reduction;

MPCResults.comparison.RMSE_improvement_percent = ...
    RMSE_improvement;

MPCResults.comparison.stress_time_improvement_percent = ...
    stress_improvement;

%% Validation

MPCResults.validation.theta_bounds = ...
    theta_bounds_pass;

MPCResults.validation.storage_bounds = ...
    storage_bounds_pass;

MPCResults.validation.nonnegative_fluxes = ...
    flux_pass;

MPCResults.validation.water_balance = ...
    water_balance_pass;

MPCResults.validation.irrigation_constraints = ...
    irrigation_constraint_pass;

MPCResults.validation.all_pass = ...
    all_validation_pass;

save( ...
    'V3_03_MPC_IrrigationController_Results.mat', ...
    'MPCResults');

%% ============================================================
% 27. FINAL MESSAGE
% ============================================================

fprintf('\nResults saved:\n');

fprintf('V3_03_MPC_IrrigationController_Results.mat\n');

fprintf('13_V3_MPC_RootZoneMoisture_Final.png\n');

fprintf('14_V3_MPC_Irrigation_Final.png\n');

fprintf('15_V3_MPC_LayerMoisture_Final.png\n');

fprintf('16_V3_MPC_ET_Drainage_Final.png\n');

fprintf('17_V3_MPC_vs_Fixed_Moisture_Final.png\n');

fprintf('18_V3_MPC_Performance_Final.png\n');

fprintf('\n============================================================\n');

if all_validation_pass

    fprintf(' ALL MPC PHYSICAL VALIDATION CHECKS: PASS\n');

else

    fprintf(' WARNING: ONE OR MORE MPC VALIDATION CHECKS FAILED\n');

end

fprintf('============================================================\n');


%% ============================================================
% LOCAL FUNCTION 1: MPC OBJECTIVE
% ============================================================

function J = mpcObjective( ...
    u, ...
    x0, ...
    ET_now, ...
    P_now, ...
    dt, ...
    Np, ...
    theta_target, ...
    theta_lower, ...
    theta_upper, ...
    w_tracking, ...
    w_irrigation, ...
    w_drainage, ...
    w_lower, ...
    w_upper, ...
    w_terminal, ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    Z, ...
    ET_fraction, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf)

x = x0;

J = 0;

for j = 1:Np

    u_j = u(j);

    [x_next,~,~,~,~,q3d,~,~,~] = ...
        soilStepV3( ...
        x, ...
        u_j, ...
        P_now, ...
        ET_now, ...
        dt, ...
        theta_r, ...
        theta_s, ...
        theta_FC, ...
        theta_WP, ...
        Z, ...
        ET_fraction, ...
        kp12, ...
        kp23, ...
        kp3d, ...
        Kinf);

    %% Root-zone moisture

    theta_root = ...
        sum(x_next) / sum(Z);

    %% Tracking error

    tracking_error = ...
        theta_root - theta_target;

    %% Band violations

    lower_violation = ...
        max(0,theta_lower-theta_root);

    upper_violation = ...
        max(0,theta_root-theta_upper);

    %% Objective

    J = J ...
        + w_tracking * tracking_error^2 ...
        + w_irrigation * u_j ...
        + w_drainage * (q3d*1000)^2 ...
        + w_lower * lower_violation^2 ...
        + w_upper * upper_violation^2;

    x = x_next;

end

%% Terminal penalty

theta_terminal = ...
    sum(x) / sum(Z);

terminal_error = ...
    theta_terminal - theta_target;

terminal_lower_violation = ...
    max(0,theta_lower-theta_terminal);

terminal_upper_violation = ...
    max(0,theta_terminal-theta_upper);

J = J ...
    + w_terminal * terminal_error^2 ...
    + w_lower * terminal_lower_violation^2 ...
    + w_upper * terminal_upper_violation^2;

end


%% ============================================================
% LOCAL FUNCTION 2: V3 SOIL DYNAMICS
% ============================================================

function [S_next,theta_next,ET_layer,q12,q23,q3d, ...
    infiltration,runoff,stress] = ...
    soilStepV3( ...
    S_current, ...
    u_mm_day, ...
    P_mm_day, ...
    ET_mm_day, ...
    dt, ...
    theta_r, ...
    theta_s, ...
    theta_FC, ...
    theta_WP, ...
    Z, ...
    ET_fraction, ...
    kp12, ...
    kp23, ...
    kp3d, ...
    Kinf)

%% Storage limits

S_min = theta_r .* Z;

S_max = theta_s .* Z;

S_FC = theta_FC .* Z;

S_WP = theta_WP .* Z;

%% External input

I = u_mm_day / 1000;

P = P_mm_day / 1000;

water_input = I + P;

%% ============================================================
% Infiltration
% ============================================================

current_theta1 = ...
    S_current(1) / Z(1);

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

runoff = ...
    max(0,water_input-actual_infiltration);

S_current(1) = ...
    S_current(1) + ...
    actual_infiltration*dt;

infiltration = ...
    actual_infiltration;

%% ============================================================
% Soil water stress
% ============================================================

theta_current = ...
    S_current ./ Z;

stress = ...
    (theta_current-theta_WP) ./ ...
    (theta_FC-theta_WP);

stress = ...
    min(max(stress,0),1);

%% ============================================================
% Evapotranspiration
% ============================================================

ET_demand = ...
    (ET_mm_day/1000) .* ...
    ET_fraction .* ...
    stress;

ET_layer = zeros(3,1);

for i = 1:3

    available_water = ...
        max(0,S_current(i)-S_min(i));

    ET_remove = ...
        min(ET_demand(i)*dt,available_water);

    S_current(i) = ...
        S_current(i)-ET_remove;

    ET_layer(i) = ...
        ET_remove/dt;

end

%% ============================================================
% Layer 1 -> Layer 2
% ============================================================

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
    min(transfer12,max_receive12);

transfer12 = ...
    max(transfer12,0);

S_current(1) = ...
    S_current(1)-transfer12;

S_current(2) = ...
    S_current(2)+transfer12;

q12 = ...
    transfer12/dt;

%% ============================================================
% Layer 2 -> Layer 3
% ============================================================

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
    min(transfer23,max_receive23);

transfer23 = ...
    max(transfer23,0);

S_current(2) = ...
    S_current(2)-transfer23;

S_current(3) = ...
    S_current(3)+transfer23;

q23 = ...
    transfer23/dt;

%% ============================================================
% Deep drainage
% ============================================================

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

q3d = ...
    drainage/dt;

%% ============================================================
% Physical bounds
% ============================================================

S_current = ...
    min(max(S_current,S_min),S_max);

%% ============================================================
% Outputs
% ============================================================

S_next = S_current;

theta_next = ...
    S_next ./ Z;

end


%% ============================================================
% LOCAL FUNCTION 3: PASS/FAIL
% ============================================================

function txt = passFail(flag)

if flag

    txt = 'PASS';

else

    txt = 'FAIL';

end

end