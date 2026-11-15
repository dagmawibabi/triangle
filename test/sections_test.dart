import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/books/book_parsers.dart';
import 'package:teleai/features/books/books.dart';
import 'package:teleai/features/gallery/gallery.dart';
import 'package:teleai/features/marketplace/market.dart';
import 'package:teleai/features/media/music_stats.dart';
import 'package:teleai/features/movies/movies.dart';
import 'package:teleai/features/sections/section_kit.dart';
import 'package:teleai/features/settings/data/app_data.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('prices are read however a post writes them', () {
    expect(parsePrice('iPhone 13 Pro\nPrice: 85,000 birr'), (amount: 85000.0, currency: 'ETB'));
    expect(parsePrice('ዋጋ 12k ብር'), (amount: 12000.0, currency: 'ETB'));
    expect(parsePrice(r'Only $249.99 today'), (amount: 249.99, currency: 'USD'));
    expect(parsePrice('Laptop, 32GB RAM, 1TB').amount, isNull);
    expect(priceText(1250000, 'ETB'), 'ETB 1,250,000');
  });

  test('post keys survive accounts with colons', () {
    final k = postKey('acc:1', -100123, 456);
    expect(parsePostKey(k), (account: 'acc:1', chatId: -100123, messageId: 456));
    expect(parsePostKey('nonsense'), isNull);
  });

  test('plain text and markdown become blocks and chapters', () {
    final d = parsePlain('# One\n\nFirst para\nwrapped line.\n\n> a quote\n\n# Two\n\nSecond.', markdown: true);
    expect(d.blocks.first.type, BlockType.heading);
    expect(d.blocks[1].text, 'First para wrapped line.');
    expect(d.blocks[2].type, BlockType.quote);
    expect(d.sections.map((s) => s.title), ['One', 'Two']);
    expect(d.sectionOf(d.blocks.length - 1), 1);
    expect(d.wordOffsets.last, d.wordCount);
  });

  test('sources, cart and listings persist and add up', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final m = c.read(marketProvider.notifier);
    await m.ready;
    await m.setSources(const [SourceRef(account: 'a', chatId: 1, title: 'Shop')]);
    await m.addToCart(SavedProduct(key: postKey('a', 1, 10), title: 'Shoes', price: 1000, currency: 'ETB', store: 'Shop', addedAt: DateTime(2026)), qty: 2);
    await m.addToCart(SavedProduct(key: postKey('a', 1, 11), title: 'Hat', price: 5, currency: 'USD', store: 'Shop', addedAt: DateTime(2026)));
    expect(c.read(marketProvider).cartTotals, {'ETB': 2000, 'USD': 5});
    expect(c.read(marketProvider).cartCount, 3);

    final again = ProviderContainer();
    addTearDown(again.dispose);
    await again.read(marketProvider.notifier).ready;
    expect(again.read(marketProvider).sources.single.title, 'Shop');
    expect(again.read(marketProvider).cart, hasLength(2));
  });

  test('books keep shelves, highlights and reading time', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final b = c.read(booksProvider.notifier);
    await b.ready;
    await b.addShelf('Classics');
    await b.renameShelf('Classics', 'Old books');
    expect(c.read(booksProvider).shelves, ['Old books']);
    await b.addHighlight('x', 3, 0, 5, 'Hello');
    await b.setGoal(30);
    expect(c.read(booksProvider).goal, 30);
    expect(c.read(booksProvider).highlights.single.text, 'Hello');
  });

  test('gallery albums and favorites', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final g = c.read(galleryProvider.notifier);
    await g.ready;
    final al = await g.createAlbum('Trip');
    expect(await g.addKeysToAlbum(al.id, ['a:1:1', 'a:1:2']), 2);
    expect(await g.addKeysToAlbum(al.id, ['a:1:2']), 0);
    await g.setFavoriteKeys(['a:1:1'], true);
    expect(c.read(galleryProvider).isFavorite('a:1:1'), isTrue);
    expect(g.album('trip')?.keys, ['a:1:1', 'a:1:2']);
  });

  test('watch progress feeds continue watching', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final m = c.read(moviesProvider.notifier);
    await m.ready;
    final v = Video(account: 'a', chatId: 1, messageId: 2, channel: 'C', title: 'Film', seconds: 3600, date: DateTime(2026));
    m.saveProgress(v, 600, 3600);
    expect(c.read(moviesProvider).continueWatching.single.key, v.key);
    m.saveProgress(v, 3550, 3600);
    expect(c.read(moviesProvider).continueWatching, isEmpty);
  });

  test('listening stats count plays and time', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(musicStatsProvider.notifier);
    await s.ready;
    s.started(key: 'k', title: 'Song', artist: 'Band', playlist: 'p1');
    s.heard('k', 120);
    s.started(key: 'k', title: 'Song', artist: 'Band', playlist: 'p1');
    final st = c.read(musicStatsProvider);
    expect(st.tracks['k']!.plays, 2);
    expect(st.totalSeconds, 120);
    expect(st.playlistPlays['p1'], 2);
    expect(st.artists.first.$1, 'Band');
  });

  test('restoring maps section accounts and item keys', () {
    final raw = jsonEncode({
      'sources': [{'a': 'old', 'c': 5, 't': 'Shop'}],
      'cart': [{'k': 'old:5:9', 't': 'Thing', 's': 'Shop', 'at': 0}],
    });
    final out = jsonDecode(AppData.remapAccounts(MarketStore.key, raw, {'old': 'new'})) as Map;
    expect((out['sources'] as List).single['a'], 'new');
    expect((out['cart'] as List).single['k'], 'new:5:9');
  });

  test('section tools are registered with policies and references', () {
    for (final t in sectionTools) {
      expect(sectionToolNames, contains(t.name));
      expect(telegramTools.where((x) => x.name == t.name), hasLength(1), reason: t.name);
      expect(toolPolicies[t.name], isNotNull, reason: t.name);
      expect(toolReferences[t.name], isNotNull, reason: t.name);
    }
    expect(sectionToolNames, hasLength(sectionTools.length));
    expect(toolNamed('remove_book')!.destructive, isTrue);
    for (final n in ['like_tracks', 'music_stats', 'player_control']) {
      expect(toolPolicies[n], isNotNull, reason: n);
      expect(toolReferences[n], isNotNull, reason: n);
    }
  });
}
