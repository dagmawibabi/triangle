import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/finance_result_cards.dart';
import 'package:teleai/features/finance/finance_insights.dart';
import 'package:teleai/features/finance/finance_models.dart';
import 'package:teleai/features/finance/finance_store.dart';
import 'package:teleai/features/finance/finance_tools.dart';
import 'package:teleai/features/finance/parser_config.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart' show ToolOutput;
import 'package:teleai/features/finance/sms_parser.dart';

void main() {
  final banks = [
    for (final b in (jsonDecode(File('assets/finance/banks.json').readAsStringSync())['banks'] as List)) FinBank.fromJson(Map<String, dynamic>.from(b)),
    cashBank,
    otherBank,
  ];
  final patterns = [
    for (final p in (jsonDecode(File('assets/finance/sms_patterns.json').readAsStringSync())['patterns'] as List)) SmsPattern.fromJson(Map<String, dynamic>.from(p)),
  ];
  ParsedSms? parse(String body, String sender) => parseBankSms(body, sender, banks: banks, patterns: patterns);

  group('SMS parsing with Totals patterns', () {
    test('every bundled pattern compiles as a Dart RegExp', () {
      final bad = <String>[];
      for (final p in patterns) {
        try {
          RegExp(p.regex, caseSensitive: false, multiLine: true, dotAll: true);
        } catch (_) {
          bad.add(p.description);
        }
      }
      expect(bad, isEmpty);
      expect(patterns.length, greaterThan(50));
    });

    test('senders resolve to their bank, exact codes first', () {
      expect(bankForSender('CBE', banks)?.shortName, 'CBE');
      expect(bankForSender('CBE Birr', banks)?.shortName, 'CBE Birr');
      expect(bankForSender('127', banks)?.shortName, 'Telebirr');
      expect(bankForSender('DashenBank', banks)?.shortName, 'Dashen');
      expect(bankForSender('+251911223344', banks), isNull);
    });

    test('reads a Telebirr ATM withdrawal: amount, fee, balance, reference', () {
      const body = '''Dear EYOSIAS
The request to withdraw ETB 1,000.00 from your telebirr account 251957063583 via secret code 671826 on 2025-06-28 15:15:39 using Bank of Abyssinia ATM with transaction number CFS07I3GTC is successfully completed. The service fee (including 15% VAT) is ETB 5.75. Your current Account balance is ETB 90.82. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/CFS07I3GTC
Thank you for using telebirr''';
      final p = parse(body, '127');
      expect(p, isNotNull);
      expect(p!.bankId, 6);
      expect(p.type, 'DEBIT');
      expect(p.amount, 1000.0);
      expect(p.balance, 90.82);
      expect(p.reference, 'CFS07I3GTC');
      expect(p.link, startsWith('https://transactioninfo.ethiotelecom.et/receipt/'));
    });

    test('reads a Dashen credit and keeps the masked account ending', () {
      const body = '''Dear Customer, You have received ETB 51,450.00 from
telebirr account number 251943685872 Ref No:2603092000308528 on 09/03/2026
08:23:58 AM to your bank account '5107*****011'. Your account balance
is ETB 51,509.06.''';
      final p = parse(body, 'DashenBank');
      expect(p, isNotNull);
      expect(p!.type, 'CREDIT');
      expect(p.amount, 51450.0);
      expect(p.balance, 51509.06);
      expect(p.account, endsWith('011'));
    });

    test('ignores texts where no money moved and unknown senders', () {
      expect(parse('Your telebirr ATM withdrawal secret code is 123456. Valid for 30 minutes.', '127'), isNull);
      expect(parse('You have received ETB 50.00 airtime from 251920945085 on 14/04/2026 11:13:19. Your transaction number is DDE12AB34C.', '127'), isNull);
      expect(parse('Your OTP is 4455', 'CBE'), isNull);
      expect(parse('Lunch at 1?', '+251911000000'), isNull);
    });

    test('matches a message to the account whose number ends with the visible digits', () {
      final cbe = banks.firstWhere((b) => b.id == 1);
      final a = FinAccount(id: 'a', bankId: 1, number: '1000123456789', createdAt: DateTime(2026));
      final b = FinAccount(id: 'b', bankId: 1, number: '1000555500123', createdAt: DateTime(2026), isDefault: true);
      final p = ParsedSms(bankId: 1, type: 'DEBIT', amount: 10, pattern: '')..account = '789';
      expect(matchAccount(p, [a, b], cbe)?.id, 'a');
      // A number neither account has: nowhere to go.
      expect(matchAccount(ParsedSms(bankId: 1, type: 'DEBIT', amount: 10, pattern: '')..account = '1*****444', [a, b], cbe), isNull);
      // No number at all: the default.
      expect(matchAccount(ParsedSms(bankId: 1, type: 'DEBIT', amount: 10, pattern: ''), [a, b], cbe)?.id, 'b');
    });

    test('guesses common categories', () {
      expect(guessCategory(income: false, counterparty: 'Ethio telecom', body: 'airtime recharge'), 'airtime');
      expect(guessCategory(income: true, counterparty: 'ACME PLC', body: 'Salary for May'), 'salary');
      expect(guessCategory(income: false, counterparty: 'Abebe', body: 'You have transferred ETB 50'), isNull);
    });
  });

  group('Downloaded patterns', () {
    final banksBody = File('assets/finance/banks.json').readAsStringSync();
    final patternsBody = File('assets/finance/sms_patterns.json').readAsStringSync();

    test('a complete set is accepted, with Cash and Other added', () {
      final c = decodeParserConfig(banksBody, patternsBody, bundled: patterns, fetchedAt: DateTime(2026, 11, 11));
      expect(c, isNotNull);
      expect(c!.source, 'downloaded');
      expect(c.patterns.length, patterns.length);
      expect(c.banks.map((b) => b.id), containsAll([1, 6, cashBankId, otherBankId]));
    });

    test('the JS-wrapped form Totals accepts is read too', () {
      final c = decodeParserConfig('export const banks = $banksBody;', 'const patterns = $patternsBody', bundled: patterns);
      expect(c, isNotNull);
    });

    test('truncated, empty or broken files leave the current patterns alone', () {
      final few = jsonEncode({'patterns': (jsonDecode(patternsBody)['patterns'] as List).take(5).toList()});
      expect(decodeParserConfig(banksBody, few, bundled: patterns), isNull);
      expect(decodeParserConfig(banksBody, '<html>502 Bad Gateway</html>', bundled: patterns), isNull);
      expect(decodeParserConfig('{"banks": []}', patternsBody, bundled: patterns), isNull);
      expect(decodeParserConfig(banksBody, patternsBody.substring(0, patternsBody.length ~/ 2), bundled: patterns), isNull);
    });

    test('patterns that don\'t compile are dropped, and bundled overrides win', () {
      final list = [...(jsonDecode(patternsBody)['patterns'] as List)];
      list.add({'bankId': 1, 'regex': '(?<amount>[', 'type': 'DEBIT', 'description': 'broken'});
      final i = list.indexWhere((p) => '${p['bankId']}|${'${p['description']}'.toLowerCase()}' == '4|dashen telebirr credit');
      list[i] = {...list[i] as Map, 'regex': 'never matches anything'};
      final c = decodeParserConfig(banksBody, jsonEncode({'patterns': list}), bundled: patterns)!;
      expect(c.dropped, 1);
      expect(c.patterns.where((p) => p.description == 'broken'), isEmpty);
      final override = c.patterns.firstWhere((p) => p.description.toLowerCase() == 'dashen telebirr credit');
      expect(override.regex, isNot('never matches anything'));
    });
  });

  group('Analysis', () {
    final now = DateTime(2026, 11, 20, 12);
    FinTransaction tx(String id, String type, double amount, DateTime t, {String? acc = 'a', String who = '', String? cat, double fee = 0, double? bal}) =>
        FinTransaction(id: id, bankId: 1, type: type, amount: amount, time: t, reference: id, accountId: acc, counterparty: who, category: cat, fee: fee, balanceAfter: bal);
    final txs = [
      tx('s1', 'CREDIT', 20000, DateTime(2026, 11, 1), who: 'ACME', cat: 'salary', bal: 25000),
      tx('g1', 'DEBIT', 1500, DateTime(2026, 11, 3), who: 'Shoa', cat: 'groceries', fee: 2.3, bal: 23497.7),
      tx('r1', 'DEBIT', 8000, DateTime(2026, 11, 5), who: 'Landlord', cat: 'rent', bal: 15497.7),
      // A transfer between the user's own accounts, out of a and into b.
      tx('t1', 'DEBIT', 3000, DateTime(2026, 11, 6, 9, 0), bal: 12497.7),
      tx('t2', 'CREDIT', 3000, DateTime(2026, 11, 6, 9, 4), acc: 'b'),
      tx('o1', 'DEBIT', 900, DateTime(2026, 10, 12), who: 'Shoa', cat: 'groceries'),
    ];
    final cats = {for (final c in builtInCategories) c.key: c};

    test('own transfers are paired and left out of income and spending', () {
      expect(ownTransfers(txs), {'t1', 't2'});
      final s = periodSummary(txs, FinPeriod.resolve('this_month', now: now), categories: cats);
      expect(s['income'], 20000);
      expect(s['expense'], 9502.3);
      expect(s['fees'], 2.3);
      expect(s['net'], 10497.7);
      expect(s['own_transfers'], 2);
      expect((s['categories'] as List).first['key'], 'rent');
      expect((s['previous'] as Map)['expense'], 900);
      expect((s['series'] as Map)['bucket'], 'day');
    });

    test('budgets count this period\'s spending in the category', () {
      final b = budgetStatus([const FinBudget(id: 'x', category: 'groceries', limit: 1000)], txs, cats, now: now).single;
      expect(b['spent'], 1502.3);
      expect(b['over'], isTrue);
    });

    test('insights score, recurring and projection', () {
      final more = [
        ...txs,
        for (var i = 0; i < 4; i++) tx('e$i', 'DEBIT', 200, DateTime(2026, 7 + i, 2), who: 'Ethio Telecom', cat: 'airtime'),
      ];
      final i = financeInsights(more, cats);
      expect(i['health_score'], inInclusiveRange(1, 100));
      expect((i['recurring'] as List).map((r) => r['label']), contains('Ethio Telecom'));
      expect((i['recurring'] as List).firstWhere((r) => r['label'] == 'Ethio Telecom')['every'], 'monthly');
      expect(i['projection'], isA<Map>());
    });

    test('balance history follows the reported balances', () {
      final h = balanceHistory(txs, [FinAccount(id: 'a', bankId: 1, createdAt: DateTime(2026), balance: 12497.7)]);
      expect(h.values.last, 12497.7);
      expect(h.values.first, 25000);
    });
  });

  testWidgets('tools return only what was asked for', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final run = FutureProvider.family<ToolOutput, (String, Map<String, dynamic>)>((ref, a) => runFinanceTool(ref, a.$1, a.$2));
    Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async => (await tester.runAsync(() => c.read(run((name, args)).future)))!.json;
    await tester.runAsync(() async {
      final s = c.read(financeStoreProvider.notifier);
      await s.ready();
      final cbe = await s.addAccount(bankId: 1, number: '1000123456789', balance: 500);
      await s.addAccount(bankId: 6, number: '251911223344', balance: 70);
      await s.addTransaction(type: 'DEBIT', amount: 40, accountId: cbe.id, counterparty: 'Shoa', category: 'groceries', adjustBalance: false);
      await s.addTransaction(type: 'CREDIT', amount: 900, accountId: cbe.id, counterparty: 'ACME', category: 'salary', adjustBalance: false);
    });

    final one = await call('finance_accounts', {'account_id': 'CBE'});
    expect(one['count'], 1);
    expect(one['total_balance'], 500);
    expect(one['filtered'], isTrue);
    expect((await call('finance_accounts', {}))['count'], 2);

    final spending = await call('finance_summary', {'view': 'spending'});
    expect(spending['view'], 'spending');
    expect(spending.containsKey('categories'), isFalse);
    expect(spending.containsKey('series'), isTrue);
    final cats = await call('finance_summary', {'view': 'categories'});
    expect(cats.containsKey('series'), isFalse);
    expect((cats['categories'] as List).single['key'], 'groceries');
    expect((await call('finance_summary', {'view': 'all'})).containsKey('top_payees'), isTrue);

    final recurring = await call('finance_insights', {'view': 'recurring'});
    expect(recurring.containsKey('health_score'), isFalse);
    expect(financeResultFor(ToolPart(callId: 'r', name: 'finance_insights'), recurring), isNotNull);
  });

  testWidgets('finance cards render', (tester) async {
    ToolPart part(String name) => ToolPart(callId: name, name: name);
    final now = DateTime.now();
    final txs = [
      FinTransaction(id: '1', bankId: 1, type: 'CREDIT', amount: 5000, time: now.subtract(const Duration(days: 2)), reference: '1', accountId: 'a', counterparty: 'ACME', category: 'salary', balanceAfter: 6000),
      FinTransaction(id: '2', bankId: 1, type: 'DEBIT', amount: 700, time: now.subtract(const Duration(days: 1)), reference: '2', accountId: 'a', counterparty: 'Shoa', category: 'groceries', balanceAfter: 5300),
    ];
    final cats = {for (final c in builtInCategories) c.key: c};
    final summary = periodSummary(txs, FinPeriod.resolve('last_7_days'), categories: cats);
    final account = {'id': 'a', 'name': 'CBE ·6789', 'bank': 'CBE', 'colors': ['#1b0b2e', '#3a0f5c'], 'number_ending': '6789', 'balance': 5300, 'month_in': 5000, 'month_out': 700};
    final row = {'id': '2', 'date': now.toIso8601String(), 'type': 'expense', 'amount': 700, 'account': 'CBE ·6789', 'counterparty': 'Shoa', 'category_name': 'Groceries', 'icon': 'cart'};
    final cards = [
      financeResultFor(part('finance_overview'), {'currency': 'ETB', 'total_balance': 5300, 'accounts': [account], 'summary': summary, 'budgets': [], 'recent': [row]}),
      financeResultFor(part('finance_summary'), {'currency': 'ETB', ...summary, 'balance_trend': {'values': [6000, 5300], 'times': [for (final t in txs) t.time.millisecondsSinceEpoch]}}),
      financeResultFor(part('finance_insights'), {'currency': 'ETB', ...financeInsights(txs, cats)}),
      financeResultFor(part('finance_transactions'), {'currency': 'ETB', 'total_matching': 1, 'income': 0, 'expense': 700, 'transactions': [row], 'filters': {'period': 'All time'}}),
      financeResultFor(part('finance_accounts'), {'currency': 'ETB', 'total_balance': 5300, 'accounts': [account]}),
    ];
    expect(cards.every((c) => c != null), isTrue);
    expect(financeResultFor(part('finance_summary'), {'error': 'nope'}), isNull);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: ListView(children: [for (final c in cards) c!])))));
    expect(find.text('Shoa'), findsWidgets);
    expect(find.textContaining('5,300.00'), findsWidgets);
    expect(tester.takeException(), isNull);

    // And at phone width.
    tester.view
      ..physicalSize = const Size(360 * 3, 3000 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: ListView(children: [for (final c in cards) c!])))));
    expect(tester.takeException(), isNull);
  });
}
