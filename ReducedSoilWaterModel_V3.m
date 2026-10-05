%% ============================================================
% 01_ReducedSoilWaterModel_V3
% AI-Driven Smart Irrigation
%
% Three-Layer Control-Oriented Soil Water Model
%
% Version: V3.0
%
% Main design principle:
%   Model soil water as physical storage:
%
%       S_i = theta_i * Z_i
%
%   instead of directly integrating theta dynamics.
%
% This version emphasizes:
%   1. Mass conservation
%   2. Physical storage bounds
%   3. Stable water transfer
%   4. Explicit infiltration
%   5. Explicit drainage
%   6. Soil-water stress
%
% This is still a reduced-order control model.
% The high-fidelity Richards model will be developed separately.
%
% ============================================================

clc;
clear;
close all;

%% ============================================================
% 1. Simulation Settings
% =============================================================

dt = 0.25;                         % [day]
T  = 120;                          % [day]

N = round(T/dt) + 1;

time = (0:N-1)' * dt;

%% ============================================================
% 2. Soil Parameters
% =============================================================

theta_r  = 0.078;                  % Residual water content [-]
theta_s  = 0.430;                  % Saturated water content [-]

theta_FC = 0.250;                  % Field capacity [-]
theta_WP = 0.120;                  % Wilting point [-]

%% ============================================================
% 3. Soil Layer Geometry
% =============================================================

Z1 = 0.10;                          % Layer 1 [m]
Z2 = 0.20;                          % Layer 2 [m]
Z3 = 0.30;                          % Layer 3 [m]

Z = [Z1; Z2; Z3];

root_depth = sum(Z);

%% ============================================================
% 4. Initial Conditions
% =============================================================

theta0 = [0.20; 0.20; 0.20];

% Convert volumetric water content to water storage [m]
S0 = theta0 .* Z;

S = zeros(N,3);

S(1,:) = S0';

%% ============================================================
% 5. Environmental Inputs
% =============================================================

% ------------------------------------------------------------
% Rainfall [mm/day]
% ------------------------------------------------------------

rainfall = zeros(N,1);

% Controlled first experiment:
% No rainfall.

% ------------------------------------------------------------
% Irrigation [mm/day]
% ------------------------------------------------------------

irrigation = zeros(N,1);

% Days 0-20       : 0 mm/day
% Days 20-60      : 8 mm/day
% Days 60-120     : 0 mm/day

irrigation(time >= 20 & time < 60) = 8;

% ------------------------------------------------------------
% Potential ET [mm/day]
% ------------------------------------------------------------

ET_potential = 4 * ones(N,1);

%% ============================================================
% 6. ET Distribution
% =============================================================

ET_fraction = [0.50; 0.30; 0.20];

%% ============================================================
% 7. Reduced-Order Water Transfer Parameters
% =============================================================

% Percolation coefficients [1/day]

kp12 = 0.80;

kp23 = 0.50;

kp3d = 0.20;

%% ============================================================
% 8. Maximum Surface Infiltration
% =============================================================

Kinf = 0.020;                       % [m/day] = 20 mm/day

%% ============================================================
% 9. Storage Limits
% =============================================================

S_min = theta_r .* Z;

S_max = theta_s .* Z;

S_FC = theta_FC .* Z;

S_WP = theta_WP .* Z;

%% ============================================================
% 10. Allocate Variables
% =============================================================

% Soil water storage [m]
S = zeros(N,3);

S(1,:) = S0';

% Volumetric water content [-]
theta = zeros(N,3);

theta(1,:) = theta0';

% Water fluxes [m/day]
infiltration = zeros(N,1);

runoff = zeros(N,1);

q12 = zeros(N,1);

q23 = zeros(N,1);

q3d = zeros(N,1);

% Actual ET [m/day]
ET_actual = zeros(N,3);

% Soil stress
soil_stress = zeros(N,3);

%% ============================================================
% 11. Main Simulation
% =============================================================

for k = 1:N-1

    % --------------------------------------------------------
    % Current storage
    % --------------------------------------------------------

    S_current = S(k,:)';

    % --------------------------------------------------------
    % External water input
    % --------------------------------------------------------

    I = irrigation(k) / 1000;       % [m/day]

    P = rainfall(k) / 1000;         % [m/day]

    water_input = I + P;

    % --------------------------------------------------------
    % 1. Surface infiltration
    % --------------------------------------------------------

    current_theta1 = ...
        S_current(1) / Z1;

    % Remaining storage capacity of layer 1
    remaining_capacity = ...
        S_max(1) - S_current(1);

    % Saturation-dependent infiltration capacity
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
        min(potential_infiltration / 1, ...
            remaining_capacity / dt);

    actual_infiltration = ...
        max(actual_infiltration,0);

    % Surface runoff
    surface_excess = ...
        max(0,water_input-actual_infiltration);

    infiltration(k) = actual_infiltration;

    runoff(k) = surface_excess;

    % Add infiltration to layer 1
    S_current(1) = ...
        S_current(1) + actual_infiltration*dt;

    % --------------------------------------------------------
    % 2. Calculate soil water stress
    % --------------------------------------------------------

    theta_current = ...
        S_current ./ Z;

    stress = ...
        (theta_current-theta_WP) ./ ...
        (theta_FC-theta_WP);

    stress = ...
        min(max(stress,0),1);

    soil_stress(k,:) = stress';

    % --------------------------------------------------------
    % 3. Actual evapotranspiration
    % --------------------------------------------------------

    ET_demand = ...
        (ET_potential(k)/1000) .* ...
        ET_fraction .* stress;

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

    % --------------------------------------------------------
    % 4. Percolation: Layer 1 -> Layer 2
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

    % --------------------------------------------------------
    % 5. Percolation: Layer 2 -> Layer 3
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

    % --------------------------------------------------------
    % 6. Deep Drainage from Layer 3
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

    % --------------------------------------------------------
    % 7. Final Physical Bounds
    % --------------------------------------------------------

    S_current = ...
        min(max(S_current,S_min),S_max);

    % --------------------------------------------------------
    % 8. Store New State
    % --------------------------------------------------------

    S(k+1,:) = S_current';

    theta(k+1,:) = ...
        (S_current ./ Z)';

end

%% ============================================================
% 12. Final Stress Values
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

stress1 = min(max(stress1,0),1);
stress2 = min(max(stress2,0),1);
stress3 = min(max(stress3,0),1);

soil_stress = ...
    [stress1,stress2,stress3];

%% ============================================================
% 13. Actual ET
% =============================================================

ET_actual_total = ...
    sum(ET_actual,2);

%% ============================================================
% 14. Soil Water Storage
% =============================================================

storage = ...
    S(:,1) + S(:,2) + S(:,3);

%% ============================================================
% 15. Cumulative Fluxes
% =============================================================

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
% 16. Water Balance
% =============================================================

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
% 17. Console Output
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' REDUCED SOIL-WATER MODEL V3\n');
fprintf('====================================================\n');

fprintf('\nSimulation duration: %.1f days\n',T);

fprintf('Time step: %.2f day\n',dt);

fprintf('Root-zone depth: %.2f m\n',root_depth);

fprintf('\n----------------------------------------------------\n');
fprintf('Initial Soil Moisture\n');
fprintf('----------------------------------------------------\n');

fprintf('Layer 1: %.4f\n',theta1(1));
fprintf('Layer 2: %.4f\n',theta2(1));
fprintf('Layer 3: %.4f\n',theta3(1));

fprintf('\n----------------------------------------------------\n');
fprintf('Final Soil Moisture\n');
fprintf('----------------------------------------------------\n');

fprintf('Layer 1: %.4f\n',theta1(end));
fprintf('Layer 2: %.4f\n',theta2(end));
fprintf('Layer 3: %.4f\n',theta3(end));

fprintf('\n----------------------------------------------------\n');
fprintf('Minimum Soil Moisture\n');
fprintf('----------------------------------------------------\n');

fprintf('Layer 1: %.4f\n',min(theta1));
fprintf('Layer 2: %.4f\n',min(theta2));
fprintf('Layer 3: %.4f\n',min(theta3));

fprintf('\n----------------------------------------------------\n');
fprintf('Maximum Soil Moisture\n');
fprintf('----------------------------------------------------\n');

fprintf('Layer 1: %.4f\n',max(theta1));
fprintf('Layer 2: %.4f\n',max(theta2));
fprintf('Layer 3: %.4f\n',max(theta3));

fprintf('\n----------------------------------------------------\n');
fprintf('Water Fluxes\n');
fprintf('----------------------------------------------------\n');

fprintf('Total irrigation: %.2f mm\n', ...
    sum(irrigation)*dt);

fprintf('Total rainfall: %.2f mm\n', ...
    sum(rainfall)*dt);

fprintf('Total infiltration: %.2f mm\n', ...
    sum(infiltration)*dt*1000);

fprintf('Total runoff: %.2f mm\n', ...
    sum(runoff)*dt*1000);

fprintf('Total actual ET: %.2f mm\n', ...
    sum(ET_actual_total)*dt*1000);

fprintf('Total drainage: %.2f mm\n', ...
    sum(q3d)*dt*1000);

fprintf('\n----------------------------------------------------\n');
fprintf('Water Balance Verification\n');
fprintf('----------------------------------------------------\n');

fprintf('Maximum absolute error: %.6e m\n', ...
    max(abs(water_balance_error)));

fprintf('Maximum absolute error: %.6e mm\n', ...
    max(abs(water_balance_error))*1000);

%% ============================================================
% 18. Figure 1 - Soil Moisture
% =============================================================

figure( ...
    'Name','V3 - Soil Moisture Dynamics', ...
    'Color','w');

plot(time,theta1,'LineWidth',1.8);
hold on;

plot(time,theta2,'LineWidth',1.8);

plot(time,theta3,'LineWidth',1.8);

yline(theta_FC, ...
    '--','Field Capacity','LineWidth',1.2);

yline(theta_WP, ...
    '--','Wilting Point','LineWidth',1.2);

grid on;

xlabel('Time [day]');
ylabel('Volumetric Water Content [-]');

title('Three-Layer Soil Moisture Dynamics - V3');

legend( ...
    '\theta_1 - Surface', ...
    '\theta_2 - Middle', ...
    '\theta_3 - Root Zone', ...
    'Field Capacity', ...
    'Wilting Point', ...
    'Location','best');

ylim([0.05 0.45]);

%% ============================================================
% 19. Figure 2 - Irrigation
% =============================================================

figure( ...
    'Name','V3 - Irrigation', ...
    'Color','w');

stairs(time,irrigation, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('Irrigation [mm/day]');

title('Irrigation Input');

%% ============================================================
% 20. Figure 3 - ET
% =============================================================

figure( ...
    'Name','V3 - Evapotranspiration', ...
    'Color','w');

plot(time,ET_potential, ...
    'LineWidth',1.8);

hold on;

plot(time,ET_actual_total*1000, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('ET [mm/day]');

title('Potential and Actual Evapotranspiration');

legend( ...
    'Potential ET', ...
    'Actual ET', ...
    'Location','best');

%% ============================================================
% 21. Figure 4 - Internal Fluxes
% =============================================================

figure( ...
    'Name','V3 - Internal Fluxes', ...
    'Color','w');

plot(time,q12*1000, ...
    'LineWidth',1.8);

hold on;

plot(time,q23*1000, ...
    'LineWidth',1.8);

plot(time,q3d*1000, ...
    'LineWidth',1.8);

plot(time,infiltration*1000, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('Flux [mm/day]');

title('Soil Water Fluxes');

legend( ...
    'q_{12}', ...
    'q_{23}', ...
    'Drainage', ...
    'Infiltration', ...
    'Location','best');

%% ============================================================
% 22. Figure 5 - Soil Water Stress
% =============================================================

figure( ...
    'Name','V3 - Soil Water Stress', ...
    'Color','w');

plot(time,stress1,'LineWidth',1.8);
hold on;

plot(time,stress2,'LineWidth',1.8);

plot(time,stress3,'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('Stress Factor [-]');

title('Soil Water Stress');

legend( ...
    'Layer 1', ...
    'Layer 2', ...
    'Layer 3', ...
    'Location','best');

ylim([0 1.05]);

%% ============================================================
% 23. Figure 6 - Water Balance
% =============================================================

figure( ...
    'Name','V3 - Water Balance', ...
    'Color','w');

plot(time,storage*1000, ...
    'LineWidth',1.8);

hold on;

plot(time,water_balance_storage*1000, ...
    '--','LineWidth',1.5);

grid on;

xlabel('Time [day]');
ylabel('Soil Water Storage [mm]');

title('Water Balance Verification');

legend( ...
    'Actual Storage', ...
    'Calculated Storage', ...
    'Location','best');

%% ============================================================
% 24. Save Results
% =============================================================

results = struct();

results.version = 'V3.0';

results.time = time;
results.dt = dt;
results.T = T;

results.theta = theta;
results.theta1 = theta1;
results.theta2 = theta2;
results.theta3 = theta3;

results.S = S;

results.theta_r = theta_r;
results.theta_s = theta_s;
results.theta_FC = theta_FC;
results.theta_WP = theta_WP;

results.Z = Z;

results.irrigation = irrigation;
results.rainfall = rainfall;

results.ET_potential = ET_potential;
results.ET_actual = ET_actual;
results.ET_actual_total = ET_actual_total;

results.soil_stress = soil_stress;

results.infiltration = infiltration;
results.runoff = runoff;

results.q12 = q12;
results.q23 = q23;
results.q3d = q3d;

results.storage = storage;

results.water_balance_storage = ...
    water_balance_storage;

results.water_balance_error = ...
    water_balance_error;

results.cumulative_irrigation = ...
    cum_irrigation;

results.cumulative_rainfall = ...
    cum_rainfall;

results.cumulative_infiltration = ...
    cum_infiltration;

results.cumulative_runoff = ...
    cum_runoff;

results.cumulative_ET = ...
    cum_ET;

results.cumulative_drainage = ...
    cum_q3d;

save( ...
    '01_ReducedSoilWaterModel_V3_Results.mat', ...
    'results');

fprintf('\n');
fprintf('====================================================\n');
fprintf('V3 simulation completed.\n');
fprintf('Results saved to:\n');
fprintf('01_ReducedSoilWaterModel_V3_Results.mat\n');
fprintf('====================================================\n');