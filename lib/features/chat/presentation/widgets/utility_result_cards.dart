import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/files/download_progress.dart' show formatBytes;
import '../../../../core/widgets/app_sheet.dart';
import '../../../device/device.dart';
import '../../../device/net.dart';
import '../../../ethiopian/ethiopian_calendar.dart';
import '../../domain/chat_models.dart';

/// Cards for the Ethiopian calendar, QR codes, the phone's SIM cards and
/// connection, speed tests, data usage per app and notifications.
Widget? utilityResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  if (j['access'] == false) {
    return switch (part.name) {
      'phone_data_usage' => const _AccessCard(
        icon: Icons.data_usage_rounded,
        title: 'Allow usage access',
        text: 'Android shares data usage per app only with apps you allow under Usage access. Turn it on for Triangle, then ask again.',
        open: Net.openUsageAccess,
      ),
      'phone_notifications' => const _AccessCard(
        icon: Icons.notifications_active_outlined,
        title: 'Allow notification access',
        text: 'Triangle can keep your notifications for up to 3 days, on this phone only, so you can ask what you missed. Turn on notification access for Triangle; notifications that arrive after that are kept.',
        open: Net.openNotificationAccess,
      ),
      _ => null,
    };
  }
  if (j['error'] != null && part.name != 'speed_test') return null;
  return switch (part.name) {
    'ethiopian_date' when j['ethiopian'] is Map => _EtDateCard(data: j),
    'ethiopian_calendar' when j['year'] is num => _EtMonthCard(year: (j['year'] as num).toInt(), month: (j['month'] as num?)?.toInt() ?? 1),
    'ethiopian_holidays' => _EtHolidaysCard(data: j, events: list(j['events'])),
    'qr_generate' when j['image_path'] is String => _QrMadeCard(data: j),
    'qr_read' => _QrCodesCard(codes: list(j['codes']), file: '${j['file'] ?? ''}'),
    'qr_scan' when j['scanned'] == true => _QrCodesCard(codes: [j], scanned: true),
    'sim_cards' => _SimCard(data: j),
    'speed_test' => _SpeedCard(result: j),
    'phone_data_usage' => _UsageCard(data: j),
    'phone_notifications' => _NotificationsCard(data: j),
    _ => null,
  };
}

// ---- shared ---------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.s),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s + 2), border: Border.all(color: AppColors.line)),
          child: Icon(icon, size: 17, color: AppColors.text),
        ),
        const SizedBox(width: Space.s + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon, this.color, this.filled = false});
  final String text;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: filled ? c : c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: filled ? AppColors.bg : c), const SizedBox(width: 4)],
          Text(text, style: context.text.labelSmall?.copyWith(color: filled ? AppColors.bg : c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
    padding: const EdgeInsets.fromLTRB(Space.s, 2, Space.s, 2),
    child: Row(children: children),
  );
}

Widget _button(IconData icon, String label, VoidCallback? onTap) => TextButton.icon(
  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
  onPressed: onTap,
  icon: Icon(icon, size: 16),
  label: Text(label),
);

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.copy = false});
  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: copy
        ? () {
            Clipboard.setData(ClipboardData(text: value));
            showSnack(context, '$label copied');
          }
        : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
          if (copy) Icon(Icons.copy_rounded, size: 14, color: AppColors.text3),
        ],
      ),
    ),
  );
}

Widget _rows(List<(String, String?, bool)> rows) => Container(
  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
  child: Column(
    children: [
      for (final (i, r) in rows.where((r) => r.$2 != null && r.$2!.isNotEmpty && r.$2 != 'null').indexed) ...[
        if (i > 0) Divider(height: 1, indent: Space.l, endIndent: Space.l, color: AppColors.line),
        _Row(r.$1, r.$2!, copy: r.$3),
      ],
    ],
  ),
);

void _sheet(BuildContext context, String title, List<Widget> Function(BuildContext) children, {double size = 0.75}) => showAppSheet<void>(
  context,
  initialSize: size,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: Space.m),
      ...children(context),
    ],
  ),
);

/// Signal strength as four rising bars.
class _Bars extends StatelessWidget {
  const _Bars({required this.level, this.max = 4});
  final int level;
  final int max;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 14,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 3.5,
            height: 3.5 + i * 2.6,
            decoration: BoxDecoration(color: i * max / 4 <= level ? AppColors.text : AppColors.surface3, borderRadius: BorderRadius.circular(1)),
          ),
      ],
    ),
  );
}

/// An installed app's icon, or its first letter.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.package, required this.name, this.size = 32});
  final String? package;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(size * 0.28), border: Border.all(color: AppColors.line)),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: AppColors.text2)),
    );
    if (package == null || package!.isEmpty || !Device.supported) return fallback;
    return FutureBuilder<Uint8List?>(
      future: Net.appIcon(package!),
      builder: (_, s) => s.data == null
          ? fallback
          : ClipRRect(borderRadius: BorderRadius.circular(size * 0.28), child: Image.memory(s.data!, width: size, height: size, gaplessPlayback: true)),
    );
  }
}

/// Asks for a special Android access the tool needs, with a button there.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.icon, required this.title, required this.text, required this.open});
  final IconData icon;
  final String title;
  final String text;
  final Future<void> Function() open;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.bg),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(text, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
      _Footer(children: [const Spacer(), _button(Icons.open_in_new_rounded, 'Open settings', () => unawaited(open().catchError((Object _) {})))]),
    ],
  );
}

// ---- Ethiopian calendar ---------------------------------------------------------

/// Today (or the date asked about) in both calendars.
class _EtDateCard extends StatelessWidget {
  const _EtDateCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final et = Map<String, dynamic>.from(data['ethiopian'] as Map);
    final events = [for (final e in (data['events'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    final next = data['next_holiday'] is Map ? Map<String, dynamic>.from(data['next_holiday'] as Map) : null;
    final g = DateTime.tryParse('${data['gregorian']}');
    final year = (et['year'] as num).toInt();
    final month = (et['month'] as num).toInt();
    final day = (et['day'] as num).toInt();
    return _Card(
      children: [
        InkWell(
          onTap: () => _openMonth(context, year, month),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(Radii.l)),
                  child: Column(
                    children: [
                      Text('${et['month_amharic']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.bg)),
                      Text('$day', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.bg, height: 1.1)),
                      Text(geez(day), style: TextStyle(fontSize: 12, color: AppColors.bg.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${et['amharic']}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
                      Text('${data['weekday']}, ${et['english']}', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                      const SizedBox(height: 2),
                      Text(
                        [if (g != null) 'Gregorian ${_fmtG(g)}', if (data['ethiopian_time'] != null) '🕒 ${data['ethiopian_time']}'].join('  ·  '),
                        style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill('${data['year_of_amharic'] ?? data['year_of']}', icon: Icons.menu_book_outlined),
              _Pill('Day ${data['day_of_year']} of the year'),
              if (data['leap_year'] == true) const _Pill('Leap year · Pagume 6'),
              for (final e in events) _Pill('${e['amharic'] ?? e['name']}', icon: e['kind'] == 'fast' ? Icons.no_food_outlined : Icons.celebration_outlined, filled: e['kind'] == 'public'),
              if (data['weekly_fast'] == true && events.every((e) => e['kind'] != 'fast')) const _Pill('Wednesday/Friday fast', icon: Icons.no_food_outlined),
              if (data['days_from_today'] is num && data['days_from_today'] != 0)
                _Pill((data['days_from_today'] as num) > 0 ? 'In ${data['days_from_today']} days' : '${-(data['days_from_today'] as num)} days ago', icon: Icons.schedule_rounded),
            ],
          ),
        ),
        if (next != null)
          Container(
            margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            padding: const EdgeInsets.all(Space.s + 2),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: AppColors.text2),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next: ${next['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${next['amharic']} · ${next['ethiopian']} · ${next['gregorian']}${next['approximate'] == true ? ' (about)' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
                _Countdown(days: (next['days_until'] as num?)?.toInt() ?? 0),
              ],
            ),
          ),
        _Footer(children: [const Spacer(), _button(Icons.calendar_month_outlined, 'Month', () => _openMonth(context, year, month))]),
      ],
    );
  }
}

String _fmtG(DateTime d) => '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.day}, ${d.year}';

class _Countdown extends StatelessWidget {
  const _Countdown({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(days <= 0 ? 'Today' : '$days', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
      if (days > 0) Text(days == 1 ? 'day' : 'days', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
    ],
  );
}

void _openMonth(BuildContext context, int year, int month) => showAppSheet<void>(
  context,
  initialSize: 0.8,
  builder: (context, scroll) => SingleChildScrollView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.x4),
    child: _EtMonth(year: year, month: month),
  ),
);

class _EtMonthCard extends StatelessWidget {
  const _EtMonthCard({required this.year, required this.month});
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) => _Card(children: [Padding(padding: const EdgeInsets.all(Space.s), child: _EtMonth(year: year, month: month))]);
}

/// An Ethiopian month you can page through: each day with its Gregorian
/// date, holidays and fasts marked; tap a day for what it is.
class _EtMonth extends StatefulWidget {
  const _EtMonth({required this.year, required this.month});
  final int year;
  final int month;

  @override
  State<_EtMonth> createState() => _EtMonthState();
}

class _EtMonthState extends State<_EtMonth> {
  late int _year = widget.year;
  late int _month = widget.month;

  void _move(int by) => setState(() {
    _month += by;
    if (_month > 13) {
      _month = 1;
      _year++;
    } else if (_month < 1) {
      _month = 13;
      _year--;
    }
  });

  @override
  Widget build(BuildContext context) {
    final events = etEvents(_year);
    final count = EtDate.daysIn(_year, _month);
    final first = EtDate(_year, _month, 1);
    final lead = first.weekdayIndex;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final g1 = first.gregorian, g2 = EtDate(_year, _month, count).gregorian;
    final monthEvents = events.where((e) => e.kind != EtEventKind.fast && !e.start.isBefore(g1) && !e.start.isAfter(g2)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Previous month', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Column(
                children: [
                  Text('${etMonths[_month - 1].$2} $_year', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${etMonths[_month - 1].$1} · ${_fmtG(g1)} – ${_fmtG(g2)}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                ],
              ),
            ),
            IconButton(tooltip: 'Next month', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            for (final w in etWeekdays)
              Expanded(child: Center(child: Text(w.characters.take(2).toString(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w700)))),
          ],
        ),
        const SizedBox(height: Space.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.82,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= count; d++)
              () {
                final g = EtDate(_year, _month, d).gregorian;
                final on = events.where((e) => e.covers(g)).toList();
                final public = on.any((e) => e.kind == EtEventKind.public);
                final holiday = on.any((e) => e.kind != EtEventKind.fast);
                final fast = on.any((e) => e.kind == EtEventKind.fast) || weeklyFast(g);
                final isToday = g == today;
                return InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: () => _dayDetails(context, EtDate(_year, _month, d), on),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.text : (public ? AppColors.surface3 : Colors.transparent),
                      borderRadius: BorderRadius.circular(Radii.m),
                      border: Border.all(color: holiday && !isToday ? AppColors.text2 : Colors.transparent),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$d', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isToday ? AppColors.bg : AppColors.text)),
                        Text('${g.day}', style: TextStyle(fontSize: 9.5, color: isToday ? AppColors.bg.withValues(alpha: 0.7) : AppColors.text3)),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (holiday) _dot(isToday ? AppColors.bg : AppColors.text),
                            if (fast) _dot(isToday ? AppColors.bg.withValues(alpha: 0.6) : AppColors.text3, hollow: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.xs),
          child: Row(
            children: [
              _dot(AppColors.text),
              const SizedBox(width: 4),
              Text('Holiday', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              const SizedBox(width: Space.m),
              _dot(AppColors.text3, hollow: true),
              const SizedBox(width: 4),
              Text('Fast', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              const Spacer(),
              Text(EtDate.evangelistOf(_year), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
        for (final e in monthEvents)
          InkWell(
            onTap: () => _dayDetails(context, EtDate.fromGregorian(e.start), [e]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 30, child: Text('${EtDate.fromGregorian(e.start).day}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                        Text('${e.amharic} · ${_fmtG(e.start)}${e.approximate ? ' (about)' : ''}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                      ],
                    ),
                  ),
                  if (e.kind == EtEventKind.public) const _Pill('Public holiday'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static Widget _dot(Color c, {bool hollow = false}) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(shape: BoxShape.circle, color: hollow ? Colors.transparent : c, border: Border.all(color: c, width: 1.2)),
  );
}

void _dayDetails(BuildContext context, EtDate d, List<EtEvent> on) {
  final g = d.gregorian;
  final now = DateTime.now();
  final days = g.difference(DateTime(now.year, now.month, now.day)).inDays;
  _sheet(context, d.amharic, (context) => [
    Text('${enWeekdays[g.weekday - 1]}, ${d.english} · ${_fmtG(g)}', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
    const SizedBox(height: Space.m),
    _rows([
      ('Ethiopian', '${d.monthName} ${d.day}, ${d.year}', true),
      ('Amharic', '${d.monthAmharic} ${d.day} ቀን ${d.year} ዓ.ም.', true),
      ('Ge\'ez numerals', '${geez(d.day)} ${d.monthAmharic} ${geez(d.year)}', true),
      ('Gregorian', g.toIso8601String().substring(0, 10), true),
      ('Weekday', '${d.weekdayAmharic} · ${enWeekdays[g.weekday - 1]}', false),
      ('Year of', '${EtDate.evangelistOf(d.year)} · ዘመነ ${EtDate.evangelistAmharic(d.year)}', false),
      ('Day of year', '${d.dayOfYear}', false),
      ('From today', days == 0 ? 'Today' : (days > 0 ? 'In $days days' : '${-days} days ago'), false),
    ]),
    if (on.isNotEmpty || weeklyFast(g)) ...[
      const SizedBox(height: Space.l),
      Text('ON THIS DAY', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8)),
      const SizedBox(height: Space.s),
      for (final e in on)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(e.kind == EtEventKind.fast ? Icons.no_food_outlined : Icons.celebration_outlined),
          title: Text(e.name),
          subtitle: Text([
            e.amharic,
            e.kind == EtEventKind.public ? 'Public holiday' : (e.kind == EtEventKind.fast ? 'Fast, ${e.days} days until ${_fmtG(e.end!)}' : (e.kind == EtEventKind.religious ? 'Religious day' : 'Observance')),
            if (e.approximate) 'Date follows the moon',
          ].join(' · ')),
        ),
      if (weeklyFast(g) && on.every((e) => e.kind != EtEventKind.fast))
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.no_food_outlined), title: Text('Wednesday/Friday fast'), subtitle: Text('Orthodox weekly fast day')),
    ],
  ], size: 0.65);
}

class _EtHolidaysCard extends StatefulWidget {
  const _EtHolidaysCard({required this.data, required this.events});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> events;

  @override
  State<_EtHolidaysCard> createState() => _EtHolidaysCardState();
}

class _EtHolidaysCardState extends State<_EtHolidaysCard> {
  String _filter = 'all';
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown = widget.events.where((e) => switch (_filter) {
      'public' => e['kind'] == 'public',
      'fast' => e['kind'] == 'fast',
      _ => true,
    }).toList();
    final upcoming = shown.indexWhere((e) => ((e['days_until'] as num?) ?? 0) >= 0 || e['now'] == true);
    final visible = _all ? shown : shown.skip(upcoming < 0 ? 0 : upcoming).take(8).toList();
    return _Card(
      children: [
        _Head(icon: Icons.celebration_outlined, title: 'Ethiopian holidays ${widget.data['year']}', subtitle: '${widget.data['year_of']} · ${widget.data['gregorian_span']}'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          child: Wrap(
            spacing: 6,
            children: [
              for (final (k, l) in const [('all', 'All'), ('public', 'Public holidays'), ('fast', 'Fasts')])
                ChoiceChip(
                  label: Text(l),
                  selected: _filter == k,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = k),
                ),
            ],
          ),
        ),
        for (final e in visible) _HolidayRow(e: e),
        if (!_all && shown.length > visible.length)
          InkWell(
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.all(Space.s + 2),
              child: Center(child: Text('Show the whole year (${shown.length})', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
          child: Text('Muslim holidays follow the moon and may move by a day.', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
        ),
      ],
    );
  }
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({required this.e});
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final days = (e['days_until'] as num?)?.toInt() ?? 0;
    final fast = e['kind'] == 'fast';
    final past = days < 0 && e['now'] != true;
    final g = DateTime.tryParse('${e['gregorian']}');
    return InkWell(
      onTap: g == null ? null : () => _dayDetails(context, EtDate.fromGregorian(g), [for (final x in etEvents(EtDate.fromGregorian(g).year)) if (x.name == e['name'] && x.start == g) x]),
      child: Opacity(
        opacity: past ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: e['kind'] == 'public' ? AppColors.text : AppColors.surface2,
                  borderRadius: BorderRadius.circular(Radii.s + 2),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  children: [
                    Text('${g?.day ?? ''}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: e['kind'] == 'public' ? AppColors.bg : AppColors.text)),
                    Text(g == null ? '' : const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][g.month - 1], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: e['kind'] == 'public' ? AppColors.bg.withValues(alpha: 0.7) : AppColors.text3)),
                  ],
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      [
                        '${e['amharic']}',
                        '${e['ethiopian']}',
                        if (fast) '${e['days']} days',
                        if (e['approximate'] == true) 'about',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              if (e['now'] == true)
                const _Pill('Now', filled: true)
              else if (!past)
                Text(days == 0 ? 'Today' : (days == 1 ? 'Tomorrow' : 'in $days d'), style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- QR codes --------------------------------------------------------------------

IconData _qrIcon(String type) => switch (type) {
  'url' => Icons.link_rounded,
  'wifi' => Icons.wifi_rounded,
  'contact' => Icons.contact_page_outlined,
  'phone' => Icons.call_outlined,
  'sms' => Icons.sms_outlined,
  'email' => Icons.mail_outline_rounded,
  'geo' => Icons.place_outlined,
  _ => Icons.notes_rounded,
};

String _qrType(String type) => switch (type) {
  'url' => 'Link',
  'wifi' => 'Wi-Fi',
  'contact' => 'Contact',
  'phone' => 'Phone number',
  'sms' => 'Text message',
  'email' => 'Email',
  'geo' => 'Place',
  _ => 'Text',
};

/// The fields of a parsed code worth showing, in order.
List<(String, String?, bool)> _qrFields(Map<String, dynamic> p) => switch ('${p['type']}') {
  'wifi' => [('Network', p['ssid'] as String?, true), ('Password', p['password'] as String?, true), ('Security', p['security'] as String?, false), if (p['hidden'] == true) ('Hidden', 'Yes', false)],
  'contact' => [('Name', p['name'] as String?, true), ('Phone', p['phone'] as String?, true), ('Email', p['email'] as String?, true), ('Company', p['organization'] as String?, false), ('Title', p['title'] as String?, false), ('Website', p['url'] as String?, true), ('Address', p['address'] as String?, true)],
  'url' => [('Link', p['url'] as String?, true), ('Site', p['host'] as String?, false)],
  'phone' => [('Number', p['phone'] as String?, true)],
  'sms' => [('To', p['phone'] as String?, true), ('Message', p['text'] as String?, true)],
  'email' => [('To', p['email'] as String?, true), ('Subject', p['subject'] as String?, true), ('Message', p['text'] as String?, true)],
  'geo' => [('Latitude', '${p['latitude']}', true), ('Longitude', '${p['longitude']}', true)],
  _ => [('Text', p['text'] as String?, true)],
};

/// The action that suits a code: open the link, call, text, email, map.
(IconData, String, VoidCallback)? _qrAction(BuildContext context, Map<String, dynamic> p) {
  Future<void> go(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  return switch ('${p['type']}') {
    'url' => (Icons.open_in_new_rounded, 'Open', () => go('${p['url']}')),
    'phone' => (Icons.call_outlined, 'Call', () => go('tel:${p['phone']}')),
    'sms' => (Icons.sms_outlined, 'Text', () => go('sms:${p['phone']}?body=${Uri.encodeComponent('${p['text'] ?? ''}')}')),
    'email' => (Icons.mail_outline_rounded, 'Email', () => go('mailto:${p['email']}')),
    'geo' => (Icons.map_outlined, 'Map', () => go('geo:${p['latitude']},${p['longitude']}')),
    'contact' when p['phone'] != null => (Icons.call_outlined, 'Call', () => go('tel:${p['phone']}')),
    'wifi' when p['password'] != null => (Icons.key_rounded, 'Copy password', () {
      Clipboard.setData(ClipboardData(text: '${p['password']}'));
      showSnack(context, 'Wi-Fi password copied');
    }),
    _ => null,
  };
}

class _QrMadeCard extends StatelessWidget {
  const _QrMadeCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final path = '${data['image_path']}';
    final parsed = data['parsed'] is Map ? Map<String, dynamic>.from(data['parsed'] as Map) : <String, dynamic>{'type': data['kind']};
    final type = '${parsed['type'] ?? data['kind']}';
    final exists = File(path).existsSync();
    void open() => _sheet(context, '${data['label']}', (context) => [
      Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.l)),
          clipBehavior: Clip.antiAlias,
          child: exists ? Image.file(File(path)) : const SizedBox(height: 200),
        ),
      ),
      const SizedBox(height: Space.l),
      _rows([('Kind', _qrType(type), false), ..._qrFields(parsed), ('Holds', '${data['data']}', true)]),
    ], size: 0.85);
    return _Card(
      children: [
        InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Row(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.m)),
                  clipBehavior: Clip.antiAlias,
                  child: exists ? Image.file(File(path), fit: BoxFit.contain) : Icon(Icons.qr_code_2_rounded, size: 60, color: Colors.black.withValues(alpha: 0.3)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Pill(_qrType(type), icon: _qrIcon(type)),
                      const SizedBox(height: 6),
                      Text('${data['label']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        type == 'wifi' ? 'Scan to join ${parsed['ssid']}' : '${_qrFields(parsed).where((f) => f.$2 != null).firstOrNull?.$2 ?? data['data']}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _Footer(
          children: [
            _button(Icons.copy_rounded, 'Copy', () {
              Clipboard.setData(ClipboardData(text: '${data['data']}'));
              showSnack(context, 'Copied what the code holds');
            }),
            const Spacer(),
            _button(Icons.download_rounded, 'Save', !exists
                ? null
                : () async {
                    try {
                      await Gal.putImage(path, album: 'Triangle');
                      if (context.mounted) showSnack(context, 'Saved to the gallery');
                    } catch (e) {
                      if (context.mounted) showSnack(context, 'Couldn\'t save: $e');
                    }
                  }),
            _button(Icons.open_in_full_rounded, 'View', open),
          ],
        ),
      ],
    );
  }
}

class _QrCodesCard extends StatelessWidget {
  const _QrCodesCard({required this.codes, this.file = '', this.scanned = false});
  final List<Map<String, dynamic>> codes;
  final String file;
  final bool scanned;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      _Head(
        icon: scanned ? Icons.qr_code_scanner_rounded : Icons.qr_code_2_rounded,
        title: scanned ? 'Scanned' : (codes.isEmpty ? 'No code found' : '${codes.length} code${codes.length == 1 ? '' : 's'} found'),
        subtitle: scanned ? 'With the camera' : file.split(RegExp(r'[\\/]')).last,
      ),
      if (codes.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: Text('Nothing readable in that picture. A sharper, closer shot helps.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
        ),
      for (final (i, c) in codes.indexed) ...[
        if (i > 0) Divider(height: 1, color: AppColors.line),
        _QrCodeRow(code: c),
      ],
    ],
  );
}

class _QrCodeRow extends StatelessWidget {
  const _QrCodeRow({required this.code});
  final Map<String, dynamic> code;

  @override
  Widget build(BuildContext context) {
    final type = '${code['type'] ?? 'text'}';
    final fields = _qrFields(code).where((f) => f.$2 != null && f.$2!.isNotEmpty && f.$2 != 'null').toList();
    final action = _qrAction(context, code);
    final format = '${code['format'] ?? ''}'.replaceAll('_', ' ');
    void open() => _sheet(context, _qrType(type), (context) => [
      _rows([...fields, ('Format', format, false), ('Raw', '${code['value']}', true)]),
      if (action != null) ...[
        const SizedBox(height: Space.l),
        FilledButton.icon(onPressed: action.$3, icon: Icon(action.$1), label: Text(action.$2)),
      ],
    ], size: 0.6);
    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.s),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(Radii.m)),
              child: Icon(_qrIcon(type), size: 20, color: AppColors.bg),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type == 'wifi' ? '${code['ssid']}' : (fields.firstOrNull?.$2 ?? '${code['value']}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [_qrType(type), if (type == 'wifi' && code['security'] != null) '${code['security']}', if (format.isNotEmpty && format != 'qrCode') format].join(' · '),
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                ],
              ),
            ),
            if (action != null) _button(action.$1, action.$2, action.$3),
          ],
        ),
      ),
    );
  }
}

// ---- SIM cards and connection ---------------------------------------------------------

class _SimCard extends StatefulWidget {
  const _SimCard({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_SimCard> createState() => _SimCardState();
}

class _SimCardState extends State<_SimCard> {
  late Map<String, dynamic> _d = widget.data;
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final d = await Net.snapshot();
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _d['active'] is Map ? Map<String, dynamic>.from(_d['active'] as Map) : null;
    final sims = [for (final s in (_d['sims'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    final wifi = _d['wifi'] is Map ? Map<String, dynamic>.from(_d['wifi'] as Map) : null;
    final transport = '${active?['transport'] ?? 'none'}';
    return _Card(
      children: [
        _Head(
          icon: transport == 'wifi' ? Icons.wifi_rounded : (transport == 'cellular' ? Icons.signal_cellular_alt_rounded : Icons.signal_wifi_off_rounded),
          title: '${active?['label'] ?? 'No connection'}',
          subtitle: [
            if (active?['validated'] == true) 'Internet works' else if (active != null) 'No internet access',
            if (active?['metered'] == true) 'metered',
            if (_d['vpn'] == true) 'VPN on',
          ].join(' · '),
          trailing: IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : _refresh,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.refresh_rounded, size: 18, color: AppColors.text2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (_d['airplane'] == true) const _Pill('Airplane mode', icon: Icons.airplanemode_active_rounded, filled: true),
              if (_d['vpn'] == true) const _Pill('VPN', icon: Icons.vpn_lock_outlined),
              if (_d['hotspot'] == true) const _Pill('Hotspot on', icon: Icons.wifi_tethering_rounded),
              _Pill(_d['wifiEnabled'] == true ? 'Wi-Fi on' : 'Wi-Fi off', icon: Icons.wifi_rounded),
              if (active?['ipv4'] != null) _Pill('${active!['ipv4']}', icon: Icons.lan_outlined),
            ],
          ),
        ),
        for (final s in sims) _SimRow(sim: s),
        if (sims.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text(_d['phonePermission'] == false ? 'Allow the SIM cards permission to see carriers and signal.' : 'No SIM card.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        if (wifi != null) _WifiRow(wifi: wifi),
        _Footer(
          children: [
            const Spacer(),
            _button(Icons.info_outline_rounded, 'Details', () => _sheet(context, 'Connection details', (context) => [
              _rows([
                ('Connection', '${active?['label'] ?? 'None'}', false),
                ('Internet', active?['validated'] == true ? 'Works' : 'Not reached', false),
                ('Metered', active?['metered'] == true ? 'Yes' : 'No', false),
                ('Interface', active?['iface'] as String?, false),
                ('IPv4', active?['ipv4'] as String?, true),
                ('IPv6', active?['ipv6'] as String?, true),
                ('DNS', (active?['dns'] as List?)?.join(', '), true),
                ('Private DNS', active?['privateDns'] as String?, true),
                ('Link down', active?['downKbps'] == null ? null : '${((active!['downKbps'] as num) / 1000).toStringAsFixed(1)} Mbps (estimate)', false),
                ('Link up', active?['upKbps'] == null ? null : '${((active!['upKbps'] as num) / 1000).toStringAsFixed(1)} Mbps (estimate)', false),
              ]),
              for (final s in sims) ...[
                const SizedBox(height: Space.l),
                Text('SIM ${(s['slot'] as num? ?? 0) + 1}', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8)),
                const SizedBox(height: Space.s),
                _rows([
                  ('Carrier', s['carrier'] as String?, false),
                  ('Network', s['operator'] as String?, false),
                  ('Type', s['networkType'] as String?, false),
                  ('Signal', s['signalDbm'] == null ? null : '${s['signalDbm']} dBm (${s['signalLevel']}/4)', false),
                  ('Mobile data', s['isDefaultData'] == true ? 'This SIM' : 'Other SIM', false),
                  ('Data enabled', s['dataEnabled'] == null ? null : (s['dataEnabled'] == true ? 'Yes' : 'No'), false),
                  ('Roaming', s['roaming'] == true ? 'Yes' : 'No', false),
                  ('eSIM', s['isEmbedded'] == true ? 'Yes' : 'No', false),
                  ('Country', '${s['countryIso'] ?? ''}'.toUpperCase(), false),
                  ('MCC / MNC', s['mcc'] == null ? null : '${s['mcc']} / ${s['mnc']}', false),
                ]),
              ],
              if (wifi != null) ...[
                const SizedBox(height: Space.l),
                Text('WI-FI', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8)),
                const SizedBox(height: Space.s),
                _rows([
                  ('Network', wifi['ssid'] as String? ?? 'Hidden (allow location to see it)', true),
                  ('Signal', '${wifi['rssi']} dBm', false),
                  ('Band', wifi['band'] as String?, false),
                  ('Channel', wifi['channel']?.toString(), false),
                  ('Standard', wifi['standard'] as String?, false),
                  ('Link speed', wifi['linkSpeed'] == null ? null : '${wifi['linkSpeed']} Mbps', false),
                  ('Router', wifi['bssid'] as String?, true),
                ]),
              ],
            ], size: 0.85)),
          ],
        ),
      ],
    );
  }
}

class _SimRow extends StatelessWidget {
  const _SimRow({required this.sim});
  final Map<String, dynamic> sim;

  @override
  Widget build(BuildContext context) {
    final slot = (sim['slot'] as num? ?? 0).toInt() + 1;
    final data = sim['isDefaultData'] == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
      padding: const EdgeInsets.all(Space.s + 2),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: data ? AppColors.text2 : AppColors.line)),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: data ? AppColors.text : AppColors.surface3,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(4), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(4)),
            ),
            child: Text('$slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: data ? AppColors.bg : AppColors.text)),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sim['carrier'] ?? 'SIM $slot'}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (sim['networkType'] != null) '${sim['networkType']}',
                    if (sim['signalDbm'] != null) '${sim['signalDbm']} dBm',
                    if (sim['roaming'] == true) 'Roaming',
                    if (sim['isEmbedded'] == true) 'eSIM',
                  ].join(' · '),
                  style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                ),
              ],
            ),
          ),
          if (data) const Padding(padding: EdgeInsets.only(right: Space.s), child: _Pill('Data', icon: Icons.swap_vert_rounded)),
          _Bars(level: (sim['signalLevel'] as num?)?.toInt() ?? 0),
        ],
      ),
    );
  }
}

class _WifiRow extends StatelessWidget {
  const _WifiRow({required this.wifi});
  final Map<String, dynamic> wifi;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
    padding: const EdgeInsets.all(Space.s + 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          child: Icon(Icons.wifi_rounded, size: 18, color: AppColors.text),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${wifi['ssid'] ?? 'Wi-Fi'}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                [
                  if (wifi['band'] != null) '${wifi['band']}',
                  if (wifi['standard'] != null) '${wifi['standard']}',
                  if (wifi['linkSpeed'] != null) '${wifi['linkSpeed']} Mbps link',
                  '${wifi['rssi']} dBm',
                ].join(' · '),
                style: context.text.labelSmall?.copyWith(color: AppColors.text3),
              ),
            ],
          ),
        ),
        _Bars(level: (wifi['level'] as num?)?.toInt() ?? 0, max: (wifi['maxLevel'] as num?)?.toInt() ?? 4),
      ],
    ),
  );
}

// ---- speed test -----------------------------------------------------------------------

/// A speed test's live progress, for the running tool card.
class SpeedTestPanel extends StatelessWidget {
  const SpeedTestPanel({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, SpeedProgress>>(
    valueListenable: Net.speed,
    builder: (context, all, _) {
      final p = all[id];
      if (p == null || p.done) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(top: Space.s), child: _Card(children: [_SpeedLive(p: p, onStop: () => Net.cancelSpeedTest(id))]));
    },
  );
}

class _SpeedLive extends StatelessWidget {
  const _SpeedLive({required this.p, this.onStop});
  final SpeedProgress p;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final label = switch (p.phase) {
      'ping' => 'Measuring ping',
      'download' => 'Downloading',
      'upload' => 'Uploading',
      _ => 'Starting',
    };
    final speed = p.phase == 'ping' ? '${p.mbps.toStringAsFixed(0)} ms' : '${p.mbps.toStringAsFixed(p.mbps >= 100 ? 0 : 1)} Mbps';
    return Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(value: p.fraction.clamp(0, 1), strokeWidth: 5, backgroundColor: AppColors.surface3, color: AppColors.text),
                    Center(child: Icon(p.phase == 'upload' ? Icons.arrow_upward_rounded : (p.phase == 'ping' ? Icons.timer_outlined : Icons.arrow_downward_rounded), color: AppColors.text)),
                  ],
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
                    Text(speed, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                    if (p.info['isp'] != null || p.info['server'] != null)
                      Text([if (p.info['isp'] != null) '${p.info['isp']}', if (p.info['server'] != null) '${p.info['server']}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ),
              if (onStop != null) IconButton(tooltip: 'Stop', onPressed: onStop, icon: Icon(Icons.stop_circle_outlined, color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: Space.s),
          Row(
            children: [
              _MiniStat('Ping', p.info['ping_ms'] is num ? '${(p.info['ping_ms'] as num).round()} ms' : '–'),
              _MiniStat('Download', p.info['download_mbps'] is num ? '${(p.info['download_mbps'] as num).toStringAsFixed(1)}' : '–'),
              _MiniStat('Upload', p.info['upload_mbps'] is num ? '${(p.info['upload_mbps'] as num).toStringAsFixed(1)}' : '–'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
        Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
      ],
    ),
  );
}

/// A finished speed test, with "Test again" right in the card.
class _SpeedCard extends StatefulWidget {
  const _SpeedCard({required this.result});
  final Map<String, dynamic> result;

  @override
  State<_SpeedCard> createState() => _SpeedCardState();
}

class _SpeedCardState extends State<_SpeedCard> {
  late Map<String, dynamic> _r = widget.result;
  String? _running;

  Future<void> _again() async {
    final id = 'card-${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _running = id);
    try {
      final r = await Net.speedTest(id, profile: '${_r['profile'] ?? 'light'}');
      if (mounted) setState(() => _r = {...r, 'data_used': formatBytes((r['bytes_used'] as num?) ?? 0)});
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running != null) {
      return ValueListenableBuilder<Map<String, SpeedProgress>>(
        valueListenable: Net.speed,
        builder: (context, all, _) => _Card(children: [_SpeedLive(p: all[_running] ?? const SpeedProgress(), onStop: () => Net.cancelSpeedTest(_running!))]),
      );
    }
    final r = _r;
    final down = (r['download_mbps'] as num?)?.toDouble();
    final up = (r['upload_mbps'] as num?)?.toDouble();
    final ping = (r['ping_ms'] as num?)?.toDouble();
    String grade() {
      final d = down ?? 0;
      if (down == null) return ping == null ? '' : (ping < 40 ? 'Snappy' : (ping < 100 ? 'Fine for most things' : 'Laggy'));
      if (d >= 100) return 'Very fast · 4K, big downloads, video calls';
      if (d >= 25) return 'Fast · HD streaming and video calls';
      if (d >= 8) return 'OK · HD video, calls';
      if (d >= 2) return 'Slow · browsing, music, SD video';
      return 'Very slow · messages and light browsing';
    }

    return _Card(
      children: [
        _Head(
          icon: Icons.speed_rounded,
          title: 'Speed test · ${r['label'] ?? r['transport'] ?? 'this connection'}',
          subtitle: [if (r['isp'] != null) '${r['isp']}', if (r['server'] != null) '${r['server']}'].join(' · '),
        ),
        if (r['error'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text('${r['error']}', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
          child: Row(
            children: [
              Expanded(child: _BigStat(icon: Icons.arrow_downward_rounded, label: 'Download', value: down == null ? '–' : down.toStringAsFixed(down >= 100 ? 0 : 1), unit: 'Mbps')),
              Container(width: 1, height: 52, color: AppColors.line),
              Expanded(child: _BigStat(icon: Icons.arrow_upward_rounded, label: 'Upload', value: up == null ? '–' : up.toStringAsFixed(up >= 100 ? 0 : 1), unit: 'Mbps')),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
          child: Row(
            children: [
              _MiniStat('Ping', ping == null ? '–' : '${ping.round()} ms'),
              _MiniStat('Jitter', r['jitter_ms'] is num ? '${(r['jitter_ms'] as num).toStringAsFixed(1)} ms' : '–'),
              _MiniStat('Loss', r['loss_pct'] is num ? '${(r['loss_pct'] as num).toStringAsFixed(0)}%' : '–'),
              _MiniStat('Data', '${r['data_used'] ?? '–'}'),
            ],
          ),
        ),
        if (grade().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Text(grade(), style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        _Footer(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.s),
              child: Text('${'${r['profile'] ?? ''}'.toUpperCase()}${r['duration_ms'] is num ? ' · ${((r['duration_ms'] as num) / 1000).toStringAsFixed(0)} s' : ''}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ),
            const Spacer(),
            _button(Icons.info_outline_rounded, 'Details', () => _sheet(context, 'Speed test', (context) => [
              _rows([
                ('Connection', '${r['label'] ?? r['transport'] ?? ''}', false),
                ('Download', down == null ? null : '${down.toStringAsFixed(2)} Mbps', false),
                ('Upload', up == null ? null : '${up.toStringAsFixed(2)} Mbps', false),
                ('Ping', ping == null ? null : '${ping.toStringAsFixed(1)} ms', false),
                ('Jitter', r['jitter_ms'] is num ? '${(r['jitter_ms'] as num).toStringAsFixed(2)} ms' : null, false),
                ('Packet loss', r['loss_pct'] is num ? '${(r['loss_pct'] as num).toStringAsFixed(1)}%' : null, false),
                ('Provider', r['isp'] as String?, false),
                ('Server', r['server'] as String?, false),
                ('Your IP', r['client_ip'] as String?, true),
                ('Carrier', r['carrier'] as String?, false),
                ('Network type', r['network_type'] as String?, false),
                ('Wi-Fi', r['ssid'] as String?, false),
                ('Signal', r['signal_dbm'] == null ? null : '${r['signal_dbm']} dBm', false),
                ('Data used', '${r['data_used'] ?? ''}', false),
                ('Profile', '${r['profile'] ?? ''}', false),
                ('Took', r['duration_ms'] is num ? '${((r['duration_ms'] as num) / 1000).toStringAsFixed(1)} s' : null, false),
                ('Tested', r['tested_at'] as String?, false),
              ]),
            ])),
            _button(Icons.replay_rounded, 'Test again', Device.supported ? _again : null),
          ],
        ),
      ],
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.icon, required this.label, required this.value, required this.unit});
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.text3),
          const SizedBox(width: 3),
          Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
          const SizedBox(width: 3),
          Text(unit, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
        ],
      ),
    ],
  );
}

// ---- data usage ---------------------------------------------------------------------

class _UsageCard extends StatefulWidget {
  const _UsageCard({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<_UsageCard> {
  late Map<String, dynamic> _d = widget.data;
  late String _period = '${widget.data['period'] ?? 'week'}';
  bool _busy = false;

  /// Asks Android again for another period, right in the card.
  Future<void> _load(String period) async {
    setState(() {
      _period = period;
      _busy = true;
    });
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = switch (period) {
        'today' => today,
        'month' => DateTime(now.year, now.month),
        '30_days' => today.subtract(const Duration(days: 29)),
        _ => today.subtract(const Duration(days: 6)),
      };
      int n(Object? v) => (v as num?)?.toInt() ?? 0;
      if (_d['view'] == 'daily') {
        final rows = await Net.dailyUsage(today.difference(start).inDays + 1);
        final days = [for (final r in rows) {'day': DateTime.fromMillisecondsSinceEpoch(n(r['day'])).toIso8601String().substring(0, 10), 'wifi': n(r['wifiRx']) + n(r['wifiTx']), 'mobile': n(r['mobileRx']) + n(r['mobileTx'])}];
        final wifi = days.fold<int>(0, (t, r) => t + (r['wifi'] as int)), mobile = days.fold<int>(0, (t, r) => t + (r['mobile'] as int));
        if (mounted) setState(() => _d = {..._d, 'period': period, 'days': days, 'wifi': wifi, 'mobile': mobile, 'total': wifi + mobile});
      } else {
        final apps = await Net.appUsage(start, now);
        final mapped = [
          for (final x in apps.take(30))
            {'name': x['name'], 'package': x['package'], 'system': x['system'], 'wifi': n(x['wifiRx']) + n(x['wifiTx']), 'mobile': n(x['mobileRx']) + n(x['mobileTx']), 'download': n(x['wifiRx']) + n(x['mobileRx']), 'upload': n(x['wifiTx']) + n(x['mobileTx']), 'total': n(x['total'])},
        ];
        final wifi = apps.fold<int>(0, (t, x) => t + n(x['wifiRx']) + n(x['wifiTx'])), mobile = apps.fold<int>(0, (t, x) => t + n(x['mobileRx']) + n(x['mobileTx']));
        if (mounted) setState(() => _d = {..._d, 'view': 'apps', 'period': period, 'apps': mapped, 'app_count': apps.length, 'wifi': wifi, 'mobile': mobile, 'total': wifi + mobile});
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = '${_d['view'] ?? 'apps'}';
    final wifi = (_d['wifi'] as num?)?.toInt() ?? 0;
    final mobile = (_d['mobile'] as num?)?.toInt() ?? 0;
    final total = view == 'hotspot' ? ((_d['total'] as num?)?.toInt() ?? 0) : wifi + mobile;
    final apps = [for (final a in (_d['apps'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    final days = [for (final a in (_d['days'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    final top = apps.isEmpty ? 1 : apps.map((a) => (a['total'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b);
    return _Card(
      children: [
        _Head(
          icon: view == 'hotspot' ? Icons.wifi_tethering_rounded : Icons.data_usage_rounded,
          title: view == 'hotspot' ? 'Hotspot data' : 'Data usage',
          subtitle: '${formatBytes(total)} · ${switch (_period) {'today' => 'today', 'month' => 'this month', '30_days' => 'last 30 days', _ => 'last 7 days'}}',
          trailing: _busy ? const Padding(padding: EdgeInsets.all(Space.s), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
        ),
        if (view != 'hotspot')
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (k, l) in const [('today', 'Today'), ('week', '7 days'), ('month', 'This month'), ('30_days', '30 days')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(l), selected: _period == k, visualDensity: VisualDensity.compact, onSelected: _busy || !Device.supported ? null : (_) => _load(k)),
                    ),
                ],
              ),
            ),
          ),
        if (view != 'hotspot')
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        if (wifi > 0) Expanded(flex: wifi, child: Container(color: AppColors.text)),
                        if (mobile > 0) Expanded(flex: mobile, child: Container(color: AppColors.text3)),
                        if (wifi + mobile == 0) Expanded(child: Container(color: AppColors.surface3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _legend(context, AppColors.text, 'Wi-Fi ${formatBytes(wifi)}'),
                    const SizedBox(width: Space.m),
                    _legend(context, AppColors.text3, 'Mobile ${formatBytes(mobile)}'),
                  ],
                ),
              ],
            ),
          ),
        if (view == 'apps')
          for (final a in apps.take(8))
            _UsageAppRow(app: a, top: top),
        if (view == 'apps' && apps.length > 8)
          InkWell(
            onTap: () => _sheet(context, 'Data by app', (context) => [for (final a in apps) _UsageAppRow(app: a, top: top)], size: 0.9),
            child: Padding(
              padding: const EdgeInsets.all(Space.s + 2),
              child: Center(child: Text('All ${_d['app_count'] ?? apps.length} apps', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            ),
          ),
        if (view != 'apps' && days.isNotEmpty) _DayBars(days: days, hotspot: view == 'hotspot'),
        const SizedBox(height: Space.s),
      ],
    );
  }

  static Widget _legend(BuildContext context, Color c, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(text, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
    ],
  );
}

class _UsageAppRow extends StatelessWidget {
  const _UsageAppRow({required this.app, required this.top});
  final Map<String, dynamic> app;
  final int top;

  @override
  Widget build(BuildContext context) {
    final total = (app['total'] as num?)?.toInt() ?? 0;
    final wifi = (app['wifi'] as num?)?.toInt() ?? 0;
    final mobile = (app['mobile'] as num?)?.toInt() ?? 0;
    final name = '${app['name'] ?? app['package'] ?? 'App'}';
    return InkWell(
      onTap: () => _sheet(context, name, (context) => [
        Row(children: [_AppIcon(package: app['package'] as String?, name: name, size: 48), const SizedBox(width: Space.m), Expanded(child: Text(formatBytes(total), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)))]),
        const SizedBox(height: Space.l),
        _rows([
          ('Wi-Fi', formatBytes(wifi), false),
          ('Mobile data', formatBytes(mobile), false),
          ('Downloaded', formatBytes((app['download'] as num?) ?? 0), false),
          ('Uploaded', formatBytes((app['upload'] as num?) ?? 0), false),
          ('Package', app['package'] as String?, true),
          if (app['system'] == true) ('Kind', 'System app', false),
        ]),
      ], size: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
        child: Row(
          children: [
            _AppIcon(package: app['package'] as String?, name: name),
            const SizedBox(width: Space.s + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
                      Text(formatBytes(total), style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Row(
                        children: [
                          if (wifi > 0) Expanded(flex: (wifi * 1000 / (top == 0 ? 1 : top)).ceil(), child: Container(color: AppColors.text)),
                          if (mobile > 0) Expanded(flex: (mobile * 1000 / (top == 0 ? 1 : top)).ceil(), child: Container(color: AppColors.text3)),
                          if (top > total) Expanded(flex: ((top - total) * 1000 / top).ceil().clamp(1, 1000), child: Container(color: AppColors.surface2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBars extends StatelessWidget {
  const _DayBars({required this.days, required this.hotspot});
  final List<Map<String, dynamic>> days;
  final bool hotspot;

  @override
  Widget build(BuildContext context) {
    int a(Map<String, dynamic> d) => ((hotspot ? d['received'] : d['wifi']) as num?)?.toInt() ?? 0;
    int b(Map<String, dynamic> d) => ((hotspot ? d['sent'] : d['mobile']) as num?)?.toInt() ?? 0;
    final top = days.map((d) => a(d) + b(d)).fold<int>(1, (m, v) => v > m ? v : m);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Tooltip(
                  message: '${d['day']}: ${formatBytes(a(d) + b(d))}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(height: 92 * b(d) / top, decoration: BoxDecoration(color: AppColors.text3, borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
                        Container(height: 92 * a(d) / top, color: AppColors.text),
                        const SizedBox(height: 4),
                        Text(days.length > 10 ? '${DateTime.tryParse('${d['day']}')?.day ?? ''}' : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][(DateTime.tryParse('${d['day']}')?.weekday ?? 1) - 1], style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 9.5)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- notifications --------------------------------------------------------------------

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final items = [for (final x in (data['notifications'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final apps = [for (final x in (data['apps'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final hours = (data['since_hours'] as num?)?.toDouble() ?? 24;
    final byApp = <String, List<Map<String, dynamic>>>{};
    for (final x in items) {
      byApp.putIfAbsent('${x['package']}', () => []).add(x);
    }
    return _Card(
      children: [
        _Head(
          icon: Icons.notifications_none_rounded,
          title: '${data['total'] ?? items.length} notification${(data['total'] ?? items.length) == 1 ? '' : 's'}',
          subtitle: 'Last ${hours >= 1 ? '${hours.round()} h' : '${(hours * 60).round()} min'} · ${apps.length} app${apps.length == 1 ? '' : 's'}',
        ),
        if (apps.isNotEmpty)
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              children: [
                for (final a in apps)
                  GestureDetector(
                    onTap: () => _appSheet(context, '${a['app']}', '${a['package']}', byApp['${a['package']}'] ?? const []),
                    child: Container(
                      width: 60,
                      margin: const EdgeInsets.only(right: Space.s),
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _AppIcon(package: '${a['package']}', name: '${a['app']}', size: 40),
                              Positioned(
                                right: -6,
                                top: -5,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 18),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.surface, width: 1.5)),
                                  child: Text('${a['count']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.bg)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${a['app']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontSize: 10.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Text('${data['note'] ?? 'Nothing new.'}', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        for (final (i, x) in items.take(6).indexed) ...[
          Divider(height: 1, indent: i == 0 ? 0 : Space.m + 44, color: AppColors.line),
          _NotificationRow(n: x, onTap: () => _appSheet(context, '${x['app']}', '${x['package']}', byApp['${x['package']}'] ?? [x])),
        ],
        if (items.length > 6)
          InkWell(
            onTap: () => _allSheet(context, items),
            child: Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.all(Space.s + 2),
              child: Center(child: Text('See all ${items.length}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            ),
          ),
      ],
    );
  }

  static void _appSheet(BuildContext context, String app, String package, List<Map<String, dynamic>> items) => showAppSheet<void>(
    context,
    initialSize: 0.8,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            _AppIcon(package: package, name: app, size: 44),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${items.length} notification${items.length == 1 ? '' : 's'} · $package', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.m),
        for (final x in items) _NotificationDetail(n: x),
      ],
    ),
  );

  static void _allSheet(BuildContext context, List<Map<String, dynamic>> items) => showAppSheet<void>(
    context,
    initialSize: 0.9,
    builder: (context, scroll) => ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.x4),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(height: 1, indent: Space.m + 44, color: AppColors.line),
      itemBuilder: (context, i) => _NotificationRow(n: items[i], onTap: null, full: true),
    ),
  );
}

String _ago(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap, this.full = false});
  final Map<String, dynamic> n;
  final VoidCallback? onTap;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final messages = [for (final m in (n['messages'] as List? ?? const [])) if (m is Map) m];
    final text = messages.isNotEmpty ? messages.map((m) => m['sender'] == null ? '${m['text']}' : '${m['sender']}: ${m['text']}').join('\n') : '${n['text'] ?? ''}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppIcon(package: '${n['package']}', name: '${n['app']}', size: 32),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${n['app']}${n['title'] == null ? '' : ' · ${n['title']}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: n['dismissed'] == true ? AppColors.text2 : AppColors.text),
                        ),
                      ),
                      Text(_ago(n['time'] as String?), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                    ],
                  ),
                  if (text.isNotEmpty) Text(text, maxLines: full ? 8 : 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDetail extends StatelessWidget {
  const _NotificationDetail({required this.n});
  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    final messages = [for (final m in (n['messages'] as List? ?? const [])) if (m is Map) m];
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${n['title'] ?? n['app']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text('${'${n['time'] ?? ''}'.replaceFirst('T', ' ')}${n['dismissed'] == true ? ' · dismissed' : ''}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
          if (n['sub'] != null) Text('${n['sub']}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          const SizedBox(height: 4),
          if (messages.isEmpty)
            SelectableText('${n['text'] ?? ''}', style: context.text.bodySmall?.copyWith(height: 1.4))
          else
            for (final m in messages)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (m['sender'] != null) TextSpan(text: '${m['sender']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '${m['text']}'),
                    ],
                  ),
                  style: context.text.bodySmall?.copyWith(height: 1.4),
                ),
              ),
        ],
      ),
    );
  }
}

/// Opens a saved file (a generated QR picture, say).
Future<void> openSaved(String path) => OpenFilex.open(path);
