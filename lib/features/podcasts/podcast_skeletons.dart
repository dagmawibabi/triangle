import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../sections/skeletons.dart';
import 'podcast_models.dart';
import 'podcast_widgets.dart';

// Loading skeletons shaped like Podcasts' and Radio's real rows and pages,
// so nothing jumps when the content arrives. Whatever is already known (a
// chart entry's art and title) is drawn for real; only the rest shimmers.

/// The charts grid while it loads: art, a rank badge, two title lines and
/// a genre line, on the same grid as the real one.
class PodcastGridSkeleton extends StatelessWidget {
  const PodcastGridSkeleton({super.key, this.count = 12, this.ranked = true});
  final int count;
  final bool ranked;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: BoneGrid(
      count: count,
      maxExtent: 150,
      aspectRatio: 0.66,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
      cell: (i) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              const SquareBone(radius: 14),
              if (ranked)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 20,
                    height: 18,
                    decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(widthFactor: i % 3 == 0 ? 0.95 : 0.8, child: const Bone(height: 11)),
          const SizedBox(height: 5),
          if (i.isEven) ...[const FractionallySizedBox(widthFactor: 0.6, child: Bone(height: 11)), const SizedBox(height: 6)],
          FractionallySizedBox(widthFactor: i % 3 == 1 ? 0.4 : 0.55, child: const Bone(height: 8)),
        ],
      ),
    ),
  );
}

/// Search results while they load: like the result rows (art, a title,
/// the author and genre, a chevron).
class PodcastHitSkeleton extends StatelessWidget {
  const PodcastHitSkeleton({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 10),
            child: Row(
              children: [
                const Bone(width: 56, height: 56, radius: 12),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: i.isEven ? 0.8 : 0.6, child: const Bone(height: 13)),
                      const SizedBox(height: 7),
                      FractionallySizedBox(widthFactor: i % 3 == 0 ? 0.65 : 0.5, child: const Bone(height: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.m),
                const Bone(width: 10, height: 14, radius: 3),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Stations while they load: like a station row (logo, name, where it's
/// from, its bitrate, a heart).
class StationSkeleton extends StatelessWidget {
  const StationSkeleton({super.key, this.count = 9});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 9),
            child: Row(
              children: [
                const Bone(width: 52, height: 52, radius: 12),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.5, child: const Bone(height: 13)),
                      const SizedBox(height: 6),
                      FractionallySizedBox(widthFactor: i % 3 == 0 ? 0.55 : 0.4, child: const Bone(height: 10)),
                      const SizedBox(height: 5),
                      const FractionallySizedBox(widthFactor: 0.25, child: Bone(height: 8)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.m),
                const Padding(padding: EdgeInsets.all(8), child: Bone(height: 22, circle: true)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Episodes while they load: like an episode row (a title over one or two
/// lines, the date and length, the play button).
class EpisodeSkeleton extends StatelessWidget {
  const EpisodeSkeleton({super.key, this.count = 7});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: i % 3 == 2 ? 0.75 : 0.95, child: const Bone(height: 14)),
                      if (i % 3 != 2) ...[const SizedBox(height: 6), FractionallySizedBox(widthFactor: i.isEven ? 0.55 : 0.7, child: const Bone(height: 14))],
                      const SizedBox(height: 8),
                      FractionallySizedBox(widthFactor: i.isEven ? 0.35 : 0.42, child: const Bone(height: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                const Bone(height: 40, circle: true),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A show's page while its feed loads: the header (with [hit]'s art and
/// title when it came from the directory), the follow and play buttons,
/// the search and filter bar, and episode rows.
class PodcastShowSkeleton extends StatelessWidget {
  const PodcastShowSkeleton({super.key, this.hit});
  final PodcastHit? hit;

  @override
  Widget build(BuildContext context) {
    final h = hit;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 330,
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.text,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, kToolbarHeight + Space.s, Space.xl, Space.l),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (h != null)
                          PodArt(h.artwork, title: h.title, size: 132, radius: 18)
                        else
                          const Shimmer(child: Bone(width: 132, height: 132, radius: 18)),
                        const SizedBox(width: Space.l),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (h != null) ...[
                                Text(h.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 21, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text)),
                                if (h.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(h.author, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text2))),
                                const SizedBox(height: 8),
                                const Shimmer(child: FractionallySizedBox(widthFactor: 0.45, child: Bone(height: 10))),
                              ] else
                                const Shimmer(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Bone(height: 18),
                                      SizedBox(height: 8),
                                      FractionallySizedBox(widthFactor: 0.7, child: Bone(height: 18)),
                                      SizedBox(height: 10),
                                      FractionallySizedBox(widthFactor: 0.5, child: Bone(height: 12)),
                                      SizedBox(height: 10),
                                      FractionallySizedBox(widthFactor: 0.4, child: Bone(height: 10)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.l),
                    const Shimmer(
                      child: Row(
                        children: [
                          Expanded(child: Bone(height: 46, radius: 99)),
                          SizedBox(width: Space.s),
                          Bone(height: 46, circle: true),
                          SizedBox(width: Space.s),
                          Bone(height: 46, circle: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Shimmer(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Bone(height: 10),
                  const SizedBox(height: 6),
                  const FractionallySizedBox(widthFactor: 0.85, child: Bone(height: 10)),
                  const SizedBox(height: Space.l),
                  Row(
                    children: [
                      const Expanded(child: Bone(height: 42, radius: 99)),
                      const SizedBox(width: Space.m),
                      Bone(width: 70, height: 16, radius: 6),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  const Wrap(
                    spacing: 0,
                    runSpacing: 6,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Bone(width: 64, height: 28, radius: 99),
                      SizedBox(width: 6),
                      Bone(width: 96, height: 28, radius: 99),
                      SizedBox(width: 6),
                      Bone(width: 104, height: 28, radius: 99),
                      SizedBox(width: 6),
                      Bone(width: 80, height: 28, radius: 99),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: EpisodeSkeleton(count: 8)),
      ],
    );
  }
}
