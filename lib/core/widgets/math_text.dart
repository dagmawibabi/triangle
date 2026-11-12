import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Text that may hold LaTeX, as paper titles and abstracts do: `$…$`,
/// `\(…\)` inline and `$$…$$`, `\[…\]` on their own. The math is typeset;
/// the prose around it has its TeX escapes and markup (`\%`, `--`,
/// `\emph{…}`, ``quotes'') turned into plain characters. A formula that
/// does not parse is shown as its source rather than dropped.
class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.selectable = false, this.textAlign});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  final TextAlign? textAlign;

  /// Whether [s] looks like it holds any LaTeX worth typesetting.
  static bool hasMath(String s) => _math.hasMatch(s) || _markup.hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final source = _normalise(text);
    if (!hasMath(source)) {
      final t = Text(source, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
      return selectable ? SelectionArea(child: t) : t;
    }
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _math.allMatches(source)) {
      if (m.start > at) spans.add(TextSpan(text: _prose(source.substring(at, m.start))));
      final display = m.group(1) != null || m.group(2) != null;
      final tex = (m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
      spans.add(_formula(tex, display, base));
      at = m.end;
    }
    if (at < source.length) spans.add(TextSpan(text: _prose(source.substring(at))));
    final t = Text.rich(TextSpan(children: spans), style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
    return selectable ? SelectionArea(child: t) : t;
  }

  InlineSpan _formula(String tex, bool display, TextStyle base) {
    if (tex.isEmpty) return const TextSpan();
    Widget math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: base.copyWith(height: 1),
      onErrorFallback: (_) => Text(display ? '\$\$$tex\$\$' : '\$$tex\$', style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) * 0.92)),
    );
    if (display) {
      math = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: math),
      );
    }
    return WidgetSpan(alignment: PlaceholderAlignment.middle, baseline: TextBaseline.alphabetic, child: math);
  }
}

// $$…$$ | \[…\] | \(…\) | $…$ — a lone $ must hug its content and not be
// followed by a digit, so "$5 and $10" stays prose.
final _math = RegExp(
  r'\$\$([\s\S]+?)\$\$'
  r'|\\\[([\s\S]+?)\\\]'
  r'|\\\(([\s\S]+?)\\\)'
  r'|(?<![\\$])\$(?!\s)((?:\\\$|[^$\n])+?)(?<!\s)\$(?!\d)',
);

final _markup = RegExp(r'\\(?:emph|textit|textbf|textrm|texttt|textsc|mathrm|url|href|cite|%|&|_|#)|``|---?|[A-Za-z.]~\S');

/// Single line breaks (abstracts come hard-wrapped) become spaces; blank
/// lines stay paragraph breaks.
String _normalise(String s) => s
    .replaceAll('\r\n', '\n')
    .replaceAllMapped(RegExp(r'([^\n])\n(?!\n)'), (m) => '${m[1]} ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();

String _prose(String s) {
  var out = s;
  // \emph{x} → x, a few levels deep for nested braces.
  for (var i = 0; i < 3; i++) {
    out = out.replaceAllMapped(RegExp(r'\\(?:emph|textit|textbf|textrm|texttt|textsc|mathrm|url)\{([^{}]*)\}'), (m) => m[1]!);
  }
  out = out
      .replaceAllMapped(RegExp(r'\\href\{([^{}]*)\}\{([^{}]*)\}'), (m) => m[2]!)
      .replaceAll(RegExp(r'\\cite[pt]?\{[^{}]*\}'), '')
      .replaceAll('---', '—')
      .replaceAll('--', '–')
      .replaceAll('``', '“')
      .replaceAll("''", '”')
      .replaceAll(RegExp(r'(?<=[A-Za-z.])~(?=\S)'), '\u00a0')
      .replaceAllMapped(RegExp(r'\\([%&_#$])'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\{\\(?:it|bf|em|sc|rm|tt)\s+([^{}]*)\}'), (m) => m[1]!);
  return out;
}
