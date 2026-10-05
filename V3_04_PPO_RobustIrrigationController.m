%% V3_04_PPO_RobustIrrigationController.m
% Robust PPO Irrigation Controller
% MATLAB R2023b
%
% Purpose:
%   Train and evaluate a PPO controller for closed-loop irrigation
%   under uncertainty in soil-water parameters.
%
% Plant:
%   Exact V3 reduced three-layer soil-water model.
%
% Controller objective:
%   Maintain root-zone moisture within the desired operating band
%   while reducing irrigation, drainage, and runoff.
%
% Important:
%   This file is self-contained.
%   All MATLAB files and outputs remain in the same project folder.

clear;
clc;
close all;

fprintf('\n============================================================\n');
fprintf(' V3 ROBUST PPO IRRIGATION CONTROLLER - MATLAB R2023b\n');
fprintf('============================================================\n\n');

%% ============================================================
%  USER SETTINGS
% =============================================================

TRAIN_NEW_AGENT = true;

agentFile = 'V3_04_PPO_TrainedAgent.mat';
resultFile = 'V3_04_PPO_RobustIrrigationController_Results.mat';

% Simulation
dt = 0.25;                 % day
T_eval = 120;              % evaluation horizon, day

% Training horizon
T_train = 120;             % full seasonal horizon
N_train = round(T_train/dt);

% PPO training
numEpisodes = 300;

% Action limits
uMin = 0.0;                % mm/day
uMax = 12.0;               % mm/day

% Root-zone target
thetaTarget = 0.205;
thetaLower  = 0.180;
thetaUpper  = 0.230;

% Plant parameters
theta_r  = 0.078;
theta_s  = 0.430;
theta_FC = 0.250;
theta_WP = 0.120;

Z = [0.10; 0.20; 0.30];

% Hydraulic parameters
kp12 = 0.80;
kp23 = 0.50;
kp3d = 0.20;
Kinf = 0.020;

% ET
ET_potential = 4.0;        % mm/day
ET_fraction = [0.50; 0.30; 0.20];

% Initial state
theta0 = [0.20; 0.20; 0.20];

% Uncertainty ranges
FC_range  = [0.225 0.275];
WP_range  = [0.108 0.132];
kp3d_range = [0.160 0.240];

rng(10,'twister');

fprintf('PPO TRAINING SETTINGS\n');
fprintf('Training episodes = %d\n',numEpisodes);
fprintf('Training horizon  = %.1f days\n',T_train);
fprintf('Time step         = %.2f day\n',dt);
fprintf('Steps/episode     = %d\n',N_train);
fprintf('Action limits     = [%.1f, %.1f] mm/day\n',uMin,uMax);
fprintf('Target theta      = %.3f\n',thetaTarget);
fprintf('Target band       = [%.3f, %.3f]\n',thetaLower,thetaUpper);

fprintf('Domain randomization:\n');
fprintf('theta_FC = [%.3f, %.3f]\n',FC_range(1),FC_range(2));
fprintf('theta_WP = [%.3f, %.3f]\n',WP_range(1),WP_range(2));
fprintf('kp3d = [%.3f, %.3f]\n\n',kp3d_range(1),kp3d_range(2));

%% ============================================================
%  LOAD V3 BASELINE
% =============================================================

baselineFile = '01_ReducedSoilWaterModel_V3_Results.mat';

if exist(baselineFile,'file')

    D = load(baselineFile);

    if isfield(D,'results')
        baseline = D.results;
    else
        baseline = D;
    end

    fprintf('Validated V3 baseline loaded successfully.\n\n');

else

    error(['Required baseline file not found: ',baselineFile]);

end

%% ============================================================
%  RL TOOLBOX CHECK
% =============================================================

fprintf('Checking Reinforcement Learning Toolbox API...\n');

if exist('rlPPOAgent','class') ~= 8 && ...
        exist('rlPPOAgent','file') ~= 2

    error('Reinforcement Learning Toolbox / rlPPOAgent is not available.');

end

fprintf('Proceeding with PPO agent construction...\n\n');

%% ============================================================
%  OBSERVATION / ACTION SPECIFICATIONS
% ============================================================

% Observation vector:
%
% 1 theta1
% 2 theta2
% 3 theta3
% 4 root-zone theta
% 5 normalized time
% 6 theta_FC
% 7 theta_WP
% 8 kp3d
% 9 previous irrigation action

obsInfo = rlNumericSpec([9 1]);

obsInfo.Name = 'soil_observation';

obsInfo.LowerLimit = [ ...
    theta_r
    theta_r
    theta_r
    theta_r
    0
    FC_range(1)
    WP_range(1)
    kp3d_range(1)
    uMin];

obsInfo.UpperLimit = [ ...
    theta_s
    theta_s
    theta_s
    theta_s
    1
    FC_range(2)
    WP_range(2)
    kp3d_range(2)
    uMax];

actInfo = rlNumericSpec([1 1]);

actInfo.Name = 'irrigation_action';

actInfo.LowerLimit = uMin;
actInfo.UpperLimit = uMax;

%% ============================================================
%  BUILD OR LOAD PPO AGENT
% =============================================================

if TRAIN_NEW_AGENT || ~exist(agentFile,'file')

    %% --------------------------------------------------------
    %  ACTOR
    % ---------------------------------------------------------

    fprintf('Building PPO actor...\n');

    actorLG = layerGraph();

    actorInput = featureInputLayer(9, ...
        'Normalization','none', ...
        'Name','state');

    commonLayers = [
        fullyConnectedLayer(128,'Name','actor_fc1')
        reluLayer('Name','actor_relu1')
        fullyConnectedLayer(128,'Name','actor_fc2')
        reluLayer('Name','actor_relu2')
        fullyConnectedLayer(64,'Name','actor_fc3')
        reluLayer('Name','actor_relu3')
        ];

    actorLG = addLayers(actorLG,actorInput);
    actorLG = addLayers(actorLG,commonLayers);

    meanPath = [
        fullyConnectedLayer(32,'Name','mean_fc')
        reluLayer('Name','mean_relu')
        fullyConnectedLayer(1,'Name','mean_fc_out')
        tanhLayer('Name','mean_tanh')
        scalingLayer( ...
            'Name','mean_scaling', ...
            'Scale',uMax/2, ...
            'Bias',uMax/2)
        ];

    stdPath = [
        fullyConnectedLayer(32,'Name','std_fc')
        reluLayer('Name','std_relu')
        fullyConnectedLayer(1,'Name','std_fc_out')
        softplusLayer('Name','std_softplus')
        ];

    actorLG = addLayers(actorLG,meanPath);
    actorLG = addLayers(actorLG,stdPath);

    actorLG = connectLayers(actorLG,'state','actor_fc1');
    actorLG = connectLayers(actorLG,'actor_relu3','mean_fc');
    actorLG = connectLayers(actorLG,'actor_relu3','std_fc');

    actor = rlContinuousGaussianActor( ...
        actorLG, ...
        obsInfo, ...
        actInfo, ...
        'ObservationInputNames',{'state'}, ...
        'ActionMeanOutputNames',{'mean_scaling'}, ...
        'ActionStandardDeviationOutputNames',{'std_softplus'});

    %% --------------------------------------------------------
    %  CRITIC
    % ---------------------------------------------------------

    fprintf('Building PPO critic...\n');

    criticNetwork = [
        featureInputLayer(9, ...
            'Normalization','none', ...
            'Name','state')
        fullyConnectedLayer(128,'Name','critic_fc1')
        reluLayer('Name','critic_relu1')
        fullyConnectedLayer(128,'Name','critic_fc2')
        reluLayer('Name','critic_relu2')
        fullyConnectedLayer(64,'Name','critic_fc3')
        reluLayer('Name','critic_relu3')
        fullyConnectedLayer(1,'Name','value')
        ];

    critic = rlValueFunction( ...
        criticNetwork, ...
        obsInfo, ...
        'ObservationInputNames',{'state'});

    %% ========================================================
    %  ENVIRONMENT
    % ========================================================

    fprintf('Creating reinforcement-learning environment...\n');

    env = rlFunctionEnv( ...
        obsInfo, ...
        actInfo, ...
        @localStep, ...
        @localReset);

    fprintf('Environment created successfully.\n\n');

    %% ========================================================
    %  PPO OPTIONS
    % ========================================================

    agentOpts = rlPPOAgentOptions;

    agentOpts.SampleTime = dt;

    agentOpts.DiscountFactor = 0.995;

    agentOpts.ExperienceHorizon = 512;

    agentOpts.MiniBatchSize = 256;

    agentOpts.NumEpoch = 5;

    agentOpts.ClipFactor = 0.20;

    agentOpts.EntropyLossWeight = 0.005;

    agentOpts.ActorOptimizerOptions.LearnRate = 3e-4;
    agentOpts.ActorOptimizerOptions.GradientThreshold = 1;

    agentOpts.CriticOptimizerOptions.LearnRate = 1e-3;
    agentOpts.CriticOptimizerOptions.GradientThreshold = 1;

    fprintf('Creating new PPO agent...\n');

    agent = rlPPOAgent(actor,critic,agentOpts);

    %% ========================================================
    %  TRAINING
    % ========================================================

    fprintf('\n============================================================\n');
    fprintf(' STARTING PPO TRAINING\n');
    fprintf('============================================================\n\n');

    trainOpts = rlTrainingOptions;

    trainOpts.MaxEpisodes = numEpisodes;

    trainOpts.MaxStepsPerEpisode = N_train;

    trainOpts.ScoreAveragingWindowLength = 20;

    trainOpts.Verbose = true;

    trainOpts.Plots = 'training-progress';

    trainOpts.StopTrainingCriteria = 'none';

    trainingStats = train(agent,env,trainOpts);

    fprintf('\nPPO training completed.\n');

    save(agentFile,'agent','trainingStats','-v7.3');

    fprintf('Trained PPO agent saved to:\n%s\n\n',agentFile);

else

    %% --------------------------------------------------------
    %  LOAD EXISTING AGENT
    % ---------------------------------------------------------

    fprintf('Loading existing trained PPO agent...\n');

    Dagent = load(agentFile);

    agent = Dagent.agent;

    if isfield(Dagent,'trainingStats')
        trainingStats = Dagent.trainingStats;
    else
        trainingStats = [];
    end

    fprintf('Existing PPO agent loaded successfully.\n\n');

end

%% ============================================================
%  DETERMINISTIC EVALUATION
% =============================================================

agent.UseExplorationPolicy = false;

fprintf('============================================================\n');
fprintf(' PPO EVALUATION\n');
fprintf('============================================================\n\n');

% Evaluation scenarios
scenarioNames = { ...
    'Nominal'
    'Dry'
    'Wet'
    'Low drainage'
    'High drainage'
    'Combined'};

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
    0.200
    0.200
    0.200
    0.160
    0.240
    0.240];

numScenarios = numel(scenarioNames);

results = struct([]);

for s = 1:numScenarios

    fprintf('\n--------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n',s,numScenarios,scenarioNames{s});
    fprintf('--------------------------------------------\n');

    thetaFC_s = scenarioFC(s);
    thetaWP_s = scenarioWP(s);
    kp3d_s = scenarioKp3d(s);

    % Run one deterministic 120-day episode
    [obs,~] = localReset();

    N = round(T_eval/dt) + 1;
    time = (0:N-1)'*dt;

    thetaHist = zeros(N,3);
    S_hist = zeros(N,3);

    irrigation = zeros(N,1);
    infiltration = zeros(N,1);
    runoff = zeros(N,1);

    ET_actual = zeros(N,3);

    q12 = zeros(N,1);
    q23 = zeros(N,1);
    q3d = zeros(N,1);

    soilStress = zeros(N,3);

    thetaHist(1,:) = theta0';
    S_hist(1,:) = (theta0 .* Z)';

    previousAction = 0;

    % Scenario-specific initial observation
    root0 = sum(theta0 .* Z)/sum(Z);

    obs = [ ...
        theta0
        root0
        0
        thetaFC_s
        thetaWP_s
        kp3d_s
        previousAction];

    for k = 1:N-1

        % -----------------------------------------------------
        % PPO ACTION
        % -----------------------------------------------------

        action = getAction(agent,{obs});

        if iscell(action)
            action = action{1};
        end

        action = double(action);

        if isempty(action)
            action = 0;
        end

        action = action(1);

        % Saturate action
        action = min(max(action,uMin),uMax);

        irrigation(k) = action;

        % -----------------------------------------------------
        % PLANT STEP
        % -----------------------------------------------------

        [Snew,flux,ETlayer] = localPlantStep( ...
            S_hist(k,:)', ...
            action, ...
            thetaFC_s, ...
            thetaWP_s, ...
            kp3d_s);

        S_hist(k+1,:) = Snew';

        thetaHist(k+1,:) = (Snew ./ Z)';

        infiltration(k) = flux.infiltration;
        runoff(k) = flux.runoff;

        q12(k) = flux.q12;
        q23(k) = flux.q23;
        q3d(k) = flux.q3d;

        ET_actual(k,:) = ETlayer';

        thetaCurrent = Snew ./ Z;

        stress = ...
            (thetaCurrent-thetaWP_s) ./ ...
            (thetaFC_s-thetaWP_s);

        stress = min(max(stress,0),1);

        soilStress(k+1,:) = stress';

        % -----------------------------------------------------
        % NEXT OBSERVATION
        % -----------------------------------------------------

        rootTheta = sum(thetaCurrent .* Z)/sum(Z);

        normalizedTime = time(k+1)/T_eval;

        obs = [ ...
            thetaCurrent
            rootTheta
            normalizedTime
            thetaFC_s
            thetaWP_s
            kp3d_s
            action];

        previousAction = action;

    end

    % ---------------------------------------------------------
    % FINAL STEP VALUES
    % ---------------------------------------------------------

    ET_actual(end,:) = ET_actual(end-1,:);
    infiltration(end) = infiltration(end-1);
    runoff(end) = runoff(end-1);
    q12(end) = q12(end-1);
    q23(end) = q23(end-1);
    q3d(end) = q3d(end-1);

    % ---------------------------------------------------------
    % METRICS
    % ---------------------------------------------------------

    rootTheta = ...
        (thetaHist(:,1)*Z(1) + ...
         thetaHist(:,2)*Z(2) + ...
         thetaHist(:,3)*Z(3)) / sum(Z);

    ET_total = sum(ET_actual,2);

    storageTotal = sum(S_hist,2);

    totalIrrigation_mm = sum(irrigation(1:N-1))*dt;

    totalInfiltration_mm = ...
        sum(infiltration(1:N-1))*dt*1000;

    totalRunoff_mm = ...
        sum(runoff(1:N-1))*dt*1000;

    totalET_mm = ...
        sum(ET_total(1:N-1))*dt*1000;

    totalDrainage_mm = ...
        sum(q3d(1:N-1))*dt*1000;

    initialStorage_mm = storageTotal(1)*1000;

    finalStorage_mm = storageTotal(end)*1000;

    % ---------------------------------------------------------
    % ROOT-ZONE PERFORMANCE
    % ---------------------------------------------------------

    rmse = sqrt(mean((rootTheta-thetaTarget).^2));

    stressMask = rootTheta < thetaWP_s;

    aboveMask = rootTheta > thetaUpper;

    insideMask = ...
        rootTheta >= thetaLower & ...
        rootTheta <= thetaUpper;

    timeUnderStress = sum(stressMask)*dt;

    timeAboveBand = sum(aboveMask)*dt;

    timeInsideBand = sum(insideMask)*dt;

    meanTheta = mean(rootTheta);

    minTheta = min(rootTheta);

    maxTheta = max(rootTheta);

    meanStress = mean( ...
        min(max( ...
        (rootTheta-thetaWP_s)/ ...
        (thetaFC_s-thetaWP_s),0),1));

    % ---------------------------------------------------------
    % WATER BALANCE
    % ---------------------------------------------------------

    % Independent total balance:
    %
    % final storage =
    % initial storage
    % + infiltration
    % - runoff
    % - ET
    % - deep drainage

    expectedFinalStorage_m = ...
        storageTotal(1) ...
        + sum(infiltration(1:N-1))*dt ...
        - sum(runoff(1:N-1))*dt ...
        - sum(ET_total(1:N-1))*dt ...
        - sum(q3d(1:N-1))*dt;

    balanceError_m = ...
        storageTotal(end) - expectedFinalStorage_m;

    balanceError_mm = balanceError_m*1000;

    % ---------------------------------------------------------
    % INTERVAL WATER BALANCE
    % ---------------------------------------------------------

    intervalBalance = zeros(N-1,1);

    for k = 1:N-1

        storageChange = ...
            storageTotal(k+1)-storageTotal(k);

        netFlux = ...
            infiltration(k) ...
            - runoff(k) ...
            - ET_total(k) ...
            - q3d(k);

        intervalBalance(k) = ...
            storageChange - netFlux*dt;

    end

    maxIntervalBalanceError_mm = ...
        max(abs(intervalBalance))*1000;

    % ---------------------------------------------------------
    % PHYSICAL VALIDATION
    % ---------------------------------------------------------

    S_min = theta_r .* Z;
    S_max = theta_s .* Z;

    thetaPass = ...
        all(thetaHist(:) >= theta_r-1e-10) && ...
        all(thetaHist(:) <= theta_s+1e-10);

    storagePass = ...
        all(S_hist >= repmat(S_min',N,1)-1e-10,'all') && ...
        all(S_hist <= repmat(S_max',N,1)+1e-10,'all');

    fluxPass = ...
        all(infiltration(1:N-1) >= -1e-12) && ...
        all(runoff(1:N-1) >= -1e-12) && ...
        all(ET_actual(1:N-1,:) >= -1e-12,'all') && ...
        all(q12(1:N-1) >= -1e-12) && ...
        all(q23(1:N-1) >= -1e-12) && ...
        all(q3d(1:N-1) >= -1e-12);

    irrigationPass = ...
        all(irrigation(1:N-1) >= uMin-1e-10) && ...
        all(irrigation(1:N-1) <= uMax+1e-10);

    balancePass = ...
        isfinite(balanceError_mm) && ...
        abs(balanceError_mm) <= 1e-5 && ...
        maxIntervalBalanceError_mm <= 1e-5;

    overallPass = ...
        thetaPass && ...
        storagePass && ...
        fluxPass && ...
        irrigationPass && ...
        balancePass;

    % ---------------------------------------------------------
    % SAVE SCENARIO RESULTS
    % ---------------------------------------------------------

    results(s).name = scenarioNames{s};

    results(s).theta = thetaHist;

    results(s).storage = S_hist;

    results(s).storageTotal = storageTotal;

    results(s).rootTheta = rootTheta;

    results(s).irrigation = irrigation;

    results(s).infiltration = infiltration;

    results(s).runoff = runoff;

    results(s).ET_actual = ET_actual;

    results(s).ET_total = ET_total;

    results(s).q12 = q12;

    results(s).q23 = q23;

    results(s).q3d = q3d;

    results(s).soilStress = soilStress;

    results(s).time = time;

    results(s).thetaFC = thetaFC_s;

    results(s).thetaWP = thetaWP_s;

    results(s).kp3d = kp3d_s;

    results(s).totalIrrigation_mm = totalIrrigation_mm;

    results(s).totalInfiltration_mm = totalInfiltration_mm;

    results(s).totalRunoff_mm = totalRunoff_mm;

    results(s).totalET_mm = totalET_mm;

    results(s).totalDrainage_mm = totalDrainage_mm;

    results(s).initialStorage_mm = initialStorage_mm;

    results(s).finalStorage_mm = finalStorage_mm;

    results(s).RMSE = rmse;

    results(s).timeUnderStress = timeUnderStress;

    results(s).timeAboveBand = timeAboveBand;

    results(s).timeInsideBand = timeInsideBand;

    results(s).meanTheta = meanTheta;

    results(s).minTheta = minTheta;

    results(s).maxTheta = maxTheta;

    results(s).meanStress = meanStress;

    results(s).balanceError_mm = balanceError_mm;

    results(s).maxIntervalBalanceError_mm = ...
        maxIntervalBalanceError_mm;

    results(s).thetaPass = thetaPass;

    results(s).storagePass = storagePass;

    results(s).fluxPass = fluxPass;

    results(s).irrigationPass = irrigationPass;

    results(s).balancePass = balancePass;

    results(s).overallPass = overallPass;

    % ---------------------------------------------------------
    % CONSOLE OUTPUT
    % ---------------------------------------------------------

    fprintf('Total irrigation       = %.6f mm\n', ...
        totalIrrigation_mm);

    fprintf('Actual ET              = %.6f mm\n', ...
        totalET_mm);

    fprintf('Deep drainage          = %.6f mm\n', ...
        totalDrainage_mm);

    fprintf('Runoff                 = %.6f mm\n', ...
        totalRunoff_mm);

    fprintf('Total infiltration     = %.6f mm\n', ...
        totalInfiltration_mm);

    fprintf('Initial storage        = %.6f mm\n', ...
        initialStorage_mm);

    fprintf('Final storage          = %.6f mm\n', ...
        finalStorage_mm);

    fprintf('Root-zone RMSE         = %.6f\n',rmse);

    fprintf('Time under stress      = %.2f days\n', ...
        timeUnderStress);

    fprintf('Time above target band = %.2f days\n', ...
        timeAboveBand);

    fprintf('Time inside target     = %.2f days\n', ...
        timeInsideBand);

    fprintf('Mean theta             = %.6f\n',meanTheta);

    fprintf('Min theta              = %.6f\n',minTheta);

    fprintf('Max theta              = %.6f\n',maxTheta);

    fprintf('Mean stress            = %.6f\n',meanStress);

    fprintf('Water balance error    = %.6e mm\n', ...
        balanceError_mm);

    fprintf('Max interval WB error  = %.6e mm\n', ...
        maxIntervalBalanceError_mm);

end

%% ============================================================
%  SAVE RESULTS
% =============================================================

save(resultFile, ...
    'results', ...
    'scenarioNames', ...
    'scenarioFC', ...
    'scenarioWP', ...
    'scenarioKp3d', ...
    'thetaTarget', ...
    'thetaLower', ...
    'thetaUpper', ...
    'uMin', ...
    'uMax', ...
    'dt', ...
    'T_eval', ...
    'theta_r', ...
    'theta_s', ...
    'theta0', ...
    'Z', ...
    'kp12', ...
    'kp23', ...
    'Kinf', ...
    'ET_potential', ...
    'ET_fraction', ...
    '-v7.3');

%% ============================================================
%  PHYSICAL VALIDATION REPORT
% =============================================================

fprintf('\n============================================================\n');
fprintf(' PPO PHYSICAL VALIDATION\n');
fprintf('============================================================\n');

allPass = true;

for s = 1:numScenarios

    fprintf('%-16s | Theta=%d | Storage=%d | Flux=%d | Irrigation=%d | Balance=%d | Overall=%d\n', ...
        scenarioNames{s}, ...
        results(s).thetaPass, ...
        results(s).storagePass, ...
        results(s).fluxPass, ...
        results(s).irrigationPass, ...
        results(s).balancePass, ...
        results(s).overallPass);

    allPass = allPass && results(s).overallPass;

end

if allPass
    fprintf('\nOVERALL PPO VALIDATION: PASS\n');
else
    fprintf('\nOVERALL PPO VALIDATION: FAIL\n');
end

%% ============================================================
%  FIGURE 1 - ROOT-ZONE MOISTURE
% =============================================================

figure('Name','PPO Root-Zone Moisture','Color','w');

hold on;

for s = 1:numScenarios
    plot(results(s).time,results(s).rootTheta,'LineWidth',1.3);
end

yline(thetaTarget,'--','Target');
yline(thetaLower,':','Lower bound');
yline(thetaUpper,':','Upper bound');

xlabel('Time (days)');
ylabel('\theta_{root}');

title('Robust PPO Root-Zone Moisture');

legend(scenarioNames,'Location','best');

grid on;
box on;

saveas(gcf,'19_V3_PPO_RootZoneMoisture.png');

%% ============================================================
%  FIGURE 2 - IRRIGATION
% =============================================================

figure('Name','PPO Irrigation','Color','w');

hold on;

for s = 1:numScenarios
    stairs(results(s).time,results(s).irrigation, ...
        'LineWidth',1.1);
end

xlabel('Time (days)');
ylabel('Irrigation (mm/day)');

title('Robust PPO Irrigation Actions');

legend(scenarioNames,'Location','best');

grid on;
box on;

saveas(gcf,'20_V3_PPO_Irrigation.png');

%% ============================================================
%  FIGURE 3 - CUMULATIVE IRRIGATION
% =============================================================

figure('Name','PPO Cumulative Irrigation','Color','w');

hold on;

for s = 1:numScenarios

    cumulativeIrrigation = ...
        cumsum(results(s).irrigation)*dt;

    plot(results(s).time,cumulativeIrrigation, ...
        'LineWidth',1.3);

end

xlabel('Time (days)');
ylabel('Cumulative irrigation (mm)');

title('Cumulative PPO Irrigation');

legend(scenarioNames,'Location','best');

grid on;
box on;

saveas(gcf,'21_V3_PPO_CumulativeIrrigation.png');

%% ============================================================
%  FIGURE 4 - PERFORMANCE SUMMARY
% =============================================================

figure('Name','PPO Performance Summary','Color','w');

metricMatrix = [ ...
    [results.totalIrrigation_mm]' ...
    [results.totalET_mm]' ...
    [results.totalDrainage_mm]' ...
    [results.totalRunoff_mm]' ...
    [results.RMSE]' ];

bar(metricMatrix);

xlabel('Scenario');
ylabel('Metric value');

title('PPO Performance Summary');

legend( ...
    'Irrigation (mm)', ...
    'ET (mm)', ...
    'Drainage (mm)', ...
    'Runoff (mm)', ...
    'Root-zone RMSE', ...
    'Location','best');

xticks(1:numScenarios);
xticklabels(scenarioNames);

grid on;
box on;

saveas(gcf,'22_V3_PPO_PerformanceSummary.png');

%% ============================================================
%  FIGURE 5 - FINAL STORAGE
% =============================================================

figure('Name','PPO Final Storage','Color','w');

finalStorage = [results.finalStorage_mm];

bar(finalStorage);

xlabel('Scenario');
ylabel('Final storage (mm)');

title('PPO Final Soil-Water Storage');

xticks(1:numScenarios);
xticklabels(scenarioNames);

grid on;
box on;

saveas(gcf,'23_V3_PPO_FinalStorage.png');

%% ============================================================
%  FINAL CONSOLE SUMMARY
% =============================================================

fprintf('\n============================================================\n');
fprintf(' PPO CONTROLLER COMPLETE\n');
fprintf('============================================================\n');

fprintf('\nFinal PPO results:\n\n');

fprintf('%-16s %12s %12s %12s %12s %12s\n', ...
    'Scenario','Irrigation','ET','Drainage','RMSE','WB Error');

fprintf('%-16s %12s %12s %12s %12s %12s\n', ...
    '----------------', ...
    '------------', ...
    '------------', ...
    '------------', ...
    '------------', ...
    '------------');

for s = 1:numScenarios

    fprintf('%-16s %12.3f %12.3f %12.3f %12.5f %12.5f\n', ...
        scenarioNames{s}, ...
        results(s).totalIrrigation_mm, ...
        results(s).totalET_mm, ...
        results(s).totalDrainage_mm, ...
        results(s).RMSE, ...
        results(s).balanceError_mm);

end

fprintf('\nResults saved:\n');
fprintf('%s\n',resultFile);
fprintf('%s\n',agentFile);
fprintf('19_V3_PPO_RootZoneMoisture.png\n');
fprintf('20_V3_PPO_Irrigation.png\n');
fprintf('21_V3_PPO_CumulativeIrrigation.png\n');
fprintf('22_V3_PPO_PerformanceSummary.png\n');
fprintf('23_V3_PPO_FinalStorage.png\n');

fprintf('\n============================================================\n');
fprintf(' END\n');
fprintf('============================================================\n');


%% ========================================================================
%  LOCAL RESET FUNCTION
% ========================================================================

function [obs,loggedSignals] = localReset()

    % Global parameters are accessed through nested/shared workspace
    % variables defined below using persistent configuration.

    theta_r = 0.078;

    theta0 = [0.20;0.20;0.20];

    thetaFC = 0.250;
    thetaWP = 0.120;
    kp3d = 0.200;

    Z = [0.10;0.20;0.30];

    rootTheta = sum(theta0.*Z)/sum(Z);

    obs = [ ...
        theta0
        rootTheta
        0
        thetaFC
        thetaWP
        kp3d
        0];

    loggedSignals.state = theta0;

    loggedSignals.thetaFC = ...
        0.225 + rand*(0.275-0.225);

    loggedSignals.thetaWP = ...
        0.108 + rand*(0.132-0.108);

    loggedSignals.kp3d = ...
        0.160 + rand*(0.240-0.160);

    loggedSignals.state = theta0;

    loggedSignals.time = 0;

    loggedSignals.previousAction = 0;

    loggedSignals.done = false;

end


%% ========================================================================
%  LOCAL STEP FUNCTION
% ========================================================================

function [nextObs,reward,isDone,loggedSignals] = ...
    localStep(action,loggedSignals)

    % Plant constants
    theta_r = 0.078;
    theta_s = 0.430;

    thetaFC = loggedSignals.thetaFC;
    thetaWP = loggedSignals.thetaWP;
    kp3d = loggedSignals.kp3d;

    Z = [0.10;0.20;0.30];

    kp12 = 0.80;
    kp23 = 0.50;
    Kinf = 0.020;

    ET_potential = 4.0;

    ET_fraction = [0.50;0.30;0.20];

    dt = 0.25;

    T_episode = 120;

    thetaTarget = 0.205;

    thetaLower = 0.180;

    thetaUpper = 0.230;

    uMin = 0;

    uMax = 12;

    % -------------------------------------------------------------
    % ACTION
    % -------------------------------------------------------------

    if iscell(action)
        action = action{1};
    end

    action = double(action);

    if isempty(action)
        action = 0;
    end

    action = action(1);

    action = min(max(action,uMin),uMax);

    % -------------------------------------------------------------
    % CURRENT STATE
    % -------------------------------------------------------------

    thetaCurrent = loggedSignals.state;

    S_current = thetaCurrent .* Z;

    % -------------------------------------------------------------
    % PLANT STEP
    % -------------------------------------------------------------

    [Snew,flux,ETlayer] = localPlantStep( ...
        S_current, ...
        action, ...
        thetaFC, ...
        thetaWP, ...
        kp3d);

    thetaNew = Snew ./ Z;

    rootTheta = sum(thetaNew.*Z)/sum(Z);

    % -------------------------------------------------------------
    % REWARD
    % -------------------------------------------------------------

    trackingError = rootTheta-thetaTarget;

    lowerViolation = max(0,thetaLower-rootTheta);

    upperViolation = max(0,rootTheta-thetaUpper);

    stressViolation = max(0,thetaWP-rootTheta);

    % Reward components
    %
    % Strong moisture regulation
    trackingPenalty = 3000*(trackingError^2);

    % Strong protection against leaving target band
    lowerPenalty = 15000*(lowerViolation^2);

    upperPenalty = 8000*(upperViolation^2);

    % Explicit penalty for entering water-stress region
    stressPenalty = 30000*(stressViolation^2);

    % Irrigation cost
    irrigationPenalty = 0.20*(action/uMax);

    % Drainage and runoff penalties
    drainagePenalty = 2500*(flux.q3d*1000)^2;

    runoffPenalty = 2500*(flux.runoff*1000)^2;

    % Large penalty for excessive irrigation
    excessiveWaterPenalty = ...
        0.10*(max(0,action-6)/uMax)^2;

    reward = ...
        -trackingPenalty ...
        -lowerPenalty ...
        -upperPenalty ...
        -stressPenalty ...
        -irrigationPenalty ...
        -drainagePenalty ...
        -runoffPenalty ...
        -excessiveWaterPenalty;

    % Small positive reward for staying inside target band
    if rootTheta >= thetaLower && ...
            rootTheta <= thetaUpper

        reward = reward + 1.0;

    end

    % -------------------------------------------------------------
    % UPDATE LOGGED SIGNALS
    % -------------------------------------------------------------

    loggedSignals.state = thetaNew;

    loggedSignals.time = ...
        loggedSignals.time + dt;

    loggedSignals.previousAction = action;

    % -------------------------------------------------------------
    % NEXT OBSERVATION
    % -------------------------------------------------------------

    normalizedTime = ...
        min(loggedSignals.time/T_episode,1);

    nextObs = [ ...
        thetaNew
        rootTheta
        normalizedTime
        thetaFC
        thetaWP
        kp3d
        action];

    % -------------------------------------------------------------
    % TERMINATION
    % -------------------------------------------------------------

    isDone = ...
        loggedSignals.time >= T_episode;

end


%% ========================================================================
%  EXACT V3 PLANT STEP
% ========================================================================

function [S_current,flux,ET_actual] = ...
    localPlantStep(S_current,irrigation_mm_day,thetaFC,thetaWP,kp3d)

    % Exact V3 reduced soil-water model structure.

    dt = 0.25;

    theta_r = 0.078;
    theta_s = 0.430;

    Z = [0.10;0.20;0.30];

    kp12 = 0.80;
    kp23 = 0.50;
    Kinf = 0.020;

    ET_potential = 4.0;

    ET_fraction = [0.50;0.30;0.20];

    S_min = theta_r .* Z;

    S_max = theta_s .* Z;

    S_FC = thetaFC .* Z;

    S_WP = thetaWP .* Z;

    % -------------------------------------------------------------
    % EXTERNAL INPUT
    % -------------------------------------------------------------

    water_input = irrigation_mm_day/1000;

    % No rainfall in the controlled experiment
    P = 0;

    water_input = water_input + P;

    % -------------------------------------------------------------
    % INFILTRATION
    % -------------------------------------------------------------

    current_theta1 = S_current(1)/Z(1);

    remaining_capacity = ...
        S_max(1)-S_current(1);

    saturation_factor = ...
        (theta_s-current_theta1) / ...
        (theta_s-thetaFC);

    saturation_factor = ...
        min(max(saturation_factor,0),1);

    infiltration_capacity = ...
        Kinf*saturation_factor;

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
        S_current(1) + actual_infiltration*dt;

    % -------------------------------------------------------------
    % SOIL WATER STRESS
    % -------------------------------------------------------------

    theta_current = S_current./Z;

    stress = ...
        (theta_current-thetaWP) ./ ...
        (thetaFC-thetaWP);

    stress = ...
        min(max(stress,0),1);

    % -------------------------------------------------------------
    % ET
    % -------------------------------------------------------------

    ET_demand = ...
        (ET_potential/1000) .* ...
        ET_fraction .* ...
        stress;

    ET_actual = zeros(3,1);

    for i = 1:3

        available_water = ...
            max(0,S_current(i)-S_min(i));

        ET_remove = ...
            min(ET_demand(i)*dt,available_water);

        S_current(i) = ...
            S_current(i)-ET_remove;

        ET_actual(i) = ...
            ET_remove/dt;

    end

    % -------------------------------------------------------------
    % LAYER 1 -> LAYER 2
    % -------------------------------------------------------------

    excess1 = ...
        max(0,S_current(1)-S_FC(1));

    potential_q12 = ...
        kp12*excess1;

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

    q12 = transfer12/dt;

    % -------------------------------------------------------------
    % LAYER 2 -> LAYER 3
    % -------------------------------------------------------------

    excess2 = ...
        max(0,S_current(2)-S_FC(2));

    potential_q23 = ...
        kp23*excess2;

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

    q23 = transfer23/dt;

    % -------------------------------------------------------------
    % DEEP DRAINAGE
    % -------------------------------------------------------------

    excess3 = ...
        max(0,S_current(3)-S_FC(3));

    potential_q3d = ...
        kp3d*excess3;

    max_drainage = ...
        S_current(3)-S_min(3);

    drainage = ...
        min(potential_q3d*dt,max_drainage);

    drainage = ...
        max(drainage,0);

    S_current(3) = ...
        S_current(3)-drainage;

    q3d = drainage/dt;

    % -------------------------------------------------------------
    % PHYSICAL BOUNDS
    % -------------------------------------------------------------

    S_current = ...
        min(max(S_current,S_min),S_max);

    % -------------------------------------------------------------
    % OUTPUT FLUXES
    % -------------------------------------------------------------

    flux.infiltration = actual_infiltration;

    flux.runoff = runoff;

    flux.q12 = q12;

    flux.q23 = q23;

    flux.q3d = q3d;

end