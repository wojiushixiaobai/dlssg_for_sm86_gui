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
            margin: const EdgeInsets.symmetric(horizontal: 6),
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
    this.icon,
    this.iconWidget,
    required this.selected,
    required this.onTap,
  }) : assert(icon != null || iconWidget != null);
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
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
                child:
                    widget.iconWidget ??
                    Icon(
                      widget.icon,
                      size: 18,
                      color: widget.selected ? _primaryText : _secondaryText,
                    ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      return Semantics(
        button: true,
        label: '$label，打开 GitHub 仓库',
        child: _DesktopNavigationItem(
          label: snapshot.connectionState == ConnectionState.done ? label : '',
          selected: false,
          iconWidget: const CustomPaint(painter: _GitHubIconPainter()),
          onTap: () {
            try {
              _openRepository();
            } catch (error) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$error')));
            }
          },
        ),
      );
    },
  );
}

class _GitHubIconPainter extends CustomPainter {
  const _GitHubIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(12, 0)
      ..cubicTo(5.37, 0, 0, 5.37, 0, 12)
      ..cubicTo(0, 17.3, 3.44, 21.8, 8.21, 23.39)
      ..cubicTo(8.81, 23.5, 9.03, 23.13, 9.03, 22.81)
      ..lineTo(9.03, 20.58)
      ..cubicTo(5.69, 21.31, 4.99, 19.16, 4.99, 19.16)
      ..cubicTo(4.44, 17.77, 3.66, 17.4, 3.66, 17.4)
      ..cubicTo(2.57, 16.65, 3.74, 16.67, 3.74, 16.67)
      ..cubicTo(4.94, 16.75, 5.57, 17.9, 5.57, 17.9)
      ..cubicTo(6.64, 19.73, 8.38, 19.2, 9.07, 18.89)
      ..cubicTo(9.18, 18.11, 9.49, 17.58, 9.83, 17.28)
      ..cubicTo(7.16, 16.98, 4.36, 15.94, 4.36, 11.34)
      ..cubicTo(4.36, 10.03, 4.83, 8.96, 5.6, 8.12)
      ..cubicTo(5.48, 7.82, 5.06, 6.6, 5.72, 4.95)
      ..cubicTo(5.72, 4.95, 6.73, 4.63, 9.02, 6.18)
      ..cubicTo(10.93, 5.65, 13.07, 5.65, 14.98, 6.18)
      ..cubicTo(17.27, 4.63, 18.28, 4.95, 18.28, 4.95)
      ..cubicTo(18.94, 6.6, 18.52, 7.82, 18.4, 8.12)
      ..cubicTo(19.17, 8.96, 19.64, 10.03, 19.64, 11.34)
      ..cubicTo(19.64, 15.95, 16.83, 16.98, 14.16, 17.28)
      ..cubicTo(14.59, 17.65, 14.97, 18.38, 14.97, 19.5)
      ..lineTo(14.97, 22.81)
      ..cubicTo(14.97, 23.13, 15.19, 23.5, 15.8, 23.39)
      ..cubicTo(20.56, 21.8, 24, 17.3, 24, 12)
      ..cubicTo(24, 5.37, 18.63, 0, 12, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = _secondaryText);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GitHubIconPainter oldDelegate) => false;
}
