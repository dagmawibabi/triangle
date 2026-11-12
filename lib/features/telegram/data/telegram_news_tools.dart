part of 'telegram_tools.dart';

// Reddit and Hacker News, from their free public APIs: Reddit's JSON
// listings (no account; NSFW posts are left out unless asked for) and
// Hacker News through its Firebase API and Algolia's search. None needs a
// key.

final _newsTools = <TelegramTool>[
  TelegramTool(
    name: 'reddit_posts',
    label: 'Reading Reddit',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description:
        'Posts from a subreddit, or Reddit\'s front page (r/popular): title, author, score, comment count, flair, '
        'link, picture and the start of the text. sort: hot (default), new, top, rising; time for top: hour, day, '
        'week, month, year, all. The user sees cards; reddit_post opens one with its comments.',
    parameters: _obj({
      'subreddit': {'type': 'string', 'description': 'A subreddit name without r/, like "flutterdev"; leave out for r/popular.'},
      'sort': {'type': 'string', 'enum': ['hot', 'new', 'top', 'rising'], 'description': 'Order of the posts; default hot.'},
      'time': {'type': 'string', 'enum': ['hour', 'day', 'week', 'month', 'year', 'all'], 'description': 'For top: the time window; default day.'},
      'limit': {'type': 'integer', 'description': 'How many posts, 1-25; default 10.'},
      'include_nsfw': {'type': 'boolean', 'description': 'Keep posts marked NSFW; default false.'},
    }),
  ),
  TelegramTool(
    name: 'reddit_search',
    label: 'Searching Reddit',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'Searches Reddit posts, everywhere or in one subreddit. sort: relevance (default), hot, top, new, comments.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to search for.'},
      'subreddit': {'type': 'string', 'description': 'Only this subreddit (name without r/).'},
      'sort': {'type': 'string', 'enum': ['relevance', 'hot', 'top', 'new', 'comments'], 'description': 'Order of results; default relevance.'},
      'time': {'type': 'string', 'enum': ['hour', 'day', 'week', 'month', 'year', 'all'], 'description': 'Time window; default all.'},
      'limit': {'type': 'integer', 'description': 'How many posts, 1-25; default 10.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'reddit_post',
    label: 'Opening a Reddit post',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'One Reddit post with its full text and top comments (with replies), by link or post id.',
    parameters: _obj({
      'post': {'type': 'string', 'description': 'A reddit.com link to the post, or its id like "1abcde".'},
      'comments': {'type': 'integer', 'description': 'Top-level comments to include, 1-30; default 12.'},
      'sort': {'type': 'string', 'enum': ['top', 'best', 'new', 'controversial'], 'description': 'Comment order; default top.'},
    }, ['post']),
  ),
  TelegramTool(
    name: 'reddit_subreddit',
    label: 'Looking up a subreddit',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'About a subreddit: title, description, members, online now, created, icon and banner.',
    parameters: _obj({
      'subreddit': {'type': 'string', 'description': 'The name without r/, like "worldnews".'},
    }, ['subreddit']),
  ),
  TelegramTool(
    name: 'hn_stories',
    label: 'Reading Hacker News',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description:
        'Hacker News stories: top (default), new, best, ask (Ask HN), show (Show HN) or job. Each with title, link, '
        'site, points, author, comment count and age. The user sees cards; hn_item opens one with its comments.',
    parameters: _obj({
      'list': {'type': 'string', 'enum': ['top', 'new', 'best', 'ask', 'show', 'job'], 'description': 'Which list; default top.'},
      'limit': {'type': 'integer', 'description': 'How many stories, 1-30; default 15.'},
    }),
  ),
  TelegramTool(
    name: 'hn_search',
    label: 'Searching Hacker News',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'Searches Hacker News stories or comments (Algolia). sort: relevance (default) or date.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to search for.'},
      'kind': {'type': 'string', 'enum': ['story', 'comment', 'ask_hn', 'show_hn'], 'description': 'What to search; default story.'},
      'sort': {'type': 'string', 'enum': ['relevance', 'date'], 'description': 'Order; default relevance.'},
      'since_days': {'type': 'integer', 'description': 'Only from the last this many days.'},
      'limit': {'type': 'integer', 'description': 'How many results, 1-30; default 15.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'hn_item',
    label: 'Opening a Hacker News thread',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'One Hacker News story (or comment) with its text and comment tree, by id or news.ycombinator.com link.',
    parameters: _obj({
      'item': {'type': 'string', 'description': 'The item id like "41234567", or its news.ycombinator.com link.'},
      'comments': {'type': 'integer', 'description': 'Top-level comments to include, 1-30; default 12.'},
    }, ['item']),
  ),
  TelegramTool(
    name: 'hn_user',
    label: 'Looking up a Hacker News user',
    category: ToolCategory.news,
    cost: ToolCost.web,
    description: 'A Hacker News user: karma, when they joined, about text, and their latest submissions.',
    parameters: _obj({
      'username': {'type': 'string', 'description': 'Their username, like "dang".'},
    }, ['username']),
  ),
];

const _newsPolicies = <String, ToolPolicy>{
  'reddit_posts': ToolPolicy(ToolAccess.read),
  'reddit_search': ToolPolicy(ToolAccess.read),
  'reddit_post': ToolPolicy(ToolAccess.read),
  'reddit_subreddit': ToolPolicy(ToolAccess.read),
  'hn_stories': ToolPolicy(ToolAccess.read),
  'hn_search': ToolPolicy(ToolAccess.read),
  'hn_item': ToolPolicy(ToolAccess.read),
  'hn_user': ToolPolicy(ToolAccess.read),
};

const _newsReferences = <String, ToolReference>{
  'reddit_posts': ToolReference(['subreddit', 'sort', 'posts', 'hidden_nsfw', 'source'], limits: ['limit: 1-25.']),
  'reddit_search': ToolReference(['query', 'subreddit', 'posts', 'source'], limits: ['limit: 1-25.']),
  'reddit_post': ToolReference(['post', 'comments', 'source'], limits: ['comments: 1-30 top-level, two levels of replies.']),
  'reddit_subreddit': ToolReference(['name', 'title', 'description', 'members', 'online', 'created', 'icon', 'banner', 'nsfw', 'url']),
  'hn_stories': ToolReference(['list', 'stories', 'source'], limits: ['limit: 1-30.']),
  'hn_search': ToolReference(['query', 'kind', 'hits', 'total', 'source'], limits: ['limit: 1-30.']),
  'hn_item': ToolReference(['item', 'comments', 'source'], limits: ['comments: 1-30 top-level, two levels of replies.']),
  'hn_user': ToolReference(['username', 'karma', 'created', 'about', 'submissions', 'url']),
};

extension _NewsTools on TelegramToolRunner {
  Future<ToolOutput>? _runNews(String name, Map<String, dynamic> args) => switch (name) {
    'reddit_posts' => _redditPosts(args),
    'reddit_search' => _redditSearch(args),
    'reddit_post' => _redditPost(args),
    'reddit_subreddit' => _redditSubreddit(args),
    'hn_stories' => _hnStories(args),
    'hn_search' => _hnSearch(args),
    'hn_item' => _hnItem(args),
    'hn_user' => _hnUser(args),
    _ => null,
  };

  static int _limit(Object? v, int def, int max) => ((v as num?)?.toInt() ?? def).clamp(1, max);

  static String? _iso(Object? seconds) =>
      seconds is num ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).toInt()).toIso8601String().substring(0, 16) : null;

  static String _plain(Object? html) {
    final s = '${html ?? ''}';
    if (s.isEmpty) return '';
    final text = html_parser.parse(s.replaceAll('<p>', '\n\n')).documentElement?.text ?? s;
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  // ---- Reddit --------------------------------------------------------------------

  static const _redditAgent = 'android:app.triangle:1.0 (personal assistant)';

  /// App-only tokens for Reddit's official API, by client id.
  static final Map<String, (String, DateTime)> _redditTokens = {};
  static final String _deviceId = () {
    final r = math.Random.secure();
    return List.generate(24, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
  }();

  /// An app-only token for the user's Reddit client id (an "installed app"
  /// made at reddit.com/prefs/apps), valid about an hour.
  Future<String> _redditToken(String clientId) async {
    final cached = _redditTokens[clientId];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;
    final r = await _web.request(
      'POST',
      Uri.https('www.reddit.com', '/api/v1/access_token'),
      headers: {
        'authorization': 'Basic ${base64Encode(utf8.encode('$clientId:'))}',
        'content-type': 'application/x-www-form-urlencoded',
        'user-agent': _redditAgent,
      },
      body: 'grant_type=${Uri.encodeQueryComponent('https://oauth.reddit.com/grants/installed_client')}&device_id=$_deviceId',
    );
    if (r.statusCode == 401) throw ArgumentError('Reddit refused the client id. Check it under Settings → More apps → Reddit (it must be an "installed app").');
    if (r.statusCode >= 400) throw ArgumentError('Reddit sign-in failed (${r.statusCode}).');
    final j = jsonDecode(WebFetcher.decodeBody(r)) as Map;
    final token = '${j['access_token'] ?? ''}';
    if (token.isEmpty) throw ArgumentError('Reddit gave no token: ${j['error'] ?? 'unknown error'}.');
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _redditTokens[clientId] = (token, DateTime.now().add(Duration(seconds: secs - 120)));
    return token;
  }

  /// Reddit's JSON for [path] ("/r/flutterdev/hot.json"): Reddit's public
  /// JSON pages (www.reddit.com/…/.json, no key; the way APIHub reads
  /// Reddit), and only if Reddit refuses those, its official API with the
  /// user's client id when one is set.
  Future<Object?> _reddit(String path, Map<String, String> query) async {
    final q = {...query, 'raw_json': '1'};
    try {
      return await _json(Uri.https('www.reddit.com', path, q), headers: const {'user-agent': _redditAgent});
    } on ArgumentError catch (e) {
      final refused = '${e.message}'.contains('403') || '${e.message}'.contains('429');
      if (!refused) rethrow;
      final clientId = _settings.redditClientId.trim();
      if (clientId.isNotEmpty) {
        final token = await _redditToken(clientId);
        return _json(
          Uri.https('oauth.reddit.com', path.replaceFirst(RegExp(r'\.json$'), ''), q),
          headers: {'authorization': 'bearer $token', 'user-agent': _redditAgent},
        );
      }
      throw ArgumentError(
        'Reddit refused its public JSON from this network just now (${'${e.message}'.contains('429') ? 'too many requests' : 'it limits clients that aren\'t signed in'}). '
        'Trying again later or on another network (Wi-Fi vs mobile data) often works. As a backup the user can add a free '
        'Reddit client id under Settings → More apps → Reddit, used only when the public JSON is refused.',
      );
    }
  }

  static String _sub(Object? v) => '${v ?? ''}'.trim().replaceFirst(RegExp(r'^/?r/', caseSensitive: false), '').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');

  static Map<String, dynamic> _redditPostRow(Map d, {int textMax = 500}) {
    String? image;
    final preview = ((d['preview'] as Map?)?['images'] as List?)?.firstOrNull as Map?;
    final src = (preview?['source'] as Map?)?['url'];
    if (src is String && src.startsWith('http')) image = src;
    final thumb = d['thumbnail'];
    if (image == null && thumb is String && thumb.startsWith('http')) image = thumb;
    final gallery = d['gallery_data'] is Map ? ((d['gallery_data'] as Map)['items'] as List?)?.length : null;
    return {
      'id': d['id'],
      'subreddit': d['subreddit'],
      'title': d['title'],
      'author': d['author'],
      'score': d['score'],
      'upvote_ratio': d['upvote_ratio'],
      'comments': d['num_comments'],
      'flair': '${d['link_flair_text'] ?? ''}'.trim().isEmpty ? null : d['link_flair_text'],
      'created': _iso(d['created_utc']),
      'url': d['is_self'] == true ? null : d['url'],
      'domain': d['is_self'] == true ? null : d['domain'],
      'permalink': 'https://www.reddit.com${d['permalink']}',
      if ('${d['selftext'] ?? ''}'.trim().isNotEmpty) 'text': _DiscoverTools._cut(d['selftext'], textMax),
      'image': ?image,
      if (d['is_video'] == true) 'video': true,
      'gallery_count': ?gallery,
      if (d['over_18'] == true) 'nsfw': true,
      if (d['stickied'] == true) 'pinned': true,
      if (d['spoiler'] == true) 'spoiler': true,
      'awards': d['total_awards_received'],
    };
  }

  List<Map<String, dynamic>> _listing(Object? j, {required bool nsfw, int textMax = 500}) => [
    for (final c in ((j as Map?)?['data'] as Map?)?['children'] as List? ?? const [])
      if (c is Map && c['kind'] == 't3' && c['data'] is Map && (nsfw || (c['data'] as Map)['over_18'] != true))
        _redditPostRow(c['data'] as Map, textMax: textMax),
  ];

  Future<ToolOutput> _redditPosts(Map<String, dynamic> args) async {
    final sub = _sub(args['subreddit']);
    final sort = const ['hot', 'new', 'top', 'rising'].contains(args['sort']) ? '${args['sort']}' : 'hot';
    final limit = _limit(args['limit'], 10, 25);
    final nsfw = args['include_nsfw'] == true;
    final j = await _reddit('/r/${sub.isEmpty ? 'popular' : sub}/$sort.json', {
      'limit': '${limit + 5}',
      if (sort == 'top') 't': '${args['time'] ?? 'day'}',
    });
    final all = _listing(j, nsfw: true);
    final posts = nsfw ? all : all.where((p) => p['nsfw'] != true).toList();
    return ToolOutput({
      'subreddit': sub.isEmpty ? 'popular' : sub,
      'sort': sort,
      'posts': posts.take(limit).toList(),
      if (all.length != posts.length) 'hidden_nsfw': all.length - posts.length,
      'source': 'Reddit',
    });
  }

  Future<ToolOutput> _redditSearch(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) throw ArgumentError('query is required');
    final sub = _sub(args['subreddit']);
    final limit = _limit(args['limit'], 10, 25);
    final j = await _reddit(sub.isEmpty ? '/search.json' : '/r/$sub/search.json', {
      'q': q,
      if (sub.isNotEmpty) 'restrict_sr': '1',
      'sort': const ['relevance', 'hot', 'top', 'new', 'comments'].contains(args['sort']) ? '${args['sort']}' : 'relevance',
      't': '${args['time'] ?? 'all'}',
      'limit': '$limit',
    });
    return ToolOutput({
      'query': q,
      'subreddit': sub.isEmpty ? null : sub,
      'posts': _listing(j, nsfw: false).take(limit).toList(),
      'source': 'Reddit',
    });
  }

  static List<Map<String, dynamic>> _redditComments(Object? children, {int max = 12, int depth = 0}) => [
    for (final c in (children as List? ?? const []).take(max))
      if (c is Map && c['kind'] == 't1' && c['data'] is Map)
        {
          'author': (c['data'] as Map)['author'],
          'score': (c['data'] as Map)['score'],
          'created': _iso((c['data'] as Map)['created_utc']),
          'text': _DiscoverTools._cut((c['data'] as Map)['body'], depth == 0 ? 900 : 500),
          if ((c['data'] as Map)['is_submitter'] == true) 'op': true,
          if (depth < 2 && (c['data'] as Map)['replies'] is Map)
            'replies': _redditComments((((c['data'] as Map)['replies'] as Map)['data'] as Map?)?['children'], max: depth == 0 ? 3 : 2, depth: depth + 1),
        },
  ];

  Future<ToolOutput> _redditPost(Map<String, dynamic> args) async {
    final raw = '${args['post'] ?? ''}'.trim();
    final id = RegExp(r'comments/([a-z0-9]+)', caseSensitive: false).firstMatch(raw)?[1] ??
        RegExp(r'redd\.it/([a-z0-9]+)', caseSensitive: false).firstMatch(raw)?[1] ??
        (RegExp(r'^(t3_)?[a-z0-9]{4,10}$', caseSensitive: false).hasMatch(raw) ? raw.replaceFirst('t3_', '') : null);
    if (id == null) throw ArgumentError('Give a reddit.com post link or its id.');
    final n = _limit(args['comments'], 12, 30);
    final j = await _reddit('/comments/$id.json', {
      'limit': '${n * 3}',
      'depth': '3',
      'sort': const ['top', 'best', 'new', 'controversial'].contains(args['sort']) ? '${args['sort']}' : 'top',
    });
    final parts = j as List;
    final post = _listing(parts.first, nsfw: true, textMax: 4000).firstOrNull;
    if (post == null) throw ArgumentError('No such post.');
    return ToolOutput({
      'post': post,
      'comments': _redditComments(((parts.length > 1 ? parts[1] : null) as Map?)?['data']?['children'], max: n),
      'source': 'Reddit',
    });
  }

  Future<ToolOutput> _redditSubreddit(Map<String, dynamic> args) async {
    final sub = _sub(args['subreddit']);
    if (sub.isEmpty) throw ArgumentError('subreddit is required');
    final d = ((await _reddit('/r/$sub/about.json', {})) as Map)['data'] as Map? ?? const {};
    String? pic(Object? v) => v is String && v.startsWith('http') ? v.split('?').first : null;
    return ToolOutput({
      'name': d['display_name'] ?? sub,
      'title': d['title'],
      'description': _DiscoverTools._cut(d['public_description'] ?? d['description'], 800),
      'members': d['subscribers'],
      'online': d['active_user_count'] ?? d['accounts_active'],
      'created': _iso(d['created_utc']),
      'icon': pic(d['community_icon']) ?? pic(d['icon_img']),
      'banner': pic(d['banner_background_image']) ?? pic(d['banner_img']),
      if (d['over18'] == true) 'nsfw': true,
      'url': 'https://www.reddit.com/r/${d['display_name'] ?? sub}',
    });
  }

  // ---- Hacker News -----------------------------------------------------------------

  Future<Object?> _hn(String path) => _json(Uri.https('hacker-news.firebaseio.com', '/v0$path'));

  static Map<String, dynamic> _hnStoryRow(Map d) {
    final url = d['url'] as String?;
    return {
      'id': d['id'],
      'type': d['type'],
      'title': d['title'],
      'url': url,
      'site': url == null ? null : Uri.tryParse(url)?.host.replaceFirst('www.', ''),
      'points': d['score'],
      'author': d['by'],
      'comments': d['descendants'],
      'created': _iso(d['time']),
      if (d['text'] != null) 'text': _DiscoverTools._cut(_plain(d['text']), 600),
      'hn_url': 'https://news.ycombinator.com/item?id=${d['id']}',
    };
  }

  Future<ToolOutput> _hnStories(Map<String, dynamic> args) async {
    final list = const ['top', 'new', 'best', 'ask', 'show', 'job'].contains(args['list']) ? '${args['list']}' : 'top';
    final limit = _limit(args['limit'], 15, 30);
    final ids = ((await _hn('/${list}stories.json')) as List? ?? const []).take(limit).toList();
    final items = await Future.wait([
      for (final id in ids) _hn('/item/$id.json').then<Object?>((v) => v, onError: (_) => null),
    ]);
    return ToolOutput({
      'list': list,
      'stories': [for (final (i, d) in items.indexed) if (d is Map && d['deleted'] != true) {'rank': i + 1, ..._hnStoryRow(d)}],
      'source': 'Hacker News',
    });
  }

  Future<ToolOutput> _hnSearch(Map<String, dynamic> args) async {
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) throw ArgumentError('query is required');
    final kind = const ['story', 'comment', 'ask_hn', 'show_hn'].contains(args['kind']) ? '${args['kind']}' : 'story';
    final days = (args['since_days'] as num?)?.toInt();
    final j = await _json(Uri.https('hn.algolia.com', args['sort'] == 'date' ? '/api/v1/search_by_date' : '/api/v1/search', {
      'query': q,
      'tags': kind,
      'hitsPerPage': '${_limit(args['limit'], 15, 30)}',
      if (days != null && days > 0)
        'numericFilters': 'created_at_i>${DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000}',
    })) as Map;
    return ToolOutput({
      'query': q,
      'kind': kind,
      'total': j['nbHits'],
      'hits': [
        for (final h in (j['hits'] as List? ?? const []).whereType<Map>())
          {
            'id': int.tryParse('${h['objectID']}') ?? h['objectID'],
            'title': h['title'] ?? h['story_title'],
            'url': h['url'] ?? h['story_url'],
            'site': Uri.tryParse('${h['url'] ?? h['story_url'] ?? ''}')?.host.replaceFirst('www.', ''),
            'points': h['points'],
            'author': h['author'],
            'comments': h['num_comments'],
            'created': '${h['created_at'] ?? ''}'.length >= 16 ? '${h['created_at']}'.substring(0, 16) : h['created_at'],
            if (h['comment_text'] != null) 'text': _DiscoverTools._cut(_plain(h['comment_text']), 500),
            if (h['story_id'] != null && kind == 'comment') 'story_id': h['story_id'],
            'hn_url': 'https://news.ycombinator.com/item?id=${h['objectID']}',
          },
      ],
      'source': 'Hacker News (Algolia)',
    });
  }

  static List<Map<String, dynamic>> _hnComments(Object? children, {int max = 12, int depth = 0}) => [
    for (final c in (children as List? ?? const []).whereType<Map>().where((c) => c['text'] != null).take(max))
      {
        'author': c['author'],
        'created': '${c['created_at'] ?? ''}'.length >= 16 ? '${c['created_at']}'.substring(0, 16) : c['created_at'],
        'text': _DiscoverTools._cut(_plain(c['text']), depth == 0 ? 900 : 500),
        if (depth < 2 && (c['children'] as List?)?.isNotEmpty == true)
          'replies': _hnComments(c['children'], max: depth == 0 ? 3 : 2, depth: depth + 1),
        if ((c['children'] as List?)?.isNotEmpty == true) 'reply_count': (c['children'] as List).length,
      },
  ];

  Future<ToolOutput> _hnItem(Map<String, dynamic> args) async {
    final raw = '${args['item'] ?? ''}'.trim();
    final id = RegExp(r'id=(\d+)').firstMatch(raw)?[1] ?? RegExp(r'^\d+$').firstMatch(raw)?[0];
    if (id == null) throw ArgumentError('Give a Hacker News item id or link.');
    final (tree, item) = await (
      _json(Uri.https('hn.algolia.com', '/api/v1/items/$id')),
      _hn('/item/$id.json'),
    ).wait;
    final t = tree as Map;
    return ToolOutput({
      'item': {
        if (item is Map) ..._hnStoryRow(item) else ...{
          'id': t['id'],
          'title': t['title'],
          'url': t['url'],
          'points': t['points'],
          'author': t['author'],
        },
        if (t['text'] != null) 'text': _DiscoverTools._cut(_plain(t['text']), 4000),
      },
      'comments': _hnComments(t['children'], max: _limit(args['comments'], 12, 30)),
      'source': 'Hacker News',
    });
  }

  Future<ToolOutput> _hnUser(Map<String, dynamic> args) async {
    final name = '${args['username'] ?? ''}'.trim();
    if (name.isEmpty) throw ArgumentError('username is required');
    final u = await _hn('/user/${Uri.encodeComponent(name)}.json');
    if (u is! Map) throw ArgumentError('No Hacker News user "$name".');
    final subs = (u['submitted'] as List? ?? const []).take(8).toList();
    final items = await Future.wait([for (final id in subs) _hn('/item/$id.json').then<Object?>((v) => v, onError: (_) => null)]);
    return ToolOutput({
      'username': u['id'],
      'karma': u['karma'],
      'created': _iso(u['created']),
      if (u['about'] != null) 'about': _DiscoverTools._cut(_plain(u['about']), 800),
      'submissions': [
        for (final d in items)
          if (d is Map && d['deleted'] != true)
            d['type'] == 'comment'
                ? {'type': 'comment', 'id': d['id'], 'text': _DiscoverTools._cut(_plain(d['text']), 240), 'created': _iso(d['time'])}
                : _hnStoryRow(d),
      ],
      'url': 'https://news.ycombinator.com/user?id=${u['id']}',
    });
  }
}
