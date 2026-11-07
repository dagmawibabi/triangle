import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'accounts.dart';
import 'telegram_client.dart';

/// Shares TDLib's open-chat lifecycle between screens and background watches.
///
/// TDLib only supplies several live updates (including group and channel chat
/// actions) for chats that are open. An owner can safely acquire a chat without
/// closing it while another feature is still relying on those updates.
class OpenChats {
  OpenChats(this._client);

  final TelegramClient _client;
  final Map<int, Set<Object>> _owners = {};

  Future<void> acquire(int chatId, Object owner) async {
    final owners = _owners.putIfAbsent(chatId, () => <Object>{});
    if (!owners.add(owner) || owners.length != 1) return;
    try {
      await _client.send<td.Ok>(td.OpenChat(chatId: chatId), limited: true);
    } catch (_) {
      owners.remove(owner);
      if (owners.isEmpty) _owners.remove(chatId);
      rethrow;
    }
  }

  Future<void> release(int chatId, Object owner) async {
    final owners = _owners[chatId];
    if (owners == null || !owners.remove(owner) || owners.isNotEmpty) return;
    _owners.remove(chatId);
    await _client.send<td.Ok>(td.CloseChat(chatId: chatId));
  }

  void releaseAll(Object owner) {
    for (final chatId
        in _owners.entries
            .where((entry) => entry.value.contains(owner))
            .map((entry) => entry.key)
            .toList()) {
      unawaited(release(chatId, owner));
    }
  }
}

/// Each account's open chats: a chat is opened in the account that wants
/// its live updates.
final openChatsFamily = Provider.family<OpenChats, String>((ref, accountId) {
  return OpenChats(ref.watch(telegramClientFamily(accountId)));
});

/// The active account's open chats.
final openChatsProvider = Provider<OpenChats>((ref) {
  return ref.watch(openChatsFamily(ref.watch(activeAccountIdProvider)));
});
