import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/explore_result_cards.dart';
import 'package:teleai/features/chat/presentation/widgets/library_result_cards.dart';
import 'package:teleai/features/library/library_api.dart';
import 'package:teleai/features/library/library_favorites.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/media/audio_center.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

ToolPart _part(String name) => ToolPart(callId: 'c', name: name, arguments: '{}')
  ..result = '{}'
  ..status = ToolStatus.done;

void main() {
  test('library and explore tools are registered', () {
    for (final n in [
      'ebook_search', 'ebook_details', 'ebook_download', 'search_books', 'audiobook_search', 'audiobook_chapters', //
      'radio_search', 'podcast_search', 'podcast_top', 'podcast_episodes', 'audio_download', 'play_audio',
      'country_info', 'countries_list', 'nasa_apod', 'bible_search',
    ]) {
      expect(toolNamed(n), isNotNull, reason: n);
    }
    expect(toolNamed('ebook_search')!.modifiesData, isFalse);
    expect(toolNamed('play_audio')!.modifiesData, isTrue);
  });

  test('podcast feeds parse', () async {
    const rss = '''<?xml version="1.0"?><rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
      <title>Show</title><itunes:author>Host</itunes:author><description>About &lt;b&gt;it&lt;/b&gt;</description>
      <itunes:image href="https://x/cover.jpg"/><itunes:category text="History"/>
      <item><title>Ep 1</title><pubDate>Tue, 05 Nov 2024 09:30:00 +0000</pubDate><itunes:duration>1:02:03</itunes:duration>
        <enclosure url="https://x/1.mp3" type="audio/mpeg"/><description>First</description></item>
      <item><title>Video</title><enclosure url="https://x/v.mp4" type="video/mp4"/></item>
    </channel></rss>''';
    final api = LibraryApi(client: MockClient((_) async => http.Response(rss, 200)));
    final f = await api.podcastFeed('https://x/feed');
    expect(f['title'], 'Show');
    expect(f['author'], 'Host');
    expect(f['description'], 'About it');
    expect(f['categories'], ['History']);
    final eps = f['episodes'] as List;
    expect(eps, hasLength(1));
    expect((eps.first as Map)['seconds'], 3723);
    expect((eps.first as Map)['published'], '2024-11-05');
  });

  test('countries and APOD map cleanly', () async {
    final api = LibraryApi(
      client: MockClient((req) async {
        if (req.url.host == 'cdn.jsdelivr.net') {
          return http.Response(
            jsonEncode([
              for (var i = 0; i < 120; i++) {'name': {'common': 'Land $i'}, 'cca2': 'L$i', 'cca3': 'L${i}X', 'region': 'Europe'},
              {
                'name': {'common': 'Ethiopia', 'official': 'Federal Democratic Republic of Ethiopia'},
                'cca2': 'ET',
                'cca3': 'ETH',
                'capital': ['Addis Ababa'],
                'region': 'Africa',
                'area': 1104300,
                'latlng': [8, 38],
                'idd': {'root': '+2', 'suffixes': ['51']},
                'languages': {'amh': 'Amharic'},
                'currencies': {'ETB': {'name': 'Ethiopian birr', 'symbol': 'Br'}},
              },
            ]),
            200,
          );
        }
        if (req.url.host == 'api.worldbank.org') {
          return http.Response(jsonEncode([{'page': 1}, [{'countryiso3code': 'ETH', 'value': 135472051}]]), 200);
        }
        if (req.url.host == 'science.nasa.gov') return http.Response('[]', 200);
        return http.Response(jsonEncode({'date': '2024-04-08', 'title': 'Eclipse', 'media_type': 'image', 'url': 'https://apod/x.jpg', 'explanation': 'Dark'}), 200);
      }),
    );
    final c = await api.countryInfo('ET');
    expect(c['capital'], 'Addis Ababa');
    expect(c['population'], 135472051);
    expect(c['flag'], 'https://flagcdn.com/w320/et.png');
    expect((await api.countryInfo('ethiopia'))['code'], 'ET');
    expect((await api.countries(region: 'africa')).single['name'], 'Ethiopia');
    expect(c['calling_code'], '+251');
    expect((c['currencies'] as List).first, {'code': 'ETB', 'name': 'Ethiopian birr', 'symbol': 'Br'});
    final apod = await api.apod(key: '');
    expect(apod.single['thumbnail'], 'https://apod/x.jpg');
    expect(apod.single['page'], 'https://apod.nasa.gov/apod/ap240408.html');
  });

  test('APOD posts on science.nasa.gov give the real picture', () {
    final p = LibraryApi.apodPost({
      'title': {'rendered': 'APOD: 2026 November 10 &#8211; Saturn Behind the Moon'},
      'link': 'https://science.nasa.gov/image-article/apod-2026-november-10-saturn-behind-the-moon/',
      'featured_image_url': 'https://assets.science.nasa.gov/dynamicimage/assets/science/cds/apod/apod/2026/november/Moonsaturn.jpg?w=2048&h=1320&fit=clip',
      'content': {
        'rendered': '<p>Astronomy Picture of the Day</p><p>Image Credit &amp; Copyright: Ortu</p>'
            '<p>Explanation: Sometimes Saturn disappears. Tomorrow&#8217;s picture: a date in Poland</p>',
      },
    })!;
    expect(p['date'], '2026-11-10');
    expect(p['title'], 'Saturn Behind the Moon');
    expect(p['explanation'], 'Sometimes Saturn disappears.');
    expect(p['copyright'], 'Ortu');
    expect(p['media_type'], 'image');
    expect(p['hd_url'], 'https://assets.science.nasa.gov/dynamicimage/assets/science/cds/apod/apod/2026/november/Moonsaturn.jpg');
    expect('${p['thumbnail']}', contains('w=900'));
    // NASA's stand-in logo isn't a picture.
    final none = LibraryApi.apodPost({
      'title': {'rendered': 'APOD: 2026 October 18 – Sonified'},
      'featured_image_url': 'https://science.nasa.gov/wp-content/themes/nasa-child/assets/images/nasa-logo@2x.png',
      'content': {'rendered': '<iframe src="https://www.youtube.com/embed/DzrCEm1ZBRY?feature=oembed"></iframe>'},
    })!;
    expect(none['media_type'], 'video');
    expect(none['thumbnail'], 'https://img.youtube.com/vi/DzrCEm1ZBRY/hqdefault.jpg');
  });

  test('favourite shows and episodes toggle and stay', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final favs = c.read(libraryFavoritesProvider.notifier);
    expect(await favs.toggleShow({'title': 'The Daily', 'feed': 'https://f/daily'}), isTrue);
    expect(await favs.toggleEpisode({'title': 'Ep 1', 'audio': 'https://f/1.mp3', 'show': 'The Daily'}), isTrue);
    expect(c.read(libraryFavoritesProvider).hasShow({'feed': 'https://f/daily'}), isTrue);
    expect(c.read(libraryFavoritesProvider).episodes.single['show'], 'The Daily');
    expect(await favs.toggleShow({'feed': 'https://f/daily'}), isFalse);
    expect(c.read(libraryFavoritesProvider).shows, isEmpty);
  });

  test('stream tracks are keyed by their url', () {
    final t = Track.stream(url: 'https://radio/x', title: 'X', live: true);
    expect(t.key, 'url:https://radio/x');
    expect(t.live, isTrue);
  });

  testWidgets('library and explore cards draw', (tester) async {
    final cards = [
      libraryResultFor(_part('radio_search'), {
        'stations': [
          {'id': 'a', 'name': 'Jazz FM', 'stream': 'https://s/1', 'country': 'France', 'country_code': 'FR', 'tags': ['jazz'], 'bitrate': 128},
        ],
      }),
      libraryResultFor(_part('ebook_search'), {
        'total': 1,
        'books': [
          {'id': 1, 'title': 'Pride and Prejudice', 'authors': [{'name': 'Jane Austen'}], 'epub': 'https://g/1.epub'},
        ],
      }),
      libraryResultFor(_part('podcast_top'), {
        'country': 'us',
        'shows': [
          {'id': 1, 'title': 'The Daily', 'author': 'NYT', 'rank': 1},
        ],
      }),
      exploreResultFor(_part('country_info'), {'name': 'Ethiopia', 'official': 'FDRE', 'capital': 'Addis Ababa', 'region': 'Africa', 'population': 120000000, 'area_km2': 1104300}),
      exploreResultFor(_part('nasa_apod'), {
        'pictures': [
          {'date': '2024-04-08', 'title': 'Eclipse', 'media_type': 'image', 'explanation': 'Dark'},
        ],
      }),
    ];
    expect(cards.every((c) => c != null), isTrue);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [for (final c in cards) c!]))))));
    expect(find.text('Jazz FM'), findsOneWidget);
    expect(find.text('Pride and Prejudice'), findsOneWidget);
    expect(find.text('The Daily'), findsOneWidget);
    expect(find.text('Ethiopia'), findsOneWidget);
    expect(find.text('Eclipse'), findsOneWidget);
  });
}
