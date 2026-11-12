part of 'telegram_tools.dart';

// Pokémon from PokéAPI (keyless). The cards are in pokemon_result_cards.dart.

final _pokemonTools = <TelegramTool>[
  TelegramTool(
    name: 'pokemon_search',
    label: 'Searching Pokémon',
    category: ToolCategory.explore,
    cost: ToolCost.web,
    description:
        'Finds Pokémon by part of a name, type (one or two, like ["fire","flying"]) and generation (1-9), in National '
        'Dex order, or random ones. The user sees a grid of Pokémon they can tap for details. Use pokemon_info for one '
        'Pokémon\'s full details.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Part of a name, or a dex number.'},
      'types': {
        'type': 'array',
        'items': {'type': 'string', 'enum': pokeTypes},
        'description': 'Up to two types the Pokémon must have.',
      },
      'generation': {'type': 'integer', 'description': '1 (Kanto) to 9 (Paldea).'},
      'random': {'type': 'boolean', 'description': 'Pick random matches instead of dex order.'},
      'limit': {'type': 'integer', 'description': '1-30; default 12.'},
    }),
  ),
  TelegramTool(
    name: 'pokemon_info',
    label: 'Looking up a Pokémon',
    category: ToolCategory.explore,
    cost: ToolCost.web,
    description:
        'One Pokémon\'s details: Pokédex entry, types, base stats, abilities, height and weight, weaknesses and '
        'resistances, evolution line with methods, forms, gender ratio and more. Takes a name (misspellings are '
        'corrected), a form like "charizard-mega-x" or a dex number. The user sees a Pokémon card, so answer in a '
        'sentence or two instead of repeating every stat.',
    parameters: _obj({
      'pokemon': {'type': 'string', 'description': 'A name, form name or National Dex number, like "Pikachu" or "25".'},
    }, ['pokemon']),
  ),
];

const _pokemonPolicies = <String, ToolPolicy>{
  'pokemon_search': ToolPolicy(ToolAccess.read),
  'pokemon_info': ToolPolicy(ToolAccess.read),
};

const _pokemonReferences = <String, ToolReference>{
  'pokemon_search': ToolReference(['count', 'pokemon: id, name, types, generation, artwork', 'source'], limits: ['limit: 1-30.']),
  'pokemon_info': ToolReference([
    'id', 'name', 'genus', 'types', 'artwork', 'stats', 'total', 'abilities', 'height_m', 'weight_kg', 'description', //
    'generation', 'region', 'weaknesses', 'resistances', 'immunities', 'evolution', 'forms', 'gender', 'egg_groups',
  ]),
};

extension _PokemonTools on TelegramToolRunner {
  Future<ToolOutput>? _runPokemon(String name, Map<String, dynamic> args) => switch (name) {
    'pokemon_search' => _pokeWrap(_pokemonSearch(args)),
    'pokemon_info' => _pokeWrap(_pokemonInfo(args)),
    _ => null,
  };

  static Future<ToolOutput> _pokeWrap(Future<ToolOutput> f) async {
    try {
      return await f;
    } on PokemonException catch (e) {
      return ToolOutput({'error': e.message});
    } on TimeoutException {
      return const ToolOutput({'error': 'PokéAPI took too long to answer; try again.'});
    } on SocketException {
      return const ToolOutput({'error': 'Couldn\'t reach PokéAPI; check the connection.'});
    }
  }

  Future<ToolOutput> _pokemonSearch(Map<String, dynamic> a) async {
    final types = [for (final t in (a['types'] as List? ?? const [])) '$t'.trim().toLowerCase()].take(2).toList();
    final gen = (a['generation'] as num?)?.toInt();
    final list = await PokemonApi.instance.search(
      query: '${a['query'] ?? ''}',
      types: types,
      generation: gen?.clamp(1, 9),
      random: a['random'] == true,
      limit: ((a['limit'] as num?)?.toInt() ?? 12).clamp(1, 30),
    );
    return ToolOutput({'count': list.length, 'pokemon': list, 'source': 'PokéAPI'});
  }

  Future<ToolOutput> _pokemonInfo(Map<String, dynamic> a) async => ToolOutput(await PokemonApi.instance.info('${a['pokemon'] ?? ''}'));
}
