import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart' show openFullscreenFile, openFullscreenUrl;
import '../../core/widgets/net_image.dart';
import '../telegram/data/file_loader.dart' show fileLoaderFamily;
import '../../infrastructure/telegram/accounts.dart';
import '../movies/movies.dart';
import '../movies/movies_screen.dart' show openVideo, videoMenu;
import '../sections/section_kit.dart';
import '../sections/skeletons.dart';
import '../account/account_router.dart' show openChatInAccount;
import '../telegram/presentation/link_opener.dart' show openUrl;
import '../telegram/data/telegram_store.dart' show telegramStoreFamily;
import 'cinema.dart';
import 'series_editor.dart';

/// The section's colour: a warm amber, or the app's monochrome one.
Color get cinemaColor => AppLook.brand(const Color(0xFFF5A524));
Color get _onMedia => AppLook.minimalExplore ? Colors.white : const Color(0xFFF5A524);

String _runtime(int? minutes) => minutes == null || minutes <= 0 ? '' : (minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m');

String _clock(int s) {
  if (s <= 0) return '';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Cinema: Home (a banner and rows), Movies, Shows and My list.
class CinemaScreen extends ConsumerStatefulWidget {
  const CinemaScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CinemaScreen()));

  @override
  ConsumerState<CinemaScreen> createState() => _CinemaScreenState();
}

class _CinemaScreenState extends ConsumerState<CinemaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(cinemaProvider.notifier).ready;
      if (!mounted) return;
      unawaited(ref.read(videoFeedProvider.notifier).loadAll(_allMine()));
      if (ref.read(cinemaProvider).posterPosts) unawaited(ref.read(infoFeedProvider.notifier).loadAll(_mine()));
    });
  }

  List<SourceRef> _mine() => [for (final s in ref.read(cinemaProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  /// Every channel videos come from: the catalogue's and the series'.
  List<SourceRef> _allMine() => [for (final s in ref.read(cinemaProvider).allSources) if (s.account == ref.read(activeAccountIdProvider)) s];

  Future<void> _newSeries() async {
    final key = await openSeriesEditor(context);
    if (key != null && key != seriesDeleted && mounted) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TitleScreen(titleKey: key)));
  }

  Future<void> _sources() async {
    final picked = await pickSources(
      context,
      account: ref.read(activeAccountIdProvider),
      current: ref.read(cinemaProvider).sources,
      title: 'Movie & show channels',
      hint: 'Channels that post films and series: episodes and films (“Title 2019”, “Show S01E02”), or posters with the details and links.',
    );
    if (picked == null) return;
    await ref.read(cinemaProvider.notifier).setSources(picked);
    unawaited(ref.read(videoFeedProvider.notifier).loadAll(_allMine()));
    if (ref.read(cinemaProvider).posterPosts) unawaited(ref.read(infoFeedProvider.notifier).loadAll(_mine()));
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cinemaProvider);
    final feed = ref.watch(videoFeedProvider);
    final account = ref.watch(activeAccountIdProvider);
    final catalog = cinemaCatalog(c, feed, account, ref.watch(infoFeedProvider));
    final movies = catalog.where((t) => !t.isShow).length;
    final shows = catalog.length - movies;
    final episodes = catalog.fold<int>(0, (a, t) => a + t.episodeCount);
    Tab tab(IconData i, String l) => Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16), const SizedBox(width: 6), Text(l)]));
    return SectionScaffold(
      title: 'Cinema',
      icon: Icons.theaters_rounded,
      color: cinemaColor,
      tabs: [
        tab(Icons.home_outlined, 'Home'),
        tab(Icons.movie_outlined, 'Movies'),
        tab(Icons.live_tv_rounded, 'Shows'),
        tab(Icons.bookmark_border_rounded, 'My list'),
      ],
      actions: [
        IconButton(tooltip: 'Channels', icon: const Icon(Icons.add_to_queue_rounded), onPressed: _sources),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'series') await _newSeries();
            if (v == 'posters') {
              final on = !c.posterPosts;
              await ref.read(cinemaProvider.notifier).setPosterPosts(on);
              if (on) unawaited(ref.read(infoFeedProvider.notifier).loadAll(_mine()));
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'series', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.playlist_add_rounded), title: Text('New series'))),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: 'posters',
              checked: c.posterPosts,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Poster posts'),
                subtitle: Text('Posts with a poster, the details and links but no video'),
              ),
            ),
          ],
        ),
      ],
      hero: SectionHero(
        subtitle: c.sources.isEmpty ? 'Your film and series channels, as one catalogue.' : 'Films and series from your channels',
        stats: [('$movies', 'movies'), ('$shows', 'shows'), ('$episodes', 'episodes'), ('${c.watchlist.length}', 'in my list')],
      ),
      views: [
        _HomeTab(catalog: catalog, onSources: _sources),
        _GridTab(titles: [for (final t in catalog) if (!t.isShow) t], empty: 'No movies found yet', onSources: _sources, kind: TitleKind.movie),
        _GridTab(titles: [for (final t in catalog) if (t.isShow) t], empty: 'No shows found yet', onSources: _sources, kind: TitleKind.show, onCreate: _newSeries),
        _GridTab(titles: [for (final k in c.watchlist) ?catalog.where((t) => t.key == k).firstOrNull], empty: 'Nothing in your list', onSources: null),
      ],
    );
  }
}

/// Pull to refresh: fetches what's new in the background and returns at
/// once, so the pull's spinner goes and the poster skeletons at the foot
/// show the loading instead.
Future<void> _refresh(WidgetRef ref) async {
  final account = ref.read(activeAccountIdProvider);
  final c = ref.read(cinemaProvider);
  final mine = c.sources.where((s) => s.account == account).toList();
  unawaited(ref.read(videoFeedProvider.notifier).loadAll(c.allSources.where((s) => s.account == account), refresh: true));
  if (c.posterPosts) unawaited(ref.read(infoFeedProvider.notifier).loadAll(mine, refresh: true));
}

Future<void> _loadMore(WidgetRef ref) {
  final account = ref.read(activeAccountIdProvider);
  final c = ref.read(cinemaProvider);
  final feed = ref.read(videoFeedProvider.notifier);
  final infos = ref.read(infoFeedProvider.notifier);
  final mine = [for (final s in c.sources) if (s.account == account) s];
  return Future.wait([
    pooled([for (final s in c.allSources) if (s.account == account && ref.read(videoFeedProvider).hasMore(s.key)) s], 3, (s) => feed.load(s, more: true)),
    if (c.posterPosts) pooled([for (final s in mine) if (ref.read(infoFeedProvider).hasMore(s.key)) s], 3, (s) => infos.load(s, more: true)),
  ]);
}

/// Whether the catalogue is still coming in: the saved channels not read
/// yet, a request out, or a channel of this account not loaded (or failed)
/// yet. Shows the skeleton instead of an empty catalogue.
bool _loadingCatalog(WidgetRef ref) {
  final c = ref.watch(cinemaProvider);
  final feed = ref.watch(videoFeedProvider);
  final account = ref.watch(activeAccountIdProvider);
  if (!ref.read(cinemaProvider.notifier).isReady || feed.anyLoading) return true;
  return c.allSources.any((s) => s.account == account && !feed.bySource.containsKey(s.key) && !feed.errors.containsKey(s.key));
}

const _posterSkeleton = Align(alignment: Alignment.topCenter, child: SkeletonGrid(count: 9, maxExtent: 160, childAspectRatio: 0.55, captions: false));

void openTitle(BuildContext context, CinemaTitle t) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TitleScreen(titleKey: t.key)));

// ---- home ------------------------------------------------------------------------

class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.catalog, required this.onSources});
  final List<CinemaTitle> catalog;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cinemaProvider);
    final feed = ref.watch(videoFeedProvider);
    final progress = ref.watch(moviesProvider.select((m) => m.progress));
    final loading = _loadingCatalog(ref);
    if (c.sources.isEmpty && !ref.read(cinemaProvider.notifier).isReady) return const SkeletonPage(child: _posterSkeleton);
    if (c.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.theaters_outlined,
          title: 'No movie channels yet',
          body: 'Pick channels that post films and series. Their posts become a catalogue with posters, seasons and episodes, and what you watch is remembered.',
          action: 'Add channels',
          onAction: onSources,
        ),
      );
    }
    if (catalog.isEmpty) {
      if (loading) return const SkeletonPage(child: _posterSkeleton);
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.search_off_rounded,
          title: 'No films or episodes found',
          body: 'The videos loaded so far don’t look like films or episodes. Pull down to load more, or add other channels.',
          action: 'Add channels',
          onAction: onSources,
        ),
      );
    }
    // Continue watching: titles with something part-watched, latest first.
    final watching = <(CinemaTitle, WatchProgress)>[];
    for (final t in catalog) {
      WatchProgress? last;
      for (final v in t.allVideos) {
        final p = progress[v.key];
        if (p != null && p.position > 15 && (last == null || p.at.isAfter(last.at))) last = p;
      }
      if (last != null && (!last.finished || t.isShow)) watching.add((t, last));
    }
    watching.sort((a, b) => b.$2.at.compareTo(a.$2.at));
    final movies = [for (final t in catalog) if (!t.isShow) t];
    final shows = [for (final t in catalog) if (t.isShow) t];
    final featured = [...catalog.where((t) => t.isShow ? (t.episodeCount > 1 || !t.hasVideo) : true)].take(6).toList();
    final myList = [for (final k in c.watchlist) ?catalog.where((t) => t.key == k).firstOrNull];
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600 && !feed.anyLoading) unawaited(_loadMore(ref));
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.x4 + 40),
          children: [
            if (featured.isNotEmpty) _Billboard(titles: featured),
            if (watching.isNotEmpty) _Row(title: 'Continue watching', titles: [for (final w in watching) w.$1], wide: true),
            if (shows.isNotEmpty) _Row(title: 'New episodes', titles: shows.take(20).toList()),
            if (movies.isNotEmpty) _Row(title: 'Recently added movies', titles: movies.take(20).toList()),
            // Only the saved titles loaded so far: before any are, the row
            // would be a heading over an empty strip.
            if (myList.isNotEmpty) _Row(title: 'My list', titles: myList),
            _GenreRows(catalog: catalog),
            if (feed.anyLoading) const _RowSkeleton(),
          ],
        ),
      ),
    );
  }
}

/// Rows by genre, once the posters and genres are in.
class _GenreRows extends ConsumerWidget {
  const _GenreRows({required this.catalog});
  final List<CinemaTitle> catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byGenre = <String, List<CinemaTitle>>{};
    for (final t in catalog.take(80)) {
      final meta = ref.watch(titleMetaProvider((t.kind, t.title, t.year))).value;
      for (final g in meta?.genres ?? const <String>[]) {
        byGenre.putIfAbsent(g, () => []).add(t);
      }
    }
    final genres = byGenre.entries.where((e) => e.value.length >= 3).toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Column(children: [for (final e in genres.take(6)) _Row(title: e.key, titles: e.value)]);
  }
}

/// The big banners at the top of Home, swiped through.
class _Billboard extends StatefulWidget {
  const _Billboard({required this.titles});
  final List<CinemaTitle> titles;

  @override
  State<_Billboard> createState() => _BillboardState();
}

class _BillboardState extends State<_Billboard> {
  final _pages = PageController();
  int _at = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_pages.hasClients || widget.titles.length < 2) return;
      _pages.animateToPage((_at + 1) % widget.titles.length, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 520,
    child: Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            if (n.dragDetails != null) _auto?.cancel();
            return false;
          },
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.titles.length,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (_, i) => _BillboardPage(title: widget.titles[i]),
          ),
        ),
        if (widget.titles.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.titles.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _at ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: i == _at ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(99)),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _BillboardPage extends ConsumerWidget {
  const _BillboardPage({required this.title});
  final CinemaTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = title;
    final meta = ref.watch(titleMetaProvider((t.kind, t.title, t.year))).value;
    final inList = ref.watch(cinemaProvider.select((c) => c.watchlist.contains(t.key)));
    final line = [
      if ((meta?.year ?? t.year) != null) '${meta?.year ?? t.year}',
      t.isShow ? '${t.seasons.length} season${t.seasons.length == 1 ? '' : 's'}' : _runtime(meta?.runtime),
      ...?meta?.genres.take(2),
    ].where((s) => s.isNotEmpty).join('  ·  ');
    return GestureDetector(
      onTap: () => openTitle(context, t),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The poster blurred behind, the poster itself in front.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: _Art(title: t, meta: meta, cacheWidth: 300),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 210,
                height: 315,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))]),
                clipBehavior: Clip.antiAlias,
                child: _Art(title: t, meta: meta, cacheWidth: 600, label: meta?.poster == null),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000), Color(0xFF000000)], stops: [0, 0.5, 0.78, 1]),
            ),
          ),
          Positioned(
            left: Space.l,
            right: Space.l,
            bottom: Space.x4,
            child: Column(
              children: [
                Text(t.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Text(line, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.l),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _IconLabel(icon: inList ? Icons.check_rounded : Icons.add_rounded, label: 'My list', onTap: () => ref.read(cinemaProvider.notifier).toggleWatchlist(t.key)),
                    const SizedBox(width: Space.xl),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(130, 46)),
                      icon: Icon(playIcon(ref, t), size: 26),
                      label: Text(playLabel(ref, t), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      onPressed: () => playTitle(context, ref, t),
                    ),
                    const SizedBox(width: Space.xl),
                    _IconLabel(icon: Icons.info_outline_rounded, label: 'Info', onTap: () => openTitle(context, t)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(Radii.m),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white), const SizedBox(height: 2), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))]),
    ),
  );
}

/// What to play for [t]: where it was left, the next episode, or the start.
Video? nextToPlay(WidgetRef ref, CinemaTitle t) {
  final progress = ref.read(moviesProvider).progress;
  if (!t.isShow) {
    final watched = t.versions.where((v) => progress[v.key] != null).toList()..sort((a, b) => progress[b.key]!.at.compareTo(progress[a.key]!.at));
    return watched.firstOrNull ?? t.bestVersion;
  }
  final eps = [for (final s in t.seasonNumbers) ...t.episodesOf(s)];
  if (eps.isEmpty) return null;
  Episode? last;
  WatchProgress? lastP;
  for (final e in eps) {
    for (final v in e.versions) {
      final p = progress[v.key];
      if (p != null && (lastP == null || p.at.isAfter(lastP.at))) {
        last = e;
        lastP = p;
      }
    }
  }
  if (last == null) return eps.first.best;
  if (!lastP!.finished) return last.versions.firstWhere((v) => v.key == lastP!.key, orElse: () => last!.best);
  final i = eps.indexOf(last);
  return i + 1 < eps.length ? eps[i + 1].best : last.best;
}

String playLabel(WidgetRef ref, CinemaTitle t) {
  final v = nextToPlay(ref, t);
  if (v == null) {
    final i = t.info;
    return i == null ? 'Play' : (i.links.isNotEmpty ? i.links.first.$1 : 'Open post');
  }
  final p = ref.watch(moviesProvider.select((m) => m.progress[v.key]));
  final resume = p != null && !p.finished && p.position > 15;
  if (!t.isShow) return resume ? 'Resume' : 'Play';
  final r = parseRelease(v);
  final ep = r == null ? '' : ' S${r.season}:E${r.episode}';
  return '${resume ? 'Resume' : 'Play'}$ep';
}

IconData playIcon(WidgetRef ref, CinemaTitle t) => t.hasVideo ? Icons.play_arrow_rounded : ((t.info?.links.isNotEmpty ?? false) ? Icons.open_in_new_rounded : Icons.forum_outlined);

void playTitle(BuildContext context, WidgetRef ref, CinemaTitle t) {
  final v = nextToPlay(ref, t);
  if (v != null) return openVideo(context, v);
  final i = t.info;
  if (i == null) return;
  if (i.links.isNotEmpty) {
    openUrl(i.links.first.$2, context: context);
  } else {
    openChatInAccount(context, i.chatId, hint: i.account, openAt: i.messageId);
  }
}

/// A title's picture: its poster when one was found, else the video's
/// own frame with the name written over it.
class _Art extends StatelessWidget {
  const _Art({required this.title, required this.meta, this.cacheWidth = 400, this.label = false});
  final CinemaTitle title;
  final TitleMeta? meta;
  final int cacheWidth;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final t = title;
    if (t.customId != null) {
      // A made-up series: the picture picked for it, else its channel's.
      if (t.customPoster != null) {
        return Image.file(File(t.customPoster!), fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => _Art(title: _without(t), meta: this.meta, cacheWidth: cacheWidth, label: label));
      }
      if (!t.posterOnline && t.info?.photo == null && t.posterChat != null) return _ChannelPoster(source: t.posterChat!, title: t.title, label: label, cacheWidth: cacheWidth);
    }
    final meta = t.customId != null && !t.posterOnline ? null : this.meta;
    final v = title.cover;
    final i = title.info;
    // A poster post's own poster beats a frame from the video.
    final frame = i?.photo != null
        ? TgPicture(file: i!.photo, mini: i.mini, account: i.account, cacheWidth: cacheWidth, placeholder: Container(color: const Color(0xFF1A1A1A)))
        : TgPicture(file: v?.thumb, mini: v?.mini, account: v?.account, cacheWidth: cacheWidth, placeholder: Container(color: const Color(0xFF1A1A1A)));
    final poster = meta?.poster;
    final ownPoster = poster != null || i?.photo != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null) NetImage(poster, fit: BoxFit.cover, errorWidget: frame) else frame,
        if (!ownPoster && label) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0xDD000000)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                title.title.toUpperCase(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, height: 1.1, letterSpacing: 0.6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// [t] without its picked picture (when that file is gone).
CinemaTitle _without(CinemaTitle t) {
  final c = CinemaTitle(key: t.key, kind: t.kind, title: t.title, year: t.year, customId: t.customId, posterChat: t.posterChat, posterOnline: t.posterOnline);
  c.versions.addAll(t.versions);
  c.seasons.addAll(t.seasons);
  c.infos.addAll(t.infos);
  return c;
}

/// A channel's photo as a poster, the series' name over it.
class _ChannelPoster extends ConsumerWidget {
  const _ChannelPoster({required this.source, required this.title, required this.label, required this.cacheWidth});
  final SourceRef source;
  final String title;
  final bool label;
  final int cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(telegramStoreFamily(source.account)).chat(source.chatId)?.photo;
    return Stack(
      fit: StackFit.expand,
      children: [
        TgPicture(file: photo?.big, mini: photo?.minithumbnail, account: source.account, cacheWidth: cacheWidth, placeholder: Container(color: const Color(0xFF1A1A1A))),
        if (label) ...[
          const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xDD000000)], stops: [0, 0.45, 1])),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(title.toUpperCase(), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, height: 1.1, letterSpacing: 0.6)),
            ),
          ),
        ],
      ],
    );
  }
}

/// A poster card: 2:3 art, a badge (episodes or quality), progress.
class TitlePoster extends ConsumerWidget {
  const TitlePoster({super.key, required this.title, this.width});
  final CinemaTitle title;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = title;
    final meta = ref.watch(titleMetaProvider((t.kind, t.title, t.year))).value;
    final progress = ref.watch(moviesProvider.select((m) => m.progress));
    final next = nextToPlay(ref, t);
    final p = next == null ? null : progress[next.key];
    final best = t.isShow ? null : t.bestVersion;
    final badge = !t.hasVideo ? 'POSTER' : (t.isShow ? '${t.episodeCount} EP' : (best?.quality ?? ''));
    final rating = meta?.rating ?? t.info?.average;
    return GestureDetector(
      onTap: () => openTitle(context, t),
      onLongPress: () => _titleMenu(context, ref, t),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.m),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Art(title: t, meta: meta, label: true),
                    if (badge.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
                          child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                        ),
                      ),
                    if (rating != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 11, color: _onMedia),
                              const SizedBox(width: 2),
                              Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    if (p != null && p.position > 15)
                      Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: p.fraction, minHeight: 3, color: _onMedia, backgroundColor: Colors.white24)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(
              [if ((meta?.year ?? t.year) != null) '${meta?.year ?? t.year}', t.isShow ? (t.hasVideo ? '${t.seasons.length} season${t.seasons.length == 1 ? '' : 's'}' : 'Series') : (meta?.genres.firstOrNull ?? t.info?.genres.firstOrNull ?? 'Movie')].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _titleMenu(BuildContext context, WidgetRef ref, CinemaTitle t) async {
  final inList = ref.read(cinemaProvider).watchlist.contains(t.key);
  final on = await ref.read(cinemaProvider.notifier).toggleWatchlist(t.key);
  if (context.mounted) showSnack(context, on ? 'Added to My list' : (inList ? 'Removed from My list' : ''), icon: Icons.bookmark_rounded);
}

/// A row of posters that scrolls sideways.
class _Row extends StatelessWidget {
  const _Row({required this.title, required this.titles, this.wide = false});
  final String title;
  final List<CinemaTitle> titles;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) return const SizedBox.shrink();
    final w = wide ? 230.0 : 116.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
          child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: wide ? w * 9 / 16 + 48 : w * 1.5 + 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            itemCount: titles.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (context, i) => wide ? _ContinueCard(title: titles[i], width: w) : TitlePoster(title: titles[i], width: w),
          ),
        ),
      ],
    );
  }
}

/// A poster with its title and year lines, in grey.
class _PosterBone extends StatelessWidget {
  const _PosterBone();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SquareBone(radius: 10, aspect: 2 / 3),
      SizedBox(height: 8),
      FractionallySizedBox(widthFactor: 0.85, child: Bone(height: 11)),
      SizedBox(height: 5),
      FractionallySizedBox(widthFactor: 0.4, child: Bone(height: 9)),
    ],
  );
}

/// A row of posters still coming, shaped like [_Row], in place of a
/// spinner at the foot of Home.
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    const w = 116.0;
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s), child: Bone(width: 150, height: 15)),
          SizedBox(
            height: w * 1.5 + 44,
            // As many as fit, clipped at the edge like a row scrolled to its start.
            child: UnconstrainedBox(
              alignment: Alignment.topLeft,
              constrainedAxis: Axis.vertical,
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 8; i++) ...[if (i > 0) const SizedBox(width: Space.s), const SizedBox(width: w, child: _PosterBone())],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue watching: the frame where it was left, and what's next.
class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.title, required this.width});
  final CinemaTitle title;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = title;
    final v = nextToPlay(ref, t);
    if (v == null) return const SizedBox.shrink();
    final p = ref.watch(moviesProvider.select((m) => m.progress[v.key]));
    final r = parseRelease(v);
    return GestureDetector(
      onTap: () => openVideo(context, v),
      onLongPress: () => openTitle(context, t),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.m),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 500, placeholder: Container(color: const Color(0xFF1A1A1A))),
                    Container(color: Colors.black26),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 40, shadows: [Shadow(blurRadius: 12)])),
                    if (p != null) Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: p.fraction, minHeight: 3, color: _onMedia, backgroundColor: Colors.white24)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(
              [if (t.isShow && r != null) 'S${r.season} · E${r.episode}', if (p != null && v.seconds > 0) '${_clock(v.seconds - p.position)} left'].join('  ·  '),
              maxLines: 1,
              style: context.text.labelSmall?.copyWith(color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- grids -----------------------------------------------------------------------

class _GridTab extends ConsumerStatefulWidget {
  const _GridTab({required this.titles, required this.empty, required this.onSources, this.kind, this.onCreate});

  /// Shows a card to put a series together.
  final VoidCallback? onCreate;
  final List<CinemaTitle> titles;
  final String empty;
  final VoidCallback? onSources;
  final TitleKind? kind;

  @override
  ConsumerState<_GridTab> createState() => _GridTabState();
}

class _GridTabState extends ConsumerState<_GridTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _genre;
  String _sort = 'new';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final feed = ref.watch(videoFeedProvider);
    final q = _q.toLowerCase().trim();
    final metas = {for (final t in widget.titles) t.key: ref.watch(titleMetaProvider((t.kind, t.title, t.year))).value};
    final genres = <String, int>{};
    for (final m in metas.values) {
      for (final g in m?.genres ?? const <String>[]) {
        genres[g] = (genres[g] ?? 0) + 1;
      }
    }
    final list = [
      for (final t in widget.titles)
        if ((q.isEmpty || t.title.toLowerCase().contains(q)) && (_genre == null || (metas[t.key]?.genres.contains(_genre) ?? false))) t,
    ];
    switch (_sort) {
      case 'az':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'year':
        list.sort((a, b) => ((metas[b.key]?.year ?? b.year) ?? 0).compareTo((metas[a.key]?.year ?? a.year) ?? 0));
      case 'rating':
        list.sort((a, b) => (metas[b.key]?.rating ?? 0).compareTo(metas[a.key]?.rating ?? 0));
    }
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 6 : (width > 600 ? 4 : 3);
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (widget.kind != null && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600 && !feed.anyLoading) unawaited(_loadMore(ref));
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (widget.onCreate != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                  child: Material(
                    color: cinemaColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.l),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.l),
                      onTap: widget.onCreate,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.m),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: cinemaColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(Radii.m)),
                              child: Icon(Icons.playlist_add_rounded, color: cinemaColor),
                            ),
                            const SizedBox(width: Space.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Put a series together', style: TextStyle(fontWeight: FontWeight.w800)),
                                  Text('Name it, add seasons and pick the channels each comes from', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.titles.length > 6)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search titles', isDense: true),
                          onChanged: (v) => setState(() => _q = v),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.sort_rounded),
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (_) => [
                          for (final (k, l) in const [('new', 'Recently added'), ('az', 'A–Z'), ('year', 'Year'), ('rating', 'Rating')]) CheckedPopupMenuItem(value: k, checked: _sort == k, child: Text(l)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (genres.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                    children: [
                      Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _genre == null, onSelected: (_) => setState(() => _genre = null))),
                      for (final g in (genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key))
                        Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(g), selected: _genre == g, onSelected: (_) => setState(() => _genre = _genre == g ? null : g))),
                    ],
                  ),
                ),
              ),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _loadingCatalog(ref) && widget.titles.isEmpty
                    ? _posterSkeleton
                    : SectionEmpty(icon: Icons.theaters_outlined, title: widget.empty, body: widget.onSources == null ? 'Long-press a poster, or use My list on a title, to keep it here.' : 'Pull down to load more, or add channels.', action: widget.onSources == null ? null : 'Add channels', onAction: widget.onSources),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4 + 40),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: Space.s, mainAxisSpacing: Space.m, childAspectRatio: 0.52),
                  itemCount: list.length,
                  itemBuilder: (_, i) => TitlePoster(title: list[i]),
                ),
              ),
            // More on the way: a row of posters still coming, on the same grid.
            if (feed.anyLoading && list.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
                  child: Shimmer(
                    child: BoneGrid(count: cols, columns: cols, spacing: Space.s, aspectRatio: 0.52, cell: (_) => const _PosterBone()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- a title ---------------------------------------------------------------------

/// A film or show: its poster over a blurred backdrop, what it's about,
/// Play, My list, and the seasons and episodes or the copies to pick from.
class TitleScreen extends ConsumerStatefulWidget {
  const TitleScreen({super.key, required this.titleKey});
  final String titleKey;

  @override
  ConsumerState<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends ConsumerState<TitleScreen> {
  int? _season;

  /// Newest episode first.
  bool _desc = false;
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cinemaProvider);
    final feed = ref.watch(videoFeedProvider);
    final t = cinemaCatalog(c, feed, ref.watch(activeAccountIdProvider), ref.watch(infoFeedProvider)).where((x) => x.key == widget.titleKey).firstOrNull;
    if (t == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This title isn’t loaded anymore.')));
    final meta = ref.watch(titleMetaProvider((t.kind, t.title, t.year))).value;
    final info = t.info;
    // What the poster posts say, where nothing was found online.
    final overview = (meta?.overview.isNotEmpty ?? false) ? meta!.overview : (info?.plot ?? '');
    final genres = (meta?.genres.isNotEmpty ?? false) ? meta!.genres : (info?.genres ?? const <String>[]);
    final rating = meta?.rating ?? info?.average;
    final progress = ref.watch(moviesProvider.select((m) => m.progress));
    final inList = c.watchlist.contains(t.key);
    final seasons = t.seasonNumbers;
    final season = _season != null && seasons.contains(_season) ? _season! : (seasons.firstOrNull ?? 0);
    final episodeNames = meta?.showId == null ? const <String, EpisodeInfo>{} : (ref.watch(showEpisodesProvider(meta!.showId!)).value ?? const <String, EpisodeInfo>{});
    // The season's episodes, with the ones the catalogue knows of but no
    // channel posted as gaps.
    final posted = {for (final e in t.episodesOf(season)) e.number: e};
    final knownNumbers = [
      for (final k in episodeNames.keys)
        if (k.startsWith('$season:')) ?int.tryParse(k.substring('$season:'.length)),
    ];
    final numbers = {...posted.keys, if (posted.isNotEmpty || t.customId == null) ...knownNumbers.where((n) => n > 0)}.toList()..sort();
    final rows = [for (final n in _desc ? numbers.reversed : numbers) (n, posted[n])];
    final nextKey = t.isShow ? nextToPlay(ref, t)?.key : null;
    final line = [
      if ((meta?.year ?? t.year) != null) '${meta?.year ?? t.year}',
      if (meta?.rated != null) meta!.rated! else if (info?.rated.isNotEmpty ?? false) info!.rated,
      if (t.isShow && seasons.isNotEmpty) '${seasons.length} season${seasons.length == 1 ? '' : 's'}' else if (_runtime(meta?.runtime).isNotEmpty) _runtime(meta?.runtime) else if (info?.runtime.isNotEmpty ?? false) info!.runtime,
      if (meta?.network != null) meta!.network!,
    ];
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 470,
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (t.customId != null)
                IconButton(
                  tooltip: 'Edit series',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final series = c.series.where((x) => x.id == t.customId).firstOrNull;
                    if (series == null) return;
                    final r = await openSeriesEditor(context, series: series);
                    if (r == seriesDeleted && context.mounted) Navigator.pop(context);
                  },
                ),
              IconButton(
                tooltip: inList ? 'Remove from My list' : 'Add to My list',
                icon: Icon(inList ? Icons.bookmark_rounded : Icons.bookmark_add_outlined),
                onPressed: () => ref.read(cinemaProvider.notifier).toggleWatchlist(t.key),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (meta?.backdrop != null)
                    NetImage(meta!.backdrop, fit: BoxFit.cover, errorWidget: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: _Art(title: t, meta: meta, cacheWidth: 300)))
                  else
                    ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: _Art(title: t, meta: meta, cacheWidth: 300)),
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  Positioned(
                    top: top + kToolbarHeight + 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => openPoster(context, ref, t, meta),
                        child: Container(
                        width: 190,
                        height: 285,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 34, offset: Offset(0, 16))]),
                        clipBehavior: Clip.antiAlias,
                        child: _Art(title: t, meta: meta, cacheWidth: 600, label: meta?.poster == null),
                      ),
                      ),
                    ),
                  ),
                  // The fade only draws: a decorated box takes taps, and
                  // this one lies over the poster.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.transparent, AppColors.bg], stops: const [0, 0.72, 1]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(t.title, textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (rating != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star_rounded, size: 16, color: cinemaColor), const SizedBox(width: 2), Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800))]),
                      for (final s in line) Text(s, style: context.text.bodySmall?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (genres.isNotEmpty) ...[
                    const SizedBox(height: Space.s),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in genres)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
                            child: Text(g, style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.l),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 50), backgroundColor: AppColors.text, foregroundColor: AppColors.bg),
                          icon: Icon(playIcon(ref, t), size: 26),
                          label: Text(playLabel(ref, t), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          onPressed: () => playTitle(context, ref, t),
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m))),
                          onPressed: () => ref.read(cinemaProvider.notifier).toggleWatchlist(t.key),
                          child: Icon(inList ? Icons.check_rounded : Icons.add_rounded),
                        ),
                      ),
                    ],
                  ),
                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: Space.l),
                    GestureDetector(
                      onTap: () => setState(() => _more = !_more),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: Text(
                          overview,
                          maxLines: _more ? null : 4,
                          overflow: _more ? null : TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(height: 1.5, color: AppColors.text2),
                        ),
                      ),
                    ),
                  ],
                  if (meta != null && (meta.cast.isNotEmpty || meta.director.isNotEmpty || meta.awards.isNotEmpty || meta.status.isNotEmpty)) ...[
                    const SizedBox(height: Space.m),
                    for (final (label, value) in [
                      if (meta.cast.isNotEmpty) ('Starring', meta.cast.take(5).join(', ')),
                      if (meta.director.isNotEmpty) (meta.director.length == 1 ? 'Director' : 'Directors', meta.director.join(', ')),
                      if (t.isShow && meta.status.isNotEmpty) ('Status', meta.status),
                      if (meta.awards.isNotEmpty) ('Awards', meta.awards),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text.rich(
                          TextSpan(children: [TextSpan(text: '$label  ', style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w700)), TextSpan(text: value)]),
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (t.infos.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
                    child: Text(t.infos.length == 1 ? 'From the channel' : 'From the channels', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  for (final i in [...t.infos]..sort((a, b) => b.date.compareTo(a.date))) _InfoCard(info: i),
                ],
              ),
            ),
          if (t.isShow && (t.seasons.isNotEmpty || t.customId != null)) ...[
            SliverToBoxAdapter(
              child: _SeasonsBar(
                title: t,
                season: season,
                custom: c.series.where((x) => x.id == t.customId).firstOrNull,
                known: episodeNames,
                progress: progress,
                descending: _desc,
                onSeason: (s) => setState(() => _season = s),
                onSort: () => setState(() => _desc = !_desc),
                onEdit: t.customId == null
                    ? null
                    : () async {
                        final series = c.series.where((x) => x.id == t.customId).firstOrNull;
                        if (series != null) await openSeriesEditor(context, series: series);
                      },
              ),
            ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final (n, e) = rows[i];
                final info = episodeNames['$season:$n'];
                return _EpisodeTile(
                  season: season,
                  number: n,
                  episode: e,
                  info: info,
                  progress: progress,
                  next: e != null && nextKey != null && e.versions.any((v) => v.key == nextKey),
                );
              },
            ),
            if (rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    children: [
                      Icon(Icons.video_library_outlined, size: 36, color: AppColors.text3),
                      const SizedBox(height: Space.s),
                      Text('No episodes in season $season yet', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        t.customId != null ? 'Pick the channels this season comes from.' : 'Pull down on the Shows tab to load more posts.',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
              ),
          ] else if (t.versions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
                child: Text(t.versions.length > 1 ? 'Versions' : 'Watch', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            SliverList.builder(
              itemCount: t.versions.length,
              itemBuilder: (_, i) => _VersionTile(video: t.versions[i], progress: progress[t.versions[i].key]),
            ),
          ],
          if (feed.anyLoading || ref.read(cinemaProvider).allSources.any((s) => feed.hasMore(s.key)))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Center(
                  child: feed.anyLoading
                      ? const SkeletonRows(count: 2, art: 72, artRadius: 8, padding: EdgeInsets.symmetric(vertical: Space.s))
                      : TextButton.icon(onPressed: () => _loadMore(ref), icon: const Icon(Icons.expand_more_rounded), label: const Text('Look for more episodes and copies')),
                ),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: Space.x4 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}

/// The seasons as cards to pick from, then the picked season's progress,
/// its name and the sort.
class _SeasonsBar extends StatelessWidget {
  const _SeasonsBar({
    required this.title,
    required this.season,
    required this.custom,
    required this.known,
    required this.progress,
    required this.descending,
    required this.onSeason,
    required this.onSort,
    this.onEdit,
  });
  final CinemaTitle title;
  final int season;
  final CustomSeries? custom;
  final Map<String, EpisodeInfo> known;
  final Map<String, WatchProgress> progress;
  final bool descending;
  final ValueChanged<int> onSeason;
  final VoidCallback onSort;
  final VoidCallback? onEdit;

  bool _watched(Episode e) => e.versions.any((v) => progress[v.key]?.finished ?? false);

  @override
  Widget build(BuildContext context) {
    final t = title;
    final seasons = t.seasonNumbers;
    final eps = t.episodesOf(season);
    final watched = eps.where(_watched).length;
    final knownCount = known.keys.where((k) => k.startsWith('$season:')).length;
    final total = eps.length > knownCount ? eps.length : knownCount;
    final name = custom?.seasons.where((s) => s.number == season).firstOrNull?.name ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.s, Space.s),
          child: Row(
            children: [
              Text('Episodes', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99)),
                child: Text('${t.episodeCount}', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              if (onEdit != null) IconButton(tooltip: 'Seasons and channels', icon: const Icon(Icons.tune_rounded), onPressed: onEdit),
              IconButton(
                tooltip: descending ? 'Oldest first' : 'Newest first',
                icon: Icon(descending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                onPressed: onSort,
              ),
            ],
          ),
        ),
        if (seasons.length > 1)
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (_, i) {
                final n = seasons[i];
                final on = n == season;
                final list = t.episodesOf(n);
                final w = list.where(_watched).length;
                return InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: () => onSeason(n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 108,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: on ? AppColors.text : AppColors.surface,
                      borderRadius: BorderRadius.circular(Radii.m),
                      border: Border.all(color: on ? AppColors.text : AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Season $n', style: TextStyle(fontWeight: FontWeight.w800, color: on ? AppColors.bg : AppColors.text)),
                        const SizedBox(height: 2),
                        Text(
                          list.isEmpty ? 'No episodes' : (w == 0 ? '${list.length} episodes' : '$w/${list.length} watched'),
                          maxLines: 1,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? AppColors.bg.withValues(alpha: 0.75) : AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Season $season' : 'Season $season · $name',
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    total == 0 ? '' : (eps.length < total ? '${eps.length} of $total posted' : '$total episodes'),
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                ],
              ),
              if (eps.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(value: eps.isEmpty ? 0 : watched / eps.length, minHeight: 4, color: cinemaColor, backgroundColor: AppColors.surface2),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Text('$watched watched', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One episode: its still with the length, progress and a watched mark;
/// its number, name, air date and rating; the plot, opening on tap. One
/// the catalogue knows of that no channel posted shows faded.
class _EpisodeTile extends ConsumerStatefulWidget {
  const _EpisodeTile({required this.season, required this.number, required this.episode, this.info, required this.progress, this.next = false});
  final int season;
  final int number;
  final Episode? episode;
  final EpisodeInfo? info;
  final Map<String, WatchProgress> progress;
  final bool next;

  @override
  ConsumerState<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<_EpisodeTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final info = widget.info;
    final v = e?.best;
    final p = e == null ? null : [for (final x in e.versions) ?widget.progress[x.key]].fold<WatchProgress?>(null, (a, b) => a == null || b.at.isAfter(a.at) ? b : a);
    final watched = p?.finished ?? false;
    final name = (info?.name ?? '').isNotEmpty ? info!.name : 'Episode ${widget.number}';
    final summary = info?.summary ?? '';
    final aired = info?.aired;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final missing = e == null;
    final still = SizedBox(
      width: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.m),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (info?.image != null)
                NetImage(info!.image, fit: BoxFit.cover, errorWidget: v == null ? Container(color: AppColors.surface2) : TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 400))
              else if (v != null)
                TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 400, placeholder: Container(color: AppColors.surface2))
              else
                Container(color: AppColors.surface2, child: Icon(Icons.movie_outlined, color: AppColors.text3)),
              if (missing) Container(color: AppColors.bg.withValues(alpha: 0.55)),
              if (!missing) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x88000000)])),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1.5)),
                    child: Icon(watched ? Icons.replay_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
                if (v != null && v.seconds > 0)
                  Positioned(
                    right: 5,
                    bottom: p == null ? 5 : 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(4)),
                      child: Text(_clock(v.seconds), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (watched)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: cinemaColor, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, size: 12, color: AppLook.onBrand(cinemaColor)),
                    ),
                  ),
                if (p != null && !watched) Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: p.fraction, minHeight: 3, color: _onMedia, backgroundColor: Colors.white24)),
              ],
            ],
          ),
        ),
      ),
    );
    return Opacity(
      opacity: missing ? 0.55 : 1,
      child: InkWell(
        onTap: missing ? () => setState(() => _open = !_open) : () => e.versions.length > 1 ? _pickVersion(context, ref, e.versions) : openVideo(context, v!),
        onLongPress: v == null ? null : () => videoMenu(context, ref, v),
        child: Container(
          margin: const EdgeInsets.fromLTRB(Space.m, 2, Space.m, 2),
          padding: const EdgeInsets.all(Space.s),
          decoration: BoxDecoration(
            color: widget.next ? cinemaColor.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: widget.next ? cinemaColor.withValues(alpha: 0.35) : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  still,
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('E${widget.number}', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w900, color: cinemaColor, letterSpacing: 0.5)),
                            if (widget.next) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: cinemaColor, borderRadius: BorderRadius.circular(99)),
                                child: Text(p != null && !watched ? 'CONTINUE' : 'UP NEXT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppLook.onBrand(cinemaColor), letterSpacing: 0.6)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (aired != null) '${months[aired.month - 1]} ${aired.day}, ${aired.year}',
                            if (info?.rating != null) '★ ${info!.rating!.toStringAsFixed(1)}',
                            if (missing) 'Not in your channels',
                            if (v != null && v.quality.isNotEmpty) v.quality,
                            if (v != null && v.size > 0) sizeText(v.size),
                            if ((e?.versions.length ?? 0) > 1) '${e!.versions.length} copies',
                          ].join(' · '),
                          maxLines: 2,
                          style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (summary.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, Space.s, 2, 0),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: Text(
                        summary,
                        maxLines: _open ? null : 2,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionTile extends ConsumerWidget {
  const _VersionTile({required this.video, this.progress});
  final Video video;
  final WatchProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 2),
      leading: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
        child: Text(v.quality.isEmpty ? 'SD' : v.quality, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      title: Text(v.fileName.isNotEmpty ? v.fileName : v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [v.channel, if (v.seconds > 0) _clock(v.seconds), if (v.size > 0) sizeText(v.size), if (progress != null) progress!.finished ? 'watched' : '${(progress!.fraction * 100).round()}% watched'].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.play_circle_outline_rounded, color: AppColors.text2),
      onTap: () => openVideo(context, v),
      onLongPress: () => videoMenu(context, ref, v),
    );
  }
}

Future<void> _pickVersion(BuildContext context, WidgetRef ref, List<Video> versions) => showAppSheet<void>(
  context,
  initialSize: 0.45,
  builder: (context, scroll) => ListView(
    controller: scroll,
    children: [
      Padding(padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s), child: Text('Pick a copy', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
      for (final v in versions..sort((a, b) => b.height.compareTo(a.height)))
        _VersionTile(video: v, progress: ref.read(moviesProvider).progress[v.key]),
    ],
  ),
);


/// A poster post on a title's page: where it's from, its ratings, and its
/// links and the post itself to open.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info});
  final InfoPost info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Consumer(
                builder: (context, ref, _) => GestureDetector(
                  onTap: () => _openInfoPhoto(context, ref, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.s),
                    child: SizedBox(width: 44, height: 64, child: TgPicture(file: i.photo, mini: i.mini, account: i.account, cacheWidth: 160, placeholder: Container(color: AppColors.surface2))),
                  ),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      [agoText(i.date), if (i.kind == TitleKind.show && i.season > 0) 'Season ${i.season}', if (i.runtime.isNotEmpty) i.runtime].join(' · '),
                      style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open the post',
                icon: Icon(Icons.forum_outlined, color: AppColors.text2),
                onPressed: () => openChatInAccount(context, i.chatId, hint: i.account, openAt: i.messageId),
              ),
            ],
          ),
          if (i.ratings.isNotEmpty || i.average != null) ...[
            const SizedBox(height: Space.m),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (i.average != null) _RatingChip(label: 'Average', value: '${i.average}/10', strong: true),
                for (final (name, value) in i.ratings) _RatingChip(label: name, value: value),
              ],
            ),
          ],
          if (i.links.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final (n, (label, url)) in i.links.indexed)
                  n == 0
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.text, foregroundColor: AppColors.bg, visualDensity: VisualDensity.compact),
                          onPressed: () => openUrl(url, context: context),
                          icon: Icon(label.toLowerCase().contains('download') ? Icons.download_rounded : Icons.open_in_new_rounded, size: 18),
                          label: Text(label),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => openUrl(url, context: context),
                          icon: Icon(label.toLowerCase().contains('download') ? Icons.download_rounded : Icons.open_in_new_rounded, size: 18),
                          label: Text(label),
                        ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: strong ? cinemaColor.withValues(alpha: 0.15) : AppColors.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: strong ? cinemaColor.withValues(alpha: 0.4) : AppColors.line)),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label  ', style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w600)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    ),
  );
}


/// Opens a poster post's picture full screen.
Future<void> _openInfoPhoto(BuildContext context, WidgetRef ref, InfoPost i) async {
  final f = i.photo;
  if (f == null) return;
  final path = await ref.read(fileLoaderFamily(i.account)).download(f, priority: 24);
  if (path != null && context.mounted) await openFullscreenFile(context, path, title: i.title);
}

/// Opens [t]'s poster full screen: the channel's own poster when there is
/// one, else the one found online, else a frame of the video.
Future<void> openPoster(BuildContext context, WidgetRef ref, CinemaTitle t, TitleMeta? meta) async {
  if (t.customPoster != null) return openFullscreenFile(context, t.customPoster!, title: t.title);
  if (t.customId != null && !t.posterOnline && t.info?.photo == null && t.posterChat != null) {
    final src = t.posterChat!;
    final f = ref.read(telegramStoreFamily(src.account)).chat(src.chatId)?.photo?.big;
    if (f == null) return;
    final path = await ref.read(fileLoaderFamily(src.account)).download(f, priority: 24);
    if (path != null && context.mounted) await openFullscreenFile(context, path, title: t.title);
    return;
  }
  if (t.customId != null && !t.posterOnline) meta = null;
  final i = t.info;
  if (i?.photo != null) return _openInfoPhoto(context, ref, i!);
  final url = meta?.poster;
  if (url != null) return openFullscreenUrl(context, url, title: t.title);
  final v = t.cover;
  final f = v?.thumb;
  if (v == null || f == null) return;
  final path = await ref.read(fileLoaderFamily(v.account)).download(f, priority: 24);
  if (path != null && context.mounted) await openFullscreenFile(context, path, title: t.title);
}
