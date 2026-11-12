import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Podcasts and episodes the user starred, shown under Files → Podcasts.
@immutable
class LibraryFavorites {
  const LibraryFavorites({this.shows = const [], this.episodes = const []});

  /// Shows as podcast cards know them: id, title, author, cover, feed, url.
  final List<Map<String, dynamic>> shows;

  /// Episodes: title, audio, image, published, seconds, show, show_cover, feed.
  final List<Map<String, dynamic>> episodes;

  static String showKey(Map s) => '${s['feed'] ?? s['id'] ?? s['title']}';
  static String episodeKey(Map e) => '${e['audio'] ?? e['title']}';

  bool hasShow(Map s) => shows.any((x) => showKey(x) == showKey(s));
  bool hasEpisode(Map e) => episodes.any((x) => episodeKey(x) == episodeKey(e));
}

class LibraryFavoritesController extends Notifier<LibraryFavorites> {
  static const _key = 'library_favorites.v1';

  @override
  LibraryFavorites build() {
    _load();
    return const LibraryFavorites();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      List<Map<String, dynamic>> list(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      state = LibraryFavorites(shows: list(j['shows']), episodes: list(j['episodes']));
    } catch (e) {
      debugPrint('[Favorites] $e');
    }
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode({'shows': state.shows, 'episodes': state.episodes}));

  /// Stars [show], or unstars it; true when it is starred now.
  Future<bool> toggleShow(Map<String, dynamic> show) async {
    final k = LibraryFavorites.showKey(show);
    final on = !state.hasShow(show);
    state = LibraryFavorites(
      shows: on
          ? [
              {
                for (final f in const ['id', 'title', 'author', 'cover', 'feed', 'url', 'genre'])
                  if (show[f] != null) f: show[f],
              },
              ...state.shows,
            ]
          : state.shows.where((s) => LibraryFavorites.showKey(s) != k).toList(),
      episodes: state.episodes,
    );
    await _save();
    return on;
  }

  Future<bool> toggleEpisode(Map<String, dynamic> episode) async {
    final k = LibraryFavorites.episodeKey(episode);
    final on = !state.hasEpisode(episode);
    state = LibraryFavorites(
      shows: state.shows,
      episodes: on
          ? [
              {
                for (final f in const ['title', 'audio', 'image', 'published', 'seconds', 'show', 'show_cover', 'feed', 'description'])
                  if (episode[f] != null) f: episode[f],
              },
              ...state.episodes,
            ]
          : state.episodes.where((e) => LibraryFavorites.episodeKey(e) != k).toList(),
    );
    await _save();
    return on;
  }
}

final libraryFavoritesProvider = NotifierProvider<LibraryFavoritesController, LibraryFavorites>(LibraryFavoritesController.new);
