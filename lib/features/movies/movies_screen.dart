import 'dart:async';
import '../account/account_router.dart' show openChatInAccount;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../telegram/presentation/tg_avatar.dart';
import 'movies.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../telegram/presentation/formatted_text.dart';
import 'pip.dart';
import 'shorts_screen.dart';
import 'video_comments.dart';
import 'video_session.dart';
import 'video_stats_screen.dart';

import '../sections/skeletons.dart';
/// The section's colour; the app's monochrome one in the minimal look.
Color get moviesColor => AppLook.brand(const Color(0xFFE50914));

/// The accent over pictures and the player (always dark): red, or white in
/// the minimal look.
Color get moviesOnMedia => AppLook.minimalExplore ? Colors.white : const Color(0xFFE50914);

String _clock(int s) {
  if (s <= 0) return '';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

String _views(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M views' : (v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K views' : '$v views');

/// Opens [v]: a vertical one as Shorts (with the channel's other shorts
/// after it), a regular one on the watch page.
void openVideo(BuildContext context, Video v) {
  if (v.vertical) {
    final c = ProviderScope.containerOf(context, listen: false);
    final rest = [for (final x in allVideos(c.read(moviesProvider), c.read(videoFeedProvider), shape: 'tall')) if (x.key != v.key) x];
    rest.sort((a, b) => (b.chatId == v.chatId ? 1 : 0).compareTo(a.chatId == v.chatId ? 1 : 0));
    openShorts(context, [v, ...rest], 0);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: v.key, video: v)));
}

/// Movies: Home (rows, like a streaming service), Browse (a feed, like a
/// video site), Channels and My list.
class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MoviesScreen()));

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(moviesProvider.notifier).ready;
      if (mounted) unawaited(ref.read(videoFeedProvider.notifier).loadAll(_mine()));
    });
  }

  List<SourceRef> _mine() => [for (final s in ref.read(moviesProvider).sources) if (s.account == ref.read(activeAccountIdProvider)) s];

  Future<void> _sources() async {
    final picked = await pickSources(
      context,
      account: ref.read(activeAccountIdProvider),
      current: ref.read(moviesProvider).sources,
      title: 'Video channels',
      hint: 'Channels and groups that post videos and movies.',
    );
    if (picked == null) return;
    await ref.read(moviesProvider.notifier).setSources(picked);
    unawaited(ref.read(videoFeedProvider.notifier).loadAll(_mine()));
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    final all = allVideos(m, feed);
    final hours = all.fold<int>(0, (a, v) => a + v.seconds) ~/ 3600;
    return SectionScaffold(
      title: 'Video',
      icon: Icons.movie_filter_rounded,
      color: moviesColor,
      tabs: const [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.home_outlined, size: 16), SizedBox(width: 6), Text('Home')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.video_library_outlined, size: 16), SizedBox(width: 6), Text('Browse')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.slow_motion_video_rounded, size: 16), SizedBox(width: 6), Text('Shorts')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.subscriptions_outlined, size: 16), SizedBox(width: 6), Text('Channels')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bookmark_border_rounded, size: 16), SizedBox(width: 6), Text('My list')])),
      ],
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            final store = ref.read(moviesProvider.notifier);
            if (v == 'autoplay') await store.setAutoplay(!m.autoplay);
            if (v == 'stats' && context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoStatsScreen()));
            if (v == 'history' && await confirmDelete(context, title: 'Clear watch history?', message: 'Continue watching and progress bars are cleared.', action: 'Clear')) {
              await store.clearHistory();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'stats', child: Text('Watching stats')),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(value: 'autoplay', checked: m.autoplay, child: const Text('Autoplay next')),
            const PopupMenuItem(value: 'history', child: Text('Clear watch history')),
          ],
        ),
        IconButton(tooltip: 'Watching stats', icon: const Icon(Icons.insights_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoStatsScreen()))),
        IconButton(tooltip: 'Channels', icon: const Icon(Icons.add_to_queue_rounded), onPressed: _sources),
      ],
      hero: SectionHero(
        subtitle: m.sources.isEmpty ? 'Your video channels, as a streaming service.' : 'Movies, shows and clips from your channels',
        stats: [
          ('${m.sources.length}', 'channels'),
          ('${all.length}', 'videos'),
          (hours > 0 ? '${hours}h' : '–', 'to watch'),
          ('${m.myList.length}', 'in my list'),
        ],
      ),
      views: [
        _HomeTab(onSources: _sources),
        _BrowseTab(onSources: _sources),
        _ShortsTab(onSources: _sources),
        _ChannelsTab(onSources: _sources),
        const _MyListTab(),
      ],
    );
  }
}

// ---- pieces ------------------------------------------------------------------

/// A video's picture with its length, quality and how much is watched.
class VideoThumb extends ConsumerWidget {
  const VideoThumb({super.key, required this.video, this.aspect = 16 / 9, this.radius = Radii.m, this.showChannel = false});
  final Video video;
  final double aspect;
  final double radius;
  final bool showChannel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    final p = ref.watch(moviesProvider.select((s) => s.progress[v.key]));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TgPicture(
              file: v.thumb,
              mini: v.mini,
              account: v.account,
              cacheWidth: 640,
              placeholder: Container(color: const Color(0xFF1A1A1A), child: const Icon(Icons.movie_outlined, color: Colors.white38)),
            ),
            if (v.seconds > 0 || v.quality.isNotEmpty)
              Positioned(
                right: 6,
                bottom: p == null ? 6 : 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    [if (v.quality.isNotEmpty) v.quality, if (v.seconds > 0) _clock(v.seconds)].join(' · '),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (v.size > 0)
              Positioned(
                left: 6,
                bottom: p == null ? 6 : 9,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(4)),
                  child: Text(sizeText(v.size), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            if (p != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(value: p.fraction, minHeight: 3, color: moviesOnMedia, backgroundColor: Colors.white24),
              ),
          ],
        ),
      ),
    );
  }
}

/// A video in the feed: its picture, the channel's avatar, title and line.
class VideoTile extends ConsumerWidget {
  const VideoTile({super.key, required this.video});
  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    return InkWell(
      onTap: () => openVideo(context, v),
      onLongPress: () => videoMenu(context, ref, v),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoThumb(video: v, radius: Radii.l),
            const SizedBox(height: Space.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TgAvatar(chatId: v.chatId, title: v.channel, size: 36, accountId: v.account),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                      const SizedBox(height: 2),
                      Text(
                        [v.channel, if (v.views > 0) _views(v.views), agoText(v.date)].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.more_vert_rounded, size: 20, color: AppColors.text3), onPressed: () => videoMenu(context, ref, v)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [extras] are actions of the page it's opened from, listed first.
Future<void> videoMenu(BuildContext context, WidgetRef ref, Video v, {List<(IconData, String, VoidCallback)> extras = const []}) async {
  final m = ref.read(moviesProvider);
  final store = ref.read(moviesProvider.notifier);
  final choice = await showAppSheet<String>(
    context,
    initialSize: 0.5,
    builder: (context, scroll) => ListView(
      controller: scroll,
      children: [
        ListTile(title: Text(v.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(v.channel)),
        const Divider(),
        for (final (i, e) in extras.indexed) ListTile(leading: lead(Icon(e.$1)), title: Text(e.$2), onTap: () => Navigator.pop(context, 'extra:$i')),
        if (extras.isNotEmpty) const Divider(),
        ListTile(leading: lead(Icon(m.inList(v.key) ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined)), title: Text(m.inList(v.key) ? 'Remove from My list' : 'Add to My list'), onTap: () => Navigator.pop(context, 'list')),
        ListTile(leading: lead(Icon(m.liked.contains(v.key) ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined)), title: Text(m.liked.contains(v.key) ? 'Unlike' : 'Like'), onTap: () => Navigator.pop(context, 'like')),
        if (m.progress.containsKey(v.key)) ListTile(leading: lead(const Icon(Icons.history_toggle_off_rounded)), title: const Text('Remove from watch history'), onTap: () => Navigator.pop(context, 'unwatch')),
        ListTile(leading: lead(const Icon(Icons.forward_rounded)), title: const Text('Share to a chat'), onTap: () => Navigator.pop(context, 'share')),
        ListTile(leading: lead(const Icon(Icons.forum_outlined)), title: const Text('Open the post'), onTap: () => Navigator.pop(context, 'chat')),
        ListTile(leading: lead(const Icon(Icons.visibility_off_outlined)), title: Text(m.hidden.contains(v.key) ? 'Show again' : 'Hide'), onTap: () => Navigator.pop(context, 'hide')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.startsWith('extra:')) {
    extras[int.parse(choice.substring(6))].$3();
    return;
  }
  switch (choice) {
    case 'list':
      final on = await store.toggleList(SavedVideo.of(v));
      if (context.mounted) showSnack(context, on ? 'Added to My list' : 'Removed from My list', icon: Icons.bookmark_rounded);
    case 'like':
      await store.toggleLike(v.key);
    case 'unwatch':
      await store.clearProgress(v.key);
    case 'share':
      await shareVideo(context, ref, v);
    case 'chat':
      await openChatInAccount(context, v.chatId, hint: v.account, openAt: v.messageId);
    case 'hide':
      await store.setHidden(v.key, !m.hidden.contains(v.key));
  }
}

Future<void> shareVideo(BuildContext context, WidgetRef ref, Video v) async {
  final chat = await pickTelegramChat(context, title: 'Share to…');
  if (chat == null) return;
  try {
    await ref.read(toolRunnerFamily(v.account)).forwardTo(chat, v.chatId, [v.messageId]);
    if (context.mounted) showSnack(context, 'Shared', icon: Icons.forward_rounded);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t share: $e', icon: Icons.error_outline_rounded);
  }
}

// ---- home --------------------------------------------------------------------

class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.onSources});
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.movie_filter_outlined,
          title: 'No video channels yet',
          body: 'Pick channels that post movies, shows or videos. They become rows to browse and watch, with your progress kept.',
          action: 'Add channels',
          onAction: onSources,
        ),
      );
    }
    final seed = ref.watch(videoShuffleProvider);
    final all = allVideos(m, feed, sort: VideoSort.newest, shape: 'wide');
    final shorts = shuffledBy(allVideos(m, feed, sort: VideoSort.newest, shape: 'tall'), seed);
    if (all.isEmpty && shorts.isEmpty) {
      if (feed.anyLoading) return const _HomeSkeleton();
      return SingleChildScrollView(
        child: SectionEmpty(
          icon: Icons.videocam_off_outlined,
          title: feed.errors.isEmpty ? 'No videos yet' : 'Couldn’t load videos',
          body: feed.errors.values.firstOrNull ?? 'Your channels haven’t posted any videos we can find. Add more channels, or pull down to try again.',
          action: 'Add channels',
          onAction: onSources,
        ),
      );
    }
    final seen = <String>{};
    final mixed = shuffledBy(all, seed);
    final featured = [
      for (final v in [...mixed.where((v) => v.seconds >= 600 || v.size > 200 << 20), ...mixed])
        if (seen.add(v.key)) v,
    ].take(5).toList();
    final cont = [for (final p in m.continueWatching) ?ref.read(videoFeedProvider.notifier).byKey(p.key)];
    final long = all.where((v) => v.isLong || (v.seconds == 0 && v.size > 500 << 20)).toList();
    final popular = [...all]..sort((a, b) => b.views.compareTo(a.views));
    final mine = [for (final s in m.myList) ?ref.read(videoFeedProvider.notifier).byKey(s.key)];
    return RefreshIndicator(
      onRefresh: () async => ref.read(videoFeedProvider.notifier).refreshMixed(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          if (featured.isNotEmpty) _FeaturedCarousel(key: ValueKey(identityHashCode(seed)), videos: featured),
          if (seed.isNotEmpty && mixed.length > 4) _Rail(title: 'Mixed for you', videos: mixed.take(20).toList()),
          if (cont.isNotEmpty) _Rail(title: 'Continue watching', videos: cont, wide: true),
          _Rail(title: 'New on your channels', videos: all.take(20).toList()),
          if (mine.isNotEmpty) _Rail(title: 'My list', videos: mine),
          if (popular.isNotEmpty && popular.first.views > 0) _Rail(title: 'Most watched', videos: popular.take(20).toList(), ranked: true),
          if (long.length >= 2) _Rail(title: 'Movies & long watches', videos: long.take(20).toList(), poster: true),
          if (shorts.isNotEmpty)
            _Rail(
              title: 'Shorts',
              videos: shorts.take(30).toList(),
              vertical: true,
              onOpen: (i) => openShorts(context, shorts, i),
              onMore: () => openShorts(context, shorts, 0),
              moreLabel: 'Watch all',
            ),
          for (final s in m.sources.where((s) => !s.hidden))
            if ((feed.bySource[s.key] ?? const <Video>[]).any((v) => !v.vertical))
              _Rail(
                title: s.title,
                chatId: s.chatId,
                videos: [for (final v in feed.bySource[s.key]!) if (!m.hidden.contains(v.key) && !v.vertical) v].take(20).toList(),
                onMore: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: s))),
              ),
        ],
      ),
    );
  }
}

/// The banners at the top of Home, swiped through, with dots.
class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({super.key, required this.videos});
  final List<Video> videos;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final _pages = PageController();
  int _at = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_pages.hasClients || widget.videos.length < 2) return;
      _pages.animateToPage((_at + 1) % widget.videos.length, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
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
    height: 440,
    child: Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          // Swiping by hand stops the slideshow.
          onNotification: (n) {
            if (n.dragDetails != null) _auto?.cancel();
            return false;
          },
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.videos.length,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (_, i) => _Featured(video: widget.videos[i]),
          ),
        ),
        if (widget.videos.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.videos.length; i++)
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

/// Grey shapes where Home's rows will be, while the first pages load.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, {double r = Radii.m}) => Container(width: w, height: h, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(r)));
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.l),
      children: [
        box(double.infinity, 220, r: Radii.l),
        for (var r = 0; r < 3; r++) ...[
          const SizedBox(height: Space.xl),
          box(140, 16, r: 6),
          const SizedBox(height: Space.m),
          Row(children: [for (var i = 0; i < 2; i++) ...[Expanded(child: AspectRatio(aspectRatio: 16 / 9, child: box(double.infinity, double.infinity))), if (i == 0) const SizedBox(width: Space.s)]]),
        ],
      ],
    );
  }
}

/// The big banner at the top of Home.
class _Featured extends ConsumerWidget {
  const _Featured({required this.video});
  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    final m = ref.watch(moviesProvider);
    final p = m.progress[v.key];
    return GestureDetector(
      onTap: () => openVideo(context, v),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 1000, placeholder: Container(color: Colors.black)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xDD000000), Color(0xFF000000)], stops: [0, 0.35, 0.8, 1]),
            ),
          ),
          Positioned(
            left: Space.l,
            right: Space.l,
            bottom: Space.x4,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TgAvatar(chatId: v.chatId, title: v.channel, size: 20, accountId: v.account),
                    const SizedBox(width: 6),
                    Flexible(child: Text(v.channel.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(v.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: Space.s),
                Text(
                  [if (v.quality.isNotEmpty) v.quality, if (v.seconds > 0) _clock(v.seconds), agoText(v.date), if (v.views > 0) _views(v.views)].join('  ·  '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: Space.l),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BannerButton(
                      icon: m.inList(v.key) ? Icons.check_rounded : Icons.add_rounded,
                      label: 'My list',
                      onTap: () => ref.read(moviesProvider.notifier).toggleList(SavedVideo.of(v)),
                    ),
                    const SizedBox(width: Space.l),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size(130, 46)),
                      icon: const Icon(Icons.play_arrow_rounded, size: 28),
                      label: Text(p != null && !p.finished ? 'Resume' : 'Play', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      onPressed: () => openVideo(context, v),
                    ),
                    const SizedBox(width: Space.l),
                    _BannerButton(icon: Icons.info_outline_rounded, label: 'Info', onTap: () => videoMenu(context, ref, v)),
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

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(Radii.m),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11))]),
    ),
  );
}

/// A row of videos that scrolls sideways.
class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.videos, this.wide = false, this.poster = false, this.vertical = false, this.ranked = false, this.chatId, this.onMore, this.onOpen, this.moreLabel = 'See all'});
  final String title;

  /// Opens the video at a place in the row; the watch page when null.
  final void Function(int index)? onOpen;
  final String moreLabel;
  final List<Video> videos;
  final bool wide;
  final bool poster;
  final bool vertical;
  final bool ranked;
  final int? chatId;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final w = vertical ? 120.0 : (poster ? 128.0 : (wide ? 240.0 : 200.0));
    final aspect = vertical ? 9 / 16 : (poster ? 2 / 3 : 16 / 9);
    final h = w / aspect + (vertical || poster ? 24 : 48);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.s, Space.s),
          child: Row(
            children: [
              if (chatId != null) ...[TgAvatar(chatId: chatId, title: title, size: 22), const SizedBox(width: Space.s)],
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              if (onMore != null) TextButton(onPressed: onMore, child: Text(moreLabel)),
            ],
          ),
        ),
        SizedBox(
          height: h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (context, i) {
              final v = videos[i];
              return Consumer(
                builder: (context, ref, _) => GestureDetector(
                  onTap: () => onOpen != null ? onOpen!(i) : openVideo(context, v),
                  onLongPress: () => videoMenu(context, ref, v),
                  child: SizedBox(
                    width: ranked ? w + 34 : w,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ranked)
                          SizedBox(
                            width: 34,
                            child: Text('${i + 1}', style: TextStyle(fontSize: 52, height: 1, fontWeight: FontWeight.w900, color: AppColors.text3.withValues(alpha: 0.6))),
                          ),
                        SizedBox(
                          width: w,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              VideoThumb(video: v, aspect: aspect),
                              const SizedBox(height: 6),
                              Text(v.title, maxLines: vertical || poster ? 1 : 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text)),
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

// ---- browse ------------------------------------------------------------------

class _BrowseTab extends ConsumerStatefulWidget {
  const _BrowseTab({required this.onSources});
  final VoidCallback onSources;

  @override
  ConsumerState<_BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends ConsumerState<_BrowseTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _source;
  String _length = 'any';

  @override
  bool get wantKeepAlive => true;

  Future<void> _more(MoviesState m) async {
    final feed = ref.read(videoFeedProvider.notifier);
    final mine = [for (final s in m.sources) if (!s.hidden && s.account == ref.read(activeAccountIdProvider) && (_source == null || s.key == _source)) s];
    await pooled(mine, 3, (s) => feed.load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(child: SectionEmpty(icon: Icons.video_library_outlined, title: 'Nothing to browse', body: 'Add channels that post videos.', action: 'Add channels', onAction: widget.onSources));
    }
    final seed = ref.watch(videoShuffleProvider);
    final sorted = allVideos(m, feed, sourceKey: _source, query: _q, length: _length, shape: 'wide');
    // A refresh mixes the feed until a sort is picked.
    final list = m.sort == VideoSort.newest && _q.isEmpty ? shuffledBy(sorted, seed) : sorted;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 1000 ? 3 : (width > 640 ? 2 : 1);
    final anyMore = m.sources.any((s) => feed.hasMore(s.key));
    return RefreshIndicator(
      onRefresh: () async => ref.read(videoFeedProvider.notifier).refreshMixed(),
      child: NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800 && !feed.anyLoading && anyMore) _more(m);
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
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search videos', isDense: true),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  PopupMenuButton<VideoSort>(
                    icon: const Icon(Icons.sort_rounded),
                    onSelected: (v) {
                      ref.read(videoShuffleProvider.notifier).clear();
                      ref.read(moviesProvider.notifier).setSort(v);
                    },
                    itemBuilder: (_) => [for (final s in VideoSort.values) CheckedPopupMenuItem(value: s, checked: m.sort == s, child: Text(s.label))],
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
                  for (final (k, label) in const [('any', 'All'), ('short', 'Under 4 min'), ('medium', '4–20 min'), ('long', 'Over 20 min')])
                    Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _length == k, onSelected: (_) => setState(() => _length = k))),
                  const SizedBox(width: Space.s),
                  for (final s in m.sources.where((s) => !s.hidden)) SourceChip(source: s, selected: _source == s.key, onTap: () => setState(() => _source = _source == s.key ? null : s.key)),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: feed.anyLoading ? const Align(alignment: Alignment.topCenter, child: SkeletonGrid(count: 6, maxExtent: 420, childAspectRatio: 1.25)) : Center(child: Text('No videos match', style: context.text.bodySmall)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
              sliver: cols == 1
                  ? SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => VideoTile(video: list[i]))
                  : SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: Space.l, childAspectRatio: 1.15),
                      itemCount: list.length,
                      itemBuilder: (_, i) => VideoTile(video: list[i]),
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

// ---- shorts ------------------------------------------------------------------

/// Every vertical video, as a grid of tall covers; tapping one opens the
/// Shorts feed there.
class _ShortsTab extends ConsumerStatefulWidget {
  const _ShortsTab({required this.onSources});
  final VoidCallback onSources;

  @override
  ConsumerState<_ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends ConsumerState<_ShortsTab> with AutomaticKeepAliveClientMixin {
  String? _source;

  @override
  bool get wantKeepAlive => true;

  Future<void> _more(MoviesState m) async {
    final feed = ref.read(videoFeedProvider.notifier);
    final mine = [for (final s in m.sources) if (!s.hidden && s.account == ref.read(activeAccountIdProvider) && (_source == null || s.key == _source)) s];
    await pooled(mine, 3, (s) => feed.load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(
        child: SectionEmpty(icon: Icons.slow_motion_video_rounded, title: 'No shorts yet', body: 'Add channels that post videos; the vertical ones gather here as Shorts.', action: 'Add channels', onAction: widget.onSources),
      );
    }
    final list = shuffledBy(allVideos(m, feed, sourceKey: _source, sort: VideoSort.newest, shape: 'tall'), ref.watch(videoShuffleProvider));
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 5 : (width > 600 ? 4 : 3);
    final anyMore = m.sources.any((s) => feed.hasMore(s.key));
    final channels = {for (final v in allVideos(m, feed).where((v) => v.vertical)) '${v.account}:${v.chatId}'};
    return RefreshIndicator(
      onRefresh: () async => ref.read(videoFeedProvider.notifier).refreshMixed(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 800 && !feed.anyLoading && anyMore) _more(m);
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (channels.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                    children: [
                      Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _source == null, onSelected: (_) => setState(() => _source = null))),
                      for (final s in m.sources.where((s) => !s.hidden && channels.contains(s.key)))
                        SourceChip(source: s, selected: _source == s.key, onTap: () => setState(() => _source = _source == s.key ? null : s.key)),
                    ],
                  ),
                ),
              ),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: feed.anyLoading
                    ? const Align(alignment: Alignment.topCenter, child: SkeletonGrid(count: 6, maxExtent: 180, childAspectRatio: 0.56, captions: false))
                    : const SectionEmpty(icon: Icons.slow_motion_video_rounded, title: 'No shorts found', body: 'None of the videos loaded so far are vertical. Scroll Browse or pull to refresh to load more.'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.x4 + 80),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 9 / 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ShortCover(video: list[i], progress: m.progress[list[i].key]?.fraction, onTap: () => openShorts(context, list, i)),
                ),
              ),
            if (feed.anyLoading && list.isNotEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
          ],
        ),
      ),
    );
  }
}

// ---- channels ----------------------------------------------------------------

class _ChannelsTab extends ConsumerWidget {
  const _ChannelsTab({required this.onSources});
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    final store = ref.read(moviesProvider.notifier);
    if (m.sources.isEmpty) {
      return SingleChildScrollView(child: SectionEmpty(icon: Icons.subscriptions_outlined, title: 'No channels', body: 'Add channels that post videos.', action: 'Add channels', onAction: onSources));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.x4),
      itemCount: m.sources.length,
      onReorder: (a, b) => store.moveSource(a, b > a ? b - 1 : b),
      itemBuilder: (_, i) {
        final s = m.sources[i];
        final vids = feed.bySource[s.key] ?? const <Video>[];
        return ListTile(
          key: ValueKey(s.key),
          leading: TgAvatar(chatId: s.chatId, title: s.title, size: 46, accountId: s.account),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [feed.loading.contains(s.key) ? 'Loading…' : '${vids.length}${feed.hasMore(s.key) ? '+' : ''} videos', if (s.hidden) 'hidden from Home'].join(' · '),
            style: context.text.bodySmall,
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: s))),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'hide') await store.setSourceHidden(s.key, !s.hidden);
                  if (v == 'remove') await store.removeSource(s.key);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'hide', child: Text(s.hidden ? 'Show on Home' : 'Hide from Home')),
                  PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.danger))),
                ],
              ),
              ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
            ],
          ),
        );
      },
    );
  }
}

/// What a channel says about itself: its description, subscribers and how
/// many videos it has posted in all.
class ChannelAbout {
  const ChannelAbout({this.description = '', this.entities = const [], this.members, this.videos, this.username});
  final String description;
  final List<td.TextEntity> entities;
  final int? members;
  final int? videos;
  final String? username;
}

final _channelAbout = <String, Future<ChannelAbout>>{};

Future<ChannelAbout> loadChannelAbout(WidgetRef ref, SourceRef s) => _channelAbout[s.key] ??= () async {
  final client = ref.read(telegramClientFamily(s.account));
  var description = '';
  int? members;
  String? username;
  try {
    final chat = await client.send<td.Chat>(td.GetChat(chatId: s.chatId), limited: true);
    switch (chat.type) {
      case td.ChatTypeSupergroup(:final supergroupId):
        final full = await client.send<td.SupergroupFullInfo>(td.GetSupergroupFullInfo(supergroupId: supergroupId), limited: true);
        description = full.description;
        members = full.memberCount > 0 ? full.memberCount : null;
        try {
          final sg = await client.send<td.Supergroup>(td.GetSupergroup(supergroupId: supergroupId), limited: true);
          members ??= sg.memberCount > 0 ? sg.memberCount : null;
          username = sg.usernames?.activeUsernames.firstOrNull;
        } catch (_) {}
      case td.ChatTypeBasicGroup(:final basicGroupId):
        final full = await client.send<td.BasicGroupFullInfo>(td.GetBasicGroupFullInfo(basicGroupId: basicGroupId), limited: true);
        description = full.description;
        members = full.members.length;
      default:
        break;
    }
  } catch (_) {}
  var entities = const <td.TextEntity>[];
  if (description.trim().isNotEmpty) {
    try {
      entities = (await client.send<td.TextEntities>(td.GetTextEntities(text: description), limited: true)).entities;
    } catch (_) {}
  }
  int? videos;
  try {
    final v = await client.send<td.Count>(td.GetChatMessageCount(chatId: s.chatId, filter: const td.SearchMessagesFilterVideo(), returnLocal: false), limited: true);
    videos = v.count;
  } catch (_) {}
  return ChannelAbout(description: description, entities: entities, members: members, videos: videos, username: username);
}();

String _compact(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M' : (n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K' : '$n');

/// One channel's page, like a video site's: its banner and picture, name,
/// handle, subscribers and video count, description, then Videos and
/// Shorts tabs.
class ChannelVideosScreen extends ConsumerStatefulWidget {
  const ChannelVideosScreen({super.key, required this.source});
  final SourceRef source;

  @override
  ConsumerState<ChannelVideosScreen> createState() => _ChannelVideosScreenState();
}

class _ChannelVideosScreenState extends ConsumerState<ChannelVideosScreen> {
  VideoSort _sort = VideoSort.newest;
  late final Future<ChannelAbout> _about = loadChannelAbout(ref, widget.source);

  @override
  void initState() {
    super.initState();
    if (!ref.read(videoFeedProvider).bySource.containsKey(widget.source.key)) ref.read(videoFeedProvider.notifier).load(widget.source);
  }

  void _showAbout(ChannelAbout a) => showAppSheet<void>(
    context,
    initialSize: 0.6,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
      children: [
        Row(
          children: [
            TgAvatar(chatId: widget.source.chatId, title: widget.source.title, size: 48, accountId: widget.source.account),
            const SizedBox(width: Space.m),
            Expanded(child: Text(widget.source.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          ],
        ),
        const SizedBox(height: Space.l),
        Text.rich(formattedSpan(td.FormattedText(text: a.description, entities: a.entities)), style: context.text.bodyLarge?.copyWith(height: 1.45)),
        const SizedBox(height: Space.l),
        Divider(color: AppColors.line),
        if (a.username != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.alternate_email_rounded), title: Text('t.me/${a.username}')),
        if (a.members != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.people_alt_outlined), title: Text('${NumberFormat.decimalPattern().format(a.members)} subscribers')),
        if (a.videos != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.video_library_outlined), title: Text('${NumberFormat.decimalPattern().format(a.videos)} videos')),
      ],
    ),
  );

  Widget _grid(List<Video> list, {required bool shorts}) {
    final s = widget.source;
    final feed = ref.watch(videoFeedProvider);
    final m = ref.watch(moviesProvider);
    final width = MediaQuery.sizeOf(context).width;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600 && !feed.loading.contains(s.key) && feed.hasMore(s.key)) ref.read(videoFeedProvider.notifier).load(s, more: true);
        return false;
      },
      child: CustomScrollView(
        key: PageStorageKey('channel-${s.key}-$shorts'),
        slivers: [
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: feed.loading.contains(s.key)
                  ? Align(alignment: Alignment.topCenter, child: SkeletonGrid(count: 6, maxExtent: shorts ? 180 : 420, childAspectRatio: shorts ? 0.56 : 1.25, captions: !shorts))
                  : SectionEmpty(icon: shorts ? Icons.slow_motion_video_rounded : Icons.videocam_off_outlined, title: shorts ? 'No shorts' : 'No videos', body: shorts ? 'This channel hasn’t posted vertical videos yet.' : 'Nothing loaded from this channel yet.'),
            )
          else if (shorts)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.x4),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: width > 600 ? 4 : 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 9 / 16),
                itemCount: list.length,
                itemBuilder: (_, i) => ShortCover(video: list[i], progress: m.progress[list[i].key]?.fraction, onTap: () => openShorts(context, list, i)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
              sliver: SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => VideoTile(video: list[i])),
            ),
          if (feed.loading.contains(s.key) && list.isNotEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    final all = allVideos(m, feed, sourceKey: s.key, sort: _sort, includeHidden: false);
    final wide = [for (final v in all) if (!v.vertical) v];
    final shorts = [for (final v in all) if (v.vertical) v];
    final subscribed = m.sources.any((x) => x.key == s.key);
    final minimal = AppLook.minimalExplore;
    final fg = minimal ? AppColors.text : Colors.white;
    final fg2 = minimal ? AppColors.text2 : Colors.white70;
    return SectionScaffold(
      title: s.title,
      icon: Icons.smart_display_rounded,
      color: moviesColor,
      expandedHeight: 250,
      actions: [
        PopupMenuButton<VideoSort>(
          icon: const Icon(Icons.sort_rounded),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [for (final x in VideoSort.values) CheckedPopupMenuItem(value: x, checked: _sort == x, child: Text(x.label))],
        ),
      ],
      tabs: [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.smart_display_outlined, size: 16), const SizedBox(width: 6), Text('Videos${wide.isEmpty ? '' : ' · ${wide.length}'}')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.slow_motion_video_rounded, size: 16), const SizedBox(width: 6), Text('Shorts${shorts.isEmpty ? '' : ' · ${shorts.length}'}')])),
      ],
      views: [_grid(wide, shorts: false), _grid(shorts, shorts: true)],
      hero: FutureBuilder<ChannelAbout>(
        future: _about,
        builder: (context, snap) {
          final a = snap.data;
          final loaded = '${all.length}${feed.hasMore(s.key) ? '+' : ''}';
          final line = [
            if (a?.username != null) '@${a!.username}',
            if (a?.members != null) '${_compact(a!.members!)} subscribers',
            '${a?.videos != null ? _compact(a!.videos!) : loaded} videos',
          ].join('  ·  ');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: 0.5), width: 1.5)),
                    child: TgAvatar(chatId: s.chatId, title: s.title, size: 64, accountId: s.account),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
                        const SizedBox(height: 4),
                        Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg2, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              if (a != null && a.description.trim().isNotEmpty) ...[
                const SizedBox(height: Space.m),
                GestureDetector(
                  onTap: () => _showAbout(a),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          a.description.replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg2, fontSize: 13, height: 1.35),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: fg2, size: 20),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Space.m),
              Row(
                children: [
                  if (!subscribed)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: minimal ? AppColors.bg : Colors.black, visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                      onPressed: () => ref.read(moviesProvider.notifier).addSources([s]),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add to my channels'),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.4)), visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                      onPressed: null,
                      icon: Icon(Icons.check_rounded, size: 18, color: fg),
                      label: Text('In my channels', style: TextStyle(color: fg)),
                    ),
                  const SizedBox(width: Space.s),
                  if (shorts.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.4)), visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                      onPressed: () => openShorts(context, shorts, 0),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Play shorts'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A short's tall cover in a grid: picture, title, views or length.
class ShortCover extends ConsumerWidget {
  const ShortCover({super.key, required this.video, required this.onTap, this.progress});
  final Video video;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = video;
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => videoMenu(context, ref, v),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.s),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 360, placeholder: Container(color: AppColors.surface2)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)], stops: [0, 0.55, 1]),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 13, color: Colors.white70),
                      Text(v.views > 0 ? _views(v.views).replaceAll(' views', '') : _clock(v.seconds), style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            if (progress != null) Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: progress, minHeight: 2.5, color: moviesOnMedia, backgroundColor: Colors.white24)),
          ],
        ),
      ),
    );
  }
}

// ---- my list -----------------------------------------------------------------

class _MyListTab extends ConsumerWidget {
  const _MyListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(moviesProvider);
    final store = ref.read(moviesProvider.notifier);
    final history = m.progress.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    if (m.myList.isEmpty && history.isEmpty) {
      return const SingleChildScrollView(
        child: SectionEmpty(icon: Icons.bookmark_border_rounded, title: 'Nothing saved yet', body: 'Tap “My list” on any video to keep it for later. What you watch shows up here too, so you can pick up where you left off.'),
      );
    }
    Widget row(String key, String title, String sub, String? mini, {double? fraction, int seconds = 0, required VoidCallback onRemove, required String removeLabel}) => Dismissible(
      key: ValueKey('$removeLabel$key'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        color: AppColors.danger.withValues(alpha: 0.15),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delete_outline_rounded, color: AppColors.danger), const SizedBox(width: 6), Text(removeLabel, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700))]),
      ),
      onDismissed: (_) => onRemove(),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: key))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.s),
                child: SizedBox(
                  width: 132,
                  height: 74,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      mini == null ? Container(color: AppColors.surface2, child: Icon(Icons.movie_outlined, color: AppColors.text3)) : Image.memory(base64Decode(mini), fit: BoxFit.cover),
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 28, shadows: [Shadow(blurRadius: 8)])),
                      if (seconds > 0)
                        Positioned(
                          right: 4,
                          bottom: fraction == null ? 4 : 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(4)),
                            child: Text(_clock(seconds), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      if (fraction != null) Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: fraction, minHeight: 3, color: moviesOnMedia, backgroundColor: Colors.white24)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                    const SizedBox(height: 3),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget heading(String text, int count, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.xs),
      child: Row(
        children: [
          Text(text, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text('$count', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(top: Space.xs, bottom: Space.x4 + 80),
      children: [
        if (m.myList.isNotEmpty) ...[
          heading('My list', m.myList.length),
          for (final s in m.myList)
            row(
              s.key,
              s.title,
              [s.channel, 'added ${agoText(s.addedAt)}'].join(' · '),
              s.mini,
              seconds: s.seconds,
              fraction: m.progress[s.key]?.fraction,
              removeLabel: 'Remove',
              onRemove: () => store.toggleList(s),
            ),
        ],
        if (history.isNotEmpty) ...[
          heading(
            'History',
            history.length,
            trailing: TextButton(
              onPressed: () async {
                if (await confirmDelete(context, title: 'Clear watch history?', message: 'Continue watching and progress bars are cleared.', action: 'Clear')) await store.clearHistory();
              },
              child: const Text('Clear'),
            ),
          ),
          for (final p in history.take(60))
            row(
              p.key,
              p.title,
              [p.channel, p.finished ? 'watched' : '${(p.fraction * 100).round()}% watched', agoText(p.at)].join(' · '),
              p.mini,
              seconds: p.length,
              fraction: p.fraction,
              removeLabel: 'Forget',
              onRemove: () => store.clearProgress(p.key),
            ),
        ],
      ],
    );
  }
}

// ---- watching ----------------------------------------------------------------

/// The watch page: the player, then the title, actions, channel,
/// description and what's next from the same channel. What plays lives in
/// [videoSessionProvider], so closing this page (the chevron, back, or a
/// swipe down on the player) leaves it playing in the mini player.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, required this.videoKey, this.video});
  final String videoKey;
  final Video? video;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  late final VideoSession _session = ref.read(videoSessionProvider.notifier);
  bool _full = false;
  bool _chrome = true;
  bool _more = false;
  bool _saving = false;
  Timer? _hide;

  /// The side last double-tapped (−1 back, 1 ahead) while its hint shows.
  int _seekHint = 0;
  int _seekBy = 0;
  Timer? _seekHintOff;
  double _pull = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session.enterWatchPage();
      final v = widget.video;
      v != null ? _session.open(v) : _session.openKey(widget.videoKey);
      _autoHide();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _seekHintOff?.cancel();
    final s = _session;
    Future.microtask(s.leftWatchPage);
    if (_full) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (ref.read(videoSessionProvider).controller?.value.isPlaying ?? false)) setState(() => _chrome = false);
    });
  }

  Future<void> _setFull(bool v) async {
    setState(() => _full = v);
    if (v) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final landscape = (ref.read(videoSessionProvider).controller?.value.aspectRatio ?? 1.7) > 1;
      await SystemChrome.setPreferredOrientations(landscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  void _seek(VideoPlayerController c, int by) {
    final at = c.value.position + Duration(seconds: by);
    c.seekTo(at < Duration.zero ? Duration.zero : at);
    _session.restartIfEnded();
    setState(() {
      _seekBy = _seekHint == by.sign ? _seekBy + by : by;
      _seekHint = by.sign;
    });
    _seekHintOff?.cancel();
    _seekHintOff = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = 0);
    });
  }

  Future<void> _saveToDevice(Video v) async {
    if (v.file == null || _saving) return;
    setState(() => _saving = true);
    try {
      final path = await ref.read(fileLoaderFamily(v.account)).download(v.file!, priority: 32);
      if (path != null) await Gal.putVideo(path, album: 'Triangle');
      if (mounted) showSnack(context, path == null ? 'Couldn\'t download it' : 'Saved to your gallery', icon: Icons.download_done_rounded);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t save: $e', icon: Icons.error_outline_rounded);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _openPost(Video v) => openChatInAccount(context, v.chatId, hint: v.account, openAt: v.messageId);

  Widget _player(VideoSessionState s) {
    final v = s.video;
    final c = s.controller;
    final loader = fileLoaderFor(ref, v?.account);
    Widget body;
    if (s.error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 36),
              const SizedBox(height: Space.s),
              Text(s.error!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: Space.m),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v != null) ...[
                    FilledButton.tonalIcon(onPressed: _session.retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                    const SizedBox(width: Space.s),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                      onPressed: () => _openPost(v),
                      child: const Text('Open post'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (v != null) TgPicture(file: v.thumb, mini: v.mini, account: v.account, fit: BoxFit.cover, cacheWidth: 900, placeholder: const SizedBox()),
          Container(color: Colors.black.withValues(alpha: 0.6)),
          Center(
            child: v?.file == null
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                : ValueListenableBuilder<double>(
                    valueListenable: loader.progress(v!.file!),
                    builder: (_, p, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.square(dimension: 60, child: CircularProgressIndicator(value: p > 0 ? p : null, color: Colors.white, backgroundColor: Colors.white12, strokeWidth: 3)),
                            if (p > 0) Text('${(p * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: Space.m),
                        Text(
                          s.paused ? 'Download paused' : (p > 0 ? 'Downloading${v.size > 0 ? ' · ${sizeText(v.size)}' : ''}' : 'Getting the video ready…'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: Space.m),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundButton(icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, onTap: s.paused ? _session.resumeDownload : _session.pauseDownload),
                            const SizedBox(width: Space.m),
                            _RoundButton(
                              icon: Icons.close_rounded,
                              onTap: () async {
                                await _session.cancelDownload();
                                if (mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    } else {
      body = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, value, _) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _chrome = !_chrome);
            if (_chrome) _autoHide();
          },
          onDoubleTapDown: (d) {
            final w = context.size?.width ?? 400;
            _seek(c, d.localPosition.dx < w / 2 ? -10 : 10);
          },
          onDoubleTap: () {},
          // Holding the video: full screen with nothing over it.
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() => _chrome = false);
            if (!_full) _setFull(true);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(c))),
              if (value.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5)),
              if (_seekHint != 0)
                Align(
                  alignment: _seekHint < 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: _seekHint < 0
                            ? const BorderRadius.horizontal(right: Radius.circular(999))
                            : const BorderRadius.horizontal(left: Radius.circular(999)),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_seekHint < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: Colors.white),
                          Text('${_seekBy.abs()} seconds', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _chrome ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x33000000), Color(0x33000000), Color(0xAA000000)],
                        stops: [0, 0.3, 0.65, 1],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4,
                          top: 4,
                          right: 4,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: _full ? 'Exit full screen' : 'Minimize',
                                icon: Icon(_full ? Icons.close_fullscreen_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                                onPressed: () => _full ? _setFull(false) : Navigator.pop(context),
                              ),
                              if (_full && v != null)
                                Expanded(child: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))
                              else
                                const Spacer(),
                              if (s.streaming)
                                Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                                  child: const Text('STREAMING', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                ),
                              IconButton(
                                tooltip: 'Picture in picture',
                                icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 22),
                                onPressed: () async {
                                  final ok = await Pip.enter(value.size == Size.zero ? const Size(16, 9) : value.size);
                                  if (!ok && context.mounted) showSnack(context, 'Picture in picture needs the app rebuilt, or isn’t on for Triangle in Android settings', icon: Icons.picture_in_picture_alt_rounded);
                                },
                              ),
                              PopupMenuButton<double>(
                                tooltip: 'Speed',
                                icon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
                                    if (value.playbackSpeed != 1) Text(' ${value.playbackSpeed}×', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                onSelected: c.setPlaybackSpeed,
                                itemBuilder: (_) => [for (final sp in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) CheckedPopupMenuItem(value: sp, checked: value.playbackSpeed == sp, child: Text(sp == 1 ? 'Normal' : '$sp×'))],
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoundButton(icon: Icons.replay_10_rounded, size: 46, onTap: () => _seek(c, -10)),
                              const SizedBox(width: Space.xxl),
                              _RoundButton(
                                icon: value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 64,
                                onTap: () {
                                  _session.toggle();
                                  _autoHide();
                                },
                              ),
                              const SizedBox(width: Space.xxl),
                              _RoundButton(icon: Icons.forward_10_rounded, size: 46, onTap: () => _seek(c, 10)),
                            ],
                          ),
                        ),
                        Positioned(
                          left: Space.m,
                          right: 4,
                          bottom: 0,
                          child: Row(
                            children: [
                              Text(
                                '${_clock(value.position.inSeconds).isEmpty ? '0:00' : _clock(value.position.inSeconds)} / ${_clock(value.duration.inSeconds)}',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: moviesOnMedia,
                                    thumbColor: moviesOnMedia,
                                    inactiveTrackColor: Colors.white24,
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  ),
                                  child: Slider(
                                    value: value.position.inMilliseconds.toDouble().clamp(0, value.duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                                    max: value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                    onChangeStart: (_) => _hide?.cancel(),
                                    onChanged: (x) => c.seekTo(Duration(milliseconds: x.round())),
                                    onChangeEnd: (_) {
                                      _session.restartIfEnded();
                                      _autoHide();
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: _full ? 'Exit full screen' : 'Full screen',
                                icon: Icon(_full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                                onPressed: () => _setFull(!_full),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // The thin progress line while the controls are hidden.
              if (!_chrome && !_full)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: value.duration.inMilliseconds <= 0 ? 0 : (value.position.inMilliseconds / value.duration.inMilliseconds).clamp(0.0, 1.0),
                    minHeight: 2,
                    color: moviesOnMedia,
                    backgroundColor: Colors.white24,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(color: Colors.black, child: body);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(videoSessionProvider);
    final v = s.video ?? widget.video;
    if (_full) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _setFull(false);
        },
        child: Scaffold(backgroundColor: Colors.black, resizeToAvoidBottomInset: false, body: SizedBox.expand(child: _player(s))),
      );
    }
    final m = ref.watch(moviesProvider);
    ref.watch(videoFeedProvider);
    final next = _session.upNext();
    final source = v == null ? null : m.sources.where((x) => x.chatId == v.chatId && x.account == v.account).firstOrNull;
    final channelCount = source == null ? 0 : (ref.read(videoFeedProvider).bySource[source.key]?.length ?? 0);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Container(color: Colors.black, height: MediaQuery.paddingOf(context).top),
          // Pulling the player down closes the page into the mini player.
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() => _pull = (_pull + d.delta.dy).clamp(0, 240)),
            onVerticalDragEnd: (d) {
              if (_pull > 90 || d.velocity.pixelsPerSecond.dy > 700) {
                Navigator.pop(context);
              } else {
                setState(() => _pull = 0);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _pull * 0.6),
              // Never taller than part of the screen, so turning the phone
              // (leaving full screen) can't push the page past its edge.
              child: Opacity(
                opacity: (1 - _pull / 400).clamp(0.4, 1),
                child: SizedBox(
                  width: double.infinity,
                  height: math.min(MediaQuery.sizeOf(context).width * 9 / 16, MediaQuery.sizeOf(context).height * 0.5),
                  child: _player(s),
                ),
              ),
            ),
          ),
          if (v != null)
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(0, Space.l, 0, Space.x4 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (v.quality.isNotEmpty) _Badge(v.quality),
                            Text(
                              [if (v.views > 0) _views(v.views), agoText(v.date), if (v.seconds > 0) _clock(v.seconds), if (v.size > 0) sizeText(v.size)].join(' · '),
                              style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  // The channel, like a video site's.
                  InkWell(
                    onTap: source == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: source))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
                      child: Row(
                        children: [
                          TgAvatar(chatId: v.chatId, title: v.channel, size: 40, accountId: v.account),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (channelCount > 0) Text('$channelCount videos', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                              ],
                            ),
                          ),
                          if (source != null)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, shape: const StadiumBorder()),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: source))),
                              child: const Text('View channel'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.m),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Space.l),
                      children: [
                        _Action(
                          icon: m.liked.contains(v.key) ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                          label: m.liked.contains(v.key) ? 'Liked' : 'Like',
                          active: m.liked.contains(v.key),
                          onTap: () => ref.read(moviesProvider.notifier).toggleLike(v.key),
                        ),
                        _Action(
                          icon: m.inList(v.key) ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                          label: m.inList(v.key) ? 'Saved' : 'My list',
                          active: m.inList(v.key),
                          onTap: () => ref.read(moviesProvider.notifier).toggleList(SavedVideo.of(v)),
                        ),
                        _Action(icon: Icons.forward_rounded, label: 'Share', onTap: () => shareVideo(context, ref, v)),
                        _Action(icon: _saving ? Icons.hourglass_top_rounded : Icons.download_rounded, label: _saving ? 'Saving…' : 'Download', onTap: () => _saveToDevice(v)),
                        _Action(icon: Icons.forum_outlined, label: 'Open post', onTap: () => _openPost(v)),
                      ],
                    ),
                  ),
                  if (v.description.isNotEmpty && v.description != v.title)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
                      child: Material(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(Radii.m),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.m),
                          onTap: () => setState(() => _more = !_more),
                          child: Padding(
                            padding: const EdgeInsets.all(Space.m),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  formattedSpan(v.caption ?? td.FormattedText(text: v.description, entities: const [])),
                                  maxLines: _more ? null : 3,
                                  overflow: _more ? null : TextOverflow.ellipsis,
                                  style: context.text.bodyMedium?.copyWith(height: 1.4),
                                ),
                                const SizedBox(height: 4),
                                Text(_more ? 'Show less' : 'More', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                    child: CommentsPreview(key: ValueKey(v.key), account: v.account, chatId: v.chatId, messageId: v.messageId),
                  ),
                  if (next.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.s, Space.xs),
                      child: Row(
                        children: [
                          Expanded(child: Text('Up next', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                          Text('Autoplay', style: context.text.bodySmall),
                          const SizedBox(width: 4),
                          Switch(value: m.autoplay, onChanged: ref.read(moviesProvider.notifier).setAutoplay),
                        ],
                      ),
                    ),
                    for (final (i, x) in next.take(12).indexed)
                      InkWell(
                        onTap: () => _session.open(x),
                        onLongPress: () => videoMenu(context, ref, x),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 156, child: VideoThumb(video: x)),
                              const SizedBox(width: Space.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (i == 0 && m.autoplay)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text('NEXT', style: context.text.labelSmall?.copyWith(color: moviesColor, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                      ),
                                    Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                                    const SizedBox(height: 2),
                                    Text([if (x.views > 0) _views(x.views), agoText(x.date)].join(' · '), style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            )
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.size = 44});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.35),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox.square(dimension: size, child: Icon(icon, color: Colors.white, size: size * 0.58)),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(border: Border.all(color: AppColors.text3), borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(color: AppColors.text2, fontSize: 10.5, fontWeight: FontWeight.w800)),
  );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.s),
    child: Material(
      color: active ? AppColors.text : AppColors.surface2,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? AppColors.bg : AppColors.text),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? AppColors.bg : AppColors.text)),
            ],
          ),
        ),
      ),
    ),
  );
}
