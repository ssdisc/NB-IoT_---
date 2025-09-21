# 案例：基于RTL-SDR的NB-IoT信号实时处理与解析

## 1. 任务背景和要求

### 1.1 实验完整要求

根据实验报告的要求，本实验需要完成以下任务：

1. **信号发现与频率识别**
   - 使用RTL-SDR找到一个NB-IoT信号
   - 结合网络检索、资料查询等，分析得到这个NB-IoT信号的频点、中心频率

2. **下行同步实现**
   - 自行学习NB-IoT（OFDM）下行同步机制
   - 使用Matlab脚本或Simulink编写代码，实现NB-IoT下行信号同步
   - 画出相关峰图，检测所接收到NB-IoT信号的小区编号PCID

3. **广播信道解析**
   - 尝试解析NB-IoT的广播信道NPBCH
   - 画出NPBCH原始星座图、信道补偿之后的星座图
   - 给出所解码出来的系统帧号SFN高4位

### 1.2 具体实现要求

我们遇到的任务是这样的：需要使用RTL-SDR软件定义无线电设备来接收和解析真实的NB-IoT（窄带物联网）信号。这个任务的挑战在于，NB-IoT是一个相对较新的通信标准，而且我们要在MATLAB环境下完成整个信号处理流程，从最基础的无线信号接收一直到高层协议的信息解析。

具体的技术要求包括：
- 使用RTL-SDR设备接收879.4MHz频段的NB-IoT信号
- 进行小区身份识别（PCID检测）
- 实现信号同步
- 解调窄带物理广播信道（NPBCH）
- 解析系统信息，特别是系统帧号（SFN）信息

## 2. 具体实现过程

### 2.1 项目开始——设备配置的摸索

一开始，我们就遇到了实际工程中经常会碰到的问题：硬件设备的配置。RTL-SDR虽然是个便宜好用的软件定义无线电设备，但是要让它正确接收NB-IoT信号，需要很多参数调试。

我们创建了`rtlsdr_setup.m`文件来专门处理设备初始化：

```matlab
function sdrobj = rtlsdr_setup()
    % 检查是否已安装RTL-SDR支持包
    if ~exist('comm.SDRRTLReceiver', 'class')
        error('未安装RTL-SDR支持包。请使用MATLAB Add-On Explorer安装RTL-SDR支持包。');
    end

    % 创建RTL-SDR接收器对象
    sdrobj = comm.SDRRTLReceiver;

    % 这些参数都是经过反复调试得出的
    sdrobj.SampleRate = 1.92e6;  % NB-IoT需要的采样率
    sdrobj.CenterFrequency = 879.4e6;  % 中心频率
    sdrobj.FrequencyCorrection = 21;  % 频偏校正，这个数值是试出来的
    sdrobj.EnableTunerAGC = true;
    sdrobj.TunerGain = 80;
    sdrobj.SamplesPerFrame = 19200;  % 一个NB-IoT子帧的样本数
end
```

这里面每个参数都有来头。比如频偏校正值21ppm，这是因为RTL-SDR设备的晶振不够精确，不同设备的偏差不一样，需要根据实际情况调整。采样率1.92MHz是LTE系统的标准采样率，NB-IoT虽然带宽只有180kHz，但是处理时需要用LTE工具箱的函数。

### 2.2 信号接收——第一个技术难点

有了设备配置，下一步就是接收信号。这看起来很简单，但实际上遇到了很多问题。

在`nbiot_realtime_npbch_demod.m`文件中，我们实现了实时信号接收：

```matlab
%% 实时信号接收
fprintf('\n开始实时接收NB-IoT信号...\n');
recordingTime = 0.2;  % 接收时间
samplingRate = sdrobj.SampleRate;
totalSamples = recordingTime * samplingRate;
numFrames = ceil(totalSamples / samplesPerFrame);

% 初始化接收缓冲区
rxWaveform = complex(zeros(totalSamples, 1), zeros(totalSamples, 1));
receivedSamples = 0;

try
    tic;
    for frameIdx = 1:numFrames
        [data, len] = step(sdrobj);
        
        if len > 0
            endIdx = min(receivedSamples + len, totalSamples);
            rxWaveform(receivedSamples+1:endIdx) = data(1:(endIdx-receivedSamples));
            receivedSamples = endIdx;
        end
    end
    elapsedTime = toc;
    
    fprintf('接收完成！\n');
    fprintf('实际接收时间: %.3f 秒\n', elapsedTime);
    fprintf('接收到样本数: %d\n', receivedSamples);
    
catch ME
    error('信号接收失败: %s', ME.message);
end
```

刚开始的时候，我们经常遇到接收到的信号全是噪声，或者信号幅度太小。后来发现问题出在：
1. 天线位置不对，要放在窗边
2. 增益设置不合适
3. 频偏校正没调好

### 2.3 小区身份检测——最核心的算法挑战

接收到信号后，最关键的步骤是检测小区身份（PCID）。这个步骤决定了后续所有处理能否成功。

NB-IoT支持0-503个小区ID，如果一个个遍历检测，计算量太大。我们设计了一个多阶段检测策略，在`nbiot_sync_and_pcid_detection.m`中实现：

```matlab
% 阶段1：快速粗略检测 - 检测常见PCID
commonPCIDs = [0:10:100, 150:5:200, 250:10:350, 400:20:503];
commonPCIDs = unique(commonPCIDs(commonPCIDs <= 503));

maxCorrelation = 0;
bestPCID = 0;
candidatePCIDs = [];

for pcid = commonPCIDs
    try
        enb.NNCellID = pcid;
        [frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);
        
        corrValue = max(abs(correlation));
        
        if corrValue > maxCorrelation
            maxCorrelation = corrValue;
            bestPCID = pcid;
        end
        
        % 收集候选PCID
        if corrValue > 0.05
            candidatePCIDs(end+1) = pcid;
        end
    catch
        % 某些PCID可能会导致函数出错，跳过即可
    end
end
```

这个策略的思路是：先检测一些常见的PCID值，找到相关性最高的几个候选，然后再进行精确检测。这样可以大大减少计算时间。

经过多次调试，我们发现：
- 相关阈值0.05是比较合适的，太高会漏掉真实信号，太低会包含太多噪声
- 不同的基站使用的PCID确实有规律，通常不会使用全部503个值
- 有些PCID会导致MATLAB的LTE工具箱函数出错，需要用try-catch处理

### 2.4 信号同步——时域对齐的精细工作

检测到正确的PCID后，下一步是信号同步。这个步骤的目标是找到信号帧的准确起始位置。

```matlab
% 使用检测到的最佳PCID进行精确同步
enb.NNCellID = bestPCID;
[frameOffset, correlation] = lteNBDLFrameOffset(enb, rxWaveform);

% 根据帧偏移对信号进行同步
if frameOffset > 0
    syncedWaveform = rxWaveform(frameOffset+1:end);
else
    syncedWaveform = rxWaveform;
end

fprintf('帧偏移: %d 采样点\n', frameOffset);
fprintf('同步后信号长度: %d 采样点\n', length(syncedWaveform));
```

这一步看起来简单，但是frameOffset的正确性直接影响后续所有处理。我们发现：
- frameOffset通常不是0，说明接收到的信号确实需要时域对齐
- 同步后的信号长度会减少，这是正常的
- 如果同步不正确，后面的解调就会完全失败

### 2.5 NPBCH解调——协议层面的信息提取

同步完成后，就可以进行NPBCH（窄带物理广播信道）的解调了。这是整个项目最复杂的部分，涉及到信道估计、均衡、解调等多个步骤。

在`nbiot_npbch_analysis.m`中，我们实现了完整的NPBCH解调流程：

```matlab
%% NPBCH解调和解码
fprintf('\n开始NPBCH解调...\n');

% 信道估计
[hest, nest] = lteNBDLChannelEstimate(enb, cec, syncedWaveform);

% 提取NPBCH符号
npbchIndices = lteNBPBCHIndices(enb);
npbchSymbols = lteNBResourceGrid(enb, syncedWaveform);
npbchSymbols = npbchSymbols(npbchIndices);

% 信道均衡
hestNPBCH = hest(npbchIndices);
eqSymbols = npbchSymbols ./ hestNPBCH;

% 解调
npbchBits = lteNBPBCHDecode(enb, eqSymbols);
```

这里面每一步都可能出错：
- 信道估计可能因为信噪比太低而失败
- 资源网格提取可能因为同步偏差而错位  
- 信道均衡可能因为估计不准确而效果不好

我们通过绘制星座图来直观检查各个步骤的效果：

```matlab
% 绘制信道补偿前后的QPSK星座图
figure;
subplot(1,2,1);
plot(real(npbchSymbols), imag(npbchSymbols), 'ro', 'MarkerSize', 3);
title('信道补偿前NPBCH符号星座图');
grid on; axis equal;

subplot(1,2,2);
plot(real(eqSymbols), imag(eqSymbols), 'bo', 'MarkerSize', 3);
title('信道补偿后NPBCH符号星座图');
grid on; axis equal;
```

### 2.6 遇到的主要问题和解决方案

在整个实现过程中，我们遇到了很多实际问题：

**问题1：接收信号幅度不稳定**
- 现象：有时候信号很强，有时候很弱，甚至接收不到
- 原因：RTL-SDR设备对环境敏感，天线位置、电磁干扰都会影响
- 解决方案：固定天线位置，使用AGC自动增益控制

**问题2：PCID检测成功率不高**
- 现象：经常检测不到正确的小区ID
- 原因：全遍历计算量太大，而且很多PCID实际并不使用
- 解决方案：设计多阶段检测策略，先检测常见值

**问题3：NPBCH解码失败**
- 现象：解调出来的比特全是错误的
- 原因：信道估计不准确，或者同步存在偏差
- 解决方案：调整信道估计参数，增加滤波和平均

**问题4：MATLAB工具箱函数不稳定**
- 现象：某些参数组合会导致函数崩溃
- 原因：工具箱函数对输入参数有隐含的限制条件
- 解决方案：加入大量的try-catch错误处理

### 2.7 最终结果和验证

经过反复调试，我们最终实现了完整的NB-IoT信号处理流程。从生成的图片可以看到：

1. **相关峰检测图**（figure_20250701_182411.png）：显示了PCID检测过程中的相关性分布，可以清楚看到哪个PCID的相关性最高。

2. **星座图对比**（figure_20250701_182453.png）：展示了信道补偿前后的QPSK星座图，补偿后的星座点明显更聚集，说明信道均衡效果良好。

3. **实时处理结果**（figure_20250921_215312.png和figure_20250921_215457.png）：显示了实时信号处理的最新结果。

最终系统能够：
- 成功接收879.4MHz的NB-IoT信号
- 正确检测出小区身份PCID
- 实现精确的信号同步
- 解调出NPBCH信道信息
- 解析出系统帧号等关键信息

### 2.8 技术总结和收获

这个项目让我们深刻体会到了理论与实践的差距。教科书上的通信原理看起来很简单，但是用软件无线电实现真实信号处理时，会遇到各种意想不到的问题：

1. **硬件特性的影响**：RTL-SDR的频偏、增益控制、动态范围等都会影响信号质量
2. **协议复杂性**：3GPP标准虽然详细，但是实际实现时有很多细节需要注意
3. **工程经验的重要性**：很多参数需要根据实际情况调试，没有标准答案
4. **错误处理的必要性**：实时系统必须能够处理各种异常情况

通过这个项目，我们不仅掌握了NB-IoT的技术细节，更重要的是学会了如何用系统性的方法解决复杂的工程问题。

## 3. 项目文件清单

### 代码文件：
- `rtlsdr_setup.m` - RTL-SDR设备配置和初始化
- `nbiot_realtime_npbch_demod.m` - 实时信号接收和处理主程序
- `nbiot_sync_and_pcid_detection.m` - 信号同步和小区ID检测
- `nbiot_npbch_analysis.m` - NPBCH信道解调和分析

### 数据文件：
- `nbiot_received_signal.mat` - 接收到的原始信号数据
- `nbiot_signalNBRefP1.mat` - 处理后的信号数据
- `nbiot_sync_results.mat` - 同步检测结果
- `nbiot_npbch_results.mat` - NPBCH解调结果

### 结果图片：
- `figure_20250701_182411.png` - PCID检测相关峰图
- `figure_20250701_182453.png` - QPSK星座图对比
- `figure_20250921_215312.png` - 最新处理结果图1
- `figure_20250921_215457.png` - 最新处理结果图2

### 文档资料：
- `苏世鼎_NB-IoT实验报告.docx` - 详细的实验报告和分析

这个案例展示了一个完整的通信系统实现过程，从硬件配置到协议解析，涵盖了软件无线电、数字信号处理、通信协议等多个技术领域，是一个很好的综合性工程实践项目。