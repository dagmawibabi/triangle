import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import 'section_kit.dart';

/// A stats page in the shape of Listening stats: the header with the big
/// numbers, time per day over 7, 14 or 30 days, then the page's own cards.
/// Follows the Explore look (branded or minimal).
class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.stats,
    required this.valueOn,
    required this.format,
    required this.cards,
    this.chartTitle = 'Time',
    this.goal,
    this.onClear,
    this.clearMessage = '',
  });
  final String title;
  final IconData icon;
  final Color color;
  final String subtitle;
  final List<(String, String)> stats;

  /// The amount on a day (seconds, minutes…).
  final num Function(DateTime day) valueOn;

  /// An amount as words, like "1h 20m".
  final String Function(num v) format;

  /// Cards under the chart: a title and what's in it.
  final List<(String, Widget)> cards;
  final String chartTitle;

  /// A daily goal drawn across the chart.
  final num? goal;
  final Future<void> Function()? onClear;
  final String clearMessage;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _range = 14;

  @override
  Widget build(BuildContext context) {
    final accent = AppLook.brand(widget.color);
    final now = DateTime.now();
    final days = [
      for (var i = _range - 1; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
          return (d, widget.valueOn(d));
        }(),
    ];
    final top = days.fold<num>(widget.goal ?? 1, (m, d) => d.$2 > m ? d.$2 : m).clamp(1, double.infinity);
    final sum = days.fold<num>(0, (a, d) => a + d.$2);
    final active = days.where((d) => d.$2 > 0).length;
    return SectionScaffold(
      title: widget.title,
      icon: widget.icon,
      color: widget.color,
      expandedHeight: 200,
      actions: [
        if (widget.onClear != null)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear' && await confirmDelete(context, title: 'Clear ${widget.title.toLowerCase()}?', message: widget.clearMessage, action: 'Clear')) {
                await widget.onClear!();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear stats'))],
          ),
      ],
      hero: SectionHero(subtitle: widget.subtitle, stats: widget.stats),
      slivers: [
        SliverToBoxAdapter(
          child: StatsCard(
            title: widget.chartTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.format(sum), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          Text('last $_range days · $active active · ${widget.format(sum / _range)} a day', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                    ),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 14, label: Text('14d')), ButtonSegment(value: 30, label: Text('30d'))],
                      selected: {_range},
                      onSelectionChanged: (v) => setState(() => _range = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: Space.l),
                SizedBox(
                  height: 132,
                  child: Stack(
                    children: [
                      if (widget.goal != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 18 + (widget.goal! / top) * 106,
                          child: Row(
                            children: [
                              Expanded(child: Container(height: 1, color: AppColors.text3.withValues(alpha: 0.5))),
                              const SizedBox(width: 4),
                              Text('goal', style: TextStyle(fontSize: 9.5, color: AppColors.text3)),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final (i, (d, v)) in days.indexed)
                            Expanded(
                              child: Tooltip(
                                message: '${d.day}/${d.month}: ${widget.format(v)}',
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                      height: v <= 0 ? 3 : (v / top * 106).clamp(4, 106).toDouble(),
                                      margin: EdgeInsets.symmetric(horizontal: _range > 14 ? 1.5 : 3),
                                      decoration: BoxDecoration(
                                        color: v <= 0 ? AppColors.line : (i == days.length - 1 ? accent : accent.withValues(alpha: 0.55)),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 14,
                                      child: _range <= 14 || i % 5 == 0 || i == days.length - 1
                                          ? Text(
                                              _range == 7 ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1] : '${d.day}',
                                              style: TextStyle(fontSize: 9.5, color: i == days.length - 1 ? AppColors.text : AppColors.text3, fontWeight: i == days.length - 1 ? FontWeight.w800 : FontWeight.w500),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final (t, w) in widget.cards) SliverToBoxAdapter(child: StatsCard(title: t, child: w)),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x4 + 80)),
      ],
    );
  }
}

/// A titled card on a stats page.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
    child: Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: Space.m), child],
      ),
    ),
  );
}

/// A ranked row on a stats page: place, picture, title, words, a bar for
/// its share and its amount.
class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.rank, required this.title, this.subtitle = '', required this.value, required this.fraction, this.leading, this.color, this.onTap});
  final int rank;
  final String title;
  final String subtitle;
  final String value;
  final double fraction;
  final Widget? leading;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppLook.brand(color ?? AppColors.text);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 22, child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text3, fontFeatures: tabularFigures))),
            if (leading != null) ...[leading!, const SizedBox(width: Space.m)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: fraction.clamp(0, 1), minHeight: 3, color: c.withValues(alpha: 0.7), backgroundColor: AppColors.line),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text2, fontFeatures: tabularFigures)),
          ],
        ),
      ),
    );
  }
}

/// A small number with its word, in a soft box.
class StatsFact extends StatelessWidget {
  const StatsFact(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 100,
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.text3),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text, fontFeatures: tabularFigures)),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.text3)),
      ],
    ),
  );
}

/// A duration in seconds as "1h 20m", "12m" or "40s".
String durationWords(num seconds) {
  final s = seconds.round();
  if (s < 60) return '${s}s';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}
