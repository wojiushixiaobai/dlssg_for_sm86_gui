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
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _appBackground,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _surfaceBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SettingsTab('程序设置', gameTab, () => onTab(true)),
                _SettingsTab('全局设置', !gameTab, () => onTab(false)),
              ],
            ),
          ),
        ),
        if (!hasMod)
          const Padding(padding: EdgeInsets.only(top: 14), child: Lock()),
        const SizedBox(height: 16),
        Expanded(
          child: _PageEntrance(
            key: ValueKey(gameTab),
            child: gameTab
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final list = GameList(
                        games,
                        selected?.game.id,
                        onSelect,
                        () => choose(),
                        remove,
                      );
                      final detail = GameSettings(
                        selected,
                        hasMod,
                        busy,
                        choose,
                        manager,
                        act,
                        launch: launch,
                        hagsStatus: hagsStatus,
                      );
                      if (constraints.maxWidth < 760) {
                        return Column(
                          children: [
                            SizedBox(
                              height: constraints.maxHeight < 420 ? 150 : 200,
                              child: list,
                            ),
                            const SizedBox(height: 12),
                            Expanded(child: detail),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(width: 280, child: list),
                          const SizedBox(width: 16),
                          Expanded(child: detail),
                        ],
                      );
                    },
                  )
                : GlobalSettings(hasMod, manager, act, busy: busy),
          ),
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
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: AnimatedContainer(
      duration: _motion(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? _selectionBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: TextButton(
        onPressed: tap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          foregroundColor: selected ? _primaryText : _secondaryText,
          minimumSize: const Size(112, 34),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(label),
      ),
    ),
  );
}

class Lock extends StatelessWidget {
  const Lock({super.key});
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xff363127),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff514637)),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 17, color: Color(0xffe5c590)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '配置功能已锁定：请先在“驱动程序”页面下载并验证 dlssg_for_sm86。',
            style: TextStyle(fontSize: 12, color: Color(0xffe5d1b0)),
          ),
        ),
      ],
    ),
  );
}
