import '../device/device.dart';
import '../finance/finance_insights.dart' show FinPeriod;
import '../telegram/data/telegram_tools.dart' show ToolOutput;
import 'call_history.dart';

// Runs the call history tools (telegram_call_history_tools.dart). Each
// returns only what its view is about, so the card and the answer match
// the question.

Future<ToolOutput> runCallHistoryTool(String name, Map<String, dynamic> a) async {
  String str(String k) => '${a[k] ?? ''}'.trim();
  if (!Device.supported) return const ToolOutput({'error': 'Call history is on Android only.'});
  try {
    final all = await CallHistory.instance.load();
    if (all.isEmpty) return const ToolOutput({'note': 'The call log is empty.', 'calls': 0});
    switch (name) {
      case 'call_history_summary':
        final view = str('view').isEmpty ? 'overview' : str('view');
        final p = FinPeriod.resolve(str('period').isEmpty ? 'last_30_days' : str('period'), since: str('since'), until: str('until'));
        final s = callSummary(all, p);
        const core = ['period', 'calls', 'incoming', 'outgoing', 'missed', 'talk_time', 'talk_seconds'];
        final keys = switch (view) {
          'overview' => ['rejected', 'blocked', 'answer_rate', 'calls_per_day', 'talk_per_day_seconds', 'incoming_seconds', 'outgoing_seconds', 'series', 'previous', 'people'],
          'missed' => ['rejected', 'blocked', 'answer_rate', 'unreturned_missed', 'series'],
          'people' => ['people', 'top_by_calls', 'top_by_time'],
          'patterns' => ['hours', 'weekdays', 'busiest_hour', 'busiest_day', 'avg_call_seconds', 'longest', 'calls_per_day'],
          _ => null,
        };
        return ToolOutput({
          'view': view,
          if (keys == null) ...s else ...{for (final k in [...core, ...keys]) if (s.containsKey(k)) k: s[k]},
        });

      case 'call_history_person':
        final who = str('who');
        if (who.isEmpty) return const ToolOutput({'error': 'Who? Give a name or number.'});
        final p = personStats(all, who);
        return ToolOutput(p ?? {'error': 'No calls with "$who" in the log.'});

      case 'call_history_calls':
        final type = str('type');
        final who = str('who').toLowerCase();
        final digits = who.replaceAll(RegExp(r'\D'), '');
        final minSecs = ((a['min_minutes'] as num?)?.toDouble() ?? 0) * 60;
        final p = FinPeriod.resolve(str('period').isEmpty ? 'all' : str('period'), since: str('since'), until: str('until'));
        final list = all.where((c) {
          if (type.isNotEmpty && type != 'all' && c.type != type) return false;
          if (who.isNotEmpty && !(c.who.toLowerCase().contains(who) || (digits.length >= 4 && c.number.replaceAll(RegExp(r'\D'), '').endsWith(digits)))) return false;
          if (c.seconds < minSecs) return false;
          return p.contains(c.at);
        }).toList();
        if (str('sort') == 'longest') list.sort((x, y) => y.seconds.compareTo(x.seconds));
        final limit = ((a['limit'] as num?)?.toInt() ?? 30).clamp(1, 200);
        final secs = list.fold(0, (s, c) => s + c.seconds);
        return ToolOutput({
          'total_matching': list.length,
          'talk_time': talkTime(secs),
          'calls': [for (final c in list.take(limit)) describeCall(c)],
          'filters': {
            'period': p.label,
            if (type.isNotEmpty && type != 'all') 'type': type,
            if (who.isNotEmpty) 'who': str('who'),
            if (minSecs > 0) 'min_minutes': a['min_minutes'],
            if (str('sort') == 'longest') 'sort': 'longest',
          },
        });
    }
    return ToolOutput({'error': 'Unknown call history tool $name'});
  } on DeviceException catch (e) {
    return ToolOutput({'error': e.message});
  }
}
