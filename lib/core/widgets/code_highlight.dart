import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/settings/data/settings.dart';

/// Colours for code, from the code theme chosen in Settings → Chat.
class CodePalette {
  const CodePalette({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.function,
    required this.type,
    required this.decorator,
  });
  final Color keyword, string, number, comment, function, type, decorator;

  /// [theme]'s colours, deepened on a light page so they stay readable.
  static CodePalette of(CodeThemeChoice theme) {
    final p = _of(theme);
    return AppColors.isLight ? p._forLight() : p;
  }

  CodePalette _forLight() {
    Color d(Color c) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness(0.34).withSaturation((hsl.saturation * 1.1).clamp(0, 1)).toColor();
    }

    return CodePalette(
      keyword: d(keyword),
      string: d(string),
      number: d(number),
      comment: const Color(0xFF6B7280),
      function: d(function),
      type: d(type),
      decorator: d(decorator),
    );
  }

  static CodePalette _of(CodeThemeChoice theme) => switch (theme) {
    CodeThemeChoice.midnight => const CodePalette(
      keyword: Color(0xFF7DD3FC),
      string: Color(0xFFFDE68A),
      number: Color(0xFFC4B5FD),
      comment: Color(0xFF94A3B8),
      function: Color(0xFF86EFAC),
      type: Color(0xFFF9A8D4),
      decorator: Color(0xFFFDBA74),
    ),
    CodeThemeChoice.ocean => const CodePalette(
      keyword: Color(0xFF67E8F9),
      string: Color(0xFFF9A8D4),
      number: Color(0xFF86EFAC),
      comment: Color(0xFF9CA3AF),
      function: Color(0xFF93C5FD),
      type: Color(0xFFFDE68A),
      decorator: Color(0xFFC4B5FD),
    ),
    CodeThemeChoice.ember => const CodePalette(
      keyword: Color(0xFFFDA4AF),
      string: Color(0xFF86EFAC),
      number: Color(0xFFFCD34D),
      comment: Color(0xFFA1A1AA),
      function: Color(0xFFFDBA74),
      type: Color(0xFF7DD3FC),
      decorator: Color(0xFFC4B5FD),
    ),
  };
}

const _keywords = <String, Set<String>>{
  'python': {
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif', //
    'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or', //
    'pass', 'raise', 'return', 'try', 'while', 'with', 'yield', 'match', 'case', 'self',
  },
  'javascript': {
    'async', 'await', 'break', 'case', 'catch', 'class', '', 'continue', 'default', 'delete', 'do', 'else', 'export', //
    'extends', 'false', 'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'null', 'of', //
    'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void', 'while', 'yield', 'from',
  },
  'bash': {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case', 'esac', 'in', 'function', 'return', 'export', //
    'local', 'echo', 'cd', 'sudo', 'pip', 'apt', 'git', 'ls', 'cat', 'grep', 'curl', 'wget', 'python', 'npm', 'set',
  },
  'r': {'if', 'else', 'for', 'while', 'repeat', 'function', 'return', 'next', 'break', 'TRUE', 'FALSE', 'NULL', 'NA', 'library', 'in'},
  'java': {
    'abstract', 'boolean', 'break', 'case', 'catch', 'char', 'class', 'continue', 'default', 'do', 'double', 'else', //
    'extends', 'false', 'final', 'finally', 'float', 'for', 'if', 'implements', 'import', 'int', 'interface', 'long', //
    'new', 'null', 'package', 'private', 'protected', 'public', 'return', 'static', 'super', 'switch', 'this', 'throw', //
    'throws', 'true', 'try', 'var', 'void', 'while',
  },
};

String _family(String language) => switch (language.toLowerCase()) {
  'py' || 'python' || 'python3' => 'python',
  'js' || 'javascript' || 'ts' || 'typescript' || 'node' || 'json' => 'javascript',
  'sh' || 'bash' || 'shell' || 'zsh' => 'bash',
  'r' => 'r',
  'java' || 'kotlin' || 'dart' || 'c' || 'cpp' || 'go' => 'java',
  _ => 'python',
};

/// Coloured spans for [source] in [language]: comments, strings (with
/// Python's triple quotes), numbers, keywords, decorators, calls and types.
List<TextSpan> highlightCode(String source, String language, CodePalette p) {
  final family = _family(language);
  final keywords = _keywords[family]!;
  final hashComments = family == 'python' || family == 'bash' || family == 'r';
  final pattern = RegExp(
    [
      if (family == 'python') r'"""[\s\S]*?(?:"""|$)|' "'''" r"[\s\S]*?(?:'''|$)",
      if (hashComments) r'#[^\n]*',
      if (!hashComments) r'//[^\n]*|/\*[\s\S]*?(?:\*/|$)',
      r'"(?:\\.|[^"\\\n])*"?',
      r"'(?:\\.|[^'\\\n])*'?",
      if (family == 'javascript') r'`(?:\\.|[^`\\])*`?',
      r'@[A-Za-z_][\w.]*',
      r'\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\b0x[0-9a-fA-F]+\b',
      r'\$\{?[A-Za-z_]\w*\}?',
      r'[A-Za-z_]\w*',
    ].join('|'),
  );
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in pattern.allMatches(source)) {
    if (m.start > at) spans.add(TextSpan(text: source.substring(at, m.start)));
    final t = m[0]!;
    Color? color;
    var bold = false;
    var italic = false;
    if (t.startsWith('#') && hashComments || t.startsWith('//') || t.startsWith('/*')) {
      color = p.comment;
      italic = true;
    } else if (t.startsWith('"') || t.startsWith("'") || t.startsWith('`')) {
      color = p.string;
    } else if (t.startsWith('@')) {
      color = p.decorator;
    } else if (t.startsWith(r'$')) {
      color = p.type;
    } else if (RegExp(r'^\d|^0x').hasMatch(t)) {
      color = p.number;
    } else if (keywords.contains(t)) {
      color = p.keyword;
      bold = true;
    } else if (m.end < source.length && source[m.end] == '(') {
      color = p.function;
    } else if (RegExp(r'^[A-Z][a-z]\w*$').hasMatch(t)) {
      color = p.type;
    }
    spans.add(
      color == null
          ? TextSpan(text: t)
          : TextSpan(
              text: t,
              style: TextStyle(color: color, fontWeight: bold ? FontWeight.w600 : null, fontStyle: italic ? FontStyle.italic : null),
            ),
    );
    at = m.end;
  }
  if (at < source.length) spans.add(TextSpan(text: source.substring(at)));
  return spans;
}

/// Read on every use: the text colour follows a switch between light and
/// dark.
TextStyle get codeTextStyle => TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.45, color: AppColors.text);

/// Read-only highlighted code, selectable, scrolling sideways.
class HighlightedCode extends StatelessWidget {
  const HighlightedCode({super.key, required this.code, required this.language, required this.theme, this.maxLines});
  final String code;
  final String language;
  final CodeThemeChoice theme;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    final shown = maxLines == null || lines.length <= maxLines! ? code : lines.take(maxLines!).join('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText.rich(
        TextSpan(style: codeTextStyle, children: highlightCode(shown, language, CodePalette.of(theme))),
      ),
    );
  }
}

/// A text controller that colours what is typed: the editor's highlighting.
class HighlightingController extends TextEditingController {
  HighlightingController({super.text, required this.language, required this.theme});
  String language;
  CodeThemeChoice theme;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return TextSpan(style: style, children: highlightCode(text, language, CodePalette.of(theme)));
  }
}
