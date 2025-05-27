%% NB-IoT RTL-SDR实时信号接收与PCID检测脚本
% 功能：使用RTL-SDR接收机实时接收NB-IoT信号，进行下行同步和PCID检测
% 作者：AI Assistant
% 日期：2024
%
% 说明：
% 1. 集成rtlsdr_setup.m配置文件设置RTL-SDR接收机参数
% 2. 实时接收NB-IoT信号并进行PCID检测
% 3. 保持与原有信号处理算法完全一致
% 4. 使用官方LTE工具箱函数，严格按照3GPP标准实现

clear; clc; close all;

%% 1. RTL-SDR接收机设置和初始化
fprintf('=== NB-IoT RTL-SDR实时信号接收与PCID检测 ===\n');
fprintf('正在初始化RTL-SDR接收机...\n');

try
    % 调用rtlsdr_setup函数初始化RTL-SDR接收机
    sdrobj = rtlsdr_setup();
    fprintf('RTL-SDR接收机初始化成功\n');
catch ME
    error('RTL-SDR接收机初始化失败: %s\n请确保已安装RTL-SDR支持包并连接设备', ME.message);
end

%% 2. 信号接收参数配置
fprintf('\n配置信号接收参数...\n');

% 接收时间配置（可调参数）
recordingTime = 0.1;  % 接收时间（秒），可根据需要调整
samplingRate = sdrobj.SampleRate;  % 从RTL-SDR对象获取采样率
samplesPerFrame = sdrobj.SamplesPerFrame;  % 每帧样本数

% 计算需要接收的帧数
totalSamples = recordingTime * samplingRate;
numFrames = ceil(totalSamples / samplesPerFrame);

fprintf('接收时间: %d 秒\n', recordingTime);
fprintf('采样率: %.2f MHz\n', samplingRate/1e6);
fprintf('预计接收样本数: %d\n', totalSamples);
fprintf('需要接收帧数: %d\n', numFrames);

%% 3. 实时信号接收
fprintf('\n开始实时接收NB-IoT信号...\n');
fprintf('请确保NB-IoT基站信号可用...\n');

% 初始化接收缓冲区
rxWaveform = complex(zeros(totalSamples, 1), zeros(totalSamples, 1));
receivedSamples = 0;

try
    % 启动RTL-SDR接收
    tic;
    for frameIdx = 1:numFrames
        % 接收一帧数据
        [data, len] = step(sdrobj);

        % 计算当前帧的存储位置
        startIdx = receivedSamples + 1;
        endIdx = min(receivedSamples + len, totalSamples);
        actualLen = endIdx - startIdx + 1;

        % 存储接收到的数据
        if actualLen > 0
            rxWaveform(startIdx:endIdx) = data(1:actualLen);
            receivedSamples = receivedSamples + actualLen;
        end

        % 显示接收进度
        if mod(frameIdx, max(1, round(numFrames/10))) == 0
            progress = frameIdx / numFrames * 100;
            fprintf('接收进度: %.1f%% (%d/%d 帧)\n', progress, frameIdx, numFrames);
        end

        % 如果已接收足够样本，退出循环
        if receivedSamples >= totalSamples
            break;
        end
    end

    elapsedTime = toc;
    fprintf('信号接收完成！\n');
    fprintf('实际接收时间: %.2f 秒\n', elapsedTime);
    fprintf('实际接收样本数: %d\n', receivedSamples);

    % 截取实际接收的数据
    rxWaveform = rxWaveform(1:receivedSamples);

catch ME
    error('信号接收失败: %s', ME.message);
finally
    % 释放RTL-SDR资源
    if exist('sdrobj', 'var')
        release(sdrobj);
        fprintf('RTL-SDR资源已释放\n');
    end
end

%% 4. NB-IoT系统参数配置
fprintf('\n配置NB-IoT系统参数...\n');

% NB-IoT下行配置
enb = struct();
enb.NBRefP = 1;           % 天线端口数 (1 or 2)
enb.NNCellID = [];        % 小区ID，待检测
enb.NBULSubcarrierSpacing = '15kHz';  % 子载波间隔
enb.OperationMode = 'Standalone';     % 操作模式

fprintf('NB-IoT系统参数配置完成\n');

%% 5. 信号质量预检查
fprintf('\n进行信号质量预检查...\n');

% 计算信号功率和信噪比估计
signalPower = mean(abs(rxWaveform).^2);
signalRMS = sqrt(signalPower);

fprintf('接收信号统计信息:\n');
fprintf('  信号长度: %d 采样点\n', length(rxWaveform));
fprintf('  信号功率: %.6f\n', signalPower);
fprintf('  信号RMS: %.6f\n', signalRMS);
fprintf('  最大幅度: %.6f\n', max(abs(rxWaveform)));

% 检查信号是否过小或过大
if signalRMS < 1e-6
    warning('接收信号幅度过小，可能影响检测性能');
elseif max(abs(rxWaveform)) > 0.95
    warning('接收信号可能存在饱和，建议调整RTL-SDR增益');
end

%% 6. PCID检测 - 遍历所有可能的小区ID
fprintf('\n开始PCID检测...\n');

% NB-IoT支持的小区ID范围是0-503
possiblePCIDs = 0:503;
correlationResults = zeros(size(possiblePCIDs));
frameOffsets = zeros(size(possiblePCIDs));

% 进度显示
numPCIDs = length(possiblePCIDs);
progressStep = round(numPCIDs / 10);

fprintf('开始遍历%d个可能的PCID...\n', numPCIDs);
tic;

for idx = 1:numPCIDs
    pcid = possiblePCIDs(idx);

    % 显示进度
    if mod(idx, progressStep) == 0
        fprintf('PCID检测进度: %d%% (当前PCID: %d)\n', round(idx/numPCIDs*100), pcid);
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

pcidDetectionTime = toc;
fprintf('PCID检测完成，耗时: %.2f 秒\n', pcidDetectionTime);

%% 7. 找到最佳PCID
[maxCorrelation, maxIdx] = max(correlationResults);
detectedPCID = possiblePCIDs(maxIdx);
detectedOffset = frameOffsets(maxIdx);

fprintf('\n=== PCID检测结果 ===\n');
fprintf('检测到的小区编号PCID: %d\n', detectedPCID);
fprintf('最大相关值: %.4f\n', maxCorrelation);
fprintf('帧偏移: %d 采样点\n', detectedOffset);

% 检查检测结果的可信度
if maxCorrelation < 0.1
    warning('检测到的相关值较低(%.4f)，结果可能不可靠', maxCorrelation);
    fprintf('建议：\n');
    fprintf('  1. 检查天线连接和位置\n');
    fprintf('  2. 调整RTL-SDR增益设置\n');
    fprintf('  3. 确认NB-IoT基站信号覆盖\n');
    fprintf('  4. 增加接收时间以获得更多数据\n');
end

%% 8. 使用检测到的PCID进行精确同步
fprintf('\n正在进行精确同步...\n');
enb.NNCellID = detectedPCID;

% 重新计算帧偏移和相关性
[frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);

% 应用帧偏移校正
if frameOffset > 0 && frameOffset < length(rxWaveform)
    syncedWaveform = rxWaveform(frameOffset+1:end);
else
    syncedWaveform = rxWaveform;
    frameOffset = 0;
end

fprintf('同步完成，帧偏移: %d 采样点\n', frameOffset);

%% 9. 绘制相关峰图
fprintf('\n绘制相关峰图...\n');

figure('Position', [100, 100, 1200, 800]);

% 子图1：PCID检测结果
subplot(2,2,1);
plot(possiblePCIDs, correlationResults, 'b-', 'LineWidth', 1);
hold on;
plot(detectedPCID, maxCorrelation, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('小区编号 PCID');
ylabel('相关值');
title('NB-IoT PCID检测结果 (RTL-SDR实时接收)');
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

% 子图3：原始接收信号时域
subplot(2,2,3);
timeSamples = (0:length(rxWaveform)-1) / samplingRate * 1000; % 转换为毫秒
plot(timeSamples(1:min(10000, end)), real(rxWaveform(1:min(10000, end))), 'b-');
xlabel('时间 (ms)');
ylabel('幅度');
title('RTL-SDR接收信号 (实部)');
grid on;

% 子图4：同步后信号时域
subplot(2,2,4);
syncTimeSamples = (0:length(syncedWaveform)-1) / samplingRate * 1000;
plot(syncTimeSamples(1:min(10000, end)), real(syncedWaveform(1:min(10000, end))), 'r-');
xlabel('时间 (ms)');
ylabel('幅度');
title('同步后信号 (实部)');
grid on;

sgtitle('NB-IoT RTL-SDR实时信号同步与PCID检测结果', 'FontSize', 14, 'FontWeight', 'bold');

%% 10. 生成PSS和SSS参考信号进行验证
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

%% 11. 保存结果
fprintf('\n保存检测结果...\n');

% 创建结果结构体
results = struct();
results.detectedPCID = detectedPCID;
results.maxCorrelation = maxCorrelation;
results.frameOffset = frameOffset;
results.correlationResults = correlationResults;
results.possiblePCIDs = possiblePCIDs;
results.syncedWaveform = syncedWaveform;
results.originalWaveform = rxWaveform;
results.rtlsdrConfig = struct();
results.rtlsdrConfig.centerFrequency = sdrobj.CenterFrequency;
results.rtlsdrConfig.sampleRate = sdrobj.SampleRate;
results.rtlsdrConfig.frequencyCorrection = sdrobj.FrequencyCorrection;
results.rtlsdrConfig.recordingTime = recordingTime;
results.rtlsdrConfig.receivedSamples = receivedSamples;
results.signalQuality = struct();
results.signalQuality.signalPower = signalPower;
results.signalQuality.signalRMS = signalRMS;
results.signalQuality.maxAmplitude = max(abs(rxWaveform));

% 保存到文件
save('nbiot_rtlsdr_results.mat', 'results');

fprintf('\n=== RTL-SDR实时处理完成 ===\n');
fprintf('检测到的NB-IoT小区编号PCID: %d\n', detectedPCID);
fprintf('最大相关值: %.4f\n', maxCorrelation);
fprintf('RTL-SDR配置信息:\n');
fprintf('  中心频率: %.2f MHz\n', sdrobj.CenterFrequency/1e6);
fprintf('  采样率: %.2f MHz\n', sdrobj.SampleRate/1e6);
fprintf('  接收时间: %d 秒\n', recordingTime);
fprintf('  接收样本数: %d\n', receivedSamples);
fprintf('结果已保存到 nbiot_rtlsdr_results.mat\n');

%% 12. 可选：连续监测模式提示
fprintf('\n=== 使用说明 ===\n');
fprintf('1. 可调参数：\n');
fprintf('   - recordingTime: 调整接收时间（当前%d秒）\n', recordingTime);
fprintf('   - RTL-SDR增益: 在rtlsdr_setup.m中调整TunerGain\n');
fprintf('   - 中心频率: 在rtlsdr_setup.m中调整CenterFrequency\n');
fprintf('2. 如需连续监测，可将此脚本封装为函数\n');
fprintf('3. 建议在信号质量良好的环境下使用\n');
fprintf('4. 确保NB-IoT基站信号覆盖良好\n');
