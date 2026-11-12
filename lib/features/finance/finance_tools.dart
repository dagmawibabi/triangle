import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device.dart';
import '../telegram/data/telegram_tools.dart' show ToolOutput;
import 'finance_insights.dart';
import 'finance_models.dart';
import 'finance_store.dart';
import 'payment_verifier.dart';
import 'verify_et.dart';
import '../settings/data/settings.dart' show settingsProvider;
import '../qr/qr.dart';

// Runs the finance tools (telegram_finance_tools.dart) against the
// FinanceStore. Their JSON feeds both the model and the chat cards in
// finance_result_cards.dart.

double _r(double v) => (v * 100).roundToDouble() / 100;
String _iso(DateTime t) => t.toIso8601String().substring(0, 16);

/// [t] for the model and the cards.
Map<String, dynamic> describeTransaction(FinanceStore store, FinanceState s, FinTransaction t, {Set<String> transfers = const {}}) {
  final a = s.account(t.accountId);
  final b = store.bank(t.bankId);
  final c = t.category == null ? null : s.categoryMap[t.category];
  return {
    'id': t.id,
    'date': _iso(t.time),
    'type': t.isCredit ? 'income' : 'expense',
    'amount': t.amount,
    if (t.fee > 0) 'fee': t.fee,
    'balance_after': ?t.balanceAfter,
    if (a != null) 'account_id': a.id,
    'account': a == null ? b.shortName : store.accountName(a),
    'bank': b.shortName,
    if (b.colors.isNotEmpty) 'color': b.colors.first,
    if (t.counterparty.isNotEmpty) 'counterparty': t.counterparty,
    if (c != null) 'category': c.key,
    if (c != null) 'category_name': c.name,
    if (c != null) 'icon': c.icon,
    if (t.note.isNotEmpty) 'note': t.note,
    'reference': t.reference,
    'source': t.source,
    'link': ?t.link,
    if (transfers.contains(t.id)) 'own_transfer': true,
  };
}

/// [a] for the model and the cards: the number shows only its last digits.
Map<String, dynamic> describeAccount(FinanceStore store, FinanceState s, FinAccount a) {
  final b = store.bank(a.bankId);
  final month = FinPeriod.resolve('this_month');
  final mine = s.transactions.where((t) => t.accountId == a.id).toList();
  final thisMonth = mine.where((t) => month.contains(t.time));
  final d = a.digits;
  return {
    'id': a.id,
    'name': store.accountName(a),
    'bank': b.shortName,
    'bank_name': b.name,
    'bank_id': b.id,
    if (b.colors.isNotEmpty) 'colors': b.colors,
    if (d.isNotEmpty) 'number_ending': d.length > 4 ? d.substring(d.length - 4) : d,
    if (a.holder.isNotEmpty) 'holder': a.holder,
    if (a.nickname.isNotEmpty) 'nickname': a.nickname,
    'balance': _r(a.balance),
    if (a.balanceAt != null) 'balance_as_of': _iso(a.balanceAt!),
    'include_in_totals': a.includeInTotals,
    if (a.dormant) 'dormant': true,
    // Default matters only when the bank has more than one account.
    if (a.isDefault && s.accounts.where((x) => x.bankId == a.bankId).length > 1) 'default': true,
    if (a.detected) 'detected': true,
    if (b.simBased) 'wallet': true,
    'transactions': mine.length,
    'month_in': _r(thisMonth.where((t) => t.isCredit).fold(0.0, (x, t) => x + t.amount)),
    'month_out': _r(thisMonth.where((t) => t.isDebit).fold(0.0, (x, t) => x + t.outflow)),
    if (mine.isNotEmpty) 'last_activity': _iso(mine.first.time),
  };
}

DateTime? _date(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.length == 10 ? '${s}T12:00' : s);
}

/// Runs finance tool [name] with [a].
Future<ToolOutput> runFinanceTool(Ref ref, String name, Map<String, dynamic> a) async {
  final store = ref.read(financeStoreProvider.notifier);
  // Read only when verifying: settings load the phone's secure storage.
  String verifyEtKey() => ref.read(settingsProvider).verifyEtKey.trim();
  var s = await store.ready();
  String str(String k) => '${a[k] ?? ''}'.trim();
  double? num_(String k) => a[k] is num ? (a[k] as num).toDouble() : double.tryParse(str(k).replaceAll(',', ''));
  bool flag(String k, bool fallback) => a[k] is bool ? a[k] as bool : fallback;
  final cur = s.currency;

  FinAccount? accountArg({bool required = false}) {
    if (str('account_id').isEmpty) {
      if (required) throw ArgumentError('account_id is required.');
      return null;
    }
    final acc = store.findAccount(str('account_id'));
    if (acc == null) throw ArgumentError('No account matches "${str('account_id')}". finance_accounts lists them.');
    return acc;
  }

  FinCategory? categoryArg(String k) {
    if (str(k).isEmpty) return null;
    final c = store.findCategory(str(k));
    if (c == null) throw ArgumentError('No category "${str(k)}". finance_categories lists them; finance_categorize can create one.');
    return c;
  }

  FinPeriod period({String fallback = 'this_month'}) => FinPeriod.resolve(str('period').isEmpty ? fallback : str('period'), since: str('since'), until: str('until'));
  Map<String, String> names() => {for (final x in s.accounts) x.id: store.accountName(x)};

  try {
    switch (name) {
      case 'finance_sync_sms':
        if (!Device.supported) return const ToolOutput({'error': 'Reading bank SMS needs the Android app. finance_parse_sms reads a pasted message, and finance_add_transaction records one by hand.'});
        final days = (a['since_days'] as num?)?.toInt().clamp(1, 730);
        final r = await store.syncSms(since: days == null ? null : DateTime.now().subtract(Duration(days: days)), createAccounts: flag('create_accounts', true));
        s = store.current;
        final addedIds = r.addedIds.toSet();
        final added = s.transactions.where((t) => addedIds.contains(t.id)).toList();
        return ToolOutput({
          'scanned': r.scanned,
          'bank_messages': r.bankMessages,
          'added': r.added,
          'duplicates': r.duplicates,
          'skipped': r.skipped,
          'not_understood': r.unmatched,
          if (r.unparsed.isNotEmpty) 'unparsed_samples': r.unparsed,
          'new_accounts': [for (final x in r.newAccounts) if (s.account(x.id) != null) describeAccount(store, s, s.account(x.id)!)],
          'by_bank': {for (final e in r.perBank.entries) store.bank(e.key).shortName: e.value},
          'income': _r(added.where((t) => t.isCredit).fold(0.0, (x, t) => x + t.amount)),
          'expense': _r(added.where((t) => t.isDebit).fold(0.0, (x, t) => x + t.outflow)),
          'latest': [for (final t in added.take(8)) describeTransaction(store, s, t)],
          'total_balance': _r(s.totalBalance),
          'currency': cur,
          'patterns': store.parser.toJson(),
          if (r.scanned == 0) 'note': 'No messages in that window. since_days reads further back.',
        });

      case 'finance_parse_sms':
        final bank = str('bank').isEmpty ? null : store.findBank(str('bank'));
        if (str('bank').isNotEmpty && bank == null) return ToolOutput({'error': 'No bank "${str('bank')}". finance_banks lists them.'});
        final p = store.parse(str('text'), sender: str('sender').isEmpty ? null : str('sender'), bankId: bank?.id);
        if (p == null) {
          return const ToolOutput({
            'parsed': false,
            'note': 'No pattern matched. It may not be a transaction message, or its bank or wording isn\'t supported yet; finance_add_transaction can record it by hand.',
          });
        }
        final out = {'parsed': true, ...p.toJson(), 'bank': store.bank(p.bankId).shortName, 'type': p.type == 'CREDIT' ? 'income' : 'expense', 'currency': cur};
        if (flag('save', false)) {
          final reference = p.reference ?? 'pasted_${str('text').hashCode}';
          if (s.transactions.any((t) => t.bankId == p.bankId && t.reference == reference)) {
            out['saved'] = false;
            out['note'] = 'Already recorded.';
          } else {
            final t = await store.addTransaction(
              type: p.type,
              amount: p.amount,
              fee: p.serviceCharge + p.vat,
              accountId: store.findAccount(p.account ?? '')?.id ?? s.accounts.where((x) => x.bankId == p.bankId).firstOrNull?.id,
              bankId: p.bankId,
              counterparty: p.counterparty,
              adjustBalance: p.balance == null,
            );
            if (p.balance != null && t.accountId != null) await store.updateAccount(t.accountId!, balance: p.balance);
            s = store.current;
            out['saved'] = true;
            out['transaction'] = describeTransaction(store, s, t);
          }
        }
        return ToolOutput(out);

      case 'finance_overview':
        final p = period();
        final sum = periodSummary(s.transactions, p, categories: s.categoryMap, accountNames: names());
        final visible = s.accounts.where((x) => !x.dormant).toList()..sort((x, y) => y.balance.compareTo(x.balance));
        return ToolOutput({
          'currency': cur,
          'total_balance': _r(s.totalBalance),
          'accounts': [for (final x in visible) describeAccount(store, s, x)],
          'summary': {
            for (final k in const ['period', 'income', 'expense', 'net', 'savings_rate', 'transactions', 'avg_daily_spend', 'series', 'previous']) k: sum[k],
            'categories': (sum['categories'] as List).take(6).toList(),
          },
          'budgets': budgetStatus(s.budgets, s.transactions, s.categoryMap),
          'recent': [for (final t in s.transactions.take(6)) describeTransaction(store, s, t)],
          'uncategorized': s.transactions.where((t) => t.category == null && p.contains(t.time)).length,
          'last_sync': s.lastSync == null ? null : _iso(s.lastSync!),
          if (s.accounts.isEmpty && s.transactions.isEmpty) 'note': 'Nothing here yet: finance_sync_sms reads bank texts, or finance_add_account adds an account by hand.',
        });

      case 'finance_accounts':
        final one = accountArg();
        final bank = str('bank').isEmpty ? null : store.findBank(str('bank'));
        if (str('bank').isNotEmpty && bank == null) return ToolOutput({'error': 'No bank "${str('bank')}". finance_banks lists them.'});
        final list = (one != null ? [one] : s.accounts.where((x) => (bank == null || x.bankId == bank.id) && (flag('include_dormant', true) || !x.dormant)).toList())
          ..sort((x, y) => y.balance.compareTo(x.balance));
        final filtered = one != null || bank != null;
        return ToolOutput({
          'currency': cur,
          if (filtered) 'filtered': true,
          // The total of what was asked for: one account's balance, or every account's.
          'total_balance': _r(filtered ? list.where((x) => x.includeInTotals).fold(0.0, (t, x) => t + x.balance) : s.totalBalance),
          'count': list.length,
          'accounts': [for (final x in list) describeAccount(store, s, x)],
          if (list.isEmpty) 'note': 'No accounts yet. finance_add_account adds one; finance_sync_sms finds them in bank texts.',
        });

      case 'finance_add_account':
        final bank = store.findBank(str('bank'));
        if (bank == null) return ToolOutput({'error': 'No bank "${str('bank')}". finance_banks lists them; use "Cash" or "Other" for anything else.'});
        final before = s.transactions.where((t) => t.accountId == null && t.bankId == bank.id).length;
        final acc = await store.addAccount(
          bankId: bank.id,
          number: str('number'),
          holder: str('holder'),
          nickname: str('nickname'),
          balance: num_('balance') ?? 0,
          includeInTotals: flag('include_in_totals', true),
          isDefault: flag('default', false),
        );
        s = store.current;
        final after = s.transactions.where((t) => t.accountId == null && t.bankId == bank.id).length;
        return ToolOutput({'created': true, 'account': describeAccount(store, s, acc), if (before > after) 'moved_transactions': before - after});

      case 'finance_update_account':
        final acc = accountArg(required: true)!;
        final u = await store.updateAccount(
          acc.id,
          nickname: a.containsKey('nickname') ? str('nickname') : null,
          number: a.containsKey('number') ? str('number') : null,
          holder: a.containsKey('holder') ? str('holder') : null,
          balance: num_('balance'),
          includeInTotals: a['include_in_totals'] as bool?,
          dormant: a['dormant'] as bool?,
          isDefault: a['default'] as bool?,
        );
        return ToolOutput({'updated': true, 'account': describeAccount(store, store.current, u!)});

      case 'finance_delete_account':
        final acc = accountArg(required: true)!;
        final desc = describeAccount(store, s, acc);
        final del = flag('delete_transactions', false);
        final r = await store.deleteAccount(acc.id, withTransactions: del);
        return ToolOutput({'deleted': true, 'account': desc, if (del) 'transactions_deleted': r?.$2 ?? 0, if (!del) 'transactions_kept': r?.$2 ?? 0});

      case 'finance_transactions':
        final acc = accountArg();
        final bank = str('bank').isEmpty ? null : store.findBank(str('bank'));
        if (str('bank').isNotEmpty && bank == null) return ToolOutput({'error': 'No bank "${str('bank')}".'});
        final uncategorized = str('category').toLowerCase() == 'uncategorized';
        final cat = uncategorized ? null : categoryArg('category');
        final p = period(fallback: 'all');
        final q = str('query').toLowerCase();
        final type = str('type');
        final lo = num_('min_amount'), hi = num_('max_amount');
        final transfers = ownTransfers(s.transactions);
        final matches = s.transactions.where((t) {
          if (acc != null && t.accountId != acc.id) return false;
          if (bank != null && t.bankId != bank.id) return false;
          if (type == 'income' && !t.isCredit) return false;
          if (type == 'expense' && !t.isDebit) return false;
          if (uncategorized && t.category != null) return false;
          if (cat != null && t.category != cat.key) return false;
          if (lo != null && t.amount < lo) return false;
          if (hi != null && t.amount > hi) return false;
          if (!p.contains(t.time)) return false;
          if (q.isNotEmpty && !'${t.counterparty} ${t.note} ${t.reference}'.toLowerCase().contains(q)) return false;
          return true;
        }).toList();
        switch (str('sort')) {
          case 'oldest':
            matches.sort((x, y) => x.time.compareTo(y.time));
          case 'largest':
            matches.sort((x, y) => y.amount.compareTo(x.amount));
        }
        final limit = ((a['limit'] as num?)?.toInt() ?? 25).clamp(1, 200);
        return ToolOutput({
          'currency': cur,
          'total_matching': matches.length,
          'income': _r(matches.where((t) => t.isCredit && !transfers.contains(t.id)).fold(0.0, (x, t) => x + t.amount)),
          'expense': _r(matches.where((t) => t.isDebit).fold(0.0, (x, t) => x + (transfers.contains(t.id) ? t.fee : t.outflow))),
          'transactions': [for (final t in matches.take(limit)) describeTransaction(store, s, t, transfers: transfers)],
          'filters': {
            'period': p.label,
            if (acc != null) 'account': store.accountName(acc),
            if (bank != null) 'bank': bank.shortName,
            if (type.isNotEmpty && type != 'all') 'type': type,
            if (cat != null) 'category': cat.name,
            if (uncategorized) 'category': 'Uncategorized',
            if (q.isNotEmpty) 'query': str('query'),
          },
        });

      case 'finance_add_transaction':
        final acc = accountArg() ?? s.accounts.where((x) => x.bankId == cashBankId).firstOrNull;
        final amount = num_('amount');
        if (amount == null || amount <= 0) return const ToolOutput({'error': 'amount must be a positive number.'});
        final t = await store.addTransaction(
          type: str('type') == 'income' ? 'CREDIT' : 'DEBIT',
          amount: amount,
          fee: num_('fee') ?? 0,
          accountId: acc?.id,
          time: _date(a['date']),
          counterparty: str('counterparty'),
          note: str('note'),
          category: categoryArg('category')?.key,
          adjustBalance: flag('adjust_balance', true),
        );
        s = store.current;
        return ToolOutput({'created': true, 'transaction': describeTransaction(store, s, t), if (s.account(t.accountId) != null) 'account': describeAccount(store, s, s.account(t.accountId)!)});

      case 'finance_update_transaction':
        final id = str('transaction_id');
        final before = s.transactions.where((t) => t.id == id).firstOrNull;
        if (before == null) return ToolOutput({'error': 'No transaction "$id". finance_transactions lists ids.'});
        final clear = str('category').toLowerCase() == 'none';
        final cat = clear ? null : categoryArg('category');
        final uncategorizedBefore = s.transactions.where((t) => t.category == null).length;
        final u = await store.updateTransaction(
          id,
          category: cat?.key,
          clearCategory: clear,
          note: a.containsKey('note') ? str('note') : null,
          counterparty: a.containsKey('counterparty') ? str('counterparty') : null,
          accountId: accountArg()?.id,
          amount: num_('amount'),
          type: str('type').isEmpty ? null : (str('type') == 'income' ? 'CREDIT' : 'DEBIT'),
          time: _date(a['date']),
          remember: flag('remember', false),
        );
        s = store.current;
        final also = uncategorizedBefore - s.transactions.where((t) => t.category == null).length - (before.category == null && cat != null ? 1 : 0);
        return ToolOutput({
          'updated': true,
          'transaction': describeTransaction(store, s, u!),
          if (flag('remember', false) && cat != null && u.counterparty.isNotEmpty) 'rule_saved': '${u.counterparty} → ${cat.name}',
          if (also > 0) 'also_categorized': also,
        });

      case 'finance_delete_transaction':
        final t = s.transactions.where((x) => x.id == str('transaction_id')).firstOrNull;
        if (t == null) return ToolOutput({'error': 'No transaction "${str('transaction_id')}".'});
        final desc = describeTransaction(store, s, t);
        await store.deleteTransaction(t.id);
        return ToolOutput({'deleted': true, 'transaction': desc});

      case 'finance_summary':
        final acc = accountArg();
        final p = period();
        final txs = acc == null ? s.transactions : s.transactions.where((t) => t.accountId == acc.id).toList();
        final sum = periodSummary(txs, p, categories: s.categoryMap, accountNames: names(), describe: (t) => describeTransaction(store, s, t));
        final trendAccounts = acc != null ? [acc] : s.accounts.where((x) => x.includeInTotals && !x.dormant).toList();
        final trend = balanceHistory(s.transactions, trendAccounts, from: p.from);
        final view = str('view').isEmpty ? 'cashflow' : str('view');
        final all = {
          ...sum,
          if (trend.values.length >= 2) 'balance_trend': {'values': trend.values, 'times': trend.times},
        };
        // Every view has the period's headline numbers; the rest is what
        // that view is about, so the card and the answer stay on it.
        const core = ['period', 'income', 'expense', 'net', 'transactions'];
        final keys = switch (view) {
          'spending' => ['fees', 'avg_daily_spend', 'series', 'previous', 'biggest_expense'],
          'categories' => ['categories'],
          'payees' => ['top_payees'],
          'income' => ['income_sources', 'top_payers', 'previous'],
          'balance' => ['balance_trend'],
          'cashflow' => ['savings_rate', 'series', 'previous', 'own_transfers'],
          _ => null,
        };
        return ToolOutput({
          'currency': cur,
          'view': view,
          if (acc != null) 'account': store.accountName(acc),
          if (keys == null) ...all else ...{for (final k in [...core, ...keys]) if (all.containsKey(k)) k: all[k]},
          if (view == 'balance' && trend.values.length < 2) 'note': 'Not enough balances reported by bank texts in this period to chart.',
        });

      case 'finance_insights':
        final acc = accountArg();
        final txs = acc == null ? s.transactions : s.transactions.where((t) => t.accountId == acc.id).toList();
        final view = str('view').isEmpty ? 'health' : str('view');
        final all = financeInsights(txs, s.categoryMap, describe: (t) => describeTransaction(store, s, t));
        final keys = switch (view) {
          'health' => ['health_score', 'grade', 'score_parts', 'savings_rate', 'categorized_share', 'tips'],
          'recurring' => ['recurring'],
          'unusual' => ['unusual_expenses', 'unusual_income'],
          'projection' => ['monthly', 'projection', 'months'],
          'budget' => ['budget_503020', 'essentials_ratio'],
          _ => null,
        };
        return ToolOutput({
          'currency': cur,
          'view': view,
          if (acc != null) 'account': store.accountName(acc),
          if (keys == null) ...all else ...{for (final k in keys) if (all.containsKey(k)) k: all[k]},
        });

      case 'finance_budgets':
        final want = str('category').toLowerCase();
        final cat = want.isEmpty || want == 'all' ? null : categoryArg('category');
        final status = budgetStatus(s.budgets, s.transactions, s.categoryMap);
        final list = want.isEmpty ? status : status.where((b) => b['category'] == cat?.key).toList();
        return ToolOutput({
          'currency': cur,
          'budgets': list,
          if (s.budgets.isEmpty) 'note': 'No budgets yet; finance_set_budget sets one.' else if (list.isEmpty) 'note': 'No budget for ${cat?.name ?? 'all spending'}; finance_set_budget sets one.',
        });

      case 'finance_set_budget':
        final cat = categoryArg('category');
        final per = str('period') == 'week' ? 'week' : 'month';
        if (flag('remove', false)) {
          final b = s.budgets.where((x) => x.category == cat?.key && x.period == per).firstOrNull;
          final removed = b != null && await store.removeBudget(b.id);
          s = store.current;
          return ToolOutput({'removed': removed, 'budgets': budgetStatus(s.budgets, s.transactions, s.categoryMap), 'currency': cur});
        }
        final limit = num_('limit');
        if (limit == null || limit <= 0) return const ToolOutput({'error': 'limit must be a positive number.'});
        final b = await store.setBudget(category: cat?.key, limit: limit, period: per);
        s = store.current;
        final all = budgetStatus(s.budgets, s.transactions, s.categoryMap);
        return ToolOutput({'saved': true, 'budget': all.firstWhere((x) => x['id'] == b.id), 'budgets': all, 'currency': cur});

      case 'finance_categories':
        final uncategorized = s.transactions.where((t) => t.category == null).length;
        return ToolOutput({
          'categories': [for (final c in s.categories) c.toJson()],
          'rules': [for (final e in s.rules.entries) {'counterparty': e.key, 'category': s.categoryMap[e.value]?.name ?? e.value}],
          'uncategorized': uncategorized,
        });

      case 'finance_categorize':
        final cp = str('counterparty');
        if (str('category').toLowerCase() == 'none') {
          await store.setRule(cp, null);
          return ToolOutput({'forgotten': true, 'counterparty': cp});
        }
        var cat = store.findCategory(str('category'));
        var created = false;
        if (cat == null) {
          if (!flag('create', false)) return ToolOutput({'error': 'No category "${str('category')}". Pass create true to make it, or pick one from finance_categories.'});
          cat = await store.addCategory(str('category'), income: flag('income', false), essential: flag('essential', false));
          created = true;
        }
        final n = await store.setRule(cp, cat.key);
        return ToolOutput({'categorized': n, 'counterparty': cp, 'category': cat.toJson(), if (created) 'created_category': true});

      case 'finance_update_patterns':
        if (flag('reset', false)) {
          await store.resetParser();
          return ToolOutput({'updated': true, 'changed': true, 'patterns': store.parser.toJson(), 'note': 'Back to the shipped patterns. The next finance_sync_sms re-reads older texts.'});
        }
        final r = await store.refreshParser(force: true);
        return ToolOutput({
          'updated': r.error == null,
          'changed': r.changed,
          'error': ?r.error,
          'patterns': r.config.toJson(),
          if (r.changed) 'note': 'New patterns in use. The next finance_sync_sms re-reads older texts they may now understand.',
        });

      case 'finance_verify_payment':
        var ref = str('reference').toUpperCase().replaceAll(RegExp(r'\s'), '');
        var url = str('receipt_url');
        String? fromQr;
        if (str('image').isNotEmpty) {
          if (!Device.supported) return const ToolOutput({'error': 'Reading a receipt\'s QR code needs the Android app; give the reference instead.'});
          final codes = await Qr.read(str('image'));
          final value = codes.map((c) => '${c['value'] ?? ''}').where((v) => v.isNotEmpty).firstOrNull;
          if (value == null) return const ToolOutput({'error': 'No QR code in that picture. Give the reference number from the receipt instead.'});
          fromQr = value;
          if (value.startsWith('http')) {
            url = value;
          } else if (ref.isEmpty) {
            ref = value.trim().toUpperCase();
          }
        }
        if (ref.isEmpty && url.isNotEmpty) {
          ref = RegExp(r'(?:id=|trx=|receipt/|rt/)([A-Za-z0-9]+)').firstMatch(url)?[1]?.toUpperCase() ?? '';
        }
        if (ref.isEmpty && url.isEmpty) return const ToolOutput({'error': 'Give the transaction reference, a receipt link, or a picture of the receipt\'s QR code.'});
        // What the user's own bank texts say about it.
        final local = ref.isEmpty
            ? null
            : s.transactions.where((t) => t.reference.toUpperCase().replaceAll(RegExp(r'\s'), '') == ref || (t.reference.length >= 8 && ref.startsWith(t.reference.toUpperCase()))).firstOrNull;
        if (url.isEmpty && (local?.link ?? '').startsWith('http')) url = local!.link!;
        final bankIds = {'cbe': 1, 'awash': 2, 'boa': 3, 'dashen': 4, 'zemen': 5, 'telebirr': 6, 'mpesa': 8, 'cbebirr': 37};
        var bank = str('bank').toLowerCase();
        if (bank.isEmpty || bank == 'auto') {
          bank = local == null ? PaymentVerifier.guessBank(ref) : (bankIds.entries.where((e) => e.value == local.bankId).firstOrNull?.key ?? 'unknown');
        }
        final suffixes = <String>[
          if (str('account').isNotEmpty) str('account'),
          for (final acc in s.accounts)
            if (acc.bankId == bankIds[bank] && !acc.number.contains('*')) acc.number,
        ];
        // Verify.ET first when its key is set (more banks, a receiver check,
        // and whether the receipt was used before); the bank's own page next.
        final vetKey = verifyEtKey();
        String? vetError;
        if (vetKey.isNotEmpty && a['direct'] != true) {
          final vetBank = switch (str('bank').toLowerCase()) {
            '' || 'auto' => bank == 'unknown' ? null : bank,
            final b => b,
          };
          final digits = str('account').replaceAll(RegExp(r'\D'), '');
          final own = [for (final acc in s.accounts) if (acc.bankId == bankIds[vetBank] && !acc.number.contains('*')) acc.number];
          try {
            final j = await VerifyEt(vetKey).verify(
              bank: vetBank,
              reference: url.isNotEmpty && ref.isEmpty ? url : (ref.isNotEmpty ? ref : url),
              suffix: digits.length >= 5 ? (vetBank == 'boa' ? digits.substring(digits.length - 5) : digits.substring(digits.length - (digits.length >= 8 ? 8 : digits.length))) : null,
              phone: str('phone').isEmpty ? null : str('phone'),
              settlementAccount: str('to_account').isNotEmpty ? str('to_account') : (own.length == 1 ? own.single : null),
            );
            final r = VerifyEt.result(j);
            final st = '${r['status'] ?? ''}';
            if (st == 'success' || r['verified'] == true || st == 'not_found') {
              final verified = r['verified'] == true || st == 'success';
              final match = r['settlementAccountMatch'] as Map?;
              final history = r['confirmationHistory'] as Map?;
              final cur2 = '${r['currency'] ?? cur}';
              final amount = (r['amount'] as num?)?.toDouble() ?? double.tryParse('${r['amount'] ?? ''}');
              final details = <String, String>{
                if (r['senderName'] != null) 'payer': '${r['senderName']}',
                if (r['senderAccount'] != null) 'payer_account': '${r['senderAccount']}',
                if (r['receiverName'] != null) 'receiver': '${r['receiverName']}',
                if (r['receiverAccount'] != null) 'receiver_account': '${r['receiverAccount']}',
                if (amount != null) 'amount': '${amount.toStringAsFixed(2)} $cur2',
                if (r['timestamp'] != null) 'date': '${r['timestamp']}'.replaceFirst('T', ' ').split('.').first,
                if (r['referenceNumber'] != null) 'reference': '${r['referenceNumber']}',
                if (r['receiptNumber'] != null) 'receipt_number': '${r['receiptNumber']}',
                if (r['reason'] != null) 'reason': '${r['reason']}',
                if (verified) 'status': 'Verified',
              };
              final expected = num_('expected_amount');
              final from = str('expected_from').toLowerCase();
              final seenBefore = history?['confirmedBefore'] == true;
              final matchOk = match?['matched'] == true;
              final matchKnown = match != null && match['reason'] != 'no_registered_accounts' && match['reason'] != 'verification_not_successful';
              final rBank = '${r['bank'] ?? vetBank ?? ''}';
              return ToolOutput({
                'status': verified ? 'verified' : 'not_found',
                'source': 'Verify.ET',
                'reference': ref.isNotEmpty ? ref : '${r['referenceNumber'] ?? r['receiptNumber'] ?? r['transactionNumber'] ?? url}',
                'bank': store.banks.where((b) => b.id == bankIds[rBank]).firstOrNull?.shortName ?? (rBank.isEmpty ? null : rBank.toUpperCase()),
                if (details.isNotEmpty) 'details': details,
                if (local != null)
                  'in_your_texts': {
                    'type': local.isCredit ? 'money in' : 'money out',
                    'amount': local.amount,
                    'counterparty': local.counterparty,
                    'account': names()[local.accountId] ?? local.accountMask,
                    'date': local.time.toIso8601String().substring(0, 16),
                    'currency': cur,
                  },
                if (matchKnown) 'receiver_match': {'matched': matchOk, 'confidence': match['matchConfidence'], 'account': match['matchedSettlementAccount'] ?? match['receiverAccount'], 'reason': match['reason']},
                if (history != null)
                  'history': {
                    'seen_before': seenBefore,
                    'times_confirmed': history['confirmationCount'],
                    'first_confirmed': history['firstConfirmedAt'],
                  },
                'checks': [
                  {'check': 'Verify.ET', 'ok': verified, 'note': verified ? 'Confirmed with ${rBank.isEmpty ? 'the bank' : rBank.toUpperCase()}' : '${r['message'] ?? 'No such transaction'}'},
                  if (history != null && verified) {'check': 'First time used', 'ok': !seenBefore, 'note': seenBefore ? 'Confirmed ${history['confirmationCount']} times before' : 'Never confirmed before'},
                  if (matchKnown) {'check': 'Paid to your account', 'ok': matchOk, 'note': matchOk ? 'Receiver ${match['receiverAccount'] ?? ''}' : 'Receiver ${match['receiverAccount'] ?? 'is someone else'}'},
                  if (local != null || ref.isNotEmpty) {'check': 'In your bank texts', 'ok': local != null, 'note': local == null ? 'No SMS of yours mentions it' : '${local.isCredit ? 'Received' : 'Sent'} ${local.amount.toStringAsFixed(2)} $cur'},
                  if (expected != null) {'check': 'Amount ${expected.toStringAsFixed(2)}', 'ok': amount != null && (amount - expected).abs() < 0.01, 'note': amount == null ? 'Amount unknown' : 'Shows ${amount.toStringAsFixed(2)}'},
                  if (from.isNotEmpty) {'check': 'From "${str('expected_from')}"', 'ok': '${r['senderName'] ?? ''}'.toLowerCase().contains(from), 'note': 'Payer: ${r['senderName'] ?? 'unknown'}'},
                ],
                'request_id': ?r['requestId'],
                'note': verified
                    ? (seenBefore ? 'Real receipt, but it was confirmed before: someone may be reusing an old receipt.' : 'The bank confirms this payment. Check the amount and receiver match what was claimed.')
                    : 'No transaction with that reference. It may be mistyped, too new, from another bank, or not real.',
              });
            }
            vetError = '${r['message'] ?? 'Verify.ET couldn\'t finish the check'}';
          } on VerifyEtException catch (e) {
            vetError = e.message;
          } catch (e) {
            vetError = 'Verify.ET didn\'t answer ($e)';
          }
        }
        final urls = url.isNotEmpty ? [Uri.parse(url)] : PaymentVerifier.receiptUrls(bank, ref, suffixes);
        final verifier = PaymentVerifier();
        Map<String, dynamic>? receipt;
        Uri? hit;
        var unreachable = 0;
        for (final u in urls) {
          try {
            receipt = await verifier.fetch(u);
            if (receipt != null) {
              hit = u;
              break;
            }
          } catch (_) {
            unreachable++;
          }
        }
        final fields = Map<String, String>.from((receipt?['fields'] as Map?) ?? const {});
        final expected = num_('expected_amount');
        final got = PaymentVerifier.amountOf(fields['amount']) ?? local?.amount;
        final from = str('expected_from').toLowerCase();
        final who = '${fields['payer'] ?? ''} ${local?.counterparty ?? ''}'.toLowerCase();
        final status = receipt != null
            ? 'verified'
            : urls.isNotEmpty && unreachable == urls.length
            ? 'unreachable'
            : local != null
            ? 'in_your_texts'
            : urls.isEmpty
            ? 'cannot_check'
            : 'not_found';
        final bankName = store.banks.where((b) => b.id == bankIds[bank]).firstOrNull?.shortName ?? (bank == 'unknown' ? null : bank.toUpperCase());
        return ToolOutput({
          'status': status,
          'reference': ref,
          'bank': ?bankName,
          'receipt_url': ?hit?.toString(),
          'format': ?receipt?['format'],
          'file_path': ?receipt?['file_path'],
          if (fields.isNotEmpty) 'details': fields,
          if (local != null)
            'in_your_texts': {
              'type': local.isCredit ? 'money in' : 'money out',
              'amount': local.amount,
              'counterparty': local.counterparty,
              'account': names()[local.accountId] ?? local.accountMask,
              'date': local.time.toIso8601String().substring(0, 16),
              'currency': cur,
            },
          'checks': [
            {'check': 'Bank receipt', 'ok': receipt != null, 'note': receipt != null ? 'Found on ${hit!.host}' : (status == 'unreachable' ? 'The bank\'s site didn\'t answer' : (urls.isEmpty ? 'No public receipt for this bank: needs its receipt link' : 'No receipt for that reference'))},
            if (local != null || ref.isNotEmpty) {'check': 'In your bank texts', 'ok': local != null, 'note': local == null ? 'No SMS of yours mentions it' : '${local.isCredit ? 'Received' : 'Sent'} ${local.amount.toStringAsFixed(2)} $cur'},
            if (expected != null) {'check': 'Amount ${expected.toStringAsFixed(2)}', 'ok': got != null && (got - expected).abs() < 0.01, 'note': got == null ? 'Amount unknown' : 'Shows ${got.toStringAsFixed(2)}'},
            if (from.isNotEmpty) {'check': 'From "${str('expected_from')}"', 'ok': who.contains(from), 'note': who.trim().isEmpty ? 'Payer unknown' : 'Payer: ${(fields['payer'] ?? local?.counterparty ?? '').trim()}'},
          ],
          if (fromQr != null) 'qr': fromQr,
          'tried': urls.length,
          'source': 'Bank receipt page',
          if (vetError != null) 'verify_et': vetError,
          'note': switch (status) {
            'verified' => 'The bank\'s own receipt exists for this reference. Compare the amount, receiver and date with what was claimed.',
            'unreachable' => 'The bank\'s receipt site didn\'t answer (it may only work on Ethiopian networks, or be down). Try again later.',
            'not_found' => bank == 'cbe' || bank == 'boa'
                ? 'No receipt found. CBE and BoA receipts need the right account: give account (the payer\'s or your account number).'
                : 'No receipt found for that reference: it may be mistyped, too new, or not real.',
            'in_your_texts' => 'Your bank texts show it, but the bank\'s receipt page couldn\'t confirm it.',
            _ => 'This bank has no public receipt page; give the receipt link from its SMS.',
          },
        });

      case 'finance_banks':
        return ToolOutput({'banks': [for (final b in store.banks) b.toJson()], 'patterns': store.parser.toJson()});
    }
    return ToolOutput({'error': 'Unknown finance tool $name'});
  } on ArgumentError catch (e) {
    return ToolOutput({'error': '${e.message}'});
  } on DeviceException catch (e) {
    return ToolOutput({'error': e.message});
  }
}
