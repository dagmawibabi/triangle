import 'dart:convert';

import 'finance_models.dart';

// The banks and SMS patterns the parser uses. Like Totals, the app ships a
// copy (assets/finance) and downloads newer ones from the server Totals
// publishes them on; a download is used only once it passes [decodeParserConfig].

const remoteBanksUrl = 'https://sms-parsing-visualizer.vercel.app/banks.json';
const remotePatternsUrl = 'https://sms-parsing-visualizer.vercel.app/sms_patterns.json';

/// Patterns the bundled copy always supplies, whatever a download says
/// (Totals keeps the same list: its own fix for this one is newer than the
/// published file).
const bundledPatternOverrides = {'4|dashen telebirr credit'};

class ParserConfig {
  const ParserConfig({required this.banks, required this.patterns, required this.source, this.fetchedAt, this.dropped = 0});

  /// From the files, plus Cash and Other.
  final List<FinBank> banks;
  final List<SmsPattern> patterns;

  /// "bundled" or "downloaded".
  final String source;
  final DateTime? fetchedAt;

  /// Downloaded patterns left out because they didn't parse or compile.
  final int dropped;

  Map<String, dynamic> toJson() => {
    'source': source,
    if (fetchedAt != null) 'downloaded_at': fetchedAt!.toIso8601String().substring(0, 16),
    'banks': banks.where((b) => !b.manual).length,
    'patterns': patterns.length,
    if (dropped > 0) 'patterns_skipped': dropped,
  };
}

/// The JSON in [body]: plain, or wrapped in a JS `export const x = …` as
/// Totals also accepts.
Object? _json(String body) {
  var b = body.trim();
  if (b.startsWith('export') || b.startsWith('const') || b.startsWith('var') || b.startsWith('let')) {
    final m = RegExp(r'(\[[\s\S]*\])|(\{[\s\S]*\})').firstMatch(b);
    if (m != null) b = m.group(0)!;
  }
  return jsonDecode(b);
}

List<Map<String, dynamic>> _items(Object? j, String key) => [
  for (final x in (j is List ? j : (j is Map ? j[key] as List? ?? const [] : const [])))
    if (x is Map) Map<String, dynamic>.from(x),
];

String _key(SmsPattern p) => '${p.bankId}|${p.description.trim().toLowerCase()}';

/// Banks and patterns from downloaded [banksBody] and [patternsBody], or
/// null when they don't look like a complete, working set: no banks, or
/// fewer than half as many usable patterns as [bundled] has (a truncated or
/// broken file must not replace a working one). Patterns that don't parse
/// or compile are dropped; [bundledPatternOverrides] come from [bundled].
ParserConfig? decodeParserConfig(String banksBody, String patternsBody, {required List<SmsPattern> bundled, DateTime? fetchedAt}) {
  try {
    final banks = <FinBank>[];
    for (final m in _items(_json(banksBody), 'banks')) {
      try {
        final b = FinBank.fromJson(m);
        if (b.name.isNotEmpty && b.codes.isNotEmpty && b.id != cashBankId && b.id != otherBankId) banks.add(b);
      } catch (_) {}
    }
    if (banks.isEmpty) return null;

    final patterns = <SmsPattern>[];
    var dropped = 0;
    for (final m in _items(_json(patternsBody), 'patterns')) {
      try {
        final p = SmsPattern.fromJson(m);
        if (p.type != 'CREDIT' && p.type != 'DEBIT') throw const FormatException('type');
        RegExp(p.regex, caseSensitive: false, multiLine: true, dotAll: true);
        patterns.add(p);
      } catch (_) {
        dropped++;
      }
    }
    if (patterns.length < bundled.length / 2 || patterns.length < 10) return null;

    for (final b in bundled.where((p) => bundledPatternOverrides.contains(_key(p)))) {
      final at = patterns.indexWhere((p) => _key(p) == _key(b));
      if (at < 0) {
        patterns.add(b);
      } else {
        patterns[at] = b;
      }
    }
    return ParserConfig(banks: [...banks, cashBank, otherBank], patterns: patterns, source: 'downloaded', fetchedAt: fetchedAt, dropped: dropped);
  } catch (_) {
    return null;
  }
}

/// The bundled files, which the app always has.
ParserConfig bundledParserConfig(String banksBody, String patternsBody) => ParserConfig(
  banks: [for (final m in _items(_json(banksBody), 'banks')) FinBank.fromJson(m), cashBank, otherBank],
  patterns: [for (final m in _items(_json(patternsBody), 'patterns')) SmsPattern.fromJson(m)],
  source: 'bundled',
);
