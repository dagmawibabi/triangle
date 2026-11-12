part of 'telegram_tools.dart';

// Free, legal retro games from Nostalgia's stores: Homebrew Hub, SMS Power,
// the idgames Doom archive and staff picks. Search, details, download.

const _retroStores = ['all', 'homebrew_hub', 'smspower', 'idgames', 'picks'];

final _retroTools = <TelegramTool>[
  TelegramTool(
    name: 'retro_games_search',
    label: 'Searching retro games',
    category: ToolCategory.games,
    cost: ToolCost.web,
    description:
        'Finds free, legal retro games: homebrew and community releases (not pirated commercial ROMs). Stores: Homebrew Hub '
        '(Game Boy, Game Boy Color, GBA, NES), SMS Power (Master System, Game Gear), idgames (Doom and Doom II map packs '
        'and megawads) and staff picks. Leave query empty to browse what is new or best. Each game has its store, id, '
        'system, author, picture and page; use retro_game_details for more and retro_game_download to save it.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'A title, author or word, e.g. "tetris", "platformer", "scythe". Empty to browse.'},
      'store': {'type': 'string', 'enum': _retroStores, 'description': 'Default all.'},
      'system': {
        'type': 'string',
        'enum': ['gb', 'gbc', 'gba', 'nes', 'sms', 'gg', 'doom'],
        'description': 'Only games for this system.',
      },
      'limit': {'type': 'integer', 'description': '1-40, default 20.'},
    }),
  ),
  TelegramTool(
    name: 'retro_game_details',
    label: 'Reading about a retro game',
    category: ToolCategory.games,
    cost: ToolCost.web,
    description:
        'One retro game in full (store and id from retro_games_search): description, screenshots, developer, licence, '
        'release date, tags, links, what plays it, and whether there is a download. The user sees a detailed sheet.',
    parameters: _obj({
      'store': {'type': 'string', 'enum': ['homebrew_hub', 'smspower', 'idgames', 'picks'], 'description': 'From retro_games_search.'},
      'id': {'type': 'string', 'description': 'The game\'s id from retro_games_search.'},
    }, ['store', 'id']),
  ),
  TelegramTool(
    name: 'retro_game_download',
    label: 'Downloading a retro game',
    category: ToolCategory.games,
    cost: ToolCost.web,
    description:
        'Downloads a free retro game (store and id from retro_games_search) to the phone: the ROM, or for Doom the map '
        'pack zip. It lands in Files and becomes a file of this conversation; open it with an emulator (the result says '
        'which), or send it with send_message.',
    parameters: _obj({
      'store': {'type': 'string', 'enum': ['homebrew_hub', 'smspower', 'idgames', 'picks'], 'description': 'From retro_games_search.'},
      'id': {'type': 'string', 'description': 'The game\'s id from retro_games_search.'},
    }, ['store', 'id']),
  ),
];

final _retroToolNames = {for (final t in _retroTools) t.name};

extension _RetroToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runRetro(String name, Map<String, dynamic> args) {
    if (!_retroToolNames.contains(name)) return null;
    return _retro(name, args);
  }

  Future<ToolOutput> _retro(String name, Map<String, dynamic> a) async {
    String s(String k) => '${a[k] ?? ''}'.trim();
    final games = RetroGames();
    try {
      switch (name) {
        case 'retro_games_search':
          final r = await games.search(
            query: s('query'),
            store: s('store').isEmpty ? 'all' : s('store'),
            system: s('system').isEmpty ? null : s('system'),
            limit: TelegramToolRunner._int(a, 'limit', fallback: 20, max: 40),
          );
          return ToolOutput({...r, if ((r['games'] as List).isEmpty) 'note': 'Nothing in those stores matches. PDRoms has more homebrew: the link opens its search in the browser.'});
        case 'retro_game_details':
          final d = await games.details(s('store'), s('id'));
          return ToolOutput({...d, 'play_with': ?RetroGames.playWith[d['system']]});
        case 'retro_game_download':
          final d = await games.details(s('store'), s('id'));
          var url = d['download'] as String?;
          // Homebrew Hub entries without a file often release on GitHub.
          if (url == null) {
            final repo = [for (final l in (d['links'] as List? ?? const [])) RegExp(r'github\.com/([^/\s]+)/([^/\s#?]+)').firstMatch('$l')].nonNulls.firstOrNull;
            if (repo != null) {
              final r = await _web.request('GET', Uri.https('api.github.com', '/repos/${repo[1]}/${repo[2]!.replaceAll(RegExp(r'\.git$'), '')}/releases/latest'), headers: {'accept': 'application/vnd.github+json'});
              if (r.statusCode == 200) {
                final ext = switch (d['system']) {
                  'gba' => const ['gba'],
                  'nes' => const ['nes'],
                  'gbc' => const ['gbc', 'gb'],
                  _ => const ['gb', 'gbc'],
                };
                final assets = ((jsonDecode(WebFetcher.decodeBody(r)) as Map)['assets'] as List? ?? const []).cast<Map>();
                url = assets.where((x) => ext.contains('${x['name']}'.split('.').last.toLowerCase())).map((x) => '${x['browser_download_url']}').firstOrNull;
              }
            }
          }
          if (url == null) return ToolOutput({'error': 'There is no download for ${d['title']}. Its page: ${d['page']}'});
          final file = await _web.download(Uri.parse(url), name: '${d['file'] ?? url.split('/').last}');
          final size = await file.length();
          return ToolOutput({
            'downloaded': true,
            'title': d['title'],
            'store': d['store'],
            'store_name': d['store_name'],
            'system': d['system'],
            'system_name': d['system_name'],
            'image': ?d['image'],
            'file_path': file.path,
            'name': file.path.split(RegExp(r'[\\/]')).last,
            'size': formatBytes(size),
            'created_files': [file.path],
            'play_with': ?RetroGames.playWith[d['system']],
            'note': d['system'] == 'doom'
                ? 'A Doom map pack: open it in a Doom source port with Freedoom (free) or the original game as the base.'
                : 'Open it with ${RetroGames.playWith[d['system']] ?? 'an emulator for its system'}.',
          });
      }
      return ToolOutput({'error': 'Unknown tool $name'});
    } on HttpException catch (e) {
      return ToolOutput({'error': e.message});
    }
  }
}
