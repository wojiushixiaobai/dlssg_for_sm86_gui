part of '../../app.dart';

// Windows approximation of macOS dark semantic colors, not fixed AppKit values.
// Keep content, controls, selection, focus and status independent.
// https://developer.apple.com/design/human-interface-guidelines/color
const _appBackground = Color(0xff1e1e1e);
// Also used by the native Windows caption (win32_window.cpp).
const _chromeSurface = Color(0xff282828);
const _raisedSurface = Color(0xff333333);
const _hoverSurface = Color(0xff414141);
const _selectionBackground = Color(0xff454545);
const _accent = Color(0xff409cff);
const _primaryText = Color(0xffeeeeee);
const _secondaryText = Color(0xffb8b8b8);
const _surface = Color(0xff2b2b2b);
const _surfaceBorder = Color(0xff3d3d3d);
const _success = Color(0xff32d74b);
const _uiFontFamily = 'Segoe UI';
const _uiFontFallback = <String>['Microsoft YaHei UI', 'Microsoft YaHei'];
const _uiEmphasisWeight = FontWeight.w500;
const _motionDuration = Duration(milliseconds: 200);
Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : _motionDuration;
const _controlButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
);
final _buttonMouseCursor = WidgetStateProperty.resolveWith<MouseCursor?>(
  (states) => states.contains(WidgetState.disabled)
      ? SystemMouseCursors.basic
      : SystemMouseCursors.click,
);
final _desktopButtonStyle = ButtonStyle(
  mouseCursor: _buttonMouseCursor,
  animationDuration: _motionDuration,
  visualDensity: VisualDensity.standard,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  minimumSize: const WidgetStatePropertyAll(Size(72, 32)),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  ),
  shape: const WidgetStatePropertyAll(_controlButtonShape),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(
      fontFamily: _uiFontFamily,
      fontFamilyFallback: _uiFontFallback,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.2,
    ),
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? const Color(0xff777777)
        : _primaryText,
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? const Color(0xff2d2d2d)
        : states.contains(WidgetState.pressed)
        ? const Color(0xff505050)
        : states.contains(WidgetState.hovered)
        ? const Color(0xff484848)
        : const Color(0xff3c3c3c),
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => BorderSide(
      color: states.contains(WidgetState.focused)
          ? _accent
          : states.contains(WidgetState.disabled)
          ? const Color(0xff363636)
          : const Color(0xff555555),
    ),
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
);
final _inlineActionButtonStyle = _desktopButtonStyle;
final _inlineIconActionButtonStyle = _desktopButtonStyle.copyWith(
  minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
  fixedSize: const WidgetStatePropertyAll(Size(32, 32)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) =>
        _isActionHighlighted(states) ? _hoverSurface : Colors.transparent,
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => BorderSide(
      color: states.contains(WidgetState.focused)
          ? _accent
          : Colors.transparent,
    ),
  ),
);

/// All ordinary actions share the same control, including disabled and focus states.
class DesktopButton extends StatelessWidget {
  const DesktopButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    style: _desktopButtonStyle,
    onPressed: onPressed,
    child: Text(label),
  );
}

bool _isActionHighlighted(Set<WidgetState> states) =>
    states.contains(WidgetState.hovered) ||
    states.contains(WidgetState.focused) ||
    states.contains(WidgetState.pressed);

ThemeData _desktopTheme() {
  // Explicit neutral containers avoid Material's generated accent-tinted fills.
  final scheme = const ColorScheme.dark().copyWith(
    primary: _accent,
    onPrimary: const Color(0xff001c38),
    primaryContainer: _selectionBackground,
    onPrimaryContainer: _primaryText,
    secondary: _accent,
    onSecondary: const Color(0xff001c38),
    secondaryContainer: _selectionBackground,
    onSecondaryContainer: _primaryText,
    tertiary: _secondaryText,
    onTertiary: _appBackground,
    tertiaryContainer: _raisedSurface,
    onTertiaryContainer: _primaryText,
    surface: _surface,
    onSurface: _primaryText,
    onSurfaceVariant: _secondaryText,
    outline: _surfaceBorder,
    outlineVariant: _surfaceBorder,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: _appBackground,
    surfaceContainerLow: _surface,
    surfaceContainer: _surface,
    surfaceContainerHigh: _raisedSurface,
    surfaceContainerHighest: _hoverSurface,
  );
  final button = _desktopButtonStyle;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _uiFontFamily,
    fontFamilyFallback: _uiFontFallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: _appBackground,
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.white.withValues(alpha: .05),
    focusColor: _accent.withValues(alpha: .16),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: _accent,
      selectionColor: _accent.withValues(alpha: .30),
      selectionHandleColor: _accent,
    ),
    dividerColor: _surfaceBorder,
    dividerTheme: const DividerThemeData(color: _surfaceBorder, thickness: 1),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: _primaryText),
      bodyLarge: TextStyle(fontSize: 14, height: 1.5, color: _primaryText),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: _secondaryText),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: _uiEmphasisWeight,
        color: _primaryText,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: _uiEmphasisWeight,
        color: _primaryText,
      ),
      labelLarge: TextStyle(fontSize: 13, fontWeight: _uiEmphasisWeight),
    ),
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _surfaceBorder),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    filledButtonTheme: FilledButtonThemeData(style: button),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button.copyWith(elevation: const WidgetStatePropertyAll(0)),
    ),
    iconButtonTheme: IconButtonThemeData(style: _inlineIconActionButtonStyle),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _appBackground,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _raisedSurface,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      labelStyle: const TextStyle(
        fontFamily: _uiFontFamily,
        fontFamilyFallback: _uiFontFallback,
        fontSize: 11,
        color: _secondaryText,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _surfaceBorder),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _surfaceBorder),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: _hoverSurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _surfaceBorder),
      ),
      textStyle: const TextStyle(
        fontFamily: _uiFontFamily,
        fontFamilyFallback: _uiFontFallback,
        fontSize: 12,
        color: _primaryText,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(5),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => Colors.white.withValues(
          alpha: states.contains(WidgetState.hovered) ? .35 : .18,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _accent,
      linearTrackColor: _raisedSurface,
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
  );
}

/// Incoming-only transition keeps outgoing controls out of the focus tree.
class _PageEntrance extends StatelessWidget {
  const _PageEntrance({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: _motion(context),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}
