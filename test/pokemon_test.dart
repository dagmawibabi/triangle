import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/pokemon_result_cards.dart';
import 'package:teleai/features/pokemon/pokemon_api.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

ToolPart _part(String name) => ToolPart(callId: 'c', name: name, arguments: '{}')
  ..result = '{}'
  ..status = ToolStatus.done;

Map<String, dynamic> _named(String name, int id, String kind) => {'name': name, 'url': 'https://pokeapi.co/api/v2/$kind/$id/'};

void main() {
  test('pokemon tools are registered and read-only', () {
    for (final n in ['pokemon_search', 'pokemon_info']) {
      expect(toolNamed(n), isNotNull, reason: n);
      expect(toolNamed(n)!.modifiesData, isFalse, reason: n);
    }
  });

  test('type matchups multiply', () {
    expect(typeMultiplier('ice', ['grass', 'flying']), 4);
    expect(typeMultiplier('electric', ['ground']), 0);
    expect(typeMultiplier('fire', ['water', 'rock']), 0.25);
  });

  test('info maps species, matchups and evolution; misspellings resolve', () async {
    final api = PokemonApi(
      client: MockClient((req) async {
        final path = req.url.path.replaceFirst('/api/v2/', '');
        final body = switch (path) {
          'pokemon/pikachu' => {
            'id': 25,
            'name': 'pikachu',
            'height': 4,
            'weight': 60,
            'species': _named('pikachu', 25, 'pokemon-species'),
            'types': [{'slot': 1, 'type': {'name': 'electric'}}],
            'stats': [{'base_stat': 35, 'stat': {'name': 'hp'}}, {'base_stat': 90, 'stat': {'name': 'speed'}}],
            'abilities': [{'ability': {'name': 'static'}, 'is_hidden': false}, {'ability': {'name': 'lightning-rod'}, 'is_hidden': true}],
            'cries': {'latest': 'https://x/25.ogg'},
            'moves': [{}, {}],
          },
          'pokemon-species/25' => {
            'id': 25,
            'gender_rate': 4,
            'genera': [{'genus': 'Mouse Pokémon', 'language': {'name': 'en'}}],
            'flavor_text_entries': [{'flavor_text': 'Stores\nelectricity.', 'language': {'name': 'en'}}],
            'evolution_chain': {'url': 'https://pokeapi.co/api/v2/evolution-chain/10/'},
            'varieties': [{'is_default': true, 'pokemon': {'name': 'pikachu'}}],
          },
          'evolution-chain/10' => {
            'chain': {
              'species': _named('pichu', 172, 'pokemon-species'),
              'evolution_details': [],
              'evolves_to': [
                {
                  'species': _named('pikachu', 25, 'pokemon-species'),
                  'evolution_details': [{'trigger': {'name': 'level-up'}, 'min_happiness': 220}],
                  'evolves_to': [
                    {
                      'species': _named('raichu', 26, 'pokemon-species'),
                      'evolution_details': [{'trigger': {'name': 'use-item'}, 'item': {'name': 'thunder-stone'}}],
                      'evolves_to': [],
                    },
                  ],
                },
              ],
            },
          },
          'pokemon-species' => {'results': [_named('pichu', 172, 'pokemon-species'), _named('pikachu', 25, 'pokemon-species')]},
          final p when p.startsWith('type/') => {
            'pokemon': p == 'type/electric' ? [{'slot': 1, 'pokemon': _named('pikachu', 25, 'pokemon')}] : [],
          },
          _ => null,
        };
        return body == null ? http.Response('Not Found', 404) : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
    final p = await api.info('Pikachu');
    expect(p['name'], 'Pikachu');
    expect(p['genus'], 'Mouse Pokémon');
    expect(p['description'], 'Stores electricity.');
    expect(p['height_m'], 0.4);
    expect(p['gender'], '50% male');
    expect((p['weaknesses'] as List).single, {'type': 'ground', 'x': 2.0});
    final evo = p['evolution'] as List;
    expect([for (final e in evo) (e as Map)['slug']], ['pichu', 'pikachu', 'raichu']);
    expect((evo[1] as Map)['how'], 'Level up, high friendship');
    expect((evo[2] as Map)['how'], 'Thunder Stone');

    expect((await api.info('pikachuu'))['id'], 25);
    final found = await api.search(types: ['electric']);
    expect(found.single['name'], 'Pikachu');
  });

  testWidgets('pokemon cards draw', (tester) async {
    final cards = [
      pokemonResultFor(_part('pokemon_info'), {
        'id': 6,
        'dex': 6,
        'slug': 'charizard',
        'name': 'Charizard',
        'genus': 'Flame Pokémon',
        'types': ['fire', 'flying'],
        'stats': {'hp': 78, 'attack': 84, 'defense': 78, 'special_attack': 109, 'special_defense': 85, 'speed': 100},
        'total': 534,
        'abilities': [{'name': 'Blaze', 'hidden': false}, {'name': 'Solar Power', 'hidden': true}],
        'weaknesses': [{'type': 'rock', 'x': 4.0}],
        'resistances': [{'type': 'grass', 'x': 0.25}],
        'immunities': ['ground'],
        'evolution': [
          {'id': 4, 'slug': 'charmander', 'name': 'Charmander', 'stage': 1},
          {'id': 5, 'slug': 'charmeleon', 'name': 'Charmeleon', 'stage': 2, 'how': 'Level 16'},
          {'id': 6, 'slug': 'charizard', 'name': 'Charizard', 'stage': 3, 'how': 'Level 36'},
        ],
        'generation': 1,
        'region': 'Kanto',
      }),
      pokemonResultFor(_part('pokemon_search'), {
        'pokemon': [
          {'id': 25, 'slug': 'pikachu', 'name': 'Pikachu', 'types': ['electric']},
        ],
      }),
    ];
    expect(cards.every((c) => c != null), isTrue);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [for (final c in cards) c!]))))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Charizard'), findsWidgets);
    expect(find.text('Flame Pokémon'), findsOneWidget);
    expect(find.text('Pikachu'), findsOneWidget);
    expect(find.text('Level 16'), findsOneWidget);
  });
}
