import 'dart:convert';
import 'dart:io';

import 'package:handy_tdlib/api.dart' as td;

import '../../core/files/app_files.dart';
import '../../infrastructure/telegram/telegram_client.dart';
import '../telegram/data/telegram_store.dart';
import 'playlists.dart';

/// Which Telegram audio to look for.
enum TgAudioType {
  music('Music'),
  voice('Voice'),
  files('Audio files');

  const TgAudioType(this.label);
  final String label;

  td.SearchMessagesFilter get filter => switch (this) {
    music => const td.SearchMessagesFilterAudio(),
    voice => const td.SearchMessagesFilterVoiceNote(),
    files => const td.SearchMessagesFilterDocument(),
  };

  static TgAudioType? named(String n) => switch (n.trim().toLowerCase()) {
    'music' || 'songs' || 'song' || 'audio' => music,
    'voice' || 'voice_messages' || 'voice_notes' => voice,
    'files' || 'audio_files' || 'documents' => files,
    _ => null,
  };
}

/// One page of Telegram audio, as playlist tracks.
typedef AudioPage = ({List<PlaylistTrack> tracks, String next, int total});

/// Songs, voice messages or audio files sent as documents: in one chat when
/// [chatId] is given, else across every chat. [next] continues a search.
/// Documents that aren't audio are dropped, so a page of "files" can come
/// back short; [next] is empty once there are no more.
Future<AudioPage> searchTelegramAudio(
  TelegramClient client,
  TelegramStore store,
  String account, {
  required TgAudioType type,
  int? chatId,
  String query = '',
  String next = '',
  int limit = 40,
}) async {
  final out = <PlaylistTrack>[];
  var offset = next;
  var total = 0;
  // Documents are mostly not audio: read a few pages to fill one.
  for (var round = 0; round < (type == TgAudioType.files ? 4 : 1); round++) {
    List<td.Message> messages;
    if (chatId != null) {
      final r = await client.send<td.FoundChatMessages>(
        td.SearchChatMessages(
          chatId: chatId,
          query: query,
          senderId: null,
          fromMessageId: int.tryParse(offset) ?? 0,
          offset: 0,
          limit: limit,
          filter: type.filter,
          topicId: null,
        ),
        limited: true,
      );
      messages = r.messages;
      total = r.totalCount;
      offset = r.nextFromMessageId == 0 || r.messages.isEmpty ? '' : '${r.nextFromMessageId}';
    } else {
      final r = await client.send<td.FoundMessages>(
        td.SearchMessages(
          chatList: null,
          chatTypeFilter: null,
          query: query,
          offset: offset,
          limit: limit,
          filter: type.filter,
          minDate: 0,
          maxDate: 0,
        ),
        limited: true,
      );
      messages = r.messages;
      total = r.totalCount;
      offset = r.messages.isEmpty ? '' : r.nextOffset;
    }
    for (final m in messages) {
      final t = PlaylistTrack.fromMessage(m, store, account);
      if (t != null) out.add(t);
    }
    if (offset.isEmpty || out.length >= limit ~/ 2) break;
  }
  return (tracks: out, next: offset, total: total);
}

/// The audio files the app saved (the Files page): music, podcasts,
/// audiobook chapters, voice clips and generated audio, newest first.
Future<List<PlaylistTrack>> savedAudioFiles({String query = ''}) async {
  final files = await listAppFiles();
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <PlaylistTrack>[];
  for (final f in files) {
    if (f.kind != 'audio' && !isAudioName(f.name)) continue;
    var meta = const <String, dynamic>{};
    final dot = f.path.lastIndexOf('.');
    final side = File('${dot < 0 ? f.path : f.path.substring(0, dot)}.meta.json');
    if (await side.exists()) {
      try {
        final j = jsonDecode(await side.readAsString());
        if (j is Map) meta = Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    final t = PlaylistTrack.fromFile(f.path, meta: meta);
    final hay = '${t.title} ${t.artist} ${f.name}'.toLowerCase();
    if (words.every(hay.contains)) out.add(t);
  }
  return out;
}
