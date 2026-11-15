import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/chat/data/tool_loading.dart';
import 'package:teleai/features/playlists/playlists.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

PlaylistTrack tg(int chat, int msg, {String title = 'Song'}) => PlaylistTrack(
  id: 'x$chat$msg',
  source: TrackSource.telegram,
  title: title,
  account: 'main',
  chatId: chat,
  messageId: msg,
  kind: TrackKind.music,
  seconds: 200,
  addedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a track survives JSON and keeps its key', () {
    final t = tg(5, 9, title: 'Tizita');
    final back = PlaylistTrack.fromJson(t.toJson());
    expect(back.key, 'tg:main:5:9');
    expect(back.title, 'Tizita');
    expect(back.kind, TrackKind.music);
    expect(back.seconds, 200);
  });

  test('files take their title and kind from the sidecar', () {
    final t = PlaylistTrack.fromFile('/x/downloads/ep-12.mp3', meta: {'title': 'Episode 12', 'library': 'podcast', 'subtitle': 'Some show'});
    expect(t.title, 'Episode 12');
    expect(t.kind, TrackKind.podcast);
    expect(t.subtitle, 'Some show');
    expect(t.key, 'file:/x/downloads/ep-12.mp3');
  });

  test('guesses podcasts and audiobooks from names and length', () {
    expect(guessKind('Chapter 3', 0), TrackKind.audiobook);
    expect(guessKind('Episode 41 — guests', 0), TrackKind.podcast);
    expect(guessKind('Long talk', 40 * 60), TrackKind.podcast);
    expect(guessKind('A song', 180, music: true), TrackKind.music);
    expect(isAudioName('talk.OPUS'), isTrue);
    expect(isAudioName('notes.pdf'), isFalse);
    expect(isAudioName('blob', 'audio/mpeg'), isTrue);
  });

  test('the store adds without duplicates, reorders, removes and persists', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(playlistsProvider.notifier);
    await store.ready;
    final p = await store.create('Road trip', tracks: [tg(1, 1), tg(1, 1)]);
    expect(store.byId(p.id)!.tracks, hasLength(1));
    expect(await store.addTracks(p.id, [tg(1, 1), tg(1, 2), tg(2, 3)]), 2);
    var now = store.byId(p.id)!;
    expect(now.tracks.map((t) => t.messageId), [1, 2, 3]);
    await store.moveTrack(p.id, 2, 0);
    now = store.byId(p.id)!;
    expect(now.tracks.map((t) => t.messageId), [3, 1, 2]);
    await store.removeTracks(p.id, [now.tracks.first.id]);
    expect(store.byId(p.id)!.tracks.map((t) => t.messageId), [1, 2]);
    expect(store.find('road')!.id, p.id);
    expect(store.playlistsWith(tg(1, 2)).single.id, p.id);

    // A fresh container reads what was saved.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final again = c2.read(playlistsProvider.notifier);
    await again.ready;
    expect(again.byId(p.id)!.name, 'Road trip');
    expect(again.byId(p.id)!.tracks, hasLength(2));
  });

  test('pinned playlists sort first', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(playlistsProvider.notifier);
    await store.ready;
    await store.create('B');
    final a = await store.create('A');
    await store.setSort(PlaylistSort.name);
    await store.setPinned(a.id, false);
    final z = await store.create('Z');
    await store.setPinned(z.id, true);
    expect(c.read(playlistsProvider).sorted.map((p) => p.name), ['Z', 'A', 'B']);
  });

  test('the playlist tools are registered and load when playlists come up', () {
    final names = {for (final t in telegramTools) if (t.category == ToolCategory.playlists) t.name};
    expect(names, {
      'list_playlists', 'playlist_tracks', 'find_audio', 'create_playlist', 'update_playlist', 'play_playlist', 'delete_playlist',
      'arrange_playlists', 'duplicate_playlist', 'share_playlist', 'import_playlist', 'like_tracks', 'music_stats', 'player_control',
    });
    expect(toolNamed('delete_playlist')!.destructive, isTrue);
    expect(toolNamed('find_audio')!.modifiesData, isFalse);
    expect(categoriesMentioned('Make a playlist of the songs in my Saved Messages'), contains(ToolCategory.playlists));
  });
}
