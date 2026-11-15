import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// One set of colours for the whole app: surfaces, lines, three text tones
/// and the status colours.
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.success,
    required this.warning,
    required this.danger,
  });
  final Brightness brightness;
  final Color bg, surface, surface2, surface3, line, text, text2, text3, success, warning, danger;

  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0D),
    surface: Color(0xFF131316),
    surface2: Color(0xFF1A1A1E),
    surface3: Color(0xFF222227),
    line: Color(0xFF26262C),
    text: Color(0xFFEDEDF0),
    text2: Color(0xFFA3A3AD),
    text3: Color(0xFF6C6C76),
    success: Color(0xFF6FCF97),
    warning: Color(0xFFF2C46D),
    danger: Color(0xFFFF7A7A),
  );

  /// Paper-white surfaces with the same calm, low-contrast layering.
  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F0F2),
    surface3: Color(0xFFE6E6EA),
    line: Color(0xFFE2E2E7),
    text: Color(0xFF16161A),
    text2: Color(0xFF55555F),
    text3: Color(0xFF8C8C96),
    success: Color(0xFF1F9D5B),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFD64545),
  );
}

/// The palette in use: near-black (or paper-white) surfaces, one accent,
/// three text tones. Read at build time, so a change of theme takes effect
/// when the app rebuilds.
abstract final class AppColors {
  static Palette palette = Palette.dark;
  static bool get isLight => palette.brightness == Brightness.light;

  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get surface2 => palette.surface2;
  static Color get surface3 => palette.surface3;
  static Color get line => palette.line;
  static Color get text => palette.text;
  static Color get text2 => palette.text2;
  static Color get text3 => palette.text3;
  static Color get success => palette.success;
  static Color get warning => palette.warning;
  static Color get danger => palette.danger;

  /// The accent chosen in Settings (monochrome by default).
  static Color activeAccent = const Color(0xFFF4F4F5);
  static Color activeAccentDim = const Color(0xFFF4F4F5).withValues(alpha: 0.16);
  static Color get accent => activeAccent;
  static Color get accentDim => activeAccentDim;

  /// For decoration (tinted backgrounds, gradients, badges, chart colours):
  /// the accent, except the monochrome accent on a light page, which turns
  /// near-black and would read as a dark smudge; there a soft slate is used.
  /// Buttons and links keep [accent].
  static Color get tint => isLight && activeAccent.computeLuminance() < 0.05 ? const Color(0xFF5B6B8C) : activeAccent;

  /// [color] as the accent. On a light page the monochrome (white) accent
  /// turns near-black so it stays visible.
  static void applyAccent(Color color) {
    if (isLight && color.computeLuminance() > 0.8) color = const Color(0xFF18181B);
    activeAccent = color;
    activeAccentDim = color.withValues(alpha: color.computeLuminance() > 0.6 ? 0.16 : 0.18);
  }
}

abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x4 = 32;
}

abstract final class Radii {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 22;
}

const tabularFigures = [FontFeature.tabularFigures()];

/// Appearance choices read while building, like [AppColors.palette]: the
/// app sets them and rebuilds every screen when they change.
abstract final class AppLook {
  /// Icons at the start of list rows.
  static bool leadingIcons = true;
}

/// A list row's leading icon, or none when Appearance turns them off (the
/// row then starts with its text, with no gap).
Widget? lead(Widget icon) => AppLook.leadingIcons ? icon : null;

/// A hand-built row's leading icon and the gap after it, or nothing.
List<Widget> leadRow(Widget icon, double gap) => AppLook.leadingIcons ? [icon, SizedBox(width: gap)] : const [];

ThemeData buildTheme({
  Color? accent,
  double chatFontSize = 15.5,
  String? chatFontFamily,
}) {
  accent ??= AppColors.accent;
  final light = AppColors.isLight;
  final scheme = (light ? ColorScheme.light : ColorScheme.dark)(
    surface: AppColors.bg,
    primary: accent,
    onPrimary: accent.computeLuminance() > 0.5 ? const Color(0xFF0B1220) : Colors.white,
    secondary: accent,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.text2,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
    error: AppColors.danger,
    surfaceContainerLowest: AppColors.bg,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surface2,
    surfaceContainerHighest: AppColors.surface3,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: AppColors.palette.brightness,
  );
  final text = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.5, fontSize: chatFontSize, fontFamily: chatFontFamily),
      bodyMedium: text.bodyMedium?.copyWith(
        height: 1.45,
        fontFamily: chatFontFamily,
        color: AppColors.text,
        fontSize: chatFontSize - 1,
      ),
      bodySmall: text.bodySmall?.copyWith(color: AppColors.text2),
      labelSmall: text.labelSmall?.copyWith(
        color: AppColors.text3,
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(statusBarColor: Colors.transparent),
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.text3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      hintStyle: TextStyle(color: AppColors.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        borderSide: BorderSide(color: AppColors.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      // A sensible height for buttons in rows and sheets; full-width calls to
      // action set their own (48+) where they want more.
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.bg,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.l),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface2,
      selectedColor: AppColors.accentDim,
      side: BorderSide(color: AppColors.line),
      labelStyle: TextStyle(fontSize: 13, color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.text
              : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? AppColors.bg : AppColors.text2,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surface3,
      thumbColor: AppColors.text,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? AppColors.bg : AppColors.text3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.surface3,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface3,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}

extension ThemeX on BuildContext {
  TextTheme get text => Theme.of(this).textTheme;
}

OverlayEntry? _toast;

/// A short message that slides in at the top of the screen and leaves on
/// its own, rather than a snackbar over the input box.
void showSnack(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_outline_rounded,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      icon: icon,
      onDone: () {
        if (_toast == entry) _toast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _toast = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.icon,
    required this.onDone,
  });
  final String message;
  final IconData icon;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + Space.s;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: top,
      left: Space.l,
      right: Space.l,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -0.6),
              end: Offset.zero,
            ).animate(curve),
            child: Center(
              child: Material(
                color: AppColors.surface3,
                elevation: 8,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: AppColors.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.l,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 16, color: AppColors.text2),
                      const SizedBox(width: Space.s),
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
