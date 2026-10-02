part of '../../app.dart';

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
    height: _navigationItemHeight,
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
              height: _navigationHighlightHeight,
              decoration: BoxDecoration(
                color: widget.selected ? _nvidiaGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: _navigationHighlightHeight,
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
