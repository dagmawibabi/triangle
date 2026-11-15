import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../telegram/data/telegram_store.dart' show ChatKind, TelegramStore;

/// A chat in a custom folder: chat ids belong to one Telegram account, so
/// each ref carries its account.
@immutable
class FolderChatRef {
  const FolderChatRef(this.account, this.chatId);
  final String account;
  final int chatId;

  @override
  bool operator ==(Object o) => o is FolderChatRef && o.account == account && o.chatId == chatId;
  @override
  int get hashCode => Object.hash(account, chatId);

  Map<String, dynamic> toJson() => {'a': account, 'c': chatId};
  factory FolderChatRef.fromJson(Map j) => FolderChatRef('${j['a']}', (j['c'] as num).toInt());
}

/// A folder the person makes in the app, beside Telegram's own: any chats
/// (DMs, groups, channels, bots, from any account), a chat in as many
/// folders as they like. Shown in the drawer; the assistant can manage them.
///
/// Its mark is an emoji, one of the app's icons ([icon]), or nothing (both
/// empty). Besides chats picked one by one it can take whole [kinds] of
/// chat (every channel, every bot…), less any [excluded] from them.
@immutable
class CustomFolder {
  const CustomFolder({
    required this.id,
    required this.name,
    this.emoji = '📁',
    this.icon,
    this.chats = const [],
    this.kinds = const {},
    this.excluded = const [],
    required this.createdAt,
  });
  final String id;
  final String name;
  final String emoji;

  /// A key of the folder icon set; wins over [emoji] when set.
  final String? icon;
  final List<FolderChatRef> chats;

  /// Kinds of chat in the folder whole, in every account.
  final Set<ChatKind> kinds;

  /// Chats of those kinds taken out one by one.
  final List<FolderChatRef> excluded;
  final DateTime createdAt;

  /// Kinds a folder can take whole.
  static const pickableKinds = [ChatKind.private, ChatKind.bot, ChatKind.group, ChatKind.channel];

  static String kindLabel(ChatKind k) => switch (k) {
    ChatKind.private => 'People',
    ChatKind.bot => 'Bots',
    ChatKind.group => 'Groups',
    ChatKind.channel => 'Channels',
    ChatKind.secret => 'Secret chats',
    ChatKind.saved => 'Saved messages',
  };

  /// Whether [account]'s chat [chatId], of [kind], is in the folder.
  bool has(String account, int chatId, ChatKind? kind) {
    final ref = FolderChatRef(account, chatId);
    if (chats.contains(ref)) return true;
    return kind != null && kinds.contains(kind) && !excluded.contains(ref);
  }

  /// The ids of [account]'s chats in the folder: those picked, plus every
  /// chat [store] knows of the folder's kinds, less those taken out.
  List<int> chatIdsIn(String account, [TelegramStore? store]) {
    final ids = <int>{for (final c in chats) if (c.account == account) c.chatId};
    if (store != null && kinds.isNotEmpty) {
      final out = {for (final c in excluded) if (c.account == account) c.chatId};
      for (final c in store.chats.values) {
        if (c.title.isNotEmpty && kinds.contains(store.kindOf(c)) && !out.contains(c.id)) ids.add(c.id);
      }
    }
    return ids.toList();
  }

  CustomFolder copyWith({
    String? name,
    String? emoji,
    String? icon,
    bool clearIcon = false,
    List<FolderChatRef>? chats,
    Set<ChatKind>? kinds,
    List<FolderChatRef>? excluded,
  }) => CustomFolder(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    icon: clearIcon ? null : (icon ?? this.icon),
    chats: chats ?? this.chats,
    kinds: kinds ?? this.kinds,
    excluded: excluded ?? this.excluded,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    if (icon != null) 'icon': icon,
    'chats': [for (final c in chats) c.toJson()],
    if (kinds.isNotEmpty) 'kinds': [for (final k in kinds) k.name],
    if (excluded.isNotEmpty) 'excluded': [for (final c in excluded) c.toJson()],
    'created': createdAt.toIso8601String(),
  };

  factory CustomFolder.fromJson(Map j) => CustomFolder(
    id: '${j['id']}',
    name: '${j['name'] ?? 'Folder'}',
    emoji: '${j['emoji'] ?? '📁'}',
    icon: j['icon'] == null ? null : '${j['icon']}',
    chats: [for (final c in (j['chats'] as List? ?? const [])) if (c is Map) FolderChatRef.fromJson(c)],
    kinds: {for (final k in (j['kinds'] as List? ?? const [])) ?ChatKind.values.asNameMap()['$k']},
    excluded: [for (final c in (j['excluded'] as List? ?? const [])) if (c is Map) FolderChatRef.fromJson(c)],
    createdAt: DateTime.tryParse('${j['created']}') ?? DateTime.now(),
  );

  /// For the assistant.
  Map<String, dynamic> describe([int? chatCount]) => {
    'folder_id': id,
    'name': name,
    if (icon == null && emoji.isNotEmpty) 'emoji': emoji,
    if (icon != null) 'icon': icon,
    if (kinds.isNotEmpty) 'whole_types': [for (final k in kinds) chatTypeName(k)],
    'chat_count': chatCount ?? chats.length,
  };
}

/// The names the assistant uses for chat types.
String chatTypeName(ChatKind k) => switch (k) {
  ChatKind.private => 'dms',
  ChatKind.bot => 'bots',
  ChatKind.group => 'groups',
  ChatKind.channel => 'channels',
  _ => k.name,
};

/// A chat type named by the assistant ("channels", "dms", "bots", "groups").
ChatKind? chatKindNamed(String name) => switch (name.trim().toLowerCase()) {
  'dm' || 'dms' || 'people' || 'person' || 'private' || 'users' => ChatKind.private,
  'bot' || 'bots' => ChatKind.bot,
  'group' || 'groups' => ChatKind.group,
  'channel' || 'channels' => ChatKind.channel,
  _ => null,
};

@immutable
class CustomFoldersState {
  const CustomFoldersState({this.folders = const [], this.inDrawer = true, this.drawerOpen = true});
  final List<CustomFolder> folders;
  final bool inDrawer;
  final bool drawerOpen;

  CustomFoldersState copyWith({List<CustomFolder>? folders, bool? inDrawer, bool? drawerOpen}) =>
      CustomFoldersState(folders: folders ?? this.folders, inDrawer: inDrawer ?? this.inDrawer, drawerOpen: drawerOpen ?? this.drawerOpen);
}

class CustomFoldersStore extends Notifier<CustomFoldersState> {
  static const _key = 'custom_folders.v1';
  static const _uuid = Uuid();
  late Future<void> ready;

  @override
  CustomFoldersState build() {
    ready = _load();
    return const CustomFoldersState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = CustomFoldersState(
        folders: [for (final f in (j['folders'] as List? ?? const [])) if (f is Map) CustomFolder.fromJson(f)],
        inDrawer: j['in_drawer'] != false,
        drawerOpen: j['drawer_open'] != false,
      );
    } catch (e) {
      debugPrint('[CustomFolders] $e');
    }
  }

  Future<void> _set(CustomFoldersState s) async {
    state = s;
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'folders': [for (final f in s.folders) f.toJson()],
        'in_drawer': s.inDrawer,
        'drawer_open': s.drawerOpen,
      }),
    );
  }

  CustomFolder? byId(String id) => state.folders.where((f) => f.id == id).firstOrNull;

  /// A folder by id, or by name (any case).
  CustomFolder? find(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    return byId(idOrName.trim()) ?? state.folders.where((f) => f.name.toLowerCase() == q).firstOrNull;
  }

  Future<CustomFolder> create(
    String name, {
    String emoji = '📁',
    String? icon,
    List<FolderChatRef> chats = const [],
    Set<ChatKind> kinds = const {},
  }) async {
    await ready;
    final f = CustomFolder(
      id: _uuid.v4().substring(0, 8),
      name: name.trim().isEmpty ? 'Folder' : name.trim(),
      emoji: emoji.trim(),
      icon: icon,
      chats: chats.toSet().toList(),
      kinds: kinds,
      createdAt: DateTime.now(),
    );
    await _set(state.copyWith(folders: [...state.folders, f]));
    return f;
  }

  Future<CustomFolder?> update(String id, CustomFolder Function(CustomFolder) change) async {
    await ready;
    CustomFolder? out;
    await _set(state.copyWith(folders: [for (final f in state.folders) if (f.id == id) out = change(f) else f]));
    return out;
  }

  Future<CustomFolder?> addChats(String id, Iterable<FolderChatRef> refs) {
    final add = refs.toSet();
    return update(id, (f) => f.copyWith(
      chats: {...f.chats, ...add}.toList(),
      excluded: [for (final c in f.excluded) if (!add.contains(c)) c],
    ));
  }

  /// Takes chats out, including ones that were in through their type.
  Future<CustomFolder?> removeChats(String id, Iterable<FolderChatRef> refs) {
    final drop = refs.toSet();
    return update(id, (f) => f.copyWith(
      chats: [for (final c in f.chats) if (!drop.contains(c)) c],
      excluded: f.kinds.isEmpty ? f.excluded : {...f.excluded, ...drop}.toList(),
    ));
  }

  /// Sets exactly what of [account] is in the folder: the chats picked one
  /// by one, the whole kinds (for every account), and the chats of those
  /// kinds left out.
  Future<CustomFolder?> setMembers(
    String id,
    String account, {
    required Iterable<int> chatIds,
    required Set<ChatKind> kinds,
    Iterable<int> excluded = const [],
  }) => update(id, (f) => f.copyWith(
    chats: [for (final c in f.chats) if (c.account != account) c, for (final i in chatIds.toSet()) FolderChatRef(account, i)],
    kinds: kinds,
    excluded: [for (final c in f.excluded) if (c.account != account) c, for (final i in excluded.toSet()) FolderChatRef(account, i)],
  ));

  /// Sets exactly which of [account]'s chats are in the folder one by one,
  /// keeping its kinds and other accounts' chats.
  Future<CustomFolder?> setChats(String id, String account, Iterable<int> chatIds) => update(id, (f) => f.copyWith(
    chats: [for (final c in f.chats) if (c.account != account) c, for (final i in chatIds.toSet()) FolderChatRef(account, i)],
  ));

  Future<CustomFolder?> addKinds(String id, Iterable<ChatKind> kinds) =>
      update(id, (f) => f.copyWith(kinds: {...f.kinds, ...kinds}));

  Future<CustomFolder?> removeKinds(String id, Iterable<ChatKind> kinds) {
    final drop = kinds.toSet();
    return update(id, (f) => f.copyWith(kinds: {for (final k in f.kinds) if (!drop.contains(k)) k}));
  }

  Future<bool> delete(String id) async {
    await ready;
    final before = state.folders.length;
    await _set(state.copyWith(folders: [for (final f in state.folders) if (f.id != id) f]));
    return state.folders.length != before;
  }

  Future<void> reorder(int from, int to) async {
    final list = [...state.folders];
    final f = list.removeAt(from);
    list.insert(to > from ? to - 1 : to, f);
    await _set(state.copyWith(folders: list));
  }

  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
  Future<void> setDrawerOpen(bool v) => _set(state.copyWith(drawerOpen: v));

  /// The folders [account]'s chat [chatId] (of [kind]) is in.
  List<CustomFolder> foldersOf(String account, int chatId, [ChatKind? kind]) => [
    for (final f in state.folders)
      if (f.has(account, chatId, kind)) f,
  ];
}

final customFoldersProvider = NotifierProvider<CustomFoldersStore, CustomFoldersState>(CustomFoldersStore.new);
