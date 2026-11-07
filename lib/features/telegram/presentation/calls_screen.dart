import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_actions.dart';
import 'chat_profile_screen.dart';
import 'chat_view_screen.dart';
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../account/account_switcher.dart';

/// The account's call history, as Telegram keeps it: every voice and video
/// call, newest first, with a Missed tab.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: const [AccountSwitcherButton()],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'All'),
            Tab(text: 'Missed'),
          ],
        ),
      ),
      // Keyed by account: switching starts the lists over for that account.
      body: Consumer(
        builder: (context, ref, _) {
          final account = ref.watch(activeAccountIdProvider);
          return TabBarView(
            children: [
              _CallList(key: ValueKey('$account-all'), onlyMissed: false),
              _CallList(key: ValueKey('$account-missed'), onlyMissed: true),
            ],
          );
        },
      ),
    ),
  );
}

class _CallList extends ConsumerStatefulWidget {
  const _CallList({super.key, required this.onlyMissed});
  final bool onlyMissed;

  @override
  ConsumerState<_CallList> createState() => _CallListState();
}

class _CallListState extends ConsumerState<_CallList> with AutomaticKeepAliveClientMixin {
  final List<CallRecord> _calls = [];
  String _next = '';
  bool _loading = false;
  bool _end = false;
  int _total = 0;
  String? _error;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_end && !reset)) return;
    setState(() {
      _loading = true;
      if (reset) {
        _calls.clear();
        _next = '';
        _end = false;
        _error = null;
      }
    });
    try {
      final r = await ref.read(toolRunnerProvider).callHistory(offset: _next, onlyMissed: widget.onlyMissed);
      _calls.addAll(r.calls);
      _total = r.total;
      _next = r.next;
      _end = r.next.isEmpty || r.calls.isEmpty;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_calls.isEmpty) {
      return Center(
        child: _loading
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_outlined, size: 40, color: AppColors.text3),
                  const SizedBox(height: Space.m),
                  Text(_error ?? (widget.onlyMissed ? 'No missed calls' : 'No calls yet'), style: context.text.bodySmall),
                ],
              ),
      );
    }
    final totalSeconds = _calls.fold<int>(0, (a, c) => a + c.call.duration);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: Space.x4),
        itemCount: _calls.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
              child: Text(
                '$_total call${_total == 1 ? '' : 's'}'
                '${widget.onlyMissed ? '' : ' · ${_duration(totalSeconds)} talked in the ${_calls.length} shown'}',
                style: context.text.labelSmall,
              ),
            );
          }
          if (i == _calls.length + 1) {
            return Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Center(
                child: _loading
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const SizedBox.shrink(),
              ),
            );
          }
          final c = _calls[i - 1];
          final prev = i > 1 ? _calls[i - 2] : null;
          final newDay = prev == null || !DateUtils.isSameDay(prev.at, c.at);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (newDay)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
                  child: Text(_day(c.at).toUpperCase(), style: context.text.labelSmall),
                ),
              _CallTile(call: c),
            ],
          );
        },
      ),
    );
  }

  static String _day(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return 'Today';
    if (DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEEE d MMMM' : 'd MMMM y').format(d);
  }
}

String _duration(int s) {
  if (s <= 0) return '0s';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${sec}s';
  return '${sec}s';
}

IconData _directionIcon(CallRecord c) => c.missed || c.declined
    ? (c.outgoing ? Icons.call_missed_outgoing_rounded : Icons.call_missed_rounded)
    : (c.outgoing ? Icons.call_made_rounded : Icons.call_received_rounded);

class _CallTile extends ConsumerWidget {
  const _CallTile({required this.call});
  final CallRecord call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final c = call;
    final chat = store.chat(c.message.chatId);
    final name = chat?.title ?? 'Unknown';
    final bad = !c.outgoing && (c.missed || c.declined);
    return ListTile(
      leading: TgAvatar(chatId: c.message.chatId, title: name, size: 44),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: bad ? AppColors.danger : AppColors.text, fontWeight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          Icon(_directionIcon(c), size: 14, color: bad ? AppColors.danger : AppColors.success),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              [
                c.outgoing ? 'Outgoing' : 'Incoming',
                if (c.call.isVideo) 'video',
                c.call.duration > 0 ? _duration(c.call.duration) : c.outcome.toLowerCase(),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat.Hm().format(c.at), style: context.text.labelSmall),
          const SizedBox(width: Space.s),
          Icon(c.call.isVideo ? Icons.videocam_outlined : Icons.call_outlined, size: 20, color: AppColors.text3),
        ],
      ),
      onTap: () => _showCall(context, ref, c),
    );
  }
}

void _showCall(BuildContext context, WidgetRef ref, CallRecord c) {
  final store = ref.read(telegramStoreProvider);
  final chat = store.chat(c.message.chatId);
  final name = chat?.title ?? 'Unknown';
  Widget row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(k, style: context.text.bodySmall)),
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
                TgAvatar(chatId: c.message.chatId, title: name, size: 52),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: context.text.titleLarge),
                      Row(
                        children: [
                          Icon(_directionIcon(c), size: 16, color: AppColors.text2),
                          const SizedBox(width: 4),
                          Text(
                            '${c.outgoing ? 'Outgoing' : 'Incoming'} ${c.call.isVideo ? 'video' : 'voice'} call',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            row('When', DateFormat('EEEE d MMMM y, HH:mm:ss').format(c.at)),
            row('Outcome', c.outcome),
            row('Duration', c.call.duration > 0 ? _duration(c.call.duration) : 'Not connected'),
            if (c.call.duration > 0)
              row('Ended at', DateFormat('HH:mm:ss').format(c.at.add(Duration(seconds: c.call.duration)))),
            row('Kind', c.call.isVideo ? 'Video call' : 'Voice call'),
            row('Direction', c.outgoing ? 'You called' : 'They called you'),
            if (chat != null) ...[
              if (store.chatUsername(chat) case final u?) row('Username', '@$u'),
              row('Chat ID', '${chat.id}'),
            ],
            row('Message ID', '${c.message.id}'),
            const SizedBox(height: Space.l),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Open chat'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: c.message.chatId)));
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('Profile'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: c.message.chatId)));
                  },
                ),
                if (chat != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Ask AI'),
                    onPressed: () {
                      Navigator.pop(sheet);
                      askAiAbout(context, ref, chat);
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            '${c.outgoing ? 'Outgoing' : 'Incoming'} ${c.call.isVideo ? 'video' : 'voice'} call with $name, '
                            '${DateFormat('d MMM y HH:mm').format(c.at)}, ${c.outcome}, ${_duration(c.call.duration)}',
                      ),
                    );
                    Navigator.pop(sheet);
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
