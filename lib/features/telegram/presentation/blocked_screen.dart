import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../data/content_filters.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'chat_actions.dart' show confirmAction;
import 'chat_profile_screen.dart';
import 'tg_avatar.dart';

/// Everyone the account has blocked, with unblocking, and blocking someone
/// new from the contacts and recent chats.
class BlockedScreen extends ConsumerStatefulWidget {
  const BlockedScreen({super.key});

  @override
  ConsumerState<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends ConsumerState<BlockedScreen> {
  List<td.MessageSender>? _senders;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(toolRunnerProvider).blocked();
      unawaited(ref.read(blockedSendersProvider.notifier).reload());
      if (mounted) {
        setState(() {
          _senders = r.senders;
          _total = r.total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _blockSomeone() async {
    final store = ref.read(telegramStoreProvider);
    final me = store.me?.id;
    final candidates =
        store.chats.values
            .where((c) => c.type is td.ChatTypePrivate && c.isListed && c.id != me && c.title.isNotEmpty)
            .toList()
          ..sort((a, b) => (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0));
    final picked = await showModalBottomSheet<ChatInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                child: Text('Block someone', style: context.text.titleMedium),
              ),
              for (final c in candidates)
                ListTile(
                  leading: TgAvatar(chatId: c.id, title: c.title, size: 40),
                  title: Text(c.title),
                  subtitle: Text(store.kindOf(c).name, style: context.text.bodySmall),
                  onTap: () => Navigator.pop(sheet, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (!await confirmAction(
      context,
      title: 'Block ${picked.title}?',
      message: 'They won\'t be able to message or call you.',
      action: 'Block',
    )) {
      return;
    }
    try {
      await ref.read(toolRunnerProvider).setBlocked((picked.type as td.ChatTypePrivate).userId, true);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t block: $e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final list = _senders;
    return Scaffold(
      appBar: AppBar(title: Text('Blocked${_total > 0 ? ' · $_total' : ''}')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.block_rounded),
        label: const Text('Block someone'),
        onPressed: _blockSomeone,
      ),
      body: list == null
          ? Center(
              child: _error != null
                  ? Text(_error!, style: context.text.bodySmall)
                  : const CircularProgressIndicator(strokeWidth: 2),
            )
          : list.isEmpty
          ? Center(child: Text('You haven\'t blocked anyone', style: context.text.bodySmall))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final name = store.senderName(s);
                  final (userId, chatId) = switch (s) {
                    td.MessageSenderUser(:final userId) => (userId, userId),
                    td.MessageSenderChat(:final chatId) => (0, chatId),
                  };
                  final user = store.users[userId];
                  final username = user == null ? null : store.username(user.usernames);
                  return ListTile(
                    leading: userId != 0
                        ? TgAvatar(userId: userId, title: name, size: 42)
                        : TgAvatar(chatId: chatId, title: name, size: 42),
                    title: Text(name),
                    subtitle: Text(
                      [
                        if (user?.type is td.UserTypeBot) 'bot' else if (userId != 0) 'user' else 'chat',
                        if (username != null) '@$username',
                        if (user != null && user.phoneNumber.isNotEmpty) '+${user.phoneNumber}',
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(toolRunnerProvider).setBlocked(userId, false);
                          await _load();
                          if (context.mounted) showSnack(context, 'Unblocked $name');
                        } catch (e) {
                          if (context.mounted) showSnack(context, 'Couldn\'t unblock: $e', icon: Icons.error_outline_rounded);
                        }
                      },
                      child: const Text('Unblock'),
                    ),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => ChatProfileScreen(chatId: chatId))),
                  );
                },
              ),
            ),
    );
  }
}
