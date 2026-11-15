import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../sections/section_kit.dart';
import '../telegram/data/message_content.dart';
import '../telegram/data/telegram_store.dart';

// The gallery: photos and videos from the chats picked as sources, with
// albums, favorites and hidden items kept on this phone.

class GalleryItem {
  GalleryItem({
    required this.account,
    required this.chatId,
    required this.messageId,
    required this.source,
    required this.date,
    required this.video,
    this.thumb,
    this.mini,
    this.full,
    this.width = 0,
    this.height = 0,
    this.seconds = 0,
    this.caption = '',
    this.size = 0,
  });
  final String account;
  final int chatId;
  final int messageId;
  final String source;
  final DateTime date;
  final bool video;

  /// A small picture for the grid, and the whole file for the viewer.
  final td.File? thumb;
  final td.Minithumbnail? mini;
  final td.File? full;
  final int width;
  final int height;
  final int seconds;
  final String caption;
  final int size;

  String get key => postKey(account, chatId, messageId);

  static GalleryItem? fromMessage(td.Message m, String account, String source) {
    final caption = messageText(m);
    switch (m.content) {
      case td.MessagePhoto(:final photo):
        final big = pickPhotoSize(photo.sizes, minWidth: 2000);
        return GalleryItem(
          account: account,
          chatId: m.chatId,
          messageId: m.id,
          source: source,
          date: unixDate(m.date),
          video: false,
          thumb: pickPhotoSize(photo.sizes, minWidth: 320)?.photo,
          mini: photo.minithumbnail,
          full: big?.photo,
          width: big?.width ?? 0,
          height: big?.height ?? 0,
          caption: caption,
          size: big?.photo.size ?? 0,
        );
      case td.MessageVideo(:final video):
        return GalleryItem(
          account: account,
          chatId: m.chatId,
          messageId: m.id,
          source: source,
          date: unixDate(m.date),
          video: true,
          thumb: video.thumbnail?.file,
          mini: video.minithumbnail,
          full: video.video,
          width: video.width,
          height: video.height,
          seconds: video.duration,
          caption: caption,
          size: video.video.size > 0 ? video.video.size : video.video.expectedSize,
        );
      default:
        return null;
    }
  }

  Map<String, dynamic> describe() => {
    'item_key': key,
    'type': video ? 'video' : 'photo',
    'source': source,
    'chat_id': chatId,
    'message_id': messageId,
    'date': date.toIso8601String().substring(0, 10),
    if (width > 0) 'size_px': '${width}x$height',
    if (seconds > 0) 'seconds': seconds,
    if (caption.isNotEmpty) 'caption': caption.length > 200 ? '${caption.substring(0, 200)}…' : caption,
  };
}

@immutable
class GalleryAlbum {
  const GalleryAlbum({required this.id, required this.name, this.keys = const [], this.minis = const {}, this.emoji = '', required this.createdAt});
  final String id;
  final String name;

  /// Items, newest added first.
  final List<String> keys;

  /// A blurry preview per item, to show the album without loading posts.
  final Map<String, String> minis;
  final String emoji;
  final DateTime createdAt;

  GalleryAlbum copyWith({String? name, List<String>? keys, Map<String, String>? minis, String? emoji}) =>
      GalleryAlbum(id: id, name: name ?? this.name, keys: keys ?? this.keys, minis: minis ?? this.minis, emoji: emoji ?? this.emoji, createdAt: createdAt);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'keys': keys, 'minis': minis, if (emoji.isNotEmpty) 'emoji': emoji, 'at': createdAt.millisecondsSinceEpoch};
  factory GalleryAlbum.fromJson(Map j) => GalleryAlbum(
    id: '${j['id']}',
    name: '${j['name'] ?? 'Album'}',
    keys: [for (final k in (j['keys'] as List? ?? const [])) '$k'],
    minis: {for (final e in ((j['minis'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    emoji: '${j['emoji'] ?? ''}',
    createdAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {'album_id': id, 'name': name, 'items': keys.length, if (emoji.isNotEmpty) 'emoji': emoji};
}

@immutable
class GalleryState {
  const GalleryState({
    this.sources = const [],
    this.albums = const [],
    this.favorites = const [],
    this.hidden = const {},
    this.minis = const {},
    this.columns = 4,
    this.inDrawer = true,
    this.autoDownload = true,
  });

  /// Downloads thumbnails and photos as they show; off, only previews
  /// until a photo is opened.
  final bool autoDownload;
  final List<SourceRef> sources;
  final List<GalleryAlbum> albums;

  /// Newest favorite first.
  final List<String> favorites;
  final Set<String> hidden;

  /// Previews of favorites and hidden items.
  final Map<String, String> minis;
  final int columns;
  final bool inDrawer;

  bool isFavorite(String k) => favorites.contains(k);

  GalleryState copyWith({List<SourceRef>? sources, List<GalleryAlbum>? albums, List<String>? favorites, Set<String>? hidden, Map<String, String>? minis, int? columns, bool? inDrawer, bool? autoDownload}) => GalleryState(
    autoDownload: autoDownload ?? this.autoDownload,
    sources: sources ?? this.sources,
    albums: albums ?? this.albums,
    favorites: favorites ?? this.favorites,
    hidden: hidden ?? this.hidden,
    minis: minis ?? this.minis,
    columns: columns ?? this.columns,
    inDrawer: inDrawer ?? this.inDrawer,
  );
}

class GalleryStore extends Notifier<GalleryState> {
  static const key = 'gallery.v1';
  late Future<void> ready;

  @override
  GalleryState build() {
    ready = _load();
    return const GalleryState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = GalleryState(
        sources: [for (final s in (j['sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        albums: [for (final a in (j['albums'] as List? ?? const [])) if (a is Map) GalleryAlbum.fromJson(a)],
        favorites: [for (final f in (j['favorites'] as List? ?? const [])) '$f'],
        hidden: {for (final f in (j['hidden'] as List? ?? const [])) '$f'},
        minis: {for (final e in ((j['minis'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        columns: (j['columns'] as num?)?.toInt() ?? 4,
        inDrawer: j['in_drawer'] != false,
        autoDownload: j['auto_download'] != false,
      );
    } catch (e) {
      debugPrint('[Gallery] $e');
    }
  }

  Future<void> _set(GalleryState s) async {
    // Keep previews only for items still favorited or hidden.
    final keep = {...s.favorites, ...s.hidden};
    s = s.copyWith(minis: {for (final e in s.minis.entries) if (keep.contains(e.key)) e.key: e.value});
    state = s;
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'sources': [for (final x in s.sources) x.toJson()],
        'albums': [for (final x in s.albums) x.toJson()],
        'favorites': s.favorites,
        'hidden': s.hidden.toList(),
        'minis': s.minis,
        'columns': s.columns,
        'in_drawer': s.inDrawer,
        'auto_download': s.autoDownload,
      }),
    );
  }

  Future<void> setAutoDownload(bool v) => _set(state.copyWith(autoDownload: v));

  Future<void> setSources(List<SourceRef> v) => _set(state.copyWith(sources: v));
  Future<void> addSources(Iterable<SourceRef> v) {
    final have = {for (final s in state.sources) s.key};
    return _set(state.copyWith(sources: [...state.sources, for (final s in v) if (have.add(s.key)) s]));
  }

  Future<void> removeSource(String k) => _set(state.copyWith(sources: [for (final s in state.sources) if (s.key != k) s]));
  Future<void> setSourceHidden(String k, bool v) => _set(state.copyWith(sources: [for (final s in state.sources) s.key == k ? s.copyWith(hidden: v) : s]));

  Future<void> setFavorite(Iterable<GalleryItem> items, bool on) {
    final keys = {for (final i in items) i.key};
    final minis = {...state.minis, for (final i in items) if (i.mini != null) i.key: i.mini!.data};
    return _set(state.copyWith(
      favorites: on ? [for (final i in items) if (!state.favorites.contains(i.key)) i.key, ...state.favorites] : [for (final f in state.favorites) if (!keys.contains(f)) f],
      minis: minis,
    ));
  }

  Future<void> setFavoriteKeys(Iterable<String> keys, bool on) {
    final k = keys.toSet();
    return _set(state.copyWith(favorites: on ? [for (final x in k) if (!state.favorites.contains(x)) x, ...state.favorites] : [for (final f in state.favorites) if (!k.contains(f)) f]));
  }

  Future<void> setHidden(Iterable<GalleryItem> items, bool on) {
    final minis = {...state.minis, for (final i in items) if (i.mini != null) i.key: i.mini!.data};
    return setHiddenKeys([for (final i in items) i.key], on, minis: minis);
  }

  Future<void> setHiddenKeys(Iterable<String> keys, bool on, {Map<String, String>? minis}) {
    final k = keys.toSet();
    return _set(state.copyWith(hidden: on ? {...state.hidden, ...k} : ({...state.hidden}..removeAll(k)), minis: minis));
  }

  Future<GalleryAlbum> createAlbum(String name, {String emoji = '', Iterable<GalleryItem> items = const []}) async {
    await ready;
    final a = GalleryAlbum(
      id: const Uuid().v4().substring(0, 8),
      name: name.trim().isEmpty ? 'Album' : name.trim(),
      emoji: emoji,
      keys: [for (final i in items) i.key],
      minis: {for (final i in items) if (i.mini != null) i.key: i.mini!.data},
      createdAt: DateTime.now(),
    );
    await _set(state.copyWith(albums: [...state.albums, a]));
    return a;
  }

  GalleryAlbum? album(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    return state.albums.where((a) => a.id == idOrName.trim()).firstOrNull ??
        state.albums.where((a) => a.name.toLowerCase() == q).firstOrNull ??
        state.albums.where((a) => a.name.toLowerCase().contains(q)).firstOrNull;
  }

  Future<void> updateAlbum(String id, GalleryAlbum Function(GalleryAlbum) f) => _set(state.copyWith(albums: [for (final a in state.albums) a.id == id ? f(a) : a]));

  Future<int> addToAlbum(String id, Iterable<GalleryItem> items) async {
    var added = 0;
    await updateAlbum(id, (a) {
      final fresh = [for (final i in items) if (!a.keys.contains(i.key)) i];
      added = fresh.length;
      return a.copyWith(keys: [for (final i in fresh) i.key, ...a.keys], minis: {...a.minis, for (final i in fresh) if (i.mini != null) i.key: i.mini!.data});
    });
    return added;
  }

  Future<int> addKeysToAlbum(String id, Iterable<String> keys) async {
    var added = 0;
    await updateAlbum(id, (a) {
      final fresh = [for (final k in keys) if (!a.keys.contains(k)) k];
      added = fresh.length;
      return a.copyWith(keys: [...fresh, ...a.keys]);
    });
    return added;
  }

  Future<void> removeFromAlbum(String id, Iterable<String> keys) {
    final k = keys.toSet();
    return updateAlbum(id, (a) => a.copyWith(keys: [for (final x in a.keys) if (!k.contains(x)) x], minis: {for (final e in a.minis.entries) if (!k.contains(e.key)) e.key: e.value}));
  }

  Future<void> deleteAlbum(String id) => _set(state.copyWith(albums: [for (final a in state.albums) if (a.id != id) a]));
  Future<void> moveAlbum(int from, int to) {
    final list = [...state.albums];
    if (from < 0 || from >= list.length) return Future.value();
    final a = list.removeAt(from);
    list.insert(to.clamp(0, list.length), a);
    return _set(state.copyWith(albums: list));
  }

  Future<void> setColumns(int v) => _set(state.copyWith(columns: v.clamp(2, 6)));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
}

final galleryProvider = NotifierProvider<GalleryStore, GalleryState>(GalleryStore.new);

// ---- the feed ----------------------------------------------------------------

@immutable
class GalleryFeedState {
  const GalleryFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}, this.errors = const {}});
  final Map<String, List<GalleryItem>> bySource;
  final Set<String> loading;
  final Map<String, int> next;
  final Map<String, String> errors;
  bool get anyLoading => loading.isNotEmpty;
  bool hasMore(String k) => (next[k] ?? 1) != 0;
}

class GalleryFeed extends Notifier<GalleryFeedState> {
  @override
  GalleryFeedState build() => const GalleryFeedState();

  Future<void> load(SourceRef s, {bool more = false}) async {
    if (state.loading.contains(s.key) || (more && state.next[s.key] == 0)) return;
    state = GalleryFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next, errors: {...state.errors}..remove(s.key));
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      final page = await loadChatPage(client, s.chatId, filter: const td.SearchMessagesFilterPhotoAndVideo(), from: more ? (state.next[s.key] ?? 0) : 0, limit: 100);
      final found = [for (final m in page.messages) ?GalleryItem.fromMessage(m, s.account, title)];
      final have = more ? (state.bySource[s.key] ?? const <GalleryItem>[]) : const <GalleryItem>[];
      final keys = {for (final i in have) i.key};
      state = GalleryFeedState(
        bySource: {...state.bySource, s.key: [...have, for (final i in found) if (keys.add(i.key)) i]},
        loading: {...state.loading}..remove(s.key),
        next: {...state.next, s.key: page.next},
        errors: state.errors,
      );
    } catch (e) {
      state = GalleryFeedState(bySource: state.bySource, loading: {...state.loading}..remove(s.key), next: state.next, errors: {...state.errors, s.key: '$e'});
    }
  }

  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));

  GalleryItem? byKey(String key) {
    for (final list in state.bySource.values) {
      for (final i in list) {
        if (i.key == key) return i;
      }
    }
    return null;
  }

  /// Items by key, read from their posts when they aren't loaded.
  Future<List<GalleryItem>> fetchMany(List<String> keys) async {
    final out = <String, GalleryItem>{};
    final missing = <String>[];
    for (final k in keys) {
      final i = byKey(k);
      i == null ? missing.add(k) : out[k] = i;
    }
    final byChat = <String, List<int>>{};
    for (final k in missing) {
      final p = parsePostKey(k);
      if (p != null) byChat.putIfAbsent('${p.account}|${p.chatId}', () => []).add(p.messageId);
    }
    for (final e in byChat.entries) {
      final account = e.key.split('|').first;
      final chatId = int.parse(e.key.split('|').last);
      try {
        final client = ref.read(telegramClientFamily(account));
        final title = ref.read(telegramStoreFamily(account)).chat(chatId)?.title ?? '';
        for (var i = 0; i < e.value.length; i += 100) {
          final r = await client.send<td.Messages>(td.GetMessages(chatId: chatId, messageIds: e.value.sublist(i, (i + 100).clamp(0, e.value.length))), limited: true);
          for (final m in r.messages) {
            final g = GalleryItem.fromMessage(m, account, title);
            if (g != null) out[g.key] = g;
          }
        }
      } catch (_) {}
    }
    return [for (final k in keys) ?out[k]];
  }
}

final galleryFeedProvider = NotifierProvider<GalleryFeed, GalleryFeedState>(GalleryFeed.new);

/// Every visible source's items, newest first.
List<GalleryItem> galleryItems(GalleryState g, GalleryFeedState feed, {String? sourceKey, bool? videos, bool hidden = false}) {
  final out = <GalleryItem>[
    for (final s in g.sources)
      if (sourceKey != null ? s.key == sourceKey : !s.hidden)
        for (final i in feed.bySource[s.key] ?? const <GalleryItem>[])
          if (g.hidden.contains(i.key) == hidden && (videos == null || i.video == videos)) i,
  ];
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
