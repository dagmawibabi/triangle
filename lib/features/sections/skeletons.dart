import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

// Loading skeletons for the Explore pages: the shape of what's coming,
// with a soft light sweeping across, instead of a spinner.

/// Sweeps a soft highlight across its [child]'s bones, over and over.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surface2;
    final light = Color.lerp(base, AppColors.isLight ? Colors.white : AppColors.surface3, AppColors.isLight ? 0.75 : 0.9)!;
    // Bones mean nothing to a screen reader, and keeping them out of the
    // semantics tree spares it an update on every shimmer frame.
    return AnimatedBuilder(
      animation: _c,
      child: ExcludeSemantics(child: widget.child),
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = -1.5 + 3.0 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 1, -0.3),
            end: Alignment(x + 1, 0.3),
            colors: [base, light, base],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(r);
        },
        child: child,
      ),
    );
  }
}

/// One grey shape in a skeleton.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surface2, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(radius)),
  );
}

/// A square bone that fills its width.
class SquareBone extends StatelessWidget {
  const SquareBone({super.key, this.radius = 14, this.aspect = 1});
  final double radius;
  final double aspect;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspect,
    child: DecoratedBox(decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(radius))),
  );
}

/// Rows with a picture on the left and two or three lines of text.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 6, this.art = 56, this.artRadius = 12, this.lines = 2, this.padding = const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s), this.trailing = false});
  final int count;
  final double? art;
  final double artRadius;
  final int lines;
  final EdgeInsets padding;

  /// A round button on the right, like play.
  final bool trailing;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: padding,
            child: Row(
              children: [
                if (art != null) ...[Bone(width: art, height: art!, radius: artRadius), const SizedBox(width: Space.m)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: i.isEven ? 0.85 : 0.65, child: const Bone(height: 13)),
                      const SizedBox(height: 7),
                      FractionallySizedBox(widthFactor: i.isEven ? 0.45 : 0.55, child: const Bone(height: 10)),
                      if (lines > 2) ...[const SizedBox(height: 6), const FractionallySizedBox(widthFactor: 0.35, child: Bone(height: 10))],
                    ],
                  ),
                ),
                if (trailing) ...[const SizedBox(width: Space.m), const Bone(height: 40, circle: true)],
              ],
            ),
          ),
      ],
    ),
  );
}

/// A skeleton standing in for a whole tab: scrollable, like the page it
/// replaces, so the tab under a [NestedScrollView] keeps a scroll view of
/// its own (and the header still folds) while it loads.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [SliverToBoxAdapter(child: child)]);
}

/// [count] cells in rows, laid out like a grid but without a scroll view of
/// its own: a skeleton sits inside the page's scroll view (often in a
/// [SliverFillRemaining], which measures it), and a nested scrollable
/// there breaks layout and semantics. Columns come from the screen width,
/// as [SliverGridDelegateWithMaxCrossAxisExtent] (or [columns]) would.
class BoneGrid extends StatelessWidget {
  const BoneGrid({super.key, required this.count, required this.cell, this.maxExtent = 150, this.columns, this.padding = EdgeInsets.zero, this.spacing = Space.m, this.runSpacing = Space.l, this.aspectRatio});
  final int count;
  final Widget Function(int i) cell;
  final double maxExtent;
  final int? columns;
  final EdgeInsets padding;
  final double spacing;
  final double runSpacing;

  /// Width over height of each cell, when it should keep a fixed shape.
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - padding.horizontal;
    final cols = columns ?? math.max(1, (width / (maxExtent + spacing)).ceil());
    final rows = (count / cols).ceil();
    Widget at(int i) {
      if (i >= count) return const SizedBox.shrink();
      final c = cell(i);
      return aspectRatio == null ? c : AspectRatio(aspectRatio: aspectRatio!, child: Align(alignment: Alignment.topLeft, child: c));
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows; r++)
            Padding(
              padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : runSpacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(child: at(r * cols + c)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A grid of square tiles with a title line under each.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 9, this.maxExtent = 150, this.childAspectRatio = 0.7, this.padding = const EdgeInsets.all(Space.l), this.captions = true, this.radius = 14});
  final int count;
  final double maxExtent;
  final double childAspectRatio;
  final EdgeInsets padding;
  final bool captions;
  final double radius;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: BoneGrid(
      count: count,
      maxExtent: maxExtent,
      padding: padding,
      aspectRatio: childAspectRatio,
      cell: (i) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SquareBone(radius: radius),
          if (captions) ...[
            const SizedBox(height: 8),
            FractionallySizedBox(widthFactor: i.isEven ? 0.9 : 0.7, child: const Bone(height: 11)),
            const SizedBox(height: 5),
            const FractionallySizedBox(widthFactor: 0.5, child: Bone(height: 9)),
          ],
        ],
      ),
    ),
  );
}

/// A photo grid's skeleton: tight square tiles.
class SkeletonTiles extends StatelessWidget {
  const SkeletonTiles({super.key, this.columns = 4, this.count = 24});
  final int columns;
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: BoneGrid(
      count: count,
      columns: columns,
      spacing: 2,
      runSpacing: 2,
      aspectRatio: 1,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: Space.l),
      cell: (_) => DecoratedBox(decoration: BoxDecoration(color: AppColors.surface2), child: const SizedBox.expand()),
    ),
  );
}

/// Cards like a job listing: logo, two lines, chips, a footer.
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.count = 4, this.padding = const EdgeInsets.symmetric(horizontal: Space.l)});
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: Space.s),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Bone(width: 46, height: 46, radius: 12),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(widthFactor: i.isEven ? 0.8 : 0.6, child: const Bone(height: 14)),
                            const SizedBox(height: 7),
                            const FractionallySizedBox(widthFactor: 0.45, child: Bone(height: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  const Row(children: [Bone(width: 70, height: 20, radius: 99), SizedBox(width: 6), Bone(width: 56, height: 20, radius: 99), SizedBox(width: 6), Bone(width: 90, height: 20, radius: 99)]),
                  const SizedBox(height: Space.m),
                  const FractionallySizedBox(widthFactor: 0.4, child: Bone(height: 9)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A big page's top: a picture, a title and lines (a show or an event).
class SkeletonHeader extends StatelessWidget {
  const SkeletonHeader({super.key, this.art = 132});
  final double art;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Bone(width: art, height: art, radius: 18),
          const SizedBox(width: Space.l),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(height: 18),
                SizedBox(height: 8),
                FractionallySizedBox(widthFactor: 0.7, child: Bone(height: 18)),
                SizedBox(height: 12),
                FractionallySizedBox(widthFactor: 0.5, child: Bone(height: 11)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
