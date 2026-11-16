import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../media/music_stats.dart';
import '../sections/section_kit.dart';
import 'playlist_widgets.dart';
import 'playlists.dart';
import 'playlists_screen.dart' show PlaylistScreen;

/// Listening stats: time listened, plays, streak, the last two weeks,
/// top tracks, artists and playlists, and what played lately.
class MusicStatsScreen extends ConsumerStatefulWidget {
  const MusicStatsScreen({super.key});

  @override
  ConsumerState<MusicStatsScreen> createState() => _MusicStatsScreenState();
}

class _MusicStatsScreenState extends ConsumerState<MusicStatsScreen> {
  int _range = 14;

  static String _hours(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(musicStatsProvider);
    final lists = ref.watch(playlistsProvider).playlists;
    final now = DateTime.now();
    final days = [
      for (var i = _range - 1; i >= 0; i--)
        () {
          final d = now.subtract(Duration(days: i));
          return (d, s.days[MusicStatsState.dayKey(d)] ?? 0);
        }(),
    ];
    final maxDay = days.fold<int>(1, (m, d) => d.$2 > m ? d.$2 : m);
    final inRange = days.fold<int>(0, (a, d) => a + d.$2);
    final top = s.top.take(10).toList();
    final artists = s.artists.take(8).toList();
    final topLists = (s.playlistPlays.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => (lists.where((p) => p.id == e.key).firstOrNull, e.value))
        .where((e) => e.$1 != null)
        .take(6)
        .toList();
    final colour = AppLook.brand(const Color(0xFF1DB954));

    Widget card(String title, Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
      child: Container(
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: Space.m), child],
        ),
      ),
    );

    return SectionScaffold(
      title: 'Listening stats',
      icon: Icons.insights_rounded,
      color: colour,
      expandedHeight: 200,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'clear' &&
                await confirmDelete(context, title: 'Clear listening stats?', message: 'Plays and time listened are forgotten. Playlists stay.', action: 'Clear')) {
              await ref.read(musicStatsProvider.notifier).clear();
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear stats'))],
        ),
      ],
      hero: SectionHero(
        subtitle: s.tracks.isEmpty ? 'Play something and it shows up here.' : 'Since ${_first(s)}',
        stats: [
          (_hours(s.totalSeconds), 'listened'),
          ('${s.totalPlays}', 'plays'),
          ('${s.tracks.length}', 'tracks'),
          ('${s.streak}', s.streak == 1 ? 'day streak' : 'days streak'),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: card(
            'Time listened',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${_hours(inRange)} in the last $_range days', style: context.text.bodySmall)),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 14, label: Text('14d')), ButtonSegment(value: 30, label: Text('30d'))],
                      selected: {_range},
                      onSelectionChanged: (v) => setState(() => _range = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: Space.m),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (d, sec) in days)
                        Expanded(
                          child: Tooltip(
                            message: '${d.day}/${d.month}: ${_hours(sec)}',
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: _range > 14 ? 1 : 3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: sec == 0 ? 3 : 4 + 96 * sec / maxDay,
                                    decoration: BoxDecoration(
                                      color: sec == 0 ? AppColors.surface3 : colour.withValues(alpha: d.day == now.day && d.month == now.month ? 1 : 0.65),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_range <= 14) Text('${d.day}', style: TextStyle(fontSize: 9.5, color: AppColors.text3)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (top.isNotEmpty)
          SliverToBoxAdapter(
            child: card(
              'Top tracks',
              Column(
                children: [
                  for (final (i, t) in top.indexed)
                    _StatRow(rank: i + 1, art: t.artPath, title: t.title, subtitle: t.artist, value: '${t.plays}×', detail: _hours(t.seconds)),
                ],
              ),
            ),
          ),
        if (artists.isNotEmpty)
          SliverToBoxAdapter(
            child: card(
              'Top artists',
              Column(
                children: [
                  for (final (i, a) in artists.indexed) _StatRow(rank: i + 1, title: a.$1, subtitle: '${a.$2} plays', value: _hours(a.$3)),
                ],
              ),
            ),
          ),
        if (topLists.isNotEmpty)
          SliverToBoxAdapter(
            child: card(
              'Top playlists',
              Column(
                children: [
                  for (final (p, n) in topLists)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: PlaylistCover(playlist: p!, size: 44, radius: Radii.s),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(p.summary, style: context.text.bodySmall),
                      trailing: Text('$n plays', style: context.text.labelMedium),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id))),
                    ),
                ],
              ),
            ),
          ),
        if (s.tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: card(
              'Recently played',
              Column(
                children: [
                  for (final t in s.recent.take(15)) _StatRow(art: t.artPath, title: t.title, subtitle: t.artist, value: agoText(t.last)),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x4 * 2)),
      ],
      bottomBar: const BottomAudioBar(),
    );
  }

  static String _first(MusicStatsState s) {
    if (s.tracks.isEmpty) return '';
    final f = s.tracks.values.map((t) => t.first).reduce((a, b) => a.isBefore(b) ? a : b);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${f.day} ${months[f.month - 1]} ${f.year}';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({this.rank, this.art, required this.title, this.subtitle = '', required this.value, this.detail});
  final int? rank;
  final String? art;
  final String title;
  final String subtitle;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        if (rank != null)
          SizedBox(width: 26, child: Text('$rank', style: context.text.titleSmall?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w800))),
        if (art != null && fileExists(art!))
          Padding(
            padding: const EdgeInsets.only(right: Space.m),
            child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image(image: ResizeImage(FileImage(File(art!)), width: 100), width: 38, height: 38, fit: BoxFit.cover)),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (detail != null) Text(detail!, style: context.text.labelSmall),
          ],
        ),
      ],
    ),
  );
}
