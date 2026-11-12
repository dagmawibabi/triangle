import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/files/download_progress.dart';
import '../../core/files/generated_files.dart';

/// Free books, audiobooks, radio and podcasts, and a few public reference
/// sources, all keyless: Project Gutenberg (through Gutendex), Open
/// Library, LibriVox, the Internet Archive, Radio Browser, Apple's podcast
/// directory and the shows' own RSS feeds, an open countries dataset with
/// World Bank population, and NASA's
/// picture of the day. The chat tools and the cards' sheets both use it.
class LibraryApi {
  LibraryApi({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static final LibraryApi instance = LibraryApi();
  static const _ua = {'user-agent': 'Triangle/1.0 (personal assistant; free media catalogue)'};

  Future<Object?> _json(Uri url, {Duration timeout = const Duration(seconds: 25)}) async {
    final r = await _http.get(url, headers: {..._ua, 'accept': 'application/json'}).timeout(timeout);
    if (r.statusCode == 404) throw LibraryException('Not found at ${url.host}.');
    if (r.statusCode == 429) throw LibraryException('${url.host} is busy (rate limited); try again in a bit.');
    if (r.statusCode >= 400) throw LibraryException('${url.host} said ${r.statusCode}.');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<String> _text(Uri url, {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _http.get(url, headers: _ua).timeout(timeout);
    if (r.statusCode >= 400) throw LibraryException('${url.host} said ${r.statusCode}.');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  static String plain(Object? s) {
    final t = '${s ?? ''}';
    if (t.isEmpty) return '';
    return (html_parser.parseFragment(t.replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')).text ?? t)
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  static int seconds(Object? v) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty) return 0;
    if (s.contains(':')) return s.split(':').map((x) => double.tryParse(x) ?? 0).fold(0.0, (a, x) => a * 60 + x).round();
    return (double.tryParse(s) ?? 0).round();
  }

  // ---- ebooks: Project Gutenberg via Gutendex ----------------------------------------

  static Map<String, dynamic> _gutenbergBook(Map r) {
    final f = (r['formats'] as Map?) ?? const {};
    String? fmt(bool Function(String) test) => f.entries.where((e) => test('${e.key}') && !'${e.value}'.endsWith('.zip')).map((e) => '${e.value}').firstOrNull;
    String flip(String n) {
      final p = n.split(', ');
      return p.length == 2 ? '${p[1]} ${p[0]}' : n;
    }

    return {
      'id': r['id'],
      'title': r['title'],
      'authors': [
        for (final a in (r['authors'] as List? ?? const []).whereType<Map>())
          {'name': flip('${a['name'] ?? ''}'), if (a['birth_year'] != null) 'years': '${a['birth_year']}–${a['death_year'] ?? ''}'},
      ],
      'languages': r['languages'],
      'subjects': (r['subjects'] as List? ?? const []).take(6).toList(),
      'bookshelves': (r['bookshelves'] as List? ?? const []).map((b) => '$b'.replaceFirst('Category: ', '')).take(4).toList(),
      if ((r['summaries'] as List?)?.isNotEmpty == true)
        'summary': clip('${(r['summaries'] as List).first}'.replaceFirst(RegExp(r'\s*\(This is an automatically generated summary\.\)\s*$'), ''), 900),
      'downloads': r['download_count'],
      'cover': f['image/jpeg'],
      'epub': fmt((k) => k.startsWith('application/epub')),
      'kindle': fmt((k) => k.startsWith('application/x-mobipocket')),
      'text': fmt((k) => k.startsWith('text/plain')),
      'html': fmt((k) => k.startsWith('text/html')),
      'url': 'https://www.gutenberg.org/ebooks/${r['id']}',
      'source': 'Project Gutenberg',
    };
  }

  /// Free public-domain ebooks. [topic] matches subjects and bookshelves.
  Future<({int total, List<Map<String, dynamic>> books})> ebooks({String query = '', String topic = '', String language = '', String sort = 'popular', int page = 1}) async {
    final j = await _json(
      Uri.https('gutendex.com', '/books/', {
        if (query.trim().isNotEmpty) 'search': query.trim(),
        if (topic.trim().isNotEmpty) 'topic': topic.trim(),
        if (language.trim().isNotEmpty) 'languages': language.trim().toLowerCase(),
        'sort': sort == 'new' ? 'descending' : (sort == 'old' ? 'ascending' : 'popular'),
        if (page > 1) 'page': '$page',
      }),
      timeout: const Duration(seconds: 40),
    ) as Map;
    return (
      total: (j['count'] as num?)?.toInt() ?? 0,
      books: [for (final r in (j['results'] as List? ?? const []).whereType<Map>()) _gutenbergBook(r)],
    );
  }

  Future<Map<String, dynamic>> ebook(int id) async => _gutenbergBook(await _json(Uri.https('gutendex.com', '/books/$id/'), timeout: const Duration(seconds: 40)) as Map);

  /// A Gutenberg book's plain text, without the licence header and footer.
  Future<String> ebookText(String url) async {
    final uri = Uri.parse(url);
    var t = uri.scheme == 'file' ? await File.fromUri(uri).readAsString() : await _text(uri, timeout: const Duration(seconds: 60));
    final start = RegExp(r'\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG EBOOK[^\n]*\n', caseSensitive: false).firstMatch(t);
    if (start != null) t = t.substring(start.end);
    final end = RegExp(r'\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG EBOOK', caseSensitive: false).firstMatch(t);
    if (end != null) t = t.substring(0, end.start);
    return t.replaceAll('\r\n', '\n').trim();
  }

  /// Any book (not only free ones) in Open Library's catalogue.
  Future<List<Map<String, dynamic>>> openLibrary(String query, {int limit = 12}) async {
    final j = await _json(Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'limit': '$limit',
      'fields': 'key,title,author_name,first_publish_year,cover_i,subject,number_of_pages_median,ratings_average,ebook_access,ia,edition_count',
    })) as Map;
    return [
      for (final d in (j['docs'] as List? ?? const []).whereType<Map>())
        {
          'title': d['title'],
          'authors': [for (final a in (d['author_name'] as List? ?? const []).take(3)) {'name': '$a'}],
          'year': d['first_publish_year'],
          'pages': d['number_of_pages_median'],
          'rating': d['ratings_average'] is num ? double.parse((d['ratings_average'] as num).toStringAsFixed(1)) : null,
          'editions': d['edition_count'],
          'subjects': (d['subject'] as List? ?? const []).take(5).toList(),
          if (d['cover_i'] != null) 'cover': 'https://covers.openlibrary.org/b/id/${d['cover_i']}-L.jpg',
          'free_to_read': d['ebook_access'] == 'public',
          if (d['ebook_access'] == 'public' && (d['ia'] as List?)?.isNotEmpty == true) 'read_url': 'https://archive.org/details/${(d['ia'] as List).first}',
          'url': 'https://openlibrary.org${d['key']}',
          'source': 'Open Library',
        },
    ];
  }

  // ---- audiobooks: LibriVox and the Internet Archive -----------------------------------

  static String? _archiveId(String? url) {
    final seg = Uri.tryParse(url ?? '')?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    return seg.length >= 2 && seg[seg.length - 2] == 'details' ? seg.last : null;
  }

  static Map<String, dynamic> _librivox(Map b) {
    final ia = _archiveId(b['url_iarchive'] as String?);
    return {
      'source': 'librivox',
      'id': '${b['id']}',
      'title': plain(b['title']),
      'author': (b['authors'] as List? ?? const []).whereType<Map>().map((a) => '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim()).where((s) => s.isNotEmpty).join(', '),
      'description': clip(plain(b['description']), 700),
      'language': b['language'],
      'seconds': seconds(b['totaltimesecs']),
      'sections': int.tryParse('${b['num_sections'] ?? ''}'),
      if (ia != null) 'cover': 'https://archive.org/services/img/$ia',
      'url': b['url_librivox'] ?? 'https://librivox.org',
    };
  }

  /// Free audiobooks, from LibriVox (volunteer readings of public-domain
  /// books) and the Internet Archive's audiobook collection.
  Future<List<Map<String, dynamic>>> audiobooks(String query, {String source = 'all', int limit = 15}) async {
    final q = query.trim();
    const fields = '{id,title,authors,description,totaltimesecs,num_sections,language,url_iarchive,url_librivox}';
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    if (source != 'archive') {
      final urls = q.isEmpty
          ? [Uri.parse('https://librivox.org/api/feed/audiobooks/?format=json&fields=$fields&limit=$limit&offset=${DateTime.now().day * 7}')]
          : [
              Uri.parse('https://librivox.org/api/feed/audiobooks/?format=json&fields=$fields&limit=$limit&title=${Uri.encodeQueryComponent('^$q')}'),
              Uri.parse('https://librivox.org/api/feed/audiobooks/?format=json&fields=$fields&limit=8&author=${Uri.encodeQueryComponent(q.split(' ').last)}'),
            ];
      for (final j in await Future.wait(urls.map((u) => _json(u).then<Object?>((v) => v, onError: (_) => null)))) {
        for (final b in ((j is Map ? j['books'] : null) as List? ?? const []).whereType<Map>()) {
          if (seen.add(plain(b['title']).toLowerCase())) out.add(_librivox(b));
        }
      }
    }
    if (source != 'librivox' && q.isNotEmpty) {
      try {
        for (final b in await _archive(q, limit: limit)) {
          if (seen.add('${b['title']}'.toLowerCase())) out.add(b);
        }
      } catch (_) {}
    }
    return out.take(limit * 2).toList();
  }

  Future<List<Map<String, dynamic>>> _archive(String q, {int limit = 15}) async {
    final clean = q.replaceAll(RegExp(r'[():"]'), ' ');
    final j = await _json(Uri.https('archive.org', '/advancedsearch.php', {
      'q': '(collection:(librivoxaudio) OR collection:(audio_bookspoetry)) AND mediatype:(audio) AND (title:($clean) OR creator:($clean))',
      'fl[]': ['identifier', 'title', 'creator', 'description', 'year', 'language', 'downloads'],
      'sort[]': 'downloads desc',
      'rows': '$limit',
      'output': 'json',
    })) as Map;
    String one(Object? v) => v is List ? v.map((e) => '$e').join(', ') : '${v ?? ''}';
    return [
      for (final d in ((j['response'] as Map?)?['docs'] as List? ?? const []).whereType<Map>())
        {
          'source': 'archive',
          'id': '${d['identifier']}',
          'title': plain(one(d['title'])),
          'author': one(d['creator']),
          'description': clip(plain(one(d['description'])), 700),
          'language': one(d['language']),
          'year': one(d['year']),
          'downloads': d['downloads'],
          'cover': 'https://archive.org/services/img/${d['identifier']}',
          'url': 'https://archive.org/details/${d['identifier']}',
        },
    ];
  }

  /// An audiobook's chapters, each a stream to play or download.
  Future<List<Map<String, dynamic>>> audiobookTracks(String source, String id) async {
    if (source == 'librivox') {
      final j = await _json(Uri.parse('https://librivox.org/api/feed/audiobooks/?format=json&extended=1&id=$id')) as Map;
      final b = (j['books'] as List?)?.whereType<Map>().firstOrNull;
      final sections = ((b?['sections'] as List?) ?? const []).whereType<Map>().toList()
        ..sort((x, y) => (int.tryParse('${x['section_number']}') ?? 0).compareTo(int.tryParse('${y['section_number']}') ?? 0));
      return [
        for (final s in sections)
          if ('${s['listen_url'] ?? ''}'.startsWith('http'))
            {
              'n': int.tryParse('${s['section_number']}'),
              'title': plain(s['title'] ?? 'Section ${s['section_number']}'),
              'url': '${s['listen_url']}'.replaceFirst('http://', 'https://'),
              'seconds': seconds(s['playtime']),
              if ((s['readers'] as List?)?.isNotEmpty == true) 'reader': ((s['readers'] as List).first as Map?)?['display_name'],
            },
      ];
    }
    final j = await _json(Uri.https('archive.org', '/metadata/$id')) as Map;
    final files = (j['files'] as List? ?? const []).whereType<Map>().toList();
    const prefs = ['VBR MP3', '128Kbps MP3', '64Kbps MP3', 'MP3'];
    final format = prefs.firstWhere((f) => files.any((x) => x['format'] == f), orElse: () => '');
    if (format.isEmpty) return const [];
    final chosen = files.where((f) => f['format'] == format).toList()
      ..sort((a, b) {
        final ta = int.tryParse('${a['track'] ?? ''}'.split('/').first) ?? 1 << 20;
        final tb = int.tryParse('${b['track'] ?? ''}'.split('/').first) ?? 1 << 20;
        return ta != tb ? ta.compareTo(tb) : '${a['name']}'.compareTo('${b['name']}');
      });
    return [
      for (final (i, f) in chosen.indexed)
        {
          'n': i + 1,
          'title': '${f['title'] ?? ''}'.trim().isNotEmpty ? '${f['title']}' : '${f['name']}'.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '').replaceAll('_', ' '),
          'url': 'https://archive.org/download/$id/${'${f['name']}'.split('/').map(Uri.encodeComponent).join('/')}',
          'seconds': seconds(f['length']),
        },
    ];
  }

  // ---- radio: Radio Browser -------------------------------------------------------------

  static const _radioServers = ['de1', 'de2', 'fi1', 'at1', 'nl1'];
  int _radioServer = 0;

  Future<List> _radio(String path, Map<String, String> query) async {
    Object? last;
    for (var n = 0; n < _radioServers.length; n++) {
      final at = (_radioServer + n) % _radioServers.length;
      try {
        final j = await _json(Uri.https('${_radioServers[at]}.api.radio-browser.info', path, query), timeout: const Duration(seconds: 8));
        _radioServer = at;
        return j is List ? j : const [];
      } catch (e) {
        last = e;
      }
    }
    throw LibraryException('Radio Browser didn\'t answer ($last).');
  }

  static Map<String, dynamic> station(Map s) => {
    'id': s['stationuuid'],
    'name': '${s['name'] ?? ''}'.trim(),
    'stream': s['url_resolved'] ?? s['url'],
    'homepage': '${s['homepage'] ?? ''}'.isEmpty ? null : s['homepage'],
    'logo': '${s['favicon'] ?? ''}'.startsWith('http') ? s['favicon'] : null,
    'country': s['country'],
    'country_code': s['countrycode'],
    'state': '${s['state'] ?? ''}'.isEmpty ? null : s['state'],
    'language': s['language'],
    'tags': '${s['tags'] ?? ''}'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).take(6).toList(),
    'codec': s['codec'],
    'bitrate': s['bitrate'],
    'votes': s['votes'],
    'listeners': s['clickcount'],
    'online': s['lastcheckok'] == 1,
  };

  /// Live radio stations, most listened first.
  Future<List<Map<String, dynamic>>> stations({String name = '', String country = '', String tag = '', String language = '', String order = 'clickcount', int limit = 20, int offset = 0}) async {
    final list = await _radio('/json/stations/search', {
      'hidebroken': 'true',
      'is_https': 'true',
      'order': const ['clickcount', 'votes', 'name', 'bitrate', 'random', 'clicktrend'].contains(order) ? order : 'clickcount',
      'reverse': order == 'name' ? 'false' : 'true',
      'limit': '$limit',
      'offset': '$offset',
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (country.trim().length == 2) 'countrycode': country.trim().toUpperCase() else if (country.trim().isNotEmpty) 'country': country.trim(),
      if (tag.trim().isNotEmpty) 'tag': tag.trim().toLowerCase(),
      if (language.trim().isNotEmpty) 'language': language.trim().toLowerCase(),
    });
    final seen = <String>{};
    return [
      for (final s in list.whereType<Map>())
        if (seen.add('${s['name']}'.trim().toLowerCase())) station(s),
    ];
  }

  /// Tells Radio Browser a station was played (its community counts).
  Future<void> countClick(String stationId) async {
    try {
      await _radio('/json/url/$stationId', const {});
    } catch (_) {}
  }

  // ---- podcasts: Apple's directory and RSS feeds ---------------------------------------

  static Map<String, dynamic> _show(Map r) => {
    'id': r['collectionId'] ?? r['id'],
    'title': r['collectionName'] ?? r['name'],
    'author': r['artistName'],
    'cover': r['artworkUrl600'] ?? r['artworkUrl100'],
    'genre': r['primaryGenreName'] ?? ((r['genres'] as List?)?.whereType<Map>().firstOrNull?['name']),
    'episodes': r['trackCount'],
    'feed': r['feedUrl'],
    'latest': '${r['releaseDate'] ?? ''}'.split('T').first,
    'explicit': r['collectionExplicitness'] == 'explicit' || r['contentAdvisoryRating'] == 'Explicit',
    'url': r['collectionViewUrl'] ?? r['url'],
  };

  Future<List<Map<String, dynamic>>> podcasts(String term, {String country = 'us', int limit = 15}) async {
    final j = await _json(Uri.https('itunes.apple.com', '/search', {
      'media': 'podcast',
      'entity': 'podcast',
      'term': term.trim().isEmpty ? 'podcast' : term.trim(),
      'country': country,
      'limit': '$limit',
    })) as Map;
    return [for (final r in (j['results'] as List? ?? const []).whereType<Map>()) if (r['feedUrl'] != null) _show(r)];
  }

  /// Today's most popular shows in [country].
  Future<List<Map<String, dynamic>>> topPodcasts({String country = 'us', int limit = 20}) async {
    final j = await _json(Uri.parse('https://rss.marketingtools.apple.com/api/v2/${country.toLowerCase()}/podcasts/top/${limit.clamp(10, 50)}/podcasts.json')) as Map;
    return [
      for (final (i, r) in (((j['feed'] as Map?)?['results'] as List?) ?? const []).whereType<Map>().indexed)
        {..._show(r), 'rank': i + 1, 'cover': '${r['artworkUrl100'] ?? ''}'.replaceAll('100x100', '600x600')},
    ];
  }

  /// A show's feed address, from its Apple id when the chart left it out.
  Future<String?> feedFor(Object id) async {
    final j = await _json(Uri.https('itunes.apple.com', '/lookup', {'id': '$id', 'entity': 'podcast'})) as Map;
    return (j['results'] as List?)?.whereType<Map>().firstOrNull?['feedUrl'] as String?;
  }

  /// A show and its latest episodes, from its RSS feed.
  Future<Map<String, dynamic>> podcastFeed(String url, {int limit = 20}) async {
    final body = await _text(Uri.parse(url), timeout: const Duration(seconds: 40));
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      throw const LibraryException('That feed isn\'t valid RSS.');
    }
    final ch = doc.findAllElements('channel').firstOrNull;
    if (ch == null) throw const LibraryException('That feed has no channel.');
    XmlElement? el(XmlElement e, String name) => e.childElements.where((c) => c.name.qualified == name).firstOrNull;
    String txt(XmlElement e, String name) => el(e, name)?.innerText.trim() ?? '';
    String? img(XmlElement e) => el(e, 'itunes:image')?.getAttribute('href') ?? el(e, 'image')?.childElements.where((c) => c.name.local == 'url').firstOrNull?.innerText.trim();
    final cover = img(ch);
    final episodes = <Map<String, dynamic>>[];
    for (final it in ch.childElements.where((c) => c.name.local == 'item')) {
      final enc = el(it, 'enclosure');
      final audio = enc?.getAttribute('url')?.trim() ?? '';
      if (audio.isEmpty || (enc?.getAttribute('type') ?? '').startsWith('video/')) continue;
      final desc = [txt(it, 'description'), txt(it, 'itunes:summary'), txt(it, 'content:encoded')].firstWhere((d) => d.isNotEmpty, orElse: () => '');
      episodes.add({
        'title': plain(txt(it, 'title')),
        'audio': audio,
        'published': _rssDate(txt(it, 'pubDate'))?.toIso8601String().substring(0, 10),
        'seconds': seconds(txt(it, 'itunes:duration')),
        'description': clip(plain(desc), 500),
        'image': img(it),
        if (txt(it, 'itunes:episode').isNotEmpty) 'episode': int.tryParse(txt(it, 'itunes:episode')),
        if (txt(it, 'itunes:season').isNotEmpty) 'season': int.tryParse(txt(it, 'itunes:season')),
        if (txt(it, 'link').isNotEmpty) 'link': txt(it, 'link'),
      });
      if (episodes.length >= limit) break;
    }
    return {
      'title': plain(txt(ch, 'title')),
      'author': plain(txt(ch, 'itunes:author').isNotEmpty ? txt(ch, 'itunes:author') : txt(ch, 'managingEditor')),
      'description': clip(plain(txt(ch, 'description').isNotEmpty ? txt(ch, 'description') : txt(ch, 'itunes:summary')), 800),
      'cover': cover,
      'link': txt(ch, 'link').isEmpty ? null : txt(ch, 'link'),
      'categories': ch.childElements.where((c) => c.name.qualified == 'itunes:category').map((c) => c.getAttribute('text') ?? '').where((s) => s.isNotEmpty).toSet().take(5).toList(),
      'feed': url,
      'episodes': episodes,
    };
  }

  static DateTime? _rssDate(String s) {
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})').firstMatch(s);
    if (m == null) return DateTime.tryParse(s.trim());
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final mon = months.indexOf(m[2]!.toLowerCase()) + 1;
    return mon == 0 ? null : DateTime(int.parse(m[3]!), mon, int.parse(m[1]!));
  }

  // ---- Countries -----------------------------------------------------------------------
  //
  // REST Countries retired its free v3.1 API (it now answers every request
  // with a deprecation notice; v5 needs an account and key). So: the open
  // mledoze/countries dataset through jsDelivr for the facts, the World
  // Bank for population and flagcdn for flag images, all keyless. The
  // dataset (about 1.4 MB) is fetched once a session.

  static final _countriesUrl = Uri.https('cdn.jsdelivr.net', '/gh/mledoze/countries@master/countries.json');
  static final _populationUrl = Uri.https('api.worldbank.org', '/v2/country/all/indicator/SP.POP.TOTL', {'format': 'json', 'mrnev': '1', 'per_page': '400'});

  List<Map>? _countryData;
  Map<String, num>? _populationData;

  Future<List<Map>> _allCountries() async {
    if (_countryData != null) return _countryData!;
    final j = await _json(_countriesUrl, timeout: const Duration(seconds: 40));
    if (j is! List || j.length < 100) throw const LibraryException('The country list came back incomplete; try again in a moment.');
    return _countryData = j.whereType<Map>().toList(growable: false);
  }

  /// Latest population by ISO 3166 alpha-3 code; empty when the World
  /// Bank can't be reached (the rest still works).
  Future<Map<String, num>> _population() async {
    if (_populationData != null) return _populationData!;
    try {
      final j = await _json(_populationUrl);
      final rows = j is List && j.length > 1 && j[1] is List ? j[1] as List : const [];
      return _populationData = {
        for (final r in rows.whereType<Map>())
          if (r['value'] is num && '${r['countryiso3code'] ?? ''}'.length == 3) '${r['countryiso3code']}': r['value'] as num,
      };
    } catch (_) {
      return const {};
    }
  }

  static String? _continent(Map c) {
    final region = '${c['region'] ?? ''}';
    final sub = '${c['subregion'] ?? ''}';
    if (region == 'Americas') return sub.contains('South') ? 'South America' : 'North America';
    if (region == 'Antarctic') return 'Antarctica';
    return region.isEmpty ? null : region;
  }

  /// A country from the dataset as the tools and cards use it. Without
  /// [full], just enough for a list.
  static Map<String, dynamic> country(Map c, {bool full = true, num? population}) {
    final name = (c['name'] as Map?) ?? const {};
    final idd = (c['idd'] as Map?) ?? const {};
    final suffixes = (idd['suffixes'] as List? ?? const []);
    final code = '${c['cca2'] ?? ''}';
    final latlng = c['latlng'] as List?;
    return {
      'name': name['common'],
      'official': name['official'],
      'native': ((name['native'] ?? name['nativeName']) as Map?)?.values.whereType<Map>().firstOrNull?['common'],
      'code': c['cca2'],
      'code3': c['cca3'],
      'flag_emoji': c['flag'],
      if (code.length == 2) 'flag': 'https://flagcdn.com/w320/${code.toLowerCase()}.png',
      'capital': (c['capital'] as List?)?.join(', '),
      'region': c['region'],
      'subregion': c['subregion'],
      'population': population ?? c['population'],
      'area_km2': c['area'],
      if (full) ...{
        'languages': ((c['languages'] as Map?) ?? const {}).values.toList(),
        'currencies': [
          for (final e in ((c['currencies'] as Map?) ?? const {}).entries)
            {'code': e.key, 'name': (e.value as Map?)?['name'], 'symbol': (e.value as Map?)?['symbol']},
        ],
        'borders': c['borders'],
        'calling_code': idd['root'] == null ? null : '${idd['root']}${suffixes.length == 1 ? suffixes.first : ''}',
        'tld': (c['tld'] as List?)?.join(', '),
        'demonym': ((c['demonyms'] as Map?)?['eng'] as Map?)?['m'],
        'landlocked': c['landlocked'],
        'independent': c['independent'],
        'un_member': c['unMember'],
        'continents': [?_continent(c)],
        'latlng': latlng,
        if (latlng != null && latlng.length == 2) 'map': 'https://www.openstreetmap.org/#map=5/${latlng[0]}/${latlng[1]}',
      },
    };
  }

  /// One country by name or code ("Ethiopia", "ET", "ETH", "Côte d'Ivoire").
  Future<Map<String, dynamic>> countryInfo(String query) async {
    final q = query.trim();
    if (q.isEmpty) throw const LibraryException('Which country?');
    final all = await _allCountries();
    final lower = q.toLowerCase();
    String n(Object? v) => '${v ?? ''}'.toLowerCase();
    bool codeMatch(Map c) => q.length <= 3 && (n(c['cca2']) == lower || n(c['cca3']) == lower || n(c['cioc']) == lower);
    bool exact(Map c) {
      final name = (c['name'] as Map?) ?? const {};
      return n(name['common']) == lower || n(name['official']) == lower || (c['altSpellings'] as List? ?? const []).any((a) => n(a) == lower);
    }

    final hit = all.where(codeMatch).firstOrNull ??
        all.where(exact).firstOrNull ??
        all.where((c) => n((c['name'] as Map?)?['common']).startsWith(lower)).firstOrNull ??
        all.where((c) => n((c['name'] as Map?)?['common']).contains(lower) || n((c['name'] as Map?)?['official']).contains(lower)).firstOrNull;
    if (hit == null) throw LibraryException('No country called "$q".');
    return country(hit, population: (await _population())['${hit['cca3']}']);
  }

  /// Countries in a region, or speaking a language, or using a currency.
  Future<List<Map<String, dynamic>>> countries({String region = '', String language = '', String currency = '', String sort = 'population', int limit = 30}) async {
    final all = await _allCountries();
    final pop = await _population();
    String n(Object? v) => '${v ?? ''}'.toLowerCase();
    final picked = all.where((c) {
      if (region.isNotEmpty && n(c['region']) != region && n(c['subregion']) != region && !n(c['subregion']).contains(region)) return false;
      if (language.isNotEmpty) {
        final langs = (c['languages'] as Map?) ?? const {};
        if (!langs.keys.any((k) => n(k) == language) && !langs.values.any((v) => n(v) == language || n(v).startsWith(language))) return false;
      }
      if (currency.isNotEmpty) {
        final cur = (c['currencies'] as Map?) ?? const {};
        if (!cur.keys.any((k) => n(k) == currency) && !cur.values.whereType<Map>().any((v) => n(v['name']).contains(currency))) return false;
      }
      return true;
    });
    final list = [for (final c in picked) country(c, full: false, population: pop['${c['cca3']}'])];
    int cmp(Map a, Map b) => switch (sort) {
      'name' => '${a['name']}'.compareTo('${b['name']}'),
      'area' => ((b['area_km2'] as num?) ?? 0).compareTo((a['area_km2'] as num?) ?? 0),
      _ => ((b['population'] as num?) ?? 0).compareTo((a['population'] as num?) ?? 0),
    };
    list.sort(cmp);
    return list.take(limit).toList();
  }

  // ---- NASA: astronomy picture of the day ---------------------------------------------------

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /// One of NASA's APOD posts on science.nasa.gov (where APOD moved): the
  /// real picture, title, credit and explanation.
  static Map<String, dynamic>? apodPost(Map r) {
    final title = plain((r['title'] as Map?)?['rendered']);
    final m = RegExp(r'^APOD:\s*(\d{4})\s+([A-Za-z]+)\s+(\d{1,2})\s*[^\w\s]*\s*(.*)$').firstMatch(title);
    if (m == null) return null;
    final month = _months.indexWhere((x) => x.toLowerCase() == m[2]!.toLowerCase()) + 1;
    if (month == 0) return null;
    final date = '${m[1]}-${month.toString().padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
    final html = '${(r['content'] as Map?)?['rendered'] ?? ''}';
    final paras = [for (final p in RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true).allMatches(html)) plain(p[1])];
    var explanation = paras.firstWhere((p) => p.startsWith('Explanation:'), orElse: () => plain((r['excerpt'] as Map?)?['rendered']));
    explanation = explanation.replaceFirst(RegExp(r'^Explanation:\s*'), '').trim();
    final tomorrow = RegExp(r"Tomorrow['’]s picture:.*$", caseSensitive: false, dotAll: true).firstMatch(explanation);
    if (tomorrow != null) explanation = explanation.substring(0, tomorrow.start).trim();
    final credit = paras.firstWhere((p) => RegExp(r'^(Image|Video|Illustration)?\s*Credit', caseSensitive: false).hasMatch(p), orElse: () => '');
    final video = RegExp(r'<(?:iframe|video|source)[^>]+src="([^"]+)"').firstMatch(html)?[1];
    final media = ((r['_embedded'] as Map?)?['wp:featuredmedia'] as List?)?.whereType<Map>().firstOrNull;
    String? image = '${r['featured_image_url'] ?? media?['source_url'] ?? ''}';
    // NASA's stand-ins when a post has no picture of its own.
    if (image.isEmpty || image.contains('nasa-logo') || image.contains('news-thumbnail')) image = null;
    // Pictures come from NASA's image service: a sized copy for the card,
    // the original for full resolution.
    final full = image?.split('?').first;
    // The dynamic image service resizes; plain asset links are used as they are.
    final sized = full != null && full.contains('/dynamicimage/');
    final shown = full == null ? null : (sized ? '$full?w=1600&fit=clip' : full);
    return {
      'date': date,
      'title': m[4]!.trim(),
      'explanation': explanation,
      'media_type': video != null && image == null ? 'video' : (video != null ? 'video' : 'image'),
      'url': video ?? shown,
      'hd_url': full,
      'thumbnail': shown != null ? (sized ? '$full?w=900&fit=clip' : full) : (video != null ? _youtubeThumb(video) : null),
      'copyright': credit.isEmpty ? null : clip(credit.replaceFirst(RegExp(r'^[^:]*Credit[^:]*:\s*', caseSensitive: false), ''), 200),
      'page': r['link'] ?? 'https://science.nasa.gov/apod/',
    };
  }

  static String? _youtubeThumb(String url) {
    final id = RegExp(r'(?:youtube\.com/embed/|youtu\.be/|v=)([\w-]{11})').firstMatch(url)?[1];
    return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  Future<List<Map<String, dynamic>>> _apodPosts(Map<String, String> query) async {
    final j = await _json(
      Uri.https('science.nasa.gov', '/wp-json/wp/v2/image-article', {'search': 'APOD', 'orderby': 'date', 'order': 'desc', ...query}),
      timeout: const Duration(seconds: 30),
    );
    return [for (final r in (j as List? ?? const []).whereType<Map>()) ?apodPost(r)];
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// APOD for one [date] (default: the latest), a range, or [count] random
  /// days. Read from NASA's APOD posts on science.nasa.gov; NASA's old APOD
  /// API now answers with a placeholder logo instead of the picture.
  Future<List<Map<String, dynamic>>> apod({required String key, String? date, int? count, String? start, String? end}) async {
    try {
      final out = <Map<String, dynamic>>[];
      if (count != null) {
        final rnd = DateTime.now().microsecondsSinceEpoch;
        final first = DateTime(1995, 6, 16), span = DateTime.now().difference(first).inDays;
        final days = {for (var i = 0; i < count.clamp(1, 12); i++) first.add(Duration(days: (rnd ~/ (i + 7) + i * 7919) % span))};
        final found = await Future.wait([for (final d in days) _apodOn(d).then<Map<String, dynamic>?>((v) => v, onError: (_) => null)]);
        out.addAll(found.whereType<Map<String, dynamic>>());
      } else if (start != null) {
        final from = DateTime.parse(start);
        final to = end == null ? DateTime.now() : DateTime.parse(end);
        final last = to.difference(from).inDays > 11 ? from.add(const Duration(days: 11)) : to;
        final posts = await _apodPosts({
          'per_page': '30',
          'after': '${_day(from.subtract(const Duration(days: 1)))}T12:00:00',
          'before': '${_day(last.add(const Duration(days: 1)))}T12:00:00',
        });
        out.addAll(posts.where((p) => '${p['date']}'.compareTo(_day(from)) >= 0 && '${p['date']}'.compareTo(_day(last)) <= 0));
      } else if (date != null) {
        final p = await _apodOn(DateTime.parse(date));
        if (p != null) out.add(p);
      } else {
        // The newest one: today's, or yesterday's before today's is posted.
        out.addAll((await _apodPosts({'per_page': '3'})).take(1));
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
        return out;
      }
    } catch (_) {
      // Fall back to the API below.
    }
    return _apodApi(key: key, date: date, count: count, start: start, end: end);
  }

  /// The APOD post for [d].
  Future<Map<String, dynamic>?> _apodOn(DateTime d) async {
    final posts = await _apodPosts({
      'per_page': '5',
      'after': '${_day(d.subtract(const Duration(days: 1)))}T12:00:00',
      'before': '${_day(d.add(const Duration(days: 1)))}T12:00:00',
    });
    return posts.where((p) => p['date'] == _day(d)).firstOrNull;
  }

  static Map<String, dynamic> _apod(Map j) {
    final placeholder = '${j['url'] ?? ''}'.contains('nasa-logo');
    return {
      'date': j['date'],
      'title': placeholder && j['title'] == 'NASA Science' ? 'Astronomy Picture of the Day' : j['title'],
      'explanation': '${j['explanation'] ?? ''}'.trim(),
      'media_type': j['media_type'],
      'url': placeholder ? null : j['url'],
      'hd_url': placeholder ? null : j['hdurl'],
      'thumbnail': placeholder ? null : (j['thumbnail_url'] ?? (j['media_type'] == 'image' ? j['url'] : null)),
      'copyright': '${j['copyright'] ?? ''}'.replaceAll('\n', ' ').trim().isEmpty ? null : '${j['copyright']}'.replaceAll('\n', ' ').trim(),
      'page': j['date'] == null ? 'https://science.nasa.gov/apod/' : 'https://apod.nasa.gov/apod/ap${'${j['date']}'.replaceAll('-', '').substring(2)}.html',
    };
  }

  Future<List<Map<String, dynamic>>> _apodApi({required String key, String? date, int? count, String? start, String? end}) async {
    final j = await _json(Uri.https('api.nasa.gov', '/planetary/apod', {
      'api_key': key.isEmpty ? 'DEMO_KEY' : key,
      'thumbs': 'true',
      if (count != null) 'count': '${count.clamp(1, 12)}',
      if (count == null && start != null) 'start_date': start,
      if (count == null && start != null && end != null) 'end_date': end,
      if (count == null && start == null && date != null) 'date': date,
    }), timeout: const Duration(seconds: 30));
    final list = j is List ? j.whereType<Map>().map(_apod).toList() : [_apod(j as Map)];
    list.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return list;
  }

  // ---- downloads ---------------------------------------------------------------------

  /// Saves [url] among the app's files as [name], reporting progress (0-1).
  /// [meta] goes in the file's sidecar, which Files reads to put it on the
  /// right tab: `library` (book, audiobook or podcast), `title`, `subtitle`
  /// (author or show), `cover`.
  Future<File> download(String url, String name, {void Function(double)? progress, Map<String, Object?>? meta}) async {
    final req = http.Request('GET', Uri.parse(url))..headers.addAll(_ua);
    final r = await _http.send(req).timeout(const Duration(seconds: 60));
    if (r.statusCode >= 400) throw LibraryException('Download failed (${r.statusCode}).');
    final file = await uniqueGeneratedFile(name, folder: 'downloads');
    final sink = file.openWrite();
    final total = r.contentLength ?? 0;
    // Shown live on the tool card that started it.
    final track = DownloadProgress.start(name, url: url, total: r.contentLength);
    var got = 0;
    final counted = r.stream.map((chunk) {
      got += chunk.length;
      if (total > 0) progress?.call(got / total);
      return chunk;
    });
    try {
      // On a tool card the person can pause, resume or cancel it.
      if (track != null) {
        await track.pipe(counted, sink);
      } else {
        await sink.addStream(counted);
      }
    } catch (e) {
      track?.fail('$e');
      await sink.close();
      // A cancelled or broken download leaves nothing half-written.
      await file.delete().catchError((Object _) => file);
      rethrow;
    }
    await sink.close();
    track?.finish(file.path);
    if (meta != null) {
      final dot = file.path.lastIndexOf('.');
      final side = File('${dot < 0 ? file.path : file.path.substring(0, dot)}.meta.json');
      await side.writeAsString(jsonEncode({
        for (final e in meta.entries)
          if (e.value != null) e.key: e.value,
        'source_url': url,
      }));
    }
    return file;
  }

  /// A safe file name from a title: "Pride and Prejudice.epub".
  static String fileName(String title, String ext) {
    final t = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${t.isEmpty ? 'download' : (t.length > 80 ? t.substring(0, 80) : t)}.$ext';
  }
}

class LibraryException implements Exception {
  const LibraryException(this.message);
  final String message;

  @override
  String toString() => message;
}
