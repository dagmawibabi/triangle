import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../../core/net/http_cache.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../assistant/notifications.dart' show appNotifierProvider;
import '../media/audio_center.dart';
import '../playlists/playlist_sources.dart';
import '../playlists/playlists.dart';
import '../sections/section_kit.dart' show SourceRef, pooled;
import '../telegram/data/telegram_store.dart';
import 'podcast_models.dart';

const _ua = {'User-Agent': 'Triangle/1.0 (podcast player)'};

final _breaks = RegExp(r'<\s*(br|/p|/div|/li|/h\d)\b[^>]*>', caseSensitive: false);
final _tags = RegExp(r'<[^>]*>');
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');
final _spaces = RegExp(r'[ \t ]+');
final _blankLines = RegExp(r'\n\s*\n\s*');
const _named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'mdash': '—', 'ndash': '–', 'hellip': '…', 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“', 'copy': '©'};

/// HTML show notes as plain text. A light pass (tags out, entities
/// decoded) rather than a full HTML parse: a long-running show has
/// hundreds of episodes, and parsing each one's notes made feeds slow.
/// Very long notes are cut, since only the first part is ever shown.
String _plain(String s, {int max = 6000}) {
  if (s.length > max * 2) s = s.substring(0, max * 2);
  if (s.contains('<')) s = s.replaceAll(_breaks, '\n').replaceAll(_tags, '');
  if (s.contains('&')) {
    s = s.replaceAllMapped(_entity, (m) {
      final e = m[1]!;
      if (e.startsWith('#x')) return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 32);
      if (e.startsWith('#')) return String.fromCharCode(int.tryParse(e.substring(1)) ?? 32);
      return _named[e.toLowerCase()] ?? m[0]!;
    });
  }
  s = s.replaceAll(_spaces, ' ').replaceAll(_blankLines, '\n\n').trim();
  return s.length > max ? '${s.substring(0, max)}…' : s;
}

/// Feeds are parsed in a background isolate when big: a long-running show's
/// feed is megabytes of XML.
Podcast? _parseInIsolate((String, String) a) => PodcastStore.parseFeed(a.$1, a.$2);

/// A JSON file read and decoded off the UI thread: the store's files hold
/// every followed show's episodes, megabytes with many shows.
Future<Map?> _readJsonFile(String path) => Isolate.run(() async {
  final f = File(path);
  if (!await f.exists()) return null;
  final j = jsonDecode(await f.readAsString());
  return j is Map ? j : null;
});

typedef _Saved = ({Map j, List<Podcast> subs, Map<String, EpisodeState> states, List<Episode> queue});

/// podcasts.json, read and turned into shows and episodes in the
/// background.
Future<_Saved?> _readStore(String path) => Isolate.run(() async {
  final f = File(path);
  if (!await f.exists()) return null;
  final j = jsonDecode(await f.readAsString());
  if (j is! Map) return null;
  final states = <String, EpisodeState>{};
  for (final e in ((j['states'] as Map?) ?? const {}).entries) {
    if (e.value is! Map) continue;
    final st = EpisodeState.fromJson(e.value as Map);
    if (st.meaningful) states['${e.key}'] = st;
  }
  final subs = [for (final s in (j['subscriptions'] as List? ?? const [])) if (s is Map) Podcast.fromJson(s)];
  final queue = [for (final e in (j['queue'] as List? ?? const [])) if (e is Map) Episode.fromJson(e)];
  // Only the small settings travel back as JSON.
  j
    ..remove('subscriptions')
    ..remove('states')
    ..remove('queue');
  return (j: j, subs: subs, states: states, queue: queue);
});

/// Progress of an OPML import. [total] counts only shows not followed yet.
class OpmlImport {
  OpmlImport({required this.total, required this.already});
  final int total;
  final int already;
  int done = 0;
  int added = 0;
  final List<String> failed = [];
  bool running = true;
  bool cancelled = false;
}

/// Subscriptions, listening history, the queue and downloaded episodes,
/// played through the app's one player.
class PodcastStore extends ChangeNotifier {
  PodcastStore(this._ref) {
    ready = _load();
    final audio = _ref.read(audioCenterProvider);
    audio.addListener(_onAudio);
    audio.onTrackEnded.add(_ended);
    _timer = Timer.periodic(const Duration(hours: 4), (_) => refreshAll(quiet: true));
  }

  final Ref _ref;
  late final Future<void> ready;
  Timer? _timer;

  final List<Podcast> subscriptions = [];
  final Map<String, EpisodeState> states = {};
  final List<Episode> queue = [];
  final Map<String, UserMark> showMarks = {};
  final Map<String, String> showSorts = {};

  // Settings.
  String episodeSort = 'newest';
  String chartCountry = 'us';
  bool notifyNew = true;
  bool deletePlayedDownloads = false;
  bool inDrawer = true;
  double talkSpeed = 1;

  final Map<String, Podcast> _feeds = {};
  final Map<String, Future<Podcast?>> _loading = {};
  bool refreshing = false;
  bool unreachable = false;
  DateTime? _lastRefresh;
  static const _refreshEvery = Duration(minutes: 15);

  /// Download progress by episode guid (0..1, or -1 while starting).
  final Map<String, double> downloads = {};
  final Set<String> _cancel = {};

  OpmlImport? opml;

  // ---- storage ----------------------------------------------------------------------

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/podcasts.json');

  Future<void> _load() async {
    try {
      final saved = await _readStore((await _file()).path);
      if (saved != null) _apply(saved);
    } catch (e) {
      debugPrint('[Podcasts] load: $e');
    }
    await _loadRecent();
    notifyListeners();
  }

  void _apply(_Saved saved) {
    final j = saved.j;
    subscriptions.addAll(saved.subs);
    states.addAll(saved.states);
    queue.addAll(saved.queue);
    for (final e in ((j['showMarks'] as Map?) ?? const {}).entries) {
      showMarks['${e.key}'] = UserMark.fromJson(e.value);
    }
    for (final e in ((j['showSorts'] as Map?) ?? const {}).entries) {
      showSorts['${e.key}'] = '${e.value}';
    }
    episodeSort = '${j['episodeSort'] ?? 'newest'}';
    chartCountry = '${j['chartCountry'] ?? 'us'}';
    notifyNew = j['notifyNew'] != false;
    deletePlayedDownloads = j['deletePlayed'] == true;
    inDrawer = j['inDrawer'] != false;
    talkSpeed = ((j['speed'] ?? 1) as num).toDouble();
    _ref.read(audioCenterProvider).talkSpeed = talkSpeed;
    for (final s in subscriptions) {
      _feeds[s.feedUrl] = s;
    }
  }

  Timer? _pending;

  void _persist({bool notify = true}) {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 600), () async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');
        // Shows and episodes are written from text kept per episode, so a
        // save (every few seconds while something plays) doesn't encode
        // thousands of episodes again; only states worth keeping are saved.
        final rest = jsonEncode({
          'showMarks': {for (final e in showMarks.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
          'showSorts': showSorts,
          'episodeSort': episodeSort,
          'chartCountry': chartCountry,
          'notifyNew': notifyNew,
          'deletePlayed': deletePlayedDownloads,
          'inDrawer': inDrawer,
          'speed': talkSpeed,
        });
        final out = StringBuffer('{"subscriptions":[')
          ..writeAll([for (final s in subscriptions) s.json], ',')
          ..write('],"states":{')
          ..writeAll([for (final e in states.entries) if (e.value.meaningful) '${jsonEncode(e.key)}:${e.value.json}'], ',')
          ..write('},"queue":[')
          ..writeAll([for (final e in queue) e.json], ',')
          ..write('],')
          ..write(rest.substring(1));
        await tmp.writeAsString(out.toString());
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('[Podcasts] save: $e');
      }
    });
    if (notify) notifyListeners();
  }

  void setSettings({String? sort, String? country, bool? notify, bool? deletePlayed, bool? drawer}) {
    episodeSort = sort ?? episodeSort;
    chartCountry = country ?? chartCountry;
    notifyNew = notify ?? notifyNew;
    deletePlayedDownloads = deletePlayed ?? deletePlayedDownloads;
    inDrawer = drawer ?? inDrawer;
    _persist();
  }

  // ---- the network ------------------------------------------------------------------

  /// Directory answers and feeds, kept on disk: charts and searches open
  /// instantly after a restart, and a feed that hasn't changed isn't
  /// downloaded again (the server is asked with ETag / Last-Modified).
  final HttpCache _http = HttpCache('podcasts', maxEntries: 400);

  Future<CacheResult?> _get(String url, {Duration ttl = const Duration(hours: 6), Duration timeout = const Duration(seconds: 20), bool force = false, bool staleFirst = false}) async {
    final r = await _http.get(url, ttl: ttl, timeout: timeout, headers: _ua, force: force, staleFirst: staleFirst && !force);
    unreachable = _http.offline;
    return r;
  }

  /// Lists from the directory: a kept copy shows at once (refreshed behind
  /// the scenes when old) unless [force].
  Future<dynamic> _json(String url, {Duration ttl = const Duration(hours: 6), bool force = false}) async {
    final b = (await _get(url, ttl: ttl, force: force, staleFirst: true))?.body;
    if (b == null) return null;
    try {
      return jsonDecode(b);
    } catch (_) {
      return null;
    }
  }

  // ---- the directory ----------------------------------------------------------------

  PodcastHit _hit(Map r) => PodcastHit(
    id: '${r['collectionId'] ?? r['id'] ?? ''}',
    title: '${r['collectionName'] ?? r['name'] ?? ''}',
    author: '${r['artistName'] ?? ''}',
    artwork: (r['artworkUrl600'] ?? r['artworkUrl100'])?.toString().replaceAll('100x100bb', '600x600bb'),
    feedUrl: r['feedUrl'] as String?,
    genre: '${r['primaryGenreName'] ?? ((r['genres'] as List?)?.whereType<Map>().firstOrNull?['name']) ?? ''}',
    episodes: (r['trackCount'] as num?)?.toInt() ?? 0,
  );

  /// Apple's podcast directory: free, no key.
  Future<List<PodcastHit>> search(String term, {int? genre, String? country, bool force = false}) async {
    final q = Uri.encodeQueryComponent(term.trim().isEmpty ? 'podcast' : term.trim());
    final j = await _json('https://itunes.apple.com/search?media=podcast&entity=podcast&limit=50&term=$q&country=${country ?? chartCountry}${genre == null ? '' : '&genreId=$genre'}', force: force);
    final list = (j is Map ? j['results'] : null) as List? ?? const [];
    return [for (final r in list.whereType<Map>()) if (r['feedUrl'] != null) _hit(r)];
  }

  /// Today's top shows in [country].
  Future<List<PodcastHit>> top({String? country, bool force = false}) async {
    final j = await _json('https://rss.marketingtools.apple.com/api/v2/${country ?? chartCountry}/podcasts/top/50/podcasts.json', ttl: const Duration(hours: 3), force: force);
    final feed = j is Map ? j['feed'] : null;
    final list = (feed is Map ? feed['results'] : null) as List? ?? const [];
    final hits = [for (final r in list.whereType<Map>()) _hit(r)];
    unawaited(_lookupFeeds(hits));
    return hits;
  }

  /// Chart entries come without feed addresses: they're asked for all at
  /// once, in the background, so opening one goes straight to its feed
  /// instead of waiting on a lookup first.
  Future<void> _lookupFeeds(List<PodcastHit> hits) async {
    final ids = [for (final h in hits) if (knownFeedFor(h) == null && h.id.isNotEmpty) h.id];
    if (ids.isEmpty) return;
    try {
      for (var i = 0; i < ids.length; i += 100) {
        final batch = ids.skip(i).take(100).join(',');
        final j = await _json('https://itunes.apple.com/lookup?id=$batch&entity=podcast', ttl: const Duration(days: 7));
        for (final r in ((j is Map ? j['results'] : null) as List? ?? const []).whereType<Map>()) {
          final id = '${r['collectionId'] ?? ''}';
          final url = r['feedUrl'];
          if (id.isNotEmpty && url is String && url.isNotEmpty) _feedIds[id] = url;
        }
      }
      _saveRecent();
    } catch (e) {
      debugPrint('[Podcasts] lookup: $e');
    }
  }

  /// Chart entries come without a feed address; the lookup API has it.
  Future<String?> feedFor(PodcastHit h) async {
    if (knownFeedFor(h) case final known?) return known;
    final j = await _json('https://itunes.apple.com/lookup?id=${h.id}&entity=podcast', ttl: const Duration(days: 7));
    final r = ((j is Map ? j['results'] : null) as List?)?.whereType<Map>().firstOrNull;
    final url = r?['feedUrl'] as String?;
    if (url != null && h.id.isNotEmpty) {
      _feedIds[h.id] = url;
      _saveRecent();
    }
    return url;
  }

  /// [h]'s feed address without asking the network, when it's known: it
  /// came with the entry, or the show was looked up before.
  String? knownFeedFor(PodcastHit h) => h.feedUrl ?? _feedIds[h.id];

  // ---- shows opened recently ---------------------------------------------------------

  /// Shows opened without following them, newest last, kept in the cache
  /// folder so they open instantly next time too.
  static const _recentMax = 30;
  final List<String> _recentShows = [];

  /// Directory ids → feed addresses (chart entries come without one).
  final Map<String, String> _feedIds = {};

  /// Feeds parsed since the app started: an unchanged download needn't be
  /// parsed again. (Kept copies hold only the newest episodes.)
  final Set<String> _parsed = {};

  Future<File> _recentFile() async => File('${(await getApplicationCacheDirectory()).path}/podcast_shows.json');

  Future<void> _loadRecent() async {
    try {
      final j = await _readJsonFile((await _recentFile()).path);
      if (j == null) return;
      for (final e in ((j['ids'] as Map?) ?? const {}).entries) {
        _feedIds['${e.key}'] = '${e.value}';
      }
      for (final m in (j['shows'] as List? ?? const []).whereType<Map>()) {
        final pod = Podcast.fromJson(m);
        if (pod.feedUrl.isEmpty) continue;
        _recentShows.add(pod.feedUrl);
        _feeds.putIfAbsent(pod.feedUrl, () => pod);
      }
    } catch (e) {
      debugPrint('[Podcasts] recent shows: $e');
    }
  }

  Timer? _recentPending;

  void _saveRecent() {
    _recentPending?.cancel();
    _recentPending = Timer(const Duration(seconds: 2), () async {
      try {
        final shows = [
          for (final url in _recentShows)
            if (_feeds[url] case final p? when !subscribed(url)) p.json,
        ];
        final ids = _feedIds.entries.toList();
        final idsJson = jsonEncode({for (final e in ids.skip(math.max(0, ids.length - 500))) e.key: e.value});
        await (await _recentFile()).writeAsString('{"shows":[${shows.join(',')}],"ids":$idsJson}');
      } catch (e) {
        debugPrint('[Podcasts] save recent shows: $e');
      }
    });
  }

  /// Settings → Cache: drops the directory answers, kept feeds and the
  /// shows opened without following them. Followed shows stay.
  Future<void> clearCache() async {
    _recentPending?.cancel();
    await _http.clear();
    for (final url in _recentShows) {
      if (!subscribed(url)) _feeds.remove(url);
    }
    _recentShows.clear();
    _feedIds.clear();
    _parsed.clear();
    try {
      final f = await _recentFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  void _rememberShow(Podcast p) {
    if (p.isTelegram || subscribed(p.feedUrl)) return;
    _recentShows
      ..remove(p.feedUrl)
      ..add(p.feedUrl);
    while (_recentShows.length > _recentMax) {
      _recentShows.removeAt(0);
    }
    _saveRecent();
  }

  // ---- feeds ------------------------------------------------------------------------

  Podcast? cached(String feedUrl) => _feeds[feedUrl];

  /// Loads a show: an RSS feed, or a Telegram channel's audio posts.
  /// With [refresh], the feed is checked (a kept copy younger than half an
  /// hour counts); [force] always asks the server. Without [full], a feed
  /// whose text hasn't changed isn't read again (background checks: the
  /// saved newest episodes are enough there); opening a show reads it all.
  Future<Podcast?> feed(String url, {bool refresh = false, bool force = false, bool full = true}) {
    final have = _feeds[url];
    if (!refresh && have != null && have.episodes.isNotEmpty) return Future.value(have);
    final key = full ? url : '~$url';
    return _loading[key] ??= (url.startsWith('tg:') ? _telegramShow(url) : _fetchFeed(url, force: force, full: full)).whenComplete(() {
      _loading.remove(key);
    });
  }

  /// Parses off the UI thread unless the feed is tiny.
  static Future<Podcast?> _parse(String url, String body) async {
    try {
      return body.length < 40000 ? parseFeed(url, body) : await compute(_parseInIsolate, (url, body));
    } catch (e) {
      debugPrint('[Podcasts] parse $url: $e');
      return null;
    }
  }

  Future<Podcast?> _fetchFeed(String url, {bool force = false, bool full = true}) async {
    // A copy kept on disk shows at once (episodes and all) while the
    // server is asked behind it; the page updates when that answers.
    if (!force && !_parsed.contains(url) && (_feeds[url]?.episodes.isEmpty ?? true)) {
      final kept = await _http.peek(url);
      if (kept != null) {
        final parsed = await _parse(url, kept.body);
        if (parsed != null && parsed.episodes.isNotEmpty) {
          _parsed.add(url);
          final pod = _absorb(parsed);
          _rememberShow(pod);
          if (!kept.freshFor(const Duration(minutes: 30))) {
            unawaited(_refreshFeed(url).then((_) => notifyListeners(), onError: (_) {}));
          }
          return pod;
        }
      }
    }
    return _refreshFeed(url, force: force, full: full);
  }

  Future<Podcast?> _refreshFeed(String url, {bool force = false, bool full = true}) async {
    // Long-running shows' feeds are megabytes: give slow connections time.
    final res = await _get(url, ttl: const Duration(minutes: 30), timeout: const Duration(seconds: 75), force: force);
    if (res == null) return _feeds[url];
    // Same text as the last one parsed: nothing to do. In a background
    // check, the same text as the kept copy needn't be read either: the
    // saved episodes already say what's new. (Before, every followed feed
    // was read in full on each start of the app.)
    final have = _feeds[url];
    if (!res.changed && have != null && (_parsed.contains(url) || (!full && have.episodes.isNotEmpty))) return have;
    final parsed = await _parse(url, res.body);
    if (parsed == null) return _feeds[url];
    _parsed.add(url);
    final pod = _absorb(parsed);
    _rememberShow(pod);
    return pod;
  }

  /// Takes a freshly read show in: a subscribed one keeps its place and is
  /// saved again.
  Podcast _absorb(Podcast parsed) {
    final sub = subscriptions.where((s) => s.feedUrl == parsed.feedUrl).firstOrNull;
    if (sub != null) {
      sub
        ..title = parsed.title
        ..author = parsed.author
        ..description = parsed.description
        ..imageUrl = parsed.imageUrl ?? sub.imageUrl
        ..categories = parsed.categories
        ..episodes = parsed.episodes
        ..updatedAt = DateTime.now();
      _persist();
      return sub;
    }
    return _feeds[parsed.feedUrl] = parsed;
  }

  /// RSS 2.0 with the iTunes extensions most feeds use.
  static Podcast? parseFeed(String url, String body) {
    XmlDocument? doc;
    // A byte-order mark or whitespace before the declaration breaks the
    // parser, and some feeds use HTML entities XML doesn't know.
    final start = body.indexOf('<');
    if (start > 0) body = body.substring(start);
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      try {
        doc = XmlDocument.parse(body.replaceAllMapped(RegExp(r'&([a-zA-Z]+);'), (m) => const {'amp', 'lt', 'gt', 'quot', 'apos'}.contains(m[1]) ? m[0]! : (_named[m[1]!.toLowerCase()] ?? ' ')));
      } catch (e) {
        debugPrint('[Podcasts] feed $url: $e');
        return null;
      }
    }
    final ch = doc.findAllElements('channel').firstOrNull;
    if (ch == null) return null;
    XmlElement? el(XmlElement e, String name) => e.childElements.where((c) => c.name.qualified == name).firstOrNull;
    String txt(XmlElement e, String name) => el(e, name)?.innerText.trim() ?? '';
    String? img(XmlElement e) => el(e, 'itunes:image')?.getAttribute('href') ?? el(e, 'image')?.childElements.where((c) => c.name.local == 'url').firstOrNull?.innerText.trim();
    final title = _plain(txt(ch, 'title'));
    final image = img(ch);
    final episodes = <Episode>[];
    for (final it in ch.childElements.where((c) => c.name.local == 'item')) {
      final enc = el(it, 'enclosure');
      final audio = enc?.getAttribute('url')?.trim() ?? '';
      if (audio.isEmpty) continue;
      if ((enc?.getAttribute('type') ?? '').startsWith('video/')) continue;
      var desc = txt(it, 'content:encoded');
      if (desc.isEmpty) desc = txt(it, 'description');
      if (desc.isEmpty) desc = txt(it, 'itunes:summary');
      final guid = txt(it, 'guid');
      final link = txt(it, 'link');
      episodes.add(Episode(
        guid: guid.isNotEmpty ? guid : audio,
        feedUrl: url,
        title: _plain(txt(it, 'title')),
        audioUrl: audio,
        description: _plain(desc),
        published: parseRssDate(txt(it, 'pubDate')),
        durationMs: parseDuration(txt(it, 'itunes:duration')) * 1000,
        imageUrl: img(it),
        link: link.isEmpty ? null : link,
        podcastTitle: title,
        podcastImage: image,
      ));
    }
    episodes.sort((a, b) => (b.published ?? DateTime(1970)).compareTo(a.published ?? DateTime(1970)));
    return Podcast(
      feedUrl: url,
      title: title,
      author: _plain(txt(ch, 'itunes:author').isNotEmpty ? txt(ch, 'itunes:author') : txt(ch, 'managingEditor')),
      description: _plain(txt(ch, 'description').isNotEmpty ? txt(ch, 'description') : txt(ch, 'itunes:summary')),
      imageUrl: image,
      link: txt(ch, 'link').isEmpty ? null : txt(ch, 'link'),
      categories: ch.childElements.where((c) => c.name.qualified == 'itunes:category').map((c) => c.getAttribute('text') ?? '').where((s) => s.isNotEmpty).toSet().toList(),
      episodes: episodes,
      updatedAt: DateTime.now(),
    );
  }

  /// "Tue, 05 Nov 2024 09:30:00 +0000" and its GMT / EST cousins.
  static DateTime? parseRssDate(String s) {
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?').firstMatch(s);
    if (m == null) return DateTime.tryParse(s.trim());
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final mon = months.indexOf(m[2]!.toLowerCase()) + 1;
    if (mon == 0) return null;
    var d = DateTime.utc(int.parse(m[3]!), mon, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.tryParse(m[6] ?? '') ?? 0);
    final z = m[7] ?? '';
    const zones = {'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5, 'MST': -7, 'MDT': -6, 'PST': -8, 'PDT': -7};
    if (z.startsWith('+') || z.startsWith('-')) {
      final sign = z.startsWith('-') ? -1 : 1;
      d = d.subtract(Duration(hours: sign * int.parse(z.substring(1, 3)), minutes: sign * int.parse(z.substring(3, 5))));
    } else if (zones[z] != null) {
      d = d.subtract(Duration(hours: zones[z]!));
    }
    return d.toLocal();
  }

  /// "1:02:03", "62:03" or "3723" → seconds.
  static int parseDuration(String s) {
    s = s.trim();
    if (s.isEmpty) return 0;
    if (s.contains(':')) return s.split(':').map((x) => int.tryParse(x.trim()) ?? 0).fold(0, (a, x) => a * 60 + x);
    return double.tryParse(s)?.round() ?? 0;
  }

  // ---- Telegram channels as shows ----------------------------------------------------

  static String telegramShowId(String account, int chatId) => 'tg:$account:$chatId';

  /// A channel's songs, audio files and voice posts, newest first, as a show.
  Future<Podcast?> _telegramShow(String url) async {
    final parts = url.split(':');
    if (parts.length < 3) return null;
    final chatId = int.tryParse(parts.last);
    final account = parts.sublist(1, parts.length - 1).join(':');
    if (chatId == null) return null;
    try {
      final client = _ref.read(telegramClientFamily(account));
      final store = _ref.read(telegramStoreFamily(account));
      final chat = store.chat(chatId);
      final tracks = <PlaylistTrack>[];
      for (final type in TgAudioType.values) {
        final page = await searchTelegramAudio(client, store, account, type: type, chatId: chatId, limit: 100);
        tracks.addAll(page.tracks);
      }
      final seen = <String>{};
      final eps = [
        for (final t in tracks)
          if (seen.add(t.key))
            Episode(
              guid: t.key,
              feedUrl: url,
              title: t.title,
              audioUrl: '',
              description: t.fileName ?? '',
              published: t.postedAt,
              durationMs: t.seconds * 1000,
              podcastTitle: chat?.title ?? t.chatTitle ?? 'Telegram',
              tg: t,
            ),
      ]..sort((a, b) => (b.published ?? DateTime(1970)).compareTo(a.published ?? DateTime(1970)));
      // Keep covers already found for episodes read before.
      final before = {for (final e in _feeds[url]?.episodes ?? const <Episode>[]) e.guid: e.imageUrl};
      final withArt = [for (final e in eps) before[e.guid] != null ? e.copyWith(imageUrl: before[e.guid]) : (e.tg?.artPath != null ? e.copyWith(imageUrl: e.tg!.artPath) : e)];
      final pod = _absorb(Podcast(feedUrl: url, title: chat?.title ?? 'Telegram channel', author: 'Telegram', description: '', episodes: withArt, updatedAt: DateTime.now()));
      unawaited(_fillTelegramArt(url));
      return pod;
    } catch (e) {
      debugPrint('[Podcasts] telegram: $e');
      return _feeds[url];
    }
  }

  /// Each Telegram episode's own album art, saved on the phone, newest
  /// first. Episodes without one show the channel's photo instead.
  Future<void> _fillTelegramArt(String url) async {
    final playlists = _ref.read(playlistsProvider.notifier);
    var tried = 0;
    while (true) {
      final pod = _feeds[url];
      if (pod == null) return;
      final i = pod.episodes.indexWhere((e) => e.tg != null && (e.imageUrl == null || !File(e.imageUrl!).existsSync()) && !_noArt.contains(e.guid));
      if (i < 0 || tried >= 60) break;
      tried++;
      final e = pod.episodes[i];
      String? art;
      try {
        art = await playlists.artFor(e.tg!);
      } catch (_) {}
      if (art == null) {
        _noArt.add(e.guid);
        continue;
      }
      final eps = [...pod.episodes];
      eps[i] = e.copyWith(imageUrl: art, tg: e.tg!.copyWith(artPath: art));
      pod.episodes = eps;
      final s = states[e.guid];
      if (s != null) s.episode = eps[i];
      if (tried % 6 == 0) _persist();
    }
    _persist();
  }

  final Set<String> _noArt = {};

  /// Follows channels as shows.
  Future<void> addTelegramShows(List<SourceRef> sources) async {
    for (final s in sources) {
      final id = telegramShowId(s.account, s.chatId);
      if (subscribed(id)) continue;
      final pod = Podcast(feedUrl: id, title: s.title, author: 'Telegram');
      subscribe(pod);
    }
    await pooled([for (final s in sources) telegramShowId(s.account, s.chatId)], 2, (id) => feed(id, refresh: true));
  }

  // ---- subscriptions ----------------------------------------------------------------

  bool subscribed(String feedUrl) => subscriptions.any((s) => s.feedUrl == feedUrl);

  void subscribe(Podcast pod, {int at = 0}) {
    if (subscribed(pod.feedUrl)) return;
    pod.subscribedAt = DateTime.now();
    subscriptions.insert(at.clamp(0, subscriptions.length), pod);
    _feeds[pod.feedUrl] = pod;
    _persist();
  }

  void unsubscribe(String feedUrl) {
    subscriptions.removeWhere((s) => s.feedUrl == feedUrl);
    _feeds[feedUrl]?.subscribedAt = null;
    // Still opens instantly from the recent shows.
    if (_feeds[feedUrl] case final p?) _rememberShow(p);
    _persist();
  }

  void moveShow(int from, int to) {
    if (from < 0 || from >= subscriptions.length) return;
    final s = subscriptions.removeAt(from);
    subscriptions.insert(to.clamp(0, subscriptions.length), s);
    _persist();
  }

  /// Adds a show by its RSS address. Null if it isn't a podcast feed.
  Future<Podcast?> addByUrl(String url) async {
    final u = url.trim();
    if (!u.startsWith('http')) return null;
    final pod = await feed(u, refresh: true, force: true);
    if (pod == null || pod.episodes.isEmpty) return null;
    subscribe(pod);
    return pod;
  }

  /// Re-reads every show; with [quiet], says nothing unless there's news.
  /// Quiet refreshes (opening Podcasts, coming back to the app) are
  /// skipped within [_refreshEvery] of the last one; pulling to refresh
  /// always asks every feed's server.
  Future<void> refreshAll({bool quiet = false}) async {
    await ready;
    if (refreshing || subscriptions.isEmpty) return;
    final last = _lastRefresh;
    if (quiet && last != null && DateTime.now().difference(last) < _refreshEvery) return;
    refreshing = true;
    if (!quiet) notifyListeners();
    final before = {for (final s in subscriptions) s.feedUrl: s.episodes.isEmpty ? null : s.episodes.first.published};
    try {
      await pooled([...subscriptions], 4, (s) => feed(s.feedUrl, refresh: true, force: !quiet, full: false));
      if (!unreachable) _lastRefresh = DateTime.now();
    } finally {
      refreshing = false;
      notifyListeners();
    }
    final fresh = <Episode>[];
    for (final s in subscriptions) {
      final was = before[s.feedUrl];
      if (was == null || s.isTelegram) continue;
      fresh.addAll(s.episodes.where((e) => e.published != null && e.published!.isAfter(was)));
    }
    if (fresh.isNotEmpty && notifyNew) {
      try {
        await _ref.read(appNotifierProvider).show(
          fresh.length == 1 ? 'New episode: ${fresh.first.podcastTitle}' : '${fresh.length} new episodes',
          fresh.take(4).map((e) => fresh.length == 1 ? e.title : '${e.podcastTitle}: ${e.title}').join('\n'),
        );
      } catch (_) {}
    }
  }

  // ---- OPML -------------------------------------------------------------------------

  String toOpml() {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('opml', attributes: {'version': '2.0'}, nest: () {
      b.element('head', nest: () {
        b.element('title', nest: 'Triangle podcast subscriptions');
        b.element('dateCreated', nest: HttpDate.format(DateTime.now()));
      });
      b.element('body', nest: () {
        for (final s in subscriptions.where((s) => !s.isTelegram)) {
          b.element('outline', attributes: {
            'type': 'rss',
            'text': s.title,
            'title': s.title,
            'xmlUrl': s.feedUrl,
            if (s.link != null && s.link!.isNotEmpty) 'htmlUrl': s.link!,
            if (s.imageUrl != null && s.imageUrl!.isNotEmpty) 'imageUrl': s.imageUrl!,
          });
        }
      });
    });
    return b.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  Future<File> exportOpml() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/exports');
    await dir.create(recursive: true);
    final f = File('${dir.path}/podcasts.opml');
    await f.writeAsString(toOpml());
    return f;
  }

  /// The feeds in an OPML file, as (title, address). Throws a
  /// [FormatException] if it isn't OPML.
  static List<({String title, String url})> parseOpml(String text) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text.trimLeft().replaceFirst('﻿', ''));
    } on XmlException {
      throw const FormatException('That file isn\'t OPML.');
    }
    if (doc.rootElement.name.local.toLowerCase() != 'opml') throw const FormatException('That file isn\'t OPML.');
    String? attr(XmlElement e, String name) {
      for (final a in e.attributes) {
        if (a.name.local.toLowerCase() == name.toLowerCase()) return a.value.trim();
      }
      return null;
    }

    final seen = <String>{};
    final out = <({String title, String url})>[];
    for (final o in doc.findAllElements('outline')) {
      final url = attr(o, 'xmlUrl');
      if (url == null || !url.startsWith('http') || !seen.add(url)) continue;
      final title = attr(o, 'title') ?? attr(o, 'text') ?? '';
      out.add((title: title.isEmpty ? url : title, url: url));
    }
    return out;
  }

  /// Subscribes to every feed in [feeds] not followed yet, four at a time.
  /// Each is subscribed as soon as it's read, so a stopped import keeps what
  /// it got.
  void startOpmlImport(List<({String title, String url})> feeds) {
    if (opml?.running ?? false) return;
    final todo = feeds.where((f) => !subscribed(f.url)).toList();
    final job = opml = OpmlImport(total: todo.length, already: feeds.length - todo.length);
    notifyListeners();
    () async {
      var next = 0;
      Future<void> worker() async {
        while (!job.cancelled && next < todo.length) {
          final k = next++;
          final pod = await feed(todo[k].url, refresh: true).catchError((_) => null);
          if (job.cancelled) return;
          job.done++;
          if (pod == null || pod.episodes.isEmpty) {
            job.failed.add(todo[k].title);
          } else if (!subscribed(pod.feedUrl)) {
            subscribe(pod, at: subscriptions.length);
            job.added++;
          }
          notifyListeners();
        }
      }

      await Future.wait([for (var w = 0; w < math.min(4, todo.length); w++) worker()]);
    }()
        .whenComplete(() {
          job.running = false;
          notifyListeners();
        })
        .ignore();
  }

  void cancelOpmlImport() {
    opml?.cancelled = true;
    notifyListeners();
  }

  void dismissOpmlImport() {
    if (opml?.running ?? false) return;
    opml = null;
    notifyListeners();
  }

  // ---- lists ------------------------------------------------------------------------

  /// Newest unplayed episodes across your shows.
  List<Episode> get latest {
    final all = [for (final s in subscriptions) ...s.episodes.take(10)].where((e) => !(states[e.guid]?.played ?? false)).toList()
      ..sort((a, b) => (b.published ?? DateTime(1970)).compareTo(a.published ?? DateTime(1970)));
    return all.take(40).toList();
  }

  /// Started but not finished, latest first.
  List<EpisodeState> get inProgress => states.values.where((s) => s.posMs > 15000 && !s.played).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<EpisodeState> get downloaded => states.values.where((s) => s.localPath != null).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Episodes heard to the end, latest first.
  List<EpisodeState> get history => states.values.where((s) => s.played || s.posMs > 15000).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<EpisodeState> get bookmarked => states.values.where((s) => s.mark.favorite || s.mark.bookmarks.isNotEmpty || s.mark.note.isNotEmpty).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  int unplayedIn(Podcast p) => p.episodes.take(20).where((e) => stage(e) == 'unplayed').length;

  // ---- episode state ----------------------------------------------------------------

  EpisodeState _state(Episode e) => states[e.guid] ??= EpisodeState(episode: e);

  double progressOf(Episode e) {
    final s = states[e.guid];
    if (s == null) return 0;
    if (s.played) return 1;
    final dur = e.durationMs > 0 ? e.durationMs : s.episode.durationMs;
    return dur > 0 ? (s.posMs / dur).clamp(0.0, 1.0) : 0;
  }

  bool played(Episode e) => states[e.guid]?.played ?? false;

  /// 'played', 'started' or 'unplayed'.
  String stage(Episode e) {
    final s = states[e.guid];
    if (s == null) return 'unplayed';
    if (s.played) return 'played';
    return s.posMs > 15000 ? 'started' : 'unplayed';
  }

  void setPlayed(Episode e, bool v) {
    final s = _state(e)
      ..played = v
      ..posMs = 0
      ..updatedAt = DateTime.now();
    if (v) queue.removeWhere((q) => q.guid == e.guid);
    if (v && deletePlayedDownloads) unawaited(removeDownload(s.episode));
    _persist();
  }

  void markOlderPlayed(Podcast pod, Episode e) {
    final i = pod.episodes.indexWhere((x) => x.guid == e.guid);
    for (final x in pod.episodes.skip(i + 1)) {
      _state(x).played = true;
    }
    _persist();
  }

  void markAllPlayed(Podcast pod, bool v) {
    for (final x in pod.episodes) {
      _state(x)
        ..played = v
        ..posMs = 0;
    }
    _persist();
  }

  UserMark showMark(String feedUrl) => showMarks[feedUrl] ??= UserMark();
  UserMark episodeMark(Episode e) => _state(e).mark;

  /// For lists: unlike [episodeMark], doesn't make a state for [e].
  bool isFavorite(Episode e) => states[e.guid]?.mark.favorite ?? false;

  /// Call after changing a [UserMark] in place.
  void marksChanged() => _persist();

  EpisodeSort sortOf(String feedUrl) => EpisodeSort.parse(showSorts[feedUrl] ?? episodeSort);
  bool hasOwnSort(String feedUrl) => showSorts.containsKey(feedUrl);
  void setSort(String feedUrl, EpisodeSort? sort) {
    sort == null ? showSorts.remove(feedUrl) : showSorts[feedUrl] = sort.name;
    _persist();
  }

  Episode? episodeById(String guid) {
    final s = states[guid];
    if (s != null) return s.episode;
    for (final p in _feeds.values) {
      for (final e in p.episodes) {
        if (e.guid == guid) return e;
      }
    }
    return queue.where((e) => e.guid == guid).firstOrNull;
  }

  // ---- playing ----------------------------------------------------------------------

  /// What is playing, by track key, for the podcasts this store started.
  final Map<String, Episode> _playing = {};

  static String trackKey(Episode e) => e.tg != null ? e.tg!.key : 'pod:${e.guid}';

  Track trackOf(Episode e) {
    final s = states[e.guid];
    final start = s == null || s.played ? 0 : math.max(0, s.posMs - 3000);
    if (e.tg != null) return _ref.read(playlistsProvider.notifier).trackFor(e.tg!, tag: 'podcasts').withPlayback(startMs: start, spoken: true);
    final local = s?.localPath != null && File(s!.localPath!).existsSync() ? s.localPath : null;
    return Track(
      chatId: 0,
      messageId: 0,
      identifier: trackKey(e),
      localPath: local,
      url: local == null ? e.audioUrl : null,
      title: e.title,
      subtitle: e.podcastTitle,
      seconds: e.durationMs ~/ 1000,
      voice: false,
      artUrl: e.art,
      spoken: true,
      startMs: start,
      queueTag: 'podcasts',
      info: {
        'Show': e.podcastTitle,
        if (e.published != null) 'Published': '${e.published!.day}/${e.published!.month}/${e.published!.year}',
        if (local != null) 'Saved': 'On this phone',
      },
    );
  }

  bool isCurrent(Episode e) => _ref.read(audioCenterProvider).current?.key == trackKey(e);
  bool isPlaying(Episode e) {
    final a = _ref.read(audioCenterProvider);
    return a.current?.key == trackKey(e) && a.playing;
  }

  Future<void> play(Episode e) async {
    final audio = _ref.read(audioCenterProvider);
    if (isCurrent(e)) return audio.toggle();
    final s = _state(e);
    if (s.played) {
      s.played = false;
      s.posMs = 0;
    }
    queue.removeWhere((q) => q.guid == e.guid);
    _persist();
    if (audio.shuffle) audio.setShuffle(false);
    final list = [e, ...queue];
    for (final x in list) {
      _playing[trackKey(x)] = x;
    }
    await audio.play(trackOf(e), playlist: [for (final x in list) trackOf(x)]);
  }

  /// Every episode of a list in order, from [start].
  Future<void> playAll(List<Episode> eps, {int start = 0}) async {
    if (eps.isEmpty) return;
    final audio = _ref.read(audioCenterProvider);
    if (audio.shuffle) audio.setShuffle(false);
    for (final x in eps) {
      _playing[trackKey(x)] = x;
    }
    await audio.play(trackOf(eps[start]), playlist: [for (final x in eps) trackOf(x)]);
  }

  /// The episode playing now, if a podcast is.
  Episode? get nowPlaying {
    final k = _ref.read(audioCenterProvider).current?.key;
    return k == null ? null : _playing[k];
  }

  DateTime _lastSave = DateTime(0);
  String? _lastKey;

  void _onAudio() {
    final a = _ref.read(audioCenterProvider);
    final k = a.current?.key;
    if (a.talkSpeed != talkSpeed) {
      talkSpeed = a.talkSpeed;
      _persist(notify: false);
    }
    final e = k == null ? null : _playing[k];
    if (k != _lastKey) {
      _lastKey = k;
      if (e != null && queue.any((q) => q.guid == e.guid)) {
        queue.removeWhere((q) => q.guid == e.guid);
        _persist();
      }
    }
    if (e == null || a.loading) return;
    final pos = a.position.inMilliseconds;
    if (pos <= 0 || DateTime.now().difference(_lastSave).inSeconds < 5) return;
    _lastSave = DateTime.now();
    final s = _state(e)
      ..posMs = pos
      ..updatedAt = DateTime.now();
    final dur = a.duration.inMilliseconds;
    if (dur > 60000 && pos >= dur - 30000 && !s.played) {
      s.played = true;
      _persist();
      return;
    }
    _persist(notify: false);
  }

  void _ended(Track t) {
    final e = _playing[t.key];
    if (e == null) return;
    final s = _state(e)
      ..played = true
      ..posMs = 0
      ..updatedAt = DateTime.now();
    queue.removeWhere((q) => q.guid == e.guid);
    if (deletePlayedDownloads) unawaited(removeDownload(s.episode));
    _persist();
  }

  // ---- the queue --------------------------------------------------------------------

  bool queued(Episode e) => queue.any((q) => q.guid == e.guid);

  bool get _podcastPlaying => nowPlaying != null;

  void enqueue(Episode e, {bool next = false}) {
    queue.removeWhere((q) => q.guid == e.guid);
    next ? queue.insert(0, e) : queue.add(e);
    _state(e);
    _playing[trackKey(e)] = e;
    if (_podcastPlaying) {
      final audio = _ref.read(audioCenterProvider);
      next ? audio.playNext(trackOf(e)) : audio.enqueue(trackOf(e));
    }
    _persist();
  }

  void dequeue(Episode e) {
    queue.removeWhere((q) => q.guid == e.guid);
    if (_podcastPlaying) _ref.read(audioCenterProvider).dequeue(trackOf(e));
    _persist();
  }

  void reorderQueue(int from, int to) {
    if (to > from) to--;
    queue.insert(to.clamp(0, queue.length), queue.removeAt(from));
    if (_podcastPlaying) {
      final audio = _ref.read(audioCenterProvider);
      for (final e in queue) {
        audio.dequeue(trackOf(e));
      }
      for (final e in queue) {
        audio.enqueue(trackOf(e));
      }
    }
    _persist();
  }

  void clearQueue() {
    if (_podcastPlaying) {
      final audio = _ref.read(audioCenterProvider);
      for (final e in queue) {
        audio.dequeue(trackOf(e));
      }
    }
    queue.clear();
    _persist();
  }

  // ---- downloads --------------------------------------------------------------------

  bool isDownloaded(Episode e) {
    final p = states[e.guid]?.localPath;
    return p != null && File(p).existsSync();
  }

  Future<bool> download(Episode e) async {
    if (e.isTelegram || downloads.containsKey(e.guid) || isDownloaded(e)) return true;
    final ext = RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav)(\?|$)', caseSensitive: false).firstMatch(e.audioUrl)?.group(1) ?? 'mp3';
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/podcasts');
    await dir.create(recursive: true);
    final dest = File('${dir.path}/${sha1.convert(utf8.encode(e.guid))}.$ext');
    final part = File('${dest.path}.part');
    downloads[e.guid] = -1;
    _cancel.remove(e.guid);
    _state(e);
    notifyListeners();
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(e.audioUrl))..headers.addAll(_ua)).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      final sink = part.openWrite();
      var got = 0;
      var last = DateTime(0);
      try {
        await for (final chunk in res.stream) {
          if (_cancel.contains(e.guid)) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0 && DateTime.now().difference(last).inMilliseconds > 250) {
            last = DateTime.now();
            downloads[e.guid] = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      await part.rename(dest.path);
      _state(e).localPath = dest.path;
      return true;
    } catch (err) {
      if (await part.exists()) await part.delete().catchError((_) => part);
      if (err is! _Cancelled) debugPrint('[Podcasts] download: $err');
      return false;
    } finally {
      client.close();
      downloads.remove(e.guid);
      _cancel.remove(e.guid);
      _persist();
    }
  }

  void cancelDownload(String guid) {
    _cancel.add(guid);
    notifyListeners();
  }

  /// Saves [eps] one after another. False if any failed or it was stopped.
  Future<bool> downloadAll(List<Episode> eps) async {
    var ok = true;
    for (final e in eps.where((e) => !isDownloaded(e) && !e.isTelegram)) {
      if (_cancel.contains('*')) break;
      ok = await download(e) && ok;
    }
    _cancel.remove('*');
    return ok;
  }

  void cancelAllDownloads() {
    _cancel.add('*');
    _cancel.addAll(downloads.keys);
    notifyListeners();
  }

  Future<void> removeDownload(Episode e) async {
    final s = states[e.guid];
    final path = s?.localPath;
    if (s == null || path == null) return;
    s.localPath = null;
    _persist();
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  /// Bytes the downloads take on this phone.
  int get downloadedBytes {
    var n = 0;
    for (final s in downloaded) {
      try {
        n += File(s.localPath!).lengthSync();
      } catch (_) {}
    }
    return n;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pending?.cancel();
    try {
      final audio = _ref.read(audioCenterProvider);
      audio.removeListener(_onAudio);
      audio.onTrackEnded.remove(_ended);
    } catch (_) {}
    super.dispose();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

final podcastsProvider = ChangeNotifierProvider<PodcastStore>((ref) => PodcastStore(ref));

/// The active Telegram account, for picking channels.
String activeAccount(WidgetRef ref) => ref.read(activeAccountIdProvider);
