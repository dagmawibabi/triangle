import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../sections/stats_page.dart';
import 'books.dart';
import 'books_screen.dart' show BookCover, openBookDetail;

/// Reading stats: minutes per day against the daily goal, the streak, the
/// books the time went to, authors, and what got finished this year.
class ReadingStatsScreen extends ConsumerWidget {
  const ReadingStatsScreen({super.key});

  static String _mins(num m) {
    final v = m.round();
    if (v < 60) return '${v}m';
    return '${v ~/ 60}h ${v % 60}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(booksProvider);
    final now = DateTime.now();
    final total = s.days.values.fold<int>(0, (a, b) => a + b);
    final finished = s.books.where((b) => b.status == ReadStatus.finished).toList()..sort((a, b) => (b.finishedAt ?? b.addedAt).compareTo(a.finishedAt ?? a.addedAt));
    final thisYear = finished.where((b) => b.finishedAt?.year == now.year).toList();
    final reading = s.books.where((b) => b.status == ReadStatus.reading).toList();
    final top = ([...s.books]..sort((a, b) => b.minutes.compareTo(a.minutes))).where((b) => b.minutes > 0).take(8).toList();
    final authors = <String, int>{};
    for (final b in s.books) {
      if (b.author.isNotEmpty && b.minutes > 0) authors[b.author] = (authors[b.author] ?? 0) + b.minutes;
    }
    final topAuthors = (authors.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).toList();
    final goalDays = s.days.values.where((m) => m >= s.goal).length;
    final first = s.days.keys.isEmpty ? null : (s.days.keys.toList()..sort()).first;

    return StatsPage(
      title: 'Reading stats',
      icon: Icons.insights_rounded,
      color: const Color(0xFF8B5CF6),
      subtitle: s.days.isEmpty ? 'Read something and it shows up here.' : 'Since $first · goal ${s.goal} min a day',
      stats: [
        (_mins(total), 'read'),
        ('${finished.length}', 'finished'),
        ('${s.streak}', s.streak == 1 ? 'day streak' : 'days streak'),
        ('${s.todayMinutes}/${s.goal}', 'min today'),
      ],
      chartTitle: 'Minutes read',
      goal: s.goal,
      valueOn: (d) => s.days[BooksState.dayKey(d)] ?? 0,
      format: _mins,
      cards: [
        (
          'Habits',
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              StatsFact(Icons.flag_outlined, '$goalDays', 'goal days'),
              StatsFact(Icons.auto_stories_outlined, '${reading.length}', 'reading now'),
              StatsFact(Icons.emoji_events_outlined, '${thisYear.length}', 'finished ${now.year}'),
              StatsFact(Icons.timer_outlined, s.days.isEmpty ? '–' : _mins(total / s.days.length), 'per reading day'),
              StatsFact(Icons.border_color_outlined, '${s.highlights.length}', 'highlights'),
              StatsFact(Icons.bookmark_border_rounded, '${s.bookmarks.length}', 'bookmarks'),
            ],
          ),
        ),
        if (top.isNotEmpty)
          (
            'Most read',
            Column(
              children: [
                for (final (i, b) in top.indexed)
                  StatsRow(
                    rank: i + 1,
                    leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 30, height: 44, child: BookCover(book: b, width: 30))),
                    title: b.title,
                    subtitle: [if (b.author.isNotEmpty) b.author, '${(b.progress * 100).round()}%'].join(' · '),
                    value: _mins(b.minutes),
                    fraction: b.minutes / top.first.minutes,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => openBookDetail(context, b),
                  ),
              ],
            ),
          ),
        if (topAuthors.isNotEmpty)
          (
            'Top authors',
            Column(
              children: [
                for (final (i, a) in topAuthors.indexed)
                  StatsRow(rank: i + 1, title: a.key, value: _mins(a.value), fraction: a.value / topAuthors.first.value, color: const Color(0xFF8B5CF6)),
              ],
            ),
          ),
        if (finished.isNotEmpty)
          (
            'Finished',
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: finished.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                itemBuilder: (_, i) {
                  final b = finished[i];
                  return GestureDetector(
                    onTap: () => openBookDetail(context, b),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCover(book: b, width: 76),
                          const SizedBox(height: 4),
                          Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
