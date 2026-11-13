import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/calls_screen.dart';
import '../../telegram/presentation/chat_list_screen.dart';
import '../../telegram/presentation/chat_profile_screen.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../account/account_switcher.dart';
import '../../settings/data/settings.dart';

import 'package:handy_tdlib/api.dart' as td;

import '../../telegram/presentation/tg_avatar.dart';
import '../data/chat_controller.dart';
import '../domain/chat_models.dart';
import 'generated_files_screen.dart';
import 'chat_search_sheet.dart';
import 'widgets/chat_sheets.dart';
import '../../brief/brief_screen.dart';
import '../../brief/brief_store.dart';
import '../../canvas/canvas_store.dart';
import '../../telegram/presentation/content_canvas_screen.dart';
import '../../web/browser_screen.dart';
import '../../pc/pc_screen.dart';
import '../../auth/data/auth_controller.dart';
import '../../search/everywhere_search_screen.dart';
import '../../settings/presentation/tools_screen.dart' show AppsWebScreen;

/// Past conversations, grouped by when they were last used.
class HistoryDrawer extends ConsumerStatefulWidget {
  const HistoryDrawer({super.key, required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends ConsumerState<HistoryDrawer> {
  static String _bucket(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'Previous 7 days';
    if (diff < 30) return 'Previous 30 days';
    return 'Older';
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary c,
  ) => showRenameSheet(context, id: c.id, title: c.title);

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary c,
  ) async {
    final conversation = await ref.read(chatControllerProvider.notifier).conversationById(c.id);
    if (conversation != null && context.mounted) await showExportSheet(context, conversation);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: const Text(
          'It is removed from this app only. Nothing in Telegram changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true)
      await ref.read(chatControllerProvider.notifier).delete(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final store = ref.watch(telegramStoreProvider);
    final me = store.me;
    final controller = ref.read(chatControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final telegram = ref.watch(telegramConnectedProvider);
    final prefs = ref.read(settingsProvider.notifier);
    // Closes the drawer and opens a page.
    void go(WidgetBuilder page) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute<void>(builder: page));
    }

    // Pinned chats first, then the rest by when they were used; archived
    // ones only under Archived at the end.
    final groups = <String, List<ConversationSummary>>{
      if (state.history.any((c) => c.pinned && !c.archived))
        'Pinned': [for (final c in state.history) if (c.pinned && !c.archived) c],
    };
    for (final c in state.history) {
      if (c.pinned || c.archived) continue;
      groups.putIfAbsent(_bucket(c.updatedAt), () => []).add(c);
    }
    final archived = [for (final c in state.history) if (c.archived) c];

    return Drawer(
      width: 300,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.l,
                Space.m,
                Space.s,
              ),
              child: Row(
                children: [
                  const BrandLockup(markSize: 26),
                  const Spacer(),
                  IconButton(
                    tooltip: 'New chat',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () {
                      controller.newChat();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                children: [
                  if (!telegram)
                    _DrawerActionTile(
                      icon: Icons.send_rounded,
                      title: 'Connect Telegram',
                      subtitle: 'Your chats, channels, briefs and watches',
                      onTap: () => go((_) => const AppsWebScreen()),
                    ),
                  if (telegram && settings.drawerChats)
                    _DrawerSection(
                      title: 'Chats',
                      open: settings.drawerChatsOpen,
                      onOpen: prefs.setDrawerChatsOpen,
                      children: [
                        for (final section in BrowseSection.values)
                          if (settings.drawerShows('chats.${section.name}'))
                          _BrowseTile(
                            section: section,
                            count: section == BrowseSection.contacts
                                ? null
                                : chatsIn(store, section).length,
                            unread: section == BrowseSection.contacts
                                ? 0
                                : chatsIn(store, section)
                                      .where((c) => c.hasUnread && !c.isMuted)
                                      .length,
                            onTap: () =>
                                go((_) => ChatListScreen(section: section)),
                          ),
                        if (settings.drawerShows('chats.calls'))
                        InkWell(
                          borderRadius: BorderRadius.circular(Radii.s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.m,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.call_outlined,
                                  size: 20,
                                  color: AppColors.text2,
                                ),
                                const SizedBox(width: Space.m + 2),
                                Expanded(
                                  child: Text(
                                    'Calls',
                                    style: context.text.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => go((_) => const CallsScreen()),
                        ),
                      ],
                    ),
                  if (telegram &&
                      settings.drawerFolders &&
                      store.folders.isNotEmpty)
                    _DrawerSection(
                      title: 'Folders',
                      open: settings.drawerFoldersOpen,
                      onOpen: prefs.setDrawerFoldersOpen,
                      children: [
                        for (final f in store.folders)
                          _FolderTile(
                            folder: f,
                            count: store.folderChats[f.id]?.length,
                            onTap: () => go((_) => ChatListScreen(folder: f)),
                          ),
                      ],
                    ),
                  if (settings.drawerTools)
                    _DrawerSection(
                      title: 'Tools',
                      open: settings.drawerToolsOpen,
                      onOpen: prefs.setDrawerToolsOpen,
                      children: [
                        if (settings.drawerShows('tools.files'))
                        _DrawerActionTile(
                          icon: Icons.folder_copy_outlined,
                          title: 'Files',
                          subtitle: telegram
                              ? 'Generated, downloaded, sandbox and Telegram files'
                              : 'Generated, downloaded and sandbox files',
                          onTap: () => go((_) => const GeneratedFilesScreen()),
                        ),
                        if (settings.drawerShows('tools.brief'))
                        _DrawerActionTile(
                          icon: Icons.wb_twilight_rounded,
                          title: 'Brief',
                          subtitle: briefSubtitle(
                            ref.watch(briefStoreProvider).briefs,
                          ),
                          onTap: () => go((_) => const BriefScreen()),
                        ),
                        if (settings.drawerShows('tools.canvas'))
                        _DrawerActionTile(
                          icon: Icons.dashboard_customize_outlined,
                          title: 'Content Canvas',
                          subtitle:
                              '${ref.watch(canvasProvider).folders.length} folders · ${ref.watch(canvasProvider).items.length} saved',
                          onTap: () => go((_) => const ContentCanvasScreen()),
                        ),
                        if (settings.drawerShows('tools.search'))
                        _DrawerActionTile(
                          icon: Icons.manage_search_rounded,
                          title: 'Search',
                          subtitle: telegram
                              ? 'Conversations, canvas, files, email and every Telegram chat'
                              : 'Conversations, canvas, files, email and the web',
                          onTap: () =>
                              go((_) => const EverywhereSearchScreen()),
                        ),
                        if (settings.drawerShows('tools.browser'))
                        _DrawerActionTile(
                          icon: Icons.public_rounded,
                          title: 'Browser',
                          subtitle: 'What the assistant has open on the web',
                          onTap: () {
                            Navigator.pop(context);
                            BrowserScreen.open(context);
                          },
                        ),
                        if (settings.drawerShows('tools.pc'))
                        _DrawerActionTile(
                          icon: Icons.desktop_windows_outlined,
                          title: 'PC screen',
                          subtitle: 'See and use your PC live, through Triangle Companion',
                          onTap: () {
                            Navigator.pop(context);
                            PcScreen.open(context);
                          },
                        ),
                      ],
                    ),
                  if (state.history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Center(
                        child: Text(
                          'No conversations yet',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ),
                  for (final g in groups.entries) ...[
                    // The first heading ("Today", "Pinned"…) carries the
                    // search, on its right.
                    if (g.key == groups.keys.first)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, 0, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                g.key.toUpperCase(),
                                style: context.text.labelSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Search chats',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.search_rounded, size: 20),
                              onPressed: () async {
                                final opened = await ChatSearchSheet.show(context);
                                // A chat was opened from the sheet: close the drawer too.
                                if (opened == true && context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.m,
                          Space.l,
                          Space.m,
                          Space.xs,
                        ),
                        child: Text(
                          g.key.toUpperCase(),
                          style: context.text.labelSmall,
                        ),
                      ),
                    for (final c in g.value)
                      _HistoryTile(
                        summary: c,
                        selected: c.id == state.conversation.id,
                        running: controller.runningIds.contains(c.id),
                        onTap: () {
                          controller.open(c.id);
                          Navigator.pop(context);
                        },
                        onRename: () => _rename(context, ref, c),
                        onExport: () => _export(context, ref, c),
                        onPin: () => controller.pin(c.id, !c.pinned),
                        onArchive: () => controller.archive(c.id, !c.archived),
                        onDelete: () => _delete(context, ref, c),
                      ),
                  ],
                  if (archived.isNotEmpty)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: Space.m),
                        childrenPadding: EdgeInsets.zero,
                        leading: lead(Icon(Icons.archive_outlined, size: 20, color: AppColors.text2)),
                        title: Text('ARCHIVED · ${archived.length}', style: context.text.labelSmall),
                        children: [
                          for (final c in archived)
                            _HistoryTile(
                              summary: c,
                              selected: c.id == state.conversation.id,
                              running: controller.runningIds.contains(c.id),
                              onTap: () {
                                controller.open(c.id);
                                Navigator.pop(context);
                              },
                              onRename: () => _rename(context, ref, c),
                              onExport: () => _export(context, ref, c),
                              onPin: () => controller.pin(c.id, !c.pinned),
                              onArchive: () => controller.archive(c.id, !c.archived),
                              onDelete: () => _delete(context, ref, c),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              leading: me == null
                  ? (telegram
                        ? CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.surface3,
                          )
                        : const BrandMark(size: 32))
                  : TgAvatar(
                      userId: me.id,
                      title: '${me.firstName} ${me.lastName}',
                      size: 34,
                    ),
              title: Text(
                me == null
                    ? (telegram ? 'Telegram' : 'Triangle')
                    : '${me.firstName} ${me.lastName}'.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                !telegram
                    ? 'Telegram not connected'
                    : store.chatsLoaded
                    ? '${store.chats.values.where((c) => c.isListed).length} chats'
                    : 'Loading chats…',
                style: context.text.bodySmall,
              ),
              trailing: IconButton(
                tooltip: 'Settings',
                icon: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: AppColors.text2,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onOpenSettings();
                },
              ),
              // Long press: switch to another account or add one.
              onLongPress: telegram || ref.read(accountsProvider).hasSeveral
                  ? () => showAccountsSheet(context, ref)
                  : null,
              onTap: me == null
                  ? (telegram ? null : () => go((_) => const AppsWebScreen()))
                  : () async {
                      final nav = Navigator.of(context);
                      nav.pop();
                      // Your profile lives on your Saved Messages chat; this
                      // finds it (it creates nothing visible).
                      try {
                        final chat = await ref
                            .read(telegramClientProvider)
                            .send<td.Chat>(
                              td.CreatePrivateChat(userId: me.id, force: false),
                              limited: true,
                            );
                        nav.push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChatProfileScreen(chatId: chat.id, self: true),
                          ),
                        );
                      } catch (_) {
                        widget.onOpenSettings();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible drawer section whose open state is remembered.
class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.title,
    required this.open,
    required this.onOpen,
    required this.children,
  });
  final String title;
  final bool open;
  final ValueChanged<bool> onOpen;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    // Keyed by state so a change from Settings rebuilds it open or closed.
    key: ValueKey('drawer-$title-$open'),
    initiallyExpanded: open,
    onExpansionChanged: onOpen,
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(title, style: context.text.titleSmall),
    trailing: Icon(
      open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
      color: AppColors.text3,
    ),
    children: children,
  );
}

class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Radii.s),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.s,
      ),
      child: Row(
        children: [
          ...leadRow(Icon(icon, size: 20, color: AppColors.text2), Space.m + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.bodyMedium),
                Text(subtitle, style: context.text.labelSmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ],
      ),
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.summary,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onExport,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    this.running = false,
  });

  final ConversationSummary summary;
  final bool selected;

  /// The assistant is still working in it (another chat is on screen).
  final bool running;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surface3 : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: Space.m),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summary.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: selected || summary.unread > 0
                        ? AppColors.text
                        : AppColors.text2,
                    fontWeight: summary.unread > 0 ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (summary.pinned && !running && summary.unread == 0)
                Padding(
                  padding: const EdgeInsets.only(left: Space.s),
                  child: Transform.rotate(angle: 0.6, child: Icon(Icons.push_pin_rounded, size: 14, color: AppColors.text3)),
                ),
              if (running)
                const Padding(
                  padding: EdgeInsets.only(left: Space.s),
                  child: SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                )
              else if (summary.unread > 0 && !selected)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.activeAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${summary.unread}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.bg,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: AppColors.text3,
                ),
                onSelected: (v) => switch (v) {
                  'rename' => onRename(),
                  'export' => onExport(),
                  'pin' => onPin(),
                  'archive' => onArchive(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'pin', child: Text(summary.pinned ? 'Unpin' : 'Pin to top')),
                  PopupMenuItem(value: 'archive', child: Text(summary.archived ? 'Unarchive' : 'Archive')),
                  PopupMenuItem(value: 'export', child: Text('Export')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile({
    required this.section,
    required this.count,
    required this.unread,
    required this.onTap,
  });
  final BrowseSection section;
  final int? count;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.s),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 11),
        child: Row(
          children: [
            ...leadRow(Icon(section.icon, size: 20, color: AppColors.text2), Space.m + 2),
            Expanded(
              child: Text(section.title, style: context.text.bodyMedium),
            ),
            if (unread > 0)
              Container(
                margin: const EdgeInsets.only(right: Space.s),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.activeAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$unread',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bg,
                  ),
                ),
              ),
            if (count != null)
              Text(
                '$count',
                style: TextStyle(fontSize: 12.5, color: AppColors.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.count,
    required this.onTap,
  });
  final FolderInfo folder;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.s),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 11),
        child: Row(
          children: [
            ...leadRow(Icon(folderIcon(folder.icon), size: 20, color: AppColors.text2), Space.m + 2),
            Expanded(
              child: Text(
                folder.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium,
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: TextStyle(fontSize: 12.5, color: AppColors.text3),
              ),
          ],
        ),
      ),
    );
  }
}
