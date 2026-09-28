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
