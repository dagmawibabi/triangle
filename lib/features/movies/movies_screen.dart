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
import '../../infrastructure/telegram/accounts.dart';
import '../media/audio_center.dart';
import '../playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../telegram/presentation/chat_view_screen.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'movies.dart';
import 'tg_stream.dart';

const moviesColor = Color(0xFFE50914);

String _clock(int s) {
  if (s <= 0) return '';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

String _views(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M views' : (v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K views' : '$v views');

void openVideo(BuildContext context, Video v) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: v.key, video: v)));

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
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.subscriptions_outlined, size: 16), SizedBox(width: 6), Text('Channels')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bookmark_border_rounded, size: 16), SizedBox(width: 6), Text('My list')])),
      ],
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            final store = ref.read(moviesProvider.notifier);
            if (v == 'autoplay') await store.setAutoplay(!m.autoplay);
            if (v == 'history' && await confirmDelete(context, title: 'Clear watch history?', message: 'Continue watching and progress bars are cleared.', action: 'Clear')) {
              await store.clearHistory();
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: 'autoplay', checked: m.autoplay, child: const Text('Autoplay next')),
            const PopupMenuItem(value: 'history', child: Text('Clear watch history')),
          ],
        ),
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
                child: LinearProgressIndicator(value: p.fraction, minHeight: 3, color: moviesColor, backgroundColor: Colors.white24),
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
                TgAvatar(chatId: v.chatId, title: v.channel, size: 36),
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

Future<void> videoMenu(BuildContext context, WidgetRef ref, Video v) async {
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
  switch (choice) {
    case 'list':
      final on = await store.toggleList(SavedVideo.of(v));
      if (context.mounted) showSnack(context, on ? 'Added to My list' : 'Removed from My list', icon: Icons.bookmark_rounded);
    case 'like':
      await store.toggleLike(v.key);
    case 'unwatch':
      await store.clearProgress(v.key);
    case 'share':
      await _share(context, ref, v);
    case 'chat':
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: v.chatId, openAt: v.messageId)));
    case 'hide':
      await store.setHidden(v.key, !m.hidden.contains(v.key));
  }
}

Future<void> _share(BuildContext context, WidgetRef ref, Video v) async {
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
    final all = allVideos(m, feed, sort: VideoSort.newest);
    if (all.isEmpty) {
      return Center(child: feed.anyLoading ? const CircularProgressIndicator(strokeWidth: 2) : Text(feed.errors.values.firstOrNull ?? 'No videos yet', style: context.text.bodySmall));
    }
    final featured = (all.where((v) => v.seconds >= 600 || v.size > 200 << 20).toList()..addAll(all)).first;
    final cont = [for (final p in m.continueWatching) ?ref.read(videoFeedProvider.notifier).byKey(p.key)];
    final long = all.where((v) => v.isLong || (v.seconds == 0 && v.size > 500 << 20)).toList();
    final shorts = all.where((v) => v.isShort).toList();
    final popular = [...all]..sort((a, b) => b.views.compareTo(a.views));
    final mine = [for (final s in m.myList) ?ref.read(videoFeedProvider.notifier).byKey(s.key)];
    return RefreshIndicator(
      onRefresh: () => ref.read(videoFeedProvider.notifier).loadAll(m.sources.where((s) => s.account == ref.read(activeAccountIdProvider)), refresh: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          _Featured(video: featured),
          if (cont.isNotEmpty) _Rail(title: 'Continue watching', videos: cont, wide: true),
          _Rail(title: 'New on your channels', videos: all.take(20).toList()),
          if (mine.isNotEmpty) _Rail(title: 'My list', videos: mine),
          if (popular.first.views > 0) _Rail(title: 'Most watched', videos: popular.take(20).toList(), ranked: true),
          if (long.length >= 2) _Rail(title: 'Movies & long watches', videos: long.take(20).toList(), poster: true),
          if (shorts.length >= 3) _Rail(title: 'Shorts', videos: shorts.take(20).toList(), vertical: true),
          for (final s in m.sources.where((s) => !s.hidden))
            if ((feed.bySource[s.key] ?? const <Video>[]).isNotEmpty)
              _Rail(
                title: s.title,
                chatId: s.chatId,
                videos: [for (final v in feed.bySource[s.key]!) if (!m.hidden.contains(v.key)) v].take(20).toList(),
                onMore: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: s))),
              ),
        ],
      ),
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
    return SizedBox(
      height: 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TgPicture(file: v.thumb, mini: v.mini, cacheWidth: 1000, placeholder: Container(color: Colors.black)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xDD000000), Color(0xFF000000)], stops: [0, 0.35, 0.8, 1]),
            ),
          ),
          Positioned(
            left: Space.l,
            right: Space.l,
            bottom: Space.l,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TgAvatar(chatId: v.chatId, title: v.channel, size: 20),
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
  const _Rail({required this.title, required this.videos, this.wide = false, this.poster = false, this.vertical = false, this.ranked = false, this.chatId, this.onMore});
  final String title;
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
              if (onMore != null) TextButton(onPressed: onMore, child: const Text('See all')),
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
                  onTap: () => openVideo(context, v),
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
    final list = allVideos(m, feed, sourceKey: _source, query: _q, length: _length);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 1000 ? 3 : (width > 640 ? 2 : 1);
    final anyMore = m.sources.any((s) => feed.hasMore(s.key));
    return NotificationListener<ScrollNotification>(
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
                    onSelected: ref.read(moviesProvider.notifier).setSort,
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
              child: Center(child: feed.anyLoading ? const CircularProgressIndicator(strokeWidth: 2) : Text('No videos match', style: context.text.bodySmall)),
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
          leading: TgAvatar(chatId: s.chatId, title: s.title, size: 46),
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

/// One channel's page: every video it posted.
class ChannelVideosScreen extends ConsumerStatefulWidget {
  const ChannelVideosScreen({super.key, required this.source});
  final SourceRef source;

  @override
  ConsumerState<ChannelVideosScreen> createState() => _ChannelVideosScreenState();
}

class _ChannelVideosScreenState extends ConsumerState<ChannelVideosScreen> {
  VideoSort _sort = VideoSort.newest;

  @override
  void initState() {
    super.initState();
    if (!ref.read(videoFeedProvider).bySource.containsKey(widget.source.key)) ref.read(videoFeedProvider.notifier).load(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final m = ref.watch(moviesProvider);
    final feed = ref.watch(videoFeedProvider);
    final list = allVideos(m, feed, sourceKey: s.key, sort: _sort);
    final hours = list.fold<int>(0, (a, v) => a + v.seconds) ~/ 3600;
    return SectionScaffold(
      title: s.title,
      icon: Icons.smart_display_rounded,
      color: moviesColor,
      expandedHeight: 200,
      actions: [
        PopupMenuButton<VideoSort>(
          icon: const Icon(Icons.sort_rounded),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [for (final x in VideoSort.values) CheckedPopupMenuItem(value: x, checked: _sort == x, child: Text(x.label))],
        ),
      ],
      hero: Row(
        children: [
          TgAvatar(chatId: s.chatId, title: s.title, size: 60),
          const SizedBox(width: Space.l),
          Expanded(child: SectionHero(subtitle: 'Channel', stats: [('${list.length}${feed.hasMore(s.key) ? '+' : ''}', 'videos'), (hours > 0 ? '${hours}h' : '–', 'of video')])),
        ],
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Space.l),
          sliver: SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => VideoTile(video: list[i])),
        ),
        if (feed.hasMore(s.key))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.x4),
              child: Center(
                child: feed.loading.contains(s.key)
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : OutlinedButton(onPressed: () => ref.read(videoFeedProvider.notifier).load(s, more: true), child: const Text('Load more')),
              ),
            ),
          ),
      ],
    );
  }
}

// ---- my list -----------------------------------------------------------------

class _MyListTab extends ConsumerWidget {
  const _MyListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(moviesProvider);
    final history = m.progress.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    if (m.myList.isEmpty && history.isEmpty) {
      return const SingleChildScrollView(child: SectionEmpty(icon: Icons.bookmark_border_rounded, title: 'Nothing saved', body: 'Add videos to My list to watch later. What you watch shows here too.'));
    }
    Widget row(String key, String title, String sub, String? mini, {double? fraction}) => ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.s),
        child: SizedBox(
          width: 96,
          height: 54,
          child: Stack(
            fit: StackFit.expand,
            children: [
              mini == null ? Container(color: AppColors.surface2, child: Icon(Icons.movie_outlined, color: AppColors.text3)) : Image.memory(base64Decode(mini), fit: BoxFit.cover),
              if (fraction != null) Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: fraction, minHeight: 3, color: moviesColor, backgroundColor: Colors.white24)),
            ],
          ),
        ),
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, style: context.text.bodySmall),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: key))),
    );
    return ListView(
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.x4),
      children: [
        if (m.myList.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs), child: Text('MY LIST', style: context.text.labelSmall)),
          for (final s in m.myList) row(s.key, s.title, [s.channel, if (s.seconds > 0) _clock(s.seconds)].join(' · '), s.mini, fraction: m.progress[s.key]?.fraction),
        ],
        if (history.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs), child: Text('HISTORY', style: context.text.labelSmall)),
          for (final p in history.take(60)) row(p.key, p.title, '${p.channel} · ${agoText(p.at)}', p.mini, fraction: p.fraction),
        ],
      ],
    );
  }
}

// ---- watching ----------------------------------------------------------------

/// The watch page: the player, then the title, actions, channel,
/// description and what's next from the same channel.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, required this.videoKey, this.video});
  final String videoKey;
  final Video? video;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  Video? _v;
  String? _error;
  VideoPlayerController? _c;
  bool _full = false;
  bool _chrome = true;
  bool _more = false;
  bool _saving = false;
  bool _paused = false;

  /// Playing from Telegram as it's fetched, not from a finished download.
  bool _streaming = false;

  /// The person asked to download the whole file instead of streaming.
  bool _wholeFile = false;
  Timer? _hide;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _v = widget.video;
    if (_v == null) {
      ref.read(videoFeedProvider.notifier).fetch(widget.videoKey).then((v) {
        if (!mounted) return;
        if (v == null) {
          setState(() => _error = 'This video is gone.');
        } else {
          setState(() => _v = v);
          _start();
        }
      }).catchError((Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    } else {
      _start();
    }
  }

  Future<void> _start() async {
    final v = _v!;
    final file = v.file;
    if (file == null) return setState(() => _error = 'This video can\'t be played.');
    // The music player pauses while a video plays.
    final audio = ref.read(audioCenterProvider);
    if (audio.playing) unawaited(audio.toggle());
    final loader = ref.read(fileLoaderProvider);
    VideoPlayerController? c;
    // Streams when Telegram allows it and the file isn't on the phone yet.
    if (!_wholeFile && loader.cachedPath(file) == null && (v.streaming || v.fileName.toLowerCase().endsWith('.mp4'))) {
      try {
        final mime = v.fileName.toLowerCase().endsWith('.mkv') ? 'video/x-matroska' : (v.fileName.toLowerCase().endsWith('.webm') ? 'video/webm' : 'video/mp4');
        final url = await ref.read(tgStreamFamily(v.account)).url(file, mime: mime);
        final s = VideoPlayerController.networkUrl(url);
        await s.initialize();
        c = s;
        _streaming = true;
      } catch (e) {
        debugPrint('[Watch] streaming failed, downloading: $e');
        _streaming = false;
      }
    }
    if (c == null) {
      final path = await (_paused ? loader.resume(file) : loader.download(file, priority: 32));
      if (!mounted) return;
      if (path == null && loader.isPaused(file)) return setState(() => _paused = true);
      if (path == null) return setState(() => _error = 'Couldn\'t download the video.');
      _paused = false;
      final f = VideoPlayerController.file(File(path));
      try {
        await f.initialize();
      } catch (_) {
        await f.dispose();
        if (mounted) setState(() => _error = 'This video format can\'t be played here. Open the post to play it in Telegram\'s viewer.');
        return;
      }
      c = f;
    }
    if (!mounted) return c.dispose();
    final done = c;
    final p = ref.read(moviesProvider).progress[v.key];
    if (p != null && !p.finished && p.position > 5) await done.seekTo(Duration(seconds: p.position));
    done.addListener(_onTick);
    await done.play();
    setState(() => _c = done);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _save());
    _autoHide();
  }

  Future<void> _pauseDownload() async {
    final f = _v?.file;
    if (f == null) return;
    await ref.read(fileLoaderProvider).pause(f);
    if (mounted) setState(() => _paused = true);
  }

  void _resumeDownload() {
    // _start sees _paused and resumes; then it's no longer paused.
    _start();
    setState(() => _paused = false);
  }

  Future<void> _cancelDownload() async {
    final f = _v?.file;
    if (f != null) await ref.read(fileLoaderProvider).cancel(f, delete: true);
    if (mounted) Navigator.pop(context);
  }

  bool _ended = false;
  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final value = c.value;
    if (value.isInitialized && value.duration > Duration.zero && value.position >= value.duration - const Duration(milliseconds: 400) && !value.isPlaying && !_ended) {
      _ended = true;
      _save();
      if (ref.read(moviesProvider).autoplay) {
        final next = _upNext().firstOrNull;
        if (next != null) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: next.key, video: next)));
        }
      }
    }
    setState(() {});
  }

  void _save() {
    final c = _c, v = _v;
    if (c == null || v == null || !c.value.isInitialized) return;
    ref.read(moviesProvider.notifier).saveProgress(v, c.value.position.inSeconds, c.value.duration.inSeconds);
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _chrome = false);
    });
  }

  Future<void> _setFull(bool v) async {
    setState(() => _full = v);
    if (v) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final landscape = (_c?.value.aspectRatio ?? 1.7) > 1;
      await SystemChrome.setPreferredOrientations(landscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  List<Video> _upNext() {
    final v = _v;
    if (v == null) return const [];
    final feed = ref.read(videoFeedProvider);
    final m = ref.read(moviesProvider);
    final list = [for (final x in feed.bySource['${v.account}:${v.chatId}'] ?? const <Video>[]) if (x.key != v.key && !m.hidden.contains(x.key)) x];
    // Older ones after this one first (episodes in order), then newer.
    final after = list.where((x) => x.messageId > v.messageId).toList()..sort((a, b) => a.messageId.compareTo(b.messageId));
    final before = list.where((x) => x.messageId < v.messageId).toList();
    return [...after, ...before];
  }

  Future<void> _saveToDevice() async {
    final v = _v;
    if (v?.file == null || _saving) return;
    setState(() => _saving = true);
    try {
      final path = await ref.read(fileLoaderProvider).download(v!.file!, priority: 32);
      if (path != null) await Gal.putVideo(path, album: 'Triangle');
      if (mounted) showSnack(context, path == null ? 'Couldn\'t download it' : 'Saved to your gallery', icon: Icons.download_done_rounded);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t save: $e', icon: Icons.error_outline_rounded);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _save();
    _hide?.cancel();
    _tick?.cancel();
    _c?.removeListener(_onTick);
    _c?.dispose();
    if (_full) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  Widget _player() {
    final v = _v;
    final c = _c;
    final loader = ref.read(fileLoaderProvider);
    Widget body;
    if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))));
    } else if (c == null || !c.value.isInitialized) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (v != null) TgPicture(file: v.thumb, mini: v.mini, fit: BoxFit.cover, cacheWidth: 900, placeholder: const SizedBox()),
          Container(color: Colors.black54),
          Center(
            child: v?.file == null
                ? const CircularProgressIndicator(color: Colors.white)
                : ValueListenableBuilder<double>(
                    valueListenable: loader.progress(v!.file!),
                    builder: (_, p, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(dimension: 56, child: CircularProgressIndicator(value: p > 0 ? p : null, color: Colors.white, strokeWidth: 3)),
                        const SizedBox(height: Space.m),
                        Text(
                          _paused
                              ? 'Paused at ${(p * 100).round()}%'
                              : (p > 0 ? 'Downloading ${(p * 100).round()}%${v.size > 0 ? ' of ${sizeText(v.size)}' : ''}' : 'Starting…'),
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: Space.s),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.filledTonal(
                              tooltip: _paused ? 'Resume' : 'Pause',
                              icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                              onPressed: _paused ? _resumeDownload : _pauseDownload,
                            ),
                            const SizedBox(width: Space.m),
                            IconButton.filledTonal(tooltip: 'Cancel and delete', icon: const Icon(Icons.close_rounded), onPressed: _cancelDownload),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    } else {
      final value = c.value;
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _chrome = !_chrome);
          if (_chrome) _autoHide();
        },
        onDoubleTapDown: (d) {
          final w = context.size?.width ?? 400;
          final by = d.localPosition.dx < w / 2 ? -10 : 10;
          c.seekTo(value.position + Duration(seconds: by));
        },
        onDoubleTap: () {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(c))),
            if (value.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white70)),
            if (_streaming && _chrome)
              Positioned(
                left: Space.m,
                top: Space.m,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                  child: const Text('STREAMING', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _chrome ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: Container(
                  color: Colors.black38,
                  child: Stack(
                    children: [
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(iconSize: 36, icon: const Icon(Icons.replay_10_rounded, color: Colors.white), onPressed: () => c.seekTo(value.position - const Duration(seconds: 10))),
                            const SizedBox(width: Space.xl),
                            IconButton(
                              iconSize: 56,
                              icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                              onPressed: () {
                                value.isPlaying ? c.pause() : c.play();
                                _ended = false;
                                _autoHide();
                              },
                            ),
                            const SizedBox(width: Space.xl),
                            IconButton(iconSize: 36, icon: const Icon(Icons.forward_10_rounded, color: Colors.white), onPressed: () => c.seekTo(value.position + const Duration(seconds: 10))),
                          ],
                        ),
                      ),
                      Positioned(
                        left: Space.s,
                        right: Space.s,
                        bottom: 0,
                        child: Row(
                          children: [
                            Text(_clock(value.position.inSeconds).isEmpty ? '0:00' : _clock(value.position.inSeconds), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(activeTrackColor: moviesColor, thumbColor: moviesColor, inactiveTrackColor: Colors.white30, trackHeight: 3),
                                child: Slider(
                                  value: value.position.inMilliseconds.toDouble().clamp(0, value.duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                                  max: value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                  onChanged: (x) => c.seekTo(Duration(milliseconds: x.round())),
                                ),
                              ),
                            ),
                            Text(_clock(value.duration.inSeconds), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            PopupMenuButton<double>(
                              tooltip: 'Speed',
                              icon: const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
                              onSelected: c.setPlaybackSpeed,
                              itemBuilder: (_) => [for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) CheckedPopupMenuItem(value: s, checked: value.playbackSpeed == s, child: Text('$s×'))],
                            ),
                            IconButton(
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
          ],
        ),
      );
    }
    return Container(color: Colors.black, child: body);
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (_full) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _setFull(false);
        },
        child: Scaffold(backgroundColor: Colors.black, body: _player()),
      );
    }
    final m = ref.watch(moviesProvider);
    ref.watch(videoFeedProvider);
    final next = _upNext();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: _player()),
                Positioned(left: 4, top: 4, child: IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white), onPressed: () => Navigator.pop(context))),
              ],
            ),
            if (v != null)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
                  children: [
                    Text(v.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      [if (v.views > 0) _views(v.views), agoText(v.date), if (v.quality.isNotEmpty) v.quality, if (v.size > 0) sizeText(v.size)].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Space.m),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _Action(
                            icon: m.liked.contains(v.key) ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                            label: 'Like',
                            onTap: () => ref.read(moviesProvider.notifier).toggleLike(v.key),
                          ),
                          _Action(
                            icon: m.inList(v.key) ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                            label: 'My list',
                            onTap: () => ref.read(moviesProvider.notifier).toggleList(SavedVideo.of(v)),
                          ),
                          _Action(icon: Icons.forward_rounded, label: 'Share', onTap: () => _share(context, ref, v)),
                          _Action(icon: _saving ? Icons.hourglass_top_rounded : Icons.download_rounded, label: 'Save', onTap: _saveToDevice),
                          _Action(
                            icon: Icons.forum_outlined,
                            label: 'Post',
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatViewScreen(chatId: v.chatId, openAt: v.messageId))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.m),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: TgAvatar(chatId: v.chatId, title: v.channel, size: 40),
                      title: Text(v.channel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        final s = m.sources.where((s) => s.chatId == v.chatId).firstOrNull;
                        if (s != null) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: s)));
                      },
                    ),
                    if (v.description.isNotEmpty && v.description != v.title)
                      GestureDetector(
                        onTap: () => setState(() => _more = !_more),
                        child: Container(
                          padding: const EdgeInsets.all(Space.m),
                          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                          child: Text(v.description, maxLines: _more ? null : 3, overflow: _more ? null : TextOverflow.ellipsis, style: context.text.bodyMedium),
                        ),
                      ),
                    if (next.isNotEmpty) ...[
                      const SizedBox(height: Space.l),
                      Row(
                        children: [
                          Expanded(child: Text('Up next', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                          Text('Autoplay', style: context.text.bodySmall),
                          Switch(value: m.autoplay, onChanged: ref.read(moviesProvider.notifier).setAutoplay),
                        ],
                      ),
                      for (final x in next.take(12))
                        InkWell(
                          onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: x.key, video: x))),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 150, child: VideoThumb(video: x)),
                                const SizedBox(width: Space.m),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                      Text([if (x.views > 0) _views(x.views), agoText(x.date)].join(' · '), style: context.text.bodySmall),
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
              ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.s),
    child: ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap, shape: const StadiumBorder()),
  );
}
