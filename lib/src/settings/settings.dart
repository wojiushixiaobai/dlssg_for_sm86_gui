part of '../../app.dart';

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
              : GlobalSettings(hasMod, manager, act, busy: busy),
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
