import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../settings/data/settings.dart';
import '../../data/chat_controller.dart';
import '../../data/chat_export.dart';
import '../../domain/chat_models.dart';

String _tokens(int n) => NumberFormat.compact().format(n);

/// Renames conversation [id]; Regenerate asks the chat model for a title.
Future<void> showRenameSheet(BuildContext context, {required String id, required String title}) =>
    showFormSheet<void>(context, builder: (_) => _RenameSheet(id: id, title: title));

class _RenameSheet extends ConsumerStatefulWidget {
  const _RenameSheet({required this.id, required this.title});
  final String id;
  final String title;

  @override
  ConsumerState<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends ConsumerState<_RenameSheet> {
  late final _text = TextEditingController(text: widget.title);
  bool _thinking = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _regenerate() async {
    setState(() => _thinking = true);
    final ctl = ref.read(chatControllerProvider.notifier);
    final c = await ctl.conversationById(widget.id);
    final title = c == null ? null : await ctl.suggestTitle(c);
    if (!mounted) return;
    setState(() => _thinking = false);
    if (title == null) {
      showSnack(context, 'Couldn\'t write a title. Is an AI key set?', icon: Icons.error_outline_rounded);
      return;
    }
    _text
      ..text = title
      ..selection = TextSelection.collapsed(offset: title.length);
  }

  Future<void> _save() async {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    await ref.read(chatControllerProvider.notifier).rename(widget.id, title);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Rename chat', style: context.text.titleMedium),
      const SizedBox(height: Space.l),
      TextField(
        controller: _text,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          hintText: 'Chat name',
          suffixIcon: _thinking
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
      ),
      const SizedBox(height: Space.l),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
              onPressed: _thinking ? null : _regenerate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Regenerate'),
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
        ],
      ),
    ],
  );
}

/// A small ring in the app bar: how much of the model's context the chat
/// uses. Tapping it explains, and offers to compact.
class ContextMeter extends ConsumerWidget {
  const ContextMeter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatControllerProvider.select((s) => s.revision));
    final c = ref.watch(chatControllerProvider.select((s) => s.conversation));
    if (c.entries.isEmpty) return const SizedBox.shrink();
    final ctx = ref.read(chatControllerProvider.notifier).contextOf(c);
    final window = ctx.window;
    final share = window == null || window == 0 ? null : (ctx.used / window).clamp(0.0, 1.0);
    final color = share == null
        ? AppColors.text3
        : share > 0.8
        ? AppColors.danger
        : share > 0.6
        ? AppColors.warning
        : AppColors.text2;
    return IconButton(
      tooltip: share == null ? 'Context: ${_tokens(ctx.used)} tokens' : 'Context ${(share * 100).round()}% full',
      onPressed: () => showContextSheet(context),
      icon: SizedBox.square(
        dimension: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: share ?? 0,
              strokeWidth: 2.6,
              backgroundColor: AppColors.surface3,
              color: color,
            ),
            if (c.summary != null) Icon(Icons.compress_rounded, size: 11, color: color),
          ],
        ),
      ),
    );
  }
}

Future<void> showContextSheet(BuildContext context) =>
    showAppSheet<void>(context, initialSize: 0.6, builder: (_, scroll) => _ContextSheet(scroll: scroll));

class _ContextSheet extends ConsumerStatefulWidget {
  const _ContextSheet({required this.scroll});
  final ScrollController scroll;

  @override
  ConsumerState<_ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends ConsumerState<_ContextSheet> {
  bool _compacting = false;

  Future<void> _compact() async {
    setState(() => _compacting = true);
    final controller = ref.read(chatControllerProvider.notifier);
    final result = await controller.compact();
    if (!mounted) return;
    setState(() => _compacting = false);
    showSnack(
      context,
      switch (result) {
        CompactResult.done => 'Older messages summarised',
        CompactResult.tooShort => 'Nothing to compact yet: it needs at least three questions.',
        CompactResult.nothingNew => 'Already compacted: only your last two questions come after the summary.',
        CompactResult.running => 'Already summarising this chat.',
        CompactResult.failed => 'Couldn\'t summarise: ${controller.lastCompactError ?? 'the model gave no summary'}. Try again.',
      },
      icon: result == CompactResult.done ? Icons.compress_rounded : Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatControllerProvider.select((s) => s.revision));
    final c = ref.watch(chatControllerProvider.select((s) => s.conversation));
    final s = ref.watch(settingsProvider);
    final ctx = ref.read(chatControllerProvider.notifier).contextOf(c);
    final window = ctx.window;
    final share = window == null || window == 0 ? null : math.min(1.0, ctx.used / window);
    final compacting = _compacting || ref.read(chatControllerProvider.notifier).isCompacting(c.id);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Text('Context', style: context.text.titleLarge),
        const SizedBox(height: Space.xs),
        Text(
          'Everything the model reads each turn: instructions, tools, memories and this chat.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              share == null ? _tokens(ctx.used) : '${(share * 100).round()}%',
              style: context.text.headlineMedium,
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${ctx.estimated ? '≈' : ''}${_tokens(ctx.used)} of ${window == null ? 'an unknown number of' : _tokens(window)} tokens',
                  style: context.text.bodySmall,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: share ?? 0,
            minHeight: 8,
            backgroundColor: AppColors.surface3,
            color: (share ?? 0) > 0.8 ? AppColors.danger : AppColors.accent,
          ),
        ),
        const SizedBox(height: Space.xl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: lead(const Icon(Icons.auto_mode_rounded)),
          title: const Text('Compact automatically'),
          subtitle: Text('At 80%, older messages are summarised before the next answer', style: context.text.bodySmall),
          value: s.autoCompact,
          onChanged: ref.read(settingsProvider.notifier).setAutoCompact,
        ),
        const SizedBox(height: Space.s),
        FilledButton.icon(
          onPressed: compacting ? null : _compact,
          icon: compacting
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.compress_rounded),
          label: Text(compacting ? 'Summarising… (you can close this)' : 'Compact now'),
        ),
        const SizedBox(height: Space.s),
        Text(
          'Compacting keeps every message on screen. The model reads a summary of the older part instead, '
          'so long chats stay fast and cheaper.',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (c.summary case final summary?) ...[
          const SizedBox(height: Space.xl),
          Text('CURRENT SUMMARY', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: MarkdownBody(data: summary, selectable: true),
          ),
        ],
      ],
    );
  }
}

/// The line in the chat where compaction ends: what is above it the model
/// reads as a summary. While [compacting], it says so with a spinner.
class CompactionDivider extends StatelessWidget {
  const CompactionDivider({super.key, required this.compacting, this.onTap});
  final bool compacting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = compacting ? AppColors.accent : AppColors.text3;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: compacting ? null : onTap,
        child: Row(
          children: [
            Expanded(child: Divider(color: compacting ? AppColors.accent.withValues(alpha: 0.5) : AppColors.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (compacting)
                    SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: color))
                  else
                    Icon(Icons.compress_rounded, size: 14, color: color),
                  const SizedBox(width: Space.xs),
                  Text(
                    compacting ? 'Compacting earlier messages…' : 'Earlier messages summarised · view',
                    style: context.text.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            Expanded(child: Divider(color: compacting ? AppColors.accent.withValues(alpha: 0.5) : AppColors.line)),
          ],
        ),
      ),
    );
  }
}

/// What compaction wrote: the summary the model reads in place of the
/// messages above the divider.
Future<void> showCompactionSheet(BuildContext context, Conversation c) {
  final covered = c.entries.indexWhere((e) => e.id == c.summaryUntil) + 1;
  return showAppSheet<void>(
    context,
    initialSize: 0.75,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Row(
          children: [
            Icon(Icons.compress_rounded, color: AppColors.accent),
            const SizedBox(width: Space.s),
            Text('Compacted', style: context.text.titleLarge),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          [
            '$covered messages summarised',
            if (c.compactedAt case final at?) DateFormat('d MMM, HH:mm').format(at),
            '${_tokens((c.summary ?? '').length ~/ 4)} tokens now',
          ].join(' · '),
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.s),
        Text(
          'Every message stays on screen. The model reads this summary instead of them.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
          child: MarkdownBody(data: c.summary ?? '', selectable: true),
        ),
      ],
    ),
  );
}

/// Saves the open chat as Markdown or PDF.
Future<void> showExportSheet(BuildContext context, Conversation c) => showFormSheet<void>(
  context,
  builder: (sheet) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Export chat', style: sheet.text.titleMedium),
      const SizedBox(height: Space.xs),
      Text('"${c.title}" · ${c.entries.whereType<UserEntry>().length} questions', style: sheet.text.bodySmall),
      const SizedBox(height: Space.l),
      for (final (format, icon, hint) in const [
        (ChatExportFormat.pdf, Icons.picture_as_pdf_outlined, 'To read, print or share'),
        (ChatExportFormat.markdown, Icons.description_outlined, 'Plain text with formatting, for notes apps'),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: lead(Icon(icon)),
          title: Text(format.label),
          subtitle: Text(hint, style: sheet.text.bodySmall),
          trailing: const Icon(Icons.download_rounded),
          onTap: () async {
            Navigator.pop(sheet);
            try {
              final (name, bytes) = await exportChat(c, format);
              final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: format.mime);
              if (saved != null && context.mounted) showSnack(context, 'Chat exported');
            } catch (e) {
              if (context.mounted) showSnack(context, 'Couldn\'t export: $e', icon: Icons.error_outline_rounded);
            }
          },
        ),
    ],
  ),
);
