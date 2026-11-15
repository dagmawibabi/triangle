import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/widgets/code_highlight.dart';
import '../settings/data/settings.dart';
import 'package:omni_ai/omni_ai.dart' show E2BClient;
import 'e2b_session.dart';

/// Write, edit and run code in the E2B sandbox by hand, with syntax
/// highlighting, line numbers, auto-indent and a key row for symbols. Opened
/// from Settings, or from a code card in the chat to change and rerun what
/// the assistant ran. Runs share the assistant's sandbox, so its variables
/// and files are there too.
class CodeEditorScreen extends ConsumerStatefulWidget {
  const CodeEditorScreen({super.key, this.code, this.language = 'python'});
  final String? code;
  final String language;

  @override
  ConsumerState<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

const _examples = <String, String>{
  'python': '''import numpy as np
import matplotlib.pyplot as plt

x = np.linspace(0, 4 * np.pi, 400)
plt.figure(figsize=(7, 3.5))
plt.plot(x, np.sin(x), label="sin")
plt.plot(x, np.cos(x), label="cos")
plt.legend()
plt.title("Hello from E2B")
plt.show()
''',
  'javascript': '''const xs = Array.from({ length: 10 }, (_, i) => i * i);
console.log(xs);
xs.reduce((a, b) => a + b, 0);
''',
  'bash': '''uname -a
python3 --version
df -h /
''',
  'r': '''x <- rnorm(100)
summary(x)
''',
  'java': '''System.out.println("Hello from E2B");
''',
};

class _CodeEditorScreenState extends ConsumerState<CodeEditorScreen> {
  late String _language = E2BClient.languages.contains(widget.language) ? widget.language : 'python';
  late final HighlightingController _code = HighlightingController(
    text: widget.code ?? '',
    language: _language,
    theme: ref.read(settingsProvider).codeTheme,
  );
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _live = <(String, bool)>[];
  E2bRun? _run;
  String? _failure;
  bool _running = false;
  Timer? _save;

  static const _draftKey = 'e2b_editor_draft';

  @override
  void initState() {
    super.initState();
    if (widget.code == null) _loadDraft();
    _code.addListener(_onEdit);
  }

  Future<void> _loadDraft() async {
    final p = await SharedPreferences.getInstance();
    final lang = p.getString('$_draftKey.language');
    final text = p.getString(_draftKey);
    if (!mounted) return;
    setState(() {
      if (lang != null && E2BClient.languages.contains(lang)) _language = _code.language = lang;
      _code.text = text ?? _examples[_language]!;
    });
  }

  void _onEdit() {
    setState(() {});
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_draftKey, _code.text);
      await p.setString('$_draftKey.language', _language);
    });
  }

  @override
  void dispose() {
    _save?.cancel();
    _code.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _insert(String s, {int back = 0}) {
    final sel = _code.selection;
    final text = _code.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, s);
    _code.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + s.length - back));
    _focus.requestFocus();
  }

  Future<void> _runCode() async {
    final s = ref.read(settingsProvider);
    if (!s.hasE2bKey) {
      showSnack(context, 'Add an E2B key in Settings → Apps & web → E2B', icon: Icons.key_off_outlined);
      return;
    }
    if (_code.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _failure = null;
      _run = null;
      _live.clear();
    });
    final session = ref.read(e2bSessionProvider);
    session.by = 'the code editor';
    try {
      final run = await session.run(
        _code.text,
        language: _language,
        timeout: const Duration(minutes: 5),
        onLine: (line, {required error}) {
          if (mounted) setState(() => _live.add((line, error)));
        },
      );
      if (mounted) setState(() => _run = run);
    } catch (e) {
      if (mounted) setState(() => _failure = '$e');
    } finally {
      session.by = 'the assistant';
      if (mounted) setState(() => _running = false);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(settingsProvider.select((s) => s.codeTheme));
    _code.theme = theme;
    final session = ref.watch(e2bSessionProvider);
    final lines = '\n'.allMatches(_code.text).length + 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code sandbox'),
        actions: [
          ValueListenableBuilder(
            valueListenable: session.changes,
            builder: (_, _, _) => Tooltip(
              message: session.current == null ? 'No sandbox running; one starts with the first run' : 'Sandbox ${session.current!.id}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                child: Icon(Icons.circle, size: 10, color: session.current == null ? AppColors.text3 : AppColors.success),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'copy':
                  await Clipboard.setData(ClipboardData(text: _code.text));
                  if (context.mounted) showSnack(context, 'Code copied');
                case 'example':
                  _code.text = _examples[_language]!;
                case 'clear':
                  _code.clear();
                case 'restart':
                  try {
                    await session.restart();
                    if (context.mounted) showSnack(context, 'Fresh sandbox started');
                  } catch (e) {
                    if (context.mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy code')),
              PopupMenuItem(value: 'example', child: Text('Insert an example')),
              PopupMenuItem(value: 'clear', child: Text('Clear the editor')),
              PopupMenuItem(value: 'restart', child: Text('Restart the sandbox')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? null : _runCode,
        icon: _running
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow_rounded),
        label: Text(_running ? 'Running…' : 'Run'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final l in E2BClient.languages) ...[
                    ChoiceChip(
                      label: Text(l == 'javascript' ? 'JavaScript' : (l == 'r' ? 'R' : '${l[0].toUpperCase()}${l.substring(1)}')),
                      selected: _language == l,
                      onSelected: (_) => setState(() {
                        _language = _code.language = l;
                        if (_code.text.trim().isEmpty) _code.text = _examples[l]!;
                        _onEdit();
                      }),
                    ),
                    const SizedBox(width: Space.s),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 96),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.m),
                    border: Border.all(color: _focus.hasFocus ? AppColors.tint.withValues(alpha: 0.6) : AppColors.line),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: Space.m),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        padding: const EdgeInsets.only(right: 8, top: 1),
                        child: Text(
                          [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
                          textAlign: TextAlign.right,
                          style: codeTextStyle.copyWith(color: AppColors.text3),
                        ),
                      ),
                      Expanded(
                        child: Focus(
                          onKeyEvent: (_, e) {
                            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
                              _insert('    ');
                              return KeyEventResult.handled;
                            }
                            if (e is KeyDownEvent &&
                                e.logicalKey == LogicalKeyboardKey.enter &&
                                HardwareKeyboard.instance.isControlPressed) {
                              _runCode();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _code,
                            focusNode: _focus,
                            maxLines: null,
                            minLines: 12,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            enableSuggestions: false,
                            smartQuotesType: SmartQuotesType.disabled,
                            smartDashesType: SmartDashesType.disabled,
                            inputFormatters: [_AutoIndent()],
                            style: codeTextStyle,
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.only(right: Space.m),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_live.isNotEmpty || _run != null || _failure != null) ...[
                  const SizedBox(height: Space.l),
                  _Output(run: _run, live: _live, failure: _failure, running: _running),
                ],
              ],
            ),
          ),
          if (_focus.hasFocus) _KeyRow(onKey: _insert),
        ],
      ),
    );
  }
}

/// A new line keeps the indent of the one before, one level deeper after
/// a line ending in ':' or an opening bracket.
class _AutoIndent extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    if (next.text.length != old.text.length + 1 || !next.selection.isCollapsed) return next;
    final at = next.selection.baseOffset;
    if (at <= 0 || next.text[at - 1] != '\n') return next;
    final before = next.text.substring(0, at - 1);
    final line = before.substring(before.lastIndexOf('\n') + 1);
    var indent = RegExp(r'^[ \t]*').firstMatch(line)![0]!;
    if (RegExp(r'[:{(\[]\s*$').hasMatch(line)) indent += '    ';
    if (indent.isEmpty) return next;
    final text = next.text.replaceRange(at, at, indent);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at + indent.length));
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.onKey});
  final void Function(String s, {int back}) onKey;

  @override
  Widget build(BuildContext context) {
    const keys = [('⇥', '    ', 0), ('()', '()', 1), ('[]', '[]', 1), ('{}', '{}', 1), ('""', '""', 1), ("''", "''", 1), (':', ':', 0), ('=', '=', 0), ('#', '# ', 0), ('_', '_', 0), ('.', '.', 0), (',', ', ', 0), ('<', '<', 0), ('>', '>', 0), ('+', '+', 0), ('-', '-', 0), ('*', '*', 0), ('/', '/', 0), ('\\', '\\', 0), ('|', '|', 0), (r'$', r'$', 0)];
    return Material(
      color: AppColors.surface2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            children: [
              for (final (label, text, back) in keys)
                InkWell(
                  onTap: () => onKey(text, back: back),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    child: Text(label, style: codeTextStyle.copyWith(fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Output extends StatelessWidget {
  const _Output({required this.run, required this.live, required this.failure, required this.running});
  final E2bRun? run;
  final List<(String, bool)> live;
  final String? failure;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final r = run;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: (r?.error != null || failure != null) ? AppColors.danger.withValues(alpha: 0.6) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('OUTPUT', style: context.text.labelSmall),
              const Spacer(),
              if (running) const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
              if (r != null) Text('${r.count == null ? '' : '[${r.count}] '}${(r.ms / 1000).toStringAsFixed(1)} s', style: context.text.labelSmall),
            ],
          ),
          const SizedBox(height: Space.s),
          if (failure != null) SelectableText(failure!, style: codeTextStyle.copyWith(color: AppColors.danger)),
          if (r == null && live.isNotEmpty)
            SelectableText.rich(
              TextSpan(
                style: codeTextStyle,
                children: [for (final (line, err) in live) TextSpan(text: line, style: err ? TextStyle(color: AppColors.warning) : null)],
              ),
            ),
          if (r != null) ...[
            if (r.stdout.isNotEmpty) SelectableText(r.stdout.trimRight(), style: codeTextStyle),
            if (r.stderr.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              SelectableText(r.stderr.trimRight(), style: codeTextStyle.copyWith(color: AppColors.warning)),
            ],
            for (final res in r.results) ...[
              const SizedBox(height: Space.s),
              if (res['markdown'] != null)
                MarkdownBody(data: '${res['markdown']}', selectable: true)
              else if (res['text'] != null)
                SelectableText('${res['text']}', style: codeTextStyle.copyWith(color: AppColors.accent)),
            ],
            for (final img in r.images) ...[
              const SizedBox(height: Space.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.s),
                child: Container(color: Colors.white, child: Image.file(File(img))),
              ),
            ],
            if (r.error != null) ...[
              const SizedBox(height: Space.s),
              SelectableText(
                '${r.error!['name']}: ${r.error!['value']}\n${r.error!['traceback'] ?? ''}'.trim(),
                style: codeTextStyle.copyWith(color: AppColors.danger, fontSize: 12.5),
              ),
            ],
            if (r.stdout.isEmpty && r.stderr.isEmpty && r.results.isEmpty && r.images.isEmpty && r.error == null)
              Text('Ran, with no output.', style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }
}
