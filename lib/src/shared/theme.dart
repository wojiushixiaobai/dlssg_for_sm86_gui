part of '../../app.dart';

const _nvidiaAppBackground = Color(0xff1b1b1b);
const _nvidiaSidebar = Color(0xff1c1c1c);
const _nvidiaHeader = Color(0xff292929);
const _nvidiaMenuActive = Color(0xff444444);
const _nvidiaGreen = Color(0xff76b900);
const _nvidiaText = Color(0xfff2f2f2);
const _nvidiaMutedText = Color(0xffc8c8c8);
const _navigationItemHeight = 85.0;
const _navigationHighlightHeight = 70.0;
const _uiFontFamily = 'Microsoft YaHei UI';
const _uiFontFallback = <String>['Microsoft YaHei', 'Segoe UI', 'Arial'];
const _uiEmphasisWeight = FontWeight.w500;
const _controlButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
);
final _buttonMouseCursor = WidgetStateProperty.resolveWith<MouseCursor?>(
  (states) => states.contains(WidgetState.disabled)
      ? SystemMouseCursors.basic
      : SystemMouseCursors.click,
);

final _inlineActionButtonStyle = ButtonStyle(
  mouseCursor: _buttonMouseCursor,
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

final _inlineIconActionButtonStyle = _inlineActionButtonStyle.copyWith(
  fixedSize: const WidgetStatePropertyAll(Size(42, 42)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
);

bool _isActionHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.focused) ||
    states.contains(WidgetState.pressed);
