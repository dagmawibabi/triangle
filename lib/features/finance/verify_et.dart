import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class VerifyEtException implements Exception {
  VerifyEtException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Verify.ET (verify.et): payment verification for Ethiopian banks and
/// wallets with the person's API key. One request per check; queued checks
/// are followed on their status link for up to a minute.
class VerifyEt {
  VerifyEt(this.key, {http.Client? client}) : _http = client ?? http.Client();
  final String key;
  final http.Client _http;

  static const base = 'https://verify.et';

  /// The banks it checks, with what each needs besides the reference.
  static const banks = {
    'cbe': 'Commercial Bank of Ethiopia: the receipt ID (or link); older FT references need the account\'s last 8 digits',
    'telebirr': 'Telebirr: the transaction number',
    'boa': 'Bank of Abyssinia: the reference and the account\'s last 5 digits',
    'dashen': 'Dashen Bank: the reference',
    'awash': 'Awash Bank: the reference',
    'mpesa': 'M-Pesa: the transaction number',
    'cbebirr': 'CBE Birr: the receipt number and the phone number',
    'siinqee': 'Siinqee Bank: the reference',
    'kaafiebirr': 'Kaafi eBirr: the reference or receipt link',
    'coopayebirr': 'Coopay eBirr: the receipt link or its token',
  };

  Map<String, String> get _headers => {'x-api-key': key, 'accept': 'application/json'};

  static String _id() {
    final r = Random.secure();
    return 'triangle-${DateTime.now().millisecondsSinceEpoch}-${List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  /// Checks one payment. [bank] may be left out: Verify.ET works it out
  /// from the reference, a receipt link or a pasted SMS.
  Future<Map<String, dynamic>> verify({
    String? bank,
    required String reference,
    String? suffix,
    String? phone,
    String? settlementAccount,
  }) async {
    final body = {
      if (bank != null && bank.isNotEmpty && bank != 'auto') 'bank': bank,
      'reference': reference,
      if (bank == 'telebirr' || bank == 'mpesa') 'transactionNumber': reference,
      if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (settlementAccount != null && settlementAccount.isNotEmpty) 'settlementAccount': settlementAccount,
    };
    final r = await _http
        .post(
          Uri.parse('$base/api/verify?waitMs=8000'),
          headers: {..._headers, 'content-type': 'application/json', 'idempotency-key': _id()},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 40));
    var j = _decode(r);
    if (r.statusCode == 401) throw VerifyEtException('The Verify.ET key isn\'t valid. Check it in Money → Tools.', code: 'unauthorized');
    if (r.statusCode == 402) throw VerifyEtException('The Verify.ET account is out of verification credits for this month.', code: 'credits');
    if (r.statusCode == 429) throw VerifyEtException('Verify.ET is rate limiting; try again in a minute.', code: 'rate_limited');
    if (r.statusCode >= 500) throw VerifyEtException('Verify.ET is busy or down right now.', code: 'unavailable');
    // Queued: follow the status link until it finishes.
    final status = '${(j['links'] as Map?)?['statusUrl'] ?? j['statusUrl'] ?? ''}';
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (r.statusCode == 202 && _processing(j) != 'completed' && _processing(j) != 'failed' && status.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(milliseconds: ((j['links'] as Map?)?['pollAfterMs'] as num?)?.toInt() ?? 1500));
      final s = await _http.get(Uri.parse('$base$status'), headers: _headers).timeout(const Duration(seconds: 20));
      final next = _decode(s);
      final d = next['data'] is Map ? Map<String, dynamic>.from(next['data'] as Map) : null;
      j = {
        ...j,
        'verification': d ?? next['verification'],
        'data': d == null ? j['data'] : [{...?(d['result'] as Map?)?.cast<String, dynamic>(), ...d}],
        // The finished check's own words, not "Verification queued."
        'message': d?['errorMessage'] ?? (d?['error'] as Map?)?['message'] ?? next['message'] ?? j['message'],
        if (d?['error'] != null) 'error': d!['error'],
      };
    }
    return j;
  }

  static String? _processing(Map<String, dynamic> j) => (j['verification'] as Map?)?['processingStatus'] as String?;

  static Map<String, dynamic> _decode(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map ? Map<String, dynamic>.from(j) : {'data': j};
    } catch (_) {
      return {'message': 'Verify.ET answered ${r.statusCode}.'};
    }
  }

  /// The one result in a response: its data item, else the verification's.
  static Map<String, dynamic> result(Map<String, dynamic> j) {
    final data = j['data'];
    final item = data is List && data.isNotEmpty ? data.first : (data is Map ? data : null);
    final v = j['verification'] as Map?;
    return {
      ...?(v?['result'] as Map?)?.cast<String, dynamic>(),
      ...?(item as Map?)?.cast<String, dynamic>(),
      'processingStatus': ?v?['processingStatus'],
      if (j['error'] is Map) 'error': j['error'],
      'message': ?j['message'],
      'requestId': ?j['requestId'],
    };
  }

  /// Credits left this month.
  Future<Map<String, dynamic>> balance() async {
    final r = await _http.get(Uri.parse('$base/api/credits/balance'), headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 401) throw VerifyEtException('The Verify.ET key isn\'t valid.', code: 'unauthorized');
    final j = _decode(r);
    return Map<String, dynamic>.from((j['data'] as Map?) ?? const {});
  }
}
