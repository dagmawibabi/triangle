import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' as widgets show Drag;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_tabs.dart';
import '../../../core/widgets/swipe_back.dart';
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

/// Every chat of the main list, in Telegram's order: what "All" shows.
List<ChatInfo> allChats(TelegramStore store) =>
    inTelegramOrder(store.chats.values.where((c) => c.title.isNotEmpty && c.inMain), 'main');

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

/// One page of the chat list: every chat, a section, or a Telegram folder.
class _ListTab {
  const _ListTab({this.section, this.folder});
  final BrowseSection? section;
  final FolderInfo? folder;

  bool get isAll => section == null && folder == null;
  bool get isContacts => folder == null && section == BrowseSection.contacts;

  /// Identifies the page across rebuilds, and scopes its recent searches.
  String get key => folder != null ? 'folder:${folder!.id}' : (section?.name ?? 'all');
  String get title => folder?.title ?? section?.title ?? 'All';

  /// The TDLib list whose order and pins it follows.
  String get listKey => folder != null ? 'folder:${folder!.id}' : (section == null ? 'main' : listKeyOf(section!));

  /// Its chats, in Telegram's order; null while a folder is still loading.
  List<ChatInfo>? chats(TelegramStore store) {
    if (folder case final f?) {
      final ids = store.folderChats[f.id];
      if (ids == null) return null;
      return inTelegramOrder([
        for (final id in ids)
          if (store.chat(id) case final c? when c.title.isNotEmpty) c,
      ], listKey);
    }
    if (isAll) return allChats(store);
    return chatsIn(store, section!);
  }
}

/// Telegram's chat list: a floating glass header with the folder tabs, and
/// the lists themselves side by side, a swipe apart. Opened on a section
/// or folder, it starts there; contacts get a page of their own.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({
    super.key,
    this.section = BrowseSection.dms,
    this.folder,
    this.all = false,
  });
  final BrowseSection section;

  /// Opens on the "All" tab: every chat of the main list.
  final bool all;

  /// Shows this folder's chats instead of a section.
  final FolderInfo? folder;

  String get title => all ? 'All' : (folder?.title ?? section.title);

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  late final PageController _pages;
  late final ValueNotifier<double> _pos;
  late String _currentKey;
  int _current = 0;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  String _q = '';

  widgets.Drag? _drag;
  final Set<int> _folderLoads = {};

  /// The folder this page opened on; after an account switch, the new
  /// account's folder of the same name, or none.
  late FolderInfo? _folder = widget.folder;

  bool get _contacts => !widget.all && _folder == null && widget.section == BrowseSection.contacts;

  @override
  void initState() {
    super.initState();
    final store = ref.read(telegramStoreProvider);
    store.ensureChatsLoaded();
    _currentKey = widget.all
        ? const _ListTab().key
        : _ListTab(section: _folder == null ? widget.section : null, folder: _folder).key;
    final tabs = _tabsOf(store);
    _current = tabs.indexWhere((t) => t.key == _currentKey).clamp(0, tabs.length - 1);
    _pages = PageController(initialPage: _current);
    _pos = ValueNotifier(_current.toDouble());
    _pages.addListener(_onPage);
    if (_folder != null) store.loadFolder(_folder!.id);
    ref.listenManual(activeAccountIdProvider, (_, _) => _accountSwitched());
  }

  @override
  void dispose() {
    _pages.dispose();
    _pos.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_ListTab> _tabsOf(TelegramStore store) {
    if (_contacts) return const [_ListTab(section: BrowseSection.contacts)];
    final folders = [...store.folders];
    if (_folder case final f? when folders.every((x) => x.id != f.id)) folders.add(f);
    return [
      const _ListTab(),
      for (final s in const [BrowseSection.dms, BrowseSection.groups, BrowseSection.channels, BrowseSection.bots])
        _ListTab(section: s),
      for (final f in folders) _ListTab(folder: f),
      const _ListTab(section: BrowseSection.archived),
    ];
  }

  void _onPage() {
    final p = _pages.page ?? _current.toDouble();
    _pos.value = p;
    final i = p.round();
    if (i != _current) {
      final tabs = _tabsOf(ref.read(telegramStoreProvider));
      if (i < tabs.length) {
        setState(() {
          _current = i;
          _currentKey = tabs[i].key;
        });
      }
    }
  }

  /// Another account was picked: its chats replace these, on the same
  /// page. A folder belongs to one account, so a folder page moves to the
  /// new account's folder of the same name, or to All when it has none.
  void _accountSwitched() {
    final store = ref.read(telegramStoreProvider);
    _folderLoads.clear();
    store.ensureChatsLoaded();
    if (_folder != null) {
      final same = store.folders.where((f) => f.title.trim().toLowerCase() == _folder!.title.trim().toLowerCase()).firstOrNull;
      _folder = same;
      _currentKey = same != null ? _ListTab(folder: same).key : const _ListTab().key;
      if (same != null) store.loadFolder(same.id);
    } else {
      final tabs = _tabsOf(store);
      if (tabs.every((t) => t.key != _currentKey)) _currentKey = const _ListTab().key;
    }
    setState(() {});
  }

  /// Folder lists are read when their page (or the one beside it) shows.
  void _loadNearbyFolders(List<_ListTab> tabs) {
    final store = ref.read(telegramStoreProvider);
    for (var i = _current - 1; i <= _current + 1; i++) {
      if (i < 0 || i >= tabs.length) continue;
      final f = tabs[i].folder;
      if (f != null && _folderLoads.add(f.id)) store.loadFolder(f.id);
    }
  }

  void _goTo(int i) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _search.clear();
    setState(() {
      _searching = false;
      _q = '';
    });
  }

  void _setQuery(String q) {
    _search.text = q;
    _search.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _q = q);
    _remember();
  }

  void _remember() {
    if (_q.trim().isEmpty) return;
    unawaited(ref.read(searchHistoryProvider(_currentKey).notifier).add(_q));
  }

  /// Rightward drags go back a page unless this is the first one, in which
  /// case they're left for the route's swipe-back; leftward ones go on
  /// unless this is the last.
  bool _allowPageDrag(double dx, int count) {
    final p = _pages.hasClients ? (_pages.page ?? _current.toDouble()) : _current.toDouble();
    return dx > 0 ? p > 0.01 : p < count - 1 - 0.01;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final tabs = _tabsOf(store);
    final index = tabs.indexWhere((t) => t.key == _currentKey);
    if (index >= 0 && index != _current) {
      // The folders changed underneath: stay on the same list.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients && _drag == null) _pages.jumpToPage(index);
      });
    } else if (index < 0 && tabs.isNotEmpty) {
      _currentKey = tabs[_current.clamp(0, tabs.length - 1)].key;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNearbyFolders(tabs);
    });

    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final hasTabs = tabs.length > 1;
    final headerHeight = top + Space.s + 48 + (hasTabs ? Space.s + 44 : 0) + Space.s;
    final canPop = Navigator.of(context).canPop();
    final current = tabs[_current.clamp(0, tabs.length - 1)];

    final pager = DirectionalDrag(
      allow: (dx) => _allowPageDrag(dx, tabs.length),
      onStart: (d) => _drag = _pages.position.drag(d, () => _drag = null),
      onUpdate: (d) => _drag?.update(d),
      onEnd: (d) => _drag?.end(d),
      onCancel: () => _drag?.cancel(),
      child: PageView.builder(
        controller: _pages,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tabs.length,
        itemBuilder: (context, i) => _ChatListPage(
          key: ValueKey(tabs[i].key),
          tab: tabs[i],
          query: _q,
          searching: _searching && i == _current,
          topPadding: headerHeight,
          bottomPadding: media.padding.bottom + 96,
          onPickQuery: _setQuery,
        ),
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: pager),
          Positioned(top: 0, left: 0, right: 0, child: HeaderScrim(height: headerHeight + 28)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Space.m, top + Space.s, Space.m, 0),
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        if (canPop || _searching) ...[
                          GlassIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Back',
                            size: 46,
                            onTap: _searching ? _closeSearch : () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: Space.s),
                        ],
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                                child: child,
                              ),
                            ),
                            child: _searching
                                ? _SearchField(
                                    key: const ValueKey('search'),
                                    controller: _search,
                                    focus: _searchFocus,
                                    hint: 'Search ${current.title.toLowerCase()}',
                                    onChanged: (v) => setState(() => _q = v),
                                    onSubmitted: (_) => _remember(),
                                    onClear: () {
                                      _search.clear();
                                      setState(() => _q = '');
                                    },
                                  )
                                : _Title(
                                    key: ValueKey('title:${current.key}'),
                                    title: _contacts ? 'Contacts' : current.title,
                                    count: _contacts ? null : current.chats(store)?.length,
                                  ),
                          ),
                        ),
                        if (!_searching) ...[
                          const SizedBox(width: Space.s),
                          GlassIconButton(icon: Icons.search_rounded, tooltip: 'Search', size: 46, onTap: _openSearch),
                          const AccountSwitcherButton(),
                        ],
                      ],
                    ),
                  ),
                  if (hasTabs) ...[
                    const SizedBox(height: Space.s),
                    GlassTabStrip(
                      position: _pos,
                      onTap: _goTo,
                      tabs: [
                        for (final t in tabs)
                          () {
                            final chats = t.chats(store);
                            final unread = chats?.where((c) => c.hasUnread).toList() ?? const <ChatInfo>[];
                            return GlassTab(
                              t.title,
                              badge: t.section == BrowseSection.archived ? 0 : unread.length,
                              badgeMuted: unread.isNotEmpty && unread.every((c) => c.isMuted),
                            );
                          }(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: const AudioMiniBar(margin: EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({super.key, required this.title, this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(left: Space.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppColors.text),
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: Space.s),
            Text('$count', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text3)),
          ],
        ],
      ),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Glass(
    child: SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
          const SizedBox(width: Space.s),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: TextStyle(fontSize: 15.5, color: AppColors.text),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox(width: Space.m)
                : IconButton(
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: AppColors.text2),
                    onPressed: onClear,
                  ),
          ),
        ],
      ),
    ),
  );
}

/// One list of the pager: its filters, its chats (or, while searching with
/// nothing typed, recent searches and the most-used chats), scrolling
/// under the floating header.
class _ChatListPage extends ConsumerStatefulWidget {
  const _ChatListPage({
    super.key,
    required this.tab,
    required this.query,
    required this.searching,
    required this.topPadding,
    required this.bottomPadding,
    required this.onPickQuery,
  });
  final _ListTab tab;
  final String query;
  final bool searching;
  final double topPadding;
  final double bottomPadding;
  final ValueChanged<String> onPickQuery;

  @override
  ConsumerState<_ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends ConsumerState<_ChatListPage> with AutomaticKeepAliveClientMixin {
  late final SearchHistoryController _history;
  late final SearchHistoryController _recentChats;

  /// The chats Telegram counts as this list's most used, for the row of
  /// faces over the search panel; loaded the first time search opens here.
  List<int>? _top;
  bool _unreadOnly = false;
  ChatRole _role = ChatRole.any;
  bool _myBots = false;
  List<int>? _contacts;
  String? _error;

  _ListTab get _tab => widget.tab;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _history = ref.read(searchHistoryProvider(_scope).notifier);
    _recentChats = ref.read(recentChatsProvider(_scope).notifier);
    if (_tab.isContacts) _loadContacts();
    if (widget.searching) _loadTop();
    ref.listenManual(activeAccountIdProvider, (_, _) {
      _top = null;
      if (_tab.isContacts) {
        setState(() {
          _contacts = null;
          _error = null;
        });
        _loadContacts();
      }
    });
  }

  @override
  void didUpdateWidget(_ChatListPage old) {
    super.didUpdateWidget(old);
    if (widget.searching && !old.searching && _top == null) _loadTop();
  }

  String get _scope => _tab.key;

  td.TopChatCategory? get _topCategory => _tab.folder != null || _tab.isAll
      ? const td.TopChatCategoryUsers()
      : switch (_tab.section!) {
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
    if (!always && widget.query.trim().isEmpty) return;
    if (widget.query.trim().isNotEmpty) unawaited(_history.add(widget.query));
    unawaited(_recentChats.add('$id'));
  }

  void _openRecent(int id) {
    _opened(id, always: true);
    if (_tab.isContacts) {
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
      _openChat(chat.id);
    } catch (e) {
      if (mounted)
        showSnack(
          context,
          'Couldn\'t open the chat: $e',
          icon: Icons.error_outline_rounded,
        );
    }
  }

  bool get _roleFilters =>
      _tab.section == BrowseSection.channels || _tab.section == BrowseSection.groups;

  static const _spinner = SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = ref.watch(telegramStoreProvider);
    final q = widget.query.toLowerCase().trim();
    final runner = ref.read(toolRunnerProvider);
    final source = _tab.isContacts ? const <ChatInfo>[] : (_tab.chats(store) ?? const <ChatInfo>[]);
    final loaded = _tab.isContacts || (_tab.folder == null ? store.chatsLoaded : _tab.chats(store) != null);

    final Widget body;
    if (_tab.isContacts) {
      final ids = _contacts;
      if (_error != null) {
        body = _Message(_error!);
      } else if (ids == null) {
        body = _spinner;
      } else {
        final users =
            ids.map((id) => store.users[id]).whereType<td.User>().where((u) {
              if (q.isEmpty) return true;
              final name = '${u.firstName} ${u.lastName}'.toLowerCase();
              return name.contains(q) || (store.username(u.usernames)?.toLowerCase().contains(q) ?? false);
            }).toList()..sort(
              (a, b) => store.userName(a.id).toLowerCase().compareTo(store.userName(b.id).toLowerCase()),
            );
        body = users.isEmpty
            ? const _Message('No contacts')
            : SliverList.builder(
                itemCount: users.length,
                itemBuilder: (_, i) => _ContactTile(user: users[i], onTap: () => _openContact(users[i].id)),
              );
      }
    } else {
      final chats = source.where((c) {
        if (_unreadOnly && !c.hasUnread) return false;
        if (_role != ChatRole.any && !runner.hasRole(c, _role)) return false;
        if (_myBots && !runner.ownsBot(c)) return false;
        if (q.isEmpty) return true;
        return c.title.toLowerCase().contains(q) || (store.chatUsername(c)?.toLowerCase().contains(q) ?? false);
      }).toList();
      body = !loaded && chats.isEmpty
          ? _spinner
          : chats.isEmpty
          ? _Message(_unreadOnly ? 'Nothing unread' : (q.isEmpty ? 'Nothing here' : 'No chats match “${widget.query.trim()}”'))
          : SliverList.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) => ChatTile(
                chat: chats[i],
                pinned: chats[i].pinnedIn.contains(_tab.listKey),
                onTap: () {
                  _opened(chats[i].id);
                  _openChat(chats[i].id);
                },
              ),
            );
    }

    final history = ref.watch(searchHistoryProvider(_scope));
    final recentIds = [for (final x in ref.watch(recentChatsProvider(_scope))) ?int.tryParse(x)];
    final top = [
      for (final id in _top ?? const <int>[])
        if (store.chat(id) case final c? when c.title.isNotEmpty) c,
    ];
    final showHistory = widget.searching && q.isEmpty && (history.isNotEmpty || recentIds.isNotEmpty || top.isNotEmpty);

    final filters = <Widget>[
      if (!_tab.isContacts)
        _FilterPill(
          label: 'Unread',
          icon: Icons.mark_chat_unread_outlined,
          selected: _unreadOnly,
          onTap: () => setState(() => _unreadOnly = !_unreadOnly),
        ),
      if (_roleFilters)
        for (final r in ChatRole.values)
          if (r != ChatRole.any)
            _FilterPill(
              label: '${r.label} · ${source.where((c) => runner.hasRole(c, r)).length}',
              selected: _role == r,
              onTap: () => setState(() => _role = _role == r ? ChatRole.any : r),
            ),
      if (_tab.section == BrowseSection.bots)
        _FilterPill(
          label: 'My bots · ${source.where(runner.ownsBot).length}',
          selected: _myBots,
          onTap: () => setState(() => _myBots = !_myBots),
        ),
    ];

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
        if (showHistory) ...[
          if (top.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 108,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                  children: [for (final c in top) _TopPeer(chat: c, onTap: () => _openRecent(c.id))],
                ),
              ),
            ),
          if (history.isNotEmpty || recentIds.isNotEmpty) SliverToBoxAdapter(child: RecentHeader(onClear: _clearAll)),
          if (history.isNotEmpty)
            SliverToBoxAdapter(
              child: RecentTermChips(terms: history, onPick: widget.onPickQuery, onRemove: _history.remove),
            ),
          SliverList.list(
            children: [
              for (final id in recentIds)
                RecentChatRow(
                  id: id,
                  contact: _tab.isContacts,
                  onTap: () => _openRecent(id),
                  onRemove: () => _recentChats.remove('$id'),
                ),
            ],
          ),
        ] else ...[
          if (filters.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
                child: Wrap(spacing: Space.s, runSpacing: Space.s, children: filters),
              ),
            ),
          body,
        ],
        SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      color: selected ? AppColors.tint.withValues(alpha: 0.18) : AppColors.surface2.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: selected ? AppColors.tint.withValues(alpha: 0.45) : AppColors.line),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: selected ? AppColors.text : AppColors.text2),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.text : AppColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(text, textAlign: TextAlign.center, style: context.text.bodySmall),
      ),
    ),
  );
}

/// A chat row as Telegram draws it: a large face (with a green dot when
/// they're online), the name and when the last message came, then who
/// said what, with the unread count, a mention mark or a pin at the end.
class ChatTile extends ConsumerWidget {
  const ChatTile({super.key, required this.chat, required this.onTap, this.onLongPress, this.pinned = false});
  final ChatInfo chat;
  final VoidCallback onTap;

  /// Pinned in the list it is shown in: the time sits in a pin pill, and a
  /// pin shows where the unread badge would.
  final bool pinned;

  /// Defaults to the chat menu.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final kind = store.kindOf(chat);
    final last = chat.lastMessage;
    String who = '';
    String body = '';
    var media = false;
    if (last != null) {
      final g = gistOf(last.content);
      final text = g.kind == 'rich' ? (g.detail ?? '') : (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind));
      who = kind == ChatKind.group
          ? (last.isOutgoing ? 'You: ' : '${store.senderName(last.senderId).split(' ').first}: ')
          : (last.isOutgoing && kind != ChatKind.channel && kind != ChatKind.saved ? 'You: ' : '');
      final icon = _kindLabel(g.kind);
      media = g.kind != 'text' && g.text.isEmpty;
      body = '${icon.isEmpty ? '' : '$icon '}$text'.replaceAll('\n', ' ');
    }
    final unread = chat.unreadCount > 0 || chat.markedUnread;
    final compact = ref.watch(settingsProvider.select((s) => s.compactList));
    final avatar = compact ? 46.0 : 56.0;
    final online = switch (chat.type) {
      td.ChatTypePrivate(:final userId) when kind == ChatKind.private => store.users[userId]?.status is td.UserStatusOnline,
      _ => false,
    };
    final outgoing = last != null && last.isOutgoing && kind != ChatKind.channel && kind != ChatKind.saved;
    final read = outgoing && last.id <= chat.lastReadOutboxMessageId;
    final timeColor = unread && !chat.isMuted ? AppColors.accent : AppColors.text3;
    final mediaColor = AppColors.isLight ? AppColors.tint : Color.lerp(AppColors.tint, const Color(0xFF8FA8FF), 0.55)!;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress ?? () => showChatMenu(context, ref, chat),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.m, compact ? 5 : 7, Space.l, compact ? 5 : 7),
        child: Row(
          children: [
            SizedBox.square(
              dimension: avatar,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  kind == ChatKind.saved
                      ? SavedAvatar(size: avatar)
                      : TgAvatar(chatId: chat.id, title: chat.title, size: avatar),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 1,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DDC84),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      if (kind == ChatKind.channel) _KindMark(Icons.campaign_rounded),
                      if (kind == ChatKind.bot) _KindMark(Icons.smart_toy_rounded),
                      if (kind == ChatKind.group) _KindMark(Icons.groups_rounded),
                      if (kind == ChatKind.secret) _KindMark(Icons.lock_rounded, color: AppColors.success),
                      Flexible(
                        child: Text(
                          kind == ChatKind.saved ? 'Saved Messages' : chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.text),
                        ),
                      ),
                      if (chat.isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.volume_off_rounded, size: 14, color: AppColors.text3),
                      ],
                      const Spacer(),
                      if (outgoing) ...[
                        const SizedBox(width: Space.s),
                        Icon(
                          last.sendingState != null
                              ? Icons.schedule_rounded
                              : (read ? Icons.done_all_rounded : Icons.done_rounded),
                          size: 17,
                          color: read ? AppColors.accent : AppColors.text3,
                        ),
                      ],
                      if (last != null) ...[
                        const SizedBox(width: 4),
                        pinned
                            ? Container(
                                padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surface3.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Transform.rotate(
                                      angle: 0.6,
                                      child: Icon(Icons.push_pin_rounded, size: 12, color: AppColors.text3),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(shortTime(last.date), style: TextStyle(fontSize: 12.5, color: timeColor)),
                                  ],
                                ),
                              )
                            : Text(shortTime(last.date), style: TextStyle(fontSize: 13, color: timeColor)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (who.isNotEmpty)
                                TextSpan(text: who, style: TextStyle(color: AppColors.text)),
                              TextSpan(text: body, style: TextStyle(color: media ? mediaColor : AppColors.text2)),
                            ],
                          ),
                          maxLines: compact ? 1 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, height: 1.3),
                        ),
                      ),
                      if (chat.unreadMentionCount > 0) ...[
                        const SizedBox(width: Space.xs),
                        const _Badge(text: '@', muted: false),
                      ],
                      if (chat.unreadReactionCount > 0) ...[
                        const SizedBox(width: Space.xs),
                        _Badge(text: '♥', muted: chat.isMuted, danger: true),
                      ],
                      if (unread) ...[
                        const SizedBox(width: Space.xs),
                        _Badge(
                          text: chat.unreadCount > 0 ? NumberFormat.compact().format(chat.unreadCount) : '',
                          muted: chat.isMuted,
                        ),
                      ] else if (pinned) ...[
                        const SizedBox(width: Space.xs),
                        Transform.rotate(
                          angle: 0.6,
                          child: Icon(Icons.push_pin_rounded, size: 16, color: AppColors.text3),
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
    'audio' => '🎧',
    'document' => '📎',
    'poll' => '📊',
    'rich' => '📰',
    'sticker' => '',
    _ => '',
  };
}

class _KindMark extends StatelessWidget {
  const _KindMark(this.icon, {this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Icon(icon, size: 15, color: color ?? AppColors.text2),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.muted, this.danger = false});
  final String text;
  final bool muted;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = muted ? AppColors.text3.withValues(alpha: 0.45) : (danger ? AppColors.danger : AppColors.accent);
    final fg = muted
        ? AppColors.text
        : (bg.computeLuminance() > 0.5 ? const Color(0xFF0B0B0D) : Colors.white);
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
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
class RecentChatRow extends ConsumerWidget {
  const RecentChatRow({required this.id, required this.contact, required this.onTap, required this.onRemove});

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
    final online = status == 'online';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 7),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 50,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  TgAvatar(userId: user.id, title: name, size: 50),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DDC84),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (username != null) '@$username', status].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: online ? AppColors.accent : AppColors.text3),
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
