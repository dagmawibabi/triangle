import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pictures from the web kept on the phone: each URL is downloaded once
/// into the app's own folder and read from there afterwards, offline too.
/// The folder is trimmed to [_maxBytes], oldest first.
class ImageDiskCache {
  ImageDiskCache._();

  static const _maxBytes = 300 * 1024 * 1024;
  static Directory? _dir;
  static Future<Directory>? _opening;
  static final _inflight = <String, Future<File?>>{};

  /// URLs that failed this session, so a dead link isn't fetched on every
  /// rebuild.
  static final _failed = <String>{};
  static bool _trimmed = false;

  static String _name(String url) => md5.convert(utf8.encode(url)).toString();

  static Future<Directory> _open() => _opening ??= () async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/net_images');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    if (!_trimmed) {
      _trimmed = true;
      unawaited(_trim(d));
    }
    return d;
  }();

  /// The saved copy of [url], when there is one and the folder is open
  /// (it opens on the first [get]); null otherwise.
  static File? peek(String url) {
    final d = _dir;
    if (d == null) return null;
    final f = File('${d.path}/${_name(url)}');
    return f.existsSync() ? f : null;
  }

  /// The saved copy of [url], downloading it first when needed; null when
  /// it can't be had.
  static Future<File?> get(String url) {
    if (_failed.contains(url)) return Future.value();
    return _inflight[url] ??= _fetch(url).whenComplete(() {
      _inflight.remove(url);
    });
  }

  static Future<File?> _fetch(String url) async {
    try {
      final d = await _open();
      final f = File('${d.path}/${_name(url)}');
      if (await f.exists()) return f;
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      final type = r.headers['content-type'] ?? '';
      if (r.statusCode != 200 || r.bodyBytes.isEmpty || type.startsWith('text/') || type.contains('json')) {
        _failed.add(url);
        return null;
      }
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(r.bodyBytes, flush: true);
      await tmp.rename(f.path);
      return f;
    } catch (e) {
      debugPrint('[ImageCache] $url: $e');
      _failed.add(url);
      return null;
    }
  }

  static Future<void> _trim(Directory d) async {
    try {
      final files = <(File, FileStat)>[];
      await for (final e in d.list()) {
        if (e is File) files.add((e, await e.stat()));
      }
      var total = files.fold<int>(0, (a, x) => a + x.$2.size);
      if (total <= _maxBytes) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (f, st) in files) {
        if (total <= _maxBytes * 0.8) break;
        await f.delete();
        total -= st.size;
      }
    } catch (_) {}
  }

  /// How much the saved pictures take, in bytes.
  static Future<int> size() async {
    final d = await _open();
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) total += (await e.stat()).size;
    }
    return total;
  }

  static Future<void> clear() async {
    final d = await _open();
    await for (final e in d.list()) {
      try {
        await e.delete();
      } catch (_) {}
    }
  }
}
