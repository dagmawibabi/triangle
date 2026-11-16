import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'image_disk_cache.dart';

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
        // Downloaded once into the app's folder, then read from there
        // (offline too).
        : _DiskImage(
            key: ValueKey(u),
            url: u,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            cacheWidth: width != null && width!.isFinite ? (width! * MediaQuery.devicePixelRatioOf(context)).round() : null,
            loading: Skeleton(width: width, height: height, shape: circle ? BoxShape.circle : BoxShape.rectangle),
            fallback: fallback,
          );
    if (circle) return ClipOval(child: image);
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: image) : image;
  }

  double get _iconSize {
    final s = [width, height].whereType<double>().where((x) => x.isFinite).fold<double?>(null, (a, b) => a == null || b < a ? b : a);
    return s == null ? 22 : (s * 0.4).clamp(14, 32);
  }
}


class _DiskImage extends StatefulWidget {
  const _DiskImage({super.key, required this.url, this.width, this.height, required this.fit, required this.alignment, this.cacheWidth, required this.loading, required this.fallback});
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final Widget loading;
  final Widget Function() fallback;

  @override
  State<_DiskImage> createState() => _DiskImageState();
}

class _DiskImageState extends State<_DiskImage> {
  late File? _file = ImageDiskCache.peek(widget.url);

  /// It was already on the phone: shown at once, no fade.
  late final bool _instant = _file != null;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_file == null) {
      ImageDiskCache.get(widget.url).then((f) {
        if (!mounted) return;
        setState(() => f == null ? _failed = true : _file = f);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback();
    final f = _file;
    if (f == null) return widget.loading;
    return Image.file(
      f,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => sync || _instant
          ? child
          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: child),
      errorBuilder: (_, _, _) {
        // A broken file: drop it so it's fetched again next time.
        unawaited(f.delete().catchError((_) => f));
        return widget.fallback();
      },
    );
  }
}
