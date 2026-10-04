part of '../../app.dart';

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
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<GameView> get ordered {
    final query = search.text.trim().toLowerCase();
    final entries = widget.games
        .where(
          (game) =>
              game.game.name.toLowerCase().contains(query) ||
              (game.game.source.appId?.toString().contains(query) ?? false),
        )
        .toList();
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
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '程序  ${widget.games.length}',
                    style: const TextStyle(
                      fontSize: 13,
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
                IconButton(
                  onPressed: widget.add,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  tooltip: '添加游戏',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索游戏',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(search.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? SingleChildScrollView(
                    child: Empty(
                      search.text.isEmpty
                          ? '使用“添加游戏”将其他游戏加入此列表。'
                          : '没有找到匹配的游戏。',
                    ),
                  )
                : ListView.builder(
                    // A scrollbar jump must not lay out every preceding game
                    // (and start loading each one's executable icon).
                    itemExtent: 76 * MediaQuery.textScalerOf(c).scale(13) / 13,
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final x = entries[i];
                      return Padding(
                        key: ValueKey(x.game.id),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          titleTextStyle: const TextStyle(
                            fontFamily: _uiFontFamily,
                            fontFamilyFallback: _uiFontFallback,
                            fontSize: 13,
                            color: _primaryText,
                          ),
                          subtitleTextStyle: const TextStyle(
                            fontFamily: _uiFontFamily,
                            fontFamilyFallback: _uiFontFallback,
                            fontSize: 11,
                            color: _secondaryText,
                          ),
                          mouseCursor: SystemMouseCursors.click,
                          selected: x.game.id == widget.selected,
                          selectedTileColor: _selectionBackground,
                          selectedColor: _primaryText,
                          horizontalTitleGap: 12,
                          leading: _GameListIcon(x),
                          title: Text(
                            x.game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            x.game.source.kind == GameSourceKind.steam
                                ? 'Steam · ${x.game.source.appId}'
                                : '手动添加',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => widget.change(x.game.id),
                          onLongPress: () => widget.remove(x),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GameListIcon extends StatelessWidget {
  const _GameListIcon(this.game);
  final GameView game;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: modLabel(game.mod),
    child: Semantics(
      label: modLabel(game.mod),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GameIcon(game.game),
          if (game.mod.kind == ModStateKind.applied)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: _surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: _success,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
