import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_tabs.dart';
import '../../../core/widgets/swipe_back.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_actions.dart';
import 'chat_list_screen.dart' show lastSeenText;
import 'chat_profile_screen.dart';
import 'message_tile.dart' show MessageTile;
import 'tg_avatar.dart';

enum _MemberFilter {
  recent('Recent'),
  admins('Admins'),
  bots('Bots'),
  restricted('Restricted'),
  banned('Banned');

  const _MemberFilter(this.label);
  final String label;
}

/// A group's members or a channel's subscribers (Telegram shows a channel's
/// list only to its admins), with search, role filters and, for admins,
/// removing and banning.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, required this.chatId, this.initialFilter = 'recent'});
  final int chatId;

  /// recent, admins, bots, restricted or banned.
  final String initialFilter;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> with SingleTickerProviderStateMixin {
  final List<td.ChatMember> _members = [];
  int _total = 0;
  bool _loading = false;
  bool _end = false;
  String? _error;
  String _q = '';
  Timer? _debounce;
  late _MemberFilter _filter = _MemberFilter.values.asNameMap()[widget.initialFilter] ?? _MemberFilter.recent;
  final _scroll = ScrollController();

  td.ChatPermissions? _defaults;
  bool _showDefaults = false;

  /// Where the filter tabs' lozenge sits (unbounded: a filter index).
  late final AnimationController _tabPos = AnimationController.unbounded(vsync: this, value: _filter.index.toDouble());

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
    });
    _load();
    ref.read(toolRunnerProvider).chatPermissions(widget.chatId).then((p) {
      if (mounted) setState(() => _defaults = p);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _tabPos.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reset() {
    _members.clear();
    _end = false;
    _error = null;
    _load();
  }

  Future<void> _load() async {
    if (_loading || _end) return;
    final store = ref.read(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    if (chat == null) return;
    setState(() => _loading = true);
    final client = ref.read(telegramClientProvider);
    try {
      switch (chat.type) {
        case td.ChatTypeSupergroup(:final supergroupId):
          final q = _q.trim();
          final td.SupergroupMembersFilter filter = switch (_filter) {
            _MemberFilter.recent => q.isEmpty ? const td.SupergroupMembersFilterRecent() : td.SupergroupMembersFilterSearch(query: q),
            _MemberFilter.admins => const td.SupergroupMembersFilterAdministrators(),
            _MemberFilter.bots => const td.SupergroupMembersFilterBots(),
            _MemberFilter.restricted => td.SupergroupMembersFilterRestricted(query: q),
            _MemberFilter.banned => td.SupergroupMembersFilterBanned(query: q),
          };
          final r = await client.send<td.ChatMembers>(
            td.GetSupergroupMembers(supergroupId: supergroupId, filter: filter, offset: _members.length, limit: 100),
            limited: true,
          );
          _total = r.totalCount;
          _members.addAll(r.members.where((m) => _members.every((x) => !_same(x.memberId, m.memberId))));
          _end = r.members.isEmpty || _members.length >= r.totalCount;
        case td.ChatTypeBasicGroup(:final basicGroupId):
          final info = await client.send<td.BasicGroupFullInfo>(
            td.GetBasicGroupFullInfo(basicGroupId: basicGroupId),
            limited: true,
          );
          final q = _q.trim().toLowerCase();
          _members
            ..clear()
            ..addAll(
              info.members.where((m) {
                final ok = switch (_filter) {
                  _MemberFilter.admins =>
                    m.status is td.ChatMemberStatusAdministrator || m.status is td.ChatMemberStatusCreator,
                  _MemberFilter.bots => store.users[_userId(m.memberId)]?.type is td.UserTypeBot,
                  _MemberFilter.recent => true,
                  _ => false,
                };
                return ok && (q.isEmpty || store.senderName(m.memberId).toLowerCase().contains(q));
              }),
            );
          _total = info.members.length;
          _end = true;
        default:
          _end = true;
      }
    } catch (e) {
      _error = '$e';
      _end = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  static int _userId(td.MessageSender s) => switch (s) {
    td.MessageSenderUser(:final userId) => userId,
    _ => 0,
  };

  static bool _same(td.MessageSender a, td.MessageSender b) => switch ((a, b)) {
    (td.MessageSenderUser(userId: final x), td.MessageSenderUser(userId: final y)) => x == y,
    (td.MessageSenderChat(chatId: final x), td.MessageSenderChat(chatId: final y)) => x == y,
    _ => false,
  };

  /// Moves to another filter: the list reloads and the tabs' lozenge slides.
  void _pick(_MemberFilter f, List<_MemberFilter> filters) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _reset();
    });
    _tabPos.animateTo(filters.indexOf(f).toDouble(), duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  double _dragDx = 0;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    final channel = chat != null && store.kindOf(chat) == ChatKind.channel;
    final admin = chat != null && store.isAdmin(chat);
    final filters = [
      _MemberFilter.recent,
      _MemberFilter.admins,
      _MemberFilter.bots,
      if (admin && chat.type is td.ChatTypeSupergroup) ...[_MemberFilter.restricted, _MemberFilter.banned],
    ];
    final index = filters.indexOf(_filter).clamp(0, filters.length - 1);
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = top + Space.s + 46 + Space.s + 44 + Space.s;
    final noun = channel ? 'Subscribers' : 'Members';

    final list = CustomScrollView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: headerHeight + Space.xs)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Glass(
              opacity: 0.5,
              child: SizedBox(
                height: 44,
                child: TextField(
                  onChanged: (v) {
                    _q = v;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 450), () {
                      if (mounted) setState(_reset);
                    });
                  },
                  style: TextStyle(fontSize: 15, color: AppColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: 'Search ${noun.toLowerCase()}',
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_defaults case final d? when !channel && _filter == _MemberFilter.recent)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: _GroupCard(
                child: InkWell(
                  onTap: () => setState(() => _showDefaults = !_showDefaults),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 20, color: AppColors.text2),
                            const SizedBox(width: Space.m),
                            Expanded(child: Text('What members can do', style: context.text.titleSmall)),
                            Text(
                              '${permissionsOf(d).values.where((v) => v).length}/${permissionsOf(d).length}',
                              style: TextStyle(fontSize: 13.5, color: AppColors.text3),
                            ),
                            const SizedBox(width: Space.xs),
                            AnimatedRotation(
                              turns: _showDefaults ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more_rounded, color: AppColors.text3),
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: !_showDefaults
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: Space.m),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final e in permissionsOf(d).entries)
                                        _RolePill(
                                          '${e.value ? '✓' : '✕'} ${e.key.replaceAll('_', ' ')}',
                                          color: e.value ? AppColors.success : AppColors.danger,
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_members.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: _loading
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text(
                        _error ??
                            (channel && !admin
                                ? 'Telegram only shows a channel\'s subscribers to its admins.'
                                : 'Nobody here'),
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall,
                      ),
                    ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
              ),
              sliver: SliverList.builder(
                itemCount: _members.length + (_end ? 0 : 1),
                itemBuilder: (_, i) {
                  if (i == _members.length) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.l),
                      child: Center(
                        child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    );
                  }
                  return MemberRow(
                    member: _members[i],
                    chatId: widget.chatId,
                    canManage: admin,
                    divider: i < _members.length - 1,
                    onChanged: () => setState(_reset),
                  );
                },
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.x4)),
      ],
    );

    return Scaffold(
      body: Stack(
        children: [
          // A sideways swipe moves between filters; past the first one it
          // is left for the page's swipe-back.
          Positioned.fill(
            child: DirectionalDrag(
              allow: (dx) => dx > 0 ? index > 0 : index < filters.length - 1,
              onStart: (_) => _dragDx = 0,
              onUpdate: (d) => _dragDx += d.delta.dx,
              onEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (_dragDx < -56 || v < -400) {
                  _pick(filters[(index + 1).clamp(0, filters.length - 1)], filters);
                } else if (_dragDx > 56 || v > 400) {
                  _pick(filters[(index - 1).clamp(0, filters.length - 1)], filters);
                }
              },
              child: list,
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: HeaderScrim(height: headerHeight + 24)),
          Positioned(
            top: top + Space.s,
            left: Space.m,
            right: Space.m,
            child: Column(
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      size: 46,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Center(
                        child: Glass(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                chat?.title ?? noun,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.text),
                              ),
                              Text(
                                _total > 0 ? '${NumberFormat.decimalPattern().format(_total)} ${noun.toLowerCase()}' : noun.toLowerCase(),
                                style: TextStyle(fontSize: 12, color: AppColors.text2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    const SizedBox(width: 46),
                  ],
                ),
                const SizedBox(height: Space.s),
                GlassTabStrip(
                  position: _tabPos,
                  tabs: [for (final f in filters) GlassTab(f == _MemberFilter.recent ? noun : f.label)],
                  onTap: (i) => _pick(filters[i], filters),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded card the rows of a list sit in, Telegram's grouped style.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface.withValues(alpha: 0.9),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.xl),
      side: BorderSide(color: AppColors.line.withValues(alpha: 0.6)),
    ),
    child: child,
  );
}

/// A tinted pill for a role or custom title ("Owner", "Pirate").
class _RolePill extends StatelessWidget {
  const _RolePill(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// The first members of a group, in a card, for its profile page; "See
/// all" opens the full list.
class MembersCard extends ConsumerStatefulWidget {
  const MembersCard({super.key, required this.chatId, this.limit = 40});
  final int chatId;
  final int limit;

  @override
  ConsumerState<MembersCard> createState() => _MembersCardState();
}

class _MembersCardState extends ConsumerState<MembersCard> {
  List<td.ChatMember>? _members;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(telegramStoreProvider);
    final client = ref.read(telegramClientProvider);
    final chat = store.chat(widget.chatId);
    try {
      switch (chat?.type) {
        case td.ChatTypeSupergroup(:final supergroupId):
          final r = await client.send<td.ChatMembers>(
            td.GetSupergroupMembers(
              supergroupId: supergroupId,
              filter: const td.SupergroupMembersFilterRecent(),
              offset: 0,
              limit: widget.limit,
            ),
            limited: true,
          );
          _members = r.members;
          _total = r.totalCount;
        case td.ChatTypeBasicGroup(:final basicGroupId):
          final info = await client.send<td.BasicGroupFullInfo>(
            td.GetBasicGroupFullInfo(basicGroupId: basicGroupId),
            limited: true,
          );
          _members = info.members.take(widget.limit).toList();
          _total = info.members.length;
        default:
          _members = const [];
      }
    } catch (e) {
      _error = '$e';
      _members = const [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chat = store.chat(widget.chatId);
    final admin = chat != null && store.isAdmin(chat);
    final members = _members;
    if (members == null) {
      return const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Center(child: Text(_error ?? 'Nobody here', style: context.text.bodySmall)),
      );
    }
    // Owner first, then admins, then everyone else as Telegram lists them.
    int rank(td.ChatMember m) => switch (m.status) {
      td.ChatMemberStatusCreator() => 0,
      td.ChatMemberStatusAdministrator() => 1,
      _ => 2,
    };
    final sorted = [...members]..sort((a, b) => rank(a).compareTo(rank(b)));
    return _GroupCard(
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++)
            MemberRow(
              member: sorted[i],
              chatId: widget.chatId,
              canManage: admin,
              divider: true,
              onChanged: () {
                setState(() => _members = null);
                _load();
              },
            ),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => MembersScreen(chatId: widget.chatId)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.people_alt_outlined, size: 20, color: AppColors.accent),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Text(
                      _total > sorted.length
                          ? 'See all ${NumberFormat.decimalPattern().format(_total)} members'
                          : 'Search and manage members',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _role(td.ChatMemberStatus s) => switch (s) {
  td.ChatMemberStatusCreator() => 'Owner',
  td.ChatMemberStatusAdministrator() => 'Admin',
  td.ChatMemberStatusRestricted() => 'Restricted',
  td.ChatMemberStatusBanned() => 'Banned',
  td.ChatMemberStatusLeft() => 'Left',
  td.ChatMemberStatusMember() => '',
};

/// A member as Telegram's member list shows them: face, name, when they
/// were last seen, and on the right their title (a coloured pill for the
/// owner and admins, plain grey for a member's tag).
class MemberRow extends ConsumerWidget {
  const MemberRow({
    super.key,
    required this.member,
    required this.chatId,
    required this.canManage,
    required this.onChanged,
    this.divider = false,
  });
  final td.ChatMember member;
  final int chatId;
  final bool canManage;
  final VoidCallback onChanged;

  /// A hairline under the row, from the name onward.
  final bool divider;

  static const _avatar = 46.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    final m = member;
    final name = store.senderName(m.memberId);
    final userId = _MembersScreenState._userId(m.memberId);
    final user = store.users[userId];
    final role = [_role(m.status), if (m.tag.isNotEmpty) m.tag].where((e) => e.isNotEmpty).join(' · ');
    final bot = user?.type is td.UserTypeBot;
    final status = bot ? 'bot' : (user == null ? '' : lastSeenText(user.status));
    final online = status == 'online';
    final staff = m.status is td.ChatMemberStatusCreator || m.status is td.ChatMemberStatusAdministrator;
    final title = m.tag.isNotEmpty ? m.tag : _role(m.status);
    final Widget? trailing = switch (m.status) {
      td.ChatMemberStatusBanned() => _RolePill('Banned', color: AppColors.danger),
      td.ChatMemberStatusRestricted() => _RolePill(title.isEmpty ? 'Restricted' : title, color: AppColors.warning),
      _ when staff => _RolePill(
        title,
        color: m.status is td.ChatMemberStatusCreator ? const Color(0xFFB69CFF) : MessageTile.nameColor(title),
      ),
      _ when title.isNotEmpty => Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, color: AppColors.text3),
      ),
      _ => null,
    };
    return InkWell(
      onTap: () => _showMember(context, ref, userId, name, role),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.m),
        child: Row(
          children: [
            switch (m.memberId) {
              td.MessageSenderUser(:final userId) => TgAvatar(userId: userId, title: name, size: _avatar),
              td.MessageSenderChat(:final chatId) => TgAvatar(chatId: chatId, title: name, size: _avatar),
            },
            const SizedBox(width: Space.m),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 9, Space.l, 9),
                decoration: BoxDecoration(
                  border: divider
                      ? Border(bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.7), width: 0.6))
                      : null,
                ),
                child: Row(
                  children: [
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
                          if (status.isNotEmpty)
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: online ? AppColors.accent : AppColors.text3),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: Space.s),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: trailing),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMember(BuildContext context, WidgetRef ref, int userId, String name, String role) {
    final store = ref.read(telegramStoreProvider);
    final runner = ref.read(toolRunnerProvider);
    final m = member;
    final mine = userId == store.me?.id;
    final manageable = canManage && !mine && m.status is! td.ChatMemberStatusCreator && userId != 0;
    final inviter = m.inviterUserId == 0 ? null : store.userName(m.inviterUserId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: TgAvatar(userId: userId == 0 ? null : userId, title: name, size: 44),
              title: Text(name, style: context.text.titleMedium),
              subtitle: Text(
                [
                  if (role.isNotEmpty) role,
                  if (store.users[userId] case final u? when store.username(u.usernames) != null)
                    '@${store.username(u.usernames)}',
                  if (m.joinedChatDate > 0)
                    'joined ${DateFormat('d MMM y, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(m.joinedChatDate * 1000))}',
                  if (inviter != null) 'added by $inviter',
                  if (m.status case td.ChatMemberStatusBanned(:final bannedUntilDate) when bannedUntilDate > 0)
                    'banned until ${DateFormat('d MMM y').format(DateTime.fromMillisecondsSinceEpoch(bannedUntilDate * 1000))}',
                ].join(' · '),
                style: context.text.bodySmall,
              ),
            ),
            if (_rightsLines(m.status) case final lines when lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (label, on) in lines)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (on ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${on ? '✓' : '✕'} $label',
                          style: TextStyle(fontSize: 11.5, color: on ? AppColors.success : AppColors.danger),
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
            if (userId != 0)
              ListTile(
                leading: lead(const Icon(Icons.person_outline_rounded)),
                title: const Text('View profile'),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: userId)));
                },
              ),
            if (manageable && m.status is td.ChatMemberStatusBanned)
              ListTile(
                leading: lead(const Icon(Icons.lock_open_rounded)),
                title: const Text('Unban'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await runner.unbanMember(chatId, userId);
                  onChanged();
                },
              ),
            if (manageable && m.status is! td.ChatMemberStatusBanned) ...[
              ListTile(
                leading: lead(Icon(Icons.person_remove_outlined, color: AppColors.danger)),
                title: Text('Remove', style: TextStyle(color: AppColors.danger)),
                subtitle: const Text('They can come back with a link'),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (!await confirmAction(
                    context,
                    title: 'Remove $name?',
                    message: 'They are removed now and can rejoin later.',
                    action: 'Remove',
                  )) {
                    return;
                  }
                  try {
                    await runner.banMember(chatId, userId);
                    await runner.unbanMember(chatId, userId);
                    onChanged();
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Couldn\'t remove: $e', icon: Icons.error_outline_rounded);
                  }
                },
              ),
              ListTile(
                leading: lead(Icon(Icons.gavel_rounded, color: AppColors.danger)),
                title: Text('Ban', style: TextStyle(color: AppColors.danger)),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (!await confirmAction(
                    context,
                    title: 'Ban $name?',
                    message: 'They are removed and can\'t rejoin until unbanned.',
                    action: 'Ban',
                  )) {
                    return;
                  }
                  try {
                    await runner.banMember(chatId, userId);
                    onChanged();
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Couldn\'t ban: $e', icon: Icons.error_outline_rounded);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a member's status lets them do (admins) or not do (restricted).
List<(String, bool)> _rightsLines(td.ChatMemberStatus s) => switch (s) {
  td.ChatMemberStatusCreator() => const [('All rights (owner)', true)],
  td.ChatMemberStatusAdministrator(:final rights) => [for (final r in adminRightsOf(rights)) (r, true)],
  td.ChatMemberStatusRestricted(:final permissions, :final restrictedUntilDate) => [
    for (final e in permissionsOf(permissions).entries) (e.key.replaceAll('_', ' '), e.value),
    if (restrictedUntilDate > 0)
      ('until ${DateFormat('d MMM y').format(DateTime.fromMillisecondsSinceEpoch(restrictedUntilDate * 1000))}', false),
  ],
  _ => const [],
};
