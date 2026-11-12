import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage.dart';

/// Caps on what the assistant may spend on AI, in US dollars, counted from
/// the usage log (reported costs, or estimates from catalog prices). A run
/// stops when it reaches what is left; a new one doesn't start once a cap is
/// reached. Null: no cap.
@immutable
class SpendLimits {
  const SpendLimits({this.daily, this.monthly, this.perWatchDaily, this.loaded = false});

  /// Everything, since local midnight.
  final double? daily;

  /// Everything, since the 1st of this month.
  final double? monthly;

  /// Each watch or scheduled job, since local midnight.
  final double? perWatchDaily;
  final bool loaded;

  bool get any => daily != null || monthly != null || perWatchDaily != null;

  SpendLimits copyWith({double? Function()? daily, double? Function()? monthly, double? Function()? perWatchDaily, bool? loaded}) =>
      SpendLimits(
        daily: daily == null ? this.daily : daily(),
        monthly: monthly == null ? this.monthly : monthly(),
        perWatchDaily: perWatchDaily == null ? this.perWatchDaily : perWatchDaily(),
        loaded: loaded ?? this.loaded,
      );
}

/// What a run may still spend: [remaining] dollars (null: no cap applies),
/// or [blocked] with the reason when a cap is already reached.
typedef SpendBudget = ({double? remaining, String? blocked});

double spentSince(Iterable<UsageEvent> events, DateTime since, {String? conversationId}) {
  var total = 0.0;
  for (final e in events) {
    if (e.at.isBefore(since)) continue;
    if (conversationId != null && e.conversationId != conversationId) continue;
    total += e.cost;
  }
  return total;
}

String formatUsd(double v) => v < 0.01 && v > 0 ? '\$${v.toStringAsFixed(4)}' : '\$${v.toStringAsFixed(2)}';

/// The budget for a run in [conversationId]; [automatic] for watches and jobs.
SpendBudget budgetFor(SpendLimits limits, List<UsageEvent> events, {String? conversationId, bool automatic = false, DateTime? now}) {
  final t = now ?? DateTime.now();
  final midnight = DateTime(t.year, t.month, t.day);
  final monthStart = DateTime(t.year, t.month);
  double? remaining;
  String? blocked;
  void cap(double? limit, double spent, String what) {
    if (limit == null) return;
    final left = limit - spent;
    if (left <= 0 && blocked == null) blocked = '$what of ${formatUsd(limit)} is reached (${formatUsd(spent)} spent).';
    remaining = remaining == null ? left : (left < remaining! ? left : remaining);
  }

  cap(limits.daily, spentSince(events, midnight), 'Today\'s spending limit');
  cap(limits.monthly, spentSince(events, monthStart), 'This month\'s spending limit');
  if (automatic && conversationId != null) {
    cap(limits.perWatchDaily, spentSince(events, midnight, conversationId: conversationId), 'This watch\'s daily spending limit');
  }
  return (remaining: blocked != null ? 0 : remaining, blocked: blocked);
}

class SpendLimitsStore extends Notifier<SpendLimits> {
  @override
  SpendLimits build() {
    _load();
    return const SpendLimits();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = SpendLimits(
      daily: p.getDouble('spend_limit_daily'),
      monthly: p.getDouble('spend_limit_monthly'),
      perWatchDaily: p.getDouble('spend_limit_watch_daily'),
      loaded: true,
    );
  }

  Future<void> _write(String key, double? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null || v <= 0) {
      await p.remove(key);
    } else {
      await p.setDouble(key, v);
    }
  }

  static double? _clean(double? v) => v == null || v <= 0 ? null : v;

  Future<void> setDaily(double? v) async {
    state = state.copyWith(daily: () => _clean(v));
    await _write('spend_limit_daily', v);
  }

  Future<void> setMonthly(double? v) async {
    state = state.copyWith(monthly: () => _clean(v));
    await _write('spend_limit_monthly', v);
  }

  Future<void> setPerWatchDaily(double? v) async {
    state = state.copyWith(perWatchDaily: () => _clean(v));
    await _write('spend_limit_watch_daily', v);
  }
}

final spendLimitsProvider = NotifierProvider<SpendLimitsStore, SpendLimits>(SpendLimitsStore.new);
