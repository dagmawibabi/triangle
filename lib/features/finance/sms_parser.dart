import 'finance_models.dart';

// Reads bank SMS into transactions. A port of Totals' PatternParser,
// sender matching and message classifier
// (github.com/detached-space/totals, MIT licence): the sender picks the
// bank, then that bank's regexes are tried in order and the first whose
// required fields are all there wins.

/// What one bank SMS said.
class ParsedSms {
  ParsedSms({required this.bankId, required this.type, required this.amount, required this.pattern});

  final int bankId;

  /// CREDIT or DEBIT.
  String type;
  final double amount;
  final String pattern;
  double? balance;

  /// As the SMS shows it, masked or not.
  String? account;
  String? reference;
  String? receiver;
  String? creditor;
  double serviceCharge = 0;
  double vat = 0;
  String? link;

  /// Who paid, for money in; whom the user paid, for money out.
  String get counterparty => (type == 'CREDIT' ? (creditor ?? receiver) : (receiver ?? creditor))?.trim() ?? '';

  Map<String, dynamic> toJson() => {
    'bank_id': bankId,
    'type': type,
    'amount': amount,
    if (serviceCharge + vat > 0) 'fee': _round(serviceCharge + vat),
    'balance_after': ?balance,
    'account': ?account,
    'reference': ?reference,
    if (counterparty.isNotEmpty) 'counterparty': counterparty,
    'link': ?link,
    'pattern': pattern,
  };
}

double _round(double v) => (v * 100).roundToDouble() / 100;

String _token(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The bank whose SMS sender id best matches [address]: an exact match
/// first, then the longest code, then one at the start.
FinBank? bankForSender(String? address, Iterable<FinBank> banks) {
  final a = address == null ? '' : _token(address);
  if (a.isEmpty) return null;
  FinBank? best;
  var bestScore = -1;
  for (final bank in banks) {
    for (final code in bank.codes) {
      final c = _token(code);
      if (c.isEmpty) continue;
      final at = a.indexOf(c);
      if (at < 0) continue;
      // Exact beats longer beats at-the-start beats less left over.
      final score = (a == c ? 1 << 20 : 0) + (c.length << 10) + (at == 0 ? 1 << 9 : 0) + (255 - (a.length - c.length).clamp(0, 255));
      if (score > bestScore) {
        bestScore = score;
        best = bank;
      }
    }
  }
  return best;
}

/// Texts that look like money moved but didn't: Telebirr's ATM
/// authorization code, and the airtime acknowledgement the receiving phone
/// gets (counting it would invent income).
bool isNonLedgerSms(String body) =>
    RegExp(r'\bATM\s+withdraw(?:al)?\s+secret\s+code\s+is\s+\d{4,8}\b', caseSensitive: false).hasMatch(body) ||
    RegExp(r'you\s+have\s+received\s+ETB\s+[\d,.]+\s+airtime\s+from\s+\S+[\s\S]*?transaction\s+number\s+is\s+[A-Z0-9@-]+', caseSensitive: false).hasMatch(body) ||
    RegExp(r'[\d,.]+\s+ብር[\s\S]*?ተሞልቶሎታል[\s\S]*?ቁጥርዎ\s+[A-Z0-9@-]+', caseSensitive: false).hasMatch(body);

final _compiled = <String, RegExp?>{};

RegExp? _regex(String source) => _compiled.putIfAbsent(source, () {
  try {
    return RegExp(source, caseSensitive: false, multiLine: true, dotAll: true);
  } catch (_) {
    return null;
  }
});

/// Parses [body] from [sender]. With [bankId] the sender isn't needed;
/// with neither, every bank's patterns are tried. Null when nothing matches
/// or the text isn't a ledger entry.
ParsedSms? parseBankSms(
  String body,
  String? sender, {
  required List<FinBank> banks,
  required List<SmsPattern> patterns,
  int? bankId,
}) {
  final text = body.trim();
  if (text.isEmpty || isNonLedgerSms(text)) return null;
  final bank = bankId != null ? banks.where((b) => b.id == bankId).firstOrNull : bankForSender(sender, banks);
  if (bank == null && (bankId != null || (sender ?? '').trim().isNotEmpty)) return null;
  final candidates = bank == null ? patterns : patterns.where((p) => p.bankId == bank.id);
  for (final p in candidates) {
    final re = _regex(p.regex);
    if (re == null) continue;
    final RegExpMatch? m;
    try {
      m = re.firstMatch(text);
    } catch (_) {
      continue;
    }
    if (m == null) continue;
    final parsed = _extract(m, p, text, banks.where((b) => b.id == p.bankId).firstOrNull);
    if (parsed != null) return parsed;
  }
  return null;
}

ParsedSms? _extract(RegExpMatch m, SmsPattern p, String body, FinBank? bank) {
  final names = m.groupNames.toSet();
  String? group(String n) {
    if (!names.contains(n)) return null;
    final v = m.namedGroup(n)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  String? first(List<String> ns) {
    for (final n in ns) {
      final v = group(n);
      if (v != null) return v;
    }
    return null;
  }

  final amount = _number(group('amount'));
  if (amount == null) return null;
  // A pattern with a balance group that didn't capture one matched the
  // wrong message.
  final balance = _number(group('balance'));
  if (names.contains('balance') && balance == null) return null;

  var type = p.type;
  final rawType = group('type')?.toLowerCase();
  if (rawType != null) {
    if (rawType.contains('debit')) type = 'DEBIT';
    if (rawType.contains('credit')) type = 'CREDIT';
  }
  final out = ParsedSms(bankId: p.bankId, type: type, amount: amount, pattern: p.description)
    ..balance = balance
    ..serviceCharge = _number(first(const ['serviceCharge', 'ServiceCharge', 'servicecharge', 'service_charge'])) ?? 0
    ..vat = _number(first(const ['vat', 'VAT'])) ?? 0
    ..receiver = group('receiver')
    ..creditor = group('creditor');

  final account = group('account');
  if (account != null) {
    final mask = bank?.maskPattern ?? 0;
    out.account = bank != null && bank.uniformMasking && mask > 0 && account.length >= mask ? account.substring(account.length - mask) : account;
  }
  if (p.hasAccount == true && names.contains('account') && out.account == null) return null;

  if (type == 'CREDIT') {
    final from = first(const ['sender', 'source', 'agent', 'payer', 'from']) ?? _fallbackCounterparty(body);
    if (from != null && from.trim().isNotEmpty) out.creditor ??= from.trim();
  }

  out.link = RegExp(r'https?://[^\s<>"]+').firstMatch(body)?.group(0)?.replaceAll(RegExp(r'[.,;)]+$'), '');
  out.reference = group('reference') ?? _referenceFromLink(out.link);
  if (p.refRequired == true && out.reference == null) return null;
  return out;
}

String? _referenceFromLink(String? link) {
  if (link == null) return null;
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  for (final k in const ['id', 'ref', 'reference', 'trx', 'tx']) {
    final v = uri.queryParameters[k];
    if (v != null && v.length >= 6) return v;
  }
  final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  return last != null && RegExp(r'^[A-Za-z0-9]{8,}$').hasMatch(last) ? last : null;
}

String? _fallbackCounterparty(String body) {
  for (final re in [
    RegExp(r'from\s+(.+?)\s+(?:to|on|at|ref|reference|transaction|balance)', caseSensitive: false),
    RegExp(r'by\s+(.+?)\s+(?:on|through|ref|reference|transaction|balance)', caseSensitive: false),
    RegExp(r'with\s+agent\s+(.+?)\s+(?:on|at|ref|reference|transaction|balance)', caseSensitive: false),
  ]) {
    final v = re.firstMatch(body)?.group(1)?.trim();
    if (v == null || v.isEmpty) continue;
    final l = v.toLowerCase();
    if (l.contains('your account') || l.contains('your telebirr') || l.contains('your mpesa')) continue;
    return v;
  }
  return null;
}

double? _number(String? s) {
  if (s == null) return null;
  var c = s.replaceAll(',', '').trim();
  c = c.replaceAll(RegExp(r'[^0-9.]+$'), '').replaceAll(RegExp(r'\.+$'), '').replaceAll(RegExp(r'^[^0-9]+'), '');
  return double.tryParse(c);
}

/// Picks the account [p] belongs to among [accounts]: the bank's accounts
/// whose number ends with the SMS's visible digits, else the bank's only
/// (or default) account when the SMS gives no usable number. Null when the
/// SMS names an account the user hasn't added.
FinAccount? matchAccount(ParsedSms p, List<FinAccount> accounts, FinBank? bank) {
  final ofBank = accounts.where((a) => a.bankId == p.bankId).toList();
  if (ofBank.isEmpty) return null;
  final visible = (p.account ?? '').replaceAll(RegExp(r'\D'), '');
  // Masked numbers show the digits at the end ("1*****1234" → 1234).
  final tail = RegExp(r'(\d+)\D*$').firstMatch(p.account ?? '')?.group(1) ?? '';
  final suffix = tail.length >= 2 ? tail : (visible.length >= 2 ? visible.substring(visible.length - (visible.length < 4 ? visible.length : 4)) : '');
  if (suffix.isNotEmpty && !(bank?.simBased ?? false)) {
    final hits = ofBank.where((a) => a.digits.isNotEmpty && (a.digits.endsWith(suffix) || suffix.endsWith(a.digits))).toList();
    if (hits.length == 1) return hits.first;
    if (hits.length > 1) return hits.where((a) => a.isDefault).firstOrNull ?? hits.first;
    // The SMS names a number none of the accounts has.
    if (ofBank.every((a) => a.digits.isNotEmpty)) return null;
  }
  if (ofBank.length == 1) return ofBank.first;
  return ofBank.where((a) => a.isDefault).firstOrNull ?? ofBank.where((a) => !a.dormant).firstOrNull ?? ofBank.first;
}

/// A category from what the counterparty and SMS say, for the common
/// cases: airtime, fuel and rides, utilities, food, health. Null when it
/// can't tell.
String? guessCategory({required bool income, required String counterparty, required String body}) {
  final t = '$counterparty $body'.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (income) {
    if (has(['salary', 'payroll', 'ደመወዝ'])) return 'salary';
    if (has(['refund', 'reversal', 'reversed'])) return 'refund';
    return null;
  }
  if (has(['airtime', 'recharge', 'data package', 'package purchase', 'ethio telecom', 'safaricom', 'ተሞልቶ'])) return 'airtime';
  if (has(['fuel', 'petrol', 'benzine', 'total energies', 'ola energy', 'noc ', 'ride', 'feres', 'zayride', 'taxi', 'uber', 'bus ticket'])) return 'transport';
  if (has(['electric', 'eeu', 'water', 'aawsa', 'dstv', 'canal+', 'internet', 'wifi', 'utility'])) return 'utilities';
  if (has(['pharmacy', 'hospital', 'clinic', 'medical', 'health'])) return 'health';
  if (has(['restaurant', 'cafe', 'coffee', 'pizza', 'burger', 'kitchen', 'deliveraddis', 'beu delivery', 'zmall food'])) return 'eating_out';
  if (has(['supermarket', 'grocery', 'shoa', 'queens', 'safeway', 'fresh corner', 'market'])) return 'groceries';
  if (has(['school', 'university', 'tuition', 'college', 'academy'])) return 'education';
  if (has(['rent', 'ኪራይ'])) return 'rent';
  if (has(['loan repayment', 'loan payment', 'installment'])) return 'loan';
  return null;
}
