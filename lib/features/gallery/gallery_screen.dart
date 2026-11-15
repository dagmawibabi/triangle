import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../telegram/presentation/chat_view_screen.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'gallery.dart';

const galleryColor = Color(0xFF0EA5E9);

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
                  child: widget.loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : (widget.empty ?? Center(child: Text('Nothing here', style: context.text.bodySmall))),
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

class _Cell extends StatelessWidget {
  const _Cell({this.hero = 'g', required this.item, required this.favorite, required this.picked, required this.onTap, required this.onLongPress, this.autoload = true});
  final bool autoload;
  final String hero;
  final GalleryItem item;
  final bool favorite;
  final bool? picked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Hero(tag: '$hero-${item.key}', child: TgPicture(file: item.thumb, mini: item.mini, cacheWidth: 360, autoload: autoload)),
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
  );
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
    return RefreshIndicator(
      onRefresh: () => ref.read(galleryFeedProvider.notifier).loadAll(g.sources.where((s) => s.account == ref.read(activeAccountIdProvider)), refresh: true),
      child: GalleryGrid(
        items: items,
        loading: feed.anyLoading,
        onEnd: _more,
        header: [
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
  String _for = '';

  void _load() {
    final sig = widget.keys.join(',');
    if (sig == _for) return;
    _for = sig;
    ref.read(galleryFeedProvider.notifier).fetchMany(widget.keys).then((v) {
      if (mounted) setState(() {
        _items = v;
        _loading = false;
      });
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(galleryProvider);
    final width = MediaQuery.sizeOf(context).width;
    return GridView.builder(
      padding: const EdgeInsets.all(Space.l),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: width > 700 ? 4 : 2, mainAxisSpacing: Space.l, crossAxisSpacing: Space.l, childAspectRatio: 0.82),
      itemCount: g.albums.length + 1,
      itemBuilder: (_, i) {
        if (i == g.albums.length) {
          return InkWell(
            borderRadius: BorderRadius.circular(Radii.l),
            onTap: () => editAlbum(context, ref),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line, width: 1.5)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_rounded, size: 32, color: AppColors.text2), const SizedBox(height: 4), const Text('New album')]),
            ),
          );
        }
        final a = g.albums[i];
        final minis = [for (final k in a.keys.take(4)) ?a.minis[k]];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumScreen(albumId: a.id))),
          onLongPress: () => editAlbum(context, ref, album: a),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.l),
                  child: minis.isEmpty
                      ? Container(
                          color: galleryColor.withValues(alpha: 0.15),
                          child: Center(child: a.emoji.isEmpty ? Icon(Icons.photo_album_outlined, size: 40, color: galleryColor) : Text(a.emoji, style: const TextStyle(fontSize: 44))),
                        )
                      : GridView.count(
                          crossAxisCount: minis.length == 1 ? 1 : 2,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 1,
                          crossAxisSpacing: 1,
                          children: [for (final m in minis) Image.memory(base64Decode(m), fit: BoxFit.cover)],
                        ),
                ),
              ),
              const SizedBox(height: Space.s),
              Text('${a.emoji.isEmpty ? '' : '${a.emoji} '}${a.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('${a.keys.length} items', style: context.text.bodySmall),
            ],
          ),
        );
      },
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
            leading: TgAvatar(chatId: s.chatId, title: s.title, size: 44),
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
      appBar: AppBar(title: Row(children: [TgAvatar(chatId: source.chatId, title: source.title, size: 28), const SizedBox(width: Space.s), Expanded(child: Text(source.title, overflow: TextOverflow.ellipsis))])),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(galleryProvider.select((g) => g.albums.where((a) => a.id == albumId).firstOrNull));
    if (a == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This album was deleted')));
    return Scaffold(
      appBar: AppBar(
        title: Text('${a.emoji.isEmpty ? '' : '${a.emoji} '}${a.name}'),
        actions: [IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editAlbum(context, ref, album: a))],
      ),
      body: KeyedItems(
        keys: a.keys,
        builder: (items, loading) => GalleryGrid(
          items: items,
          loading: loading,
          albumId: a.id,
          empty: const SectionEmpty(icon: Icons.photo_album_outlined, title: 'Empty album', body: 'Long-press photos in the Library to pick them, then add them here.'),
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
  String _for = '';

  @override
  Widget build(BuildContext context) {
    final sig = widget.keys.join(',');
    if (sig != _for) {
      _for = sig;
      ref.read(galleryFeedProvider.notifier).fetchMany(widget.keys).then((v) {
        if (mounted) setState(() {
          _items = v;
          _loading = false;
        });
      });
    }
    return widget.builder([for (final i in _items) if (widget.keys.contains(i.key)) i], _loading);
  }
}

// ---- actions -----------------------------------------------------------------

Future<GalleryAlbum?> editAlbum(BuildContext context, WidgetRef ref, {GalleryAlbum? album, List<GalleryItem> items = const []}) async {
  final r = await showFieldsSheet(
    context,
    icon: Icons.photo_album_outlined,
    color: galleryColor,
    title: album == null ? 'New album' : 'Edit album',
    subtitle: album == null
        ? (items.isEmpty ? 'Add photos to it from the Library afterwards.' : 'With the ${items.length} you picked.')
        : '${album.keys.length} items',
    preview: items.isEmpty
        ? null
        : SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length.clamp(0, 12),
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(Radii.s), child: SizedBox.square(dimension: 64, child: TgPicture(file: items[i].thumb, mini: items[i].mini, cacheWidth: 200))),
            ),
          ),
    fields: [
      SheetField('name', label: 'Name', initial: album?.name ?? '', hint: 'Trips, Family, Inspiration…', suggestions: album == null ? const ['Favorites', 'Travel', 'Family', 'Screenshots', 'Inspiration', 'Memes'] : const []),
      SheetField('emoji', label: 'Emoji (optional)', initial: album?.emoji ?? '', suggestions: const ['📸', '🌍', '❤️', '🎉', '🍲', '🐾', '🏖️', '🎨']),
    ],
    action: album == null ? 'Create album' : 'Save',
    destructive: album == null ? null : 'Delete album',
  );
  final store = ref.read(galleryProvider.notifier);
  if (r?['_destructive'] != null && album != null) {
    if (context.mounted && await confirmDelete(context, title: 'Delete “${album.name}”?', message: 'The album goes; its photos stay in their chats.')) {
      await store.deleteAlbum(album.id);
    }
    return null;
  }
  if (r == null) return null;
  final name = TextEditingController(text: r['name'] ?? '');
  final emoji = TextEditingController(text: r['emoji'] ?? '');
  final e = emoji.text.trim().characters.take(1).toString();
  if (album == null) return store.createAlbum(name.text, emoji: e, items: items);
  await store.updateAlbum(album.id, (a) => a.copyWith(name: name.text.trim().isEmpty ? a.name : name.text.trim(), emoji: e));
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
            leading: lead(a.emoji.isEmpty ? const Icon(Icons.photo_album_outlined) : Text(a.emoji, style: const TextStyle(fontSize: 20))),
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
      final path = await ref.read(fileLoaderProvider).download(f, priority: 16);
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
        ListTile(contentPadding: EdgeInsets.zero, leading: TgAvatar(chatId: i.chatId, title: i.source, size: 36), title: Text(i.source)),
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
                        IconButton(
                          icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? const Color(0xFFFF4D6D) : white),
                          onPressed: () => ref.read(galleryProvider.notifier).setFavorite([item], !fav),
                        ),
                        IconButton(icon: const Icon(Icons.photo_album_outlined, color: white), onPressed: () => addToAlbumFlow(context, ref, [item])),
                        IconButton(icon: const Icon(Icons.forward_rounded, color: white), onPressed: () => shareItems(context, ref, [item])),
                        IconButton(icon: const Icon(Icons.download_rounded, color: white), onPressed: () => saveToDevice(context, ref, [item])),
                        IconButton(
                          icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: white),
                          onPressed: () => ref.read(galleryProvider.notifier).setHidden([item], !hidden),
                        ),
                        IconButton(
                          icon: const Icon(Icons.forum_outlined, color: white),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: item.chatId, openAt: item.messageId))),
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
    final have = f == null ? null : ref.read(fileLoaderProvider).cachedPath(f);
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
    final p = await ref.read(fileLoaderProvider).download(f, priority: widget.item.video ? 32 : 20);
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
          Center(child: Hero(tag: '${widget.hero}-${i.key}', child: TgPicture(file: i.thumb, mini: i.mini, fit: BoxFit.contain, cacheWidth: 600, autoload: ref.read(galleryProvider).autoDownload))),
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
              bottom: 110,
              child: Row(
                children: [
                  IconButton(icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white), onPressed: () => v.isPlaying ? c.pause() : c.play()),
                  Expanded(child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: galleryColor))),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: TgPicture(file: i.thumb, mini: i.mini, fit: BoxFit.contain, cacheWidth: 800)),
        Center(
          child: _loading
              ? ValueListenableBuilder<double>(
                  valueListenable: ref.read(fileLoaderProvider).progress(i.full!),
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
