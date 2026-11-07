import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../chat/data/chat_controller.dart';
import '../chat/domain/chat_models.dart';
import '../chat/presentation/widgets/message_view.dart';
import '../telegram/data/telegram_tools.dart' show toolNamed;
import '../settings/data/settings.dart';
import '../telegram/presentation/chat_actions.dart' show confirmAction;
import 'brief_settings_screen.dart';
import 'brief_schedule.dart';
import 'brief_store.dart';
import 'brief_export.dart';

/// Briefs: write one now, see the latest, browse earlier ones, and set the
/// morning and night times.
class BriefScreen extends ConsumerWidget {
  const BriefScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(briefStoreProvider);
    final s = ref.watch(settingsProvider);
    final store = ref.read(briefStoreProvider.notifier);
    final latest = st.briefs.firstOrNull;


    return Scaffold(
      appBar: AppBar(
        title: const Text('Brief'),
        actions: [
          // The newest brief, as a PDF, Markdown or copied text.
          if (latest != null && latest.error == null && latest.text.isNotEmpty)
            IconButton(
              tooltip: 'Export latest brief',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => showBriefExportSheet(context, latest),
            ),
          IconButton(
            tooltip: 'Brief settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BriefSettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A detailed, priority-ordered rundown of what happened since the last brief across your DMs, groups and '
                  'channels, and your email, calendar, Slack and other connected apps (set in Brief settings). Read-only: '
                  'nothing is sent or marked as read.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.m),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: st.running != null
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bolt_rounded),
                    label: Text(st.running != null ? 'Writing your ${st.running!.label.toLowerCase()}…' : 'Brief me now'),
                    onPressed: st.running != null
                        ? null
                        : () async {
                            if (!s.hasAnyKey) {
                              showSnack(context, 'Add an AI key in Settings first', icon: Icons.key_off_outlined);
                              return;
                            }
                            final b = await store.generate(BriefKind.manual);
                            if (b != null && context.mounted) {
                              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BriefView(brief: b)));
                            }
                          },
                  ),
                ),
                const Divider(height: Space.xl),
                const BriefSchedule(),
              ],
            ),
          ),
          if (st.live case final live?) ...[
            const SizedBox(height: Space.xl),
            _LiveBrief(conversation: live, kind: st.running ?? BriefKind.manual),
          ],
          if (latest != null) ...[
            const SizedBox(height: Space.xl),
            Text('LATEST', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            _BriefCard(brief: latest, big: true),
          ],
          if (st.briefs.length > 1) ...[
            const SizedBox(height: Space.xl),
            Text('EARLIER · ${st.briefs.length - 1}', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            for (final b in st.briefs.skip(1)) _BriefCard(brief: b),
          ],
          if (st.briefs.isEmpty && st.running == null)
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Center(child: Text('No briefs yet', style: context.text.bodySmall)),
            ),
        ],
      ),
    );
  }
}

/// The brief being written, live: which chats and apps it is reading (each
/// tool call as it runs), its thinking, and the text as it streams in.
class _LiveBrief extends ConsumerWidget {
  const _LiveBrief({required this.conversation, required this.kind});
  final Conversation conversation;
  final BriefKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatControllerProvider.select((s) => s.revision));
    final answer = conversation.entries.whereType<AssistantEntry>().lastOrNull;
    final calls = [for (final s in answer?.steps ?? const <ModelStep>[]) ...s.tools];
    final done = calls.where((t) => t.status == ToolStatus.done || t.status == ToolStatus.error).length;
    final running = calls.where((t) => t.status == ToolStatus.running).lastOrNull;
    final writing = (answer?.steps.lastOrNull?.text ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text('${kind.emoji} Writing your ${kind.label.toLowerCase()}', style: context.text.titleSmall),
              ),
              Text('$done step${done == 1 ? '' : 's'}', style: context.text.labelSmall),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            writing
                ? 'Writing it up…'
                : running != null
                ? (toolNamed(running.name)?.label ?? running.name)
                : 'Thinking about what to read…',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(minHeight: 3),
          ),
          if (answer != null) ...[
            const SizedBox(height: Space.m),
            AssistantMessage(entry: answer, posts: conversation.posts, streaming: true),
          ],
        ],
      ),
    );
  }
}

class _BriefCard extends ConsumerWidget {
  const _BriefCard({required this.brief, this.big = false});
  final Brief brief;
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = brief;
    final preview = b.text
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'[#*_>`]'), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BriefView(brief: b))),
          onLongPress: () async {
            if (await confirmAction(context, title: 'Delete this brief?', message: 'Only the saved brief goes.', action: 'Delete')) {
              await ref.read(briefStoreProvider.notifier).delete(b.id);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.kind.emoji, style: TextStyle(fontSize: big ? 26 : 20)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${b.kind.label} · ${DateFormat('EEE d MMM, HH:mm').format(b.at)}',
                        style: context.text.titleSmall,
                      ),
                      Text(
                        'Covers since ${DateFormat('d MMM HH:mm').format(b.since)}',
                        style: context.text.labelSmall,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        b.error ?? (preview.isEmpty ? 'Empty' : preview),
                        maxLines: big ? 5 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: b.error != null ? AppColors.danger : null),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One brief in full, with its post chips and the tool calls behind it.
class BriefView extends StatelessWidget {
  const BriefView({super.key, required this.brief});
  final Brief brief;

  @override
  Widget build(BuildContext context) {
    final answer = brief.answer;
    return Scaffold(
      appBar: AppBar(
        title: Text('${brief.kind.emoji} ${DateFormat('EEE d MMM, HH:mm').format(brief.at)}'),
        actions: [
          if (brief.error == null && brief.text.isNotEmpty)
            IconButton(
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => showBriefExportSheet(context, brief),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(
            'From ${DateFormat('d MMM HH:mm').format(brief.since)} to ${DateFormat('d MMM HH:mm').format(brief.at)}',
            style: context.text.labelSmall,
          ),
          const SizedBox(height: Space.m),
          if (answer == null)
            Text(brief.error ?? 'Nothing was written.', style: context.text.bodySmall)
          else
            AssistantMessage(entry: answer, posts: brief.conversation.posts, streaming: false),
        ],
      ),
    );
  }
}

/// For the drawer: when the last brief was written.
String briefSubtitle(List<Brief> briefs) {
  final b = briefs.firstOrNull;
  if (b == null) return 'What happened, by priority';
  return 'Last: ${DateFormat('EEE HH:mm').format(b.at)}';
}
