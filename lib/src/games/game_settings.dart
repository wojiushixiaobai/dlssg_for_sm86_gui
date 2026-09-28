part of '../../app.dart';

bool _hasManageableConfig(ModStatus status) =>
    status.kind == ModStateKind.applied;

bool _needsDriverUpdate(ModStatus status, String? currentVersion) =>
    status.kind == ModStateKind.applied &&
    (status.version == '未知版本' ||
        (currentVersion != null && status.version != currentVersion));

class GameSettings extends StatefulWidget {
  const GameSettings(
    this.view,
    this.hasMod,
    this.busy,
    this.choose,
    this.manager,
    this.act, {
    required this.launch,
    this.hagsStatus = HardwareAcceleratedGpuSchedulingStatus.unavailable,
    super.key,
  });
  final GameView? view;
  final bool hasMod, busy;
  final Future<void> Function([GameEntry?]) choose;
  final ModManager manager;
  final Future<void> Function(Future<void> Function()) act;
  final ValueChanged<GameView> launch;
  final HardwareAcceleratedGpuSchedulingStatus hagsStatus;
  @override
  State<GameSettings> createState() => _GameSettingsState();
}

class _GameSettingsState extends State<GameSettings> {
  String? proxy = defaultProxy;
  ConfigProfile? config;
  bool loadingConfig = false;

  @override
  void initState() {
    super.initState();
    proxy = _initialProxy(widget.view);
    _loadConfig();
  }

  @override
  void didUpdateWidget(GameSettings old) {
    super.didUpdateWidget(old);
    final gameChanged = old.view?.game.id != widget.view?.game.id;
    if (gameChanged ||
        old.view?.mod.proxy != widget.view?.mod.proxy ||
        old.view?.mod.unrecognizedProxyHashes.length !=
            widget.view?.mod.unrecognizedProxyHashes.length) {
      proxy = _initialProxy(widget.view);
    }
    if (gameChanged) config = null;
    if (gameChanged ||
        old.hasMod != widget.hasMod ||
        old.view?.target != widget.view?.target ||
        old.view?.mod.kind != widget.view?.mod.kind) {
      _loadConfig();
    }
  }

  String? _initialProxy(GameView? view) {
    if ((view?.mod.unrecognizedProxyHashes.length ?? 0) > 1) return null;
    return view?.mod.proxy ?? view?.game.selectedProxy ?? defaultProxy;
  }

  Future<void> _loadConfig() async {
    final view = widget.view;
    final id = view?.game.id;
    final manageable = view != null && _hasManageableConfig(view.mod);
    if (id == null || !manageable) {
      if (mounted) {
        setState(() {
          config = null;
          loadingConfig = false;
        });
      }
      return;
    }
    setState(() => loadingConfig = true);
    try {
      final loaded = await widget.manager.loadGameConfig(id);
      if (mounted && widget.view?.game.id == id) {
        setState(() => config = loaded);
      }
    } finally {
      if (mounted && widget.view?.game.id == id) {
        setState(() => loadingConfig = false);
      }
    }
  }

  Future<void> _saveConfig(ConfigProfile next) async {
    final v = widget.view;
    if (v == null) return;
    setState(() => config = next);
    await widget.act(() => widget.manager.saveGameConfig(v.game.id, next));
  }

  @override
  Widget build(BuildContext c) {
    final v = widget.view;
    if (v == null) return const Empty('从左侧选择游戏。');
    final g = v.game;
    final canInstall =
        widget.hasMod && v.target == TargetState.ready && !widget.busy;
    final manageableConfig = _hasManageableConfig(v.mod);
    final canEdit = manageableConfig && !widget.busy;
    final canUpdate =
        canInstall &&
        proxy != null &&
        _needsDriverUpdate(v.mod, widget.manager.info.installedVersion);
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _GameControlHeader(
            game: g,
            status: v.mod,
            onRun: v.target == TargetState.ready && !widget.busy
                ? () => widget.launch(v)
                : null,
            proxy: proxy,
            onProxyChanged:
                (v.mod.kind == ModStateKind.applied &&
                        v.mod.unrecognizedProxyHashes.isEmpty) ||
                    widget.busy
                ? null
                : (x) => setState(() => proxy = x!),
            hagsStatus: widget.hagsStatus,
            action: v.mod.kind == ModStateKind.applied
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canUpdate)
                        TextButton(
                          style: _inlineActionButtonStyle,
                          onPressed: () => install(c, v),
                          child: const Text('更新'),
                        ),
                      if (v.mod.canUninstall)
                        TextButton(
                          style: _inlineActionButtonStyle,
                          onPressed: widget.busy || proxy == null
                              ? null
                              : () => uninstall(c, v),
                          child: const Text('卸载'),
                        ),
                    ],
                  )
                : TextButton(
                    style: _inlineActionButtonStyle,
                    onPressed: canInstall ? () => install(c, v) : null,
                    child: Text(manageableConfig ? '安装代理' : '安装'),
                  ),
          ),
          const SizedBox(height: 26),
          MouseRegion(
            cursor: widget.busy
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.busy ? null : () => widget.choose(g),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff1d1d1d),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SetRow(
                    'EXE 路径',
                    Text(g.exePath ?? '尚未指定', softWrap: true),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          if (!manageableConfig)
            const _DriverSettingsDisabled()
          else if (loadingConfig || config == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _DirectDriverSettings(
              config: config!,
              enabled: canEdit,
              onChanged: _saveConfig,
            ),
        ],
      ),
    );
  }

  Future<void> install(BuildContext c, GameView v) async {
    final selectedProxy = proxy;
    if (selectedProxy == null) return;
    await widget.act(() async {
      try {
        await widget.manager.installMod(v.game.id, proxy: selectedProxy);
      } on StateError catch (error) {
        final isManualConflict =
            v.game.source.kind == GameSourceKind.manual &&
            error.toString().contains('目标 DLL 不是已知 DLSSG 文件');
        if (!isManualConflict) rethrow;
        if (!c.mounted) return;
        final accepted = await dialog(
          c,
          '覆盖未知 DLL？',
          '将保留该代理 DLL 的原始备份，再安装驱动程序。',
        );
        if (!mounted) return;
        if (accepted) {
          await widget.manager.installMod(
            v.game.id,
            proxy: selectedProxy,
            confirmOverwrite: true,
          );
        }
      }
    });
  }

  Future<void> uninstall(BuildContext c, GameView v) async {
    final selectedProxy = proxy;
    if (selectedProxy == null) return;
    final expectedSha256 = v.mod.unrecognizedProxyHashes[selectedProxy];
    if (expectedSha256 != null) {
      final accepted = await dialog(
        c,
        '卸载未知版本 DLL？',
        '无法验证 $selectedProxy 的来源。确认后将移除该 DLL 和 dlssg_sm86.ini；如有原始备份则恢复。',
      );
      if (!accepted || !mounted) return;
    }
    await widget.act(
      () => widget.manager.uninstallMod(
        v.game.id,
        proxy: selectedProxy,
        confirmUnrecognized: expectedSha256 != null,
        expectedSha256: expectedSha256,
      ),
    );
  }
}
