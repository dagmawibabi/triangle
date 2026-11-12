import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../calls/call_history.dart' show talkTime;
import '../../../calls/call_history_screen.dart';
import '../../../calls/call_ui.dart';
import '../../../finance/ui/finance_ui.dart' show Caption, DeltaBadge, RingProgress, listOf, mapOf, numOf;
import '../../domain/chat_models.dart';

/// Cards for the call history tools, one per question: an overview, missed
/// calls, people, patterns, a person, or a list of calls. Calls open their
/// sheet (call back, message, history); people open theirs. Null for other
/// tools.
Widget? callHistoryResultFor(ToolPart part, Map<String, dynamic> j) {
  if (!part.name.startsWith('call_history_') || j['error'] != null) return null;
  return switch (part.name) {
    'call_history_summary' when j['calls'] != null => _SummaryCard(data: j),
    'call_history_person' when j['who'] != null => _PersonCard(p: j),
    'call_history_calls' when j['calls'] is List => _CallsCard(data: j),
    _ => null,
  };
}

void _open(BuildContext context, [int tab = 0]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallHistoryScreen(initialTab: tab)));

class _Frame extends StatelessWidget {
  const _Frame({required this.icon, required this.title, required this.children, this.subtitle, this.tab = 0, this.color});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final int tab;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.m),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: (color ?? callIncoming).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: color ?? callIncoming),
              ),
              const SizedBox(width: Space.s + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null && subtitle!.isNotEmpty) Caption(subtitle!),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text2, padding: const EdgeInsets.symmetric(horizontal: Space.s)),
                onPressed: () => _open(context, tab),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Open'), Icon(Icons.chevron_right_rounded, size: 18)]),
              ),
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _Pad extends StatelessWidget {
  const _Pad(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: child);
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final view = '${data['view'] ?? 'overview'}';
    final period = '${mapOf(data['period'])['label'] ?? ''}';
    final points = listOf(mapOf(data['series'])['points']);
    final prev = mapOf(data['previous']);
    final missedAll = numOf(data['missed']).toInt() + numOf(data['rejected']).toInt();
    Widget hero(String label, String value, {Widget? badge}) => _Pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption(label, color: AppColors.text2),
          const SizedBox(height: 2),
          Row(children: [Flexible(child: Text(value, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5))), if (badge != null) ...[const SizedBox(width: Space.s), badge]]),
        ],
      ),
    );
    final split = _Pad(CallTypeSplit(incoming: numOf(data['incoming']).toInt(), outgoing: numOf(data['outgoing']).toInt(), missed: missedAll));
    switch (view) {
      case 'missed':
        final unreturned = listOf(data['unreturned_missed']);
        final rate = data['answer_rate'];
        return _Frame(
          icon: Icons.call_missed_rounded,
          color: callMissed,
          title: 'Missed calls',
          subtitle: '$period · ${data['calls']} calls',
          tab: 2,
          children: [
            _Pad(
              Row(
                children: [
                  RingProgress(
                    value: rate is num ? rate / 100 : 0,
                    color: rate is num && rate >= 80 ? callOutgoing : (rate is num && rate >= 50 ? AppColors.warning : callMissed),
                    size: 78,
                    stroke: 8,
                    child: Text(rate is num ? '${rate.round()}%' : '—', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$missedAll missed or declined', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Caption('${rate is num ? '${rate.round()}%' : 'None'} of calls to you were answered', color: AppColors.text2),
                        Caption('${unreturned.length} never returned'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (unreturned.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
                child: Text('NOT CALLED BACK', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
              ),
              for (final c in unreturned.take(6)) CallRow(call: c, showDay: true),
              const SizedBox(height: Space.s),
            ] else
              const _Pad(Caption('Every missed call has been returned.')),
          ],
        );
      case 'people':
        final byCalls = listOf(data['top_by_calls']);
        final byTime = listOf(data['top_by_time']);
        final maxCalls = byCalls.isEmpty ? 0 : numOf(byCalls.first['calls']);
        return _Frame(
          icon: Icons.people_alt_rounded,
          title: 'Who you talk to',
          subtitle: '$period · ${data['people']} people',
          tab: 1,
          children: [
            for (final p in byCalls.take(5)) PersonRow(person: p, max: maxCalls),
            if (byTime.isNotEmpty && byTime.first['who'] != (byCalls.isEmpty ? null : byCalls.first['who']))
              _Pad(Caption('Most time on the phone: ${byTime.first['who']} (${byTime.first['talk_time']})', color: AppColors.text2)),
            const SizedBox(height: Space.xs),
          ],
        );
      case 'patterns':
        final hours = [for (final h in (data['hours'] as List? ?? const [])) (h as num).toInt()];
        final weekdays = [for (final h in (data['weekdays'] as List? ?? const [])) (h as num).toInt()];
        return _Frame(
          icon: Icons.schedule_rounded,
          color: callOutgoing,
          title: 'When you call',
          subtitle: [period, if (data['busiest_day'] != null) 'busiest on ${data['busiest_day']}s'].join(' · '),
          children: [
            if (hours.length == 24) _Pad(HourStrip(hours: hours)),
            if (weekdays.length == 7) _Pad(WeekdayBars(weekdays: weekdays)),
            _Pad(Caption('Average call ${talkTime(numOf(data['avg_call_seconds']))} · ${data['calls_per_day']} calls a day', color: AppColors.text2)),
            if (data['longest'] is Map) ...[
              Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0), child: Text('LONGEST CALL', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600))),
              CallRow(call: mapOf(data['longest']), showDay: true),
              const SizedBox(height: Space.s),
            ],
          ],
        );
      case 'overview':
        return _Frame(
          icon: Icons.call_rounded,
          title: 'Your calls',
          subtitle: '$period · ${data['calls']} calls',
          children: [
            hero(
              'On the phone',
              '${data['talk_time']}',
              badge: prev['talk_change_pct'] is num && (prev['talk_change_pct'] as num).abs() <= 500 ? DeltaBadge(pct: (prev['talk_change_pct'] as num).toDouble(), upIsGood: true) : null,
            ),
            split,
            if (points.isNotEmpty) _Pad(CallStackBars(points: points, height: 110)),
            _Pad(
              Caption(
                [
                  if (data['answer_rate'] is num) '${(data['answer_rate'] as num).round()}% answered',
                  '${data['calls_per_day']} calls a day',
                  '${data['people']} people',
                ].join(' · '),
                color: AppColors.text2,
              ),
            ),
          ],
        );
      default:
        // A full report: every section.
        final unreturned = listOf(data['unreturned_missed']);
        final byCalls = listOf(data['top_by_calls']);
        final hours = [for (final h in (data['hours'] as List? ?? const [])) (h as num).toInt()];
        return _Frame(
          icon: Icons.insights_rounded,
          title: 'Call report',
          subtitle: '$period · ${data['calls']} calls',
          children: [
            hero('On the phone', '${data['talk_time']}'),
            split,
            if (points.isNotEmpty) _Pad(CallStackBars(points: points, height: 110)),
            if (hours.length == 24) _Pad(HourStrip(hours: hours)),
            for (final p in byCalls.take(3)) PersonRow(person: p, max: byCalls.isEmpty ? 0 : numOf(byCalls.first['calls'])),
            for (final c in unreturned.take(3)) CallRow(call: c, showDay: true),
            const SizedBox(height: Space.s),
          ],
        );
    }
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) => _Frame(
    icon: Icons.person_rounded,
    title: '${p['who']}',
    subtitle: '${p['calls']} calls · ${p['talk_time']}',
    tab: 1,
    children: [
      InkWell(
        onTap: () => showPersonSheet(context, '${p['number'] ?? p['who']}', fallbackName: '${p['who']}'),
        child: _Pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CallTypeSplit(incoming: numOf(p['incoming']).toInt(), outgoing: numOf(p['outgoing']).toInt(), missed: numOf(p['missed']).toInt()),
              const SizedBox(height: Space.m),
              Caption('You start ${numOf(p['you_call_share']).round()}% of your calls · average ${talkTime(numOf(p['avg_call_seconds']))}', color: AppColors.text2),
              if (p['unreturned'] == true) ...[const SizedBox(height: 4), Caption('Their last missed call hasn\'t been returned', color: callMissed)],
            ],
          ),
        ),
      ),
      for (final c in listOf(p['recent']).take(4)) CallRow(call: c, showDay: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.xs),
        child: TextButton(onPressed: () => showPersonSheet(context, '${p['number'] ?? p['who']}', fallbackName: '${p['who']}'), child: const Text('Full history')),
      ),
    ],
  );
}

class _CallsCard extends StatefulWidget {
  const _CallsCard({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_CallsCard> createState() => _CallsCardState();
}

class _CallsCardState extends State<_CallsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final calls = listOf(widget.data['calls']);
    final f = mapOf(widget.data['filters']);
    final type = f['type'] as String?;
    final shown = _all ? calls : calls.take(8).toList();
    final total = numOf(widget.data['total_matching']).toInt();
    return _Frame(
      icon: callTypeIcon(type),
      color: type == null ? null : callTypeColor(type),
      title: [type == null ? 'Calls' : '${callTypeLabel(type)} calls', if (f['who'] != null) 'with ${f['who']}'].join(' '),
      subtitle: '${f['period'] ?? ''} · $total calls · ${widget.data['talk_time']}',
      tab: 2,
      children: [
        if (calls.isEmpty) const _Pad(Caption('Nothing matches.')),
        ...callsByDay(shown),
        if (calls.length > shown.length)
          TextButton(onPressed: () => setState(() => _all = true), child: Text('Show all ${calls.length}'))
        else
          const SizedBox(height: Space.s),
      ],
    );
  }
}
