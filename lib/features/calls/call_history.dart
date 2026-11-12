import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device.dart';
import '../finance/finance_insights.dart' show FinPeriod;

// The phone's call history, analysed: how much time goes to calls, who
// calls and who gets called, when, what gets missed and what was never
// returned. Read from Android's call log (nothing is copied or kept);
// pure functions below so the tools and the screen agree.

/// One call from the phone's log.
@immutable
class CallRecord {
  const CallRecord({required this.number, required this.name, required this.type, required this.at, required this.seconds});

  final String number;

  /// The contact's name, when the number is saved.
  final String? name;

  /// incoming, outgoing, missed, rejected, blocked or other.
  final String type;
  final DateTime at;
  final int seconds;

  bool get missed => type == 'missed' || type == 'rejected';
  bool get answered => (type == 'incoming' || type == 'outgoing') && seconds > 0;

  /// The person: their name, else the number.
  String get who => (name ?? '').trim().isEmpty ? (number.isEmpty ? 'Unknown' : number) : name!.trim();

  /// The number's digits from the end, so +251911… and 0911… match.
  String get key {
    final d = number.replaceAll(RegExp(r'\D'), '');
    return d.isEmpty ? who.toLowerCase() : (d.length > 9 ? d.substring(d.length - 9) : d);
  }

  factory CallRecord.fromMap(Map<String, dynamic> m) => CallRecord(
    number: '${m['number'] ?? ''}',
    name: m['name'] as String?,
    type: '${m['type'] ?? 'other'}',
    at: m['date'] is num ? DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()) : DateTime.tryParse('${m['date']}') ?? DateTime.now(),
    seconds: (m['seconds'] as num?)?.toInt() ?? 0,
  );
}

String _iso(DateTime t) => t.toIso8601String().substring(0, 16);
double _r(double v) => (v * 10).roundToDouble() / 10;
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "1 h 05 min", "4 min", "38 s".
String talkTime(num seconds) {
  final s = seconds.round();
  if (s < 60) return '$s s';
  final m = s ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

Map<String, dynamic> describeCall(CallRecord c) => {
  'who': c.who,
  if (c.name != null && c.name!.trim().isNotEmpty) 'name': c.name,
  if (c.number.isNotEmpty) 'number': c.number,
  'type': c.type,
  'date': _iso(c.at),
  'seconds': c.seconds,
  if (c.seconds > 0) 'duration': talkTime(c.seconds),
};

/// Per person: calls each way, talk time, last call.
List<Map<String, dynamic>> _people(List<CallRecord> calls) {
  final by = <String, List<CallRecord>>{};
  for (final c in calls) {
    by.putIfAbsent(c.key, () => []).add(c);
  }
  return [
    for (final xs in by.values)
      () {
        final named = xs.firstWhere((c) => (c.name ?? '').trim().isNotEmpty, orElse: () => xs.first);
        final secs = xs.fold(0, (s, c) => s + c.seconds);
        return {
          'who': named.who,
          'number': named.number,
          'calls': xs.length,
          'incoming': xs.where((c) => c.type == 'incoming').length,
          'outgoing': xs.where((c) => c.type == 'outgoing').length,
          'missed': xs.where((c) => c.missed).length,
          'seconds': secs,
          'talk_time': talkTime(secs),
          'last': _iso(xs.map((c) => c.at).reduce((a, b) => a.isAfter(b) ? a : b)),
        };
      }(),
  ];
}

/// Missed calls not followed by any call with that number (either way).
List<Map<String, dynamic>> unreturnedMissed(List<CallRecord> all, {int limit = 20}) {
  final newest = <String, DateTime>{};
  for (final c in all) {
    if (c.missed) continue;
    final t = newest[c.key];
    if (t == null || c.at.isAfter(t)) newest[c.key] = c.at;
  }
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final c in [...all]..sort((a, b) => b.at.compareTo(a.at))) {
    if (!c.missed || seen.contains(c.key)) continue;
    final after = newest[c.key];
    if (after != null && after.isAfter(c.at)) continue;
    seen.add(c.key);
    final tries = all.where((x) => x.key == c.key && x.missed && (after == null || x.at.isAfter(after))).length;
    out.add({...describeCall(c), 'missed_times': tries});
    if (out.length >= limit) break;
  }
  return out;
}

/// The whole picture for [period]: counts by type, talk time, answer rate,
/// a series by day/week/month, hours and weekdays, top people by calls
/// and by time, the longest call, missed calls never returned, and the
/// change from the period before.
Map<String, dynamic> callSummary(List<CallRecord> all, FinPeriod period) {
  final calls = all.where((c) => period.contains(c.at)).toList()..sort((a, b) => a.at.compareTo(b.at));
  int count(String t) => calls.where((c) => c.type == t).length;
  final incoming = count('incoming'), outgoing = count('outgoing'), missed = count('missed'), rejected = count('rejected'), blocked = count('blocked');
  final talk = calls.fold(0, (s, c) => s + c.seconds);
  final inSecs = calls.where((c) => c.type == 'incoming').fold(0, (s, c) => s + c.seconds);
  final outSecs = calls.where((c) => c.type == 'outgoing').fold(0, (s, c) => s + c.seconds);
  final answered = calls.where((c) => c.answered).toList();
  final reachedMe = incoming + missed + rejected;
  final start = period.from ?? (calls.isEmpty ? DateTime.now() : DateTime(calls.first.at.year, calls.first.at.month, calls.first.at.day));
  final spanDays = math.max(1, period.to.difference(start).inDays);
  final days = period.from == null ? spanDays : math.max(1, math.min(period.days, DateTime.now().difference(period.from!).inDays + 1));

  final bucket = spanDays <= 45 ? 'day' : (spanDays <= 190 ? 'week' : 'month');
  DateTime bucketOf(DateTime t) => switch (bucket) {
    'day' => DateTime(t.year, t.month, t.day),
    'week' => DateTime(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1)),
    _ => DateTime(t.year, t.month),
  };
  DateTime next(DateTime b) => switch (bucket) {
    'day' => DateTime(b.year, b.month, b.day + 1),
    'week' => DateTime(b.year, b.month, b.day + 7),
    _ => DateTime(b.year, b.month + 1),
  };
  final series = <DateTime, List<int>>{};
  for (var b = bucketOf(start); b.isBefore(period.to) && series.length < 400; b = next(b)) {
    series[b] = [0, 0, 0, 0];
  }
  for (final c in calls) {
    final s = series.putIfAbsent(bucketOf(c.at), () => [0, 0, 0, 0]);
    if (c.type == 'incoming') s[0]++;
    if (c.type == 'outgoing') s[1]++;
    if (c.missed) s[2]++;
    s[3] += c.seconds;
  }
  final keys = series.keys.toList()..sort();

  final hours = List.filled(24, 0);
  final weekdays = List.filled(7, 0);
  for (final c in calls) {
    hours[c.at.hour]++;
    weekdays[c.at.weekday - 1]++;
  }
  final busiestHour = calls.isEmpty ? null : hours.indexOf(hours.reduce(math.max));
  final busiestDay = calls.isEmpty ? null : weekdays.indexOf(weekdays.reduce(math.max));

  final people = _people(calls);
  final byCalls = [...people]..sort((a, b) => (b['calls'] as int).compareTo(a['calls'] as int));
  final byTime = [...people]..sort((a, b) => (b['seconds'] as int).compareTo(a['seconds'] as int));
  final longest = answered.isEmpty ? null : answered.reduce((a, b) => a.seconds >= b.seconds ? a : b);

  Map<String, dynamic>? before;
  final prev = period.previous;
  if (prev != null) {
    final p = all.where((c) => prev.contains(c.at)).toList();
    final pTalk = p.fold(0, (s, c) => s + c.seconds);
    final pMissed = p.where((c) => c.missed).length;
    before = {
      'label': prev.label,
      'calls': p.length,
      'seconds': pTalk,
      'missed': pMissed,
      if (p.isNotEmpty) 'calls_change_pct': _r((calls.length - p.length) / p.length * 100),
      if (pTalk > 0) 'talk_change_pct': _r((talk - pTalk) / pTalk * 100),
    };
  }

  return {
    'period': period.toJson(),
    'calls': calls.length,
    'incoming': incoming,
    'outgoing': outgoing,
    'missed': missed,
    'rejected': rejected,
    'blocked': blocked,
    'talk_seconds': talk,
    'talk_time': talkTime(talk),
    'incoming_seconds': inSecs,
    'outgoing_seconds': outSecs,
    'avg_call_seconds': answered.isEmpty ? 0 : (talk / answered.length).round(),
    'calls_per_day': _r(calls.length / days),
    'talk_per_day_seconds': (talk / days).round(),
    // Of the calls that reached the phone, how many were picked up.
    'answer_rate': reachedMe == 0 ? null : _r(incoming / reachedMe * 100),
    'people': people.length,
    'series': {
      'bucket': bucket,
      'points': [
        for (final k in keys)
          {
            'label': bucket == 'month' ? '${_shortMonths[k.month - 1]}${k.year == DateTime.now().year ? '' : ' ${k.year % 100}'}' : '${k.day} ${_shortMonths[k.month - 1]}',
            'start': k.toIso8601String().substring(0, 10),
            'incoming': series[k]![0],
            'outgoing': series[k]![1],
            'missed': series[k]![2],
            'seconds': series[k]![3],
          },
      ],
    },
    'hours': hours,
    'weekdays': weekdays,
    'busiest_hour': ?busiestHour,
    'busiest_day': busiestDay == null ? null : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][busiestDay],
    'top_by_calls': byCalls.take(10).toList(),
    'top_by_time': byTime.where((p) => (p['seconds'] as int) > 0).take(10).toList(),
    'longest': longest == null ? null : describeCall(longest),
    'unreturned_missed': unreturnedMissed(all.where((c) => period.contains(c.at)).toList(), limit: 10),
    'previous': ?before,
  };
}

/// One person's history with the user: [match] is a name or number.
Map<String, dynamic>? personStats(List<CallRecord> all, String match) {
  final q = match.trim().toLowerCase();
  final digits = q.replaceAll(RegExp(r'\D'), '');
  bool hit(CallRecord c) =>
      (digits.length >= 4 && c.key.endsWith(digits.length > 9 ? digits.substring(digits.length - 9) : digits)) ||
      (q.isNotEmpty && c.who.toLowerCase().contains(q));
  final calls = all.where(hit).toList()..sort((a, b) => b.at.compareTo(a.at));
  if (calls.isEmpty) return null;
  // The most common person among the matches.
  final keys = <String, int>{};
  for (final c in calls) {
    keys[c.key] = (keys[c.key] ?? 0) + 1;
  }
  final key = keys.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final mine = calls.where((c) => c.key == key).toList();
  final p = _people(mine).single;
  final answered = mine.where((c) => c.answered).toList();
  final months = <String, List<int>>{};
  for (final c in mine) {
    final k = '${c.at.year}-${c.at.month.toString().padLeft(2, '0')}';
    final m = months.putIfAbsent(k, () => [0, 0]);
    m[0]++;
    m[1] += c.seconds;
  }
  final mk = (months.keys.toList()..sort()).reversed.take(12).toList().reversed;
  final hours = List.filled(24, 0);
  for (final c in mine) {
    hours[c.at.hour]++;
  }
  return {
    ...p,
    'first': _iso(mine.last.at),
    'avg_call_seconds': answered.isEmpty ? 0 : (p['seconds'] as int) ~/ answered.length,
    'longest': answered.isEmpty ? null : describeCall(answered.reduce((a, b) => a.seconds >= b.seconds ? a : b)),
    // Who usually calls whom.
    'you_call_share': (p['calls'] as int) == 0 ? 0 : _r((p['outgoing'] as int) / (p['calls'] as int) * 100),
    'monthly': [for (final k in mk) {'month': k, 'label': '${_shortMonths[int.parse(k.substring(5)) - 1]} ${k.substring(2, 4)}', 'calls': months[k]![0], 'seconds': months[k]![1]}],
    'hours': hours,
    'recent': [for (final c in mine.take(15)) describeCall(c)],
    'unreturned': unreturnedMissed(mine, limit: 1).isNotEmpty,
  };
}

/// Reads the call log; kept a minute so a screen and tools don't re-read it
/// for every view.
class CallHistory {
  CallHistory._();
  static final instance = CallHistory._();

  List<CallRecord>? _cache;
  DateTime? _at;

  Future<List<CallRecord>> load({bool fresh = false, int max = 20000}) async {
    final at = _at;
    if (!fresh && _cache != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 1)) return _cache!;
    final rows = Device.list(await Device.call<List>('callLog', {'limit': max, 'bulk': true}));
    _cache = [for (final r in rows) CallRecord.fromMap(r)]..sort((a, b) => b.at.compareTo(a.at));
    _at = DateTime.now();
    return _cache!;
  }
}

/// The call log for the screen, read once and refreshed on demand.
final callHistoryProvider = FutureProvider<List<CallRecord>>((ref) => CallHistory.instance.load());
