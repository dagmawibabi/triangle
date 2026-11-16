import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../sections/section_kit.dart';
import '../telegram/data/telegram_store.dart';

// Movies: channels and groups that post videos, watched like a mix of a
// streaming service and a video site. Progress, My list, likes and hidden
// videos are kept on this phone; the videos stay in Telegram.

const _videoExt = {'mp4', 'mkv', 'mov', 'webm', 'avi', 'm4v', '3gp', 'ts', 'flv', 'wmv'};

/// A video post.
class Video {
  Video({
    required this.account,
    required this.chatId,
    required this.messageId,
    required this.channel,
    required this.title,
    this.description = '',
    this.seconds = 0,
    this.width = 0,
    this.height = 0,
    this.size = 0,
    required this.date,
    this.views = 0,
    this.thumb,
    this.mini,
    this.file,
    this.fileName = '',
    this.streaming = false,
    this.caption,
  });
  final String account;
  final int chatId;
  final int messageId;
  final String channel;
  final String title;
  final String description;
  final int seconds;
  final int width;
  final int height;
  final int size;
  final DateTime date;
  final int views;
  final td.File? thumb;
  final td.Minithumbnail? mini;
  final td.File? file;
  final String fileName;
  final bool streaming;

  /// The post's words with their links, @mentions and styles.
  final td.FormattedText? caption;

  String get key => postKey(account, chatId, messageId);
  bool get vertical => height > width && width > 0;
  bool get isShort => seconds > 0 && seconds < 180;
  bool get isLong => seconds >= 40 * 60;
  String get quality => height >= 2160 ? '4K' : (height >= 1080 ? 'HD' : (height >= 720 ? '720p' : (height > 0 ? '${height}p' : '')));

  static Video? fromMessage(td.Message m, String account, String channel) {
    final caption = messageText(m);
    String titleFrom(String fileName) {
      final first = caption.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 2, orElse: () => '');
      if (first.isNotEmpty) return first.length > 90 ? '${first.substring(0, 90)}…' : first;
      final dot = fileName.lastIndexOf('.');
      final base = dot > 0 ? fileName.substring(0, dot) : fileName;
      final clean = base.replaceAll(RegExp(r'[._]+'), ' ').trim();
      return clean.isEmpty ? 'Video' : clean;
    }

    final views = m.interactionInfo?.viewCount ?? 0;
    switch (m.content) {
      case td.MessageVideo(:final video, caption: final cap):
        return Video(
          caption: cap,
          account: account,
          chatId: m.chatId,
          messageId: m.id,
          channel: channel,
          title: titleFrom(video.fileName),
          description: caption,
          seconds: video.duration,
          width: video.width,
          height: video.height,
          size: video.video.size > 0 ? video.video.size : video.video.expectedSize,
          date: unixDate(m.date),
          views: views,
          thumb: video.thumbnail?.file,
          mini: video.minithumbnail,
          file: video.video,
          fileName: video.fileName,
          streaming: video.supportsStreaming,
        );
      case td.MessageDocument(:final document, caption: final cap) when document.mimeType.startsWith('video/') || _videoExt.contains(document.fileName.split('.').last.toLowerCase()):
        return Video(
          account: account,
          chatId: m.chatId,
          messageId: m.id,
          channel: channel,
          title: titleFrom(document.fileName),
          caption: cap,
          description: caption,
          size: document.document.size > 0 ? document.document.size : document.document.expectedSize,
          date: unixDate(m.date),
          views: views,
          thumb: document.thumbnail?.file,
          mini: document.minithumbnail,
          file: document.document,
          fileName: document.fileName,
        );
      default:
        return null;
    }
  }

  Map<String, dynamic> describe({WatchProgress? progress}) => {
    'video_key': key,
    'title': title,
    'channel': channel,
    'chat_id': chatId,
    'message_id': messageId,
    if (seconds > 0) 'length_minutes': (seconds / 60).toStringAsFixed(seconds < 600 ? 1 : 0),
    if (quality.isNotEmpty) 'quality': quality,
    if (size > 0) 'size': sizeText(size),
    'posted': date.toIso8601String().substring(0, 10),
    if (views > 0) 'views': views,
    if (progress != null) 'watched_percent': (progress.fraction * 100).round(),
    if (description.isNotEmpty && description != title) 'description': description.length > 300 ? '${description.substring(0, 300)}…' : description,
  };
}

/// How far into a video the person got.
@immutable
class WatchProgress {
  const WatchProgress({required this.key, required this.position, required this.length, required this.at, this.title = '', this.channel = '', this.mini});
  final String key;
  final int position;
  final int length;
  final DateTime at;
  final String title;
  final String channel;
  final String? mini;

  double get fraction => length <= 0 ? 0 : (position / length).clamp(0, 1).toDouble();
  bool get finished => fraction > 0.92;

  Map<String, dynamic> toJson() => {'k': key, 'p': position, 'l': length, 'at': at.millisecondsSinceEpoch, 't': title, 'c': channel, if (mini != null) 'm': mini};
  factory WatchProgress.fromJson(Map j) => WatchProgress(
    key: '${j['k']}',
    position: (j['p'] as num?)?.toInt() ?? 0,
    length: (j['l'] as num?)?.toInt() ?? 0,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
    title: '${j['t'] ?? ''}',
    channel: '${j['c'] ?? ''}',
    mini: j['m'] == null ? null : '${j['m']}',
  );
}

/// A video kept in My list.
@immutable
class SavedVideo {
  const SavedVideo({required this.key, required this.title, required this.channel, this.seconds = 0, this.mini, required this.addedAt});
  final String key;
  final String title;
  final String channel;
  final int seconds;
  final String? mini;
  final DateTime addedAt;

  factory SavedVideo.of(Video v) => SavedVideo(key: v.key, title: v.title, channel: v.channel, seconds: v.seconds, mini: v.mini?.data, addedAt: DateTime.now());

  Map<String, dynamic> toJson() => {'k': key, 't': title, 'c': channel, if (seconds > 0) 's': seconds, if (mini != null) 'm': mini, 'at': addedAt.millisecondsSinceEpoch};
  factory SavedVideo.fromJson(Map j) => SavedVideo(
    key: '${j['k']}',
    title: '${j['t'] ?? 'Video'}',
    channel: '${j['c'] ?? ''}',
    seconds: (j['s'] as num?)?.toInt() ?? 0,
    mini: j['m'] == null ? null : '${j['m']}',
    addedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {'video_key': key, 'title': title, 'channel': channel, if (seconds > 0) 'length_minutes': (seconds / 60).round()};
}

enum VideoSort {
  newest('Newest'),
  oldest('Oldest'),
  views('Most viewed'),
  longest('Longest'),
  shortest('Shortest');

  const VideoSort(this.label);
  final String label;
}

@immutable
class MoviesState {
  const MoviesState({
    this.sources = const [],
    this.progress = const {},
    this.myList = const [],
    this.liked = const {},
    this.hidden = const {},
    this.autoplay = true,
    this.sort = VideoSort.newest,
    this.inDrawer = true,
  });
  final List<SourceRef> sources;
  final Map<String, WatchProgress> progress;
  final List<SavedVideo> myList;
  final Set<String> liked;
  final Set<String> hidden;

  /// Plays the next video when one ends.
  final bool autoplay;
  final VideoSort sort;
  final bool inDrawer;

  bool inList(String key) => myList.any((v) => v.key == key);

  List<WatchProgress> get continueWatching =>
      progress.values.where((p) => !p.finished && p.position > 15).toList()..sort((a, b) => b.at.compareTo(a.at));

  MoviesState copyWith({
    List<SourceRef>? sources,
    Map<String, WatchProgress>? progress,
    List<SavedVideo>? myList,
    Set<String>? liked,
    Set<String>? hidden,
    bool? autoplay,
    VideoSort? sort,
    bool? inDrawer,
  }) => MoviesState(
    sources: sources ?? this.sources,
    progress: progress ?? this.progress,
    myList: myList ?? this.myList,
    liked: liked ?? this.liked,
    hidden: hidden ?? this.hidden,
    autoplay: autoplay ?? this.autoplay,
    sort: sort ?? this.sort,
    inDrawer: inDrawer ?? this.inDrawer,
  );
}

class MoviesStore extends Notifier<MoviesState> {
  static const key = 'movies.v1';
  late Future<void> ready;

  @override
  MoviesState build() {
    ready = _load();
    return const MoviesState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = MoviesState(
        sources: [for (final s in (j['sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        progress: {for (final p in (j['progress'] as List? ?? const [])) if (p is Map) '${p['k']}': WatchProgress.fromJson(p)},
        myList: [for (final s in (j['my_list'] as List? ?? const [])) if (s is Map) SavedVideo.fromJson(s)],
        liked: {for (final s in (j['liked'] as List? ?? const [])) '$s'},
        hidden: {for (final s in (j['hidden'] as List? ?? const [])) '$s'},
        autoplay: j['autoplay'] != false,
        sort: VideoSort.values.asNameMap()['${j['sort']}'] ?? VideoSort.newest,
        inDrawer: j['in_drawer'] != false,
      );
    } catch (e) {
      debugPrint('[Movies] $e');
    }
  }

  Future<void> _set(MoviesState s) async {
    state = s;
    final progress = s.progress.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'sources': [for (final x in s.sources) x.toJson()],
        'progress': [for (final x in progress.take(500)) x.toJson()],
        'my_list': [for (final x in s.myList) x.toJson()],
        'liked': s.liked.toList(),
        'hidden': s.hidden.toList(),
        'autoplay': s.autoplay,
        'sort': s.sort.name,
        'in_drawer': s.inDrawer,
      }),
    );
  }

  Future<void> setSources(List<SourceRef> v) => _set(state.copyWith(sources: v));
  Future<void> addSources(Iterable<SourceRef> v) {
    final have = {for (final s in state.sources) s.key};
    return _set(state.copyWith(sources: [...state.sources, for (final s in v) if (have.add(s.key)) s]));
  }

  Future<void> removeSource(String k) => _set(state.copyWith(sources: [for (final s in state.sources) if (s.key != k) s]));
  Future<void> setSourceHidden(String k, bool v) => _set(state.copyWith(sources: [for (final s in state.sources) s.key == k ? s.copyWith(hidden: v) : s]));
  Future<void> moveSource(int from, int to) {
    final list = [...state.sources];
    if (from < 0 || from >= list.length) return Future.value();
    final s = list.removeAt(from);
    list.insert(to.clamp(0, list.length), s);
    return _set(state.copyWith(sources: list));
  }

  Timer? _later;

  /// Remembers where [v] is up to; saved at most every few seconds.
  void saveProgress(Video v, int position, int length) {
    state = state.copyWith(progress: {
      ...state.progress,
      v.key: WatchProgress(key: v.key, position: position, length: length > 0 ? length : v.seconds, at: DateTime.now(), title: v.title, channel: v.channel, mini: v.mini?.data),
    });
    _later?.cancel();
    _later = Timer(const Duration(seconds: 4), () => _set(state));
  }

  Future<void> clearProgress(String k) => _set(state.copyWith(progress: {...state.progress}..remove(k)));
  Future<void> clearHistory() => _set(state.copyWith(progress: const {}));

  Future<bool> toggleList(SavedVideo v) async {
    if (state.inList(v.key)) {
      await _set(state.copyWith(myList: [for (final x in state.myList) if (x.key != v.key) x]));
      return false;
    }
    await _set(state.copyWith(myList: [v, ...state.myList]));
    return true;
  }

  Future<bool> toggleLike(String k) async {
    final on = !state.liked.contains(k);
    await _set(state.copyWith(liked: on ? {...state.liked, k} : ({...state.liked}..remove(k))));
    return on;
  }

  Future<void> setHidden(String k, bool v) => _set(state.copyWith(hidden: v ? {...state.hidden, k} : ({...state.hidden}..remove(k))));
  Future<void> setAutoplay(bool v) => _set(state.copyWith(autoplay: v));
  Future<void> setSort(VideoSort v) => _set(state.copyWith(sort: v));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
}

final moviesProvider = NotifierProvider<MoviesStore, MoviesState>(MoviesStore.new);

// ---- the feed ----------------------------------------------------------------

@immutable
class VideoFeedState {
  const VideoFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}, this.errors = const {}});
  final Map<String, List<Video>> bySource;
  final Set<String> loading;

  /// Per source and kind (`key|v` videos, `key|d` video files): where the
  /// next page starts, 0 when done.
  final Map<String, int> next;
  final Map<String, String> errors;

  bool get anyLoading => loading.isNotEmpty;
  bool hasMore(String sourceKey) => (next['$sourceKey|v'] ?? 1) != 0 || (next['$sourceKey|d'] ?? 1) != 0;
}

class VideoFeed extends Notifier<VideoFeedState> {
  static final _memory = FeedMemory('videos');

  @override
  VideoFeedState build() => const VideoFeedState();

  Future<void> load(SourceRef s, {bool more = false}) async {
    if (state.loading.contains(s.key)) return;
    // Loaded before this run: a refresh adds what's new to what's there
    // (keeping what was paged in and where paging left off).
    final refreshing = !more && state.next.containsKey('${s.key}|v');
    state = VideoFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next, errors: {...state.errors}..remove(s.key));
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      // First time this run: what it showed last time, at once.
      if (!more && !state.bySource.containsKey(s.key)) {
        final kept = [for (final m in await _memory.recall(client, s)) ?Video.fromMessage(m, s.account, title)];
        if (kept.isNotEmpty && !state.bySource.containsKey(s.key)) {
          state = VideoFeedState(bySource: {...state.bySource, s.key: kept}, loading: state.loading, next: state.next, errors: state.errors);
        }
      }
      final next = {...state.next};
      final found = <Video>[];
      for (final (kind, filter) in const [('v', td.SearchMessagesFilterVideo()), ('d', td.SearchMessagesFilterDocument())]) {
        final k = '${s.key}|$kind';
        if (more && next[k] == 0) continue;
        final page = await loadChatPage(client, s.chatId, filter: filter, from: more ? (next[k] ?? 0) : 0, limit: kind == 'v' ? 40 : 60);
        for (final m in page.messages) {
          final v = Video.fromMessage(m, s.account, title);
          if (v != null) found.add(v);
        }
        if (!refreshing || !next.containsKey(k)) next[k] = page.next;
      }
      final have = more || refreshing ?(state.bySource[s.key] ?? const <Video>[]) : const <Video>[];
      final keys = {for (final v in have) v.key};
      final all = [...have, for (final v in found) if (keys.add(v.key)) v]..sort((a, b) => b.messageId.compareTo(a.messageId));
      state = VideoFeedState(bySource: {...state.bySource, s.key: all}, loading: {...state.loading}..remove(s.key), next: next, errors: state.errors);
      unawaited(_memory.remember(s, all.map((v) => v.messageId)));
    } catch (e) {
      state = VideoFeedState(bySource: state.bySource, loading: {...state.loading}..remove(s.key), next: state.next, errors: {...state.errors, s.key: '$e'});
    }
  }

  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));

  /// Pull to refresh: what's loaded is mixed into a new order at once, then
  /// what's new is fetched in the background and mixed in further down, so
  /// the feed neither waits on the network nor jumps.
  void refreshMixed() {
    final shuffle = ref.read(videoShuffleProvider.notifier);
    final m = ref.read(moviesProvider);
    shuffle.reshuffle(allVideos(m, state).map((v) => v.key));
    final account = ref.read(activeAccountIdProvider);
    unawaited(
      loadAll(m.sources.where((s) => s.account == account), refresh: true)
          .then((_) => shuffle.mixIn(allVideos(ref.read(moviesProvider), state).map((v) => v.key))),
    );
  }

  Video? byKey(String key) {
    for (final list in state.bySource.values) {
      for (final v in list) {
        if (v.key == key) return v;
      }
    }
    return null;
  }

  Future<Video?> fetch(String key) async {
    final have = byKey(key);
    if (have != null) return have;
    final k = parsePostKey(key);
    if (k == null) return null;
    final m = await ref.read(telegramClientFamily(k.account)).send<td.Message>(td.GetMessage(chatId: k.chatId, messageId: k.messageId), limited: true);
    return Video.fromMessage(m, k.account, ref.read(telegramStoreFamily(k.account)).chat(k.chatId)?.title ?? '');
  }
}

final videoFeedProvider = NotifierProvider<VideoFeed, VideoFeedState>(VideoFeed.new);

/// The order a refresh mixed the feeds into: a place for each video that
/// was loaded then. Videos loaded later (scrolling further) come after
/// them in their usual order, so the mix stays put instead of reshuffling
/// as more arrive. Empty: no mix (sorted).
class VideoShuffle extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  /// Mixes [keys] (everything loaded now) into a new order.
  void reshuffle(Iterable<String> keys) {
    final list = keys.toSet().toList()..shuffle(math.Random());
    state = {for (final (i, k) in list.indexed) k: i};
  }

  /// Places [keys] not in the mix yet at random spots past the first
  /// [keep], so what's on screen stays put.
  void mixIn(Iterable<String> keys, {int keep = 8}) {
    if (state.isEmpty) return;
    final fresh = [for (final k in keys.toSet()) if (!state.containsKey(k)) k];
    if (fresh.isEmpty) return;
    final order = [...state.keys]..sort((a, b) => state[a]!.compareTo(state[b]!));
    final rnd = math.Random();
    for (final k in fresh) {
      final from = math.min(order.length, keep);
      order.insert(from + rnd.nextInt(order.length - from + 1), k);
    }
    state = {for (final (i, k) in order.indexed) k: i};
  }

  void clear() => state = const {};
}

final videoShuffleProvider = NotifierProvider<VideoShuffle, Map<String, int>>(VideoShuffle.new);

/// [list] in the refresh's mixed order ([rank]); unmixed ones after.
List<Video> shuffledBy(List<Video> list, Map<String, int> rank) {
  if (rank.isEmpty) return list;
  final mixed = [for (final v in list) if (rank.containsKey(v.key)) v]..sort((a, b) => rank[a.key]!.compareTo(rank[b.key]!));
  return [...mixed, for (final v in list) if (!rank.containsKey(v.key)) v];
}

/// Every visible source's videos (or one source's), filtered and sorted.
/// [shape] picks 'wide' (regular videos) or 'tall' (shorts) only.
List<Video> allVideos(MoviesState m, VideoFeedState feed, {String? sourceKey, String query = '', String length = 'any', bool includeHidden = false, VideoSort? sort, String shape = 'any'}) {
  final q = query.toLowerCase().trim();
  final out = <Video>[
    for (final s in m.sources)
      if (sourceKey != null ? s.key == sourceKey : !s.hidden)
        for (final v in feed.bySource[s.key] ?? const <Video>[])
          if ((includeHidden || !m.hidden.contains(v.key)) &&
              (shape == 'any' || (shape == 'tall') == v.vertical) &&
              (q.isEmpty || '${v.title} ${v.description} ${v.channel} ${v.fileName}'.toLowerCase().contains(q)) &&
              switch (length) {
                'short' => v.seconds > 0 && v.seconds < 240,
                'medium' => v.seconds >= 240 && v.seconds < 1200,
                'long' => v.seconds >= 1200 || (v.seconds == 0 && v.size > 300 << 20),
                _ => true,
              })
            v,
  ];
  out.sort(switch (sort ?? m.sort) {
    VideoSort.newest => (a, b) => b.date.compareTo(a.date),
    VideoSort.oldest => (a, b) => a.date.compareTo(b.date),
    VideoSort.views => (a, b) => b.views.compareTo(a.views),
    VideoSort.longest => (a, b) => b.seconds.compareTo(a.seconds),
    VideoSort.shortest => (a, b) => a.seconds.compareTo(b.seconds),
  });
  return out;
}
