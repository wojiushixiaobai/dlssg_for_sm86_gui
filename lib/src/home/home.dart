part of '../../app.dart';

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
      key: const PageStorageKey('home-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
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
        style: const TextStyle(fontSize: 16, fontWeight: _uiEmphasisWeight),
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
  bool focused = false;

  bool get hovered => (widget.selected ?? localHovered) || focused;

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
        duration: _motion(c),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        scale: hovered && !MediaQuery.disableAnimationsOf(c) ? 1.025 : 1,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => changeHover(true),
          onExit: (_) => changeHover(false),
          child: AnimatedContainer(
            duration: _motion(c),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: hovered
                  ? const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Card(
              margin: EdgeInsets.zero,
              color: _surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: focused ? _accent : _surfaceBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.tap,
                onFocusChange: (value) => setState(() => focused = value),
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
                          IgnorePointer(
                            ignoring: !hovered,
                            child: AnimatedSwitcher(
                              duration: _motion(c),
                              child: !hovered
                                  ? const SizedBox.expand()
                                  : ColoredBox(
                                      color: const Color(0xa61b1b1b),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 106,
                                              child: DesktopButton(
                                                onPressed: widget.tap,
                                                label: '设置',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              width: 106,
                                              child: DesktopButton(
                                                onPressed: widget.launch,
                                                label: '启动',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                            backgroundColor: _raisedSurface,
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
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff353535), Color(0xff292929)],
      ),
    ),
    child: Center(
      child: Text(
        'DLSSG',
        style: TextStyle(
          fontSize: 25,
          letterSpacing: 4,
          color: _secondaryText,
          fontWeight: _uiEmphasisWeight,
        ),
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
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _surfaceBorder),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.sports_esports_outlined,
          size: 30,
          color: _secondaryText,
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _secondaryText, height: 1.7),
        ),
      ],
    ),
  );
}
