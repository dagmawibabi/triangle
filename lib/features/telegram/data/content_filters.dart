import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/telegram/telegram_client.dart';
import 'message_content.dart';
import 'telegram_store.dart';

/// Channels and groups blocked on this phone only (Telegram itself can't
/// block a chat you're in), muted words, and how hidden messages show.
class ContentFilters {
  ContentFilters({
    this.blockedChats = const {},
    this.mutedWords = const [],
    this.labelBlockedAccounts = true,
    this.labelBlockedChats = true,
    this.labelMutedWords = true,
    this.inArchived = false,
  }) : _muted = _pattern(mutedWords);

  /// Chat id → the title it had when it was blocked, for when the chat
  /// isn't loaded.
  final Map<int, String> blockedChats;
  final List<String> mutedWords;

  /// Whether a hidden message leaves a "tap to view" notice (true) or
  /// disappears without a trace (false).
  final bool labelBlockedAccounts;
  final bool labelBlockedChats;
  final bool labelMutedWords;

  /// Whether blocks and muted words also hide messages in archived chats.
  final bool inArchived;

  final RegExp? _muted;

  static RegExp? _pattern(List<String> words) {
    final parts = [
      for (final w in words)
        if (w.trim().isNotEmpty) RegExp.escape(w.trim()),
    ];
    if (parts.isEmpty) return null;
    // Whole words, so "cat" doesn't hide "education"; a phrase or a word
    // with symbols matches where it starts and ends at a word edge.
    return RegExp(
      r'(?<![\p{L}\p{N}_])(?:' + parts.join('|') + r')(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
  }

  /// The muted word [text] contains, if any.
  String? mutedWordIn(String text) {
    if (_muted == null || text.isEmpty) return null;
    final m = _muted.firstMatch(text);
    if (m == null) return null;
    final hit = m.group(0)!.toLowerCase();
    return mutedWords.firstWhere((w) => w.trim().toLowerCase() == hit, orElse: () => m.group(0)!);
  }

  ContentFilters copyWith({
    Map<int, String>? blockedChats,
    List<String>? mutedWords,
    bool? labelBlockedAccounts,
    bool? labelBlockedChats,
    bool? labelMutedWords,
    bool? inArchived,
  }) => ContentFilters(
    blockedChats: blockedChats ?? this.blockedChats,
    mutedWords: mutedWords ?? this.mutedWords,
    labelBlockedAccounts: labelBlockedAccounts ?? this.labelBlockedAccounts,
    labelBlockedChats: labelBlockedChats ?? this.labelBlockedChats,
    labelMutedWords: labelMutedWords ?? this.labelMutedWords,
    inArchived: inArchived ?? this.inArchived,
  );

  Map<String, Object?> toJson() => {
    'chats': {for (final e in blockedChats.entries) '${e.key}': e.value},
    'words': mutedWords,
    'labelAccounts': labelBlockedAccounts,
    'labelChats': labelBlockedChats,
    'labelWords': labelMutedWords,
    'inArchived': inArchived,
  };

  factory ContentFilters.fromJson(Map<String, dynamic> j) => ContentFilters(
    blockedChats: {
      for (final e in ((j['chats'] as Map?) ?? const {}).entries)
        ?int.tryParse('${e.key}'): '${e.value}',
    },
    mutedWords: [for (final w in (j['words'] as List?) ?? const []) '$w'],
    labelBlockedAccounts: j['labelAccounts'] as bool? ?? true,
    labelBlockedChats: j['labelChats'] as bool? ?? true,
    labelMutedWords: j['labelWords'] as bool? ?? true,
    inArchived: j['inArchived'] as bool? ?? false,
  );
}

class ContentFiltersController extends Notifier<ContentFilters> {
  static const _key = 'tg_content_filters';

  @override
  ContentFilters build() {
    unawaited(_load());
    return ContentFilters();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      state = ContentFilters.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _save(ContentFilters next) async {
    state = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(next.toJson()));
  }

  Future<void> blockChat(int id, String title) => _save(state.copyWith(blockedChats: {...state.blockedChats, id: title}));

  Future<void> unblockChat(int id) => _save(state.copyWith(blockedChats: {...state.blockedChats}..remove(id)));

  /// Adds a word or phrase; false when it is empty or already muted.
  bool muteWord(String word) {
    final w = word.trim();
    if (w.isEmpty || state.mutedWords.any((x) => x.toLowerCase() == w.toLowerCase())) return false;
    unawaited(_save(state.copyWith(mutedWords: [...state.mutedWords, w])));
    return true;
  }

  Future<void> unmuteWord(String word) =>
      _save(state.copyWith(mutedWords: state.mutedWords.where((w) => w != word).toList()));

  Future<void> setLabels({bool? accounts, bool? chats, bool? words}) => _save(
    state.copyWith(labelBlockedAccounts: accounts, labelBlockedChats: chats, labelMutedWords: words),
  );

  Future<void> setInArchived(bool v) => _save(state.copyWith(inArchived: v));
}

final contentFiltersProvider = NotifierProvider<ContentFiltersController, ContentFilters>(ContentFiltersController.new);

/// Who the active account has blocked on Telegram, as sender ids: a user's
/// id (the same as their private chat's) or a chat's id. Kept current from
/// TDLib's block-list updates.
class BlockedSendersController extends Notifier<Set<int>> {
  StreamSubscription<td.TdObject>? _sub;

  @override
  Set<int> build() {
    final client = ref.watch(telegramClientProvider);
    final ready = ref.watch(authStateProvider).value is td.AuthorizationStateReady;
    _sub = client.updates.listen((u) {
      if (u is td.UpdateChatBlockList) {
        final blocked = u.blockList is td.BlockListMain;
        if (blocked != state.contains(u.chatId)) {
          state = blocked ? {...state, u.chatId} : ({...state}..remove(u.chatId));
        }
      }
    });
    ref.onDispose(() => _sub?.cancel());
    if (ready) unawaited(reload());
    return const {};
  }

  /// Reads the whole block list again.
  Future<void> reload() async {
    final client = ref.read(telegramClientProvider);
    final ids = <int>{};
    try {
      for (var offset = 0; ; offset += 100) {
        final r = await client.send<td.MessageSenders>(
          td.GetBlockedMessageSenders(blockList: const td.BlockListMain(), offset: offset, limit: 100),
          limited: true,
        );
        for (final s in r.senders) {
          ids.add(switch (s) {
            td.MessageSenderUser(:final userId) => userId,
            td.MessageSenderChat(:final chatId) => chatId,
          });
        }
        if (r.senders.isEmpty || offset + r.senders.length >= r.totalCount) break;
      }
      state = ids;
    } catch (_) {}
  }
}

final blockedSendersProvider = NotifierProvider<BlockedSendersController, Set<int>>(BlockedSendersController.new);

enum HideReason { blockedAccount, blockedChat, mutedWord }

/// Why a message is hidden, and how.
class HiddenVerdict {
  const HiddenVerdict(this.reason, this.label, {required this.silent});
  final HideReason reason;

  /// "You blocked Jane", "Forwarded from a channel you blocked: …".
  final String label;

  /// Drop the message entirely, leaving no notice.
  final bool silent;
}

/// Whether [message] (or any message of its [album]) should be hidden in
/// the chat [viewingChatId]. Your own messages never are, nor is a blocked
/// channel's own content when you open that channel, nor anything in an
/// archived chat unless [ContentFilters.inArchived] is on.
HiddenVerdict? hiddenVerdict(
  td.Message message, {
  required ContentFilters filters,
  required Set<int> blockedSenders,
  required TelegramStore store,
  required int viewingChatId,
  List<td.Message> album = const [],
}) {
  if (message.isOutgoing) return null;
  if (store.chat(viewingChatId) case final c?) {
    if (store.kindOf(c) == ChatKind.saved) return null;
    // An archived chat (or the comments of one) is left alone unless asked.
    if (!filters.inArchived && c.inArchive && !c.inMain) return null;
  }

  String chatName(int id) => store.chat(id)?.title ?? filters.blockedChats[id] ?? 'a chat';

  HiddenVerdict account({bool forwarded = false}) => HiddenVerdict(
    HideReason.blockedAccount,
    // Never named (not even as "User 123…" when they aren't loaded): the
    // notice shouldn't show who you chose not to see.
    forwarded ? 'Forwarded from someone you blocked' : 'Message from someone you blocked',
    silent: !filters.labelBlockedAccounts,
  );
  HiddenVerdict chat(int id, {bool forwarded = false}) {
    final asAccount = blockedSenders.contains(id) && !filters.blockedChats.containsKey(id);
    final name = chatName(id);
    return HiddenVerdict(
      asAccount ? HideReason.blockedAccount : HideReason.blockedChat,
      forwarded
          ? (asAccount ? 'Forwarded from someone you blocked' : 'Forwarded from a chat you blocked')
          : (asAccount ? 'Message from someone you blocked' : 'Posted by $name, which you blocked'),
      silent: asAccount ? !filters.labelBlockedAccounts : !filters.labelBlockedChats,
    );
  }

  bool chatBlocked(int id) => id != viewingChatId && (filters.blockedChats.containsKey(id) || blockedSenders.contains(id));

  for (final m in [message, ...album]) {
    switch (m.senderId) {
      case td.MessageSenderUser(:final userId) when blockedSenders.contains(userId):
        return account();
      case td.MessageSenderChat(:final chatId) when chatBlocked(chatId):
        return chat(chatId);
      default:
    }
    switch (m.forwardInfo?.origin) {
      case td.MessageOriginUser(:final senderUserId) when blockedSenders.contains(senderUserId):
        return account(forwarded: true);
      case td.MessageOriginChannel(:final chatId) when chatBlocked(chatId):
        return chat(chatId, forwarded: true);
      case td.MessageOriginChat(:final senderChatId) when chatBlocked(senderChatId):
        return chat(senderChatId, forwarded: true);
      default:
    }
  }

  if (filters.mutedWords.isNotEmpty) {
    for (final m in [message, ...album]) {
      final g = gistOf(m.content);
      final word = filters.mutedWordIn(g.text) ?? (g.detail == null ? null : filters.mutedWordIn(g.detail!));
      if (word != null) {
        return HiddenVerdict(HideReason.mutedWord, 'Contains a word you muted', silent: !filters.labelMutedWords);
      }
    }
  }
  return null;
}
