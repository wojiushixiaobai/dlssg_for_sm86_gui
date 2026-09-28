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
                                          style: TextStyle(
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
