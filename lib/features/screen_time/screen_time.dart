import 'package:flutter/services.dart';

import '../device/device.dart';
import '../device/net.dart';

// Screen time from Android's usage stats (ScreenTime.kt): time on screen
// per app, per day and per hour, opens and unlocks, and the trend across
// weeks. Nothing is stored; every call reads Android's own records.

class ScreenTimeAccessException implements Exception {
  const ScreenTimeAccessException();
  @override
  String toString() =>
      'Usage access is off. The user can turn it on for Triangle in Android\'s "Usage access" settings (the same switch as data usage).';
}

const _channel = MethodChannel('teleai/device');

/// Raw days from Android: oldest first, today (or [end]) last.
Future<Map<String, dynamic>> loadScreenTime({int days = 7, DateTime? end}) async {
  if (!Device.supported) throw DeviceException('Screen time is on Android only.');
  try {
    final r = await _channel.invokeMethod<Map>('screenTime', {'days': days, 'end': ?end?.millisecondsSinceEpoch});
    return Device.map(r);
  } on PlatformException catch (e) {
    if (e.code == 'usage_access') throw const ScreenTimeAccessException();
    throw DeviceException(e.message ?? e.code);
  }
}

Future<bool> screenTimeAccess() => Net.usageAccess();
Future<void> openScreenTimeAccess() => Net.openUsageAccess();

/// "2 h 05 min", "14 min", "under a minute".
String screenDuration(num ms) {
  final m = (ms / 60000).round();
  if (m < 1) return ms > 0 ? '<1 min' : '0 min';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

double _min(num ms) => (ms / 60000 * 10).roundToDouble() / 10;
String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Turns [raw] into what the tools and cards show. [view] picks the focus:
/// today (or one day), week (the last 7 days against the 7 before), or
/// app (one app over the span).
Map<String, dynamic> analyzeScreenTime(Map<String, dynamic> raw, {required String view, String? app, int focusDays = 7}) {
  final days = [for (final d in (raw['days'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)];
  final meta = {
    for (final a in (raw['apps'] as List? ?? const []))
      if (a is Map) '${a['package']}': Map<String, dynamic>.from(a),
  };
  String name(String pkg) => '${meta[pkg]?['name'] ?? pkg}';
  DateTime date(Map d) => DateTime.fromMillisecondsSinceEpoch((d['date'] as num).toInt());
  List<Map<String, dynamic>> appsOf(Map d) => [for (final a in (d['apps'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];

  Map<String, dynamic> appRow(String pkg, num ms, {int launches = 0, num? share}) => {
    'name': name(pkg),
    'package': pkg,
    'minutes': _min(ms),
    'time': screenDuration(ms),
    if (launches > 0) 'opens': launches,
    'category': ?meta[pkg]?['category'],
    if (share != null) 'share': share,
    if (meta[pkg]?['last_used'] is num) 'last_used': DateTime.fromMillisecondsSinceEpoch((meta[pkg]!['last_used'] as num).toInt()).toIso8601String().substring(0, 16),
  };

  List<Map<String, dynamic>> totals(List<Map<String, dynamic>> span, {int limit = 15}) {
    final ms = <String, num>{};
    final opens = <String, int>{};
    for (final d in span) {
      for (final a in appsOf(d)) {
        final p = '${a['package']}';
        ms[p] = (ms[p] ?? 0) + (a['ms'] as num);
        opens[p] = (opens[p] ?? 0) + ((a['launches'] as num?)?.toInt() ?? 0);
      }
    }
    final all = ms.values.fold<num>(0, (s, v) => s + v);
    final sorted = ms.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(limit))
        appRow(e.key, e.value, launches: opens[e.key] ?? 0, share: all == 0 ? 0 : (e.value / all * 100).round()),
    ];
  }

  Map<String, num> categories(List<Map<String, dynamic>> span) {
    final out = <String, num>{};
    for (final d in span) {
      for (final a in appsOf(d)) {
        final c = '${meta['${a['package']}']?['category'] ?? 'other'}';
        out[c] = (out[c] ?? 0) + (a['ms'] as num);
      }
    }
    return out;
  }

  num total(Iterable<Map<String, dynamic>> span) => span.fold<num>(0, (s, d) => s + (d['total'] as num? ?? 0));
  Map<String, dynamic> dayRow(Map<String, dynamic> d) => {
    'date': _day(date(d)),
    'weekday': _weekdays[date(d).weekday - 1],
    'minutes': _min(d['total'] as num? ?? 0),
    'time': screenDuration(d['total'] as num? ?? 0),
    'unlocks': d['unlocks'],
    if (d['summary_only'] == true) 'estimated': true,
  };

  final base = <String, dynamic>{
    'view': view,
    if (raw['history_from'] is num) 'detailed_history_since': _day(DateTime.fromMillisecondsSinceEpoch((raw['history_from'] as num).toInt())),
  };

  switch (view) {
    case 'app':
      final want = (app ?? '').toLowerCase().trim();
      final pkg = meta.keys.where((p) => p.toLowerCase() == want || name(p).toLowerCase() == want).firstOrNull ??
          meta.keys.where((p) => name(p).toLowerCase().contains(want) || p.toLowerCase().contains(want)).firstOrNull;
      if (pkg == null) return {...base, 'error': 'No screen time for "$app" in this span.'};
      final series = [
        for (final d in days)
          () {
            final a = appsOf(d).where((x) => x['package'] == pkg).firstOrNull;
            return {
              'date': _day(date(d)),
              'weekday': _weekdays[date(d).weekday - 1],
              'minutes': _min(a?['ms'] as num? ?? 0),
              'opens': (a?['launches'] as num?)?.toInt() ?? 0,
            };
          }(),
      ];
      final ms = series.fold<num>(0, (s, d) => s + (d['minutes'] as num)) * 60000;
      final opens = series.fold<int>(0, (s, d) => s + (d['opens'] as int));
      final used = series.where((d) => (d['minutes'] as num) > 0).length;
      final half = series.length ~/ 2;
      final recent = series.skip(half).fold<num>(0, (s, d) => s + (d['minutes'] as num));
      final before = series.take(half).fold<num>(0, (s, d) => s + (d['minutes'] as num));
      final peak = series.isEmpty ? null : (series.toList()..sort((a, b) => (b['minutes'] as num).compareTo(a['minutes'] as num))).first;
      return {
        ...base,
        ...appRow(pkg, ms, launches: opens),
        'days': series.length,
        'days_used': used,
        'average_per_day': screenDuration(ms / series.length.clamp(1, 999)),
        'average_minutes': _min(ms / series.length.clamp(1, 999)),
        'share_of_screen_time': total(days) == 0 ? 0 : (ms / total(days) * 100).round(),
        if (peak != null) 'busiest_day': peak,
        if (half > 0 && before > 0) 'change_percent': ((recent - before) / before * 100).round(),
        'series': series,
      };

    case 'week':
      final cur = days.length > 7 ? days.sublist(days.length - 7) : days;
      final prev = days.length > 7 ? days.sublist(0, days.length - 7) : <Map<String, dynamic>>[];
      final t = total(cur);
      final p = total(prev);
      final busiest = cur.isEmpty ? null : (cur.toList()..sort((a, b) => (b['total'] as num).compareTo(a['total'] as num))).first;
      final quietest = cur.isEmpty ? null : (cur.toList()..sort((a, b) => (a['total'] as num).compareTo(b['total'] as num))).first;
      final hours = List<num>.filled(24, 0);
      for (final d in cur) {
        final h = d['hours'] as List? ?? const [];
        for (var i = 0; i < 24 && i < h.length; i++) {
          hours[i] += h[i] as num;
        }
      }
      return {
        ...base,
        'from': cur.isEmpty ? null : _day(date(cur.first)),
        'to': cur.isEmpty ? null : _day(date(cur.last)),
        'total': screenDuration(t),
        'total_minutes': _min(t),
        'average_per_day': screenDuration(t / cur.length.clamp(1, 7)),
        'average_minutes': _min(t / cur.length.clamp(1, 7)),
        'unlocks': cur.fold<int>(0, (s, d) => s + ((d['unlocks'] as num?)?.toInt() ?? 0)),
        if (prev.isNotEmpty) 'previous_week_total': screenDuration(p),
        if (prev.isNotEmpty) 'previous_week_minutes': _min(p),
        if (prev.isNotEmpty && p > 0) 'change_percent': ((t - p) / p * 100).round(),
        if (busiest != null) 'busiest_day': dayRow(busiest),
        if (quietest != null) 'quietest_day': dayRow(quietest),
        'daily': [for (final d in cur) dayRow(d)],
        if (prev.isNotEmpty) 'previous_daily': [for (final d in prev) dayRow(d)],
        'hourly_minutes': [for (final h in hours) _min(h / cur.length.clamp(1, 7))],
        'categories': {for (final e in (categories(cur).entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) e.key: _min(e.value)},
        'top_apps': totals(cur),
      };

    default: // today / one day
      final d = days.isEmpty ? null : days.last;
      if (d == null) return {...base, 'error': 'No usage recorded.'};
      final before = days.length > 1 ? days.sublist(0, days.length - 1) : <Map<String, dynamic>>[];
      final avg = before.isEmpty ? null : total(before) / before.length;
      final hours = [for (final h in (d['hours'] as List? ?? const [])) _min(h as num)];
      final peak = hours.isEmpty ? null : hours.indexOf(hours.reduce((a, b) => a > b ? a : b));
      return {
        ...base,
        'date': _day(date(d)),
        'weekday': _weekdays[date(d).weekday - 1],
        'is_today': _day(date(d)) == _day(DateTime.now()),
        'total': screenDuration(d['total'] as num),
        'total_minutes': _min(d['total'] as num),
        'unlocks': d['unlocks'],
        if (d['first_use'] is num) 'first_use': DateTime.fromMillisecondsSinceEpoch((d['first_use'] as num).toInt()).toIso8601String().substring(11, 16),
        if (avg != null) 'average_of_previous_days': screenDuration(avg),
        if (avg != null && avg > 0) 'vs_average_percent': (((d['total'] as num) - avg) / avg * 100).round(),
        'hourly_minutes': hours,
        if (peak != null && hours[peak] > 0) 'busiest_hour': '${peak.toString().padLeft(2, '0')}:00',
        'categories': {for (final e in (categories([d]).entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) e.key: _min(e.value)},
        'top_apps': totals([d]),
        'week': [for (final x in days.length > 7 ? days.sublist(days.length - 7) : days) dayRow(x)],
      };
  }
}
