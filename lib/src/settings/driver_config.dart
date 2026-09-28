part of '../../app.dart';

class _GameControlHeader extends StatelessWidget {
  const _GameControlHeader({
    required this.game,
    required this.status,
    required this.onRun,
    required this.proxy,
    required this.onProxyChanged,
    required this.hagsStatus,
    required this.action,
  });
  final GameEntry game;
  final ModStatus status;
  final VoidCallback? onRun;
  final String? proxy;
  final ValueChanged<String?>? onProxyChanged;
  final HardwareAcceleratedGpuSchedulingStatus hagsStatus;
  final Widget action;

  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xff202020),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GameIcon(game, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: _uiEmphasisWeight,
                    ),
                  ),
                  Text(
                    game.source.kind == GameSourceKind.steam
                        ? 'Steam · ${game.source.appId}'
                        : '手动添加',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              style: _inlineActionButtonStyle,
              onPressed: onRun,
              child: const Text('启动游戏'),
            ),
          ],
        ),
        const Divider(height: 27),
        if (hagsStatus != HardwareAcceleratedGpuSchedulingStatus.enabled) ...[
          _HagsWarning(status: hagsStatus),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Icon(
              status.kind == ModStateKind.applied
                  ? Icons.check_circle
                  : Icons.info_outline,
              color: status.kind == ModStateKind.applied
                  ? const Color(0xff9dcc3a)
                  : Colors.white54,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(modLabel(status))),
            const SizedBox(width: 12),
            action,
          ],
        ),
        const SizedBox(height: 8),
        SetRow(
          '代理 DLL',
          MouseRegion(
            cursor: onProxyChanged == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: DropdownButton<String>(
              value: proxy,
              hint: const Text('请选择代理 DLL'),
              isExpanded: true,
              items:
                  (status.unrecognizedProxyHashes.isEmpty
                          ? proxies
                          : status.unrecognizedProxyHashes.keys)
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
              onChanged: onProxyChanged,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DriverSettingsDisabled extends StatelessWidget {
  const _DriverSettingsDisabled();

  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xff28251c),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline, color: Colors.white60),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('配置功能已禁用', style: TextStyle(fontWeight: _uiEmphasisWeight)),
              SizedBox(height: 3),
              Text(
                '请先安装驱动程序；安装后将读取 dlssg_sm86.ini。',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DirectDriverSettings extends StatelessWidget {
  const _DirectDriverSettings({
    required this.config,
    required this.enabled,
    required this.onChanged,
  });
  final ConfigProfile config;
  final bool enabled;
  final ValueChanged<ConfigProfile> onChanged;

  @override
  Widget build(BuildContext c) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff1d1d1d),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const _DriverSettingsTableHeader(),
          for (final section in config.sections) ...[
            _IniSectionHeader(section.name),
            for (final setting in section.settings)
              _DriverSettingRow(
                section: section.name,
                setting: setting,
                enabled: enabled,
                onChanged: (value) => onChanged(
                  config.withValue(section.name, setting.key, value),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DriverSettingsTableHeader extends StatelessWidget {
  const _DriverSettingsTableHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    decoration: const BoxDecoration(
      color: _nvidiaHeader,
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    child: const Row(
      children: [
        Expanded(
          flex: 6,
          child: Text(
            'Key',
            style: TextStyle(fontSize: 18, fontWeight: _uiEmphasisWeight),
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            'Value',
            style: TextStyle(fontSize: 18, fontWeight: _uiEmphasisWeight),
          ),
        ),
      ],
    ),
  );
}

class _DriverSettingRow extends StatefulWidget {
  const _DriverSettingRow({
    required this.section,
    required this.setting,
    required this.enabled,
    required this.onChanged,
  });

  final String section;
  final IniSetting setting;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_DriverSettingRow> createState() => _DriverSettingRowState();
}

class _DriverSettingRowState extends State<_DriverSettingRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final definition = driverSettingDefinition(
      widget.section,
      widget.setting.key,
    );
    return MouseRegion(
      cursor: MouseCursor.defer,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 61),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: hovered ? _nvidiaHeader : Colors.transparent,
            border: const Border(top: BorderSide(color: Color(0xff2b2b2b))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    Flexible(child: Text(widget.setting.key)),
                    if (definition != null) ...[
                      const SizedBox(width: 6),
                      _DriverSettingInfo(
                        section: widget.section,
                        settingKey: widget.setting.key,
                        definition: definition,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: _DriverSettingValue(
                  section: widget.section,
                  setting: widget.setting,
                  definition: definition,
                  enabled: widget.enabled,
                  onChanged: widget.onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverSettingInfo extends StatelessWidget {
  const _DriverSettingInfo({
    required this.section,
    required this.settingKey,
    required this.definition,
  });

  final String section;
  final String settingKey;
  final DriverSettingDefinition definition;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: IconButton(
      tooltip: definition.description,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      iconSize: 16,
      color: Colors.white60,
      mouseCursor: SystemMouseCursors.click,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('[$section] $settingKey'),
          content: Text(
            '${definition.description}\n\n默认值：${definition.defaultValue.isEmpty ? '留空' : definition.defaultValue}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
      icon: const Icon(Icons.info_outline),
    ),
  );
}

class _DriverSettingValue extends StatelessWidget {
  const _DriverSettingValue({
    required this.section,
    required this.setting,
    required this.definition,
    required this.enabled,
    required this.onChanged,
  });

  final String section;
  final IniSetting setting;
  final DriverSettingDefinition? definition;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (definition case final known? when known.choices.isNotEmpty) {
      return Theme(
        data: Theme.of(context).copyWith(
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: PopupMenuButton<String>(
            enabled: enabled,
            tooltip: '',
            onSelected: onChanged,
            itemBuilder: (context) => [
              for (final option in known.choices)
                PopupMenuItem(value: option, child: Text(option)),
            ],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    setting.value.isEmpty ? '未设置' : setting.value,
                    style: TextStyle(
                      color: enabled ? _nvidiaText : Colors.white38,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: enabled ? Colors.white60 : Colors.white24,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return TextFormField(
      key: ValueKey('$section/${setting.key}'),
      initialValue: setting.value,
      enabled: enabled,
      onFieldSubmitted: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: setting.key == 'CacheDirectory' && setting.value.isEmpty
            ? r'%LOCALAPPDATA%\DlssgSm86\bundles'
            : '按 Enter 保存',
      ),
    );
  }
}

class _IniSectionHeader extends StatelessWidget {
  const _IniSectionHeader(this.section);

  final String section;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 5),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xff2b2b2b))),
    ),
    child: Text(
      '[$section]',
      style: const TextStyle(
        color: _nvidiaGreen,
        fontWeight: _uiEmphasisWeight,
      ),
    ),
  );
}
