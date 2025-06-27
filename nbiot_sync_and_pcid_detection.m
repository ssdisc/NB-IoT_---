%% NB-IoT下行信号同步与PCID检测脚本
% 功能：实现NB-IoT下行信号同步，绘制相关峰图，检测小区编号PCID
% 作者：AI Assistant
% 日期：2024

clear; clc; close all;

%% 1. 加载NB-IoT信号数据
fprintf('正在加载NB-IoT信号数据...\n');
try
    load('..\nbiot_received_signal.mat');
    % 假设变量名为signal，如果不是请根据实际情况修改
    if exist('signal', 'var')
        rxWaveform = signal;
    elseif exist('rxWaveform', 'var')
        % 变量已经是rxWaveform
    else
        % 尝试获取第一个变量
        vars = whos;
        rxWaveform = eval(vars(1).name);
    end
    fprintf('数据加载成功，信号长度: %d 采样点\n', length(rxWaveform));
catch ME
    error('无法加载数据文件: %s', ME.message);
end

%% 2. NB-IoT系统参数配置
fprintf('配置NB-IoT系统参数...\n');

% NB-IoT下行配置
enb = struct();
enb.NBRefP = 1;           % 天线端口数 (1 or 2)
enb.NNCellID = [];        % 小区ID，待检测
enb.NBULSubcarrierSpacing = '15kHz';  % 子载波间隔
enb.OperationMode = 'Standalone';     % 操作模式

% 采样率配置
samplingRate = 1.92e6;    % 1.92 MHz采样率 (NB-IoT典型值)

%% 3. 优化的PCID检测 - 多阶段检测策略
fprintf('开始优化的PCID检测...\n');

% 采用多阶段检测策略提高效率：
% 阶段1：快速粗略检测 - 检测常见PCID
% 阶段2：候选PCID精确检测
% 阶段3：如果需要，扩展搜索

% NB-IoT支持的小区ID范围是0-503
allPCIDs = 0:503;
correlationResults = zeros(size(allPCIDs));
frameOffsets = zeros(size(allPCIDs));

% 阶段1：快速粗略检测 - 检测常见的PCID
fprintf('阶段1：快速粗略检测...\n');

% 常见PCID：通常基站会使用0-167的PCID（168的倍数）
commonPCIDs = [0:10:100, 150:5:200, 250:10:350, 400:20:503]; % 约50个常见值
commonPCIDs = unique(commonPCIDs(commonPCIDs <= 503)); % 确保在有效范围内

fprintf('检测%d个常见PCID...\n', length(commonPCIDs));
tic;

maxCorrelation = 0;
bestPCID = 0;
bestOffset = 0;
candidatePCIDs = [];
candidateCorrelations = [];

for pcid = commonPCIDs
    try
        % 设置当前测试的小区ID
        enb.NNCellID = pcid;

        % 检测帧偏移和相关性
        [frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);
        
        corrValue = max(abs(correlation));
        idx = find(allPCIDs == pcid);
        correlationResults(idx) = corrValue;
        frameOffsets(idx) = frameOffset;

        % 记录最佳结果
        if corrValue > maxCorrelation
            maxCorrelation = corrValue;
            bestPCID = pcid;
            bestOffset = frameOffset;
        end

        % 收集候选PCID（相关值超过阈值的）
        if corrValue > 0.05  % 动态阈值
            candidatePCIDs(end+1) = pcid;
            candidateCorrelations(end+1) = corrValue;
        end

    catch
        % 如果某个PCID检测失败，继续下一个
        idx = find(allPCIDs == pcid);
        correlationResults(idx) = 0;
        frameOffsets(idx) = 0;
    end
end

stage1Time = toc;
fprintf('阶段1完成，耗时: %.2f 秒\n', stage1Time);
fprintf('最佳候选PCID: %d，相关值: %.4f\n', bestPCID, maxCorrelation);
fprintf('发现%d个候选PCID\n', length(candidatePCIDs));

% 判断是否需要进行阶段2和3
needStage2 = (maxCorrelation < 0.3) || (length(candidatePCIDs) > 3);
needStage3 = (maxCorrelation < 0.15);

if needStage2
    % 阶段2：候选PCID邻域搜索
    fprintf('\n阶段2：候选PCID邻域搜索...\n');
    
    % 对每个候选PCID搜索其邻域
    neighborPCIDs = [];
    for pcid = candidatePCIDs
        % 搜索±10范围内的PCID
        neighbors = max(0, pcid-10):min(503, pcid+10);
        neighborPCIDs = [neighborPCIDs, neighbors];
    end
    
    % 去重并排除已经检测过的
    neighborPCIDs = unique(neighborPCIDs);
    neighborPCIDs = setdiff(neighborPCIDs, commonPCIDs);
    
    fprintf('检测%d个邻域PCID...\n', length(neighborPCIDs));
    tic;
    
    for pcid = neighborPCIDs
        try
            enb.NNCellID = pcid;
            [frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);
            
            corrValue = max(abs(correlation));
            idx = find(allPCIDs == pcid);
            correlationResults(idx) = corrValue;
            frameOffsets(idx) = frameOffset;
            
            if corrValue > maxCorrelation
                maxCorrelation = corrValue;
                bestPCID = pcid;
                bestOffset = frameOffset;
            end
            
        catch
            idx = find(allPCIDs == pcid);
            correlationResults(idx) = 0;
            frameOffsets(idx) = 0;
        end
    end
    
    stage2Time = toc;
    fprintf('阶段2完成，耗时: %.2f 秒\n', stage2Time);
    fprintf('当前最佳PCID: %d，相关值: %.4f\n', bestPCID, maxCorrelation);
else
    stage2Time = 0;
    neighborPCIDs = [];
    fprintf('跳过阶段2（检测质量良好）\n');
end

if needStage3 && maxCorrelation < 0.15
    % 阶段3：完整搜索（仅在前两阶段效果不佳时执行）
    fprintf('\n阶段3：完整搜索（信号质量较差）...\n');
    
    % 获取尚未检测的PCID
    testedPCIDs = [commonPCIDs, neighborPCIDs];
    remainingPCIDs = setdiff(allPCIDs, testedPCIDs);
    
    fprintf('检测剩余%d个PCID...\n', length(remainingPCIDs));
    tic;
    
    progressStep = max(1, round(length(remainingPCIDs) / 10));
    
    for idx = 1:length(remainingPCIDs)
        pcid = remainingPCIDs(idx);
        
        % 显示进度
        if mod(idx, progressStep) == 0
            fprintf('阶段3进度: %d%% (%d/%d)\n', round(idx/length(remainingPCIDs)*100), idx, length(remainingPCIDs));
        end
        
        try
            enb.NNCellID = pcid;
            [frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);
            
            corrValue = max(abs(correlation));
            pcidIdx = find(allPCIDs == pcid);
            correlationResults(pcidIdx) = corrValue;
            frameOffsets(pcidIdx) = frameOffset;
            
            if corrValue > maxCorrelation
                maxCorrelation = corrValue;
                bestPCID = pcid;
                bestOffset = frameOffset;
            end
            
        catch
            pcidIdx = find(allPCIDs == pcid);
            correlationResults(pcidIdx) = 0;
            frameOffsets(pcidIdx) = 0;
        end
    end
    
    stage3Time = toc;
    fprintf('阶段3完成，耗时: %.2f 秒\n', stage3Time);
else
    stage3Time = 0;
    fprintf('跳过阶段3（检测质量足够）\n');
end

pcidDetectionTime = stage1Time + stage2Time + stage3Time;

%% 4. 优化PCID检测结果
fprintf('PCID检测完成，总耗时: %.2f 秒\n', pcidDetectionTime);

% 使用已经找到的最佳结果
detectedPCID = bestPCID;
detectedOffset = bestOffset;

fprintf('\n=== 优化PCID检测结果 ===\n');
fprintf('检测到的小区编号PCID: %d\n', detectedPCID);
fprintf('最大相关值: %.4f\n', maxCorrelation);
fprintf('帧偏移: %d 采样点\n', detectedOffset);

% 显示检测过程统计
testedCount = sum(correlationResults > 0);
fprintf('实际测试PCID数量: %d / %d (%.1f%%)\n', testedCount, length(allPCIDs), testedCount/length(allPCIDs)*100);
fprintf('检测策略效率提升: 约%.1fx\n', length(allPCIDs)/testedCount);

%% 5. 使用检测到的PCID进行精确同步
fprintf('\n正在进行精确同步...\n');
enb.NNCellID = detectedPCID;

% 重新计算帧偏移和相关性
[frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);

% 应用帧偏移校正
if frameOffset > 0
    syncedWaveform = rxWaveform(frameOffset+1:end);
else
    syncedWaveform = rxWaveform;
end

fprintf('同步完成，帧偏移: %d 采样点\n', frameOffset);

%% 6. 绘制优化PCID检测结果图
fprintf('绘制相关峰图...\n');

figure('Position', [100, 100, 1200, 800]);

% 子图1：PCID检测结果（只显示测试过的PCID）
subplot(2,2,1);
testedPCIDs = allPCIDs(correlationResults > 0);
testedCorrelations = correlationResults(correlationResults > 0);
plot(testedPCIDs, testedCorrelations, 'b-', 'LineWidth', 1);
hold on;
plot(detectedPCID, maxCorrelation, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('小区编号 PCID');
ylabel('相关值');
title(sprintf('优化PCID检测结果 (测试%d/%d个PCID)', length(testedPCIDs), length(allPCIDs)));
grid on;
legend('相关值', sprintf('检测到的PCID=%d', detectedPCID), 'Location', 'best');

% 子图2：最佳PCID的详细相关性
subplot(2,2,2);
correlationTimeSamples = (0:length(correlation)-1) / samplingRate * 1000; % 转换为毫秒
plot(correlationTimeSamples, abs(correlation), 'g-', 'LineWidth', 1.5);
xlabel('时间 (ms)');
ylabel('相关值幅度');
title(sprintf('PCID %d 的相关峰 (帧偏移=%d)', detectedPCID, frameOffset));
grid on;

% 子图3：原始信号时域
subplot(2,2,3);
timeSamples = (0:length(rxWaveform)-1) / samplingRate * 1000; % 转换为毫秒
plot(timeSamples(1:min(10000, end)), real(rxWaveform(1:min(10000, end))), 'b-');
xlabel('时间 (ms)');
ylabel('幅度');
title('原始接收信号 (实部)');
grid on;

% 子图4：同步后信号时域
subplot(2,2,4);
syncTimeSamples = (0:length(syncedWaveform)-1) / samplingRate * 1000;
plot(syncTimeSamples(1:min(10000, end)), real(syncedWaveform(1:min(10000, end))), 'r-');
xlabel('时间 (ms)');
ylabel('幅度');
title('同步后信号 (实部)');
grid on;

sgtitle('NB-IoT下行信号同步与PCID检测结果', 'FontSize', 14, 'FontWeight', 'bold');

%% 7. 生成PSS和SSS参考信号进行验证
fprintf('生成参考信号进行验证...\n');

try
    % 由于lteNBPSS和lteNBSSS函数不可用，使用标准LTE函数替代
    % NB-IoT的PCID映射到LTE的小区ID组

    % NB-IoT PCID到LTE参数的映射
    % NB-IoT使用不同的PCID范围，这里进行简化映射
    lteCellId = mod(detectedPCID, 504);  % 确保在LTE范围内

    % 生成标准LTE的PSS和SSS（作为参考）
    pssSeq = ltePSS(lteCellId);
    sssSeq = lteSSS(lteCellId);

    fprintf('使用标准LTE函数生成参考信号\n');
    fprintf('映射后的LTE小区ID: %d\n', lteCellId);
    fprintf('PSS序列长度: %d\n', length(pssSeq));
    fprintf('SSS序列长度: %d\n', length(sssSeq));

    % 绘制参考信号
    figure('Position', [150, 150, 1000, 600]);

    subplot(2,2,1);
    plot(real(pssSeq), 'b-o', 'MarkerSize', 4);
    xlabel('符号索引');
    ylabel('实部');
    title(sprintf('PSS序列 (映射PCID=%d->%d) - 实部', detectedPCID, lteCellId));
    grid on;

    subplot(2,2,2);
    plot(imag(pssSeq), 'r-o', 'MarkerSize', 4);
    xlabel('符号索引');
    ylabel('虚部');
    title(sprintf('PSS序列 (映射PCID=%d->%d) - 虚部', detectedPCID, lteCellId));
    grid on;

    subplot(2,2,3);
    plot(real(sssSeq), 'b-o', 'MarkerSize', 4);
    xlabel('符号索引');
    ylabel('实部');
    title(sprintf('SSS序列 (映射PCID=%d->%d) - 实部', detectedPCID, lteCellId));
    grid on;

    subplot(2,2,4);
    plot(imag(sssSeq), 'r-o', 'MarkerSize', 4);
    xlabel('符号索引');
    ylabel('虚部');
    title(sprintf('SSS序列 (映射PCID=%d->%d) - 虚部', detectedPCID, lteCellId));
    grid on;

    sgtitle('LTE同步信号序列 (NB-IoT参考)', 'FontSize', 14, 'FontWeight', 'bold');

    % 添加说明文本
    annotation('textbox', [0.02, 0.02, 0.96, 0.1], ...
        'String', sprintf('注意：由于lteNBPSS/lteNBSSS函数不可用，使用标准LTE函数ltePSS/lteSSS作为参考\nNB-IoT PCID %d 映射到 LTE小区ID %d', detectedPCID, lteCellId), ...
        'FitBoxToText', 'on', 'BackgroundColor', 'yellow', 'EdgeColor', 'red');

catch ME
    fprintf('警告：无法生成参考信号: %s\n', ME.message);
    fprintf('建议：检查LTE Toolbox版本或NB-IoT功能可用性\n');
end

%% 8. 保存优化检测结果
fprintf('保存检测结果...\n');

results = struct();
results.detectedPCID = detectedPCID;
results.maxCorrelation = maxCorrelation;
results.frameOffset = frameOffset;
results.correlationResults = correlationResults;
results.allPCIDs = allPCIDs; % 更新为allPCIDs
results.syncedWaveform = syncedWaveform;

% 添加优化检测统计信息
results.optimizedDetection = struct();
results.optimizedDetection.totalTime = pcidDetectionTime;
results.optimizedDetection.stage1Time = stage1Time;
results.optimizedDetection.stage2Time = stage2Time;
results.optimizedDetection.stage3Time = stage3Time;
results.optimizedDetection.testedCount = testedCount;
results.optimizedDetection.totalPCIDs = length(allPCIDs);
results.optimizedDetection.efficiency = length(allPCIDs)/testedCount;
results.optimizedDetection.commonPCIDs = commonPCIDs;
if exist('neighborPCIDs', 'var')
    results.optimizedDetection.neighborPCIDs = neighborPCIDs;
end

save('nbiot_sync_results.mat', 'results');

fprintf('\n=== 优化处理完成 ===\n');
fprintf('检测到的NB-IoT小区编号PCID: %d\n', detectedPCID);
fprintf('检测效率提升: %.1fx (测试%d/%d个PCID)\n', length(allPCIDs)/testedCount, testedCount, length(allPCIDs));
fprintf('结果已保存到 nbiot_sync_results.mat\n');
