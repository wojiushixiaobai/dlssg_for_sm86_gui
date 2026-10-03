part of '../../app.dart';

class DesktopNavigation extends StatelessWidget {
  const DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const _items = [
    (label: '主页', icon: Icons.grid_view_rounded),
    (label: '驱动', icon: Icons.downloading_rounded),
    (label: '游戏', icon: Icons.tune_rounded),
  ];
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: _chromeSurface,
        border: Border(right: BorderSide(color: _surfaceBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (var index = 0; index < _items.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: _DesktopNavigationItem(
                label: _items[index].label,
                icon: _items[index].icon,
                selected: selectedIndex == index,
                onTap: () => onSelected(index),
              ),
            ),
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _surfaceBorder)),
            ),
            child: const Center(child: _AppVersion()),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavigationItem extends StatefulWidget {
  const _DesktopNavigationItem({
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
  State<_DesktopNavigationItem> createState() => _DesktopNavigationItemState();
}

class _DesktopNavigationItemState extends State<_DesktopNavigationItem> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: widget.selected,
    child: AnimatedContainer(
      duration: _motion(context),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: widget.selected
            ? _selectionBackground
            : hovered
            ? Colors.white.withValues(alpha: .05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: focused ? _accent : Colors.transparent),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => hovered = value),
        onFocusChange: (value) => setState(() => focused = value),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected ? _primaryText : _secondaryText,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: widget.selected
                      ? _uiEmphasisWeight
                      : FontWeight.w400,
                  color: widget.selected ? _primaryText : _secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AppVersion extends StatefulWidget {
  const _AppVersion();

  @override
  State<_AppVersion> createState() => _AppVersionState();
}

class _AppVersionState extends State<_AppVersion> {
  // The runner exposes Flutter's build version from pubspec.yaml / --build-name.
  late final Future<String?> _version = _readVersion();

  Future<String?> _readVersion() async {
    try {
      return await const MethodChannel('dlssg/app-info')
          .invokeMethod<String>('version');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _version,
    builder: (context, snapshot) {
      final version = snapshot.data;
      final label = version == null ? '版本未知' : 'v$version';
      return Tooltip(
        message: version == null ? '无法读取应用版本' : '应用版本 $version',
        child: Text(
          snapshot.connectionState == ConnectionState.done ? label : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.2,
            letterSpacing: .2,
            color: _secondaryText,
          ),
        ),
      );
    },
  );
}
