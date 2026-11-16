import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:uuid/uuid.dart';

import '../../app/start_page.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../ai/data/ai.dart';
import '../books/book_parsers.dart';
import '../books/books.dart';
import '../cinema/cinema.dart';
import '../custom_folders/custom_folders.dart';
import '../assistant/reminders.dart';
import '../gallery/gallery.dart';
import '../gallery/gallery_search.dart';
import '../opportunity/opportunity.dart';
import '../podcasts/podcast_store.dart';
import '../podcasts/podcast_tools.dart';
import '../marketplace/market.dart';
import '../movies/movies.dart';
import '../playlists/playlists.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_store.dart';
import 'activity_stats.dart';
import 'section_kit.dart';

/// Runs a Marketplace, Movies, Books, Gallery or sections tool for the
/// assistant. [account] is the Telegram account the call is for.
Future<Map<String, dynamic>> runSectionTool(Ref ref, String name, Map<String, dynamic> a, String account) async {
  try {
    return await _run(ref, name, a, account);
  } catch (e) {
    return {'error': '$e'};
  }
}

String _str(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();
int? _int(Map<String, dynamic> a, String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(_str(a, k));
bool? _bool(Map<String, dynamic> a, String k) => a[k] is bool ? a[k] as bool : null;
List<int> _ints(Map<String, dynamic> a, String k) => [for (final v in (a[k] as List? ?? const [])) if (v is num) v.toInt() else if (int.tryParse('$v') case final i?) i];
List<String> _strs(Map<String, dynamic> a, String k) => [for (final v in (a[k] as List? ?? const [])) if ('$v'.trim().isNotEmpty) '$v'.trim()];

/// Sources from chat ids, titled from [account]'s chats.
List<SourceRef> _refs(Ref ref, String account, List<int> ids) {
  final store = ref.read(telegramStoreFamily(account));
  return [for (final id in ids) SourceRef(account: account, chatId: id, title: store.chat(id)?.title ?? 'Chat $id')];
}

/// Cinema's catalogue for [account]: its channels (and the person's own
/// series') videos and poster posts loaded, older ones too with [more].
Future<List<CinemaTitle>> _cinemaTitles(Ref ref, String account, {bool more = false}) async {
  await ref.read(cinemaProvider.notifier).ready;
  final c = ref.read(cinemaProvider);
  final all = [for (final s in c.allSources) if (s.account == account) s];
  final mine = [for (final s in c.sources) if (s.account == account) s];
  final videos = ref.read(videoFeedProvider.notifier);
  final posters = ref.read(infoFeedProvider.notifier);
  await videos.loadAll(all);
  if (c.posterPosts) await posters.loadAll(mine);
  if (more) {
    await pooled(all, 3, (s) => videos.load(s, more: true));
    if (c.posterPosts) await pooled(mine, 3, (s) => posters.load(s, more: true));
  }
  return cinemaCatalog(ref.read(cinemaProvider), ref.read(videoFeedProvider), account, ref.read(infoFeedProvider));
}

/// A Cinema title as the assistant sees it in a list.
Map<String, dynamic> _describeTitle(CinemaTitle t, Map<String, WatchProgress> progress, List<String> watchlist) {
  final info = t.info;
  final watched = t.allVideos.where((v) => progress[v.key]?.finished ?? false).length;
  return {
    'title_key': t.key,
    'title': t.title,
    'kind': t.isShow ? 'show' : 'movie',
    'year': ?t.year,
    if (t.customId != null) 'own_series': true,
    if (t.isShow) ...{'seasons': t.seasonNumbers, 'episodes': t.episodeCount} else 'versions': t.versions.length,
    if (!t.hasVideo) 'no_video': 'Only a poster post so far; its links may have it.',
    if (watched > 0) 'watched_videos': watched,
    if (watchlist.contains(t.key)) 'in_watchlist': true,
    if (info != null && info.plot.isNotEmpty) 'plot': info.plot,
    if (info != null && info.ratings.isNotEmpty) 'ratings': {for (final r in info.ratings) r.$1: r.$2},
    if (info != null && info.genres.isNotEmpty) 'genres': info.genres,
    'updated': t.updated.toIso8601String().substring(0, 10),
  };
}

/// The common list/add/remove/hide/show/reorder of a section's sources.
Future<Map<String, dynamic>> _sources({
  required Ref ref,
  required Map<String, dynamic> a,
  required String account,
  required List<SourceRef> current,
  required Future<void> Function(List<SourceRef>) set,
  required Map<String, dynamic> Function(SourceRef) describe,
  required String plural,
}) async {
  final action = _str(a, 'action').isEmpty ? 'list' : _str(a, 'action');
  final ids = _ints(a, 'chat_ids');
  final out = <String, dynamic>{};
  switch (action) {
    case 'add':
      final have = {for (final s in current) s.key};
      final fresh = [for (final s in _refs(ref, account, ids)) if (have.add(s.key)) s];
      await set([...current, ...fresh]);
      out['added'] = [for (final s in fresh) s.title];
    case 'remove':
      final drop = ids.toSet();
      await set([for (final s in current) if (!(s.account == account && drop.contains(s.chatId))) s]);
      out['removed'] = ids.length;
    case 'hide' || 'show':
      final pick = ids.toSet();
      await set([for (final s in current) s.account == account && pick.contains(s.chatId) ? s.copyWith(hidden: action == 'hide') : s]);
    case 'reorder':
      final order = [for (final id in ids) ?current.where((s) => s.chatId == id).firstOrNull];
      await set([...order, ...current.where((s) => !order.contains(s))]);
  }
  return out;
}

Future<Map<String, dynamic>> _run(Ref ref, String name, Map<String, dynamic> a, String account) async {
  switch (name) {
    // ---- marketplace -------------------------------------------------------------
    case 'market_stores':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(marketProvider).sources, set: store.setSources, describe: (s) => s.describe(), plural: 'stores');
      final m = ref.read(marketProvider);
      final feed = ref.read(marketFeedProvider);
      return {
        ...out,
        'stores': [for (final s in m.sources) {...s.describe(), 'products_loaded': feed.bySource[s.key]?.length ?? 0}],
      };

    case 'market_search':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final m = ref.read(marketProvider);
      if (m.sources.isEmpty) return {'error': 'The Marketplace has no stores yet; add some with market_stores.'};
      final feed = ref.read(marketFeedProvider.notifier);
      final mine = [for (final s in m.sources) if (s.account == account) s];
      await feed.loadAll(mine);
      if (a['more'] == true) await pooled(mine, 3, (s) => feed.load(s, more: true));
      final chat = _int(a, 'chat_id');
      final sourceKey = chat == null ? null : '$account:$chat';
      final sort = MarketSort.values.asNameMap()[_str(a, 'sort')];
      final state = sort == null ? m : m.copyWith(sort: sort);
      var list = shopProducts(state, ref.read(marketFeedProvider), sourceKey: sourceKey, query: _str(a, 'query'), category: _str(a, 'category').isEmpty ? null : _str(a, 'category'));
      final minP = (a['min_price'] as num?)?.toDouble(), maxP = (a['max_price'] as num?)?.toDouble();
      if (minP != null || maxP != null) {
        list = [
          for (final x in list)
            if ((x.$2?.price ?? x.$1.guessPrice.amount) case final p? when (minP == null || p >= minP) && (maxP == null || p <= maxP)) x,
        ];
      }
      final limit = (_int(a, 'limit') ?? 20).clamp(1, 60);
      final cats = <String>{for (final x in list) if ((x.$2?.category ?? '').isNotEmpty) x.$2!.category};
      return {
        'products': [for (final x in list.take(limit)) describeProduct(x.$1, x.$2)],
        'total': list.length,
        if (cats.isNotEmpty) 'categories': cats.toList(),
        if (!m.ai.enabled) 'note': 'The AI tidy-up is off, so names and prices are guesses from the posts. market_ai_settings enabled:true turns it on; market_tidy runs it now.',
      };

    case 'market_item':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final key = _str(a, 'item_key');
      final p = await ref.read(marketFeedProvider.notifier).fetch(key);
      if (p == null) return {'error': 'No product $key.'};
      final hide = _bool(a, 'hide');
      if (hide != null) await store.setHidden(p.key, hide);
      final m = ref.read(marketProvider);
      return {
        'product': {...describeProduct(p, m.listings[p.key]), 'text': p.text},
        'in_cart': m.inCart(p.key),
        'in_wishlist': m.wished(p.key),
        'hidden': m.hidden.contains(p.key),
      };

    case 'market_cart':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final key = _str(a, 'item_key');
      switch (_str(a, 'action')) {
        case 'add':
          final p = await ref.read(marketFeedProvider.notifier).fetch(key);
          if (p == null) return {'error': 'No product $key.'};
          await store.addToCart(MarketStore.snapshot(p, ref.read(marketProvider).listings[p.key]), qty: (_int(a, 'quantity') ?? 1).clamp(1, 99));
        case 'remove':
          await store.removeFromCart(key);
        case 'set_quantity':
          await store.setQty(key, _int(a, 'quantity') ?? 1);
        case 'note':
          await store.setCartNote(key, _str(a, 'note'));
        case 'clear':
          await store.clearCart();
      }
      final m = ref.read(marketProvider);
      return {
        'cart': [for (final c in m.cart) c.describe()],
        'totals': {for (final e in m.cartTotals.entries) e.key.isEmpty ? 'unknown currency' : e.key: priceText(e.value, e.key)},
        'count': m.cartCount,
      };

    case 'market_wishlist':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final key = _str(a, 'item_key');
      switch (_str(a, 'action')) {
        case 'add':
          if (!ref.read(marketProvider).wished(key)) {
            final p = await ref.read(marketFeedProvider.notifier).fetch(key);
            if (p == null) return {'error': 'No product $key.'};
            await store.toggleWish(MarketStore.snapshot(p, ref.read(marketProvider).listings[p.key]));
          }
        case 'remove':
          await store.removeWish(key);
        case 'move_to_cart':
          final w = ref.read(marketProvider).wishlist.where((x) => x.key == key).firstOrNull;
          if (w == null) return {'error': '$key isn\'t in the wishlist.'};
          await store.addToCart(w);
          await store.removeWish(key);
        case 'clear':
          await store.clearWishlist();
      }
      final m = ref.read(marketProvider);
      return {'wishlist': [for (final w in m.wishlist) w.describe()], 'count': m.wishlist.length};

    case 'market_ai_settings':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      final c = ref.read(marketProvider).ai;
      await store.setAi(c.copyWith(
        enabled: _bool(a, 'enabled'),
        auto: _bool(a, 'auto'),
        model: _str(a, 'model').isEmpty ? null : _str(a, 'model'),
        name: _bool(a, 'name'),
        description: _bool(a, 'description'),
        price: _bool(a, 'price'),
        legit: _bool(a, 'legit'),
        reviews: _bool(a, 'reviews'),
        hideNonProducts: _bool(a, 'hide_non_products'),
        extra: a.containsKey('extra_instructions') ? _str(a, 'extra_instructions') : null,
      ));
      if (MarketSort.values.asNameMap()[_str(a, 'sort')] case final s?) await store.setSort(s);
      if (_int(a, 'columns') case final c?) await store.setColumns(c);
      final m = ref.read(marketProvider);
      return {
        ...m.ai.toJson(),
        'resolved_model': automationModel(ref.read(aiProvider), ref.read(settingsProvider), m.ai.model),
        'sort': m.sort.name,
        'columns': m.columns,
      };

    case 'market_tidy':
      final store = ref.read(marketProvider.notifier);
      await store.ready;
      switch (_str(a, 'action')) {
        case 'pause':
          store.pauseTidy();
        case 'resume':
          store.resumeTidy();
        case 'stop':
          store.stopTidy();
      }
      if (['status', 'pause', 'resume', 'stop'].contains(_str(a, 'action'))) {
        final j = store.job.value;
        return {'status': j.status.name, 'done': j.done, 'total': j.total, 'failed': j.failed, 'reading_now': j.current};
      }
      final limit = (_int(a, 'limit') ?? 16).clamp(1, 64);
      final keys = _strs(a, 'item_keys');
      final feed = ref.read(marketFeedProvider.notifier);
      List<Product> products;
      if (keys.isNotEmpty) {
        products = [for (final k in keys) ?await feed.fetch(k)];
      } else {
        final m = ref.read(marketProvider);
        final chat = _int(a, 'chat_id');
        final mine = [for (final s in m.sources) if (s.account == account && (chat == null || s.chatId == chat)) s];
        await feed.loadAll(mine);
        products = [for (final x in shopProducts(m, ref.read(marketFeedProvider), sourceKey: chat == null ? null : '$account:$chat')) x.$1].take(limit).toList();
      }
      final n = await store.enrich(products, force: a['force'] == true);
      final m = ref.read(marketProvider);
      return {'tidied': n, 'products': [for (final p in products.take(limit)) describeProduct(p, m.listings[p.key])]};

    // ---- movies ----------------------------------------------------------------------
    case 'movie_channels':
      final store = ref.read(moviesProvider.notifier);
      await store.ready;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(moviesProvider).sources, set: store.setSources, describe: (s) => s.describe(), plural: 'channels');
      final feed = ref.read(videoFeedProvider);
      return {...out, 'channels': [for (final s in ref.read(moviesProvider).sources) {...s.describe(), 'videos_loaded': feed.bySource[s.key]?.length ?? 0}]};

    case 'find_videos':
      final store = ref.read(moviesProvider.notifier);
      await store.ready;
      final m = ref.read(moviesProvider);
      if (m.sources.isEmpty) return {'error': 'Video has no channels yet; add some with movie_channels.'};
      final feed = ref.read(videoFeedProvider.notifier);
      final mine = [for (final s in m.sources) if (s.account == account) s];
      await feed.loadAll(mine);
      if (a['more'] == true) await pooled(mine, 3, (s) => feed.load(s, more: true));
      final chat = _int(a, 'chat_id');
      final list = allVideos(
        m,
        ref.read(videoFeedProvider),
        sourceKey: chat == null ? null : '$account:$chat',
        query: _str(a, 'query'),
        length: _str(a, 'length').isEmpty ? 'any' : _str(a, 'length'),
        sort: VideoSort.values.asNameMap()[_str(a, 'sort')],
      );
      final limit = (_int(a, 'limit') ?? 20).clamp(1, 60);
      return {'videos': [for (final v in list.take(limit)) v.describe(progress: m.progress[v.key])], 'total': list.length};

    case 'movie_library':
      final store = ref.read(moviesProvider.notifier);
      await store.ready;
      final key = _str(a, 'video_key');
      Future<Video?> video() => ref.read(videoFeedProvider.notifier).fetch(key);
      String? done;
      switch (_str(a, 'action')) {
        case 'add' || 'remove':
          final inList = ref.read(moviesProvider).inList(key);
          if ((_str(a, 'action') == 'add') != inList) {
            final v = await video();
            if (v == null && !inList) return {'error': 'No video $key.'};
            await store.toggleList(v == null ? SavedVideo(key: key, title: '', channel: '', addedAt: DateTime.now()) : SavedVideo.of(v));
          }
          done = _str(a, 'action') == 'add' ? 'added to My list' : 'removed from My list';
        case 'like' || 'unlike':
          if (ref.read(moviesProvider).liked.contains(key) != (_str(a, 'action') == 'like')) await store.toggleLike(key);
          done = _str(a, 'action') == 'like' ? 'liked' : 'unliked';
        case 'hide' || 'unhide':
          await store.setHidden(key, _str(a, 'action') == 'hide');
          done = _str(a, 'action') == 'hide' ? 'hidden' : 'shown';
        case 'forget':
          await store.clearProgress(key);
          done = 'removed from history';
        case 'clear_history':
          await store.clearHistory();
          done = 'history cleared';
        case 'settings':
          if (_bool(a, 'autoplay') case final v?) await store.setAutoplay(v);
          if (VideoSort.values.asNameMap()[_str(a, 'sort')] case final s?) await store.setSort(s);
      }
      final m = ref.read(moviesProvider);
      return {
        if (done != null) 'done': done,
        'my_list': [for (final s in m.myList.take(50)) s.describe()],
        'history': [
          for (final p in (m.progress.values.toList()..sort((x, y) => y.at.compareTo(x.at))).take(20))
            {'video_key': p.key, 'title': p.title, 'channel': p.channel, 'watched_percent': (p.fraction * 100).round(), 'when': p.at.toIso8601String().substring(0, 16)},
        ],
        'autoplay': m.autoplay,
        'sort': m.sort.name,
      };

    case 'video_stats':
      final stats = ref.read(activityStatsProvider('video').notifier);
      await stats.ready;
      final s = ref.read(activityStatsProvider('video'));
      final now = DateTime.now();
      final days = (_int(a, 'days') ?? 14).clamp(1, 60);
      int mins(int seconds) => (seconds / 60).round();
      return {
        'today_minutes': mins(s.today),
        'total_hours': double.parse((s.totalSeconds / 3600).toStringAsFixed(1)),
        'streak_days': s.streak,
        'per_day': {
          for (var i = days - 1; i >= 0; i--)
            ActivityStatsState.dayKey(now.subtract(Duration(days: i))): mins(s.days[ActivityStatsState.dayKey(now.subtract(Duration(days: i)))] ?? 0),
        },
        'most_watched': [
          for (final i in s.top.where((i) => i.seconds > 0).take(10))
            {'video_key': i.key, 'title': i.title, if (i.group.isNotEmpty) 'channel': i.group, 'minutes': mins(i.seconds), 'times_started': i.count},
        ],
        'top_channels': [for (final g in s.groups.take(8)) {'channel': g.$1, 'chat_id': g.$3, 'minutes': mins(g.$2)}],
        if (s.since != null) 'since': s.since!.toIso8601String().substring(0, 10),
      };

    // ---- cinema ----------------------------------------------------------------------
    case 'cinema_channels':
      final store = ref.read(cinemaProvider.notifier);
      await store.ready;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(cinemaProvider).sources, set: store.setSources, describe: (s) => s.describe(), plural: 'channels');
      if (_bool(a, 'poster_posts') case final v?) await store.setPosterPosts(v);
      final c = ref.read(cinemaProvider);
      final feed = ref.read(videoFeedProvider);
      return {
        ...out,
        'channels': [for (final s in c.sources) {...s.describe(), 'videos_loaded': feed.bySource[s.key]?.length ?? 0}],
        'poster_posts': c.posterPosts,
        'own_series': c.series.length,
      };

    case 'find_titles':
      await ref.read(cinemaProvider.notifier).ready;
      await ref.read(moviesProvider.notifier).ready;
      if (ref.read(cinemaProvider).allSources.isEmpty) return {'error': 'Cinema has no channels yet; add some with cinema_channels.'};
      final all = await _cinemaTitles(ref, account, more: a['more'] == true);
      final q = titleKey(_str(a, 'query'));
      final kind = _str(a, 'kind');
      final wl = ref.read(cinemaProvider).watchlist;
      final list = [
        for (final t in all)
          if ((q.isEmpty || titleKey(t.title).contains(q) || (t.info?.genres.any((g) => titleKey(g) == q) ?? false)) &&
              (kind.isEmpty || kind == 'any' || (kind == 'show') == t.isShow) &&
              (a['watchlist'] != true || wl.contains(t.key)) &&
              (a['with_video'] != true || t.hasVideo))
            t,
      ];
      final limit = (_int(a, 'limit') ?? 25).clamp(1, 80);
      final progress = ref.read(moviesProvider).progress;
      return {'titles': [for (final t in list.take(limit)) _describeTitle(t, progress, wl)], 'total': list.length};

    case 'cinema_title':
      await ref.read(cinemaProvider.notifier).ready;
      await ref.read(moviesProvider.notifier).ready;
      final key = _str(a, 'title_key');
      final all = await _cinemaTitles(ref, account);
      final t = all.where((x) => x.key == key).firstOrNull ?? all.where((x) => titleKey(x.title) == titleKey(key)).firstOrNull;
      if (t == null) return {'error': 'No title "$key" in Cinema; find_titles lists them.'};
      final progress = ref.read(moviesProvider).progress;
      final wl = ref.read(cinemaProvider).watchlist;
      TitleMeta? meta;
      if (a['details'] != false && (t.customId == null || t.posterOnline)) {
        try {
          meta = await ref.read(titleMetaProvider((t.kind, t.title, t.year)).future).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }
      WatchProgress? seen(Episode e) => [for (final x in e.versions) ?progress[x.key]].fold<WatchProgress?>(null, (p, q) => p == null || q.at.isAfter(p.at) ? q : p);
      Map<String, dynamic> ep(Episode e) {
        final v = e.best, p = seen(e);
        return {
          'season': e.season,
          'episode': e.number,
          'video_key': v.key,
          if (v.quality.isNotEmpty) 'quality': v.quality,
          if (v.seconds > 0) 'length_minutes': (v.seconds / 60).round(),
          if (e.versions.length > 1) 'copies': e.versions.length,
          if (p != null) 'watched_percent': (p.fraction * 100).round(),
        };
      }

      final season = _int(a, 'season');
      final episodes = [for (final s in t.seasonNumbers) ...t.episodesOf(s)];
      Episode? next;
      if (t.isShow && episodes.isNotEmpty) {
        final last = episodes.lastIndexWhere((e) => seen(e) != null);
        next = last < 0 ? episodes.first : ((seen(episodes[last])?.finished ?? false) ? (last + 1 < episodes.length ? episodes[last + 1] : null) : episodes[last]);
      }
      final info = t.info;
      return {
        ..._describeTitle(t, progress, wl),
        if (meta != null)
          'details': {
            if (meta.overview.isNotEmpty) 'overview': meta.overview,
            if (meta.genres.isNotEmpty) 'genres': meta.genres,
            'imdb_rating': ?meta.rating,
            if (meta.yearText.isNotEmpty) 'years': meta.yearText,
            'runtime_minutes': ?meta.runtime,
            'rated': ?meta.rated,
            if (meta.cast.isNotEmpty) 'cast': meta.cast,
            if (meta.director.isNotEmpty) 'director': meta.director,
            'network': ?meta.network,
            if (meta.status.isNotEmpty) 'status': meta.status,
            if (meta.awards.isNotEmpty) 'awards': meta.awards,
            'imdb_id': ?meta.imdbId,
            if (meta.trailer != null) 'trailer': 'https://youtu.be/${meta.trailer}',
          },
        if (info != null && info.links.isNotEmpty) 'links': [for (final l in info.links) {'label': l.$1, 'url': l.$2}],
        if (t.isShow) 'episodes': [for (final e in episodes) if (season == null || e.season == season) ep(e)].take(150).toList(),
        if (next != null) 'up_next': ep(next),
        if (!t.isShow) 'versions': [for (final v in [...t.versions]..sort((x, y) => y.height.compareTo(x.height))) v.describe(progress: progress[v.key])],
      };

    case 'cinema_watchlist':
      final store = ref.read(cinemaProvider.notifier);
      await store.ready;
      final key = _str(a, 'title_key');
      final action = _str(a, 'action').isEmpty ? 'list' : _str(a, 'action');
      if (action == 'add' || action == 'remove') {
        if (key.isEmpty) return {'error': 'Give the title_key (from find_titles).'};
        if (ref.read(cinemaProvider).watchlist.contains(key) != (action == 'add')) await store.toggleWatchlist(key);
      }
      final wl = ref.read(cinemaProvider).watchlist;
      final titles = {for (final t in await _cinemaTitles(ref, account)) t.key: t};
      final progress = ref.read(moviesProvider).progress;
      return {
        'watchlist': [for (final k in wl) titles[k] == null ? {'title_key': k, 'note': 'Not in the loaded catalogue.'} : _describeTitle(titles[k]!, progress, wl)],
        'count': wl.length,
      };

    case 'cinema_series':
      final store = ref.read(cinemaProvider.notifier);
      await store.ready;
      final action = _str(a, 'action').isEmpty ? 'list' : _str(a, 'action');
      final pick = _str(a, 'series');
      final found = ref.read(cinemaProvider).series.where((x) => x.id == pick || x.name.toLowerCase() == pick.toLowerCase()).firstOrNull;
      if (!{'list', 'create'}.contains(action) && found == null) return {'error': 'No series "$pick"; cinema_series list shows them.'};
      String? done;
      switch (action) {
        case 'create':
          final name = _str(a, 'name');
          if (name.isEmpty) return {'error': 'Give the series a name.'};
          await store.saveSeries(CustomSeries(id: const Uuid().v4(), name: name, year: _int(a, 'year'), sources: _refs(ref, account, _ints(a, 'chat_ids')), createdAt: DateTime.now()));
          done = 'created $name';
        case 'update':
          await store.saveSeries(found!.copyWith(
            name: _str(a, 'name').isEmpty ? null : _str(a, 'name'),
            year: _int(a, 'year'),
            sources: a.containsKey('chat_ids') ? _refs(ref, account, _ints(a, 'chat_ids')) : null,
          ));
          done = 'updated';
        case 'set_season':
          final n = _int(a, 'season') ?? 1;
          final had = found!.seasons.where((s) => s.number == n).firstOrNull;
          final season = CustomSeason(
            number: n,
            name: a.containsKey('season_name') ? _str(a, 'season_name') : (had?.name ?? ''),
            sources: a.containsKey('chat_ids') ? _refs(ref, account, _ints(a, 'chat_ids')) : (had?.sources ?? const []),
          );
          await store.saveSeries(found.copyWith(seasons: [for (final s in found.seasons) if (s.number != n) s, season]..sort((x, y) => x.number.compareTo(y.number))));
          done = 'season $n saved';
        case 'remove_season':
          final n = _int(a, 'season');
          await store.saveSeries(found!.copyWith(seasons: [for (final s in found.seasons) if (s.number != n) s]));
          done = 'season $n removed';
        case 'delete':
          await store.deleteSeries(found!.id);
          done = 'deleted ${found.name}';
      }
      return {
        'done': ?done,
        'series': [
          for (final c in ref.read(cinemaProvider).series)
            {
              'series_id': c.id,
              'title_key': c.key,
              'name': c.name,
              'year': ?c.year,
              'channels': [for (final s in c.sources) s.describe()],
              'seasons': [for (final s in c.seasons) {'season': s.number, if (s.name.isNotEmpty) 'name': s.name, 'channels': [for (final x in s.sources) x.describe()]}],
            },
        ],
      };

    // ---- books -------------------------------------------------------------------------
    case 'book_sources':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(booksProvider).sources, set: store.setSources, describe: (s) => s.describe(), plural: 'sources');
      final feed = ref.read(bookFeedProvider);
      return {...out, 'sources': [for (final s in ref.read(booksProvider).sources) {...s.describe(), 'books_found': feed.bySource[s.key]?.length ?? 0}]};

    case 'find_books':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final s = ref.read(booksProvider);
      if (s.sources.isEmpty) return {'error': 'The Library has no sources yet; add channels with book_sources.'};
      final chat = _int(a, 'chat_id');
      final q = _str(a, 'query');
      final feed = ref.read(bookFeedProvider.notifier);
      final mine = [for (final x in s.sources) if (x.account == account && (chat == null || x.chatId == chat)) x];
      if (q.isNotEmpty) {
        // A search reads each source for the words, not only what's loaded.
        await pooled(mine, 3, (x) => feed.load(x, query: q));
      } else {
        await feed.loadAll(mine);
      }
      final fmt = _str(a, 'format').toLowerCase();
      final list = [
        for (final p in feed.all(mine))
          if ((q.isEmpty || '${p.title} ${p.fileName} ${p.caption}'.toLowerCase().contains(q.toLowerCase())) && (fmt.isEmpty || p.format == fmt)) p,
      ];
      final limit = (_int(a, 'limit') ?? 25).clamp(1, 80);
      return {
        'books': [for (final p in list.take(limit)) {...p.describe(), 'in_library': s.byPost(p.key)?.id ?? false}],
        'total': list.length,
      };

    case 'list_books':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final s = ref.read(booksProvider);
      final status = ReadStatus.values.asNameMap()[_str(a, 'status')];
      final shelf = _str(a, 'shelf');
      final q = _str(a, 'query').toLowerCase();
      final list = [
        for (final b in s.sorted)
          if ((status == null || b.status == status) &&
              (shelf.isEmpty || b.shelves.any((x) => x.toLowerCase() == shelf.toLowerCase())) &&
              (a['favorite'] != true || b.favorite) &&
              (q.isEmpty || '${b.title} ${b.author}'.toLowerCase().contains(q)))
            b,
      ];
      final limit = (_int(a, 'limit') ?? 40).clamp(1, 200);
      return {'books': [for (final b in list.take(limit)) b.describe()], 'shelves': s.shelves, 'total': list.length};

    case 'add_book':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final shelf = _str(a, 'shelf').isEmpty ? null : _str(a, 'shelf');
      Book b;
      if (_str(a, 'file_path').isNotEmpty) {
        final path = _str(a, 'file_path');
        if (!await File(path).exists()) return {'error': 'No file at $path.'};
        b = await store.importFile(path, shelf: shelf);
      } else {
        var key = _str(a, 'post_key');
        if (key.isEmpty) {
          final c = _int(a, 'chat_id'), m = _int(a, 'message_id');
          if (c == null || m == null) return {'error': 'Give post_key, chat_id + message_id, or file_path.'};
          key = postKey(account, c, m);
        }
        final k = parsePostKey(key)!;
        final client = ref.read(telegramClientFamily(k.account));
        final msg = await client.send<td.Message>(td.GetMessage(chatId: k.chatId, messageId: k.messageId), limited: true);
        final post = BookPost.fromMessage(msg, k.account, ref.read(telegramStoreFamily(k.account)).chat(k.chatId)?.title ?? '');
        if (post == null) return {'error': 'That message has no book file.'};
        b = await store.addPost(post, download: a['download'] == true, shelf: shelf);
      }
      return {'added': {'book_id': b.id, 'title': b.title, 'format': b.format, 'downloaded': b.downloaded}};

    case 'update_book':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final b = store.find(_str(a, 'book'));
      if (b == null) return {'error': 'No book "${_str(a, 'book')}" in the Library.'};
      if (ReadStatus.values.asNameMap()[_str(a, 'status')] case final st?) await store.setStatus(b.id, st);
      if (_bool(a, 'favorite') case final v?) await store.setFavorite(b.id, v);
      if (_int(a, 'rating') case final r?) await store.setRating(b.id, r);
      var shelves = a.containsKey('shelves') ? _strs(a, 'shelves') : [...store.find(b.id)!.shelves];
      shelves = [...shelves, for (final x in _strs(a, 'add_shelves')) if (!shelves.contains(x)) x];
      shelves.removeWhere(_strs(a, 'remove_shelves').contains);
      await store.setShelves(b.id, shelves);
      await store.update(b.id, (x) => x.copyWith(
        title: _str(a, 'title').isEmpty ? null : _str(a, 'title'),
        author: a.containsKey('author') ? _str(a, 'author') : null,
        notes: a.containsKey('notes') ? _str(a, 'notes') : null,
      ));
      return {'updated': ref.read(booksProvider).byId(b.id)!.describe()};

    case 'book_shelves':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final n = _str(a, 'name');
      switch (_str(a, 'action')) {
        case 'create':
          await store.addShelf(n);
        case 'rename':
          await store.renameShelf(n, _str(a, 'new_name'));
        case 'delete':
          await store.deleteShelf(n);
        case 'reorder':
          final s = ref.read(booksProvider);
          final order = [for (final x in _strs(a, 'order')) if (s.shelves.contains(x)) x];
          for (var i = 0; i < order.length; i++) {
            await store.moveShelf(ref.read(booksProvider).shelves.indexOf(order[i]), i);
          }
      }
      final s = ref.read(booksProvider);
      return {'shelves': [for (final x in s.shelves) {'name': x, 'books': [for (final b in s.books) if (b.shelves.contains(x)) b.title]}]};

    case 'book_notes':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      if (_str(a, 'action') == 'delete') {
        final id = _str(a, 'id');
        await store.removeHighlight(id);
        await store.removeBookmark(id);
        return {'deleted': id};
      }
      final s = ref.read(booksProvider);
      final b = _str(a, 'book').isEmpty ? null : store.find(_str(a, 'book'));
      String title(String id) => s.byId(id)?.title ?? '';
      return {
        'highlights': [for (final h in s.highlights) if (b == null || h.bookId == b.id) {'id': h.id, 'book': title(h.bookId), 'text': h.text, if (h.note.isNotEmpty) 'note': h.note, 'date': h.at.toIso8601String().substring(0, 10)}],
        'bookmarks': [for (final m in s.bookmarks) if (b == null || m.bookId == b.id) {'id': m.id, 'book': title(m.bookId), 'label': m.label, if (m.excerpt.isNotEmpty) 'excerpt': m.excerpt}],
      };

    case 'read_book_text':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      var b = store.find(_str(a, 'book'));
      if (b == null) return {'error': 'No book "${_str(a, 'book')}" in the Library.'};
      if (!b.downloaded) b = await store.download(b.id);
      if (!readableFormats.contains(b.format)) return {'error': '${b.format.toUpperCase()} books can\'t be read as text here; the user can open it in the PDF viewer.'};
      final d = await store.openDoc(b);
      final max = (_int(a, 'max_chars') ?? 12000).clamp(1000, 40000);
      final chapter = _int(a, 'chapter');
      final pct = (a['from_percent'] as num?)?.toDouble();
      var start = 0;
      var sectionIndex = 0;
      if (chapter != null) {
        sectionIndex = (chapter - 1).clamp(0, d.sections.length - 1);
        start = d.sections[sectionIndex].start;
      } else if (pct != null) {
        final target = (d.wordCount * pct / 100).round();
        start = d.wordOffsets.indexWhere((w) => w >= target).clamp(0, d.blocks.length);
        sectionIndex = d.sectionOf(start);
      }
      final buf = StringBuffer();
      var i = start;
      for (; i < d.blocks.length && buf.length < max; i++) {
        final blk = d.blocks[i];
        if (blk.text.isEmpty) continue;
        buf.writeln(blk.type == BlockType.heading ? '\n## ${blk.text}\n' : blk.text);
      }
      return {
        'book': b.describe(),
        if (chapter == null && pct == null) 'contents': [for (final (n, s) in d.sections.indexed) '${n + 1}. ${s.title}'],
        'chapter': d.sections[sectionIndex].title,
        'text': buf.toString(),
        'progress_percent': d.wordCount == 0 ? 0 : (d.wordOffsets[i.clamp(0, d.blocks.length)] * 100 / d.wordCount).round(),
        if (i < d.blocks.length) 'next_chapter': d.sectionOf(i) + 1 + (d.sections[d.sectionOf(i)].start < i ? 1 : 0),
      };

    case 'reading_stats':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      if (_int(a, 'goal_minutes') case final g?) await store.setGoal(g);
      final s = ref.read(booksProvider);
      final now = DateTime.now();
      final top = [...s.books]..sort((x, y) => y.minutes.compareTo(x.minutes));
      return {
        'today_minutes': s.todayMinutes,
        'goal_minutes': s.goal,
        'streak_days': s.streak,
        'last_14_days': {for (var i = 13; i >= 0; i--) BooksState.dayKey(now.subtract(Duration(days: i))): s.days[BooksState.dayKey(now.subtract(Duration(days: i)))] ?? 0},
        'books_finished': s.books.where((b) => b.status == ReadStatus.finished).length,
        'books_reading': s.books.where((b) => b.status == ReadStatus.reading).length,
        'most_read': [for (final b in top.where((b) => b.minutes > 0).take(8)) {'title': b.title, 'minutes': b.minutes}],
      };

    case 'remove_book':
      final store = ref.read(booksProvider.notifier);
      await store.ready;
      final b = store.find(_str(a, 'book'));
      if (b == null) return {'error': 'No book "${_str(a, 'book')}" in the Library.'};
      await store.remove(b.id);
      return {'removed': b.title};

    // ---- gallery -------------------------------------------------------------------------
    case 'gallery_sources':
      final store = ref.read(galleryProvider.notifier);
      await store.ready;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(galleryProvider).sources, set: store.setSources, describe: (s) => s.describe(), plural: 'sources');
      final feed = ref.read(galleryFeedProvider);
      return {...out, 'sources': [for (final s in ref.read(galleryProvider).sources) {...s.describe(), 'items_loaded': feed.bySource[s.key]?.length ?? 0}]};

    case 'gallery_items':
      final store = ref.read(galleryProvider.notifier);
      await store.ready;
      final g = ref.read(galleryProvider);
      final limit = (_int(a, 'limit') ?? 30).clamp(1, 100);
      final feed = ref.read(galleryFeedProvider.notifier);
      List<GalleryItem> list;
      final album = _str(a, 'album');
      if (album.isNotEmpty) {
        final al = store.album(album);
        if (al == null) return {'error': 'No album "$album".'};
        list = await feed.fetchMany(al.keys.take(limit).toList());
      } else if (a['favorites'] == true) {
        list = await feed.fetchMany(g.favorites.take(limit).toList());
      } else if (a['hidden'] == true) {
        list = await feed.fetchMany(g.hidden.take(limit).toList());
      } else {
        final mine = [for (final s in g.sources) if (s.account == account) s];
        if (mine.isEmpty) return {'error': 'The Gallery has no sources yet; add some with gallery_sources.'};
        await feed.loadAll(mine);
        if (a['more'] == true) await pooled(mine, 3, (s) => feed.load(s, more: true));
        final chat = _int(a, 'chat_id');
        final type = _str(a, 'type');
        list = galleryItems(g, ref.read(galleryFeedProvider), sourceKey: chat == null ? null : '$account:$chat', videos: type.isEmpty ? null : type == 'video');
      }
      return {'items': [for (final i in list.take(limit)) {...i.describe(), if (g.isFavorite(i.key)) 'favorite': true}], 'total': list.length};

    case 'gallery_albums':
      final store = ref.read(galleryProvider.notifier);
      await store.ready;
      final keys = _strs(a, 'item_keys');
      final out = <String, dynamic>{};
      switch (_str(a, 'action')) {
        case 'create':
          final items = await ref.read(galleryFeedProvider.notifier).fetchMany(keys);
          final al = await store.createAlbum(_str(a, 'name'), emoji: _str(a, 'emoji'), items: items);
          out['album'] = al.describe();
        case 'rename':
          final al = store.album(_str(a, 'album'));
          if (al == null) return {'error': 'No album "${_str(a, 'album')}".'};
          await store.updateAlbum(al.id, (x) => x.copyWith(name: _str(a, 'name').isEmpty ? null : _str(a, 'name'), emoji: a.containsKey('emoji') ? _str(a, 'emoji') : null));
        case 'delete':
          final al = store.album(_str(a, 'album'));
          if (al == null) return {'error': 'No album "${_str(a, 'album')}".'};
          await store.deleteAlbum(al.id);
        case 'add':
          final al = store.album(_str(a, 'album'));
          if (al == null) return {'error': 'No album "${_str(a, 'album')}".'};
          final items = await ref.read(galleryFeedProvider.notifier).fetchMany(keys);
          out['added'] = await store.addToAlbum(al.id, items);
        case 'remove':
          final al = store.album(_str(a, 'album'));
          if (al == null) return {'error': 'No album "${_str(a, 'album')}".'};
          await store.removeFromAlbum(al.id, keys);
          out['removed'] = keys.length;
        case 'reorder':
          final order = [for (final x in _strs(a, 'order')) ?store.album(x)];
          for (var i = 0; i < order.length; i++) {
            await store.moveAlbum(ref.read(galleryProvider).albums.indexWhere((x) => x.id == order[i].id), i);
          }
      }
      return {...out, 'albums': [for (final al in ref.read(galleryProvider).albums) al.describe()]};

    case 'gallery_mark':
      final store = ref.read(galleryProvider.notifier);
      await store.ready;
      final keys = _strs(a, 'item_keys');
      if (_bool(a, 'favorite') case final v?) await store.setFavoriteKeys(keys, v);
      if (_bool(a, 'hidden') case final v?) await store.setHiddenKeys(keys, v);
      final g = ref.read(galleryProvider);
      return {'changed': keys.length, 'favorites': g.favorites.length, 'hidden': g.hidden.length};

    case 'gallery_search':
      final store = ref.read(galleryProvider.notifier);
      await store.ready;
      final idx = ref.read(galleryIndexProvider.notifier);
      await idx.ready;
      final g = ref.read(galleryProvider);
      final mine = [for (final s in g.sources) if (s.account == account) s];
      if (mine.isEmpty) return {'error': 'The Gallery has no sources yet; add some with gallery_sources.'};
      await ref.read(galleryFeedProvider.notifier).loadAll(mine);
      final q = _str(a, 'query');
      var deepAdded = 0;
      if (a['deep'] == true && q.isNotEmpty) deepAdded = await deepSearchGallery(ref.read, mine, q);
      final chat = _int(a, 'chat_id');
      final all = galleryItems(g, ref.read(galleryFeedProvider));
      final notes = ref.read(galleryIndexProvider).notes;
      final hits = searchGallery(
        g,
        all,
        notes,
        query: q,
        videos: _str(a, 'type').isEmpty ? null : _str(a, 'type') == 'video',
        since: DateTime.tryParse(_str(a, 'since')),
        until: DateTime.tryParse(_str(a, 'until')),
        sourceKey: chat == null ? null : '$account:$chat',
        shape: PhotoShape.values.asNameMap()[_str(a, 'shape')],
        favorites: a['favorites'] == true,
      );
      final limit = (_int(a, 'limit') ?? 30).clamp(1, 100);
      final photos = all.where((i) => !i.video).length;
      final indexed = all.where((i) => !i.video && notes.containsKey(i.key)).length;
      return {
        'items': [
          for (final h in hits.take(limit))
            {
              ...h.item.describe(),
              if (h.seen.isNotEmpty) 'matched_in': h.seen,
              if (notes[h.item.key] case final n?) 'seen': n.description,
              if (g.isFavorite(h.item.key)) 'favorite': true,
            },
        ],
        'total': hits.length,
        'indexed': '$indexed of $photos loaded photos',
        if (deepAdded > 0) 'found_in_older_posts': deepAdded,
        if (q.isNotEmpty && indexed < photos) 'note': 'Only $indexed of $photos photos are indexed by what they show; gallery_index run indexes more (uses a vision model).',
      };

    case 'gallery_index':
      final idx = ref.read(galleryIndexProvider.notifier);
      await idx.ready;
      switch (_str(a, 'action')) {
        case 'run':
          final g = ref.read(galleryProvider);
          final mine = [for (final s in g.sources) if (s.account == account) s];
          await ref.read(galleryFeedProvider.notifier).loadAll(mine);
          final photos = [for (final i in galleryItems(g, ref.read(galleryFeedProvider))) if (!i.video) i];
          final n = await idx.run(photos, limit: (_int(a, 'limit') ?? 60).clamp(1, 400));
          final st = ref.read(galleryIndexProvider);
          return {'described_now': n, 'indexed': st.notes.length, 'model': st.model, 'error': ?st.error};
        case 'stop':
          idx.stop();
        case 'forget':
          await idx.forget();
      }
      final st = ref.read(galleryIndexProvider);
      final g = ref.read(galleryProvider);
      return {
        'indexed': st.notes.length,
        'loaded_photos': galleryItems(g, ref.read(galleryFeedProvider)).where((i) => !i.video).length,
        'running': st.running,
        if (st.running) ...{'done': st.done, 'total': st.total},
        'model': st.model.isEmpty ? (visionModel(ref) ?? 'none that can see pictures') : st.model,
        'error': ?st.error,
      };

    // ---- events & jobs -------------------------------------------------------------------
    case 'opportunity_sources':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      final kind = _str(a, 'kind') == 'jobs' ? OppKind.job : OppKind.event;
      final out = await _sources(ref: ref, a: a, account: account, current: ref.read(opportunityProvider).sourcesOf(kind), set: (v) => store.setSources(kind, v), describe: (s) => s.describe(), plural: 'sources');
      final feed = ref.read(oppFeedProvider(kind));
      return {...out, 'kind': kind.label, 'sources': [for (final s in ref.read(opportunityProvider).sourcesOf(kind)) {...s.describe(), 'posts': feed.bySource[s.key]?.length ?? 0}]};

    case 'find_events':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      final o = ref.read(opportunityProvider);
      if (o.eventSources.isEmpty) return {'error': 'No event channels yet; add some with opportunity_sources (kind events).'};
      final feed = ref.read(oppFeedProvider(OppKind.event).notifier);
      final mine = [for (final s in o.eventSources) if (s.account == account) s];
      await feed.loadAll(mine);
      if (a['more'] == true) await pooled(mine, 3, (s) => feed.load(s, more: true));
      final chat = _int(a, 'chat_id');
      final list = allEvents(
        ref.read(opportunityProvider),
        ref.read(oppFeedProvider(OppKind.event)),
        sourceKey: chat == null ? null : '$account:$chat',
        query: _str(a, 'query'),
        when: EventWhen.values.asNameMap()[_str(a, 'when')] ?? EventWhen.upcoming,
        day: DateTime.tryParse(_str(a, 'date')),
        online: _bool(a, 'online'),
        freeOnly: a['free'] == true,
        category: _str(a, 'category').isEmpty ? null : _str(a, 'category'),
      );
      final limit = (_int(a, 'limit') ?? 20).clamp(1, 60);
      final now = ref.read(opportunityProvider);
      return {
        'events': [for (final e in list.take(limit)) e.describe(saved: now.savedEvent(e.key))],
        'total': list.length,
        'categories': {for (final e in list) if (e.category.isNotEmpty) e.category}.toList(),
        if (!now.ai.enabled) 'note': 'AI reading is off, so dates are guessed from the words; opportunity_settings ai_enabled true reads posts properly.',
      };

    case 'event_plan':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      final key = _str(a, 'event_key');
      final action = _str(a, 'action').isEmpty ? 'list' : _str(a, 'action');
      String? done;
      Future<EventView?> view() async {
        final p = await ref.read(oppFeedProvider(OppKind.event).notifier).fetch(key);
        return p == null ? null : EventView(p, ref.read(opportunityProvider).events[p.key]);
      }

      switch (action) {
        case 'going' || 'interested' || 'went':
          final e = await view();
          if (e == null) return {'error': 'No event $key.'};
          await store.saveEvent(e, EventStatus.values.byName(action));
          done = 'marked $action';
        case 'remove':
          for (final id in ref.read(opportunityProvider).savedEvent(key)?.reminders ?? const <String>[]) {
            await ref.read(reminderStoreProvider.notifier).remove(id);
          }
          await store.unsaveEvent(key);
          done = 'removed';
        case 'note':
          if (ref.read(opportunityProvider).savedEvent(key) == null) {
            final e = await view();
            if (e == null) return {'error': 'No event $key.'};
            await store.saveEvent(e, EventStatus.interested);
          }
          await store.updateSavedEvent(key, (x) => x.copyWith(note: _str(a, 'note')));
          done = 'note saved';
        case 'remind':
          final e = await view();
          if (e == null) return {'error': 'No event $key.'};
          final start = e.start;
          if (start == null) return {'error': 'That event has no date to remind before.'};
          final at = start.subtract(Duration(minutes: (_int(a, 'minutes_before') ?? 60).clamp(0, 60 * 24 * 14)));
          final r = await ref.read(reminderStoreProvider.notifier).add(text: '📅 ${e.title} · starts ${start.toIso8601String().substring(11, 16)}${e.place.isEmpty ? '' : ' at ${e.place}'}', at: at);
          if (ref.read(opportunityProvider).savedEvent(key) == null) await store.saveEvent(e, EventStatus.interested);
          await store.updateSavedEvent(key, (x) => x.copyWith(reminders: [...x.reminders, r.id]));
          done = 'reminder set for ${at.toIso8601String().substring(0, 16)}';
      }
      return {
        'done': ?done,
        'my_events': [for (final e in ref.read(opportunityProvider).savedEvents) e.describe()],
      };

    case 'find_jobs':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      final o = ref.read(opportunityProvider);
      if (o.jobSources.isEmpty) return {'error': 'No job channels yet; add some with opportunity_sources (kind jobs).'};
      final feed = ref.read(oppFeedProvider(OppKind.job).notifier);
      final mine = [for (final s in o.jobSources) if (s.account == account) s];
      await feed.loadAll(mine);
      if (a['more'] == true) await pooled(mine, 3, (s) => feed.load(s, more: true));
      final chat = _int(a, 'chat_id');
      final list = allJobs(
        ref.read(opportunityProvider),
        ref.read(oppFeedProvider(OppKind.job)),
        sourceKey: chat == null ? null : '$account:$chat',
        query: _str(a, 'query'),
        workplace: _str(a, 'workplace').isEmpty ? null : _str(a, 'workplace'),
        type: _str(a, 'type').isEmpty ? null : _str(a, 'type'),
        level: _str(a, 'level').isEmpty ? null : _str(a, 'level'),
        category: _str(a, 'category').isEmpty ? null : _str(a, 'category'),
        closingWithinDays: _int(a, 'closing_within_days'),
        minSalary: (a['min_salary'] as num?)?.toDouble(),
        hideClosed: a['include_closed'] != true,
        sort: JobSort.values.asNameMap()[_str(a, 'sort')] ?? JobSort.newest,
      );
      final limit = (_int(a, 'limit') ?? 20).clamp(1, 60);
      final now = ref.read(opportunityProvider);
      return {
        'jobs': [for (final j in list.take(limit)) j.describe(tracked: now.trackedJob(j.key))],
        'total': list.length,
        if (!now.ai.enabled) 'note': 'AI reading is off, so titles, pay and deadlines are guesses; opportunity_settings ai_enabled true reads posts properly.',
        if (now.ai.enabled && now.profile.isEmpty) 'tip': 'With a job profile (opportunity_settings profile) each job gets a match score.',
      };

    case 'job_tracker':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      final key = _str(a, 'job_key');
      final action = _str(a, 'action').isEmpty ? 'list' : _str(a, 'action');
      String? done;
      Future<JobView?> view() async {
        final p = await ref.read(oppFeedProvider(OppKind.job).notifier).fetch(key);
        return p == null ? null : JobView(p, ref.read(opportunityProvider).jobs[p.key]);
      }

      switch (action) {
        case 'save' || 'applied' || 'interview' || 'offer' || 'rejected':
          final status = action == 'save' ? JobStatus.saved : JobStatus.values.byName(action);
          if (ref.read(opportunityProvider).trackedJob(key) != null) {
            await store.updateTracked(key, (x) => x.copyWith(status: status, appliedAt: status == JobStatus.applied && x.appliedAt == null ? DateTime.now() : null));
          } else {
            final j = await view();
            if (j == null) return {'error': 'No job $key.'};
            await store.track(j, status);
          }
          done = 'moved to ${status.label}';
        case 'remove':
          for (final id in ref.read(opportunityProvider).trackedJob(key)?.reminders ?? const <String>[]) {
            await ref.read(reminderStoreProvider.notifier).remove(id);
          }
          await store.untrack(key);
          done = 'removed';
        case 'note':
          if (ref.read(opportunityProvider).trackedJob(key) == null) {
            final j = await view();
            if (j == null) return {'error': 'No job $key.'};
            await store.track(j, JobStatus.saved);
          }
          await store.updateTracked(key, (x) => x.copyWith(note: _str(a, 'note')));
          done = 'note saved';
        case 'remind':
          final j = await view();
          if (j == null) return {'error': 'No job $key.'};
          final d = j.deadline;
          if (d == null) return {'error': 'That job has no deadline to remind before.'};
          var at = DateTime(d.year, d.month, d.day - 1, 9);
          if (!at.isAfter(DateTime.now())) at = DateTime.now().add(const Duration(hours: 1));
          final r = await ref.read(reminderStoreProvider.notifier).add(text: '💼 Apply for ${j.title}${j.company.isEmpty ? '' : ' at ${j.company}'} before ${d.toIso8601String().substring(0, 10)}', at: at);
          if (ref.read(opportunityProvider).trackedJob(key) == null) await store.track(j, JobStatus.saved);
          await store.updateTracked(key, (x) => x.copyWith(reminders: [...x.reminders, r.id]));
          done = 'reminder set for ${at.toIso8601String().substring(0, 16)}';
      }
      final o = ref.read(opportunityProvider);
      final only = JobStatus.values.asNameMap()[_str(a, 'status')];
      return {
        'done': ?done,
        'applications': [for (final t in o.tracked) if (only == null || t.status == only) t.describe()],
        'counts': {for (final s in JobStatus.values) s.name: o.tracked.where((t) => t.status == s).length},
      };

    case 'opportunity_settings':
      final store = ref.read(opportunityProvider.notifier);
      await store.ready;
      switch (_str(a, 'action')) {
        case 'pause':
          store.pauseTidy();
        case 'resume':
          store.resumeTidy();
        case 'stop':
          store.stopTidy();
      }
      if (['status', 'pause', 'resume', 'stop'].contains(_str(a, 'action'))) {
        final j = store.readJob.value;
        return {
          'status': j.status.name,
          'done': j.done,
          'total': j.total,
          'failed': j.failed,
          'reading_now': j.current,
          'recent': [for (final l in j.log.take(10)) {'title': l.name, 'kind': l.kind.single, if (l.line.isNotEmpty) 'result': l.line, 'trust_score': ?l.legit, 'error': ?l.error, if (l.skipped) 'hidden': true}],
        };
      }
      final c = ref.read(opportunityProvider).ai;
      await store.setAi(c.copyWith(
        enabled: _bool(a, 'ai_enabled'),
        auto: _bool(a, 'auto'),
        hideOthers: _bool(a, 'hide_others'),
        model: _str(a, 'model').isEmpty ? null : _str(a, 'model'),
        eventSummary: _bool(a, 'event_summary'),
        eventPlace: _bool(a, 'event_place'),
        eventPrice: _bool(a, 'event_price'),
        eventLink: _bool(a, 'event_link'),
        eventTags: _bool(a, 'event_tags'),
        jobPay: _bool(a, 'job_pay'),
        jobApply: _bool(a, 'job_apply'),
        jobRequirements: _bool(a, 'job_requirements'),
        jobSummary: _bool(a, 'job_summary'),
        jobMatch: _bool(a, 'job_match'),
        jobTrust: _bool(a, 'job_trust'),
        extra: a.containsKey('extra_instructions') ? _str(a, 'extra_instructions') : null,
      ));
      if (a.containsKey('profile')) await store.setProfile(_str(a, 'profile'));
      if (a.containsKey('city')) await store.setCity(_str(a, 'city'));
      int? read;
      if (_str(a, 'read').isNotEmpty) {
        if (!ref.read(opportunityProvider).ai.enabled) return {'error': 'Turn AI reading on first (ai_enabled true).'};
        final kind = _str(a, 'read') == 'jobs' ? OppKind.job : OppKind.event;
        final o = ref.read(opportunityProvider);
        final mine = [for (final s in o.sourcesOf(kind)) if (s.account == account) s];
        await ref.read(oppFeedProvider(kind).notifier).loadAll(mine);
        final feed = ref.read(oppFeedProvider(kind));
        read = await store.read(kind, [for (final s in mine) ...?feed.bySource[s.key]], force: a['force'] == true);
      }
      final o = ref.read(opportunityProvider);
      return {
        ...o.ai.toJson(),
        'ai_enabled': o.ai.enabled,
        'auto': o.ai.auto,
        'hide_others': o.ai.hideOthers,
        'model': o.ai.model,
        'resolved_model': automationModel(ref.read(aiProvider), ref.read(settingsProvider), o.ai.model),
        'profile': o.profile.isEmpty ? '(not set)' : o.profile,
        if (o.city.isNotEmpty) 'city': o.city,
        'read': ?read,
        'events_read': o.events.length,
        'jobs_read': o.jobs.length,
      };

    // ---- sections ------------------------------------------------------------------------
    case 'app_sections':
      // In the drawer's order.
      final setters = <String, Future<void> Function(bool)>{
        'explore': ref.read(exploreEnabledProvider.notifier).set,
        'playlists': ref.read(playlistsProvider.notifier).setInDrawer,
        'movies': ref.read(moviesProvider.notifier).setInDrawer,
        'cinema': ref.read(cinemaProvider.notifier).setInDrawer,
        'podcasts': (v) async => ref.read(podcastsProvider).setSettings(drawer: v),
        'books': ref.read(booksProvider.notifier).setInDrawer,
        'gallery': ref.read(galleryProvider.notifier).setInDrawer,
        'opportunity': ref.read(opportunityProvider.notifier).setInDrawer,
        'marketplace': ref.read(marketProvider.notifier).setInDrawer,
        'my_folders': ref.read(customFoldersProvider.notifier).setInDrawer,
      };
      const aliases = {
        'music': 'playlists', 'playlist': 'playlists', 'musicplaylists': 'playlists',
        'video': 'movies', 'videos': 'movies', 'movie': 'movies',
        'films': 'cinema', 'film': 'cinema', 'shows': 'cinema', 'series': 'cinema',
        'podcast': 'podcasts', 'radio': 'podcasts', 'podcastsradio': 'podcasts',
        'library': 'books', 'book': 'books', 'photos': 'gallery',
        'events': 'opportunity', 'jobs': 'opportunity', 'opportunities': 'opportunity', 'eventsjobs': 'opportunity',
        'market': 'marketplace', 'shop': 'marketplace',
        'folders': 'my_folders', 'myfolders': 'my_folders',
        'explorepages': 'explore', 'sections': 'explore',
      };
      String norm(String s) {
        final k = s.toLowerCase().replaceAll(RegExp(r'[^a-z_]'), '');
        return aliases[k] ?? aliases[k.replaceAll('_', '')] ?? k;
      }

      await Future.wait([
        ref.read(cinemaProvider.notifier).ready,
        ref.read(moviesProvider.notifier).ready,
        ref.read(booksProvider.notifier).ready,
        ref.read(galleryProvider.notifier).ready,
        ref.read(opportunityProvider.notifier).ready,
        ref.read(marketProvider.notifier).ready,
      ]);
      final unknown = <String>[];
      for (final (list, on) in [(_strs(a, 'show'), true), (_strs(a, 'hide'), false)]) {
        for (final s in list) {
          final f = setters[norm(s)];
          f == null ? unknown.add(s) : await f(on);
        }
      }
      final start = _str(a, 'start_page');
      if (start.isNotEmpty) {
        final p = StartPage.values.where((p) => p.name == start || p.label.toLowerCase() == start.toLowerCase()).firstOrNull;
        if (p == null) return {'error': 'No start page "$start". Pages: ${StartPage.values.map((p) => p.name).join(', ')}'};
        await ref.read(settingsProvider.notifier).setStartPage(p.name);
      }
      return {
        'in_drawer': {
          'explore': ref.read(exploreEnabledProvider),
          'playlists': ref.read(playlistsProvider).inDrawer,
          'movies': ref.read(moviesProvider).inDrawer,
          'cinema': ref.read(cinemaProvider).inDrawer,
          'podcasts': ref.read(podcastsProvider).inDrawer,
          'books': ref.read(booksProvider).inDrawer,
          'gallery': ref.read(galleryProvider).inDrawer,
          'opportunity': ref.read(opportunityProvider).inDrawer,
          'marketplace': ref.read(marketProvider).inDrawer,
          'my_folders': ref.read(customFoldersProvider).inDrawer,
        },
        'start_page': ref.read(settingsProvider).startPage,
        'start_pages': [for (final p in StartPage.values) p.name],
        if (unknown.isNotEmpty) 'unknown': unknown,
      };
  }
  if (name.startsWith('podcast_') || name == 'radio') return runPodcastTool(ref, name, a, account);
  return {'error': 'Unknown tool $name.'};
}
