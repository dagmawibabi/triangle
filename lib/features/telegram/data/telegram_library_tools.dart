part of 'telegram_tools.dart';

// Free books, audiobooks, radio and podcasts (Project Gutenberg, Open
// Library, LibriVox, the Internet Archive, Radio Browser, Apple's podcast
// directory) and two reference sources (country facts, NASA's astronomy
// picture of the day). All keyless; NASA takes an optional key.

final _libraryTools = <TelegramTool>[
  TelegramTool(
    name: 'ebook_search',
    label: 'Finding free ebooks',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Free public-domain ebooks from Project Gutenberg (70,000+ classics): title, authors, languages, subjects, '
        'summary, cover and download links (EPUB, Kindle, plain text). Search by title or author, or browse a topic '
        '("science fiction", "philosophy"); leave both out for the most popular. The user sees book cards they can '
        'read, download or listen to.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Words in the title or author name.'},
      'topic': {'type': 'string', 'description': 'A subject or bookshelf, like "detective", "poetry", "children".'},
      'language': {'type': 'string', 'description': 'Two-letter language codes, comma-separated, like "en" or "fr,de".'},
      'sort': {'type': 'string', 'enum': ['popular', 'new', 'old'], 'description': 'popular (default), new or old (by Gutenberg id).'},
      'page': {'type': 'integer', 'description': 'Page of 32 results; default 1.'},
    }),
  ),
  TelegramTool(
    name: 'ebook_details',
    label: 'Looking at an ebook',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'One Project Gutenberg book: authors with their years, subjects, summary, downloads and every format link.',
    parameters: _obj({
      'id': {'type': 'integer', 'description': 'The Gutenberg book id, from ebook_search.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'ebook_download',
    label: 'Downloading an ebook',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Downloads a Project Gutenberg book to the phone (EPUB by default, or Kindle or plain text). It becomes a file of '
        'this conversation: the user can open it, and you can send it with send_message.',
    parameters: _obj({
      'id': {'type': 'integer', 'description': 'The Gutenberg book id.'},
      'format': {'type': 'string', 'enum': ['epub', 'kindle', 'text'], 'description': 'File format; default epub.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'audiobook_search',
    label: 'Finding free audiobooks',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Free audiobooks: LibriVox volunteer readings of public-domain books and the Internet Archive\'s audiobook '
        'collection. Each with author, length, chapters, language and cover. Leave query out for new LibriVox releases. '
        'The user sees cards with chapters to play or download.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'A title or author, like "Sherlock Holmes" or "Austen".'},
      'source': {'type': 'string', 'enum': ['all', 'librivox', 'archive'], 'description': 'Where to look; default all.'},
      'limit': {'type': 'integer', 'description': '1-25; default 12.'},
    }),
  ),
  TelegramTool(
    name: 'audiobook_chapters',
    label: 'Opening an audiobook',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'An audiobook\'s chapters with their lengths and stream links, ready to play or download.',
    parameters: _obj({
      'source': {'type': 'string', 'enum': ['librivox', 'archive'], 'description': 'The source from audiobook_search.'},
      'id': {'type': 'string', 'description': 'The audiobook id from audiobook_search.'},
      'title': {'type': 'string', 'description': 'Its title, for the card.'},
    }, ['source', 'id']),
  ),
  TelegramTool(
    name: 'radio_search',
    label: 'Finding radio stations',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Live radio from around the world (Radio Browser, 50,000+ stations): by name, country, genre tag or language, '
        'most listened first. Each with its logo, country, tags, bitrate and a stream the user can play right away.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Words in the station name, like "BBC" or "jazz fm".'},
      'country': {'type': 'string', 'description': 'A country name or two-letter code, like "ET" or "Germany".'},
      'tag': {'type': 'string', 'description': 'A genre or topic, like news, jazz, classical, gospel, lofi, sports.'},
      'language': {'type': 'string', 'description': 'A language name, like amharic, english, spanish.'},
      'order': {'type': 'string', 'enum': ['clickcount', 'votes', 'clicktrend', 'bitrate', 'name', 'random'], 'description': 'Order; default clickcount (most listened).'},
      'limit': {'type': 'integer', 'description': '1-40; default 15.'},
    }),
  ),
  TelegramTool(
    name: 'podcast_search',
    label: 'Finding podcasts',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'Podcasts from Apple\'s directory: show, host, genre, episode count, cover and feed. The user can open a show\'s episodes and play them.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'A show, topic or person, like "history" or "Lex Fridman".'},
      'country': {'type': 'string', 'description': 'Store country code; default us.'},
      'limit': {'type': 'integer', 'description': '1-25; default 12.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'podcast_top',
    label: 'Checking the podcast charts',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'Today\'s most popular podcasts in a country (Apple Podcasts charts).',
    parameters: _obj({
      'country': {'type': 'string', 'description': 'Two-letter country code; default us.'},
      'limit': {'type': 'integer', 'description': '10-50; default 20.'},
    }),
  ),
  TelegramTool(
    name: 'podcast_episodes',
    label: 'Opening a podcast',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'A podcast\'s latest episodes from its feed: title, date, length, description and audio, ready to play or download.',
    parameters: _obj({
      'feed': {'type': 'string', 'description': 'The show\'s RSS feed address, from podcast_search.'},
      'show_id': {'type': 'integer', 'description': 'Or its Apple id (from podcast_top), when there is no feed.'},
      'limit': {'type': 'integer', 'description': 'Episodes, 1-50; default 15.'},
    }),
  ),
  TelegramTool(
    name: 'audio_download',
    label: 'Downloading audio',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description: 'Saves a podcast episode or audiobook chapter to the phone, to listen offline or send to a chat.',
    parameters: _obj({
      'url': {'type': 'string', 'description': 'The episode or chapter audio link.'},
      'title': {'type': 'string', 'description': 'What to call the file: the episode or chapter title.'},
      'kind': {'type': 'string', 'enum': ['podcast', 'audiobook'], 'description': 'Which Files tab it goes in; default podcast.'},
      'from': {'type': 'string', 'description': 'The show or book it is from.'},
      'cover': {'type': 'string', 'description': 'Its cover picture link, from the episode or book.'},
    }, ['url']),
  ),
  TelegramTool(
    name: 'play_audio',
    label: 'Playing audio',
    category: ToolCategory.library,
    cost: ToolCost.device,
    description:
        'Plays a radio station, podcast episode or audiobook chapter in the app\'s player (it keeps playing while the '
        'user chats; the player bar controls it). Use when the user asks to play or listen.',
    parameters: _obj({
      'url': {'type': 'string', 'description': 'The stream or audio link.'},
      'title': {'type': 'string', 'description': 'What is playing, like the station or episode name.'},
      'subtitle': {'type': 'string', 'description': 'A second line, like the show, author or country.'},
      'live': {'type': 'boolean', 'description': 'A live stream (radio): no seeking, no end.'},
    }, ['url', 'title']),
  ),
  TelegramTool(
    name: 'country_info',
    label: 'Looking up a country',
    category: ToolCategory.explore,
    cost: ToolCost.web,
    description:
        'A country\'s facts (an open countries dataset, with World Bank population): official and native names, flag, '
        'capital, region, population, area, languages, currencies, neighbours, calling code, internet domain and map. '
        'The user sees a country card.',
    parameters: _obj({
      'country': {'type': 'string', 'description': 'A name or code, like "Ethiopia", "ET" or "ETH".'},
    }, ['country']),
  ),
  TelegramTool(
    name: 'countries_list',
    label: 'Listing countries',
    category: ToolCategory.explore,
    cost: ToolCost.web,
    description: 'Countries in a region, or that speak a language or use a currency, sorted by population, area or name.',
    parameters: _obj({
      'region': {'type': 'string', 'description': 'africa, americas, asia, europe or oceania.'},
      'language': {'type': 'string', 'description': 'A language name or code, like "french" or "amh".'},
      'currency': {'type': 'string', 'description': 'A currency code, like EUR or USD.'},
      'sort': {'type': 'string', 'enum': ['population', 'area', 'name'], 'description': 'Order; default population.'},
      'limit': {'type': 'integer', 'description': '1-60; default 20.'},
    }),
  ),
  TelegramTool(
    name: 'nasa_apod',
    label: 'Fetching NASA\'s picture of the day',
    category: ToolCategory.explore,
    cost: ToolCost.web,
    description:
        'NASA\'s Astronomy Picture of the Day: the image (or video), its title and an astronomer\'s explanation. Today '
        'by default; a date (since 1995-06-16), a range, or a few random ones.',
    parameters: _obj({
      'date': {'type': 'string', 'description': 'A date like "2024-04-08"; default today.'},
      'count': {'type': 'integer', 'description': 'Instead: this many random pictures, 1-12.'},
      'start_date': {'type': 'string', 'description': 'Instead: from this date (up to 12 days).'},
      'end_date': {'type': 'string', 'description': 'With start_date: until this date; default today.'},
    }),
  ),
];

const _libraryPolicies = <String, ToolPolicy>{
  'ebook_search': ToolPolicy(ToolAccess.read),
  'ebook_details': ToolPolicy(ToolAccess.read),
  'ebook_download': ToolPolicy(ToolAccess.modify),
  'audiobook_search': ToolPolicy(ToolAccess.read),
  'audiobook_chapters': ToolPolicy(ToolAccess.read),
  'radio_search': ToolPolicy(ToolAccess.read),
  'podcast_search': ToolPolicy(ToolAccess.read),
  'podcast_top': ToolPolicy(ToolAccess.read),
  'podcast_episodes': ToolPolicy(ToolAccess.read),
  'audio_download': ToolPolicy(ToolAccess.modify),
  'play_audio': ToolPolicy(ToolAccess.modify),
  'country_info': ToolPolicy(ToolAccess.read),
  'countries_list': ToolPolicy(ToolAccess.read),
  'nasa_apod': ToolPolicy(ToolAccess.read),
};

const _libraryReferences = <String, ToolReference>{
  'ebook_search': ToolReference(['total', 'books', 'page', 'source'], limits: ['32 per page.']),
  'ebook_details': ToolReference(['id', 'title', 'authors', 'languages', 'subjects', 'bookshelves', 'summary', 'downloads', 'cover', 'epub', 'kindle', 'text', 'html', 'url']),
  'ebook_download': ToolReference(['saved', 'title', 'format', 'file', 'size_kb', 'size', 'created_files']),
  'audiobook_search': ToolReference(['query', 'audiobooks', 'source'], limits: ['limit: 1-25.']),
  'audiobook_chapters': ToolReference(['source', 'id', 'title', 'chapters', 'total_seconds']),
  'radio_search': ToolReference(['stations', 'source'], limits: ['limit: 1-40.']),
  'podcast_search': ToolReference(['query', 'shows', 'source'], limits: ['limit: 1-25.']),
  'podcast_top': ToolReference(['country', 'shows', 'source'], limits: ['limit: 10-50.']),
  'podcast_episodes': ToolReference(['title', 'author', 'description', 'cover', 'categories', 'feed', 'episodes'], limits: ['limit: 1-50.']),
  'audio_download': ToolReference(['saved', 'title', 'file', 'size_kb', 'size', 'created_files']),
  'play_audio': ToolReference(['playing', 'title']),
  'country_info': ToolReference(['name', 'official', 'native', 'code', 'flag', 'capital', 'region', 'population', 'area_km2', 'languages', 'currencies', 'timezones', 'borders', 'calling_code', 'map']),
  'countries_list': ToolReference(['count', 'countries', 'source'], limits: ['limit: 1-60.']),
  'nasa_apod': ToolReference(['pictures', 'source'], limits: ['count: 1-12; dates from 1995-06-16.']),
};

extension _LibraryTools on TelegramToolRunner {
  Future<ToolOutput>? _runLibrary(String name, Map<String, dynamic> args) => switch (name) {
    'ebook_search' => _wrap(_ebookSearch(args)),
    'ebook_details' => _wrap(_ebookDetails(args)),
    'ebook_download' => _wrap(_ebookDownload(args)),
    'book_search' => _wrap(_bookSearch(args)),
    'audiobook_search' => _wrap(_audiobookSearch(args)),
    'audiobook_chapters' => _wrap(_audiobookChapters(args)),
    'radio_search' => _wrap(_radioSearch(args)),
    'podcast_search' => _wrap(_podcastSearch(args)),
    'podcast_top' => _wrap(_podcastTop(args)),
    'podcast_episodes' => _wrap(_podcastEpisodes(args)),
    'audio_download' => _wrap(_audioDownload(args)),
    'country_info' => _wrap(_countryInfo(args)),
    'countries_list' => _wrap(_countriesList(args)),
    'nasa_apod' => _wrap(_nasaApod(args)),
    _ => null,
  };

  LibraryApi get _lib => LibraryApi.instance;

  static Future<ToolOutput> _wrap(Future<ToolOutput> f) async {
    try {
      return await f;
    } on LibraryException catch (e) {
      return ToolOutput({'error': e.message});
    } on TimeoutException {
      return const ToolOutput({'error': 'The service took too long to answer; try again.'});
    }
  }

  static int _n(Object? v, int def, int min, int max) => ((v as num?)?.toInt() ?? def).clamp(min, max);

  Future<ToolOutput> _ebookSearch(Map<String, dynamic> a) async {
    final page = _n(a['page'], 1, 1, 100);
    final r = await _lib.ebooks(query: '${a['query'] ?? ''}', topic: '${a['topic'] ?? ''}', language: '${a['language'] ?? ''}', sort: '${a['sort'] ?? 'popular'}', page: page);
    return ToolOutput({'total': r.total, 'page': page, 'books': r.books, 'source': 'Project Gutenberg (Gutendex)'});
  }

  Future<ToolOutput> _ebookDetails(Map<String, dynamic> a) async {
    final id = (a['id'] as num?)?.toInt();
    if (id == null) throw const LibraryException('id is required.');
    return ToolOutput(await _lib.ebook(id));
  }

  Future<ToolOutput> _ebookDownload(Map<String, dynamic> a) async {
    final id = (a['id'] as num?)?.toInt();
    if (id == null) throw const LibraryException('id is required.');
    final b = await _lib.ebook(id);
    final format = const ['epub', 'kindle', 'text'].contains(a['format']) ? '${a['format']}' : 'epub';
    final url = b[format] as String? ?? b['epub'] as String?;
    if (url == null) throw LibraryException('"${b['title']}" has no $format file.');
    final ext = url == b[format] ? (format == 'kindle' ? 'mobi' : (format == 'text' ? 'txt' : 'epub')) : 'epub';
    final f = await _lib.download(url, LibraryApi.fileName('${b['title']}', ext), meta: {
      'library': 'book',
      'title': b['title'],
      'subtitle': (b['authors'] as List? ?? const []).whereType<Map>().map((a) => '${a['name']}').join(', '),
      'cover': b['cover'],
    });
    return ToolOutput({
      'saved': true,
      'title': b['title'],
      'authors': b['authors'],
      'cover': b['cover'],
      'format': ext,
      'file': f.path,
      'size_kb': ((await f.length()) / 1024).ceil(),
      'size': formatBytes(await f.length()),
      'created_files': [f.path],
    });
  }

  Future<ToolOutput> _bookSearch(Map<String, dynamic> a) async {
    final q = '${a['query'] ?? ''}'.trim();
    if (q.isEmpty) throw const LibraryException('query is required.');
    return ToolOutput({'query': q, 'books': await _lib.openLibrary(q, limit: _n(a['limit'], 10, 1, 20)), 'source': 'Open Library'});
  }

  Future<ToolOutput> _audiobookSearch(Map<String, dynamic> a) async {
    final q = '${a['query'] ?? ''}'.trim();
    final list = await _lib.audiobooks(q, source: '${a['source'] ?? 'all'}', limit: _n(a['limit'], 12, 1, 25));
    return ToolOutput({'query': q, 'audiobooks': list, 'source': 'LibriVox and the Internet Archive'});
  }

  Future<ToolOutput> _audiobookChapters(Map<String, dynamic> a) async {
    final source = '${a['source'] ?? ''}', id = '${a['id'] ?? ''}'.trim();
    if (id.isEmpty || !const ['librivox', 'archive'].contains(source)) throw const LibraryException('Give source (librivox or archive) and id.');
    final tracks = await _lib.audiobookTracks(source, id);
    return ToolOutput({
      'source': source,
      'id': id,
      'title': a['title'],
      'chapters': tracks,
      'total_seconds': tracks.fold<int>(0, (n, t) => n + ((t['seconds'] as int?) ?? 0)),
    });
  }

  Future<ToolOutput> _radioSearch(Map<String, dynamic> a) async => ToolOutput({
    'stations': await _lib.stations(
      name: '${a['name'] ?? ''}',
      country: '${a['country'] ?? ''}',
      tag: '${a['tag'] ?? ''}',
      language: '${a['language'] ?? ''}',
      order: '${a['order'] ?? 'clickcount'}',
      limit: _n(a['limit'], 15, 1, 40),
    ),
    'source': 'Radio Browser',
  });

  Future<ToolOutput> _podcastSearch(Map<String, dynamic> a) async {
    final q = '${a['query'] ?? ''}'.trim();
    if (q.isEmpty) throw const LibraryException('query is required.');
    return ToolOutput({'query': q, 'shows': await _lib.podcasts(q, country: '${a['country'] ?? 'us'}', limit: _n(a['limit'], 12, 1, 25)), 'source': 'Apple Podcasts'});
  }

  Future<ToolOutput> _podcastTop(Map<String, dynamic> a) async {
    final c = '${a['country'] ?? 'us'}'.toLowerCase();
    return ToolOutput({'country': c, 'shows': await _lib.topPodcasts(country: c, limit: _n(a['limit'], 20, 10, 50)), 'source': 'Apple Podcasts charts'});
  }

  Future<ToolOutput> _podcastEpisodes(Map<String, dynamic> a) async {
    var feed = '${a['feed'] ?? ''}'.trim();
    if (feed.isEmpty && a['show_id'] != null) feed = await _lib.feedFor(a['show_id']!) ?? '';
    if (feed.isEmpty) throw const LibraryException('Give feed (or show_id).');
    return ToolOutput(await _lib.podcastFeed(feed, limit: _n(a['limit'], 15, 1, 50)));
  }

  Future<ToolOutput> _audioDownload(Map<String, dynamic> a) async {
    final url = '${a['url'] ?? ''}'.trim();
    if (!url.startsWith('http')) throw const LibraryException('Give the audio url.');
    final title = '${a['title'] ?? 'audio'}';
    final ext = RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav)(\?|$)', caseSensitive: false).firstMatch(url)?[1]?.toLowerCase() ?? 'mp3';
    final from = '${a['from'] ?? ''}'.trim();
    final f = await _lib.download(url, LibraryApi.fileName(from.isEmpty ? title : '$from - $title', ext), meta: {
      'library': a['kind'] == 'audiobook' ? 'audiobook' : 'podcast',
      'title': title,
      'subtitle': from.isEmpty ? null : from,
      'cover': a['cover'],
    });
    return ToolOutput({'saved': true, 'title': title, 'file': f.path, 'size_kb': ((await f.length()) / 1024).ceil(), 'size': formatBytes(await f.length()), 'created_files': [f.path]});
  }

  Future<ToolOutput> _countryInfo(Map<String, dynamic> a) async {
    final q = '${a['country'] ?? ''}'.trim();
    if (q.isEmpty) throw const LibraryException('country is required.');
    return ToolOutput({...await _lib.countryInfo(q), 'source': 'mledoze/countries and the World Bank'});
  }

  Future<ToolOutput> _countriesList(Map<String, dynamic> a) async {
    final list = await _lib.countries(
      region: '${a['region'] ?? ''}'.trim().toLowerCase(),
      language: '${a['language'] ?? ''}'.trim().toLowerCase(),
      currency: '${a['currency'] ?? ''}'.trim().toLowerCase(),
      sort: '${a['sort'] ?? 'population'}',
      limit: _n(a['limit'], 20, 1, 60),
    );
    return ToolOutput({'count': list.length, 'countries': list, 'source': 'mledoze/countries and the World Bank'});
  }

  Future<ToolOutput> _nasaApod(Map<String, dynamic> a) async {
    String? d(String k) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${a[k] ?? ''}') ? '${a[k]}' : null;
    final pics = await _lib.apod(key: _settings.nasaKey.trim(), date: d('date'), count: (a['count'] as num?)?.toInt(), start: d('start_date'), end: d('end_date'));
    return ToolOutput({'pictures': pics.take(12).toList(), 'source': 'NASA APOD'});
  }
}
