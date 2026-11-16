import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/net/http_cache.dart';
import '../media/audio_center.dart';
import 'podcast_models.dart';

/// Live stations from Radio Browser (radio-browser.info), a free community
/// directory, with TuneIn's public directory as the fallback when Radio
/// Browser is down. Neither needs a key. Ported from Alexandria.
class RadioStore extends ChangeNotifier {
  RadioStore(this._ref) {
    ready = _load();
  }

  final Ref _ref;
  late final Future<void> ready;

  static const servers = ['de1', 'de2', 'fi1', 'at1', 'nl1'];
  static const pageSize = 60;

  static const genres = [
    ('news', 'News'), ('talk', 'Talk'), ('pop', 'Pop'), ('rock', 'Rock'), ('jazz', 'Jazz'), ('classical', 'Classical'), //
    ('christian', 'Christian'), ('gospel', 'Gospel'), ('orthodox', 'Orthodox'), ('islamic', 'Islamic'), ('quran', 'Quran'), //
    ('hiphop', 'Hip hop'), ('afrobeats', 'Afrobeats'), ('rnb', 'R&B'), ('soul', 'Soul'), ('funk', 'Funk'), ('blues', 'Blues'), ('reggae', 'Reggae'), //
    ('dance', 'Dance'), ('electronic', 'Electronic'), ('house', 'House'), ('techno', 'Techno'), ('trance', 'Trance'), ('disco', 'Disco'), //
    ('alternative', 'Alternative'), ('indie', 'Indie'), ('classic rock', 'Classic rock'), ('metal', 'Metal'), ('punk', 'Punk'), //
    ('ambient', 'Ambient'), ('lofi', 'Lo-fi'), ('chillout', 'Chillout'), ('lounge', 'Lounge'), ('easy listening', 'Easy listening'), //
    ('smooth jazz', 'Smooth jazz'), ('instrumental', 'Instrumental'), ('piano', 'Piano'), ('meditation', 'Meditation'), //
    ('country', 'Country'), ('folk', 'Folk'), ('world music', 'World'), ('african', 'African'), ('latin', 'Latin'), ('salsa', 'Salsa'), //
    ('reggaeton', 'Reggaeton'), ('arabic', 'Arabic'), ('bollywood', 'Bollywood'), ('kpop', 'K-pop'), ('anime', 'Anime'), //
    ('top 40', 'Top 40'), ('oldies', 'Oldies'), ('60s', '60s'), ('70s', '70s'), ('80s', '80s'), ('90s', '90s'), ('2000s', '2000s'), //
    ('sports', 'Sports'), ('public radio', 'Public radio'), ('culture', 'Culture'), ('education', 'Education'), ('comedy', 'Comedy'), //
    ('kids', 'Kids'), ('old time radio', 'Old-time radio'), ('christmas', 'Christmas'),
  ];

  /// Stations kept: favourited, rated, noted or played recently.
  final Map<String, Station> stations = {};
  final Map<String, UserMark> marks = {};
  final List<String> recent = [];

  /// The country browsed: a two-letter code (or a TuneIn region `ti:…`),
  /// and its name; empty for every country.
  String country = '';
  String countryName = '';
  bool inDrawerOnly = false;

  bool unreachable = false;
  bool usingFallback = false;
  DateTime? _downUntil;
  int _server = 0;
  final Map<String, Station> _seen = {};
  /// Directory answers, kept on disk so the lists open instantly.
  final HttpCache _cache = HttpCache('radio', maxEntries: 300);
  static const _ua = {'User-Agent': 'Triangle/1.0 (radio)'};

  // ---- storage ----------------------------------------------------------------------

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/radio.json');

  Future<void> _load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final e in ((j['stations'] as Map?) ?? const {}).entries) {
        if (e.value is Map) stations['${e.key}'] = Station.fromJson(e.value as Map);
      }
      for (final e in ((j['marks'] as Map?) ?? const {}).entries) {
        marks['${e.key}'] = UserMark.fromJson(e.value);
      }
      recent.addAll([for (final id in (j['recent'] as List? ?? const [])) '$id']);
      country = '${j['country'] ?? ''}';
      countryName = '${j['countryName'] ?? ''}';
    } catch (e) {
      debugPrint('[Radio] load: $e');
    }
    notifyListeners();
  }

  Timer? _pending;

  void _persist() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 600), () async {
      try {
        final f = await _file();
        await f.writeAsString(jsonEncode({
          'stations': {for (final e in stations.entries) e.key: e.value.toJson()},
          'marks': {for (final e in marks.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
          'recent': recent,
          'country': country,
          'countryName': countryName,
        }));
      } catch (e) {
        debugPrint('[Radio] save: $e');
      }
    });
    notifyListeners();
  }

  void setCountry(String code, String name) {
    country = code;
    countryName = name;
    _persist();
  }

  // ---- the network ------------------------------------------------------------------

  /// [url]'s text: a kept copy when it's young enough (or, with
  /// [staleFirst], any copy, refreshed behind the scenes).
  Future<String?> _http(String url, {Duration ttl = const Duration(hours: 12), Duration timeout = const Duration(seconds: 8), String? cacheKey, bool force = false, bool staleFirst = true}) async =>
      (await _cache.get(url, ttl: ttl, timeout: timeout, headers: _ua, key: cacheKey, force: force, staleFirst: staleFirst && !force))?.body;

  static List<dynamic>? _decodeList(String? body) {
    if (body == null) return null;
    try {
      final j = jsonDecode(body);
      return j is List ? j : const [];
    } catch (_) {
      return null;
    }
  }

  /// Asks each Radio Browser server in turn; when none answers, the last
  /// copy kept (however old); null if there's none.
  Future<List<dynamic>?> _get(String pathAndQuery, Duration ttl, {bool force = false}) async {
    final key = 'rb$pathAndQuery';
    final down = _downUntil;
    if (down == null || DateTime.now().isAfter(down)) {
      for (var n = 0; n < servers.length; n++) {
        final at = (_server + n) % servers.length;
        final r = await _cache.get('https://${servers[at]}.api.radio-browser.info$pathAndQuery', ttl: ttl, timeout: const Duration(seconds: 8), headers: _ua, key: key, force: force, staleFirst: !force, okOnly: true);
        final list = _decodeList(r?.body);
        if (list == null) continue;
        _server = at;
        return list;
      }
      _downUntil = DateTime.now().add(const Duration(minutes: 5));
    }
    return _decodeList((await _cache.peek(key))?.body);
  }

  /// Stations, most popular first, by name, country and genre.
  Future<List<Station>> browse({String? name, String? tag, int offset = 0, String order = 'clickcount', bool force = false}) async {
    unreachable = false;
    if (!country.startsWith('ti:')) {
      final q = <String, String>{
        'hidebroken': 'true',
        'is_https': 'true',
        'order': order,
        'reverse': 'true',
        'limit': '$pageSize',
        'offset': '$offset',
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (country.isNotEmpty) 'countrycode': country,
        if (tag != null && tag.isNotEmpty) ...{'tag': tag, 'tagExact': 'true'},
      };
      final list = await _get(Uri(path: '/json/stations/search', queryParameters: q).toString(), const Duration(hours: 12), force: force);
      if (list != null) {
        usingFallback = false;
        return _remember(list.whereType<Map>().map(Station.fromDirectory));
      }
    }
    usingFallback = true;
    return offset > 0 ? const [] : _tuneIn(name: name, tag: tag, force: force);
  }

  List<Station> _remember(Iterable<Station?> list) {
    final seen = <String>{};
    final out = <Station>[];
    for (final s in list) {
      if (s == null || !seen.add(s.name.toLowerCase())) continue;
      _seen[s.id] = s;
      out.add(s);
    }
    return out;
  }

  Future<List<RadioCountry>> countries() async {
    final list = await _get('/json/countries?hidebroken=true', const Duration(days: 7));
    if (list == null) return _tuneInCountries();
    return [
      for (final m in list.whereType<Map>())
        if ('${m['iso_3166_1'] ?? ''}'.length == 2 && ((m['stationcount'] as num?)?.toInt() ?? 0) > 0)
          RadioCountry('${m['iso_3166_1']}'.toUpperCase(), '${m['name'] ?? ''}'.trim(), (m['stationcount'] as num).toInt()),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ---- TuneIn ----------------------------------------------------------------------

  static const _tuneInBase = 'https://opml.radiotime.com';
  static const _continents = ['r101215', 'r101216', 'r100297', 'r101320', 'r101217', 'r101218', 'r101219'];

  Future<Map?> _tuneInGet(String pathAndQuery, Duration ttl, {bool force = false}) async {
    final body = await _http('$_tuneInBase$pathAndQuery${pathAndQuery.contains('?') ? '&' : '?'}render=json', ttl: ttl, timeout: const Duration(seconds: 12), force: force);
    if (body == null) {
      unreachable = true;
      return null;
    }
    try {
      final j = jsonDecode(body);
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  static Iterable<Map> _outlines(dynamic list) sync* {
    for (final m in (list is List ? list : const []).whereType<Map>()) {
      yield m;
      yield* _outlines(m['children']);
    }
  }

  Future<List<Station>> _tuneIn({String? name, String? tag, bool force = false}) async {
    final query = (name ?? '').trim();
    final words = (tag ?? '').trim();
    String? region = country.startsWith('ti:') ? country.substring(3) : null;
    if (region == null && country.isNotEmpty && countryName.isNotEmpty) {
      final want = countryName.toLowerCase();
      for (final c in await _tuneInCountries()) {
        if (c.name.toLowerCase() == want) region = c.code.substring(3);
      }
    }
    final Map? j;
    if (region != null) {
      j = await _tuneInGet('/Browse.ashx?id=$region&formats=mp3,aac', const Duration(days: 1), force: force);
    } else if (query.isNotEmpty || words.isNotEmpty) {
      j = await _tuneInGet('/Search.ashx?query=${Uri.encodeQueryComponent([query, words].where((x) => x.isNotEmpty).join(' '))}&types=station&formats=mp3,aac', const Duration(days: 1), force: force);
    } else {
      j = await _tuneInGet('/Browse.ashx?c=trending&formats=mp3,aac', const Duration(hours: 6), force: force);
    }
    var list = _remember(_outlines(j?['body']).map(Station.fromTuneIn));
    if (region != null) {
      for (final w in [query, words]) {
        if (w.isEmpty) continue;
        final lower = w.toLowerCase();
        list = list.where((s) => s.name.toLowerCase().contains(lower) || s.tags.any((t) => t.toLowerCase().contains(lower))).toList();
      }
    }
    return list;
  }

  Future<List<RadioCountry>> _tuneInCountries() async {
    final parts = await Future.wait(_continents.map((c) => _tuneInGet('/Browse.ashx?id=$c', const Duration(days: 30))));
    final seen = <String>{};
    return [
      for (final j in parts)
        for (final m in _outlines(j?['body']))
          if ('${m['guide_id'] ?? ''}'.startsWith('r') && seen.add('${m['guide_id']}')) RadioCountry('ti:${m['guide_id']}', '${m['text'] ?? ''}'.trim(), 0),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The address to actually play: TuneIn hands out several; https is what
  /// phones allow, and a direct stream beats a playlist file.
  Future<String?> _resolve(Station s) async {
    if (!s.needsResolving) return s.url;
    final body = await _http(s.url, ttl: const Duration(days: 1), timeout: const Duration(seconds: 12), staleFirst: false);
    if (body == null) return null;
    try {
      final j = jsonDecode(body);
      final options = (j is Map && j['body'] is List ? j['body'] as List : const []).whereType<Map>().where((e) => '${e['url'] ?? ''}'.startsWith('https://')).toList();
      if (options.isEmpty) return null;
      final direct = options.where((e) => e['is_direct'] != false);
      return '${(direct.isNotEmpty ? direct.first : options.first)['url']}';
    } catch (_) {
      return null;
    }
  }

  // ---- yours ------------------------------------------------------------------------

  Station? stationFor(String id) => stations[id] ?? _seen[id];
  UserMark markOf(String id) => marks[id] ??= UserMark();
  bool isFavorite(String id) => marks[id]?.favorite ?? false;

  void changed(Station s) {
    stations[s.id] = s;
    _persist();
  }

  void toggleFavorite(Station s) {
    final m = markOf(s.id);
    m.favorite = !m.favorite;
    changed(s);
  }

  void forgetRecent() {
    recent.clear();
    _persist();
  }

  List<Station> get favorites => [for (final e in marks.entries) if (e.value.favorite && stations[e.key] != null) stations[e.key]!]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<Station> get recents => [for (final id in recent) ?stations[id]];

  // ---- playing ----------------------------------------------------------------------

  static String trackKey(String id) => 'radio:$id';

  bool isCurrent(String id) => _ref.read(audioCenterProvider).current?.key == trackKey(id);
  bool isPlaying(String id) {
    final a = _ref.read(audioCenterProvider);
    return a.current?.key == trackKey(id) && a.playing;
  }

  Track trackOf(Station s) => Track.stream(
    url: s.needsResolving ? '' : s.url,
    identifier: trackKey(s.id),
    title: s.name,
    subtitle: s.subtitle.isEmpty ? 'Live radio' : s.subtitle,
    artUrl: s.favicon,
    live: true,
    queueTag: 'radio',
    resolve: s.needsResolving
        ? () async {
            final url = await _resolve(s);
            return url == null ? null : Track.stream(url: url, identifier: trackKey(s.id), title: s.name, subtitle: s.subtitle, artUrl: s.favicon, live: true, queueTag: 'radio');
          }
        : null,
  );

  /// Plays [s]; [around] (a list it was picked from) lets the player's next
  /// and previous move through stations like a dial.
  Future<void> play(Station s, {List<Station>? around}) async {
    final audio = _ref.read(audioCenterProvider);
    if (isCurrent(s.id)) return audio.toggle();
    stations[s.id] = s;
    recent
      ..remove(s.id)
      ..insert(0, s.id);
    if (recent.length > 40) recent.removeLast();
    _persist();
    if (!s.needsResolving) {
      http.get(Uri.parse('https://${servers[_server]}.api.radio-browser.info/json/url/${s.id}'), headers: const {'User-Agent': 'Triangle/1.0 (radio)'}).timeout(const Duration(seconds: 8)).then((_) {}, onError: (_) {});
    }
    final list = around ?? (isFavorite(s.id) ? favorites : [s]);
    if (audio.shuffle) audio.setShuffle(false);
    for (final x in list) {
      _seen[x.id] = x;
    }
    await audio.play(trackOf(s), playlist: [for (final x in list.any((x) => x.id == s.id) ? list : [s]) trackOf(x)]);
  }

  /// The station playing now, if the radio is.
  Station? get nowPlaying {
    final k = _ref.read(audioCenterProvider).current?.key;
    if (k == null || !k.startsWith('radio:')) return null;
    return stationFor(k.substring(6));
  }
}

final radioProvider = ChangeNotifierProvider<RadioStore>((ref) => RadioStore(ref));
