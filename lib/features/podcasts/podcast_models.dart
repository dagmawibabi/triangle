import 'dart:convert';

import '../playlists/playlists.dart' show PlaylistTrack;

// Shows, episodes and stations. Ported from Alexandria's podcast player,
// with Telegram channels as shows too: their audio posts are episodes.

/// A bookmark in an episode: a moment and what about it.
class EpisodeNote {
  EpisodeNote({required this.ms, this.text = '', DateTime? at}) : at = at ?? DateTime.now();
  final int ms;
  String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'ms': ms, if (text.isNotEmpty) 't': text, 'at': at.millisecondsSinceEpoch};
  factory EpisodeNote.fromJson(Map j) => EpisodeNote(ms: (j['ms'] as num?)?.toInt() ?? 0, text: '${j['t'] ?? ''}', at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0));
}

/// Rating, favourite and notes on a show, an episode or a station.
class UserMark {
  UserMark({this.rating = 0, this.favorite = false, this.note = '', List<EpisodeNote>? bookmarks}) : bookmarks = bookmarks ?? [];
  int rating;
  bool favorite;
  String note;
  final List<EpisodeNote> bookmarks;

  bool get isEmpty => rating == 0 && !favorite && note.isEmpty && bookmarks.isEmpty;

  Map<String, dynamic> toJson() => {
    if (rating > 0) 'r': rating,
    if (favorite) 'f': true,
    if (note.isNotEmpty) 'n': note,
    if (bookmarks.isNotEmpty) 'b': [for (final b in bookmarks) b.toJson()],
  };

  factory UserMark.fromJson(Object? j) {
    if (j is! Map) return UserMark();
    return UserMark(
      rating: (j['r'] as num?)?.toInt() ?? 0,
      favorite: j['f'] == true,
      note: '${j['n'] ?? ''}',
      bookmarks: [for (final b in (j['b'] as List? ?? const [])) if (b is Map) EpisodeNote.fromJson(b)],
    );
  }
}

class Episode {
  Episode({
    required this.guid,
    required this.feedUrl,
    required this.title,
    required this.audioUrl,
    this.description = '',
    this.published,
    this.durationMs = 0,
    this.imageUrl,
    this.link,
    this.podcastTitle = '',
    this.podcastImage,
    this.tg,
  });

  final String guid;

  /// The show: an RSS address, or `tg:<account>:<chat>` for a channel.
  final String feedUrl;
  final String title;
  final String audioUrl;
  final String description;
  final DateTime? published;
  final int durationMs;
  final String? imageUrl;
  final String? link;

  /// Copied from the show so an episode can be listed on its own.
  final String podcastTitle;
  final String? podcastImage;

  /// For an episode posted in Telegram: the audio message.
  final PlaylistTrack? tg;

  String? get art => imageUrl ?? podcastImage;
  bool get isTelegram => tg != null;

  Episode copyWith({String? imageUrl, PlaylistTrack? tg}) => Episode(
    guid: guid,
    feedUrl: feedUrl,
    title: title,
    audioUrl: audioUrl,
    description: description,
    published: published,
    durationMs: durationMs,
    imageUrl: imageUrl ?? this.imageUrl,
    link: link,
    podcastTitle: podcastTitle,
    podcastImage: podcastImage,
    tg: tg ?? this.tg,
  );

  /// Whether every word of [query] appears in the title or show notes.
  bool matches(String query) => query.toLowerCase().split(RegExp(r'\s+')).every(_haystack.contains);
  late final String _haystack = '$title\n$description\n$podcastTitle'.toLowerCase();

  Map<String, dynamic> toJson() => {
    'guid': guid,
    'feedUrl': feedUrl,
    'title': title,
    'audioUrl': audioUrl,
    if (description.isNotEmpty) 'description': description.length > 4000 ? description.substring(0, 4000) : description,
    'published': published?.toIso8601String(),
    'durationMs': durationMs,
    'imageUrl': imageUrl,
    'link': link,
    'podcastTitle': podcastTitle,
    'podcastImage': podcastImage,
    if (tg != null) 'tg': tg!.toJson(),
  };

  factory Episode.fromJson(Map j) => Episode(
    guid: '${j['guid'] ?? ''}',
    feedUrl: '${j['feedUrl'] ?? ''}',
    title: '${j['title'] ?? ''}',
    audioUrl: '${j['audioUrl'] ?? ''}',
    description: '${j['description'] ?? ''}',
    published: DateTime.tryParse('${j['published'] ?? ''}'),
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    imageUrl: j['imageUrl'] as String?,
    link: j['link'] as String?,
    podcastTitle: '${j['podcastTitle'] ?? ''}',
    podcastImage: j['podcastImage'] as String?,
    tg: j['tg'] is Map ? PlaylistTrack.fromJson(j['tg'] as Map) : null,
  );

  /// [toJson] as text, made once: an episode never changes, and the store
  /// saves thousands of them every few seconds while something plays.
  String get json => _json[this] ??= jsonEncode(toJson());
  static final _json = Expando<String>();

  Map<String, dynamic> describe({EpisodeState? state}) => {
    'episode_id': guid,
    'title': title,
    'show': podcastTitle,
    if (published != null) 'published': published!.toIso8601String().substring(0, 10),
    if (durationMs > 0) 'minutes': (durationMs / 60000).round(),
    if (state != null && state.played) 'played': true,
    if (state != null && !state.played && state.posMs > 15000) 'listened_minutes': (state.posMs / 60000).round(),
    if (state?.localPath != null) 'downloaded': true,
    if (description.isNotEmpty) 'notes': description.length > 300 ? '${description.substring(0, 300)}…' : description,
  };
}

class Podcast {
  Podcast({
    required this.feedUrl,
    required this.title,
    this.author = '',
    this.description = '',
    this.imageUrl,
    this.link,
    this.categories = const [],
    this.episodes = const [],
    this.updatedAt,
    this.subscribedAt,
  });

  final String feedUrl;
  String title;
  String author;
  String description;
  String? imageUrl;
  String? link;
  List<String> categories;
  List<Episode> episodes;
  DateTime? updatedAt;
  DateTime? subscribedAt;

  bool get isTelegram => feedUrl.startsWith('tg:');

  /// Keep the newest episodes only; the feed has the rest.
  static const keptEpisodes = 150;

  Map<String, dynamic> toJson({bool withEpisodes = true}) => {
    'feedUrl': feedUrl,
    'title': title,
    'author': author,
    'description': description,
    'imageUrl': imageUrl,
    'link': link,
    'categories': categories,
    if (withEpisodes) 'episodes': episodes.take(keptEpisodes).map((e) => e.toJson()).toList(),
    'updatedAt': updatedAt?.toIso8601String(),
    'subscribedAt': subscribedAt?.toIso8601String(),
  };

  /// [toJson] as text, with each episode's kept text reused.
  String get json {
    final head = jsonEncode(toJson(withEpisodes: false));
    return '${head.substring(0, head.length - 1)},"episodes":[${episodes.take(keptEpisodes).map((e) => e.json).join(',')}]}';
  }

  factory Podcast.fromJson(Map j) => Podcast(
    feedUrl: '${j['feedUrl'] ?? ''}',
    title: '${j['title'] ?? ''}',
    author: '${j['author'] ?? ''}',
    description: '${j['description'] ?? ''}',
    imageUrl: j['imageUrl'] as String?,
    link: j['link'] as String?,
    categories: [for (final c in (j['categories'] as List? ?? const [])) '$c'],
    episodes: [for (final e in (j['episodes'] as List? ?? const [])) if (e is Map) Episode.fromJson(e)],
    updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}'),
    subscribedAt: DateTime.tryParse('${j['subscribedAt'] ?? ''}'),
  );

  Map<String, dynamic> describe() => {
    'show_id': feedUrl,
    'title': title,
    if (author.isNotEmpty) 'author': author,
    'episodes': episodes.length,
    if (isTelegram) 'telegram': true,
    if (categories.isNotEmpty) 'categories': categories.take(4).toList(),
    if (episodes.isNotEmpty && episodes.first.published != null) 'latest': episodes.first.published!.toIso8601String().substring(0, 10),
  };
}

/// Your history with one episode.
class EpisodeState {
  EpisodeState({required this.episode, this.posMs = 0, this.played = false, this.localPath, DateTime? updatedAt, UserMark? mark})
    : updatedAt = updatedAt ?? DateTime.now(),
      mark = mark ?? UserMark();

  Episode episode;
  int posMs;
  bool played;
  String? localPath;
  DateTime updatedAt;
  final UserMark mark;

  /// Worth keeping: something happened with this episode. (A state is made
  /// for any episode looked at; the rest needn't be saved.)
  bool get meaningful => played || posMs > 0 || localPath != null || !mark.isEmpty;

  /// [toJson] as text, with the episode's kept text reused.
  String get json {
    final rest = jsonEncode(toJson(withEpisode: false));
    return '{"episode":${episode.json},${rest.substring(1)}';
  }

  Map<String, dynamic> toJson({bool withEpisode = true}) => {
    if (withEpisode) 'episode': episode.toJson(),
    'posMs': posMs,
    'played': played,
    'localPath': localPath,
    'updatedAt': updatedAt.toIso8601String(),
    if (!mark.isEmpty) 'mark': mark.toJson(),
  };

  factory EpisodeState.fromJson(Map j) => EpisodeState(
    episode: Episode.fromJson(j['episode'] is Map ? j['episode'] as Map : const {}),
    posMs: (j['posMs'] as num?)?.toInt() ?? 0,
    played: j['played'] == true,
    localPath: j['localPath'] as String?,
    updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}'),
    mark: UserMark.fromJson(j['mark']),
  );
}

/// A show from the directory, before its feed is loaded.
class PodcastHit {
  PodcastHit({required this.title, this.id = '', this.author = '', this.artwork, this.feedUrl, this.genre = '', this.episodes = 0});
  final String id;
  final String title;
  final String author;
  final String? artwork;
  final String? feedUrl;
  final String genre;
  final int episodes;

  Map<String, dynamic> describe() => {
    'title': title,
    if (author.isNotEmpty) 'author': author,
    if (genre.isNotEmpty) 'genre': genre,
    if (episodes > 0) 'episodes': episodes,
    if (feedUrl != null) 'feed_url': feedUrl else 'apple_id': id,
  };
}

/// How a show's episodes are ordered.
enum EpisodeSort {
  newest('Newest first', 'Newest'),
  oldest('Oldest first', 'Oldest'),
  az('Title A–Z', 'A–Z'),
  za('Title Z–A', 'Z–A'),
  longest('Longest first', 'Longest'),
  shortest('Shortest first', 'Shortest');

  const EpisodeSort(this.label, this.short);
  final String label;
  final String short;

  static EpisodeSort parse(String? name) => values.where((v) => v.name == name).firstOrNull ?? newest;

  /// [eps] in this order. Feeds list newest first, so that needs no sorting.
  List<Episode> apply(List<Episode> eps) => switch (this) {
    newest => eps,
    oldest => eps.reversed.toList(),
    az => [...eps]..sort((a, b) => naturalCompare(a.title, b.title)),
    za => [...eps]..sort((a, b) => naturalCompare(b.title, a.title)),
    longest => [...eps]..sort((a, b) => b.durationMs.compareTo(a.durationMs)),
    shortest => [...eps]..sort((a, b) => a.durationMs.compareTo(b.durationMs)),
  };
}

/// Compares ignoring case, with runs of digits by their value, so
/// "Episode 9" comes before "Episode 10".
int naturalCompare(String a, String b) {
  a = a.toLowerCase();
  b = b.toLowerCase();
  bool digit(int c) => c >= 48 && c <= 57;
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
    if (digit(ca) && digit(cb)) {
      while (i < a.length - 1 && a.codeUnitAt(i) == 48 && digit(a.codeUnitAt(i + 1))) {
        i++;
      }
      while (j < b.length - 1 && b.codeUnitAt(j) == 48 && digit(b.codeUnitAt(j + 1))) {
        j++;
      }
      final si = i, sj = j;
      while (i < a.length && digit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && digit(b.codeUnitAt(j))) {
        j++;
      }
      if (i - si != j - sj) return (i - si) - (j - sj);
      final c = a.substring(si, i).compareTo(b.substring(sj, j));
      if (c != 0) return c;
      continue;
    }
    if (ca != cb) return ca - cb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

/// Podcast categories in Apple's directory: (name, genre id).
const podcastGenres = <(String, int)>[
  ('Technology', 1318), ('News', 1489), ('History', 1487), ('Science', 1533), ('Comedy', 1303), ('True Crime', 1488), //
  ('Business', 1321), ('Society & Culture', 1324), ('Health & Fitness', 1512), ('Education', 1304), ('Arts', 1301), //
  ('Fiction', 1483), ('Sports', 1545), ('TV & Film', 1309), ('Kids & Family', 1305), ('Music', 1310), //
  ('Religion & Spirituality', 1314), ('Self-Improvement', 1500), ('Mental Health', 1517), ('Books', 1482), //
  ('Philosophy', 1443), ('Documentary', 1543), ('Politics', 1527), ('Entrepreneurship', 1493), ('Investing', 1412), //
  ('Careers', 1410), ('Relationships', 1544), ('Parenting', 1521), ('Language Learning', 1498), ('Food', 1306), //
  ('Places & Travel', 1320), ('Nature', 1537), ('Science Fiction', 1485), ('Stand-Up', 1497), ('Video Games', 1509),
];

/// Countries Apple publishes podcast charts for: (code, name).
const chartCountries = <(String, String)>[
  ('us', 'United States'), ('gb', 'United Kingdom'), ('ca', 'Canada'), ('au', 'Australia'), ('in', 'India'), //
  ('ng', 'Nigeria'), ('ke', 'Kenya'), ('za', 'South Africa'), ('eg', 'Egypt'), ('ae', 'UAE'), ('sa', 'Saudi Arabia'), //
  ('de', 'Germany'), ('fr', 'France'), ('es', 'Spain'), ('it', 'Italy'), ('nl', 'Netherlands'), ('se', 'Sweden'), //
  ('br', 'Brazil'), ('mx', 'Mexico'), ('jp', 'Japan'), ('kr', 'South Korea'), ('sg', 'Singapore'), ('ph', 'Philippines'), //
  ('id', 'Indonesia'), ('tr', 'Türkiye'), ('ie', 'Ireland'), ('nz', 'New Zealand'),
];

// ---- radio ------------------------------------------------------------------------------

/// A live radio station from the directory.
class Station {
  const Station({required this.id, required this.name, required this.url, this.favicon, this.country = '', this.countryCode = '', this.tags = const [], this.language = '', this.bitrate = 0, this.homepage, this.codec = '', this.votes = 0});

  final String id;
  final String name;

  /// The stream itself (for TuneIn, the address that gives it).
  final String url;
  final String? favicon;
  final String country;
  final String countryCode;
  final List<String> tags;
  final String language;

  /// In kbps; 0 if unknown.
  final int bitrate;
  final String? homepage;
  final String codec;
  final int votes;

  String get flag => flagOf(countryCode);

  /// "jazz · news • 🇪🇹 Ethiopia"
  String get subtitle => [
    if (tags.isNotEmpty) tags.take(2).join(' · '),
    if (country.isNotEmpty) '$flag $country'.trim(),
  ].join(' • ');

  /// TuneIn stations don't carry a stream address until asked for one.
  bool get needsResolving => id.startsWith('ti:');

  static Station? fromTuneIn(Map m) {
    final guide = '${m['guide_id'] ?? ''}';
    final name = '${m['text'] ?? ''}'.trim();
    if (m['type'] != 'audio' || m['item'] != 'station' || guide.isEmpty || name.isEmpty) return null;
    final image = '${m['image'] ?? ''}'.trim().replaceFirst('http://', 'https://');
    final note = '${m['subtext'] ?? ''}'.trim();
    return Station(
      id: 'ti:$guide',
      name: name,
      url: 'https://opml.radiotime.com/Tune.ashx?id=$guide&formats=mp3,aac&render=json',
      favicon: image.startsWith('https://') ? image : null,
      tags: note.isEmpty ? const [] : [note],
      bitrate: int.tryParse('${m['bitrate'] ?? ''}') ?? 0,
    );
  }

  /// From Radio Browser. Null for anything that can't play: phones block
  /// plain-http audio, so only https streams are usable.
  static Station? fromDirectory(Map m) {
    final url = '${m['url_resolved'] ?? ''}'.trim();
    final id = '${m['stationuuid'] ?? ''}';
    final name = '${m['name'] ?? ''}'.trim();
    if (!url.startsWith('https://') || id.isEmpty || name.isEmpty) return null;
    final icon = '${m['favicon'] ?? ''}'.trim();
    final home = '${m['homepage'] ?? ''}'.trim();
    return Station(
      id: id,
      name: name,
      url: url,
      favicon: icon.startsWith('https://') ? icon : null,
      country: '${m['country'] ?? ''}'.trim(),
      countryCode: '${m['countrycode'] ?? ''}'.trim().toUpperCase(),
      tags: '${m['tags'] ?? ''}'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      language: '${m['language'] ?? ''}'.trim(),
      bitrate: m['bitrate'] is int ? m['bitrate'] as int : 0,
      homepage: home.startsWith('http') ? home : null,
      codec: '${m['codec'] ?? ''}'.trim(),
      votes: m['votes'] is int ? m['votes'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'favicon': favicon,
    'country': country,
    'countryCode': countryCode,
    'tags': tags,
    'language': language,
    'bitrate': bitrate,
    'homepage': homepage,
    if (codec.isNotEmpty) 'codec': codec,
  };

  factory Station.fromJson(Map j) => Station(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    url: '${j['url'] ?? ''}',
    favicon: j['favicon'] as String?,
    country: '${j['country'] ?? ''}',
    countryCode: '${j['countryCode'] ?? ''}',
    tags: [for (final t in (j['tags'] as List? ?? const [])) '$t'],
    language: '${j['language'] ?? ''}',
    bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
    homepage: j['homepage'] as String?,
    codec: '${j['codec'] ?? ''}',
  );

  Map<String, dynamic> describe() => {
    'station_id': id,
    'name': name,
    if (country.isNotEmpty) 'country': country,
    if (tags.isNotEmpty) 'tags': tags.take(4).toList(),
    if (language.isNotEmpty) 'language': language,
    if (bitrate > 0) 'kbps': bitrate,
  };
}

class RadioCountry {
  const RadioCountry(this.code, this.name, this.count);
  final String code;
  final String name;
  final int count;
  String get flag => countryFlag(code, name);
}

String countryFlag(String code, String name) {
  final direct = flagOf(code);
  if (direct.isNotEmpty) return direct;
  return flagOf(_isoByName[name.trim().toLowerCase().replaceFirst(RegExp(r'^the '), '')] ?? '');
}

/// 🇪🇹 from "ET".
String flagOf(String code) {
  if (code.length != 2) return '';
  final c = code.toUpperCase();
  final a = c.codeUnitAt(0), b = c.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// Country names TuneIn uses (it has no codes), for their flags.
const _isoByName = <String, String>{
  'afghanistan': 'AF', 'algeria': 'DZ', 'angola': 'AO', 'argentina': 'AR', 'armenia': 'AM', 'australia': 'AU', 'austria': 'AT', //
  'azerbaijan': 'AZ', 'bahrain': 'BH', 'bangladesh': 'BD', 'belarus': 'BY', 'belgium': 'BE', 'benin': 'BJ', 'bolivia': 'BO', //
  'bosnia and herzegovina': 'BA', 'botswana': 'BW', 'brazil': 'BR', 'bulgaria': 'BG', 'burkina faso': 'BF', 'burundi': 'BI', //
  'cambodia': 'KH', 'cameroon': 'CM', 'canada': 'CA', 'chad': 'TD', 'chile': 'CL', 'china': 'CN', 'colombia': 'CO', //
  'congo': 'CG', 'democratic republic of the congo': 'CD', 'costa rica': 'CR', "cote d'ivoire": 'CI', 'ivory coast': 'CI', //
  'croatia': 'HR', 'cuba': 'CU', 'cyprus': 'CY', 'czech republic': 'CZ', 'czechia': 'CZ', 'denmark': 'DK', 'djibouti': 'DJ', //
  'dominican republic': 'DO', 'ecuador': 'EC', 'egypt': 'EG', 'el salvador': 'SV', 'eritrea': 'ER', 'estonia': 'EE', //
  'ethiopia': 'ET', 'finland': 'FI', 'france': 'FR', 'gabon': 'GA', 'gambia': 'GM', 'georgia': 'GE', 'germany': 'DE', //
  'ghana': 'GH', 'greece': 'GR', 'guatemala': 'GT', 'guinea': 'GN', 'haiti': 'HT', 'honduras': 'HN', 'hong kong': 'HK', //
  'hungary': 'HU', 'iceland': 'IS', 'india': 'IN', 'indonesia': 'ID', 'iran': 'IR', 'iraq': 'IQ', 'ireland': 'IE', //
  'israel': 'IL', 'italy': 'IT', 'jamaica': 'JM', 'japan': 'JP', 'jordan': 'JO', 'kazakhstan': 'KZ', 'kenya': 'KE', //
  'kuwait': 'KW', 'latvia': 'LV', 'lebanon': 'LB', 'liberia': 'LR', 'libya': 'LY', 'lithuania': 'LT', 'luxembourg': 'LU', //
  'madagascar': 'MG', 'malawi': 'MW', 'malaysia': 'MY', 'mali': 'ML', 'malta': 'MT', 'mauritius': 'MU', 'mexico': 'MX', //
  'moldova': 'MD', 'mongolia': 'MN', 'morocco': 'MA', 'mozambique': 'MZ', 'myanmar': 'MM', 'namibia': 'NA', 'nepal': 'NP', //
  'netherlands': 'NL', 'new zealand': 'NZ', 'nicaragua': 'NI', 'niger': 'NE', 'nigeria': 'NG', 'north macedonia': 'MK', //
  'norway': 'NO', 'oman': 'OM', 'pakistan': 'PK', 'palestine': 'PS', 'panama': 'PA', 'paraguay': 'PY', 'peru': 'PE', //
  'philippines': 'PH', 'poland': 'PL', 'portugal': 'PT', 'puerto rico': 'PR', 'qatar': 'QA', 'romania': 'RO', 'russia': 'RU', //
  'rwanda': 'RW', 'saudi arabia': 'SA', 'senegal': 'SN', 'serbia': 'RS', 'sierra leone': 'SL', 'singapore': 'SG', //
  'slovakia': 'SK', 'slovenia': 'SI', 'somalia': 'SO', 'south africa': 'ZA', 'south korea': 'KR', 'south sudan': 'SS', //
  'spain': 'ES', 'sri lanka': 'LK', 'sudan': 'SD', 'sweden': 'SE', 'switzerland': 'CH', 'syria': 'SY', 'taiwan': 'TW', //
  'tanzania': 'TZ', 'thailand': 'TH', 'togo': 'TG', 'trinidad and tobago': 'TT', 'tunisia': 'TN', 'turkey': 'TR', //
  'türkiye': 'TR', 'uganda': 'UG', 'ukraine': 'UA', 'united arab emirates': 'AE', 'united kingdom': 'GB', 'uk': 'GB', //
  'united states': 'US', 'usa': 'US', 'uruguay': 'UY', 'uzbekistan': 'UZ', 'venezuela': 'VE', 'vietnam': 'VN', //
  'yemen': 'YE', 'zambia': 'ZM', 'zimbabwe': 'ZW',
};
