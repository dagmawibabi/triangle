import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../media/audio_center.dart';
import '../sections/activity_stats.dart';
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/presentation/formatted_text.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'movies.dart';
import '../../infrastructure/telegram/accounts.dart';
import 'movies_screen.dart' show ChannelVideosScreen, videoMenu, shareVideo;
import 'tg_stream.dart';
import 'video_comments.dart';
import 'video_session.dart';

/// Opens [videos] as Shorts at [index].
void openShorts(BuildContext context, List<Video> videos, int index) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShortsScreen(videos: videos, initial: index)));

/// Vertical videos one screen each: swipe up and down between them, tap to
/// pause, double-tap to like, with the actions down the side.
class ShortsScreen extends ConsumerStatefulWidget {
  const ShortsScreen({super.key, required this.videos, this.initial = 0});
  final List<Video> videos;
  final int initial;

  @override
  ConsumerState<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends ConsumerState<ShortsScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;
  late List<Video> _videos = [...widget.videos];
  final _players = <int, VideoPlayerController>{};
  final _failed = <int, String>{};
  final _loading = <int>{};

  /// Whole-file downloads started for shorts that couldn't stream, so they
  /// stop when the short is left.
  final _downloads = <int, td.File>{};
  Timer? _tick;
  late final ActivityStats _stats = ref.read(activityStatsProvider('video').notifier);
  late final MoviesStore _movies = ref.read(moviesProvider.notifier);

  /// Clean view: everything over the video hidden, for every short, until
  /// a long press in the middle (or More) brings it back.
  bool _clean = false;
  bool _cleanHint = false;
  Timer? _cleanHintOff;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // One thing plays at a time.
      final s = ref.read(videoSessionProvider).controller;
      if (s?.value.isPlaying ?? false) s!.pause();
      final audio = ref.read(audioCenterProvider);
      if (audio.playing) unawaited(audio.toggle());
      _around(_at);
    });
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      final c = _players[_at];
      if (c != null && c.value.isPlaying && _at < _videos.length) {
        final v = _videos[_at];
        _stats.add(v.key, title: v.title, group: v.channel, groupId: v.chatId, mini: v.mini?.data, seconds: 5);
      }
    });
  }

  /// Stops every player now (going back must not leave one playing).
  void _stopAll() {
    for (final c in _players.values) {
      c.pause();
    }
  }

  void _stopDownload(int i) {
    final f = _downloads.remove(i);
    if (f == null || i >= _videos.length) return;
    final loader = ref.read(fileLoaderFamily(_videos[i].account));
    if (loader.cachedPath(f) == null) unawaited(loader.cancel(f));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cleanHintOff?.cancel();
    // Saving changes a provider, which can't happen while the tree is torn
    // down: read where it was now, save just after.
    final c = _players[_at];
    final v = _at < _videos.length ? _videos[_at] : null;
    final at = c != null && c.value.isInitialized ? (c.value.position.inSeconds, c.value.duration.inSeconds) : null;
    final players = [..._players.values];
    _players.clear();
    for (final p in players) {
      p.pause();
      p.dispose();
    }
    for (final i in [..._downloads.keys]) {
      _stopDownload(i);
    }
    _pages.dispose();
    final movies = _movies;
    if (at != null && v != null) Future.microtask(() => movies.saveProgress(v, at.$1, at.$2));
    super.dispose();
  }

  void _saveAt(int i) {
    final c = _players[i];
    if (c == null || !c.value.isInitialized || i >= _videos.length) return;
    _movies.saveProgress(_videos[i], c.value.position.inSeconds, c.value.duration.inSeconds);
  }

  /// Loads the one showing and its neighbours; lets go of the rest.
  void _around(int i) {
    for (final k in _players.keys.toList()) {
      if ((k - i).abs() > 1) _players.remove(k)?.dispose();
    }
    for (final k in _downloads.keys.toList()) {
      if ((k - i).abs() > 1) _stopDownload(k);
    }
    for (final k in [i, i + 1, i - 1]) {
      if (k >= 0 && k < _videos.length) _load(k);
    }
  }

  /// Bumped when the feed is reshuffled; loads for the old order stop.
  int _gen = 0;

  Future<void> _load(int i) async {
    if (_players.containsKey(i) || _loading.contains(i) || _failed.containsKey(i)) return;
    final gen = _gen;
    final v = _videos[i];
    final file = v.file;
    if (file == null) return setState(() => _failed[i] = 'Can’t be played');
    _loading.add(i);
    final loader = ref.read(fileLoaderFamily(v.account));
    VideoPlayerController? c;
    var gone = false;
    try {
      final have = loader.cachedPath(file);
      if (have != null) {
        c = VideoPlayerController.file(File(have));
        await c.initialize();
      } else {
        // Streams: only what's watched is fetched.
        try {
          final name = v.fileName.toLowerCase();
          final mime = name.endsWith('.mkv') ? 'video/x-matroska' : (name.endsWith('.webm') ? 'video/webm' : 'video/mp4');
          c = VideoPlayerController.networkUrl(await ref.read(tgStreamFamily(v.account)).url(file, mime: mime));
          await c.initialize();
        } catch (_) {
          await c?.dispose();
          c = null;
          if (!mounted || gen != _gen || (i - _at).abs() > 1) {
            gone = true;
            rethrow;
          }
          // The fallback: the whole file, stopped if the short is left.
          _downloads[i] = file;
          final p = await loader.download(file, priority: i == _at ? 32 : 8);
          _downloads.remove(i);
          if (p == null) throw 'Couldn’t download it';
          c = VideoPlayerController.file(File(p));
          await c.initialize();
        }
      }
      await c.setLooping(true);
      _stats.add(v.key, title: v.title, group: v.channel, groupId: v.chatId, mini: v.mini?.data, started: true);
    } catch (e) {
      await c?.dispose();
      c = null;
      if (mounted && gen == _gen && !gone) setState(() => _failed[i] = 'This video can’t be played here');
    }
    _loading.remove(i);
    if (c == null) return;
    // Scrolled far away meanwhile, reshuffled, or the page closed.
    if (!mounted || gen != _gen || (i - _at).abs() > 1) {
      await c.dispose();
      return;
    }
    _players[i] = c;
    await c.setPlaybackSpeed(_locked2x ? 2 : 1);
    if (i == _at) await c.play();
    setState(() {});
  }

  void _changed(int i) {
    _saveAt(_at);
    _players[_at]?.pause();
    setState(() => _at = i);
    final c = _players[i];
    if (c != null) {
      c.seekTo(Duration.zero);
      c.setPlaybackSpeed(_locked2x ? 2 : 1);
      c.play();
    }
    _around(i);
  }

  /// How far the first short has been pulled down past the top.
  double _pull = 0;
  bool _refreshing = false;
  static const _pullToRefresh = 90.0;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0 || _refreshing) return false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null && _at == 0) {
      final was = _pull;
      setState(() => _pull = (_pull - n.overscroll).clamp(0, 200));
      if (was < _pullToRefresh && _pull >= _pullToRefresh) HapticFeedback.selectionClick();
    } else if (n is ScrollUpdateNotification && _pull > 0 && (n.scrollDelta ?? 0) > 0) {
      setState(() => _pull = (_pull - n.scrollDelta!).clamp(0, 200));
    } else if (n is ScrollEndNotification && _pull > 0) {
      final go = _pull >= _pullToRefresh;
      setState(() => _pull = 0);
      if (go) _pullRefresh();
    }
    return false;
  }

  Future<void> _pullRefresh() async {
    setState(() => _refreshing = true);
    try {
      await _refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// The shorts loaded now from the channels the feed opened with.
  List<Video> _fromChannels(Set<String> chats) =>
      allVideos(ref.read(moviesProvider), ref.read(videoFeedProvider)).where((v) => v.vertical && chats.contains('${v.account}:${v.chatId}')).toList();

  /// Pulled down on the first short: shuffles the feed at once (from the
  /// same channels it opened with), with a different first short each
  /// time, and fetches what's new in the background.
  Future<void> _refresh() async {
    final m = ref.read(moviesProvider);
    final account = ref.read(activeAccountIdProvider);
    final chats = {for (final v in widget.videos) '${v.account}:${v.chatId}'};
    final feed = ref.read(videoFeedProvider.notifier);
    unawaited(feed.loadAll(m.sources.where((s) => s.account == account && chats.contains(s.key)), refresh: true).then((_) {
      if (mounted) _mixInNew(chats);
    }));
    final fresh = _fromChannels(chats);
    final next = (fresh.isEmpty ? [..._videos] : fresh)..shuffle();
    // Never the same short on top twice in a row.
    if (next.length > 1 && next.first.key == _videos.firstOrNull?.key) next.add(next.removeAt(0));
    _saveAt(_at);
    _gen++;
    for (final c in _players.values) {
      c.pause();
      c.dispose();
    }
    _players.clear();
    for (final i in [..._downloads.keys]) {
      _stopDownload(i);
    }
    _failed.clear();
    _loading.clear();
    setState(() {
      _videos = next;
      _at = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    _around(0);
    HapticFeedback.mediumImpact();
  }

  /// Background fetch done: new shorts are shuffled into the part of the
  /// feed not reached yet, leaving the current one and its neighbours be.
  void _mixInNew(Set<String> chats) {
    final have = {for (final v in _videos) v.key};
    final added = [for (final v in _fromChannels(chats)) if (!have.contains(v.key)) v];
    if (added.isEmpty) return;
    final cut = (_at + 2).clamp(0, _videos.length);
    final rest = [..._videos.sublist(cut), ...added]..shuffle();
    _failed.removeWhere((k, _) => k >= cut);
    setState(() => _videos = [..._videos.sublist(0, cut), ...rest]);
  }

  /// 2x kept for every short in the feed, until tapped off.
  bool _locked2x = false;

  void _setLock(bool on) {
    setState(() => _locked2x = on);
    for (final c in _players.values) {
      c.setPlaybackSpeed(on ? 2 : 1);
    }
  }

  void _setClean(bool on) {
    HapticFeedback.mediumImpact();
    setState(() {
      _clean = on;
      _cleanHint = true;
    });
    _cleanHintOff?.cancel();
    _cleanHintOff = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _cleanHint = false);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (popped, _) {
      if (popped) _stopAll();
    },
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.black, systemNavigationBarColor: Colors.black),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // The videos stay below the status bar. Pulling down on the
            // first short refreshes and reshuffles the feed.
            SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                itemCount: _videos.length,
                onPageChanged: _changed,
                itemBuilder: (_, i) => _ShortPage(
                  key: ValueKey('$_gen:${_videos[i].key}'),
                  video: _videos[i],
                  controller: _players[i],
                  error: _failed[i],
                  active: i == _at,
                  locked: _locked2x,
                  onLock: _setLock,
                  clean: _clean,
                  onClean: _setClean,
                ),
              ),
              ),
            ),
            if (_pull > 0 || _refreshing)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12 + (_refreshing ? 40 : (_pull.clamp(0, 140) * 0.45)),
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _refreshing ? 1 : (_pull / 50).clamp(0, 1),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(9),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10)]),
                          child: _refreshing
                              ? const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black)
                              : Transform.rotate(
                                  angle: _pull / _pullToRefresh * 3.14,
                                  child: Icon(_pull >= _pullToRefresh ? Icons.shuffle_rounded : Icons.refresh_rounded, color: Colors.black, size: 22),
                                ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _refreshing ? 'Shuffling…' : (_pull >= _pullToRefresh ? 'Release to shuffle' : 'Pull to shuffle'),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_clean)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 8)]),
                        onPressed: () {
                          _stopAll();
                          Navigator.pop(context);
                        },
                      ),
                      const Text('Shorts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, shadows: [Shadow(blurRadius: 8)])),
                      const Spacer(),
                      Text('${_at + 1} / ${_videos.length}', style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 8)])),
                      const SizedBox(width: Space.m),
                    ],
                  ),
                ),
              ),
            if (_cleanHint)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: _clean ? Colors.white : Colors.black54, borderRadius: BorderRadius.circular(99)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_clean ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: _clean ? Colors.black : Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _clean ? 'Full screen for all shorts · long-press the middle to undo' : 'Controls back',
                            style: TextStyle(color: _clean ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ],
                      ),
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

class _ShortPage extends ConsumerStatefulWidget {
  const _ShortPage({super.key, required this.video, required this.controller, required this.error, required this.active, required this.locked, required this.onLock, required this.clean, required this.onClean});

  /// Full screen (nothing over the video), and how to change it.
  final bool clean;
  final ValueChanged<bool> onClean;

  /// The feed's 2x lock, and how to change it.
  final bool locked;
  final ValueChanged<bool> onLock;
  final Video video;
  final VideoPlayerController? controller;
  final String? error;
  final bool active;

  @override
  ConsumerState<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends ConsumerState<_ShortPage> with TickerProviderStateMixin {
  bool _more = false;
  Offset? _tapAt;

  /// A heart where the double-tap was, floating up as it fades.
  final _bursts = <(Offset, AnimationController)>[];

  /// Held on a side: playing at 2×. Dragged down while held, the feed
  /// keeps 2× for every short ([_ShortPage.locked]).
  bool _fast = false;
  bool get _locked => widget.locked;
  double _holdY = 0;
  bool _downloading = false;

  void _speed(bool fast) {
    final c = widget.controller;
    if (c == null) return;
    c.setPlaybackSpeed(fast ? 2 : 1);
    if (fast && !c.value.isPlaying) c.play();
  }

  /// The lock changed during this hold (so the same hold doesn't flip it
  /// back).
  bool _flipped = false;

  void _holdStart(LongPressStartDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final x = d.localPosition.dx;
    if (x > w * 0.32 && x < w * 0.68) {
      // The middle: full screen on or off, for every short.
      widget.onClean(!widget.clean);
      return;
    }
    HapticFeedback.mediumImpact();
    _holdY = d.localPosition.dy;
    _flipped = false;
    _speed(true);
    setState(() => _fast = true);
  }

  /// Dragging down while holding locks 2x; the same gesture while locked
  /// unlocks it. Nothing else does.
  void _holdMove(LongPressMoveUpdateDetails d) {
    if (!_fast || _flipped) return;
    if (d.localPosition.dy - _holdY > 70) {
      HapticFeedback.heavyImpact();
      _flipped = true;
      widget.onLock(!_locked);
    }
  }

  void _holdEnd(LongPressEndDetails _) {
    if (!_fast) return;
    // Locked: it stays at 2x. Otherwise back to normal.
    if (!_locked) _speed(false);
    setState(() => _fast = false);
  }

  Future<void> _download() async {
    final v = widget.video;
    final f = v.file;
    if (f == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final path = await ref.read(fileLoaderFamily(v.account)).download(f, priority: 32);
      if (path != null) await Gal.putVideo(path, album: 'Triangle');
      if (mounted) showSnack(context, path == null ? 'Couldn’t download it' : 'Saved to your phone’s gallery', icon: Icons.download_done_rounded);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t save: $e', icon: Icons.error_outline_rounded);
    }
    if (mounted) setState(() => _downloading = false);
  }

  /// The play or pause sign, shown a moment after a tap.
  IconData? _flash;
  Timer? _flashOff;
  Future<CommentThread?>? _comments;

  @override
  void didUpdateWidget(_ShortPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && _fast) {
      _fast = false;
      if (!_locked) widget.controller?.setPlaybackSpeed(1);
    }
    if (widget.active && _comments == null) _comments = loadComments(ref, widget.video.account, widget.video.chatId, widget.video.messageId);
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _comments = loadComments(ref, widget.video.account, widget.video.chatId, widget.video.messageId);
  }

  @override
  void dispose() {
    _flashOff?.cancel();
    for (final (_, a) in _bursts) {
      a.dispose();
    }
    super.dispose();
  }

  void _togglePlay() {
    final c = widget.controller;
    if (c == null) return;
    final playing = c.value.isPlaying;
    playing ? c.pause() : c.play();
    setState(() => _flash = playing ? Icons.pause_rounded : Icons.play_arrow_rounded);
    _flashOff?.cancel();
    _flashOff = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _doubleTap() {
    HapticFeedback.lightImpact();
    final v = widget.video;
    if (!ref.read(moviesProvider).liked.contains(v.key)) ref.read(moviesProvider.notifier).toggleLike(v.key);
    final a = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    final at = _tapAt ?? Offset(MediaQuery.sizeOf(context).width / 2, MediaQuery.sizeOf(context).height / 2);
    setState(() => _bursts.add((at, a)));
    a.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _bursts.removeWhere((b) => b.$2 == a));
      a.dispose();
    });
  }

  void _openChannel() {
    final v = widget.video;
    final s = ref.read(moviesProvider).sources.where((x) => x.chatId == v.chatId && x.account == v.account).firstOrNull ??
        SourceRef(account: v.account, chatId: v.chatId, title: v.channel);
    widget.controller?.pause();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelVideosScreen(source: s))).then((_) {
      if (mounted && widget.active) widget.controller?.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final c = widget.controller;
    final m = ref.watch(moviesProvider);
    final liked = m.liked.contains(v.key);
    final saved = m.inList(v.key);
    // Likes are red in every look.
    const likeColor = Color(0xFFFF3040);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      onLongPressStart: _holdStart,
      onLongPressMoveUpdate: _holdMove,
      onLongPressEnd: _holdEnd,
      // Swiping left opens the channel, like tapping its picture.
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) _openChannel();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            FittedBox(
              fit: v.vertical ? BoxFit.cover : BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                TgPicture(file: v.thumb, mini: v.mini, account: v.account, fit: BoxFit.cover, cacheWidth: 720, placeholder: const SizedBox()),
                Center(
                  child: widget.error != null
                      ? Text(widget.error!, style: const TextStyle(color: Colors.white70))
                      : const SizedBox.square(dimension: 34, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                ),
              ],
            ),
          // Shade so the words read.
          if (!widget.clean)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                  stops: [0, 0.18, 0.55, 1],
                ),
              ),
            ),
          ),
          if (c != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, value, _) => value.isBuffering && value.isPlaying ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)) : const SizedBox.shrink(),
            ),
          if (_fast || (_locked && widget.active))
            Positioned(
              top: MediaQuery.paddingOf(context).top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: _locked ? Colors.white : Colors.black54, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_locked ? Icons.lock_rounded : Icons.fast_forward_rounded, size: 16, color: _locked ? Colors.black : Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          _locked ? (_fast ? '2× locked · drag down to unlock' : '2× locked for all shorts') : '2× · drag down to lock',
                          style: TextStyle(color: _locked ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_flash != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(Space.l),
                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: Icon(_flash, color: Colors.white, size: 46),
              ),
            ),
          for (final (at, a) in _bursts)
            AnimatedBuilder(
              animation: a,
              builder: (_, _) {
                final t = Curves.easeOut.transform(a.value);
                return Positioned(
                  left: at.dx - 48,
                  top: at.dy - 48 - t * 70,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - a.value).clamp(0, 1),
                      child: Transform.scale(
                        scale: 0.6 + (a.value < 0.25 ? a.value * 2.4 : 0.6 + (a.value - 0.25) * 0.3),
                        child: Transform.rotate(angle: (at.dx % 2 == 0 ? -0.2 : 0.2), child: Icon(Icons.favorite_rounded, size: 96, color: likeColor, shadows: const [Shadow(blurRadius: 18)])),
                      ),
                    ),
                  ),
                );
              },
            ),
          // The actions down the right side.
          if (!widget.clean)
          Positioned(
            right: Space.s,
            bottom: bottom + 84,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _openChannel,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: TgAvatar(chatId: v.chatId, title: v.channel, size: 36, accountId: v.account),
                  ),
                ),
                const SizedBox(height: Space.m),
                _SideAction(
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? likeColor : Colors.white,
                  label: liked ? 'Liked' : 'Like',
                  onTap: () => ref.read(moviesProvider.notifier).toggleLike(v.key),
                ),
                FutureBuilder<CommentThread?>(
                  future: _comments,
                  builder: (_, snap) => _SideAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: snap.data == null ? 'Comments' : '${snap.data!.count}',
                    onTap: () async {
                      c?.pause();
                      await showCommentsSheet(context, account: v.account, chatId: v.chatId, messageId: v.messageId);
                      if (mounted && widget.active) c?.play();
                    },
                  ),
                ),
                _SideAction(
                  icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  label: saved ? 'In list' : 'My list',
                  onTap: () => ref.read(moviesProvider.notifier).toggleList(SavedVideo.of(v)),
                ),
                _SideAction(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  busy: _downloading && v.file != null ? ref.read(fileLoaderFamily(v.account)).progress(v.file!) : null,
                  onTap: _download,
                ),
                _SideAction(icon: Icons.reply_rounded, flip: true, label: 'Share', onTap: () => shareVideo(context, ref, v)),
                _SideAction(
                  icon: Icons.more_horiz_rounded,
                  label: 'More',
                  onTap: () => videoMenu(context, ref, v, extras: [
                    (widget.clean ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, widget.clean ? 'Show controls again' : 'Full screen for all shorts', () => widget.onClean(!widget.clean)),
                  ]),
                ),
              ],
            ),
          ),
          // Who posted it and what it says.
          if (!widget.clean)
          Positioned(
            left: Space.l,
            right: 72,
            bottom: bottom + 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _openChannel,
                  child: Text('@${v.channel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5, shadows: [Shadow(blurRadius: 6)])),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => setState(() => _more = !_more),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: _more ? MediaQuery.sizeOf(context).height * 0.4 : 60),
                      child: SingleChildScrollView(
                        physics: _more ? null : const NeverScrollableScrollPhysics(),
                        child: Text.rich(
                          formattedSpan(v.caption ?? td.FormattedText(text: v.description.isEmpty ? v.title : v.description, entities: const []), link: Colors.white),
                          maxLines: _more ? null : 2,
                          overflow: _more ? null : TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35, shadows: [Shadow(blurRadius: 6)]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [if (v.views > 0) '${v.views} views', agoText(v.date)].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 6)]),
                ),
              ],
            ),
          ),
          // Progress, scrubbable.
          if (c != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom,
              child: SizedBox(
                height: 14,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  padding: const EdgeInsets.only(top: 11),
                  colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({required this.icon, required this.label, required this.onTap, this.color = Colors.white, this.flip = false, this.busy});
  final IconData icon;

  /// Shows progress instead of the icon while set.
  final ValueListenable<double>? busy;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool flip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.m),
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: Column(
        children: [
          if (busy != null)
            SizedBox.square(
              dimension: 26,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ValueListenableBuilder<double>(
                  valueListenable: busy!,
                  builder: (_, p, _) => CircularProgressIndicator(value: p > 0 ? p : null, strokeWidth: 2.4, color: Colors.white, backgroundColor: Colors.white24),
                ),
              ),
            )
          else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Transform(
              key: ValueKey('$icon$color'),
              alignment: Alignment.center,
              transform: flip ? (Matrix4.identity()..scaleByDouble(-1, 1, 1, 1)) : Matrix4.identity(),
              child: Icon(icon, color: color, size: 26, shadows: const [Shadow(blurRadius: 10)]),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)])),
        ],
      ),
    ),
  );
}
