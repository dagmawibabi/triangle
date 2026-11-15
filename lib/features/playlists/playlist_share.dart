import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/td_compat.dart' show inputDocument;
import '../telegram/data/telegram_store.dart';
import '../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import 'playlist_sources.dart';
import 'playlists.dart';

// A playlist as a file others can import: its name, words, look (with the
// picture, shrunk) and tracks. Telegram tracks travel as message links, so
// anyone who can see the chat or channel gets the same audio; tracks from
// private chats keep their ids, which only work on the account they came
// from. Saved files travel by name and title only.

const playlistFileFormat = 'triangle.playlist';
const playlistFileSuffix = '.playlist.json';

/// Whether [name] looks like a shared playlist file.
bool isPlaylistFile(String name) => name.toLowerCase().endsWith(playlistFileSuffix);

/// Writes [p] to a file in the app's exports (it shows in Files) and
/// returns it.
Future<File> exportPlaylist(Ref ref, Playlist p) async {
  final tracks = <Map<String, dynamic>>[];
  final links = <String, String?>{};
  for (final t in p.tracks) {
    final j = <String, dynamic>{
      'title': t.title,
      if (t.artist.isNotEmpty) 'artist': t.artist,
      if (t.seconds > 0) 'seconds': t.seconds,
      'kind': t.kind.name,
      'source': t.source.name,
    };
    switch (t.source) {
      case TrackSource.telegram:
        final account = t.account, chat = t.chatId, msg = t.messageId;
        if (account != null && chat != null && msg != null) {
          final k = t.key;
          links[k] ??= await _link(ref, account, chat, msg);
          if (links[k] != null) j['link'] = links[k];
          j['chat_id'] = chat;
          j['message_id'] = msg;
          final username = _username(ref.read(telegramStoreFamily(account)), chat);
          if (username != null) j['chat_username'] = username;
        }
        if (t.chatTitle != null) j['chat'] = t.chatTitle;
        if (t.fileName != null) j['file_name'] = t.fileName;
      case TrackSource.file:
        j['file_name'] = t.fileName ?? t.path?.split(RegExp(r'[\\/]')).last;
      case TrackSource.stream:
        j['url'] = t.url;
        if (t.artUrl != null) j['art_url'] = t.artUrl;
    }
    tracks.add(j);
  }
  String? cover;
  if (p.coverPath != null && fileExists(p.coverPath!)) cover = await _shrink(p.coverPath!);
  final data = {
    'format': playlistFileFormat,
    'version': 1,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'playlist': {
      'name': p.name,
      if (p.description.isNotEmpty) 'description': p.description,
      'emoji': p.emoji,
      if (p.icon != null) 'icon': p.icon,
      'palette': p.palette,
      'collage': p.collage,
      if (cover != null) 'cover_png': cover,
    },
    'tracks': tracks,
  };
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/exports');
  await dir.create(recursive: true);
  final safe = p.name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  final file = File('${dir.path}/${safe.isEmpty ? 'playlist' : safe}$playlistFileSuffix');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  return file;
}

String? _username(TelegramStore store, int chatId) {
  final c = store.chat(chatId);
  if (c == null) return null;
  final usernames = switch (c.type) {
    td.ChatTypeSupergroup(:final supergroupId) => store.supergroups[supergroupId]?.usernames,
    td.ChatTypePrivate(:final userId) => store.users[userId]?.usernames,
    _ => null,
  };
  final u = usernames?.activeUsernames.firstOrNull;
  return u == null || u.isEmpty ? null : u;
}

Future<String?> _link(Ref ref, String account, int chatId, int messageId) async {
  try {
    final l = await ref.read(telegramClientFamily(account)).send<td.MessageLink>(
      td.GetMessageLink(chatId: chatId, messageId: messageId, mediaTimestamp: 0, checklistTaskId: 0, pollOptionId: '', forAlbum: false, inMessageThread: false),
      limited: true,
    );
    return l.link.isEmpty ? null : l.link;
  } catch (_) {
    return null;
  }
}

/// The picture at [path] at most 480 px wide, as base64 PNG.
Future<String?> _shrink(String path) async {
  try {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 480);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return png == null ? null : base64Encode(png.buffer.asUint8List());
  } catch (e) {
    debugPrint('[Playlists] cover: $e');
    return null;
  }
}

/// What an import made, and what couldn't come along.
typedef ImportResult = ({Playlist playlist, int added, List<String> unavailable});

/// Reads a shared playlist file and makes a playlist of it in [account],
/// finding each Telegram track again by its link.
Future<ImportResult> importPlaylist(Ref ref, String path, String account, {String? name}) async {
  final raw = jsonDecode(await File(path).readAsString());
  if (raw is! Map || raw['format'] != playlistFileFormat) throw const FormatException('That file is not a Triangle playlist.');
  final info = raw['playlist'] is Map ? raw['playlist'] as Map : const {};
  final client = ref.read(telegramClientFamily(account));
  final store = ref.read(telegramStoreFamily(account));
  final tracks = <PlaylistTrack>[];
  final unavailable = <String>[];
  List<PlaylistTrack>? saved;
  for (final t in (raw['tracks'] as List? ?? const [])) {
    if (t is! Map) continue;
    final title = '${t['title'] ?? 'Audio'}';
    switch ('${t['source']}') {
      case 'telegram':
        td.Message? m;
        final link = t['link'];
        if (link is String && link.isNotEmpty) {
          try {
            m = (await client.send<td.MessageLinkInfo>(td.GetMessageLinkInfo(url: link), limited: true)).message;
          } catch (_) {}
        }
        if (m == null && t['chat_id'] is num && t['message_id'] is num) {
          try {
            m = await client.send<td.Message>(td.GetMessage(chatId: (t['chat_id'] as num).toInt(), messageId: (t['message_id'] as num).toInt()), limited: true);
          } catch (_) {}
        }
        final found = m == null ? null : PlaylistTrack.fromMessage(m, store, account);
        if (found == null) {
          unavailable.add(title);
        } else {
          // Keep the sharer's title for voice messages and renamed tracks.
          tracks.add(found.copyWith(title: title));
        }
      case 'stream':
        final url = t['url'];
        if (url is String && url.startsWith('http')) {
          tracks.add(PlaylistTrack.stream(url: url, title: title, artist: '${t['artist'] ?? ''}', artUrl: t['art_url'] is String ? t['art_url'] as String : null, kind: TrackKind.named('${t['kind']}')));
        } else {
          unavailable.add(title);
        }
      default:
        final fileName = '${t['file_name'] ?? ''}';
        saved ??= await savedAudioFiles();
        final match = saved.where((x) => x.fileName == fileName || x.title == title).firstOrNull;
        match == null ? unavailable.add(title) : tracks.add(match);
    }
  }
  final playlists = ref.read(playlistsProvider.notifier);
  final p = await playlists.create(
    name ?? '${info['name'] ?? 'Imported playlist'}',
    description: '${info['description'] ?? ''}',
    emoji: '${info['emoji'] ?? '🎵'}',
    icon: info['icon'] is String ? info['icon'] as String : null,
    collage: info['collage'] != false,
    palette: (info['palette'] as num?)?.toInt(),
    tracks: tracks,
  );
  if (info['cover_png'] is String) {
    try {
      final tmp = File('${(await getTemporaryDirectory()).path}/import-${p.id}.png');
      await tmp.writeAsBytes(base64Decode(info['cover_png'] as String));
      await playlists.setCover(p.id, tmp.path);
    } catch (_) {}
  }
  return (playlist: playlists.byId(p.id)!, added: tracks.length, unavailable: unavailable);
}

/// Sends [p] as a playlist file to a Telegram chat, for others to import.
Future<void> sendPlaylistFile(Ref ref, Playlist p, int chatId, String account) async {
  final file = await exportPlaylist(ref, p);
  final runner = ref.read(toolRunnerFamily(account));
  await runner.sendAndSettle(
    td.SendMessage(
      chatId: chatId,
      inputMessageContent: td.InputMessageDocument(
        document: inputDocument(file.path, keepAsFile: true),
        caption: td.FormattedText(
          text: '🎵 ${p.name} · ${p.tracks.length} tracks\nOpen in Triangle: long-press this file → Import playlist.',
          entities: const [],
        ),
      ),
    ),
  );
}

/// Forwards [p]'s Telegram tracks (from [account]) to a chat, so anyone
/// can listen without the app. Returns how many went.
Future<int> forwardPlaylistTracks(Ref ref, Playlist p, int chatId, String account) async {
  final runner = ref.read(toolRunnerFamily(account));
  final byChat = <int, List<int>>{};
  for (final t in p.tracks) {
    if (t.source == TrackSource.telegram && t.account == account && t.chatId != null && t.messageId != null) {
      byChat.putIfAbsent(t.chatId!, () => []).add(t.messageId!);
    }
  }
  var sent = 0;
  for (final e in byChat.entries) {
    for (var i = 0; i < e.value.length; i += 100) {
      sent += await runner.forwardTo(chatId, e.key, e.value.sublist(i, (i + 100).clamp(0, e.value.length)));
    }
  }
  return sent;
}
