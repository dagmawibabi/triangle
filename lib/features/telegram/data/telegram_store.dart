import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../../infrastructure/telegram/td_compat.dart';

enum ChatKind { private, bot, group, channel, secret, saved }

/// What the app knows about one chat, kept current from TDLib's updates so
/// questions about the chat list never cost a request.
class ChatInfo {
  ChatInfo({required this.id, required this.title, required this.type});

  final int id;
  String title;
  td.ChatType type;
  int unreadCount = 0;
  int unreadMentionCount = 0;

  /// Messages of the account's with reactions it hasn't seen yet.
  int unreadReactionCount = 0;

  /// The group call of a running (or scheduled) video chat; 0 when none.
  int videoChatId = 0;
  bool markedUnread = false;
  int lastReadInboxMessageId = 0;
  td.Message? lastMessage;
  int muteFor = 0;
  int lastReadOutboxMessageId = 0;
  td.ChatPhotoInfo? photo;
  td.ChatNotificationSettings? notifications;

  /// The chat's own background, when one is set.
  td.ChatBackground? background;

  /// Has messages waiting to be sent at a set time.
  bool hasScheduled = false;

  /// Order within each list it is in: `main`, `archive`, `folder:<id>`.
  final Map<String, int> order = {};

  /// The lists ('main', 'archive', 'folder:<id>') the chat is pinned in.
  final Set<String> pinnedIn = {};
  bool get isPinned => pinnedIn.contains(inMain ? 'main' : 'archive');

  bool get inMain => (order['main'] ?? 0) != 0;
  bool get inArchive => (order['archive'] ?? 0) != 0;
  bool get isListed => inMain || inArchive;
  bool get isMuted => muteFor > 0;
  bool get hasUnread => unreadCount > 0 || markedUnread;
}

/// The account's chats, users and channels as TDLib reports them.
class TelegramStore extends ChangeNotifier {
  TelegramStore(this._client) {
    _sub = _client.updates.listen(_onUpdate);
    unawaited(_client.ready.then((_) => _afterSignIn()));
  }

  final TelegramClient _client;
  late final StreamSubscription<td.TdObject> _sub;

  final Map<int, ChatInfo> chats = {};

  /// Animated effects messages can be sent with, as TDLib announces them.
  List<int> messageEffectIds = const [];
  final Map<int, td.User> users = {};
  final Map<int, td.Supergroup> supergroups = {};
  final Map<int, td.BasicGroup> basicGroups = {};
  td.User? me;

  /// How many members of an open group are online right now.
  final Map<int, int> onlineMembers = {};

  /// Channel direct-messages topics by chat, then topic id.
  final Map<int, Map<int, td.DirectMessagesChatTopic>> directMessagesTopics = {};

  /// Welcome messages of chats the account manages, once loaded.
  final Map<int, List<td.WelcomeMessage>> welcomeMessages = {};

  /// A bot's reply being written, shown live until the real message lands.
  final Map<int, td.UpdatePendingMessage> pendingMessages = {};

  /// The account's chat folders, in Telegram's order.
  List<FolderInfo> folders = const [];

  /// Chat ids per folder, once [loadFolder] has read the folder's list.
  final Map<int, List<int>> folderChats = {};
  final Map<int, Future<List<int>>> _folderLoads = {};

  /// Whether every chat in Main and Archive has been loaded once.
  bool chatsLoaded = false;
  Future<void>? _loading;

  Future<void> _afterSignIn() async {
    try {
      me = await _client.send<td.User>(const td.GetMe());
    } catch (e) {
      debugPrint('[Store] getMe failed: $e');
    }
    unawaited(ensureChatsLoaded());
  }

  /// TDLib sends chats as updates while `loadChats` pages through the list;
  /// a 404 means the list is complete. Each page goes through the limiter.
  Future<void> ensureChatsLoaded() => _loading ??= _loadAll().whenComplete(() {
    if (!chatsLoaded) _loading = null;
  });

  Future<void> _loadAll() async {
    for (final list in const [td.ChatListMain(), td.ChatListArchive()]) {
      for (var page = 0; page < 60; page++) {
        try {
          await _client.send<td.Ok>(td.LoadChats(chatList: list, limit: 100), limited: true, timeout: const Duration(seconds: 60));
        } on TelegramException catch (e) {
          if (e.code == 404) break;
          rethrow;
        }
      }
    }
    await _fillFromCache();
    await _recoverFolders();
    chatsLoaded = true;
    notifyListeners();
  }

  /// TDLib announces each chat, user and group once per client. A client
  /// taken over from an earlier run of the app (a hot restart, or a new
  /// Flutter engine in the same process) won't announce them again, so the
  /// ones this store hasn't heard of are read from TDLib's own cache. These
  /// requests don't reach Telegram's servers.
  Future<void> _fillFromCache() async {
    for (final list in const [td.ChatListMain(), td.ChatListArchive()]) {
      try {
        final ids = await _client.send<td.Chats>(td.GetChats(chatList: list, limit: 5000));
        for (final id in ids.chatIds) {
          if ((chats[id]?.title ?? '').isNotEmpty) continue;
          final chat = await _client.send<td.Chat>(td.GetChat(chatId: id));
          _onUpdate(td.UpdateNewChat(chat: chat));
          switch (chat.type) {
            case td.ChatTypePrivate(:final userId) when !users.containsKey(userId):
              _onUpdate(td.UpdateUser(user: await _client.send<td.User>(td.GetUser(userId: userId))));
            case td.ChatTypeSupergroup(:final supergroupId) when !supergroups.containsKey(supergroupId):
              _onUpdate(
                td.UpdateSupergroup(
                  supergroup: await _client.send<td.Supergroup>(td.GetSupergroup(supergroupId: supergroupId)),
                ),
              );
            case td.ChatTypeBasicGroup(:final basicGroupId) when !basicGroups.containsKey(basicGroupId):
              _onUpdate(
                td.UpdateBasicGroup(
                  basicGroup: await _client.send<td.BasicGroup>(td.GetBasicGroup(basicGroupId: basicGroupId)),
                ),
              );
            default:
              break;
          }
        }
      } catch (e) {
        debugPrint('[Store] cache fill: $e');
      }
    }
  }

  ChatInfo? chat(int id) => chats[id];

  /// A client taken over from an earlier run doesn't announce the folders
  /// again; their ids are in the chats' positions, and each folder's name
  /// comes from TDLib's cache.
  Future<void> _recoverFolders() async {
    if (folders.isNotEmpty) return;
    final ids = <int>{
      for (final c in chats.values)
        for (final key in c.order.keys)
          if (key.startsWith('folder:')) int.parse(key.substring(7)),
    };
    final found = <FolderInfo>[];
    for (final id in ids) {
      try {
        final f = await _client.send<td.ChatFolder>(td.GetChatFolder(chatFolderId: id));
        found.add(FolderInfo(id: id, title: f.title, icon: f.icon?.name ?? ''));
      } catch (_) {}
    }
    if (found.isNotEmpty) folders = found..sort((a, b) => a.id.compareTo(b.id));
  }

  /// The chats in a folder, newest activity first. Loads the folder's list
  /// once (paged through the rate limiter); TDLib works out who belongs,
  /// rules like "all groups" included.
  Future<List<int>> loadFolder(int folderId) => _folderLoads[folderId] ??= () async {
    final list = td.ChatListFolder(chatFolderId: folderId);
    for (var page = 0; page < 30; page++) {
      try {
        await _client.send<td.Ok>(td.LoadChats(chatList: list, limit: 100), limited: true, timeout: const Duration(seconds: 60));
      } on TelegramException catch (e) {
        if (e.code == 404) break;
        rethrow;
      }
    }
    final r = await _client.send<td.Chats>(td.GetChats(chatList: list, limit: 5000));
    for (final id in r.chatIds) {
      if ((chats[id]?.title ?? '').isEmpty) {
        try {
          _onUpdate(td.UpdateNewChat(chat: await _client.send<td.Chat>(td.GetChat(chatId: id))));
        } catch (_) {}
      }
    }
    folderChats[folderId] = r.chatIds;
    notifyListeners();
    return r.chatIds;
  }().whenComplete(() {
    if (!folderChats.containsKey(folderId)) _folderLoads.remove(folderId);
  });

  // ---- profile pictures ----------------------------------------------------

  final Map<int, String> _photoPaths = {};
  final Map<int, Future<String?>> _photoLoads = {};
  int _activeDownloads = 0;
  final List<Completer<void>> _downloadQueue = [];

  /// The small photo of a chat or a user, as TDLib describes it.
  td.File? chatPhotoFile(int chatId) => chats[chatId]?.photo?.small;
  td.File? userPhotoFile(int userId) => users[userId]?.profilePhoto?.small;

  /// A blurry inline preview TDLib sends with the photo, for while it loads.
  td.Minithumbnail? chatMinithumbnail(int chatId) => chats[chatId]?.photo?.minithumbnail;

  /// The local path of [file], downloading it once if needed. A few photos
  /// download at a time, so a long list doesn't fire dozens at once, and
  /// the newest request goes first: the avatars on screen now, not the ones
  /// scrolled past.
  Future<String?> photoPath(td.File file) {
    final cached = _photoPaths[file.id];
    if (cached != null) return Future.value(cached);
    if (file.local.isDownloadingCompleted && file.local.path.isNotEmpty) {
      return Future.value(_photoPaths[file.id] = file.local.path);
    }
    return _photoLoads[file.id] ??= _download(file.id).whenComplete(() => _photoLoads.remove(file.id));
  }

  String? cachedPhotoPath(td.File? file) {
    if (file == null) return null;
    if (file.local.isDownloadingCompleted && file.local.path.isNotEmpty) return file.local.path;
    return _photoPaths[file.id];
  }

  Future<String?> _download(int fileId) async {
    if (_activeDownloads >= 6) {
      final turn = Completer<void>();
      _downloadQueue.add(turn);
      await turn.future;
    }
    _activeDownloads++;
    try {
      final f = await _client.send<td.File>(
        td.DownloadFile(fileId: fileId, priority: 12, offset: 0, limit: 0, synchronous: true),
        timeout: const Duration(seconds: 60),
      );
      if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) return _photoPaths[fileId] = f.local.path;
      return null;
    } catch (e) {
      debugPrint('[Store] photo $fileId: $e');
      return null;
    } finally {
      _activeDownloads--;
      if (_downloadQueue.isNotEmpty) _downloadQueue.removeLast().complete();
    }
  }

  String userName(int userId) {
    final u = users[userId];
    if (u == null) return 'User $userId';
    final name = '${u.firstName} ${u.lastName}'.trim();
    return name.isEmpty ? 'Deleted account' : name;
  }

  String? username(td.Usernames? names) {
    final list = names?.activeUsernames ?? const [];
    return list.isEmpty ? null : list.first;
  }

  ChatKind kindOf(ChatInfo c) => switch (c.type) {
    td.ChatTypePrivate(:final userId) =>
      userId == me?.id ? ChatKind.saved : (users[userId]?.type is td.UserTypeBot ? ChatKind.bot : ChatKind.private),
    td.ChatTypeSecret() => ChatKind.secret,
    td.ChatTypeBasicGroup() => ChatKind.group,
    td.ChatTypeSupergroup(:final isChannel) => isChannel ? ChatKind.channel : ChatKind.group,
  };

  /// The public @username of a chat, when it has one.
  String? chatUsername(ChatInfo c) => switch (c.type) {
    td.ChatTypePrivate(:final userId) => username(users[userId]?.usernames),
    td.ChatTypeSupergroup(:final supergroupId) => username(supergroups[supergroupId]?.usernames),
    _ => null,
  };

  /// A supergroup with topics.
  /// A channel's direct messages group: one topic per person writing in.
  bool isDirectMessagesGroup(ChatInfo c) => switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId) => supergroups[supergroupId]?.isDirectMessagesGroup ?? false,
    _ => false,
  };

  bool isForum(ChatInfo c) => switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId) => supergroups[supergroupId]?.isForum ?? false,
    _ => false,
  };

  /// Whether the account can write here: always in private chats and
  /// groups it belongs to, only as an admin who may post in channels.
  bool canPost(ChatInfo c) => switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId, :final isChannel) => switch (supergroups[supergroupId]?.status) {
      td.ChatMemberStatusCreator() => true,
      td.ChatMemberStatusAdministrator(:final rights) => !isChannel || rights.canPostMessages,
      td.ChatMemberStatusMember() || td.ChatMemberStatusRestricted() => !isChannel,
      _ => false,
    },
    td.ChatTypeBasicGroup(:final basicGroupId) => switch (basicGroups[basicGroupId]?.status) {
      td.ChatMemberStatusLeft() || td.ChatMemberStatusBanned() || null => false,
      _ => true,
    },
    _ => true,
  };

  /// The account's own status in a group or channel, null elsewhere.
  td.ChatMemberStatus? myStatus(ChatInfo c) => switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId) => supergroups[supergroupId]?.status,
    td.ChatTypeBasicGroup(:final basicGroupId) => basicGroups[basicGroupId]?.status,
    _ => null,
  };

  bool isCreator(ChatInfo c) => myStatus(c) is td.ChatMemberStatusCreator;

  /// Owner or admin.
  bool isAdmin(ChatInfo c) => switch (myStatus(c)) {
    td.ChatMemberStatusCreator(:final isMember) => isMember,
    td.ChatMemberStatusAdministrator() => true,
    _ => false,
  };

  bool isMember(ChatInfo c) => switch (myStatus(c)) {
    td.ChatMemberStatusCreator(:final isMember) => isMember,
    td.ChatMemberStatusRestricted(:final isMember) => isMember,
    td.ChatMemberStatusLeft() || td.ChatMemberStatusBanned() => false,
    null => c.type is td.ChatTypePrivate || c.type is td.ChatTypeSecret,
    _ => true,
  };

  int? memberCount(ChatInfo c) => switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId) => supergroups[supergroupId]?.memberCount,
    td.ChatTypeBasicGroup(:final basicGroupId) => basicGroups[basicGroupId]?.memberCount,
    _ => null,
  };

  String senderName(td.MessageSender sender) => switch (sender) {
    td.MessageSenderUser(:final userId) => userName(userId),
    td.MessageSenderChat(:final chatId) => chats[chatId]?.title ?? 'Chat $chatId',
  };

  ChatInfo _chatFor(int id) => chats[id] ??= ChatInfo(id: id, title: '', type: const td.ChatTypePrivate(userId: 0));

  void _setPosition(ChatInfo c, td.ChatPosition p) {
    final key = switch (p.list) {
      td.ChatListMain() => 'main',
      td.ChatListArchive() => 'archive',
      td.ChatListFolder(:final chatFolderId) => 'folder:$chatFolderId',
    };
    if (p.order == 0) {
      c.order.remove(key);
    } else {
      c.order[key] = p.order;
    }
    if (p.isPinned && p.order != 0) {
      c.pinnedIn.add(key);
    } else {
      c.pinnedIn.remove(key);
    }
  }

  Timer? _notify;

  /// Updates come in bursts while chats load; listeners hear once per burst.
  void _changed() {
    _notify ??= Timer(const Duration(milliseconds: 250), () {
      _notify = null;
      notifyListeners();
    });
  }

  void _onUpdate(td.TdObject u) {
    switch (u) {
      case td.UpdateNewChat(:final chat):
        final c = _chatFor(chat.id)
          ..title = chat.title
          ..type = chat.type
          ..unreadCount = chat.unreadCount
          ..unreadMentionCount = chat.unreadMentionCount
          ..unreadReactionCount = chat.unreadReactionCount
          ..videoChatId = chat.videoChat.groupCallId
          ..markedUnread = chat.isMarkedAsUnread
          ..lastReadInboxMessageId = chat.lastReadInboxMessageId
          ..lastMessage = chat.lastMessage
          ..muteFor = chat.notificationSettings.muteFor
          ..notifications = chat.notificationSettings
          ..lastReadOutboxMessageId = chat.lastReadOutboxMessageId
          ..photo = chat.photo
          ..background = chat.background
          ..hasScheduled = chat.hasScheduledMessages;
        for (final p in chat.positions) {
          _setPosition(c, p);
        }
      case td.UpdateChatTitle(:final chatId, :final title):
        _chatFor(chatId).title = title;
      case td.UpdateChatPhoto(:final chatId, :final photo):
        _chatFor(chatId).photo = photo;
      case td.UpdateChatBackground(:final chatId, :final background):
        _chatFor(chatId).background = background;
      case td.UpdateChatHasScheduledMessages(:final chatId, :final hasScheduledMessages):
        _chatFor(chatId).hasScheduled = hasScheduledMessages;
      case td.UpdateChatLastMessage(:final chatId, :final lastMessage, :final positions):
        final c = _chatFor(chatId)..lastMessage = lastMessage;
        for (final p in positions) {
          _setPosition(c, p);
        }
      case td.UpdateChatPosition(:final chatId, :final position):
        _setPosition(_chatFor(chatId), position);
      case td.UpdateChatReadInbox(:final chatId, :final lastReadInboxMessageId, :final unreadCount):
        _chatFor(chatId)
          ..lastReadInboxMessageId = lastReadInboxMessageId
          ..unreadCount = unreadCount;
      case td.UpdateChatUnreadMentionCount(:final chatId, :final unreadMentionCount):
        _chatFor(chatId).unreadMentionCount = unreadMentionCount;
      case td.UpdateChatUnreadReactionCount(:final chatId, :final unreadReactionCount):
        _chatFor(chatId).unreadReactionCount = unreadReactionCount;
      case td.UpdateChatVideoChat(:final chatId, :final videoChat):
        _chatFor(chatId).videoChatId = videoChat.groupCallId;
      case td.UpdateAvailableMessageEffects(:final reactionEffectIds, :final stickerEffectIds):
        messageEffectIds = [...reactionEffectIds, ...stickerEffectIds];
      case td.UpdateChatIsMarkedAsUnread(:final chatId, :final isMarkedAsUnread):
        _chatFor(chatId).markedUnread = isMarkedAsUnread;
      case td.UpdateChatNotificationSettings(:final chatId, :final notificationSettings):
        _chatFor(chatId)
          ..muteFor = notificationSettings.muteFor
          ..notifications = notificationSettings;
      case td.UpdateChatReadOutbox(:final chatId, :final lastReadOutboxMessageId):
        _chatFor(chatId).lastReadOutboxMessageId = lastReadOutboxMessageId;
      case td.UpdateUser(:final user):
        users[user.id] = user;
        if (user.id == me?.id) me = user;
      case td.UpdateUserStatus(:final userId, :final status):
        final u = users[userId];
        if (u != null) users[userId] = u.copyWith(status: status);
      case td.UpdateChatOnlineMemberCount(:final chatId, :final onlineMemberCount):
        onlineMembers[chatId] = onlineMemberCount;
      case td.UpdateDirectMessagesChatTopic(:final topic):
        (directMessagesTopics[topic.chatId] ??= {})[topic.id] = topic;
      case td.UpdateChatWelcomeMessages(:final chatId, :final messages):
        welcomeMessages[chatId] = messages;
      case td.UpdatePendingMessage(:final chatId):
        pendingMessages[chatId] = u;
      case td.UpdateNewMessage(:final message) when !message.isOutgoing && pendingMessages.containsKey(message.chatId):
        pendingMessages.remove(message.chatId);
      case td.UpdateSupergroup(:final supergroup):
        supergroups[supergroup.id] = supergroup;
      case td.UpdateChatFolders(:final chatFolders):
        folders = [for (final f in chatFolders) FolderInfo(id: f.id, title: f.title, icon: f.icon.name)];
      case td.UpdateBasicGroup(:final basicGroup):
        basicGroups[basicGroup.id] = basicGroup;
      case td.UpdateAuthorizationState(:final authorizationState):
        if (authorizationState is td.AuthorizationStateClosed) {
          chats.clear();
          users.clear();
          supergroups.clear();
          basicGroups.clear();
          me = null;
          chatsLoaded = false;
          _loading = null;
          unawaited(_client.ready.then((_) => _afterSignIn()));
        }
      default:
        return;
    }
    _changed();
  }

  @override
  void dispose() {
    _notify?.cancel();
    _sub.cancel();
    super.dispose();
  }
}

/// Each account's store, alive as long as its client, so every account's
/// chat list stays current whichever one is on screen. Read through
/// [accountStoreProvider] or [telegramStoreProvider] to hear its changes.
final telegramStoreFamily = Provider.family<TelegramStore, String>((ref, id) {
  final store = TelegramStore(ref.watch(telegramClientFamily(id)));
  ref.onDispose(store.dispose);
  return store;
});

TelegramStore _listened(Ref ref, TelegramStore store) {
  void changed() => ref.notifyListeners();
  store.addListener(changed);
  ref.onDispose(() => store.removeListener(changed));
  return store;
}

/// One account's store; widgets watching it rebuild when it changes.
final accountStoreProvider = Provider.family<TelegramStore, String>(
  (ref, id) => _listened(ref, ref.watch(telegramStoreFamily(id))),
);

/// The active account's store. Switching accounts swaps it.
final telegramStoreProvider = Provider<TelegramStore>(
  (ref) => _listened(ref, ref.watch(telegramStoreFamily(ref.watch(activeAccountIdProvider)))),
);

/// A chat folder: its id, name and Telegram's icon name.
class FolderInfo {
  const FolderInfo({required this.id, required this.title, this.icon = ''});
  final int id;
  final String title;

  /// "All", "Unread", "Bots", "Channels", "Groups", "Private", "Custom",
  /// "Work", "Home", "Study", "Travel", … or empty.
  final String icon;
}
