import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../chat/presentation/widgets/post_viewer.dart' show kindIcon;
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_actions.dart' show confirmAction;
import 'chat_view_screen.dart';
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../account/account_switcher.dart';

/// Every message waiting to be sent, across all chats: grouped by when it
/// goes out or by the chat it goes to, with send-now, reschedule, copy and
/// delete.
class ScheduledScreen extends ConsumerStatefulWidget {
  const ScheduledScreen({super.key});

  @override
  ConsumerState<ScheduledScreen> createState() => _ScheduledScreenState();
}

enum _Group { date, chat }

class _ScheduledScreenState extends ConsumerState<ScheduledScreen> {
  List<td.Message>? _messages;
  String? _error;
  bool _loading = false;
  _Group _group = _Group.date;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
    ref.listenManual(activeAccountIdProvider, (_, _) {
      setState(() => _messages = null);
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = ref.read(telegramStoreProvider);
    final client = ref.read(telegramClientProvider);
    // Telegram flags the chats that have any; without flags (an older
    // session) the most active chats one can write to are checked.
    var chats = store.chats.values.where((c) => c.hasScheduled).toList();
    if (chats.isEmpty) {
      chats = (store.chats.values.where((c) => c.isListed && store.canPost(c)).toList()
            ..sort((a, b) => (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0)))
          .take(25)
          .toList();
    }
    final out = <td.Message>[];
    try {
      for (final c in chats) {
        final r = await client.send<td.Messages>(td.GetChatScheduledMessages(chatId: c.id), limited: true);
        out.addAll(r.messages.whereType<td.Message>());
      }
    } catch (e) {
      _error = '$e';
    }
    out.sort((a, b) => _sendAt(a).compareTo(_sendAt(b)));
    if (mounted) {
      setState(() {
        _messages = out;
        _loading = false;
      });
    }
  }

  static int _sendAt(td.Message m) => switch (m.schedulingState) {
    td.MessageSchedulingStateSendAtDate(:final sendDate) => sendDate,
    _ => 1 << 40,
  };

  static String _bucket(td.Message m) {
    final at = _sendAt(m);
    if (at >= 1 << 40) return 'When they come online';
    final d = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return DateFormat('EEEE').format(d);
    if (d.year == now.year) return DateFormat('EEEE d MMMM').format(d);
    return DateFormat('d MMMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final q = _q.toLowerCase().trim();
    final all = (_messages ?? const <td.Message>[]).where((m) {
      if (q.isEmpty) return true;
      return gistOf(m.content).text.toLowerCase().contains(q) ||
          (store.chat(m.chatId)?.title.toLowerCase().contains(q) ?? false);
    }).toList();
    final groups = <String, List<td.Message>>{};
    for (final m in all) {
      final key = _group == _Group.date ? _bucket(m) : (store.chat(m.chatId)?.title ?? '${m.chatId}');
      (groups[key] ??= []).add(m);
    }
    final next = all.where((m) => _sendAt(m) < 1 << 40).firstOrNull;
    final chatCount = {for (final m in all) m.chatId}.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduled messages'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
          const AccountSwitcherButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            if (_messages != null)
              Container(
                padding: const EdgeInsets.all(Space.l),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.l),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    _Stat('${all.length}', 'waiting'),
                    _Stat('$chatCount', chatCount == 1 ? 'chat' : 'chats'),
                    _Stat(
                      next == null
                          ? '—'
                          : DateFormat('d MMM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_sendAt(next) * 1000)),
                      'next',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.m),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s),
                SegmentedButton<_Group>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Group.date, icon: Icon(Icons.event_rounded, size: 16), label: Text('Date')),
                    ButtonSegment(value: _Group.chat, icon: Icon(Icons.forum_outlined, size: 16), label: Text('Chat')),
                  ],
                  selected: {_group},
                  onSelectionChanged: (v) => setState(() => _group = v.first),
                ),
              ],
            ),
            if (_messages == null)
              const Padding(
                padding: EdgeInsets.all(Space.x4),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  children: [
                    Icon(Icons.schedule_send_outlined, size: 44, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text(_error ?? 'Nothing scheduled', style: context.text.bodySmall),
                    const SizedBox(height: Space.s),
                    Text(
                      'Ask the assistant to "schedule a message to … for tomorrow at 9".',
                      textAlign: TextAlign.center,
                      style: context.text.labelSmall,
                    ),
                  ],
                ),
              ),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
                child: Row(
                  children: [
                    if (_group == _Group.chat && g.value.isNotEmpty) ...[
                      TgAvatar(chatId: g.value.first.chatId, title: g.key, size: 22),
                      const SizedBox(width: Space.s),
                    ],
                    Expanded(child: Text(g.key.toUpperCase(), style: context.text.labelSmall)),
                    Text('${g.value.length}', style: context.text.labelSmall),
                  ],
                ),
              ),
              for (final m in g.value) _ScheduledTile(message: m, showChat: _group == _Group.date, onChanged: _load),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: context.text.labelSmall),
      ],
    ),
  );
}

class _ScheduledTile extends ConsumerWidget {
  const _ScheduledTile({required this.message, required this.showChat, required this.onChanged});
  final td.Message message;
  final bool showChat;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final m = message;
    final g = gistOf(m.content);
    final chat = store.chat(m.chatId);
    final at = _ScheduledScreenState._sendAt(m);
    final when = at >= 1 << 40 ? 'When online' : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(at * 1000));
    final date = at >= 1 << 40 ? '' : DateFormat('EEE d MMM').format(DateTime.fromMillisecondsSinceEpoch(at * 1000));
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => _details(context, ref),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Column(
                    children: [
                      Text(when, style: context.text.titleSmall?.copyWith(color: AppColors.accent)),
                      if (!showChat && date.isNotEmpty) Text(date, style: context.text.labelSmall),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showChat)
                        Row(
                          children: [
                            TgAvatar(chatId: m.chatId, title: chat?.title ?? '', size: 20),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                chat?.title ?? 'Chat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (g.kind != 'text') ...[
                            Icon(kindIcon(g.kind), size: 14, color: AppColors.text3),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              g.text.isNotEmpty ? g.text : (g.detail ?? g.kind),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium,
                            ),
                          ),
                        ],
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

  void _details(BuildContext context, WidgetRef ref) {
    final store = ref.read(telegramStoreProvider);
    final client = ref.read(telegramClientProvider);
    final m = message;
    final g = gistOf(m.content);
    final chat = store.chat(m.chatId);
    final at = _ScheduledScreenState._sendAt(m);

    Future<void> setWhen(td.MessageSchedulingState? state, String done) async {
      try {
        await client.send<td.Ok>(
          td.EditMessageSchedulingState(chatId: m.chatId, messageId: m.id, schedulingState: state),
          limited: true,
        );
        if (context.mounted) showSnack(context, done, icon: Icons.schedule_send_outlined);
        onChanged();
      } catch (e) {
        if (context.mounted) showSnack(context, 'Couldn\'t change it: $e', icon: Icons.error_outline_rounded);
      }
    }

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: context.text.bodySmall)),
          Expanded(child: SelectableText(v, style: context.text.bodyMedium)),
        ],
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TgAvatar(chatId: m.chatId, title: chat?.title ?? '', size: 40),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(chat?.title ?? 'Chat', style: context.text.titleMedium)),
                ],
              ),
              const SizedBox(height: Space.l),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                child: SelectableText(g.text.isNotEmpty ? g.text : (g.detail ?? g.kind), style: context.text.bodyLarge),
              ),
              const SizedBox(height: Space.l),
              row(
                'Goes out',
                at >= 1 << 40
                    ? 'When they next come online'
                    : DateFormat('EEEE d MMMM y, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(at * 1000)),
              ),
              if (at < 1 << 40) row('In', _until(DateTime.fromMillisecondsSinceEpoch(at * 1000))),
              row('Written', DateFormat('d MMM y, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(m.date * 1000))),
              row('Type', g.kind),
              if (chat != null) row('Chat', '${store.kindOf(chat).name} · ${chat.id}'),
              row('Message ID', '${m.id}'),
              const SizedBox(height: Space.l),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send now'),
                    onPressed: () {
                      Navigator.pop(sheet);
                      setWhen(null, 'Sent');
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Reschedule'),
                    onPressed: () async {
                      final base = at >= 1 << 40
                          ? DateTime.now().add(const Duration(hours: 1))
                          : DateTime.fromMillisecondsSinceEpoch(at * 1000);
                      final day = await showDatePicker(
                        context: sheet,
                        initialDate: base,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (day == null || !sheet.mounted) return;
                      final time = await showTimePicker(context: sheet, initialTime: TimeOfDay.fromDateTime(base));
                      if (time == null || !sheet.mounted) return;
                      final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
                      Navigator.pop(sheet);
                      await setWhen(
                        td.MessageSchedulingStateSendAtDate(sendDate: when.millisecondsSinceEpoch ~/ 1000, repeatPeriod: 0),
                        'Rescheduled for ${DateFormat('d MMM HH:mm').format(when)}',
                      );
                    },
                  ),
                  if (chat != null && chat.type is td.ChatTypePrivate)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: const Text('When online'),
                      onPressed: () {
                        Navigator.pop(sheet);
                        setWhen(const td.MessageSchedulingStateSendWhenOnline(), 'Will send when they come online');
                      },
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: g.text));
                      Navigator.pop(sheet);
                      showSnack(context, 'Copied');
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Open chat'),
                    onPressed: () {
                      Navigator.pop(sheet);
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: m.chatId)));
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                    onPressed: () async {
                      Navigator.pop(sheet);
                      if (!await confirmAction(
                        context,
                        title: 'Delete this scheduled message?',
                        message: 'It won\'t be sent.',
                        action: 'Delete',
                      )) {
                        return;
                      }
                      try {
                        await ref.read(toolRunnerProvider).deleteMessages(m.chatId, [m.id], forEveryone: true);
                        onChanged();
                      } catch (e) {
                        if (context.mounted) showSnack(context, 'Couldn\'t delete: $e', icon: Icons.error_outline_rounded);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _until(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) return 'any moment';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}
