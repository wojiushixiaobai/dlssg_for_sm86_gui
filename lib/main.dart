import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui show Image, PixelFormat, decodeImageFromPixels;

import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'driver_settings.dart';
import 'hags.dart';
import 'manager.dart';
import 'models.dart';
import 'steam.dart';

const _nvidiaAppBackground = Color(0xff1b1b1b);
const _nvidiaSidebar = Color(0xff1c1c1c);
const _nvidiaHeader = Color(0xff292929);
const _nvidiaMenuActive = Color(0xff444444);
const _nvidiaGreen = Color(0xff76b900);
const _nvidiaText = Color(0xfff2f2f2);
const _nvidiaMutedText = Color(0xffc8c8c8);
const _installationGuideUrl = 'https://github.com/sdli1995/dlssg_for_sm86';

const _uiFontFamily = 'Microsoft YaHei UI';
const _uiFontFallback = <String>['Microsoft YaHei', 'Segoe UI', 'Arial'];
const _uiEmphasisWeight = FontWeight.w500;
const _controlButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
);
final _buttonMouseCursor = WidgetStateProperty.resolveWith<MouseCursor?>(
  (states) => states.contains(WidgetState.disabled)
      ? SystemMouseCursors.basic
      : SystemMouseCursors.click,
);

final _inlineActionButtonStyle = ButtonStyle(
  mouseCursor: _buttonMouseCursor,
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.disabled) ? Colors.white38 : _nvidiaText,
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => _isActionHighlighted(states)
        ? const Color(0xff343434)
        : Colors.transparent,
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => _isActionHighlighted(states)
        ? const BorderSide(color: Color(0xff555555))
        : BorderSide.none,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  ),
  shape: const WidgetStatePropertyAll(_controlButtonShape),
);

final _inlineIconActionButtonStyle = _inlineActionButtonStyle.copyWith(
  fixedSize: const WidgetStatePropertyAll(Size(42, 42)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
);

bool _isActionHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.focused) ||
    states.contains(WidgetState.pressed);

void _openInstallationGuide() {
  if (!Platform.isWindows) return;
  final operation = 'open'.toNativeUtf16();
  final url = _installationGuideUrl.toNativeUtf16();
  try {
    final result = ShellExecute(
      0,
      operation,
      url,
      nullptr,
      nullptr,
      SW_SHOWNORMAL,
    );
    if (result <= 32) {
      throw StateError('无法使用默认浏览器打开安装说明。');
    }
  } finally {
    calloc.free(operation);
    calloc.free(url);
  }
}

void _openWindowsGraphicsSettings() {
  if (!Platform.isWindows) return;
  final operation = 'open'.toNativeUtf16();
  final target = 'ms-settings:display-advancedgraphics'.toNativeUtf16();
  try {
    final result = ShellExecute(
      0,
      operation,
      target,
      nullptr,
      nullptr,
      SW_SHOWNORMAL,
    );
    if (result <= 32) {
      throw StateError('无法打开 Windows 图形设置。');
    }
  } finally {
    calloc.free(operation);
    calloc.free(target);
  }
}

Future<bool> _openGameExecutableDirectory(String executablePath) async {
  if (!Platform.isWindows) return false;
  final executable = File(executablePath);
  if (!executable.existsSync()) return false;
  try {
    // Explorer requires /select, and the target as separate command-line
    // arguments. ShellExecute can discard that selection argument when it
    // reuses an existing Explorer window.
    await Process.start('explorer.exe', [
      '/select,',
      executable.absolute.path,
    ], mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DlssgApp(await ModManager.open()));
}

class DlssgApp extends StatelessWidget {
  DlssgApp(this.manager, {super.key})
    : artworkCache = SteamArtworkCache(manager.artworkSourcesFile);
  final ModManager manager;
  final SteamArtworkCache artworkCache;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DLSSG for SM86 Manager',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _uiFontFamily,
      fontFamilyFallback: _uiFontFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _nvidiaGreen,
        brightness: Brightness.dark,
        surface: _nvidiaAppBackground,
      ),
      scaffoldBackgroundColor: _nvidiaAppBackground,
      dividerColor: const Color(0xff303030),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: _nvidiaText),
        titleMedium: TextStyle(color: _nvidiaText),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonMouseCursor),
      ),
    ),
    home: ArtworkCacheScope(cache: artworkCache, child: Shell(manager)),
  );
}

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
  const Shell(this.manager, {super.key});
  final ModManager manager;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int page = 0;
  bool gameTab = true, busy = false;
  String? selected, note;
  String? latestDriverVersion;
  DownloadProgress? downloadProgress;
  bool updateCheckFailed = false;
  List<GameView> games = [];
  ManagerInfo? info;
  var hagsStatus = HardwareAcceleratedGpuSchedulingStatus.unavailable;
  late final bool _refreshHagsWhenSwitchingGames;

  @override
  void initState() {
    super.initState();
    hagsStatus = readHagsStatus();
    _refreshHagsWhenSwitchingGames =
        hagsStatus == HardwareAcceleratedGpuSchedulingStatus.disabled;
    load();
  }

  void _refreshHagsStatus() {
    if (_refreshHagsWhenSwitchingGames) hagsStatus = readHagsStatus();
  }

  Future<void> load() async {
    final found = await widget.manager.listGames();
    String? latest;
    var latestFailed = false;
    try {
      latest = await widget.manager.latestDriverVersion();
    } catch (_) {
      latestFailed = true;
    }
    if (mounted) {
      setState(() {
        games = found;
        info = widget.manager.info;
        latestDriverVersion = latest;
        updateCheckFailed = latestFailed;
        selected = found.any((x) => x.game.id == selected)
            ? selected
            : (found.isEmpty ? null : found.first.game.id);
      });
    }
  }

  Future<bool> _runAction(Future<void> Function() job) async {
    setState(() {
      busy = true;
      note = null;
      downloadProgress = null;
    });
    try {
      await job();
      await load();
      return true;
    } catch (e) {
      if (mounted) setState(() => note = '操作失败：$e');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(Future<void> Function() job) async {
    await _runAction(job);
  }

  Future<void> launchGame(GameView game) async {
    setState(() {
      busy = true;
      note = null;
      downloadProgress = null;
    });
    GameRequiresElevationException? elevationError;
    try {
      await widget.manager.launchGame(game.game.id);
      await load();
    } on GameRequiresElevationException catch (error) {
      elevationError = error;
    } catch (error) {
      if (mounted) setState(() => note = '操作失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }

    if (elevationError == null) return;
    final directoryOpened = await _openGameExecutableDirectory(
      elevationError.executablePath,
    );
    if (!mounted) return;
    setState(() {
      note = directoryOpened
          ? '游戏需要管理员权限，已定位并选中游戏 EXE，请手动运行。'
          : '游戏需要管理员权限，请手动运行游戏 EXE。';
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要管理员权限'),
        content: Text(
          directoryOpened
              ? '游戏需要管理员权限，已定位并选中游戏 EXE，请手动运行。'
              : '游戏需要管理员权限，请手动运行游戏 EXE。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

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
      0 => Home(games, openGame, launch: launchGame),
      1 => Drivers(
        info,
        latestDriverVersion,
        updateCheckFailed,
        busy,
        () => act(() async {
          await widget.manager.refreshModFromGithub(
            onProgress: (progress) {
              if (mounted) setState(() => downloadProgress = progress);
            },
          );
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
      body: Row(
        children: [
          NvidiaNavigation(
            selectedIndex: page,
            onSelected: (index) => setState(() {
              page = index;
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
                if (note != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(30, 0, 30, 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xff29391c),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(note!),
                  ),
                Expanded(child: content),
              ],
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

class NvidiaNavigation extends StatelessWidget {
  const NvidiaNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (label: '主页', icon: Icons.home),
    (label: '驱动程序', icon: Icons.archive),
    (label: '游戏设置', icon: Icons.tune),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 108,
    color: _nvidiaSidebar,
    child: Column(
      children: [
        for (var index = 0; index < _items.length; index++)
          _NvidiaNavigationItem(
            label: _items[index].label,
            icon: _items[index].icon,
            selected: selectedIndex == index,
            onTap: () => onSelected(index),
          ),
        const Spacer(),
      ],
    ),
  );
}

class _NvidiaNavigationItem extends StatefulWidget {
  const _NvidiaNavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NvidiaNavigationItem> createState() => _NvidiaNavigationItemState();
}

class _NvidiaNavigationItemState extends State<_NvidiaNavigationItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 85,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 5,
              height: 70,
              decoration: BoxDecoration(
                color: widget.selected ? _nvidiaGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered ? _nvidiaMenuActive : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 28,
                      color: widget.selected ? _nvidiaText : _nvidiaMutedText,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.selected ? _nvidiaText : _nvidiaMutedText,
                        fontSize: 15,
                        fontWeight: _uiEmphasisWeight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
        ),
      ),
    ),
  );
}

class Home extends StatelessWidget {
  const Home(this.games, this.open, {this.launch, super.key});
  final List<GameView> games;
  final ValueChanged<GameView> open;
  final ValueChanged<GameView>? launch;
  @override
  Widget build(BuildContext c) {
    final recent = [
      for (final game in games)
        if (game.game.lastPlayedAt != null) game,
    ]..sort((a, b) => b.game.lastPlayedAt!.compareTo(a.game.lastPlayedAt!));
    final steam = games
        .where((x) => x.game.source.kind == GameSourceKind.steam)
        .toList();
    final manual = games
        .where((x) => x.game.source.kind == GameSourceKind.manual)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
      children: [
        if (recent.isNotEmpty)
          Shelf('最近运行', recent.take(10).toList(), open, launch),
        if (recent.isNotEmpty && (steam.isNotEmpty || manual.isNotEmpty))
          const SizedBox(height: 36),
        if (steam.isNotEmpty)
          Shelf('Steam 库', steam.take(10).toList(), open, launch),
        if (steam.isNotEmpty && manual.isNotEmpty) const SizedBox(height: 36),
        if (manual.isNotEmpty)
          Shelf('其他游戏库', manual.take(10).toList(), open, launch),
        if (games.isEmpty) const Empty('暂未发现游戏。'),
      ],
    );
  }
}

class Shelf extends StatelessWidget {
  const Shelf(this.title, this.games, this.open, this.launch, {super.key});
  final String title;
  final List<GameView> games;
  final ValueChanged<GameView> open;
  final ValueChanged<GameView>? launch;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: _uiEmphasisWeight),
      ),
      const SizedBox(height: 11),
      CardRow(games, open, launch: launch),
    ],
  );
}

class CardRow extends StatefulWidget {
  const CardRow(this.games, this.open, {this.launch, super.key});
  final List<GameView> games;
  final ValueChanged<GameView> open;
  final ValueChanged<GameView>? launch;

  @override
  State<CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<CardRow> {
  static const _cardWidth = 265.0;
  static const _cardHeight = 215.0;
  static const _cardGap = 14.0;
  static const _edgeSpace = 8.0;

  final controller = ScrollController();
  int? hoveredIndex;

  @override
  void initState() {
    super.initState();
    controller.addListener(_clearHoveredCardOnScroll);
  }

  @override
  void dispose() {
    controller.removeListener(_clearHoveredCardOnScroll);
    controller.dispose();
    super.dispose();
  }

  void _clearHoveredCardOnScroll() {
    if (hoveredIndex != null) setState(() => hoveredIndex = null);
  }

  @override
  Widget build(BuildContext c) {
    final contentWidth =
        _edgeSpace * 2 +
        widget.games.length * _cardWidth +
        (widget.games.length - 1) * _cardGap;
    Widget card(int index) => Positioned(
      key: ValueKey('home-game-${widget.games[index].game.id}'),
      left: _edgeSpace + index * (_cardWidth + _cardGap),
      top: 14,
      width: _cardWidth,
      height: _cardHeight,
      child: GameCard(
        widget.games[index],
        () => widget.open(widget.games[index]),
        selected: hoveredIndex == index,
        onHoverChanged: (hovered) {
          if ((hoveredIndex == index && !hovered) ||
              (hoveredIndex != index && hovered)) {
            setState(() => hoveredIndex = hovered ? index : null);
          }
        },
        launch: widget.launch == null
            ? null
            : () => widget.launch!(widget.games[index]),
      ),
    );

    return SizedBox(
      height: 239,
      child: Stack(
        children: [
          Positioned.fill(
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  height: 239,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < widget.games.length; i++)
                        if (i != hoveredIndex) card(i),
                      if (hoveredIndex case final index?) card(index),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GameCard extends StatefulWidget {
  const GameCard(
    this.game,
    this.tap, {
    this.launch,
    this.selected,
    this.onHoverChanged,
    super.key,
  });
  final GameView game;
  final VoidCallback tap;
  final VoidCallback? launch;
  final bool? selected;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool localHovered = false;

  bool get hovered => widget.selected ?? localHovered;

  void changeHover(bool value) {
    if (widget.selected == null && localHovered != value) {
      setState(() => localHovered = value);
    }
    widget.onHoverChanged?.call(value);
  }

  @override
  Widget build(BuildContext c) {
    final game = widget.game;
    final steam = game.game.source.kind == GameSourceKind.steam;
    return SizedBox(
      width: 265,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        scale: hovered ? 1.06 : 1,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => changeHover(true),
          onExit: (_) => changeHover(false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: hovered
                  ? const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Card(
              margin: EdgeInsets.zero,
              color: const Color(0xff272727),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.tap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          steam
                              ? SteamArtwork(
                                  appId: game.game.source.appId!,
                                  cache: ArtworkCacheScope.of(context),
                                  kind: SteamArtworkKind.card,
                                  fit: BoxFit.cover,
                                  fallback: const Cover(),
                                )
                              : const Cover(),
                          if (hovered)
                            ColoredBox(
                              color: const Color(0x88000000),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 106,
                                      child: ElevatedButton(
                                        onPressed: widget.tap,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _nvidiaGreen,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        child: const Text('设置'),
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    SizedBox(
                                      width: 106,
                                      child: TextButton(
                                        onPressed: widget.launch,
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor: const Color(
                                            0xff747474,
                                          ),
                                        ),
                                        child: const Text(
                                          '启动',
                                          style: const TextStyle(
                                            fontWeight: _uiEmphasisWeight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 9, 13, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game.game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: _uiEmphasisWeight,
                            ),
                          ),
                          Text(
                            steam
                                ? 'Steam · ${game.game.source.appId}'
                                : '手动添加',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Chip(
                            label: Text(
                              modLabel(game.mod),
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                game.mod.kind == ModStateKind.applied
                                ? const Color(0xff274915)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Cover extends StatelessWidget {
  const Cover({super.key});
  @override
  Widget build(BuildContext c) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xff36561d), Color(0xff162019)]),
    ),
    child: Center(
      child: Text(
        'DLSSG',
        style: TextStyle(fontSize: 30, fontWeight: _uiEmphasisWeight),
      ),
    ),
  );
}

class Empty extends StatelessWidget {
  const Empty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xff1b1f21),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white60)),
  );
}

bool _hasManageableConfig(ModStatus status) =>
    status.kind == ModStateKind.applied;

bool _needsDriverUpdate(ModStatus status, String? currentVersion) =>
    status.kind == ModStateKind.applied &&
    (status.version == '未知版本' ||
        (currentVersion != null && status.version != currentVersion));

String modLabel(ModStatus x) =>
    x.kind == ModStateKind.applied ? '已安装 · ${x.version ?? '未知版本'}' : '未安装';

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DriverDownloadProgress extends StatelessWidget {
  const _DriverDownloadProgress(this.progress);

  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final current = progress;
    final fraction = current?.fraction;
    final verifying = current?.phase == DownloadPhase.verifying;
    final detail = current == null
        ? '正在准备下载…'
        : verifying
        ? '下载完成，正在校验驱动程序包…'
        : fraction == null
        ? '已下载 ${_formatBytes(current.downloadedBytes)}'
        : '已下载 ${_formatBytes(current.downloadedBytes)} / '
              '${_formatBytes(current.totalBytes!)} '
              '(${(fraction * 100).toStringAsFixed(0)}%)';
    final title = verifying ? '正在校验…' : '正在下载……';
    final percent = fraction == null ? null : '${(fraction * 100).round()}%';
    return Semantics(
      label: detail,
      value: percent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: _uiEmphasisWeight,
                ),
              ),
              const Spacer(),
              if (percent != null)
                Text(
                  percent,
                  style: const TextStyle(fontWeight: _uiEmphasisWeight),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: verifying ? 1 : fraction,
            minHeight: 4,
            color: _nvidiaGreen,
            backgroundColor: const Color(0xff3b3b3b),
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: _nvidiaMutedText)),
        ],
      ),
    );
  }
}

class Drivers extends StatelessWidget {
  const Drivers(
    this.info,
    this.latestVersion,
    this.updateCheckFailed,
    this.busy,
    this.download, {
    this.progress,
    super.key,
  });
  final ManagerInfo? info;
  final String? latestVersion;
  final bool updateCheckFailed;
  final bool busy;
  final VoidCallback download;
  final DownloadProgress? progress;
  @override
  Widget build(BuildContext c) {
    final ready = info?.modAvailable == true;
    final installedVersion = info?.installedVersion;
    final updateAvailable =
        latestVersion != null && latestVersion != installedVersion;
    final upToDate = ready && latestVersion == installedVersion;
    final updateTitle = updateCheckFailed
        ? '暂时无法检查更新'
        : updateAvailable
        ? ready
              ? '有可用的驱动程序更新'
              : '有可用的驱动程序'
        : upToDate
        ? '驱动程序已是最新版本'
        : '正在检查驱动程序更新';
    final updateDetail = updateCheckFailed
        ? '请检查网络连接后重试。'
        : latestVersion != null
        ? '最新版本：$latestVersion'
        : '正在读取上游 latest Release。';
    final pageStatus = updateCheckFailed
        ? '更新检查失败'
        : updateAvailable
        ? '有可用更新'
        : upToDate
        ? '驱动程序已是最新版本'
        : '检查更新中';
    final downloadLabel = updateAvailable
        ? '下载'
        : ready
        ? '重新下载'
        : '下载';
    final updateInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          updateAvailable ? '新 - DLSSG for SM86 驱动程序' : 'DLSSG for SM86 驱动程序',
          style: const TextStyle(fontSize: 21, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(updateDetail, style: const TextStyle(color: _nvidiaMutedText)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('已安装版本', style: TextStyle(color: _nvidiaMutedText)),
            const SizedBox(width: 8),
            Text(installedVersion ?? '尚未安装'),
          ],
        ),
      ],
    );
    final downloadControl = busy
        ? _DriverDownloadProgress(progress)
        : Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: download,
              style: FilledButton.styleFrom(
                backgroundColor: _nvidiaGreen,
                foregroundColor: Colors.black,
                minimumSize: const Size(80, 44),
              ),
              child: Text(downloadLabel),
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 18, 30, 30),
      children: [
        Row(
          children: [
            Text(
              pageStatus,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: _uiEmphasisWeight,
              ),
            ),
            const Spacer(),
            const Text(
              'DLSSG for SM86 驱动程序',
              style: TextStyle(color: _nvidiaMutedText, fontSize: 16),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.expand_more, color: _nvidiaMutedText),
          ],
        ),
        const Divider(height: 26),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 920
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    updateInfo,
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: downloadControl),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: updateInfo),
                    const SizedBox(width: 34),
                    SizedBox(width: 520, child: downloadControl),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _DriverUpdateHero(
          title: updateTitle,
          detail: updateCheckFailed
              ? '暂时无法获取上游版本信息。恢复网络后可再次下载并校验驱动程序。'
              : '下载经过校验的最新版驱动程序包，为支持的游戏启用 DLSSG for SM86。',
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _nvidiaGreen, width: 5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '最新版本会从 sdli1995/dlssg_for_sm86 的 GitHub latest Release 获取。下载完成后会校验所需 DLL 并缓存安装包；不会改动已安装游戏的 INI。',
                style: TextStyle(color: _nvidiaMutedText, height: 1.55),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: _openInstallationGuide,
                style: TextButton.styleFrom(
                  foregroundColor: _nvidiaText,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                child: const Text(
                  '了解安装方式',
                  style: TextStyle(fontWeight: _uiEmphasisWeight),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 15),
        Text(
          ready ? '已安装 - DLSSG for SM86 驱动程序' : '尚未安装 - DLSSG for SM86 驱动程序',
          style: const TextStyle(fontSize: 19, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(
          installedVersion == null ? '版本：尚未安装' : '版本：$installedVersion',
          style: const TextStyle(color: _nvidiaMutedText),
        ),
      ],
    );
  }
}

class _DriverUpdateHero extends StatelessWidget {
  const _DriverUpdateHero({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 224),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xff080a0b),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xff242424)),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -70,
          top: -120,
          child: Container(
            width: 440,
            height: 440,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _nvidiaGreen.withValues(alpha: 0.22),
                  const Color(0xff101a0c).withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0, .45, 1],
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(100, 32, 28, 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DLSSG for SM86\n驱动程序更新',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: _uiEmphasisWeight,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        color: _nvidiaGreen,
                        fontWeight: _uiEmphasisWeight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: _nvidiaMutedText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Center(
                child: Icon(
                  title.contains('失败') ? Icons.error_outline : Icons.memory,
                  size: 96,
                  color: _nvidiaGreen.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
        const Positioned(
          left: 42,
          top: 0,
          bottom: 0,
          child: VerticalDivider(width: 1, thickness: 3, color: _nvidiaGreen),
        ),
      ],
    ),
  );
}

class Settings extends StatelessWidget {
  const Settings({
    super.key,
    required this.games,
    required this.selected,
    required this.gameTab,
    required this.hasMod,
    required this.busy,
    required this.onTab,
    required this.onSelect,
    required this.choose,
    required this.remove,
    required this.manager,
    required this.act,
    required this.launch,
    this.hagsStatus = HardwareAcceleratedGpuSchedulingStatus.unavailable,
  });
  final List<GameView> games;
  final GameView? selected;
  final bool gameTab, hasMod, busy;
  final ValueChanged<bool> onTab;
  final ValueChanged<String> onSelect;
  final Future<void> Function([GameEntry?]) choose;
  final ValueChanged<GameView> remove;
  final ModManager manager;
  final Future<void> Function(Future<void> Function()) act;
  final ValueChanged<GameView> launch;
  final HardwareAcceleratedGpuSchedulingStatus hagsStatus;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
    child: Column(
      children: [
        Row(
          children: [
            _SettingsTab('程序设置', gameTab, () => onTab(true)),
            _SettingsTab('全局设置', !gameTab, () => onTab(false)),
          ],
        ),
        const Divider(height: 1),
        if (!hasMod)
          const Padding(padding: EdgeInsets.only(top: 13), child: Lock()),
        const SizedBox(height: 15),
        Expanded(
          child: gameTab
              ? Row(
                  children: [
                    SizedBox(
                      width: 330,
                      child: GameList(
                        games,
                        selected?.game.id,
                        onSelect,
                        () => choose(),
                        remove,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GameSettings(
                        selected,
                        hasMod,
                        busy,
                        choose,
                        manager,
                        act,
                        launch: launch,
                        hagsStatus: hagsStatus,
                      ),
                    ),
                  ],
                )
              : GlobalSettings(hasMod, manager, act),
        ),
      ],
    ),
  );
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab(this.label, this.selected, this.tap);
  final String label;
  final bool selected;
  final VoidCallback tap;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool hovered = false;

  @override
  Widget build(BuildContext c) => SizedBox(
    width: 130,
    height: 60,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Semantics(
        button: true,
        selected: widget.selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.tap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? _nvidiaMenuActive : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: widget.selected
                      ? const Color(0xff76b900)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: _uiEmphasisWeight,
                color: widget.selected ? Colors.white : Colors.white60,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Lock extends StatelessWidget {
  const Lock({super.key});
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xff40351c),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock),
        SizedBox(width: 9),
        Text('配置功能已锁定：请先在“驱动程序”页面下载并验证 dlssg_for_sm86。'),
      ],
    ),
  );
}

enum GameSort { name, newest }

class GameList extends StatefulWidget {
  const GameList(
    this.games,
    this.selected,
    this.change,
    this.add,
    this.remove, {
    super.key,
  });
  final List<GameView> games;
  final String? selected;
  final ValueChanged<String> change;
  final VoidCallback add;
  final ValueChanged<GameView> remove;

  @override
  State<GameList> createState() => _GameListState();
}

class _GameListState extends State<GameList> {
  GameSort sort = GameSort.name;

  List<GameView> get ordered {
    final entries = [...widget.games];
    entries.sort(
      (a, b) => switch (sort) {
        GameSort.name => a.game.name.toLowerCase().compareTo(
          b.game.name.toLowerCase(),
        ),
        GameSort.newest => (b.game.createdAt ?? DateTime(0)).compareTo(
          a.game.createdAt ?? DateTime(0),
        ),
      },
    );
    return entries;
  }

  @override
  Widget build(BuildContext c) {
    final entries = ordered;
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xff1f1f1f),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '程序  ${widget.games.length}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: _uiEmphasisWeight,
                    ),
                  ),
                ),
                PopupMenuButton<GameSort>(
                  tooltip: '排序',
                  initialValue: sort,
                  onSelected: (value) => setState(() => sort = value),
                  style: _inlineIconActionButtonStyle,
                  icon: const Icon(Icons.sort),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: GameSort.name, child: Text('按名称排序')),
                    PopupMenuItem(
                      value: GameSort.newest,
                      child: Text('按最近添加排序'),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: widget.add,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('添加游戏'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? const Empty('使用“添加游戏”将其他游戏加入此列表。')
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final x = entries[i];
                      return ListTile(
                        mouseCursor: SystemMouseCursors.click,
                        selected: x.game.id == widget.selected,
                        selectedTileColor: const Color(0xff2b3d1c),
                        leading: GameIcon(x.game),
                        title: Text(
                          x.game.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          x.game.source.kind == GameSourceKind.steam
                              ? 'Steam · ${x.game.source.appId}'
                              : '手动添加',
                        ),
                        trailing: Icon(
                          x.mod.kind == ModStateKind.applied
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: x.mod.kind == ModStateKind.applied
                              ? const Color(0xff9dcc3a)
                              : Colors.white38,
                          size: 18,
                        ),
                        onTap: () => widget.change(x.game.id),
                        onLongPress: () => widget.remove(x),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

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
  String proxy = defaultProxy;
  ConfigProfile? config;
  bool loadingConfig = false;

  @override
  void initState() {
    super.initState();
    proxy =
        widget.view?.mod.proxy ??
        widget.view?.game.selectedProxy ??
        defaultProxy;
    _loadConfig();
  }

  @override
  void didUpdateWidget(GameSettings old) {
    super.didUpdateWidget(old);
    final gameChanged = old.view?.game.id != widget.view?.game.id;
    if (gameChanged) {
      proxy =
          widget.view?.mod.proxy ??
          widget.view?.game.selectedProxy ??
          defaultProxy;
      config = null;
    }
    if (gameChanged ||
        old.hasMod != widget.hasMod ||
        old.view?.target != widget.view?.target ||
        old.view?.mod.kind != widget.view?.mod.kind) {
      _loadConfig();
    }
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
    final needsUpdate = _needsDriverUpdate(
      v.mod,
      widget.manager.info.installedVersion,
    );
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
            onProxyChanged: v.mod.kind == ModStateKind.applied || widget.busy
                ? null
                : (x) => setState(() => proxy = x!),
            hagsStatus: widget.hagsStatus,
            action: v.mod.kind == ModStateKind.applied
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (needsUpdate)
                        TextButton(
                          style: _inlineActionButtonStyle,
                          onPressed: canInstall ? () => install(c, v) : null,
                          child: const Text('更新'),
                        ),
                      TextButton(
                        style: _inlineActionButtonStyle,
                        onPressed: widget.busy
                            ? null
                            : () => widget.act(
                                () => widget.manager.uninstallMod(g.id),
                              ),
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
    await widget.act(() async {
      try {
        await widget.manager.installMod(v.game.id, proxy: proxy);
      } on StateError catch (error) {
        final isManualConflict =
            v.game.source.kind == GameSourceKind.manual &&
            error.toString().contains('目标 DLL 不是已知 DLSSG 文件');
        if (!isManualConflict) rethrow;
        if (!c.mounted) return;
        final accepted = await dialog(
          c,
          '覆盖未知 DLL？',
          '将保存原始 DLL 的单一最新备份，再安装驱动程序。',
        );
        if (!mounted) return;
        if (accepted) {
          await widget.manager.installMod(
            v.game.id,
            proxy: proxy,
            confirmOverwrite: true,
          );
        }
      }
    });
  }
}

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
  final String proxy;
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
            Expanded(
              child: Text(
                status.kind == ModStateKind.applied
                    ? '驱动已安装 · ${status.version ?? '未知版本'}'
                    : '驱动尚未安装',
              ),
            ),
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
              isExpanded: true,
              items: proxies
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

class _HagsWarning extends StatelessWidget {
  const _HagsWarning({required this.status});

  final HardwareAcceleratedGpuSchedulingStatus status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.warning_amber_rounded, color: Colors.white54),
      const SizedBox(width: 10),
      Expanded(
        child: Text(switch (status) {
          HardwareAcceleratedGpuSchedulingStatus.disabled => '硬件加速 GPU 调度未开启',
          HardwareAcceleratedGpuSchedulingStatus.unavailable =>
            '无法读取硬件加速 GPU 调度状态',
          HardwareAcceleratedGpuSchedulingStatus.enabled => '',
        }),
      ),
      const SizedBox(width: 12),
      TextButton(
        style: _inlineActionButtonStyle,
        onPressed: _openWindowsGraphicsSettings,
        child: const Text('设置'),
      ),
    ],
  );
}

class SteamArtwork extends StatefulWidget {
  const SteamArtwork({
    required this.appId,
    required this.cache,
    required this.fallback,
    required this.kind,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    super.key,
  });

  final int appId;
  final SteamArtworkCache cache;
  final SteamArtworkKind kind;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<SteamArtwork> createState() => _SteamArtworkState();
}

class _SteamArtworkState extends State<SteamArtwork> {
  late Future<SteamArtworkSource?> _artwork;
  var _retryingNetworkSource = false;

  @override
  void initState() {
    super.initState();
    _artwork = widget.cache.load(widget.appId, kind: widget.kind);
  }

  @override
  void didUpdateWidget(covariant SteamArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appId != widget.appId ||
        oldWidget.cache != widget.cache ||
        oldWidget.kind != widget.kind) {
      _artwork = widget.cache.load(widget.appId, kind: widget.kind);
      _retryingNetworkSource = false;
    }
  }

  void _tryNextNetworkSource(String failedUrl) {
    if (_retryingNetworkSource) return;
    _retryingNetworkSource = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final next = await widget.cache.nextNetworkSource(
        widget.appId,
        failedUrl,
        kind: widget.kind,
      );
      if (mounted && next != null) {
        setState(() {
          _artwork = Future.value(next);
          _retryingNetworkSource = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SteamArtworkSource?>(
    future: _artwork,
    builder: (_, snapshot) {
      final source = snapshot.data;
      if (source == null) return widget.fallback;
      return source.local
          ? Image.file(
              File(source.value),
              fit: widget.fit,
              alignment: widget.alignment,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => widget.fallback,
            )
          : Image.network(
              source.value,
              fit: widget.fit,
              alignment: widget.alignment,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) {
                _tryNextNetworkSource(source.value);
                return widget.fallback;
              },
            );
    },
  );
}

class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {this.size = 40, super.key});
  final GameEntry game;
  final double size;

  @override
  Widget build(BuildContext c) {
    final appId = game.source.appId;
    final fallback = appId == null
        ? const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xff283129)),
            child: Icon(Icons.sports_esports, color: Color(0xff9dcc3a)),
          )
        : SteamArtwork(
            appId: appId,
            cache: ArtworkCacheScope.of(c),
            kind: SteamArtworkKind.icon,
            fit: BoxFit.cover,
            fallback: const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xff283129)),
              child: Icon(Icons.sports_esports, color: Color(0xff9dcc3a)),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: SizedBox(
        width: size,
        height: size,
        child: ExecutableIcon(executablePath: game.exePath, fallback: fallback),
      ),
    );
  }
}

class ExecutableIcon extends StatefulWidget {
  const ExecutableIcon({
    required this.executablePath,
    required this.fallback,
    super.key,
  });

  final String? executablePath;
  final Widget fallback;

  @override
  State<ExecutableIcon> createState() => _ExecutableIconState();
}

class _ExecutableIconState extends State<ExecutableIcon> {
  static const _channel = MethodChannel('dlssg/executable-icon');
  Future<ui.Image?>? _icon;
  ui.Image? _displayedImage;
  final _deferredDisposals = <ui.Image>[];

  @override
  void initState() {
    super.initState();
    _replaceIcon();
  }

  @override
  void didUpdateWidget(covariant ExecutableIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.executablePath != widget.executablePath) _replaceIcon();
  }

  void _replaceIcon() {
    final icon = _load();
    _icon = icon;
    unawaited(
      icon.then<void>((image) {
        if (!mounted || !identical(_icon, icon)) {
          image?.dispose();
          return;
        }
        final previous = _displayedImage;
        _displayedImage = image;
        if (previous != null && !identical(previous, image)) {
          // FutureBuilder still renders the previous image until it rebuilds
          // with this future's result, so release it after that frame.
          _deferredDisposals.add(previous);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_deferredDisposals.remove(previous)) previous.dispose();
          });
        }
      }, onError: (_, _) {}),
    );
  }

  @override
  void dispose() {
    _displayedImage?.dispose();
    for (final image in _deferredDisposals) {
      image.dispose();
    }
    _deferredDisposals.clear();
    super.dispose();
  }

  Future<ui.Image?> _load() async {
    final path = widget.executablePath;
    if (path == null || !File(path).existsSync()) return null;
    try {
      final icon = await _channel.invokeMapMethod<String, dynamic>('extract', {
        'path': path,
      });
      final bytes = icon?['pixels'];
      final size = icon?['size'];
      if (bytes is! Uint8List ||
          size is! int ||
          bytes.length != size * size * 4) {
        return null;
      }
      return await _decodeBgraIcon(bytes, size);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ui.Image> _decodeBgraIcon(Uint8List bytes, int size) {
    final result = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      size,
      size,
      ui.PixelFormat.bgra8888,
      result.complete,
      rowBytes: size * 4,
    );
    return result.future;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
    future: _icon,
    builder: (_, snapshot) => snapshot.data == null
        ? widget.fallback
        : RawImage(
            image: snapshot.data,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
  );
}

class SetRow extends StatelessWidget {
  const SetRow(this.label, this.value, {super.key});
  final String label;
  final Widget value;

  static const _labelWidth = 190.0;
  static const _columnGap = 24.0;

  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        const SizedBox(width: _columnGap),
        Expanded(child: value),
      ],
    ),
  );
}

Future<bool> dialog(BuildContext c, String t, String b) async =>
    (await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(t),
        content: Text(b),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('继续'),
          ),
        ],
      ),
    )) ??
    false;

class GlobalSettings extends StatefulWidget {
  const GlobalSettings(this.hasMod, this.manager, this.act, {super.key});
  final bool hasMod;
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
            enabled: true,
            onChanged: _save,
          ),
      ],
    ),
  );
}
