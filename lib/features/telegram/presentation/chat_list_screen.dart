import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/message_content.dart';
import '../data/search_history.dart';
import '../data/telegram_store.dart';
import '../../media/audio_player_ui.dart';
import '../../settings/data/settings.dart';
import '../data/telegram_tools.dart';
import 'chat_actions.dart';
import 'chat_view_screen.dart';
import 'recent_searches.dart';
import 'tg_avatar.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../account/account_switcher.dart';

enum BrowseSection {
  dms('DMs', Icons.person_outline_rounded),
  bots('Bots', Icons.smart_toy_outlined),
  groups('Groups', Icons.groups_outlined),
  channels('Channels', Icons.campaign_outlined),
  contacts('Contacts', Icons.contacts_outlined),
  archived('Archived', Icons.archive_outlined);

  const BrowseSection(this.title, this.icon);
  final String title;
  final IconData icon;

  bool includes(ChatKind kind) => switch (this) {
    dms =>
      kind == ChatKind.private ||
          kind == ChatKind.saved ||
          kind == ChatKind.secret,
    bots => kind == ChatKind.bot,
    groups => kind == ChatKind.group,
    channels => kind == ChatKind.channel,
    contacts => false,
    archived => true,
  };
}

/// The TDLib list a section's chats come from: `main` or `archive`.
String listKeyOf(BrowseSection section) => section == BrowseSection.archived ? 'archive' : 'main';

/// [chats] in Telegram's order for list [key]: pinned chats first, in the
/// order they were pinned, then the rest by latest activity.
List<ChatInfo> inTelegramOrder(Iterable<ChatInfo> chats, String key) => chats.toList()
  ..sort((a, b) {
    final pinned = (b.pinnedIn.contains(key) ? 1 : 0).compareTo(a.pinnedIn.contains(key) ? 1 : 0);
    if (pinned != 0) return pinned;
    final order = (b.order[key] ?? 0).compareTo(a.order[key] ?? 0);
    return order != 0 ? order : (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
  });

/// Listed chats of a section, pinned first, then newest activity.
List<ChatInfo> chatsIn(TelegramStore store, BrowseSection section) => inTelegramOrder(
  store.chats.values.where(
    (c) =>
        c.title.isNotEmpty &&
        (section == BrowseSection.archived ? c.inArchive : c.inMain) &&
        section.includes(store.kindOf(c)),
  ),
  listKeyOf(section),
);

/// 24-hour clock in times (set from Settings at the app's root).
bool clock24 = true;

/// A clock time in the chosen format.
String clockTime(DateTime d) => clock24 ? DateFormat.Hm().format(d) : DateFormat.jm().format(d);

String shortTime(int unix) {
  final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day)
    return clockTime(d);
  if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
  if (d.year == now.year) return DateFormat.MMMd().format(d);
  return DateFormat.yMd().format(d);
}

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({
    super.key,
    this.section = BrowseSection.dms,
    this.folder,
  });
  final BrowseSection section;

  /// Shows this folder's chats instead of a section.
  final FolderInfo? folder;

  String get title => folder?.title ?? section.title;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  String _q = '';
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final SearchHistoryController _history;
  late final SearchHistoryController _recentChats;

  /// The chats Telegram counts as this list's most used, for the row of
  /// faces over the search panel; loaded the first time the box is focused.
  List<int>? _top;
  bool _unreadOnly = false;
  ChatRole _role = ChatRole.any;
  bool _myBots = false;
  List<int>? _contacts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _history = ref.read(searchHistoryProvider(_historyScope).notifier);
    _recentChats = ref.read(recentChatsProvider(_historyScope).notifier);
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _top == null) _loadTop();
      setState(() {});
    });
    ref.read(telegramStoreProvider).ensureChatsLoaded();
    if (widget.folder == null && widget.section == BrowseSection.contacts)
      _loadContacts();
    if (widget.folder != null)
      ref.read(telegramStoreProvider).loadFolder(widget.folder!.id);
    ref.listenManual(activeAccountIdProvider, (_, _) => _accountSwitched());
  }

  /// Each list keeps its own recent searches.
  String get _historyScope => widget.folder == null ? widget.section.name : 'folder:${widget.folder!.id}';

  /// Saves what's typed as a recent search.
  void _remember() => unawaited(_history.add(_q));

  td.TopChatCategory? get _topCategory => widget.folder != null
      ? const td.TopChatCategoryUsers()
      : switch (widget.section) {
          BrowseSection.dms || BrowseSection.contacts => const td.TopChatCategoryUsers(),
          BrowseSection.bots => const td.TopChatCategoryBots(),
          BrowseSection.groups => const td.TopChatCategoryGroups(),
          BrowseSection.channels => const td.TopChatCategoryChannels(),
          BrowseSection.archived => null,
        };

  Future<void> _loadTop() async {
    _top = const [];
    final category = _topCategory;
    if (category == null) return;
    try {
      final r = await ref
          .read(telegramClientProvider)
          .send<td.Chats>(td.GetTopChats(category: category, limit: 20), limited: true);
      if (mounted) setState(() => _top = r.chatIds);
    } catch (_) {
      // Top chats can be turned off in Telegram; the row just stays away.
    }
  }

  /// Notes a chat (or contact) opened while searching, for "Recent".
  void _opened(int id, {bool always = false}) {
    if (!always && _q.trim().isEmpty) return;
    _remember();
    unawaited(_recentChats.add('$id'));
  }

  void _openRecent(int id) {
    _opened(id, always: true);
    if (widget.folder == null && widget.section == BrowseSection.contacts) {
      _openContact(id);
    } else {
      _openChat(id);
    }
  }

  void _clearAll() {
    _history.clear();
    _recentChats.clear();
  }

  void _openChat(int id) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: id)),
  );

  void _pickRecent(String q) {
    _search.text = q;
    _search.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _q = q);
    _remember();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Another account was picked from the app bar: its chats replace these.
  /// A folder belongs to one account, so its page closes instead.
  void _accountSwitched() {
    if (widget.folder != null) {
      Navigator.of(context).maybePop();
      return;
    }
    ref.read(telegramStoreProvider).ensureChatsLoaded();
    if (widget.section == BrowseSection.contacts) {
      setState(() {
        _contacts = null;
        _error = null;
      });
      _loadContacts();
    }
  }

  Future<void> _loadContacts() async {
    try {
      final users = await ref
          .read(telegramClientProvider)
          .send<td.Users>(const td.GetContacts(), limited: true);
      if (mounted) setState(() => _contacts = users.userIds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _openContact(int userId) async {
    _opened(userId);
    try {
      // Opens (or finds) the private chat; nothing is sent.
      final chat = await ref
          .read(telegramClientProvider)
          .send<td.Chat>(
            td.CreatePrivateChat(userId: userId, force: false),
            limited: true,
          );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatViewScreen(chatId: chat.id),
        ),
      );
    } catch (e) {
      if (mounted)
        showSnack(
          context,
          'Couldn\'t open the chat: $e',
          icon: Icons.error_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final q = _q.toLowerCase().trim();
    final contacts =
        widget.folder == null && widget.section == BrowseSection.contacts;
    final folderIds = widget.folder == null
        ? null
        : store.folderChats[widget.folder!.id];
    final listKey = widget.folder == null ? listKeyOf(widget.section) : 'folder:${widget.folder!.id}';
    final source = widget.folder == null
        ? chatsIn(store, widget.section)
        : inTelegramOrder([
            for (final id in folderIds ?? const <int>[])
              if (store.chat(id) case final c? when c.title.isNotEmpty) c,
          ], listKey);

    final Widget body;
    if (contacts) {
      final ids = _contacts;
      if (_error != null) {
        body = _Message(_error!);
      } else if (ids == null) {
        body = const Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      } else {
        final users =
            ids.map((id) => store.users[id]).whereType<td.User>().where((u) {
              if (q.isEmpty) return true;
              final name = '${u.firstName} ${u.lastName}'.toLowerCase();
              return name.contains(q) ||
                  (store.username(u.usernames)?.toLowerCase().contains(q) ??
                      false);
            }).toList()..sort(
              (a, b) => store
                  .userName(a.id)
                  .toLowerCase()
                  .compareTo(store.userName(b.id).toLowerCase()),
            );
        body = users.isEmpty
            ? const _Message('No contacts')
            : ListView.builder(
                itemCount: users.length,
                itemBuilder: (_, i) => _ContactTile(
                  user: users[i],
                  onTap: () => _openContact(users[i].id),
                ),
              );
      }
    } else {
      final runner = ref.read(toolRunnerProvider);
      final chats = source.where((c) {
        if (_unreadOnly && !c.hasUnread) return false;
        if (_role != ChatRole.any && !runner.hasRole(c, _role)) return false;
        if (_myBots && !runner.ownsBot(c)) return false;
        if (q.isEmpty) return true;
        return c.title.toLowerCase().contains(q) ||
            (store.chatUsername(c)?.toLowerCase().contains(q) ?? false);
      }).toList();
      body =
          (widget.folder == null ? !store.chatsLoaded : folderIds == null) &&
              chats.isEmpty
          ? const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : chats.isEmpty
          ? _Message(_unreadOnly ? 'Nothing unread' : 'Nothing here')
          : ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) => ChatTile(
                chat: chats[i],
                pinned: chats[i].pinnedIn.contains(listKey),
                onTap: () {
                  _opened(chats[i].id);
                  _openChat(chats[i].id);
                },
              ),
            );
    }

    final history = ref.watch(searchHistoryProvider(_historyScope));
    final recentIds = [for (final x in ref.watch(recentChatsProvider(_historyScope))) ?int.tryParse(x)];
    final top = [
      for (final id in _top ?? const <int>[])
        if (store.chat(id) case final c? when c.title.isNotEmpty) c,
    ];
    final showHistory =
        _searchFocus.hasFocus && q.isEmpty && (history.isNotEmpty || recentIds.isNotEmpty || top.isNotEmpty);
    final count = contacts ? (_contacts?.length ?? 0) : source.length;
    return Scaffold(
      appBar: AppBar(
        actions: const [AccountSwitcherButton()],
        title: Row(
          children: [
            Text(widget.title),
            const SizedBox(width: Space.s),
            if (count > 0)
              Text(
                '$count',
                style: context.text.titleMedium?.copyWith(
                  color: AppColors.text3,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          const AudioMiniBar(
            margin: EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _q = v),
                    onSubmitted: (_) => _remember(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Search ${widget.title.toLowerCase()}',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppColors.text3,
                      ),
                    ),
                  ),
                ),
                if (!contacts) ...[
                  const SizedBox(width: Space.s),
                  FilterChip(
                    label: const Text('Unread'),
                    selected: _unreadOnly,
                    onSelected: (v) => setState(() => _unreadOnly = v),
                  ),
                ],
              ],
            ),
          ),
          if (!contacts && widget.folder == null && _roleFilters)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                children: [
                  for (final r in ChatRole.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s),
                      child: ChoiceChip(
                        label: Text(
                          '${r.label}${r == ChatRole.any ? '' : ' · ${source.where((c) => ref.read(toolRunnerProvider).hasRole(c, r)).length}'}',
                        ),
                        selected: _role == r,
                        onSelected: (_) => setState(() => _role = r),
                      ),
                    ),
                ],
              ),
            ),
          if (!contacts && widget.folder == null && widget.section == BrowseSection.bots)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                children: [
                  ChoiceChip(label: const Text('All bots'), selected: !_myBots, onSelected: (_) => setState(() => _myBots = false)),
                  const SizedBox(width: Space.s),
                  ChoiceChip(
                    label: Text('My bots · ${source.where(ref.read(toolRunnerProvider).ownsBot).length}'),
                    selected: _myBots,
                    onSelected: (_) => setState(() => _myBots = true),
                  ),
                ],
              ),
            ),
          Expanded(
            child: showHistory
                ? ListView(
                    children: [
                      if (top.isNotEmpty)
                        SizedBox(
                          height: 108,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                            children: [
                              for (final c in top) _TopPeer(chat: c, onTap: () => _openRecent(c.id)),
                            ],
                          ),
                        ),
                      if (history.isNotEmpty || recentIds.isNotEmpty) RecentHeader(onClear: _clearAll),
                      if (history.isNotEmpty)
                        RecentTermChips(terms: history, onPick: _pickRecent, onRemove: _history.remove),
                      for (final id in recentIds)
                        _RecentChatRow(
                          id: id,
                          contact: contacts,
                          onTap: () => _openRecent(id),
                          onRemove: () => _recentChats.remove('$id'),
                        ),
                    ],
                  )
                : body,
          ),
        ],
      ),
    );
  }

  bool get _roleFilters =>
      widget.section == BrowseSection.channels || widget.section == BrowseSection.groups;
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Text(text, style: context.text.bodySmall),
    ),
  );
}

class ChatTile extends ConsumerWidget {
  const ChatTile({super.key, required this.chat, required this.onTap, this.onLongPress, this.pinned = false});
  final ChatInfo chat;
  final VoidCallback onTap;

  /// Pinned in the list it is shown in: a pin where the unread badge goes.
  final bool pinned;

  /// Defaults to the chat menu.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final kind = store.kindOf(chat);
    final last = chat.lastMessage;
    String preview = '';
    if (last != null) {
      final g = gistOf(last.content);
      final body = g.kind == 'rich' ? (g.detail ?? '') : (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind));
      final who = kind == ChatKind.group
          ? (last.isOutgoing
                ? 'You: '
                : '${store.senderName(last.senderId).split(' ').first}: ')
          : (last.isOutgoing && kind != ChatKind.channel ? 'You: ' : '');
      preview = '$who${g.kind == 'text' ? '' : '${_kindLabel(g.kind)} '}$body'
          .replaceAll('\n', ' ');
    }
    final unread = chat.unreadCount > 0 || chat.markedUnread;
    final compact = ref.watch(settingsProvider.select((s) => s.compactList));
    final avatar = compact ? 40.0 : 48.0;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress ?? () => showChatMenu(context, ref, chat),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.l, vertical: compact ? 6 : 10),
        child: Row(
          children: [
            kind == ChatKind.saved
                ? SavedAvatar(size: avatar)
                : TgAvatar(chatId: chat.id, title: chat.title, size: avatar),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (kind == ChatKind.channel)
                        Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.campaign_outlined,
                            size: 14,
                            color: AppColors.text3,
                          ),
                        ),
                      if (kind == ChatKind.bot)
                        Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.smart_toy_outlined,
                            size: 14,
                            color: AppColors.text3,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          kind == ChatKind.saved
                              ? 'Saved Messages'
                              : chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (chat.isMuted)
                        Icon(
                          Icons.volume_off_rounded,
                          size: 14,
                          color: AppColors.text3,
                        ),
                      if (last != null) ...[
                        const SizedBox(width: Space.s),
                        Text(
                          shortTime(last.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? AppColors.accent : AppColors.text3,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.text2,
                          ),
                        ),
                      ),
                      if (chat.unreadMentionCount > 0) ...[
                        const SizedBox(width: Space.xs),
                        const _Badge(text: '@', muted: false),
                      ],
                      if (unread) ...[
                        const SizedBox(width: Space.xs),
                        _Badge(
                          text: chat.unreadCount > 0
                              ? NumberFormat.compact().format(chat.unreadCount)
                              : '',
                          muted: chat.isMuted,
                        ),
                      ] else if (pinned) ...[
                        const SizedBox(width: Space.xs),
                        Transform.rotate(
                          angle: 0.6,
                          child: Icon(Icons.push_pin_rounded, size: 15, color: AppColors.text3),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
    'photo' => '🖼',
    'video' || 'gif' || 'video_note' => '🎬',
    'voice' => '🎤',
    'audio' => '🎵',
    'document' => '📎',
    'poll' => '📊',
    'rich' => '📰',
    'sticker' => '',
    _ => '',
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.muted});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: muted ? AppColors.surface3 : AppColors.accent,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: muted ? AppColors.text2 : AppColors.bg,
      ),
    ),
  );
}

/// "last seen recently", "online", … for a person.
String lastSeenText(td.UserStatus? status) => switch (status) {
  td.UserStatusOnline() => 'online',
  td.UserStatusOffline(:final wasOnline) => 'last seen ${shortTime(wasOnline)}',
  td.UserStatusRecently() => 'last seen recently',
  td.UserStatusLastWeek() => 'last seen within a week',
  td.UserStatusLastMonth() => 'last seen within a month',
  _ => 'last seen a long time ago',
};

/// One face in the row of most-used chats over the search panel.
class _TopPeer extends StatelessWidget {
  const _TopPeer({required this.chat, required this.onTap});
  final ChatInfo chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Radii.m),
    onTap: onTap,
    child: SizedBox(
      width: 78,
      child: Column(
        children: [
          TgAvatar(chatId: chat.id, title: chat.title, size: 60),
          const SizedBox(height: 6),
          Text(
            chat.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: AppColors.text),
          ),
        ],
      ),
    ),
  );
}

/// A chat (or contact) opened from a search: face, name and a status line,
/// like "last seen recently", "bot" or "16 557 subscribers". Long-press
/// removes it.
class _RecentChatRow extends ConsumerWidget {
  const _RecentChatRow({required this.id, required this.contact, required this.onTap, required this.onRemove});

  /// A chat id, or for [contact] a user id (the same as their chat's).
  final int id;
  final bool contact;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(id);
    final userId = switch (chat?.type) {
      td.ChatTypePrivate(:final userId) => userId,
      _ => contact ? id : null,
    };
    final user = userId == null ? null : store.users[userId];
    final title = chat != null && chat.title.isNotEmpty ? chat.title : (user != null ? store.userName(user.id) : '');
    if (title.isEmpty) return const SizedBox.shrink();
    final kind = chat == null ? ChatKind.private : store.kindOf(chat);
    final members = chat == null ? null : store.memberCount(chat);
    String count(int n) => NumberFormat.decimalPattern().format(n).replaceAll(',', ' ');
    final sub = switch (kind) {
      ChatKind.saved => 'your cloud storage',
      ChatKind.bot => 'bot',
      ChatKind.private || ChatKind.secret => lastSeenText(user?.status),
      ChatKind.channel => members == null ? 'channel' : '${count(members)} subscribers',
      ChatKind.group => members == null ? 'group' : '${count(members)} members',
    };
    return InkWell(
      onTap: onTap,
      onLongPress: () async {
        final remove = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text('Remove $title from recent'),
              onTap: () => Navigator.pop(sheet, true),
            ),
          ),
        );
        if (remove == true) onRemove();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: Row(
          children: [
            chat == null && userId != null
                ? TgAvatar(userId: userId, title: title, size: 52)
                : TgAvatar(chatId: id, title: title, size: 52),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      color: sub == 'online' ? AppColors.accent : AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.user, required this.onTap});
  final td.User user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final name = store.userName(user.id);
    final username = store.username(user.usernames);
    final status = lastSeenText(user.status);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: 2,
      ),
      leading: TgAvatar(userId: user.id, title: name, size: 44),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (username != null) '@$username', status].join(' · '),
        style: TextStyle(
          fontSize: 12.5,
          color: status == 'online' ? AppColors.accent : AppColors.text3,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Telegram's folder icon names as Material icons.
IconData folderIcon(String name) => switch (name) {
  'All' => Icons.chat_bubble_outline_rounded,
  'Unread' => Icons.mark_chat_unread_outlined,
  'Unmuted' => Icons.notifications_none_rounded,
  'Bots' => Icons.smart_toy_outlined,
  'Channels' => Icons.campaign_outlined,
  'Groups' => Icons.groups_outlined,
  'Private' => Icons.person_outline_rounded,
  'Setup' => Icons.settings_outlined,
  'Cat' => Icons.pets_outlined,
  'Crown' => Icons.workspace_premium_outlined,
  'Favorite' => Icons.star_outline_rounded,
  'Flower' => Icons.local_florist_outlined,
  'Game' => Icons.sports_esports_outlined,
  'Home' => Icons.home_outlined,
  'Love' => Icons.favorite_outline_rounded,
  'Mask' => Icons.theater_comedy_outlined,
  'Party' => Icons.celebration_outlined,
  'Sport' => Icons.sports_soccer_outlined,
  'Study' => Icons.school_outlined,
  'Trade' => Icons.trending_up_rounded,
  'Travel' => Icons.flight_outlined,
  'Work' => Icons.work_outline_rounded,
  'Airplane' => Icons.flight_outlined,
  'Book' => Icons.menu_book_outlined,
  'Light' => Icons.lightbulb_outline_rounded,
  'Like' => Icons.thumb_up_alt_outlined,
  'Money' => Icons.payments_outlined,
  'Note' => Icons.music_note_outlined,
  'Palette' => Icons.palette_outlined,
  _ => Icons.folder_outlined,
};
