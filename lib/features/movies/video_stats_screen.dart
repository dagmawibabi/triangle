import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../sections/activity_stats.dart';
import '../sections/stats_page.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'movies.dart';
import 'movies_screen.dart' show WatchScreen;

/// Watching stats: time watched per day, the videos and channels it went
/// to, how much got finished, and what's in My list.
class VideoStatsScreen extends ConsumerWidget {
  const VideoStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(activityStatsProvider('video'));
    final m = ref.watch(moviesProvider);
    final top = s.top.where((i) => i.seconds > 0).take(10).toList();
    final groups = s.groups.take(8).toList();
    final finished = m.progress.values.where((p) => p.finished).length;
    final started = m.progress.length;
    final maxItem = top.isEmpty ? 1 : top.first.seconds;
    final maxGroup = groups.isEmpty ? 1 : groups.first.$2;

    Widget thumb(ActivityItem i) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        height: 36,
        child: i.mini == null ? ColoredBox(color: AppColors.surface2, child: Icon(Icons.movie_outlined, size: 16, color: AppColors.text3)) : Image.memory(base64Decode(i.mini!), fit: BoxFit.cover),
      ),
    );

    return StatsPage(
      title: 'Watching stats',
      icon: Icons.insights_rounded,
      color: const Color(0xFFE50914),
      subtitle: s.items.isEmpty ? 'Watch something and it shows up here.' : 'Since ${_date(s.since ?? DateTime.now())}',
      stats: [
        (durationWords(s.totalSeconds), 'watched'),
        ('${s.items.length}', 'videos'),
        ('$finished', 'finished'),
        ('${s.streak}', s.streak == 1 ? 'day streak' : 'days streak'),
      ],
      chartTitle: 'Time watched',
      valueOn: (d) => s.days[ActivityStatsState.dayKey(d)] ?? 0,
      format: durationWords,
      onClear: () => ref.read(activityStatsProvider('video').notifier).clear(),
      clearMessage: 'Time watched is forgotten. Progress and My list stay.',
      cards: [
        (
          'Habits',
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              StatsFact(Icons.today_rounded, durationWords(s.today), 'today'),
              StatsFact(Icons.play_circle_outline_rounded, '$started', 'started'),
              StatsFact(Icons.task_alt_rounded, started == 0 ? '–' : '${(finished / started * 100).round()}%', 'finished'),
              StatsFact(Icons.bookmark_border_rounded, '${m.myList.length}', 'in My list'),
              StatsFact(Icons.thumb_up_alt_outlined, '${m.liked.length}', 'liked'),
              StatsFact(Icons.subscriptions_outlined, '${m.sources.length}', 'channels'),
            ],
          ),
        ),
        if (top.isNotEmpty)
          (
            'Most watched',
            Column(
              children: [
                for (final (i, x) in top.indexed)
                  StatsRow(
                    rank: i + 1,
                    leading: thumb(x),
                    title: x.title,
                    subtitle: x.group,
                    value: durationWords(x.seconds),
                    fraction: x.seconds / maxItem,
                    color: const Color(0xFFE50914),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: x.key))),
                  ),
              ],
            ),
          ),
        if (groups.isNotEmpty)
          (
            'Top channels',
            Column(
              children: [
                for (final (i, g) in groups.indexed)
                  StatsRow(
                    rank: i + 1,
                    leading: TgAvatar(chatId: g.$3, title: g.$1, size: 30),
                    title: g.$1,
                    value: durationWords(g.$2),
                    fraction: g.$2 / maxGroup,
                    color: const Color(0xFFE50914),
                  ),
              ],
            ),
          ),
        if (s.items.isNotEmpty)
          (
            'Lately',
            Column(
              children: [
                for (final x in s.recent.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: thumb(x),
                    title: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${x.group} · ${_ago(x.last)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: x.key))),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String _date(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

String _ago(DateTime d) {
  final e = DateTime.now().difference(d);
  if (e.inMinutes < 1) return 'just now';
  if (e.inHours < 1) return '${e.inMinutes} min ago';
  if (e.inDays < 1) return '${e.inHours} h ago';
  return '${e.inDays} d ago';
}
