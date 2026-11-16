import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' show InAppWebViewController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../core/net/http_cache.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../playlists/playlists.dart' show forgetAllFiles;
import '../../podcasts/podcast_store.dart' show podcastsProvider;

/// One kind of cached thing: what it is, and how much it takes.
@immutable
class CacheKind {
  const CacheKind(this.id, this.label, this.detail, this.icon, this.color, {this.bytes = 0, this.files = 0});
  final String id;
  final String label;

  /// What it is, and what happens when it's cleared.
  final String detail;
  final IconData icon;
  final Color color;
  final int bytes;
  final int files;

  CacheKind sized(int bytes, int files) => CacheKind(id, label, detail, icon, color, bytes: bytes, files: files);
}

/// Everything the app keeps only to be faster or work offline, measured
/// and cleared by kind. Nothing here is the person's own: downloads,
/// followed shows, playlists, books and chats are never touched.
abstract final class AppCache {
  static const telegram = CacheKind('telegram', 'Telegram files', 'Photos, videos and files from chats. They download again when opened.', Icons.send_rounded, Color(0xFF8AB4FF));
  static const podcasts = CacheKind('podcasts', 'Podcasts', 'Charts, searches, feeds and shows you opened without following. Followed shows and downloaded episodes stay.', Icons.podcasts_rounded, Color(0xFFB69CFF));
  static const radio = CacheKind('radio', 'Radio', 'Station lists and countries from the radio directories.', Icons.radio_rounded, Color(0xFFF2C46D));
  static const web = CacheKind('web', 'Web pages', 'Pages, scripts and pictures from the in-app browser. Sign-ins and cookies stay.', Icons.public_rounded, Color(0xFF6FCF97));
  static const art = CacheKind('art', 'Album art', 'Covers found for playlist tracks. They\'re found again when shown.', Icons.album_outlined, Color(0xFFFF9B85));
  static const books = CacheKind('books', 'Book pages', 'Books\' text and pictures, prepared for reading. Prepared again when opened; books, notes and covers stay.', Icons.menu_book_outlined, Color(0xFF7FD6E8));
  static const images = CacheKind('images', 'Pictures in memory', 'Pictures decoded for the screen right now. Freed when the app closes anyway.', Icons.memory_rounded, Color(0xFFE88FCF));
  static const temp = CacheKind('temp', 'Temporary files', 'Leftovers from sharing, picking files, voices and imports.', Icons.auto_delete_outlined, Color(0xFFB0B6C3));

  static const kinds = [telegram, podcasts, radio, web, art, books, images, temp];

  /// Names in the cache folder that belong to a kind of their own.
  static const _ownNames = {'http', ..._webNames, 'podcast_shows.json'};

  /// Where Android's WebView keeps its cache (newer, then older versions).
  static const _webNames = ['WebView', 'org.chromium.android_webview'];

  /// The app's cache and temporary folders (one on Android, two on iOS).
  static Future<List<String>> _cacheRoots() async {
    final roots = <String>{};
    try {
      roots.add((await getApplicationCacheDirectory()).path);
    } catch (_) {}
    try {
      roots.add((await getTemporaryDirectory()).path);
    } catch (_) {}
    return roots.toList();
  }

  /// Every kind with its size, biggest first (Telegram summed over the
  /// signed-in accounts).
  static Future<List<CacheKind>> measure(Ref ref) async {
    final roots = await _cacheRoots();
    final support = (await getApplicationSupportDirectory()).path;
    final cache = roots.first;
    final http = (await HttpCache.root()).path;
    // Folder walks happen off the UI thread.
    final sizes = await Isolate.run(() => {
      'podcasts': _sizeOf(['$http/podcasts', '$cache/podcast_shows.json']),
      'radio': _sizeOf(['$http/radio']),
      'web': _sizeOf([for (final r in roots) for (final w in _webNames) '$r/$w']),
      'art': _sizeOf(['$support/playlist_art']),
      'books': _bookPages('$support/books'),
      'temp': _sizeOf(roots, skip: _ownNames),
    });
    final tg = await _telegram(ref);
    final img = PaintingBinding.instance.imageCache;
    final out = [
      telegram.sized(tg.$1, tg.$2),
      for (final k in kinds)
        if (sizes[k.id] case final s?) k.sized(s.$1, s.$2),
      images.sized(img.currentSizeBytes, img.currentSize),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return out;
  }

  static Future<(int, int)> _telegram(Ref ref) async {
    var bytes = 0, files = 0;
    for (final a in ref.read(accountsProvider).signedIn) {
      try {
        final s = await ref.read(telegramClientFamily(a.id)).send<td.StorageStatisticsFast>(const td.GetStorageStatisticsFast(), timeout: const Duration(seconds: 15));
        bytes += s.filesSize;
        files += s.fileCount;
      } catch (_) {}
    }
    return (bytes, files);
  }

  /// Clears one kind; what it freed, roughly.
  static Future<int> clear(Ref ref, String id) async {
    final roots = await _cacheRoots();
    final support = (await getApplicationSupportDirectory()).path;
    switch (id) {
      case 'telegram':
        var freed = 0;
        for (final a in ref.read(accountsProvider).signedIn) {
          try {
            final s = await ref.read(telegramClientFamily(a.id)).send<td.StorageStatistics>(
              td.OptimizeStorage(size: 0, ttl: 0, count: -1, immunityDelay: 0, fileTypes: [], chatIds: [], excludeChatIds: [], returnDeletedFileStatistics: true, chatLimit: 1),
              timeout: const Duration(minutes: 3),
            );
            freed += s.size;
          } catch (_) {}
        }
        return freed;
      case 'podcasts':
        final before = await Isolate.run(() => _sizeOf(['${roots.first}/http/podcasts', '${roots.first}/podcast_shows.json']).$1);
        await ref.read(podcastsProvider).clearCache();
        return before;
      case 'radio':
        final dir = await HttpCache.folderOf('radio');
        final before = await Isolate.run(() => _sizeOf([dir.path]).$1);
        if (HttpCache.all['radio'] case final c?) {
          await c.clear();
        } else {
          await _delete(dir);
        }
        return before;
      case 'web':
        final before = await Isolate.run(() => _sizeOf([for (final r in roots) for (final w in _webNames) '$r/$w']).$1);
        try {
          await InAppWebViewController.clearAllCache();
        } catch (_) {}
        for (final r in roots) {
          for (final w in _webNames) {
            await _delete(Directory('$r/$w'));
          }
        }
        return before;
      case 'art':
        final dir = Directory('$support/playlist_art');
        final before = await Isolate.run(() => _sizeOf([dir.path]).$1);
        await _delete(dir);
        forgetAllFiles();
        PaintingBinding.instance.imageCache.clear();
        return before;
      case 'books':
        return Isolate.run(() => _clearBookPages('$support/books'));
      case 'images':
        final c = PaintingBinding.instance.imageCache;
        final before = c.currentSizeBytes;
        c
          ..clear()
          ..clearLiveImages();
        return before;
      case 'temp':
        return Isolate.run(() => _clearTemp(roots, _ownNames));
    }
    return 0;
  }

  /// Every kind, one after another.
  static Future<int> clearAll(Ref ref) async {
    var freed = 0;
    for (final k in kinds) {
      freed += await clear(ref, k.id);
    }
    return freed;
  }

  static Future<void> _delete(FileSystemEntity e) async {
    try {
      if (await e.exists()) await e.delete(recursive: true);
    } catch (_) {}
  }
}

// ---- off the UI thread -------------------------------------------------------------

/// Bytes and files under [paths] (files or folders), leaving out direct
/// children named in [skip].
(int, int) _sizeOf(List<String> paths, {Set<String> skip = const {}}) {
  var bytes = 0, files = 0;
  void walk(FileSystemEntity e) {
    try {
      if (e is File) {
        bytes += e.lengthSync();
        files++;
      } else if (e is Directory) {
        for (final c in e.listSync(followLinks: false)) {
          walk(c);
        }
      }
    } catch (_) {}
  }

  for (final p in paths) {
    final type = FileSystemEntity.typeSync(p, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type == FileSystemEntityType.directory && skip.isNotEmpty) {
      try {
        for (final c in Directory(p).listSync(followLinks: false)) {
          if (!skip.contains(c.uri.pathSegments.where((s) => s.isNotEmpty).last)) walk(c);
        }
      } catch (_) {}
    } else {
      walk(type == FileSystemEntityType.file ? File(p) : Directory(p));
    }
  }
  return (bytes, files);
}

/// The prepared pages in each book's folder: `doc.json` and `img/`.
List<FileSystemEntity> _bookPageEntries(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return [
    for (final b in dir.listSync(followLinks: false))
      if (b is Directory) ...[File('${b.path}/doc.json'), Directory('${b.path}/img')],
  ];
}

(int, int) _bookPages(String root) => _sizeOf([for (final e in _bookPageEntries(root)) e.path]);

int _clearBookPages(String root) {
  final entries = _bookPageEntries(root);
  final before = _sizeOf([for (final e in entries) e.path]).$1;
  for (final e in entries) {
    try {
      if (e.existsSync()) e.deleteSync(recursive: true);
    } catch (_) {}
  }
  return before;
}

/// Deletes what's in [roots] except [keep]; anything touched in the last
/// ten minutes stays (it may be in use: a file being shared, a voice
/// playing).
int _clearTemp(List<String> roots, Set<String> keep) {
  final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
  var freed = 0;
  void sweep(Directory d) {
    for (final e in d.listSync(followLinks: false)) {
      try {
        if (e is File) {
          final st = e.statSync();
          if (st.modified.isAfter(cutoff)) continue;
          e.deleteSync();
          freed += st.size;
        } else if (e is Directory) {
          sweep(e);
          if (e.listSync().isEmpty) e.deleteSync();
        }
      } catch (_) {}
    }
  }

  for (final r in roots) {
    final dir = Directory(r);
    if (!dir.existsSync()) continue;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (keep.contains(e.uri.pathSegments.where((s) => s.isNotEmpty).last)) continue;
        if (e is Directory) {
          sweep(e);
          try {
            if (e.listSync().isEmpty) e.deleteSync();
          } catch (_) {}
        } else if (e is File) {
          final st = e.statSync();
          if (st.modified.isAfter(cutoff)) continue;
          e.deleteSync();
          freed += st.size;
        }
      }
    } catch (_) {}
  }
  return freed;
}

/// [AppCache] with the app's providers at hand.
final appCacheProvider = Provider<AppCacheActions>(AppCacheActions.new);

class AppCacheActions {
  AppCacheActions(this._ref);
  final Ref _ref;

  Future<List<CacheKind>> measure() => AppCache.measure(_ref);
  Future<int> clear(String id) => AppCache.clear(_ref, id);
  Future<int> clearAll() => AppCache.clearAll(_ref);
}
