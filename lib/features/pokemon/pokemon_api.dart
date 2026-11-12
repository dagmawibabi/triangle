import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class PokemonException implements Exception {
  const PokemonException(this.message);
  final String message;
  @override
  String toString() => message;
}

const pokeTypes = [
  'normal', 'fire', 'water', 'electric', 'grass', 'ice', 'fighting', 'poison', 'ground', //
  'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy',
];

/// attacker -> defender -> multiplier (only entries that differ from 1x).
const _chart = <String, Map<String, double>>{
  'normal': {'rock': .5, 'ghost': 0, 'steel': .5},
  'fire': {'fire': .5, 'water': .5, 'grass': 2, 'ice': 2, 'bug': 2, 'rock': .5, 'dragon': .5, 'steel': 2},
  'water': {'fire': 2, 'water': .5, 'grass': .5, 'ground': 2, 'rock': 2, 'dragon': .5},
  'electric': {'water': 2, 'electric': .5, 'grass': .5, 'ground': 0, 'flying': 2, 'dragon': .5},
  'grass': {'fire': .5, 'water': 2, 'grass': .5, 'poison': .5, 'ground': 2, 'flying': .5, 'bug': .5, 'rock': 2, 'dragon': .5, 'steel': .5},
  'ice': {'fire': .5, 'water': .5, 'grass': 2, 'ice': .5, 'ground': 2, 'flying': 2, 'dragon': 2, 'steel': .5},
  'fighting': {'normal': 2, 'ice': 2, 'poison': .5, 'flying': .5, 'psychic': .5, 'bug': .5, 'rock': 2, 'ghost': 0, 'dark': 2, 'steel': 2, 'fairy': .5},
  'poison': {'grass': 2, 'poison': .5, 'ground': .5, 'rock': .5, 'ghost': .5, 'steel': 0, 'fairy': 2},
  'ground': {'fire': 2, 'electric': 2, 'grass': .5, 'poison': 2, 'flying': 0, 'bug': .5, 'rock': 2, 'steel': 2},
  'flying': {'electric': .5, 'grass': 2, 'fighting': 2, 'bug': 2, 'rock': .5, 'steel': .5},
  'psychic': {'fighting': 2, 'poison': 2, 'psychic': .5, 'dark': 0, 'steel': .5},
  'bug': {'fire': .5, 'grass': 2, 'fighting': .5, 'poison': .5, 'flying': .5, 'psychic': 2, 'ghost': .5, 'dark': 2, 'steel': .5, 'fairy': .5},
  'rock': {'fire': 2, 'ice': 2, 'fighting': .5, 'ground': .5, 'flying': 2, 'bug': 2, 'steel': .5},
  'ghost': {'normal': 0, 'psychic': 2, 'ghost': 2, 'dark': .5},
  'dragon': {'dragon': 2, 'steel': .5, 'fairy': 0},
  'dark': {'fighting': .5, 'psychic': 2, 'ghost': 2, 'dark': .5, 'fairy': .5},
  'steel': {'fire': .5, 'water': .5, 'electric': .5, 'ice': 2, 'rock': 2, 'steel': .5, 'fairy': 2},
  'fairy': {'fire': .5, 'fighting': 2, 'poison': .5, 'dragon': 2, 'dark': 2, 'steel': .5},
};

/// Damage multiplier of [attack] against a Pokémon with [types].
double typeMultiplier(String attack, List<String> types) => types.fold(1.0, (m, t) => m * (_chart[attack]?[t] ?? 1));

const _generations = [(1, 'Kanto', 151), (2, 'Johto', 251), (3, 'Hoenn', 386), (4, 'Sinnoh', 493), (5, 'Unova', 649), (6, 'Kalos', 721), (7, 'Alola', 809), (8, 'Galar', 905), (9, 'Paldea', 1025)];
const maxDex = 1025;

int generationOf(int id) => _generations.firstWhere((g) => id <= g.$3, orElse: () => _generations.last).$1;

String pokeName(String slug) {
  const special = {
    'nidoran-f': 'Nidoran♀', 'nidoran-m': 'Nidoran♂', 'mr-mime': 'Mr. Mime', 'mr-rime': 'Mr. Rime', //
    'mime-jr': 'Mime Jr.', 'farfetchd': 'Farfetch\'d', 'sirfetchd': 'Sirfetch\'d', 'ho-oh': 'Ho-Oh',
    'porygon-z': 'Porygon-Z', 'jangmo-o': 'Jangmo-o', 'hakamo-o': 'Hakamo-o', 'kommo-o': 'Kommo-o',
    'type-null': 'Type: Null', 'flabebe': 'Flabébé',
  };
  return special[slug] ?? titleCase(slug);
}

String titleCase(String slug) => slug.split('-').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// Pokémon facts from PokéAPI (pokeapi.co, keyless). The chat tools and the
/// cards (tapping a search result or an evolution) both use it.
class PokemonApi {
  PokemonApi({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static final PokemonApi instance = PokemonApi();
  static const _host = 'pokeapi.co';
  static const _art = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork';

  static String artwork(int id, {bool shiny = false}) => '$_art/${shiny ? 'shiny/' : ''}$id.png';

  final _cache = <String, Future<Object?>>{};
  Future<List<({int id, String slug, List<String> types})>>? _dex;

  Future<Object?> _json(String path, [Map<String, String>? query]) => _cache.putIfAbsent('$path?$query', () async {
    try {
      final r = await _http.get(Uri.https(_host, '/api/v2/$path', query), headers: {'accept': 'application/json'}).timeout(const Duration(seconds: 25));
      if (r.statusCode == 404) throw const PokemonException('not found');
      if (r.statusCode >= 400) throw PokemonException('PokéAPI said ${r.statusCode}.');
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      // Forget the failure (after it is returned) so a retry asks again.
      unawaited(Future(() {
        _cache.remove('$path?$query');
      }));
      rethrow;
    }
  });

  static int _idFrom(String url) => int.parse(url.split('/').where((s) => s.isNotEmpty).last);

  /// Every species with its types: one list call and one per type, kept for
  /// the session.
  Future<List<({int id, String slug, List<String> types})>> dex() => _dex ??= () async {
    final list = await _json('pokemon-species', {'limit': '$maxDex'}) as Map;
    final types = <int, List<String>>{};
    await Future.wait(pokeTypes.map((t) async {
      final d = await _json('type/$t') as Map;
      for (final p in (d['pokemon'] as List? ?? const []).whereType<Map>()) {
        final id = _idFrom('${p['pokemon']['url']}');
        if (id <= maxDex) (types[id] ??= ['', ''])[((p['slot'] as num?)?.toInt() ?? 1) - 1] = t;
      }
    }));
    final out = [
      for (final r in (list['results'] as List).whereType<Map>())
        (id: _idFrom('${r['url']}'), slug: '${r['name']}', types: [for (final t in types[_idFrom('${r['url']}')] ?? const <String>[]) if (t.isNotEmpty) t]),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return out;
  }().catchError((Object e) {
    _dex = null;
    throw e;
  });

  static Map<String, dynamic> _tile(({int id, String slug, List<String> types}) e) =>
      {'id': e.id, 'slug': e.slug, 'name': pokeName(e.slug), 'types': e.types, 'generation': generationOf(e.id), 'artwork': artwork(e.id)};

  /// Pokémon by name, type and generation, in dex order (or shuffled).
  Future<List<Map<String, dynamic>>> search({String query = '', List<String> types = const [], int? generation, bool random = false, int limit = 12}) async {
    final q = _slug(query);
    for (final t in types) {
      if (!pokeTypes.contains(t)) throw PokemonException('Unknown type "$t". Types: ${pokeTypes.join(', ')}.');
    }
    var hits = [
      for (final e in await dex())
        if ((q.isEmpty || e.slug.contains(q) || '${e.id}' == q) &&
            types.every(e.types.contains) &&
            (generation == null || generationOf(e.id) == generation))
          e,
    ];
    if (random) hits.shuffle(math.Random());
    // Names that start with the query first, each group in dex order.
    if (q.isNotEmpty && !random) hits = [...hits.where((e) => e.slug.startsWith(q)), ...hits.where((e) => !e.slug.startsWith(q))];
    return [for (final e in hits.take(limit)) _tile(e)];
  }

  static String _slug(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('♀', '-f')
      .replaceAll('♂', '-m')
      .replaceAll('é', 'e')
      .replaceAll(RegExp(r"[.':]"), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'^#0*'), '');

  /// The closest species names to [q], for "did you mean".
  Future<List<String>> _closest(String q) async {
    final dex = await this.dex();
    final scored = [for (final e in dex) (e.slug, e.slug.contains(q) || q.contains(e.slug) ? 0 : _distance(q, e.slug))]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final s in scored.take(4)) if (s.$2 <= 4) s.$1];
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// One Pokémon (a name, form name like "charizard-mega-x", or dex number)
  /// with its species, matchups and evolution line.
  Future<Map<String, dynamic>> info(String nameOrId) async {
    final q = _slug(nameOrId);
    if (q.isEmpty) throw const PokemonException('Give a Pokémon name or number.');
    Map p;
    try {
      p = await _json('pokemon/$q') as Map;
    } on PokemonException {
      // A species name whose default form has a longer name ("giratina", "deoxys").
      try {
        final s = await _json('pokemon-species/$q') as Map;
        final v = (s['varieties'] as List).whereType<Map>().firstWhere((v) => v['is_default'] == true, orElse: () => (s['varieties'] as List).first as Map);
        p = await _json('pokemon/${v['pokemon']['name']}') as Map;
      } on PokemonException {
        final close = await _closest(q);
        if (close.length == 1 || (close.isNotEmpty && _distance(q, close.first) <= 2)) return info(close.first);
        throw PokemonException('No Pokémon called "$nameOrId".${close.isEmpty ? '' : ' Did you mean ${close.map(pokeName).join(', ')}?'}');
      }
    }
    final species = await _json('pokemon-species/${_idFrom('${p['species']['url']}')}') as Map;
    final id = (p['id'] as num).toInt();
    final speciesId = (species['id'] as num).toInt();
    final types = [
      for (final t in ((p['types'] as List).whereType<Map>().toList()..sort((a, b) => (a['slot'] as num).compareTo(b['slot'] as num)))) '${t['type']['name']}',
    ];
    final stats = {for (final s in (p['stats'] as List).whereType<Map>()) '${s['stat']['name']}'.replaceAll('-', '_'): (s['base_stat'] as num).toInt()};
    String? en(List? entries, String key) {
      final hits = [for (final e in (entries ?? const []).whereType<Map>()) if (e['language']?['name'] == 'en') '${e[key]}'];
      return hits.isEmpty ? null : hits.last;
    }

    final flavor = en(species['flavor_text_entries'] as List?, 'flavor_text')?.replaceAll(RegExp(r'[\n\f\r­]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final genderRate = (species['gender_rate'] as num?)?.toInt() ?? -1;
    final matchups = {for (final t in pokeTypes) t: typeMultiplier(t, types)};
    final art = p['sprites']?['other']?['official-artwork'] as Map?;
    List<Map<String, dynamic>> evolution = const [];
    final chainUrl = species['evolution_chain']?['url'];
    if (chainUrl != null) {
      try {
        evolution = _evolution((await _json('evolution-chain/${_idFrom('$chainUrl')}') as Map)['chain'] as Map);
      } catch (_) {}
    }
    return {
      'id': id,
      'dex': speciesId,
      'slug': '${p['name']}',
      'name': pokeName('${p['name']}'),
      'genus': en(species['genera'] as List?, 'genus'),
      'types': types,
      'artwork': art?['front_default'] ?? artwork(speciesId),
      'shiny_artwork': art?['front_shiny'] ?? artwork(speciesId, shiny: true),
      'cry': p['cries']?['latest'] ?? p['cries']?['legacy'],
      'height_m': ((p['height'] as num?) ?? 0) / 10,
      'weight_kg': ((p['weight'] as num?) ?? 0) / 10,
      'abilities': [
        for (final a in (p['abilities'] as List).whereType<Map>()) {'name': titleCase('${a['ability']['name']}'), 'hidden': a['is_hidden'] == true},
      ],
      'stats': stats,
      'total': stats.values.fold(0, (a, b) => a + b),
      'description': flavor,
      'generation': generationOf(speciesId),
      'region': _generations[generationOf(speciesId) - 1].$2,
      'habitat': species['habitat'] == null ? null : titleCase('${species['habitat']['name']}'),
      'color': species['color']?['name'],
      'legendary': species['is_legendary'] == true,
      'mythical': species['is_mythical'] == true,
      'baby': species['is_baby'] == true,
      'capture_rate': species['capture_rate'],
      'gender': genderRate < 0 ? 'Genderless' : '${(100 - genderRate * 12.5).toStringAsFixed(1).replaceAll('.0', '')}% male',
      'egg_groups': [for (final g in (species['egg_groups'] as List? ?? const []).whereType<Map>()) titleCase('${g['name']}')],
      'weaknesses': [for (final e in matchups.entries) if (e.value > 1) {'type': e.key, 'x': e.value}]..sort((a, b) => (b['x'] as double).compareTo(a['x'] as double)),
      'resistances': [for (final e in matchups.entries) if (e.value > 0 && e.value < 1) {'type': e.key, 'x': e.value}],
      'immunities': [for (final e in matchups.entries) if (e.value == 0) e.key],
      'evolution': evolution,
      'forms': [
        for (final v in (species['varieties'] as List? ?? const []).whereType<Map>())
          if ('${v['pokemon']['name']}' != '${p['name']}') '${v['pokemon']['name']}',
      ],
      'moves_count': (p['moves'] as List?)?.length ?? 0,
      'source': 'PokéAPI',
    };
  }

  /// The evolution tree, flattened: each stage with what it comes from and how.
  static List<Map<String, dynamic>> _evolution(Map chain) {
    final out = <Map<String, dynamic>>[];
    void walk(Map node, int stage, String? from) {
      final slug = '${node['species']['name']}';
      final id = _idFrom('${node['species']['url']}');
      final details = (node['evolution_details'] as List? ?? const []).whereType<Map>().firstOrNull;
      out.add({'id': id, 'slug': slug, 'name': pokeName(slug), 'stage': stage, 'from': from, 'how': details == null ? null : _how(details), 'artwork': artwork(id)});
      for (final next in (node['evolves_to'] as List? ?? const []).whereType<Map>()) {
        walk(next, stage + 1, slug);
      }
    }

    walk(chain, 1, null);
    return out;
  }

  static String _how(Map d) {
    String? n(String k) => d[k] is Map ? titleCase('${d[k]['name']}') : null;
    final trigger = '${d['trigger']?['name'] ?? ''}';
    final parts = <String>[
      if (trigger == 'level-up' && d['min_level'] != null) 'Level ${d['min_level']}' else if (trigger == 'level-up') 'Level up',
      if (trigger == 'use-item' && n('item') != null) n('item')!,
      if (trigger == 'trade') 'Trade',
      if (!{'level-up', 'use-item', 'trade'}.contains(trigger) && trigger.isNotEmpty) titleCase(trigger),
      if (d['min_happiness'] != null) 'high friendship',
      if (d['min_affection'] != null) 'high affection',
      if (n('held_item') != null) 'holding ${n('held_item')}',
      if (n('known_move') != null) 'knowing ${n('known_move')}',
      if (n('known_move_type') != null) 'knowing a ${n('known_move_type')} move',
      if (n('location') != null) 'at ${n('location')}',
      if ('${d['time_of_day'] ?? ''}'.isNotEmpty) 'at ${d['time_of_day']}',
      if (n('trade_species') != null) 'for ${n('trade_species')}',
    ];
    return parts.join(', ');
  }
}
