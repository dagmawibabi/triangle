import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../media/audio_center.dart';
import '../media/music_stats.dart';
import '../telegram/data/telegram_store.dart';
import 'playlist_share.dart';
import 'playlist_sources.dart';
import 'playlists.dart';

/// The assistant's playlist and player tools. [account] is the Telegram
/// account the call is for; Telegram tracks are kept with it.
Future<Map<String, dynamic>> runPlaylistTool(Ref ref, String name, Map<String, dynamic> a, String account) async {
  try {
    return await _runPlaylistTool(ref, name, a, account);
  } catch (e) {
    return {'error': '$e'};
  }
}

/// A picture for a cover: a file on the phone, or an https link fetched
/// to a temporary file.
Future<String?> _coverSource(String v) async {
  if (v.isEmpty) return null;
  if (v.startsWith('http')) {
    final r = await http.get(Uri.parse(v)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw 'Couldn\'t fetch the cover picture (HTTP ${r.statusCode}).';
    final f = File('${(await getTemporaryDirectory()).path}/cover-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await f.writeAsBytes(r.bodyBytes);
    return f.path;
  }
  if (!await File(v).exists()) throw 'No picture at $v.';
  return v;
}

Future<Map<String, dynamic>> _runPlaylistTool(Ref ref, String name, Map<String, dynamic> a, String account) async {
  final store = ref.read(playlistsProvider.notifier);
  await store.ready;
  String str(String k) => '${a[k] ?? ''}'.trim();
  int? integer(String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(str(k));
  bool? boolean(String k) => a[k] is bool ? a[k] as bool : (str(k) == 'true' ? true : (str(k) == 'false' ? false : null));
  List<int> ints(String k) => [for (final v in (a[k] as List? ?? const [])) if (v is num) v.toInt() else if (int.tryParse('$v') case final i?) i];
  List<String> strs(String k) => [for (final v in (a[k] as List? ?? const [])) if ('$v'.trim().isNotEmpty) '$v'.trim()];

  Playlist? playlist() => store.find(str('playlist'));
  String missing() {
    final names = ref.read(playlistsProvider).playlists.map((p) => p.name).join(', ');
    return 'No playlist "${str('playlist')}".${names.isEmpty ? ' There are none yet; create_playlist makes one.' : ' Playlists: $names'}';
  }

  /// The tracks a create or update call names, and what couldn't be added.
  Future<({List<PlaylistTrack> tracks, List<int> notAudio, List<String> notFound, String? error})> gather() async {
    final tracks = <PlaylistTrack>[];
    final notAudio = <int>[];
    final notFound = <String>[];
    final chatId = integer('chat_id');
    final messageIds = ints('message_ids');
    final wholeChat = integer('whole_chat_id');
    final paths = strs('file_paths');
    final client = ref.read(telegramClientFamily(account));
    final tg = ref.read(telegramStoreFamily(account));
    if (messageIds.isNotEmpty) {
      if (chatId == null) return (tracks: tracks, notAudio: notAudio, notFound: notFound, error: 'Give chat_id with message_ids.');
      for (var i = 0; i < messageIds.length; i += 100) {
        final batch = messageIds.sublist(i, (i + 100).clamp(0, messageIds.length));
        final r = await client.send<td.Messages>(td.GetMessages(chatId: chatId, messageIds: batch), limited: true);
        final got = {for (final m in r.messages) m.id: m};
        for (final id in batch) {
          final m = got[id];
          if (m == null) {
            notFound.add('$chatId/$id');
            continue;
          }
          final t = PlaylistTrack.fromMessage(m, tg, account);
          t == null ? notAudio.add(id) : tracks.add(t);
        }
      }
    }
    if (wholeChat != null) {
      final type = TgAudioType.named(str('whole_chat_type')) ?? TgAudioType.music;
      final max = (integer('max_tracks') ?? 100).clamp(1, 300);
      var next = '';
      final found = <PlaylistTrack>[];
      do {
        final page = await searchTelegramAudio(client, tg, account, type: type, chatId: wholeChat, next: next, limit: 50);
        found.addAll(page.tracks);
        next = page.next;
      } while (next.isNotEmpty && found.length < max);
      // Oldest first, the order they were posted in, unless asked otherwise.
      final taken = found.take(max).toList();
      tracks.addAll(str('order') == 'newest_first' ? taken : taken.reversed);
    }
    for (final p in paths) {
      final f = File(p);
      if (!await f.exists()) {
        notFound.add(p);
      } else if (!isAudioName(p)) {
        notFound.add('$p (not audio)');
      } else {
        final saved = (await savedAudioFiles()).where((t) => t.path == p).firstOrNull;
        tracks.add(saved ?? PlaylistTrack.fromFile(p));
      }
    }
    return (tracks: tracks, notAudio: notAudio, notFound: notFound, error: null);
  }

  /// The look a create or update call asks for, applied to [id].
  Future<void> applyLook(String id) async {
    final icon = str('icon');
    final emoji = str('emoji');
    final colour = integer('colour');
    final cover = str('cover');
    final pinned = boolean('pinned');
    await store.update(id, (p) {
      var x = p;
      if (boolean('no_mark') == true) {
        x = x.copyWith(emoji: '', clearIcon: true);
      } else if (icon.isNotEmpty && playlistIcons.containsKey(icon)) {
        x = x.copyWith(icon: icon);
      } else if (emoji.isNotEmpty) {
        x = x.copyWith(emoji: emoji, clearIcon: true);
      }
      if (colour != null) x = x.copyWith(palette: colour.clamp(0, playlistPalettes.length - 1));
      if (cover == 'collage') x = x.copyWith(collage: true);
      if (cover == 'colour') x = x.copyWith(collage: false);
      if (pinned != null) x = x.copyWith(pinned: pinned, touch: false);
      return x;
    });
    if (boolean('remove_cover_image') == true) await store.clearCover(id);
    final pic = await _coverSource(str('cover_image'));
    if (pic != null) await store.setCover(id, pic);
  }

  switch (name) {
    case 'list_playlists':
      final lists = ref.read(playlistsProvider).sorted;
      return {
        'playlists': [
          for (final p in lists)
            {
              ...p.describe(),
              if (a['with_tracks'] == true) 'tracks': [for (final t in p.tracks.take(200)) t.describe()],
            },
        ],
        'sort': ref.read(playlistsProvider).sort.name,
        'view': ref.read(playlistsProvider).grid ? 'grid' : 'list',
        'in_drawer': ref.read(playlistsProvider).inDrawer,
        if (lists.isEmpty) 'note': 'No playlists yet; create_playlist makes one.',
      };

    case 'playlist_tracks':
      final p = playlist();
      if (p == null) return {'error': missing()};
      return {
        'playlist': p.describe(),
        'tracks': [for (final t in p.tracks.take(300)) t.describe()..['liked'] = store.isLiked(t.key)],
        if (p.tracks.length > 300) 'note': 'Showing the first 300 of ${p.tracks.length}.',
      };

    case 'find_audio':
      final limit = (integer('limit') ?? 30).clamp(1, 100);
      final q = str('query');
      if (str('source') == 'files') {
        final all = await savedAudioFiles(query: q);
        return {
          'source': 'files',
          'results': [for (final t in all.take(limit)) t.describe()..remove('track_id')],
          'total': all.length,
          if (all.isEmpty) 'note': 'No saved audio${q.isEmpty ? '' : ' matching "$q"'}.',
        };
      }
      final type = TgAudioType.named(str('type').isEmpty ? 'music' : str('type'));
      if (type == null) return {'error': 'type is music, voice or files.'};
      final tg = ref.read(telegramStoreFamily(account));
      final r = await searchTelegramAudio(
        ref.read(telegramClientFamily(account)),
        tg,
        account,
        type: type,
        chatId: integer('chat_id'),
        query: q,
        next: str('next'),
        limit: limit,
      );
      return {
        'source': 'telegram',
        'type': type.name,
        'results': [for (final t in r.tracks) t.describe()..remove('track_id')..remove('source')],
        'total': r.total,
        if (r.next.isNotEmpty) 'next': r.next,
        if (r.tracks.isEmpty) 'note': 'Nothing found. Try another type, other words, or a chat_id of a channel that posts audio.',
      };

    case 'create_playlist':
      if (str('name').isEmpty) return {'error': 'Give the playlist a name.'};
      final g = await gather();
      if (g.error != null) return {'error': g.error};
      final p = await store.create(
        str('name'),
        description: str('description'),
        emoji: boolean('no_mark') == true ? '' : (str('emoji').isEmpty ? '🎵' : str('emoji')),
        icon: str('icon').isEmpty ? null : str('icon'),
        collage: str('cover') != 'colour',
        palette: integer('colour'),
        tracks: g.tracks,
      );
      await applyLook(p.id);
      return {
        'created': store.byId(p.id)!.describe(),
        if (g.tracks.isNotEmpty) 'added': g.tracks.length,
        if (g.notAudio.isNotEmpty) 'not_audio': g.notAudio,
        if (g.notFound.isNotEmpty) 'not_found': g.notFound,
      };

    case 'update_playlist':
      final p = playlist();
      if (p == null) return {'error': missing()};
      final g = await gather();
      if (g.error != null) return {'error': g.error};
      await store.update(p.id, (x) => x.copyWith(
        name: str('name').isEmpty ? null : str('name'),
        description: a.containsKey('description') ? str('description') : null,
      ));
      await applyLook(p.id);
      final added = g.tracks.isEmpty ? 0 : await store.addTracks(p.id, g.tracks);
      final drop = strs('remove_track_ids');
      final removed = [for (final t in p.tracks) if (drop.contains(t.id)) t.title];
      if (drop.isNotEmpty) await store.removeTracks(p.id, drop);
      final move = str('move_track_id');
      if (move.isNotEmpty) {
        final now = store.byId(p.id)!;
        final from = now.tracks.indexWhere((t) => t.id == move);
        if (from < 0) return {'error': 'No track $move in ${p.name}.'};
        await store.moveTrack(p.id, from, ((integer('move_to') ?? 1) - 1).clamp(0, now.tracks.length - 1));
      }
      final order = strs('track_order');
      if (order.isNotEmpty) {
        final now = store.byId(p.id)!;
        final byId = {for (final t in now.tracks) t.id: t};
        final first = [for (final id in order) ?byId.remove(id)];
        await store.setTracks(p.id, [...first, ...now.tracks.where((t) => byId.containsKey(t.id))]);
      }
      final sort = str('sort_tracks');
      if (sort.isNotEmpty) await store.sortTracks(p.id, sort);
      final rename = a['rename_tracks'];
      if (rename is Map) {
        for (final e in rename.entries) {
          await store.renameTrack(p.id, '${e.key}', '${e.value}');
        }
      }
      return {
        'updated': store.byId(p.id)!.describe(),
        if (g.tracks.isNotEmpty) 'added': added,
        if (g.tracks.length > added) 'already_there': g.tracks.length - added,
        if (removed.isNotEmpty) 'removed': removed,
        if (sort.isNotEmpty) 'sorted': sort,
        if (g.notAudio.isNotEmpty) 'not_audio': g.notAudio,
        if (g.notFound.isNotEmpty) 'not_found': g.notFound,
      };

    case 'play_playlist':
      final p = playlist();
      if (p == null) return {'error': missing()};
      if (p.tracks.isEmpty) return {'error': '${p.name} is empty.'};
      final startId = str('start_track_id');
      final start = startId.isEmpty ? 0 : p.tracks.indexWhere((t) => t.id == startId);
      if (start < 0) return {'error': 'No track $startId in ${p.name}.'};
      final shuffle = a['shuffle'] == true;
      await store.play(p, shuffle: shuffle && startId.isEmpty, start: start);
      return {
        'playing': true,
        'playlist': p.name,
        if (!shuffle) 'first_track': p.tracks[start].title,
        if (shuffle) 'shuffle': true,
      };

    case 'arrange_playlists':
      final order = strs('order');
      final unknown = <String>[];
      if (order.isNotEmpty) {
        final ids = <String>[];
        for (final o in order) {
          final p = store.find(o);
          p == null ? unknown.add(o) : ids.add(p.id);
        }
        await store.arrange(ids);
      }
      final sort = PlaylistSort.values.asNameMap()[str('sort')];
      if (sort != null) await store.setSort(sort);
      if (str('view') == 'grid' || str('view') == 'list') await store.setGrid(str('view') == 'grid');
      final drawer = boolean('show_in_drawer');
      if (drawer != null) await store.setInDrawer(drawer);
      final s = ref.read(playlistsProvider);
      return {
        'playlists': [for (final p in s.sorted) {'playlist_id': p.id, 'name': p.name, 'track_count': p.tracks.length, if (p.pinned) 'pinned': true}],
        'sort': s.sort.name,
        'view': s.grid ? 'grid' : 'list',
        'show_in_drawer': s.inDrawer,
        if (unknown.isNotEmpty) 'unknown': unknown,
      };

    case 'duplicate_playlist':
      final p = playlist();
      if (p == null) return {'error': missing()};
      final c = await store.duplicate(p.id);
      if (c == null) return {'error': 'Couldn\'t copy ${p.name}.'};
      if (str('name').isNotEmpty) await store.update(c.id, (x) => x.copyWith(name: str('name')));
      return {'created': store.byId(c.id)!.describe()};

    case 'share_playlist':
      final p = playlist();
      if (p == null) return {'error': missing()};
      final mode = str('mode').isEmpty ? 'file' : str('mode');
      if (mode == 'save') {
        final f = await store.exportFile(p.id);
        return {'file_path': f.path, 'saved': true};
      }
      var chat = integer('chat_id');
      if (str('to') == 'saved_messages' || (chat == null && mode == 'file')) {
        final me = await ref.read(telegramClientFamily(account)).send<td.User>(const td.GetMe());
        chat = (await ref.read(telegramClientFamily(account)).send<td.Chat>(td.CreatePrivateChat(userId: me.id, force: false))).id;
      }
      if (chat == null) return {'error': 'Give chat_id (or to: saved_messages).'};
      if (mode == 'forward') {
        final n = await store.forwardTracks(p.id, chat, account: account);
        return {'forwarded': n, 'chat_id': chat};
      }
      await store.sendFile(p.id, chat, account: account);
      return {'sent': true, 'chat_id': chat};

    case 'import_playlist':
      var path = str('file_path');
      if (path.isEmpty) {
        final chat = integer('chat_id'), msg = integer('message_id');
        if (chat == null || msg == null) return {'error': 'Give file_path, or chat_id and message_id of the playlist file.'};
        final client = ref.read(telegramClientFamily(account));
        final m = await client.send<td.Message>(td.GetMessage(chatId: chat, messageId: msg), limited: true);
        final doc = m.content is td.MessageDocument ? (m.content as td.MessageDocument).document : null;
        if (doc == null || !isPlaylistFile(doc.fileName) && !doc.fileName.endsWith('.json')) return {'error': 'That message has no playlist file.'};
        final got = await client.send<td.File>(
          td.DownloadFile(fileId: doc.document.id, priority: 32, offset: 0, limit: 0, synchronous: true),
          timeout: const Duration(minutes: 2),
        );
        if (!got.local.isDownloadingCompleted) return {'error': 'Couldn\'t download the playlist file.'};
        path = got.local.path;
      }
      final r = await store.importFile(path, account: account, name: str('name').isEmpty ? null : str('name'));
      return {
        'imported': {'playlist_id': r.playlist.id, 'name': r.playlist.name, 'track_count': r.playlist.tracks.length},
        'added': r.added,
        if (r.unavailable.isNotEmpty) 'unavailable': r.unavailable,
      };

    case 'delete_playlist':
      final p = playlist();
      if (p == null) return {'error': missing()};
      await store.delete(p.id);
      return {'deleted': true, 'name': p.name};

    case 'like_tracks':
      final unlike = a['unlike'] == true;
      final done = <String>[];
      // Tracks from a playlist by id, Telegram messages, or what's playing.
      final picks = <PlaylistTrack>[];
      final p = str('playlist').isEmpty ? null : playlist();
      for (final id in strs('track_ids')) {
        final t = p?.tracks.where((x) => x.id == id).firstOrNull;
        if (t != null) picks.add(t);
      }
      if (ints('message_ids').isNotEmpty) {
        final g = await gather();
        picks.addAll(g.tracks);
      }
      if (a['now_playing'] == true || (picks.isEmpty && strs('track_ids').isEmpty && ints('message_ids').isEmpty)) {
        final cur = ref.read(audioCenterProvider).current;
        if (cur == null) return {'error': 'Nothing is playing; give track_ids (with playlist) or chat_id + message_ids.'};
        picks.add(PlaylistTrack.fromTrack(cur, account));
      }
      for (final t in picks) {
        if (store.isLiked(t.key) == unlike) {
          await store.toggleLike(t);
          done.add(t.title);
        }
      }
      return {unlike ? 'unliked' : 'liked': done, 'liked_count': store.liked?.tracks.length ?? 0};

    case 'music_stats':
      final stats = ref.read(musicStatsProvider.notifier);
      await stats.ready;
      final s = ref.read(musicStatsProvider);
      final limit = (integer('limit') ?? 10).clamp(1, 50);
      final lists = ref.read(playlistsProvider).playlists;
      return {
        'minutes_listened': (s.totalSeconds / 60).round(),
        'plays': s.totalPlays,
        'tracks_heard': s.tracks.length,
        'day_streak': s.streak,
        'last_14_days_minutes': {
          for (var i = 13; i >= 0; i--)
            () {
              final d = DateTime.now().subtract(Duration(days: i));
              return MusicStatsState.dayKey(d);
            }(): ((s.days[MusicStatsState.dayKey(DateTime.now().subtract(Duration(days: i)))] ?? 0) / 60).round(),
        },
        'top_tracks': [for (final t in s.top.take(limit)) t.describe()],
        'top_artists': [for (final x in s.artists.take(limit)) {'artist': x.$1, 'plays': x.$2, 'minutes': (x.$3 / 60).round()}],
        'top_playlists': [
          for (final e in (s.playlistPlays.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(limit))
            if (lists.where((p) => p.id == e.key).firstOrNull case final p?) {'name': p.name, 'plays': e.value},
        ],
        'recent': [for (final t in s.recent.take(limit)) t.describe()],
      };

    case 'player_control':
      final au = ref.read(audioCenterProvider);
      final action = str('action');
      switch (action) {
        case 'pause':
          if (au.playing) await au.toggle();
        case 'resume' || 'play':
          if (!au.playing && au.current != null) await au.toggle();
        case 'next':
          await au.next();
        case 'previous':
          await au.previous();
        case 'stop':
          await au.stop();
        case 'seek':
          await au.seek(Duration(seconds: integer('seconds') ?? 0));
        case 'skip':
          await au.skip(integer('seconds') ?? 10);
        case 'shuffle':
          au.setShuffle(boolean('on') ?? !au.shuffle);
        case 'repeat':
          final want = str('mode');
          final target = AudioRepeat.values.asNameMap()[want];
          if (target == null) return {'error': 'mode is off, all or one.'};
          while (au.repeat != target) {
            au.cycleRepeat();
          }
        case 'speed':
          final v = (a['speed'] as num?)?.toDouble() ?? 1;
          await au.setSpeed(v.clamp(0.5, 3));
        case 'sleep':
          final m = integer('minutes');
          if (a['end_of_track'] == true) {
            au.setSleep(null, endOfTrack: true);
          } else {
            au.setSleep(m == null || m <= 0 ? null : Duration(minutes: m));
          }
        case 'status' || '':
          break;
        default:
          return {'error': 'Unknown action $action.'};
      }
      final cur = au.current;
      return {
        'playing': au.playing,
        if (cur != null) 'track': {'title': cur.title, 'subtitle': cur.subtitle, 'position_seconds': au.position.inSeconds, 'length_seconds': au.duration.inSeconds},
        if (cur?.queueTag != null) 'playlist': store.byId(cur!.queueTag!)?.name,
        'queue_length': au.queue.length,
        'up_next': [for (final t in au.upNext.take(5)) t.title],
        'shuffle': au.shuffle,
        'repeat': au.repeat.name,
        'speed': au.speed,
        if (au.sleepAt != null) 'sleep_at': au.sleepAt!.toIso8601String().substring(11, 16),
        if (au.sleepAtEnd) 'sleep_at_end_of_track': true,
      };
  }
  return {'error': 'Unknown tool $name.'};
}
