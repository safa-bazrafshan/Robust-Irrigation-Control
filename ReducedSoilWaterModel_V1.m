%% 01_ReducedSoilWaterModel_V1
% AI-Driven Smart Irrigation
%
% Control-Oriented Three-Layer Soil-Water Model
%
% Version: V1.0
%
% Purpose:
%   1. Build a nonlinear reduced-order soil-water model
%   2. Simulate soil moisture dynamics
%   3. Evaluate irrigation, rainfall, ET and drainage effects
%
% IMPORTANT:
%   This is NOT the final high-fidelity Richards model.
%   It is the control-oriented model that will later support
%   UKF and SAC development.

clc;
clear;
close all;

%% ============================================================
% 1. Simulation Settings
% =============================================================

dt = 1;                 % Time step [day]
T  = 120;               % Simulation horizon [day]
N  = T / dt;

time = (0:N-1)' * dt;

%% ============================================================
% 2. Soil Parameters
% =============================================================

% Residual and saturated volumetric water content
theta_r = 0.078;        % Residual water content [-]
theta_s = 0.430;        % Saturated water content [-]

% Field capacity and wilting point
theta_FC = 0.250;       % Field capacity [-]
theta_WP = 0.120;       % Wilting point [-]

% Soil layer thicknesses
Z1 = 0.10;              % Layer 1 thickness [m]
Z2 = 0.20;              % Layer 2 thickness [m]
Z3 = 0.30;              % Layer 3 thickness [m]

Z = [Z1; Z2; Z3];

% Hydraulic conductivity-like parameters
K1 = 0.080;             % Layer 1 transfer coefficient [m/day]
K2 = 0.050;             % Layer 2 transfer coefficient [m/day]

% Drainage coefficient
Kd = 0.050;             % Drainage coefficient [m/day]

%% ============================================================
% 3. Initial Conditions
% =============================================================

theta0 = [0.20; 0.20; 0.20];

% State matrix
theta = zeros(N,3);

% Initial state
theta(1,:) = theta0';

%% ============================================================
% 4. Environmental Inputs
% =============================================================

% Rainfall [mm/day]
rainfall = zeros(N,1);

% No rainfall during the first prototype experiment
rainfall(:) = 0;

% Evapotranspiration [mm/day]
ET = 4 * ones(N,1);

% Irrigation [mm/day]
irrigation = zeros(N,1);

% Irrigation schedule
%
% Days 1-20   : No irrigation
% Days 21-60  : 8 mm/day
% Days 61-120 : No irrigation

irrigation(time >= 20 & time < 60) = 8;

%% ============================================================
% 5. Root Uptake / ET Distribution
% =============================================================

% Fraction of ET assigned to each soil layer
ET_fraction = [0.50; 0.30; 0.20];

%% ============================================================
% 6. Main Simulation Loop
% =============================================================

for k = 1:N-1

    % ----------------------------------------------------------
    % Current state
    % ----------------------------------------------------------

    theta1 = theta(k,1);
    theta2 = theta(k,2);
    theta3 = theta(k,3);

    % ----------------------------------------------------------
    % External inputs
    % ----------------------------------------------------------

    I = irrigation(k);      % Irrigation [mm/day]
    P = rainfall(k);        % Rainfall [mm/day]
    ET_total = ET(k);       % ET [mm/day]

    % Convert mm/day to m/day
    I_m = I / 1000;
    P_m = P / 1000;
    ET_m = ET_total / 1000;

    % ----------------------------------------------------------
    % ET distribution
    % ----------------------------------------------------------

    ET1 = ET_m * ET_fraction(1);
    ET2 = ET_m * ET_fraction(2);
    ET3 = ET_m * ET_fraction(3);

    % ----------------------------------------------------------
    % Infiltration input
    % ----------------------------------------------------------

    water_input = I_m + P_m;

    % ----------------------------------------------------------
    % Soil moisture dependent vertical flux
    % ----------------------------------------------------------

    % Layer 1 -> Layer 2
    moisture_gradient_12 = ...
        (theta1 - theta2) / (theta_s - theta_r);

    q12 = K1 * max(0, moisture_gradient_12);

    % Layer 2 -> Layer 3
    moisture_gradient_23 = ...
        (theta2 - theta3) / (theta_s - theta_r);

    q23 = K2 * max(0, moisture_gradient_23);

    % ----------------------------------------------------------
    % Drainage from Layer 3
    % ----------------------------------------------------------

    q3d = Kd * max(0, theta3 - theta_FC);

    % ----------------------------------------------------------
    % Soil-water balance
    % ----------------------------------------------------------

    dtheta1 = ...
        (water_input - q12 - ET1) / Z1;

    dtheta2 = ...
        (q12 - q23 - ET2) / Z2;

    dtheta3 = ...
        (q23 - q3d - ET3) / Z3;

    % ----------------------------------------------------------
    % Euler integration
    % ----------------------------------------------------------

    theta1_next = theta1 + dt * dtheta1;
    theta2_next = theta2 + dt * dtheta2;
    theta3_next = theta3 + dt * dtheta3;

    % ----------------------------------------------------------
    % Physical bounds
    % ----------------------------------------------------------

    theta1_next = min(max(theta1_next, theta_r), theta_s);
    theta2_next = min(max(theta2_next, theta_r), theta_s);
    theta3_next = min(max(theta3_next, theta_r), theta_s);

    % ----------------------------------------------------------
    % Store state
    % ----------------------------------------------------------

    theta(k+1,:) = ...
        [theta1_next, theta2_next, theta3_next];

end

%% ============================================================
% 7. Extract States
% =============================================================

theta1 = theta(:,1);
theta2 = theta(:,2);
theta3 = theta(:,3);

%% ============================================================
% 8. Basic Statistics
% =============================================================

fprintf('\n');
fprintf('=============================================\n');
fprintf('Reduced Soil-Water Model V1\n');
fprintf('=============================================\n');

fprintf('Simulation time: %.0f days\n', T);

fprintf('\nInitial soil moisture:\n');
fprintf('Layer 1: %.3f\n', theta1(1));
fprintf('Layer 2: %.3f\n', theta2(1));
fprintf('Layer 3: %.3f\n', theta3(1));

fprintf('\nFinal soil moisture:\n');
fprintf('Layer 1: %.3f\n', theta1(end));
fprintf('Layer 2: %.3f\n', theta2(end));
fprintf('Layer 3: %.3f\n', theta3(end));

fprintf('\nMinimum soil moisture:\n');
fprintf('Layer 1: %.3f\n', min(theta1));
fprintf('Layer 2: %.3f\n', min(theta2));
fprintf('Layer 3: %.3f\n', min(theta3));

fprintf('\nMaximum soil moisture:\n');
fprintf('Layer 1: %.3f\n', max(theta1));
fprintf('Layer 2: %.3f\n', max(theta2));
fprintf('Layer 3: %.3f\n', max(theta3));

fprintf('\nTotal irrigation:\n');
fprintf('%.2f mm\n', sum(irrigation) * dt);

fprintf('\nTotal rainfall:\n');
fprintf('%.2f mm\n', sum(rainfall) * dt);

fprintf('\nTotal ET:\n');
fprintf('%.2f mm\n', sum(ET) * dt);

%% ============================================================
% 9. Plot Soil Moisture
% =============================================================

figure('Name','Soil Moisture Dynamics','Color','w');

plot(time, theta1, 'LineWidth', 1.8);
hold on;

plot(time, theta2, 'LineWidth', 1.8);
plot(time, theta3, 'LineWidth', 1.8);

yline(theta_FC, '--', 'Field Capacity', ...
    'LineWidth', 1.2);

yline(theta_WP, '--', 'Wilting Point', ...
    'LineWidth', 1.2);

grid on;

xlabel('Time [day]');
ylabel('Volumetric Water Content [-]');

title('Three-Layer Soil Moisture Dynamics');

legend( ...
    '\theta_1 - Surface Layer', ...
    '\theta_2 - Middle Layer', ...
    '\theta_3 - Root Zone', ...
    'Field Capacity', ...
    'Wilting Point', ...
    'Location','best');

%% ============================================================
% 10. Plot Irrigation
% =============================================================

figure('Name','Irrigation Input','Color','w');

stairs(time, irrigation, ...
    'LineWidth', 1.8);

grid on;

xlabel('Time [day]');
ylabel('Irrigation [mm/day]');

title('Irrigation Schedule');

%% ============================================================
% 11. Plot Environmental Water Balance
% =============================================================

figure('Name','Water Inputs','Color','w');

plot(time, irrigation, ...
    'LineWidth', 1.8);

hold on;

plot(time, rainfall, ...
    'LineWidth', 1.8);

plot(time, ET, ...
    'LineWidth', 1.8);

grid on;

xlabel('Time [day]');
ylabel('Water Flux [mm/day]');

title('Water Inputs and Evapotranspiration');

legend( ...
    'Irrigation', ...
    'Rainfall', ...
    'Evapotranspiration', ...
    'Location','best');

%% ============================================================
% 12. Save Results
% =============================================================

results.time = time;

results.theta1 = theta1;
results.theta2 = theta2;
results.theta3 = theta3;

results.irrigation = irrigation;
results.rainfall = rainfall;
results.ET = ET;

results.theta_r = theta_r;
results.theta_s = theta_s;
results.theta_FC = theta_FC;
results.theta_WP = theta_WP;

results.Z = Z;

results.dt = dt;
results.T = T;

save('01_ReducedSoilWaterModel_V1_Results.mat', ...
    'results');

fprintf('\n');
fprintf('Results saved to:\n');
fprintf('01_ReducedSoilWaterModel_V1_Results.mat\n');
fprintf('=============================================\n');