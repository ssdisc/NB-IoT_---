%% RTL-SDR设置和配置
% 此脚本用于设置和配置RTL-SDR接收器以接收NB-IoT信号
% 中心频率设置为959.8MHz，考虑设备频偏为55ppm

function sdrobj = rtlsdr_setup()
    % 检查是否已安装RTL-SDR支持包
    if ~exist('comm.SDRRTLReceiver', 'class')
        error('未安装RTL-SDR支持包。请使用MATLAB Add-On Explorer安装RTL-SDR支持包。');
    end

    % 创建RTL-SDR接收器对象
    sdrobj = comm.SDRRTLReceiver;

    % 设置接收参数
    % NB-IoT带宽为180kHz，采样率设置为1.92MHz（LTE采样率）
    sdrobj.SampleRate = 1.92e6;

    % 设置中心频率（879.4MHz）
    sdrobj.CenterFrequency = 879.4e6;
        % sdrobj.CenterFrequency = 879.4e6;


    % 设置频率校正因子（ppm）
    sdrobj.FrequencyCorrection = 21;  % 设备频偏为21ppm

    % 设置增益模式和增益
    sdrobj.EnableTunerAGC = true;
    sdrobj.TunerGain = 80;  % 可根据实际情况调整

    % 设置帧长度
    % NB-IoT子帧长度为10ms，对应于1.92MHz采样率下的19200个样本
    sdrobj.SamplesPerFrame = 19200;

    % 设置输出数据类型为single
    sdrobj.OutputDataType = 'single';

    % 输出配置信息
    fprintf('RTL-SDR配置完成:\n');
    fprintf('中心频率: %.2f MHz\n', sdrobj.CenterFrequency/1e6);
    fprintf('采样率: %.2f MHz\n', sdrobj.SampleRate/1e6);
    fprintf('频率校正: %d ppm\n', sdrobj.FrequencyCorrection);
    if sdrobj.EnableTunerAGC
        fprintf('增益模式: 自动 (AGC)\n');
    else
        fprintf('增益模式: 手动\n');
    end
    if ~sdrobj.EnableTunerAGC
        fprintf('增益: %d dB\n', sdrobj.TunerGain);
    end
    fprintf('每帧样本数: %d\n', sdrobj.SamplesPerFrame);
    fprintf('输出数据类型: %s\n', sdrobj.OutputDataType);
end
