import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/widgets/post_viewer.dart';
import '../../telegram/data/telegram_store.dart';
import '../watch_engine.dart';
import '../watches.dart';
import 'watches_screen.dart';

final _ref = RegExp(r'post:(-?\d+):(\d+)');
final _ids = RegExp(r'chat_id (-?\d+), message_id (\d+)');

/// Everything about one watch update: the watch, what set it off, and the
/// messages involved.
Future<void> showWatchEventSheet(BuildContext context, UserEntry entry, Map<String, PostSnapshot> posts) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 1,
      builder: (context, scroll) => _Sheet(entry: entry, posts: posts, scroll: scroll),
    ),
  );
}

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.entry, required this.posts, required this.scroll});
  final UserEntry entry;
  final Map<String, PostSnapshot> posts;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final watch = ref.watch(watchStoreProvider).where((w) => w.name == entry.event).firstOrNull;

    // The messages the event names, by ref or by chat and message id.
    final keys = <String>{
      for (final m in _ref.allMatches(entry.text)) '${m[1]}:${m[2]}',
      for (final m in _ids.allMatches(entry.text)) '${m[1]}:${m[2]}',
    };
    final messages = [
      for (final k in keys)
        posts[k] ??
            PostSnapshot(
              chatId: int.parse(k.split(':').first),
              messageId: int.parse(k.split(':').last),
              chatTitle: store.chat(int.parse(k.split(':').first))?.title ?? 'Message',
              date: entry.at,
              text: '',
            ),
    ];

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: context.text.bodySmall)),
          Expanded(child: Text(v, style: context.text.bodyMedium)),
        ],
      ),
    );

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Space.s),
              decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(Radii.m)),
              child: Icon(watch == null ? Icons.visibility_outlined : watchModeIcon(watch.mode), color: AppColors.accent),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.event ?? 'Watch', style: context.text.titleLarge),
                  Text(DateFormat('EEE d MMM, HH:mm').format(entry.at), style: context.text.bodySmall),
                ],
              ),
            ),
          ],
        ),
        if (messages.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          Text('MESSAGES · ${messages.length}', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [for (final p in messages) PostChip(post: p)]),
        ],
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Text('WHAT HAPPENED', style: context.text.labelSmall),
            const Spacer(),
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 16, color: AppColors.text3),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.text));
                showSnack(context, 'Copied');
              },
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
          child: SelectableText(entry.text, style: context.text.bodySmall?.copyWith(color: AppColors.text)),
        ),
        const SizedBox(height: Space.xl),
        Text('THE WATCH', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        if (watch == null)
          Text('This watch has since been removed.', style: context.text.bodySmall)
        else ...[
          row('Status', watch.enabled ? 'On' : 'Paused'),
          row('When', watchTrigger(watch, store, find: (id) => chatAnywhere(ref, store, id))),
          row('Then', '${watch.mode.label}: ${watch.mode.explanation}'),
          if (watch.instructions.isNotEmpty) row('Instructions', watch.instructions),
          if (!watch.includeMuted) row('Muted chats', 'Ignored'),
          row('Runs', '${watch.runs}${watch.lastRunAt == null ? '' : ' · last ${DateFormat('d MMM HH:mm').format(watch.lastRunAt!)}'}'),
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Run now'),
                  onPressed: () async {
                    final problem = await ref.read(watchEngineProvider).runNow(watch);
                    if (context.mounted) showSnack(context, problem ?? 'Ran "${watch.name}"');
                  },
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(watch.enabled ? Icons.pause_rounded : Icons.play_circle_outline_rounded, size: 18),
                  label: Text(watch.enabled ? 'Pause' : 'Resume'),
                  onPressed: () =>
                      ref.read(watchStoreProvider.notifier).update(watch.id, (w) => w.copyWith(enabled: !w.enabled)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Edit watch'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchEditor(watch: watch)));
              },
            ),
          ),
        ],
      ],
    );
  }
}
