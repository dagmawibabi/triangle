import 'package:flutter/foundation.dart';

// The finance feature's data: banks and their SMS patterns (from Totals,
// github.com/detached-space/totals, MIT licence), the user's accounts and
// transactions, categories, learned category rules and budgets. Everything
// is kept on this phone in finance.json.

/// A bank or wallet whose SMS the parser understands, from
/// assets/finance/banks.json, plus Cash and Other for manual accounts.
@immutable
class FinBank {
  const FinBank({
    required this.id,
    required this.name,
    required this.shortName,
    this.codes = const [],
    this.maskPattern,
    this.uniformMasking = false,
    this.simBased = false,
    this.colors = const [],
  });

  final int id;
  final String name;
  final String shortName;

  /// SMS sender ids, like "CBE" or "127" for Telebirr.
  final List<String> codes;

  /// How many trailing digits of the account number the bank's SMS show.
  final int? maskPattern;
  final bool uniformMasking;

  /// A phone-number wallet (Telebirr, M-Pesa): one account per SIM, and the
  /// SMS often carry no account number.
  final bool simBased;

  /// Two hex colours, like "#1b0b2e", for the account card.
  final List<String> colors;

  bool get manual => id == cashBankId || id == otherBankId;

  factory FinBank.fromJson(Map<String, dynamic> j) => FinBank(
    id: (j['id'] as num).toInt(),
    name: '${j['name'] ?? ''}',
    shortName: '${j['shortName'] ?? j['name'] ?? ''}',
    codes: [for (final c in (j['codes'] as List? ?? const [])) '$c'],
    maskPattern: (j['maskPattern'] as num?)?.toInt(),
    uniformMasking: j['uniformMasking'] == true,
    simBased: j['simBased'] == true,
    colors: [for (final c in (j['colors'] as List? ?? const [])) '$c'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'sms_senders': codes,
    if (colors.isNotEmpty) 'colors': colors,
    if (simBased) 'phone_wallet': true,
    if (manual) 'manual': true,
  };
}

const cashBankId = 100;
const otherBankId = 0;

const cashBank = FinBank(id: cashBankId, name: 'Cash Wallet', shortName: 'Cash', colors: ['#0f766e', '#14b8a6']);
const otherBank = FinBank(id: otherBankId, name: 'Other account', shortName: 'Other', colors: ['#3f3f46', '#71717a']);

/// One regex for one kind of bank SMS, from assets/finance/sms_patterns.json.
@immutable
class SmsPattern {
  const SmsPattern({
    required this.bankId,
    required this.regex,
    required this.type,
    this.description = '',
    this.refRequired,
    this.hasAccount,
  });

  final int bankId;
  final String regex;

  /// CREDIT or DEBIT.
  final String type;
  final String description;
  final bool? refRequired;
  final bool? hasAccount;

  factory SmsPattern.fromJson(Map<String, dynamic> j) => SmsPattern(
    bankId: (j['bankId'] as num).toInt(),
    regex: '${j['regex']}',
    type: '${j['type'] ?? 'DEBIT'}'.toUpperCase(),
    description: '${j['description'] ?? ''}',
    refRequired: j['refRequired'] as bool?,
    hasAccount: j['hasAccount'] as bool?,
  );
}

/// A bank account, wallet or cash pocket the user keeps track of.
@immutable
class FinAccount {
  const FinAccount({
    required this.id,
    required this.bankId,
    this.number = '',
    this.holder = '',
    this.nickname = '',
    this.balance = 0,
    this.includeInTotals = true,
    this.dormant = false,
    this.isDefault = false,
    this.detected = false,
    required this.createdAt,
    this.balanceAt,
  });

  final String id;
  final int bankId;

  /// The account number, phone number for wallets, or the masked number
  /// the bank's SMS show ("1*****1234") for accounts found in messages.
  final String number;
  final String holder;
  final String nickname;
  final double balance;
  final bool includeInTotals;
  final bool dormant;

  /// Where messages go when the bank has several accounts and the SMS
  /// doesn't say which.
  final bool isDefault;

  /// Created by an SMS sync rather than by the user.
  final bool detected;
  final DateTime createdAt;

  /// When [balance] was last set from an SMS or by hand.
  final DateTime? balanceAt;

  /// The digits of [number], for matching masked SMS numbers.
  String get digits => number.replaceAll(RegExp(r'\D'), '');

  FinAccount copyWith({
    int? bankId,
    String? number,
    String? holder,
    String? nickname,
    double? balance,
    bool? includeInTotals,
    bool? dormant,
    bool? isDefault,
    bool? detected,
    DateTime? balanceAt,
  }) => FinAccount(
    id: id,
    bankId: bankId ?? this.bankId,
    number: number ?? this.number,
    holder: holder ?? this.holder,
    nickname: nickname ?? this.nickname,
    balance: balance ?? this.balance,
    includeInTotals: includeInTotals ?? this.includeInTotals,
    dormant: dormant ?? this.dormant,
    isDefault: isDefault ?? this.isDefault,
    detected: detected ?? this.detected,
    createdAt: createdAt,
    balanceAt: balanceAt ?? this.balanceAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bank': bankId,
    'number': number,
    if (holder.isNotEmpty) 'holder': holder,
    if (nickname.isNotEmpty) 'nickname': nickname,
    'balance': balance,
    if (!includeInTotals) 'include_in_totals': false,
    if (dormant) 'dormant': true,
    if (isDefault) 'default': true,
    if (detected) 'detected': true,
    'created_at': createdAt.toIso8601String(),
    if (balanceAt != null) 'balance_at': balanceAt!.toIso8601String(),
  };

  factory FinAccount.fromJson(Map<String, dynamic> j) => FinAccount(
    id: '${j['id']}',
    bankId: (j['bank'] as num?)?.toInt() ?? otherBankId,
    number: '${j['number'] ?? ''}',
    holder: '${j['holder'] ?? ''}',
    nickname: '${j['nickname'] ?? ''}',
    balance: (j['balance'] as num?)?.toDouble() ?? 0,
    includeInTotals: j['include_in_totals'] != false,
    dormant: j['dormant'] == true,
    isDefault: j['default'] == true,
    detected: j['detected'] == true,
    createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
    balanceAt: DateTime.tryParse('${j['balance_at'] ?? ''}'),
  );
}

/// Money in (CREDIT) or out (DEBIT) of an account.
@immutable
class FinTransaction {
  const FinTransaction({
    required this.id,
    required this.bankId,
    required this.type,
    required this.amount,
    required this.time,
    required this.reference,
    this.accountId,
    this.fee = 0,
    this.balanceAfter,
    this.counterparty = '',
    this.note = '',
    this.category,
    this.source = 'manual',
    this.smsId,
    this.accountMask,
    this.link,
  });

  final String id;
  final String? accountId;
  final int bankId;

  /// CREDIT or DEBIT.
  final String type;

  /// The principal, always positive.
  final double amount;

  /// Service charge and VAT the bank added.
  final double fee;

  /// The account balance the bank reported after this transaction.
  final double? balanceAfter;
  final DateTime time;
  final String reference;

  /// Who paid the user, or whom they paid.
  final String counterparty;
  final String note;

  /// A category key, like "groceries".
  final String? category;

  /// "sms" or "manual".
  final String source;
  final String? smsId;

  /// The account number as the SMS showed it.
  final String? accountMask;

  /// The bank's receipt link, when the SMS had one.
  final String? link;

  bool get isCredit => type == 'CREDIT';
  bool get isDebit => type == 'DEBIT';

  /// What left the account: principal and fees.
  double get outflow => isDebit ? amount + fee : 0;

  FinTransaction copyWith({
    String? accountId,
    bool clearAccount = false,
    String? type,
    double? amount,
    double? fee,
    DateTime? time,
    String? counterparty,
    String? note,
    String? category,
    bool clearCategory = false,
  }) => FinTransaction(
    id: id,
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    bankId: bankId,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    fee: fee ?? this.fee,
    balanceAfter: balanceAfter,
    time: time ?? this.time,
    reference: reference,
    counterparty: counterparty ?? this.counterparty,
    note: note ?? this.note,
    category: clearCategory ? null : (category ?? this.category),
    source: source,
    smsId: smsId,
    accountMask: accountMask,
    link: link,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (accountId != null) 'account': accountId,
    'bank': bankId,
    'type': type,
    'amount': amount,
    if (fee > 0) 'fee': fee,
    if (balanceAfter != null) 'balance_after': balanceAfter,
    'time': time.toIso8601String(),
    'reference': reference,
    if (counterparty.isNotEmpty) 'counterparty': counterparty,
    if (note.isNotEmpty) 'note': note,
    if (category != null) 'category': category,
    'source': source,
    if (smsId != null) 'sms_id': smsId,
    if (accountMask != null) 'account_mask': accountMask,
    if (link != null) 'link': link,
  };

  factory FinTransaction.fromJson(Map<String, dynamic> j) => FinTransaction(
    id: '${j['id']}',
    accountId: j['account'] as String?,
    bankId: (j['bank'] as num?)?.toInt() ?? otherBankId,
    type: '${j['type']}' == 'CREDIT' ? 'CREDIT' : 'DEBIT',
    amount: (j['amount'] as num?)?.toDouble().abs() ?? 0,
    fee: (j['fee'] as num?)?.toDouble() ?? 0,
    balanceAfter: (j['balance_after'] as num?)?.toDouble(),
    time: DateTime.tryParse('${j['time']}') ?? DateTime.now(),
    reference: '${j['reference'] ?? j['id']}',
    counterparty: '${j['counterparty'] ?? ''}',
    note: '${j['note'] ?? ''}',
    category: j['category'] as String?,
    source: '${j['source'] ?? 'manual'}',
    smsId: j['sms_id'] as String?,
    accountMask: j['account_mask'] as String?,
    link: j['link'] as String?,
  );
}

/// A spending or income category. The built-in set follows Totals'.
@immutable
class FinCategory {
  const FinCategory(this.key, this.name, {this.income = false, this.essential = false, this.recurring = false, this.icon = 'more', this.custom = false});

  final String key;
  final String name;
  final bool income;

  /// Needs rather than wants: rent, groceries, transport, health…
  final bool essential;
  final bool recurring;

  /// A key into the card icons: home, bolt, cart, car, food, shirt, health,
  /// phone, loan, gift, spa, pay, transfer, more.
  final String icon;
  final bool custom;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'flow': income ? 'income' : 'expense',
    if (essential) 'essential': true,
    if (recurring) 'recurring': true,
    'icon': icon,
    if (custom) 'custom': true,
  };

  factory FinCategory.fromJson(Map<String, dynamic> j) => FinCategory(
    '${j['key']}',
    '${j['name']}',
    income: j['flow'] == 'income',
    essential: j['essential'] == true,
    recurring: j['recurring'] == true,
    icon: '${j['icon'] ?? 'more'}',
    custom: true,
  );
}

const builtInCategories = <FinCategory>[
  FinCategory('salary', 'Salary', income: true, essential: true, recurring: true, icon: 'pay'),
  FinCategory('business', 'Business', income: true, essential: true, recurring: true, icon: 'pay'),
  FinCategory('side_hustle', 'Side hustle', income: true, recurring: true, icon: 'pay'),
  FinCategory('bonus', 'Bonus', income: true, icon: 'pay'),
  FinCategory('refund', 'Refund', income: true, icon: 'pay'),
  FinCategory('reimbursement', 'Reimbursement', income: true, icon: 'pay'),
  FinCategory('gifts_received', 'Gifts received', income: true, icon: 'gift'),
  FinCategory('debt', 'Borrowed', income: true, icon: 'loan'),
  FinCategory('repayment_in', 'Repaid to me', income: true, icon: 'loan'),
  FinCategory('income_misc', 'Other income', income: true, icon: 'more'),
  FinCategory('rent', 'Rent', essential: true, recurring: true, icon: 'home'),
  FinCategory('utilities', 'Utilities', essential: true, recurring: true, icon: 'bolt'),
  FinCategory('groceries', 'Groceries', essential: true, icon: 'cart'),
  FinCategory('transport', 'Transport', essential: true, icon: 'car'),
  FinCategory('eating_out', 'Eating out', icon: 'food'),
  FinCategory('clothing', 'Clothing', icon: 'shirt'),
  FinCategory('health', 'Health', essential: true, icon: 'health'),
  FinCategory('airtime', 'Airtime & data', essential: true, recurring: true, icon: 'phone'),
  FinCategory('loan', 'Loan payment', essential: true, recurring: true, icon: 'loan'),
  FinCategory('repayment_out', 'Repaying someone', icon: 'loan'),
  FinCategory('beauty', 'Beauty', icon: 'spa'),
  FinCategory('gifts_given', 'Gifts given', icon: 'gift'),
  FinCategory('education', 'Education', essential: true, icon: 'school'),
  FinCategory('entertainment', 'Entertainment', icon: 'movie'),
  FinCategory('shopping', 'Shopping', icon: 'bag'),
  FinCategory('transfer', 'Own transfer', icon: 'transfer'),
  FinCategory('misc', 'Other spending', icon: 'more'),
];

/// A spending limit for a category (or everything) per week or month.
@immutable
class FinBudget {
  const FinBudget({required this.id, required this.limit, this.category, this.period = 'month'});

  final String id;

  /// A category key; null for all spending.
  final String? category;
  final double limit;

  /// "month" or "week".
  final String period;

  Map<String, dynamic> toJson() => {'id': id, if (category != null) 'category': category, 'limit': limit, 'period': period};

  factory FinBudget.fromJson(Map<String, dynamic> j) => FinBudget(
    id: '${j['id']}',
    category: j['category'] as String?,
    limit: (j['limit'] as num?)?.toDouble() ?? 0,
    period: j['period'] == 'week' ? 'week' : 'month',
  );
}
