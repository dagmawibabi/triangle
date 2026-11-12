import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/code_highlight.dart';
import '../../../voice/player_sheet.dart';
import '../../../voice/speaker.dart';
import '../../domain/chat_models.dart';
import '../../../assistant/presentation/watch_event_sheet.dart';
import '../../../settings/data/settings.dart';
import '../../../settings/presentation/model_picker_screen.dart' show showModelDetails;
import '../../../ai/data/ai.dart';
import '../../../integrations/code_editor_screen.dart';
import 'post_viewer.dart';
import 'post_sources.dart';
import 'thinking_block.dart';
import 'tool_card.dart';
import '../../../telegram/presentation/link_opener.dart';

final _postRef = RegExp(r'post:(-?\d+):(\d+)');

class UserBubble extends ConsumerWidget {
  const UserBubble({super.key, required this.entry, this.posts = const {}});
  final UserEntry entry;
  final Map<String, PostSnapshot> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDateTime = ref.watch(settingsProvider.select((s) => s.showChatDateTime));
    final showCompact = ref.watch(settingsProvider.select((s) => s.compactChat));
    final event = entry.event;
    if (event != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.l),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.l),
            onTap: () => showWatchEventSheet(context, entry, posts),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(
                  color: AppColors.activeAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 15,
                        color: AppColors.activeAccent,
                      ),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(
                          'Watch · $event',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.activeAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showDateTime) Text(
                        TimeOfDay.fromDateTime(entry.at.toLocal()).format(context),
                        style: context.text.labelSmall,
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.text3,
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    entry.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: entry.text));
            showSnack(context, 'Copied');
          },
          child: Padding(
            padding: EdgeInsets.only(bottom: showCompact ? Space.s : Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (entry.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final a in entry.attachments)
                          _SentAttachment(attachment: a),
                      ],
                    ),
                  ),
                if (entry.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.l,
                      vertical: Space.m,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(Radii.xl),
                    ),
                    child: Text(entry.text, style: context.text.bodyLarge),
                  ),
                if (showDateTime) ...[
                const SizedBox(height: Space.xs),
                Padding(
                  padding: const EdgeInsets.only(right: Space.xs),
                  child: Text(
                    TimeOfDay.fromDateTime(entry.at.toLocal()).format(context),
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AssistantMessage extends ConsumerWidget {
  const AssistantMessage({
    super.key,
    required this.entry,
    required this.posts,
    required this.streaming,
  });

  final AssistantEntry entry;
  final Map<String, PostSnapshot> posts;

  /// This is the reply still being written.
  final bool streaming;

  /// Posts the answer links to, in the order it first mentions them.
  List<PostSnapshot> _cited() {
    final seen = <String>{};
    final out = <PostSnapshot>[];
    for (final s in entry.steps) {
      for (final m in _postRef.allMatches(s.text)) {
        final key = '${m[1]}:${m[2]}';
        final p = posts[key];
        if (p != null && seen.add(key)) out.add(p);
      }
    }
    return out;
  }

  void _openLink(BuildContext context, String? href) {
    if (href == null) return;
    final m = _postRef.firstMatch(href);
    if (m != null) {
      final key = '${m[1]}:${m[2]}';
      final p =
          posts[key] ??
          PostSnapshot(
            chatId: int.parse(m[1]!),
            messageId: int.parse(m[2]!),
            chatTitle: 'Post',
            date: DateTime.now(),
            text: '',
          );
      showPost(context, p);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri != null) openUrl(href, context: context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[];
    final prefs = ref.watch(settingsProvider);
    for (final (i, s) in entry.steps.indexed) {
      final last = i == entry.steps.length - 1;
      if (s.reasoning.trim().isNotEmpty && prefs.showThinking) {
        children.add(
          ThinkingBlock(
            text: s.reasoning,
            active: streaming && last && s.text.isEmpty && s.tools.isEmpty,
            durationMs: s.thinkingMs,
          ),
        );
      }
      if (s.text.trim().isNotEmpty) {
        children.add(
          GestureDetector(
            // Long-press: the answer in a sheet where any of it can be selected.
            onLongPress: () {
              HapticFeedback.selectionClick();
              showSelectableAnswer(context, entry);
            },
            child: Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tables are drawn apart, so they can scroll sideways.
                for (final part in splitTables(s.text))
                  if (part.markdown != null)
                    MarkdownBody(
                      data: part.markdown!,
                      selectable: false,
                      styleSheet: _markdownStyle(context),
                      syntaxHighlighter: _CodeHighlighter(
                        ref.watch(settingsProvider).codeTheme,
                      ),
                      builders: {'pre': _CodeBlockBuilder(_CodeHighlighter(ref.watch(settingsProvider).codeTheme))},
                      onTapLink: (text, href, title) => _openLink(context, href),
                    )
                  else
                    MarkdownTable(head: part.head!, rows: part.rows!, onLink: (href) => _openLink(context, href)),
              ],
            ),
          ),
          ),
        );
      }
      for (final t in s.tools) {
        // With tool cards hidden, approvals still show: they need a tap.
        if (prefs.showToolCalls || t.status == ToolStatus.awaitingApproval) {
          children.add(ToolCallCard(key: ValueKey(t.callId), part: t));
        }
      }
    }
    final waiting =
        streaming &&
        (entry.steps.isEmpty ||
            (entry.steps.last.text.isEmpty &&
                entry.steps.last.reasoning.isEmpty &&
                entry.steps.last.tools.isEmpty) ||
            entry.steps.last.tools.isNotEmpty &&
                entry.steps.last.tools.every(
                  (t) =>
                      t.status != ToolStatus.running &&
                      t.status != ToolStatus.awaitingApproval,
                ));
    if (waiting) children.add(const _Typing());

    if (entry.notice != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  entry.notice!,
                  style: context.text.bodySmall?.copyWith(color: AppColors.text2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (entry.error != null) {
      children.add(
        Container(
          margin: const EdgeInsets.only(top: Space.xs),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  entry.error!,
                  style: context.text.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cited = streaming ? const <PostSnapshot>[] : _cited();
    if (cited.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: PostSources(posts: cited),
        ),
      );
    }

    final finalText = entry.steps
        .map((s) => s.text)
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
    if (!streaming && finalText.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(
            children: [
              if (prefs.showChatCopyButton) _ActionIcon(
                icon: Icons.copy_rounded,
                tooltip: 'Copy',
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: finalText.replaceAllMapped(
                        RegExp(r'\]\(post:[^)]+\)'),
                        (_) => ']',
                      ),
                    ),
                  );
                  showSnack(context, 'Copied');
                },
              ),
              if (prefs.showChatSpeakButton && prefs.voiceEnabled) _ReadAloudButton(entry: entry, text: finalText),
              if (entry.model.isNotEmpty && prefs.showModelName) ...[
                const SizedBox(width: Space.xs),
                Flexible(
                  // The model that wrote this answer: tap for what it is and costs.
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.s),
                    onTap: () {
                      final info = ref.read(modelCatalogProvider).byId(entry.model);
                      if (info != null) {
                        showModelDetails(context, info);
                      } else {
                        showSnack(context, 'No details for ${modelLabel(entry.model)}', icon: Icons.info_outline_rounded);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        entry.model.replaceFirst('or:', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.line),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      children.add(_UsageLine(entry: entry));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: prefs.compactChat ? Space.m : Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final body = context.text.bodyLarge!;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      listBullet: body,
      a: body.copyWith(
        color: AppColors.activeAccent,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accent.withValues(alpha: 0.4),
      ),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      h1: context.text.titleLarge,
      h2: context.text.titleMedium?.copyWith(fontSize: 17),
      h3: context.text.titleSmall?.copyWith(fontSize: 15.5),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5,
        backgroundColor: AppColors.surface2,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: AppColors.line),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.line, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: Space.m),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      tableBorder: TableBorder.all(color: AppColors.line),
      tableHead: body.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
      tableBody: body.copyWith(fontSize: 14),
      pPadding: const EdgeInsets.only(bottom: 2),
    );
  }
}

/// Lightweight token colouring for fenced code blocks, with user-selectable
/// palettes. It covers common Dart, JavaScript, Python, JSON and shell output.
class _CodeHighlighter extends SyntaxHighlighter {
  _CodeHighlighter(this.theme);
  final CodeThemeChoice theme;

  @override
  TextSpan format(String source) {
    // Chat code uses the same colours as the code theme's preview, deepened
    // on a light page.
    final p = CodePalette.of(theme);
    final colors = (p.keyword, p.number, p.string, p.comment);
    final token = RegExp(
      r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|//[^\n]*|#[^\n]*|\b(?:class|final|const|return|if|else|for|while|import|from|def|function|async|await|void|int|double|String|true|false|null)\b|\b\d+(?:\.\d+)?\b)''',
    );
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in token.allMatches(source)) {
      if (match.start > at)
        spans.add(TextSpan(text: source.substring(at, match.start)));
      final text = match.group(0)!;
      final color = text.startsWith('//') || text.startsWith('#')
          ? colors.$4
          : (text.startsWith('"') || text.startsWith("'")
                ? colors.$3
                : (RegExp(r'^\d').hasMatch(text) ? colors.$2 : colors.$1));
      spans.add(
        TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontWeight: color == colors.$1 ? FontWeight.w600 : null,
          ),
        ),
      );
      at = match.end;
    }
    if (at < source.length) spans.add(TextSpan(text: source.substring(at)));
    return TextSpan(
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5,
        color: AppColors.text,
      ),
      children: spans,
    );
  }
}

/// An answer in a sheet whose text can be selected word by word and copied.
Future<void> showSelectableAnswer(BuildContext context, AssistantEntry entry) {
  final text = entry.steps.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join('\n\n');
  return showAppSheet<void>(
    context,
    initialSize: 0.7,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Row(
          children: [
            Expanded(child: Text('Select text', style: context.text.titleMedium)),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                showSnack(context, 'Copied');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy all'),
            ),
          ],
        ),
        Text('Press and hold a word, then drag the handles.', style: context.text.bodySmall),
        const SizedBox(height: Space.l),
        MarkdownBody(
          data: text,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: context.text.bodyLarge,
            code: TextStyle(fontFamily: 'monospace', fontSize: 13.5, backgroundColor: AppColors.surface2),
          ),
        ),
      ],
    ),
  );
}

/// Fenced code in an answer: a card with its language, Copy and Expand,
/// that opens full screen in the code editor when tapped.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.highlighter);
  final _CodeHighlighter highlighter;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    final inner = element.children?.whereType<md.Element>().firstOrNull;
    final language = '${inner?.attributes['class'] ?? ''}'.replaceFirst('language-', '');
    return _CodeBlock(code: code, language: language, theme: highlighter.theme);
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language, required this.theme});
  final String code;
  final String language;
  final CodeThemeChoice theme;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CodeEditorScreen(code: code, language: _editorLanguage(language)),
    ),
  );

  /// The editor's name for [language], e.g. `py` → python.
  static String _editorLanguage(String language) => switch (language.toLowerCase()) {
    'py' || 'python' || 'python3' => 'python',
    'js' || 'javascript' || 'ts' || 'typescript' || 'node' => 'javascript',
    'sh' || 'bash' || 'shell' || 'zsh' => 'bash',
    'r' => 'r',
    'java' => 'java',
    _ => 'python',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        side: BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.surface2,
              padding: const EdgeInsets.fromLTRB(Space.m, 2, 2, 2),
              child: Row(
                children: [
                  Text(language.isEmpty ? 'code' : language, style: context.text.labelSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.copy_rounded, size: 16, color: AppColors.text2),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      showSnack(context, 'Code copied');
                    },
                  ),
                  IconButton(
                    tooltip: 'Open full screen',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.open_in_full_rounded, size: 16, color: AppColors.text2),
                    onPressed: () => _open(context),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(Space.m),
              // Plain text, so a tap anywhere opens the editor.
              child: Text.rich(TextSpan(style: codeTextStyle, children: highlightCode(code, language, CodePalette.of(theme)))),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    icon: Icon(icon, size: 16, color: color ?? AppColors.text3),
    onPressed: onTap,
  );
}

/// Three dots that breathe while the model is working.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.text2.withValues(
                    alpha:
                        0.25 +
                        0.75 * (0.5 + 0.5 * _wave((_c.value - i * 0.18) % 1)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _wave(double t) =>
      t < 0.5 ? t * 2 * 2 - 1 : (1 - t) * 2 * 2 - 1;
}

class _ReadAloudButton extends ConsumerWidget {
  const _ReadAloudButton({required this.entry, required this.text});
  final AssistantEntry entry;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speaker = ref.watch(speakerProvider);
    final active = speaker.speaking && speaker.sourceId == entry.id;
    return _ActionIcon(
      icon: active ? Icons.graphic_eq_rounded : Icons.volume_up_outlined,
      tooltip: active ? 'Reading – open controls' : 'Read aloud',
      color: active ? AppColors.accent : null,
      onTap: () {
        if (!active) speaker.play(text, title: 'Answer', sourceId: entry.id);
        showPlayerSheet(context);
      },
    );
  }
}

class _SentAttachment extends StatelessWidget {
  const _SentAttachment({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final file = File(a.path);
    if (a.isImage && file.existsSync()) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                title: Text(a.name),
              ),
              body: Center(
                child: InteractiveViewer(maxScale: 5, child: Image.file(file)),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: Image.file(file, width: 160, height: 160, fit: BoxFit.cover),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.s + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            a.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.description_outlined,
            size: 20,
            color: AppColors.text2,
          ),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}


/// Tokens and cost of one answer, under it; tap for the per-call
/// breakdown. Hidden with the setting.
class _UsageLine extends ConsumerWidget {
  const _UsageLine({required this.entry});
  final AssistantEntry entry;

  static String _n(int v) => v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';

  static String money(double c) => c == 0
      ? '\$0'
      : c < 0.01
      ? '\$${c.toStringAsFixed(4)}'
      : '\$${c.toStringAsFixed(3)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider.select((s) => s.showMessageUsage))) return const SizedBox.shrink();
    final u = entry.usage;
    if (u == null) return const SizedBox.shrink();
    final calls = entry.steps.where((s) => s.usage != null).toList();
    final style = context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 11);
    return Padding(
      padding: const EdgeInsets.only(left: Space.xs, top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (c) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.toll_outlined, color: AppColors.accent),
                      const SizedBox(width: Space.m),
                      Expanded(child: Text('Usage for this answer', style: c.text.titleLarge)),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  _row(c, 'Model', entry.model.replaceFirst('or:', '')),
                  _row(c, 'Model calls', '${calls.length}'),
                  _row(c, 'Input tokens', '${u.input}'),
                  if (u.cached > 0) _row(c, '  of which cached', '${u.cached}'),
                  _row(c, 'Output tokens', '${u.output}'),
                  if (u.reasoning > 0) _row(c, '  of which reasoning', '${u.reasoning}'),
                  _row(c, 'Total tokens', '${u.input + u.output}'),
                  _row(c, 'Cost', '${money(u.cost)}${u.estimated ? ' (estimated at list price)' : ''}'),
                  if (calls.length > 1) ...[
                    const Divider(),
                    for (final (i, s) in calls.indexed)
                      _row(
                        c,
                        'Call ${i + 1}${s.tools.isEmpty ? '' : ' · ${s.tools.length} tool${s.tools.length == 1 ? '' : 's'}'}',
                        '${_n(s.usage!.input)} in · ${_n(s.usage!.output)} out · ${money(s.usage!.cost)}',
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.toll_outlined, size: 12, color: AppColors.text3),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  [
                    '${_n(u.input)} in',
                    if (u.cached > 0) '${_n(u.cached)} cached',
                    '${_n(u.output)} out',
                    if (u.reasoning > 0) '${_n(u.reasoning)} thinking',
                    '${u.estimated ? '≈' : ''}${money(u.cost)}',
                    if (calls.length > 1) '${calls.length} calls',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(k, style: context.text.bodySmall)),
        const SizedBox(width: Space.m),
        Flexible(child: Text(v, textAlign: TextAlign.right, style: context.text.bodyMedium)),
      ],
    ),
  );
}

/// A piece of an answer: Markdown, or a table drawn by [MarkdownTable].
typedef AnswerPart = ({String? markdown, List<String>? head, List<List<String>>? rows});

final _tableRule = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

/// [text] split around its Markdown tables (outside code blocks), so tables
/// can scroll sideways while the rest renders as usual.
List<AnswerPart> splitTables(String text) {
  final lines = text.split('\n');
  final parts = <AnswerPart>[];
  final buffer = <String>[];
  var fenced = false;
  void flush() {
    if (buffer.join().trim().isNotEmpty) parts.add((markdown: buffer.join('\n'), head: null, rows: null));
    buffer.clear();
  }

  List<String> cells(String line) {
    var l = line.trim();
    if (l.startsWith('|')) l = l.substring(1);
    if (l.endsWith('|') && !l.endsWith(r'\|')) l = l.substring(0, l.length - 1);
    return [for (final c in l.split(RegExp(r'(?<!\\)\|'))) c.trim().replaceAll(r'\|', '|')];
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```') || line.trimLeft().startsWith('~~~')) fenced = !fenced;
    if (!fenced && line.contains('|') && i + 1 < lines.length && _tableRule.hasMatch(lines[i + 1]) && lines[i + 1].contains('-')) {
      flush();
      final head = cells(line);
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
        rows.add(cells(lines[i]));
        i++;
      }
      i--;
      parts.add((markdown: null, head: head, rows: rows));
      continue;
    }
    buffer.add(line);
  }
  flush();
  return parts;
}

/// A Markdown table in an answer: each column as wide as its content up to
/// a limit (longer text wraps), scrolling sideways on its own when wider
/// than the chat, with a tinted header, banded rows and numbers on the right.
class MarkdownTable extends StatefulWidget {
  const MarkdownTable({super.key, required this.head, required this.rows, required this.onLink});
  final List<String> head;
  final List<List<String>> rows;
  final void Function(String href) onLink;

  @override
  State<MarkdownTable> createState() => _MarkdownTableState();
}

class _MarkdownTableState extends State<MarkdownTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static final _number = RegExp(r'^[\s$€£¥+\-−~≈]*\d[\d,.\s]*(%|[kKmMbB]|x)?\s*$');

  /// Columns whose filled cells are all numbers line up on the right.
  bool _numeric(int column) {
    final cells = [
      for (final r in widget.rows)
        if (column < r.length && r[column].trim().isNotEmpty) r[column].replaceAll('*', '').trim(),
    ];
    return cells.isNotEmpty && cells.every(_number.hasMatch);
  }

  TextSpan _span(md.Node node, TextStyle style) {
    if (node is md.Text) return TextSpan(text: node.text, style: style);
    if (node is! md.Element) return TextSpan(text: node.textContent, style: style);
    if (node.tag == 'br') return const TextSpan(text: '\n');
    final next = switch (node.tag) {
      'strong' => style.copyWith(fontWeight: FontWeight.w700),
      'em' => style.copyWith(fontStyle: FontStyle.italic),
      'del' => style.copyWith(decoration: TextDecoration.lineThrough),
      'code' => style.copyWith(fontFamily: 'monospace', fontSize: (style.fontSize ?? 14) - 1, backgroundColor: AppColors.surface2),
      'a' => style.copyWith(
        color: AppColors.activeAccent,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accent.withValues(alpha: 0.4),
      ),
      _ => style,
    };
    return TextSpan(style: next, children: [for (final c in node.children ?? const <md.Node>[]) _span(c, next)]);
  }

  Widget _cell(String source, TextStyle style, TextAlign align) {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false).parseInline(source);
    md.Element? firstLink(List<md.Node> list) {
      for (final n in list) {
        if (n is md.Element) {
          if (n.tag == 'a') return n;
          final inner = firstLink(n.children ?? const []);
          if (inner != null) return inner;
        }
      }
      return null;
    }

    final link = firstLink(nodes)?.attributes['href'];
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 1),
      child: Text.rich(TextSpan(children: [for (final n in nodes) _span(n, style)]), textAlign: align),
    );
    return link == null ? text : InkWell(onTap: () => widget.onLink(link), child: text);
  }

  @override
  Widget build(BuildContext context) {
    final columns = [widget.head.length, for (final r in widget.rows) r.length].fold<int>(0, (m, n) => n > m ? n : m);
    if (columns == 0) return const SizedBox.shrink();
    final base = context.text.bodyMedium!.copyWith(fontSize: 14, height: 1.35, color: AppColors.text);
    final headStyle = base.copyWith(fontWeight: FontWeight.w600);
    final numeric = [for (var c = 0; c < columns; c++) _numeric(c)];
    TableRow row(List<String> cells, {required bool header, required int index}) => TableRow(
      decoration: BoxDecoration(
        color: header
            ? AppColors.surface2
            : index.isOdd
            ? AppColors.surface2.withValues(alpha: 0.45)
            : null,
        border: header ? null : Border(top: BorderSide(color: AppColors.line, width: 0.6)),
      ),
      children: [
        for (var c = 0; c < columns; c++)
          c < cells.length
              ? _cell(cells[c], header ? headStyle : base, numeric[c] ? TextAlign.right : TextAlign.left)
              : const SizedBox.shrink(),
      ],
    );
    final table = Table(
      // Each column as wide as its content, up to 280 px; longer text wraps.
      defaultColumnWidth: const MinColumnWidth(IntrinsicColumnWidth(), FixedColumnWidth(280)),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        if (widget.head.any((h) => h.isNotEmpty)) row(widget.head, header: true, index: -1),
        for (final (i, r) in widget.rows.indexed) row(r, header: false, index: i),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: LayoutBuilder(
        builder: (context, box) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // A narrow table still spans the chat's width.
                constraints: BoxConstraints(minWidth: box.maxWidth - 2),
                child: IntrinsicWidth(child: table),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
