import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import 'link_opener.dart';

/// Telegram's entities as text styles. Entities may nest (a bold link, bold
/// italics), so the text is cut at every entity edge and each piece gets the
/// styles of all entities covering it. Links open in the app or browser,
/// @mentions open the chat or profile, #hashtags search, spoilers reveal on
/// tap and bot commands copy.
///
/// [selectable] is for SelectableText, which can't hold widgets: spoilers
/// are then shown dimmed rather than hidden.
TextSpan formattedSpan(td.FormattedText f, {Color? link, bool selectable = false}) {
  // The user-selectable accent defaults to white in the monochrome theme, so
  // it cannot communicate that an entity is interactive. Keep explicitly
  // supplied preview accents, but give in-message links a dependable blue.
  final tint = link ?? const Color(0xFF8AB4FF);
  final linked = _linkify(f);
  final text = linked.text;
  final entities = [
    for (final e in linked.entities)
      if (e.length > 0 && e.offset >= 0 && e.offset + e.length <= text.length) e,
  ];
  if (entities.isEmpty) return TextSpan(text: text);

  final cuts = <int>{0, text.length};
  for (final e in entities) {
    cuts
      ..add(e.offset)
      ..add(e.offset + e.length);
  }
  final edges = cuts.toList()..sort();

  final spans = <InlineSpan>[];
  for (var i = 0; i + 1 < edges.length; i++) {
    final a = edges[i], b = edges[i + 1];
    if (a == b) continue;
    final piece = text.substring(a, b);
    final covering = [for (final e in entities) if (e.offset <= a && e.offset + e.length >= b) e];
    if (covering.isEmpty) {
      spans.add(TextSpan(text: piece));
      continue;
    }
    var style = const TextStyle();
    final decorations = <TextDecoration>[];
    VoidCallback? tap;
    var spoiler = false;
    for (final e in covering) {
      final whole = text.substring(e.offset, e.offset + e.length);
      switch (e.type) {
        case td.TextEntityTypeBold():
          style = style.copyWith(fontWeight: FontWeight.w700);
        case td.TextEntityTypeItalic():
          style = style.copyWith(fontStyle: FontStyle.italic);
        case td.TextEntityTypeUnderline():
          decorations.add(TextDecoration.underline);
        case td.TextEntityTypeStrikethrough():
          decorations.add(TextDecoration.lineThrough);
        case td.TextEntityTypeSpoiler():
          spoiler = true;
        case td.TextEntityTypeCode() || td.TextEntityTypePre() || td.TextEntityTypePreCode():
          style = style.copyWith(fontFamily: 'monospace', backgroundColor: AppColors.surface3);
        case td.TextEntityTypeBlockQuote() || td.TextEntityTypeExpandableBlockQuote():
          style = style.copyWith(color: AppColors.text2, fontStyle: FontStyle.italic);
        case td.TextEntityTypeUrl():
          tap ??= () => openUrl(whole.contains('://') ? whole : 'https://$whole');
        case td.TextEntityTypeTextUrl(url: final u):
          tap ??= () => openUrl(u);
        case td.TextEntityTypeEmailAddress():
          tap ??= () => openUrl('mailto:$whole');
        case td.TextEntityTypePhoneNumber():
          tap ??= () => openUrl('tel:$whole');
        case td.TextEntityTypeMention():
          tap ??= () => openUrl('https://t.me/${whole.replaceFirst('@', '')}');
        case td.TextEntityTypeMentionName(:final userId):
          tap ??= () => openUser(userId);
        case td.TextEntityTypeHashtag() || td.TextEntityTypeCashtag():
          tap ??= () => openHashtag(whole);
        case td.TextEntityTypeBotCommand():
          tap ??= () => copyBotCommand(whole);
        default:
          break;
      }
    }
    if (decorations.isNotEmpty || tap != null) {
      style = style.copyWith(
        decoration: TextDecoration.combine([...decorations, if (tap != null) TextDecoration.underline]),
        decorationColor: tap != null ? tint.withValues(alpha: 0.85) : null,
        decorationThickness: tap != null ? 1.25 : null,
      );
    }
    if (tap != null) style = style.copyWith(color: tint, fontWeight: style.fontWeight ?? FontWeight.w600);
    if (spoiler && !selectable) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _Spoiler(text: piece, style: style),
        ),
      );
      continue;
    }
    if (spoiler) style = style.copyWith(backgroundColor: AppColors.text3.withValues(alpha: 0.35));
    final onTap = tap;
    spans.add(
      TextSpan(
        text: piece,
        style: style,
        recognizer: onTap == null ? null : (TapGestureRecognizer()..onTap = onTap),
      ),
    );
  }
  return TextSpan(children: spans);
}

/// Hidden text that shows when tapped, like Telegram's spoilers.
class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _shown = !_shown),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: _shown ? Colors.transparent : AppColors.text3.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.text,
        style: DefaultTextStyle.of(context).style.merge(widget.style).copyWith(
          color: _shown ? null : Colors.transparent,
        ),
      ),
    ),
  );
}

/// Profile descriptions don't always arrive with entities from TDLib, even
/// though Telegram itself makes their URLs and @usernames interactive. Add
/// the same minimal entity layer before rendering when that happens.
td.FormattedText _linkify(td.FormattedText formatted) {
  final text = formatted.text;
  final entities = [...formatted.entities];
  final matches = RegExp(
    r'(?:(?:https?://|www\.)[^\s<>()]+|(?<![\w@/.])(?:[a-z0-9-]+\.)+(?:com|org|net|io|me|app|dev|co|ai|tv|gg|xyz|info|ly|to|so|link|us|uk|et|site|store|shop|news|live|pro|biz)(?:/[^\s<>()]*)?(?![\w.])|(?<![\w@])@[A-Za-z][A-Za-z0-9_]{4,31}|(?<![\w])#[\p{L}\p{N}_]{2,}|(?<![\w])\$[A-Za-z]{1,8}(?![\w]))',
    caseSensitive: false,
    unicode: true,
  ).allMatches(text);
  for (final m in matches) {
    final value = m.group(0)!;
    // Trim punctuation people naturally put right after a link.
    var length = value.length;
    while (length > 0 && '.,!?;:)]}'.contains(value[length - 1])) {
      length--;
    }
    if (length == 0) {
      continue;
    }
    if (entities.any(
      (e) => m.start < e.offset + e.length && m.start + length > e.offset,
    )) {
      continue;
    }
    entities.add(
      td.TextEntity(
        offset: m.start,
        length: length,
        type: value.startsWith('@')
            ? const td.TextEntityTypeMention()
            : value.startsWith('#')
            ? const td.TextEntityTypeHashtag()
            : value.startsWith(r'$')
            ? const td.TextEntityTypeCashtag()
            : const td.TextEntityTypeUrl(),
      ),
    );
  }
  return td.FormattedText(text: text, entities: entities);
}

/// A voice note's waveform: 5-bit samples packed little-endian.
List<int> decodeWaveform(String base64Data, {int bars = 40}) {
  List<int> bytes;
  try {
    bytes = base64Decode(base64Data);
  } catch (_) {
    bytes = const [];
  }
  final count = bytes.length * 8 ~/ 5;
  if (count == 0) return List.filled(bars, 4);
  final values = <int>[];
  for (var i = 0; i < count; i++) {
    final bit = i * 5;
    final byte = bit ~/ 8;
    final shift = bit % 8;
    final lo = bytes[byte];
    final hi = byte + 1 < bytes.length ? bytes[byte + 1] : 0;
    values.add(((lo | (hi << 8)) >> shift) & 31);
  }
  return [
    for (var b = 0; b < bars; b++)
      values[(b * values.length / bars).floor().clamp(0, values.length - 1)],
  ];
}
