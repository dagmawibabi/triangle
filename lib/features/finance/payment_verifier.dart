import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Checks a payment against the bank's own public receipt page, straight
/// from the phone: CBE, Telebirr, Bank of Abyssinia, Dashen and Zemen
/// publish receipts by reference number; other banks' receipt links come
/// from their SMS. Nothing goes through anyone else's server.
///
/// A receipt found means the bank recorded the transaction; its details
/// (payer, receiver, amount, date) are read from the page or PDF where
/// they can be.
class PaymentVerifier {
  PaymentVerifier({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _headers = {'user-agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36'};

  /// The bank a reference looks like it is from, when not said.
  static String guessBank(String ref) {
    final r = ref.trim().toUpperCase();
    if (RegExp(r'^FT\d{2}[A-Z0-9]{8,}$').hasMatch(r)) return 'cbe';
    if (RegExp(r'^[A-Z]{2,3}[A-Z0-9]{7,8}$').hasMatch(r) && RegExp(r'\d').hasMatch(r)) return 'telebirr';
    return 'unknown';
  }

  /// The receipt pages to try for [bank] and [ref], most likely first.
  /// CBE and Bank of Abyssinia add the end of an account number to the
  /// reference; [suffixes] are the account numbers to try.
  static List<Uri> receiptUrls(String bank, String ref, List<String> suffixes) {
    final r = ref.trim().toUpperCase();
    final digits = {for (final s in suffixes) s.replaceAll(RegExp(r'\D'), '')}..removeWhere((s) => s.length < 5);
    return switch (bank) {
      'cbe' => [for (final d in digits) Uri.parse('https://apps.cbe.com.et:100/?id=$r${d.substring(d.length - 8 < 0 ? 0 : d.length - 8)}')],
      'telebirr' => [Uri.parse('https://transactioninfo.ethiotelecom.et/receipt/$r')],
      'boa' => [for (final d in digits) Uri.parse('https://cs.bankofabyssinia.com/api/onlineSlip/getDetails/?id=$r${d.substring(d.length - 5)}')],
      'dashen' => [Uri.parse('https://receipt.dashensuperapp.com/receipt/$r')],
      'zemen' => [Uri.parse('https://share.zemenbank.com/rt/$r/pdf')],
      _ => const [],
    };
  }

  /// Fetches [url] and reads what kind of receipt it is and its details.
  /// Null when there is no receipt there.
  Future<Map<String, dynamic>?> fetch(Uri url) async {
    final r = await _http.get(url, headers: _headers).timeout(const Duration(seconds: 25));
    if (r.statusCode >= 400) return null;
    final bytes = r.bodyBytes;
    final type = r.headers['content-type'] ?? '';
    if (bytes.length > 4 && String.fromCharCodes(bytes.take(4)) == '%PDF') {
      if (bytes.length < 800) return null;
      final text = pdfText(bytes);
      final file = await _save(bytes, url);
      return {'format': 'pdf', 'file_path': file.path, 'fields': fieldsFromText(text), if (text.isNotEmpty) 'text': text.length > 3000 ? text.substring(0, 3000) : text};
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    if (type.contains('json') || body.trimLeft().startsWith('{')) {
      try {
        final j = jsonDecode(body);
        final fields = _flatten(j);
        if (fields.isEmpty || (j is Map && (j['header'] as Map?)?['status'] == 'error')) return null;
        return {'format': 'json', 'fields': _normal(fields)};
      } catch (_) {}
    }
    final doc = html_parser.parse(body);
    final text = doc.body?.text.replaceAll(RegExp(r'[ \t]+'), ' ').trim() ?? '';
    if (text.length < 40 || RegExp(r'not found|invalid|no record|does not exist', caseSensitive: false).hasMatch(text) && text.length < 400) return null;
    // Receipt pages lay details out as label/value cells.
    final pairs = <String, String>{};
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td,th').map((c) => c.text.replaceAll(RegExp(r'\s+'), ' ').trim()).where((t) => t.isNotEmpty).toList();
      for (var i = 0; i + 1 < cells.length; i += 2) {
        if (cells[i].length < 60) pairs[cells[i].replaceAll(RegExp(r'[:：]\s*$'), '')] = cells[i + 1];
      }
    }
    final fields = {..._normal(pairs), ...fieldsFromText(text)..removeWhere((k, _) => pairs.isNotEmpty && _normal(pairs).containsKey(k))};
    return {'format': 'html', 'fields': fields, 'labels': pairs};
  }

  Future<File> _save(Uint8List bytes, Uri url) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/downloads/receipts');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = url.toString().split(RegExp(r'[/=]')).last.replaceAll(RegExp(r'[^\w-]'), '');
    return File('${dir.path}/receipt_${name.isEmpty ? DateTime.now().millisecondsSinceEpoch : name}.pdf').writeAsBytes(bytes);
  }

  static Map<String, String> _flatten(Object? j, [String prefix = '']) {
    final out = <String, String>{};
    if (j is Map) {
      for (final e in j.entries) {
        out.addAll(_flatten(e.value, '${e.key}'));
      }
    } else if (j is List) {
      for (final x in j) {
        out.addAll(_flatten(x, prefix));
      }
    } else if (j != null && prefix.isNotEmpty && '$j'.trim().isNotEmpty) {
      out[prefix] = '$j'.trim();
    }
    return out;
  }

  /// The usual details under the same names, whatever the bank calls them.
  static Map<String, String> _normal(Map<String, String> raw) {
    final out = <String, String>{};
    String? pick(List<String> words) {
      for (final e in raw.entries) {
        final k = e.key.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
        if (words.any((w) => k.contains(w))) return e.value;
      }
      return null;
    }

    void put(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) out[k] = v.trim();
    }

    put('payer', pick(['payer name', 'payer', 'sender name', 'source account name', 'debited', 'from']));
    put('payer_account', pick(['payer account', 'payer telebirr', 'sender account', 'source account', 'debit account', 'payer phone']));
    put('receiver', pick(['receiver name', 'credited party name', 'beneficiary name', 'receiver', 'beneficiary', 'credited party', 'to ']));
    put('receiver_account', pick(['receiver account', 'credited party account', 'beneficiary account', 'credit account', 'receiver phone']));
    put('amount', pick(['settled amount', 'transferred amount', 'transaction amount', 'amount']));
    put('fee', pick(['service fee', 'commission', 'charge']));
    put('total', pick(['total paid', 'total amount', 'total']));
    put('date', pick(['payment date', 'transaction date', 'date']));
    put('status', pick(['transaction status', 'status']));
    put('reason', pick(['reason', 'narrative', 'remark', 'purpose']));
    put('reference', pick(['reference', 'invoice no', 'receipt no', 'transaction id']));
    return out;
  }

  /// The labels receipts use, longest first so "Payer Name" wins over "Payer".
  static const _labels = [
    'Payment Date & Time', 'Transaction Date', 'Payment Date', 'Transferred Amount', 'Transaction Amount', 'Settled Amount',
    'Total Paid Amount', 'Total Amount', 'Debited Amount', 'Credited Amount', 'Amount in Word', 'Amount',
    'Payer Name', 'Payer Account', 'Payer Telebirr No.', 'Payer', 'Sender Name', 'Sender Account', 'Sender',
    'Receiver Name', 'Receiver Account', 'Receiver', 'Credited Party Name', 'Credited Party Account No', 'Credited Party',
    'Beneficiary Name', 'Beneficiary Account', 'Beneficiary', 'Account Number', 'Account Name',
    'Reference No.', 'Reference No', 'Reference', 'Transaction ID', 'Invoice No', 'Receipt No', 'Transaction Reference',
    'Service Fee', 'Service Charge', 'Commission', 'VAT', 'Transaction Status', 'Status', 'Reason / Type of service',
    'Reason', 'Narrative', 'Remark', 'Payment Reason', 'Branch', 'Date',
  ];

  /// Details read from a receipt's plain text ("Payer  ABEBE KEBEDE", or a
  /// label on one line and its value on the next).
  static Map<String, String> fieldsFromText(String text) {
    if (text.isEmpty) return {};
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final pairs = <String, String>{};
    String? label(String line) {
      final l = line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      for (final k in _labels) {
        if (l.startsWith(k.toLowerCase())) return k;
      }
      return null;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // "Label<tab>Value": the PDF reader keeps columns apart with a tab.
      final cols = line.split('\t').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      if (cols.length >= 2 && label(cols.first) != null) {
        pairs.putIfAbsent(label(cols.first)!, () => cols.sublist(1).join(' '));
        continue;
      }
      final k = label(line);
      if (k == null) continue;
      final rest = line.substring(k.length).replaceFirst(RegExp(r'^[\s:：.-]+'), '').trim();
      if (rest.isNotEmpty) {
        pairs.putIfAbsent(k, () => rest);
      } else if (i + 1 < lines.length && label(lines[i + 1]) == null) {
        pairs.putIfAbsent(k, () => lines[i + 1].replaceAll('\t', ' '));
        i++;
      }
    }
    final out = _normal(pairs);
    out.putIfAbsent('amount', () => RegExp(r'(?:ETB|Birr|Br)\s*([\d,]+\.\d{2})|([\d,]+\.\d{2})\s*(?:ETB|Birr|Br)', caseSensitive: false).firstMatch(text)?.groups([1, 2]).whereType<String>().firstOrNull ?? '');
    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  /// The text of a simple PDF (receipts are): the strings its pages draw,
  /// from plain and zlib-compressed content streams, put back into lines by
  /// where they are drawn. Words far apart on a line (a label and its value)
  /// are kept apart by a tab. Fonts with their own encodings come out
  /// garbled or not at all.
  static String pdfText(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final runs = <(double, double, String)>[];
    final stream = RegExp(r'stream\r?\n');
    final token = RegExp(
      r'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]+>|(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+T[dD]\b|(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+Tm\b|(-?\d*\.?\d+)\s+TL\b|T\*'
      r'|-?\d*\.?\d+\s+-?\d*\.?\d+\s+-?\d*\.?\d+\s+-?\d*\.?\d+\s+(-?\d*\.?\d+)\s+(-?\d*\.?\d+)\s+cm\b|\bq\b|\bQ\b|\bBT\b',
    );
    var page = 0.0;
    var at = 0;
    while (true) {
      final m = stream.firstMatch(raw.substring(at));
      if (m == null) break;
      final start = at + m.end;
      final end = raw.indexOf('endstream', start);
      if (end < 0) break;
      final chunk = bytes.sublist(start, end);
      String content;
      try {
        content = latin1.decode(ZLibCodec().decode(chunk), allowInvalid: true);
      } catch (_) {
        content = latin1.decode(chunk, allowInvalid: true);
      }
      at = end + 9;
      if (!content.contains('BT')) continue;
      // Each stream is a page (or part of one): later ones sit below.
      page -= 10000;
      // Where text lands: the text matrix moved by the current transform
      // (cm, saved and restored with q and Q). Only moves are followed.
      var ex = 0.0, ey = 0.0;
      final saved = <(double, double)>[];
      var x = 0.0, y = 0.0, lineX = 0.0, lineY = 0.0, leading = 12.0;
      for (final t in token.allMatches(content)) {
        final s = t[0]!;
        if (t[10] != null) {
          ex += double.parse(t[10]!);
          ey += double.parse(t[11]!);
        } else if (s == 'q') {
          saved.add((ex, ey));
        } else if (s == 'Q') {
          if (saved.isNotEmpty) (ex, ey) = saved.removeLast();
        } else if (s == 'BT') {
          x = y = lineX = lineY = 0;
        } else if (t[1] != null) {
          lineX += double.parse(t[1]!);
          lineY += double.parse(t[2]!);
          x = lineX;
          y = lineY;
        } else if (t[3] != null) {
          lineX = double.parse(t[7]!);
          lineY = double.parse(t[8]!);
          x = lineX;
          y = lineY;
        } else if (t[9] != null) {
          leading = double.parse(t[9]!);
        } else if (s == 'T*') {
          lineY -= leading;
          x = lineX;
          y = lineY;
        } else if (s.startsWith('(') || s.startsWith('<')) {
          final text = s.startsWith('(') ? _unescape(s.substring(1, s.length - 1)) : _hex(s);
          if (text.trim().isEmpty) continue;
          runs.add((page + ey + y, ex + x, text));
          // Roughly where the next run on this line would start.
          x += text.length * 5.0;
        }
      }
    }
    if (runs.isEmpty) return '';
    // Lines from top to bottom, words left to right.
    runs.sort((a, b) => (b.$1 - a.$1).abs() < 2 ? a.$2.compareTo(b.$2) : b.$1.compareTo(a.$1));
    final out = StringBuffer();
    double? lineY;
    double lastEnd = 0;
    for (final (y, x, text) in runs) {
      if (lineY == null || (y - lineY).abs() >= 2) {
        if (lineY != null) out.writeln();
        lineY = y;
        out.write(text.trim());
      } else {
        out.write(x - lastEnd > 25 ? '\t' : ' ');
        out.write(text.trim());
      }
      lastEnd = x + text.length * 5.0;
    }
    return out.toString().replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  }

  static String _hex(String s) {
    final hex = s.substring(1, s.length - 1).replaceAll(RegExp(r'\s'), '');
    final out = StringBuffer();
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final c = int.parse(hex.substring(i, i + 2), radix: 16);
      if (c >= 32 && c < 127) out.writeCharCode(c);
    }
    return out.toString();
  }

  static String _unescape(String s) => s.replaceAllMapped(RegExp(r'\\([nrtbf()\\]|[0-7]{1,3})'), (m) {
    final c = m[1]!;
    return switch (c) {
      'n' => '\n',
      'r' => '',
      't' => ' ',
      'b' || 'f' => '',
      '(' || ')' || r'\' => c,
      _ => String.fromCharCode(int.parse(c, radix: 8)),
    };
  });

  /// Parses "1,250.00" and "ETB 1,250.00 Birr".
  static double? amountOf(String? s) => s == null ? null : double.tryParse(RegExp(r'[\d,]+(?:\.\d+)?').firstMatch(s)?[0]?.replaceAll(',', '') ?? '');
}
