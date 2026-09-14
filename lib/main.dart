import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'manager.dart';
import 'models.dart';

// Colours sampled from the supplied NVIDIA App references.  Keeping these in
// one place prevents the navigation chrome drifting away from the page body.
const _nvidiaAppBackground = Color(0xff1b1b1b);
const _nvidiaSidebar = Color(0xff1c1c1c);
const _nvidiaHeader = Color(0xff292929);
const _nvidiaMenuActive = Color(0xff444444);
const _nvidiaGreen = Color(0xff76b900);
const _nvidiaText = Color(0xfff2f2f2);
const _nvidiaMutedText = Color(0xffc8c8c8);

// Windows' default Material and glyph fallback fonts render Chinese at
// noticeably different weights.  Use one UI font for every Material text role
// so labels, buttons and dropdown values have a consistent Chinese face.
const _uiFontFamily = 'Microsoft YaHei UI';
const _uiFontFallback = <String>['Microsoft YaHei', 'Segoe UI', 'Arial'];
const _controlButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
);

/// NVIDIA App-style inline actions: no persistent outline, with a restrained
/// dark highlight and border only while the action is targeted.
final _inlineActionButtonStyle = ButtonStyle(
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

/// Compact version of the inline action treatment for toolbar icons such as
/// the game-list sort menu.
final _inlineIconActionButtonStyle = _inlineActionButtonStyle.copyWith(
  fixedSize: const WidgetStatePropertyAll(Size(42, 42)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
);

bool _isActionHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.focused) ||
    states.contains(WidgetState.pressed);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DlssgApp(await ModManager.open()));
}

class DlssgApp extends StatelessWidget {
  const DlssgApp(this.manager, {super.key});
  final ModManager manager;
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
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(_controlButtonShape)),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(_controlButtonShape)),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(_controlButtonShape)),
      ),
      elevatedButtonTheme: const ElevatedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(_controlButtonShape)),
      ),
    ),
    home: Shell(manager),
  );
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
  List<GameView> games = [];
  List<ConfigProfile> profiles = [];
  ManagerInfo? info;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final found = await widget.manager.listGames();
    final saved = await widget.manager.listProfiles();
    if (mounted)
      setState(() {
        games = found;
        profiles = saved;
        info = widget.manager.info;
        selected = found.any((x) => x.game.id == selected)
            ? selected
            : (found.isEmpty ? null : found.first.game.id);
      });
  }

  Future<void> act(Future<void> Function() job, [String? success]) async {
    setState(() {
      busy = true;
      note = null;
    });
    try {
      await job();
      await load();
      if (mounted && success != null) setState(() => note = success);
    } catch (e) {
      if (mounted) setState(() => note = '操作失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    final found = games.where((x) => x.game.id == selected);
    return found.isEmpty ? null : found.first;
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (page) {
      0 => Home(
        games,
        openGame,
        launch: (game) {
          act(
            () => widget.manager.launchGame(game.game.id),
            '${game.game.name} 已启动。',
          );
        },
      ),
      1 => Drivers(
        info,
        busy,
        () => act(() async {
          final v = await widget.manager.refreshModFromGithub();
          if (mounted) setState(() => note = 'Mod $v 已就绪并完成校验。');
        }),
      ),
      _ => Settings(
        games: games,
        profiles: profiles,
        selected: current,
        gameTab: gameTab,
        hasMod: info?.modAvailable == true,
        busy: busy,
        onTab: (x) => setState(() => gameTab = x),
        onSelect: (id) => setState(() => selected = id),
        choose: choose,
        manager: widget.manager,
        act: act,
      ),
    };
    return Scaffold(
      body: Row(
        children: [
          NvidiaNavigation(
            selectedIndex: page,
            onSelected: (index) => setState(() => page = index),
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
                      fontWeight: FontWeight.w600,
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

/// The NVIDIA App navigation uses a left accent, rather than a pill-shaped
/// selection indicator.  A dedicated widget keeps selected and idle entries
/// visually identical to the supplied references on every page.
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
                // The green bar identifies the open page.  The grey card is
                // only shown when the pointer is over the menu icon.
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
                        fontWeight: FontWeight.w600,
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
    final steam = games
        .where((x) => x.game.source.kind == GameSourceKind.steam)
        .toList();
    final manual = games
        .where((x) => x.game.source.kind == GameSourceKind.manual)
        .toList();
    return ListView(
      // Keep the first visible shelf clear of the page header even when the
      // optional recent-games shelf is empty.
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
      children: [
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
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
  final controller = ScrollController();
  bool showPrevious = false;
  bool showNext = false;

  @override
  void initState() {
    super.initState();
    // The precise extent is available after layout; show the forward control
    // initially for a multi-card shelf, then replace it with the measured
    // availability in the post-frame callback below.
    showNext = widget.games.length > 1;
    controller.addListener(_updateArrowVisibility);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateArrowVisibility(),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_updateArrowVisibility);
    controller.dispose();
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!controller.hasClients) return;
    final previous = controller.offset > 1;
    final next = controller.offset < controller.position.maxScrollExtent - 1;
    if (previous != showPrevious || next != showNext) {
      setState(() {
        showPrevious = previous;
        showNext = next;
      });
    }
  }

  void move(double amount) {
    if (!controller.hasClients) return;
    controller.animateTo(
      (controller.offset + amount).clamp(
        0,
        controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext c) => SizedBox(
    height: 215,
    child: Stack(
      children: [
        Positioned.fill(
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.games.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => GameCard(
              widget.games[i],
              () => widget.open(widget.games[i]),
              launch: widget.launch == null
                  ? null
                  : () => widget.launch!(widget.games[i]),
            ),
          ),
        ),
        if (showPrevious)
          Align(
            alignment: Alignment.centerLeft,
            child: _LibraryArrow(Icons.chevron_left, () => move(-560)),
          ),
        if (showNext)
          Align(
            alignment: Alignment.centerRight,
            child: _LibraryArrow(Icons.chevron_right, () => move(560)),
          ),
      ],
    ),
  );
}

class _LibraryArrow extends StatelessWidget {
  const _LibraryArrow(this.icon, this.press);
  final IconData icon;
  final VoidCallback press;

  @override
  Widget build(BuildContext c) => SizedBox(
    width: 50,
    height: 50,
    child: IconButton(
      onPressed: press,
      icon: Icon(icon, size: 30),
      color: Colors.white70,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xdd151515),
        side: const BorderSide(color: Color(0xff707070)),
        shape: const CircleBorder(),
      ),
    ),
  );
}

class GameCard extends StatefulWidget {
  const GameCard(this.game, this.tap, {this.launch, super.key});
  final GameView game;
  final VoidCallback tap;
  final VoidCallback? launch;

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext c) {
    final game = widget.game;
    final steam = game.game.source.kind == GameSourceKind.steam;
    final canLaunch =
        game.target == TargetState.ready &&
        (game.mod.kind == ModStateKind.applied ||
            game.mod.kind == ModStateKind.outdated);
    return SizedBox(
      width: 265,
      child: Card(
        margin: EdgeInsets.zero,
        color: const Color(0xff272727),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: Stack(
            children: [
              Positioned.fill(
                child: InkWell(
                  onTap: widget.tap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: steam
                            ? Image.network(
                                'https://cdn.akamai.steamstatic.com/steam/apps/${game.game.source.appId}/header.jpg',
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Cover(),
                              )
                            : const Cover(),
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
                                fontWeight: FontWeight.bold,
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
                                  : game.mod.kind == ModStateKind.outdated
                                  ? const Color(0xff5a4915)
                                  : game.mod.kind == ModStateKind.broken
                                  ? const Color(0xff542626)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hovered)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 76,
                  child: ColoredBox(
                    color: const Color(0xbb000000),
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
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: const Text('设置'),
                            ),
                          ),
                          const SizedBox(height: 9),
                          TextButton(
                            onPressed: canLaunch ? widget.launch : null,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: const Color(0xff747474),
                            ),
                            child: const Text(
                              '启动',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
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
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
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

String modLabel(ModStatus x) => x.kind == ModStateKind.applied
    ? '已应用 · ${x.version}'
    : x.kind == ModStateKind.outdated
    ? '需要更新 · ${x.version ?? '上游历史版本'}'
    : x.kind == ModStateKind.broken
    ? '安装异常'
    : '未应用';

class Drivers extends StatelessWidget {
  const Drivers(this.info, this.busy, this.download, {super.key});
  final ManagerInfo? info;
  final bool busy;
  final VoidCallback download;
  @override
  Widget build(BuildContext c) {
    final ready = info?.modAvailable == true;
    return ListView(
      padding: const EdgeInsets.all(30),
      children: [
        Container(
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            color: const Color(0xff1a211b),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DLSSG FOR SM86',
                      style: TextStyle(color: Color(0xff9dcc3a)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ready ? 'Mod 已就绪' : '下载 Mod 后开始配置',
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ready
                          ? '已验证的 Mod 包可用于安装、更新和配置应用。'
                          : '配置定义和游戏设置已锁定；请先下载并校验发布包。',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: busy ? null : download,
                      icon: const Icon(Icons.download),
                      label: Text(
                        busy
                            ? '正在验证…'
                            : ready
                            ? '检查并下载更新'
                            : '下载 Mod',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 175,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: ready
                      ? const Color(0xff294618)
                      : const Color(0xff303335),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Icon(
                      ready ? Icons.verified : Icons.download_for_offline,
                      size: 38,
                      color: ready ? const Color(0xff9dcc3a) : Colors.white54,
                    ),
                    Text(
                      info?.installedVersion ?? '未下载',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ready
                          ? '${info?.knownHashes ?? 0} 个历史 DLL 哈希'
                          : '配置功能已禁用',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '驱动程序状态',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const Divider(height: 30),
                InfoLine('Mod 来源', 'wojiushixiaobai/dlssg_for_sm86_gui'),
                InfoLine('当前缓存', info?.installedVersion ?? '尚未下载'),
                const InfoLine('更新行为', '不会改动任何已安装游戏的 INI'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine(this.a, this.b, {super.key});
  final String a, b;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 105,
          child: Text(a, style: const TextStyle(color: Colors.white60)),
        ),
        Expanded(child: SelectableText(b)),
      ],
    ),
  );
}

class Settings extends StatelessWidget {
  const Settings({
    super.key,
    required this.games,
    required this.profiles,
    required this.selected,
    required this.gameTab,
    required this.hasMod,
    required this.busy,
    required this.onTab,
    required this.onSelect,
    required this.choose,
    required this.manager,
    required this.act,
  });
  final List<GameView> games;
  final List<ConfigProfile> profiles;
  final GameView? selected;
  final bool gameTab, hasMod, busy;
  final ValueChanged<bool> onTab;
  final ValueChanged<String> onSelect;
  final Future<void> Function([GameEntry?]) choose;
  final ModManager manager;
  final Future<void> Function(Future<void> Function(), [String?]) act;
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
                      child: GameList(games, selected?.game.id, onSelect, () {
                        choose();
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GameSettings(
                        selected,
                        profiles,
                        hasMod,
                        busy,
                        choose,
                        manager,
                        act,
                      ),
                    ),
                  ],
                )
              : GlobalSettings(profiles, hasMod, manager, act),
        ),
      ],
    ),
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab(this.label, this.selected, this.tap);
  final String label;
  final bool selected;
  final VoidCallback tap;

  @override
  Widget build(BuildContext c) => SizedBox(
    width: 130,
    height: 60,
    child: Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // The reference tabs use only this underline for selection.  A
            // GestureDetector avoids Material ink/highlight layers entirely.
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xff76b900) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.white60,
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
  const GameList(this.games, this.selected, this.change, this.add, {super.key});
  final List<GameView> games;
  final String? selected;
  final ValueChanged<String> change;
  final VoidCallback add;

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
  Widget build(BuildContext c) => Card(
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
                    fontWeight: FontWeight.w600,
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
                  PopupMenuItem(value: GameSort.newest, child: Text('按最近添加排序')),
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
          child: widget.games.isEmpty
              ? const Empty('使用“添加游戏”将其他游戏加入此列表。')
              : ListView.builder(
                  itemCount: ordered.length,
                  itemBuilder: (_, i) {
                    final x = ordered[i];
                    return ListTile(
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
                            : x.mod.kind == ModStateKind.outdated
                            ? Icons.system_update_alt
                            : Icons.circle_outlined,
                        color: x.mod.kind == ModStateKind.applied
                            ? const Color(0xff9dcc3a)
                            : x.mod.kind == ModStateKind.outdated
                            ? Colors.amberAccent
                            : Colors.white38,
                        size: 18,
                      ),
                      onTap: () => widget.change(x.game.id),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class GameSettings extends StatefulWidget {
  const GameSettings(
    this.view,
    this.profiles,
    this.hasMod,
    this.busy,
    this.choose,
    this.manager,
    this.act, {
    super.key,
  });
  final GameView? view;
  final List<ConfigProfile> profiles;
  final bool hasMod, busy;
  final Future<void> Function([GameEntry?]) choose;
  final ModManager manager;
  final Future<void> Function(Future<void> Function(), [String?]) act;
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
    proxy = widget.view?.game.selectedProxy ?? defaultProxy;
    _loadConfig();
  }

  @override
  void didUpdateWidget(GameSettings old) {
    super.didUpdateWidget(old);
    final gameChanged = old.view?.game.id != widget.view?.game.id;
    if (gameChanged) {
      proxy = widget.view?.game.selectedProxy ?? defaultProxy;
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
    final installed =
        view?.mod.kind == ModStateKind.applied ||
        view?.mod.kind == ModStateKind.outdated;
    if (id == null || !installed) {
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
    final installed =
        v.mod.kind == ModStateKind.applied ||
        v.mod.kind == ModStateKind.outdated;
    final canEdit = installed && !widget.busy;
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _GameControlHeader(
            game: g,
            status: v.mod,
            onChooseExe: () => widget.choose(g),
            proxy: proxy,
            onProxyChanged: installed || widget.busy
                ? null
                : (x) => setState(() => proxy = x!),
            action: installed
                ? TextButton.icon(
                    style: _inlineActionButtonStyle,
                    onPressed: widget.busy
                        ? null
                        : () => widget.act(
                            () => widget.manager.uninstallMod(g.id),
                          ),
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('恢复'),
                  )
                : TextButton.icon(
                    style: _inlineActionButtonStyle,
                    onPressed: canInstall ? () => install(c, v) : null,
                    icon: const Icon(Icons.install_desktop),
                    label: const Text('安装'),
                  ),
          ),
          const SizedBox(height: 26),
          if (!installed)
            const _DriverSettingsDisabled()
          else if (loadingConfig || config == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const _DriverSettingsTitle(),
            const SizedBox(height: 8),
            _DirectDriverSettings(
              config: config!,
              enabled: canEdit,
              onChanged: _saveConfig,
            ),
          ],
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
        final accepted = await dialog(
          c,
          '覆盖未知 DLL？',
          '将保存原始 DLL 的单一最新备份，再安装 Mod。',
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
    required this.onChooseExe,
    required this.proxy,
    required this.onProxyChanged,
    required this.action,
  });
  final GameEntry game;
  final ModStatus status;
  final VoidCallback onChooseExe;
  final String proxy;
  final ValueChanged<String?>? onProxyChanged;
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
                      fontWeight: FontWeight.w600,
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
            TextButton.icon(
              style: _inlineActionButtonStyle,
              onPressed: onChooseExe,
              icon: const Icon(Icons.folder_open),
              label: const Text('指定 EXE'),
            ),
          ],
        ),
        const Divider(height: 27),
        Row(
          children: [
            Icon(
              status.kind == ModStateKind.applied
                  ? Icons.check_circle
                  : status.kind == ModStateKind.outdated
                  ? Icons.system_update_alt
                  : status.kind == ModStateKind.broken
                  ? Icons.error_outline
                  : Icons.info_outline,
              color: status.kind == ModStateKind.applied
                  ? const Color(0xff9dcc3a)
                  : status.kind == ModStateKind.outdated
                  ? Colors.amberAccent
                  : status.kind == ModStateKind.broken
                  ? Colors.orangeAccent
                  : Colors.white54,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.kind == ModStateKind.applied
                    ? '驱动已安装 · ${status.version ?? '已知版本'}'
                    : status.kind == ModStateKind.outdated
                    ? '驱动需要更新 · ${status.detail ?? '检测到上游历史 DLL'}'
                    : status.kind == ModStateKind.broken
                    ? '安装异常 · ${status.detail ?? '请重新安装'}'
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
          DropdownButton<String>(
            value: proxy,
            isExpanded: true,
            items: proxies
                .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                .toList(),
            onChanged: onProxyChanged,
          ),
        ),
      ],
    ),
  );
}

class _DriverSettingsTitle extends StatelessWidget {
  const _DriverSettingsTitle();

  @override
  Widget build(BuildContext c) => const Row(
    children: [
      Expanded(
        child: Text(
          '驱动程序设置',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      ),
      Text('修改后自动保存', style: TextStyle(color: Colors.white54)),
    ],
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
              Text('配置功能已禁用', style: TextStyle(fontWeight: FontWeight.w600)),
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

  ConfigProfile _copy({
    bool? router,
    bool? kernelImage,
    bool? hardwareBilinear,
    int? maxGeneratedFrames,
    int? loggingLevel,
    AdvancedOverrides? advanced,
  }) => ConfigProfile(
    name: config.name,
    router: router ?? config.router,
    kernelImage: kernelImage ?? config.kernelImage,
    hardwareBilinear: hardwareBilinear ?? config.hardwareBilinear,
    maxGeneratedFrames: maxGeneratedFrames ?? config.maxGeneratedFrames,
    loggingLevel: loggingLevel ?? config.loggingLevel,
    advanced: advanced ?? config.advanced,
  );

  @override
  Widget build(BuildContext c) {
    final advanced = config.advanced;
    AdvancedOverrides editAdvanced({bool? extra, bool? debug, bool? enabled}) =>
        AdvancedOverrides(
          loggingExtra: extra == true ? true : null,
          debug: debug == true ? true : null,
          enabled: enabled == true ? true : null,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff1d1d1d),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SetRow(
            'Router',
            DropdownButton<String>(
              value: config.router ? 'SM86' : 'SM75',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'SM86', child: Text('SM86')),
                DropdownMenuItem(value: 'SM75', child: Text('SM75')),
              ],
              onChanged: enabled
                  ? (x) => onChanged(_copy(router: x == 'SM86'))
                  : null,
            ),
          ),
          SetRow(
            'KernelImage',
            DropdownButton<String>(
              value: config.kernelImage ? 'PTX' : 'Auto',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'PTX', child: Text('PTX')),
                DropdownMenuItem(value: 'Auto', child: Text('Auto')),
              ],
              onChanged: enabled
                  ? (x) => onChanged(_copy(kernelImage: x == 'PTX'))
                  : null,
            ),
          ),
          BoolRow(
            'HardwareBilinear',
            config.hardwareBilinear,
            enabled ? (x) => onChanged(_copy(hardwareBilinear: x)) : (_) {},
            '1 · 近似',
            '0 · 精确',
            enabled: enabled,
          ),
          SetRow(
            'MaxGeneratedFrames',
            DropdownButton<int>(
              value: config.maxGeneratedFrames,
              isExpanded: true,
              items: [1, 2, 3]
                  .map((x) => DropdownMenuItem(value: x, child: Text('$x')))
                  .toList(),
              onChanged: enabled
                  ? (x) => onChanged(_copy(maxGeneratedFrames: x))
                  : null,
            ),
          ),
          SetRow(
            'Logging.Level',
            DropdownButton<int>(
              value: config.loggingLevel,
              isExpanded: true,
              items: [0, 1, 2, 3]
                  .map((x) => DropdownMenuItem(value: x, child: Text('$x')))
                  .toList(),
              onChanged: enabled
                  ? (x) => onChanged(_copy(loggingLevel: x))
                  : null,
            ),
          ),
          const Divider(height: 28),
          _DirectCheckbox(
            label: '额外日志',
            value: advanced.loggingExtra == true,
            enabled: enabled,
            changed: (x) => onChanged(
              _copy(
                advanced: editAdvanced(
                  extra: x,
                  debug: advanced.debug,
                  enabled: advanced.enabled,
                ),
              ),
            ),
          ),
          _DirectCheckbox(
            label: '调试标记',
            value: advanced.debug == true,
            enabled: enabled,
            changed: (x) => onChanged(
              _copy(
                advanced: editAdvanced(
                  extra: advanced.loggingExtra,
                  debug: x,
                  enabled: advanced.enabled,
                ),
              ),
            ),
          ),
          _DirectCheckbox(
            label: 'General.Enabled',
            value: advanced.enabled == true,
            enabled: enabled,
            changed: (x) => onChanged(
              _copy(
                advanced: editAdvanced(
                  extra: advanced.loggingExtra,
                  debug: advanced.debug,
                  enabled: x,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectCheckbox extends StatelessWidget {
  const _DirectCheckbox({
    required this.label,
    required this.value,
    required this.enabled,
    required this.changed,
  });
  final String label;
  final bool value, enabled;
  final ValueChanged<bool> changed;

  @override
  Widget build(BuildContext c) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: enabled ? (x) => changed(x ?? false) : null,
    title: Text(label),
  );
}

/// A compact artwork treatment shared by the settings game list and header.
/// Steam's public header artwork is used as an identifiable game icon; other
/// libraries retain a clear local-game fallback.
class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {this.size = 40, super.key});
  final GameEntry game;
  final double size;

  @override
  Widget build(BuildContext c) {
    final appId = game.source.appId;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: SizedBox(
        width: size,
        height: size,
        child: appId == null
            ? const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xff283129)),
                child: Icon(Icons.sports_esports, color: Color(0xff9dcc3a)),
              )
            : Image.network(
                'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xff283129)),
                  child: Icon(Icons.sports_esports, color: Color(0xff9dcc3a)),
                ),
              ),
      ),
    );
  }
}

class Status extends StatelessWidget {
  const Status(this.view, {super.key});
  final GameView view;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xff202628),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          view.mod.kind == ModStateKind.applied
              ? Icons.verified
              : view.mod.kind == ModStateKind.outdated
              ? Icons.system_update_alt
              : Icons.info_outline,
          color: view.mod.kind == ModStateKind.applied
              ? const Color(0xff9dcc3a)
              : view.mod.kind == ModStateKind.outdated
              ? Colors.amberAccent
              : Colors.white54,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modLabel(view.mod)),
              Text(
                view.game.exePath ?? '未选择渲染 EXE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SetRow extends StatelessWidget {
  const SetRow(this.label, this.value, {super.key});
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 115,
          child: Text(label, style: const TextStyle(color: Colors.white60)),
        ),
        Expanded(child: value),
      ],
    ),
  );
}

String configLabel(ConfigStatus x) => switch (x.kind) {
  ConfigStateKind.defaultConfig => '包内默认配置',
  ConfigStateKind.global => '全局配置 · ${x.profile}',
  ConfigStateKind.dedicated => '专属配置 · ${x.profile}',
  ConfigStateKind.externallyModified => '配置已外部修改 · ${x.profile}',
};
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
  const GlobalSettings(
    this.profiles,
    this.hasMod,
    this.manager,
    this.act, {
    super.key,
  });
  final List<ConfigProfile> profiles;
  final bool hasMod;
  final ModManager manager;
  final Future<void> Function(Future<void> Function(), [String?]) act;
  @override
  State<GlobalSettings> createState() => _GlobalSettingsState();
}

class _GlobalSettingsState extends State<GlobalSettings> {
  ConfigProfile? edit;
  @override
  Widget build(BuildContext c) {
    if (edit != null)
      return Editor(
        edit!,
        widget.manager,
        widget.act,
        () => setState(() => edit = null),
      );
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '全局设置',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '默认 INI 只读；下载 Mod 后才能定义自定义配置。',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: widget.hasMod
                    ? () => setState(
                        () => edit = const ConfigProfile(
                          name: '新配置档',
                          router: true,
                          kernelImage: true,
                          hardwareBilinear: false,
                          maxGeneratedFrames: 3,
                          loggingLevel: 1,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新建配置'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ProfileTile(
            '包内默认 INI',
            '未选择自定义全局配置时使用',
            widget.manager.db.globalProfile == null,
            widget.hasMod
                ? () => widget.act(() => widget.manager.setGlobalProfile(null))
                : null,
          ),
          ...widget.profiles.map(
            (x) => ProfileTile(
              x.name,
              widget.manager.db.globalProfile == x.name ? '当前全局配置' : '自定义配置',
              widget.manager.db.globalProfile == x.name,
              widget.hasMod ? () => setState(() => edit = x) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileTile extends StatelessWidget {
  const ProfileTile(this.name, this.note, this.active, this.tap, {super.key});
  final String name, note;
  final bool active;
  final VoidCallback? tap;
  @override
  Widget build(BuildContext c) => Card(
    color: active ? const Color(0xff293c1b) : null,
    child: ListTile(
      onTap: tap,
      title: Text(name),
      subtitle: Text(note),
      trailing: active
          ? const Icon(Icons.check_circle, color: Color(0xff9dcc3a))
          : const Icon(Icons.chevron_right),
    ),
  );
}

class Editor extends StatefulWidget {
  const Editor(this.initial, this.manager, this.act, this.done, {super.key});
  final ConfigProfile initial;
  final ModManager manager;
  final Future<void> Function(Future<void> Function(), [String?]) act;
  final VoidCallback done;
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  late TextEditingController name;
  late bool router, kernel, bilinear, extra, debug, enabled;
  late int frames, level;
  @override
  void initState() {
    super.initState();
    final x = widget.initial;
    name = TextEditingController(text: x.name);
    router = x.router;
    kernel = x.kernelImage;
    bilinear = x.hardwareBilinear;
    frames = x.maxGeneratedFrames;
    level = x.loggingLevel;
    extra = x.advanced.loggingExtra ?? false;
    debug = x.advanced.debug ?? false;
    enabled = x.advanced.enabled ?? false;
  }

  ConfigProfile get value => ConfigProfile(
    name: name.text,
    router: router,
    kernelImage: kernel,
    hardwareBilinear: bilinear,
    maxGeneratedFrames: frames,
    loggingLevel: level,
    advanced: AdvancedOverrides(
      loggingExtra: extra ? true : null,
      debug: debug ? true : null,
      enabled: enabled ? true : null,
    ),
  );
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Card(
    child: ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '编辑配置档',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton(onPressed: widget.done, child: const Text('返回')),
          ],
        ),
        const SizedBox(height: 15),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: '配置名称'),
        ),
        BoolRow(
          'Router',
          router,
          (x) => setState(() => router = x),
          'SM86',
          'SM75',
        ),
        BoolRow(
          'KernelImage',
          kernel,
          (x) => setState(() => kernel = x),
          'PTX',
          'Auto',
        ),
        BoolRow(
          'HardwareBilinear',
          bilinear,
          (x) => setState(() => bilinear = x),
          '1 · 近似',
          '0 · 精确',
        ),
        SetRow(
          'MaxGeneratedFrames',
          DropdownButton<int>(
            value: frames,
            isExpanded: true,
            items: [1, 2, 3]
                .map((x) => DropdownMenuItem(value: x, child: Text('$x')))
                .toList(),
            onChanged: (x) => setState(() => frames = x!),
          ),
        ),
        SetRow(
          'Logging.Level',
          DropdownButton<int>(
            value: level,
            isExpanded: true,
            items: [0, 1, 2, 3]
                .map((x) => DropdownMenuItem(value: x, child: Text('$x')))
                .toList(),
            onChanged: (x) => setState(() => level = x!),
          ),
        ),
        const Divider(height: 35),
        const Text(
          '高级选项',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const Text('未选择的高级项不会写入 INI。', style: TextStyle(color: Colors.white54)),
        CheckboxListTile(
          value: extra,
          onChanged: (x) => setState(() => extra = x!),
          title: const Text('额外日志'),
        ),
        CheckboxListTile(
          value: debug,
          onChanged: (x) => setState(() => debug = x!),
          title: const Text('调试标记'),
        ),
        CheckboxListTile(
          value: enabled,
          onChanged: (x) => setState(() => enabled = x!),
          title: const Text('General.Enabled'),
        ),
        Wrap(
          spacing: 10,
          children: [
            FilledButton(
              onPressed: () => widget.act(() async {
                await widget.manager.saveProfile(value);
                await widget.manager.setGlobalProfile(value.name);
                widget.done();
              }),
              child: const Text('保存并设为全局'),
            ),
            OutlinedButton(
              onPressed: () => widget.act(() async {
                await widget.manager.saveProfile(value);
                widget.done();
              }),
              child: const Text('仅保存'),
            ),
            if (widget.initial.name != '新配置档')
              OutlinedButton(
                onPressed: () => widget.act(() async {
                  await widget.manager.deleteProfile(widget.initial.name);
                  widget.done();
                }),
                child: const Text('删除'),
              ),
          ],
        ),
      ],
    ),
  );
}

class BoolRow extends StatelessWidget {
  const BoolRow(
    this.label,
    this.value,
    this.changed,
    this.yes,
    this.no, {
    this.enabled = true,
    super.key,
  });
  final String label, yes, no;
  final bool value, enabled;
  final ValueChanged<bool> changed;
  @override
  Widget build(BuildContext c) => SetRow(
    label,
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: enabled ? changed : null,
      title: Text(value ? yes : no),
    ),
  );
}
