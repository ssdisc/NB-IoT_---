%% NB-IoT下行信号同步与PCID检测脚本
% 功能：实现NB-IoT下行信号同步，绘制相关峰图，检测小区编号PCID
% 作者：AI Assistant
% 日期：2024

clear; clc; close all;

%% 1. 加载NB-IoT信号数据
fprintf('正在加载NB-IoT信号数据...\n');
try
    load('nbiot_received_signal.mat');
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

%% 3. PCID检测 - 遍历所有可能的小区ID
fprintf('开始PCID检测...\n');

% NB-IoT支持的小区ID范围是0-503
possiblePCIDs = 0:503;
correlationResults = zeros(size(possiblePCIDs));
frameOffsets = zeros(size(possiblePCIDs));

% 进度显示
numPCIDs = length(possiblePCIDs);
progressStep = round(numPCIDs / 10);

for idx = 1:numPCIDs
    pcid = possiblePCIDs(idx);

    % 显示进度
    if mod(idx, progressStep) == 0
        fprintf('检测进度: %d%%\n', round(idx/numPCIDs*100));
    end

    try
        % 设置当前测试的小区ID
        enb.NNCellID = pcid;

        % 检测帧偏移和相关性
        [frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);

        correlationResults(idx) = max(abs(correlation));
        frameOffsets(idx) = frameOffset;

    catch
        % 如果某个PCID检测失败，继续下一个
        correlationResults(idx) = 0;
        frameOffsets(idx) = 0;
    end
end

%% 4. 找到最佳PCID
[maxCorrelation, maxIdx] = max(correlationResults);
detectedPCID = possiblePCIDs(maxIdx);
detectedOffset = frameOffsets(maxIdx);

fprintf('\n=== PCID检测结果 ===\n');
fprintf('检测到的小区编号PCID: %d\n', detectedPCID);
fprintf('最大相关值: %.4f\n', maxCorrelation);
fprintf('帧偏移: %d 采样点\n', detectedOffset);

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

%% 6. 绘制相关峰图
fprintf('绘制相关峰图...\n');

figure('Position', [100, 100, 1200, 800]);

% 子图1：PCID检测结果
subplot(2,2,1);
plot(possiblePCIDs, correlationResults, 'b-', 'LineWidth', 1);
hold on;
plot(detectedPCID, maxCorrelation, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('小区编号 PCID');
ylabel('相关值');
title('NB-IoT PCID检测结果');
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

%% 8. 保存结果
fprintf('保存检测结果...\n');

results = struct();
results.detectedPCID = detectedPCID;
results.maxCorrelation = maxCorrelation;
results.frameOffset = frameOffset;
results.correlationResults = correlationResults;
results.possiblePCIDs = possiblePCIDs;
results.syncedWaveform = syncedWaveform;

save('nbiot_sync_results.mat', 'results');

fprintf('\n=== 处理完成 ===\n');
fprintf('检测到的NB-IoT小区编号PCID: %d\n', detectedPCID);
fprintf('结果已保存到 nbiot_sync_results.mat\n');
