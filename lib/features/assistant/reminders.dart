import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'notifications.dart';

/// A reminder or scheduled job: "remind me to walk in 5 minutes", "every
/// weekday at 9:00 remind me to stand up", "every Sunday at 20:00 summarise
/// my week's channels".
///
/// A plain reminder is a phone notification Android shows on time, even if
/// the app isn't running. With a [prompt] it is a job: the assistant runs the
/// prompt at that time (the app has to be alive then, which "Keep running in
/// the background" takes care of) and the notification carries its answer.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.text,
    required this.createdAt,
    this.next,
    this.cron,
    this.prompt = '',
    this.enabled = true,
    this.conversationId,
    this.lastRunAt,
    this.runs = 0,
    this.accountIds,
  });

  final String id;

  /// For jobs: the Telegram accounts the assistant may use when it runs.
  /// Null: every account.
  final List<String>? accountIds;

  /// What to remind about; the notification's text.
  final String text;

  /// When it fires next; null once a one-off has fired.
  final DateTime? next;

  /// For repeating ones: a five-field cron expression
  /// ("minute hour day-of-month month day-of-week").
  final String? cron;

  /// For jobs: what the assistant does when it fires.
  final String prompt;
  final bool enabled;
  final String? conversationId;
  final DateTime? lastRunAt;
  final int runs;
  final DateTime createdAt;

  bool get repeats => cron != null;
  bool get isJob => prompt.trim().isNotEmpty;

  /// Android notification ids: a few per reminder, one for each upcoming
  /// time scheduled ahead.
  int notificationId(int slot) => 0x200000 + (id.hashCode & 0x3FFFF) * _slots + slot;
  static const _slots = 4;

  Reminder copyWith({
    String? text,
    DateTime? next,
    bool clearNext = false,
    String? cron,
    bool clearCron = false,
    String? prompt,
    bool? enabled,
    String? conversationId,
    DateTime? lastRunAt,
    int? runs,
    List<String>? accountIds,
    bool allAccounts = false,
  }) => Reminder(
    id: id,
    text: text ?? this.text,
    next: clearNext ? null : (next ?? this.next),
    cron: clearCron ? null : (cron ?? this.cron),
    prompt: prompt ?? this.prompt,
    enabled: enabled ?? this.enabled,
    conversationId: conversationId ?? this.conversationId,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    runs: runs ?? this.runs,
    createdAt: createdAt,
    accountIds: allAccounts ? null : (accountIds ?? this.accountIds),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'next': next?.toIso8601String(),
    'cron': cron,
    'prompt': prompt,
    'enabled': enabled,
    'conversation_id': conversationId,
    'last_run': lastRunAt?.toIso8601String(),
    'runs': runs,
    'created': createdAt.toIso8601String(),
    'accounts': ?accountIds,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'],
    text: j['text'] ?? '',
    next: DateTime.tryParse(j['next'] ?? ''),
    cron: j['cron'],
    prompt: j['prompt'] ?? '',
    enabled: j['enabled'] ?? true,
    conversationId: j['conversation_id'],
    lastRunAt: DateTime.tryParse(j['last_run'] ?? ''),
    runs: (j['runs'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
    accountIds: (j['accounts'] as List?)?.map((e) => '$e').toList(),
  );

  /// For the assistant and the Watches screen.
  Map<String, dynamic> describe() => {
    'reminder_id': id,
    'text': text,
    'enabled': enabled,
    if (next != null) 'next': next!.toIso8601String().substring(0, 16),
    if (cron != null) 'cron': cron,
    if (cron != null) 'repeats': Cron.describe(cron!),
    if (isJob) 'prompt': prompt,
    if (isJob) 'accounts': accountIds ?? 'all',
    'runs': runs,
    if (lastRunAt != null) 'last_run': lastRunAt!.toIso8601String().substring(0, 16),
  };
}

/// Five-field cron expressions: minute (0-59), hour (0-23), day of month
/// (1-31), month (1-12) and day of week (0-6, Sunday 0 or 7). Each field
/// takes `*`, numbers, lists (`1,15`), ranges (`1-5`) and steps (`*/15`,
/// `9-17/2`). Month and weekday names (jan, mon) work too.
class Cron {
  Cron._(this._min, this._hour, this._dom, this._month, this._dow, this._domAny, this._dowAny);

  final Set<int> _min, _hour, _dom, _month, _dow;
  final bool _domAny, _dowAny;

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  static const _days = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

  /// Throws [FormatException] when [expr] isn't a valid expression.
  factory Cron.parse(String expr) {
    final aliases = {
      '@hourly': '0 * * * *',
      '@daily': '0 0 * * *',
      '@weekly': '0 0 * * 0',
      '@monthly': '0 0 1 * *',
      '@yearly': '0 0 1 1 *',
    };
    final parts = (aliases[expr.trim().toLowerCase()] ?? expr).trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw const FormatException('A cron expression has five fields: minute hour day-of-month month day-of-week');
    }
    final dow = _field(parts[4], 0, 7, _days).map((d) => d % 7).toSet();
    return Cron._(
      _field(parts[0], 0, 59),
      _field(parts[1], 0, 23),
      _field(parts[2], 1, 31),
      _field(parts[3], 1, 12, _months, 1),
      dow,
      parts[2] == '*' || parts[2] == '?',
      parts[4] == '*' || parts[4] == '?',
    );
  }

  static Set<int> _field(String f, int lo, int hi, [List<String> names = const [], int nameBase = 0]) {
    int value(String s) {
      final i = names.indexOf(s.toLowerCase());
      if (i >= 0) return i + nameBase;
      final n = int.tryParse(s);
      if (n == null || n < lo || n > hi) throw FormatException('"$s" is out of range $lo-$hi');
      return n;
    }

    final out = <int>{};
    for (final part in f.split(',')) {
      final [range, ...rest] = part.split('/');
      final step = rest.isEmpty ? 1 : int.tryParse(rest.first) ?? 0;
      if (step < 1) throw FormatException('Bad step in "$part"');
      var (a, b) = (lo, hi);
      if (range != '*' && range != '?') {
        final ends = range.split('-');
        a = value(ends.first);
        b = ends.length > 1 ? value(ends[1]) : (rest.isEmpty ? a : hi);
      }
      if (a > b) throw FormatException('Bad range "$range"');
      for (var v = a; v <= b; v += step) {
        out.add(v);
      }
    }
    return out;
  }

  bool _dayMatches(DateTime t) {
    final dom = _dom.contains(t.day), dow = _dow.contains(t.weekday % 7);
    // Standard cron: with both restricted, either one matching is enough.
    if (!_domAny && !_dowAny) return dom || dow;
    return dom && dow;
  }

  /// The first time strictly after [after] that matches, within ~5 years.
  DateTime? nextAfter(DateTime after) {
    var t = DateTime(after.year, after.month, after.day, after.hour, after.minute).add(const Duration(minutes: 1));
    final limit = after.add(const Duration(days: 366 * 5));
    while (t.isBefore(limit)) {
      if (!_month.contains(t.month)) {
        t = DateTime(t.year, t.month + 1);
        continue;
      }
      if (!_dayMatches(t)) {
        t = DateTime(t.year, t.month, t.day + 1);
        continue;
      }
      if (!_hour.contains(t.hour)) {
        t = DateTime(t.year, t.month, t.day, t.hour + 1);
        continue;
      }
      if (!_min.contains(t.minute)) {
        t = DateTime(t.year, t.month, t.day, t.hour, t.minute + 1);
        continue;
      }
      return t;
    }
    return null;
  }

  /// A few words for people, e.g. "every day at 09:00".
  static String describe(String expr) {
    final p = expr.trim().split(RegExp(r'\s+'));
    if (p.length != 5) return expr;
    final time = int.tryParse(p[0]) != null && int.tryParse(p[1]) != null
        ? 'at ${p[1].padLeft(2, '0')}:${p[0].padLeft(2, '0')}'
        : null;
    if (time != null && p[2] == '*' && p[3] == '*') {
      if (p[4] == '*') return 'every day $time';
      if (p[4] == '1-5') return 'weekdays $time';
      if (p[4] == '0,6' || p[4] == '6,0') return 'weekends $time';
      final d = int.tryParse(p[4]);
      if (d != null) return 'every ${const ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d]} $time';
    }
    if (p[0].startsWith('*/') && p.skip(1).every((x) => x == '*')) return 'every ${p[0].substring(2)} minutes';
    if (p[0] == '0' && p[1].startsWith('*/') && p.skip(2).every((x) => x == '*')) return 'every ${p[1].substring(2)} hours';
    return 'cron "$expr"';
  }
}

/// Runs an assistant job; set up by the chat controller, which can.
typedef JobRunner = Future<void> Function(Reminder r);

class ReminderStore extends Notifier<List<Reminder>> {
  static const _key = 'reminders.v1';
  static const _uuid = Uuid();

  /// Set by the chat layer so jobs can run the assistant.
  JobRunner? runJob;
  final Set<String> _running = {};
  bool _loaded = false;

  /// Completes once saved reminders are loaded; changes wait for it, so the
  /// load can't overwrite them (or bring a deleted one back).
  late Future<void> ready;

  @override
  List<Reminder> build() {
    ready = _load();
    return const [];
  }

  AppNotifier get _notifier => ref.read(appNotifierProvider);

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        state = [for (final r in jsonDecode(raw) as List) Reminder.fromJson(Map<String, dynamic>.from(r))];
      }
    } catch (e) {
      debugPrint('[Reminders] $e');
    }
    _loaded = true;
    // Times passed while the app was closed: plain ones were shown by
    // Android; move every repeating one on and schedule what comes next.
    await tick();
    for (final r in state) {
      await _schedule(r);
    }
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final r in state) r.toJson()]));

  Reminder? byId(String id) => state.where((r) => r.id == id).firstOrNull;

  /// Validates [cron] and works out the first time. Throws [FormatException].
  static DateTime? firstTime({DateTime? at, String? cron}) {
    if (cron != null) return Cron.parse(cron).nextAfter(DateTime.now());
    return at;
  }

  Future<Reminder> add({required String text, DateTime? at, String? cron, String prompt = '', String? conversationId, List<String>? accountIds}) async {
    await ready;
    final next = firstTime(at: at, cron: cron);
    if (next == null) throw const FormatException('Give a time (at / in_minutes) or a cron expression.');
    if (cron == null && next.isBefore(DateTime.now())) throw const FormatException('That time has already passed.');
    final r = Reminder(
      id: _uuid.v4().substring(0, 8),
      text: text,
      next: next,
      cron: cron,
      prompt: prompt,
      conversationId: conversationId,
      accountIds: accountIds,
      createdAt: DateTime.now(),
    );
    state = [...state, r];
    await _save();
    await _notifier.requestPermission();
    await _notifier.requestExactAlarms();
    await _schedule(r);
    return r;
  }

  Future<Reminder?> update(String id, Reminder Function(Reminder) change) async {
    await ready;
    final old = byId(id);
    if (old == null) return null;
    var r = change(old);
    // A new schedule, or a repeating one turned back on, starts from now.
    if (r.cron != null && (r.cron != old.cron || (r.enabled && !old.enabled))) {
      r = r.copyWith(next: Cron.parse(r.cron!).nextAfter(DateTime.now()));
    }
    state = [for (final x in state) x.id == id ? r : x];
    await _save();
    await _unschedule(old);
    await _schedule(r);
    return r;
  }

  Future<bool> remove(String id) async {
    await ready;
    final r = byId(id);
    if (r == null) return false;
    state = state.where((x) => x.id != id).toList();
    await _save();
    await _unschedule(r);
    return true;
  }

  Future<void> _unschedule(Reminder r) async {
    for (var i = 0; i < Reminder._slots; i++) {
      await _notifier.cancel(r.notificationId(i));
    }
  }

  /// Plain reminders go to Android's alarm, a few times ahead for repeating
  /// ones so they keep coming while the app is closed. Jobs are run by
  /// [tick] instead, since the assistant has to do something first.
  ///
  /// Slots are overwritten, not cancelled first: cancelling an id also
  /// takes a reminder that just went off out of the notification shade.
  Future<void> _schedule(Reminder r) async {
    if (!r.enabled || r.isJob || r.next == null) return;
    final cron = r.cron == null ? null : Cron.parse(r.cron!);
    DateTime? t = r.next;
    for (var i = 0; i < Reminder._slots && t != null; i++) {
      if (t.isAfter(DateTime.now())) await _notifier.schedule(r.notificationId(i), t, 'Reminder', r.text, conversationId: r.conversationId);
      if (cron == null) break;
      t = cron.nextAfter(t);
    }
  }

  /// Called every half minute by the watch engine (and on start): moves
  /// past-due reminders on and runs jobs that are due.
  Future<void> tick() async {
    if (!_loaded) return;
    final now = DateTime.now();
    for (final due in state.where((r) => r.enabled && r.next != null && !r.next!.isAfter(now)).toList()) {
      // Each step below awaits: one turned off or deleted meanwhile is left
      // alone, and its alarms aren't scheduled again.
      final r = byId(due.id);
      if (r == null || !r.enabled || r.next != due.next) continue;
      if (_running.contains(r.id)) continue;
      // Right at start-up nothing can run a job yet; the engine's first
      // tick will.
      if (r.isJob && runJob == null) continue;
      final late = now.difference(r.next!);
      // A job missed by hours (the phone was off) is skipped, not run late.
      if (r.isJob && late.inHours < 2) unawaited(_run(r));
      final following = r.cron == null ? null : Cron.parse(r.cron!).nextAfter(now);
      final moved = r.copyWith(
        next: following,
        clearNext: following == null,
        enabled: following != null,
        lastRunAt: r.isJob ? null : r.next,
        runs: r.isJob ? null : r.runs + 1,
      );
      if (byId(r.id) == null) continue;
      state = [for (final x in state) x.id == r.id ? moved : x];
      await _save();
      await _schedule(moved);
    }
  }

  Future<void> _run(Reminder r) async {
    final run = runJob;
    if (run == null || byId(r.id) == null) return;
    _running.add(r.id);
    try {
      await run(r);
      state = [
        for (final x in state)
          if (x.id == r.id) x.copyWith(lastRunAt: DateTime.now(), runs: x.runs + 1) else x,
      ];
      await _save();
    } catch (e) {
      debugPrint('[Reminders] job ${r.id}: $e');
    } finally {
      _running.remove(r.id);
    }
  }

  /// Runs a reminder now, for "test it".
  Future<void> runNow(Reminder r) async {
    if (r.isJob) return _run(r);
    await _notifier.show('Reminder', r.text, conversationId: r.conversationId);
  }
}

final reminderStoreProvider = NotifierProvider<ReminderStore, List<Reminder>>(ReminderStore.new);
