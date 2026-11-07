import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../chat/data/chat_controller.dart';
import '../../settings/data/settings.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/tg_avatar.dart';
import '../online_alerts.dart';
import '../reminders.dart';
import '../watch_engine.dart';
import '../watches.dart';
import '../../auth/data/auth_controller.dart';
import '../../integrations/app_toolkits.dart';
import '../../integrations/integrations_store.dart';
import '../../account/account_switcher.dart';
import '../../../infrastructure/telegram/accounts.dart';

String watchTrigger(Watch w, TelegramStore store) => switch (w.scope) {
  WatchScope.chats => w.chatIds.map((id) => store.chat(id)?.title ?? 'chat $id').join(', '),
  WatchScope.folder => 'Folder ${store.folders.where((f) => f.id == w.folderId).firstOrNull?.title ?? w.folderId}',
  WatchScope.schedule => w.dailyAt != null ? 'Every day at ${w.dailyAt}' : 'Every ${w.everyMinutes} minutes',
  WatchScope.app =>
    '${w.app == null || w.app == 'any' ? 'Any app' : appLabel(w.app!)}${w.query.isEmpty ? '' : ': ${w.query}'} · every ${w.everyMinutes ?? 15} min',
  _ => w.scope.label,
};

IconData watchModeIcon(WatchMode m) => switch (m) {
  WatchMode.notify => Icons.notifications_none_rounded,
  WatchMode.summarize => Icons.short_text_rounded,
  WatchMode.act => Icons.bolt_rounded,
};

/// Watches and routines: what they listen to and what they do.
class WatchesScreen extends ConsumerWidget {
  const WatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watches = ref.watch(watchStoreProvider);
    final store = ref.watch(telegramStoreProvider);
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Watches & routines')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.bg,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WatchEditor())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New watch'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 96),
        children: [
          ValueListenableBuilder<WatchStatus>(
            valueListenable: ref.read(watchEngineProvider).status,
            builder: (context, st, _) => Container(
              margin: const EdgeInsets.only(bottom: Space.m),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        st.listening && s.proactive ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                        size: 18,
                        color: st.listening && s.proactive ? AppColors.success : AppColors.text3,
                      ),
                      const SizedBox(width: Space.s),
                      Text(
                        st.listening && s.proactive ? 'Listening' : 'Not listening',
                        style: context.text.titleSmall,
                      ),
                      const Spacer(),
                      Text(
                        '${st.heard} heard · ${st.matched} matched · ${st.opened} chats open',
                        style: context.text.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Icon(
                        st.background ? Icons.nightlight_round : Icons.phone_android_rounded,
                        size: 14,
                        color: st.background ? AppColors.success : AppColors.text3,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          st.background
                              ? 'Keeps running in the background${s.notifications ? '' : ' · notifications off, watches still run'}'
                              : (s.keepAlive || s.backgroundAlways)
                              ? 'Background service not running yet; it starts when a watch is on'
                              : 'Only while the app is open: "Keep running in the background" is off',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (st.last != null) ...[
                    const SizedBox(height: Space.xs),
                    Text('Last match: ${st.last}', style: context.text.bodySmall),
                  ],
                  if (st.error != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(st.error!, style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
                  ],
                ],
              ),
            ),
          ),
          if (!s.proactive)
            Container(
              margin: const EdgeInsets.only(bottom: Space.m),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_outline_rounded, color: AppColors.warning),
                  const SizedBox(width: Space.m),
                  const Expanded(child: Text('Proactivity is off, so every watch is paused.')),
                  TextButton(
                    onPressed: () => ref.read(settingsProvider.notifier).setProactive(true),
                    child: const Text('Turn on'),
                  ),
                ],
              ),
            ),
          if (watches.where((w) => w.builtIn).firstOrNull case final checkIn?) _CheckInCard(watch: checkIn),
          const _OnlineAlerts(),
          if (watches.where((w) => !w.builtIn).isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Text(
                'No watches yet. Make one here, or just ask in chat: "tell me when Liya posts", '
                '"answer my DMs while I\'m busy", "every morning at 8 summarise my channels".',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ),
          for (final w in watches.where((w) => !w.builtIn))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.l),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.l),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchEditor(watch: w))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
                    child: Row(
                      children: [
                        ...leadRow(Icon(watchModeIcon(w.mode), color: w.enabled ? AppColors.accent : AppColors.text3), Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(w.name, style: context.text.titleSmall),
                              Text(
                                '${w.mode.label} · ${watchTrigger(w, store)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall,
                              ),
                              if (w.lastRunAt != null)
                                Text(
                                  'Last ran ${DateFormat('d MMM HH:mm').format(w.lastRunAt!)} · ${w.runs} times',
                                  style: context.text.labelSmall,
                                ),
                            ],
                          ),
                        ),
                        Switch(
                          value: w.enabled,
                          onChanged: (v) => ref.read(watchStoreProvider.notifier).update(w.id, (x) => x.copyWith(enabled: v)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const _Reminders(),
        ],
      ),
    );
  }
}

/// Reminders and scheduled jobs the assistant set up ("remind me to walk in
/// 5 minutes", "every Sunday at 20:00 summarise my channels").
class _Reminders extends ConsumerWidget {
  const _Reminders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(reminderStoreProvider);
    final store = ref.read(reminderStoreProvider.notifier);
    final accounts = ref.watch(accountsProvider);
    final shown = all.where((r) => r.enabled || r.repeats).toList()
      ..sort((a, b) => (a.next ?? DateTime(9999)).compareTo(b.next ?? DateTime(9999)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.s),
          child: Text('REMINDERS & SCHEDULED JOBS', style: context.text.labelSmall),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(
              'None. Ask in chat: "remind me to walk in 5 minutes", "every weekday at 9 remind me to stand up", '
              '"every Sunday at 20:00 summarise my channels".',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xs, Space.m),
                child: Row(
                  children: [
                    ...leadRow(Icon(r.isJob ? Icons.smart_toy_outlined : Icons.alarm_rounded, color: r.enabled ? AppColors.accent : AppColors.text3), Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.text, style: context.text.titleSmall),
                          Text(
                            [
                              if (r.cron != null) Cron.describe(r.cron!),
                              if (r.next != null) 'next ${DateFormat('EEE d MMM HH:mm').format(r.next!)}',
                              if (r.isJob && accounts.hasSeveral) accountScopeLabel(accounts, r.accountIds),
                              if (r.isJob) 'does: ${r.prompt}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'test' => store.runNow(r),
                        'accounts' => pickAccountScope(
                          context,
                          initial: r.accountIds,
                          title: 'ACCOUNTS THIS JOB USES',
                          note: 'When it runs, the assistant may use only these Telegram accounts.',
                        ).then((picked) async {
                          if (picked != null) {
                            await store.update(r.id, (x) => x.copyWith(accountIds: picked.ids, allAccounts: picked.ids == null));
                          }
                        }),
                        'delete' => confirmDelete(
                          context,
                          title: 'Delete this reminder?',
                          message: '"${r.text}" won\'t remind you again.',
                        ).then((ok) async {
                          if (ok) await store.remove(r.id);
                        }),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'test', child: Text('Run now')),
                        if (r.isJob && accounts.hasSeveral) const PopupMenuItem(value: 'accounts', child: Text('Accounts…')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    Switch(
                      value: r.enabled,
                      onChanged: r.next == null && !r.repeats ? null : (v) => store.update(r.id, (x) => x.copyWith(enabled: v)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class WatchEditor extends ConsumerStatefulWidget {
  const WatchEditor({super.key, this.watch});
  final Watch? watch;

  @override
  ConsumerState<WatchEditor> createState() => _WatchEditorState();
}

class _WatchEditorState extends ConsumerState<WatchEditor> {
  late final _name = TextEditingController(text: widget.watch?.name ?? '');
  late final _instructions = TextEditingController(text: widget.watch?.instructions ?? '');
  late WatchScope _scope = widget.watch?.scope ?? (ref.read(telegramConnectedProvider) ? WatchScope.chats : WatchScope.app);
  late WatchMode _mode = widget.watch?.mode ?? WatchMode.notify;
  late List<int> _chatIds = [...?widget.watch?.chatIds];
  late int? _folderId = widget.watch?.folderId;
  late String? _dailyAt = widget.watch?.dailyAt ?? '08:00';
  late int? _every = widget.watch?.everyMinutes;
  late bool _includeMuted = widget.watch?.includeMuted ?? true;
  late bool _notify = widget.watch?.notify ?? true;
  late String _app = widget.watch?.app ?? 'gmail';
  late final _query = TextEditingController(text: widget.watch?.query ?? '');

  /// The accounts it covers (null: all).
  late List<String>? _accounts = widget.watch?.accountIds;

  /// A folder watch's account: folder ids belong to one account.
  late String _folderAccount = widget.watch?.scope == WatchScope.folder
      ? (widget.watch?.folderAccountId ?? legacyAccountId)
      : ref.read(activeAccountIdProvider);

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(watchStoreProvider.notifier);
    final name = _name.text.trim().isEmpty ? 'Watch' : _name.text.trim();
    if (_scope == WatchScope.chats && _chatIds.isEmpty) {
      showSnack(context, 'Pick at least one chat', icon: Icons.info_outline_rounded);
      return;
    }
    if (_scope == WatchScope.folder && _folderId == null) {
      showSnack(context, 'Pick a folder', icon: Icons.info_outline_rounded);
      return;
    }
    final schedule = _scope == WatchScope.schedule;
    final appWatch = _scope == WatchScope.app;
    // Schedules and app watches always need the assistant.
    final mode = (schedule || appWatch) && _mode == WatchMode.notify ? WatchMode.summarize : _mode;
    if (widget.watch == null) {
      await store.add(
        (id) => Watch(
          id: id,
          name: name,
          scope: _scope,
          mode: mode,
          chatIds: _chatIds,
          folderId: _folderId,
          instructions: _instructions.text.trim(),
          includeMuted: _includeMuted,
          notify: _notify,
          dailyAt: schedule && _every == null ? _dailyAt : null,
          everyMinutes: schedule ? _every : (appWatch ? (_every ?? 15) : null),
          createdAt: DateTime.now(),
          app: appWatch ? _app : null,
          query: appWatch ? _query.text.trim() : '',
          accountIds: _scope == WatchScope.folder ? null : _accounts,
          folderAccountId: _scope == WatchScope.folder ? _folderAccount : null,
        ),
      );
    } else {
      await store.update(
        widget.watch!.id,
        (w) => Watch(
          id: w.id,
          name: name,
          scope: _scope,
          mode: mode,
          enabled: w.enabled,
          chatIds: _chatIds,
          folderId: _folderId,
          instructions: _instructions.text.trim(),
          includeMuted: _includeMuted,
          notify: _notify,
          dailyAt: schedule && _every == null ? _dailyAt : null,
          everyMinutes: schedule ? _every : (appWatch ? (_every ?? 15) : null),
          conversationId: w.conversationId,
          lastRunAt: w.lastRunAt,
          runs: w.runs,
          createdAt: w.createdAt,
          app: appWatch ? _app : null,
          query: appWatch ? _query.text.trim() : '',
          // Kept as they were: the editor doesn't show them.
          builtIn: w.builtIn,
          quietAtNight: w.quietAtNight,
          accountIds: _scope == WatchScope.folder ? null : _accounts,
          folderAccountId: _scope == WatchScope.folder ? _folderAccount : null,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickChats() async {
    final picked = await Navigator.of(
      context,
    ).push<List<int>>(MaterialPageRoute(builder: (_) => _ChatPicker(selected: _chatIds)));
    if (picked != null) setState(() => _chatIds = picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final accounts = ref.watch(accountsProvider);
    // The folder's account may not be signed in any more: fall back to the
    // account on screen.
    if (accounts.byId(_folderAccount)?.signedIn != true && accounts.signedIn.isNotEmpty) {
      _folderAccount = accounts.activeId;
    }
    final folderStore = ref.watch(accountStoreProvider(_folderAccount));
    final telegram = ref.watch(telegramConnectedProvider) || accounts.signedIn.isNotEmpty;
    final connected = ref.watch(integrationsProvider).connected;
    final w = widget.watch;
    return Scaffold(
      appBar: AppBar(
        title: Text(w == null ? 'New watch' : 'Edit watch'),
        actions: [
          if (w?.conversationId != null)
            IconButton(
              tooltip: 'Open its conversation',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () {
                ref.read(chatControllerProvider.notifier).open(w!.conversationId!);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          if (w != null)
            IconButton(
              tooltip: 'Run now',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () async {
                final problem = await ref.read(watchEngineProvider).runNow(w);
                if (!context.mounted) return;
                showSnack(
                  context,
                  problem ?? 'Ran "${w.name}". Its update is in the chat, with a notification if you were away.',
                  icon: problem == null ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                );
              },
            ),
          if (w != null && !w.builtIn)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirmDelete(context, title: 'Delete this watch?', message: '"${w.name}" stops watching. Its chat stays.')) {
                  return;
                }
                await ref.read(watchStoreProvider.notifier).remove(w.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: Space.xl),
          Text('WHEN', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in WatchScope.values)
                if (telegram || !s.needsTelegram || _scope == s)
                  ChoiceChip(label: Text(s.label), selected: _scope == s, onSelected: (_) => setState(() => _scope = s)),
            ],
          ),
          const SizedBox(height: Space.m),
          if (_scope == WatchScope.chats)
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
                leading: lead(const Icon(Icons.forum_outlined)),
                title: Text(_chatIds.isEmpty ? 'Choose chats' : '${_chatIds.length} chat${_chatIds.length == 1 ? '' : 's'}'),
                subtitle: _chatIds.isEmpty
                    ? null
                    : Text(
                        _chatIds.map((id) => store.chat(id)?.title ?? '$id').join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickChats,
              ),
            ),
          if (_scope == WatchScope.folder) ...[
            // Folders belong to one account: pick the account, then its folder.
            if (accounts.hasSeveral) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in accounts.signedIn)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: AccountAvatar(account: a, size: 20),
                      label: Text(a.label),
                      selected: _folderAccount == a.id,
                      onSelected: (_) => setState(() {
                        if (_folderAccount != a.id) _folderId = null;
                        _folderAccount = a.id;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Space.s),
            ],
            Wrap(
              spacing: 6,
              children: [
                for (final f in folderStore.folders)
                  ChoiceChip(label: Text(f.title), selected: _folderId == f.id, onSelected: (_) => setState(() => _folderId = f.id)),
                if (folderStore.folders.isEmpty) Text('No folders in this account.', style: context.text.bodySmall),
              ],
            ),
          ],
          if (!telegram)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                'Connect Telegram (Settings → Apps & web) to watch chats, groups, channels and mentions.',
                style: context.text.bodySmall,
              ),
            ),
          if (_scope == WatchScope.app) ...[
            Text(
              connected.isEmpty
                  ? 'Connect an app first (Settings → Apps & web → Composio), e.g. Gmail or Slack.'
                  : 'The assistant checks the app every so often and tells you about anything new that matches.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in {...connected, 'any', if (!connected.contains(_app) && _app != 'any') _app})
                  ChoiceChip(
                    label: Text(a == 'any' ? 'Any app' : appLabel(a)),
                    selected: _app == a,
                    onSelected: (_) => setState(() => _app = a),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _query,
              decoration: const InputDecoration(
                labelText: 'Look for',
                hintText: 'e.g. emails from my manager, Slack messages mentioning me',
              ),
            ),
            const SizedBox(height: Space.m),
            Wrap(
              spacing: 6,
              children: [
                for (final m in const [15, 30, 60, 180, 360])
                  ChoiceChip(
                    label: Text(m < 60 ? 'Every $m min' : 'Every ${m ~/ 60} h'),
                    selected: (_every ?? 15) == m,
                    onSelected: (_) => setState(() => _every = m),
                  ),
              ],
            ),
          ],
          if (_scope == WatchScope.schedule) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Daily at')),
                ButtonSegment(value: false, label: Text('Every…')),
              ],
              selected: {_every == null},
              onSelectionChanged: (v) => setState(() => _every = v.first ? null : (_every ?? 60)),
            ),
            const SizedBox(height: Space.m),
            if (_every == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(_dailyAt ?? '08:00'),
                onPressed: () async {
                  final parts = (_dailyAt ?? '08:00').split(':');
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                  );
                  if (t != null) {
                    setState(() => _dailyAt = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  }
                },
              )
            else
              Wrap(
                spacing: 6,
                children: [
                  for (final m in const [15, 30, 60, 180, 360])
                    ChoiceChip(
                      label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                      selected: _every == m,
                      onSelected: (_) => setState(() => _every = m),
                    ),
                ],
              ),
          ],
          if (_scope.needsTelegram)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include muted chats'),
              value: _includeMuted,
              onChanged: (v) => setState(() => _includeMuted = v),
            ),
          if (_scope != WatchScope.folder && accounts.hasSeveral) ...[
            const SizedBox(height: Space.l),
            AccountScopePicker(
              value: _accounts,
              onChanged: (v) => setState(() => _accounts = v),
              note: _scope.needsTelegram
                  ? 'It hears messages in these accounts, and the assistant may use only them when it runs.'
                  : 'When it runs, the assistant may use only these Telegram accounts.',
            ),
          ],
          const SizedBox(height: Space.xl),
          Text('THEN', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          RadioGroup<WatchMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? _mode),
            child: Column(
              children: [
                for (final m in WatchMode.values)
                  if (!(m == WatchMode.notify && !_scope.needsTelegram))
                    RadioListTile<WatchMode>(
                      contentPadding: EdgeInsets.zero,
                      value: m,
                      title: Row(children: [Icon(watchModeIcon(m), size: 18), const SizedBox(width: Space.s), Text(m.label)]),
                      subtitle: Text(m.explanation, style: context.text.bodySmall),
                    ),
              ],
            ),
          ),
          if (_mode != WatchMode.notify || !_scope.needsTelegram) ...[
            const SizedBox(height: Space.m),
            TextField(
              controller: _instructions,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Instructions',
                alignLabelWithHint: true,
                hintText: _mode == WatchMode.act
                    ? 'e.g. Reply to each new DM politely in their language. If it\'s urgent, notify me.'
                    : 'e.g. Summarise what matters and skip memes.',
              ),
            ),
            if (_mode == WatchMode.act) ...[
              const SizedBox(height: Space.s),
              Text(
                switch (ref.watch(settingsProvider).approvalMode) {
                  ApprovalMode.ask => 'Its actions will wait for your approval. To let it act on its own, change Approvals in Settings.',
                  _ => 'It will act without asking, as Approvals in Settings allow.',
                },
                style: context.text.bodySmall?.copyWith(color: AppColors.warning),
              ),
            ],
          ],
          const SizedBox(height: Space.m),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: lead(Icon(_notify ? Icons.notifications_active_outlined : Icons.notifications_off_outlined)),
            title: const Text('Notify me'),
            subtitle: Text(
              _notify
                  ? 'A notification each time it fires'
                  : 'Runs quietly in the background; results wait in its conversation',
              style: context.text.bodySmall,
            ),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
          const SizedBox(height: Space.xxl),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker({required this.selected, this.peopleOnly = false});
  final List<int> selected;

  /// Only one-to-one chats with people (for online alerts).
  final bool peopleOnly;

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  late final Set<int> _picked = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chats = store.chats.values
        .where((c) => c.isListed && c.title.isNotEmpty && (_q.isEmpty || c.title.toLowerCase().contains(_q)))
        .where((c) => !widget.peopleOnly || store.kindOf(c) == ChatKind.private)
        .toList()
      ..sort((a, b) {
        final pa = _picked.contains(a.id), pb = _picked.contains(b.id);
        if (pa != pb) return pa ? -1 : 1;
        return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
      });
    return Scaffold(
      appBar: AppBar(
        title: Text('${_picked.length} selected'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _picked.toList()), child: const Text('Done'))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search chats',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final c = chats[i];
                return CheckboxListTile(
                  value: _picked.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _picked.add(c.id) : _picked.remove(c.id)),
                  secondary: TgAvatar(chatId: c.id, title: c.title, size: 38),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(store.kindOf(c).name, style: context.text.bodySmall),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// People the user wants to hear about when they come online.
class _OnlineAlerts extends ConsumerWidget {
  const _OnlineAlerts();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final store = ref.read(telegramStoreProvider);
    final picked = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => const _ChatPicker(selected: [], peopleOnly: true)),
    );
    if (picked == null) return;
    for (final chatId in picked) {
      if (store.chat(chatId)?.type case td.ChatTypePrivate(:final userId)) {
        await ref.read(onlineAlertStoreProvider.notifier).add(userId, store.userName(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(onlineAlertStoreProvider);
    final store = ref.watch(telegramStoreProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.m),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.xs),
            child: Row(
              children: [
                Icon(Icons.circle_notifications_outlined, size: 18, color: AppColors.text2),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Online alerts', style: context.text.titleSmall)),
                TextButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text(
                'Get a notification when someone comes online. Works for people who let you see their last seen.',
                style: context.text.bodySmall,
              ),
            ),
          for (final a in alerts)
            Builder(
              builder: (context) {
                final user = store.users[a.userId];
                final name = user == null ? a.name : store.userName(a.userId);
                final status = user?.status;
                final online = status is td.UserStatusOnline;
                final hidden = status is td.UserStatusRecently ||
                    status is td.UserStatusLastWeek ||
                    status is td.UserStatusLastMonth ||
                    status is td.UserStatusEmpty;
                return ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      TgAvatar(userId: a.userId, title: name, size: 38),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: online ? AppColors.success : AppColors.text3,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface2, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      online ? 'Online now' : (hidden ? 'Hides last seen; may not work' : 'Offline'),
                      a.once ? 'once' : 'every time',
                      if (a.fired > 0) 'alerted ${a.fired}×',
                    ].join(' · '),
                    style: context.text.bodySmall?.copyWith(color: hidden ? AppColors.warning : null),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: a.once ? 'Alert every time' : 'Alert once',
                        icon: Icon(a.once ? Icons.looks_one_outlined : Icons.repeat_rounded, size: 20),
                        onPressed: () => ref.read(onlineAlertStoreProvider.notifier).add(a.userId, a.name, once: !a.once),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () async {
                          if (await confirmDelete(
                            context,
                            title: 'Remove this alert?',
                            message: 'You won\'t hear when ${a.name} comes online.',
                            action: 'Remove',
                          )) {
                            await ref.read(onlineAlertStoreProvider.notifier).remove(a.userId);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The built-in check-in: every few hours the assistant looks for one new
/// thing worth the person's attention and sends it as a notification. It
/// can be changed and turned off, not deleted.
class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.watch});
  final Watch watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = watch;
    final hours = (w.everyMinutes ?? 360) / 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => showFormSheet<void>(context, builder: (_) => _CheckInSheet(id: w.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
            child: Row(
              children: [
                ...leadRow(Icon(Icons.tips_and_updates_outlined, color: w.enabled ? AppColors.accent : AppColors.text3), Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check-in', style: context.text.titleSmall),
                      Text(
                        w.enabled
                            ? 'Every ${_hours(hours)}${w.quietAtNight ? ', not at night' : ''}: one new thing worth your attention, with anything it prepared.'
                            : 'Off. Turn on for a nudge every few hours about what needs you.',
                        style: context.text.bodySmall,
                      ),
                      if (w.lastRunAt != null)
                        Text('Last checked ${DateFormat('d MMM HH:mm').format(w.lastRunAt!)}', style: context.text.labelSmall),
                    ],
                  ),
                ),
                Switch(
                  value: w.enabled,
                  onChanged: (v) => ref.read(watchStoreProvider.notifier).update(w.id, (x) => x.copyWith(enabled: v)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _hours(num h) => h == 1 ? 'hour' : '${h % 1 == 0 ? h.toInt() : h} hours';

class _CheckInSheet extends ConsumerStatefulWidget {
  const _CheckInSheet({required this.id});
  final String id;

  @override
  ConsumerState<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<_CheckInSheet> {
  late final _instructions = TextEditingController(text: ref.read(watchStoreProvider.notifier).byId(widget.id)?.instructions ?? '');

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _set(Watch Function(Watch) change) => ref.read(watchStoreProvider.notifier).update(widget.id, change);

  Future<void> _saveText() {
    final text = _instructions.text.trim();
    return _set((x) => x.copyWith(instructions: text.isEmpty ? checkInInstructions : text));
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(watchStoreProvider).where((x) => x.id == widget.id).firstOrNull;
    if (w == null) return const SizedBox.shrink();
    final every = w.everyMinutes ?? 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Check-in', style: context.text.titleMedium)),
            Switch(value: w.enabled, onChanged: (v) => _set((x) => x.copyWith(enabled: v))),
          ],
        ),
        Text(
          'The assistant looks across your chats, apps, reminders and calendar, picks one new thing worth your '
          'attention, prepares what helps (a summary, draft notes) and sends it as a notification. It never sends '
          'or changes anything for you. Built in: turn it off to stop it.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        Text('HOW OFTEN', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in const [1, 2, 3, 6, 12, 24])
              ChoiceChip(
                label: Text('Every ${_hours(h)}'),
                selected: every == h * 60,
                onSelected: (_) => _set((x) => x.copyWith(everyMinutes: h * 60)),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Quiet at night'),
          subtitle: Text('Nothing between 22:00 and 08:00; it catches up in the morning.', style: context.text.bodySmall),
          value: w.quietAtNight,
          onChanged: (v) => _set((x) => x.copyWith(quietAtNight: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify me'),
          subtitle: Text('Off, its notes only land in its chat.', style: context.text.bodySmall),
          value: w.notify,
          onChanged: (v) => _set((x) => x.copyWith(notify: v)),
        ),
        if (ref.watch(accountsProvider).hasSeveral) ...[
          const SizedBox(height: Space.s),
          AccountScopePicker(
            value: w.accountIds,
            onChanged: (v) => _set((x) => x.copyWith(accountIds: v, allAccounts: v == null)),
            note: 'The Telegram accounts it looks through.',
          ),
          const SizedBox(height: Space.s),
        ],
        const SizedBox(height: Space.s),
        Row(
          children: [
            Expanded(child: Text('WHAT TO LOOK FOR', style: context.text.labelSmall)),
            TextButton(
              onPressed: () => setState(() => _instructions.text = checkInInstructions),
              child: const Text('Reset'),
            ),
          ],
        ),
        TextField(
          controller: _instructions,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'What the check-in should look at and how it should tell you'),
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _saveText();
                  final latest = ref.read(watchStoreProvider.notifier).byId(widget.id);
                  if (latest != null) unawaited(ref.read(watchEngineProvider).runNow(latest));
                  if (context.mounted) showSnack(context, 'Checking in now. A notification follows if there is something.');
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Check now'),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await _saveText();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
