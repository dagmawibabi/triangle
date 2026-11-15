import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../books/book_reader.dart';
import '../../../books/books.dart';
import '../../../books/books_screen.dart';
import '../../../gallery/gallery.dart';
import '../../../gallery/gallery_screen.dart';
import '../../../marketplace/market.dart';
import '../../../marketplace/market_screen.dart';
import '../../../media/audio_center.dart';
import '../../../media/audio_player_ui.dart';
import '../../../movies/movies.dart';
import '../../../movies/movies_screen.dart';
import '../../../playlists/music_stats_screen.dart';
import '../../../playlists/playlist_widgets.dart';
import '../../../playlists/playlists.dart';
import '../../../playlists/playlists_screen.dart';
import '../../../sections/section_kit.dart';
import '../../domain/chat_models.dart';

/// Cards for the Music, Marketplace, Video, Books and Gallery tools: what
/// came back, drawn like the sections themselves, with a sheet for the
/// rest and a tap into the page. Null for other tools.
Widget? sectionResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'list_playlists' when list(j['playlists']).isNotEmpty => _PlaylistsCard(ids: [for (final p in list(j['playlists'])) '${p['playlist_id']}']),
    'playlist_tracks' when j['playlist'] is Map => _PlaylistCard(id: '${(j['playlist'] as Map)['playlist_id']}'),
    'create_playlist' when j['created'] is Map => _PlaylistCard(id: '${(j['created'] as Map)['playlist_id']}', note: 'Made'),
    'update_playlist' when j['updated'] is Map => _PlaylistCard(id: '${(j['updated'] as Map)['playlist_id']}', note: 'Updated'),
    'duplicate_playlist' when j['created'] is Map => _PlaylistCard(id: '${(j['created'] as Map)['playlist_id']}', note: 'Copied'),
    'import_playlist' when j['imported'] is Map => _PlaylistCard(id: '${(j['imported'] as Map)['playlist_id']}', note: 'Imported'),
    'play_playlist' || 'player_control' || 'like_tracks' when j['error'] == null => const _PlayerCard(),
    'music_stats' when j['error'] == null => _StatsCard(data: j),
    'market_search' || 'market_tidy' when list(j['products']).isNotEmpty => _ProductsCard(products: list(j['products']), total: (j['total'] as num?)?.toInt()),
    'market_item' when j['product'] is Map => _ProductsCard(products: [Map<String, dynamic>.from(j['product'] as Map)]),
    'market_cart' when j['cart'] is List => _SavedCard(items: list(j['cart']), cart: true, totals: (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {}),
    'market_wishlist' when j['wishlist'] is List => _SavedCard(items: list(j['wishlist']), cart: false),
    'find_videos' when list(j['videos']).isNotEmpty => _VideosCard(keys: [for (final v in list(j['videos'])) '${v['video_key']}'], rows: list(j['videos']), total: (j['total'] as num?)?.toInt()),
    'movie_library' when list(j['my_list']).isNotEmpty || list(j['history']).isNotEmpty =>
      _VideosCard(keys: [for (final v in [...list(j['my_list']), ...list(j['history'])]) '${v['video_key']}'], rows: [...list(j['my_list']), ...list(j['history'])], title: 'My list & history'),
    'list_books' when list(j['books']).isNotEmpty => _BooksCard(ids: [for (final b in list(j['books'])) '${b['book_id']}']),
    'add_book' when j['added'] is Map => _BooksCard(ids: ['${(j['added'] as Map)['book_id']}'], title: 'Added to your library'),
    'update_book' when j['updated'] is Map => _BooksCard(ids: ['${(j['updated'] as Map)['book_id']}'], title: 'Updated'),
    'find_books' when list(j['books']).isNotEmpty => _FoundBooksCard(rows: list(j['books'])),
    'reading_stats' when j['error'] == null => _ReadingCard(data: j),
    'gallery_items' when list(j['items']).isNotEmpty => _GalleryCard(keys: [for (final i in list(j['items'])) '${i['item_key']}']),
    'gallery_albums' when list(j['albums']).isNotEmpty => _AlbumsCard(rows: list(j['albums'])),
    _ => null,
  };
}

// ---- frame -------------------------------------------------------------------

/// A card with a coloured header, the body, and an optional "See all".
class _Frame extends StatelessWidget {
  const _Frame({required this.icon, required this.color, required this.title, required this.child, this.onOpen, this.openLabel = 'Open', this.onAll});
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;
  final VoidCallback? onOpen;
  final String openLabel;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: Space.xs),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.04)])),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              if (onAll != null) TextButton(onPressed: onAll, child: const Text('See all')),
              if (onOpen != null) TextButton(onPressed: onOpen, child: Text(openLabel)),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

Future<void> _sheet(BuildContext context, String title, Widget Function(BuildContext, ScrollController) body) => showAppSheet<void>(
  context,
  initialSize: 0.75,
  builder: (context, scroll) => Column(
    children: [
      Text(title, style: context.text.titleMedium),
      const SizedBox(height: Space.s),
      Expanded(child: body(context, scroll)),
    ],
  ),
);

Widget _mini(String? b64, {double w = 56, double h = 56, IconData icon = Icons.image_outlined}) => ClipRRect(
  borderRadius: BorderRadius.circular(Radii.s),
  child: SizedBox(
    width: w,
    height: h,
    child: b64 == null ? Container(color: AppColors.surface2, child: Icon(icon, color: AppColors.text3)) : Image.memory(base64Decode(b64), fit: BoxFit.cover),
  ),
);

// ---- music -------------------------------------------------------------------

class _PlaylistsCard extends ConsumerWidget {
  const _PlaylistsCard({required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(playlistsProvider).playlists;
    final lists = [for (final id in ids) ?all.where((p) => p.id == id).firstOrNull];
    return _Frame(
      icon: Icons.queue_music_rounded,
      color: const Color(0xFF1DB954),
      title: '${lists.length} playlists',
      onOpen: () => _push(context, const PlaylistsScreen()),
      child: SizedBox(
        height: 172,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(Space.m),
          itemCount: lists.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.m),
          itemBuilder: (_, i) {
            final p = lists[i];
            return GestureDetector(
              onTap: () => _push(context, PlaylistScreen(playlistId: p.id)),
              child: SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        PlaylistCover(playlist: p, size: 112, radius: Radii.m),
                        if (p.tracks.isNotEmpty)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => ref.read(playlistsProvider.notifier).play(p),
                                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_arrow_rounded, size: 20, color: Colors.black)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
                    Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.id, this.note});
  final String id;
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(playlistsProvider.select((s) => s.playlists.where((x) => x.id == id).firstOrNull));
    if (p == null) return const SizedBox.shrink();
    final a = ref.watch(audioCenterProvider);
    final live = a.queueTag == p.id;
    return _Frame(
      icon: Icons.queue_music_rounded,
      color: p.colors.first,
      title: note == null ? p.name : '$note · ${p.name}',
      onAll: p.tracks.length > 4
          ? () => _sheet(
              context,
              p.name,
              (context, scroll) => ListView.builder(
                controller: scroll,
                itemCount: p.tracks.length,
                itemBuilder: (_, i) => TrackRow(
                  track: p.tracks[i],
                  index: i,
                  dense: true,
                  onTap: () => ref.read(playlistsProvider.notifier).play(p, start: i),
                ),
              ),
            )
          : null,
      child: Column(
        children: [
          InkWell(
            onTap: () => _push(context, PlaylistScreen(playlistId: p.id)),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Row(
                children: [
                  PlaylistCover(playlist: p, size: 72, radius: Radii.m),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (p.description.isNotEmpty) Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        Text(p.summary, style: context.text.labelSmall),
                      ],
                    ),
                  ),
                  if (p.tracks.isNotEmpty) ...[
                    IconButton(tooltip: 'Shuffle', icon: const Icon(Icons.shuffle_rounded), onPressed: () => ref.read(playlistsProvider.notifier).play(p, shuffle: true)),
                    IconButton.filled(
                      icon: Icon(live && a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      onPressed: () => live ? a.toggle() : ref.read(playlistsProvider.notifier).play(p),
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (final (i, t) in p.tracks.take(4).indexed)
            TrackRow(track: t, index: i, dense: true, onTap: () => ref.read(playlistsProvider.notifier).play(p, start: i)),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    if (t == null) return const SizedBox.shrink();
    return _Frame(
      icon: Icons.graphic_eq_rounded,
      color: AppColors.accent,
      title: a.playing ? 'Now playing' : 'Paused',
      onOpen: () => showAudioPlayer(context),
      openLabel: 'Player',
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          children: [
            Row(
              children: [
                AudioCoverArt(key: ValueKey(t.key), track: t, path: a.currentPath, size: 64),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      if (a.upNext.isNotEmpty) Text('Next: ${a.upNext.first.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            LinearProgressIndicator(
              value: a.duration.inMilliseconds == 0 ? 0 : (a.position.inMilliseconds / a.duration.inMilliseconds).clamp(0, 1).toDouble(),
              minHeight: 3,
              borderRadius: BorderRadius.circular(9),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: Icon(Icons.shuffle_rounded, color: a.shuffle ? AppColors.accent : AppColors.text3), onPressed: () => a.setShuffle(!a.shuffle)),
                IconButton(icon: const Icon(Icons.skip_previous_rounded), onPressed: a.previous),
                IconButton.filled(iconSize: 30, icon: Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded), onPressed: a.toggle),
                IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: a.hasNext ? a.next : null),
                IconButton(
                  icon: Icon(a.repeat == AudioRepeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: a.repeat == AudioRepeat.off ? AppColors.text3 : AppColors.accent),
                  onPressed: a.cycleRepeat,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _tile(BuildContext context, String v, String l) => Expanded(
  child: Container(
    padding: const EdgeInsets.all(Space.s),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900)), Text(l, style: context.text.labelSmall)]),
  ),
);

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final top = [for (final t in (data['top_tracks'] as List? ?? const [])) if (t is Map) t];
    final mins = (data['minutes_listened'] as num?)?.toInt() ?? 0;
    return _Frame(
      icon: Icons.insights_rounded,
      color: const Color(0xFF1DB954),
      title: 'Listening stats',
      onOpen: () => _push(context, const MusicStatsScreen()),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _tile(context, mins >= 60 ? '${(mins / 60).toStringAsFixed(1)}h' : '${mins}m', 'listened'),
                const SizedBox(width: Space.s),
                _tile(context, '${data['plays'] ?? 0}', 'plays'),
                const SizedBox(width: Space.s),
                _tile(context, '${data['day_streak'] ?? 0}', 'day streak'),
              ],
            ),
            for (final (i, t) in top.take(5).indexed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: context.text.labelLarge?.copyWith(color: AppColors.text3))),
                    Expanded(child: Text('${t['title']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${t['plays']}×', style: context.text.labelMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- marketplace ---------------------------------------------------------------------

class _ProductsCard extends ConsumerWidget {
  const _ProductsCard({required this.products, this.total});
  final List<Map<String, dynamic>> products;
  final int? total;

  Widget _card(BuildContext context, WidgetRef ref, Map<String, dynamic> p, {double width = 150}) {
    final key = '${p['item_key']}';
    final prod = ref.read(marketFeedProvider.notifier).byKey(key);
    final pic = prod?.pictures.firstOrNull;
    final legit = (p['legit_score'] as num?)?.toInt();
    return GestureDetector(
      onTap: () => _push(context, ProductScreen(productKey: key, product: prod)),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.m),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    pic == null ? Container(color: AppColors.surface2, child: Icon(Icons.sell_outlined, color: AppColors.text3)) : TgPicture(file: pic.file, mini: pic.mini, cacheWidth: 400),
                    if (legit != null) Positioned(left: 6, top: 6, child: LegitBadge(score: legit)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('${p['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
            if (p['price'] != null) Text('${p['price']}', style: TextStyle(fontWeight: FontWeight.w800, color: marketColor, fontSize: 13)),
            if (p['rating'] is num) Stars(rating: (p['rating'] as num).toDouble(), size: 11),
            Text('${p['store'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(marketFeedProvider);
    final m = ref.watch(marketProvider);
    return _Frame(
      icon: Icons.storefront_rounded,
      color: marketColor,
      title: products.length == 1 ? '${products.first['name']}' : '${total ?? products.length} products',
      onAll: products.length > 3
          ? () => _sheet(
              context,
              '${products.length} products',
              (context, scroll) => GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(Space.l),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.58),
                itemCount: products.length,
                itemBuilder: (context, i) => _card(context, ref, products[i], width: double.infinity),
              ),
            )
          : null,
      onOpen: () => _push(context, const MarketplaceScreen()),
      child: SizedBox(
        height: 260,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(Space.m),
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.m),
          itemBuilder: (context, i) {
            final key = '${products[i]['item_key']}';
            return Stack(
              children: [
                _card(context, ref, products[i]),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                    icon: Icon(m.inCart(key) ? Icons.shopping_cart_rounded : Icons.add_shopping_cart_rounded, size: 17, color: Colors.white),
                    onPressed: () async {
                      final p = await ref.read(marketFeedProvider.notifier).fetch(key);
                      if (p == null) return;
                      await ref.read(marketProvider.notifier).addToCart(MarketStore.snapshot(p, ref.read(marketProvider).listings[p.key]));
                      if (context.mounted) showSnack(context, 'Added to cart', icon: Icons.shopping_cart_outlined);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard({required this.items, required this.cart, this.totals = const {}});
  final List<Map<String, dynamic>> items;
  final bool cart;
  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(marketProvider);
    final saved = cart ? m.cart : m.wishlist;
    Widget row(SavedProduct s) => ListTile(
      dense: true,
      leading: SavedThumb(item: s, size: 44),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if (s.price != null) priceText(s.price, s.currency), s.store, if (cart && s.qty > 1) '× ${s.qty}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _push(context, ProductScreen(productKey: s.key)),
    );
    return _Frame(
      icon: cart ? Icons.shopping_cart_outlined : Icons.favorite_border_rounded,
      color: marketColor,
      title: cart ? 'Cart · ${m.cartCount} items' : 'Wishlist · ${saved.length}',
      onOpen: () => _push(context, MarketplaceScreen(initialTab: cart ? 3 : 2)),
      onAll: saved.length > 4 ? () => _sheet(context, cart ? 'Cart' : 'Wishlist', (context, scroll) => ListView(controller: scroll, children: [for (final s in saved) row(s)])) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved.isEmpty) Padding(padding: const EdgeInsets.all(Space.l), child: Text(cart ? 'The cart is empty' : 'The wishlist is empty', style: context.text.bodySmall)),
          for (final s in saved.take(4)) row(s),
          if (cart && m.cartTotals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
              child: Row(
                children: [
                  Text('Total', style: context.text.titleSmall),
                  const Spacer(),
                  Text(m.cartTotals.entries.map((e) => priceText(e.value, e.key)).join(' + '), style: TextStyle(fontWeight: FontWeight.w900, color: marketColor, fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- video ---------------------------------------------------------------------------

class _VideosCard extends ConsumerWidget {
  const _VideosCard({required this.keys, required this.rows, this.total, this.title});
  final List<String> keys;
  final List<Map<String, dynamic>> rows;
  final int? total;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(videoFeedProvider);
    final feed = ref.read(videoFeedProvider.notifier);
    final vids = [for (final k in keys) ?feed.byKey(k)];
    Widget fallback(Map<String, dynamic> r) => ListTile(
      leading: const Icon(Icons.movie_outlined),
      title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${r['channel'] ?? ''}'),
      onTap: () => _push(context, WatchScreen(videoKey: '${r['video_key']}')),
    );
    return _Frame(
      icon: Icons.movie_filter_rounded,
      color: moviesColor,
      title: title ?? '${total ?? rows.length} videos',
      onOpen: () => _push(context, const MoviesScreen()),
      onAll: rows.length > 3
          ? () => _sheet(
              context,
              title ?? 'Videos',
              (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(Space.l),
                children: [for (final v in vids) VideoTile(video: v), if (vids.isEmpty) for (final r in rows) fallback(r)],
              ),
            )
          : null,
      child: vids.isEmpty
          ? Column(children: [for (final r in rows.take(4)) fallback(r)])
          : SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(Space.m),
                itemCount: vids.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => openVideo(context, vids[i]),
                  child: SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VideoThumb(video: vids[i]),
                        const SizedBox(height: 6),
                        Text(vids[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ---- books ---------------------------------------------------------------------------

class _BooksCard extends ConsumerWidget {
  const _BooksCard({required this.ids, this.title});
  final List<String> ids;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(booksProvider);
    final books = [for (final id in ids) ?s.byId(id)];
    if (books.isEmpty) return const SizedBox.shrink();
    return _Frame(
      icon: Icons.auto_stories_rounded,
      color: booksColor,
      title: title ?? '${books.length} books',
      onOpen: () => _push(context, const BooksScreen()),
      child: SizedBox(
        height: 214,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(Space.m),
          itemCount: books.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.m),
          itemBuilder: (context, i) {
            final b = books[i];
            return GestureDetector(
              onTap: () => openBook(context, ref, b),
              onLongPress: () => openBookDetail(context, b),
              child: SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCover(book: b, width: 96),
                    const SizedBox(height: 4),
                    if (b.progress > 0) LinearProgressIndicator(value: b.progress, color: booksColor, minHeight: 3, borderRadius: BorderRadius.circular(9)),
                    Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FoundBooksCard extends ConsumerWidget {
  const _FoundBooksCard({required this.rows});
  final List<Map<String, dynamic>> rows;

  Widget _row(BuildContext context, WidgetRef ref, Map<String, dynamic> r) {
    final inLib = r['in_library'];
    final key = '${r['post_key']}';
    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: booksColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
        child: Text('${r['format'] ?? ''}'.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: booksColor)),
      ),
      title: Text('${r['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([r['size'], r['from']].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: inLib is String
          ? TextButton(
              onPressed: () {
                final b = ref.read(booksProvider).byId(inLib);
                if (b != null) openBook(context, ref, b);
              },
              child: const Text('Read'),
            )
          : IconButton(
              tooltip: 'Add to library',
              icon: Icon(Icons.library_add_rounded, color: booksColor),
              onPressed: () async {
                final k = parsePostKey(key);
                if (k == null) return;
                final post = ref.read(bookFeedProvider).bySource['${k.account}:${k.chatId}']?.where((p) => p.key == key).firstOrNull;
                if (post == null) return;
                await ref.read(booksProvider.notifier).addPost(post);
                if (context.mounted) showSnack(context, 'Added “${post.title}”', icon: Icons.library_add_check_rounded);
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(booksProvider);
    return _Frame(
      icon: Icons.explore_outlined,
      color: booksColor,
      title: '${rows.length} books found',
      onOpen: () => _push(context, const BooksScreen()),
      onAll: rows.length > 4 ? () => _sheet(context, 'Books found', (context, scroll) => ListView(controller: scroll, children: [for (final r in rows) _row(context, ref, r)])) : null,
      child: Column(children: [for (final r in rows.take(4)) _row(context, ref, r)]),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final today = (data['today_minutes'] as num?)?.toInt() ?? 0;
    final goal = (data['goal_minutes'] as num?)?.toInt() ?? 20;
    return _Frame(
      icon: Icons.insights_rounded,
      color: booksColor,
      title: 'Reading',
      onOpen: () => _push(context, const BooksScreen()),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: goal == 0 ? 0 : (today / goal).clamp(0, 1).toDouble(), minHeight: 8, color: booksColor, borderRadius: BorderRadius.circular(9)),
            const SizedBox(height: 4),
            Text('$today of $goal minutes today', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Row(
              children: [
                _tile(context, '${data['streak_days'] ?? 0}', 'day streak'),
                const SizedBox(width: Space.s),
                _tile(context, '${data['books_reading'] ?? 0}', 'reading'),
                const SizedBox(width: Space.s),
                _tile(context, '${data['books_finished'] ?? 0}', 'finished'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- gallery -------------------------------------------------------------------------

class _GalleryCard extends ConsumerWidget {
  const _GalleryCard({required this.keys});
  final List<String> keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(galleryFeedProvider);
    final feed = ref.read(galleryFeedProvider.notifier);
    final items = [for (final k in keys) ?feed.byKey(k)];
    if (items.isEmpty) return const SizedBox.shrink();
    Widget grid(List<GalleryItem> list, {ScrollController? scroll, bool shrink = true}) => GridView.builder(
      controller: scroll,
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: list.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => openGalleryViewer(context, items, items.indexOf(list[i])),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TgPicture(file: list[i].thumb, mini: list[i].mini, cacheWidth: 300),
            if (list[i].video) const Positioned(right: 4, bottom: 4, child: Icon(Icons.play_circle_fill_rounded, size: 16, color: Colors.white)),
          ],
        ),
      ),
    );
    return _Frame(
      icon: Icons.photo_library_rounded,
      color: galleryColor,
      title: '${items.length} photos and videos',
      onOpen: () => _push(context, const GalleryScreen()),
      onAll: items.length > 8 ? () => _sheet(context, 'Gallery', (context, scroll) => grid(items, scroll: scroll, shrink: false)) : null,
      child: grid(items.take(8).toList()),
    );
  }
}

class _AlbumsCard extends ConsumerWidget {
  const _AlbumsCard({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(galleryProvider).albums;
    return _Frame(
      icon: Icons.photo_album_outlined,
      color: galleryColor,
      title: '${albums.length} albums',
      onOpen: () => _push(context, const GalleryScreen()),
      child: Column(
        children: [
          for (final a in albums.take(6))
            ListTile(
              dense: true,
              leading: _mini(a.keys.isEmpty ? null : a.minis[a.keys.first], w: 44, h: 44, icon: Icons.photo_album_outlined),
              title: Text('${a.emoji.isEmpty ? '' : '${a.emoji} '}${a.name}'),
              subtitle: Text('${a.keys.length} items'),
              onTap: () => _push(context, AlbumScreen(albumId: a.id)),
            ),
        ],
      ),
    );
  }
}
