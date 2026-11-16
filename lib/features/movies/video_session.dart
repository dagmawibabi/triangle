import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../media/audio_center.dart';
import '../telegram/data/file_loader.dart';
import '../sections/activity_stats.dart';
import 'movies.dart';
import 'pip.dart';
import 'tg_stream.dart';

// What's playing in Video, kept app-wide: the watch page shows it big, and
// when that page closes it keeps playing in the mini player, the way a
// video site does, until it's closed there.

@immutable
class VideoSessionState {
  const VideoSessionState({this.video, this.controller, this.streaming = false, this.paused = false, this.error, this.expanded = false});
  final Video? video;
  final VideoPlayerController? controller;

  /// Playing from Telegram as it's fetched, not from a finished download.
  final bool streaming;

  /// The download was paused by the person.
  final bool paused;
  final String? error;

  /// The watch page is open (the mini player hides).
  final bool expanded;

  bool get active => video != null;
  bool get ready => controller?.value.isInitialized ?? false;

  /// Something worth showing in the mini player.
  bool get showMini => active && !expanded && error == null;

  VideoSessionState copyWith({Video? video, VideoPlayerController? controller, bool? streaming, bool? paused, String? error, bool clearError = false, bool? expanded}) => VideoSessionState(
    video: video ?? this.video,
    controller: controller ?? this.controller,
    streaming: streaming ?? this.streaming,
    paused: paused ?? this.paused,
    error: clearError ? null : (error ?? this.error),
    expanded: expanded ?? this.expanded,
  );
}

class VideoSession extends Notifier<VideoSessionState> {
  Timer? _tick;
  bool _ended = false;

  /// Bumped on every open; work for an older video stops when it sees
  /// a newer one.
  int _gen = 0;

  @override
  VideoSessionState build() {
    ref.onDispose(() {
      _tick?.cancel();
      state.controller?.dispose();
    });
    return const VideoSessionState();
  }

  /// Plays [v], unless it's already the one playing.
  Future<void> open(Video v) async {
    if (state.video?.key == v.key && state.error == null) return;
    await _teardown();
    final gen = ++_gen;
    state = VideoSessionState(video: v, expanded: state.expanded);
    await _start(gen);
  }

  /// Plays the video with [key], read from its post if it isn't loaded.
  Future<void> openKey(String key) async {
    if (state.video?.key == key && state.error == null) return;
    final gen = ++_gen;
    try {
      final v = await ref.read(videoFeedProvider.notifier).fetch(key);
      if (gen != _gen) return;
      if (v == null) {
        await _teardown();
        state = VideoSessionState(expanded: state.expanded, error: 'This video is gone.');
        return;
      }
      await open(v);
    } catch (e) {
      if (gen == _gen) state = VideoSessionState(expanded: state.expanded, error: '$e');
    }
  }

  Future<void> _start(int gen, {bool resume = false}) async {
    final v = state.video;
    if (v == null) return;
    final file = v.file;
    if (file == null) {
      state = state.copyWith(error: 'This video can\'t be played.');
      return;
    }
    // The music player pauses while a video plays.
    final audio = ref.read(audioCenterProvider);
    if (audio.playing) unawaited(audio.toggle());
    final loader = ref.read(fileLoaderFamily(v.account));
    VideoPlayerController? c;
    var streaming = false;
    // Streams whenever the file isn't on the phone yet: only the parts the
    // player asks for are fetched, so leaving early doesn't pull the rest.
    // A whole download is the fallback for files the player can't stream.
    final cached = loader.cachedPath(file);
    if (cached != null) {
      final f = VideoPlayerController.file(File(cached));
      try {
        await f.initialize();
        c = f;
      } catch (_) {
        await f.dispose();
      }
    }
    if (c == null && !resume && cached == null) {
      try {
        final name = v.fileName.toLowerCase();
        final mime = name.endsWith('.mkv') ? 'video/x-matroska' : (name.endsWith('.webm') ? 'video/webm' : 'video/mp4');
        final url = await ref.read(tgStreamFamily(v.account)).url(file, mime: mime);
        final s = VideoPlayerController.networkUrl(url);
        try {
          await s.initialize();
        } catch (_) {
          await s.dispose();
          rethrow;
        }
        c = s;
        streaming = true;
      } catch (e) {
        debugPrint('[Video] streaming failed, downloading: $e');
      }
    }
    if (gen != _gen) {
      await c?.dispose();
      return;
    }
    if (c == null) {
      _downloading = file;
      final path = await (resume ? loader.resume(file) : loader.download(file, priority: 32));
      if (_downloading?.id == file.id) _downloading = null;
      if (gen != _gen) return;
      if (path == null && loader.isPaused(file)) {
        state = state.copyWith(paused: true);
        return;
      }
      if (path == null) {
        state = state.copyWith(error: 'Couldn\'t download the video.');
        return;
      }
      final f = VideoPlayerController.file(File(path));
      try {
        await f.initialize();
      } catch (_) {
        await f.dispose();
        if (gen == _gen) state = state.copyWith(error: 'This video format can\'t be played here. Open the post to play it in Telegram\'s viewer.');
        return;
      }
      c = f;
    }
    if (gen != _gen) {
      await c.dispose();
      return;
    }
    final p = ref.read(moviesProvider).progress[v.key];
    if (p != null && !p.finished && p.position > 5) await c.seekTo(Duration(seconds: p.position));
    _ended = false;
    c.addListener(_onTick);
    await c.play();
    state = state.copyWith(controller: c, streaming: streaming, paused: false);
    _tick?.cancel();
    recordWatch(ref, v, started: true);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      save();
      if (state.controller?.value.isPlaying ?? false) recordWatch(ref, v, seconds: 5);
    });
  }

  bool? _wasPlaying;

  void _onTick() {
    final c = state.controller;
    if (c == null) return;
    final value = c.value;
    // While it plays, leaving the app floats it in picture-in-picture.
    if (value.isPlaying != _wasPlaying) {
      _wasPlaying = value.isPlaying;
      unawaited(Pip.setAuto(value.isPlaying, value.size == Size.zero ? const Size(16, 9) : value.size));
    }
    if (value.isInitialized && value.duration > Duration.zero && value.position >= value.duration - const Duration(milliseconds: 400) && !value.isPlaying && !_ended) {
      _ended = true;
      save();
      if (ref.read(moviesProvider).autoplay) {
        final next = upNext().firstOrNull;
        if (next != null) unawaited(open(next));
      }
    }
  }

  /// Remembers how far in the current video is.
  void save() {
    final c = state.controller, v = state.video;
    if (c == null || v == null || !c.value.isInitialized) return;
    ref.read(moviesProvider.notifier).saveProgress(v, c.value.position.inSeconds, c.value.duration.inSeconds);
  }

  void toggle() {
    final c = state.controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      save();
    } else {
      _ended = false;
      c.play();
    }
  }

  void restartIfEnded() => _ended = false;

  Future<void> pauseDownload() async {
    final v = state.video, f = v?.file;
    if (v == null || f == null) return;
    await ref.read(fileLoaderFamily(v.account)).pause(f);
    state = state.copyWith(paused: true);
  }

  Future<void> resumeDownload() async {
    state = state.copyWith(paused: false);
    await _start(_gen, resume: true);
  }

  /// Stops the download, deletes what came, and closes the video.
  Future<void> cancelDownload() async {
    final v = state.video, f = v?.file;
    if (v != null && f != null) await ref.read(fileLoaderFamily(v.account)).cancel(f, delete: true);
    await stop();
  }

  /// Plays the whole file from the phone instead of streaming it.
  Future<void> retry() async {
    final v = state.video;
    if (v == null) return;
    await _teardown();
    final gen = ++_gen;
    state = VideoSessionState(video: v, expanded: state.expanded);
    await _start(gen);
  }

  /// The watch page closed: keep playing in the mini player, or close
  /// the video when there's nothing to play.
  void leftWatchPage() {
    save();
    _pages = (_pages - 1).clamp(0, 99);
    setExpanded(_pages > 0);
    if (state.error != null || state.video == null) unawaited(stop());
  }

  /// Watch pages open (one can sit under a channel page opened from it).
  int _pages = 0;

  void enterWatchPage() {
    _pages++;
    setExpanded(true);
  }

  void setExpanded(bool v) {
    if (state.expanded != v) state = state.copyWith(expanded: v);
  }

  /// Closes the video (the mini player goes away).
  Future<void> stop() async {
    _gen++;
    await _teardown();
    state = VideoSessionState(expanded: state.expanded);
  }

  /// A whole-file download this session started (the fallback when a
  /// video can't stream); stopped when the video closes.
  td.File? _downloading;

  Future<void> _teardown() async {
    save();
    final d = _downloading, v = state.video;
    _downloading = null;
    if (d != null && v != null) {
      final loader = ref.read(fileLoaderFamily(v.account));
      if (loader.cachedPath(d) == null && !loader.isPaused(d)) unawaited(loader.cancel(d));
    }
    _wasPlaying = null;
    unawaited(Pip.setAuto(false));
    _tick?.cancel();
    _tick = null;
    final c = state.controller;
    if (c != null) {
      c.removeListener(_onTick);
      state = VideoSessionState(video: state.video, expanded: state.expanded);
      await c.dispose();
    }
  }

  /// What plays after the current video: the next episodes from the same
  /// channel in order, then older ones.
  List<Video> upNext() {
    final v = state.video;
    if (v == null) return const [];
    final feed = ref.read(videoFeedProvider);
    final m = ref.read(moviesProvider);
    final list = [for (final x in feed.bySource['${v.account}:${v.chatId}'] ?? const <Video>[]) if (x.key != v.key && !m.hidden.contains(x.key)) x];
    final after = list.where((x) => x.messageId > v.messageId).toList()..sort((a, b) => a.messageId.compareTo(b.messageId));
    final before = list.where((x) => x.messageId < v.messageId).toList();
    return [...after, ...before];
  }
}

final videoSessionProvider = NotifierProvider<VideoSession, VideoSessionState>(VideoSession.new);

/// Counts time watching [v] for Video stats.
void recordWatch(Ref ref, Video v, {int seconds = 0, bool started = false}) => ref
    .read(activityStatsProvider('video').notifier)
    .add(v.key, title: v.title, group: v.channel, groupId: v.chatId, mini: v.mini?.data, seconds: seconds, started: started);
