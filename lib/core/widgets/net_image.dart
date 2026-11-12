import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A shimmering placeholder block, for content that's on its way.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = 0, this.shape = BoxShape.rectangle});
  final double? width;
  final double? height;
  final double radius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surface3;
    final glow = Color.lerp(base, AppColors.isLight ? Colors.white : AppColors.text, AppColors.isLight ? 0.6 : 0.08)!;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // A soft band sweeping left to right.
        final t = _c.value * 3 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle ? null : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.3),
              end: Alignment(t + 1, 0.3),
              colors: [base, glow, base],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

/// A network image for cards: a skeleton of its size while it loads, a
/// short fade in when it arrives, and a quiet placeholder if it can't load.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.circle = false,
    this.placeholder = Icons.image_outlined,
    this.errorWidget,
    this.alignment = Alignment.center,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final bool circle;
  final IconData? placeholder;

  /// Shown instead of the placeholder box when the image fails.
  final Widget? errorWidget;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
    Widget fallback() =>
        errorWidget ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surface3, shape: circle ? BoxShape.circle : BoxShape.rectangle),
          child: placeholder == null ? null : Icon(placeholder, color: AppColors.text3, size: _iconSize),
        );
    final Widget image = u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))
        ? fallback()
        : Image.network(
            u,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            // Decode at the size shown, not the source size.
            cacheWidth: width != null && width!.isFinite ? (width! * MediaQuery.devicePixelRatioOf(context)).round() : null,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: child),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Skeleton(width: width, height: height, shape: circle ? BoxShape.circle : BoxShape.rectangle),
                      Opacity(opacity: 0, child: child),
                    ],
                  ),
            errorBuilder: (_, _, _) => fallback(),
          );
    if (circle) return ClipOval(child: image);
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: image) : image;
  }

  double get _iconSize {
    final s = [width, height].whereType<double>().where((x) => x.isFinite).fold<double?>(null, (a, b) => a == null || b < a ? b : a);
    return s == null ? 22 : (s * 0.4).clamp(14, 32);
  }
}
