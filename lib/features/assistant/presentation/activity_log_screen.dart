import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../chat/data/chat_controller.dart';
import '../activity_log.dart';

enum _Show {
  all('Everything'),
  attention('Failed, declined or blocked'),
  undoable('Can be undone'),
  undone('Undone');

  const _Show(this.label);
  final String label;
}

/// Everything the assistant did that sends, changes or deletes something:
/// who started it, why it was allowed, what came back, and Undo where it
/// can be taken back.
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  _Show _show = _Show.all;
  ActivityKind? _kind;
  ActivitySource? _source;
  String _query = '';

  bool _keep(ActivityEntry e) {
    if (_kind != null && e.kind != _kind) return false;
    if (_source != null && e.source != _source) return false;
    switch (_show) {
      case _Show.attention:
        if (e.outcome == ActivityOutcome.done) return false;
      case _Show.undoable:
        if (!e.canUndo) return false;
      case _Show.undone:
        if (e.undoneAt == null) return false;
      case _Show.all:
        break;
    }
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return '${e.summary} ${e.tool} ${e.toolLabel} ${e.sourceName ?? ''} ${e.arguments}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activityLogProvider);
    final shown = all.where(_keep).toList();
    final today = DateTime.now();
    final todays = all.where((e) => e.at.isAfter(DateTime(today.year, today.month, today.day))).toList();
    final sections = <String, List<ActivityEntry>>{};
    for (final e in shown) {
      (sections[_day(e.at)] ??= []).add(e);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          PopupMenuButton<ActivitySource?>(
            tooltip: 'Started by',
            icon: Icon(_source == null ? Icons.person_search_outlined : Icons.person_search_rounded),
            onSelected: (v) => setState(() => _source = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: null, checked: _source == null, child: const Text('Started by anyone')),
              for (final s in ActivitySource.values) CheckedPopupMenuItem(value: s, checked: _source == s, child: Text(s.plural)),
            ],
          ),
          PopupMenuButton<_Show>(
            tooltip: 'Show',
            icon: Icon(_show == _Show.all ? Icons.filter_list_rounded : Icons.filter_list_alt),
            initialValue: _show,
            onSelected: (v) => setState(() => _show = v),
            itemBuilder: (_) => [for (final s in _Show.values) CheckedPopupMenuItem(value: s, checked: _show == s, child: Text(s.label))],
          ),
          IconButton(
            tooltip: 'Clear the log',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: all.isEmpty
                ? null
                : () async {
                    if (await confirmDelete(
                      context,
                      title: 'Clear the activity log?',
                      message: 'The record of what the assistant did is removed from this phone. Nothing it did is undone.',
                      action: 'Clear',
                    )) {
                      await ref.read(activityLogProvider.notifier).clear();
                    }
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          const _AboutCard(),
          const SizedBox(height: Space.m),
          _TodayCard(entries: todays),
          const SizedBox(height: Space.m),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(isDense: true, hintText: 'Search actions', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          ),
          const SizedBox(height: Space.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in <ActivityKind?>[null, ...ActivityKind.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      avatar: k == null ? null : Icon(_kindIcon(k), size: 16),
                      label: Text(k == null ? 'All' : '${k.label} ${all.where((e) => e.kind == k).length}'),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
              ],
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Text(
                all.isEmpty
                    ? 'Nothing yet. What the assistant does, what personal data it reads, what runs on its own, and changes to approvals, tools, keys and the app lock all show here.'
                    : 'Nothing matches.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ),
          for (final MapEntry(key: day, value: entries) in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.xs),
              child: Text(day.toUpperCase(), style: context.text.labelSmall),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (final (i, e) in entries.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _EntryTile(entry: e),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _day(DateTime at) {
    final now = DateTime.now();
    final d = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEEE d MMMM' : 'd MMMM y').format(d);
  }
}

IconData _kindIcon(ActivityKind k) => switch (k) {
  ActivityKind.action => Icons.bolt_rounded,
  ActivityKind.access => Icons.visibility_outlined,
  ActivityKind.run => Icons.play_circle_outline_rounded,
  ActivityKind.settings => Icons.tune_rounded,
  ActivityKind.security => Icons.shield_outlined,
};

/// What the log is for, and what goes in it.
class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.xs),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fact_check_outlined, size: 22, color: AppColors.accent),
            const SizedBox(width: Space.m),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: Space.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your audit trail', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'A record of everything the assistant did on your behalf and what it looked at, so you can check it, '
                      'see why it was allowed, and undo what can be undone. It stays on this phone and is never sent anywhere.',
                      style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: Space.m, left: 34, right: Space.s),
            child: Column(
              children: [
                for (final k in ActivityKind.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_kindIcon(k), size: 16, color: AppColors.text2),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '${k.label}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(text: k.description, style: TextStyle(color: AppColors.text3)),
                              ],
                            ),
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Keys and passcodes are never recorded, only that they changed. Reading Telegram chats isn't logged, since almost every question does it.",
                    style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Less' : "What's recorded"),
          ),
        ),
      ],
    ),
  );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.entries});
  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    final runs = entries.where((e) => e.isRun).length;
    final actions = entries.where((e) => !e.isRun);
    final done = actions.where((e) => e.outcome == ActivityOutcome.done).length;
    final onItsOwn = actions.where((e) => e.outcome == ActivityOutcome.done && e.approval != ActivityApproval.tapped).length;
    final trouble = entries.where((e) => e.outcome != ActivityOutcome.done).length;
    Widget stat(String n, String label, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: context.text.titleLarge?.copyWith(color: color)),
          Text(label, style: context.text.labelSmall),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TODAY', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Row(
            children: [
              stat('$runs', 'runs', AppColors.text),
              stat('$done', 'actions taken', AppColors.text),
              stat('$onItsOwn', 'without a tap', onItsOwn > 0 ? AppColors.warning : AppColors.text),
              stat('$trouble', 'failed or stopped', trouble > 0 ? AppColors.danger : AppColors.text),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _outcomeIcon(ActivityEntry e) => switch (e.kind) {
  ActivityKind.access => Icons.visibility_outlined,
  ActivityKind.settings => Icons.tune_rounded,
  ActivityKind.security => Icons.shield_outlined,
  _ => _actionIcon(e),
};

IconData _actionIcon(ActivityEntry e) => e.isRun
    ? switch (e.source) {
        ActivitySource.watch => Icons.visibility_outlined,
        ActivitySource.routine => Icons.account_tree_outlined,
        ActivitySource.job => Icons.schedule_rounded,
        ActivitySource.brief => Icons.wb_twilight_rounded,
        _ => Icons.smart_toy_outlined,
      }
    : e.undoneAt != null
    ? Icons.undo_rounded
    : switch (e.outcome) {
        ActivityOutcome.done => e.destructive ? Icons.delete_outline_rounded : Icons.check_circle_outline_rounded,
        ActivityOutcome.failed => Icons.error_outline_rounded,
        ActivityOutcome.declined => Icons.block_rounded,
        ActivityOutcome.blocked => Icons.lock_outline_rounded,
      };

Color _outcomeColor(ActivityEntry e) => switch (e.kind) {
  ActivityKind.access => e.outcome == ActivityOutcome.done ? AppColors.text2 : AppColors.danger,
  ActivityKind.settings => AppColors.accent,
  ActivityKind.security => AppColors.warning,
  _ => _actionColor(e),
};

Color _actionColor(ActivityEntry e) => e.isRun
    ? (e.outcome == ActivityOutcome.done ? AppColors.accent : AppColors.danger)
    : e.undoneAt != null
    ? AppColors.text3
    : switch (e.outcome) {
        ActivityOutcome.done => e.destructive ? AppColors.warning : AppColors.success,
        ActivityOutcome.failed => AppColors.danger,
        ActivityOutcome.declined || ActivityOutcome.blocked => AppColors.text3,
      };

Future<void> _undo(BuildContext context, WidgetRef ref, ActivityEntry e) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('${e.undo!.label}?'),
      content: Text(switch (e.undo!.kind) {
        UndoKind.deleteMessages => 'The message${e.undo!.messages.length == 1 ? ' is' : 's are'} deleted for everyone in the chat. People may already have seen ${e.undo!.messages.length == 1 ? 'it' : 'them'}.',
        UndoKind.rerunTool => 'Triangle does the opposite of what the assistant did.',
        UndoKind.removeLocal => 'It is removed from this phone.',
      }),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Undo')),
      ],
    ),
  );
  if (ok != true) return;
  final problem = await ref.read(chatControllerProvider.notifier).undoActivity(e);
  if (context.mounted) {
    showSnack(context, problem == null ? 'Undone' : 'Couldn\'t undo: $problem', icon: problem == null ? Icons.undo_rounded : Icons.error_outline_rounded);
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});
  final ActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    return ListTile(
      leading: lead(Icon(_outcomeIcon(e), color: _outcomeColor(e))),
      title: Text(e.summary.isEmpty ? e.toolLabel : e.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          DateFormat.Hm().format(e.at),
          if (e.isRun) e.source.label else e.sourceName == null ? e.source.label : '${e.source.label} · ${e.sourceName}',
          if (e.isRun)
            (e.outcome == ActivityOutcome.done ? 'ran${e.durationMs == null ? '' : ' in ${(e.durationMs! / 1000).toStringAsFixed(1)} s'}' : 'failed')
          else if (e.outcome == ActivityOutcome.done)
            e.approval.label
          else
            e.outcome.name,
          if (e.undoneAt != null) 'undone',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall,
      ),
      trailing: e.canUndo
          ? TextButton(onPressed: () => _undo(context, ref, e), child: const Text('Undo'))
          : null,
      onTap: () => showAppSheet<void>(context, builder: (_, scroll) => _EntrySheet(id: e.id, scroll: scroll)),
    );
  }
}

class _EntrySheet extends ConsumerWidget {
  const _EntrySheet({required this.id, required this.scroll});
  final String id;
  final ScrollController scroll;

  static String _pretty(String raw) {
    if (raw.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(activityLogProvider).where((x) => x.id == id).firstOrNull;
    if (e == null) return const SizedBox.shrink();
    final account = e.account == null ? null : ref.watch(accountsProvider).byId(e.account!);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: context.text.bodySmall)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
    Widget code(String title, String raw) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: context.text.labelSmall)),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _pretty(raw)));
                showSnack(context, 'Copied');
              },
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
          child: SelectableText(_pretty(raw), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ],
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            Icon(_outcomeIcon(e), color: _outcomeColor(e)),
            const SizedBox(width: Space.s),
            Expanded(child: Text(e.toolLabel, style: context.text.titleMedium)),
          ],
        ),
        if (e.summary.isNotEmpty) ...[const SizedBox(height: Space.xs), Text(e.summary, style: context.text.bodyMedium)],
        const SizedBox(height: Space.m),
        row('When', DateFormat('EEE d MMM y, HH:mm:ss').format(e.at)),
        row(e.isRun ? 'What ran' : 'Started by', e.sourceName == null ? e.source.label : '${e.source.label}: ${e.sourceName}'),
        if (e.isRun && e.args['model'] != null) row('Model', '${e.args['model']}'),
        if (!e.isRun) row('Allowed because', e.approval.label),
        row('Result', switch (e.outcome) {
          ActivityOutcome.done => 'Done${e.durationMs == null ? '' : ' in ${e.durationMs} ms'}',
          ActivityOutcome.failed => 'Failed',
          ActivityOutcome.declined => 'Declined: nothing was done',
          ActivityOutcome.blocked => 'Blocked by your settings: nothing was done',
        }),
        if (account != null) row('Account', account.label),
        if (!e.isRun) row('Tool', e.tool),
        if (e.undoneAt != null) row('Undone', DateFormat('d MMM HH:mm').format(e.undoneAt!)),
        if (e.undoError != null) row('Undo failed', e.undoError!),
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            if (e.canUndo)
              FilledButton.icon(
                onPressed: () => _undo(context, ref, e),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(e.undo!.label),
              ),
            if (e.conversationId != null)
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(chatControllerProvider.notifier).open(e.conversationId!);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Open the conversation'),
              ),
            TextButton.icon(
              onPressed: () async {
                await ref.read(activityLogProvider.notifier).remove(e.id);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Remove from log'),
            ),
          ],
        ),
        if (e.arguments.isNotEmpty && e.arguments != '{}')
          ...[const SizedBox(height: Space.l), code(e.isRun ? 'WHAT STARTED IT' : 'WHAT IT WAS ASKED TO DO', e.arguments)],
        if (e.result.isNotEmpty) ...[const SizedBox(height: Space.l), code(e.isRun ? 'WHAT IT SAID' : 'WHAT CAME BACK', e.result)],
      ],
    );
  }
}
