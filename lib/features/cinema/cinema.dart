import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../telegram/data/message_content.dart' show pickPhotoSize;
import '../telegram/data/telegram_store.dart';

import '../movies/movies.dart';
import '../sections/section_kit.dart';

// Cinema: channels that post films and series, read as a streaming
// catalogue. Each video's file name and caption are read for a title, a
// year and a season/episode; posts of the same film or show gather into
// one title, with its poster, synopsis and genres looked up online
// (TVMaze for shows, the iTunes Store for films; neither needs a key).
// The videos themselves stay in Telegram and play in Video's player, so
// progress is shared with it.

enum TitleKind { movie, show }

/// What a post's words say it is.
@immutable
class Release {
  const Release({required this.kind, required this.title, this.year, this.season = 0, this.episode = 0});
  final TitleKind kind;
  final String title;
  final int? year;
  final int season;
  final int episode;
}

final _se = RegExp(r'\bS(\d{1,2})\s*[._ -]?\s*E[Pp]?\s*(\d{1,3})\b', caseSensitive: false);
final _x = RegExp(r'\b(\d{1,2})x(\d{2,3})\b');
final _seasonEp = RegExp(r'\b(?:Season|Se|Sezon)\s*(\d{1,2})\b[^\n]*?\b(?:Episode|Ep\.?|Part)\s*(\d{1,3})\b', caseSensitive: false);
final _epOnly = RegExp(r'\b(?:Episode|Ep\.?)\s*(\d{1,3})\b', caseSensitive: false);
final _year = RegExp(r'(?:^|[\s(\[._-])((?:19[3-9]|20[0-3])\d)(?=$|[\s)\]._-])');
final _junk = RegExp(
  r'\b(?:2160p|1080p|720p|480p|360p|4k|uhd|fhd|hd|hdrip|web[-. ]?dl|web[-. ]?rip|webrip|bluray|blu[-. ]?ray|brrip|bdrip|dvdrip|hdtv|camrip|cam|ts|x264|x265|h264|h265|hevc|aac\d?(?:\.\d)?|ddp?\d?(?:\.\d)?|10bit|8bit|hdr|dv|atmos|yts|yify|rarbg|psa|amzn|nf|dsnp|hmax|proper|repack|extended|remastered|unrated|imax|dubbed|subbed|esub|multi|dual audio|eng|english|hindi|amharic|mkv|mp4|avi)\b',
  caseSensitive: false,
);

/// Turns a release name into a readable title: separators to spaces,
/// tags, brackets, handles and hashtags gone.
String cleanTitle(String raw) {
  var t = raw
      .replaceAll(RegExp(r'\.(?:mkv|mp4|avi|mov|webm|m4v|ts)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[@#]\w+'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]|\{[^}]*\}'), ' ')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(_junk, ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s:&!?\x27,-]', unicode: true), ' ')
      .replaceAll(RegExp(r'\(\s*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  t = t.replaceAll(RegExp(r'^[-:,\s]+|[-:,\s]+$'), '').trim();
  if (t.isEmpty) return '';
  // Shouted names read better in title case.
  if (t == t.toUpperCase() && t.length > 3) {
    t = t.toLowerCase().split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
  return t;
}

/// A title's key: lower case letters and digits only.
String titleKey(String t) => t.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

Release? parseRelease(Video v) {
  // The file name is usually the tidiest; the caption's first line next.
  final firstLine = v.description.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 2, orElse: () => '');
  for (final source in [v.fileName, firstLine, v.title]) {
    if (source.trim().isEmpty) continue;
    RegExpMatch? m;
    int season = 0, episode = 0;
    if ((m = _se.firstMatch(source)) != null) {
      season = int.parse(m!.group(1)!);
      episode = int.parse(m.group(2)!);
    } else if ((m = _seasonEp.firstMatch(source)) != null) {
      season = int.parse(m!.group(1)!);
      episode = int.parse(m.group(2)!);
    } else if ((m = _x.firstMatch(source)) != null && !_year.hasMatch(source.substring(m!.start, m.end))) {
      season = int.parse(m.group(1)!);
      episode = int.parse(m.group(2)!);
    } else if ((m = _epOnly.firstMatch(source)) != null) {
      season = 1;
      episode = int.parse(m!.group(1)!);
    }
    if (m != null && episode > 0) {
      final title = cleanTitle(source.substring(0, m.start).replaceAll(_year, ' '));
      if (title.length < 2) continue;
      final y = _year.firstMatch(source.substring(0, m.start));
      return Release(kind: TitleKind.show, title: title, season: season, episode: episode, year: y == null ? null : int.parse(y.group(1)!));
    }
    final y = _year.firstMatch(source);
    final long = v.seconds >= 50 * 60 || (v.seconds == 0 && v.size > 350 << 20);
    if (y == null && !long) continue;
    final title = cleanTitle(y == null ? source : source.substring(0, y.start));
    if (title.length < 2) continue;
    return Release(kind: TitleKind.movie, title: title, year: y == null ? null : int.parse(y.group(1)!));
  }
  return null;
}

/// One episode, with every copy of it that was posted.
class Episode {
  Episode(this.season, this.number);
  final int season;
  final int number;
  final versions = <Video>[];

  /// The copy to play: the sharpest.
  Video get best => (versions..sort((a, b) => b.height.compareTo(a.height))).first;
  DateTime get date => versions.map((v) => v.date).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// A film or a show, gathered from the posts about it.
class CinemaTitle {
  CinemaTitle({required this.key, required this.kind, required this.title, this.year, this.customId, this.customPoster, this.posterChat, this.posterOnline = true});
  final String key;

  /// The series the person put together, when it's one of those.
  final String? customId;

  /// A made-up series' poster: a picture the person picked (a path), or
  /// its channel's (its poster posts, else [posterChat]'s photo) unless
  /// [posterOnline].
  final String? customPoster;
  final SourceRef? posterChat;
  final bool posterOnline;
  final TitleKind kind;
  final String title;
  int? year;

  /// A film's copies (qualities, cuts).
  final versions = <Video>[];

  /// A show's episodes by season.
  final seasons = <int, Map<int, Episode>>{};

  bool get isShow => kind == TitleKind.show;
  List<Video> get allVideos => isShow ? [for (final s in seasons.values) for (final e in s.values) ...e.versions] : versions;
  /// Poster posts about it (a picture with the plot, ratings and links,
  /// no video), newest first.
  final infos = <InfoPost>[];

  bool get hasVideo => versions.isNotEmpty || seasons.isNotEmpty;
  InfoPost? get info => infos.isEmpty ? null : infos.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  Video? get cover => allVideos.isEmpty ? null : allVideos.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  DateTime get updated {
    final v = cover?.date, i = info?.date;
    if (v == null) return i ?? DateTime(2000);
    if (i == null) return v;
    return v.isAfter(i) ? v : i;
  }
  int get episodeCount => seasons.values.fold(0, (a, s) => a + s.length);
  List<int> get seasonNumbers => seasons.keys.toList()..sort();

  List<Episode> episodesOf(int season) => (seasons[season]?.values.toList() ?? <Episode>[])..sort((a, b) => a.number.compareTo(b.number));

  Video? get bestVersion => versions.isEmpty ? null : (versions..sort((a, b) => b.height.compareTo(a.height))).first;
}

/// Every title in [videos] (and, given, [infos]: poster posts), newest
/// first.
List<CinemaTitle> buildCatalog(Iterable<Video> videos, [Iterable<InfoPost> infos = const []]) {
  final byKey = <String, CinemaTitle>{};
  for (final v in videos) {
    final r = parseRelease(v);
    if (r == null) continue;
    final base = titleKey(r.title);
    if (base.isEmpty) continue;
    final key = r.kind == TitleKind.show ? 'show:$base' : 'movie:$base${r.year ?? ''}';
    final t = byKey.putIfAbsent(key, () => CinemaTitle(key: key, kind: r.kind, title: r.title, year: r.year));
    t.year ??= r.year;
    if (r.kind == TitleKind.show) {
      final ep = t.seasons.putIfAbsent(r.season, () => {}).putIfAbsent(r.episode, () => Episode(r.season, r.episode));
      if (ep.versions.every((x) => x.key != v.key)) ep.versions.add(v);
    } else if (t.versions.every((x) => x.key != v.key)) {
      t.versions.add(v);
    }
  }
  for (final i in infos) {
    final base = titleKey(i.title);
    if (base.isEmpty) continue;
    String key;
    if (i.kind == TitleKind.show) {
      key = 'show:$base';
    } else {
      // A film's videos may not say the year; join them when they don't.
      key = 'movie:$base${i.year ?? ''}';
      if (!byKey.containsKey(key) && byKey.containsKey('movie:$base')) key = 'movie:$base';
    }
    final t = byKey.putIfAbsent(key, () => CinemaTitle(key: key, kind: i.kind, title: i.title, year: i.year));
    t.year ??= i.year;
    if (t.infos.every((x) => x.key != i.key)) t.infos.add(i);
  }
  return byKey.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
}

// ---- poster posts --------------------------------------------------------------

/// A post that's a poster with the film's or show's details and links, but
/// no video: "Being Heumann (2026) is now available!", the plot, ratings,
/// #Drama #History, "DOWNLOAD https://…".
class InfoPost {
  InfoPost({
    required this.account,
    required this.chatId,
    required this.messageId,
    required this.source,
    required this.date,
    required this.kind,
    required this.title,
    this.year,
    this.season = 0,
    this.photo,
    this.mini,
    this.plot = '',
    this.ratings = const [],
    this.average,
    this.runtime = '',
    this.rated = '',
    this.genres = const [],
    this.links = const [],
    this.caption,
  });
  final String account;
  final int chatId;
  final int messageId;
  final String source;
  final DateTime date;
  final TitleKind kind;
  final String title;
  final int? year;
  final int season;
  final td.File? photo;
  final td.Minithumbnail? mini;
  final String plot;

  /// ("IMDb", "6.9/10"), ("Rotten Tomatoes", "87%")…
  final List<(String, String)> ratings;

  /// Out of 10.
  final double? average;
  final String runtime;
  final String rated;
  final List<String> genres;

  /// (label, url): "Download", "Watch"…
  final List<(String, String)> links;
  final td.FormattedText? caption;

  String get key => postKey(account, chatId, messageId);
}

final _yearIn = RegExp(r'[\(\[]?\b((?:19[3-9]|20[0-3])\d)\b[\)\]]?');
final _seasonIn = RegExp(r'\b(?:Season|Series|Sezon)\s*(\d{1,2})\b|\bS(\d{1,2})(?:\s*E\d{1,3})?\b|\b(?:TV[ -]?Series|Mini[- ]?Series|Web[- ]?Series|All Episodes|Complete Series)\b', caseSensitive: false);
final _ratingIn = RegExp(r'(IMDb|Rotten Tomatoes|Letterboxd|TMDB|TMDb|Metacritic|Kinopoisk)[^\d\n]{0,12}([\d.]+\s*(?:/\s*\d+|%))', caseSensitive: false);
final _avgIn = RegExp(r'(?:Avg\.?|Average)\s*Rating[^\d\n]{0,12}([\d.]+)\s*/\s*10', caseSensitive: false);
final _runtimeIn = RegExp(r'\b(\d{1,2}h\s*\d{1,2}\s*min|\d{2,3}\s*min(?:utes)?)\b', caseSensitive: false);
final _ratedIn = RegExp(r'(?:^|\|)\s*(G|PG|PG-13|R|NC-17|NR|TV-MA|TV-14|TV-PG|TV-Y7?|TV-G)\s*(?:\||$)', multiLine: true);
final _urlIn = RegExp(r'https?://[^\s<>()]+');
final _filmy = RegExp(r'IMDb|Rotten|TMDB|Letterboxd|Rating|Genre|Runtime|Starring|Director|Cast|Trailer|Download|Watch|Stream|Episode|Season|#\w+', caseSensitive: false);

String _plain(String s) => s.replaceAll(RegExp(r'[^\p{L}\p{N}\s:&!?\x27,.()-]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Reads a poster post; null when it doesn't look like one.
InfoPost? parseInfoPost(td.Message m, String account, String source) {
  final c = m.content;
  if (c is! td.MessagePhoto) return null;
  final text = c.caption.text.trim();
  if (text.length < 25 || !_filmy.hasMatch(text)) return null;
  final lines = [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  final head = lines.first;
  final y = _yearIn.firstMatch(head);
  final se = _seasonIn.firstMatch(head);
  if (y == null && se == null) return null;
  final cut = [if (y != null) y.start, if (se != null) se.start].reduce((a, b) => a < b ? a : b);
  var title = cleanTitle(_plain(head.substring(0, cut)));
  title = title.replaceAll(RegExp(r'\b(?:is |are )?(?:now )?(?:available|streaming|out now|released|new|official)\b.*$', caseSensitive: false), '').trim();
  if (title.length < 2) return null;
  final season = se == null ? 0 : int.tryParse(se.group(1) ?? se.group(2) ?? '') ?? 1;
  // The plot: the first long paragraph that isn't ratings or links.
  final plot = lines.skip(1).firstWhere(
    (l) => l.length > 60 && !_ratingIn.hasMatch(l) && !_urlIn.hasMatch(l) && !l.startsWith('#'),
    orElse: () => '',
  );
  final ratings = <(String, String)>[];
  final seen = <String>{};
  for (final r in _ratingIn.allMatches(text)) {
    final name = r.group(1)!.toUpperCase() == 'TMDB' ? 'TMDB' : (r.group(1)!.toLowerCase() == 'imdb' ? 'IMDb' : r.group(1)!);
    if (seen.add(name.toLowerCase())) ratings.add((name, r.group(2)!.replaceAll(' ', '')));
  }
  final links = <(String, String)>[];
  final urls = <String>{};
  void addLink(String url, int at) {
    url = url.replaceAll(RegExp(r'[.,)]+$'), '');
    if (!urls.add(url)) return;
    // The words just before it ("DOWNLOAD", "Watch online"), else its site.
    final before = text.substring(0, at).split('\n').where((l) => l.trim().isNotEmpty).lastOrNull ?? '';
    var label = _plain(before.replaceAll(_urlIn, ''));
    if (label.isEmpty || label.length > 28) label = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? 'Link';
    links.add((label[0].toUpperCase() + label.substring(1).toLowerCase(), url));
  }
  for (final u in _urlIn.allMatches(text)) {
    addLink(u.group(0)!, u.start);
  }
  for (final e in c.caption.entities) {
    if (e.type case td.TextEntityTypeTextUrl(:final url)) addLink(url, e.offset);
  }
  final size = pickPhotoSize(c.photo.sizes, minWidth: 500);
  return InfoPost(
    account: account,
    chatId: m.chatId,
    messageId: m.id,
    source: source,
    date: unixDate(m.date),
    kind: se != null ? TitleKind.show : TitleKind.movie,
    title: title,
    year: y == null ? null : int.parse(y.group(1)!),
    season: season,
    photo: size?.photo,
    mini: c.photo.minithumbnail,
    plot: plot,
    ratings: ratings,
    average: double.tryParse(_avgIn.firstMatch(text)?.group(1) ?? ''),
    runtime: _runtimeIn.firstMatch(text)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ') ?? '',
    rated: _ratedIn.firstMatch(text)?.group(1) ?? '',
    genres: [for (final h in RegExp(r'#([\p{L}][\p{L}\p{N}_]+)', unicode: true).allMatches(text)) h.group(1)!.replaceAll('_', ' ')].take(5).toList(),
    links: links.take(6).toList(),
    caption: c.caption,
  );
}

@immutable
class InfoFeedState {
  const InfoFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}});
  final Map<String, List<InfoPost>> bySource;
  final Set<String> loading;
  final Map<String, int> next;
  bool hasMore(String k) => (next[k] ?? 1) != 0;
}

/// Poster posts from Cinema's channels, kept for the session.
class InfoFeed extends Notifier<InfoFeedState> {
  static final _memory = FeedMemory('posters');
  final _ids = <String, List<int>>{};

  @override
  InfoFeedState build() => const InfoFeedState();

  Future<void> load(SourceRef s, {bool more = false}) async {
    if (state.loading.contains(s.key) || (more && state.next[s.key] == 0)) return;
    state = InfoFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next);
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      // First time this run: what it showed last time, at once.
      if (!more && !state.bySource.containsKey(s.key)) {
        final kept = [for (final m in await _memory.recall(client, s)) ?parseInfoPost(m, s.account, title)];
        if (kept.isNotEmpty && !state.bySource.containsKey(s.key)) {
          state = InfoFeedState(bySource: {...state.bySource, s.key: kept}, loading: state.loading, next: state.next);
        }
      }
      final page = await loadChatPage(client, s.chatId, filter: const td.SearchMessagesFilterPhoto(), from: more ? (state.next[s.key] ?? 0) : 0, limit: 60);
      final found = [for (final m in page.messages) ?parseInfoPost(m, s.account, title)];
      final ids = [if (more) ...?_ids[s.key], ...page.messages.map((m) => m.id)];
      _ids[s.key] = ids;
      unawaited(_memory.remember(s, ids, max: 240));
      final have = more ? (state.bySource[s.key] ?? const <InfoPost>[]) : const <InfoPost>[];
      final keys = {for (final i in have) i.key};
      state = InfoFeedState(bySource: {...state.bySource, s.key: [...have, for (final i in found) if (keys.add(i.key)) i]}, loading: {...state.loading}..remove(s.key), next: {...state.next, s.key: page.next});
    } catch (e) {
      debugPrint('[Cinema] posters ${s.title}: $e');
      state = InfoFeedState(bySource: state.bySource, loading: {...state.loading}..remove(s.key), next: {...state.next, s.key: 0});
    }
  }

  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));
}

final infoFeedProvider = NotifierProvider<InfoFeed, InfoFeedState>(InfoFeed.new);

// ---- what's looked up online ---------------------------------------------------
//
// Cinemeta (Stremio's public catalogue: IMDb data, no key) for films and
// series first: poster, backdrop, logo, plot, genres, IMDb rating, cast,
// director, runtime and, for series, every episode's name, still, plot
// and air date. TVMaze (shows) and the iTunes Store (films) fill in when
// it has nothing.

@immutable
class TitleMeta {
  const TitleMeta({
    this.poster,
    this.backdrop,
    this.logo,
    this.overview = '',
    this.genres = const [],
    this.rating,
    this.year,
    this.yearText = '',
    this.runtime,
    this.network,
    this.rated,
    this.showId,
    this.imdbId,
    this.cast = const [],
    this.director = const [],
    this.status = '',
    this.awards = '',
    this.trailer,
  });
  final String? poster;
  final String? backdrop;
  final String? logo;
  final String overview;
  final List<String> genres;
  final double? rating;
  final int? year;

  /// "2008–2013".
  final String yearText;

  /// Minutes.
  final int? runtime;
  final String? network;
  final String? rated;

  /// Where its episodes come from: an IMDb id ("tt…", Cinemeta) or a
  /// TVMaze id.
  final String? showId;
  final String? imdbId;
  final List<String> cast;
  final List<String> director;
  final String status;
  final String awards;

  /// A YouTube video id.
  final String? trailer;

  Map<String, dynamic> toJson() => {
    'p': poster,
    'b': backdrop,
    'l': logo,
    'o': overview,
    'g': genres,
    'r': rating,
    'y': year,
    'yt': yearText,
    'm': runtime,
    'n': network,
    'a': rated,
    's': showId,
    'i': imdbId,
    'c': cast,
    'd': director,
    'st': status,
    'aw': awards,
    't': trailer,
  };

  factory TitleMeta.fromJson(Map j) => TitleMeta(
    poster: j['p'] as String?,
    backdrop: j['b'] as String?,
    logo: j['l'] as String?,
    overview: '${j['o'] ?? ''}',
    genres: [for (final g in (j['g'] as List? ?? const [])) '$g'],
    rating: (j['r'] as num?)?.toDouble(),
    year: (j['y'] as num?)?.toInt(),
    yearText: '${j['yt'] ?? ''}',
    runtime: (j['m'] as num?)?.toInt(),
    network: j['n'] as String?,
    rated: j['a'] as String?,
    showId: j['s'] == null ? null : '${j['s']}',
    imdbId: j['i'] as String?,
    cast: [for (final g in (j['c'] as List? ?? const [])) '$g'],
    director: [for (final g in (j['d'] as List? ?? const [])) '$g'],
    status: '${j['st'] ?? ''}',
    awards: '${j['aw'] ?? ''}',
    trailer: j['t'] as String?,
  );
}

String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").trim();

Future<Object?> _get(Uri u) async {
  final r = await http.get(u).timeout(const Duration(seconds: 12));
  if (r.statusCode == 404) return null;
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  return jsonDecode(utf8.decode(r.bodyBytes));
}

class _MetaCache {
  static const _key = 'cinema.meta.v2';
  static Map<String, dynamic>? _all;

  static Future<Map<String, dynamic>> _load() async {
    if (_all != null) return _all!;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      _all = raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _all = {};
    }
    return _all!;
  }

  static Timer? _later;

  static Future<void> put(String k, Object? v) async {
    final all = await _load();
    all[k] = v;
    _later?.cancel();
    _later = Timer(const Duration(seconds: 2), () async {
      try {
        await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(all));
      } catch (_) {}
    });
  }

  static Future<(bool, Object?)> get(String k) async {
    final all = await _load();
    return (all.containsKey(k), all[k]);
  }
}

int? _minutes(Object? v) {
  final m = RegExp(r'(?:(\d+)\s*h)?\s*(\d+)\s*min').firstMatch('${v ?? ''}');
  if (m == null) return null;
  return (int.tryParse(m.group(1) ?? '0') ?? 0) * 60 + (int.tryParse(m.group(2) ?? '') ?? 0);
}

List<String> _strs(Object? v) => [for (final x in (v is List ? v : const [])) if ('$x'.trim().isNotEmpty && '$x' != 'null') '$x'.trim()];

/// Cinemeta's best match for [title] ([year] when known).
Future<TitleMeta?> _cinemeta(TitleKind kind, String title, int? year) async {
  final type = kind == TitleKind.show ? 'series' : 'movie';
  final found = await _get(Uri.parse('https://v3-cinemeta.strem.io/catalog/$type/top/search=${Uri.encodeComponent(title)}.json'));
  final metas = (found is Map ? (found['metas'] as List? ?? const []) : const []).whereType<Map>().toList();
  final want = titleKey(title);
  Map? best;
  for (final m in metas) {
    final name = titleKey('${m['name'] ?? ''}');
    final y = int.tryParse('${m['releaseInfo'] ?? ''}'.split(RegExp(r'[–-]')).first.trim());
    final nameOk = name == want || (want.length > 4 && (name.startsWith(want) || want.startsWith(name)));
    if (nameOk && (year == null || y == null || (y - year).abs() <= (kind == TitleKind.show ? 30 : 1))) {
      best = m;
      break;
    }
  }
  if (best == null) return null;
  final id = '${best['imdb_id'] ?? best['id']}';
  final full = await _get(Uri.parse('https://v3-cinemeta.strem.io/meta/$type/$id.json'));
  final m = (full is Map ? full['meta'] : null) as Map? ?? best;
  String? big(Object? url) => url == null ? null : '$url'.replaceFirst('/poster/small/', '/poster/medium/').replaceFirst('/background/medium/', '/background/large/');
  final trailers = (m['trailers'] as List? ?? const []).whereType<Map>().toList();
  final yearText = '${m['releaseInfo'] ?? m['year'] ?? ''}';
  return TitleMeta(
    poster: big(m['poster']),
    backdrop: big(m['background']),
    logo: m['logo'] as String?,
    overview: '${m['description'] ?? ''}'.trim(),
    genres: _strs(m['genres'] ?? m['genre']),
    rating: double.tryParse('${m['imdbRating'] ?? ''}'),
    year: int.tryParse(yearText.split(RegExp(r'[–-]')).first.trim()),
    yearText: yearText,
    runtime: _minutes(m['runtime']),
    showId: kind == TitleKind.show ? id : null,
    imdbId: id,
    cast: _strs(m['cast']).take(8).toList(),
    director: _strs(m['director']),
    status: '${m['status'] ?? ''}' == 'null' ? '' : '${m['status'] ?? ''}',
    awards: '${m['awards'] ?? ''}' == 'null' ? '' : '${m['awards'] ?? ''}',
    trailer: trailers.isEmpty ? null : '${trailers.first['source']}',
  );
}

Future<TitleMeta?> _tvmaze(String title) async {
  final j = await _get(Uri.https('api.tvmaze.com', '/singlesearch/shows', {'q': title}));
  if (j is! Map) return null;
  final image = j['image'] as Map?;
  return TitleMeta(
    poster: (image?['original'] ?? image?['medium']) as String?,
    overview: _stripHtml('${j['summary'] ?? ''}'),
    genres: [for (final g in (j['genres'] as List? ?? const [])) '$g'],
    rating: ((j['rating'] as Map?)?['average'] as num?)?.toDouble(),
    year: int.tryParse('${j['premiered'] ?? ''}'.split('-').first),
    runtime: (j['averageRuntime'] as num?)?.toInt() ?? (j['runtime'] as num?)?.toInt(),
    network: ((j['network'] as Map?)?['name'] ?? (j['webChannel'] as Map?)?['name']) as String?,
    showId: j['id'] == null ? null : '${j['id']}',
    imdbId: (j['externals'] as Map?)?['imdb'] as String?,
    status: '${j['status'] ?? ''}',
  );
}

Future<TitleMeta?> _itunes(String title, int? year) async {
  final j = await _get(Uri.https('itunes.apple.com', '/search', {'term': year == null ? title : '$title $year', 'media': 'movie', 'entity': 'movie', 'limit': '8'}));
  var rows = (j is Map ? (j['results'] as List? ?? const []) : const []).whereType<Map>().toList();
  if (rows.isEmpty && year != null) {
    final k = await _get(Uri.https('itunes.apple.com', '/search', {'term': title, 'media': 'movie', 'entity': 'movie', 'limit': '8'}));
    rows = (k is Map ? (k['results'] as List? ?? const []) : const []).whereType<Map>().toList();
  }
  final want = titleKey(title);
  Map? best;
  for (final r in rows) {
    final name = titleKey('${r['trackName'] ?? ''}');
    final y = int.tryParse('${r['releaseDate'] ?? ''}'.split('-').first);
    final nameOk = name == want || name.startsWith(want) || want.startsWith(name);
    if (nameOk && (year == null || y == year)) {
      best = r;
      break;
    }
    if (nameOk) best ??= r;
  }
  if (best == null) return null;
  final art = '${best['artworkUrl100'] ?? ''}';
  return TitleMeta(
    poster: art.isEmpty ? null : art.replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/600x900bb.'),
    overview: '${best['longDescription'] ?? best['shortDescription'] ?? ''}'.trim(),
    genres: [if (best['primaryGenreName'] != null) '${best['primaryGenreName']}'],
    year: int.tryParse('${best['releaseDate'] ?? ''}'.split('-').first),
    runtime: (best['trackTimeMillis'] as num?) == null ? null : ((best['trackTimeMillis'] as num) / 60000).round(),
    rated: best['contentAdvisoryRating'] as String?,
  );
}

/// A title's poster, synopsis, genres, rating and cast; null when nothing
/// matched.
final titleMetaProvider = FutureProvider.family<TitleMeta?, (TitleKind, String, int?)>((ref, a) async {
  final (kind, title, year) = a;
  final cacheKey = '${kind.name}:${titleKey(title)}:${year ?? ''}';
  final (has, cached) = await _MetaCache.get(cacheKey);
  if (has) return cached is Map ? TitleMeta.fromJson(cached) : null;
  TitleMeta? meta;
  var failed = false;
  for (final source in [
    () => _cinemeta(kind, title, year),
    if (kind == TitleKind.show) () => _tvmaze(title) else () => _itunes(title, year),
  ]) {
    try {
      final m = await source();
      if (m == null) continue;
      // The first that answers wins; a later one only fills its gaps.
      meta = meta == null
          ? m
          : TitleMeta(
              poster: meta.poster ?? m.poster,
              backdrop: meta.backdrop ?? m.backdrop,
              logo: meta.logo,
              overview: meta.overview.isNotEmpty ? meta.overview : m.overview,
              genres: meta.genres.isNotEmpty ? meta.genres : m.genres,
              rating: meta.rating ?? m.rating,
              year: meta.year ?? m.year,
              yearText: meta.yearText,
              runtime: meta.runtime ?? m.runtime,
              network: meta.network ?? m.network,
              rated: meta.rated ?? m.rated,
              showId: meta.showId ?? m.showId,
              imdbId: meta.imdbId ?? m.imdbId,
              cast: meta.cast,
              director: meta.director,
              status: meta.status.isNotEmpty ? meta.status : m.status,
              awards: meta.awards,
              trailer: meta.trailer,
            );
      if (meta.poster != null && meta.overview.isNotEmpty) break;
    } catch (e) {
      failed = true;
      debugPrint('[Cinema] meta $title: $e');
    }
  }
  // Offline: try again next time rather than remembering a miss.
  if (meta == null && failed) return null;
  await _MetaCache.put(cacheKey, meta?.toJson());
  return meta;
});

/// One episode as the catalogue knows it.
typedef EpisodeInfo = ({String name, String? image, String summary, DateTime? aired, double? rating});

/// A show's episodes by "season:number": from Cinemeta for an IMDb id
/// ("tt…"), else from TVMaze.
final showEpisodesProvider = FutureProvider.family<Map<String, EpisodeInfo>, String>((ref, showId) async {
  final cacheKey = 'eps:$showId';
  final (has, cached) = await _MetaCache.get(cacheKey);
  Map<String, EpisodeInfo> read(Object? j) => {
    for (final e in (j is List ? j : const []).whereType<Map>())
      '${e['s']}:${e['n']}': (
        name: '${e['t'] ?? ''}',
        image: e['i'] as String?,
        summary: '${e['o'] ?? ''}',
        aired: DateTime.tryParse('${e['a'] ?? ''}'),
        rating: double.tryParse('${e['r'] ?? ''}'),
      ),
  };
  if (has) return read(cached);
  try {
    List<Map<String, Object?>> slim;
    if (showId.startsWith('tt')) {
      final j = await _get(Uri.parse('https://v3-cinemeta.strem.io/meta/series/$showId.json'));
      final videos = ((j is Map ? j['meta'] : null) as Map?)?['videos'] as List? ?? const [];
      slim = [
        for (final e in videos.whereType<Map>())
          {'s': e['season'], 'n': e['episode'] ?? e['number'], 't': e['name'] ?? e['title'], 'i': e['thumbnail'], 'o': '${e['overview'] ?? e['description'] ?? ''}', 'a': e['released'] ?? e['firstAired'], 'r': e['rating']},
      ];
    } else {
      final j = await _get(Uri.parse('https://api.tvmaze.com/shows/$showId/episodes'));
      slim = [
        for (final e in (j is List ? j : const []).whereType<Map>())
          {
            's': e['season'],
            'n': e['number'],
            't': e['name'],
            'i': (e['image'] as Map?)?['medium'],
            'o': _stripHtml('${e['summary'] ?? ''}'),
            'a': e['airdate'],
            'r': (e['rating'] as Map?)?['average'],
          },
      ];
    }
    await _MetaCache.put(cacheKey, slim);
    return read(slim);
  } catch (_) {
    return const {};
  }
});

// ---- what's kept on the phone --------------------------------------------------

// ---- series the person puts together ------------------------------------------

/// A season of a made-up series: the channels its episodes come from.
@immutable
class CustomSeason {
  const CustomSeason({required this.number, this.name = '', this.sources = const []});
  final int number;
  final String name;
  final List<SourceRef> sources;

  CustomSeason copyWith({int? number, String? name, List<SourceRef>? sources}) => CustomSeason(number: number ?? this.number, name: name ?? this.name, sources: sources ?? this.sources);
  Map<String, dynamic> toJson() => {'n': number, if (name.isNotEmpty) 'name': name, 'src': [for (final x in sources) x.toJson()]};
  factory CustomSeason.fromJson(Map j) => CustomSeason(
    number: (j['n'] as num?)?.toInt() ?? 1,
    name: '${j['name'] ?? ''}',
    sources: [for (final x in (j['src'] as List? ?? const [])) if (x is Map) SourceRef.fromJson(x)],
  );
}

/// A series the person put together: a name, channels for all of it
/// (whose posts are sorted into seasons by "S02E03" and the like), and
/// seasons with channels of their own (whose videos are that season's
/// episodes, in the order they were posted).
@immutable
class CustomSeries {
  const CustomSeries({required this.id, required this.name, this.year, this.sources = const [], this.seasons = const [], required this.createdAt, this.poster = 'channel', this.posterPath});
  final String id;

  /// Where its poster comes from: 'channel' (its poster posts, else the
  /// channel's photo), 'online' (looked up by name) or 'picture'
  /// ([posterPath], picked from the gallery).
  final String poster;
  final String? posterPath;
  final String name;
  final int? year;
  final List<SourceRef> sources;
  final List<CustomSeason> seasons;
  final DateTime createdAt;

  String get key => 'custom:$id';
  Iterable<SourceRef> get allSources => [...sources, for (final s in seasons) ...s.sources];

  CustomSeries copyWith({String? name, int? year, bool clearYear = false, List<SourceRef>? sources, List<CustomSeason>? seasons, String? poster, String? posterPath}) => CustomSeries(
    poster: poster ?? this.poster,
    posterPath: posterPath ?? this.posterPath,
    id: id,
    name: name ?? this.name,
    year: clearYear ? null : (year ?? this.year),
    sources: sources ?? this.sources,
    seasons: seasons ?? this.seasons,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (year != null) 'y': year,
    'src': [for (final x in sources) x.toJson()],
    'seasons': [for (final x in seasons) x.toJson()],
    'at': createdAt.millisecondsSinceEpoch,
    'poster': poster,
    if (posterPath != null) 'poster_path': posterPath,
  };

  factory CustomSeries.fromJson(Map j) => CustomSeries(
    poster: '${j['poster'] ?? 'channel'}',
    posterPath: j['poster_path'] as String?,
    id: '${j['id']}',
    name: '${j['name'] ?? 'Series'}',
    year: (j['y'] as num?)?.toInt(),
    sources: [for (final x in (j['src'] as List? ?? const [])) if (x is Map) SourceRef.fromJson(x)],
    seasons: [for (final x in (j['seasons'] as List? ?? const [])) if (x is Map) CustomSeason.fromJson(x)],
    createdAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

/// [c] as a title: each season's channel videos numbered in posting order
/// (or by the episode number they give), the series' own channels sorted
/// by the season and episode they name.
CinemaTitle buildCustomSeries(CustomSeries c, VideoFeedState feed, String account) {
  final t = CinemaTitle(
    key: c.key,
    kind: TitleKind.show,
    title: c.name,
    year: c.year,
    customId: c.id,
    customPoster: c.poster == 'picture' ? c.posterPath : null,
    posterChat: c.allSources.where((s) => s.account == account).firstOrNull,
    posterOnline: c.poster == 'online',
  );
  void put(int season, int? number, Video v) {
    final eps = t.seasons.putIfAbsent(season, () => {});
    if (eps.values.any((e) => e.versions.any((x) => x.key == v.key))) return;
    var n = number ?? 0;
    if (n <= 0 || (eps[n] != null && eps[n]!.versions.isNotEmpty && number == null)) {
      n = 1;
      while (eps.containsKey(n)) {
        n++;
      }
    }
    eps.putIfAbsent(n, () => Episode(season, n)).versions.add(v);
  }

  List<Video> videosOf(Iterable<SourceRef> sources) => [
    for (final s in sources)
      if (s.account == account) ...?feed.bySource[s.key],
  ]..sort((a, b) => a.date.compareTo(b.date));

  for (final season in c.seasons) {
    t.seasons.putIfAbsent(season.number, () => {});
    final vids = videosOf(season.sources);
    // Numbered ones first, so the unnumbered fill the gaps after them.
    for (final v in vids) {
      final r = parseRelease(v);
      if (r != null && r.kind == TitleKind.show && r.episode > 0) put(season.number, r.episode, v);
    }
    for (final v in vids) {
      final r = parseRelease(v);
      if (!(r != null && r.kind == TitleKind.show && r.episode > 0)) put(season.number, null, v);
    }
  }
  final wide = videosOf(c.sources);
  for (final v in wide) {
    final r = parseRelease(v);
    if (r != null && r.kind == TitleKind.show && r.episode > 0) put(r.season <= 0 ? 1 : r.season, r.episode, v);
  }
  for (final v in wide) {
    final r = parseRelease(v);
    if (!(r != null && r.kind == TitleKind.show && r.episode > 0)) put(c.seasons.firstOrNull?.number ?? 1, null, v);
  }
  return t;
}

@immutable
class CinemaState {
  const CinemaState({this.sources = const [], this.watchlist = const [], this.inDrawer = true, this.posterPosts = true, this.series = const []});
  final List<SourceRef> sources;

  /// Series the person put together.
  final List<CustomSeries> series;

  /// Every channel to read: the catalogue's and the made-up series'.
  List<SourceRef> get allSources {
    final seen = <String>{};
    return [for (final s in [...sources, for (final c in series) ...c.allSources]) if (seen.add(s.key)) s];
  }

  /// Also read poster posts (no video, just the details and links).
  final bool posterPosts;

  /// Title keys, newest first.
  final List<String> watchlist;
  final bool inDrawer;

  CinemaState copyWith({List<SourceRef>? sources, List<String>? watchlist, bool? inDrawer, bool? posterPosts, List<CustomSeries>? series}) => CinemaState(
    sources: sources ?? this.sources,
    watchlist: watchlist ?? this.watchlist,
    inDrawer: inDrawer ?? this.inDrawer,
    posterPosts: posterPosts ?? this.posterPosts,
    series: series ?? this.series,
  );
}

class CinemaStore extends Notifier<CinemaState> {
  static const _key = 'cinema.v1';
  late Future<void> ready;

  /// Whether the saved settings have been read (until then, no sources
  /// means "not known yet", not "none").
  bool isReady = false;

  @override
  CinemaState build() {
    ready = _load().whenComplete(() {
      isReady = true;
      state = state.copyWith();
    });
    return const CinemaState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = CinemaState(
        sources: [for (final s in (j['sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        watchlist: [for (final s in (j['watchlist'] as List? ?? const [])) '$s'],
        inDrawer: j['in_drawer'] != false,
        posterPosts: j['poster_posts'] != false,
        series: [for (final x in (j['series'] as List? ?? const [])) if (x is Map) CustomSeries.fromJson(x)],
      );
    } catch (e) {
      debugPrint('[Cinema] $e');
    }
  }

  Future<void> _set(CinemaState s) async {
    state = s;
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({'sources': [for (final x in s.sources) x.toJson()], 'watchlist': s.watchlist, 'in_drawer': s.inDrawer, 'poster_posts': s.posterPosts, 'series': [for (final x in s.series) x.toJson()]}),
    );
  }

  Future<void> setSources(List<SourceRef> v) => _set(state.copyWith(sources: v));
  Future<void> removeSource(String k) => _set(state.copyWith(sources: [for (final s in state.sources) if (s.key != k) s]));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
  Future<void> setPosterPosts(bool v) => _set(state.copyWith(posterPosts: v));

  /// Adds [c], or replaces the series with its id.
  Future<void> saveSeries(CustomSeries c) => _set(state.copyWith(
    series: state.series.any((x) => x.id == c.id) ? [for (final x in state.series) x.id == c.id ? c : x] : [c, ...state.series],
  ));

  Future<void> deleteSeries(String id) => _set(state.copyWith(
    series: [for (final x in state.series) if (x.id != id) x],
    watchlist: [for (final k in state.watchlist) if (k != 'custom:$id') k],
  ));

  Future<bool> toggleWatchlist(String key) async {
    final on = !state.watchlist.contains(key);
    await _set(state.copyWith(watchlist: on ? [key, ...state.watchlist] : [for (final k in state.watchlist) if (k != key) k]));
    return on;
  }
}

final cinemaProvider = NotifierProvider<CinemaStore, CinemaState>(CinemaStore.new);

/// The catalogue of the active account's Cinema channels: their videos,
/// and their poster posts unless those are off.
List<CinemaTitle> cinemaCatalog(CinemaState c, VideoFeedState feed, String account, [InfoFeedState? infos]) {
  final custom = [for (final x in c.series) buildCustomSeries(x, feed, account)];
  // A channel that feeds a made-up series isn't read again for the rest
  // of the catalogue.
  final taken = {for (final x in c.series) for (final s in x.allSources) s.key};
  final auto = buildCatalog(
    [
      for (final s in c.sources)
        if (s.account == account && !taken.contains(s.key)) ...?feed.bySource[s.key],
    ],
    [
      if (c.posterPosts && infos != null)
        for (final s in c.sources)
          if (s.account == account) ...?infos.bySource[s.key],
    ],
  );
  // A made-up series takes the poster posts about it.
  for (final t in custom) {
    final same = auto.where((a) => a.isShow && !a.hasVideo && titleKey(a.title) == titleKey(t.title)).toList();
    for (final a in same) {
      t.infos.addAll(a.infos);
      auto.remove(a);
    }
  }
  return [...custom, ...auto]..sort((a, b) => b.updated.compareTo(a.updated));
}
