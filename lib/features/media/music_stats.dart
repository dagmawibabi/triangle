import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What's known about one track the person listened to.
@immutable
class TrackStat {
  const TrackStat({
    required this.key,
    required this.title,
    this.artist = '',
    this.artPath,
    this.chatId = 0,
    this.messageId = 0,
    this.playlist,
    this.plays = 0,
    this.seconds = 0,
    required this.first,
    required this.last,
  });
  final String key;
  final String title;
  final String artist;
  final String? artPath;
  final int chatId;
  final int messageId;

  /// The playlist it last played from.
  final String? playlist;
  final int plays;

  /// Time actually listened, in seconds.
  final int seconds;
  final DateTime first;
  final DateTime last;

  TrackStat copyWith({int? plays, int? seconds, DateTime? last, String? playlist, String? artPath, String? title, String? artist}) => TrackStat(
    key: key,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    artPath: artPath ?? this.artPath,
    chatId: chatId,
    messageId: messageId,
    playlist: playlist ?? this.playlist,
    plays: plays ?? this.plays,
    seconds: seconds ?? this.seconds,
    first: first,
    last: last ?? this.last,
  );

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    if (artist.isNotEmpty) 'a': artist,
    if (artPath != null) 'ap': artPath,
    if (chatId != 0) 'c': chatId,
    if (messageId != 0) 'm': messageId,
    if (playlist != null) 'p': playlist,
    'n': plays,
    's': seconds,
    'f': first.millisecondsSinceEpoch,
    'l': last.millisecondsSinceEpoch,
  };

  factory TrackStat.fromJson(Map j) => TrackStat(
    key: '${j['k']}',
    title: '${j['t'] ?? 'Audio'}',
    artist: '${j['a'] ?? ''}',
    artPath: j['ap'] == null ? null : '${j['ap']}',
    chatId: (j['c'] as num?)?.toInt() ?? 0,
    messageId: (j['m'] as num?)?.toInt() ?? 0,
    playlist: j['p'] == null ? null : '${j['p']}',
    plays: (j['n'] as num?)?.toInt() ?? 0,
    seconds: (j['s'] as num?)?.toInt() ?? 0,
    first: DateTime.fromMillisecondsSinceEpoch((j['f'] as num?)?.toInt() ?? 0),
    last: DateTime.fromMillisecondsSinceEpoch((j['l'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {
    'title': title,
    if (artist.isNotEmpty) 'artist': artist,
    'plays': plays,
    'minutes_listened': (seconds / 60).round(),
    'last_played': last.toIso8601String().substring(0, 16),
  };
}

@immutable
class MusicStatsState {
  const MusicStatsState({this.tracks = const {}, this.days = const {}, this.playlistPlays = const {}});
  final Map<String, TrackStat> tracks;

  /// Seconds listened per day, `yyyy-mm-dd`.
  final Map<String, int> days;

  /// Plays per playlist id.
  final Map<String, int> playlistPlays;

  int get totalSeconds => days.values.fold(0, (a, b) => a + b);
  int get totalPlays => tracks.values.fold(0, (a, b) => a + b.plays);

  List<TrackStat> get top => tracks.values.toList()..sort((a, b) => b.plays != a.plays ? b.plays.compareTo(a.plays) : b.seconds.compareTo(a.seconds));
  List<TrackStat> get recent => tracks.values.toList()..sort((a, b) => b.last.compareTo(a.last));

  /// Artists by time listened.
  List<(String, int, int)> get artists {
    final m = <String, (int, int)>{};
    for (final t in tracks.values) {
      final a = t.artist.split(' · ').first.trim();
      if (a.isEmpty) continue;
      final v = m[a] ?? (0, 0);
      m[a] = (v.$1 + t.plays, v.$2 + t.seconds);
    }
    return [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$3.compareTo(a.$3));
  }

  /// Days in a row up to today with some listening.
  int get streak {
    var n = 0;
    var d = DateTime.now();
    while (days.containsKey(dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Counts what the player plays: plays per track and playlist, and time
/// listened per day. Kept on this phone.
class MusicStatsStore extends Notifier<MusicStatsState> {
  static const key = 'music_stats.v1';
  late Future<void> ready;
  Timer? _save;

  @override
  MusicStatsState build() {
    ready = _load();
    ref.onDispose(() => _save?.cancel());
    return const MusicStatsState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      final days = {for (final e in ((j['days'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
      final lists = {for (final e in ((j['playlists'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
      // Anything counted while this was loading is kept on top.
      final now = state;
      final saved = {for (final t in (j['tracks'] as List? ?? const [])) if (t is Map) '${t['k']}': TrackStat.fromJson(t)};
      state = MusicStatsState(
        tracks: {
          ...saved,
          for (final e in now.tracks.entries)
            e.key: saved[e.key] == null
                ? e.value
                : saved[e.key]!.copyWith(plays: saved[e.key]!.plays + e.value.plays, seconds: saved[e.key]!.seconds + e.value.seconds, last: e.value.last),
        },
        days: {...days, for (final e in now.days.entries) e.key: (days[e.key] ?? 0) + e.value},
        playlistPlays: {...lists, for (final e in now.playlistPlays.entries) e.key: (lists[e.key] ?? 0) + e.value},
      );
    } catch (e) {
      debugPrint('[MusicStats] $e');
    }
  }

  void _later() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 10), flush);
  }

  Future<void> flush() async {
    _save?.cancel();
    final s = state;
    // Keep the 1500 most recent tracks.
    final tracks = s.recent.take(1500).toList();
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'tracks': [for (final t in tracks) t.toJson()],
        'days': s.days,
        'playlists': s.playlistPlays,
      }),
    );
  }

  /// A track started playing.
  void started({required String key, required String title, String artist = '', String? artPath, int chatId = 0, int messageId = 0, String? playlist}) {
    final now = DateTime.now();
    final old = state.tracks[key];
    final t = old == null
        ? TrackStat(key: key, title: title, artist: artist, artPath: artPath, chatId: chatId, messageId: messageId, playlist: playlist, plays: 1, first: now, last: now)
        : old.copyWith(plays: old.plays + 1, last: now, playlist: playlist, artPath: artPath, title: title, artist: artist);
    state = MusicStatsState(
      tracks: {...state.tracks, key: t},
      days: state.days,
      playlistPlays: playlist == null ? state.playlistPlays : {...state.playlistPlays, playlist: (state.playlistPlays[playlist] ?? 0) + 1},
    );
    _later();
  }

  /// [seconds] more of [key] were heard.
  void heard(String key, int seconds) {
    if (seconds <= 0) return;
    final t = state.tracks[key];
    final day = MusicStatsState.dayKey(DateTime.now());
    state = MusicStatsState(
      tracks: t == null ? state.tracks : {...state.tracks, key: t.copyWith(seconds: t.seconds + seconds)},
      days: {...state.days, day: (state.days[day] ?? 0) + seconds},
      playlistPlays: state.playlistPlays,
    );
    _later();
  }

  Future<void> clear() async {
    state = const MusicStatsState();
    await flush();
  }
}

final musicStatsProvider = NotifierProvider<MusicStatsStore, MusicStatsState>(MusicStatsStore.new);
