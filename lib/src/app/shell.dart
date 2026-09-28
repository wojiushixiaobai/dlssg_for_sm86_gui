part of '../../app.dart';

class ArtworkCacheScope extends InheritedWidget {
  const ArtworkCacheScope({
    required this.cache,
    required super.child,
    super.key,
  });

  final SteamArtworkCache cache;

  static SteamArtworkCache of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkCacheScope>()!.cache;

  @override
  bool updateShouldNotify(ArtworkCacheScope oldWidget) =>
      cache != oldWidget.cache;
}

class Shell extends StatefulWidget {
  const Shell(
    this.manager, {
    this.initialGames,
    this.hagsStatusReader,
    super.key,
  });
  final ModManager manager;
  final List<GameView>? initialGames;
  final HardwareAcceleratedGpuSchedulingStatus Function()? hagsStatusReader;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int page = 0;
  bool gameTab = true, busy = false;
  String? selected, toast;
  String? latestDriverVersion;
  DownloadProgress? downloadProgress;
  bool updateCheckFailed = false;
  bool _checkingUpdates = false;
  DateTime? _lastUpdateCheck;
  List<GameView> games = [];
  bool gamesLoaded = false;
  ManagerInfo? info;
  var hagsStatus = HardwareAcceleratedGpuSchedulingStatus.unavailable;
  Timer? _toastTimer;
  int _toastSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hagsStatus = _readHagsStatus();
    final initialGames = widget.initialGames;
    if (initialGames != null) {
      games = initialGames;
      gamesLoaded = true;
      info = widget.manager.info;
      selected = initialGames.isEmpty ? null : initialGames.first.game.id;
    } else {
      unawaited(load());
    }
    unawaited(_checkForUpdates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        hagsStatus == HardwareAcceleratedGpuSchedulingStatus.unavailable) {
      final status = _readHagsStatus();
      if (status != hagsStatus) setState(() => hagsStatus = status);
    }
  }

  HardwareAcceleratedGpuSchedulingStatus _readHagsStatus() =>
      (widget.hagsStatusReader ?? readHagsStatus)();

  void _showToast(String message) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      toast = message;
      _toastSerial++;
    });
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => toast = null);
    });
  }

  void _clearToast() {
    _toastTimer?.cancel();
    toast = null;
  }

  void _refreshHagsStatus() {
    if (hagsStatus == HardwareAcceleratedGpuSchedulingStatus.unavailable) {
      hagsStatus = _readHagsStatus();
    }
  }

  Future<void> load() async {
    final found = await widget.manager.listGames();
    if (mounted) {
      setState(() {
        games = found;
        gamesLoaded = true;
        info = widget.manager.info;
        selected = found.any((x) => x.game.id == selected)
            ? selected
            : (found.isEmpty ? null : found.first.game.id);
      });
    }
  }

  Future<void> _checkForUpdates() async {
    final lastCheck = _lastUpdateCheck;
    final cacheDuration = Duration(minutes: updateCheckFailed ? 1 : 30);
    if (_checkingUpdates ||
        (lastCheck != null &&
            DateTime.now().difference(lastCheck) < cacheDuration)) {
      return;
    }
    _checkingUpdates = true;
    try {
      final latest = await widget.manager.latestDriverVersion();
      if (mounted) {
        setState(() {
          latestDriverVersion = latest;
          updateCheckFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => updateCheckFailed = true);
    } finally {
      _lastUpdateCheck = DateTime.now();
      _checkingUpdates = false;
    }
  }

  Future<void> act(Future<void> Function() job) async {
    if (busy) return;
    setState(() {
      busy = true;
      _clearToast();
      downloadProgress = null;
    });
    try {
      await job();
      await load();
    } catch (e) {
      _showToast('操作失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> launchGame(GameView game) =>
      act(() => widget.manager.launchGame(game.game.id));

  Future<void> removeGame(GameView game) async {
    if (busy) return;
    await act(() => widget.manager.removeGame(game.game.id));
  }

  Future<void> choose([GameEntry? game]) async {
    final initialDirectory = game == null
        ? null
        : await widget.manager.gameDirectory(game);
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '游戏程序', extensions: ['exe']),
      ],
      initialDirectory: initialDirectory,
      confirmButtonText: '选择游戏 EXE',
    );
    if (f == null) return;
    await act(() async {
      if (game == null) {
        await widget.manager.addManualGame(
          f.name.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), ''),
          f.path,
        );
      } else {
        await widget.manager.setGameExe(game.id, f.path);
      }
    });
  }

  GameView? get current {
    for (final game in games) {
      if (game.game.id == selected) return game;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (page) {
      0 =>
        gamesLoaded
            ? Home(games, openGame, launch: launchGame)
            : const Center(
                child: CircularProgressIndicator(color: _nvidiaGreen),
              ),
      1 => Drivers(
        info,
        latestDriverVersion,
        updateCheckFailed,
        busy,
        () => act(() async {
          final version = await widget.manager.refreshModFromGithub(
            onProgress: (progress) {
              if (mounted) setState(() => downloadProgress = progress);
            },
          );
          if (mounted) {
            setState(() {
              latestDriverVersion = version;
              updateCheckFailed = false;
              _lastUpdateCheck = DateTime.now();
            });
          }
        }),
        progress: downloadProgress,
      ),
      _ => Settings(
        games: games,
        selected: current,
        gameTab: gameTab,
        hasMod: info?.modAvailable == true,
        busy: busy,
        onTab: (x) => setState(() {
          gameTab = x;
          if (x) _refreshHagsStatus();
        }),
        onSelect: (id) => setState(() {
          selected = id;
          _refreshHagsStatus();
        }),
        choose: choose,
        remove: removeGame,
        manager: widget.manager,
        act: act,
        launch: launchGame,
        hagsStatus: hagsStatus,
      ),
    };
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              NvidiaNavigation(
                selectedIndex: page,
                onSelected: (index) => setState(() {
                  page = index;
                  if (index == 1) unawaited(_checkForUpdates());
                  if (index == 2) _refreshHagsStatus();
                }),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 70,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      color: _nvidiaHeader,
                      child: Text(
                        ['主页', '驱动程序', '游戏设置'][page],
                        style: const TextStyle(
                          color: _nvidiaText,
                          fontSize: 24,
                          fontWeight: _uiEmphasisWeight,
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          ),
          if (toast != null)
            Positioned(
              top: 80,
              left: 138,
              right: 30,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('toast-$_toastSerial'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 180),
                      builder: (context, progress, child) => Opacity(
                        opacity: progress,
                        child: Transform.translate(
                          offset: Offset(0, -8 * (1 - progress)),
                          child: child,
                        ),
                      ),
                      child: Material(
                        color: const Color(0xff323232),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 20,
                                color: Color(0xffffb17a),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  toast!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void openGame(GameView game) => setState(() {
    selected = game.game.id;
    page = 2;
    gameTab = true;
  });
}
