import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../device/device.dart';
import '../../../device/net.dart';
import '../../../screen_time/screen_time.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for screen_time and app_usage. Null for other tools.
Widget? screenTimeResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'screen_time' when j['view'] == 'week' && j['daily'] != null => _WeekCard(w: j),
  'screen_time' when j['total'] != null => _DayCard(d: j),
  'app_usage' when j['series'] != null => _AppCard(a: j),
  _ => null,
};

const _accent = Color(0xFF7C6CF6);

String _min(num? m) => screenDuration((m ?? 0) * 60000);

/// An installed app's icon, or its initial.
class AppIcon extends StatelessWidget {
  const AppIcon(this.package, {super.key, this.name, this.size = 32});
  final String package;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(
        (name ?? package).trim().isEmpty ? '?' : (name ?? package).trim().characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.42, color: AppColors.text2),
      ),
    );
    if (!Device.supported) return fallback;
    return FutureBuilder<Uint8List?>(
      future: Net.appIcon(package),
      builder: (context, snap) => snap.data == null
          ? fallback
          : ClipRRect(borderRadius: BorderRadius.circular(size * 0.22), child: Image.memory(snap.data!, width: size, height: size, gaplessPlayback: true)),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.top, this.detailed = false});
  final Map<String, dynamic> app;
  final num top;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final m = numOf(app['minutes']) ?? 0;
    return InkWell(
      onTap: () => showAppUsage(context, '${app['package']}', '${app['name']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
        child: Row(
          children: [
            AppIcon('${app['package']}', name: '${app['name']}', size: 30),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${app['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                      Text('${app['time']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFeatures: tabularFigures)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ShareBar(top == 0 ? 0 : (m / top).toDouble(), color: _accent),
                  if (detailed) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (app['opens'] != null) '${app['opens']} opens',
                        if (app['share'] != null) '${app['share']}% of screen time',
                        if (app['category'] != null) '${app['category']}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _apps(List<Map<String, dynamic>> apps, {int take = 5, bool detailed = false}) {
  final top = apps.isEmpty ? 0 : numOf(apps.first['minutes']) ?? 0;
  return Column(children: [for (final a in apps.take(take)) _AppRow(app: a, top: top, detailed: detailed)]);
}

Widget _hourChart(List<num> hours, {double height = 64}) {
  final peak = hours.isEmpty ? null : hours.indexOf(hours.reduce((a, b) => a > b ? a : b));
  return MiniBars(
    values: hours,
    labels: [for (var i = 0; i < hours.length; i++) i == 0 ? '12a' : i == 12 ? '12p' : i == 6 ? '6a' : i == 18 ? '6p' : ''],
    highlight: peak,
    color: _accent,
    height: height,
    valueLabel: (v) => _min(v),
  );
}

Widget _categories(BuildContext context, Map<String, dynamic> cats) {
  final total = cats.values.fold<num>(0, (s, v) => s + (numOf(v) ?? 0));
  if (total == 0) return const SizedBox.shrink();
  const colors = [Color(0xFF7C6CF6), Color(0xFF3DB6E8), Color(0xFFF0A73C), Color(0xFFE5586E), Color(0xFF4CC38A), Color(0xFFB07CE8), Color(0xFF8A8A99)];
  final entries = cats.entries.toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 10,
          child: Row(
            children: [
              for (final (i, e) in entries.indexed)
                Expanded(flex: (((numOf(e.value) ?? 0) / total) * 1000).round().clamp(1, 1000), child: Container(color: colors[i % colors.length])),
            ],
          ),
        ),
      ),
      const SizedBox(height: Space.s),
      Wrap(
        spacing: Space.m,
        runSpacing: 4,
        children: [
          for (final (i, e) in entries.indexed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('${e.key[0].toUpperCase()}${e.key.substring(1)} · ${_min(numOf(e.value))}', style: TextStyle(fontSize: 12, color: AppColors.text2)),
              ],
            ),
        ],
      ),
    ],
  );
}

// ---- one day -----------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final hours = [for (final h in (d['hourly_minutes'] as List? ?? const [])) numOf(h) ?? 0];
    final apps = maps(d['top_apps']);
    return InfoFrame(
      onTap: () => _showDay(context, d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.hourglass_bottom_rounded, d['is_today'] == true ? 'Screen time today' : 'Screen time · ${d['weekday']} ${d['date']}', color: _accent),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${d['total']}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: tabularFigures)),
                const SizedBox(width: Space.s),
                if (numOf(d['vs_average_percent']) != null)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: ChangeChip(numOf(d['vs_average_percent'])!, suffix: ' vs avg')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 4, Space.m, Space.m),
            child: Text(
              [
                if (d['unlocks'] != null) '${d['unlocks']} unlocks',
                if (d['first_use'] != null) 'first use ${d['first_use']}',
                if (d['busiest_hour'] != null) 'busiest at ${d['busiest_hour']}',
              ].join(' · '),
              style: TextStyle(color: AppColors.text3, fontSize: 12.5),
            ),
          ),
          if (hours.any((h) => h > 0)) Padding(padding: const EdgeInsets.symmetric(horizontal: Space.m), child: _hourChart(hours)),
          const SizedBox(height: Space.s),
          _apps(apps),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}

void _showDay(BuildContext context, Map<String, dynamic> d) {
  final hours = [for (final h in (d['hourly_minutes'] as List? ?? const [])) numOf(h) ?? 0];
  final week = maps(d['week']);
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${d['total']}', subtitle: '${d['is_today'] == true ? 'Today' : d['weekday']} · ${d['date']}'),
      const SizedBox(height: Space.l),
      infoGrid([
        InfoStat('Unlocks', '${d['unlocks'] ?? '—'}', icon: Icons.lock_open_rounded),
        InfoStat('First use', '${d['first_use'] ?? '—'}', icon: Icons.wb_twilight_rounded),
        InfoStat('Busiest hour', '${d['busiest_hour'] ?? '—'}', icon: Icons.schedule_rounded),
        InfoStat('Usual day', '${d['average_of_previous_days'] ?? '—'}', icon: Icons.av_timer_rounded),
      ]),
      if (hours.any((h) => h > 0)) ...[const SectionLabel('By hour'), _hourChart(hours, height: 110)],
      if (mapOf(d['categories']).isNotEmpty) ...[const SectionLabel('Categories'), _categories(context, mapOf(d['categories']))],
      if (week.length > 1) ...[
        const SectionLabel('This week'),
        MiniBars(
          values: [for (final w in week) numOf(w['minutes']) ?? 0],
          labels: [for (final w in week) '${w['weekday']}'],
          highlight: week.length - 1,
          color: _accent,
          height: 90,
          valueLabel: (v) => _min(v),
        ),
      ],
      SectionLabel('Apps', trailing: '${maps(d['top_apps']).length}'),
      _apps(maps(d['top_apps']), take: 50, detailed: true),
      _accessNote(d),
    ],
  );
}

Widget _accessNote(Map<String, dynamic> d) => Padding(
  padding: const EdgeInsets.only(top: Space.l),
  child: Text(
    'From Android\'s usage stats; nothing is copied off the phone. Home screen and system UI time isn\'t counted.'
    '${d['detailed_history_since'] == null ? '' : ' Detailed history from ${d['detailed_history_since']}.'}',
    style: TextStyle(fontSize: 11.5, color: AppColors.text3),
  ),
);

// ---- the week ----------------------------------------------------------------------

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.w});
  final Map<String, dynamic> w;

  @override
  Widget build(BuildContext context) {
    final daily = maps(w['daily']);
    final prev = maps(w['previous_daily']);
    return InfoFrame(
      onTap: () => _showWeek(context, w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.calendar_view_week_rounded, 'Screen time · last 7 days', color: _accent),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${w['average_per_day']}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: tabularFigures)),
                      Text('a day on average · ${w['total']} in all', style: TextStyle(color: AppColors.text3, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (numOf(w['change_percent']) != null) ChangeChip(numOf(w['change_percent'])!, suffix: ' vs last week'),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: MiniBars(
              values: [for (final d in daily) numOf(d['minutes']) ?? 0],
              ghost: prev.length == daily.length ? [for (final d in prev) numOf(d['minutes']) ?? 0] : const [],
              labels: [for (final d in daily) '${d['weekday']}'],
              highlight: daily.length - 1,
              color: _accent,
              height: 90,
              valueLabel: (v) => _min(v),
            ),
          ),
          const SizedBox(height: Space.s),
          _apps(maps(w['top_apps']), take: 4),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}

void _showWeek(BuildContext context, Map<String, dynamic> w) {
  final daily = maps(w['daily']);
  final prev = maps(w['previous_daily']);
  final hours = [for (final h in (w['hourly_minutes'] as List? ?? const [])) numOf(h) ?? 0];
  final busiest = mapOf(w['busiest_day']), quietest = mapOf(w['quietest_day']);
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${w['total']}', subtitle: '${w['from']} – ${w['to']}', trailing: numOf(w['change_percent']) == null ? null : ChangeChip(numOf(w['change_percent'])!)),
      const SizedBox(height: Space.l),
      infoGrid([
        InfoStat('Daily average', '${w['average_per_day']}', icon: Icons.av_timer_rounded),
        InfoStat('Week before', '${w['previous_week_total'] ?? '—'}', icon: Icons.history_rounded),
        InfoStat('Busiest day', busiest.isEmpty ? '—' : '${busiest['weekday']} · ${busiest['time']}', icon: Icons.trending_up_rounded),
        InfoStat('Quietest day', quietest.isEmpty ? '—' : '${quietest['weekday']} · ${quietest['time']}', icon: Icons.trending_down_rounded),
        InfoStat('Unlocks', '${w['unlocks'] ?? '—'}', icon: Icons.lock_open_rounded),
        InfoStat('Per day', daily.isEmpty ? '—' : '${((numOf(w['unlocks']) ?? 0) / daily.length).round()} unlocks', icon: Icons.touch_app_outlined),
      ]),
      const SectionLabel('Day by day', trailing: 'grey: week before'),
      MiniBars(
        values: [for (final d in daily) numOf(d['minutes']) ?? 0],
        ghost: prev.length == daily.length ? [for (final d in prev) numOf(d['minutes']) ?? 0] : const [],
        labels: [for (final d in daily) '${d['weekday']}'],
        highlight: daily.length - 1,
        color: _accent,
        height: 120,
        valueLabel: (v) => _min(v),
      ),
      const SizedBox(height: Space.s),
      for (final (i, d) in daily.indexed)
        KeyValueRow(
          '${d['weekday']} ${'${d['date']}'.substring(5)}',
          '${d['time']}${d['unlocks'] == null ? '' : ' · ${d['unlocks']} unlocks'}'
          '${i < prev.length ? '   (was ${prev[i]['time']})' : ''}${d['estimated'] == true ? ' · from daily summary' : ''}',
        ),
      if (hours.any((h) => h > 0)) ...[const SectionLabel('Average day, by hour'), _hourChart(hours, height: 100)],
      if (mapOf(w['categories']).isNotEmpty) ...[const SectionLabel('Categories'), _categories(context, mapOf(w['categories']))],
      SectionLabel('Top apps', trailing: '${maps(w['top_apps']).length}'),
      _apps(maps(w['top_apps']), take: 50, detailed: true),
      _accessNote(w),
    ],
  );
}

// ---- one app -----------------------------------------------------------------------

class _AppCard extends StatelessWidget {
  const _AppCard({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final series = maps(a['series']);
    return InfoFrame(
      onTap: () => _showApp(context, a),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIcon('${a['package']}', name: '${a['name']}', size: 44),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['name']}', style: context.text.titleMedium),
                      Text('${a['time']} in ${a['days']} days · ${a['average_per_day']} a day', style: context.text.bodySmall),
                    ],
                  ),
                ),
                if (numOf(a['change_percent']) != null) ChangeChip(numOf(a['change_percent'])!),
              ],
            ),
            const SizedBox(height: Space.m),
            MiniBars(
              values: [for (final s in series) numOf(s['minutes']) ?? 0],
              labels: [for (final s in series) '${s['weekday']}'.substring(0, 1)],
              highlight: series.length - 1,
              color: _accent,
              height: 70,
              valueLabel: (v) => _min(v),
            ),
            const SizedBox(height: Space.s),
            Text(
              '${a['days_used']} of ${a['days']} days used · ${a['opens'] ?? 0} opens · ${a['share_of_screen_time']}% of all screen time',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

void _showApp(BuildContext context, Map<String, dynamic> a) {
  final series = maps(a['series']);
  final busiest = mapOf(a['busiest_day']);
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${a['name']}', subtitle: '${a['package']}', leading: AppIcon('${a['package']}', name: '${a['name']}', size: 48)),
      const SizedBox(height: Space.l),
      infoGrid([
        InfoStat('Total', '${a['time']}', icon: Icons.hourglass_bottom_rounded),
        InfoStat('Per day', '${a['average_per_day']}', icon: Icons.av_timer_rounded),
        InfoStat('Days used', '${a['days_used']} of ${a['days']}', icon: Icons.event_available_rounded),
        InfoStat('Opens', '${a['opens'] ?? 0}', icon: Icons.touch_app_outlined),
        InfoStat('Share of screen time', '${a['share_of_screen_time']}%', icon: Icons.pie_chart_outline_rounded),
        InfoStat('Busiest day', busiest.isEmpty ? '—' : '${busiest['date']} · ${_min(numOf(busiest['minutes']))}', icon: Icons.trending_up_rounded),
        if (a['last_used'] != null) InfoStat('Last used', '${a['last_used']}'.replaceFirst('T', ' '), icon: Icons.schedule_rounded),
        if (a['category'] != null) InfoStat('Category', '${a['category']}', icon: Icons.category_outlined),
      ]),
      const SectionLabel('Day by day'),
      MiniBars(
        values: [for (final s in series) numOf(s['minutes']) ?? 0],
        labels: [for (final s in series) '${s['date']}'.substring(8)],
        labelEvery: series.length > 14 ? 3 : 1,
        highlight: series.length - 1,
        color: _accent,
        height: 120,
        valueLabel: (v) => _min(v),
      ),
      const SizedBox(height: Space.s),
      for (final s in series.reversed)
        if ((numOf(s['minutes']) ?? 0) > 0) KeyValueRow('${s['weekday']} ${s['date']}', '${_min(numOf(s['minutes']))} · ${s['opens']} opens'),
    ],
  );
}

/// Loads one app's last two weeks and shows them.
Future<void> showAppUsage(BuildContext context, String package, String name) => showLoadingSheet(
  context,
  () async => analyzeScreenTime(await loadScreenTime(days: 14), view: 'app', app: package),
  (context, a) => a['error'] != null
      ? [Padding(padding: const EdgeInsets.all(Space.xl), child: Text('${a['error']}', textAlign: TextAlign.center))]
      : [
          SheetTitle(name, subtitle: '${a['time']} in 14 days · ${a['average_per_day']} a day', leading: AppIcon(package, name: name, size: 44)),
          const SizedBox(height: Space.l),
          MiniBars(
            values: [for (final s in maps(a['series'])) numOf(s['minutes']) ?? 0],
            labels: [for (final s in maps(a['series'])) '${s['weekday']}'.substring(0, 1)],
            highlight: maps(a['series']).length - 1,
            color: _accent,
            height: 110,
            valueLabel: (v) => _min(v),
          ),
          const SizedBox(height: Space.l),
          infoGrid([
            InfoStat('Days used', '${a['days_used']} of ${a['days']}'),
            InfoStat('Opens', '${a['opens'] ?? 0}'),
            InfoStat('Share', '${a['share_of_screen_time']}%'),
            InfoStat('Trend', numOf(a['change_percent']) == null ? '—' : '${(numOf(a['change_percent'])! > 0 ? '+' : '')}${a['change_percent']}%'),
          ]),
        ],
);
