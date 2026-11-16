import 'dart:async';

import '../account/account_router.dart' show openChatInAccount;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../sections/section_kit.dart' show BottomAudioBar, Debounce;
import 'podcast_models.dart';
import 'podcast_store.dart';
import 'podcast_widgets.dart';

import 'podcast_skeletons.dart';

/// Opens a show from its feed address or a directory entry.
Future<void> openShow(BuildContext context, {String? feedUrl, PodcastHit? hit}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PodcastShowScreen(feedUrl: feedUrl, hit: hit),
  ),
);

/// One show: its art and details, subscribe, and its episodes to search,
/// filter, sort, download and play.
class PodcastShowScreen extends ConsumerStatefulWidget {
  const PodcastShowScreen({super.key, this.feedUrl, this.hit}) : assert(feedUrl != null || hit != null);
  final String? feedUrl;
  final PodcastHit? hit;

  @override
  ConsumerState<PodcastShowScreen> createState() => _PodcastShowScreenState();
}

class _PodcastShowScreenState extends ConsumerState<PodcastShowScreen> {
  /// Known at once for shows looked up before, so their kept copy shows
  /// while the feed is checked.
  late String? _url = widget.feedUrl ?? ref.read(podcastsProvider).knownFeedFor(widget.hit!);
  late Future<Podcast?> _feed = _load();
  bool _noFeed = false;
  String _filter = 'all';
  String _q = '';
  final _debounce = Debounce();
  (List<Episode>, EpisodeSort, List<Episode>)? _sorted;

  /// Checks the feed (a copy kept under half an hour old counts); [force]
  /// always asks its server.
  Future<Podcast?> _load({bool force = false}) async {
    final pods = ref.read(podcastsProvider);
    await pods.ready;
    _url ??= await pods.feedFor(widget.hit!);
    if (_url == null) {
      _noFeed = !pods.unreachable;
      return null;
    }
    return pods.feed(_url!, refresh: true, force: force);
  }

  @override
  void dispose() {
    _debounce.cancel();
    super.dispose();
  }

  List<Episode> _inOrder(Podcast pod, EpisodeSort sort) {
    final c = _sorted;
    if (c != null && identical(c.$1, pod.episodes) && c.$2 == sort) return c.$3;
    final out = sort.apply(pod.episodes);
    _sorted = (pod.episodes, sort, out);
    return out;
  }

  Future<void> _sortSheet(Podcast pod) async {
    final pods = ref.read(podcastsProvider);
    await showFormSheet<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Order episodes', style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          for (final v in EpisodeSort.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(v.label),
              trailing: pods.hasOwnSort(pod.feedUrl) && pods.sortOf(pod.feedUrl) == v ? Icon(Icons.check_rounded, color: podColor) : null,
              onTap: () {
                pods.setSort(pod.feedUrl, v);
                Navigator.pop(context);
              },
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use the default'),
            subtitle: Text('${EpisodeSort.parse(pods.episodeSort).label}, from the Podcasts settings', style: context.text.bodySmall),
            trailing: !pods.hasOwnSort(pod.feedUrl) ? Icon(Icons.check_rounded, color: podColor) : null,
            onTap: () {
              pods.setSort(pod.feedUrl, null);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pods = ref.watch(podcastsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: const BottomAudioBar(),
      body: FutureBuilder<Podcast?>(
        future: _feed,
        initialData: _url == null ? null : pods.cached(_url!),
        builder: (context, snap) {
          // The store's copy is the newest: a kept feed shows first and is
          // replaced when the server's answer is read.
          final pod = (_url == null ? null : pods.cached(_url!)) ?? snap.data;
          final loading = snap.connectionState != ConnectionState.done;
          if (pod == null && loading) return PodcastShowSkeleton(hit: widget.hit);
          if (pod == null) {
            final hit = widget.hit;
            return CustomScrollView(
              slivers: [
                const SliverAppBar(pinned: true),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hit != null) ...[PodArt(hit.artwork, title: hit.title, size: 140, radius: 22), const SizedBox(height: Space.l), Text(hit.title, textAlign: TextAlign.center, style: context.text.titleMedium)],
                          const SizedBox(height: Space.l),
                          ...[
                            Text(pods.unreachable ? 'Couldn\'t load this show. Check your connection.' : (_noFeed ? 'This show has no public feed.' : 'This feed couldn\'t be read.'), textAlign: TextAlign.center, style: context.text.bodySmall),
                            const SizedBox(height: Space.m),
                            OutlinedButton.icon(onPressed: () => setState(() => _feed = _load(force: true)), icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          final subbed = pods.subscribed(pod.feedUrl);
          final sort = pods.sortOf(pod.feedUrl);
          final eps = _inOrder(pod, sort).where((e) => (_filter == 'all' || pods.stage(e) == _filter || (_filter == 'saved' && pods.isDownloaded(e))) && (_q.isEmpty || e.matches(_q))).toList();
          final counts = <String, int>{};
          for (final e in pod.episodes) {
            final st = pods.stage(e);
            counts[st] = (counts[st] ?? 0) + 1;
          }
          final saved = pod.episodes.where(pods.isDownloaded).length;
          final mark = pods.showMark(pod.feedUrl);
          final art = pod.imageUrl ?? widget.hit?.artwork;
          final downloading = pods.downloads.isNotEmpty;
          return RefreshIndicator(
            color: podColor,
            onRefresh: () async {
              setState(() => _feed = _load(force: true));
              await _feed;
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: true,
                  expandedHeight: 330,
                  backgroundColor: AppColors.bg,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: AppColors.text,
                  title: Text(
                    pod.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  actions: [
                    IconButton(
                      tooltip: mark.favorite ? 'Unfavourite' : 'Favourite',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        mark.favorite = !mark.favorite;
                        pods.marksChanged();
                      },
                      icon: Icon(mark.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: mark.favorite ? podColor : null),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'sort':
                            await _sortSheet(pod);
                          case 'played':
                            pods.markAllPlayed(pod, true);
                          case 'unplayed':
                            pods.markAllPlayed(pod, false);
                          case 'copy':
                            await Clipboard.setData(ClipboardData(text: pod.feedUrl));
                            if (context.mounted) showSnack(context, 'Feed address copied');
                          case 'site':
                            await launchUrl(Uri.parse(pod.link!), mode: LaunchMode.externalApplication);
                          case 'chat':
                            // tg:<account>:<chat>
                            final parts = pod.feedUrl.split(':');
                            final id = int.tryParse(parts.last);
                            final account = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(':') : null;
                            if (id != null && context.mounted) await openChatInAccount(context, id, hint: account);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'sort', child: Text('Order episodes…')),
                        const PopupMenuItem(value: 'played', child: Text('Mark all played')),
                        const PopupMenuItem(value: 'unplayed', child: Text('Mark all unplayed')),
                        if (!pod.isTelegram) const PopupMenuItem(value: 'copy', child: Text('Copy feed address')),
                        if (pod.link != null) const PopupMenuItem(value: 'site', child: Text('Website')),
                        if (pod.isTelegram) const PopupMenuItem(value: 'chat', child: Text('Open the channel')),
                      ],
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    stretchModes: const [StretchMode.zoomBackground],
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Its own layer: the big blur is drawn once, not again
                        // on every frame the header moves or the page rebuilds.
                        if (art != null && !AppLook.minimalExplore)
                          RepaintBoundary(
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.clamp),
                              child: Transform.scale(
                                scale: 1.4,
                                child: Image.network(art, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bg.withValues(alpha: 0.35), AppColors.bg.withValues(alpha: 0.85), AppColors.bg], stops: const [0, 0.65, 1]),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(Space.xl, kToolbarHeight + Space.s, Space.xl, Space.l),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    GestureDetector(
                                      onTap: art == null || art.isEmpty ? null : () => art.startsWith('http') ? openFullscreenUrl(context, art, title: pod.title) : openFullscreenFile(context, art, title: pod.title),
                                      child: Hero(
                                        tag: 'show-${pod.feedUrl}',
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: AppColors.isLight ? 0.15 : 0.45),
                                                blurRadius: 24,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: PodArt(art, title: pod.title, size: 132, radius: 18, show: pod.feedUrl),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: Space.l),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pod.title,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 21, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text),
                                          ),
                                          if (pod.author.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                pod.author,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: AppColors.text2),
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Text('${pod.episodes.length} episodes${loading ? ' · updating' : ''}${saved > 0 ? ' · $saved saved' : ''}', style: TextStyle(fontSize: 12, color: AppColors.text3)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Space.l),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: subbed ? AppColors.text.withValues(alpha: 0.08) : podColor, foregroundColor: subbed ? AppColors.text : AppLook.onBrand(podColor)),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          subbed ? pods.unsubscribe(pod.feedUrl) : pods.subscribe(pod);
                                        },
                                        icon: Icon(subbed ? Icons.check_rounded : Icons.add_rounded),
                                        label: Text(subbed ? 'Following' : 'Follow'),
                                      ),
                                    ),
                                    const SizedBox(width: Space.s),
                                    if (pod.episodes.isNotEmpty)
                                      IconButton.filled(
                                        style: IconButton.styleFrom(minimumSize: const Size(46, 46), backgroundColor: AppColors.text, foregroundColor: AppColors.bg),
                                        tooltip: 'Play latest',
                                        onPressed: () => pods.play(pod.episodes.first),
                                        icon: const Icon(Icons.play_arrow_rounded),
                                      ),
                                    if (!pod.isTelegram) ...[
                                      const SizedBox(width: Space.s),
                                      IconButton.filledTonal(
                                        style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
                                        tooltip: downloading ? 'Stop downloading' : 'Download the ones shown',
                                        onPressed: downloading
                                            ? pods.cancelAllDownloads
                                            : () async {
                                                final todo = eps.where((e) => !pods.isDownloaded(e)).toList();
                                                if (todo.isEmpty) return showSnack(context, 'All saved already');
                                                if (todo.length > 1 && !await confirmDelete(context, title: 'Download ${todo.length} episodes?', message: 'They save one after another for listening offline. Stop any time.', action: 'Download')) return;
                                                final ok = await pods.downloadAll(todo);
                                                if (context.mounted && !ok) showSnack(context, 'Some didn\'t download', icon: Icons.error_outline_rounded);
                                              },
                                        icon: Icon(downloading ? Icons.stop_rounded : Icons.download_for_offline_outlined),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (pod.description.isNotEmpty && _q.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s), child: _Notes(pod.description)),
                  ),
                if (pod.categories.isNotEmpty && _q.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final c in pod.categories.take(6)) Chip(label: Text(c), visualDensity: VisualDensity.compact)],
                      ),
                    ),
                  ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _Pinned(
                    height: 108,
                    child: ColoredBox(
                      color: AppColors.bg,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: TextField(
                                      onChanged: (v) => _debounce(const Duration(milliseconds: 160), () => setState(() => _q = v.trim())),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                        hintText: 'Search this show',
                                        filled: true,
                                        fillColor: AppColors.surface,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: AppColors.line),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(99),
                                          borderSide: BorderSide(color: AppColors.line),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton.icon(onPressed: () => _sortSheet(pod), icon: const Icon(Icons.swap_vert_rounded, size: 18), label: Text(sort.short)),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 8),
                              children: [
                                for (final (id, name, n) in [('all', 'All', pod.episodes.length), ('unplayed', 'Unplayed', counts['unplayed'] ?? 0), ('started', 'In progress', counts['started'] ?? 0), ('played', 'Played', counts['played'] ?? 0), if (saved > 0) ('saved', 'Saved', saved)])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                                      label: Text('$name · $n'),
                                      selectedColor: podColor,
                                      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _filter == id ? AppLook.onBrand(podColor) : AppColors.text),
                                      selected: _filter == id,
                                      onSelected: (_) => setState(() => _filter = id),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (eps.isEmpty && loading && pod.episodes.isEmpty)
                  const SliverToBoxAdapter(child: EpisodeSkeleton())
                else if (eps.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x4),
                      child: Text(_q.isEmpty ? 'No episodes in this view.' : 'No episodes match "$_q".', textAlign: TextAlign.center, style: context.text.bodySmall),
                    ),
                  ),
                SliverList.builder(
                  itemCount: eps.length,
                  itemBuilder: (_, i) => EpisodeRow(episode: eps[i], podcast: pod),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pinned extends SliverPersistentHeaderDelegate {
  _Pinned({required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _Pinned old) => true;
}

class _Notes extends StatefulWidget {
  const _Notes(this.text);
  final String text;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _open = !_open),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Text(
        widget.text,
        maxLines: _open ? null : 3,
        overflow: _open ? null : TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.text2, height: 1.5),
      ),
    ),
  );
}
