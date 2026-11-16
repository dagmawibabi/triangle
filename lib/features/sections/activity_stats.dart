import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Time spent on something (watching video, …), kept on this phone: seconds
// per day, per item and per group (a channel), for a stats page.

/// One thing the time went to.
@immutable
class ActivityItem {
  const ActivityItem({required this.key, required this.title, this.group = '', this.groupId = 0, this.mini, this.seconds = 0, this.count = 0, required this.last});
  final String key;
  final String title;

  /// Where it's from (a channel's name) and that chat's id.
  final String group;
  final int groupId;

  /// A blurry preview, base64.
  final String? mini;
  final int seconds;

  /// Times started.
  final int count;
  final DateTime last;

  ActivityItem copyWith({int? seconds, int? count, DateTime? last, String? mini}) =>
      ActivityItem(key: key, title: title, group: group, groupId: groupId, mini: mini ?? this.mini, seconds: seconds ?? this.seconds, count: count ?? this.count, last: last ?? this.last);

  Map<String, dynamic> toJson() => {'k': key, 't': title, 'g': group, 'gi': groupId, if (mini != null) 'm': mini, 's': seconds, 'n': count, 'l': last.millisecondsSinceEpoch};
  factory ActivityItem.fromJson(Map j) => ActivityItem(
    key: '${j['k']}',
    title: '${j['t'] ?? ''}',
    group: '${j['g'] ?? ''}',
    groupId: (j['gi'] as num?)?.toInt() ?? 0,
    mini: j['m'] == null ? null : '${j['m']}',
    seconds: (j['s'] as num?)?.toInt() ?? 0,
    count: (j['n'] as num?)?.toInt() ?? 0,
    last: DateTime.fromMillisecondsSinceEpoch((j['l'] as num?)?.toInt() ?? 0),
  );
}

@immutable
class ActivityStatsState {
  const ActivityStatsState({this.days = const {}, this.items = const {}, this.since});

  /// Seconds per day, keyed `yyyy-mm-dd`.
  final Map<String, int> days;
  final Map<String, ActivityItem> items;
  final DateTime? since;

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get totalSeconds => days.values.fold(0, (a, b) => a + b);
  int get today => days[dayKey(DateTime.now())] ?? 0;

  /// Days in a row with some time, up to today (or yesterday).
  int get streak {
    var d = DateTime.now();
    if (!days.containsKey(dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while ((days[dayKey(d)] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<ActivityItem> get top => items.values.toList()..sort((a, b) => b.seconds.compareTo(a.seconds));
  List<ActivityItem> get recent => items.values.toList()..sort((a, b) => b.last.compareTo(a.last));

  /// Seconds per group (channel), most first.
  List<(String, int, int)> get groups {
    final m = <String, (int, int)>{};
    for (final i in items.values) {
      if (i.group.isEmpty) continue;
      final g = m[i.group];
      m[i.group] = ((g?.$1 ?? 0) + i.seconds, i.groupId);
    }
    return [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$2.compareTo(a.$2));
  }
}

class ActivityStats extends Notifier<ActivityStatsState> {
  ActivityStats(this.name);
  final String name;
  Timer? _later;

  String get _key => 'activity_stats.$name';

  /// Done once what was kept on the phone is read back.
  late Future<void> ready;

  @override
  ActivityStatsState build() {
    ready = _load();
    return const ActivityStatsState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = ActivityStatsState(
        days: {for (final e in ((j['days'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        items: {for (final i in (j['items'] as List? ?? const [])) if (i is Map) '${i['k']}': ActivityItem.fromJson(i)},
        since: j['since'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['since'] as num).toInt()),
      );
    } catch (e) {
      debugPrint('[Stats] $name: $e');
    }
  }

  void _save() {
    _later?.cancel();
    _later = Timer(const Duration(seconds: 5), () async {
      final s = state;
      final items = s.recent.take(400).toList();
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({'days': s.days, 'items': [for (final i in items) i.toJson()], if (s.since != null) 'since': s.since!.millisecondsSinceEpoch}),
      );
    });
  }

  /// [seconds] more spent on [key].
  void add(String key, {required String title, String group = '', int groupId = 0, String? mini, int seconds = 0, bool started = false}) {
    final now = DateTime.now();
    final day = ActivityStatsState.dayKey(now);
    final had = state.items[key];
    final item = (had ?? ActivityItem(key: key, title: title, group: group, groupId: groupId, mini: mini, last: now)).copyWith(
      seconds: (had?.seconds ?? 0) + seconds,
      count: (had?.count ?? 0) + (started ? 1 : 0),
      last: now,
      mini: mini,
    );
    state = ActivityStatsState(
      days: seconds > 0 ? {...state.days, day: (state.days[day] ?? 0) + seconds} : state.days,
      items: {...state.items, key: item},
      since: state.since ?? now,
    );
    _save();
  }

  Future<void> clear() async {
    state = const ActivityStatsState();
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

final activityStatsProvider = NotifierProvider.family<ActivityStats, ActivityStatsState, String>(ActivityStats.new);
