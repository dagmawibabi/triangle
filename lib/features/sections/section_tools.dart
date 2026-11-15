import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../app/start_page.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../ai/data/ai.dart';
import '../books/book_parsers.dart';
import '../books/books.dart';
import '../custom_folders/custom_folders.dart';
import '../gallery/gallery.dart';
import '../marketplace/market.dart';
import '../movies/movies.dart';
import '../playlists/playlists.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_store.dart';
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

    // ---- sections ------------------------------------------------------------------------
    case 'app_sections':
      final setters = <String, Future<void> Function(bool)>{
        'playlists': ref.read(playlistsProvider.notifier).setInDrawer,
        'marketplace': ref.read(marketProvider.notifier).setInDrawer,
        'movies': ref.read(moviesProvider.notifier).setInDrawer,
        'books': ref.read(booksProvider.notifier).setInDrawer,
        'gallery': ref.read(galleryProvider.notifier).setInDrawer,
        'my_folders': ref.read(customFoldersProvider.notifier).setInDrawer,
      };
      String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z_]'), '').replaceAll('library', 'books').replaceAll('music', 'playlists').replaceAll('folders', 'my_folders').replaceAll('market', 'marketplace').replaceAll('marketplaceplace', 'marketplace').replaceAll('my_my_', 'my_');
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
          'playlists': ref.read(playlistsProvider).inDrawer,
          'marketplace': ref.read(marketProvider).inDrawer,
          'movies': ref.read(moviesProvider).inDrawer,
          'books': ref.read(booksProvider).inDrawer,
          'gallery': ref.read(galleryProvider).inDrawer,
          'my_folders': ref.read(customFoldersProvider).inDrawer,
        },
        'start_page': ref.read(settingsProvider).startPage,
        'start_pages': [for (final p in StartPage.values) p.name],
        if (unknown.isNotEmpty) 'unknown': unknown,
      };
  }
  return {'error': 'Unknown tool $name.'};
}
