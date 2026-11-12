import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/content_filters.dart';
import '../data/telegram_store.dart';
import 'blocked_screen.dart';
import 'tg_avatar.dart';

/// Settings → Telegram → Block & mute: blocked accounts, channels and
/// groups blocked on this phone, muted words, and whether what they hide
/// leaves a "tap to view" notice or disappears.
class BlockMuteScreen extends StatelessWidget {
  const BlockMuteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Block & mute'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Blocked'),
              Tab(text: 'Muted words'),
            ],
          ),
        ),
        body: const TabBarView(children: [_BlockedTab(), _MutedTab()]),
      ),
    );
  }
}

Widget _section(BuildContext context, String title, List<Widget> children) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
      child: Text(title.toUpperCase(), style: context.text.labelSmall),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  ],
);

Widget _noticeSwitch(BuildContext context, {required bool value, required ValueChanged<bool> onChanged}) =>
    SwitchListTile(
      secondary: Icon(value ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.text2),
      title: const Text('Show a "blocked" notice'),
      subtitle: Text(
        value ? 'Hidden messages leave a notice you can tap to view' : 'Hidden messages disappear without a trace',
        style: context.text.bodySmall,
      ),
      value: value,
      onChanged: onChanged,
    );

/// Whether blocks and muted words reach into archived chats too; one
/// setting, shown on both tabs.
class _ArchivedSwitch extends ConsumerWidget {
  const _ArchivedSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(contentFiltersProvider.select((f) => f.inArchived));
    return _section(context, 'Where', [
      SwitchListTile(
        secondary: Icon(Icons.archive_outlined, color: AppColors.text2),
        title: const Text('Also in archived chats'),
        subtitle: Text(
          on ? 'Blocks and muted words hide messages in archived chats too' : 'Archived chats show everything',
          style: context.text.bodySmall,
        ),
        value: on,
        onChanged: ref.read(contentFiltersProvider.notifier).setInArchived,
      ),
    ]);
  }
}

class _BlockedTab extends ConsumerWidget {
  const _BlockedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final filters = ref.watch(contentFiltersProvider);
    final ctl = ref.read(contentFiltersProvider.notifier);
    final accounts = ref.watch(blockedSendersProvider).length;
    final chats = filters.blockedChats.entries.toList()
      ..sort((a, b) => (store.chat(a.key)?.title ?? a.value).compareTo(store.chat(b.key)?.title ?? b.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        const _ArchivedSwitch(),
        _section(context, 'Accounts', [
          ListTile(
            leading: Icon(Icons.person_off_outlined, color: AppColors.text2),
            title: const Text('Blocked accounts'),
            subtitle: Text(
              accounts == 0 ? 'Block people and bots on Telegram' : '$accounts blocked on Telegram',
              style: context.text.bodySmall,
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BlockedScreen())),
          ),
          _noticeSwitch(
            context,
            value: filters.labelBlockedAccounts,
            onChanged: (v) => ctl.setLabels(accounts: v),
          ),
        ]),
        _section(context, 'Channels & groups', [
          _noticeSwitch(context, value: filters.labelBlockedChats, onChanged: (v) => ctl.setLabels(chats: v)),
          for (final e in chats)
            ListTile(
              leading: TgAvatar(chatId: e.key, title: store.chat(e.key)?.title ?? e.value, size: 40),
              title: Text(store.chat(e.key)?.title ?? e.value),
              subtitle: Text(
                switch (store.chat(e.key)) {
                  final c? => store.kindOf(c) == ChatKind.channel ? 'channel' : 'group',
                  null => 'chat',
                },
                style: context.text.bodySmall,
              ),
              trailing: TextButton(onPressed: () => ctl.unblockChat(e.key), child: const Text('Unblock')),
            ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: AppColors.accent),
            title: Text('Block a channel or group', style: TextStyle(color: AppColors.accent)),
            onTap: () async {
              final picked = await showModalBottomSheet<ChatInfo>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const _ChatPicker(),
              );
              if (picked != null) await ctl.blockChat(picked.id, picked.title);
            },
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, 0),
          child: Text(
            'Blocking a channel or group only applies on this phone: you stay in it and can still open it, but '
            'its posts forwarded into other chats, and anything it sends in comments and groups, are hidden.',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Picks a channel or group: any you know, or a public one by @username.
class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker();

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  String _query = '';
  bool _looking = false;
  String? _miss;

  Future<void> _lookUp() async {
    final name = _query.trim().replaceFirst(RegExp(r'^(https?://)?(t\.me/|@)'), '');
    if (name.isEmpty) return;
    setState(() {
      _looking = true;
      _miss = null;
    });
    try {
      final c = await ref.read(telegramClientProvider).send<td.Chat>(td.SearchPublicChat(username: name), limited: true);
      if (!mounted) return;
      final store = ref.read(telegramStoreProvider);
      final info = store.chat(c.id) ?? ChatInfo(id: c.id, title: c.title, type: c.type);
      final kind = store.kindOf(info);
      if (kind == ChatKind.channel || kind == ChatKind.group) {
        Navigator.pop(context, info);
      } else {
        setState(() => _miss = '@$name is not a channel or group');
      }
    } catch (_) {
      if (mounted) setState(() => _miss = 'No public channel or group @$name');
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final blocked = ref.watch(contentFiltersProvider).blockedChats;
    final q = _query.trim().toLowerCase().replaceFirst('@', '');
    final list =
        store.chats.values.where((c) {
          if (c.title.isEmpty || blocked.containsKey(c.id)) return false;
          final k = store.kindOf(c);
          if (k != ChatKind.channel && k != ChatKind.group) return false;
          return q.isEmpty || c.title.toLowerCase().contains(q) || (store.chatUsername(c)?.toLowerCase().contains(q) ?? false);
        }).toList()..sort((a, b) {
          if (a.isListed != b.isListed) return a.isListed ? -1 : 1;
          return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
        });

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search, or @username for any public chat',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _miss = null;
                  }),
                  onSubmitted: (_) => _lookUp(),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (q.isNotEmpty)
                      ListTile(
                        leading: _looking
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.travel_explore_rounded, color: AppColors.text2),
                        title: Text('Find @$q'),
                        subtitle: _miss == null ? null : Text(_miss!, style: context.text.bodySmall),
                        onTap: _looking ? null : _lookUp,
                      ),
                    for (final c in list)
                      ListTile(
                        leading: TgAvatar(chatId: c.id, title: c.title, size: 40),
                        title: Text(c.title),
                        subtitle: Text(
                          [
                            store.kindOf(c) == ChatKind.channel ? 'channel' : 'group',
                            if (store.chatUsername(c) case final u?) '@$u',
                            if (!c.isListed) 'not joined',
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                        onTap: () => Navigator.pop(context, c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutedTab extends ConsumerStatefulWidget {
  const _MutedTab();

  @override
  ConsumerState<_MutedTab> createState() => _MutedTabState();
}

class _MutedTabState extends ConsumerState<_MutedTab> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    final added = ref.read(contentFiltersProvider.notifier).muteWord(_field.text);
    if (added) {
      _field.clear();
    } else if (_field.text.trim().isNotEmpty) {
      showSnack(context, 'Already muted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(contentFiltersProvider);
    final ctl = ref.read(contentFiltersProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        const _ArchivedSwitch(),
        _section(context, 'Muted words', [
          _noticeSwitch(context, value: filters.labelMutedWords, onChanged: (v) => ctl.setLabels(words: v)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _field,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(hintText: 'Add a word or phrase'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add_rounded), tooltip: 'Mute', onPressed: _add),
              ],
            ),
          ),
          for (final w in filters.mutedWords)
            ListTile(
              leading: Icon(Icons.volume_off_outlined, color: AppColors.text2),
              title: Text(w),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Unmute',
                onPressed: () => ctl.unmuteWord(w),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, 0),
          child: Text(
            'Messages with a muted word are hidden in channels, groups, comments and chats. Words match whole, in '
            'any case; your own messages are never hidden.',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }
}
