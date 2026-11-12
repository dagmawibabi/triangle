import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// A book of the Bible: its USFM code (what YouVersion's passage ids use),
/// English name, other names people type, and how many chapters it has.
@immutable
class BibleBook {
  const BibleBook(this.code, this.name, this.chapters, [this.aliases = const []]);
  final String code;
  final String name;
  final int chapters;
  final List<String> aliases;

  bool get oldTestament => bibleBooks.indexOf(this) < 39;
}

const bibleBooks = <BibleBook>[
  BibleBook('GEN', 'Genesis', 50, ['gen', 'ge', 'gn']),
  BibleBook('EXO', 'Exodus', 40, ['exod', 'ex', 'exo']),
  BibleBook('LEV', 'Leviticus', 27, ['lev', 'le', 'lv']),
  BibleBook('NUM', 'Numbers', 36, ['num', 'nu', 'nm', 'nb']),
  BibleBook('DEU', 'Deuteronomy', 34, ['deut', 'de', 'dt']),
  BibleBook('JOS', 'Joshua', 24, ['josh', 'jos', 'jsh']),
  BibleBook('JDG', 'Judges', 21, ['judg', 'jdg', 'jg', 'jdgs']),
  BibleBook('RUT', 'Ruth', 4, ['rth', 'ru']),
  BibleBook('1SA', '1 Samuel', 31, ['1 sam', '1sam', '1 sa', '1sm', 'i samuel', 'first samuel']),
  BibleBook('2SA', '2 Samuel', 24, ['2 sam', '2sam', '2 sa', '2sm', 'ii samuel', 'second samuel']),
  BibleBook('1KI', '1 Kings', 22, ['1 kgs', '1kgs', '1 ki', '1kings', 'i kings', 'first kings']),
  BibleBook('2KI', '2 Kings', 25, ['2 kgs', '2kgs', '2 ki', '2kings', 'ii kings', 'second kings']),
  BibleBook('1CH', '1 Chronicles', 29, ['1 chron', '1 chr', '1chr', '1 ch', 'i chronicles']),
  BibleBook('2CH', '2 Chronicles', 36, ['2 chron', '2 chr', '2chr', '2 ch', 'ii chronicles']),
  BibleBook('EZR', 'Ezra', 10, ['ezr', 'ez']),
  BibleBook('NEH', 'Nehemiah', 13, ['neh', 'ne']),
  BibleBook('EST', 'Esther', 10, ['esth', 'es']),
  BibleBook('JOB', 'Job', 42, ['jb']),
  BibleBook('PSA', 'Psalms', 150, ['psalm', 'ps', 'psa', 'pss', 'psalms']),
  BibleBook('PRO', 'Proverbs', 31, ['prov', 'pro', 'prv', 'pr']),
  BibleBook('ECC', 'Ecclesiastes', 12, ['eccles', 'eccl', 'ecc', 'ec', 'qoheleth']),
  BibleBook('SNG', 'Song of Songs', 8, ['song of solomon', 'song', 'sos', 'canticles', 'sg']),
  BibleBook('ISA', 'Isaiah', 66, ['isa', 'is']),
  BibleBook('JER', 'Jeremiah', 52, ['jer', 'je', 'jr']),
  BibleBook('LAM', 'Lamentations', 5, ['lam', 'la']),
  BibleBook('EZK', 'Ezekiel', 48, ['ezek', 'eze', 'ezk']),
  BibleBook('DAN', 'Daniel', 12, ['dan', 'da', 'dn']),
  BibleBook('HOS', 'Hosea', 14, ['hos', 'ho']),
  BibleBook('JOL', 'Joel', 3, ['jl', 'joe']),
  BibleBook('AMO', 'Amos', 9, ['am', 'amo']),
  BibleBook('OBA', 'Obadiah', 1, ['obad', 'ob']),
  BibleBook('JON', 'Jonah', 4, ['jnh', 'jon']),
  BibleBook('MIC', 'Micah', 7, ['mic', 'mc']),
  BibleBook('NAM', 'Nahum', 3, ['nah', 'na']),
  BibleBook('HAB', 'Habakkuk', 3, ['hab', 'hb']),
  BibleBook('ZEP', 'Zephaniah', 3, ['zeph', 'zep', 'zp']),
  BibleBook('HAG', 'Haggai', 2, ['hag', 'hg']),
  BibleBook('ZEC', 'Zechariah', 14, ['zech', 'zec', 'zc']),
  BibleBook('MAL', 'Malachi', 4, ['mal', 'ml']),
  BibleBook('MAT', 'Matthew', 28, ['matt', 'mt', 'mat']),
  BibleBook('MRK', 'Mark', 16, ['mrk', 'mk', 'mr']),
  BibleBook('LUK', 'Luke', 24, ['luk', 'lk']),
  BibleBook('JHN', 'John', 21, ['jhn', 'jn', 'joh']),
  BibleBook('ACT', 'Acts', 28, ['act', 'ac', 'acts of the apostles']),
  BibleBook('ROM', 'Romans', 16, ['rom', 'ro', 'rm']),
  BibleBook('1CO', '1 Corinthians', 16, ['1 cor', '1cor', '1 co', 'i corinthians', 'first corinthians']),
  BibleBook('2CO', '2 Corinthians', 13, ['2 cor', '2cor', '2 co', 'ii corinthians', 'second corinthians']),
  BibleBook('GAL', 'Galatians', 6, ['gal', 'ga']),
  BibleBook('EPH', 'Ephesians', 6, ['eph', 'ephes']),
  BibleBook('PHP', 'Philippians', 4, ['phil', 'php', 'pp']),
  BibleBook('COL', 'Colossians', 4, ['col', 'co']),
  BibleBook('1TH', '1 Thessalonians', 5, ['1 thess', '1thess', '1 th', 'i thessalonians']),
  BibleBook('2TH', '2 Thessalonians', 3, ['2 thess', '2thess', '2 th', 'ii thessalonians']),
  BibleBook('1TI', '1 Timothy', 6, ['1 tim', '1tim', '1 ti', 'i timothy']),
  BibleBook('2TI', '2 Timothy', 4, ['2 tim', '2tim', '2 ti', 'ii timothy']),
  BibleBook('TIT', 'Titus', 3, ['tit', 'ti']),
  BibleBook('PHM', 'Philemon', 1, ['philem', 'phm', 'pm']),
  BibleBook('HEB', 'Hebrews', 13, ['heb']),
  BibleBook('JAS', 'James', 5, ['jas', 'jm']),
  BibleBook('1PE', '1 Peter', 5, ['1 pet', '1pet', '1 pe', '1pt', 'i peter']),
  BibleBook('2PE', '2 Peter', 3, ['2 pet', '2pet', '2 pe', '2pt', 'ii peter']),
  BibleBook('1JN', '1 John', 5, ['1 jn', '1jn', '1 jo', '1john', 'i john']),
  BibleBook('2JN', '2 John', 1, ['2 jn', '2jn', '2 jo', '2john', 'ii john']),
  BibleBook('3JN', '3 John', 1, ['3 jn', '3jn', '3 jo', '3john', 'iii john']),
  BibleBook('JUD', 'Jude', 1, ['jud', 'jd']),
  BibleBook('REV', 'Revelation', 22, ['rev', 're', 'revelations', 'the revelation', 'apocalypse']),
];

String _norm(String s) => s.toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The book [name] names: "John", "1 Cor", "Ps", "JHN".
BibleBook? findBook(String name) {
  final n = _norm(name);
  if (n.isEmpty) return null;
  for (final b in bibleBooks) {
    if (_norm(b.name) == n || b.code.toLowerCase() == n || b.aliases.contains(n) || b.aliases.contains(n.replaceAll(' ', ''))) return b;
  }
  // A unique start of a name ("deuter", "philip").
  final starts = bibleBooks.where((b) => _norm(b.name).startsWith(n) && n.length >= 3).toList();
  return starts.length == 1 ? starts.first : null;
}

/// A reference: John 3:16, John 3:16-18, Psalm 23, Romans 8:28-9:2.
@immutable
class BibleRef {
  const BibleRef(this.book, this.chapter, {this.verse, this.endChapter, this.endVerse});
  final BibleBook book;
  final int chapter;
  final int? verse;
  final int? endChapter;
  final int? endVerse;

  bool get wholeChapter => verse == null;

  /// YouVersion's passage id: JHN.3, JHN.3.16, JHN.3.16-JHN.3.18.
  String get passageId {
    final start = verse == null ? '${book.code}.$chapter' : '${book.code}.$chapter.$verse';
    if (endVerse == null && endChapter == null) return start;
    // Within one chapter YouVersion writes a range as JHN.3.16-18.
    if ((endChapter == null || endChapter == chapter) && endVerse != null && verse != null) return '$start-$endVerse';
    final ec = endChapter ?? chapter;
    return endVerse == null ? '$start-$ec' : '$start-$ec.$endVerse';
  }

  /// Spans more than one chapter (read a chapter at a time).
  bool get crossesChapters => endChapter != null && endChapter != chapter;

  String get label {
    final v = verse == null ? '' : ':$verse';
    final end = endVerse == null && endChapter == null
        ? ''
        : endChapter != null && endChapter != chapter
        ? '–$endChapter${endVerse == null ? '' : ':$endVerse'}'
        : '–$endVerse';
    return '${book.name} $chapter$v$end';
  }

  BibleRef? get nextChapter => chapter < book.chapters ? BibleRef(book, chapter + 1) : null;
  BibleRef? get previousChapter => chapter > 1 ? BibleRef(book, chapter - 1) : null;

  static final _pattern = RegExp(r'^\s*((?:[1-3]|i{1,3})\s*[a-z][a-z .]*?|[a-z][a-z .]*?)\s*(\d+)(?:\s*[:.]\s*(\d+))?(?:\s*[-–—]\s*(\d+)(?:\s*[:.]\s*(\d+))?)?\s*$', caseSensitive: false);

  /// Reads "John 3:16", "1 Cor 13:4-7", "Ps 23", "Rom 8:28-9:2", "JHN.3.16".
  static BibleRef? parse(String text) {
    final t = text.trim();
    final usfm = RegExp(r'^([1-3]?[A-Z]{2,3})\.(\d+)(?:\.(\d+))?(?:-(?:[1-3]?[A-Z]{2,3}\.)?(\d+)(?:\.(\d+))?)?$').firstMatch(t.toUpperCase());
    if (usfm != null) {
      final b = bibleBooks.where((x) => x.code == usfm[1]).firstOrNull;
      if (b == null) return null;
      final c = int.parse(usfm[2]!);
      final v = usfm[3] == null ? null : int.parse(usfm[3]!);
      final a = usfm[4] == null ? null : int.parse(usfm[4]!);
      final bb = usfm[5] == null ? null : int.parse(usfm[5]!);
      return _make(b, c, v, a, bb);
    }
    final m = _pattern.firstMatch(t);
    if (m == null) return null;
    final book = findBook(m[1]!);
    if (book == null) return null;
    return _make(book, int.parse(m[2]!), m[3] == null ? null : int.parse(m[3]!), m[4] == null ? null : int.parse(m[4]!), m[5] == null ? null : int.parse(m[5]!));
  }

  static BibleRef? _make(BibleBook b, int chapter, int? verse, int? a, int? bb) {
    if (chapter < 1 || chapter > b.chapters) return null;
    // "John 3:16-18" → verses 16 to 18; "Rom 8:28-9:2" → to chapter 9 verse 2;
    // "Ps 23-24" → chapters 23 to 24.
    if (a == null) return BibleRef(b, chapter, verse: verse);
    if (bb != null) return BibleRef(b, chapter, verse: verse, endChapter: a, endVerse: bb);
    if (verse == null) return BibleRef(b, chapter, endChapter: a.clamp(chapter, b.chapters));
    return BibleRef(b, chapter, verse: verse, endVerse: a);
  }
}

/// Well-known verses the verse of the day rotates through.
const verseOfTheDayRefs = [
  'JHN.3.16', 'JER.29.11', 'PHP.4.13', 'ROM.8.28', 'PRO.3.5-PRO.3.6', 'ISA.41.10', 'PSA.23.1', 'MAT.11.28',
  'JOS.1.9', 'ROM.12.2', 'PHP.4.6-PHP.4.7', 'GAL.5.22-GAL.5.23', 'HEB.11.1', '2TI.1.7', '1CO.13.4-1CO.13.7',
  'PSA.46.1', 'ISA.40.31', 'MAT.6.33', 'ROM.15.13', 'PSA.119.105', 'JHN.14.6', 'EPH.2.8-EPH.2.9', '2CO.5.17',
  'LAM.3.22-LAM.3.23', 'PSA.37.4', 'MAT.5.16', 'COL.3.23', 'JAS.1.5', '1PE.5.7', 'PSA.27.1', 'JHN.16.33',
  'ROM.5.8', 'MIC.6.8', 'PSA.34.18', 'ZEP.3.17', 'ISA.26.3', 'DEU.31.6', 'MAT.28.19-MAT.28.20', 'HEB.13.8',
  'ROM.10.9', 'PSA.139.14', 'JHN.15.13', '1JN.4.19', 'EPH.4.32', 'PRO.16.3', 'PSA.91.1-PSA.91.2', 'NUM.6.24-NUM.6.26',
  'ISA.43.2', 'JHN.11.25', 'GAL.2.20', 'HEB.12.1-HEB.12.2', 'PSA.121.1-PSA.121.2', 'MAT.22.37-MAT.22.39',
  'ROM.8.38-ROM.8.39', '1TH.5.16-1TH.5.18', 'PSA.16.11', 'JHN.8.12', 'EPH.3.20', 'REV.21.4', 'ECC.3.1',
];

/// The verse of the day for [day]: the same for everyone on a date.
String verseOfTheDayFallback(DateTime day) {
  final n = DateTime(day.year, day.month, day.day).difference(DateTime(day.year)).inDays + day.year;
  return verseOfTheDayRefs[n % verseOfTheDayRefs.length];
}

/// The Bible settings: the YouVersion developer token (kept in the
/// keystore), the default version and the language versions are listed in.
@immutable
class BibleSettings {
  const BibleSettings({this.token = '', this.versionId, this.versionLabel = '', this.language = 'en', this.loaded = false});
  final String token;
  final int? versionId;
  final String versionLabel;
  final String language;
  final bool loaded;

  bool get hasToken => token.trim().isNotEmpty;

  BibleSettings copyWith({String? token, int? Function()? versionId, String? versionLabel, String? language}) => BibleSettings(
    token: token ?? this.token,
    versionId: versionId == null ? this.versionId : versionId(),
    versionLabel: versionLabel ?? this.versionLabel,
    language: language ?? this.language,
    loaded: true,
  );
}

class BibleSettingsController extends Notifier<BibleSettings> {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'youversion_token';

  late Future<void> ready;

  @override
  BibleSettings build() {
    ready = _load();
    return const BibleSettings();
  }

  Future<void> _load() async {
    String token = '';
    try {
      token = await _storage.read(key: _tokenKey) ?? '';
    } catch (e) {
      debugPrint('[Bible] token: $e');
    }
    final p = await SharedPreferences.getInstance();
    state = BibleSettings(
      token: token,
      versionId: p.getInt('bible_version'),
      versionLabel: p.getString('bible_version_label') ?? '',
      language: p.getString('bible_language') ?? 'en',
      loaded: true,
    );
  }

  Future<void> setToken(String t) async {
    state = state.copyWith(token: t.trim());
    await _storage.write(key: _tokenKey, value: t.trim());
  }

  Future<void> setVersion(int? id, String label) async {
    state = state.copyWith(versionId: () => id, versionLabel: label);
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove('bible_version');
      await p.remove('bible_version_label');
    } else {
      await p.setInt('bible_version', id);
      await p.setString('bible_version_label', label);
    }
  }

  Future<void> setLanguage(String l) async {
    state = state.copyWith(language: l.trim().isEmpty ? 'en' : l.trim().toLowerCase());
    await (await SharedPreferences.getInstance()).setString('bible_language', state.language);
  }
}

final bibleSettingsProvider = NotifierProvider<BibleSettingsController, BibleSettings>(BibleSettingsController.new);

/// A Bible version (translation) as YouVersion lists it.
@immutable
class BibleVersion {
  const BibleVersion({
    required this.id,
    required this.abbreviation,
    required this.title,
    this.localizedTitle = '',
    this.localizedAbbreviation = '',
    this.languageTag = '',
    this.books = const [],
    this.copyright,
    this.info,
    this.publisherName,
    this.publisherUrl,
    this.deepLink,
    this.licensed = true,
  });

  final int id;
  final String abbreviation;
  final String title;
  final String localizedTitle;
  final String localizedAbbreviation;
  final String languageTag;
  final List<String> books;
  final String? copyright;
  final String? info;
  final String? publisherName;
  final String? publisherUrl;
  final String? deepLink;

  /// Whether the user's app key may read its text. Versions listed with
  /// `all_available` but not licensed to the app return 403 for text.
  final bool licensed;

  String get name => localizedTitle.isNotEmpty ? localizedTitle : title;
  String get short => localizedAbbreviation.isNotEmpty ? localizedAbbreviation : abbreviation;

  factory BibleVersion.fromJson(Map j, {bool licensed = true}) {
    String? str(String k) => '${j[k] ?? ''}'.trim().isEmpty ? null : '${j[k]}'.trim();
    return BibleVersion(
      id: (j['id'] as num).toInt(),
      abbreviation: '${j['abbreviation'] ?? ''}',
      title: '${j['title'] ?? ''}',
      localizedTitle: '${j['localized_title'] ?? ''}',
      localizedAbbreviation: '${j['localized_abbreviation'] ?? ''}',
      languageTag: '${j['language_tag'] ?? ''}',
      books: [for (final b in (j['books'] as List? ?? const [])) '$b'],
      copyright: str('copyright'),
      info: str('info'),
      publisherName: str('publisher_name'),
      publisherUrl: str('publisher_url'),
      deepLink: str('youversion_deep_link'),
      licensed: licensed,
    );
  }

  Map<String, dynamic> describe() => {
    'version_id': id,
    'abbreviation': short,
    'title': name,
    'language': languageTag,
    'books': books.length,
    if (!licensed) 'licensed': false,
    if (copyright != null) 'copyright': copyright!.length > 300 ? '${copyright!.substring(0, 300)}…' : copyright,
    'publisher': ?publisherName,
    'publisher_url': ?publisherUrl,
    if (info != null) 'info': info!.length > 400 ? '${info!.substring(0, 400)}…' : info,
  };
}

/// Something YouVersion said no to, in words for the user.
class BibleException implements Exception {
  const BibleException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// YouVersion's Platform API (api.youversion.com/v1), called directly: every
/// page of versions, licensed or not, passages, the verse of the day, verse
/// search, verse images and each version's books.
class BibleService {
  BibleService(this._ref, {http.Client? client}) : _http = client ?? http.Client();
  final Ref _ref;
  final http.Client _http;

  final Map<String, List<BibleVersion>> _versions = {};
  final Map<int, BibleVersion> _byId = {};
  String? _token;

  Future<String> _key() async {
    await _ref.read(bibleSettingsProvider.notifier).ready;
    final s = _ref.read(bibleSettingsProvider);
    if (!s.hasToken) {
      throw const BibleException('Add a YouVersion app key under Settings → More apps → Bible (free at platform.youversion.com).');
    }
    if (_token != s.token) {
      _versions.clear();
      _byId.clear();
      _token = s.token;
    }
    return s.token;
  }

  String get _language => _ref.read(bibleSettingsProvider).language;
  String get _contentLanguage => _language == '*' ? 'en' : _language;

  Future<Object?> _get(String path, [Map<String, Object> query = const {}]) async {
    final key = await _key();
    final uri = Uri.https('api.youversion.com', '/v1$path', {
      for (final e in query.entries) e.key: e.value is List ? [for (final v in e.value as List) '$v'] : '${e.value}',
    });
    final http.Response r;
    try {
      r = await _http
          .get(uri, headers: {'X-YVP-App-Key': key, 'accept': 'application/json', 'accept-language': _contentLanguage})
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw BibleException('Couldn\'t reach YouVersion: $e');
    }
    if (r.statusCode == 204) return null;
    if (r.statusCode == 401) throw const BibleException('YouVersion refused the app key. Check it under Settings → More apps → Bible.');
    if (r.statusCode == 403) {
      throw const BibleException(
        'This version isn\'t licensed to your YouVersion app yet. Accept its publisher\'s license on platform.youversion.com, or pick another version.',
      );
    }
    if (r.statusCode == 404) throw const BibleException('YouVersion has no such passage or version.');
    if (r.statusCode == 429) throw BibleException('YouVersion is rate-limiting; try again in ${r.headers['retry-after'] ?? '60'} s.');
    if (r.statusCode >= 400) {
      var why = r.body;
      try {
        why = '${(jsonDecode(r.body) as Map)['message'] ?? r.body}';
      } catch (_) {}
      throw BibleException('YouVersion said ${r.statusCode}: ${why.length > 200 ? why.substring(0, 200) : why}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Every page of a list endpoint (page_size 99, following next_page_token).
  Future<List<Map>> _all(String path, Map<String, Object> query, {int maxPages = 30}) async {
    final out = <Map>[];
    String? token;
    for (var page = 0; page < maxPages; page++) {
      final j = await _get(path, {...query, 'page_size': 99, 'page_token': ?token}) as Map? ?? const {};
      out.addAll((j['data'] as List? ?? const []).whereType<Map>());
      token = '${j['next_page_token'] ?? ''}';
      if (token.isEmpty) break;
    }
    return out;
  }

  /// Versions in [language] ("en", "am", "*"): the app's own (licensed) ones,
  /// or with [everything] every version YouVersion has, each marked whether
  /// this app may read it.
  Future<List<BibleVersion>> versions({String? language, bool everything = false}) async {
    final lang = (language == null || language.trim().isEmpty) ? _language : language.trim().toLowerCase();
    final cacheKey = '$lang|$everything';
    if (_versions[cacheKey] case final hit?) return hit;
    final licensed = await _all('/bibles', {'language_ranges[]': [lang]});
    final ids = {for (final b in licensed) (b['id'] as num).toInt()};
    final rows = everything ? await _all('/bibles', {'language_ranges[]': [lang], 'all_available': 'true'}) : licensed;
    final list = [for (final b in rows) BibleVersion.fromJson(b, licensed: ids.contains((b['id'] as num).toInt()))]
      ..sort((a, b) => a.licensed != b.licensed ? (a.licensed ? -1 : 1) : a.short.compareTo(b.short));
    for (final v in list) {
      if (v.licensed || !_byId.containsKey(v.id)) _byId[v.id] = v;
    }
    return _versions[cacheKey] = list;
  }

  Future<BibleVersion> byId(int id) async {
    if (_byId[id] case final v?) return v;
    final j = await _get('/bibles/$id') as Map;
    return _byId[id] = BibleVersion.fromJson(j);
  }

  /// A version by id ("111"), abbreviation ("KJV", "NIV") or title; the
  /// default (Settings) when [name] is empty, else the first readable
  /// version in the language that has [book].
  Future<BibleVersion> version(String? name, {String? book}) async {
    final s = _ref.read(bibleSettingsProvider);
    final n = (name ?? '').trim();
    if (n.isEmpty && s.versionId != null) return byId(s.versionId!);
    final id = int.tryParse(n);
    if (id != null) return byId(id);
    if (n.isNotEmpty) {
      final lower = n.toLowerCase();
      BibleVersion? hit(List<BibleVersion> list) =>
          list.where((b) => b.abbreviation.toLowerCase() == lower || b.short.toLowerCase() == lower).firstOrNull ??
          list.where((b) => b.title.toLowerCase() == lower || b.name.toLowerCase() == lower).firstOrNull ??
          list.where((b) => b.title.toLowerCase().contains(lower) || b.name.toLowerCase().contains(lower)).firstOrNull;
      final found = hit(await versions()) ?? hit(await versions(language: '*')) ?? hit(await versions(language: '*', everything: true));
      if (found == null) throw BibleException('No Bible version "$n" on YouVersion. bible_versions lists them.');
      if (!found.licensed) {
        throw BibleException(
          '${found.short} (${found.name}) is on YouVersion but not licensed to your app yet. Accept its license on '
          'platform.youversion.com, or use a licensed version.',
        );
      }
      return found;
    }
    final all = await versions();
    if (all.isEmpty) throw BibleException('Your YouVersion app has no versions in "$_language".');
    return all.where((b) => book == null || b.books.isEmpty || b.books.contains(book)).firstOrNull ?? all.first;
  }

  /// The text of [passageId] ("JHN.3.16", "JHN.3.16-18", "PSA.23").
  Future<({String id, String reference, String text})> passage(BibleVersion v, String passageId) async {
    final j = await _get('/bibles/${v.id}/passages/$passageId', {'format': 'text'}) as Map;
    return (id: '${j['id'] ?? passageId}', reference: '${j['reference'] ?? ''}', text: '${j['content'] ?? ''}'.trim());
  }

  /// [ref]'s text, put together a chapter at a time when it spans several.
  Future<({String reference, String text})> read(BibleVersion v, BibleRef ref) async {
    if (!ref.crossesChapters) {
      final p = await passage(v, ref.passageId);
      return (reference: p.reference.isNotEmpty ? p.reference : ref.label, text: p.text);
    }
    final parts = <String>[];
    final last = ref.endChapter!.clamp(ref.chapter, ref.book.chapters);
    for (var c = ref.chapter; c <= last; c++) {
      final String id;
      if (c == ref.chapter && ref.verse != null) {
        final n = (await verses(v, ref.book.code, c)).length;
        id = '${ref.book.code}.$c.${ref.verse}-$n';
      } else if (c == last && ref.endVerse != null) {
        id = '${ref.book.code}.$c.1-${ref.endVerse}';
      } else {
        id = '${ref.book.code}.$c';
      }
      parts.add((await passage(v, id)).text);
    }
    return (reference: ref.label, text: parts.join('\n\n'));
  }

  Future<List<Map>> verses(BibleVersion v, String book, int chapter) async =>
      [for (final x in ((await _get('/bibles/${v.id}/books/$book/chapters/$chapter/verses') as Map?)?['data'] as List? ?? const [])) if (x is Map) x];

  /// The books of [v]: code, name and chapters.
  Future<List<({String code, String name, int chapters, String canon})>> books(BibleVersion v) async {
    final j = await _get('/bibles/${v.id}/index') as Map? ?? const {};
    return [
      for (final b in (j['books'] as List? ?? const []).whereType<Map>())
        (
          code: '${b['id']}',
          name: '${b['title'] ?? b['full_title'] ?? b['id']}',
          chapters: (b['chapters'] as List? ?? const []).where((c) => c is Map && !'${c['id']}'.toUpperCase().contains('INTRO')).length,
          canon: '${b['canon'] ?? ''}',
        ),
    ];
  }

  /// YouVersion's verse of the day for [day] (its passage id and artwork),
  /// or the app's own list when the API has none.
  Future<({String passageId, String? image})> verseOfTheDay(DateTime day) async {
    final n = DateTime(day.year, day.month, day.day).difference(DateTime(day.year)).inDays + 1;
    try {
      final j = await _get('/verse-of-the-days/$n', {'language_ranges[]': [_contentLanguage]}) as Map;
      final id = '${j['passage_id'] ?? ''}';
      if (id.isNotEmpty) {
        String? image;
        if (j['image_id'] != null) {
          try {
            image = '${((await _get('/images/${j['image_id']}')) as Map)['image_url'] ?? ''}';
          } catch (_) {}
        }
        return (passageId: id, image: image == null || image.isEmpty ? null : '$image?size=card');
      }
    } catch (e) {
      // No key at all is worth saying; anything else falls back.
      if (e is BibleException && e.message.startsWith('Add a YouVersion')) rethrow;
    }
    return (passageId: verseOfTheDayFallback(day), image: null);
  }

  /// Verse artwork for [passageId] (a verse or a range in one chapter).
  Future<List<({String url, String attribution})>> images(String passageId, {int max = 6}) async {
    try {
      final j = await _get('/images', {'passage_id': passageId, 'language_ranges[]': [_contentLanguage], 'page_size': max}) as Map?;
      return [
        for (final i in (j?['data'] as List? ?? const []).whereType<Map>().take(max))
          if ('${i['image_url'] ?? ''}'.isNotEmpty) (url: '${i['image_url']}?size=card', attribution: '${i['attribution'] ?? ''}'),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Verses about [query] in [v]: references, best first.
  Future<({List<String> references, List<String> didYouMean})> search(BibleVersion v, String query, {int limit = 10}) async {
    final j = await _get('/search-verses', {'query': query, 'bible_id': v.id, 'page_size': limit.clamp(1, 50)}) as Map? ?? const {};
    return (
      references: [for (final x in (j['verses'] as List? ?? const []).whereType<Map>()) '${x['reference'] ?? x['passage_id'] ?? ''}'].where((r) => r.isNotEmpty).toList(),
      didYouMean: [for (final d in (j['did_you_mean'] as List? ?? const [])) '$d'],
    );
  }

  /// The bible.com page for [passageId] in [v].
  static String link(BibleVersion v, String passageId) => 'https://www.bible.com/bible/${v.id}/${passageId.split('-').first}.${v.abbreviation}';

  static String explain(Object e) => switch (e) {
    BibleException(:final message) => message,
    ArgumentError(:final message) => '$message',
    _ => '$e',
  };
}

final bibleServiceProvider = Provider<BibleService>((ref) => BibleService(ref));
