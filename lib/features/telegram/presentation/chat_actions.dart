import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../chat/data/chat_controller.dart';
import '../data/content_filters.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_background.dart';
import 'chat_profile_screen.dart';
import 'members_screen.dart';
import 'tg_avatar.dart';

/// "Forever" as Telegram's apps mean it: anything over a year.
const muteForever = 0x7fffffff;

/// Mutes or unmutes a chat's notifications, keeping its other settings.
Future<void> setChatMuted(WidgetRef ref, ChatInfo chat, bool muted, {BuildContext? context}) async {
  final client = ref.read(telegramClientProvider);
  try {
    final current = chat.notifications ?? (await client.send<td.Chat>(td.GetChat(chatId: chat.id))).notificationSettings;
    await client.send<td.Ok>(
      td.SetChatNotificationSettings(
        chatId: chat.id,
        notificationSettings: current.copyWith(useDefaultMuteFor: false, muteFor: muted ? muteForever : 0),
      ),
      limited: true,
    );
    if (context != null && context.mounted) {
      showSnack(context, muted ? 'Muted ${chat.title}' : 'Unmuted ${chat.title}', icon: muted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined);
    }
  } catch (e) {
    if (context != null && context.mounted) showSnack(context, 'Couldn\'t change notifications: $e', icon: Icons.error_outline_rounded);
  }
}

/// Moves a chat into the Archive or back out. Nothing is deleted.
Future<void> setChatArchived(WidgetRef ref, ChatInfo chat, bool archived, {BuildContext? context}) async {
  try {
    await ref.read(telegramClientProvider).send<td.Ok>(
      td.AddChatToList(chatId: chat.id, chatList: archived ? const td.ChatListArchive() : const td.ChatListMain()),
      limited: true,
    );
    if (context != null && context.mounted) {
      showSnack(context, archived ? 'Archived ${chat.title}' : 'Moved ${chat.title} out of the Archive', icon: Icons.archive_outlined);
    }
  } catch (e) {
    if (context != null && context.mounted) showSnack(context, 'Could not change the Archive: $e', icon: Icons.error_outline_rounded);
  }
}

/// Starts a new assistant chat about [chat] and returns to it.
void askAiAbout(BuildContext context, WidgetRef ref, ChatInfo chat, {int? threadId, String? threadTitle}) {
  final kind = ref.read(telegramStoreProvider).kindOf(chat);
  final prompt = threadId != null
      ? 'Catch me up on the "$threadTitle" topic in ${chat.title} (chat_id ${chat.id}, topic message_id $threadId).'
      : switch (kind) {
          ChatKind.channel => 'What has ${chat.title} (chat_id ${chat.id}) posted recently? Summarize the highlights.',
          ChatKind.group => 'Catch me up on ${chat.title} (chat_id ${chat.id}): what has been discussed recently?',
          _ => 'Summarize my recent conversation with ${chat.title} (chat_id ${chat.id}).',
        };
  final controller = ref.read(chatControllerProvider.notifier);
  controller.newChat();
  controller.send(prompt);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Asks before something that can't be undone. [danger] colours it red.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// What long-pressing a chat offers: reading state, notifications, pins,
/// the Archive and folders, its profile, members and background, asking
/// the assistant, and (in red, each confirmed) clearing, leaving, deleting
/// and blocking.
Future<void> showChatMenu(BuildContext context, WidgetRef ref, ChatInfo chat) {
  final store = ref.read(telegramStoreProvider);
  final runner = ref.read(toolRunnerProvider);
  final kind = store.kindOf(chat);
  final private = chat.type is td.ChatTypePrivate;
  final userId = switch (chat.type) {
    td.ChatTypePrivate(:final userId) => userId,
    _ => 0,
  };
  final isMe = userId != 0 && userId == store.me?.id;
  final groupish = kind == ChatKind.group || kind == ChatKind.channel;
  final username = store.chatUsername(chat);

  Future<void> run(BuildContext sheet, Future<void> Function() f, String done, {IconData icon = Icons.check_rounded}) async {
    Navigator.pop(sheet);
    try {
      await f();
      if (context.mounted) showSnack(context, done, icon: icon);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Couldn\'t do that: $e', icon: Icons.error_outline_rounded);
    }
  }

  Widget tile(IconData icon, String label, VoidCallback onTap, {bool danger = false, String? subtitle}) => ListTile(
    dense: true,
    leading: lead(Icon(icon, color: danger ? AppColors.danger : AppColors.text2, size: 22)),
    title: Text(label, style: TextStyle(color: danger ? AppColors.danger : AppColors.text, fontSize: 15)),
    subtitle: subtitle == null ? null : Text(subtitle, style: context.text.bodySmall),
    onTap: onTap,
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          ListTile(
            leading: kind == ChatKind.saved
                ? const SavedAvatar(size: 44)
                : TgAvatar(chatId: chat.id, title: chat.title, size: 44),
            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
            subtitle: Text(
              [
                kind.name,
                if (store.memberCount(chat) case final n? when n > 0) '$n members',
                if (store.isCreator(chat)) 'owner' else if (store.isAdmin(chat)) 'admin',
                if (chat.unreadCount > 0) '${chat.unreadCount} unread',
              ].join(' · '),
              style: context.text.bodySmall,
            ),
          ),
          const Divider(),
          if (chat.hasUnread || chat.unreadMentionCount > 0)
            tile(Icons.mark_chat_read_outlined, 'Mark as read', () => run(sheet, () => runner.markRead(chat), 'Marked as read'))
          else
            tile(
              Icons.mark_chat_unread_outlined,
              'Mark as unread',
              () => run(sheet, () => runner.markUnread(chat.id, true), 'Marked as unread'),
            ),
          if (chat.isMuted)
            tile(Icons.notifications_active_outlined, 'Unmute', () {
              Navigator.pop(sheet);
              setChatMuted(ref, chat, false, context: context);
            })
          else
            tile(Icons.notifications_off_outlined, 'Mute…', () async {
              Navigator.pop(sheet);
              final seconds = await showModalBottomSheet<int>(
                context: context,
                showDragHandle: true,
                builder: (c) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (label, s) in const [
                        ('For 1 hour', 3600),
                        ('For 8 hours', 8 * 3600),
                        ('For 2 days', 2 * 86400),
                        ('For a week', 7 * 86400),
                        ('Forever', muteForever),
                      ])
                        ListTile(title: Text(label), onTap: () => Navigator.pop(c, s)),
                    ],
                  ),
                ),
              );
              if (seconds == null || !context.mounted) return;
              await setChatMutedFor(ref, chat, seconds, context: context);
            }),
          tile(
            chat.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            chat.isPinned ? 'Unpin' : 'Pin to top',
            () => run(sheet, () => runner.setPinned(chat, !chat.isPinned), chat.isPinned ? 'Unpinned' : 'Pinned'),
          ),
          if (kind != ChatKind.saved)
            tile(Icons.archive_outlined, chat.inArchive ? 'Move out of the Archive' : 'Archive', () {
              Navigator.pop(sheet);
              setChatArchived(ref, chat, !chat.inArchive, context: context);
            }),
          if (store.folders.isNotEmpty)
            tile(Icons.create_new_folder_outlined, 'Add to folder…', () async {
              Navigator.pop(sheet);
              final folder = await showModalBottomSheet<FolderInfo>(
                context: context,
                showDragHandle: true,
                builder: (c) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in store.folders)
                        ListTile(
                          leading: lead(Icon(
                            (store.folderChats[f.id]?.contains(chat.id) ?? false)
                                ? Icons.check_circle_rounded
                                : Icons.folder_outlined,
                          )),
                          title: Text(f.title),
                          onTap: () => Navigator.pop(c, f),
                        ),
                    ],
                  ),
                ),
              );
              if (folder == null) return;
              final inIt = store.folderChats[folder.id]?.contains(chat.id) ?? false;
              try {
                await runner.setInFolder(chat.id, folder.id, !inIt);
                if (context.mounted) {
                  showSnack(context, inIt ? 'Removed from ${folder.title}' : 'Added to ${folder.title}');
                }
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t change the folder: $e', icon: Icons.error_outline_rounded);
              }
            }),
          const Divider(),
          tile(Icons.person_outline_rounded, private ? 'View profile' : 'Info', () {
            Navigator.pop(sheet);
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: chat.id)));
          }),
          if (groupish && (kind == ChatKind.group || store.isAdmin(chat)))
            tile(Icons.groups_outlined, kind == ChatKind.channel ? 'Subscribers' : 'Members', () {
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MembersScreen(chatId: chat.id)));
            }),
          tile(Icons.wallpaper_outlined, 'Chat background', () {
            Navigator.pop(sheet);
            showBackgroundPicker(context, ref, chat.id);
          }),
          tile(Icons.auto_awesome_outlined, 'Ask AI about this chat', () {
            Navigator.pop(sheet);
            askAiAbout(context, ref, chat);
          }),
          if (username != null)
            tile(Icons.link_rounded, 'Copy link', () {
              Clipboard.setData(ClipboardData(text: 'https://t.me/$username'));
              Navigator.pop(sheet);
              showSnack(context, 'Link copied', icon: Icons.link_rounded);
            }),
          const Divider(),
          tile(Icons.cleaning_services_outlined, 'Clear history', danger: true, () async {
            Navigator.pop(sheet);
            if (!await confirmAction(
              context,
              title: 'Clear ${chat.title}?',
              message: 'Deletes all messages in this chat for you. This can\'t be undone.',
              action: 'Clear',
            )) {
              return;
            }
            try {
              await runner.clearHistory(chat.id);
              if (context.mounted) showSnack(context, 'History cleared');
            } catch (e) {
              if (context.mounted) showSnack(context, 'Couldn\'t clear it: $e', icon: Icons.error_outline_rounded);
            }
          }),
          if (groupish && store.isMember(chat) && !store.isCreator(chat))
            tile(Icons.logout_rounded, kind == ChatKind.channel ? 'Leave channel' : 'Leave group', danger: true, () async {
              Navigator.pop(sheet);
              if (!await confirmAction(
                context,
                title: 'Leave ${chat.title}?',
                message: 'You can rejoin later if it\'s public or you have an invite link.',
                action: 'Leave',
              )) {
                return;
              }
              try {
                await runner.leaveChat(chat.id);
                if (context.mounted) showSnack(context, 'Left ${chat.title}', icon: Icons.logout_rounded);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t leave: $e', icon: Icons.error_outline_rounded);
              }
            }),
          if (private && !isMe && kind != ChatKind.saved)
            tile(Icons.block_rounded, kind == ChatKind.bot ? 'Block bot' : 'Block user', danger: true, () async {
              Navigator.pop(sheet);
              if (!await confirmAction(
                context,
                title: 'Block ${chat.title}?',
                message: 'They won\'t be able to message or call you.',
                action: 'Block',
              )) {
                return;
              }
              try {
                await runner.setBlocked(userId, true);
                await ref.read(blockedSendersProvider.notifier).reload();
                if (context.mounted) showSnack(context, 'Blocked ${chat.title}', icon: Icons.block_rounded);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t block: $e', icon: Icons.error_outline_rounded);
              }
            }),
          if (kind == ChatKind.channel || kind == ChatKind.group)
            if (ref.read(contentFiltersProvider).blockedChats.containsKey(chat.id))
              tile(Icons.check_circle_outline_rounded, 'Unblock ${kind == ChatKind.channel ? 'channel' : 'group'}', () {
                Navigator.pop(sheet);
                ref.read(contentFiltersProvider.notifier).unblockChat(chat.id);
                showSnack(context, 'Unblocked ${chat.title}');
              })
            else
              tile(Icons.block_rounded, 'Block ${kind == ChatKind.channel ? 'channel' : 'group'}', danger: true, () {
                Navigator.pop(sheet);
                ref.read(contentFiltersProvider.notifier).blockChat(chat.id, chat.title);
                showSnack(
                  context,
                  'Blocked ${chat.title}. Posts forwarded from it will be hidden.',
                  icon: Icons.block_rounded,
                );
              }),
          tile(
            Icons.delete_forever_outlined,
            store.isCreator(chat) ? 'Delete for everyone' : 'Delete chat',
            danger: true,
            () async {
              Navigator.pop(sheet);
              if (!await confirmAction(
                context,
                title: 'Delete ${chat.title}?',
                message: store.isCreator(chat)
                    ? 'You own it: this deletes it for all ${store.memberCount(chat) ?? ''} members. This can\'t be undone.'
                    : groupish
                    ? 'Leaves it and removes it from your list.'
                    : 'Deletes the conversation for you and removes it from your list.',
                action: 'Delete',
              )) {
                return;
              }
              try {
                await runner.deleteChat(chat);
                if (context.mounted) showSnack(context, 'Deleted ${chat.title}', icon: Icons.delete_outline_rounded);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t delete: $e', icon: Icons.error_outline_rounded);
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Mutes for a number of seconds ([muteForever] for good).
Future<void> setChatMutedFor(WidgetRef ref, ChatInfo chat, int seconds, {BuildContext? context}) async {
  final client = ref.read(telegramClientProvider);
  try {
    final current = chat.notifications ?? (await client.send<td.Chat>(td.GetChat(chatId: chat.id))).notificationSettings;
    await client.send<td.Ok>(
      td.SetChatNotificationSettings(
        chatId: chat.id,
        notificationSettings: current.copyWith(useDefaultMuteFor: false, muteFor: seconds),
      ),
      limited: true,
    );
    if (context != null && context.mounted) {
      showSnack(context, 'Muted ${chat.title}', icon: Icons.notifications_off_outlined);
    }
  } catch (e) {
    if (context != null && context.mounted) {
      showSnack(context, 'Couldn\'t change notifications: $e', icon: Icons.error_outline_rounded);
    }
  }
}
