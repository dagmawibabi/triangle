import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../media/audio_center.dart';
import '../media/audio_tags.dart';
import '../telegram/data/telegram_store.dart';
import 'playlist_share.dart';

/// Where a playlist track lives.
enum TrackSource { telegram, file, stream }

/// What a track is, for its icon and the filters.
enum TrackKind {
  music('Music', Icons.music_note_rounded),
  voice('Voice', Icons.mic_rounded),
  podcast('Podcast', Icons.podcasts_rounded),
  audiobook('Audiobook', Icons.headphones_rounded),
  audio('Audio file', Icons.graphic_eq_rounded);

  const TrackKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static TrackKind named(String? n) => TrackKind.values.asNameMap()[n] ?? TrackKind.audio;
}

/// One song, voice message, episode or audio file in a playlist. Telegram
/// tracks are kept by reference (account, chat, message): the audio itself
/// stays in Telegram and downloads when it plays.
@immutable
class PlaylistTrack {
  const PlaylistTrack({
    required this.id,
    required this.source,
    required this.title,
    this.artist = '',
    this.seconds = 0,
    this.kind = TrackKind.audio,
    this.account,
    this.chatId,
    this.messageId,
    this.chatTitle,
    this.path,
    this.url,
    this.thumb,
    this.artUrl,
    this.artPath,
    this.fileName,
    this.size = 0,
    this.postedAt,
    required this.addedAt,
  });

  final String id;
  final TrackSource source;
  final String title;
  final String artist;
  final int seconds;
  final TrackKind kind;

  /// Telegram: whose account, which chat and message.
  final String? account;
  final int? chatId;
  final int? messageId;
  final String? chatTitle;

  /// A file the app saved.
  final String? path;

  /// A stream link.
  final String? url;

  /// A tiny base64 JPEG of the album art (Telegram's minithumbnail).
  final String? thumb;

  /// A cover image link.
  final String? artUrl;

  /// Full-size album art saved in the app's folder.
  final String? artPath;

  /// The audio's own file name, size in bytes, and when it was posted.
  final String? fileName;
  final int size;
  final DateTime? postedAt;
  final DateTime addedAt;

  /// For the player's details.
  Map<String, String> get info => audioInfo(
    fileName: fileName ?? (path?.split(RegExp(r'[\\/]')).last),
    bytes: size,
    seconds: seconds,
    chat: chatTitle,
    date: postedAt == null ? 0 : postedAt!.millisecondsSinceEpoch ~/ 1000,
  );

  /// The same audio, whichever playlist it's in.
  String get key => switch (source) {
    TrackSource.telegram => 'tg:$account:$chatId:$messageId',
    TrackSource.file => 'file:$path',
    TrackSource.stream => 'url:$url',
  };

  /// The line under the title.
  String get subtitle {
    final by = artist.trim();
    return switch (source) {
      TrackSource.telegram => [if (by.isNotEmpty) by, if (chatTitle != null && chatTitle != by) chatTitle!].join(' · '),
      _ => by.isNotEmpty ? by : kind.label,
    };
  }

  PlaylistTrack copyWith({String? title, String? artist, int? seconds, String? thumb, String? artPath, int? size}) => PlaylistTrack(
    id: id,
    source: source,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    seconds: seconds ?? this.seconds,
    kind: kind,
    account: account,
    chatId: chatId,
    messageId: messageId,
    chatTitle: chatTitle,
    path: path,
    url: url,
    thumb: thumb ?? this.thumb,
    artUrl: artUrl,
    artPath: artPath ?? this.artPath,
    fileName: fileName,
    size: size ?? this.size,
    postedAt: postedAt,
    addedAt: addedAt,
  );

  /// The same track with a fresh id, for adding to another playlist.
  PlaylistTrack fresh() => PlaylistTrack(
    id: _shortId(),
    source: source,
    title: title,
    artist: artist,
    seconds: seconds,
    kind: kind,
    account: account,
    chatId: chatId,
    messageId: messageId,
    chatTitle: chatTitle,
    path: path,
    url: url,
    thumb: thumb,
    artUrl: artUrl,
    artPath: artPath,
    fileName: fileName,
    size: size,
    postedAt: postedAt,
    addedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    's': source.name,
    't': title,
    if (artist.isNotEmpty) 'ar': artist,
    if (seconds > 0) 'd': seconds,
    'k': kind.name,
    if (account != null) 'a': account,
    if (chatId != null) 'c': chatId,
    if (messageId != null) 'm': messageId,
    if (chatTitle != null) 'ct': chatTitle,
    if (path != null) 'p': path,
    if (url != null) 'u': url,
    if (thumb != null) 'th': thumb,
    if (artUrl != null) 'art': artUrl,
    if (artPath != null) 'ap': artPath,
    if (fileName != null) 'fn': fileName,
    if (size > 0) 'sz': size,
    if (postedAt != null) 'pa': postedAt!.millisecondsSinceEpoch,
    'at': addedAt.millisecondsSinceEpoch,
  };

  factory PlaylistTrack.fromJson(Map j) => PlaylistTrack(
    id: '${j['id'] ?? _shortId()}',
    source: TrackSource.values.asNameMap()['${j['s']}'] ?? TrackSource.file,
    title: '${j['t'] ?? 'Audio'}',
    artist: '${j['ar'] ?? ''}',
    seconds: (j['d'] as num?)?.toInt() ?? 0,
    kind: TrackKind.named('${j['k']}'),
    account: j['a'] == null ? null : '${j['a']}',
    chatId: (j['c'] as num?)?.toInt(),
    messageId: (j['m'] as num?)?.toInt(),
    chatTitle: j['ct'] == null ? null : '${j['ct']}',
    path: j['p'] == null ? null : '${j['p']}',
    url: j['u'] == null ? null : '${j['u']}',
    thumb: j['th'] == null ? null : '${j['th']}',
    artUrl: j['art'] == null ? null : '${j['art']}',
    artPath: j['ap'] == null ? null : '${j['ap']}',
    fileName: j['fn'] == null ? null : '${j['fn']}',
    size: (j['sz'] as num?)?.toInt() ?? 0,
    postedAt: j['pa'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['pa'] as num).toInt()),
    addedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  /// For the assistant. Titles come from other people's messages.
  Map<String, dynamic> describe() => {
    'track_id': id,
    'title': title,
    if (artist.isNotEmpty) 'artist': artist,
    'type': kind.name,
    'source': source.name,
    if (seconds > 0) 'duration': _clock(seconds),
    if (chatTitle != null) 'chat': chatTitle,
    if (chatId != null) 'chat_id': chatId,
    if (messageId != null) 'message_id': messageId,
    if (path != null) 'file_path': path,
    if (fileName != null) 'file_name': fileName,
    if (postedAt != null) 'posted': postedAt!.toIso8601String().substring(0, 10),
    'has_album_art': artPath != null || thumb != null,
  };

  /// A Telegram voice message, song, or audio file sent as a document;
  /// null for anything else.
  static PlaylistTrack? fromMessage(td.Message m, TelegramStore store, String account) {
    final chat = store.chat(m.chatId)?.title;
    PlaylistTrack make({required String title, String artist = '', int seconds = 0, required TrackKind kind, String? thumb, String? fileName, td.File? file}) => PlaylistTrack(
      id: _shortId(),
      source: TrackSource.telegram,
      title: title.trim().isEmpty ? 'Audio' : title.trim(),
      artist: artist,
      seconds: seconds,
      kind: kind,
      account: account,
      chatId: m.chatId,
      messageId: m.id,
      chatTitle: chat,
      thumb: thumb,
      fileName: fileName == null || fileName.isEmpty ? null : fileName,
      size: file == null ? 0 : (file.size > 0 ? file.size : file.expectedSize),
      postedAt: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
      addedAt: DateTime.now(),
    );
    switch (m.content) {
      case td.MessageAudio(:final audio):
        final name = audio.title.isNotEmpty ? audio.title : _stripExt(audio.fileName);
        return make(
          title: name,
          artist: audio.performer,
          seconds: audio.duration,
          kind: guessKind(name, audio.duration, music: true),
          thumb: audio.albumCoverMinithumbnail?.data,
          fileName: audio.fileName,
          file: audio.audio,
        );
      case td.MessageVoiceNote(:final voiceNote):
        final from = m.isOutgoing ? 'You' : store.senderName(m.senderId);
        final when = DateTime.fromMillisecondsSinceEpoch(m.date * 1000);
        return make(title: 'Voice · $from', artist: _date(when), seconds: voiceNote.duration, kind: TrackKind.voice, file: voiceNote.voice);
      case td.MessageDocument(:final document) when isAudioName(document.fileName, document.mimeType):
        final name = _stripExt(document.fileName);
        return make(title: name, kind: guessKind(name, 0), thumb: document.minithumbnail?.data, fileName: document.fileName, file: document.document);
      default:
        return null;
    }
  }

  /// A file the app saved, with what its sidecar says about it.
  static PlaylistTrack fromFile(String path, {Map<String, dynamic> meta = const {}}) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final title = '${meta['title'] ?? _stripExt(name)}'.trim();
    final kind = switch (meta['library']) {
      'podcast' => TrackKind.podcast,
      'audiobook' => TrackKind.audiobook,
      _ => meta['voice'] == true || RegExp(r'^voice[-_]').hasMatch(name.toLowerCase()) ? TrackKind.voice : guessKind(title, 0),
    };
    final cover = meta['cover'];
    return PlaylistTrack(
      id: _shortId(),
      source: TrackSource.file,
      title: title.isEmpty ? name : title,
      artist: '${meta['subtitle'] ?? meta['author'] ?? ''}'.trim(),
      seconds: (meta['duration'] as num?)?.toInt() ?? 0,
      kind: kind,
      path: path,
      artUrl: cover is String && cover.startsWith('http') ? cover : null,
      fileName: name,
      size: () {
        try {
          return File(path).lengthSync();
        } catch (_) {
          return 0;
        }
      }(),
      addedAt: DateTime.now(),
    );
  }

  /// What the player is playing, as a playlist track (for liking it or
  /// adding it to a playlist from the player). [account] is the Telegram
  /// account it came from.
  static PlaylistTrack fromTrack(Track t, String account) {
    final source = t.url != null
        ? TrackSource.stream
        : (t.chatId != 0 && t.messageId != 0 ? TrackSource.telegram : TrackSource.file);
    final keyParts = t.key.split(':');
    // A playlist track already knows its account: tg:<account>:<chat>:<msg>.
    final acc = keyParts.length >= 4 && keyParts.first == 'tg' ? keyParts.sublist(1, keyParts.length - 2).join(':') : account;
    return PlaylistTrack(
      id: _shortId(),
      source: source,
      title: t.title,
      artist: t.voice ? '' : t.subtitle,
      seconds: t.seconds,
      kind: t.voice ? TrackKind.voice : (t.url != null ? TrackKind.podcast : TrackKind.music),
      account: source == TrackSource.telegram ? acc : null,
      chatId: source == TrackSource.telegram ? t.chatId : null,
      messageId: source == TrackSource.telegram ? t.messageId : null,
      chatTitle: t.info['From'],
      path: source == TrackSource.file ? t.localPath : null,
      url: t.url,
      thumb: t.cover?.data,
      artUrl: t.artUrl,
      artPath: t.artPath,
      fileName: t.info['File'],
      addedAt: DateTime.now(),
    );
  }

  static PlaylistTrack stream({required String url, required String title, String artist = '', String? artUrl, TrackKind kind = TrackKind.podcast}) =>
      PlaylistTrack(id: _shortId(), source: TrackSource.stream, title: title, artist: artist, kind: kind, url: url, artUrl: artUrl, addedAt: DateTime.now());
}

const _audioExt = {'mp3', 'm4a', 'wav', 'ogg', 'oga', 'opus', 'flac', 'aac', 'wma', 'm4b', 'amr', 'mka'};

/// Whether a file name or mime type is audio.
bool isAudioName(String name, [String mime = '']) {
  if (mime.startsWith('audio/')) return true;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return _audioExt.contains(ext);
}

/// A guess at what a Telegram audio is from its name and length: long ones
/// and "episode"/"chapter" names are podcasts or audiobooks.
TrackKind guessKind(String name, int seconds, {bool music = false}) {
  final n = name.toLowerCase();
  if (RegExp(r'chapter|audiobook|part \d|ምዕራፍ').hasMatch(n)) return TrackKind.audiobook;
  if (RegExp(r'episode|podcast|\bep\.? ?\d').hasMatch(n)) return TrackKind.podcast;
  if (seconds > 25 * 60) return TrackKind.podcast;
  return music ? TrackKind.music : TrackKind.audio;
}

String _stripExt(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String _date(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final now = DateTime.now();
  return '${d.day} ${months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

String _clock(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// A total like "1 h 12 min" or "34 min".
String playlistLength(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h h${m > 0 ? ' $m min' : ''}';
  return m > 0 ? '$m min' : '${seconds}s';
}

const _uuid = Uuid();
String _shortId() => _uuid.v4().substring(0, 8);

/// The gradients a playlist without a picture wears.
const playlistPalettes = <List<Color>>[
  [Color(0xFFFF6B6B), Color(0xFF7B2CBF)],
  [Color(0xFF00C6FF), Color(0xFF0072FF)],
  [Color(0xFFF7971E), Color(0xFFFFD200)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFFFC466B), Color(0xFF3F5EFB)],
  [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  [Color(0xFFEE0979), Color(0xFFFF6A00)],
  [Color(0xFF1D976C), Color(0xFF93F9B9)],
  [Color(0xFF232526), Color(0xFF414345)],
  [Color(0xFFDA22FF), Color(0xFF9733EE)],
  [Color(0xFF2193B0), Color(0xFF6DD5ED)],
  [Color(0xFFC33764), Color(0xFF1D2671)],
];

/// The plain icons a playlist can wear instead of an emoji, by the key it's
/// saved as.
const playlistIcons = <String, IconData>{
  'music': Icons.music_note_rounded,
  'queue': Icons.queue_music_rounded,
  'album': Icons.album_rounded,
  'headphones': Icons.headphones_rounded,
  'mic': Icons.mic_rounded,
  'podcast': Icons.podcasts_rounded,
  'radio': Icons.radio_rounded,
  'piano': Icons.piano_rounded,
  'guitar': Icons.music_video_rounded,
  'speaker': Icons.speaker_rounded,
  'waves': Icons.graphic_eq_rounded,
  'book': Icons.menu_book_rounded,
  'church': Icons.church_rounded,
  'mosque': Icons.mosque_rounded,
  'heart': Icons.favorite_rounded,
  'star': Icons.star_rounded,
  'moon': Icons.nightlight_round,
  'sun': Icons.wb_sunny_rounded,
  'fitness': Icons.fitness_center_rounded,
  'car': Icons.directions_car_rounded,
  'coffee': Icons.local_cafe_rounded,
  'party': Icons.celebration_rounded,
  'school': Icons.school_rounded,
  'bolt': Icons.bolt_rounded,
};

final _exists = <String, bool>{};

/// Whether [path] exists, remembered so covers don't touch the disk on
/// every frame.
bool fileExists(String path) => _exists[path] ??= File(path).existsSync();
void forgetFile(String path) => _exists.remove(path);

/// A named list of tracks with a cover: a picture the person picked, or a
/// gradient with an emoji.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.emoji = '🎵',
    this.icon,
    this.collage = true,
    this.coverPath,
    this.palette = 0,
    this.tracks = const [],
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.playedAt,
    this.plays = 0,
  });

  final String id;
  final String name;
  final String description;
  final String emoji;

  /// One of the plain icons ([playlistIcons]) instead of the emoji. With no
  /// icon and an empty emoji, the cover has no mark.
  final String? icon;

  /// Without a picture, a collage of the tracks' album art (when they have
  /// some) rather than the gradient.
  final bool collage;

  /// A picture kept in the app's folder.
  final String? coverPath;
  final int palette;
  final List<PlaylistTrack> tracks;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? playedAt;
  final int plays;

  List<Color> get colors => playlistPalettes[palette % playlistPalettes.length];
  int get seconds => tracks.fold(0, (n, t) => n + t.seconds);
  bool has(PlaylistTrack t) => tracks.any((x) => x.key == t.key);

  /// Up to four different album covers saved for its tracks.
  List<String> get arts {
    final out = <String>[];
    for (final t in tracks) {
      final a = t.artPath;
      if (a != null && !out.contains(a) && fileExists(a)) out.add(a);
      if (out.length == 4) break;
    }
    return out;
  }

  /// How many tracks of each kind, for the list view.
  Map<TrackKind, int> get kinds {
    final out = <TrackKind, int>{};
    for (final t in tracks) {
      out[t.kind] = (out[t.kind] ?? 0) + 1;
    }
    return out;
  }

  /// How many of each kind, for the subtitle ("12 songs · 3 voice").
  String get summary {
    if (tracks.isEmpty) return 'Empty';
    final n = tracks.length;
    final len = playlistLength(seconds);
    return '$n ${n == 1 ? 'track' : 'tracks'}${len.isEmpty ? '' : ' · $len'}';
  }

  Playlist copyWith({
    String? name,
    String? description,
    String? emoji,
    String? icon,
    bool clearIcon = false,
    bool? collage,
    String? coverPath,
    bool clearCover = false,
    int? palette,
    List<PlaylistTrack>? tracks,
    bool? pinned,
    DateTime? playedAt,
    int? plays,
    bool touch = true,
  }) => Playlist(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    emoji: emoji ?? this.emoji,
    icon: clearIcon ? null : (icon ?? this.icon),
    collage: collage ?? this.collage,
    coverPath: clearCover ? null : (coverPath ?? this.coverPath),
    palette: palette ?? this.palette,
    tracks: tracks ?? this.tracks,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
    updatedAt: touch ? DateTime.now() : updatedAt,
    playedAt: playedAt ?? this.playedAt,
    plays: plays ?? this.plays,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description.isNotEmpty) 'desc': description,
    'emoji': emoji,
    if (icon != null) 'icon': icon,
    if (!collage) 'collage': false,
    if (coverPath != null) 'cover': coverPath,
    'palette': palette,
    'tracks': [for (final t in tracks) t.toJson()],
    if (pinned) 'pinned': true,
    'created': createdAt.millisecondsSinceEpoch,
    'updated': updatedAt.millisecondsSinceEpoch,
    if (playedAt != null) 'played': playedAt!.millisecondsSinceEpoch,
    if (plays > 0) 'plays': plays,
  };

  factory Playlist.fromJson(Map j) {
    DateTime at(String k) => DateTime.fromMillisecondsSinceEpoch((j[k] as num?)?.toInt() ?? 0);
    return Playlist(
      id: '${j['id']}',
      name: '${j['name'] ?? 'Playlist'}',
      description: '${j['desc'] ?? ''}',
      emoji: '${j['emoji'] ?? '🎵'}',
      icon: j['icon'] == null ? null : '${j['icon']}',
      collage: j['collage'] != false,
      coverPath: j['cover'] == null ? null : '${j['cover']}',
      palette: (j['palette'] as num?)?.toInt() ?? 0,
      tracks: [for (final t in (j['tracks'] as List? ?? const [])) if (t is Map) PlaylistTrack.fromJson(t)],
      pinned: j['pinned'] == true,
      createdAt: at('created'),
      updatedAt: at('updated'),
      playedAt: j['played'] == null ? null : at('played'),
      plays: (j['plays'] as num?)?.toInt() ?? 0,
    );
  }

  /// For the assistant.
  Map<String, dynamic> describe() => {
    'playlist_id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'track_count': tracks.length,
    if (seconds > 0) 'length': playlistLength(seconds),
    'cover': coverPath != null ? 'picture' : (collage && arts.isNotEmpty ? 'album art collage' : 'colour'),
    if (icon != null) 'icon': icon else if (emoji.isNotEmpty) 'emoji': emoji,
    'colour': palette % playlistPalettes.length,
    if (pinned) 'pinned': true,
    if (playedAt != null) 'last_played': playedAt!.toIso8601String().substring(0, 16),
    if (plays > 0) 'plays': plays,
  };
}

/// How the library is sorted.
enum PlaylistSort {
  custom('Your order'),
  recent('Recently played'),
  updated('Recently changed'),
  name('Name'),
  size('Most tracks');

  const PlaylistSort(this.label);
  final String label;
}

@immutable
class PlaylistsState {
  const PlaylistsState({this.playlists = const [], this.sort = PlaylistSort.recent, this.grid = true, this.inDrawer = true, this.drawerOpen = true});
  final List<Playlist> playlists;
  final PlaylistSort sort;
  final bool grid;

  /// Shown as a section of the side drawer, and whether it's open.
  final bool inDrawer;
  final bool drawerOpen;

  /// Pinned first, then by [sort].
  List<Playlist> get sorted {
    final list = [...playlists];
    int by(Playlist a, Playlist b) => switch (sort) {
      PlaylistSort.custom => playlists.indexOf(a).compareTo(playlists.indexOf(b)),
      PlaylistSort.recent => (b.playedAt ?? b.updatedAt).compareTo(a.playedAt ?? a.updatedAt),
      PlaylistSort.updated => b.updatedAt.compareTo(a.updatedAt),
      PlaylistSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      PlaylistSort.size => b.tracks.length.compareTo(a.tracks.length),
    };
    list.sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : by(a, b));
    return list;
  }

  PlaylistsState copyWith({List<Playlist>? playlists, PlaylistSort? sort, bool? grid, bool? inDrawer, bool? drawerOpen}) => PlaylistsState(
    playlists: playlists ?? this.playlists,
    sort: sort ?? this.sort,
    grid: grid ?? this.grid,
    inDrawer: inDrawer ?? this.inDrawer,
    drawerOpen: drawerOpen ?? this.drawerOpen,
  );
}

/// The person's playlists, kept on this phone.
class PlaylistsStore extends Notifier<PlaylistsState> {
  static const _key = 'playlists.v1';
  late Future<void> ready;

  @override
  PlaylistsState build() {
    ready = _load();
    return const PlaylistsState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = PlaylistsState(
        playlists: [for (final p in (j['playlists'] as List? ?? const [])) if (p is Map) Playlist.fromJson(p)],
        sort: PlaylistSort.values.asNameMap()['${j['sort']}'] ?? PlaylistSort.recent,
        grid: j['grid'] != false,
        inDrawer: j['in_drawer'] != false,
        drawerOpen: j['drawer_open'] != false,
      );
    } catch (e) {
      debugPrint('[Playlists] $e');
    }
  }

  Future<void> _set(PlaylistsState s) async {
    state = s;
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        'playlists': [for (final p in s.playlists) p.toJson()],
        'sort': s.sort.name,
        'grid': s.grid,
        'in_drawer': s.inDrawer,
        'drawer_open': s.drawerOpen,
      }),
    );
  }

  Playlist? byId(String id) => state.playlists.where((p) => p.id == id).firstOrNull;

  /// A playlist by id, or by name (any case, then the first containing it).
  Playlist? find(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    if (q.isEmpty) return null;
    return byId(idOrName.trim()) ??
        state.playlists.where((p) => p.name.toLowerCase() == q).firstOrNull ??
        state.playlists.where((p) => p.name.toLowerCase().contains(q)).firstOrNull;
  }

  Future<Playlist> create(
    String name, {
    String description = '',
    String emoji = '🎵',
    String? icon,
    bool collage = true,
    int? palette,
    String? coverPath,
    List<PlaylistTrack> tracks = const [],
  }) async {
    await ready;
    final now = DateTime.now();
    final p = Playlist(
      id: _shortId(),
      name: name.trim().isEmpty ? 'New playlist' : name.trim(),
      description: description.trim(),
      emoji: emoji.trim(),
      icon: playlistIcons.containsKey(icon) ? icon : null,
      collage: collage,
      palette: palette ?? state.playlists.length % playlistPalettes.length,
      coverPath: coverPath,
      tracks: _dedupe(tracks),
      createdAt: now,
      updatedAt: now,
    );
    await _set(state.copyWith(playlists: [...state.playlists, p]));
    if (p.tracks.isNotEmpty) unawaited(ensureArt(p.id));
    return p;
  }

  Future<Playlist?> update(String id, Playlist Function(Playlist) change) async {
    await ready;
    Playlist? out;
    await _set(state.copyWith(playlists: [for (final p in state.playlists) if (p.id == id) out = change(p) else p]));
    return out;
  }

  static List<PlaylistTrack> _dedupe(Iterable<PlaylistTrack> tracks) {
    final seen = <String>{};
    return [for (final t in tracks) if (seen.add(t.key)) t];
  }

  /// Adds [tracks] at the end, skipping ones already in it. Returns how
  /// many were new.
  Future<int> addTracks(String id, Iterable<PlaylistTrack> tracks) async {
    var added = 0;
    await update(id, (p) {
      final have = {for (final t in p.tracks) t.key};
      final fresh = [for (final t in _dedupe(tracks)) if (!have.contains(t.key)) t.fresh()];
      added = fresh.length;
      return p.copyWith(tracks: [...p.tracks, ...fresh]);
    });
    if (added > 0) unawaited(ensureArt(id));
    return added;
  }

  Future<void> removeTracks(String id, Iterable<String> trackIds) {
    final drop = trackIds.toSet();
    return update(id, (p) => p.copyWith(tracks: [for (final t in p.tracks) if (!drop.contains(t.id)) t]));
  }

  Future<void> moveTrack(String id, int from, int to) => update(id, (p) {
    final list = [...p.tracks];
    if (from < 0 || from >= list.length) return p;
    final t = list.removeAt(from);
    list.insert(to.clamp(0, list.length), t);
    return p.copyWith(tracks: list);
  });

  Future<void> setTracks(String id, List<PlaylistTrack> tracks) => update(id, (p) => p.copyWith(tracks: tracks));

  Future<void> renameTrack(String id, String trackId, String title) => update(
    id,
    (p) => p.copyWith(tracks: [for (final t in p.tracks) t.id == trackId ? t.copyWith(title: title) : t]),
  );

  Future<bool> delete(String id) async {
    await ready;
    final p = byId(id);
    if (p == null) return false;
    await _set(state.copyWith(playlists: [for (final x in state.playlists) if (x.id != id) x]));
    await _dropCover(p.coverPath);
    return true;
  }

  Future<Playlist?> duplicate(String id) async {
    final p = byId(id);
    if (p == null) return null;
    String? cover;
    if (p.coverPath != null && File(p.coverPath!).existsSync()) cover = await _keepCover(p.coverPath!);
    return create(
      '${p.name} copy',
      description: p.description,
      emoji: p.emoji,
      icon: p.icon,
      collage: p.collage,
      palette: p.palette,
      coverPath: cover,
      tracks: [for (final t in p.tracks) t.fresh()],
    );
  }

  Future<void> setPinned(String id, bool v) => update(id, (p) => p.copyWith(pinned: v, touch: false));

  /// Notes that [id] started playing (for "Recently played").
  Future<void> markPlayed(String id) => update(id, (p) => p.copyWith(playedAt: DateTime.now(), plays: p.plays + 1, touch: false));

  /// Copies the picture at [source] into the app's folder as [id]'s cover.
  Future<void> setCover(String id, String source) async {
    final kept = await _keepCover(source);
    forgetFile(kept);
    final old = byId(id)?.coverPath;
    await update(id, (p) => p.copyWith(coverPath: kept));
    if (old != kept) await _dropCover(old);
  }

  Future<void> clearCover(String id) async {
    final old = byId(id)?.coverPath;
    await update(id, (p) => p.copyWith(clearCover: true));
    await _dropCover(old);
  }

  Future<String> _keepCover(String source) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/playlist_covers');
    await dir.create(recursive: true);
    final ext = source.contains('.') ? source.split('.').last.toLowerCase() : 'jpg';
    final out = '${dir.path}/${_shortId()}.${ext.length > 4 ? 'jpg' : ext}';
    await File(source).copy(out);
    return out;
  }

  Future<void> _dropCover(String? path) async {
    if (path == null || !path.contains('playlist_covers')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---- liked songs -------------------------------------------------------------

  /// The id of the Liked songs playlist, made the first time something is
  /// liked.
  static const likedId = 'liked';

  Playlist? get liked => byId(likedId);
  bool isLiked(String trackKey) => liked?.tracks.any((t) => t.key == trackKey) ?? false;

  /// Likes or unlikes [t]; true when it's now liked.
  Future<bool> toggleLike(PlaylistTrack t) async {
    await ready;
    if (isLiked(t.key)) {
      await update(likedId, (p) => p.copyWith(tracks: [for (final x in p.tracks) if (x.key != t.key) x]));
      return false;
    }
    if (liked == null) {
      final now = DateTime.now();
      await _set(state.copyWith(playlists: [
        Playlist(id: likedId, name: 'Liked songs', description: 'What you hearted', emoji: '', icon: 'heart', palette: 4, pinned: true, createdAt: now, updatedAt: now),
        ...state.playlists,
      ]));
    }
    // Newest likes first.
    await update(likedId, (p) => p.copyWith(tracks: [t.fresh(), ...p.tracks]));
    unawaited(ensureArt(likedId));
    return true;
  }

  Future<void> setSort(PlaylistSort v) => _set(state.copyWith(sort: v));
  Future<void> setGrid(bool v) => _set(state.copyWith(grid: v));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
  Future<void> setDrawerOpen(bool v) => _set(state.copyWith(drawerOpen: v));

  /// Moves a playlist in "Your order" (indexes into [PlaylistsState.sorted]
  /// as shown) and switches the library to that order.
  Future<void> movePlaylist(int from, int to) async {
    final shown = state.sorted;
    if (from < 0 || from >= shown.length) return;
    final p = shown.removeAt(from);
    shown.insert(to.clamp(0, shown.length), p);
    await _set(state.copyWith(playlists: shown, sort: PlaylistSort.custom));
  }

  /// Puts the playlists in exactly [ids]' order (others after, as they
  /// were) and switches to "Your order".
  Future<void> arrange(List<String> ids) async {
    final byId = {for (final p in state.playlists) p.id: p};
    final first = [for (final id in ids) ?byId.remove(id)];
    await _set(state.copyWith(playlists: [...first, ...state.sorted.where((p) => byId.containsKey(p.id))], sort: PlaylistSort.custom));
  }

  /// Sorts a playlist's tracks for good: by title, artist, length, date
  /// added or posted, reversed, or shuffled.
  Future<void> sortTracks(String id, String by) => update(id, (p) {
    final list = [...p.tracks];
    switch (by) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'artist':
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case 'length':
        list.sort((a, b) => a.seconds.compareTo(b.seconds));
      case 'added':
        list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      case 'posted':
        list.sort((a, b) => (a.postedAt ?? a.addedAt).compareTo(b.postedAt ?? b.addedAt));
      case 'reverse':
        return p.copyWith(tracks: list.reversed.toList());
      case 'shuffle':
        list.shuffle();
    }
    return p.copyWith(tracks: list);
  });

  // ---- album art -------------------------------------------------------------

  final _artTried = <String>{};
  bool _fetching = false;

  /// Saves full-size album art for [id]'s tracks that have none yet: the
  /// album cover Telegram keeps for a song, or the picture inside a file.
  /// It is shared by every playlist with the same track, and runs in the
  /// background a few at a time.
  Future<void> ensureArt([String? id]) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final lists = id == null ? state.playlists : [?byId(id)];
      final want = <String, PlaylistTrack>{};
      for (final p in lists) {
        for (final t in p.tracks) {
          if (t.artPath == null && t.source != TrackSource.stream && !_artTried.contains(t.key)) want[t.key] = t;
        }
      }
      var done = 0;
      for (final t in want.values) {
        if (done >= 60) break;
        _artTried.add(t.key);
        final art = await _fetchArt(t);
        done++;
        if (art == null) continue;
        await _set(state.copyWith(playlists: [
          for (final p in state.playlists)
            p.tracks.any((x) => x.key == t.key)
                ? p.copyWith(touch: false, tracks: [for (final x in p.tracks) x.key == t.key ? x.copyWith(artPath: art) : x])
                : p,
        ]));
      }
    } catch (e) {
      debugPrint('[Playlists] art: $e');
    } finally {
      _fetching = false;
    }
  }

  Future<String?> _fetchArt(PlaylistTrack t) async {
    try {
      Uint8List? bytes;
      String? from;
      if (t.source == TrackSource.file && t.path != null) {
        bytes = (await readAudioTags(t.path!)).picture;
      } else if (t.source == TrackSource.telegram && t.account != null && t.chatId != null && t.messageId != null) {
        final client = ref.read(telegramClientFamily(t.account!));
        final m = await client.send<td.Message>(td.GetMessage(chatId: t.chatId!, messageId: t.messageId!), limited: true);
        final file = switch (m.content) {
          td.MessageAudio(:final audio) => bestAlbumCover(audio),
          td.MessageDocument(:final document) => document.thumbnail?.file,
          _ => null,
        };
        if (file == null) return null;
        final got = await client.send<td.File>(
          td.DownloadFile(fileId: file.id, priority: 2, offset: 0, limit: 0, synchronous: true),
          timeout: const Duration(seconds: 40),
        );
        if (got.local.isDownloadingCompleted) from = got.local.path;
      }
      if (bytes == null && from == null) return null;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/playlist_art');
      await dir.create(recursive: true);
      final out = File('${dir.path}/${t.key.hashCode.toUnsigned(32).toRadixString(16)}.jpg');
      if (bytes != null) {
        await out.writeAsBytes(bytes);
      } else {
        await File(from!).copy(out.path);
      }
      forgetFile(out.path);
      return out.path;
    } catch (e) {
      debugPrint('[Playlists] art for ${t.key}: $e');
      return null;
    }
  }

  /// The playlists [t] is in.
  List<Playlist> playlistsWith(PlaylistTrack t) => [for (final p in state.playlists) if (p.has(t)) p];

  // ---- playing ---------------------------------------------------------------

  /// [t] as something the player can play. Telegram tracks find their file
  /// only when they're about to play.
  Track trackFor(PlaylistTrack t, {String? tag}) {
    final cover = t.thumb == null ? null : td.Minithumbnail(width: 40, height: 40, data: t.thumb!);
    switch (t.source) {
      case TrackSource.file:
        return Track(
          chatId: 0,
          messageId: 0,
          localPath: t.path,
          identifier: t.key,
          title: t.title,
          subtitle: t.subtitle,
          seconds: t.seconds,
          voice: t.kind == TrackKind.voice,
          artUrl: t.artUrl,
          cover: cover,
          queueTag: tag,
          artPath: t.artPath,
          info: t.info,
        );
      case TrackSource.stream:
        return Track(
          chatId: 0,
          messageId: 0,
          identifier: t.key,
          url: t.url,
          title: t.title,
          subtitle: t.subtitle,
          seconds: t.seconds,
          voice: false,
          artUrl: t.artUrl,
          queueTag: tag,
        );
      case TrackSource.telegram:
        late final Track base;
        base = Track(
          chatId: t.chatId ?? 0,
          messageId: t.messageId ?? 0,
          identifier: t.key,
          title: t.title,
          subtitle: t.subtitle,
          seconds: t.seconds,
          voice: t.kind == TrackKind.voice,
          cover: cover,
          queueTag: tag,
          artPath: t.artPath,
          info: t.info,
          resolve: () => _resolveTelegram(t, base),
        );
        return base;
    }
  }

  List<Track> tracksFor(Playlist p) => [for (final t in p.tracks) trackFor(t, tag: p.id)];

  /// Finds the message's audio again and, for another account than the one
  /// open, downloads it through that account.
  Future<Track?> _resolveTelegram(PlaylistTrack t, Track base) async {
    final account = t.account, chatId = t.chatId, messageId = t.messageId;
    if (account == null || chatId == null || messageId == null) return null;
    final client = ref.read(telegramClientFamily(account));
    final m = await client.send<td.Message>(td.GetMessage(chatId: chatId, messageId: messageId), limited: true);
    final art = switch (m.content) {
      td.MessageAudio(:final audio) => bestAlbumCover(audio),
      _ => null,
    };
    final (file, seconds) = switch (m.content) {
      td.MessageAudio(:final audio) => (audio.audio, audio.duration),
      td.MessageVoiceNote(:final voiceNote) => (voiceNote.voice, voiceNote.duration),
      td.MessageDocument(:final document) => (document.document, 0),
      _ => (null, 0),
    };
    if (file == null) return null;
    if (account == ref.read(activeAccountIdProvider)) return base.withSource(file: file, seconds: seconds, artFile: art);
    final done = await client.send<td.File>(
      td.DownloadFile(fileId: file.id, priority: 32, offset: 0, limit: 0, synchronous: true),
      timeout: const Duration(minutes: 5),
    );
    return done.local.isDownloadingCompleted ? base.withSource(localPath: done.local.path, seconds: seconds) : null;
  }

  // ---- sharing ----------------------------------------------------------------

  /// Writes a playlist to a file others can import (in Files → Exports).
  Future<File> exportFile(String id) => exportPlaylist(ref, byId(id)!);

  /// Makes a playlist from a shared file, finding its Telegram tracks in
  /// [account] (the open one by default).
  Future<ImportResult> importFile(String path, {String? account, String? name}) =>
      importPlaylist(ref, path, account ?? ref.read(activeAccountIdProvider), name: name);

  /// Sends a playlist file to a Telegram chat.
  Future<void> sendFile(String id, int chatId, {String? account}) =>
      sendPlaylistFile(ref, byId(id)!, chatId, account ?? ref.read(activeAccountIdProvider));

  /// Forwards a playlist's songs and voice messages themselves to a chat.
  Future<int> forwardTracks(String id, int chatId, {String? account}) =>
      forwardPlaylistTracks(ref, byId(id)!, chatId, account ?? ref.read(activeAccountIdProvider));

  /// Plays [p] from the top, shuffled, or from [start].
  Future<void> play(Playlist p, {bool shuffle = false, int start = 0}) async {
    if (p.tracks.isEmpty) return;
    await ref.read(audioCenterProvider).playAll(tracksFor(p), shuffle: shuffle, start: start);
    await markPlayed(p.id);
  }
}

final playlistsProvider = NotifierProvider<PlaylistsStore, PlaylistsState>(PlaylistsStore.new);
