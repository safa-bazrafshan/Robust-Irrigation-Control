%% ============================================================
% 01_ReducedSoilWaterModel_V3_Validation
%
% Validation and Sanity Checks for Reduced Soil-Water Model V3
%
% Corrected Version
%
% Purpose:
%   Validate:
%
%       1. Soil moisture physical bounds
%       2. Soil storage physical bounds
%       3. Non-negative water fluxes
%       4. Interval-by-interval water conservation
%       5. Independent total water balance
%       6. Numerical smoothness
%
% IMPORTANT:
%   Infiltration is an INTERNAL transfer of external water
%   into the soil system. Therefore it must NOT be subtracted
%   again from irrigation/rainfall in the total water balance.
%
% ============================================================

clc;
clear;
close all;

%% ============================================================
% 1. Load V3 Results
% =============================================================

filename = ...
    '01_ReducedSoilWaterModel_V3_Results.mat';

if ~isfile(filename)

    error(['Result file not found: ', filename]);

end

load(filename);

%% ============================================================
% 2. Extract Variables
% =============================================================

time = results.time;

dt = results.dt;

theta = results.theta;

S = results.S;

Z = results.Z;

theta_r = results.theta_r;

theta_s = results.theta_s;

irrigation = results.irrigation;

rainfall = results.rainfall;

infiltration = results.infiltration;

runoff = results.runoff;

q12 = results.q12;

q23 = results.q23;

q3d = results.q3d;

ET_actual = results.ET_actual;

ET_actual_total = ...
    results.ET_actual_total;

%% ============================================================
% 3. Total Soil Storage
% =============================================================

storage = sum(S,2);

%% ============================================================
% 4. Initialize Tests
% =============================================================

test1 = false;
test2 = false;
test3 = false;
test4 = false;
test5 = false;
test6 = false;

%% ============================================================
% TEST 1
% Physical Bounds of Soil Moisture
% =============================================================

minimum_theta = min(theta,[],'all');

maximum_theta = max(theta,[],'all');

test1 = ...
    minimum_theta >= theta_r - 1e-12 && ...
    maximum_theta <= theta_s + 1e-12;

%% ============================================================
% TEST 2
% Physical Bounds of Soil Storage
% =============================================================

S_min = theta_r .* Z;

S_max = theta_s .* Z;

storage_lower_violation = ...
    min(S - S_min',[],'all');

storage_upper_violation = ...
    max(S - S_max',[],'all');

test2 = ...
    storage_lower_violation >= -1e-12 && ...
    storage_upper_violation <= 1e-12;

%% ============================================================
% TEST 3
% Non-Negative Water Fluxes
% =============================================================

minimum_infiltration = min(infiltration);

minimum_runoff = min(runoff);

minimum_q12 = min(q12);

minimum_q23 = min(q23);

minimum_q3d = min(q3d);

minimum_ET = min(ET_actual,[],'all');

test3 = ...
    minimum_infiltration >= -1e-12 && ...
    minimum_runoff >= -1e-12 && ...
    minimum_q12 >= -1e-12 && ...
    minimum_q23 >= -1e-12 && ...
    minimum_q3d >= -1e-12 && ...
    minimum_ET >= -1e-12;

%% ============================================================
% TEST 4
% Interval-by-Interval Water Conservation
% =============================================================

% The state transition is:
%
% S(k+1)-S(k)
%
% =
%
% [Infiltration
%  - Runoff
%  - ET
%  - Drainage] * dt
%
% Internal transfers q12 and q23 cancel out when total
% root-zone storage is considered.

delta_storage = ...
    diff(storage);

net_external_flux = ...
    infiltration(1:end-1) ...
    - runoff(1:end-1) ...
    - ET_actual_total(1:end-1) ...
    - q3d(1:end-1);

expected_delta_storage = ...
    net_external_flux * dt;

balance_residual = ...
    delta_storage - expected_delta_storage;

maximum_interval_error_m = ...
    max(abs(balance_residual));

maximum_interval_error_mm = ...
    maximum_interval_error_m * 1000;

balance_tolerance_mm = 1e-9;

test4 = ...
    maximum_interval_error_mm <= balance_tolerance_mm;

%% ============================================================
% TEST 5
% Independent Total Water Balance
% =============================================================

% IMPORTANT:
%
% Irrigation and rainfall are EXTERNAL inputs.
%
% Infiltration is an INTERNAL transfer from the external
% input into the soil system.
%
% Therefore:
%
% Final Storage =
% Initial Storage
% + Irrigation
% + Rainfall
% - Runoff
% - Actual ET
% - Deep Drainage

total_irrigation_mm = ...
    sum(irrigation(1:end-1)) * dt;

total_rainfall_mm = ...
    sum(rainfall(1:end-1)) * dt;

total_runoff_mm = ...
    sum(runoff(1:end-1)) * dt * 1000;

total_ET_mm = ...
    sum(ET_actual_total(1:end-1)) * dt * 1000;

total_drainage_mm = ...
    sum(q3d(1:end-1)) * dt * 1000;

initial_storage_mm = ...
    storage(1) * 1000;

final_storage_mm = ...
    storage(end) * 1000;

total_external_input_mm = ...
    total_irrigation_mm ...
    + total_rainfall_mm;

independent_final_storage_mm = ...
    initial_storage_mm ...
    + total_external_input_mm ...
    - total_runoff_mm ...
    - total_ET_mm ...
    - total_drainage_mm;

independent_balance_error_mm = ...
    final_storage_mm ...
    - independent_final_storage_mm;

test5 = ...
    abs(independent_balance_error_mm) ...
    <= balance_tolerance_mm;

%% ============================================================
% TEST 6
% Numerical Smoothness
% =============================================================

dtheta = diff(theta);

max_delta_theta = ...
    max(abs(dtheta),[],'all');

smoothness_threshold = 0.10;

test6 = ...
    max_delta_theta <= smoothness_threshold;

%% ============================================================
% 5. Display Results
% =============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V3 MODEL VALIDATION - CORRECTED\n');
fprintf('====================================================\n');

%% ------------------------------------------------------------
% Test 1
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 1 - Soil Moisture Bounds:\n');

if test1
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Minimum theta = %.6f\n', ...
    minimum_theta);

fprintf('Maximum theta = %.6f\n', ...
    maximum_theta);

%% ------------------------------------------------------------
% Test 2
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 2 - Soil Storage Bounds:\n');

if test2
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

%% ------------------------------------------------------------
% Test 3
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 3 - Non-Negative Fluxes:\n');

if test3
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

%% ------------------------------------------------------------
% Test 4
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 4 - Interval Water Conservation:\n');

if test4
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Maximum interval error = %.12f mm\n', ...
    maximum_interval_error_mm);

%% ------------------------------------------------------------
% Test 5
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 5 - Independent Total Water Balance:\n');

if test5
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Initial storage = %.6f mm\n', ...
    initial_storage_mm);

fprintf('Final storage = %.6f mm\n', ...
    final_storage_mm);

fprintf('External input = %.6f mm\n', ...
    total_external_input_mm);

fprintf('Runoff = %.6f mm\n', ...
    total_runoff_mm);

fprintf('Actual ET = %.6f mm\n', ...
    total_ET_mm);

fprintf('Deep drainage = %.6f mm\n', ...
    total_drainage_mm);

fprintf('Independent final storage = %.6f mm\n', ...
    independent_final_storage_mm);

fprintf('Balance error = %.12f mm\n', ...
    independent_balance_error_mm);

%% ------------------------------------------------------------
% Test 6
% ------------------------------------------------------------

fprintf('\n');
fprintf('TEST 6 - Numerical Smoothness:\n');

if test6
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end

fprintf('Maximum one-step theta change = %.6f\n', ...
    max_delta_theta);

%% ============================================================
% 6. Overall Result
% =============================================================

all_tests_passed = ...
    test1 && ...
    test2 && ...
    test3 && ...
    test4 && ...
    test5 && ...
    test6;

fprintf('\n');
fprintf('====================================================\n');

if all_tests_passed

    fprintf('ALL NUMERICAL SANITY TESTS PASSED.\n');

else

    fprintf('ONE OR MORE VALIDATION TESTS FAILED.\n');

end

fprintf('====================================================\n');

%% ============================================================
% 7. Physical Water Summary
% =============================================================

fprintf('\n');
fprintf('----------------------------------------------------\n');
fprintf('PHYSICAL WATER BUDGET\n');
fprintf('----------------------------------------------------\n');

fprintf('Initial storage: %.3f mm\n', ...
    initial_storage_mm);

fprintf('Irrigation: %.3f mm\n', ...
    total_irrigation_mm);

fprintf('Rainfall: %.3f mm\n', ...
    total_rainfall_mm);

fprintf('Runoff: %.3f mm\n', ...
    total_runoff_mm);

fprintf('Actual ET: %.3f mm\n', ...
    total_ET_mm);

fprintf('Deep drainage: %.3f mm\n', ...
    total_drainage_mm);

fprintf('Final storage: %.3f mm\n', ...
    final_storage_mm);

fprintf('\n');

%% ============================================================
% 8. Save Validation Results
% =============================================================

validation = struct();

validation.test1_soil_moisture_bounds = test1;

validation.test2_storage_bounds = test2;

validation.test3_nonnegative_fluxes = test3;

validation.test4_interval_water_conservation = test4;

validation.test5_total_water_balance = test5;

validation.test6_numerical_smoothness = test6;

validation.all_tests_passed = ...
    all_tests_passed;

validation.minimum_theta = ...
    minimum_theta;

validation.maximum_theta = ...
    maximum_theta;

validation.maximum_interval_error_mm = ...
    maximum_interval_error_mm;

validation.independent_balance_error_mm = ...
    independent_balance_error_mm;

validation.maximum_one_step_theta_change = ...
    max_delta_theta;

validation.initial_storage_mm = ...
    initial_storage_mm;

validation.final_storage_mm = ...
    final_storage_mm;

validation.total_irrigation_mm = ...
    total_irrigation_mm;

validation.total_rainfall_mm = ...
    total_rainfall_mm;

validation.total_runoff_mm = ...
    total_runoff_mm;

validation.total_ET_mm = ...
    total_ET_mm;

validation.total_drainage_mm = ...
    total_drainage_mm;

save( ...
    '01_ReducedSoilWaterModel_V3_Validation_Results.mat', ...
    'validation');

fprintf('\n');
fprintf('Validation results saved to:\n');

fprintf('01_ReducedSoilWaterModel_V3_Validation_Results.mat\n');

fprintf('\n');