import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../ai/data/ai.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_store.dart';
import '../usage/usage.dart';
import '../sections/section_kit.dart';
import '../sections/ai_run.dart';
import 'package:omni_ai/omni_ai.dart' show CancelToken;

// The marketplace: channels and groups that sell things, read as shops.
// Posts become products (pictures, a name, a price), optionally tidied by
// a model that also judges how legitimate each looks. A cart and a
// wishlist are kept on this phone.

/// A picture of a product: the photo and its blurry preview.
typedef ProductPicture = ({td.File? file, td.Minithumbnail? mini});

/// A post read as a product. Built from one message, or an album of
/// photos sent together.
class Product {
  Product({
    required this.account,
    required this.chatId,
    required this.messageIds,
    required this.store,
    required this.text,
    required this.date,
    this.pictures = const [],
    this.views = 0,
    this.reactions = 0,
    this.forwards = 0,
    this.video = false,
  });
  final String account;
  final int chatId;
  final List<int> messageIds;
  final String store;
  final String text;
  final DateTime date;
  final List<ProductPicture> pictures;
  final int views;
  final int reactions;
  final int forwards;
  final bool video;

  String get key => postKey(account, chatId, messageIds.first);
  int get messageId => messageIds.first;

  /// The first line, without emoji clutter, as a name.
  late final String guessTitle = () {
    for (final line in text.split('\n')) {
      final l = line.replaceAll(RegExp(r'[#*_~`>|]+'), '').trim();
      if (l.length >= 3 && !RegExp(r'^(price|ዋጋ|contact|call|☎|📞)', caseSensitive: false).hasMatch(l)) {
        return l.length > 70 ? '${l.substring(0, 70)}…' : l;
      }
    }
    return text.isEmpty ? 'Item' : (text.length > 50 ? '${text.substring(0, 50)}…' : text);
  }();

  late final ({double? amount, String currency}) guessPrice = parsePrice(text);

  static Product? fromMessages(List<td.Message> group, String account, String store) {
    final first = group.first;
    if (first.content is td.MessageChatAddMembers || first.content is td.MessagePinMessage) return null;
    final text = group.map(messageText).where((t) => t.isNotEmpty).join('\n').trim();
    final pics = <ProductPicture>[];
    var video = false;
    for (final m in group) {
      final p = messagePicture(m, minWidth: 800);
      if (p.file != null || p.mini != null) pics.add(p);
      if (m.content is td.MessageVideo) video = true;
    }
    // A sale needs a picture, or at least a price in its words.
    if (pics.isEmpty && parsePrice(text).amount == null) return null;
    if (pics.isEmpty && text.length < 8) return null;
    final info = first.interactionInfo;
    return Product(
      account: account,
      chatId: first.chatId,
      messageIds: [for (final m in group) m.id]..sort(),
      store: store,
      text: text,
      date: unixDate(first.date),
      pictures: pics,
      views: info?.viewCount ?? 0,
      reactions: info?.reactions?.reactions.fold<int>(0, (a, r) => a + r.totalCount) ?? 0,
      forwards: info?.forwardCount ?? 0,
      video: video,
    );
  }
}

const _currencies = <String, String>{
  'etb': 'ETB', 'br': 'ETB', 'birr': 'ETB', 'ብር': 'ETB', 'usd': 'USD', r'$': 'USD', 'dollar': 'USD', 'dollars': 'USD',
  '€': 'EUR', 'eur': 'EUR', 'euro': 'EUR', '£': 'GBP', 'gbp': 'GBP', 'ksh': 'KES', 'kes': 'KES', '₦': 'NGN', 'ngn': 'NGN',
  '₹': 'INR', 'inr': 'INR', 'rs': 'INR', 'aed': 'AED', 'sar': 'SAR', 'egp': 'EGP', 'ugx': 'UGX', 'tzs': 'TZS', 'rub': 'RUB', '₽': 'RUB',
};

// An amount with a currency wins; "Price: 1200" without one is the fallback.
final _withCurrency = RegExp(
  r'(?:(etb|birr|br\.?|ብር|usd|\$|€|eur|£|gbp|ksh|kes|₦|ngn|₹|inr|rs\.?|aed|sar|egp|ugx|tzs|rub|₽)\s*(\d[\d,\. ]*\d|\d)\s*(k)?)|(?:(\d[\d,\. ]*\d|\d)\s*(k)?\s*(etb|birr|br|ብር|usd|\$|€|eur|euro|£|gbp|ksh|kes|₦|ngn|₹|inr|aed|sar|egp|ugx|tzs|rub|₽|dollars?))',
  caseSensitive: false,
);
final _labelled = RegExp(r'(?:price|ዋጋ|cost)\s*[:=\-]?\s*(\d[\d,\. ]*\d|\d)\s*(k)?', caseSensitive: false);

/// A price in [text]: the first amount with a currency, or after "price".
({double? amount, String currency}) parsePrice(String text) {
  String? cur;
  String? num;
  var k = false;
  final m = _withCurrency.firstMatch(text);
  if (m != null && m.group(2) != null) {
    cur = m.group(1);
    num = m.group(2);
    k = m.group(3) != null;
  } else if (m != null) {
    num = m.group(4);
    k = m.group(5) != null;
    cur = m.group(6);
  } else {
    final l = _labelled.firstMatch(text);
    if (l == null) return (amount: null, currency: '');
    num = l.group(1);
    k = l.group(2) != null;
  }
  final clean = (num ?? '').trim().replaceAll(' ', '');
  // "12,500" and "12.500" as thousands; "12.50" as a decimal.
  final digits = RegExp(r'^\d{1,3}([,\.]\d{3})+$').hasMatch(clean) ? clean.replaceAll(RegExp(r'[,\.]'), '') : clean.replaceAll(',', '');
  final v = double.tryParse(digits);
  if (v == null || v <= 0) return (amount: null, currency: '');
  return (amount: k ? v * 1000 : v, currency: _currencies[(cur ?? '').toLowerCase().replaceAll('.', '')] ?? (cur == null ? '' : cur.toUpperCase()));
}

/// "ETB 12,500" or "12,500".
String priceText(double? amount, String currency) {
  if (amount == null) return '';
  final whole = amount == amount.roundToDouble();
  final s = whole ? amount.round().toString() : amount.toStringAsFixed(2);
  final grouped = s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return currency.isEmpty ? grouped : '$currency $grouped';
}

/// What the model made of a post.
@immutable
class Listing {
  const Listing({
    required this.name,
    this.description = '',
    this.price,
    this.currency = '',
    this.category = '',
    this.condition = '',
    this.location = '',
    this.contact = '',
    this.legit,
    this.legitNotes = '',
    this.rating,
    this.reviews = '',
    this.tags = const [],
    this.isProduct = true,
    required this.at,
  });
  final String name;
  final String description;
  final double? price;
  final String currency;
  final String category;
  final String condition;
  final String location;
  final String contact;

  /// 0-100: how legitimate the listing looks.
  final int? legit;
  final String legitNotes;

  /// 0-5: an estimated rating.
  final double? rating;
  final String reviews;
  final List<String> tags;

  /// False for posts that aren't selling anything (announcements…).
  final bool isProduct;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'n': name,
    if (description.isNotEmpty) 'd': description,
    if (price != null) 'p': price,
    if (currency.isNotEmpty) 'c': currency,
    if (category.isNotEmpty) 'cat': category,
    if (condition.isNotEmpty) 'cond': condition,
    if (location.isNotEmpty) 'loc': location,
    if (contact.isNotEmpty) 'con': contact,
    if (legit != null) 'l': legit,
    if (legitNotes.isNotEmpty) 'ln': legitNotes,
    if (rating != null) 'r': rating,
    if (reviews.isNotEmpty) 'rv': reviews,
    if (tags.isNotEmpty) 't': tags,
    if (!isProduct) 'np': true,
    'at': at.millisecondsSinceEpoch,
  };

  factory Listing.fromJson(Map j) => Listing(
    name: '${j['n'] ?? ''}',
    description: '${j['d'] ?? ''}',
    price: (j['p'] as num?)?.toDouble(),
    currency: '${j['c'] ?? ''}',
    category: '${j['cat'] ?? ''}',
    condition: '${j['cond'] ?? ''}',
    location: '${j['loc'] ?? ''}',
    contact: '${j['con'] ?? ''}',
    legit: (j['l'] as num?)?.toInt(),
    legitNotes: '${j['ln'] ?? ''}',
    rating: (j['r'] as num?)?.toDouble(),
    reviews: '${j['rv'] ?? ''}',
    tags: [for (final t in (j['t'] as List? ?? const [])) '$t'],
    isProduct: j['np'] != true,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

/// A product as kept in the cart or wishlist: enough to show it without
/// reading the post again.
@immutable
class SavedProduct {
  const SavedProduct({
    required this.key,
    required this.title,
    this.price,
    this.currency = '',
    required this.store,
    this.mini,
    this.qty = 1,
    this.note = '',
    required this.addedAt,
  });
  final String key;
  final String title;
  final double? price;
  final String currency;
  final String store;

  /// The blurry preview (base64 JPEG).
  final String? mini;
  final int qty;
  final String note;
  final DateTime addedAt;

  int get chatId => parsePostKey(key)?.chatId ?? 0;
  int get messageId => parsePostKey(key)?.messageId ?? 0;

  /// The account it was saved from.
  String? get account => parsePostKey(key)?.account;

  SavedProduct copyWith({int? qty, String? note}) =>
      SavedProduct(key: key, title: title, price: price, currency: currency, store: store, mini: mini, qty: qty ?? this.qty, note: note ?? this.note, addedAt: addedAt);

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    if (price != null) 'p': price,
    if (currency.isNotEmpty) 'c': currency,
    's': store,
    if (mini != null) 'm': mini,
    if (qty != 1) 'q': qty,
    if (note.isNotEmpty) 'n': note,
    'at': addedAt.millisecondsSinceEpoch,
  };

  factory SavedProduct.fromJson(Map j) => SavedProduct(
    key: '${j['k']}',
    title: '${j['t'] ?? 'Item'}',
    price: (j['p'] as num?)?.toDouble(),
    currency: '${j['c'] ?? ''}',
    store: '${j['s'] ?? ''}',
    mini: j['m'] == null ? null : '${j['m']}',
    qty: (j['q'] as num?)?.toInt() ?? 1,
    note: '${j['n'] ?? ''}',
    addedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {
    'item_key': key,
    'title': title,
    if (price != null) 'price': priceText(price, currency),
    'store': store,
    if (qty != 1) 'quantity': qty,
    if (note.isNotEmpty) 'note': note,
    'chat_id': chatId,
    'message_id': messageId,
  };
}

/// What the AI pass does.
@immutable
class MarketAi {
  const MarketAi({
    this.enabled = false,
    this.auto = true,
    this.model = 'cheap',
    this.name = true,
    this.description = true,
    this.price = true,
    this.legit = true,
    this.reviews = true,
    this.hideNonProducts = true,
    this.extra = '',
  });
  final bool enabled;

  /// Tidies posts as they show, without asking.
  final bool auto;

  /// free, cheap, main or a model id (see [automationModel]).
  final String model;
  final bool name;
  final bool description;
  final bool price;
  final bool legit;
  final bool reviews;

  /// Leaves out posts the model says aren't selling anything.
  final bool hideNonProducts;

  /// The person's own instructions for the model.
  final String extra;

  MarketAi copyWith({bool? enabled, bool? auto, String? model, bool? name, bool? description, bool? price, bool? legit, bool? reviews, bool? hideNonProducts, String? extra}) => MarketAi(
    enabled: enabled ?? this.enabled,
    auto: auto ?? this.auto,
    model: model ?? this.model,
    name: name ?? this.name,
    description: description ?? this.description,
    price: price ?? this.price,
    legit: legit ?? this.legit,
    reviews: reviews ?? this.reviews,
    hideNonProducts: hideNonProducts ?? this.hideNonProducts,
    extra: extra ?? this.extra,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'auto': auto,
    'model': model,
    'name': name,
    'description': description,
    'price': price,
    'legit': legit,
    'reviews': reviews,
    'hide_non_products': hideNonProducts,
    if (extra.isNotEmpty) 'extra': extra,
  };

  factory MarketAi.fromJson(Map j) => MarketAi(
    enabled: j['enabled'] == true,
    auto: j['auto'] != false,
    model: '${j['model'] ?? 'cheap'}',
    name: j['name'] != false,
    description: j['description'] != false,
    price: j['price'] != false,
    legit: j['legit'] != false,
    reviews: j['reviews'] != false,
    hideNonProducts: j['hide_non_products'] != false,
    extra: '${j['extra'] ?? ''}',
  );
}

enum TidyStatus { idle, running, paused, stopping, stopped, done }

/// One call to the model: what was sent, what came back, and its cost.
@immutable
class TidyTrace {
  const TidyTrace({required this.model, required this.system, required this.prompt, this.response, this.error, this.inputTokens = 0, this.outputTokens = 0, this.cost, required this.ms, required this.at, this.batch = 0});
  final String model;
  final String system;

  /// The posts sent, as JSON.
  final String prompt;
  final String? response;
  final String? error;
  final int inputTokens;
  final int outputTokens;
  final double? cost;
  final int ms;
  final DateTime at;
  final int batch;
}

@immutable
class TidyLog {
  const TidyLog({required this.name, required this.store, this.listing, this.error, required this.at, this.trace, this.index, this.productKey, this.postText = ''});
  final String name;
  final String store;
  final Listing? listing;
  final String? error;
  final DateTime at;

  /// The model call this came from, and this post's place in it.
  final TidyTrace? trace;
  final int? index;
  final String? productKey;
  final String postText;
}

/// The AI tidy-up's progress.
@immutable
class TidyJob {
  const TidyJob({this.status = TidyStatus.idle, this.total = 0, this.done = 0, this.failed = 0, this.current = const [], this.log = const [], this.startedAt, this.endedAt, this.model = ''});
  final TidyStatus status;
  final int total;
  final int done;
  final int failed;

  /// The products being asked about now.
  final List<String> current;

  /// Newest first.
  final List<TidyLog> log;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String model;

  bool get active => status == TidyStatus.running || status == TidyStatus.paused || status == TidyStatus.stopping;
  int get left => (total - done).clamp(0, 1 << 30);
  double get fraction => total == 0 ? 0 : done / total;

  TidyJob copyWith({TidyStatus? status, int? total, int? done, int? failed, List<String>? current, List<TidyLog>? log, DateTime? endedAt}) => TidyJob(
    status: status ?? this.status,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    current: current ?? this.current,
    log: log ?? this.log,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    model: model,
  );
}

enum MarketSort {
  newest('Newest'),
  priceLow('Price: low to high'),
  priceHigh('Price: high to low'),
  rating('Best rated'),
  legit('Most trusted'),
  popular('Most viewed');

  const MarketSort(this.label);
  final String label;
}

@immutable
class MarketState {
  const MarketState({
    this.sources = const [],
    this.cart = const [],
    this.wishlist = const [],
    this.hidden = const {},
    this.listings = const {},
    this.ai = const MarketAi(),
    this.sort = MarketSort.newest,
    this.columns = 2,
    this.inDrawer = true,
  });
  final List<SourceRef> sources;
  final List<SavedProduct> cart;
  final List<SavedProduct> wishlist;

  /// Products hidden from the shop.
  final Set<String> hidden;

  /// What the model made of each post, by its key.
  final Map<String, Listing> listings;
  final MarketAi ai;
  final MarketSort sort;
  final int columns;
  final bool inDrawer;

  bool inCart(String key) => cart.any((c) => c.key == key);
  bool wished(String key) => wishlist.any((c) => c.key == key);
  int get cartCount => cart.fold(0, (a, c) => a + c.qty);

  /// Totals per currency.
  Map<String, double> get cartTotals {
    final out = <String, double>{};
    for (final c in cart) {
      if (c.price == null) continue;
      out[c.currency] = (out[c.currency] ?? 0) + c.price! * c.qty;
    }
    return out;
  }

  MarketState copyWith({
    List<SourceRef>? sources,
    List<SavedProduct>? cart,
    List<SavedProduct>? wishlist,
    Set<String>? hidden,
    Map<String, Listing>? listings,
    MarketAi? ai,
    MarketSort? sort,
    int? columns,
    bool? inDrawer,
  }) => MarketState(
    sources: sources ?? this.sources,
    cart: cart ?? this.cart,
    wishlist: wishlist ?? this.wishlist,
    hidden: hidden ?? this.hidden,
    listings: listings ?? this.listings,
    ai: ai ?? this.ai,
    sort: sort ?? this.sort,
    columns: columns ?? this.columns,
    inDrawer: inDrawer ?? this.inDrawer,
  );
}

/// The marketplace's sources, cart, wishlist and settings, kept on this
/// phone; the model's listings in their own setting.
class MarketStore extends Notifier<MarketState> {
  static const key = 'marketplace.v1';
  static const listingsKey = 'marketplace_listings.v1';
  late Future<void> ready;

  @override
  MarketState build() {
    ready = _load();
    return const MarketState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final j = raw == null ? const {} : jsonDecode(raw) as Map;
      final lraw = prefs.getString(listingsKey);
      final lj = lraw == null ? const {} : jsonDecode(lraw) as Map;
      state = MarketState(
        sources: [for (final s in (j['sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        cart: [for (final s in (j['cart'] as List? ?? const [])) if (s is Map) SavedProduct.fromJson(s)],
        wishlist: [for (final s in (j['wishlist'] as List? ?? const [])) if (s is Map) SavedProduct.fromJson(s)],
        hidden: {for (final h in (j['hidden'] as List? ?? const [])) '$h'},
        listings: {for (final e in lj.entries) if (e.value is Map) '${e.key}': Listing.fromJson(e.value as Map)},
        ai: j['ai'] is Map ? MarketAi.fromJson(j['ai'] as Map) : const MarketAi(),
        sort: MarketSort.values.asNameMap()['${j['sort']}'] ?? MarketSort.newest,
        columns: (j['columns'] as num?)?.toInt() ?? 2,
        inDrawer: j['in_drawer'] != false,
      );
    } catch (e) {
      debugPrint('[Market] $e');
    }
  }

  Future<void> _set(MarketState s, {bool listings = false}) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'sources': [for (final x in s.sources) x.toJson()],
        'cart': [for (final x in s.cart) x.toJson()],
        'wishlist': [for (final x in s.wishlist) x.toJson()],
        'hidden': s.hidden.toList(),
        'ai': s.ai.toJson(),
        'sort': s.sort.name,
        'columns': s.columns,
        'in_drawer': s.inDrawer,
      }),
    );
    if (listings) {
      // Keep the newest 1500.
      final entries = s.listings.entries.toList()..sort((a, b) => b.value.at.compareTo(a.value.at));
      await prefs.setString(listingsKey, jsonEncode({for (final e in entries.take(1500)) e.key: e.value.toJson()}));
    }
  }

  Future<void> setSources(List<SourceRef> v) => _set(state.copyWith(sources: v));
  Future<void> addSources(Iterable<SourceRef> v) {
    final have = {for (final s in state.sources) s.key};
    return _set(state.copyWith(sources: [...state.sources, for (final s in v) if (have.add(s.key)) s]));
  }

  Future<void> removeSource(String sourceKey) => _set(state.copyWith(sources: [for (final s in state.sources) if (s.key != sourceKey) s]));
  Future<void> setSourceHidden(String sourceKey, bool v) =>
      _set(state.copyWith(sources: [for (final s in state.sources) s.key == sourceKey ? s.copyWith(hidden: v) : s]));
  Future<void> moveSource(int from, int to) {
    final list = [...state.sources];
    if (from < 0 || from >= list.length) return Future.value();
    final s = list.removeAt(from);
    list.insert(to.clamp(0, list.length), s);
    return _set(state.copyWith(sources: list));
  }

  Future<void> setAi(MarketAi v) => _set(state.copyWith(ai: v));
  Future<void> setSort(MarketSort v) => _set(state.copyWith(sort: v));
  Future<void> setColumns(int v) => _set(state.copyWith(columns: v.clamp(1, 4)));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));

  static SavedProduct snapshot(Product p, Listing? l) => SavedProduct(
    key: p.key,
    title: l?.name.isNotEmpty == true ? l!.name : p.guessTitle,
    price: l?.price ?? p.guessPrice.amount,
    currency: (l?.currency.isNotEmpty ?? false) ? l!.currency : p.guessPrice.currency,
    store: p.store,
    mini: p.pictures.firstOrNull?.mini?.data,
    addedAt: DateTime.now(),
  );

  Future<void> addToCart(SavedProduct item, {int qty = 1}) {
    final have = state.cart.where((c) => c.key == item.key).firstOrNull;
    if (have != null) return setQty(item.key, have.qty + qty);
    return _set(state.copyWith(cart: [...state.cart, item.copyWith(qty: qty)]));
  }

  Future<void> setQty(String key, int qty) => _set(state.copyWith(cart: [
    for (final c in state.cart)
      if (c.key != key) c else if (qty > 0) c.copyWith(qty: qty),
  ]));

  Future<void> setCartNote(String key, String note) => _set(state.copyWith(cart: [for (final c in state.cart) c.key == key ? c.copyWith(note: note) : c]));
  Future<void> removeFromCart(String key) => setQty(key, 0);
  Future<void> clearCart() => _set(state.copyWith(cart: const []));

  Future<bool> toggleWish(SavedProduct item) async {
    if (state.wished(item.key)) {
      await _set(state.copyWith(wishlist: [for (final w in state.wishlist) if (w.key != item.key) w]));
      return false;
    }
    await _set(state.copyWith(wishlist: [item, ...state.wishlist]));
    return true;
  }

  Future<void> removeWish(String key) => _set(state.copyWith(wishlist: [for (final w in state.wishlist) if (w.key != key) w]));
  Future<void> clearWishlist() => _set(state.copyWith(wishlist: const []));

  Future<void> setHidden(String key, bool v) => _set(state.copyWith(hidden: v ? {...state.hidden, key} : ({...state.hidden}..remove(key))));

  Future<void> putListings(Map<String, Listing> v) => _set(state.copyWith(listings: {...state.listings, ...v}), listings: true);
  Future<void> forgetListings() => _set(state.copyWith(listings: const {}), listings: true);

  // ---- the AI pass ---------------------------------------------------------------

  // The tidy-up runs as one job: products queue up, a worker asks the model
  // 8 at a time, and the person can watch it, pause, continue or stop it.

  final job = ValueNotifier<TidyJob>(const TidyJob());

  /// The call in flight: its thinking and answer as they stream.
  final live = AiLiveNotifier();
  final _pending = <Product>[];
  final _queued = <String>{};
  Completer<int>? _run;
  Completer<void>? _resume;
  bool _stop = false;
  CancelToken? _cancel;

  /// Products already sent this session (tidied or not), so the automatic
  /// pass doesn't send the same failing ones again and again.
  final _tried = <String>{};

  /// Stopped by the person: the automatic pass waits until they run it.
  bool _held = false;

  bool get busy => _run != null;

  /// Queues [products] that have no listing yet (or all of them with
  /// [force]) for the model. Completes when the queue is done, with how
  /// many were tidied. [auto] passes (as products load) skip what was
  /// tried this session and stay off after the person pressed Stop.
  Future<int> enrich(List<Product> products, {bool force = false, bool auto = false}) {
    if (auto && _held) return _run?.future ?? Future.value(0);
    if (!auto) _held = false;
    final todo = [
      for (final p in products)
        if ((force || !state.listings.containsKey(p.key)) && !_queued.contains(p.key) && !(auto && _tried.contains(p.key))) p,
    ];
    _tried.addAll(todo.map((p) => p.key));
    if (todo.isEmpty) return _run?.future ?? Future.value(0);
    _pending.addAll(todo);
    _queued.addAll(todo.map((p) => p.key));
    final j = job.value;
    if (_run == null) {
      _stop = false;
      job.value = TidyJob(
        status: TidyStatus.running,
        total: todo.length,
        startedAt: DateTime.now(),
        model: automationModel(ref.read(aiProvider), ref.read(settingsProvider), state.ai.model),
        log: j.log,
      );
      _run = Completer<int>();
      unawaited(_work());
    } else {
      job.value = j.copyWith(total: j.total + todo.length);
    }
    return _run!.future;
  }

  Future<void> _work() async {
    var done = 0;
    try {
      while (_pending.isNotEmpty && !_stop) {
        if (_resume != null) await _resume!.future;
        if (_stop) break;
        final batch = _pending.take(2).toList();
        _pending.removeRange(0, batch.length);
        job.value = job.value.copyWith(current: [for (final p in batch) p.guessTitle]);
        live.begin(items: [for (final p in batch) p.guessTitle]);
        _cancel = CancelToken();
        try {
          final got = await _ask(batch);
          done += got.length;
          await putListings(got);
          final missed = batch.where((p) => !got.containsKey(p.key)).length;
          job.value = job.value.copyWith(
            done: job.value.done + batch.length,
            failed: job.value.failed + missed,
            log: [
              for (final (i, p) in batch.indexed)
                TidyLog(
                  name: got[p.key]?.name ?? p.guessTitle,
                  store: p.store,
                  listing: got[p.key],
                  error: got.containsKey(p.key) ? null : 'No answer for this one',
                  at: DateTime.now(),
                  trace: _trace,
                  index: i,
                  productKey: p.key,
                  postText: p.text,
                ),
              ...job.value.log,
            ].take(80).toList(),
          );
        } on AiCancelled {
          // Stopped mid-call: these weren't tidied, nor did they fail.
          _tried.removeAll(batch.map((p) => p.key));
          break;
        } catch (e) {
          job.value = job.value.copyWith(
            done: job.value.done + batch.length,
            failed: job.value.failed + batch.length,
            log: [
              for (final (i, p) in batch.indexed)
                TidyLog(name: p.guessTitle, store: p.store, error: aiErrorText(e), at: DateTime.now(), trace: _trace, index: i, productKey: p.key, postText: p.text),
              ...job.value.log,
            ].take(80).toList(),
          );
        } finally {
          _queued.removeAll(batch.map((p) => p.key));
          _cancel = null;
        }
      }
    } finally {
      final stopped = _stop;
      for (final p in _pending) {
        _queued.remove(p.key);
      }
      _pending.clear();
      live.idle();
      job.value = job.value.copyWith(status: stopped ? TidyStatus.stopped : TidyStatus.done, current: const [], endedAt: DateTime.now());
      final r = _run;
      _run = null;
      _resume = null;
      r?.complete(done);
    }
  }

  /// Holds the tidy-up after the batch being asked.
  void pauseTidy() {
    if (_run == null || _resume != null) return;
    _resume = Completer<void>();
    job.value = job.value.copyWith(status: TidyStatus.paused);
  }

  void resumeTidy() {
    final r = _resume;
    _resume = null;
    if (_run != null) job.value = job.value.copyWith(status: TidyStatus.running);
    r?.complete();
  }

  /// Stops now: the call in flight is dropped, and so is the rest of the
  /// queue. The automatic pass stays off until the person runs it again.
  void stopTidy() {
    _held = true;
    if (_run == null) return;
    _stop = true;
    _cancel?.cancel();
    resumeTidy();
    job.value = job.value.copyWith(status: TidyStatus.stopping);
  }

  void clearTidyLog() => job.value = job.value.copyWith(log: const []);

  /// The last model call, for the trace page.
  TidyTrace? _trace;

  Future<Map<String, Listing>> _ask(List<Product> batch) async {
    final cfg = state.ai;
    final ai = ref.read(aiProvider);
    final settings = ref.read(settingsProvider);
    final model = automationModel(ai, settings, cfg.model);
    final want = [
      'is_product (false if the post sells nothing: news, ads for the channel, greetings)',
      if (cfg.name) 'name (a clean product name, under 60 characters, no emoji)',
      if (cfg.description) 'description (2-3 plain sentences: what it is, key specs, what is included)',
      if (cfg.price) 'price (a number, no symbols; null if none) and currency (ISO code, e.g. ETB, USD)',
      'category (one or two words, e.g. Phones, Laptops, Fashion, Cars, Real estate, Home, Beauty, Services)',
      'condition (New, Used, Refurbished or empty)',
      'location (city or area if given)',
      'contact (phone numbers, @usernames or links to order, if given)',
      if (cfg.legit)
        'legit (0-100: how legitimate the listing looks: realistic price for the item, specific details, real photos, a reachable seller; low for too-good-to-be-true prices, pressure tactics, advance-payment-only, mismatched details) and legit_notes (one short sentence why)',
      if (cfg.reviews)
        'rating (0-5, one decimal: an estimate of how well buyers would rate this item and seller, from the item\'s reputation, the post\'s views and reactions, and how complete it is) and reviews (one or two sentences: what buyers generally say about this kind of item or model, its known strengths and problems)',
      'tags (up to 4 short words)',
    ];
    final posts = [
      for (final (i, p) in batch.indexed)
        {
          'i': i,
          'store': p.store,
          'posted': p.date.toIso8601String().substring(0, 10),
          if (p.views > 0) 'views': p.views,
          if (p.reactions > 0) 'reactions': p.reactions,
          'photos': p.pictures.length,
          'text': p.text.length > 1500 ? '${p.text.substring(0, 1500)}…' : p.text,
        },
    ];
    final system =
        'You turn messy Telegram sale posts into clean product listings for a shopping app. Posts are in any '
        'language (Amharic, English, Arabic…); write fields in the post\'s main language unless it is mixed, then '
        'English. Never invent specs or prices that aren\'t in the post. Answer with only a JSON array, one object '
        'per post, each with "i" and these fields: ${want.join('; ')}. Only "i" and "name" are required: leave '
        'out any field the post does not make clear rather than guessing. Be quick; do not deliberate.'
        '${cfg.extra.trim().isEmpty ? '' : '\nThe user adds: ${cfg.extra.trim()}'}';
    final prompt = const JsonEncoder.withIndent('  ').convert(posts);
    final started = DateTime.now();
    final main = canonicalModelId(settings.model);
    final List<Map<String, dynamic>> list;
    final AiCallResult result;
    try {
      // Room for thinking models to think and still answer.
      (list, result) = await aiJsonCall(
        ai: ai,
        model: model,
        fallbackModel: main == model ? null : main,
        system: system,
        prompt: prompt,
        maxOutputTokens: 700 * batch.length + 1600,
        cancel: _cancel ?? CancelToken(),
        live: live,
      );
    } on AiCancelled {
      rethrow;
    } catch (e) {
      _trace = TidyTrace(model: model, system: system, prompt: prompt, error: aiErrorText(e), ms: DateTime.now().difference(started).inMilliseconds, at: started, batch: batch.length);
      rethrow;
    }
    _trace = TidyTrace(
      model: result.model,
      system: system,
      prompt: prompt,
      response: result.text,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      cost: result.cost,
      ms: result.ms,
      at: started,
      batch: batch.length,
    );
    try {
      ref.read(usageProvider.notifier).recordChat(model: result.model, usage: result.usage, info: ref.read(modelCatalogProvider).byId(result.model));
    } catch (_) {}
    final out = <String, Listing>{};
    for (final o in list) {
      final i = (o['i'] as num?)?.toInt();
      if (i == null || i < 0 || i >= batch.length) continue;
      final p = batch[i];
      double? number(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d\.]'), ''));
      out[p.key] = Listing(
        name: '${o['name'] ?? ''}'.trim().isEmpty ? p.guessTitle : '${o['name']}'.trim(),
        description: '${o['description'] ?? ''}'.trim(),
        price: number(o['price']) ?? p.guessPrice.amount,
        currency: '${o['currency'] ?? ''}'.trim().isEmpty ? p.guessPrice.currency : '${o['currency']}'.trim().toUpperCase(),
        category: '${o['category'] ?? ''}'.trim(),
        condition: '${o['condition'] ?? ''}'.trim(),
        location: '${o['location'] ?? ''}'.trim(),
        contact: '${o['contact'] ?? ''}'.trim(),
        legit: (o['legit'] as num?)?.round().clamp(0, 100),
        legitNotes: '${o['legit_notes'] ?? ''}'.trim(),
        rating: (o['rating'] as num?)?.toDouble().clamp(0, 5),
        reviews: '${o['reviews'] ?? ''}'.trim(),
        tags: [for (final t in (o['tags'] as List? ?? const [])) '$t'],
        isProduct: o['is_product'] != false,
        at: DateTime.now(),
      );
    }
    return out;
  }
}

final marketProvider = NotifierProvider<MarketStore, MarketState>(MarketStore.new);

// ---- the feed ----------------------------------------------------------------

@immutable
class MarketFeedState {
  const MarketFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}, this.errors = const {}});
  final Map<String, List<Product>> bySource;
  final Set<String> loading;

  /// Where each source's next page starts; 0 when it has no more.
  final Map<String, int> next;
  final Map<String, String> errors;

  bool get anyLoading => loading.isNotEmpty;
}

/// Products read from the marketplace's sources, kept for the session.
class MarketFeed extends Notifier<MarketFeedState> {
  static final _memory = FeedMemory('market');

  /// The posts read from each source this run, newest first, for [_memory].
  final _ids = <String, List<int>>{};

  @override
  MarketFeedState build() => const MarketFeedState();

  /// Reads (more of) [s]: about [want] products.
  Future<void> load(SourceRef s, {bool more = false, int want = 30}) async {
    if (state.loading.contains(s.key)) return;
    if (more && state.next[s.key] == 0) return;
    state = MarketFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next, errors: {...state.errors}..remove(s.key));
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      // First time this run: what it showed last time, at once.
      if (!more && !state.bySource.containsKey(s.key)) {
        final kept = [for (final g in groupAlbums(await _memory.recall(client, s))) ?Product.fromMessages(g, s.account, title)];
        if (kept.isNotEmpty && !state.bySource.containsKey(s.key)) {
          state = MarketFeedState(bySource: {...state.bySource, s.key: kept}, loading: state.loading, next: state.next, errors: state.errors);
        }
      }
      var from = more ? (state.next[s.key] ?? 0) : 0;
      final found = <Product>[];
      final ids = more ? [...?_ids[s.key]] : <int>[];
      var next = 0;
      for (var round = 0; round < 5 && found.length < want; round++) {
        final page = await loadChatPage(client, s.chatId, from: from, limit: 60);
        ids.addAll(page.messages.map((m) => m.id));
        for (final g in groupAlbums(page.messages)) {
          final p = Product.fromMessages(g, s.account, title);
          if (p != null) found.add(p);
        }
        next = page.next;
        if (next == 0 || page.messages.isEmpty) {
          next = 0;
          break;
        }
        from = next;
      }
      final have = more ? (state.bySource[s.key] ?? const <Product>[]) : const <Product>[];
      final keys = {for (final p in have) p.key};
      state = MarketFeedState(
        bySource: {...state.bySource, s.key: [...have, for (final p in found) if (keys.add(p.key)) p]},
        loading: {...state.loading}..remove(s.key),
        next: {...state.next, s.key: next},
        errors: state.errors,
      );
      _ids[s.key] = ids;
      unawaited(_memory.remember(s, ids, max: 300));
    } catch (e) {
      state = MarketFeedState(
        bySource: state.bySource,
        loading: {...state.loading}..remove(s.key),
        next: state.next,
        errors: {...state.errors, s.key: '$e'},
      );
    }
  }

  /// Every source, first page each.
  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));

  Product? byKey(String key) {
    for (final list in state.bySource.values) {
      for (final p in list) {
        if (p.key == key) return p;
        final k = parsePostKey(key);
        if (k != null && p.chatId == k.chatId && p.messageIds.contains(k.messageId)) return p;
      }
    }
    return null;
  }

  /// Reads one product straight from its post (for the cart and wishlist).
  Future<Product?> fetch(String key) async {
    final have = byKey(key);
    if (have != null) return have;
    final k = parsePostKey(key);
    if (k == null) return null;
    final client = ref.read(telegramClientFamily(k.account));
    final m = await client.send<td.Message>(td.GetMessage(chatId: k.chatId, messageId: k.messageId), limited: true);
    var group = [m];
    if (m.mediaAlbumId != 0) {
      final around = await client.send<td.Messages>(
        td.GetChatHistory(chatId: k.chatId, fromMessageId: k.messageId, offset: -10, limit: 20, onlyLocal: false),
        limited: true,
      );
      group = [for (final x in around.messages) if (x.mediaAlbumId == m.mediaAlbumId) x]..sort((a, b) => a.id.compareTo(b.id));
      if (group.isEmpty) group = [m];
    }
    final title = ref.read(telegramStoreFamily(k.account)).chat(k.chatId)?.title ?? '';
    return Product.fromMessages(group, k.account, title);
  }
}

final marketFeedProvider = NotifierProvider<MarketFeed, MarketFeedState>(MarketFeed.new);

/// The shop's products: every visible source's, filtered, searched and
/// sorted, with the model's listing when there is one.
List<(Product, Listing?)> shopProducts(
  MarketState m,
  MarketFeedState feed, {
  String? sourceKey,
  String query = '',
  String? category,
  bool includeHidden = false,
}) {
  final out = <(Product, Listing?)>[];
  final q = query.toLowerCase().trim();
  for (final s in m.sources) {
    if (sourceKey != null ? s.key != sourceKey : s.hidden) continue;
    for (final p in feed.bySource[s.key] ?? const <Product>[]) {
      if (!includeHidden && m.hidden.contains(p.key)) continue;
      final l = m.listings[p.key];
      if (l != null && !l.isProduct && m.ai.hideNonProducts) continue;
      if (category != null && (l?.category ?? '') != category) continue;
      if (q.isNotEmpty && !'${l?.name ?? ''} ${l?.description ?? ''} ${l?.category ?? ''} ${l?.tags.join(' ') ?? ''} ${p.text} ${p.store}'.toLowerCase().contains(q)) continue;
      out.add((p, l));
    }
  }
  double? price((Product, Listing?) x) => x.$2?.price ?? x.$1.guessPrice.amount;
  int cmp(num? a, num? b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  out.sort(switch (m.sort) {
    MarketSort.newest => (a, b) => b.$1.date.compareTo(a.$1.date),
    MarketSort.priceLow => (a, b) => cmp(price(a), price(b)),
    MarketSort.priceHigh => (a, b) => cmp(price(a), price(b), desc: true),
    MarketSort.rating => (a, b) => cmp(a.$2?.rating, b.$2?.rating, desc: true),
    MarketSort.legit => (a, b) => cmp(a.$2?.legit, b.$2?.legit, desc: true),
    MarketSort.popular => (a, b) => b.$1.views.compareTo(a.$1.views),
  });
  return out;
}

/// What the assistant sees of a product.
Map<String, dynamic> describeProduct(Product p, Listing? l) => {
  'item_key': p.key,
  'name': l?.name ?? p.guessTitle,
  if (l?.description.isNotEmpty ?? false) 'description': l!.description,
  if ((l?.price ?? p.guessPrice.amount) != null) 'price': priceText(l?.price ?? p.guessPrice.amount, (l?.currency.isNotEmpty ?? false) ? l!.currency : p.guessPrice.currency),
  'store': p.store,
  'chat_id': p.chatId,
  'message_id': p.messageId,
  'posted': p.date.toIso8601String().substring(0, 10),
  if (p.views > 0) 'views': p.views,
  'photos': p.pictures.length,
  if (l?.category.isNotEmpty ?? false) 'category': l!.category,
  if (l?.condition.isNotEmpty ?? false) 'condition': l!.condition,
  if (l?.location.isNotEmpty ?? false) 'location': l!.location,
  if (l?.contact.isNotEmpty ?? false) 'contact': l!.contact,
  if (l?.legit != null) 'legit_score': l!.legit,
  if (l?.legitNotes.isNotEmpty ?? false) 'legit_notes': l!.legitNotes,
  if (l?.rating != null) 'rating': l!.rating,
  if (l?.reviews.isNotEmpty ?? false) 'reviews': l!.reviews,
  if (l == null) 'text': p.text.length > 600 ? '${p.text.substring(0, 600)}…' : p.text,
};
