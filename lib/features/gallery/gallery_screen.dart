import '../custom_folders/custom_folders_ui.dart' show showMarkEditor, folderIcons;
import 'dart:async';
import '../account/account_router.dart' show openChatInAccount;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData, HitTestResult;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../telegram/presentation/tg_avatar.dart';
import 'gallery.dart';
import 'gallery_search_screen.dart';

import '../sections/skeletons.dart';
/// The section's colour; the app's monochrome one in the minimal look.
Color get galleryColor => AppLook.brand(const Color(0xFF0EA5E9));

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen()));

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(galleryProvider.notifier).ready;
      if (mounted) unawaited(ref.read(galleryFeedProvider.notifier).loadAll(_mine()));
    });
  }

  List<SourceRef> _mine() => [for (final s in ref.read(galleryProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  Future<void> _sources() async {
    final picked = await pickSources(
      context,
      account: ref.read(activeAccountIdProvider),
      current: ref.read(galleryProvider).sources,
      title: 'Gallery sources',
      hint: 'Channels, groups or chats whose photos and videos you want in one gallery.',
    );
    if (picked == null) return;
    await ref.read(galleryProvider.notifier).setSources(picked);
    unawaited(ref.read(galleryFeedProvider.notifier).loadAll(_mine()));
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    final all = galleryItems(g, feed);
    final videos = all.where((i) => i.video).length;
    return SectionScaffold(
      title: 'Gallery',
      icon: Icons.photo_library_rounded,
      color: galleryColor,
      tabs: const [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.photo_outlined, size: 16), SizedBox(width: 6), Text('Library')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_outlined, size: 16), SizedBox(width: 6), Text('Videos')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.photo_album_outlined, size: 16), SizedBox(width: 6), Text('Albums')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.favorite_border_rounded, size: 16), SizedBox(width: 6), Text('Favorites')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_outlined, size: 16), SizedBox(width: 6), Text('Sources')])),
      ],
      actions: [
        IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => GallerySearchScreen.open(context)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'hidden') await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HiddenGalleryScreen()));
            if (v == 'auto') await ref.read(galleryProvider.notifier).setAutoDownload(!g.autoDownload);
            if (v.startsWith('c')) await ref.read(galleryProvider.notifier).setColumns(int.parse(v.substring(1)));
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'hidden', child: Text('Hidden (${g.hidden.length})')),
            CheckedPopupMenuItem(value: 'auto', checked: g.autoDownload, child: const Text('Download automatically')),
            const PopupMenuDivider(),
            for (final c in const [3, 4, 5]) CheckedPopupMenuItem(value: 'c$c', checked: g.columns == c, child: Text('$c per row')),
          ],
        ),
        IconButton(tooltip: 'Sources', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: _sources),
      ],
      hero: SectionHero(
        subtitle: g.sources.isEmpty ? 'Photos and videos from your chats and channels, in one gallery.' : 'Photos and videos from ${g.sources.length} ${g.sources.length == 1 ? 'chat' : 'chats'}',
        stats: [
          ('${all.length - videos}', 'photos'),
          ('$videos', 'videos'),
          ('${g.albums.length}', 'albums'),
          ('${g.favorites.length}', 'favorites'),
        ],
      ),
      views: [
        _Library(onSources: _sources),
        _Library(onSources: _sources, videos: true),
        const _AlbumsTab(),
        const _FavoritesTab(),
        _SourcesTab(onSources: _sources),
      ],
    );
  }
}

// ---- the grid ------------------------------------------------------------------

/// Items in a grid under month headings, with tap to view and long-press
/// to pick several; picked items get a bar of actions.
class GalleryGrid extends ConsumerStatefulWidget {
  const GalleryGrid({super.key, required this.items, this.header = const [], this.onEnd, this.albumId, this.hiddenView = false, this.loading = false, this.empty});
  final List<GalleryItem> items;
  final List<Widget> header;
  final VoidCallback? onEnd;

  /// In an album: "Remove from album" instead of "Add to album".
  final String? albumId;
  final bool hiddenView;
  final bool loading;
  final Widget? empty;

  @override
  ConsumerState<GalleryGrid> createState() => _GalleryGridState();
}

class _GalleryGridState extends ConsumerState<GalleryGrid> {
  /// Hero tags are this grid's own: the same photo can be in two grids
  /// (Library and Videos tabs, an album) at once.
  late final String _hero = 'g${identityHashCode(this)}';
  final _picked = <String>{};
  late final _drag = DragPick(host: this, picked: _picked, keyAt: (i) => i >= 0 && i < widget.items.length ? widget.items[i].key : null, changed: () => setState(() {}));

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  List<GalleryItem> get _pickedItems => [for (final i in widget.items) if (_picked.contains(i.key)) i];

  void _toggle(GalleryItem i) => setState(() => _picked.contains(i.key) ? _picked.remove(i.key) : _picked.add(i.key));

  Future<void> _act(String v) async {
    final items = _pickedItems;
    final store = ref.read(galleryProvider.notifier);
    switch (v) {
      case 'fav':
        final on = !items.every((i) => ref.read(galleryProvider).isFavorite(i.key));
        await store.setFavorite(items, on);
      case 'album':
        await addToAlbumFlow(context, ref, items);
      case 'unalbum':
        await store.removeFromAlbum(widget.albumId!, items.map((i) => i.key));
      case 'hide':
        await store.setHidden(items, !widget.hiddenView);
        if (mounted) showSnack(context, widget.hiddenView ? 'Shown again' : 'Hidden · find them under Hidden', icon: Icons.visibility_off_outlined);
      case 'save':
        await saveToDevice(context, ref, items);
      case 'share':
        await shareItems(context, ref, items);
      case 'all':
        setState(() => _picked.addAll(widget.items.map((i) => i.key)));
        return;
    }
    if (mounted) setState(_picked.clear);
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(galleryProvider);
    final items = widget.items;
    final groups = <String, List<GalleryItem>>{};
    for (final i in items) {
      final now = DateTime.now();
      final label = i.date.year == now.year && i.date.month == now.month ? 'This month' : '${_months[i.date.month - 1]} ${i.date.year}';
      groups.putIfAbsent(label, () => []).add(i);
    }
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? g.columns + 3 : (width > 600 ? g.columns + 1 : g.columns);
    final selecting = _picked.isNotEmpty;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 900) widget.onEnd?.call();
            return false;
          },
          child: CustomScrollView(
            slivers: [
              ...widget.header,
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: widget.loading ? Align(alignment: Alignment.topCenter, child: SkeletonTiles(columns: cols)) : (widget.empty ?? Center(child: Text('Nothing here', style: context.text.bodySmall))),
                ),
              for (final e in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                        Text('${e.value.length}', style: context.text.labelSmall),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 2, crossAxisSpacing: 2),
                    itemCount: e.value.length,
                    itemBuilder: (_, i) {
                      final item = e.value[i];
                      final at = items.indexOf(item);
                      return _Cell(
                        hero: _hero,
                        autoload: g.autoDownload,
                        item: item,
                        favorite: g.isFavorite(item.key),
                        picked: selecting ? _picked.contains(item.key) : null,
                        onTap: () => selecting ? _toggle(item) : openGalleryViewer(context, items, at, hero: _hero),
                        onLongPress: () => _toggle(item),
                        index: at,
                        drag: _drag,
                      );
                    },
                  ),
                ),
              ],
              if (widget.loading && items.isNotEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
              SliverToBoxAdapter(child: SizedBox(height: selecting ? 120 : Space.x4)),
            ],
          ),
        ),
        if (selecting)
          Positioned(
            left: Space.m,
            right: Space.m,
            bottom: Space.m,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_picked.clear)),
                      Text('${_picked.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all_rounded), onPressed: () => _act('all')),
                      IconButton(tooltip: 'Favorite', icon: const Icon(Icons.favorite_border_rounded), onPressed: () => _act('fav')),
                      if (widget.albumId == null)
                        IconButton(tooltip: 'Add to album', icon: const Icon(Icons.photo_album_outlined), onPressed: () => _act('album'))
                      else
                        IconButton(tooltip: 'Remove from album', icon: const Icon(Icons.playlist_remove_rounded), onPressed: () => _act('unalbum')),
                      IconButton(tooltip: widget.hiddenView ? 'Unhide' : 'Hide', icon: Icon(widget.hiddenView ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => _act('hide')),
                      IconButton(tooltip: 'Save to device', icon: const Icon(Icons.download_rounded), onPressed: () => _act('save')),
                      IconButton(tooltip: 'Share', icon: const Icon(Icons.forward_rounded), onPressed: () => _act('share')),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Marks a grid cell with its place, so a drag can tell which it's over.
class _CellIndex {
  const _CellIndex(this.i);
  final int i;
}

/// Long-press a photo, then drag across others to pick (or unpick) the
/// whole run between, like a phone's own gallery. Near the top or bottom
/// edge the grid scrolls by itself.
class DragPick {
  DragPick({required this.host, required this.picked, required this.keyAt, required this.changed, this.canPick});
  final State host;
  final Set<String> picked;
  final String? Function(int index) keyAt;
  final bool Function(String key)? canPick;
  final VoidCallback changed;

  int? _anchor;
  int? _last;
  bool _adding = true;
  Set<String> _before = {};
  ScrollPosition? _pos;
  Offset? _at;
  Timer? _scroll;

  bool get active => _anchor != null;

  void start(int i, BuildContext cell, Offset global) {
    final k = keyAt(i);
    if (k == null || !(canPick?.call(k) ?? true)) return;
    _anchor = i;
    _last = i;
    _before = {...picked};
    _adding = !picked.contains(k);
    _pos = Scrollable.maybeOf(cell)?.position;
    _at = global;
    HapticFeedback.mediumImpact();
    _apply(i);
    _scroll?.cancel();
    _scroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScroll());
  }

  void move(Offset global) {
    if (_anchor == null) return;
    _at = global;
    final i = _indexAt(global);
    if (i != null && i != _last) {
      _last = i;
      HapticFeedback.selectionClick();
      _apply(i);
    }
  }

  void end() {
    _scroll?.cancel();
    _scroll = null;
    _anchor = null;
    _last = null;
  }

  void dispose() => _scroll?.cancel();

  void _apply(int to) {
    final a = _anchor!;
    final lo = a < to ? a : to, hi = a < to ? to : a;
    picked
      ..clear()
      ..addAll(_before);
    for (var i = lo; i <= hi; i++) {
      final k = keyAt(i);
      if (k == null || !(canPick?.call(k) ?? true)) continue;
      _adding ? picked.add(k) : picked.remove(k);
    }
    changed();
  }

  int? _indexAt(Offset global) {
    if (!host.mounted) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, global, View.of(host.context).viewId);
    for (final e in result.path) {
      final t = e.target;
      if (t is RenderMetaData && t.metaData is _CellIndex) return (t.metaData as _CellIndex).i;
    }
    return null;
  }

  void _autoScroll() {
    final p = _pos, g = _at;
    if (p == null || g == null || !host.mounted || !p.hasPixels) return;
    final h = MediaQuery.sizeOf(host.context).height;
    const edge = 90.0;
    final top = MediaQuery.paddingOf(host.context).top + kToolbarHeight + 40;
    var v = 0.0;
    if (g.dy < top + edge) {
      v = -((top + edge - g.dy) / edge).clamp(0.0, 1.5) * 16;
    } else if (g.dy > h - edge) {
      v = ((g.dy - (h - edge)) / edge).clamp(0.0, 1.5) * 16;
    }
    if (v == 0) return;
    final to = (p.pixels + v).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to == p.pixels) return;
    p.jumpTo(to);
    move(g);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({this.hero = 'g', required this.item, required this.favorite, required this.picked, required this.onTap, required this.onLongPress, this.autoload = true, this.index, this.drag});
  final bool autoload;

  /// Its place in the grid and the drag-to-pick it joins.
  final int? index;
  final DragPick? drag;
  final String hero;
  final GalleryItem item;
  final bool favorite;
  final bool? picked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final d = drag, i = index;
    return MetaData(
      metaData: i == null ? null : _CellIndex(i),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
    onTap: onTap,
    onLongPress: d == null || i == null ? onLongPress : null,
    onLongPressStart: d == null || i == null ? null : (e) => d.start(i, context, e.globalPosition),
    onLongPressMoveUpdate: d == null ? null : (e) => d.move(e.globalPosition),
    onLongPressEnd: d == null ? null : (_) => d.end(),
    onLongPressCancel: d?.end,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Hero(tag: '$hero-${item.key}', child: TgPicture(file: item.thumb, mini: item.mini, cacheWidth: 360, autoload: autoload, account: item.account)),
        if (item.video)
          Positioned(
            right: 4,
            bottom: 4,
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded, size: 15, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                if (item.seconds > 0) ...[
                  const SizedBox(width: 2),
                  Text(_clock(item.seconds), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)])),
                ],
              ],
            ),
          ),
        if (favorite) const Positioned(left: 4, bottom: 4, child: Icon(Icons.favorite_rounded, size: 14, color: Colors.white, shadows: [Shadow(blurRadius: 6)])),
        if (picked != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: picked! ? galleryColor.withValues(alpha: 0.35) : Colors.transparent,
            alignment: Alignment.topRight,
            padding: const EdgeInsets.all(5),
            child: Icon(picked! ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: Colors.white, size: 22),
          ),
      ],
    ),
      ),
    );
  }
}

String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

// ---- tabs --------------------------------------------------------------------

class _Library extends ConsumerStatefulWidget {
  const _Library({required this.onSources, this.videos = false});
  final VoidCallback onSources;
  final bool videos;

  @override
  ConsumerState<_Library> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<_Library> with AutomaticKeepAliveClientMixin {
  String? _source;

  @override
  bool get wantKeepAlive => true;

  void _more() {
    final g = ref.read(galleryProvider);
    final feed = ref.read(galleryFeedProvider);
    if (feed.anyLoading) return;
    final mine = [for (final s in g.sources) if (!s.hidden && s.account == ref.read(activeAccountIdProvider) && feed.hasMore(s.key) && (_source == null || s.key == _source)) s];
    if (mine.isEmpty) return;
    pooled(mine, 3, (s) => ref.read(galleryFeedProvider.notifier).load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    final ready = ref.read(galleryProvider.notifier).isReady;
    if (g.sources.isEmpty && !ready) return GalleryGrid(items: const [], loading: true);
    if (g.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.photo_library_outlined,
          title: 'No sources yet',
          body: 'Pick the channels, groups and chats that post photos and videos. They gather here by month, with albums and favorites.',
          action: 'Add sources',
          onAction: widget.onSources,
        ),
      );
    }
    final items = galleryItems(g, feed, sourceKey: _source, videos: widget.videos ? true : null);
    final account = ref.watch(activeAccountIdProvider);
    // Still coming: a source of this account not loaded (or failed) yet.
    final pending = g.sources.any((s) => s.account == account && !feed.bySource.containsKey(s.key) && !feed.errors.containsKey(s.key));
    return RefreshIndicator(
      onRefresh: () => ref.read(galleryFeedProvider.notifier).loadAll(g.sources.where((s) => s.account == account), refresh: true),
      child: GalleryGrid(
        items: items,
        loading: feed.anyLoading || pending,
        onEnd: _more,
        header: [
          if (!widget.videos) const SliverToBoxAdapter(child: OnThisDayStrip()),
          if (g.sources.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  children: [
                    Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _source == null, onSelected: (_) => setState(() => _source = null))),
                    for (final s in g.sources.where((s) => !s.hidden)) SourceChip(source: s, selected: _source == s.key, onTap: () => setState(() => _source = _source == s.key ? null : s.key)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    if (g.favorites.isEmpty) {
      return const SingleChildScrollView(child: SectionEmpty(icon: Icons.favorite_border_rounded, title: 'No favorites yet', body: 'Tap the heart on a photo or video, or pick several and favorite them.'));
    }
    return KeyedItems(keys: g.favorites, builder: (items, loading) => GalleryGrid(items: items, loading: loading));
  }
}

/// Loads items by key (from the feed, else their posts) and builds with them.
class KeyedItems extends ConsumerStatefulWidget {
  const KeyedItems({super.key, required this.keys, required this.builder});
  final List<String> keys;
  final Widget Function(List<GalleryItem> items, bool loading) builder;

  @override
  ConsumerState<KeyedItems> createState() => _KeyedItemsState();
}

class _KeyedItemsState extends ConsumerState<KeyedItems> {
  List<GalleryItem> _items = const [];
  bool _loading = true;

  /// Null until the first load, so an empty list (a new album) still loads
  /// once and stops spinning.
  String? _for;

  void _load() {
    final sig = widget.keys.join(',');
    if (sig == _for) return;
    _for = sig;
    if (widget.keys.isEmpty) {
      _items = const [];
      _loading = false;
      return;
    }
    // Keys already shown stay; only new ones need fetching.
    final have = {for (final i in _items) i.key};
    if (widget.keys.every(have.contains)) {
      _loading = false;
      return;
    }
    ref.read(galleryFeedProvider.notifier).fetchMany(widget.keys).then((v) {
      if (mounted && sig == _for) setState(() {
        _items = v;
        _loading = false;
      });
    }, onError: (_) {
      if (mounted && sig == _for) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final hidden = ref.watch(galleryProvider.select((g) => g.hidden));
    return widget.builder([for (final i in _items) if (widget.keys.contains(i.key) && !hidden.contains(i.key)) i], _loading);
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final a = await editAlbum(context, ref);
    // Straight into the new album, where photos can be added.
    if (a != null && context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumScreen(albumId: a.id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    final width = MediaQuery.sizeOf(context).width;
    if (g.albums.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.photo_album_outlined,
          title: 'No albums yet',
          body: 'Albums gather photos and videos from any of your chats in one place. Make one, then add photos to it.',
          action: 'New album',
          onAction: () => _create(context, ref),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4 + 80),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: width > 700 ? 4 : 2, mainAxisSpacing: Space.l, crossAxisSpacing: Space.l, childAspectRatio: 0.8),
      itemCount: g.albums.length + 1,
      itemBuilder: (_, i) {
        if (i == g.albums.length) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Material(
                  color: galleryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.l),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.l),
                    onTap: () => _create(context, ref),
                    child: Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: galleryColor.withValues(alpha: 0.35), width: 1.5)),
                      child: Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: galleryColor.withValues(alpha: 0.18)),
                          child: Icon(Icons.add_rounded, size: 30, color: galleryColor),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
              Text('New album', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('Collect photos', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
            ],
          );
        }
        final a = g.albums[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumScreen(albumId: a.id))),
          onLongPress: () => editAlbum(context, ref, album: a),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: AlbumCover(album: a)),
              const SizedBox(height: Space.s),
              albumTitle(a, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), size: 16),
              Text(a.keys.isEmpty ? 'Empty' : '${a.keys.length} ${a.keys.length == 1 ? 'item' : 'items'}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        );
      },
    );
  }
}

/// An album's cover: its newest item big with the next two beside it, from
/// the loaded feed when it can be (sharp), else their blurry previews.
class AlbumCover extends ConsumerWidget {
  const AlbumCover({super.key, required this.album, this.radius = Radii.l});
  final GalleryAlbum album;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(galleryFeedProvider);
    final feed = ref.read(galleryFeedProvider.notifier);
    final autoload = ref.watch(galleryProvider.select((g) => g.autoDownload));
    final keys = album.keys.take(3).toList();
    Widget tile(String k) {
      final item = feed.byKey(k);
      if (item != null) return TgPicture(file: item.thumb, mini: item.mini, cacheWidth: 400, autoload: autoload, account: item.account);
      final m = album.minis[k];
      if (m != null) return Image.memory(base64Decode(m), fit: BoxFit.cover, gaplessPlayback: true);
      return ColoredBox(color: AppColors.surface2);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: keys.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [galleryColor.withValues(alpha: 0.28), galleryColor.withValues(alpha: 0.08)]),
              ),
              child: Center(child: albumMark(album, size: 46, color: galleryColor) ?? Icon(Icons.photo_album_outlined, size: 40, color: galleryColor)),
            )
          : keys.length < 3
          ? SizedBox.expand(child: tile(keys.first))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: tile(keys[0])),
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [Expanded(child: tile(keys[1])), const SizedBox(height: 2), Expanded(child: tile(keys[2]))],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SourcesTab extends ConsumerWidget {
  const _SourcesTab({required this.onSources});
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    final store = ref.read(galleryProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.x4),
      children: [
        for (final s in g.sources)
          ListTile(
            leading: TgAvatar(chatId: s.chatId, title: s.title, size: 44, accountId: s.account),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [feed.loading.contains(s.key) ? 'Loading…' : '${feed.bySource[s.key]?.length ?? 0}${feed.hasMore(s.key) ? '+' : ''} items', if (s.hidden) 'hidden from Library'].join(' · '),
              style: context.text.bodySmall,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SourceGalleryScreen(source: s))),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'hide') await store.setSourceHidden(s.key, !s.hidden);
                if (v == 'remove') await store.removeSource(s.key);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'hide', child: Text(s.hidden ? 'Show in Library' : 'Hide from Library')),
                PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ),
        ListTile(leading: lead(const Icon(Icons.add_rounded)), title: const Text('Add sources'), onTap: onSources),
      ],
    );
  }
}

/// One source's photos and videos.
class SourceGalleryScreen extends ConsumerWidget {
  const SourceGalleryScreen({super.key, required this.source});
  final SourceRef source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    if (!feed.bySource.containsKey(source.key) && !feed.loading.contains(source.key)) {
      Future.microtask(() => ref.read(galleryFeedProvider.notifier).load(source));
    }
    return Scaffold(
      appBar: AppBar(title: Row(children: [TgAvatar(chatId: source.chatId, title: source.title, size: 28, accountId: source.account), const SizedBox(width: Space.s), Expanded(child: Text(source.title, overflow: TextOverflow.ellipsis))])),
      body: GalleryGrid(
        items: galleryItems(g, feed, sourceKey: source.key),
        loading: feed.loading.contains(source.key),
        onEnd: () {
          if (!feed.loading.contains(source.key) && feed.hasMore(source.key)) ref.read(galleryFeedProvider.notifier).load(source, more: true);
        },
      ),
    );
  }
}

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});
  final String albumId;

  Future<void> _add(BuildContext context, WidgetRef ref, GalleryAlbum a) async {
    final picked = await Navigator.of(context).push<List<GalleryItem>>(MaterialPageRoute(builder: (_) => GalleryPickerScreen(title: 'Add to ${a.name}', exclude: a.keys.toSet())));
    if (picked == null || picked.isEmpty) return;
    final n = await ref.read(galleryProvider.notifier).addToAlbum(a.id, picked);
    if (context.mounted) showSnack(context, n == 0 ? 'Already in this album' : 'Added $n to ${a.name}', icon: Icons.photo_album_outlined);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(galleryProvider.select((g) => g.albums.where((a) => a.id == albumId).firstOrNull));
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const SectionEmpty(icon: Icons.photo_album_outlined, title: 'Album deleted', body: 'This album isn’t here any more. Its photos are still in their chats.'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            albumTitle(a, size: 18),
            Text(a.keys.isEmpty ? 'Empty album' : '${a.keys.length} ${a.keys.length == 1 ? 'item' : 'items'}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Add photos', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: () => _add(context, ref, a)),
          IconButton(tooltip: 'Edit album', icon: const Icon(Icons.edit_outlined), onPressed: () => editAlbum(context, ref, album: a)),
        ],
      ),
      floatingActionButton: a.keys.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: galleryColor,
              foregroundColor: AppLook.onBrand(galleryColor),
              onPressed: () => _add(context, ref, a),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
      body: KeyedItems(
        keys: a.keys,
        builder: (items, loading) => GalleryGrid(
          items: items,
          loading: loading,
          albumId: a.id,
          empty: SectionEmpty(
            icon: Icons.add_photo_alternate_outlined,
            title: 'This album is empty',
            body: 'Pick photos and videos from your gallery to add them here.',
            action: 'Add photos',
            onAction: () => _add(context, ref, a),
          ),
        ),
      ),
    );
  }
}

/// Lets the person tick photos and videos from the Library; returns them.
class GalleryPickerScreen extends ConsumerStatefulWidget {
  const GalleryPickerScreen({super.key, required this.title, this.exclude = const {}});
  final String title;

  /// Already in the album: shown faded and not pickable.
  final Set<String> exclude;

  @override
  ConsumerState<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends ConsumerState<GalleryPickerScreen> {
  final _picked = <String>{};
  List<GalleryItem> _items = const [];
  late final _drag = DragPick(
    host: this,
    picked: _picked,
    keyAt: (i) => i >= 0 && i < _items.length ? _items[i].key : null,
    canPick: (k) => !widget.exclude.contains(k),
    changed: () => setState(() {}),
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }
  String? _source;
  bool? _videos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(galleryProvider.notifier).ready;
      if (!mounted) return;
      final mine = [for (final s in ref.read(galleryProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];
      unawaited(ref.read(galleryFeedProvider.notifier).loadAll(mine));
    });
  }

  void _more() {
    final g = ref.read(galleryProvider);
    final feed = ref.read(galleryFeedProvider);
    if (feed.anyLoading) return;
    final mine = [for (final s in g.sources) if (!s.hidden && s.account == ref.read(activeAccountIdProvider) && feed.hasMore(s.key) && (_source == null || s.key == _source)) s];
    if (mine.isNotEmpty) pooled(mine, 3, (s) => ref.read(galleryFeedProvider.notifier).load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(galleryProvider);
    final feed = ref.watch(galleryFeedProvider);
    final items = _items = galleryItems(g, feed, sourceKey: _source, videos: _videos);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 7 : (width > 600 ? 5 : 4);
    final pickable = [for (final i in items) if (!widget.exclude.contains(i.key)) i.key];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_picked.isEmpty ? widget.title : '${_picked.length} picked'),
            Text('Hold and drag to pick many', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ],
        ),
        actions: [
          if (pickable.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => pickable.every(_picked.contains) ? _picked.removeAll(pickable) : _picked.addAll(pickable)),
              child: Text(pickable.every(_picked.contains) ? 'None' : 'All'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: galleryColor, foregroundColor: AppLook.onBrand(galleryColor)),
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, [for (final i in items) if (_picked.contains(i.key)) i]),
            icon: const Icon(Icons.check_rounded),
            label: Text(_picked.isEmpty ? 'Pick photos or videos' : 'Add ${_picked.length}'),
          ),
        ),
      ),
      body: g.sources.isEmpty
          ? const SingleChildScrollView(child: SectionEmpty(icon: Icons.photo_library_outlined, title: 'No sources yet', body: 'Add chats or channels as gallery sources first; their photos show here to pick from.'))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 900) _more();
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
                        children: [
                          for (final (v, label) in const [(null, 'All'), (false, 'Photos'), (true, 'Videos')])
                            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _videos == v, onSelected: (_) => setState(() => _videos = v))),
                          if (g.sources.length > 1) ...[
                            const SizedBox(width: Space.s),
                            for (final s in g.sources.where((s) => !s.hidden)) SourceChip(source: s, selected: _source == s.key, onTap: () => setState(() => _source = _source == s.key ? null : s.key)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: feed.anyLoading ? const Align(alignment: Alignment.topCenter, child: SkeletonTiles()) : Center(child: Text('Nothing to pick here', style: context.text.bodySmall)),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(2),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 2, crossAxisSpacing: 2),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];
                          final there = widget.exclude.contains(item.key);
                          return Opacity(
                            opacity: there ? 0.35 : 1,
                            child: _Cell(
                              hero: 'pick',
                              autoload: g.autoDownload,
                              item: item,
                              favorite: false,
                              picked: there ? null : _picked.contains(item.key),
                              onTap: () {
                                if (there) return showSnack(context, 'Already in this album', icon: Icons.check_rounded);
                                setState(() => _picked.contains(item.key) ? _picked.remove(item.key) : _picked.add(item.key));
                              },
                              onLongPress: () {},
                              index: i,
                              drag: _drag,
                            ),
                          );
                        },
                      ),
                    ),
                  if (feed.anyLoading && items.isNotEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
                ],
              ),
            ),
    );
  }
}

class HiddenGalleryScreen extends ConsumerWidget {
  const HiddenGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden')),
      body: KeyedItemsAll(
        keys: g.hidden.toList(),
        builder: (items, loading) => GalleryGrid(
          items: items,
          loading: loading,
          hiddenView: true,
          empty: const SectionEmpty(icon: Icons.visibility_off_outlined, title: 'Nothing hidden', body: 'Hidden photos and videos stay out of the Library and albums. Find them here to show them again.'),
        ),
      ),
    );
  }
}

/// Like [KeyedItems], hidden ones included.
class KeyedItemsAll extends ConsumerStatefulWidget {
  const KeyedItemsAll({super.key, required this.keys, required this.builder});
  final List<String> keys;
  final Widget Function(List<GalleryItem> items, bool loading) builder;

  @override
  ConsumerState<KeyedItemsAll> createState() => _KeyedItemsAllState();
}

class _KeyedItemsAllState extends ConsumerState<KeyedItemsAll> {
  List<GalleryItem> _items = const [];
  bool _loading = true;
  String? _for;

  @override
  Widget build(BuildContext context) {
    final sig = widget.keys.join(',');
    if (sig != _for) {
      _for = sig;
      if (widget.keys.isEmpty) {
        _items = const [];
        _loading = false;
      } else {
        ref.read(galleryFeedProvider.notifier).fetchMany(widget.keys).then((v) {
          if (mounted && sig == _for) setState(() {
            _items = v;
            _loading = false;
          });
        }, onError: (_) {
          if (mounted && sig == _for) setState(() => _loading = false);
        });
      }
    }
    return widget.builder([for (final i in _items) if (widget.keys.contains(i.key)) i], _loading);
  }
}

// ---- actions -----------------------------------------------------------------

const _albumEmojis = ['📸', '🌍', '❤️', '🎉', '🍲', '🐾', '🏖️', '🎨', '👨‍👩‍👧', '🌅', '🎓', '🏠', '✈️', '🎂', '🌸', '🔥', '⭐', '🖼️', '📚', '💼'];

/// An album's mark: its icon, its emoji, or nothing (null).
Widget? albumMark(GalleryAlbum a, {double size = 20, Color? color}) {
  final icon = folderIcons[a.icon];
  if (icon != null) return Icon(icon, size: size, color: color ?? AppColors.text2);
  if (a.emoji.isEmpty) return null;
  return Text(a.emoji, style: TextStyle(fontSize: size * 0.9, height: 1.1));
}

/// An album's name with its mark before it.
Widget albumTitle(GalleryAlbum a, {TextStyle? style, double size = 16}) {
  final mark = albumMark(a, size: size);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (mark != null) ...[mark, const SizedBox(width: 6)],
      Flexible(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
    ],
  );
}

Future<GalleryAlbum?> editAlbum(BuildContext context, WidgetRef ref, {GalleryAlbum? album, List<GalleryItem> items = const []}) async {
  final r = await showMarkEditor(
    context,
    title: album == null ? (items.isEmpty ? 'New album' : 'New album with ${items.length}') : 'Edit album',
    action: album == null ? 'Create album' : 'Save',
    name: album?.name ?? '',
    emoji: album == null ? '📸' : album.emoji,
    icon: album?.icon,
    isNew: album == null,
    emojis: _albumEmojis,
    hint: 'Trips, Family, Inspiration…',
    destructive: album == null ? null : 'Delete album',
    preview: items.isEmpty
        ? null
        : SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length.clamp(0, 12),
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(Radii.s), child: SizedBox.square(dimension: 64, child: TgPicture(file: items[i].thumb, mini: items[i].mini, cacheWidth: 200, account: items[i].account))),
            ),
          ),
  );
  final store = ref.read(galleryProvider.notifier);
  if (r == null) return null;
  if (r.name == '__delete__' && album != null) {
    if (context.mounted && await confirmDelete(context, title: 'Delete “${album.name}”?', message: 'The album goes; its photos stay in their chats.')) {
      await store.deleteAlbum(album.id);
    }
    return null;
  }
  final name = r.name.trim();
  if (album == null) return store.createAlbum(name, emoji: r.emoji, icon: r.icon, items: items);
  await store.updateAlbum(album.id, (a) => a.copyWith(name: name.isEmpty ? a.name : name, emoji: r.emoji, icon: r.icon, clearIcon: r.icon == null));
  return null;
}

Future<void> addToAlbumFlow(BuildContext context, WidgetRef ref, List<GalleryItem> items) async {
  final g = ref.read(galleryProvider);
  final picked = await showAppSheet<String>(
    context,
    initialSize: 0.55,
    builder: (context, scroll) => ListView(
      controller: scroll,
      children: [
        Center(child: Text('Add ${items.length} to…', style: context.text.titleMedium)),
        ListTile(leading: lead(const Icon(Icons.add_rounded)), title: const Text('New album'), onTap: () => Navigator.pop(context, '+')),
        for (final a in g.albums)
          ListTile(
            leading: lead(albumMark(a, size: 22) ?? const Icon(Icons.photo_album_outlined)),
            title: Text(a.name),
            subtitle: Text('${a.keys.length} items', style: context.text.bodySmall),
            onTap: () => Navigator.pop(context, a.id),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  if (picked == '+') {
    final a = await editAlbum(context, ref, items: items);
    if (a != null && context.mounted) showSnack(context, 'Made “${a.name}”', icon: Icons.photo_album_outlined);
    return;
  }
  final n = await ref.read(galleryProvider.notifier).addToAlbum(picked, items);
  if (context.mounted) showSnack(context, n == 0 ? 'Already in that album' : 'Added $n', icon: Icons.photo_album_outlined);
}

Future<void> saveToDevice(BuildContext context, WidgetRef ref, List<GalleryItem> items) async {
  showSnack(context, 'Saving ${items.length}…', icon: Icons.download_rounded);
  var ok = 0;
  for (final i in items) {
    final f = i.full;
    if (f == null) continue;
    try {
      final path = await ref.read(fileLoaderFamily(i.account)).download(f, priority: 16);
      if (path == null) continue;
      i.video ? await Gal.putVideo(path, album: 'Triangle') : await Gal.putImage(path, album: 'Triangle');
      ok++;
    } catch (_) {}
  }
  if (context.mounted) showSnack(context, 'Saved $ok of ${items.length} to your phone\'s gallery', icon: Icons.download_done_rounded);
}

Future<void> shareItems(BuildContext context, WidgetRef ref, List<GalleryItem> items) async {
  final chat = await pickTelegramChat(context, title: 'Share to…');
  if (chat == null) return;
  final byChat = <int, List<int>>{};
  for (final i in items) {
    byChat.putIfAbsent(i.chatId, () => []).add(i.messageId);
  }
  try {
    var n = 0;
    for (final e in byChat.entries) {
      n += await ref.read(toolRunnerFamily(items.first.account)).forwardTo(chat, e.key, e.value);
    }
    if (context.mounted) showSnack(context, 'Shared $n', icon: Icons.forward_rounded);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t share: $e', icon: Icons.error_outline_rounded);
  }
}

// ---- viewer ------------------------------------------------------------------

void openGalleryViewer(BuildContext context, List<GalleryItem> items, int index, {String hero = 'g'}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => GalleryViewer(items: items, index: index, hero: hero),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

class GalleryViewer extends ConsumerStatefulWidget {
  const GalleryViewer({super.key, required this.items, required this.index, this.hero = 'g'});
  final String hero;
  final List<GalleryItem> items;
  final int index;

  @override
  ConsumerState<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends ConsumerState<GalleryViewer> {
  late final _pages = PageController(initialPage: widget.index);
  late int _at = widget.index;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _info(GalleryItem i) => showAppSheet<void>(
    context,
    initialSize: 0.45,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.all(Space.l),
      children: [
        Text('Details', style: context.text.titleMedium),
        const SizedBox(height: Space.m),
        ListTile(contentPadding: EdgeInsets.zero, leading: TgAvatar(chatId: i.chatId, title: i.source, size: 36, accountId: i.account), title: Text(i.source)),
        Text('${i.date.day} ${_months[i.date.month - 1]} ${i.date.year}, ${i.date.hour.toString().padLeft(2, '0')}:${i.date.minute.toString().padLeft(2, '0')}'),
        if (i.width > 0) Text('${i.width} × ${i.height}'),
        if (i.size > 0) Text(sizeText(i.size)),
        if (i.seconds > 0) Text(_clock(i.seconds)),
        if (i.caption.isNotEmpty) ...[const SizedBox(height: Space.m), SelectableText(i.caption)],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(galleryProvider);
    final item = widget.items[_at];
    final fav = g.isFavorite(item.key);
    final hidden = g.hidden.contains(item.key);
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => setState(() => _chrome = !_chrome),
              child: _Page(item: widget.items[i], active: i == _at, hero: widget.hero),
            ),
          ),
          if (_chrome) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(Space.s, MediaQuery.paddingOf(context).top + Space.xs, Space.s, Space.s),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA000000), Color(0x00000000)])),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close_rounded, color: white), onPressed: () => Navigator.pop(context)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontWeight: FontWeight.w700)),
                          Text('${item.date.day} ${_months[item.date.month - 1]} ${item.date.year} · ${_at + 1} of ${widget.items.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.info_outline_rounded, color: white), onPressed: () => _info(item)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(Space.s, Space.l, Space.s, MediaQuery.paddingOf(context).bottom + Space.s),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)])),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                        child: Text(item.caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white)),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ViewerAction(
                          icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: fav ? const Color(0xFFFF4D6D) : white,
                          label: fav ? 'Loved' : 'Favorite',
                          onTap: () => ref.read(galleryProvider.notifier).setFavorite([item], !fav),
                        ),
                        _ViewerAction(icon: Icons.photo_album_outlined, label: 'Album', onTap: () => addToAlbumFlow(context, ref, [item])),
                        _ViewerAction(icon: Icons.forward_rounded, label: 'Share', onTap: () => shareItems(context, ref, [item])),
                        _ViewerAction(icon: Icons.download_rounded, label: 'Save', onTap: () => saveToDevice(context, ref, [item])),
                        _ViewerAction(
                          icon: hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          label: hidden ? 'Unhide' : 'Hide',
                          onTap: () async {
                            await ref.read(galleryProvider.notifier).setHidden([item], !hidden);
                            if (context.mounted && !hidden) showSnack(context, 'Hidden · find it under Hidden', icon: Icons.visibility_off_outlined);
                          },
                        ),
                        _ViewerAction(
                          icon: Icons.forum_outlined,
                          label: 'Post',
                          onTap: () => openChatInAccount(context, item.chatId, hint: item.account, openAt: item.messageId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Page extends ConsumerStatefulWidget {
  const _Page({required this.item, required this.active, this.hero = 'g'});
  final String hero;
  final GalleryItem item;
  final bool active;

  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page> {
  String? _path;
  VideoPlayerController? _c;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final f = widget.item.full;
    final have = f == null ? null : ref.read(fileLoaderFamily(widget.item.account)).cachedPath(f);
    if (have != null && !widget.item.video) {
      _path = have;
    } else if (!widget.item.video && ref.read(galleryProvider).autoDownload) {
      _load();
    }
  }

  @override
  void didUpdateWidget(_Page old) {
    super.didUpdateWidget(old);
    if (!widget.active) _c?.pause();
  }

  Future<void> _load() async {
    final f = widget.item.full;
    if (f == null) return;
    setState(() => _loading = true);
    final p = await ref.read(fileLoaderFamily(widget.item.account)).download(f, priority: widget.item.video ? 32 : 20);
    if (!mounted) return;
    setState(() {
      _path = p;
      _loading = false;
    });
    if (p != null && widget.item.video) {
      final c = VideoPlayerController.file(File(p));
      try {
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        await c.play();
        setState(() => _c = c);
      } catch (_) {
        await c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    if (!i.video) {
      if (_path != null) return Hero(tag: '${widget.hero}-${i.key}', child: FullscreenZoomImage(image: FileImage(File(_path!))));
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Hero(tag: '${widget.hero}-${i.key}', child: TgPicture(file: i.thumb, mini: i.mini, account: i.account, fit: BoxFit.contain, cacheWidth: 600, autoload: ref.read(galleryProvider).autoDownload))),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white70))
          else
            Center(
              child: FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.download_rounded),
                label: Text(i.size > 0 ? 'Load photo · ${sizeText(i.size)}' : 'Load photo'),
              ),
            ),
        ],
      );
    }
    final c = _c;
    if (c != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
          ValueListenableBuilder(
            valueListenable: c,
            builder: (_, v, _) => Positioned(
              left: Space.l,
              right: Space.l,
              bottom: 150 + MediaQuery.paddingOf(context).bottom,
              child: Container(
                padding: const EdgeInsets.only(right: Space.m),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  children: [
                    IconButton(icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white), onPressed: () => v.isPlaying ? c.pause() : c.play()),
                    Text(_clock(v.position.inSeconds), style: TextStyle(color: Colors.white, fontSize: 12, fontFeatures: tabularFigures)),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: VideoProgressColors(playedColor: AppLook.minimalExplore ? Colors.white : galleryColor, bufferedColor: Colors.white24, backgroundColor: Colors.white12)),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Text(_clock(v.duration.inSeconds), style: TextStyle(color: Colors.white70, fontSize: 12, fontFeatures: tabularFigures)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: TgPicture(file: i.thumb, mini: i.mini, account: i.account, fit: BoxFit.contain, cacheWidth: 800)),
        Center(
          child: _loading
              ? ValueListenableBuilder<double>(
                  valueListenable: ref.read(fileLoaderFamily(i.account)).progress(i.full!),
                  builder: (_, p, _) => CircularProgressIndicator(value: p > 0 ? p : null, color: Colors.white),
                )
              : IconButton(iconSize: 72, icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white), onPressed: _load),
        ),
      ],
    );
  }
}

/// Opens one picture from a post full screen (for links from elsewhere).
Future<void> openGalleryFile(BuildContext context, String path) => openFullscreenFile(context, path);

/// A labelled button on the viewer's bottom bar.
class _ViewerAction extends StatelessWidget {
  const _ViewerAction({required this.icon, required this.label, required this.onTap, this.color = Colors.white});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 32,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}


/// "On this day": what was posted on today's date in earlier years, one
/// card per year, each opening its photos.
class OnThisDayStrip extends ConsumerWidget {
  const OnThisDayStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    // Asked only once the grid has its first pages: its requests share
    // Telegram's pace with the grid's and would hold it up.
    final settled = ref.watch(galleryFeedProvider.select((f) => f.bySource.isNotEmpty && !f.anyLoading));
    if (!settled && !ref.exists(onThisDayProvider(day))) return const SizedBox.shrink();
    final hidden = ref.watch(galleryProvider.select((g) => g.hidden));
    final years = [
      for (final y in ref.watch(onThisDayProvider(day)).value ?? const <({int yearsAgo, List<GalleryItem> items})>[])
        if (y.items.where((i) => !hidden.contains(i.key)).toList() case final items when items.isNotEmpty) (yearsAgo: y.yearsAgo, items: items),
    ];
    if (years.isEmpty) return const SizedBox.shrink();
    final autoload = ref.watch(galleryProvider.select((g) => g.autoDownload));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: galleryColor),
              const SizedBox(width: 6),
              Text('On this day', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('${_months[now.month - 1]} ${now.day}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            itemCount: years.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (context, i) {
              final y = years[i];
              final cover = y.items.first;
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(y.yearsAgo == 1 ? 'A year ago today' : '${y.yearsAgo} years ago today')),
                    body: GalleryGrid(items: y.items),
                  ),
                )),
                child: SizedBox(
                  width: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.l),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TgPicture(file: cover.thumb, mini: cover.mini, cacheWidth: 400, autoload: autoload, account: cover.account),
                        // Up to three more, small in the corner.
                        if (y.items.length > 1)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                for (final x in y.items.skip(1).take(2))
                                  Container(
                                    width: 30,
                                    height: 30,
                                    margin: const EdgeInsets.only(left: 4),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 1.5)),
                                    clipBehavior: Clip.antiAlias,
                                    child: TgPicture(file: x.thumb, mini: x.mini, cacheWidth: 120, autoload: autoload, account: x.account),
                                  ),
                              ],
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)], stops: [0, 0.5, 1]),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(y.yearsAgo == 1 ? '1 year ago' : '${y.yearsAgo} years ago', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                              Text('${now.year - y.yearsAgo} · ${y.items.length} ${y.items.length == 1 ? 'item' : 'items'}', style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
