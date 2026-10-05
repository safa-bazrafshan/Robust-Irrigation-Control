%% ============================================================
% 01_ReducedSoilWaterModel_V2
% AI-Driven Smart Irrigation
%
% Control-Oriented Three-Layer Soil-Water Model
%
% Version: V2.0
%
% Purpose:
%   Develop a numerically stable and physically plausible
%   reduced-order soil-water model for future:
%
%       1. Sensor simulation
%       2. UKF state estimation
%       3. Baseline control
%       4. SAC reinforcement learning
%       5. Probabilistic safety filtering
%
% IMPORTANT:
%   This model is NOT the high-fidelity Richards model.
%   Richards will be implemented separately as the
%   high-fidelity environment.
%
% =============================================================

clc;
clear;
close all;

%% ============================================================
% 1. Simulation Settings
% =============================================================

dt = 1;                         % Time step [day]
T  = 120;                       % Simulation duration [day]
N  = round(T/dt);

time = (0:N-1)' * dt;

%% ============================================================
% 2. Soil Hydraulic Parameters
% =============================================================

% Volumetric water contents
theta_r  = 0.078;               % Residual water content [-]
theta_s  = 0.430;               % Saturated water content [-]

theta_FC = 0.250;               % Field capacity [-]
theta_WP = 0.120;               % Wilting point [-]

%% ============================================================
% 3. Soil Layer Geometry
% =============================================================

% Three soil layers
%
% Layer 1: surface
% Layer 2: intermediate
% Layer 3: root zone

Z1 = 0.10;                       % [m]
Z2 = 0.20;                       % [m]
Z3 = 0.30;                       % [m]

Z = [Z1; Z2; Z3];

root_depth = Z1 + Z2 + Z3;

%% ============================================================
% 4. Reduced-Order Hydraulic Exchange Parameters
% =============================================================

% These are reduced-order exchange coefficients.
%
% They are NOT saturated hydraulic conductivity values.
%
% Units:
%       k12, k23 -> [1/day]
%
% They determine the rate of water exchange between
% neighboring soil layers.

k12 = 0.25;                      % Layer 1 -> Layer 2 [1/day]
k23 = 0.20;                      % Layer 2 -> Layer 3 [1/day]

%% ============================================================
% 5. Infiltration Parameter
% =============================================================

% Maximum effective infiltration capacity
Kinf = 0.020;                    % [m/day] = 20 mm/day

%% ============================================================
% 6. Deep Drainage Parameter
% =============================================================

% Drainage coefficient from root zone
Kd = 0.020;                      % [m/day]

%% ============================================================
% 7. Initial Soil Moisture
% =============================================================

theta0 = [0.20; 0.20; 0.20];

theta = zeros(N,3);

theta(1,:) = theta0';

%% ============================================================
% 8. Environmental Inputs
% =============================================================

% ------------------------------------------------------------
% Rainfall
% ------------------------------------------------------------

rainfall = zeros(N,1);           % [mm/day]

% No rainfall in this first controlled experiment.
%
% Rainfall will be introduced later as a stochastic
% environmental disturbance.

% ------------------------------------------------------------
% Potential Evapotranspiration
% ------------------------------------------------------------

ET_potential = 4 * ones(N,1);    % [mm/day]

% ------------------------------------------------------------
% Irrigation
% ------------------------------------------------------------

irrigation = zeros(N,1);         % [mm/day]

% Days 1-20   : no irrigation
% Days 21-60  : 8 mm/day
% Days 61-120 : no irrigation

irrigation(time >= 20 & time < 60) = 8;

%% ============================================================
% 9. ET Distribution Between Soil Layers
% ============================================================

% Fraction of potential ET associated with each layer.

ET_fraction = [0.50; 0.30; 0.20];

%% ============================================================
% 10. Allocate Memory for Water Fluxes
% =============================================================

q12 = zeros(N,1);                % Layer 1 -> Layer 2 [m/day]

q23 = zeros(N,1);                % Layer 2 -> Layer 3 [m/day]

q3d = zeros(N,1);                % Deep drainage [m/day]

infiltration = zeros(N,1);       % Effective infiltration [m/day]

runoff = zeros(N,1);             % Surface excess water [m/day]

ET_actual = zeros(N,3);          % Actual ET [m/day]

soil_stress = zeros(N,3);        % Water stress factors [-]

%% ============================================================
% 11. Main Simulation Loop
% =============================================================

for k = 1:N-1

    % --------------------------------------------------------
    % Current soil moisture states
    % --------------------------------------------------------

    theta1 = theta(k,1);
    theta2 = theta(k,2);
    theta3 = theta(k,3);

    % --------------------------------------------------------
    % External inputs
    % --------------------------------------------------------

    I_mm = irrigation(k);
    P_mm = rainfall(k);

    ETp_mm = ET_potential(k);

    % Convert mm/day to m/day
    I = I_mm / 1000;
    P = P_mm / 1000;

    ETp = ETp_mm / 1000;

    % --------------------------------------------------------
    % Total water arriving at soil surface
    % --------------------------------------------------------

    water_input = I + P;

    % --------------------------------------------------------
    % Effective infiltration
    %
    % As the surface layer approaches saturation,
    % effective infiltration capacity decreases.
    % --------------------------------------------------------

    infiltration_factor = ...
        (theta_s - theta1) / ...
        (theta_s - theta_FC);

    infiltration_factor = ...
        min(max(infiltration_factor,0),1);

    infiltration_capacity = ...
        Kinf * infiltration_factor;

    infiltration(k) = ...
        min(water_input,infiltration_capacity);

    % Excess surface water
    runoff(k) = ...
        max(0,water_input - infiltration(k));

    % --------------------------------------------------------
    % Vertical water exchange
    %
    % Downward movement occurs when the upper layer
    % contains more water than the lower layer.
    % --------------------------------------------------------

    q12(k) = ...
        k12 * Z1 * max(0,theta1-theta2);

    q23(k) = ...
        k23 * Z2 * max(0,theta2-theta3);

    % --------------------------------------------------------
    % Deep drainage
    %
    % Drainage starts above field capacity.
    % --------------------------------------------------------

    q3d(k) = ...
        Kd * max(0,theta3-theta_FC);

    % --------------------------------------------------------
    % Soil water stress
    %
    % Stress = 0 at wilting point
    % Stress = 1 at field capacity and above
    % --------------------------------------------------------

    stress1 = ...
        (theta1-theta_WP) / ...
        (theta_FC-theta_WP);

    stress2 = ...
        (theta2-theta_WP) / ...
        (theta_FC-theta_WP);

    stress3 = ...
        (theta3-theta_WP) / ...
        (theta_FC-theta_WP);

    stress1 = min(max(stress1,0),1);
    stress2 = min(max(stress2,0),1);
    stress3 = min(max(stress3,0),1);

    soil_stress(k,:) = ...
        [stress1,stress2,stress3];

    % --------------------------------------------------------
    % Actual evapotranspiration
    % --------------------------------------------------------

    ET1 = ETp * ET_fraction(1) * stress1;
    ET2 = ETp * ET_fraction(2) * stress2;
    ET3 = ETp * ET_fraction(3) * stress3;

    ET_actual(k,:) = [ET1,ET2,ET3];

    % --------------------------------------------------------
    % Soil water balance
    % --------------------------------------------------------

    dtheta1 = ...
        (infiltration(k) ...
        - q12(k) ...
        - ET1) / Z1;

    dtheta2 = ...
        (q12(k) ...
        - q23(k) ...
        - ET2) / Z2;

    dtheta3 = ...
        (q23(k) ...
        - q3d(k) ...
        - ET3) / Z3;

    % --------------------------------------------------------
    % Forward Euler integration
    % --------------------------------------------------------

    theta1_next = ...
        theta1 + dt*dtheta1;

    theta2_next = ...
        theta2 + dt*dtheta2;

    theta3_next = ...
        theta3 + dt*dtheta3;

    % --------------------------------------------------------
    % Physical bounds
    % --------------------------------------------------------

    theta1_next = ...
        min(max(theta1_next,theta_r),theta_s);

    theta2_next = ...
        min(max(theta2_next,theta_r),theta_s);

    theta3_next = ...
        min(max(theta3_next,theta_r),theta_s);

    % --------------------------------------------------------
    % Store states
    % --------------------------------------------------------

    theta(k+1,:) = ...
        [theta1_next,theta2_next,theta3_next];

end

%% ============================================================
% 12. Calculate Final ET Values
% =============================================================

% Calculate stress and ET for the final state.

theta1 = theta(:,1);
theta2 = theta(:,2);
theta3 = theta(:,3);

stress1 = ...
    min(max( ...
    (theta1-theta_WP) ./ ...
    (theta_FC-theta_WP),0),1);

stress2 = ...
    min(max( ...
    (theta2-theta_WP) ./ ...
    (theta_FC-theta_WP),0),1);

stress3 = ...
    min(max( ...
    (theta3-theta_WP) ./ ...
    (theta_FC-theta_WP),0),1);

soil_stress = ...
    [stress1,stress2,stress3];

ET_actual(:,1) = ...
    (ET_potential/1000) .* ...
    ET_fraction(1) .* stress1;

ET_actual(:,2) = ...
    (ET_potential/1000) .* ...
    ET_fraction(2) .* stress2;

ET_actual(:,3) = ...
    (ET_potential/1000) .* ...
    ET_fraction(3) .* stress3;

%% ============================================================
% 13. Total Actual ET
% =============================================================

ET_actual_total = ...
    sum(ET_actual,2);

%% ============================================================
% 14. Water Storage
% =============================================================

% Total water stored in the three-layer soil profile
%
% Storage per unit surface area [m]

storage = ...
    theta(:,1)*Z1 + ...
    theta(:,2)*Z2 + ...
    theta(:,3)*Z3;

%% ============================================================
% 15. Cumulative Water Fluxes
% =============================================================

cumulative_irrigation = ...
    cumsum(irrigation) * dt / 1000;

cumulative_rainfall = ...
    cumsum(rainfall) * dt / 1000;

cumulative_infiltration = ...
    cumsum(infiltration) * dt;

cumulative_runoff = ...
    cumsum(runoff) * dt;

cumulative_ET = ...
    cumsum(ET_actual_total) * dt;

cumulative_drainage = ...
    cumsum(q3d) * dt;

%% ============================================================
% 16. Water Balance Residual
% =============================================================

initial_storage = storage(1);

water_balance_estimate = ...
    initial_storage ...
    + cumulative_infiltration ...
    - cumulative_ET ...
    - cumulative_drainage ...
    - cumulative_runoff;

water_balance_error = ...
    storage - water_balance_estimate;

%% ============================================================
% 17. Console Results
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' REDUCED SOIL-WATER MODEL V2\n');
fprintf('====================================================\n');

fprintf('\nSimulation duration:\n');
fprintf('%.0f days\n',T);

fprintf('\nTime step:\n');
fprintf('%.2f day\n',dt);

fprintf('\nRoot-zone depth:\n');
fprintf('%.2f m\n',root_depth);

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

fprintf('Total potential ET: %.2f mm\n', ...
    sum(ET_potential)*dt);

fprintf('Total actual ET: %.2f mm\n', ...
    sum(ET_actual_total)*dt*1000);

fprintf('Total infiltration: %.2f mm\n', ...
    sum(infiltration)*dt*1000);

fprintf('Total runoff: %.2f mm\n', ...
    sum(runoff)*dt*1000);

fprintf('Total drainage: %.2f mm\n', ...
    sum(q3d)*dt*1000);

fprintf('\n----------------------------------------------------\n');
fprintf('Water Balance\n');
fprintf('----------------------------------------------------\n');

fprintf('Maximum absolute balance error: %.6e m\n', ...
    max(abs(water_balance_error)));

%% ============================================================
% 18. Plot 1 - Soil Moisture Dynamics
% =============================================================

figure( ...
    'Name','V2 - Soil Moisture Dynamics', ...
    'Color','w');

plot(time,theta1, ...
    'LineWidth',1.8);

hold on;

plot(time,theta2, ...
    'LineWidth',1.8);

plot(time,theta3, ...
    'LineWidth',1.8);

yline(theta_FC, ...
    '--', ...
    'Field Capacity', ...
    'LineWidth',1.2);

yline(theta_WP, ...
    '--', ...
    'Wilting Point', ...
    'LineWidth',1.2);

grid on;

xlabel('Time [day]');
ylabel('Volumetric Water Content [-]');

title('Three-Layer Soil Moisture Dynamics - V2');

legend( ...
    '\theta_1 - Surface Layer', ...
    '\theta_2 - Middle Layer', ...
    '\theta_3 - Root Zone', ...
    'Field Capacity', ...
    'Wilting Point', ...
    'Location','best');

%% ============================================================
% 19. Plot 2 - Irrigation and Rainfall
% =============================================================

figure( ...
    'Name','V2 - Irrigation and Rainfall', ...
    'Color','w');

stairs(time,irrigation, ...
    'LineWidth',1.8);

hold on;

stairs(time,rainfall, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('Water Input [mm/day]');

title('Irrigation and Rainfall');

legend( ...
    'Irrigation', ...
    'Rainfall', ...
    'Location','best');

%% ============================================================
% 20. Plot 3 - ET
% =============================================================

figure( ...
    'Name','V2 - Evapotranspiration', ...
    'Color','w');

plot(time,ET_potential, ...
    'LineWidth',1.8);

hold on;

plot(time,ET_actual_total*1000, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('ET [mm/day]');

title('Potential vs Actual Evapotranspiration');

legend( ...
    'Potential ET', ...
    'Actual ET', ...
    'Location','best');

%% ============================================================
% 21. Plot 4 - Internal Water Fluxes
% =============================================================

figure( ...
    'Name','V2 - Internal Water Fluxes', ...
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
ylabel('Water Flux [mm/day]');

title('Internal Soil Water Fluxes');

legend( ...
    'q_{12}', ...
    'q_{23}', ...
    'Deep Drainage', ...
    'Effective Infiltration', ...
    'Location','best');

%% ============================================================
% 22. Plot 5 - Soil Water Stress
% =============================================================

figure( ...
    'Name','V2 - Soil Water Stress', ...
    'Color','w');

plot(time,stress1, ...
    'LineWidth',1.8);

hold on;

plot(time,stress2, ...
    'LineWidth',1.8);

plot(time,stress3, ...
    'LineWidth',1.8);

grid on;

xlabel('Time [day]');
ylabel('Stress Factor [-]');

title('Soil Water Stress Factors');

legend( ...
    'Layer 1', ...
    'Layer 2', ...
    'Layer 3', ...
    'Location','best');

ylim([0 1.05]);

%% ============================================================
% 23. Plot 6 - Water Balance
% =============================================================

figure( ...
    'Name','V2 - Water Balance', ...
    'Color','w');

plot(time,storage*1000, ...
    'LineWidth',1.8);

hold on;

plot(time,water_balance_estimate*1000, ...
    '--', ...
    'LineWidth',1.5);

grid on;

xlabel('Time [day]');
ylabel('Stored Water [mm]');

title('Soil Water Balance Verification');

legend( ...
    'Actual Soil Storage', ...
    'Water Balance Estimate', ...
    'Location','best');

%% ============================================================
% 24. Save Results
% =============================================================

results = struct();

results.version = 'V2.0';

results.time = time;
results.dt = dt;
results.T = T;

results.theta = theta;

results.theta1 = theta1;
results.theta2 = theta2;
results.theta3 = theta3;

results.theta_r = theta_r;
results.theta_s = theta_s;
results.theta_FC = theta_FC;
results.theta_WP = theta_WP;

results.Z = Z;
results.root_depth = root_depth;

results.k12 = k12;
results.k23 = k23;
results.Kinf = Kinf;
results.Kd = Kd;

results.irrigation = irrigation;
results.rainfall = rainfall;

results.ET_potential = ET_potential;
results.ET_actual = ET_actual;
results.ET_actual_total = ET_actual_total;

results.soil_stress = soil_stress;

results.infiltration = infiltration;
results.q12 = q12;
results.q23 = q23;
results.q3d = q3d;
results.runoff = runoff;

results.storage = storage;

results.cumulative_irrigation = ...
    cumulative_irrigation;

results.cumulative_rainfall = ...
    cumulative_rainfall;

results.cumulative_infiltration = ...
    cumulative_infiltration;

results.cumulative_ET = ...
    cumulative_ET;

results.cumulative_drainage = ...
    cumulative_drainage;

results.cumulative_runoff = ...
    cumulative_runoff;

results.water_balance_error = ...
    water_balance_error;

save( ...
    '01_ReducedSoilWaterModel_V2_Results.mat', ...
    'results');

%% ============================================================
% 25. Final Message
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf('V2 simulation completed successfully.\n');
fprintf('Results saved as:\n');
fprintf('01_ReducedSoilWaterModel_V2_Results.mat\n');
fprintf('====================================================\n');