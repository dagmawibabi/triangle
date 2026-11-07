import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../app/theme.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/presentation/chat_view_screen.dart';

/// Which account a chat or post belongs to, for links opened from the
/// assistant, briefs, watches and the canvas.
///
/// Chat ids are the same in every account, but an account only reaches the
/// chats it is in, and message ids in private chats and small groups are
/// each account's own (only supergroups and channels share them). So a link
/// is opened in the account it came from when that is known, else the one
/// on screen if it can, else another account that can.

/// [id] when it names a signed-in account, else null.
String? signedInAccount(AccountsState s, String? id) =>
    id != null && s.byId(id)?.signedIn == true ? id : null;

bool _knows(TelegramStore store, int chatId) => (store.chat(chatId)?.title ?? '').isNotEmpty;

/// The account to open [chatId] in: [hint] (where the link came from) when
/// signed in, the one on screen when it has the chat, else the first other
/// account that has it. With one account, always that one.
String accountForChat(ProviderContainer c, int chatId, {String? hint}) {
  final s = c.read(accountsProvider);
  if (!s.hasSeveral) return s.activeId;
  final from = signedInAccount(s, hint);
  if (from != null) return from;
  if (_knows(c.read(telegramStoreFamily(s.activeId)), chatId)) return s.activeId;
  for (final a in s.signedIn) {
    if (_knows(c.read(telegramStoreFamily(a.id)), chatId)) return a.id;
  }
  return s.activeId;
}

/// Finds the account that has message [messageId] of [chatId] and loads it
/// from there: [hint] first, then the account on screen, then the others
/// that have the chat, then any other. Returns the account and the message,
/// or the account to show the saved copy in and the last error.
Future<({String account, td.Message? message, Object? error})> findPost(
  ProviderContainer c,
  int chatId,
  int messageId, {
  String? hint,
}) async {
  final s = c.read(accountsProvider);
  final order = <String>[];
  void add(String? id) {
    if (id != null && !order.contains(id)) order.add(id);
  }

  add(signedInAccount(s, hint));
  // With one account (or none signed in yet) the account on screen is all
  // there is.
  if (!s.hasSeveral) {
    add(s.activeId);
  } else {
    // Ones that have the chat, the one on screen first.
    for (final a in [s.active, ...s.signedIn]) {
      if (a.signedIn && _knows(c.read(telegramStoreFamily(a.id)), chatId)) add(a.id);
    }
    add(s.activeId);
    for (final a in s.signedIn) {
      add(a.id);
    }
  }
  Object? error;
  for (final id in order) {
    try {
      final m = await c
          .read(telegramClientFamily(id))
          .send<td.Message>(td.GetMessage(chatId: chatId, messageId: messageId), limited: true);
      return (account: id, message: m, error: null);
    } catch (e) {
      error ??= e;
    }
  }
  return (account: order.firstOrNull ?? s.activeId, message: null, error: error);
}

/// Makes [account] the one on screen (saying so) before opening something
/// of it. Returns whether it switched.
bool switchToOpen(BuildContext context, ProviderContainer c, String account) {
  final s = c.read(accountsProvider);
  if (account == s.activeId || s.byId(account)?.signedIn != true) return false;
  c.read(accountsProvider.notifier).switchTo(account);
  showSnack(context, 'Switched to ${s.byId(account)!.label}', icon: Icons.swap_horiz_rounded);
  return true;
}

/// Opens [chatId] in the account that has it (see [accountForChat]),
/// switching to that account first.
Future<void> openChatInAccount(BuildContext context, int chatId, {String? hint}) async {
  final c = ProviderScope.containerOf(context, listen: false);
  final account = accountForChat(c, chatId, hint: hint);
  final nav = Navigator.of(context);
  switchToOpen(context, c, account);
  await nav.push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: chatId)));
}
