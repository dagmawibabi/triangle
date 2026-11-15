import 'blocked_screen.dart';
import 'members_screen.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../chat/presentation/widgets/post_viewer.dart';
import '../../media/audio_center.dart';
import '../../media/audio_player_ui.dart';
import '../../../infrastructure/telegram/accounts.dart' show activeAccountIdProvider;
import '../../playlists/playlists.dart' show PlaylistTrack;
import '../../playlists/playlist_widgets.dart' show showAddToPlaylist;
import '../data/file_loader.dart';
import '../data/message_content.dart';
import '../data/telegram_store.dart';
import '../../settings/presentation/settings_screen.dart';
import 'chat_actions.dart';
import 'chat_list_screen.dart' show shortTime;
import 'chat_view_screen.dart';
import 'formatted_text.dart';
import 'message_tile.dart' show snapshotOf;
import 'tg_avatar.dart';
import 'analytics_screen.dart';
import 'search_screen.dart';
import '../../../core/widgets/fullscreen_image.dart';

/// A chat's profile, the way Telegram lays it out: who or what it is,
/// quick actions, details, and everything shared in it by kind.
class ChatProfileScreen extends ConsumerStatefulWidget {
  const ChatProfileScreen({super.key, required this.chatId, this.self = false});
  final int chatId;

  /// The account's own profile ([chatId] is its Saved Messages).
  final bool self;

  @override
  ConsumerState<ChatProfileScreen> createState() => _ChatProfileScreenState();
}

enum _Tab {
  media('Media', Icons.photo_outlined),
  files('Files', Icons.description_outlined),
  links('Links', Icons.link_rounded),
  music('Music', Icons.music_note_outlined),
  voice('Voice', Icons.mic_none_rounded);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;

  td.SearchMessagesFilter get filter => switch (this) {
    media => const td.SearchMessagesFilterPhotoAndVideo(),
    files => const td.SearchMessagesFilterDocument(),
    links => const td.SearchMessagesFilterUrl(),
    music => const td.SearchMessagesFilterAudio(),
    voice => const td.SearchMessagesFilterVoiceNote(),
  };
}

class _ChatProfileScreenState extends ConsumerState<ChatProfileScreen> {
  td.UserFullInfo? _user;
  td.SupergroupFullInfo? _supergroup;
  td.BasicGroupFullInfo? _basic;
  _Tab _tab = _Tab.media;
  final Map<_Tab, List<td.Message>> _shared = {};
  final Map<_Tab, int> _totals = {};
  final Set<_Tab> _loading = {};
  final Set<_Tab> _ended = {};

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadShared(_Tab.media);
  }

  ChatInfo? get _chat => ref.read(telegramStoreProvider).chat(widget.chatId);

  Future<void> _loadInfo() async {
    final client = ref.read(telegramClientProvider);
    final c = _chat;
    if (c == null) return;
    try {
      switch (c.type) {
        case td.ChatTypePrivate(:final userId):
          final full = await client.send<td.UserFullInfo>(
            td.GetUserFullInfo(userId: userId),
            limited: true,
          );
          if (full.personalChatId != 0 &&
              ref.read(telegramStoreProvider).chat(full.personalChatId) ==
                  null) {
            await client.send<td.Chat>(
              td.GetChat(chatId: full.personalChatId),
              limited: true,
            );
          }
          if (mounted) setState(() => _user = full);
        case td.ChatTypeSupergroup(:final supergroupId):
          final full = await client.send<td.SupergroupFullInfo>(
            td.GetSupergroupFullInfo(supergroupId: supergroupId),
            limited: true,
          );
          for (final id in [full.linkedChatId, full.directMessagesChatId]) {
            if (id != 0 && ref.read(telegramStoreProvider).chat(id) == null) {
              await client.send<td.Chat>(td.GetChat(chatId: id), limited: true);
            }
          }
          if (mounted) setState(() => _supergroup = full);
        case td.ChatTypeBasicGroup(:final basicGroupId):
          final full = await client.send<td.BasicGroupFullInfo>(
            td.GetBasicGroupFullInfo(basicGroupId: basicGroupId),
            limited: true,
          );
          if (mounted) setState(() => _basic = full);
        default:
          break;
      }
    } catch (e) {
      debugPrint('[Profile] $e');
    }
  }

  Future<void> _loadShared(_Tab tab) async {
    if (_loading.contains(tab) || _ended.contains(tab)) return;
    setState(() => _loading.add(tab));
    try {
      final list = _shared[tab] ?? [];
      final r = await ref
          .read(telegramClientProvider)
          .send<td.FoundChatMessages>(
            td.SearchChatMessages(
              chatId: widget.chatId,
              query: '',
              fromMessageId: list.isEmpty ? 0 : list.last.id,
              offset: 0,
              limit: 40,
              filter: tab.filter,
              topicId: null,
            ),
            limited: true,
          );
      _totals[tab] = r.totalCount;
      final fresh = r.messages
          .where((m) => list.every((x) => x.id != m.id))
          .toList();
      _shared[tab] = [...list, ...fresh];
      if (fresh.isEmpty || r.nextFromMessageId == 0) _ended.add(tab);
    } catch (e) {
      _ended.add(tab);
    }
    if (mounted) setState(() => _loading.remove(tab));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final c = store.chat(widget.chatId);
    if (c == null) {
      return Scaffold(
        body: Center(
          child: widget.self
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Chat not found'),
        ),
      );
    }
    final kind = store.kindOf(c);
    final self = widget.self && kind == ChatKind.saved;
    final me = store.me;
    final username = store.chatUsername(c);
    final user = c.type is td.ChatTypePrivate
        ? store.users[(c.type as td.ChatTypePrivate).userId]
        : null;
    final members =
        _supergroup?.memberCount ??
        _basic?.members.length ??
        store.memberCount(c);

    final subtitle = switch (kind) {
      ChatKind.channel =>
        username != null ? 'public channel' : 'private channel',
      ChatKind.group =>
        '${members == null ? '' : '${NumberFormat.decimalPattern().format(members)} members · '}${username != null ? 'public group' : 'group'}',
      ChatKind.bot => 'bot',
      ChatKind.saved => self ? 'online' : 'your cloud storage',
      _ => switch (user?.status) {
        td.UserStatusOnline() => 'online',
        td.UserStatusRecently() => 'last seen recently',
        td.UserStatusOffline(:final wasOnline) =>
          'last seen ${shortTime(wasOnline)}',
        td.UserStatusLastWeek() => 'last seen within a week',
        td.UserStatusLastMonth() => 'last seen within a month',
        _ => 'last seen a long time ago',
      },
    };
    final about =
        _user?.bio?.text ??
        _supergroup?.description ??
        _basic?.description ??
        '';
    // Group/channel descriptions are plain strings in TDLib while user bios
    // preserve entities. Feed both through the same formatter so URLs and
    // @mentions behave like Telegram's own profile screen.
    final aboutFormatted =
        _user?.bio ??
        (about.isEmpty
            ? null
            : td.FormattedText(text: about, entities: const []));
    final link = username != null
        ? 't.me/$username'
        : _supergroup?.inviteLink?.inviteLink ?? _basic?.inviteLink?.inviteLink;
    final personal = _user != null && _user!.personalChatId != 0
        ? store.chat(_user!.personalChatId)
        : null;
    final linked = _supergroup != null && _supergroup!.linkedChatId != 0
        ? store.chat(_supergroup!.linkedChatId)
        : null;
    // Channel subscribers are visible to admins only.
    final canSeeMembers =
        kind == ChatKind.group ||
        (kind == ChatKind.channel && store.isAdmin(c));
    void openMembers(String filter) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MembersScreen(chatId: c.id, initialFilter: filter),
      ),
    );

    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(Space.l, top + 64, Space.l, Space.x4),
            children: [
              Center(
                child: GestureDetector(
                  onTap: () => _openPhoto(c),
                  child: self && me != null
                      ? TgAvatar(
                          userId: me.id,
                          title: '${me.firstName} ${me.lastName}',
                          size: 110,
                        )
                      : kind == ChatKind.saved
                      ? const SavedAvatar(size: 110)
                      : TgAvatar(chatId: c.id, title: c.title, size: 110),
                ),
              ),
              const SizedBox(height: Space.l),
              Text(
                self && me != null
                    ? '${me.firstName} ${me.lastName}'.trim()
                    : kind == ChatKind.saved
                    ? 'Saved Messages'
                    : c.title,
                textAlign: TextAlign.center,
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: subtitle == 'online'
                      ? AppColors.accent
                      : AppColors.text2,
                ),
              ),
              const SizedBox(height: Space.xl),
              _ActionGrid(
                children: [
                  if (self) ...[
                    _Action(
                      icon: Icons.bookmark_outline_rounded,
                      label: 'Saved',
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatViewScreen(chatId: c.id),
                        ),
                      ),
                    ),
                    _Action(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                    _Action(
                      icon: Icons.block_rounded,
                      label: 'Blocked',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BlockedScreen(),
                        ),
                      ),
                    ),
                  ] else ...[
                    _Action(
                      icon: kind == ChatKind.channel
                          ? Icons.forum_outlined
                          : Icons.chat_bubble_outline_rounded,
                      label: kind == ChatKind.channel ? 'Open' : 'Message',
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatViewScreen(chatId: c.id),
                        ),
                      ),
                    ),
                    _Action(
                      icon: c.isMuted
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_none_rounded,
                      label: c.isMuted ? 'Unmute' : 'Mute',
                      onTap: () =>
                          setChatMuted(ref, c, !c.isMuted, context: context),
                    ),
                    // A channel's direct messages live in a separate group
                    // its admins read, one conversation per sender.
                    if (kind == ChatKind.channel &&
                        store.isAdmin(c) &&
                        (_supergroup?.directMessagesChatId ?? 0) != 0)
                      _Action(
                        icon: Icons.forum_outlined,
                        label: 'DM',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChatViewScreen(
                              chatId: _supergroup!.directMessagesChatId,
                            ),
                          ),
                        ),
                      ),
                    if ((kind == ChatKind.group || kind == ChatKind.channel) &&
                        store.isAdmin(c))
                      _Action(
                        icon: Icons.query_stats_rounded,
                        label: 'Statistics',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AnalyticsScreen(chatId: c.id),
                          ),
                        ),
                      ),
                    _Action(
                      icon: Icons.manage_search_rounded,
                      label: 'Search',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SearchScreen(
                            chatId: c.id,
                            initialType: 'photos_and_videos',
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (link != null)
                    _Action(
                      icon: Icons.ios_share_rounded,
                      label: 'Copy link',
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: link.startsWith('http')
                                ? link
                                : 'https://$link',
                          ),
                        );
                        showSnack(context, 'Link copied');
                      },
                    ),
                ],
              ),
              if (about.isNotEmpty ||
                  link != null ||
                  (user != null && user.phoneNumber.isNotEmpty)) ...[
                const SizedBox(height: Space.l),
                _Card(
                  children: [
                    if (user != null && user.phoneNumber.isNotEmpty)
                      _InfoRow(value: '+${user.phoneNumber}', label: 'Mobile'),
                    if (about.isNotEmpty)
                      _InfoRow(
                        value: about,
                        label: kind == ChatKind.private || kind == ChatKind.bot
                            ? 'Bio'
                            : 'Description',
                        rich: aboutFormatted == null
                            ? null
                            : formattedSpan(aboutFormatted, selectable: true),
                      ),
                    if (link != null)
                      _InfoRow(
                        value: username != null ? '@$username' : link,
                        label: username != null
                            ? (kind == ChatKind.private ? 'Username' : 'Link')
                            : 'Invite link',
                        trailing: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: AppColors.text3,
                        ),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: link.startsWith('http')
                                  ? link
                                  : 'https://$link',
                            ),
                          );
                          showSnack(context, 'Copied');
                        },
                      ),
                  ],
                ),
              ],
              for (final (label, other) in [
                ('Channel', personal),
                // A channel links to its discussion group, and the group back.
                (kind == ChatKind.channel ? 'Discussion group' : 'Channel', linked),
              ])
                if (other != null) ...[
                  const SizedBox(height: Space.m),
                  _Card(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(Radii.xl),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChatViewScreen(chatId: other.id),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(Space.l),
                          child: Row(
                            children: [
                              TgAvatar(
                                chatId: other.id,
                                title: other.title,
                                size: 48,
                              ),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          label,
                                          style: TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (store.memberCount(other)
                                            case final n? when n > 0) ...[
                                          const SizedBox(width: Space.s),
                                          Text(
                                            '${NumberFormat.compact().format(n)} ${store.kindOf(other) == ChatKind.channel ? 'subscribers' : 'members'}',
                                            style: context.text.labelSmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      other.title,
                                      style: context.text.titleSmall,
                                    ),
                                    if (other.lastMessage != null)
                                      Text(
                                        () {
                                          final g = gistOf(
                                            other.lastMessage!.content,
                                          );
                                          return (g.text.isNotEmpty
                                                  ? g.text
                                                  : (g.detail ?? g.kind))
                                              .replaceAll('\n', ' ');
                                        }(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              if (_supergroup != null ||
                  (_user?.groupInCommonCount ?? 0) > 0 ||
                  _basic != null) ...[
                const SizedBox(height: Space.m),
                _Card(
                  children: [
                    if (members != null && members > 0)
                      _StatRow(
                        icon: Icons.people_outline_rounded,
                        label: kind == ChatKind.channel
                            ? 'Subscribers'
                            : 'Members',
                        value: NumberFormat.decimalPattern().format(members),
                        onTap: canSeeMembers
                            ? () => openMembers('recent')
                            : null,
                      ),
                    if ((_supergroup?.administratorCount ?? 0) > 0)
                      _StatRow(
                        icon: Icons.shield_outlined,
                        label: 'Administrators',
                        value: '${_supergroup!.administratorCount}',
                        onTap: canSeeMembers
                            ? () => openMembers('admins')
                            : null,
                      ),
                    if ((_supergroup?.bannedCount ?? 0) > 0)
                      _StatRow(
                        icon: Icons.person_off_outlined,
                        label: 'Removed users',
                        value: '${_supergroup!.bannedCount}',
                        onTap: store.isAdmin(c)
                            ? () => openMembers('banned')
                            : null,
                      ),
                    if ((_supergroup?.restrictedCount ?? 0) > 0)
                      _StatRow(
                        icon: Icons.block_outlined,
                        label: 'Restricted',
                        value: '${_supergroup!.restrictedCount}',
                        onTap: store.isAdmin(c)
                            ? () => openMembers('restricted')
                            : null,
                      ),
                    if ((_user?.groupInCommonCount ?? 0) > 0)
                      _StatRow(
                        icon: Icons.groups_outlined,
                        label: 'Groups in common',
                        value: '${_user!.groupInCommonCount}',
                      ),
                    _StatRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      value: c.isMuted ? 'Muted' : 'On',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.xl),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in _Tab.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: Icon(
                            t.icon,
                            size: 16,
                            color: _tab == t
                                ? AppColors.accent
                                : AppColors.text3,
                          ),
                          label: Text(
                            _totals[t] == null
                                ? t.label
                                : '${t.label} ${_totals[t]}',
                          ),
                          selected: _tab == t,
                          onSelected: (_) {
                            setState(() => _tab = t);
                            _loadShared(t);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.m),
              _SharedSection(
                tab: _tab,
                messages: _shared[_tab] ?? const [],
                loading: _loading.contains(_tab),
                ended: _ended.contains(_tab),
                chatTitle: c.title,
                onMore: () => _loadShared(_tab),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.m,
                  Space.s,
                  Space.m,
                  0,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GlassIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        GlassIconButton(
                          icon: Icons.auto_awesome_outlined,
                          tooltip: 'Ask AI',
                          onTap: () => askAiAbout(context, ref, c),
                        ),
                        if (link != null) const SizedBox(width: Space.s),
                        if (link != null)
                          GlassIconButton(
                            icon: Icons.open_in_new_rounded,
                            tooltip: 'Open in Telegram',
                            onTap: () => launchUrl(
                              Uri.parse(
                                link.startsWith('http')
                                    ? link
                                    : 'https://$link',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                      ],
                    ),
                    const AudioMiniBar(margin: EdgeInsets.only(top: Space.s)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPhoto(ChatInfo c) async {
    final big = c.photo?.big;
    if (big == null) return;
    final path = await ref.read(fileLoaderProvider).download(big, priority: 24);
    if (path == null || !mounted) return;
    openFullscreenFile(context, path, title: c.title);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Column(
              children: [
                Icon(icon, size: 22, color: AppColors.text),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.xl),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.value,
    required this.label,
    this.rich,
    this.trailing,
    this.onTap,
  });
  final String value;
  final String label;
  final TextSpan? rich;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text.rich lets the recognizers in a bio's URL / @mention
                // spans receive the tap. A selectable paragraph consumes
                // that gesture before the link can open.
                rich != null
                    ? Text.rich(rich!, style: context.text.bodyLarge)
                    : SelectableText(value, style: context.text.bodyLarge),
                const SizedBox(height: 2),
                Text(label, style: context.text.bodySmall),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;

  /// Opens the list behind the number, when there is one to see.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        Space.l,
        13,
        onTap == null ? Space.l : Space.s,
        13,
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.text2),
          const SizedBox(width: Space.l),
          Expanded(child: Text(label, style: context.text.bodyLarge)),
          Text(
            value,
            style: context.text.bodyLarge?.copyWith(
              color: AppColors.accent,
              fontFeatures: tabularFigures,
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ],
      ),
    ),
  );
}

/// The profile's buttons, four to a row so they never crowd.
class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.children});
  final List<Widget> children;
  static const _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final rows = (children.length / _perRow).ceil();
    // Rows share one width per button, so a short last row lines up.
    final perRow = children.length <= _perRow ? children.length : _perRow;
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : Space.s),
            child: Row(
              children: [
                ...children.skip(r * _perRow).take(_perRow),
                for (
                  var pad = children.skip(r * _perRow).take(_perRow).length;
                  pad < perRow;
                  pad++
                )
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _SharedSection extends ConsumerWidget {
  const _SharedSection({
    required this.tab,
    required this.messages,
    required this.loading,
    required this.ended,
    required this.chatTitle,
    required this.onMore,
  });

  final _Tab tab;
  final List<td.Message> messages;
  final bool loading;
  final bool ended;
  final String chatTitle;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(telegramStoreProvider);
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Center(
          child: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Nothing shared here yet', style: context.text.bodySmall),
        ),
      );
    }
    final more = ended
        ? const SizedBox.shrink()
        : Center(
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(Space.l),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(onPressed: onMore, child: const Text('Load more')),
          );
    if (tab == _Tab.media) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.l),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: messages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (_, i) =>
                  _GridTile(message: messages[i], chatTitle: chatTitle),
            ),
          ),
          more,
        ],
      );
    }
    final playlist = [for (final m in messages.reversed) ?Track.of(m, store)];
    return Column(
      children: [
        for (final m in messages)
          _SharedRow(
            tab: tab,
            message: m,
            chatTitle: chatTitle,
            playlist: playlist,
          ),
        more,
      ],
    );
  }
}

class _GridTile extends ConsumerStatefulWidget {
  const _GridTile({required this.message, required this.chatTitle});
  final td.Message message;
  final String chatTitle;

  @override
  ConsumerState<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends ConsumerState<_GridTile> {
  String? _path;

  @override
  void initState() {
    super.initState();
    final file = switch (widget.message.content) {
      td.MessagePhoto(:final photo) => pickPhotoSize(
        photo.sizes,
        minWidth: 240,
      )?.photo,
      final c => previewFileOf(c),
    };
    if (file != null) {
      final loader = ref.read(fileLoaderProvider);
      _path = loader.cachedPath(file);
      if (_path == null) {
        loader.download(file, priority: 2).then((p) {
          if (mounted && p != null) setState(() => _path = p);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.message.content;
    final mini = switch (c) {
      td.MessagePhoto(:final photo) => photo.minithumbnail,
      td.MessageVideo(:final video) => video.minithumbnail,
      _ => null,
    };
    return GestureDetector(
      onTap: () =>
          showPost(context, snapshotOf(widget.message, widget.chatTitle, null)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_path != null)
            Image.file(File(_path!), fit: BoxFit.cover, gaplessPlayback: true)
          else if (mini != null)
            Image.memory(base64Decode(mini.data), fit: BoxFit.cover)
          else
            Container(color: AppColors.surface3),
          if (c case td.MessageVideo(:final video))
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    Text(
                      formatDuration(video.duration),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedRow extends ConsumerWidget {
  const _SharedRow({
    required this.tab,
    required this.message,
    required this.chatTitle,
    required this.playlist,
  });
  final _Tab tab;
  final td.Message message;
  final String chatTitle;
  final List<Track> playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(telegramStoreProvider);
    final m = message;
    final g = gistOf(m.content);
    final date = shortTime(m.date);
    if (tab == _Tab.music || tab == _Tab.voice) {
      final audio = ref.watch(audioCenterProvider);
      final t = Track.of(m, store);
      final current = audio.isCurrent(m.chatId, m.id);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: GestureDetector(
          onTap: t == null ? null : () => audio.play(t, playlist: playlist),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.accent,
            child: Icon(
              current && audio.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: AppColors.bg,
            ),
          ),
        ),
        title: Text(
          t?.title ?? g.kind,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            t?.subtitle ?? '',
            formatDuration(t?.seconds ?? 0),
            date,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: context.text.bodySmall,
        ),
        onTap: t == null ? null : () => audio.play(t, playlist: playlist),
        onLongPress: () {
          final track = PlaylistTrack.fromMessage(m, store, ref.read(activeAccountIdProvider));
          if (track != null) showAddToPlaylist(context, ref, [track]);
        },
        trailing: IconButton(
          tooltip: 'Add to playlist',
          icon: Icon(Icons.playlist_add_rounded, color: AppColors.text3),
          onPressed: () {
            final track = PlaylistTrack.fromMessage(m, store, ref.read(activeAccountIdProvider));
            if (track != null) showAddToPlaylist(context, ref, [track]);
          },
        ),
      );
    }
    if (tab == _Tab.links) {
      final url = _firstUrl(g.formatted);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: lead(Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(Radii.m),
          ),
          child: Icon(Icons.link_rounded, color: AppColors.accent),
        )),
        title: Text(
          url ?? g.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.accent),
        ),
        subtitle: Text(
          g.text.replaceAll('\n', ' '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall,
        ),
        onTap: url == null
            ? () => showPost(context, snapshotOf(m, chatTitle, null))
            : () => launchUrl(
                Uri.parse(url.startsWith('http') ? url : 'https://$url'),
                mode: LaunchMode.externalApplication,
              ),
        onLongPress: () => showPost(context, snapshotOf(m, chatTitle, null)),
      );
    }
    final size = m.content is td.MessageDocument
        ? (m.content as td.MessageDocument).document.document.size
        : 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: lead(Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          borderRadius: BorderRadius.circular(Radii.m),
        ),
        child: Icon(kindIcon(g.kind), color: AppColors.accent),
      )),
      title: Text(
        g.detail ?? g.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [if (size > 0) formatBytes(size), date].join(' · '),
        style: context.text.bodySmall,
      ),
      onTap: () => showPost(context, snapshotOf(m, chatTitle, null)),
    );
  }

  static String? _firstUrl(td.FormattedText? f) {
    if (f == null) return null;
    for (final e in f.entities) {
      switch (e.type) {
        case td.TextEntityTypeTextUrl(:final url):
          return url;
        case td.TextEntityTypeUrl():
          return f.text.substring(e.offset, e.offset + e.length);
        default:
          break;
      }
    }
    return null;
  }
}
