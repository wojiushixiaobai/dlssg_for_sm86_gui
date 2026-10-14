class DriverSettingDefinition {
  const DriverSettingDefinition({
    required this.section,
    required this.key,
    required this.defaultValue,
    required this.description,
    this.choices = const [],
  });

  final String section;
  final String key;
  final String defaultValue;
  final String description;
  final List<String> choices;
}

// Public settings in the upstream 0.4.0 release configuration.
// https://github.com/sdli1995/dlssg_for_sm86/blob/0.4.0/dlssg_sm86.ini
const driverSettingDefinitions = <DriverSettingDefinition>[
  DriverSettingDefinition(
    section: "General",
    key: "Enabled",
    defaultValue: "1",
    description: "1 = 启用插帧；0 = 关闭插帧并使用游戏自身的 DLSS-G。超分 INT8 独立控制。",
    choices: ["1", "0"],
  ),
  DriverSettingDefinition(
    section: "FrameGeneration",
    key: "Engine",
    defaultValue: "DLSS",
    description: "DLSS = NVIDIA 插帧；XeSS = Intel 模型插帧。可用倍率、后缓冲格式支持和性能取决于当前发布版本。",
    choices: ["DLSS", "XeSS"],
  ),
  DriverSettingDefinition(
    section: "FrameGeneration",
    key: "MaxGeneratedFrames",
    defaultValue: "3",
    description: "生成帧数量上限：1 = 2X，3 = 4X，5 = 6X。实际倍率取决于当前运行库、所选引擎与游戏支持。",
    choices: ["1", "2", "3", "4", "5"],
  ),
  DriverSettingDefinition(
    section: "DLSSG",
    key: "Optimized",
    defaultValue: "2",
    description: "仅对 DLSS 引擎生效。0 = 原厂内核；1 = 与官方逐位一致的加速；2 = 增加有损图像内核（默认）；3 = 全部有损加速。数字越大越快，画质偏差越大。",
    choices: ["0", "1", "2", "3"],
  ),
  DriverSettingDefinition(
    section: "DLSSG",
    key: "Preset",
    defaultValue: "Auto",
    description: "仅对 DLSS 引擎生效。Auto = 游戏或驱动决定；A = 关闭 UI 重合成；B = 开启 UI 重合成（需游戏提供无 HUD 图像及 UI 平面）；C = FG Lite，降低插帧 GPU 时间，HUD 与遮挡边缘画质略低。",
    choices: ["Auto", "A", "B", "C"],
  ),
  DriverSettingDefinition(
    section: "XeSSFG",
    key: "FlowResolution",
    defaultValue: "Middle",
    description: "仅对 XeSS 引擎生效。光流分辨率从 Coarse、Middle 到 Fine 逐渐提高，越细越慢。",
    choices: ["Coarse", "Middle", "Fine"],
  ),
  DriverSettingDefinition(
    section: "XeSSFG",
    key: "UseHudless",
    defaultValue: "1",
    description:
        "仅对 XeSS 引擎生效。1 = 使用游戏提供的无 HUD 图像并合成 UI；0 = 不使用。游戏不提供时自动按 0 运行。",
    choices: ["1", "0"],
  ),
  DriverSettingDefinition(
    section: "Logging",
    key: "Level",
    defaultValue: "1",
    description: "日志级别：0 = 关闭；1 = 错误；2 = 配置与能力；3 = 内核与执行跟踪。日志写入 Directory。",
    choices: ["0", "1", "2", "3"],
  ),
  DriverSettingDefinition(
    section: "Logging",
    key: "Directory",
    defaultValue: "dlssg_sm86\\logs",
    description: "日志目录，相对于 INI 所在目录。",
    choices: [],
  ),
  DriverSettingDefinition(
    section: "Runtime",
    key: "Mode",
    defaultValue: "Bundled",
    description: "Bundled = 使用当前发布包提供的 DLSS-G 运行库与后端。External、Pinned 用于高级配置，需按该版本安装文档设置额外路径。",
    choices: ["Bundled"],
  ),
  DriverSettingDefinition(
    section: "SuperResolution",
    key: "Mode",
    defaultValue: "Off",
    description: "Off = 不介入超分；On = 启用随包的超分 INT8 加速，使用当前发布包提供的 DLSS SR。支持的显卡、预设和光线重建兼容性以该版本说明为准。修改后请重启游戏，可查看 dlssg_sm86/logs/backend.jsonl 确认。",
    choices: ["Off", "On"],
  ),
];

final _driverSettingDefinitionsByKey = {
  for (final definition in driverSettingDefinitions)
    _definitionKey(definition.section, definition.key): definition,
};

DriverSettingDefinition? driverSettingDefinition(String section, String key) =>
    _driverSettingDefinitionsByKey[_definitionKey(section, key)];

String _definitionKey(String section, String key) =>
    '${section.toLowerCase()}/$key'.toLowerCase();
