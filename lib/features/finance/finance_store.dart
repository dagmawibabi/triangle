import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../device/device.dart';
import 'finance_models.dart';
import 'parser_config.dart';
import 'sms_parser.dart';

@immutable
class FinanceState {
  const FinanceState({
    this.accounts = const [],
    this.transactions = const [],
    this.customCategories = const [],
    this.rules = const {},
    this.budgets = const [],
    this.lastSync,
    this.currency = 'ETB',
    this.loaded = false,
    this.parser,
  });

  /// The banks and patterns in use, and where they came from.
  final ParserConfig? parser;

  final List<FinAccount> accounts;

  /// Newest first.
  final List<FinTransaction> transactions;
  final List<FinCategory> customCategories;

  /// Learned categories: a lowercased counterparty → a category key.
  final Map<String, String> rules;
  final List<FinBudget> budgets;
  final DateTime? lastSync;
  final String currency;
  final bool loaded;

  List<FinCategory> get categories => [...builtInCategories, ...customCategories];
  Map<String, FinCategory> get categoryMap => {for (final c in categories) c.key: c};

  FinAccount? account(String? id) => id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

  double get totalBalance => accounts.where((a) => a.includeInTotals && !a.dormant).fold(0.0, (s, a) => s + a.balance);

  FinanceState copyWith({
    List<FinAccount>? accounts,
    List<FinTransaction>? transactions,
    List<FinCategory>? customCategories,
    Map<String, String>? rules,
    List<FinBudget>? budgets,
    DateTime? lastSync,
    String? currency,
    ParserConfig? parser,
  }) => FinanceState(
    accounts: accounts ?? this.accounts,
    transactions: transactions ?? this.transactions,
    customCategories: customCategories ?? this.customCategories,
    rules: rules ?? this.rules,
    budgets: budgets ?? this.budgets,
    lastSync: lastSync ?? this.lastSync,
    currency: currency ?? this.currency,
    loaded: true,
    parser: parser ?? this.parser,
  );
}

/// What a check for newer patterns did.
class ParserUpdate {
  const ParserUpdate({required this.config, this.checked = false, this.changed = false, this.error});
  final ParserConfig config;

  /// The server was asked (not skipped as already checked recently).
  final bool checked;

  /// The download differs from what was in use.
  final bool changed;
  final String? error;
}

/// What a sync of the SMS inbox found.
class SyncReport {
  int scanned = 0;
  int bankMessages = 0;
  int added = 0;
  int duplicates = 0;
  int skipped = 0;
  final unparsed = <Map<String, dynamic>>[];
  final newAccounts = <FinAccount>[];
  final unmatched = <String, int>{};
  final addedIds = <String>[];
  final perBank = <int, int>{};
}

/// The user's money, on this phone: accounts, transactions (from bank SMS
/// parsed with Totals' patterns, or added by hand), categories, rules and
/// budgets, in finance.json.
class FinanceStore extends Notifier<FinanceState> {
  static const _uuid = Uuid();

  static const _empty = ParserConfig(banks: [cashBank, otherBank], patterns: [], source: 'bundled');
  ParserConfig _bundled = _empty;
  ParserConfig _config = _empty;

  /// When the server last answered with a valid set (kept in the cache
  /// file), and when a check last failed (this session only).
  DateTime? _checkedAt;
  DateTime? _failedAt;
  Future<ParserUpdate>? _refreshing;

  /// When the patterns in use last changed: the next sync after it re-reads
  /// older texts, which the new patterns may understand.
  DateTime? _changedAt;

  /// The state, for code outside the notifier (the tools).
  FinanceState get current => state;

  List<FinBank> get _banks => _config.banks;
  List<SmsPattern> get _patterns => _config.patterns;
  List<FinBank> get banks => _banks;
  List<SmsPattern> get patterns => _patterns;
  ParserConfig get parser => _config;

  FinBank bank(int id) => _banks.where((b) => b.id == id).firstOrNull ?? otherBank;

  /// A bank from its id, name, short name or SMS sender id.
  FinBank? findBank(Object? q) {
    if (q is num) return _banks.where((b) => b.id == q.toInt()).firstOrNull;
    final s = '${q ?? ''}'.trim().toLowerCase();
    if (s.isEmpty) return null;
    final id = int.tryParse(s);
    if (id != null) return _banks.where((b) => b.id == id).firstOrNull;
    String n(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final k = n(s);
    return _banks.where((b) => n(b.shortName) == k || n(b.name) == k || b.codes.any((c) => n(c) == k)).firstOrNull ??
        _banks.where((b) => n(b.name).contains(k) || (k.length >= 3 && k.contains(n(b.shortName)))).firstOrNull;
  }

  /// An account's display name: nickname, else bank and the last digits.
  String accountName(FinAccount a) {
    if (a.nickname.isNotEmpty) return a.nickname;
    final b = bank(a.bankId);
    final d = a.digits;
    return d.isEmpty ? b.shortName : '${b.shortName} ·${d.length > 4 ? d.substring(d.length - 4) : d}';
  }

  /// An account from its id, nickname, bank name or number ending.
  FinAccount? findAccount(Object? q) {
    final s = '${q ?? ''}'.trim().toLowerCase();
    if (s.isEmpty) return null;
    final list = state.accounts;
    return list.where((a) => a.id == s).firstOrNull ??
        list.where((a) => a.nickname.toLowerCase() == s || accountName(a).toLowerCase() == s).firstOrNull ??
        list.where((a) => s.replaceAll(RegExp(r'\D'), '').length >= 3 && a.digits.endsWith(s.replaceAll(RegExp(r'\D'), ''))).firstOrNull ??
        () {
          final b = findBank(s);
          if (b == null) return null;
          final of = list.where((a) => a.bankId == b.id).toList();
          return of.length == 1 ? of.first : of.where((a) => a.isDefault).firstOrNull ?? of.firstOrNull;
        }();
  }

  @override
  FinanceState build() {
    _load();
    return const FinanceState();
  }

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/finance.json');

  Future<File> _parserFile() async => File('${(await getApplicationSupportDirectory()).path}/finance_parser.json');

  /// The bundled banks and patterns, then the last download when it is
  /// still valid.
  Future<void> _loadAssets() async {
    try {
      _bundled = bundledParserConfig(await rootBundle.loadString('assets/finance/banks.json'), await rootBundle.loadString('assets/finance/sms_patterns.json'));
      _config = _bundled;
    } catch (e) {
      debugPrint('[Finance] assets: $e');
    }
    try {
      final f = await _parserFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _checkedAt = DateTime.tryParse('${j['checked_at'] ?? ''}');
      _changedAt = DateTime.tryParse('${j['changed_at'] ?? ''}');
      final c = decodeParserConfig('${j['banks']}', '${j['patterns']}', bundled: _bundled.patterns, fetchedAt: DateTime.tryParse('${j['fetched_at'] ?? ''}'));
      if (c != null) _config = c;
    } catch (e) {
      debugPrint('[Finance] parser cache: $e');
    }
  }

  /// Downloads the banks and patterns Totals publishes: at most once a day
  /// (three hours after a failure) unless [force]. A download that fails or
  /// doesn't pass [decodeParserConfig] leaves the patterns in use as they are.
  Future<ParserUpdate> refreshParser({bool force = false}) => _refreshing ??= _refreshParser(force).whenComplete(() => _refreshing = null);

  Future<ParserUpdate> _refreshParser(bool force) async {
    await ready();
    final now = DateTime.now();
    if (!force) {
      if (_failedAt != null && now.difference(_failedAt!) < const Duration(hours: 3)) return ParserUpdate(config: _config);
      if (_checkedAt != null && now.difference(_checkedAt!) < const Duration(days: 1)) return ParserUpdate(config: _config);
    }
    try {
      final client = http.Client();
      final http.Response banks, patterns;
      try {
        (banks, patterns) = await (
          client.get(Uri.parse(remoteBanksUrl)).timeout(const Duration(seconds: 15)),
          client.get(Uri.parse(remotePatternsUrl)).timeout(const Duration(seconds: 15)),
        ).wait;
      } finally {
        client.close();
      }
      if (banks.statusCode != 200 || patterns.statusCode != 200) {
        throw HttpException('the pattern server answered ${banks.statusCode} / ${patterns.statusCode}');
      }
      final c = decodeParserConfig(banks.body, patterns.body, bundled: _bundled.patterns, fetchedAt: now);
      if (c == null) throw const FormatException('the downloaded files were incomplete or not in the expected format, so the current patterns were kept');
      String sig(ParserConfig x) => '${x.banks.map((b) => '${b.id}${b.codes}').join()}|${x.patterns.map((p) => '${p.bankId}${p.type}${p.regex}').join()}';
      final changed = sig(c) != sig(_config);
      _config = c;
      _checkedAt = now;
      _failedAt = null;
      if (changed) _changedAt = now;
      await (await _parserFile()).writeAsString(
        jsonEncode({
          'fetched_at': now.toIso8601String(),
          'checked_at': now.toIso8601String(),
          if (_changedAt != null) 'changed_at': _changedAt!.toIso8601String(),
          'banks': banks.body,
          'patterns': patterns.body,
        }),
      );
      state = state.copyWith(parser: _config);
      return ParserUpdate(config: _config, checked: true, changed: changed);
    } catch (e) {
      _failedAt = now;
      debugPrint('[Finance] parser update: $e');
      final error = switch (e) {
        TimeoutException() || SocketException() || http.ClientException() => 'Couldn\'t reach the pattern server; the current patterns stay in use.',
        HttpException(:final message) || FormatException(:final message) => message,
        _ => '$e',
      };
      return ParserUpdate(config: _config, checked: true, error: error);
    }
  }

  /// Back to the patterns the app shipped with, dropping the download.
  Future<void> resetParser() async {
    _config = _bundled;
    _checkedAt = null;
    _changedAt = DateTime.now();
    try {
      final f = await _parserFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    state = state.copyWith(parser: _config);
  }

  Future<void> _load() async {
    await _loadAssets();
    try {
      final f = await _file();
      if (!await f.exists()) {
        state = state.copyWith(parser: _config);
        return;
      }
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      List<Map<String, dynamic>> list(String k) => [for (final x in (j[k] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      state = FinanceState(
        accounts: [for (final x in list('accounts')) FinAccount.fromJson(x)],
        transactions: [for (final x in list('transactions')) FinTransaction.fromJson(x)]..sort((a, b) => b.time.compareTo(a.time)),
        customCategories: [for (final x in list('categories')) FinCategory.fromJson(x)],
        rules: {for (final e in (j['rules'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
        budgets: [for (final x in list('budgets')) FinBudget.fromJson(x)],
        lastSync: DateTime.tryParse('${j['last_sync'] ?? ''}'),
        currency: '${j['currency'] ?? 'ETB'}',
        loaded: true,
        parser: _config,
      );
    } catch (e) {
      debugPrint('[Finance] load: $e');
      state = state.copyWith(parser: _config);
    }
  }

  /// Waits for the file and assets to be read.
  Future<FinanceState> ready() async {
    for (var i = 0; i < 100 && !state.loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return state;
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'version': 1,
          'currency': state.currency,
          if (state.lastSync != null) 'last_sync': state.lastSync!.toIso8601String(),
          'accounts': [for (final a in state.accounts) a.toJson()],
          'transactions': [for (final t in state.transactions) t.toJson()],
          'categories': [for (final c in state.customCategories) c.toJson()],
          'rules': state.rules,
          'budgets': [for (final b in state.budgets) b.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('[Finance] save: $e');
    }
  }

  // ---- accounts --------------------------------------------------------------

  Future<FinAccount> addAccount({
    required int bankId,
    String number = '',
    String holder = '',
    String nickname = '',
    double balance = 0,
    bool includeInTotals = true,
    bool isDefault = false,
    bool detected = false,
  }) async {
    await ready();
    final first = !state.accounts.any((a) => a.bankId == bankId);
    final a = FinAccount(
      id: 'acc_${_uuid.v4().substring(0, 8)}',
      bankId: bankId,
      number: number.trim(),
      holder: holder.trim(),
      nickname: nickname.trim(),
      balance: balance,
      includeInTotals: includeInTotals,
      isDefault: isDefault || first,
      detected: detected,
      createdAt: DateTime.now(),
      balanceAt: balance != 0 ? DateTime.now() : null,
    );
    var list = [...state.accounts, a];
    if (a.isDefault) list = [for (final x in list) x.id != a.id && x.bankId == bankId && x.isDefault ? x.copyWith(isDefault: false) : x];
    state = state.copyWith(accounts: list);
    // Messages from this bank that had nowhere to go now do.
    if (!detected) await _adoptOrphans(a);
    await _save();
    return state.account(a.id)!;
  }

  Future<void> _adoptOrphans(FinAccount a) async {
    final b = bank(a.bankId);
    final txs = [
      for (final t in state.transactions)
        if (t.accountId == null && t.bankId == a.bankId && matchAccount(ParsedSms(bankId: t.bankId, type: t.type, amount: t.amount, pattern: '')..account = t.accountMask, [a], b) != null)
          t.copyWith(accountId: a.id)
        else
          t,
    ];
    state = state.copyWith(transactions: txs);
    _refreshBalance(a.id);
  }

  Future<FinAccount?> updateAccount(
    String id, {
    int? bankId,
    String? number,
    String? holder,
    String? nickname,
    double? balance,
    bool? includeInTotals,
    bool? dormant,
    bool? isDefault,
  }) async {
    await ready();
    final a = state.account(id);
    if (a == null) return null;
    final u = a.copyWith(
      bankId: bankId,
      number: number?.trim(),
      holder: holder?.trim(),
      nickname: nickname?.trim(),
      balance: balance,
      balanceAt: balance != null ? DateTime.now() : null,
      includeInTotals: includeInTotals,
      dormant: dormant,
      isDefault: isDefault,
      detected: false,
    );
    state = state.copyWith(
      accounts: [
        for (final x in state.accounts)
          if (x.id == id)
            u
          else if (u.isDefault && x.bankId == u.bankId && x.isDefault)
            x.copyWith(isDefault: false)
          else
            x,
      ],
    );
    await _save();
    return u;
  }

  /// Removes an account; its transactions go too, or stay without one.
  Future<(FinAccount, int)?> deleteAccount(String id, {bool withTransactions = false}) async {
    await ready();
    final a = state.account(id);
    if (a == null) return null;
    final mine = state.transactions.where((t) => t.accountId == id).length;
    state = state.copyWith(
      accounts: state.accounts.where((x) => x.id != id).toList(),
      transactions: withTransactions
          ? state.transactions.where((t) => t.accountId != id).toList()
          : [for (final t in state.transactions) t.accountId == id ? t.copyWith(clearAccount: true) : t],
    );
    await _save();
    return (a, mine);
  }

  /// Sets the account's balance from its newest SMS that reported one, when
  /// that's newer than the balance it has.
  void _refreshBalance(String id) {
    final a = state.account(id);
    if (a == null) return;
    final latest = state.transactions.where((t) => t.accountId == id && t.balanceAfter != null).fold<FinTransaction?>(null, (b, t) => b == null || t.time.isAfter(b.time) ? t : b);
    if (latest == null || (a.balanceAt != null && !latest.time.isAfter(a.balanceAt!))) return;
    state = state.copyWith(accounts: [for (final x in state.accounts) x.id == id ? x.copyWith(balance: latest.balanceAfter, balanceAt: latest.time) : x]);
  }

  // ---- transactions -----------------------------------------------------------

  String? _categoryFor(String counterparty, bool income, String body) {
    final k = counterparty.trim().toLowerCase();
    if (k.isNotEmpty && state.rules.containsKey(k)) {
      final c = state.rules[k]!;
      if (state.categoryMap[c]?.income == income || c == 'transfer') return c;
    }
    return guessCategory(income: income, counterparty: counterparty, body: body);
  }

  /// Records a transaction by hand. With [adjustBalance] the account's
  /// balance moves by it.
  Future<FinTransaction> addTransaction({
    required String type,
    required double amount,
    String? accountId,
    int? bankId,
    DateTime? time,
    String counterparty = '',
    String note = '',
    String? category,
    double fee = 0,
    bool adjustBalance = true,
  }) async {
    await ready();
    final a = state.account(accountId);
    final credit = type.toUpperCase() == 'CREDIT';
    final t = FinTransaction(
      id: 'tx_${_uuid.v4().substring(0, 12)}',
      accountId: a?.id,
      bankId: a?.bankId ?? bankId ?? cashBankId,
      type: credit ? 'CREDIT' : 'DEBIT',
      amount: amount.abs(),
      fee: fee.abs(),
      time: time ?? DateTime.now(),
      reference: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      counterparty: counterparty.trim(),
      note: note.trim(),
      category: category ?? _categoryFor(counterparty, credit, note),
      source: 'manual',
    );
    var accounts = state.accounts;
    if (a != null && adjustBalance) {
      final nb = a.balance + (credit ? t.amount : -(t.amount + t.fee));
      accounts = [for (final x in accounts) x.id == a.id ? x.copyWith(balance: (nb * 100).roundToDouble() / 100, balanceAt: DateTime.now()) : x];
    }
    state = state.copyWith(accounts: accounts, transactions: [t, ...state.transactions]..sort((a, b) => b.time.compareTo(a.time)));
    await _save();
    return t;
  }

  /// Changes a transaction. With [remember] its counterparty's future
  /// transactions get the same category.
  Future<FinTransaction?> updateTransaction(
    String id, {
    String? category,
    bool clearCategory = false,
    String? note,
    String? counterparty,
    String? accountId,
    double? amount,
    String? type,
    DateTime? time,
    bool remember = false,
  }) async {
    await ready();
    final t = state.transactions.where((x) => x.id == id).firstOrNull;
    if (t == null) return null;
    final u = t.copyWith(category: category, clearCategory: clearCategory, note: note, counterparty: counterparty, accountId: accountId, amount: amount?.abs(), type: type, time: time);
    var rules = state.rules;
    var txs = [for (final x in state.transactions) x.id == id ? u : x];
    if (remember && category != null && u.counterparty.trim().isNotEmpty) {
      final k = u.counterparty.trim().toLowerCase();
      rules = {...rules, k: category};
      // Apply it to the counterparty's uncategorized transactions as well.
      txs = [for (final x in txs) x.category == null && x.counterparty.trim().toLowerCase() == k && x.type == u.type ? x.copyWith(category: category) : x];
    }
    txs.sort((a, b) => b.time.compareTo(a.time));
    state = state.copyWith(transactions: txs, rules: rules);
    await _save();
    return u;
  }

  /// Files every transaction with [counterparty] under [category] and
  /// remembers it for new ones. How many changed.
  Future<int> setRule(String counterparty, String? category) async {
    await ready();
    final k = counterparty.trim().toLowerCase();
    if (k.isEmpty) return 0;
    final rules = {...state.rules};
    var n = 0;
    final txs = state.transactions;
    if (category == null) {
      rules.remove(k);
    } else {
      rules[k] = category;
    }
    final updated = [
      for (final x in txs)
        if (category != null && x.counterparty.trim().toLowerCase() == k && x.category != category)
          (() {
            n++;
            return x.copyWith(category: category);
          })()
        else
          x,
    ];
    state = state.copyWith(rules: rules, transactions: updated);
    await _save();
    return n;
  }

  Future<FinTransaction?> deleteTransaction(String id) async {
    await ready();
    final t = state.transactions.where((x) => x.id == id).firstOrNull;
    if (t == null) return null;
    state = state.copyWith(transactions: state.transactions.where((x) => x.id != id).toList());
    await _save();
    return t;
  }

  // ---- categories & budgets -------------------------------------------------

  Future<FinCategory> addCategory(String name, {bool income = false, bool essential = false, String icon = 'more'}) async {
    await ready();
    var key = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (key.isEmpty) key = 'custom';
    while (state.categoryMap.containsKey(key)) {
      key = '${key}_2';
    }
    final c = FinCategory(key, name.trim(), income: income, essential: essential, icon: icon, custom: true);
    state = state.copyWith(customCategories: [...state.customCategories, c]);
    await _save();
    return c;
  }

  /// The category [q] names: its key or name, ignoring case.
  FinCategory? findCategory(Object? q) {
    final s = '${q ?? ''}'.trim().toLowerCase();
    if (s.isEmpty) return null;
    final cats = state.categories;
    return cats.where((c) => c.key == s || c.name.toLowerCase() == s).firstOrNull ??
        cats.where((c) => c.name.toLowerCase().startsWith(s) || c.key.startsWith(s.replaceAll(' ', '_'))).firstOrNull;
  }

  Future<FinBudget> setBudget({String? category, required double limit, String period = 'month'}) async {
    await ready();
    final existing = state.budgets.where((b) => b.category == category && b.period == period).firstOrNull;
    final b = FinBudget(id: existing?.id ?? 'bud_${_uuid.v4().substring(0, 8)}', category: category, limit: limit, period: period);
    state = state.copyWith(budgets: [for (final x in state.budgets) if (x.id != b.id) x, b]);
    await _save();
    return b;
  }

  Future<bool> removeBudget(String id) async {
    await ready();
    final before = state.budgets.length;
    state = state.copyWith(budgets: state.budgets.where((b) => b.id != id && b.category != id).toList());
    await _save();
    return state.budgets.length != before;
  }

  Future<void> setCurrency(String code) async {
    state = state.copyWith(currency: code.trim().toUpperCase());
    await _save();
  }

  Future<void> clear() async {
    state = FinanceState(currency: state.currency, loaded: true, parser: _config);
    await _save();
  }

  // ---- SMS --------------------------------------------------------------------

  ParsedSms? parse(String body, {String? sender, int? bankId}) => parseBankSms(body, sender, banks: _banks, patterns: _patterns, bankId: bankId);

  /// Reads the SMS inbox from [since] (by default the last sync, or 180
  /// days back the first time), parses every bank message with Totals'
  /// patterns and records the new ones. Accounts named in messages that
  /// the user hasn't added are created when [createAccounts] is on.
  Future<SyncReport> syncSms({DateTime? since, int limit = 3000, bool createAccounts = true}) async {
    await ready();
    // Newer patterns first, when the day's check is due; offline is fine.
    await refreshParser();
    final report = SyncReport();
    final last = state.lastSync;
    // After a pattern change, go back the full window: texts the old
    // patterns didn't understand may parse now, and ones already recorded
    // are skipped by their SMS id.
    final rescan = _changedAt != null && last != null && _changedAt!.isAfter(last);
    final from = since ?? (rescan ? null : last?.subtract(const Duration(days: 2))) ?? DateTime.now().subtract(const Duration(days: 180));
    final rows = Device.list(await Device.call<List>('sms', {'box': 'inbox', 'limit': limit, 'bulk': true, 'since': from.millisecondsSinceEpoch}));
    report.scanned = rows.length;
    final known = {for (final t in state.transactions) '${t.bankId}|${t.reference}'};
    final seenSms = {for (final t in state.transactions) if (t.smsId != null) t.smsId!};
    var accounts = [...state.accounts];
    final added = <FinTransaction>[];
    // Oldest first, so balances end on the newest.
    for (final m in rows.reversed) {
      final sender = '${m['address'] ?? ''}';
      final body = '${m['body'] ?? ''}';
      final bank = bankForSender(sender, _banks);
      if (bank == null) continue;
      report.bankMessages++;
      final smsId = '${m['id']}';
      if (seenSms.contains(smsId)) {
        report.duplicates++;
        continue;
      }
      final time = m['date'] is num ? DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()) : DateTime.now();
      final p = parseBankSms(body, sender, banks: _banks, patterns: _patterns);
      if (p == null) {
        if (isNonLedgerSms(body)) {
          report.skipped++;
        } else if (RegExp(r'\d[\d,]*\.\d{2}|ETB|Birr|ብር', caseSensitive: false).hasMatch(body)) {
          // Looks like money but no pattern knows it.
          if (report.unparsed.length < 6) report.unparsed.add({'bank': bank.shortName, 'date': time.toIso8601String().substring(0, 16), 'text': body.length > 160 ? '${body.substring(0, 160)}…' : body});
          report.unmatched[bank.shortName] = (report.unmatched[bank.shortName] ?? 0) + 1;
        } else {
          report.skipped++;
        }
        continue;
      }
      final reference = p.reference ?? 'sms_$smsId';
      final key = '${p.bankId}|$reference';
      if (known.contains(key)) {
        report.duplicates++;
        continue;
      }
      known.add(key);
      var acc = matchAccount(p, accounts, bank);
      if (acc == null && createAccounts) {
        final first = !accounts.any((a) => a.bankId == p.bankId);
        acc = FinAccount(
          id: 'acc_${_uuid.v4().substring(0, 8)}',
          bankId: p.bankId,
          number: p.account ?? '',
          isDefault: first,
          detected: true,
          createdAt: DateTime.now(),
        );
        accounts.add(acc);
        report.newAccounts.add(acc);
      }
      final t = FinTransaction(
        id: 'tx_${_uuid.v4().substring(0, 12)}',
        accountId: acc?.id,
        bankId: p.bankId,
        type: p.type,
        amount: p.amount,
        fee: ((p.serviceCharge + p.vat) * 100).roundToDouble() / 100,
        balanceAfter: p.balance,
        time: time,
        reference: reference,
        counterparty: p.counterparty,
        category: _categoryFor(p.counterparty, p.type == 'CREDIT', body),
        source: 'sms',
        smsId: smsId,
        accountMask: p.account,
        link: p.link,
      );
      added.add(t);
      report.addedIds.add(t.id);
      report.perBank[p.bankId] = (report.perBank[p.bankId] ?? 0) + 1;
    }
    report.added = added.length;
    state = state.copyWith(
      accounts: accounts,
      transactions: [...added, ...state.transactions]..sort((a, b) => b.time.compareTo(a.time)),
      lastSync: DateTime.now(),
    );
    for (final id in {for (final t in added) if (t.accountId != null) t.accountId!}) {
      _refreshBalance(id);
    }
    await _save();
    return report;
  }
}

final financeStoreProvider = NotifierProvider<FinanceStore, FinanceState>(FinanceStore.new);
