import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Liquid glass: whatever scrolls underneath shows through, blurred and a
/// little more vivid, under a faint sheen with a lit rim along the top edge.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.blur = 22,
    this.opacity = 0.62,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;

  /// Washes the glass in a colour (a selected pill, say) instead of the
  /// surface tone.
  final Color? tint;

  /// Blur plus a saturation lift, which is what makes glass read as glass
  /// rather than frosted plastic.
  static ImageFilter filter(double blur) => ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror),
    inner: const ColorFilter.matrix(_saturate),
  );

  static const _s = 1.35;
  static const _saturate = <double>[
    0.2126 + 0.7874 * _s, 0.7152 - 0.7152 * _s, 0.0722 - 0.0722 * _s, 0, 0, //
    0.2126 - 0.2126 * _s, 0.7152 + 0.2848 * _s, 0.0722 - 0.0722 * _s, 0, 0,
    0.2126 - 0.2126 * _s, 0.7152 - 0.7152 * _s, 0.0722 + 0.9278 * _s, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final base = tint ?? AppColors.surface2;
    final light = AppColors.isLight;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: filter(blur),
        child: CustomPaint(
          foregroundPainter: GlassRim(radius: radius),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base.withValues(alpha: (opacity + (light ? 0.14 : 0.06)).clamp(0, 1)),
                  base.withValues(alpha: (opacity - 0.08).clamp(0, 1)),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The lit edge of a glass shape: bright where light would catch the top
/// left, fading round the sides, a faint glint again at the bottom right.
class GlassRim extends CustomPainter {
  const GlassRim({required this.radius, this.strength = 1});
  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = radius.clamp(0, size.shortestSide / 2).toDouble();
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(r));
    final light = AppColors.isLight;
    final hi = (light ? Colors.white : Colors.white).withValues(alpha: (light ? 0.85 : 0.22) * strength);
    final lo = (light ? Colors.black : Colors.white).withValues(alpha: (light ? 0.05 : 0.04) * strength);
    final glint = Colors.white.withValues(alpha: (light ? 0.5 : 0.10) * strength);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hi, lo, lo, glint],
          stops: const [0, 0.38, 0.7, 1],
        ).createShader(rect),
    );
    // A soft sheen across the upper half, like light lying on a lens.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: (light ? 0.18 : 0.045) * strength), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.55)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassRim old) => old.radius != radius || old.strength != strength;
}

/// A round glass button for floating headers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 44});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Glass(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: size, child: Icon(icon, size: 22, color: AppColors.text)),
          ),
        ),
      ),
    );
  }
}

/// A fade from the page colour to nothing behind a floating header, so
/// whatever scrolls under the glass softens instead of clashing with it.
class HeaderScrim extends StatelessWidget {
  const HeaderScrim({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bg.withValues(alpha: 0.92), AppColors.bg.withValues(alpha: 0.6), AppColors.bg.withValues(alpha: 0)],
          stops: const [0, 0.55, 1],
        ),
      ),
    ),
  );
}
