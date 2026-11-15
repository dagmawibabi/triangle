import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../data/settings.dart';

/// Switches between light and dark: a tap flips from whatever shows now
/// (following the system included); a long press goes back to following
/// the system. The icon is the theme a tap switches to.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key, this.size, this.color});
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final dark = switch (mode) {
      AppThemeMode.dark => true,
      AppThemeMode.light => false,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final controller = ref.read(settingsProvider.notifier);
    return GestureDetector(
      onLongPress: mode == AppThemeMode.system
          ? null
          : () {
              controller.setThemeMode(AppThemeMode.system);
              showSnack(context, 'Following the system theme', icon: Icons.brightness_auto_outlined);
            },
      child: IconButton(
        tooltip: dark ? 'Light theme (hold: follow system)' : 'Dark theme (hold: follow system)',
        onPressed: () => controller.setThemeMode(dark ? AppThemeMode.light : AppThemeMode.dark),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) => RotationTransition(turns: Tween(begin: 0.75, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
          child: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            key: ValueKey(dark),
            size: size,
            color: color,
          ),
        ),
      ),
    );
  }
}
