%% 检查NB-IoT专用函数可用性
% 详细检查LTE工具箱中的NB-IoT相关函数
% 作者：AI Assistant

clear; clc;

fprintf('=== NB-IoT函数可用性检查 ===\n');

%% 1. 检查LTE Toolbox版本
try
    v = ver;
    lteIdx = strcmp({v.Name}, 'LTE Toolbox');
    if any(lteIdx)
        lteVersion = v(lteIdx).Version;
        fprintf('✓ LTE Toolbox版本: %s\n', lteVersion);
    else
        fprintf('✗ LTE Toolbox未安装\n');
        return;
    end
catch
    fprintf('✗ 无法检查LTE Toolbox版本\n');
    return;
end

%% 2. 检查NB-IoT专用函数
fprintf('\n=== NB-IoT专用函数检查 ===\n');

% 定义需要检查的NB-IoT函数
nbiotFunctions = {
    'lteNBDLFrameOffset',    '帧偏移检测';
    'lteNBOFDMInfo',         'OFDM信息';
    'lteNBOFDMDemodulate',   'OFDM解调';
    'lteNBOFDMModulate',     'OFDM调制';
    'lteNBRS',               '参考信号生成';
    'lteNBRSIndices',        '参考信号索引';
    'lteNPBCH',              'NPBCH符号生成';
    'lteNPBCHDecode',        'NPBCH解码';
    'lteNPBCHIndices',       'NPBCH索引';
    'lteNPDCCH',             'NPDCCH符号生成';
    'lteNPDCCHDecode',       'NPDCCH解码';
    'lteNPDCCHIndices',      'NPDCCH索引';
    'lteNPDSCH',             'NPDSCH符号生成';
    'lteNPDSCHDecode',       'NPDSCH解码';
    'lteNPDSCHIndices',      'NPDSCH索引';
    'lteNBPSS',              'NB-IoT PSS';
    'lteNBSSS',              'NB-IoT SSS';
};

availableFunctions = {};
unavailableFunctions = {};

for i = 1:size(nbiotFunctions, 1)
    funcName = nbiotFunctions{i, 1};
    funcDesc = nbiotFunctions{i, 2};
    
    if exist(funcName, 'file')
        fprintf('✓ %-20s - %s\n', funcName, funcDesc);
        availableFunctions{end+1} = funcName;
    else
        fprintf('✗ %-20s - %s\n', funcName, funcDesc);
        unavailableFunctions{end+1} = funcName;
    end
end

%% 3. 测试关键函数
fprintf('\n=== 关键函数测试 ===\n');

% 测试配置
testEnb = struct();
testEnb.NBRefP = 1;
testEnb.NNCellID = 0;
testEnb.NBULSubcarrierSpacing = '15kHz';
testEnb.OperationMode = 'Standalone';

% 测试lteNBDLFrameOffset
if exist('lteNBDLFrameOffset', 'file')
    try
        testSignal = complex(randn(1000,1), randn(1000,1));
        [offset, corr] = lteNBDLFrameOffset(testEnb, testSignal);
        fprintf('✓ lteNBDLFrameOffset测试成功\n');
    catch ME
        fprintf('✗ lteNBDLFrameOffset测试失败: %s\n', ME.message);
    end
end

% 测试lteNBOFDMInfo
if exist('lteNBOFDMInfo', 'file')
    try
        ofdmInfo = lteNBOFDMInfo(testEnb);
        fprintf('✓ lteNBOFDMInfo测试成功\n');
        fprintf('  - 采样率: %.2f MHz\n', ofdmInfo.SamplingRate/1e6);
        fprintf('  - FFT大小: %d\n', ofdmInfo.Nfft);
    catch ME
        fprintf('✗ lteNBOFDMInfo测试失败: %s\n', ME.message);
    end
end

% 测试lteNPBCHIndices
if exist('lteNPBCHIndices', 'file')
    try
        npbchIdx = lteNPBCHIndices(testEnb);
        fprintf('✓ lteNPBCHIndices测试成功，索引数量: %d\n', length(npbchIdx));
    catch ME
        fprintf('✗ lteNPBCHIndices测试失败: %s\n', ME.message);
    end
end

%% 4. 生成测试报告
fprintf('\n=== 测试报告 ===\n');
fprintf('可用函数数量: %d/%d\n', length(availableFunctions), size(nbiotFunctions, 1));
fprintf('可用率: %.1f%%\n', length(availableFunctions)/size(nbiotFunctions, 1)*100);

if length(availableFunctions) >= 8  % 至少需要8个关键函数
    fprintf('✓ NB-IoT功能基本可用\n');
    canProceed = true;
else
    fprintf('⚠️  NB-IoT功能不完整，可能需要更新LTE Toolbox\n');
    canProceed = false;
end

%% 5. 提供建议
fprintf('\n=== 建议 ===\n');

if canProceed
    fprintf('✓ 可以继续进行NPBCH解析\n');
    fprintf('建议运行: nbiot_npbch_analysis.m\n');
else
    fprintf('建议检查以下事项：\n');
    fprintf('1. 确保LTE Toolbox版本支持NB-IoT（R2017a或更高版本）\n');
    fprintf('2. 检查许可证是否包含NB-IoT功能\n');
    fprintf('3. 考虑使用替代方法进行近似分析\n');
end

if ~isempty(unavailableFunctions)
    fprintf('\n不可用的函数列表：\n');
    for i = 1:length(unavailableFunctions)
        fprintf('  - %s\n', unavailableFunctions{i});
    end
end

%% 6. 保存检查结果
checkResults = struct();
checkResults.lteVersion = lteVersion;
checkResults.availableFunctions = availableFunctions;
checkResults.unavailableFunctions = unavailableFunctions;
checkResults.canProceed = canProceed;
checkResults.checkTime = datestr(now);

save('nbiot_function_check.mat', 'checkResults');
fprintf('\n检查结果已保存到: nbiot_function_check.mat\n');

fprintf('\n=== 检查完成 ===\n');
