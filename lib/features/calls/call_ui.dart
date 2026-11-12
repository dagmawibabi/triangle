import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/net_image.dart';
import '../finance/ui/finance_ui.dart' show Caption, FinCard, PillTabs, ThickBar, dayLabel, numOf, listOf, mapOf, CardTitle;
import 'call_history.dart';

// The call history look, shared by its page and the chat cards.

const callIncoming = Color(0xFF60A5FA);
const callOutgoing = Color(0xFF34D399);
const callMissed = Color(0xFFFF8473);

Color callTypeColor(String? type) => switch (type) {
  'incoming' => callIncoming,
  'outgoing' => callOutgoing,
  'missed' || 'rejected' => callMissed,
  _ => const Color(0xFF8B8B95),
};

IconData callTypeIcon(String? type) => switch (type) {
  'incoming' => Icons.call_received_rounded,
  'outgoing' => Icons.call_made_rounded,
  'missed' => Icons.call_missed_rounded,
  'rejected' => Icons.call_end_rounded,
  'blocked' => Icons.block_rounded,
  _ => Icons.call_rounded,
};

String callTypeLabel(String? type) => switch (type) {
  'incoming' => 'Incoming',
  'outgoing' => 'Outgoing',
  'missed' => 'Missed',
  'rejected' => 'Declined',
  'blocked' => 'Blocked',
  _ => 'Call',
};

Color _avatarColor(String who) => HSLColor.fromAHSL(1, (who.hashCode % 360).abs().toDouble(), 0.45, 0.45).toColor();

/// A person's initial on their colour.
class CallAvatar extends StatelessWidget {
  const CallAvatar({super.key, required this.who, this.size = 40, this.badge});
  final String who;
  final double size;

  /// A call type shown as a small badge at the corner.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final letter = RegExp(r'[A-Za-zሀ-፿]').firstMatch(who)?.group(0)?.toUpperCase() ?? '#';
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: _avatarColor(who).withValues(alpha: 0.85),
            child: Text(letter, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                child: Icon(callTypeIcon(badge), size: size * 0.32, color: callTypeColor(badge)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Incoming, outgoing and missed as three figures and one split bar.
class CallTypeSplit extends StatelessWidget {
  const CallTypeSplit({super.key, required this.incoming, required this.outgoing, required this.missed});
  final int incoming;
  final int outgoing;
  final int missed;

  @override
  Widget build(BuildContext context) {
    final total = incoming + outgoing + missed;
    Widget stat(String label, int n, Color c, IconData icon) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: c),
              const SizedBox(width: 4),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.text2))),
            ],
          ),
          const SizedBox(height: 4),
          Text('$n', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
        ],
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            stat('Incoming', incoming, callIncoming, Icons.call_received_rounded),
            stat('Outgoing', outgoing, callOutgoing, Icons.call_made_rounded),
            stat('Missed', missed, callMissed, Icons.call_missed_rounded),
          ],
        ),
        const SizedBox(height: Space.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? Container(color: AppColors.surface3)
                : Row(
                    children: [
                      for (final (n, c) in [(incoming, callIncoming), (outgoing, callOutgoing), (missed, callMissed)])
                        if (n > 0) Expanded(flex: n, child: Container(margin: const EdgeInsets.only(right: 2), color: c)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Calls per bucket stacked by type; press a bar to read it.
class CallStackBars extends StatefulWidget {
  const CallStackBars({super.key, required this.points, this.height = 140, this.minutes = false});

  /// [{label, incoming, outgoing, missed, seconds}].
  final List<Map<String, dynamic>> points;
  final double height;

  /// Talk time instead of counts.
  final bool minutes;

  @override
  State<CallStackBars> createState() => _CallStackBarsState();
}

class _CallStackBarsState extends State<CallStackBars> {
  int? _at;

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.isEmpty) return SizedBox(height: widget.height);
    final sel = _at == null ? null : pts[_at!];
    final label = context.text.labelSmall!.copyWith(color: AppColors.text3, fontSize: 10);
    void pick(Offset p, double w) {
      final i = (p.dx / w * pts.length).floor().clamp(0, pts.length - 1);
      if (i != _at) setState(() => _at = i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: sel == null
              ? Row(
                  children: [
                    if (!widget.minutes) ...[
                      for (final (t, c) in [('In', callIncoming), ('Out', callOutgoing), ('Missed', callMissed)]) ...[
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 4),
                        Text(t, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                        const SizedBox(width: Space.m),
                      ],
                    ] else
                      Text('Minutes on the phone', style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                  ],
                )
              : Row(
                  children: [
                    Text('${sel['label']}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (widget.minutes)
                      Text(talkTime(numOf(sel['seconds'])), style: context.text.labelMedium)
                    else ...[
                      Text('${sel['incoming']} in', style: context.text.labelMedium?.copyWith(color: callIncoming)),
                      const SizedBox(width: Space.s),
                      Text('${sel['outgoing']} out', style: context.text.labelMedium?.copyWith(color: callOutgoing)),
                      const SizedBox(width: Space.s),
                      Text('${sel['missed']} missed', style: context.text.labelMedium?.copyWith(color: callMissed)),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: Space.xs),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            onTapDown: (d) => pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => pick(d.localPosition, c.maxWidth),
            child: CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _StackPainter(points: pts, at: _at, minutes: widget.minutes, label: label, track: AppColors.surface2, grid: AppColors.line),
            ),
          ),
        ),
      ],
    );
  }
}

class _StackPainter extends CustomPainter {
  _StackPainter({required this.points, required this.at, required this.minutes, required this.label, required this.track, required this.grid});
  final List<Map<String, dynamic>> points;
  final int? at;
  final bool minutes;
  final TextStyle label;
  final Color track;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    final h = size.height - bottom;
    final n = points.length;
    double total(Map p) => minutes ? numOf(p['seconds']) / 60 : numOf(p['incoming']) + numOf(p['outgoing']) + numOf(p['missed']);
    final hi = points.map(total).fold(0.0, math.max);
    final top = hi <= 0 ? 1.0 : hi * 1.08;
    final slot = size.width / n;
    final w = math.min(22.0, math.max(2.0, slot * 0.62));
    canvas.drawLine(Offset(0, h + 0.5), Offset(size.width, h + 0.5), Paint()..color = grid);
    for (var i = 0; i < n; i++) {
      final x = slot * i + slot / 2 - w / 2;
      final r = Radius.circular(math.min(5, w / 2));
      if (n <= 40) canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, 0, w, h), topLeft: r, topRight: r), Paint()..color = track.withValues(alpha: 0.55));
      final dim = at != null && at != i;
      final segs = minutes
          ? [(numOf(points[i]['seconds']) / 60, callIncoming)]
          : [(numOf(points[i]['incoming']), callIncoming), (numOf(points[i]['outgoing']), callOutgoing), (numOf(points[i]['missed']), callMissed)];
      var y = h;
      final total0 = segs.fold(0.0, (s, e) => s + e.$1);
      for (final (j, (v, c)) in segs.indexed) {
        if (v <= 0) continue;
        final bh = v / top * h;
        final isTop = segs.skip(j + 1).every((e) => e.$1 <= 0);
        final rect = Rect.fromLTWH(x, y - bh, w, bh);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: isTop ? r : Radius.zero, topRight: isTop ? r : Radius.zero),
          Paint()..color = c.withValues(alpha: dim ? 0.3 : 1),
        );
        y -= bh;
      }
      if (total0 > 0 && total0 / top * h < 2) canvas.drawRect(Rect.fromLTWH(x, h - 2, w, 2), Paint()..color = callIncoming);
    }
    final every = math.max(1, (n / math.max(1, (size.width / 52).floor())).ceil());
    for (var i = 0; i < n; i += every) {
      final tp = TextPainter(text: TextSpan(text: '${points[i]['label']}', style: label), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset((slot * i + slot / 2 - tp.width / 2).clamp(0.0, size.width - tp.width), h + 5));
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.at != at || old.points != points || old.minutes != minutes;
}

/// The 24 hours of the day as a strip of cells, darker where more calls
/// happen.
class HourStrip extends StatelessWidget {
  const HourStrip({super.key, required this.hours, this.color = callIncoming});
  final List<int> hours;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hi = hours.fold(0, math.max);
    return Column(
      children: [
        Row(
          children: [
            for (var h = 0; h < 24; h++)
              Expanded(
                child: Tooltip(
                  message: '${h.toString().padLeft(2, '0')}:00 · ${hours[h]} calls',
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: hours[h] == 0 ? AppColors.surface2 : color.withValues(alpha: 0.15 + 0.85 * hours[h] / math.max(1, hi)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final t in const ['12a', '6a', '12p', '6p'])
              Expanded(child: Text(t, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 10))),
          ],
        ),
      ],
    );
  }
}

/// Calls on each weekday as short bars.
class WeekdayBars extends StatelessWidget {
  const WeekdayBars({super.key, required this.weekdays});
  final List<int> weekdays;

  @override
  Widget build(BuildContext context) {
    final hi = weekdays.fold(0, math.max);
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${weekdays[d]}', style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 10)),
                  const SizedBox(height: 3),
                  Container(
                    height: math.max(3, 50 * weekdays[d] / math.max(1, hi)),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: weekdays[d] == hi && hi > 0 ? callOutgoing : callOutgoing.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(names[d], style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _time(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  return t == null ? '' : DateFormat('HH:mm').format(t);
}

/// One call: who, its type and time, how long. Opens the call's sheet.
class CallRow extends StatelessWidget {
  const CallRow({super.key, required this.call, this.showDay = false});
  final Map<String, dynamic> call;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final type = '${call['type']}';
    final t = DateTime.tryParse('${call['date']}');
    return InkWell(
      onTap: () => showCallSheet(context, call),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 1),
        child: Row(
          children: [
            CallAvatar(who: '${call['who']}', badge: type, size: 40),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${call['who']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: type == 'missed' || type == 'rejected' ? callMissed : AppColors.text),
                  ),
                  Caption([callTypeLabel(type), if (call['name'] != null && call['number'] != null) '${call['number']}'].join(' · ')),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(showDay && t != null ? dayLabel(t) : _time(call['date']), style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
                if (numOf(call['seconds']) > 0) Caption(talkTime(numOf(call['seconds']))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Calls (newest first) under day headings.
List<Widget> callsByDay(List<Map<String, dynamic>> calls) {
  final out = <Widget>[];
  DateTime? day;
  for (final c in calls) {
    final t = DateTime.tryParse('${c['date']}');
    final d = t == null ? null : DateTime(t.year, t.month, t.day);
    if (d != null && d != day) {
      day = d;
      out.add(
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 2),
            child: Text(dayLabel(d).toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }
    out.add(CallRow(call: c));
  }
  return out;
}

/// A person in a ranking: avatar, name, calls each way and talk time, with
/// a bar for [metric] ("calls" or "seconds").
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.person, required this.max, this.metric = 'calls'});
  final Map<String, dynamic> person;
  final num max;
  final String metric;

  @override
  Widget build(BuildContext context) {
    final p = person;
    return InkWell(
      onTap: () => showPersonSheet(context, '${p['number'] ?? p['who']}', fallbackName: '${p['who']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            CallAvatar(who: '${p['who']}', size: 38),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${p['who']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                      Text(metric == 'seconds' ? '${p['talk_time']}' : '${p['calls']} calls', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ThickBar(value: max == 0 ? 0 : numOf(p[metric]) / max, color: metric == 'seconds' ? callOutgoing : callIncoming, height: 5),
                  const SizedBox(height: 4),
                  Caption('${p['incoming']} in · ${p['outgoing']} out${numOf(p['missed']) > 0 ? ' · ${p['missed']} missed' : ''}${metric == 'seconds' ? '' : ' · ${p['talk_time']}'}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _dial(String? number, {bool sms = false}) async {
  if (number == null || number.isEmpty) return;
  await launchUrl(Uri(scheme: sms ? 'sms' : 'tel', path: number), mode: LaunchMode.externalApplication);
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 6),
            Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
          ],
        ),
      ),
    ),
  );
}

/// One call: the person, what kind of call, when and how long, and ways to
/// call back, text, or see everything with them.
Future<void> showCallSheet(BuildContext context, Map<String, dynamic> call) => showAppSheet<void>(
  context,
  initialSize: 0.55,
  builder: (context, scroll) {
    final type = '${call['type']}';
    final t = DateTime.tryParse('${call['date']}');
    final number = call['number'] as String?;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Center(child: CallAvatar(who: '${call['who']}', size: 72, badge: type)),
        const SizedBox(height: Space.m),
        Text('${call['who']}', textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (call['name'] != null && number != null) Text(number, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        const SizedBox(height: Space.s),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: callTypeColor(type).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(callTypeIcon(type), size: 15, color: callTypeColor(type)),
                const SizedBox(width: 5),
                Text(
                  '${callTypeLabel(type)}${numOf(call['seconds']) > 0 ? ' · ${talkTime(numOf(call['seconds']))}' : ''}',
                  style: context.text.labelMedium?.copyWith(color: callTypeColor(type), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        if (t != null) Text('${DateFormat('EEEE d MMMM y').format(t)} at ${DateFormat('HH:mm').format(t)}', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
        const SizedBox(height: Space.xl),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(
            children: [
              _RoundAction(icon: Icons.call_rounded, label: 'Call back', color: callOutgoing, onTap: number == null ? null : () => _dial(number)),
              _RoundAction(icon: Icons.sms_outlined, label: 'Message', color: callIncoming, onTap: number == null ? null : () => _dial(number, sms: true)),
              _RoundAction(
                icon: Icons.insights_rounded,
                label: 'History',
                color: AppColors.text2,
                onTap: () {
                  Navigator.pop(context);
                  showPersonSheet(context, number ?? '${call['who']}', fallbackName: '${call['who']}');
                },
              ),
            ],
          ),
        ),
      ],
    );
  },
);

/// Everything about calls with one person, read from the log.
Future<void> showPersonSheet(BuildContext context, String who, {String? fallbackName}) => showAppSheet<void>(
  context,
  initialSize: 0.9,
  builder: (context, scroll) => _PersonSheet(who: who, name: fallbackName, scroll: scroll),
);

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.who, required this.scroll, this.name});
  final String who;
  final String? name;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: CallHistory.instance.load().then((all) => personStats(all, who)),
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.all(Space.xl),
          children: const [
            Center(child: Skeleton(width: 72, height: 72, shape: BoxShape.circle)),
            SizedBox(height: Space.l),
            Center(child: Skeleton(width: 160, height: 16, radius: 6)),
            SizedBox(height: Space.xl),
            Skeleton(height: 90, radius: 16),
            SizedBox(height: Space.m),
            Skeleton(height: 140, radius: 16),
          ],
        );
      }
      final p = snap.data;
      if (p == null) {
        return Center(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text('No calls with ${name ?? who} in the log.', style: context.text.bodySmall)));
      }
      return PersonDetail(person: p, scroll: scroll);
    },
  );
}

/// A person's call history laid out: header, quick actions, figures, month
/// by month, hours, and recent calls.
class PersonDetail extends StatelessWidget {
  const PersonDetail({super.key, required this.person, this.scroll});
  final Map<String, dynamic> person;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final number = p['number'] as String?;
    final monthly = listOf(p['monthly']);
    final hours = [for (final h in (p['hours'] as List? ?? const [])) (h as num).toInt()];
    final last = DateTime.tryParse('${p['last']}');
    final first = DateTime.tryParse('${p['first']}');
    final hiMonth = monthly.fold(0.0, (s, m) => math.max(s, numOf(m['calls'])));
    Widget fig(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
          const SizedBox(height: 2),
          Caption(label),
        ],
      ),
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Center(child: CallAvatar(who: '${p['who']}', size: 72)),
        const SizedBox(height: Space.m),
        Text('${p['who']}', textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (number != null && number != p['who']) Text(number, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Last call ${dayLabel(last).toLowerCase()}${first != null ? ' · since ${DateFormat('MMM y').format(first)}' : ''}', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
          ),
        if (p['unreturned'] == true)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: callMissed.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text('You haven\'t returned their last missed call', style: context.text.labelSmall?.copyWith(color: callMissed, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        const SizedBox(height: Space.l),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(
            children: [
              _RoundAction(icon: Icons.call_rounded, label: 'Call', color: callOutgoing, onTap: number == null ? null : () => _dial(number)),
              _RoundAction(icon: Icons.sms_outlined, label: 'Message', color: callIncoming, onTap: number == null ? null : () => _dial(number, sms: true)),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        FinCard(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              Row(children: [fig('calls', '${p['calls']}'), fig('talk time', '${p['talk_time']}'), fig('average', talkTime(numOf(p['avg_call_seconds'])))]),
              const SizedBox(height: Space.l),
              CallTypeSplit(incoming: numOf(p['incoming']).toInt(), outgoing: numOf(p['outgoing']).toInt(), missed: numOf(p['missed']).toInt()),
              const SizedBox(height: Space.m),
              Caption('You start ${numOf(p['you_call_share']).round()}% of your calls together', color: AppColors.text2),
            ],
          ),
        ),
        if (monthly.length >= 2) ...[
          const SizedBox(height: Space.m),
          FinCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CardTitle('Month by month'),
                const SizedBox(height: Space.m),
                SizedBox(
                  height: 90,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final m in monthly)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: math.max(3, 60 * numOf(m['calls']) / math.max(1, hiMonth)),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(color: callIncoming, borderRadius: BorderRadius.circular(4)),
                              ),
                              const SizedBox(height: 4),
                              Text('${m['label']}'.split(' ').first, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 9.5)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hours.length == 24) ...[
          const SizedBox(height: Space.m),
          FinCard(margin: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const CardTitle('When you talk'), const SizedBox(height: Space.m), HourStrip(hours: hours)])),
        ],
        if (p['longest'] is Map) ...[
          const SizedBox(height: Space.m),
          Text('LONGEST CALL', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          CallRow(call: mapOf(p['longest']), showDay: true),
        ],
        const SizedBox(height: Space.m),
        Text('RECENT', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        for (final c in listOf(p['recent'])) CallRow(call: c, showDay: true),
      ],
    );
  }
}

/// The period choices used on the page and the cards.
const callPeriods = [('last_7_days', 'Week'), ('last_30_days', 'Month'), ('last_90_days', '3 months'), ('this_year', 'Year'), ('all', 'All')];

/// Re-exported so pages can build period pickers.
typedef CallPeriodTabs = PillTabs<String>;
