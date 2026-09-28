part of '../../app.dart';

class GlobalSettings extends StatefulWidget {
  const GlobalSettings(
    this.hasMod,
    this.manager,
    this.act, {
    this.busy = false,
    super.key,
  });
  final bool hasMod;
  final bool busy;
  final ModManager manager;
  final Future<void> Function(Future<void> Function()) act;
  @override
  State<GlobalSettings> createState() => _GlobalSettingsState();
}

class _GlobalSettingsState extends State<GlobalSettings> {
  ConfigProfile? config;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GlobalSettings old) {
    super.didUpdateWidget(old);
    if (old.hasMod != widget.hasMod) _load();
  }

  Future<void> _load() async {
    if (!widget.hasMod) {
      if (mounted) setState(() => config = null);
      return;
    }
    setState(() => loading = true);
    try {
      final loaded = await widget.manager.loadGlobalConfig();
      if (mounted) setState(() => config = loaded);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save(ConfigProfile next) async {
    setState(() => config = next);
    await widget.act(() => widget.manager.saveGlobalConfig(next));
  }

  @override
  Widget build(BuildContext c) => Card(
    child: ListView(
      padding: const EdgeInsets.all(25),
      children: [
        const Text(
          '全局配置',
          style: TextStyle(fontSize: 23, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 4),
        const Text(
          '安装游戏时默认使用此配置。修改会同步到仍使用全局配置的已安装游戏。',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 22),
        if (!widget.hasMod)
          const _DriverSettingsDisabled()
        else if (loading || config == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _DirectDriverSettings(
            config: config!,
            enabled: !widget.busy,
            onChanged: _save,
          ),
      ],
    ),
  );
}
