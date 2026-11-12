import 'dart:math' as math;

import 'finance_models.dart';

// Money analysis over the user's transactions: period summaries with chart
// series, category and counterparty breakdowns, balance history, budgets,
// and Totals' insights (github.com/detached-space/totals, MIT licence):
// health score, recurring payments, unusual spending and next month's
// projection. Pure functions, so the tools and the screen agree.

/// A span of time, from inclusive to [to] exclusive.
class FinPeriod {
  const FinPeriod(this.key, this.label, this.from, this.to);
  final String key;
  final String label;
  final DateTime? from;
  final DateTime to;

  bool contains(DateTime t) => (from == null || !t.isBefore(from!)) && t.isBefore(to);

  int get days => from == null ? 0 : to.difference(from!).inDays.clamp(1, 100000);

  /// The span just before this one, as long as it.
  FinPeriod? get previous {
    if (from == null) return null;
    final span = to.difference(from!);
    // Calendar months compare with the previous calendar month.
    if (key == 'this_month' || key == 'last_month') {
      final f = DateTime(from!.year, from!.month - 1);
      return FinPeriod('previous', 'the month before', f, from!);
    }
    return FinPeriod('previous', 'the period before', from!.subtract(span), from!);
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    if (from != null) 'from': _day(from!),
    'to': _day(to.subtract(const Duration(milliseconds: 1))),
  };

  static const keys = ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'last_7_days', 'last_30_days', 'last_90_days', 'this_year', 'last_year', 'all'];

  /// [key] (one of [keys]), or the dates [since]..[until] (YYYY-MM-DD,
  /// inclusive) when given.
  static FinPeriod resolve(String? key, {String? since, String? until, DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final s = DateTime.tryParse(since ?? '');
    final u = DateTime.tryParse(until ?? '');
    if (s != null || u != null) {
      final from = s == null ? null : DateTime(s.year, s.month, s.day);
      final to = u == null ? today.add(const Duration(days: 1)) : DateTime(u.year, u.month, u.day + 1);
      return FinPeriod('custom', '${from == null ? 'Until' : '${_day(from)} –'} ${_day(to.subtract(const Duration(days: 1)))}', from, to);
    }
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return switch (key) {
      'today' => FinPeriod('today', 'Today', today, today.add(const Duration(days: 1))),
      'yesterday' => FinPeriod('yesterday', 'Yesterday', today.subtract(const Duration(days: 1)), today),
      'this_week' => FinPeriod('this_week', 'This week', monday, today.add(const Duration(days: 1))),
      'last_week' => FinPeriod('last_week', 'Last week', monday.subtract(const Duration(days: 7)), monday),
      'last_month' => FinPeriod('last_month', _monthName(DateTime(n.year, n.month - 1)), DateTime(n.year, n.month - 1), DateTime(n.year, n.month)),
      'last_7_days' => FinPeriod('last_7_days', 'Last 7 days', today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
      'last_30_days' => FinPeriod('last_30_days', 'Last 30 days', today.subtract(const Duration(days: 29)), today.add(const Duration(days: 1))),
      'last_90_days' => FinPeriod('last_90_days', 'Last 90 days', today.subtract(const Duration(days: 89)), today.add(const Duration(days: 1))),
      'this_year' => FinPeriod('this_year', '${n.year}', DateTime(n.year), today.add(const Duration(days: 1))),
      'last_year' => FinPeriod('last_year', '${n.year - 1}', DateTime(n.year - 1), DateTime(n.year)),
      'all' => FinPeriod('all', 'All time', null, today.add(const Duration(days: 1))),
      _ => FinPeriod('this_month', _monthName(n), DateTime(n.year, n.month), today.add(const Duration(days: 1))),
    };
  }
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _monthName(DateTime d) => '${_months[d.month - 1]} ${d.year}';
String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
double _r(double v) => (v * 100).roundToDouble() / 100;

/// Money moved between the user's own accounts: a debit and a credit of the
/// same amount on two different accounts within 30 minutes, or anything
/// filed under "transfer". Left out of income and spending.
Set<String> ownTransfers(List<FinTransaction> txs) {
  final out = <String>{for (final t in txs) if (t.category == 'transfer') t.id};
  final credits = txs.where((t) => t.isCredit && t.accountId != null && t.category == null).toList()..sort((a, b) => a.time.compareTo(b.time));
  final used = <String>{};
  for (final d in txs.where((t) => t.isDebit && t.accountId != null && t.category == null)) {
    for (final c in credits) {
      if (used.contains(c.id) || c.accountId == d.accountId) continue;
      if ((c.amount - d.amount).abs() > 0.01) continue;
      if (c.time.difference(d.time).inMinutes.abs() > 30) continue;
      out
        ..add(d.id)
        ..add(c.id);
      used.add(c.id);
      break;
    }
  }
  return out;
}

/// What a transaction counts as for the analysis.
class _Ledger {
  _Ledger(this.txs, this.categories) : transfers = ownTransfers(txs);
  final List<FinTransaction> txs;
  final Map<String, FinCategory> categories;
  final Set<String> transfers;

  bool counts(FinTransaction t) => !transfers.contains(t.id);
  double income(FinTransaction t) => t.isCredit && counts(t) ? t.amount : 0;
  double expense(FinTransaction t) => t.isDebit ? (counts(t) ? t.amount : 0) + t.fee : 0;
  String categoryOf(FinTransaction t) => t.category ?? (t.isCredit ? 'income_uncategorized' : 'uncategorized');
  String nameOf(String key) => categories[key]?.name ?? (key == 'uncategorized' ? 'Uncategorized' : key == 'income_uncategorized' ? 'Uncategorized income' : key);
}

String _who(FinTransaction t) {
  final c = t.counterparty.trim();
  return c.isEmpty ? (t.note.trim().isEmpty ? '' : t.note.trim()) : c;
}

/// Totals for [period]: income, spending, fees, net and savings rate; a
/// chart series bucketed by day, week or month; spending by category;
/// income sources; top payees; per-account flows; the comparison with the
/// period before; and the biggest expense.
Map<String, dynamic> periodSummary(
  List<FinTransaction> all,
  FinPeriod period, {
  required Map<String, FinCategory> categories,
  Map<String, String> accountNames = const {},
  Map<String, dynamic> Function(FinTransaction t)? describe,
}) {
  final ledger = _Ledger(all, categories);
  final txs = all.where((t) => period.contains(t.time)).toList()..sort((a, b) => a.time.compareTo(b.time));
  double sum(Iterable<FinTransaction> xs, double Function(FinTransaction) f) => xs.fold(0.0, (s, t) => s + f(t));
  final income = sum(txs, ledger.income);
  final expense = sum(txs, ledger.expense);
  final fees = sum(txs.where((t) => t.isDebit), (t) => t.fee);

  // Chart buckets: days for a month or so, weeks up to half a year, months
  // beyond.
  final start = period.from ?? (txs.isEmpty ? DateTime.now() : DateTime(txs.first.time.year, txs.first.time.month, txs.first.time.day));
  final spanDays = period.to.difference(start).inDays;
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
  String label(DateTime b) => switch (bucket) {
    'day' => '${b.day} ${_short[b.month - 1]}',
    'week' => '${b.day} ${_short[b.month - 1]}',
    _ => '${_short[b.month - 1]}${b.year == DateTime.now().year ? '' : ' ${b.year % 100}'}',
  };
  final series = <DateTime, List<double>>{};
  for (var b = bucketOf(start); b.isBefore(period.to) && series.length < 400; b = next(b)) {
    series[b] = [0, 0];
  }
  for (final t in txs) {
    final s = series.putIfAbsent(bucketOf(t.time), () => [0, 0]);
    s[0] += ledger.income(t);
    s[1] += ledger.expense(t);
  }
  final keys = series.keys.toList()..sort();

  Map<String, dynamic> grouped(Iterable<FinTransaction> xs, double Function(FinTransaction) f, double total) {
    final by = <String, (double, int)>{};
    for (final t in xs) {
      final v = f(t);
      if (v <= 0) continue;
      final k = ledger.categoryOf(t);
      final o = by[k] ?? (0.0, 0);
      by[k] = (o.$1 + v, o.$2 + 1);
    }
    final list = by.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return {
      'items': [
        for (final e in list)
          {
            'key': e.key,
            'name': ledger.nameOf(e.key),
            'icon': categories[e.key]?.icon ?? 'more',
            if (categories[e.key]?.essential ?? false) 'essential': true,
            'amount': _r(e.value.$1),
            'count': e.value.$2,
            'share': total == 0 ? 0 : _r(e.value.$1 / total),
          },
      ],
    };
  }

  List<Map<String, dynamic>> people(bool credit) {
    final by = <String, (double, int)>{};
    for (final t in txs.where((t) => credit ? t.isCredit : t.isDebit)) {
      if (!ledger.counts(t)) continue;
      final w = _who(t);
      if (w.isEmpty) continue;
      final o = by[w] ?? (0.0, 0);
      by[w] = (o.$1 + t.amount, o.$2 + 1);
    }
    final list = by.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return [for (final e in list.take(8)) {'name': e.key, 'amount': _r(e.value.$1), 'count': e.value.$2}];
  }

  final accounts = <String, List<double>>{};
  for (final t in txs) {
    final s = accounts.putIfAbsent(t.accountId ?? '', () => [0, 0, 0]);
    s[0] += ledger.income(t);
    s[1] += ledger.expense(t);
    s[2] += 1;
  }

  final prev = period.previous;
  Map<String, dynamic>? before;
  if (prev != null) {
    final p = all.where((t) => prev.contains(t.time));
    final pi = sum(p, ledger.income), pe = sum(p, ledger.expense);
    before = {
      'label': prev.label,
      'income': _r(pi),
      'expense': _r(pe),
      if (pe > 0) 'expense_change_pct': _r((expense - pe) / pe * 100),
      if (pi > 0) 'income_change_pct': _r((income - pi) / pi * 100),
    };
  }

  final spend = txs.where((t) => t.isDebit && ledger.counts(t)).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  final days = period.from == null ? math.max(1, spanDays) : math.max(1, math.min(period.days, DateTime.now().difference(period.from!).inDays + 1));
  return {
    'period': period.toJson(),
    'income': _r(income),
    'expense': _r(expense),
    'fees': _r(fees),
    'net': _r(income - expense),
    'savings_rate': income <= 0 ? null : _r(((income - expense) / income).clamp(-1, 1)),
    'transactions': txs.length,
    'own_transfers': txs.where((t) => ledger.transfers.contains(t.id)).length,
    'avg_daily_spend': _r(expense / days),
    'series': {
      'bucket': bucket,
      'points': [
        for (final k in keys) {'label': label(k), 'start': _day(k), 'income': _r(series[k]![0]), 'expense': _r(series[k]![1])},
      ],
    },
    'categories': grouped(txs.where((t) => t.isDebit), ledger.expense, expense)['items'],
    'income_sources': grouped(txs.where((t) => t.isCredit), ledger.income, income)['items'],
    'top_payees': people(false),
    'top_payers': people(true),
    'accounts': [
      for (final e in accounts.entries)
        {'id': e.key.isEmpty ? null : e.key, 'name': accountNames[e.key] ?? 'No account', 'income': _r(e.value[0]), 'expense': _r(e.value[1]), 'transactions': e.value[2].toInt()},
    ],
    'previous': ?before,
    if (spend.isNotEmpty) 'biggest_expense': describe?.call(spend.first) ?? spend.first.toJson(),
  };
}

/// The balance over time from what the bank SMS reported after each
/// transaction: for one account, or the sum of [accounts] (each holding its
/// last known balance). Values and epoch-millisecond times, oldest first.
({List<double> values, List<int> times}) balanceHistory(List<FinTransaction> txs, List<FinAccount> accounts, {DateTime? from, int maxPoints = 120}) {
  final ids = {for (final a in accounts) a.id};
  final events = txs.where((t) => t.accountId != null && ids.contains(t.accountId) && t.balanceAfter != null).toList()..sort((a, b) => a.time.compareTo(b.time));
  if (events.isEmpty) return (values: const [], times: const []);
  // Start every account at its first reported balance, or its current one.
  final last = <String, double>{for (final a in accounts) a.id: a.balance};
  for (final a in accounts) {
    final first = events.where((t) => t.accountId == a.id).firstOrNull;
    if (first != null) last[a.id] = first.balanceAfter! + (first.isDebit ? first.amount + first.fee : -first.amount);
  }
  final values = <double>[], times = <int>[];
  for (final t in events) {
    last[t.accountId!] = t.balanceAfter!;
    if (from != null && t.time.isBefore(from)) continue;
    values.add(_r(last.values.fold(0.0, (s, v) => s + v)));
    times.add(t.time.millisecondsSinceEpoch);
  }
  if (from != null && values.isEmpty) return (values: const [], times: const []);
  // Keep the chart light: every nth point, always the last.
  if (values.length > maxPoints) {
    final step = values.length / maxPoints;
    final v = <double>[], ti = <int>[];
    for (var i = 0.0; i < values.length - 1; i += step) {
      v.add(values[i.floor()]);
      ti.add(times[i.floor()]);
    }
    v.add(values.last);
    ti.add(times.last);
    return (values: v, times: ti);
  }
  return (values: values, times: times);
}

/// Each budget with what was spent against it in its current week or month.
List<Map<String, dynamic>> budgetStatus(List<FinBudget> budgets, List<FinTransaction> txs, Map<String, FinCategory> categories, {DateTime? now}) {
  final ledger = _Ledger(txs, categories);
  final n = now ?? DateTime.now();
  return [
    for (final b in budgets)
      () {
        final p = FinPeriod.resolve(b.period == 'week' ? 'this_week' : 'this_month', now: n);
        final spent = txs.where((t) => t.isDebit && p.contains(t.time) && (b.category == null || t.category == b.category)).fold(0.0, (s, t) => s + ledger.expense(t));
        // The period runs to the end of the week or month, not just today.
        final end = b.period == 'week' ? p.from!.add(const Duration(days: 7)) : DateTime(n.year, n.month + 1);
        final left = end.difference(n).inHours / 24;
        return {
          'id': b.id,
          'category': b.category,
          'name': b.category == null ? 'All spending' : ledger.nameOf(b.category!),
          'icon': b.category == null ? 'wallet' : categories[b.category]?.icon ?? 'more',
          'period': b.period,
          'limit': _r(b.limit),
          'spent': _r(spent),
          'remaining': _r(b.limit - spent),
          'progress': b.limit <= 0 ? 0 : _r(spent / b.limit),
          'over': spent > b.limit,
          'days_left': left.ceil().clamp(0, 31),
          if (spent < b.limit && left > 0) 'per_day_left': _r((b.limit - spent) / math.max(1, left)),
        };
      }(),
  ];
}

/// When a payment every [gap] days, last made at [last], is next due: the
/// first one after today, skipping at most one missed; null when it looks
/// stopped.
DateTime? _nextDue(DateTime last, double gap, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final step = Duration(hours: (gap * 24).round());
  var next = last.add(step);
  if (next.isBefore(n)) next = next.add(step);
  return next.isBefore(n) ? null : next;
}

/// Totals' insights over every transaction: a 0-100 health score (spending
/// against income 40%, savings 30%, stability 20%, essentials 10% once
/// enough is categorized), recurring payments (3+ to the same payee),
/// unusually large ones (over the mean plus two standard deviations),
/// next month's projection (monthly average plus the last month's trend),
/// a 50/30/20 budget suggestion and plain-language tips.
Map<String, dynamic> financeInsights(List<FinTransaction> all, Map<String, FinCategory> categories, {Map<String, dynamic> Function(FinTransaction t)? describe}) {
  final ledger = _Ledger(all, categories);
  final income = all.where((t) => ledger.income(t) > 0).toList();
  final expenses = all.where((t) => ledger.expense(t) > 0).toList();
  final totalIncome = income.fold(0.0, (s, t) => s + ledger.income(t));
  final totalExpense = expenses.fold(0.0, (s, t) => s + ledger.expense(t));

  var essential = 0.0, wants = 0.0, uncategorized = 0.0;
  for (final t in expenses) {
    final c = t.category == null ? null : categories[t.category];
    final v = ledger.expense(t);
    if (c == null) {
      uncategorized += v;
    } else if (c.essential) {
      essential += v;
    } else {
      wants += v;
    }
  }
  final categorized = essential + wants;
  final coverage = totalExpense == 0 ? 0.0 : (categorized / totalExpense).clamp(0.0, 1.0);
  final essentialsRatio = categorized == 0 ? 0.0 : (essential / categorized).clamp(0.0, 1.0);

  double mean(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  double variance(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = mean(xs);
    return xs.fold(0.0, (s, x) => s + (x - m) * (x - m)) / xs.length;
  }

  final amounts = [for (final t in all) if (ledger.counts(t)) t.amount / 1000.0];
  final stability = (1 / (1 + variance(amounts) / 5.0)).clamp(0.0, 1.0);
  final savingsRate = totalIncome <= 0 ? 0.0 : ((totalIncome - totalExpense) / totalIncome).clamp(-1.0, 1.0);
  final expenseIncome = totalIncome == 0 ? 1.0 : (totalExpense / totalIncome).clamp(0.0, 2.0);
  final coverageFactor = coverage < 0.3 ? 0.0 : (coverage <= 0.7 ? 0.5 : 1.0);
  final essentialsPart = (1 - essentialsRatio).clamp(0.0, 0.1) * coverageFactor;
  final parts = {
    'spending_vs_income': _r(0.40 * (1 - expenseIncome.clamp(0.0, 1.0))),
    'savings': _r(0.30 * savingsRate.clamp(0.0, 1.0)),
    'stability': _r(0.20 * stability),
    'essentials': _r(0.10 * essentialsPart),
  };
  final score = all.isEmpty ? 0 : ((parts.values.fold(0.0, (s, v) => s + v)) * 100).clamp(0, 100).round();

  // Monthly totals for the projection.
  Map<String, double> monthly(List<FinTransaction> xs, double Function(FinTransaction) f) {
    final by = <String, double>{};
    for (final t in xs) {
      final k = '${t.time.year}-${t.time.month.toString().padLeft(2, '0')}';
      by[k] = (by[k] ?? 0) + f(t);
    }
    return by;
  }

  double avg(Map<String, double> m) => m.isEmpty ? 0 : m.values.reduce((a, b) => a + b) / m.length;
  double trend(Map<String, double> m) {
    if (m.length < 2) return 0;
    final k = m.keys.toList()..sort();
    return m[k.last]! - m[k[k.length - 2]]!;
  }

  final mi = monthly(income, ledger.income), me = monthly(expenses, ledger.expense);
  final projectedIncome = math.max(0.0, avg(mi) + trend(mi));
  final projectedExpense = math.max(0.0, avg(me) + trend(me));

  // Recurring: 3+ payments to the same payee, with how regular they are.
  final byPayee = <String, List<FinTransaction>>{};
  for (final t in expenses.where((t) => t.isDebit && ledger.counts(t))) {
    final w = _who(t).toLowerCase();
    if (w.isEmpty) continue;
    byPayee.putIfAbsent(w, () => []).add(t);
  }
  final recurring = <Map<String, dynamic>>[];
  for (final xs in byPayee.values.where((x) => x.length >= 3)) {
    xs.sort((a, b) => a.time.compareTo(b.time));
    final gaps = [for (var i = 1; i < xs.length; i++) xs[i].time.difference(xs[i - 1].time).inHours / 24];
    final gap = mean(gaps);
    final every = gap < 2 ? 'daily' : gap < 10 ? 'weekly' : gap < 45 ? 'monthly' : 'now and then';
    final total = xs.fold(0.0, (s, t) => s + t.amount);
    recurring.add({
      'label': _who(xs.last),
      'count': xs.length,
      'avg': _r(total / xs.length),
      'total': _r(total),
      'every': every,
      'last': _day(xs.last.time),
      if (_nextDue(xs.last.time, gap) case final next? when gap >= 2) 'next_expected': _day(next),
      if (xs.last.category != null) 'category': ledger.nameOf(xs.last.category!),
    });
  }
  recurring.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

  List<FinTransaction> unusual(List<FinTransaction> xs, double Function(FinTransaction) f) {
    if (xs.length < 5) return const [];
    final v = xs.map(f).toList();
    final limit = mean(v) + 2 * math.sqrt(variance(v));
    return (xs.where((t) => f(t) > limit).toList()..sort((a, b) => b.time.compareTo(a.time))).take(8).toList();
  }

  final anomalies = unusual(expenses, ledger.expense);
  final incomeAnomalies = unusual(income, ledger.income);

  // 50/30/20 on the monthly income, against what actually goes where.
  final monthsSeen = math.max(1, me.length);
  final monthlyIncome = avg(mi);
  final budget = {
    'monthly_income': _r(monthlyIncome),
    'needs_target': _r(monthlyIncome * 0.5),
    'wants_target': _r(monthlyIncome * 0.3),
    'savings_target': _r(monthlyIncome * 0.2),
    'needs_actual': _r(essential / monthsSeen),
    'wants_actual': _r(wants / monthsSeen),
    'uncategorized_actual': _r(uncategorized / monthsSeen),
  };

  final tips = <String>[];
  if (all.isEmpty) tips.add('No transactions yet. Sync bank SMS or add transactions to get insights.');
  if (coverage < 0.5 && totalExpense > 0) tips.add('Only ${(coverage * 100).round()}% of spending is categorized; categorizing more makes the score and budget advice sharper.');
  if (totalIncome > 0 && savingsRate < 0.1) tips.add('Saving ${(savingsRate * 100).round()}% of income; 20% is a common target.');
  if (totalIncome > 0 && savingsRate >= 0.2) tips.add('Saving ${(savingsRate * 100).round()}% of income — on or above the usual 20% target.');
  final feeTotal = all.fold(0.0, (s, t) => s + t.fee);
  if (totalExpense > 0 && feeTotal / totalExpense > 0.01) tips.add('Bank fees and VAT came to ${_r(feeTotal)} (${(feeTotal / totalExpense * 100).toStringAsFixed(1)}% of spending).');
  if (projectedExpense > projectedIncome && projectedIncome > 0) tips.add('Next month\'s spending is on course to beat income by ${_r(projectedExpense - projectedIncome)}.');
  if (monthlyIncome > 0 && wants / monthsSeen > monthlyIncome * 0.3) tips.add('Wants run above 30% of monthly income.');

  return {
    'health_score': score,
    'score_parts': parts,
    'grade': score >= 75 ? 'Excellent' : score >= 55 ? 'Good' : score >= 35 ? 'Fair' : 'Needs attention',
    'total_income': _r(totalIncome),
    'total_expense': _r(totalExpense),
    'savings_rate': _r(savingsRate),
    'stability': _r(stability),
    'essentials_ratio': _r(essentialsRatio),
    'categorized_share': _r(coverage),
    'months': me.length,
    'projection': {'income': _r(projectedIncome), 'expense': _r(projectedExpense), 'savings': _r(projectedIncome - projectedExpense)},
    'monthly': [
      for (final k in ({...mi.keys, ...me.keys}.toList()..sort()).reversed.take(12).toList().reversed)
        {'month': k, 'label': '${_short[int.parse(k.substring(5)) - 1]} ${k.substring(2, 4)}', 'income': _r(mi[k] ?? 0), 'expense': _r(me[k] ?? 0)},
    ],
    'recurring': recurring.take(10).toList(),
    'unusual_expenses': [for (final t in anomalies) describe?.call(t) ?? t.toJson()],
    'unusual_income': [for (final t in incomeAnomalies) describe?.call(t) ?? t.toJson()],
    'budget_503020': budget,
    'tips': tips,
  };
}
