import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../telegram/data/file_loader.dart';
import '../telegram/data/telegram_store.dart';
import '../voice/speaker.dart';
import 'music_stats.dart';
import '../assistant/notifications.dart' show appNotifierProvider;

/// One voice message or song.
class Track {
  const Track({
    required this.chatId,
    required this.messageId,
    this.file,
    this.localPath,
    this.identifier,
    required this.title,
    required this.subtitle,
    required this.seconds,
    required this.voice,
    this.cover,
    this.url,
    this.artUrl,
    this.live = false,
    this.resolve,
    this.queueTag,
    this.artPath,
    this.artFile,
    this.info = const {},
  });

  /// Full-size album art saved on the phone.
  final String? artPath;

  /// Full-size album art still in Telegram, downloaded when shown.
  final td.File? artFile;

  /// More about it for the player: format, size, bitrate, where from, when.
  final Map<String, String> info;

  /// For tracks known only by reference (a playlist's Telegram message):
  /// finds the playable file when the track is about to play. Returns the
  /// same track with [file] or [localPath] set, or null if it's gone.
  final Future<Track?> Function()? resolve;

  /// Which list this track was queued from (a playlist id), so its page
  /// can tell it's the one playing.
  final String? queueTag;

  /// Streams (radio, podcasts, audiobooks) play from [url] instead of a file.
  final String? url;
  final String? artUrl;

  /// A live stream: no length, no seeking.
  final bool live;

  factory Track.stream({required String url, required String title, String subtitle = '', String? artUrl, bool live = false, int seconds = 0}) => Track(
    chatId: 0,
    messageId: 0,
    identifier: 'url:$url',
    title: title,
    subtitle: subtitle,
    seconds: seconds,
    voice: false,
    url: url,
    artUrl: artUrl,
    live: live,
  );

  final int chatId;
  final int messageId;

  /// Telegram media is downloaded through [file]; Files-screen audio has
  /// already been saved locally and uses [localPath] instead.
  final td.File? file;
  final String? localPath;
  final String? identifier;
  final String title;
  final String subtitle;
  final int seconds;
  final bool voice;
  final td.Minithumbnail? cover;

  String get key => identifier ?? '$chatId:$messageId';

  /// This track with its playable source filled in, keeping its key.
  Track withSource({td.File? file, String? localPath, int? seconds, td.Minithumbnail? cover, td.File? artFile, Map<String, String>? info}) => Track(
    chatId: chatId,
    messageId: messageId,
    file: file ?? this.file,
    localPath: localPath ?? this.localPath,
    identifier: key,
    title: title,
    subtitle: subtitle,
    seconds: seconds != null && seconds > 0 ? seconds : this.seconds,
    voice: voice,
    cover: cover ?? this.cover,
    url: url,
    artUrl: artUrl,
    live: live,
    queueTag: queueTag,
    artPath: artPath,
    artFile: artFile ?? this.artFile,
    info: info == null ? this.info : {...this.info, ...info},
  );

  factory Track.localFile({
    required String path,
    required String title,
    required String subtitle,
    bool voice = false,
  }) => Track(
    info: audioInfo(fileName: path.split(RegExp(r'[\\/]')).last),
    chatId: 0,
    messageId: 0,
    localPath: path,
    identifier: 'file:$path',
    title: title,
    subtitle: subtitle,
    seconds: 0,
    voice: voice,
  );

  static Track? of(td.Message m, TelegramStore store) {
    switch (m.content) {
      case td.MessageVoiceNote(:final voiceNote):
        return Track(
          chatId: m.chatId,
          messageId: m.id,
          file: voiceNote.voice,
          title: m.isOutgoing ? 'You' : store.senderName(m.senderId),
          subtitle: 'Voice message',
          seconds: voiceNote.duration,
          voice: true,
          info: audioInfo(
            mime: voiceNote.mimeType,
            bytes: _bytes(voiceNote.voice),
            seconds: voiceNote.duration,
            chat: store.chat(m.chatId)?.title,
            date: m.date,
          ),
        );
      case td.MessageAudio(:final audio):
        return Track(
          chatId: m.chatId,
          messageId: m.id,
          file: audio.audio,
          title: audio.title.isNotEmpty ? audio.title : audio.fileName,
          subtitle: audio.performer.isNotEmpty
              ? audio.performer
              : (store.chat(m.chatId)?.title ?? ''),
          seconds: audio.duration,
          voice: false,
          cover: audio.albumCoverMinithumbnail,
          artFile: bestAlbumCover(audio),
          info: audioInfo(
            fileName: audio.fileName,
            mime: audio.mimeType,
            bytes: _bytes(audio.audio),
            seconds: audio.duration,
            chat: store.chat(m.chatId)?.title,
            date: m.date,
          ),
        );
      default:
        return null;
    }
  }
}

/// The biggest album cover Telegram has for a song: an external cover
/// (often 600 px) before the small embedded thumbnail.
td.File? bestAlbumCover(td.Audio audio) {
  final ext = [...audio.externalAlbumCovers]..sort((a, b) => a.width.compareTo(b.width));
  return ext.lastOrNull?.file ?? audio.albumCoverThumbnail?.file;
}

int _bytes(td.File f) => f.size > 0 ? f.size : f.expectedSize;

/// What the player shows under a track's title: file, format, size,
/// bitrate (worked out from size and length), where and when it was posted.
Map<String, String> audioInfo({String? fileName, String? mime, int bytes = 0, int seconds = 0, String? chat, int date = 0}) {
  final ext = fileName != null && fileName.contains('.') ? fileName.split('.').last.toUpperCase() : null;
  final format = ext ?? (mime != null && mime.contains('/') ? mime.split('/').last.toUpperCase().replaceAll('MPEG', 'MP3').replaceAll('X-', '') : null);
  String size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';
  String day(int unix) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  return {
    if (format != null && format.isNotEmpty) 'Format': format,
    if (bytes > 0) 'Size': size(bytes),
    if (bytes > 0 && seconds > 0) 'Bitrate': '≈${(bytes * 8 / seconds / 1000).round()} kbps',
    if (chat != null && chat.isNotEmpty) 'From': chat,
    if (date > 0) 'Posted': day(date),
    if (fileName != null && fileName.isNotEmpty) 'File': fileName,
  };
}

/// Plays voice messages and music from any chat, with a queue so the next
/// one in the chat follows, like Telegram's player.
class AudioCenter extends ChangeNotifier {
  AudioCenter(this._ref) {
    _player.onPositionChanged.listen((p) {
      // Time actually heard, for the listening stats: small forward steps
      // while playing (not seeks).
      final step = p - _heardAt;
      if (playing && current != null && step > Duration.zero && step < const Duration(seconds: 4)) {
        _heardMs += step.inMilliseconds;
        if (_heardMs >= 5000) {
          _stats((s) => s.heard(current!.key, _heardMs ~/ 1000));
          _heardMs %= 1000;
        }
      }
      _heardAt = p;
      position = p;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => _completed());
    // The notification's buttons.
    try {
      _actions = _ref.read(appNotifierProvider).mediaActions.stream.listen((a) {
        switch (a) {
          case 'toggle':
            toggle();
          case 'next':
            next();
          case 'previous':
            previous();
          case 'stop':
            stop();
        }
      });
    } catch (_) {}
  }

  StreamSubscription<String>? _actions;
  String? _shown;

  /// Keeps the notification in step with what's playing: only when the
  /// track, play state or cover changes, not on every position tick.
  void _syncNotification() {
    final t = current;
    String? art;
    if (t != null) {
      art = t.artPath != null && File(t.artPath!).existsSync() ? t.artPath : _ref.read(fileLoaderProvider).cachedPath(t.artFile);
    }
    final sig = t == null ? null : '${t.key}|$playing|$art|$hasNext|$loading';
    if (sig == _shown) return;
    _shown = sig;
    try {
      final n = _ref.read(appNotifierProvider);
      if (t == null) {
        unawaited(n.clearMedia());
      } else {
        unawaited(n.media(title: t.title, subtitle: t.subtitle, playing: playing || loading, art: art, hasNext: hasNext));
      }
    } catch (e) {
      debugPrint('[Audio] notification: $e');
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncNotification();
  }

  final Ref _ref;
  final _player = AudioPlayer();
  Duration _heardAt = Duration.zero;
  int _heardMs = 0;

  void _stats(void Function(MusicStatsStore) f) {
    try {
      f(_ref.read(musicStatsProvider.notifier));
    } catch (e) {
      debugPrint('[Audio] stats: $e');
    }
  }

  /// Stops after this time, or at the end of the track (sleep timer).
  DateTime? sleepAt;
  bool sleepAtEnd = false;
  Timer? _sleep;

  void setSleep(Duration? after, {bool endOfTrack = false}) {
    _sleep?.cancel();
    sleepAtEnd = endOfTrack;
    sleepAt = after == null ? null : DateTime.now().add(after);
    if (after != null) {
      _sleep = Timer(after, () async {
        sleepAt = null;
        if (playing) await toggle();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Track? current;
  List<Track> queue = const [];
  bool playing = false;
  bool loading = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double speed = 1;
  String? error;

  /// Plays the queue in a random order.
  bool shuffle = false;

  /// The file on the phone that's playing, once it's downloaded.
  String? currentPath;

  /// Off, the whole queue again, or the same track again.
  AudioRepeat repeat = AudioRepeat.off;

  /// The order tracks play in while shuffling (indexes into [queue]).
  List<int> _order = const [];

  /// The list the queue came from (a playlist id), when it has one.
  String? get queueTag => current?.queueTag;

  bool isCurrent(int chatId, int messageId) =>
      current?.chatId == chatId && current?.messageId == messageId;

  int get _index =>
      current == null ? -1 : queue.indexWhere((t) => t.key == current!.key);

  /// Where the current track sits in the play order.
  int get _step => shuffle ? _order.indexOf(_index) : _index;
  int _at(int step) => shuffle ? _order[step] : step;

  bool get hasNext => _index >= 0 && (_step < queue.length - 1 || (repeat == AudioRepeat.all && queue.length > 1));
  bool get hasPrevious => _index >= 0 && (_step > 0 || (repeat == AudioRepeat.all && queue.length > 1));

  /// What plays after the current track, in order.
  List<Track> get upNext {
    final i = _step;
    if (i < 0) return const [];
    return [for (var s = i + 1; s < queue.length; s++) queue[_at(s)]];
  }

  void _shuffleOrder() {
    final i = _index;
    final rest = [for (var k = 0; k < queue.length; k++) if (k != i) k]..shuffle(Random());
    _order = [if (i >= 0) i, ...rest];
  }

  void setShuffle(bool v) {
    shuffle = v;
    if (v) _shuffleOrder();
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = AudioRepeat.values[(repeat.index + 1) % AudioRepeat.values.length];
    notifyListeners();
  }

  /// Plays [tracks] from the start (or from a random one when shuffling).
  Future<void> playAll(List<Track> tracks, {bool shuffle = false, int start = 0}) async {
    if (tracks.isEmpty) return;
    this.shuffle = shuffle;
    final first = shuffle ? Random().nextInt(tracks.length) : start.clamp(0, tracks.length - 1);
    if (current?.key == tracks[first].key) {
      queue = tracks;
      if (shuffle) _shuffleOrder();
      if (!playing) await toggle();
      notifyListeners();
      return;
    }
    await play(tracks[first], playlist: tracks);
  }

  /// Plays [track]; [playlist] (oldest first) sets what plays after it.
  Future<void> play(Track track, {List<Track>? playlist}) async {
    if (current?.key == track.key && playlist != null) queue = playlist;
    if (current?.key == track.key) return toggle();
    await _ref.read(speakerProvider).stop();
    current = track;
    currentPath = null;
    _heardAt = Duration.zero;
    _heardMs = 0;
    if (!track.live) {
      _stats((s) => s.started(
        key: track.key,
        title: track.title,
        artist: track.subtitle,
        artPath: track.artPath,
        chatId: track.chatId,
        messageId: track.messageId,
        playlist: track.queueTag,
      ));
    }
    if (playlist != null) queue = playlist;
    if (!queue.any((t) => t.key == track.key)) queue = [track];
    if (shuffle && (playlist != null || _order.length != queue.length)) _shuffleOrder();
    position = Duration.zero;
    duration = Duration(seconds: track.seconds);
    loading = true;
    error = null;
    playing = true;
    notifyListeners();
    if (track.url != null) {
      try {
        await _player.setPlaybackRate(track.live ? 1 : speed);
        await _player.play(UrlSource(track.url!));
        if (current?.key == track.key) loading = false;
      } catch (e) {
        error = 'Could not play the stream: $e';
        playing = false;
        loading = false;
      }
      notifyListeners();
      return;
    }
    if (track.file == null && track.localPath == null && track.resolve != null) {
      Track? found;
      try {
        found = await track.resolve!();
      } catch (e) {
        debugPrint('[Audio] $e');
      }
      if (current?.key != track.key) return;
      if (found == null || (found.file == null && found.localPath == null)) {
        loading = false;
        playing = false;
        error = 'This audio is no longer available.';
        notifyListeners();
        // Skip past it in a playlist.
        if (hasNext && repeat != AudioRepeat.one) unawaited(next());
        return;
      }
      track = found;
      current = found;
      if (found.seconds > 0) duration = Duration(seconds: found.seconds);
      final i = queue.indexWhere((t) => t.key == found!.key);
      if (i >= 0) queue = [...queue]..[i] = found;
      notifyListeners();
    }
    final path =
        track.localPath ??
        await _ref.read(fileLoaderProvider).download(track.file!, priority: 32);
    if (current?.key != track.key) return;
    loading = false;
    if (path == null) {
      error = 'Couldn\'t download the audio.';
      playing = false;
      notifyListeners();
      return;
    }
    currentPath = path;
    try {
      await _player.setPlaybackRate(speed);
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      error = '$e';
      playing = false;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await _player.pause();
      playing = false;
    } else {
      await _player.resume();
      playing = true;
    }
    notifyListeners();
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> skip(int seconds) {
    var t = position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    return _player.seek(t);
  }

  Future<void> next() async {
    if (!hasNext) return;
    final s = _step + 1;
    await play(queue[_at(s >= queue.length ? 0 : s)]);
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3) || !hasPrevious) {
      await _player.seek(Duration.zero);
    } else {
      final s = _step - 1;
      await play(queue[_at(s < 0 ? queue.length - 1 : s)]);
    }
  }

  /// Puts [track] right after the current one.
  void playNext(Track track) {
    final rest = [for (final t in queue) if (t.key != track.key) t];
    final i = current == null ? -1 : rest.indexWhere((t) => t.key == current!.key);
    rest.insert(i + 1, track);
    queue = rest;
    if (shuffle) _shuffleOrder();
    notifyListeners();
  }

  /// Adds [track] at the end of the queue.
  void enqueue(Track track) {
    if (queue.any((t) => t.key == track.key)) return;
    queue = [...queue, track];
    if (shuffle) _shuffleOrder();
    notifyListeners();
  }

  /// Takes [track] out of the queue (not the one playing).
  void dequeue(Track track) {
    if (track.key == current?.key) return;
    queue = [for (final t in queue) if (t.key != track.key) t];
    if (shuffle) _shuffleOrder();
    notifyListeners();
  }

  /// Moves a queued track (indexes into [queue]).
  void moveInQueue(int from, int to) {
    final list = [...queue];
    if (from < 0 || from >= list.length) return;
    final t = list.removeAt(from);
    list.insert(to.clamp(0, list.length), t);
    queue = list;
    notifyListeners();
  }

  /// Jumps to [track] in the current queue.
  Future<void> jumpTo(Track track) => play(track);

  Future<void> setSpeed(double v) async {
    speed = v;
    await _player.setPlaybackRate(v);
    notifyListeners();
  }

  void _completed() {
    if (sleepAtEnd) {
      sleepAtEnd = false;
      playing = false;
      position = Duration.zero;
      notifyListeners();
      return;
    }
    if (repeat == AudioRepeat.one && current != null) {
      unawaited(_player.seek(Duration.zero).then((_) => _player.resume()));
      return;
    }
    if (hasNext) {
      unawaited(next());
    } else {
      playing = false;
      position = Duration.zero;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _sleep?.cancel();
    sleepAt = null;
    await _player.stop();
    current = null;
    playing = false;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _actions?.cancel();
    _sleep?.cancel();
    _player.dispose();
    super.dispose();
  }
}

enum AudioRepeat { off, all, one }

final audioCenterProvider = ChangeNotifierProvider<AudioCenter>(
  (ref) => AudioCenter(ref),
);
