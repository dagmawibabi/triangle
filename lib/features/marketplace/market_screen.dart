import 'dart:async';
import '../account/account_router.dart' show openChatInAccount, switchToOpen;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../assistant/presentation/automation_widgets.dart' show AutomationModelTile;
import '../playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../sections/ai_run.dart';
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../telegram/presentation/chat_view_screen.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'market.dart';

import '../sections/skeletons.dart';
/// The section's colour; the app's monochrome one in the minimal look.
Color get marketColor => AppLook.brand(const Color(0xFFFF7A1A));

/// The marketplace: products from the channels and groups picked as
/// stores, a cart and a wishlist, tidied by a model when that's on.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key, this.initialTab = 0});
  final int initialTab;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketplaceScreen()));

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(marketProvider.notifier).ready;
      if (!mounted) return;
      final m = ref.read(marketProvider);
      unawaited(ref.read(marketFeedProvider.notifier).loadAll(_mine(m)));
    });
  }

  List<SourceRef> _mine(MarketState m) => [for (final s in m.sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  Future<void> _addStores() async {
    final m = ref.read(marketProvider);
    final picked = await pickSources(
      context,
      account: ref.read(activeAccountIdProvider),
      current: m.sources,
      title: 'Stores',
      hint: 'Channels and groups that sell things. Their posts show as products.',
    );
    if (picked == null) return;
    await ref.read(marketProvider.notifier).setSources(picked);
    unawaited(ref.read(marketFeedProvider.notifier).loadAll(_mine(ref.read(marketProvider))));
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(marketProvider);
    final feed = ref.watch(marketFeedProvider);
    final products = shopProducts(m, feed);
    final rated = m.listings.values.where((l) => l.legit != null).toList();
    return SectionScaffold(
        initialTab: widget.initialTab,
        title: 'Marketplace',
        icon: Icons.storefront_rounded,
        color: marketColor,
        tabs: [
          const Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_bag_outlined, size: 16), SizedBox(width: 6), Text('Shop')])),
          const Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.store_mall_directory_outlined, size: 16), SizedBox(width: 6), Text('Stores')])),
          Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.favorite_border_rounded, size: 16), const SizedBox(width: 6), Text('Wishlist${m.wishlist.isEmpty ? '' : ' · ${m.wishlist.length}'}')])),
          Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.shopping_cart_outlined, size: 16), const SizedBox(width: 6), Text('Cart${m.cart.isEmpty ? '' : ' · ${m.cartCount}'}')])),
        ],
        actions: [
          IconButton(
            tooltip: 'AI tidy-up',
            icon: Icon(Icons.auto_awesome_rounded, color: m.ai.enabled ? marketColor : null),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketAiSettingsScreen())),
          ),
          IconButton(tooltip: 'Stores', icon: const Icon(Icons.add_business_outlined), onPressed: _addStores),
        ],
        hero: SectionHero(
          subtitle: m.sources.isEmpty ? 'Turn the channels and groups that sell things into one store.' : 'Every post from your stores, as products',
          stats: [
            ('${m.sources.length}', m.sources.length == 1 ? 'store' : 'stores'),
            ('${products.length}', 'products'),
            ('${m.cartCount}', 'in cart'),
            (rated.isEmpty ? '–' : '${(rated.fold<int>(0, (a, l) => a + l.legit!) / rated.length).round()}%', 'avg trust'),
          ],
        ),
        views: [
          _ShopTab(onAddStores: _addStores),
          _StoresTab(onAddStores: _addStores),
          const _WishlistTab(),
          const _CartTab(),
        ],
        bottomBar: const BottomAudioBar(),
    );
  }
}

// ---- shop --------------------------------------------------------------------

class _ShopTab extends ConsumerStatefulWidget {
  const _ShopTab({required this.onAddStores});
  final VoidCallback onAddStores;

  @override
  ConsumerState<_ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends ConsumerState<_ShopTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _source;
  String? _category;
  final _debounce = Debounce();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce.cancel();
    super.dispose();
  }

  Future<void> _more(MarketState m) async {
    final feed = ref.read(marketFeedProvider.notifier);
    final mine = [for (final s in m.sources) if (!s.hidden && s.account == ref.read(activeAccountIdProvider) && (_source == null || s.key == _source)) s];
    await pooled(mine, 3, (s) => feed.load(s, more: true));
  }

  void _autoTidy(MarketState m, List<(Product, Listing?)> shown) {
    if (!m.ai.enabled || !m.ai.auto) return;
    final todo = [for (final (p, l) in shown.take(40)) if (l == null) p];
    if (todo.isEmpty || ref.read(marketProvider.notifier).busy) return;
    _debounce(const Duration(milliseconds: 800), () {
      ref.read(marketProvider.notifier).enrich(todo, auto: true).catchError((Object e) {
        if (mounted) showSnack(context, 'AI tidy-up failed: $e', icon: Icons.error_outline_rounded);
        return 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = ref.watch(marketProvider);
    final feed = ref.watch(marketFeedProvider);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.storefront_outlined,
          title: 'No stores yet',
          body: 'Pick the channels and groups that sell things. Their posts become products you can search, compare, save and put in a cart.',
          action: 'Add stores',
          onAction: widget.onAddStores,
        ),
      );
    }
    final list = shopProducts(m, feed, sourceKey: _source, query: _q, category: _category);
    final categories = <String, int>{};
    for (final (_, l) in shopProducts(m, feed, sourceKey: _source)) {
      final c = l?.category ?? '';
      if (c.isNotEmpty) categories[c] = (categories[c] ?? 0) + 1;
    }
    final cats = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _autoTidy(m, list);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? m.columns + 2 : (width > 600 ? m.columns + 1 : m.columns);
    final store = ref.read(marketProvider.notifier);
    final anyMore = m.sources.any((s) => !s.hidden && (feed.next[s.key] ?? 1) != 0);
    return RefreshIndicator(
      onRefresh: () => ref.read(marketFeedProvider.notifier).loadAll(m.sources.where((s) => s.account == ref.read(activeAccountIdProvider)), refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600 && !feed.anyLoading && anyMore) _more(m);
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search products', isDense: true),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                    PopupMenuButton<Object>(
                      tooltip: 'Sort and view',
                      icon: const Icon(Icons.tune_rounded),
                      onSelected: (v) {
                        if (v is MarketSort) store.setSort(v);
                        if (v is int) store.setColumns(v);
                      },
                      itemBuilder: (_) => [
                        for (final s in MarketSort.values) CheckedPopupMenuItem(value: s, checked: m.sort == s, child: Text(s.label)),
                        const PopupMenuDivider(),
                        for (final c in const [1, 2, 3]) CheckedPopupMenuItem(value: c, checked: m.columns == c, child: Text(c == 1 ? 'List' : '$c columns')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: const Text('All stores'), selected: _source == null, onSelected: (_) => setState(() => _source = null)),
                    ),
                    for (final s in m.sources.where((s) => !s.hidden))
                      SourceChip(source: s, selected: _source == s.key, onTap: () => setState(() => _source = _source == s.key ? null : s.key)),
                  ],
                ),
              ),
            ),
            if (cats.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
                    children: [
                      for (final c in cats.take(20))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('${c.key} · ${c.value}'),
                            selected: _category == c.key,
                            onSelected: (_) => setState(() => _category = _category == c.key ? null : c.key),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: ValueListenableBuilder<TidyJob>(
                valueListenable: store.job,
                builder: (context, job, _) => !job.active
                    ? const SizedBox.shrink()
                    : InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketAiSettingsScreen())),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 14, color: marketColor),
                              const SizedBox(width: 6),
                              Text(job.status == TidyStatus.paused ? 'AI tidy-up paused · ${job.done}/${job.total}' : 'Tidying with AI · ${job.done}/${job.total}', style: context.text.labelSmall),
                              const SizedBox(width: Space.s),
                              Expanded(child: LinearProgressIndicator(value: job.fraction, minHeight: 3, color: marketColor, borderRadius: BorderRadius.circular(9))),
                              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (list.isEmpty && feed.anyLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols.clamp(2, 6), mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.66),
                  itemCount: 6,
                  itemBuilder: (_, _) => const _CardSkeleton(),
                ),
              )
            else if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: SectionEmpty(
                  icon: Icons.search_off_rounded,
                  title: 'Nothing here',
                  body: _q.isNotEmpty || _category != null
                      ? 'No product matches. Try other words.'
                      : (feed.errors.values.firstOrNull ?? 'These stores have no posts with pictures or prices yet.'),
                ),
              )
            else if (cols == 1)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.x4),
                sliver: SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => ProductRow(product: list[i].$1, listing: list[i].$2)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: cols >= 3 ? 0.62 : 0.66),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ProductCard(product: list[i].$1, listing: list[i].$2),
                ),
              ),
            if (feed.anyLoading && list.isNotEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
          ],
        ),
      ),
    );
  }
}

/// A small trust badge: green, amber or red by the model's score.
class LegitBadge extends StatelessWidget {
  const LegitBadge({super.key, required this.score, this.big = false});
  final int score;
  final bool big;

  static Color colorOf(int s) => s >= 70 ? const Color(0xFF22C55E) : (s >= 45 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

  @override
  Widget build(BuildContext context) {
    final c = colorOf(score);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 6, vertical: big ? 5 : 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(score >= 70 ? Icons.verified_rounded : (score >= 45 ? Icons.shield_outlined : Icons.report_gmailerrorred_rounded), size: big ? 15 : 11, color: Colors.white),
          const SizedBox(width: 3),
          Text('$score%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: big ? 13 : 10.5)),
        ],
      ),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars({super.key, required this.rating, this.size = 13});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          rating >= i ? Icons.star_rounded : (rating >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: const Color(0xFFFFB400),
        ),
      const SizedBox(width: 3),
      Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w700, color: AppColors.text2)),
    ],
  );
}

void openProduct(BuildContext context, Product p) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductScreen(productKey: p.key, product: p)));

class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product, this.listing});
  final Product product;
  final Listing? listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product, l = listing;
    final m = ref.watch(marketProvider);
    final price = priceText(l?.price ?? p.guessPrice.amount, (l?.currency.isNotEmpty ?? false) ? l!.currency : p.guessPrice.currency);
    final pic = p.pictures.firstOrNull;
    final wished = m.wished(p.key);
    final inCart = m.inCart(p.key);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProduct(context, p),
        onLongPress: () => _productMenu(context, ref, p, l),
        child: Ink(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (pic != null)
                      TgPicture(file: pic.file, mini: pic.mini, cacheWidth: 500, account: p.account)
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [marketColor.withValues(alpha: 0.16), AppColors.surface2]),
                        ),
                        padding: const EdgeInsets.all(Space.m),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sell_outlined, color: marketColor.withValues(alpha: 0.8)),
                            const SizedBox(height: Space.s),
                            Text(p.guessTitle, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                          ],
                        ),
                      ),
                    // A soft shade so the badges read on bright photos.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0x40000000)], stops: [0, 0.3, 0.7, 1]),
                      ),
                    ),
                    if (p.pictures.length > 1)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_outlined, size: 11, color: Colors.white),
                              const SizedBox(width: 3),
                              Text('${p.pictures.length}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    if (inCart)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppLook.minimalExplore ? Colors.black54 : marketColor, borderRadius: BorderRadius.circular(99)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_rounded, size: 11, color: Colors.white),
                              SizedBox(width: 3),
                              Text('In cart', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    if (l?.legit != null) Positioned(left: 6, top: 6, child: LegitBadge(score: l!.legit!)),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Material(
                        color: Colors.black38,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => ref.read(marketProvider.notifier).toggleWish(MarketStore.snapshot(p, l)),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(wished ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 17, color: wished ? const Color(0xFFFF4D6D) : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s + 2, Space.s, Space.s + 2, Space.s + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (price.isNotEmpty)
                      Text(price, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: marketColor, letterSpacing: -0.2))
                    else
                      Text('Ask for price', style: context.text.labelMedium?.copyWith(color: AppColors.text3, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(l?.name ?? p.guessTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                    if (l?.rating != null) Padding(padding: const EdgeInsets.only(top: 3), child: Stars(rating: l!.rating!, size: 11)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        TgAvatar(chatId: p.chatId, title: p.store, size: 16, accountId: p.account),
                        const SizedBox(width: 5),
                        Expanded(child: Text('${p.store} · ${agoText(p.date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductRow extends ConsumerWidget {
  const ProductRow({super.key, required this.product, this.listing});
  final Product product;
  final Listing? listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product, l = listing;
    final price = priceText(l?.price ?? p.guessPrice.amount, (l?.currency.isNotEmpty ?? false) ? l!.currency : p.guessPrice.currency);
    final pic = p.pictures.firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProduct(context, p),
        onLongPress: () => _productMenu(context, ref, p, l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, height: 110, child: pic == null ? Container(color: AppColors.surface2, child: Icon(Icons.sell_outlined, color: AppColors.text3)) : TgPicture(file: pic.file, mini: pic.mini, cacheWidth: 300, account: p.account)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l?.name ?? p.guessTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    if (price.isNotEmpty) Text(price, style: TextStyle(fontWeight: FontWeight.w800, color: marketColor)),
                    if (l?.description.isNotEmpty ?? false) Text(l!.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (l?.legit != null) ...[LegitBadge(score: l!.legit!), const SizedBox(width: 6)],
                        if (l?.rating != null) Stars(rating: l!.rating!, size: 11),
                        const Spacer(),
                        Flexible(child: Text(p.store, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _productMenu(BuildContext context, WidgetRef ref, Product p, Listing? l) async {
  final m = ref.read(marketProvider);
  final store = ref.read(marketProvider.notifier);
  final v = await showAppSheet<String>(
    context,
    initialSize: 0.5,
    builder: (context, scroll) => ListView(
      controller: scroll,
      children: [
        ListTile(title: Text(l?.name ?? p.guessTitle, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(p.store)),
        const Divider(),
        ListTile(leading: lead(const Icon(Icons.add_shopping_cart_rounded)), title: Text(m.inCart(p.key) ? 'Add another to cart' : 'Add to cart'), onTap: () => Navigator.pop(context, 'cart')),
        ListTile(leading: lead(Icon(m.wished(p.key) ? Icons.favorite_rounded : Icons.favorite_border_rounded)), title: Text(m.wished(p.key) ? 'Remove from wishlist' : 'Add to wishlist'), onTap: () => Navigator.pop(context, 'wish')),
        ListTile(leading: lead(const Icon(Icons.mode_comment_outlined)), title: const Text('Comments'), onTap: () => Navigator.pop(context, 'chat')),
        ListTile(leading: lead(const Icon(Icons.forward_rounded)), title: const Text('Share to a chat'), onTap: () => Navigator.pop(context, 'share')),
        if (m.ai.enabled) ListTile(leading: lead(const Icon(Icons.auto_awesome_rounded)), title: const Text('Tidy again with AI'), onTap: () => Navigator.pop(context, 'ai')),
        ListTile(leading: lead(const Icon(Icons.visibility_off_outlined)), title: const Text('Hide from the shop'), onTap: () => Navigator.pop(context, 'hide')),
      ],
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'cart':
      await store.addToCart(MarketStore.snapshot(p, l));
      if (context.mounted) showSnack(context, 'Added to cart', icon: Icons.shopping_cart_outlined);
    case 'wish':
      await store.toggleWish(MarketStore.snapshot(p, l));
    case 'chat':
      await openProductComments(context, ref, p);
    case 'share':
      await shareProduct(context, ref, p);
    case 'ai':
      await withSnack(context, 'Asking the model…', () => store.enrich([p], force: true));
    case 'hide':
      await store.setHidden(p.key, true);
      if (context.mounted) showSnack(context, 'Hidden from the shop', icon: Icons.visibility_off_outlined);
  }
}

/// Opens the comments under a store's post; a group, or a channel without
/// comments, opens at the post instead.
Future<void> openProductComments(BuildContext context, WidgetRef ref, Product p) async {
  // Comments and the chat open in the account the store was added from.
  switchToOpen(context, ProviderScope.containerOf(context, listen: false), p.account);
  try {
    final m = await ref.read(telegramClientFamily(p.account)).send<td.Message>(td.GetMessage(chatId: p.chatId, messageId: p.messageId), limited: true);
    if (m.interactionInfo?.replyInfo != null && context.mounted) {
      await openComments(context, ref, m);
      return;
    }
  } catch (_) {}
  if (context.mounted) await openChatInAccount(context, p.chatId, hint: p.account, openAt: p.messageId);
}

Future<void> shareProduct(BuildContext context, WidgetRef ref, Product p) async {
  final chat = await pickTelegramChat(context, title: 'Share to…');
  if (chat == null) return;
  try {
    await ref.read(toolRunnerFamily(p.account)).forwardTo(chat, p.chatId, p.messageIds);
    if (context.mounted) showSnack(context, 'Shared', icon: Icons.forward_rounded);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t share: $e', icon: Icons.error_outline_rounded);
  }
}

// ---- one product -------------------------------------------------------------

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productKey, this.product});
  final String productKey;
  final Product? product;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  Product? _p;
  String? _error;
  int _page = 0;
  bool _raw = false;

  @override
  void initState() {
    super.initState();
    _p = widget.product;
    if (_p == null) {
      ref.read(marketFeedProvider.notifier).fetch(widget.productKey).then((p) {
        if (mounted) setState(() => p == null ? _error = 'This post is gone.' : _p = p);
      }).catchError((Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    }
  }

  Future<void> _viewPicture(ProductPicture pic) async {
    final f = pic.file;
    if (f == null) return;
    final path = await fileLoaderFor(ref, _p?.account).download(f, priority: 20);
    if (path != null && mounted) await openFullscreenFile(context, path, title: _p?.store);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: _error == null ? const CircularProgressIndicator(strokeWidth: 2) : Text(_error!)));
    }
    final m = ref.watch(marketProvider);
    final l = m.listings[p.key];
    final store = ref.read(marketProvider.notifier);
    final price = priceText(l?.price ?? p.guessPrice.amount, (l?.currency.isNotEmpty ?? false) ? l!.currency : p.guessPrice.currency);
    final wished = m.wished(p.key);
    final inCart = m.cart.where((c) => c.key == p.key).firstOrNull;
    final height = MediaQuery.sizeOf(context).width.clamp(0, 520).toDouble();
    Widget chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: AppColors.text2), const SizedBox(width: 5), Text(text, style: context.text.labelMedium)]),
    );
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
          child: Row(
            children: [
              IconButton.outlined(
                icon: Icon(wished ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: wished ? const Color(0xFFFF4D6D) : null),
                onPressed: () => store.toggleWish(MarketStore.snapshot(p, l)),
              ),
              const SizedBox(width: Space.s),
              IconButton.outlined(
                tooltip: 'Comments',
                icon: const Icon(Icons.mode_comment_outlined),
                onPressed: () => openProductComments(context, ref, p),
              ),
              const SizedBox(width: Space.s),
              IconButton.outlined(
                tooltip: 'Tidy with AI',
                icon: store.busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                onPressed: () async {
                  if (!m.ai.enabled) {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketAiSettingsScreen()));
                    return;
                  }
                  await withSnack(context, 'Asking the model…', () => store.enrich([p], force: true));
                },
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: marketColor, foregroundColor: AppLook.onBrand(marketColor)),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text(inCart == null ? 'Add to cart' : 'In cart · ${inCart.qty} — add one'),
                  onPressed: () async {
                    await store.addToCart(MarketStore.snapshot(p, l));
                    if (context.mounted) showSnack(context, 'Added to cart', icon: Icons.shopping_cart_outlined);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: p.pictures.isEmpty ? null : height,
            backgroundColor: AppColors.bg,
            actions: [
              IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share_rounded), onPressed: () => shareProduct(context, ref, p)),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'ai') await withSnack(context, 'Asking the model…', () => store.enrich([p], force: true));
                  if (v == 'hide') {
                    await store.setHidden(p.key, !m.hidden.contains(p.key));
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'hide', child: Text(m.hidden.contains(p.key) ? 'Show in the shop' : 'Hide from the shop')),
                ],
              ),
            ],
            flexibleSpace: p.pictures.isEmpty
                ? null
                : FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          itemCount: p.pictures.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () => _viewPicture(p.pictures[i]),
                            child: TgPicture(file: p.pictures[i].file, mini: p.pictures[i].mini, cacheWidth: 1100, account: p.account),
                          ),
                        ),
                        if (p.pictures.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < p.pictures.length; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: i == _page ? 18 : 7,
                                    height: 7,
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    decoration: BoxDecoration(color: i == _page ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(99)),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
            sliver: SliverList.list(
              children: [
                Text(l?.name ?? p.guessTitle, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: Space.s),
                Row(
                  children: [
                    if (price.isNotEmpty) Text(price, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: marketColor)),
                    const Spacer(),
                    if (l?.rating != null) Stars(rating: l!.rating!, size: 16),
                  ],
                ),
                const SizedBox(height: Space.m),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (l?.legit != null) LegitBadge(score: l!.legit!, big: true),
                    if (l?.category.isNotEmpty ?? false) chip(Icons.category_outlined, l!.category),
                    if (l?.condition.isNotEmpty ?? false) chip(Icons.new_releases_outlined, l!.condition),
                    if (l?.location.isNotEmpty ?? false) chip(Icons.place_outlined, l!.location),
                    if (p.views > 0) chip(Icons.visibility_outlined, '${p.views} views'),
                    chip(Icons.schedule_rounded, agoText(p.date)),
                    for (final t in l?.tags ?? const <String>[]) chip(Icons.tag_rounded, t),
                  ],
                ),
                if (l?.legitNotes.isNotEmpty ?? false) ...[
                  const SizedBox(height: Space.m),
                  _Note(icon: Icons.shield_outlined, color: LegitBadge.colorOf(l!.legit ?? 50), title: 'Trust check', body: l.legitNotes),
                ],
                if (l?.reviews.isNotEmpty ?? false) ...[
                  const SizedBox(height: Space.s),
                  _Note(icon: Icons.reviews_outlined, color: const Color(0xFFFFB400), title: 'What buyers say', body: l!.reviews),
                ],
                if (l?.description.isNotEmpty ?? false) ...[
                  const SizedBox(height: Space.l),
                  Text('About', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: Space.xs),
                  Text(l!.description, style: context.text.bodyMedium?.copyWith(height: 1.5)),
                ],
                if (l?.contact.isNotEmpty ?? false) ...[
                  const SizedBox(height: Space.l),
                  Text('Contact', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  SelectableText(l!.contact, style: context.text.bodyMedium),
                ],
                const SizedBox(height: Space.l),
                InkWell(
                  onTap: () => setState(() => _raw = !_raw),
                  child: Row(
                    children: [
                      Text(l == null ? 'The post' : 'Original post', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Icon(_raw || l == null ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    ],
                  ),
                ),
                if (_raw || l == null) ...[
                  const SizedBox(height: Space.xs),
                  SelectableText(p.text.isEmpty ? '(no text)' : p.text, style: context.text.bodyMedium?.copyWith(color: AppColors.text2, height: 1.5)),
                ],
                const SizedBox(height: Space.l),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: TgAvatar(chatId: p.chatId, title: p.store, size: 44, accountId: p.account),
                  title: Text(p.store, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Visit the store', style: context.text.bodySmall),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final s = m.sources.where((s) => s.chatId == p.chatId).firstOrNull;
                    // Not one of the picked stores (a shared link): its chat instead.
                    s != null ? Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreScreen(source: s))) : openChatInAccount(context, p.chatId, hint: p.account, openAt: p.messageId);
                  },
                ),
                if (!m.ai.enabled)
                  TextButton.icon(
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Turn on the AI tidy-up for clean names, prices and trust checks'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketAiSettingsScreen())),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)), Text(body, style: context.text.bodySmall)],
          ),
        ),
      ],
    ),
  );
}

// ---- stores ------------------------------------------------------------------

class _StoresTab extends ConsumerWidget {
  const _StoresTab({required this.onAddStores});
  final VoidCallback onAddStores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(marketProvider);
    final feed = ref.watch(marketFeedProvider);
    final store = ref.read(marketProvider.notifier);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(icon: Icons.store_mall_directory_outlined, title: 'No stores', body: 'Add the channels and groups you buy from.', action: 'Add stores', onAction: onAddStores),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.x4),
      itemCount: m.sources.length,
      onReorder: (a, b) => store.moveSource(a, b > a ? b - 1 : b),
      itemBuilder: (_, i) {
        final s = m.sources[i];
        final items = feed.bySource[s.key] ?? const <Product>[];
        final rated = [for (final p in items) ?m.listings[p.key]?.legit];
        final trust = rated.isEmpty ? null : (rated.fold<int>(0, (a, b) => a + b) / rated.length).round();
        final pics = [for (final p in items.take(8)) ?p.pictures.firstOrNull];
        return Card(
          key: ValueKey(s.key),
          margin: const EdgeInsets.only(bottom: Space.s),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreScreen(source: s))),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TgAvatar(chatId: s.chatId, title: s.title, size: 44, accountId: s.account),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              [
                                feed.loading.contains(s.key) ? 'Loading…' : '${items.length} products',
                                if (trust != null) 'trust $trust%',
                                if (s.hidden) 'hidden from Shop',
                              ].join(' · '),
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'hide') await store.setSourceHidden(s.key, !s.hidden);
                          if (v == 'remove') await store.removeSource(s.key);
                          if (v == 'open' && context.mounted) await openChatInAccount(context, s.chatId, hint: s.account);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'open', child: Text('Open the chat')),
                          PopupMenuItem(value: 'hide', child: Text(s.hidden ? 'Show in Shop' : 'Hide from Shop')),
                          PopupMenuItem(value: 'remove', child: Text('Remove store', style: TextStyle(color: AppColors.danger))),
                        ],
                      ),
                      ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
                    ],
                  ),
                  if (pics.isNotEmpty) ...[
                    const SizedBox(height: Space.m),
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: pics.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, j) => ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.s),
                          child: SizedBox.square(dimension: 64, child: TgPicture(file: pics[j].file, mini: pics[j].mini, cacheWidth: 200, account: s.account)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One store: its products only.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key, required this.source});
  final SourceRef source;

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    final feed = ref.read(marketFeedProvider);
    if (!feed.bySource.containsKey(widget.source.key)) ref.read(marketFeedProvider.notifier).load(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(marketProvider);
    final feed = ref.watch(marketFeedProvider);
    final s = widget.source;
    final list = shopProducts(m, feed, sourceKey: s.key, query: _q);
    final rated = [for (final (_, l) in list) ?l?.legit];
    final more = (feed.next[s.key] ?? 1) != 0;
    return SectionScaffold(
      title: s.title,
      icon: Icons.storefront_rounded,
      color: marketColor,
      expandedHeight: 210,
      actions: [IconButton(tooltip: 'Open the chat', icon: const Icon(Icons.forum_outlined), onPressed: () => openChatInAccount(context, s.chatId, hint: s.account))],
      hero: Row(
        children: [
          TgAvatar(chatId: s.chatId, title: s.title, size: 64, accountId: s.account),
          const SizedBox(width: Space.l),
          Expanded(
            child: SectionHero(
              subtitle: 'A store from Telegram',
              stats: [
                ('${list.length}', 'products'),
                (rated.isEmpty ? '–' : '${(rated.fold<int>(0, (a, b) => a + b) / rated.length).round()}%', 'trust'),
              ],
            ),
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search ${s.title}', isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
        if (list.isEmpty && feed.loading.contains(s.key))
          const SliverToBoxAdapter(child: SkeletonGrid(count: 6, maxExtent: 240, childAspectRatio: 0.66))
        else
          SliverPadding(
            padding: const EdgeInsets.all(Space.l),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: Space.l, crossAxisSpacing: Space.m, childAspectRatio: 0.66),
              itemCount: list.length,
              itemBuilder: (_, i) => ProductCard(product: list[i].$1, listing: list[i].$2),
            ),
          ),
        if (more)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.x4),
              child: Center(
                child: feed.loading.contains(s.key)
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : OutlinedButton(onPressed: () => ref.read(marketFeedProvider.notifier).load(s, more: true), child: const Text('Load more')),
              ),
            ),
          ),
      ],
    );
  }
}

// ---- wishlist and cart ---------------------------------------------------------

/// A cart or wishlist item's picture: the product's real photo (from the
/// shop, or read from its post once), over the saved blurry preview.
class SavedThumb extends ConsumerStatefulWidget {
  const SavedThumb({super.key, required this.item, this.size = 64});
  final SavedProduct item;
  final double size;

  @override
  ConsumerState<SavedThumb> createState() => _SavedThumbState();
}

class _SavedThumbState extends ConsumerState<SavedThumb> {
  Product? _p;

  @override
  void initState() {
    super.initState();
    _p = ref.read(marketFeedProvider.notifier).byKey(widget.item.key);
    if (_p == null) {
      ref.read(marketFeedProvider.notifier).fetch(widget.item.key).then((p) {
        if (mounted && p != null) setState(() => _p = p);
      }).catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pic = _p?.pictures.firstOrNull;
    final mini = widget.item.mini;
    final blur = mini == null ? Container(color: AppColors.surface2, child: Icon(Icons.sell_outlined, color: AppColors.text3)) : Image.memory(base64Decode(mini), fit: BoxFit.cover);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.s),
      child: SizedBox.square(
        dimension: widget.size,
        child: pic == null ? blur : TgPicture(file: pic.file, mini: pic.mini, cacheWidth: (widget.size * 3).round(), placeholder: blur, account: _p?.account),
      ),
    );
  }
}

class _WishlistTab extends ConsumerWidget {
  const _WishlistTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    if (m.wishlist.isEmpty) {
      return const SingleChildScrollView(
        child: SectionEmpty(icon: Icons.favorite_border_rounded, title: 'Your wishlist is empty', body: 'Tap the heart on any product to keep it here, then move it to your cart when you’re ready.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.x4 + 80),
      itemCount: m.wishlist.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.s),
            child: Text('${m.wishlist.length} saved · swipe left to remove', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          );
        }
        final w = m.wishlist[i - 1];
        final inCart = m.inCart(w.key);
        return Dismissible(
          key: ValueKey(w.key),
          direction: DismissDirection.endToStart,
          onDismissed: (_) {
            store.removeWish(w.key);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Removed “${w.title}”', maxLines: 1, overflow: TextOverflow.ellipsis),
                action: SnackBarAction(label: 'Undo', onPressed: () => store.toggleWish(w)),
              ));
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Space.xl),
            margin: const EdgeInsets.only(bottom: Space.s),
            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(Radii.l)),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductScreen(productKey: w.key))),
                child: Ink(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
                  padding: const EdgeInsets.all(Space.s),
                  child: Row(
                    children: [
                      SavedThumb(item: w, size: 76),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2)),
                            const SizedBox(height: 3),
                            Text(w.price != null ? priceText(w.price, w.currency) : 'Ask for price', style: TextStyle(fontWeight: FontWeight.w900, color: w.price != null ? marketColor : AppColors.text3)),
                            const SizedBox(height: 2),
                            Text(w.store, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: const StadiumBorder(),
                          backgroundColor: inCart ? marketColor.withValues(alpha: 0.15) : marketColor,
                          foregroundColor: inCart ? marketColor : AppLook.onBrand(marketColor),
                        ),
                        onPressed: () async {
                          await store.addToCart(w);
                          if (context.mounted) showSnack(context, inCart ? 'Added another to your cart' : 'Added to cart', icon: Icons.shopping_cart_outlined);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(inCart ? Icons.shopping_cart_rounded : Icons.add_shopping_cart_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(inCart ? 'In cart' : 'Add'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartTab extends ConsumerWidget {
  const _CartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(marketProvider);
    final store = ref.read(marketProvider.notifier);
    if (m.cart.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.shopping_cart_outlined,
          title: 'Your cart is empty',
          body: 'Add products to keep track of what you plan to buy and what it comes to.',
          action: 'Browse the shop',
          onAction: () => DefaultTabController.maybeOf(context)?.animateTo(0),
        ),
      );
    }
    final byStore = <String, List<SavedProduct>>{};
    for (final c in m.cart) {
      byStore.putIfAbsent(c.store, () => []).add(c);
    }
    final totals = m.cartTotals;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.x4 + 80),
      children: [
        for (final e in byStore.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.xs),
            child: Row(
              children: [
                TgAvatar(chatId: e.value.first.chatId, title: e.key, size: 26, accountId: e.value.first.account),
                const SizedBox(width: Space.s),
                Expanded(child: Text(e.key, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Contact'),
                  onPressed: () => openChatInAccount(context, e.value.first.chatId, hint: e.value.first.account, openAt: e.value.first.messageId),
                ),
              ],
            ),
          ),
          for (final c in e.value)
            Card(
              margin: const EdgeInsets.only(bottom: Space.s),
              child: Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Row(
                  children: [
                    GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductScreen(productKey: c.key))), child: SavedThumb(item: c)),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (c.price != null) Text(priceText(c.price! * c.qty, c.currency), style: TextStyle(fontWeight: FontWeight.w800, color: marketColor)),
                          if (c.note.isNotEmpty) Text(c.note, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(visualDensity: VisualDensity.compact, icon: Icon(c.qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, size: 18), onPressed: () => store.setQty(c.key, c.qty - 1)),
                            Text('${c.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_rounded, size: 18), onPressed: () => store.setQty(c.key, c.qty + 1)),
                          ],
                        ),
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () async {
                            final v = await showFieldsSheet(
                              context,
                              icon: Icons.sticky_note_2_outlined,
                              color: marketColor,
                              title: 'Note on this item',
                              subtitle: c.title,
                              preview: Row(
                                children: [
                                  SavedThumb(item: c, size: 56),
                                  const SizedBox(width: Space.m),
                                  Expanded(child: Text([if (c.price != null) priceText(c.price, c.currency), c.store, '× ${c.qty}'].join(' · '), style: context.text.bodySmall)),
                                ],
                              ),
                              fields: [
                                SheetField(
                                  'note',
                                  label: 'Note',
                                  hint: 'Size, colour, what to ask the seller…',
                                  initial: c.note,
                                  maxLines: 4,
                                  suggestions: const ['Ask about the size', 'Check the colour', 'Ask for a lower price', 'Ask about delivery', 'Is it still available?'],
                                ),
                              ],
                            );
                            final note = v?['note'];
                            if (note != null) await store.setCartNote(c.key, note);
                          },
                          child: const Text('Note'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: Space.m),
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [marketColor.withValues(alpha: 0.18), marketColor.withValues(alpha: 0.05)]),
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: marketColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 18, color: marketColor),
                  const SizedBox(width: Space.s),
                  Text('Summary', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${m.cartCount} ${m.cartCount == 1 ? 'item' : 'items'} · ${byStore.length} ${byStore.length == 1 ? 'store' : 'stores'}', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                ],
              ),
              const SizedBox(height: Space.m),
              Text('ESTIMATED TOTAL', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
              if (totals.isEmpty) Text('No prices known', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              for (final t in totals.entries) Text(priceText(t.value, t.key), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: marketColor, letterSpacing: -0.4)),
              if (m.cart.any((c) => c.price == null)) Text('Some items have no price — ask the seller', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              const SizedBox(height: Space.s),
              Text('Payment and delivery are arranged with each store in its chat.', style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
              const SizedBox(height: Space.m),
              if (byStore.length == 1) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: marketColor, foregroundColor: AppLook.onBrand(marketColor)),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('Contact ${byStore.keys.first}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onPressed: () => openChatInAccount(context, m.cart.first.chatId, hint: m.cart.first.account, openAt: m.cart.first.messageId),
                ),
                const SizedBox(height: Space.s),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.remove_shopping_cart_outlined),
                label: const Text('Empty the cart'),
                onPressed: () async {
                  if (await confirmDelete(context, title: 'Empty the cart?', message: 'Every item is taken out.', action: 'Empty')) await store.clearCart();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- AI settings ---------------------------------------------------------------

AiRunStatus aiRunStatusOf(TidyStatus s) => switch (s) {
  TidyStatus.idle => AiRunStatus.idle,
  TidyStatus.running => AiRunStatus.running,
  TidyStatus.paused => AiRunStatus.paused,
  TidyStatus.stopping => AiRunStatus.stopping,
  TidyStatus.stopped => AiRunStatus.stopped,
  TidyStatus.done => AiRunStatus.done,
};

/// The Marketplace's AI tidy-up: the shared run page (progress, what the
/// model is reading and thinking now, results) with its settings.
class MarketAiSettingsScreen extends ConsumerStatefulWidget {
  const MarketAiSettingsScreen({super.key});

  @override
  ConsumerState<MarketAiSettingsScreen> createState() => _MarketAiSettingsScreenState();
}

class _MarketAiSettingsScreenState extends ConsumerState<MarketAiSettingsScreen> {
  late final MarketStore _store = ref.read(marketProvider.notifier);
  late final _view = MappedListenable<TidyJob, AiRunView>(_store.job, (j) {
    final m = ref.read(marketProvider);
    final untidied = shopProducts(m, ref.read(marketFeedProvider)).where((x) => m.listings[x.$1.key] == null).length;
    return AiRunView(
      status: aiRunStatusOf(j.status),
      model: j.model,
      total: j.total,
      done: j.done,
      failed: j.failed,
      current: j.current,
      startedAt: j.startedAt,
      endedAt: j.endedAt,
      lastError: j.log.where((l) => l.error != null).firstOrNull?.error,
      summary: m.ai.enabled ? '${m.listings.length} products tidied · $untidied loaded ones not yet' : 'Turn it on under Settings to tidy posts into clean listings.',
      entries: [
        for (final l in j.log)
          AiRunEntry(
            title: l.name,
            subtitle: [l.store, if (l.listing?.price != null) priceText(l.listing!.price, l.listing!.currency), if (l.listing?.category.isNotEmpty ?? false) l.listing!.category, if (l.listing?.isProduct == false) 'not a product'].join(' · '),
            error: l.error,
            skipped: l.listing?.isProduct == false,
            badge: l.listing?.legit == null ? null : LegitBadge(score: l.listing!.legit!),
            at: l.at,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TidyTraceScreen(log: l))),
          ),
      ],
    );
  });

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  void _run() {
    final m = ref.read(marketProvider);
    if (!m.ai.enabled) {
      showSnack(context, 'Turn on “Tidy posts with AI” under Settings first', icon: Icons.auto_awesome_rounded);
      return;
    }
    final todo = [for (final x in shopProducts(m, ref.read(marketFeedProvider))) if (m.listings[x.$1.key] == null) x.$1].take(48).toList();
    if (todo.isEmpty) {
      showSnack(context, 'Every loaded product is already tidied', icon: Icons.check_rounded);
      return;
    }
    unawaited(_store.enrich(todo));
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(marketProvider);
    final ai = m.ai;
    final store = _store;
    Future<void> set(MarketAi v) => store.setAi(v);
    Widget sw(IconData icon, String title, String sub, bool v, MarketAi Function(bool) f) => SwitchListTile(
      secondary: lead(Icon(icon)),
      title: Text(title),
      subtitle: Text(sub, style: context.text.bodySmall),
      value: v,
      onChanged: ai.enabled ? (x) => set(f(x)) : null,
    );
    return AiRunPage(
      title: 'AI tidy-up',
      icon: Icons.auto_awesome_rounded,
      color: marketColor,
      view: _view,
      live: store.live,
      about: 'Reads each post into a clean listing: name, price, details and a trust check.',
      onRun: _run,
      onPause: store.pauseTidy,
      onResume: store.resumeTidy,
      onStop: store.stopTidy,
      onClear: store.clearTidyLog,
      settings: [
          SwitchListTile(
            secondary: lead(const Icon(Icons.auto_awesome_rounded)),
            title: const Text('Tidy posts with AI', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('A model reads each post and fills in a clean name, price and details, and judges how trustworthy it looks. Each batch of 8 posts is one model call.', style: context.text.bodySmall),
            value: ai.enabled,
            onChanged: (v) => set(ai.copyWith(enabled: v)),
          ),
          const Divider(),
          sw(Icons.bolt_rounded, 'Automatically', 'Tidy products as they show. Off: only when you ask. Pressing Stop pauses this until you run it again.', ai.auto, (v) => ai.copyWith(auto: v)),
          sw(Icons.title_rounded, 'Product names', 'A short clean name instead of the first line', ai.name, (v) => ai.copyWith(name: v)),
          sw(Icons.notes_rounded, 'Descriptions', 'What it is, its specs, what\'s included', ai.description, (v) => ai.copyWith(description: v)),
          sw(Icons.sell_outlined, 'Prices', 'The price and currency, however they\'re written', ai.price, (v) => ai.copyWith(price: v)),
          sw(Icons.verified_user_outlined, 'Trust check', 'How legitimate the listing looks, and why', ai.legit, (v) => ai.copyWith(legit: v)),
          sw(Icons.reviews_outlined, 'Ratings and reviews', 'An estimated rating, and what buyers say about this kind of item', ai.reviews, (v) => ai.copyWith(reviews: v)),
          sw(Icons.filter_alt_outlined, 'Hide posts that aren\'t products', 'Announcements, greetings and ads for the channel', ai.hideNonProducts, (v) => ai.copyWith(hideNonProducts: v)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
            child: Text('MODEL', style: context.text.labelSmall),
          ),
          AutomationModelTile(value: ai.model, onChanged: (v) => set(ai.copyWith(model: v))),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
            child: Text('If this model fails, the run switches to your chat model for the rest.', style: context.text.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: TextFormField(
              initialValue: ai.extra,
              enabled: ai.enabled,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Your own instructions (optional)', hintText: 'e.g. Prices are in birr. Flag anyone asking for payment before delivery.'),
              onChanged: (v) => set(ai.copyWith(extra: v)),
            ),
          ),
          ListTile(
            leading: lead(Icon(Icons.restart_alt_rounded, color: AppColors.danger)),
            title: const Text('Forget what the model wrote'),
            subtitle: Text('${m.listings.length} products tidied so far', style: context.text.bodySmall),
            onTap: () async {
              if (await confirmDelete(context, title: 'Forget AI listings?', message: 'Products go back to their raw posts until tidied again.', action: 'Forget')) {
                await store.forgetListings();
              }
            },
          ),
      ],
    );
  }
}

/// A product read straight from a message (for links into the shop).
Product? productOf(td.Message m, String account, String store) => Product.fromMessages([m], account, store);

/// The tidy-up as it runs: progress, what's being read now, what came
/// back, and pause, continue and stop.
class TidyMonitor extends StatelessWidget {
  const TidyMonitor({super.key, required this.store});
  final MarketStore store;

  String _elapsed(TidyJob j) {
    final from = j.startedAt;
    if (from == null) return '';
    final d = (j.endedAt != null && !j.active ? j.endedAt! : DateTime.now()).difference(from);
    return d.inMinutes > 0 ? '${d.inMinutes} min ${d.inSeconds % 60} s' : '${d.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TidyJob>(
    valueListenable: store.job,
    builder: (context, j, _) {
      if (j.status == TidyStatus.idle && j.log.isEmpty) return const SizedBox.shrink();
      final (label, color) = switch (j.status) {
        TidyStatus.running => ('Running', marketColor),
        TidyStatus.paused => ('Paused', const Color(0xFFF59E0B)),
        TidyStatus.stopping => ('Stopping after this batch', const Color(0xFFEF4444)),
        TidyStatus.stopped => ('Stopped', AppColors.text3),
        TidyStatus.done => ('Finished', const Color(0xFF22C55E)),
        TidyStatus.idle => ('Idle', AppColors.text3),
      };
      Widget stat(String v, String l) => Expanded(
        child: Column(children: [Text(v, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)), Text(l, style: context.text.labelSmall)]),
      );
      return Container(
        margin: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: Space.s),
                Expanded(child: Text(label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                if (j.model.isNotEmpty) Flexible(child: Text(j.model.split(':').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
              ],
            ),
            const SizedBox(height: Space.m),
            LinearProgressIndicator(value: j.total == 0 ? null : j.fraction, minHeight: 8, color: color, borderRadius: BorderRadius.circular(9)),
            const SizedBox(height: Space.m),
            Row(
              children: [
                stat('${j.done - j.failed}', 'tidied'),
                stat('${j.failed}', 'failed'),
                stat('${j.left}', 'left'),
                stat(_elapsed(j), 'time'),
              ],
            ),
            if (j.current.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text('READING NOW', style: context.text.labelSmall),
              for (final c in j.current.take(8)) Text('· $c', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
            if (j.active) ...[
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: j.status == TidyStatus.paused
                        ? FilledButton.icon(onPressed: store.resumeTidy, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Continue'))
                        : OutlinedButton.icon(onPressed: j.status == TidyStatus.stopping ? null : store.pauseTidy, icon: const Icon(Icons.pause_rounded), label: const Text('Pause')),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: j.status == TidyStatus.stopping ? null : store.stopTidy,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ],
            if (j.log.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(child: Text('RESULTS', style: context.text.labelSmall)),
                  if (!j.active) TextButton(onPressed: store.clearTidyLog, child: const Text('Clear')),
                ],
              ),
              for (final l in j.log.take(25))
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.s),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TidyTraceScreen(log: l))),
                  child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      if (l.error != null)
                        Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger)
                      else if (l.listing?.legit != null)
                        LegitBadge(score: l.listing!.legit!)
                      else
                        Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.text3),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600)),
                            Text(
                              l.error ?? [l.store, if (l.listing?.price != null) priceText(l.listing!.price, l.listing!.currency), if (l.listing?.category.isNotEmpty ?? false) l.listing!.category].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(color: l.error != null ? AppColors.danger : null),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                    ],
                  ),
                ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// One tidy-up result in full: what the model was asked and told, what it
/// answered, what the app read from that, and what the call cost.
class TidyTraceScreen extends StatelessWidget {
  const TidyTraceScreen({super.key, required this.log});
  final TidyLog log;

  @override
  Widget build(BuildContext context) {
    final t = log.trace;
    final l = log.listing;
    String? sentForThis;
    if (t != null && log.index != null) {
      try {
        final list = jsonDecode(t.prompt) as List;
        sentForThis = const JsonEncoder.withIndent('  ').convert(list[log.index!]);
      } catch (_) {}
    }
    String? answerForThis;
    if (t?.response != null && log.index != null) {
      try {
        final r = t!.response!;
        final list = jsonDecode(r.substring(r.indexOf('['), r.lastIndexOf(']') + 1)) as List;
        final mine = list.whereType<Map>().where((o) => (o['i'] as num?)?.toInt() == log.index).firstOrNull;
        if (mine != null) answerForThis = const JsonEncoder.withIndent('  ').convert(mine);
      } catch (_) {}
    }
    var n = 0;
    Widget step(String title, String subtitle, Widget child, {Color? color}) {
      n++;
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: (color ?? marketColor).withValues(alpha: 0.18),
              child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color ?? marketColor)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(subtitle, style: context.text.labelSmall),
                  const SizedBox(height: Space.s),
                  child,
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget code(String text, {int collapsed = 14}) => _CodeBlock(text: text, collapsed: collapsed);
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: context.text.bodySmall)),
          Expanded(child: SelectableText(v, style: context.text.bodyMedium)),
        ],
      ),
    );
    final facts = <(IconData, String)>[
      if (t != null) ...[
        (Icons.memory_rounded, t.model.split(':').last),
        (Icons.timer_outlined, '${(t.ms / 1000).toStringAsFixed(1)} s'),
        (Icons.input_rounded, '${t.inputTokens} tokens in'),
        (Icons.output_rounded, '${t.outputTokens} tokens out'),
        if (t.cost != null) (Icons.payments_outlined, 'USD ${t.cost!.toStringAsFixed(5)}'),
        (Icons.layers_outlined, '${t.batch} posts in this call'),
      ],
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('AI trace')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Row(
            children: [
              if (log.error != null)
                Icon(Icons.error_outline_rounded, color: AppColors.danger)
              else if (l?.legit != null)
                LegitBadge(score: l!.legit!, big: true),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${log.store} · ${agoText(log.at)}', style: context.text.bodySmall),
                  ],
                ),
              ),
              if (log.productKey != null)
                IconButton.filledTonal(
                  tooltip: 'Open the product',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductScreen(productKey: log.productKey!))),
                ),
            ],
          ),
          const SizedBox(height: Space.l),
          if (facts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
              child: Wrap(
                spacing: Space.l,
                runSpacing: Space.s,
                children: [
                  for (final (icon, text) in facts)
                    Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: AppColors.text3), const SizedBox(width: 4), Text(text, style: context.text.labelMedium)]),
                ],
              ),
            ),
          const SizedBox(height: Space.l),
          step('The post', 'What the channel posted', code(log.postText.isEmpty ? '(no text)' : log.postText, collapsed: 10)),
          if (t != null) ...[
            step('Instructions', 'The system prompt the model was given', code(t.system, collapsed: 8)),
            step('Request', sentForThis == null ? 'The posts sent in this call' : 'This post as sent (one of ${t.batch})', code(sentForThis ?? t.prompt), color: const Color(0xFF3B82F6)),
            if (t.error != null)
              step('Error', 'The call failed', Text(t.error!, style: TextStyle(color: AppColors.danger)), color: AppColors.danger)
            else ...[
              step('Model reply', answerForThis == null ? 'The whole answer' : 'Its answer for this post', code(answerForThis ?? t.response ?? ''), color: const Color(0xFF22C55E)),
              if (answerForThis != null && t.response != null) step('Full reply', 'Everything the model wrote for the batch', code(t.response!, collapsed: 6), color: const Color(0xFF22C55E)),
            ],
          ] else
            step('No trace', 'This result has no recorded call', const SizedBox.shrink()),
          if (l != null)
            step(
              'What the app kept',
              'The listing shown in the shop',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  kv('Name', l.name),
                  if (l.price != null) kv('Price', priceText(l.price, l.currency)),
                  if (l.category.isNotEmpty) kv('Category', l.category),
                  if (l.condition.isNotEmpty) kv('Condition', l.condition),
                  if (l.location.isNotEmpty) kv('Location', l.location),
                  if (l.contact.isNotEmpty) kv('Contact', l.contact),
                  if (l.legit != null) kv('Trust', '${l.legit}% · ${l.legitNotes}'),
                  if (l.rating != null) kv('Rating', '${l.rating} · ${l.reviews}'),
                  if (l.description.isNotEmpty) kv('Description', l.description),
                  if (l.tags.isNotEmpty) kv('Tags', l.tags.join(', ')),
                  if (!l.isProduct) kv('Not a product', 'Hidden from the shop'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Monospace text that folds to [collapsed] lines, with copy.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.text, this.collapsed = 14});
  final String text;
  final int collapsed;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = '\n'.allMatches(widget.text).length >= widget.collapsed || widget.text.length > 900;
    return Container(
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, 0),
            child: SelectableText(
              widget.text,
              maxLines: _open || !long ? null : widget.collapsed,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: AppColors.text),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (long) TextButton(onPressed: () => setState(() => _open = !_open), child: Text(_open ? 'Show less' : 'Show all')),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  showSnack(context, 'Copied', icon: Icons.copy_rounded);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A grey product card while the shop's first pages load.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(6)));
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Container(color: AppColors.surface2)),
          Padding(
            padding: const EdgeInsets.all(Space.s + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(60, 14), const SizedBox(height: 6), bar(double.infinity, 11), const SizedBox(height: 4), bar(90, 11), const SizedBox(height: 8), bar(70, 9)],
            ),
          ),
        ],
      ),
    );
  }
}
