part of 'telegram_tools.dart';

// Books from legal sources, YouTube and X (Twitter), all without keys.
//
// Books: Open Library (metadata for millions of books; public-domain scans
// on the Internet Archive), Project Gutenberg through Gutendex (75,000+
// public-domain ebooks), Standard Ebooks (carefully made public-domain
// ebooks), and Google Books when its shared free quota allows. Only
// public-domain and openly licensed books are downloaded.
//
// YouTube: the public watch, search and channel pages and the RSS feeds.
// No video downloads (YouTube's terms forbid them).
//
// X: single posts and profiles through public embed services. Timelines,
// search and posting need a signed-in account: the browser tools after the
// user logs in there.

final _discoverTools = <TelegramTool>[
  TelegramTool(
    name: 'search_books',
    label: 'Searching books',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Searches books by title, author, subject or anything (query), across Open Library (millions of books: '
        'editions, ratings, covers, which are free to read), Project Gutenberg and Standard Ebooks (public-domain '
        'ebooks, free to download), and Google Books. free_only keeps books with a legal free copy. Each result has '
        'a book_id for book_details and download_book.',
    parameters: _obj({
      'query': {'type': 'string'},
      'author': {'type': 'string'},
      'subject': {'type': 'string', 'description': 'e.g. "science fiction", "history of Ethiopia".'},
      'language': {'type': 'string', 'description': 'Two-letter code, e.g. en, am, fr.'},
      'free_only': {'type': 'boolean'},
      'source': {'type': 'string', 'enum': ['all', 'openlibrary', 'gutenberg', 'standardebooks', 'google']},
      'limit': {'type': 'integer', 'description': 'Per source; default 8.'},
    }),
  ),
  TelegramTool(
    name: 'book_details',
    label: 'Reading about a book',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Everything about one book (book_id from search_books): description, authors, first published, subjects, '
        'editions and ISBNs, pages, ratings, the formats it can be downloaded in when it is free, and its cover, '
        'which is shown to the user.',
    parameters: _obj({
      'book_id': {'type': 'string'},
    }, ['book_id']),
  ),
  TelegramTool(
    name: 'find_free_copy',
    label: 'Looking for a free copy',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Checks every legal source for a free copy of a book (public domain or openly licensed): Gutenberg, '
        'Standard Ebooks, and Internet Archive scans. Says plainly when there is none (most books still under '
        'copyright) and where it can be borrowed or bought instead.',
    parameters: _obj({
      'title': {'type': 'string'},
      'author': {'type': 'string'},
    }, ['title']),
  ),
  TelegramTool(
    name: 'download_book',
    label: 'Downloading a book',
    category: ToolCategory.library,
    cost: ToolCost.web,
    description:
        'Downloads a free, legal ebook (book_id from search_books or find_free_copy) onto the phone: epub (default), '
        'kindle, pdf or txt where offered. It becomes a file of this conversation: send it with send_message, or read '
        'it with run_code. Only public-domain and openly licensed books can be downloaded.',
    parameters: _obj({
      'book_id': {'type': 'string'},
      'format': {'type': 'string', 'enum': ['epub', 'kindle', 'pdf', 'txt']},
    }, ['book_id']),
  ),
  TelegramTool(
    name: 'x_post',
    label: 'Reading a post on X',
    category: ToolCategory.discover,
    cost: ToolCost.web,
    description:
        'One post on X (Twitter) from its link or id: text, author, date, likes, reposts, replies, views, its photos '
        'and videos (the first photo is shown), and the post it quotes. Works without an X account.',
    parameters: _obj({
      'post': {'type': 'string', 'description': 'An x.com / twitter.com status link, or its id.'},
    }, ['post']),
  ),
  TelegramTool(
    name: 'x_profile',
    label: 'Looking at an X profile',
    category: ToolCategory.discover,
    cost: ToolCost.web,
    description:
        'An X (Twitter) profile: name, bio, followers, following, posts count, joined date, location, website and '
        'picture. Recent posts, search and posting need the user signed in to x.com in the app\'s browser (then use '
        'browser_open on x.com).',
    parameters: _obj({
      'username': {'type': 'string', 'description': '@handle or profile link.'},
    }, ['username']),
  ),
];

extension _DiscoverTools on TelegramToolRunner {
  Future<ToolOutput>? _runDiscover(String name, Map<String, dynamic> args) => switch (name) {
    'search_books' => _searchBooks(args),
    'book_details' => _bookDetails(args),
    'find_free_copy' => _freeCopy(args),
    'download_book' => _downloadBook(args),
    'youtube_search' => _ytSearch(args),
    'youtube_video' => _ytVideo(args),
    'youtube_transcript' => _ytTranscript(args),
    'youtube_channel' => _ytChannel(args),
    'youtube_playlist' => _ytPlaylist(args),
    'x_post' => _xPost(args),
    'x_profile' => _xProfile(args),
    _ => null,
  };

  // ---- shared ------------------------------------------------------------------

  Future<Object?> _json(Uri url, {Map<String, String> headers = const {}}) async {
    final r = await _web.request('GET', url, headers: {'accept': 'application/json', ...headers});
    if (r.statusCode == 429) throw ArgumentError('${url.host} is busy (rate limited); try again in a bit.');
    if (r.statusCode >= 400) throw ArgumentError('${url.host} said ${r.statusCode}.');
    return jsonDecode(WebFetcher.decodeBody(r));
  }

  /// Saves a picture so the chat shows it; null when it can't be had.
  Future<String?> _picture(String? url, String name) async {
    if (url == null || url.isEmpty) return null;
    try {
      return (await _web.download(Uri.parse(url), name: name)).path;
    } catch (_) {
      return null;
    }
  }

  static String? _cut(Object? s, [int max = 600]) {
    if (s == null) return null;
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length > max ? '${t.substring(0, max)}…' : t;
  }

  // ---- books -------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _openLibrary(String q, {String? author, String? subject, String? language, bool freeOnly = false, int limit = 8}) async {
    final j = await _json(Uri.https('openlibrary.org', '/search.json', {
      if (q.isNotEmpty) 'q': q,
      'author': ?author,
      'subject': ?subject,
      if (language != null) 'language': _lang3(language),
      if (freeOnly) 'ebook_access': 'public',
      'limit': '$limit',
      'fields': 'key,title,author_name,first_publish_year,edition_count,isbn,cover_i,subject,ia,ebook_access,number_of_pages_median,ratings_average,ratings_count,language',
    })) as Map;
    return [
      for (final d in (j['docs'] as List? ?? const []).cast<Map>())
        {
          'book_id': 'ol:${'${d['key']}'.split('/').last}',
          'title': d['title'],
          if (d['cover_i'] != null) 'cover': 'https://covers.openlibrary.org/b/id/${d['cover_i']}-M.jpg',
          'authors': ?d['author_name'],
          'first_published': ?d['first_publish_year'],
          'editions': ?d['edition_count'],
          if (d['number_of_pages_median'] != null) 'pages': d['number_of_pages_median'],
          if (d['ratings_average'] != null) 'rating': '${(d['ratings_average'] as num).toStringAsFixed(1)}/5 (${d['ratings_count']})',
          'free': switch (d['ebook_access']) {
            'public' => 'free to read and download (Internet Archive)',
            'borrowable' => 'can be borrowed free at openlibrary.org',
            _ => 'no free copy',
          },
          if (d['ebook_access'] == 'public' && (d['ia'] as List?)?.isNotEmpty == true) 'free_copy_id': 'ia:${(d['ia'] as List).first}',
        },
    ];
  }

  /// Open Library speaks three-letter MARC codes.
  static String _lang3(String two) => const {
    'en': 'eng', 'fr': 'fre', 'de': 'ger', 'es': 'spa', 'it': 'ita', 'pt': 'por', 'ru': 'rus', 'ar': 'ara', 'am': 'amh',
    'zh': 'chi', 'ja': 'jpn', 'nl': 'dut', 'sv': 'swe', 'pl': 'pol', 'tr': 'tur', 'hi': 'hin', 'sw': 'swa',
  }[two.toLowerCase()] ?? two;

  Future<List<Map<String, dynamic>>> _gutenberg(String q, {String? language, int limit = 8}) async {
    final j = await _json(Uri.https('gutendex.com', '/books/', {'search': q, 'languages': ?language})) as Map;
    return [
      for (final b in (j['results'] as List? ?? const []).cast<Map>().take(limit))
        {
          'book_id': 'gutenberg:${b['id']}',
          'title': b['title'],
          'cover': ?(b['formats'] as Map?)?['image/jpeg'],
          'authors': [for (final a in (b['authors'] as List? ?? const [])) (a as Map)['name']],
          'languages': b['languages'],
          'downloads_last_month': b['download_count'],
          'free': 'public domain: free to download',
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _standardEbooks(String q, {int limit = 8}) async {
    final r = await _web.request('GET', Uri.https('standardebooks.org', '/ebooks', {'query': q}));
    if (r.statusCode >= 400) return const [];
    final doc = html_parser.parse(WebFetcher.decodeBody(r));
    return [
      for (final li in doc.querySelectorAll('li[typeof="schema:Book"]').take(limit))
        {
          'book_id': 'se:${li.attributes['about']}',
          if (li.querySelector('img')?.attributes['src'] case final src?) 'cover': 'https://standardebooks.org$src',
          'title': li.querySelector('[property="schema:name"]')?.text.trim() ?? li.attributes['about'],
          'authors': [for (final a in li.querySelectorAll('[typeof="schema:Person"] [property="schema:name"]')) a.text.trim()],
          'free': 'public domain: free, carefully produced ebook',
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _googleBooks(String q, {int limit = 8, bool freeOnly = false}) async {
    final j = await _json(Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': q,
      'maxResults': '$limit',
      if (freeOnly) 'filter': 'free-ebooks',
    })) as Map;
    return [
      for (final b in (j['items'] as List? ?? const []).cast<Map>())
        () {
          final v = b['volumeInfo'] as Map? ?? const {};
          final a = b['accessInfo'] as Map? ?? const {};
          return <String, dynamic>{
            'book_id': 'google:${b['id']}',
            'title': v['title'],
            if ((v['imageLinks'] as Map?)?['thumbnail'] case final t?) 'cover': '$t'.replaceFirst('http://', 'https://'),
            'authors': ?v['authors'],
            'published': ?v['publishedDate'],
            'pages': ?v['pageCount'],
            if (v['averageRating'] != null) 'rating': '${v['averageRating']}/5 (${v['ratingsCount']})',
            'free': a['viewability'] == 'ALL_PAGES' && (a['epub'] as Map?)?['downloadLink'] != null ? 'free ebook from Google' : (a['viewability'] == 'PARTIAL' ? 'preview only' : 'no free copy'),
          };
        }(),
    ];
  }

  Future<ToolOutput> _searchBooks(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    final author = '${args['author'] ?? ''}'.trim();
    final subject = '${args['subject'] ?? ''}'.trim();
    if (q.isEmpty && author.isEmpty && subject.isEmpty) throw ArgumentError('Give a query, author or subject.');
    final source = '${args['source'] ?? 'all'}';
    final freeOnly = args['free_only'] == true;
    final lang = '${args['language'] ?? ''}'.trim();
    final limit = TelegramToolRunner._int(args, 'limit', fallback: 8, max: 20);
    final words = [q, author, subject].where((s) => s.isNotEmpty).join(' ');
    final out = <String, dynamic>{};
    final failed = <String, String>{};
    Future<void> from(String key, Future<List<Map<String, dynamic>>> Function() run) async {
      if (source != 'all' && source != key) return;
      try {
        final list = await run();
        if (list.isNotEmpty) out[key] = list;
      } catch (e) {
        failed[key] = e is ArgumentError ? '${e.message}' : '$e';
      }
    }

    await Future.wait([
      from('openlibrary', () => _openLibrary(q, author: author.isEmpty ? null : author, subject: subject.isEmpty ? null : subject, language: lang.isEmpty ? null : lang, freeOnly: freeOnly, limit: limit)),
      from('gutenberg', () => _gutenberg(words, language: lang.isEmpty ? null : lang, limit: limit)),
      from('standardebooks', () => _standardEbooks(words, limit: limit)),
      from('google', () => _googleBooks(words, limit: limit, freeOnly: freeOnly)),
    ]);
    return ToolOutput({
      'query': words,
      ...out,
      if (out.isEmpty) 'note': 'Nothing found.',
      if (failed.isNotEmpty) 'unavailable': failed,
    });
  }

  Future<ToolOutput> _bookDetails(Map<String, dynamic> args) async {
    final id = '${args['book_id'] ?? ''}'.trim();
    final sep = id.indexOf(':');
    if (sep < 0) throw ArgumentError('book_id looks like "ol:OL66554W", "gutenberg:1342", "se:/ebooks/…" or "google:…".');
    final kind = id.substring(0, sep), key = id.substring(sep + 1);
    switch (kind) {
      case 'gutenberg':
        final b = await _json(Uri.https('gutendex.com', '/books/$key')) as Map;
        final formats = (b['formats'] as Map? ?? const {}).cast<String, dynamic>();
        final cover = formats['image/jpeg'] as String?;
        return ToolOutput({
          'book_id': id,
          'title': b['title'],
          'authors': [
            for (final a in (b['authors'] as List? ?? const []).cast<Map>())
              '${a['name']}${a['birth_year'] != null ? ' (${a['birth_year']}–${a['death_year'] ?? ''})' : ''}',
          ],
          'summary': ?_cut((b['summaries'] as List?)?.firstOrNull, 1500),
          'subjects': b['subjects'],
          'bookshelves': b['bookshelves'],
          'languages': b['languages'],
          'downloads_last_month': b['download_count'],
          'formats': [
            if (formats.keys.any((k) => k.contains('epub'))) 'epub',
            if (formats.keys.any((k) => k.contains('mobipocket'))) 'kindle',
            if (formats.keys.any((k) => k.startsWith('text/plain'))) 'txt',
          ],
          'read_online': formats['text/html'],
          'cover': ?cover,
          'image_path': ?await _picture(cover, 'cover_gutenberg_$key.jpg'),
        });
      case 'ol':
        final w = await _json(Uri.https('openlibrary.org', '/works/$key.json')) as Map;
        Map? ratings;
        try {
          ratings = await _json(Uri.https('openlibrary.org', '/works/$key/ratings.json')) as Map;
        } catch (_) {}
        final authors = <String>[];
        for (final a in (w['authors'] as List? ?? const []).take(4)) {
          final ak = ((a as Map)['author'] as Map?)?['key'];
          if (ak == null) continue;
          try {
            authors.add('${((await _json(Uri.https('openlibrary.org', '$ak.json'))) as Map)['name']}');
          } catch (_) {}
        }
        final editions = await _json(Uri.https('openlibrary.org', '/works/$key/editions.json', {'limit': '8'})) as Map;
        final desc = w['description'] is Map ? (w['description'] as Map)['value'] : w['description'];
        final coverId = (w['covers'] as List?)?.firstOrNull;
        return ToolOutput({
          'book_id': id,
          'title': w['title'],
          'authors': authors,
          'description': ?_cut(desc, 2000),
          'first_published': ?w['first_publish_date'],
          'subjects': (w['subjects'] as List? ?? const []).take(15).toList(),
          if (ratings?['summary'] is Map && (ratings!['summary'] as Map)['average'] != null)
            'rating': '${((ratings['summary'] as Map)['average'] as num).toStringAsFixed(1)}/5 (${(ratings['summary'] as Map)['count']})',
          'editions_total': editions['size'],
          'editions': [
            for (final e in (editions['entries'] as List? ?? const []).cast<Map>())
              {
                'title': e['title'],
                'publishers': ?e['publishers'],
                'published': ?e['publish_date'],
                if ((e['isbn_13'] as List?)?.isNotEmpty == true) 'isbn': (e['isbn_13'] as List).first,
                'pages': ?e['number_of_pages'],
                if ((e['ocaid'] ?? '').toString().isNotEmpty) 'archive_id': e['ocaid'],
              },
          ],
          'link': 'https://openlibrary.org/works/$key',
          if (coverId != null) 'cover': 'https://covers.openlibrary.org/b/id/$coverId-L.jpg',
          'note': 'For a free copy (only if it is public domain) use find_free_copy.',
          'image_path': ?await _picture(coverId == null ? null : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg', 'cover_ol_$key.jpg'),
        });
      case 'se':
        final r = await _web.request('GET', Uri.https('standardebooks.org', key));
        if (r.statusCode >= 400) throw ArgumentError('Standard Ebooks has no $key.');
        final doc = html_parser.parse(WebFetcher.decodeBody(r));
        final downloads = [for (final a in doc.querySelectorAll('a[href*="/downloads/"]')) a.attributes['href'] ?? ''];
        final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'];
        return ToolOutput({
          'book_id': id,
          'title': doc.querySelector('[property="schema:name"]')?.text.trim() ?? doc.querySelector('h1')?.text.trim(),
          'authors': [for (final a in doc.querySelectorAll('[property="schema:author"] [property="schema:name"]')) a.text.trim()].toSet().toList(),
          'description': ?_cut(doc.querySelector('meta[name="description"]')?.attributes['content'], 1500),
          'subjects': [for (final s in doc.querySelectorAll('ul.tags a')) s.text.trim()],
          'formats': [
            if (downloads.any((d) => d.endsWith('.epub') && !d.contains('kepub') && !d.contains('_advanced'))) 'epub',
            if (downloads.any((d) => d.endsWith('.azw3'))) 'kindle',
          ],
          'link': 'https://standardebooks.org$key',
          'cover': ?cover,
          'image_path': ?await _picture(cover, 'cover_se_${key.split('/').last}.jpg'),
        });
      case 'google':
        final b = await _json(Uri.https('www.googleapis.com', '/books/v1/volumes/$key')) as Map;
        final v = b['volumeInfo'] as Map? ?? const {};
        final a = b['accessInfo'] as Map? ?? const {};
        final images = v['imageLinks'] as Map?;
        return ToolOutput({
          'book_id': id,
          'title': v['title'],
          'subtitle': ?v['subtitle'],
          'authors': ?v['authors'],
          'publisher': ?v['publisher'],
          'published': ?v['publishedDate'],
          'description': ?_cut('${v['description'] ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), ' '), 2000),
          'pages': ?v['pageCount'],
          'categories': ?v['categories'],
          if (v['averageRating'] != null) 'rating': '${v['averageRating']}/5 (${v['ratingsCount']})',
          'isbns': [for (final i in (v['industryIdentifiers'] as List? ?? const [])) (i as Map)['identifier']],
          'free_ebook': (a['epub'] as Map?)?['downloadLink'] != null || (a['pdf'] as Map?)?['downloadLink'] != null,
          'preview': v['previewLink'],
          if ((images?['thumbnail'] ?? images?['smallThumbnail']) case final t?) 'cover': '$t'.replaceFirst('http://', 'https://'),
          'image_path': ?await _picture(
            '${images?['thumbnail'] ?? images?['smallThumbnail'] ?? ''}'.replaceFirst('http://', 'https://'),
            'cover_google_$key.jpg',
          ),
        });
      default:
        throw ArgumentError('Unknown book source "$kind".');
    }
  }

  Future<ToolOutput> _freeCopy(Map<String, dynamic> args) async {
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) throw ArgumentError('title is required');
    final author = '${args['author'] ?? ''}'.trim();
    final words = '$title $author'.trim();
    bool same(Object? t) => '$t'.toLowerCase().contains(title.toLowerCase().split(':').first.trim());
    final copies = <Map<String, dynamic>>[];
    final elsewhere = <String>[];
    await Future.wait([
      () async {
        for (final b in await _gutenberg(words, limit: 5)) {
          if (same(b['title'])) copies.add({...b, 'source': 'Project Gutenberg', 'formats': 'epub, kindle, txt'});
        }
      }().catchError((Object _) {}),
      () async {
        for (final b in await _standardEbooks(words, limit: 5)) {
          if (same(b['title'])) copies.add({...b, 'source': 'Standard Ebooks', 'formats': 'epub, kindle'});
        }
      }().catchError((Object _) {}),
      () async {
        for (final b in await _openLibrary(title, author: author.isEmpty ? null : author, limit: 5)) {
          if (!same(b['title'])) continue;
          if (b['free_copy_id'] != null) {
            copies.add({
              'book_id': b['free_copy_id'],
              'title': b['title'],
              'authors': b['authors'],
              'cover': 'https://archive.org/services/img/${'${b['free_copy_id']}'.substring(3)}',
              'source': 'Internet Archive (public domain scan)',
              'formats': 'pdf, epub, txt',
            });
          } else if ('${b['free']}'.contains('borrowed')) {
            elsewhere.add('Borrow it free at https://openlibrary.org/works/${'${b['book_id']}'.substring(3)} (with an Open Library account)');
          }
        }
      }().catchError((Object _) {}),
    ]);
    return ToolOutput({
      'title': title,
      'free_copies': copies,
      if (copies.isEmpty) 'note': 'No legal free copy: it is most likely still under copyright. Libraries, shops and the options below are the way to read it.',
      if (elsewhere.isNotEmpty) 'borrow': elsewhere.toSet().toList(),
      if (copies.isEmpty) 'buy_or_library': 'Search it at a library (e.g. Libby/OverDrive) or a bookshop.',
    });
  }

  Future<ToolOutput> _downloadBook(Map<String, dynamic> args) async {
    final id = '${args['book_id'] ?? ''}'.trim();
    final fmt = '${args['format'] ?? 'epub'}';
    final sep = id.indexOf(':');
    if (sep < 0) throw ArgumentError('book_id is required (from search_books or find_free_copy).');
    final kind = id.substring(0, sep), key = id.substring(sep + 1);
    late Uri url;
    String name;
    switch (kind) {
      case 'gutenberg':
        final b = await _json(Uri.https('gutendex.com', '/books/$key')) as Map;
        if (b['copyright'] == true) throw ArgumentError('This Gutenberg book is still under copyright in some places; it isn\'t downloaded here.');
        final formats = (b['formats'] as Map? ?? const {}).cast<String, dynamic>();
        final pick = switch (fmt) {
          'kindle' => formats.entries.where((e) => e.key.contains('mobipocket')).firstOrNull,
          'txt' => formats.entries.where((e) => e.key.startsWith('text/plain')).firstOrNull,
          _ => formats.entries.where((e) => e.key.contains('epub')).firstOrNull,
        };
        if (pick == null) throw ArgumentError('Gutenberg doesn\'t have $fmt for this book. Formats: ${formats.keys.join(', ')}');
        url = Uri.parse('${pick.value}');
        name = '${b['title']}'.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
        name = '$name.${fmt == 'kindle' ? 'mobi' : (fmt == 'txt' ? 'txt' : 'epub')}';
      case 'se':
        final r = await _web.request('GET', Uri.https('standardebooks.org', key));
        final links = [for (final a in html_parser.parse(WebFetcher.decodeBody(r)).querySelectorAll('a[href*="/downloads/"]')) a.attributes['href'] ?? ''];
        final pick = switch (fmt) {
          'kindle' => links.where((l) => l.endsWith('.azw3')).firstOrNull,
          _ => links.where((l) => l.endsWith('.epub') && !l.contains('kepub') && !l.contains('_advanced')).firstOrNull,
        };
        if (pick == null) throw ArgumentError('Standard Ebooks offers epub and kindle for this book.');
        // The download page counts the download and asks for ?source.
        url = Uri.parse('https://standardebooks.org$pick?source=download');
        name = pick.split('/').last;
      case 'ia':
        final meta = await _json(Uri.https('archive.org', '/metadata/$key')) as Map;
        final m = meta['metadata'] as Map? ?? const {};
        // Only what the Internet Archive itself makes freely downloadable.
        if (m['access-restricted-item'] == 'true' || m['access-restricted-item'] == true) {
          throw ArgumentError('That Internet Archive item can only be borrowed, not downloaded: it isn\'t public domain.');
        }
        final files = (meta['files'] as List? ?? const []).cast<Map>().where((f) => f['private'] != 'true').toList();
        final ext = switch (fmt) {
          'txt' => '_djvu.txt',
          'epub' => '.epub',
          _ => '.pdf',
        };
        final f = files.where((f) => '${f['name']}'.endsWith(ext)).firstOrNull ?? files.where((f) => '${f['name']}'.endsWith('.pdf')).firstOrNull;
        if (f == null) throw ArgumentError('No downloadable $fmt for that item.');
        url = Uri.parse('https://archive.org/download/$key/${Uri.encodeComponent('${f['name']}')}');
        name = '${f['name']}';
      case 'google':
        final b = await _json(Uri.https('www.googleapis.com', '/books/v1/volumes/$key')) as Map;
        final a = b['accessInfo'] as Map? ?? const {};
        final link = ((fmt == 'pdf' ? a['pdf'] : a['epub']) as Map?)?['downloadLink'] ?? ((a['epub'] ?? a['pdf']) as Map?)?['downloadLink'];
        if (link == null) throw ArgumentError('Google has no free download of this book.');
        url = Uri.parse('$link');
        name = '${(b['volumeInfo'] as Map?)?['title'] ?? key}.${fmt == 'pdf' ? 'pdf' : 'epub'}';
      default:
        throw ArgumentError('Books from Open Library listings are downloaded by their free_copy_id (find_free_copy).');
    }
    final file = await _web.download(url, name: name);
    final size = await file.length();
    if (size < 2048) throw ArgumentError('The download came back almost empty; the source may be busy. Try again later.');
    return ToolOutput({
      'created': true,
      'file_path': file.path,
      'name': file.path.split(RegExp(r'[\\/]')).last,
      'size_kb': (size / 1024).ceil(),
      'note': 'A free, legal copy, saved on the phone. Send it with send_message.',
    });
  }

  // ---- YouTube -----------------------------------------------------------------

  static const _ytHeaders = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'accept-language': 'en-US,en;q=0.9',
    // Skips the cookie-consent page some regions get.
    'cookie': 'CONSENT=YES+1; SOCS=CAI',
  };

  static String _videoId(String s) {
    final t = s.trim();
    if (RegExp(r'^[\w-]{11}$').hasMatch(t)) return t;
    final m = RegExp(r'(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([\w-]{11})').firstMatch(t);
    if (m == null) throw ArgumentError('That isn\'t a YouTube video link or id.');
    return m[1]!;
  }

  Future<String> _ytPage(Uri url) async {
    final r = await _web.request('GET', url, headers: _ytHeaders);
    if (r.statusCode >= 400) throw ArgumentError('YouTube said ${r.statusCode}.');
    return WebFetcher.decodeBody(r);
  }

  static Map<String, dynamic>? _ytJson(String page, String name) {
    final m = RegExp('(?:var |window\\["?)$name"?\\]?\\s*=\\s*(\\{.+?\\});\\s*(?:var |</script>|window)', dotAll: true).firstMatch(page);
    if (m == null) return null;
    try {
      return jsonDecode(m[1]!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Every object under [key] anywhere in [node].
  static void _collect(Object? node, String key, List<Map> out) {
    if (node is Map) {
      if (node[key] is Map) out.add(node[key] as Map);
      for (final v in node.values) {
        _collect(v, key, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collect(v, key, out);
      }
    }
  }

  static String _runs(Object? t) => t is Map ? (t['simpleText'] ?? [for (final r in (t['runs'] as List? ?? const [])) (r as Map)['text']].join()).toString() : '';

  Future<ToolOutput> _ytSearch(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) throw ArgumentError('query is required');
    final page = await _ytPage(Uri.https('www.youtube.com', '/results', {'search_query': q, 'hl': 'en'}));
    final data = _ytJson(page, 'ytInitialData');
    if (data == null) throw ArgumentError('YouTube changed its page; search didn\'t work.');
    final videos = <Map>[];
    _collect(data, 'videoRenderer', videos);
    return ToolOutput({
      'query': q,
      'results': [
        for (final v in videos.take(TelegramToolRunner._int(args, 'limit', fallback: 10, max: 20)))
          {
            'title': _runs(v['title']),
            'channel': _runs(v['ownerText']),
            'length': ?(v['lengthText'] as Map?)?['simpleText'],
            'views': _runs(v['viewCountText']),
            'published': _runs(v['publishedTimeText']),
            'url': 'https://youtu.be/${v['videoId']}',
            'video_id': v['videoId'],
            'thumbnail': 'https://i.ytimg.com/vi/${v['videoId']}/hqdefault.jpg',
          },
      ],
    });
  }

  Future<ToolOutput> _ytVideo(Map<String, dynamic> args) async {
    final id = _videoId('${args['video'] ?? ''}');
    final page = await _ytPage(Uri.https('www.youtube.com', '/watch', {'v': id, 'hl': 'en'}));
    final player = _ytJson(page, 'ytInitialPlayerResponse');
    final d = player?['videoDetails'] as Map?;
    if (d == null) throw ArgumentError('YouTube didn\'t share this video (private, removed, or age-restricted).');
    final mf = (player?['microformat'] as Map?)?['playerMicroformatRenderer'] as Map? ?? const {};
    final description = '${d['shortDescription'] ?? ''}';
    final chapters = [
      for (final m in RegExp(r'^\s*((?:\d+:)?\d{1,2}:\d{2})\s+[-–:]?\s*(.+)$', multiLine: true).allMatches(description)) '${m[1]} ${m[2]!.trim()}',
    ];
    final captions = ((player?['captions'] as Map?)?['playerCaptionsTracklistRenderer'] as Map?)?['captionTracks'] as List? ?? const [];
    final thumbs = (d['thumbnail'] as Map?)?['thumbnails'] as List? ?? const [];
    final likes = RegExp(r'"likeCount":"?(\d+)').firstMatch(page)?[1] ??
        RegExp(r'"accessibilityText":"([\d,.]+[KMB]?) likes?').firstMatch(page)?[1];
    return ToolOutput({
      'title': d['title'],
      'channel': d['author'],
      'channel_id': d['channelId'],
      'published': ?mf['publishDate'],
      'length': formatDuration(int.tryParse('${d['lengthSeconds']}') ?? 0),
      'views': NumberFormat.decimalPattern().format(int.tryParse('${d['viewCount']}') ?? 0),
      'likes': ?likes,
      'category': ?mf['category'],
      if (d['isLiveContent'] == true) 'live': true,
      if ((d['keywords'] as List?)?.isNotEmpty == true) 'tags': (d['keywords'] as List).take(20).toList(),
      'description': _cut(description, 5000),
      if (chapters.length >= 2) 'chapters': chapters,
      'captions': [
        for (final c in captions.cast<Map>()) '${_runs(c['name'])} (${c['languageCode']}${c['kind'] == 'asr' ? ', auto' : ''})',
      ],
      'url': 'https://youtu.be/$id',
      'video_id': id,
      'thumbnail': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      'image_path': ?await _picture(thumbs.isEmpty ? null : '${(thumbs.last as Map)['url']}'.split('?').first, 'youtube_$id.jpg'),
    });
  }

  Future<ToolOutput> _ytTranscript(Map<String, dynamic> args) async {
    final id = _videoId('${args['video'] ?? ''}');
    final want = '${args['language'] ?? ''}'.trim().toLowerCase();
    final page = await _ytPage(Uri.https('www.youtube.com', '/watch', {'v': id, 'hl': 'en'}));
    final player = _ytJson(page, 'ytInitialPlayerResponse');
    final tracks = (((player?['captions'] as Map?)?['playerCaptionsTracklistRenderer'] as Map?)?['captionTracks'] as List? ?? const []).cast<Map>();
    if (tracks.isEmpty) return const ToolOutput({'error': 'This video has no captions.'});
    final track = tracks.where((t) => want.isNotEmpty && '${t['languageCode']}'.toLowerCase().startsWith(want)).firstOrNull ??
        tracks.where((t) => t['kind'] != 'asr').firstOrNull ??
        tracks.first;
    final r = await _web.request('GET', Uri.parse('${track['baseUrl']}&fmt=json3'), headers: _ytHeaders);
    final body = WebFetcher.decodeBody(r).trim();
    if (r.statusCode >= 400 || body.isEmpty) {
      return ToolOutput({
        'error': 'YouTube refused the captions to this app (it now asks apps for a signed-in browser token).',
        'available': [for (final t in tracks) '${t['languageCode']}${t['kind'] == 'asr' ? ' (auto)' : ''}'],
        'note': 'Use youtube_video for the description and chapters instead, or open the video with browser_open and read its transcript panel.',
      });
    }
    final events = ((jsonDecode(body) as Map)['events'] as List? ?? const []).cast<Map>();
    final lines = <String>[];
    for (final e in events) {
      final text = [for (final s in (e['segs'] as List? ?? const [])) (s as Map)['utf8'] ?? ''].join().replaceAll('\n', ' ').trim();
      if (text.isEmpty) continue;
      lines.add('[${formatDuration(((e['tStartMs'] as num? ?? 0) / 1000).floor())}] $text');
    }
    final text = lines.join('\n');
    final details = player?['videoDetails'] as Map?;
    return ToolOutput({
      'video_id': id,
      'title': ?details?['title'],
      'channel': ?details?['author'],
      if (int.tryParse('${details?['lengthSeconds'] ?? ''}') case final secs?) 'seconds': secs,
      'language': track['languageCode'],
      if (track['kind'] == 'asr') 'auto_generated': true,
      'lines': lines.length,
      'transcript': TelegramToolRunner._clip(text, 30000),
    });
  }

  Future<ToolOutput> _ytChannel(Map<String, dynamic> args) async {
    var c = '${args['channel'] ?? ''}'.trim();
    if (c.isEmpty) throw ArgumentError('channel is required');
    final Uri url;
    if (RegExp(r'^UC[\w-]{22}$').hasMatch(c)) {
      url = Uri.parse('https://www.youtube.com/channel/$c');
    } else if (c.contains('youtube.com/')) {
      url = WebFetcher.normalize(c);
    } else {
      c = c.startsWith('@') ? c : '@$c';
      url = Uri.parse('https://www.youtube.com/$c');
    }
    final page = await _ytPage(url);
    final channelId = RegExp(r'"(?:externalId|channelId)":"(UC[\w-]{22})"').firstMatch(page)?[1];
    if (channelId == null) throw ArgumentError('No YouTube channel there.');
    final data = _ytJson(page, 'ytInitialData');
    final meta = ((data?['metadata'] as Map?)?['channelMetadataRenderer'] as Map?) ?? const {};
    final headerText = jsonEncode(data?['header'] ?? const {});
    final subs = RegExp(r'"([\d.,]+[KMB]? subscribers)"').firstMatch(headerText)?[1] ?? RegExp(r'"([\d.,]+[KMB]? subscribers)"').firstMatch(page)?[1];
    final count = RegExp(r'"([\d,.]+[KMB]? videos)"').firstMatch(headerText)?[1];
    final feed = await _web.request('GET', Uri.https('www.youtube.com', '/feeds/videos.xml', {'channel_id': channelId}));
    final videos = _feedEntries(WebFetcher.decodeBody(feed));
    return ToolOutput({
      'channel': meta['title'] ?? videos.firstOrNull?['channel'],
      'channel_id': channelId,
      'url': 'https://www.youtube.com/channel/$channelId',
      if (((meta['avatar'] as Map?)?['thumbnails'] as List?)?.firstOrNull case final Map a) 'avatar': a['url'],
      'description': ?_cut(meta['description'], 1500),
      'subscribers': ?subs,
      'videos': ?count,
      'latest': videos,
    });
  }

  /// The entries of a YouTube RSS feed (latest 15).
  List<Map<String, dynamic>> _feedEntries(String xml) {
    final doc = html_parser.parse(xml);
    return [
      for (final e in doc.querySelectorAll('entry'))
        {
          'title': e.querySelector('title')?.text.trim(),
          'channel': e.querySelector('author name')?.text.trim(),
          'published': (e.querySelector('published')?.text ?? '').split('T').first,
          if (e.querySelector('media\\:statistics')?.attributes['views'] case final v?) 'views': v,
          'url': 'https://youtu.be/${e.querySelector('yt\\:videoId')?.text.trim() ?? ''}',
          'video_id': e.querySelector('yt\\:videoId')?.text.trim(),
        },
    ];
  }

  Future<ToolOutput> _ytPlaylist(Map<String, dynamic> args) async {
    final s = '${args['playlist'] ?? ''}'.trim();
    final id = RegExp(r'list=([\w-]+)').firstMatch(s)?[1] ?? (RegExp(r'^[\w-]{12,}$').hasMatch(s) ? s : null);
    if (id == null) throw ArgumentError('That isn\'t a YouTube playlist link or id.');
    final feed = await _web.request('GET', Uri.https('www.youtube.com', '/feeds/videos.xml', {'playlist_id': id}));
    if (feed.statusCode >= 400) throw ArgumentError('YouTube has no public playlist $id.');
    final xml = WebFetcher.decodeBody(feed);
    final doc = html_parser.parse(xml);
    final videos = _feedEntries(xml);
    return ToolOutput({
      'playlist': doc.querySelector('feed > title')?.text.trim(),
      'by': doc.querySelector('feed > author name')?.text.trim(),
      'url': 'https://www.youtube.com/playlist?list=$id',
      'videos': videos,
      if (videos.length >= 15) 'note': 'YouTube\'s feed lists the latest 15; open the playlist link with browser_open for all.',
    });
  }

  // ---- X -----------------------------------------------------------------------

  Future<ToolOutput> _xPost(Map<String, dynamic> args) async {
    final s = '${args['post'] ?? ''}'.trim();
    final id = RegExp(r'status(?:es)?/(\d+)').firstMatch(s)?[1] ?? (RegExp(r'^\d{5,}$').hasMatch(s) ? s : null);
    if (id == null) throw ArgumentError('That isn\'t an X post link or id.');
    Map? t;
    try {
      t = ((await _json(Uri.https('api.fxtwitter.com', '/status/$id'))) as Map)['tweet'] as Map?;
    } catch (_) {}
    if (t != null) {
      final media = (t['media'] as Map?)?['all'] as List? ?? const [];
      final firstPhoto = media.cast<Map>().where((m) => m['type'] == 'photo').firstOrNull;
      final author = t['author'] as Map? ?? const {};
      Map<String, dynamic>? quoted;
      if (t['quote'] case final Map q) {
        quoted = {'author': '@${(q['author'] as Map?)?['screen_name']}', 'text': q['text'], 'url': q['url']};
      }
      return ToolOutput({
        'author': '${author['name']} (@${author['screen_name']})',
        'name': author['name'],
        'handle': author['screen_name'],
        'avatar': ?author['avatar_url'],
        'photos': [for (final m in media.cast<Map>()) if (m['type'] == 'photo') m['url']],
        if (media.cast<Map>().where((m) => m['type'] != 'photo').firstOrNull case final Map v) 'video_thumbnail': v['thumbnail_url'],
        'text': t['text'],
        'date': t['created_at'],
        'likes': t['likes'],
        'reposts': t['retweets'],
        'replies': t['replies'],
        'views': ?t['views'],
        if (t['replying_to'] != null) 'replying_to': '@${t['replying_to']}',
        if (media.isNotEmpty) 'media': [for (final m in media.cast<Map>()) {'type': m['type'], 'url': m['url']}],
        'quotes': ?quoted,
        'url': t['url'],
        'image_path': ?await _picture(firstPhoto?['url'] as String?, 'x_$id.jpg'),
      });
    }
    // X's own embed service, as a fallback.
    final token = ((int.parse(id) / 1e15) * math.pi).toStringAsFixed(10).replaceAll(RegExp(r'(0+|\.)'), '');
    final j = await _json(Uri.https('cdn.syndication.twimg.com', '/tweet-result', {'id': id, 'token': token})) as Map;
    final user = j['user'] as Map? ?? const {};
    return ToolOutput({
      'author': '${user['name']} (@${user['screen_name']})',
      'text': j['text'],
      'date': j['created_at'],
      'likes': j['favorite_count'],
      'replies': ?j['conversation_count'],
      'url': 'https://x.com/${user['screen_name']}/status/$id',
      'image_path': ?await _picture(((j['photos'] as List?)?.firstOrNull as Map?)?['url'] as String?, 'x_$id.jpg'),
    });
  }

  Future<ToolOutput> _xProfile(Map<String, dynamic> args) async {
    final s = '${args['username'] ?? ''}'.trim();
    final name = RegExp(r'(?:x|twitter)\.com/@?([A-Za-z0-9_]{1,15})').firstMatch(s)?[1] ?? s.replaceFirst('@', '');
    if (!RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(name)) throw ArgumentError('That isn\'t an X username.');
    final j = await _json(Uri.https('api.fxtwitter.com', '/$name')) as Map;
    final u = j['user'] as Map?;
    if (u == null) return ToolOutput({'error': 'X didn\'t return @$name (missing, suspended, or the lookup service is busy).'});
    return ToolOutput({
      'name': u['name'],
      'username': '@${u['screen_name']}',
      'bio': ?_cut(u['description'], 600),
      'followers': u['followers'],
      'following': u['following'],
      'posts': u['tweets'],
      'likes': ?u['likes'],
      'media': ?u['media_count'],
      'joined': ?u['joined'],
      'location': ?((u['location'] as String?)?.isEmpty ?? true ? null : u['location']),
      'website': ?((u['website'] as Map?)?['url']),
      if (u['verification'] is Map && (u['verification'] as Map)['verified'] == true) 'verified': true,
      'url': 'https://x.com/${u['screen_name']}',
      'avatar': ?u['avatar_url'],
      'banner': ?u['banner_url'],
      'note': 'Recent posts need the user signed in to x.com in the app\'s browser; then browser_open x.com/${u['screen_name']}.',
      'image_path': ?await _picture('${u['avatar_url'] ?? ''}'.replaceFirst('_normal', '_400x400'), 'x_${u['screen_name']}.jpg'),
    });
  }
}
