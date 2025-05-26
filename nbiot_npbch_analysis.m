%% NB-IoT NPBCH广播信道解析脚本
% 功能：解析NB-IoT的NPBCH广播信道，绘制星座图，解码SFN帧号
% 作者：AI Assistant
% 日期：2024
% 依赖：LTE Toolbox中的NB-IoT专用函数

clear; clc; close all;

%% 1. 加载同步结果和原始数据
fprintf('=== NB-IoT NPBCH广播信道解析 ===\n');
fprintf('正在加载同步结果和原始数据...\n');

try
    % 加载同步结果
    if exist('nbiot_sync_results.mat', 'file')
        load('nbiot_sync_results.mat');
        detectedPCID = results.detectedPCID;
        frameOffset = results.frameOffset;
        syncedWaveform = results.syncedWaveform;
        fprintf('✓ 同步结果加载成功，检测到的PCID: %d\n', detectedPCID);
    else
        error('未找到同步结果文件，请先运行同步脚本');
    end

    % 加载原始数据
    load('nbiot_signalNBRefP1.mat');
    if exist('waveform', 'var')
        rxWaveform = waveform;
    elseif exist('signal', 'var')
        rxWaveform = signal;
    elseif exist('rxWaveform', 'var')
        % 变量已经是rxWaveform
    else
        vars = whos;
        rxWaveform = eval(vars(1).name);
    end
    fprintf('✓ 原始数据加载成功，信号长度: %d 采样点\n', length(rxWaveform));

catch ME
    error('数据加载失败: %s', ME.message);
end

%% 2. 配置NB-IoT系统参数
fprintf('配置NB-IoT系统参数...\n');

% NB-IoT下行配置
enb = struct();
enb.NBRefP = 1;                    % 天线端口数
enb.NNCellID = detectedPCID;       % 使用检测到的小区ID
enb.NBULSubcarrierSpacing = '15kHz'; % 子载波间隔
enb.OperationMode = 'Standalone';   % 操作模式

% 采样率和帧参数
samplingRate = 1.92e6;             % 1.92 MHz采样率
subframeLength = 1920;             % NB-IoT子帧长度（采样点）
frameLength = 10 * subframeLength; % 一个无线帧长度

fprintf('✓ 系统参数配置完成\n');
fprintf('  - 小区ID: %d\n', enb.NNCellID);
fprintf('  - 天线端口数: %d\n', enb.NBRefP);
fprintf('  - 采样率: %.2f MHz\n', samplingRate/1e6);

%% 3. 应用同步偏移并提取NPBCH数据
fprintf('提取NPBCH数据...\n');

% 应用帧偏移
if frameOffset > 0 && frameOffset < length(rxWaveform)
    alignedWaveform = rxWaveform(frameOffset+1:end);
else
    alignedWaveform = rxWaveform;
    frameOffset = 0;
end

% 确保有足够的数据进行NPBCH解析
minRequiredLength = frameLength * 2; % 至少需要2个帧
if length(alignedWaveform) < minRequiredLength
    warning('信号长度可能不足，继续处理...');
    npbchWaveform = alignedWaveform;
else
    % 提取包含NPBCH的数据段
    npbchWaveform = alignedWaveform(1:minRequiredLength);
end

fprintf('✓ NPBCH数据提取完成\n');
fprintf('  - 帧偏移: %d 采样点\n', frameOffset);
fprintf('  - 处理数据长度: %d 采样点\n', length(npbchWaveform));

%% 4. 检查LTE工具箱NB-IoT函数可用性
fprintf('检查NB-IoT专用函数可用性...\n');

% 检查关键函数
npbchFunctionsAvailable = true;
requiredFunctions = {'lteNPBCH', 'lteNPBCHDecode', 'lteNPBCHIndices'};

for i = 1:length(requiredFunctions)
    if exist(requiredFunctions{i}, 'file')
        fprintf('✓ %s 函数可用\n', requiredFunctions{i});
    else
        fprintf('✗ %s 函数不可用\n', requiredFunctions{i});
        npbchFunctionsAvailable = false;
    end
end

%% 5. NPBCH解析和星座图绘制
if npbchFunctionsAvailable
    fprintf('使用LTE工具箱NB-IoT专用函数进行NPBCH解析...\n');

    try
        %% 5.1 生成NPBCH资源元素索引
        fprintf('生成NPBCH资源元素索引...\n');
        npbchIndices = lteNPBCHIndices(enb);
        fprintf('✓ NPBCH索引生成成功，资源元素数量: %d\n', length(npbchIndices));

        %% 5.2 执行OFDM解调
        fprintf('执行OFDM解调...\n');

        % 配置标准LTE参数用于NB-IoT（NB-IoT使用1.4MHz带宽）
        lteEnb = struct();
        lteEnb.NDLRB = 6;  % 1.4MHz带宽对应6个RB
        lteEnb.CyclicPrefix = 'Normal';
        lteEnb.CellRefP = enb.NBRefP;
        lteEnb.NCellID = enb.NNCellID;
        lteEnb.NSubframe = 0;  % 添加子帧号参数

        % OFDM解调
        rxGrid = lteOFDMDemodulate(lteEnb, npbchWaveform);
        fprintf('✓ OFDM解调完成，资源网格大小: %dx%d\n', size(rxGrid,1), size(rxGrid,2));

        %% 5.3 提取NPBCH符号
        fprintf('提取NPBCH符号...\n');

        % 提取NPBCH符号
        npbchSymbols = rxGrid(npbchIndices);
        fprintf('✓ NPBCH符号提取完成，符号数量: %d\n', length(npbchSymbols));

        %% 5.4 绘制原始NPBCH星座图
        figure('Position', [100, 100, 1400, 1000]);

        % 原始星座图
        subplot(2,3,1);
        scatter(real(npbchSymbols), imag(npbchSymbols), 20, 'b', 'filled');
        xlabel('同相分量 (I)');
        ylabel('正交分量 (Q)');
        title('NPBCH原始星座图');
        grid on;
        axis equal;

        %% 5.5 信道估计和补偿
        fprintf('执行信道估计...\n');

        try
            % 简化的信道补偿：使用幅度归一化
            % 计算符号的平均功率并进行归一化
            avgPower = mean(abs(npbchSymbols).^2);
            if avgPower > 0
                npbchSymbolsEq = npbchSymbols ./ sqrt(avgPower);
                fprintf('✓ 简化信道补偿完成（幅度归一化）\n');
            else
                npbchSymbolsEq = npbchSymbols;
                fprintf('⚠️  跳过信道补偿（零功率信号）\n');
            end

            % 信道补偿后的星座图
            subplot(2,3,2);
            scatter(real(npbchSymbolsEq), imag(npbchSymbolsEq), 20, 'r', 'filled');
            xlabel('同相分量 (I)');
            ylabel('正交分量 (Q)');
            title('NPBCH归一化后星座图');
            grid on;
            axis equal;

        catch ME
            fprintf('警告：信道补偿失败: %s\n', ME.message);
            npbchSymbolsEq = npbchSymbols; % 使用原始符号

            % 显示警告信息
            subplot(2,3,2);
            text(0.5, 0.5, {'信道补偿失败', '显示原始符号'}, ...
                'HorizontalAlignment', 'center', 'FontSize', 12);
            title('信道补偿失败');
        end

        %% 5.6 NPBCH解码
        fprintf('执行NPBCH解码...\n');

        try
            % 尝试解码NPBCH - 使用正确的语法
            [decodedBits, stateout, symbols, nfmod64, trblk, NBRefP] = lteNPBCHDecode(enb, npbchSymbolsEq);

            fprintf('✓ NPBCH解码完成\n');
            fprintf('  - 解码位数: %d\n', length(decodedBits));
            fprintf('  - SFN mod 64: %d\n', nfmod64);
            fprintf('  - 检测到的天线端口数: %d\n', NBRefP);

            % SFN高4位就是nfmod64的高4位
            sfnMSB = bitshift(nfmod64, -2);  % 右移2位得到高4位

            fprintf('✓ SFN高4位解码结果: %d\n', sfnMSB);

            % 显示MIB信息
            if ~isempty(trblk)
                fprintf('MIB信息块长度: %d位\n', length(trblk));
                fprintf('MIB位序列: %s\n', num2str(trblk'));
            else
                fprintf('MIB信息块为空\n');
            end

        catch ME
            fprintf('✗ NPBCH解码过程出错: %s\n', ME.message);
            sfnMSB = NaN;
            decodedBits = [];
        end

    catch ME
        fprintf('✗ NPBCH解析过程出错: %s\n', ME.message);
        npbchFunctionsAvailable = false;
    end

else
    fprintf('⚠️  NB-IoT专用函数不可用，使用替代方法...\n');
end

%% 6. 替代方法（当专用函数不可用时）
if ~npbchFunctionsAvailable
    fprintf('使用标准LTE函数进行近似分析...\n');

    try
        % 使用标准LTE OFDM解调
        lteEnb = struct();
        lteEnb.NDLRB = 6;  % 1.4MHz带宽对应6个RB
        lteEnb.CyclicPrefix = 'Normal';
        lteEnb.CellRefP = enb.NBRefP;
        lteEnb.NCellID = mod(enb.NNCellID, 504);

        % OFDM解调
        rxGrid = lteOFDMDemodulate(lteEnb, npbchWaveform);

        % 提取中心子载波（模拟NB-IoT的单子载波）
        centerSubcarriers = rxGrid(37:48, :); % 中心12个子载波
        allSymbols = centerSubcarriers(:);

        % 绘制星座图
        figure('Position', [200, 200, 1200, 800]);

        subplot(2,3,1);
        scatter(real(allSymbols), imag(allSymbols), 15, 'b', 'filled');
        xlabel('同相分量 (I)');
        ylabel('正交分量 (Q)');
        title('近似NPBCH星座图（使用LTE函数）');
        grid on;
        axis equal;

        % 简单的幅度归一化作为"信道补偿"
        normalizedSymbols = allSymbols ./ mean(abs(allSymbols));

        subplot(2,3,2);
        scatter(real(normalizedSymbols), imag(normalizedSymbols), 15, 'r', 'filled');
        xlabel('同相分量 (I)');
        ylabel('正交分量 (Q)');
        title('归一化后星座图');
        grid on;
        axis equal;

        fprintf('✓ 使用替代方法完成星座图绘制\n');
        fprintf('⚠️  注意：这是使用标准LTE函数的近似结果\n');

        % 无法准确解码SFN
        sfnMSB = NaN;
        fprintf('⚠️  无法使用替代方法解码SFN，需要专用NB-IoT函数\n');

    catch ME
        fprintf('✗ 替代方法也失败: %s\n', ME.message);
        sfnMSB = NaN;
    end
end

%% 7. 结果总结和显示
fprintf('\n=== NPBCH解析结果总结 ===\n');
fprintf('检测到的小区ID (PCID): %d\n', detectedPCID);
fprintf('帧偏移: %d 采样点\n', frameOffset);

if ~isnan(sfnMSB)
    fprintf('✓ SFN高4位: %d\n', sfnMSB);
else
    fprintf('✗ SFN解码失败或不可用\n');
end

if exist('decodedBits', 'var') && ~isempty(decodedBits)
    fprintf('MIB解码位数: %d\n', length(decodedBits));
else
    fprintf('MIB解码: 失败或不可用\n');
end

%% 8. 保存结果
fprintf('保存NPBCH解析结果...\n');

npbchResults = struct();
npbchResults.detectedPCID = detectedPCID;
npbchResults.frameOffset = frameOffset;
npbchResults.sfnMSB = sfnMSB;
npbchResults.functionsAvailable = npbchFunctionsAvailable;

if exist('decodedBits', 'var')
    npbchResults.decodedBits = decodedBits;
end

if exist('npbchSymbols', 'var')
    npbchResults.npbchSymbols = npbchSymbols;
end

if exist('npbchSymbolsEq', 'var')
    npbchResults.npbchSymbolsEq = npbchSymbolsEq;
end

save('nbiot_npbch_results.mat', 'npbchResults');

fprintf('\n=== 处理完成 ===\n');
fprintf('结果已保存到 nbiot_npbch_results.mat\n');

if npbchFunctionsAvailable
    fprintf('✓ 使用了LTE工具箱的NB-IoT专用函数\n');
else
    fprintf('⚠️  使用了替代方法，结果可能不够准确\n');
    fprintf('建议：确保LTE Toolbox版本支持NB-IoT功能\n');
end
