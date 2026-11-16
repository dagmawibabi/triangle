import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A response [HttpCache] kept: its text, when it was last confirmed, and
/// what the server said to ask about it next time.
class CachedBody {
  const CachedBody(this.body, this.at, {this.etag, this.lastModified});
  final String body;
  final DateTime at;
  final String? etag;
  final String? lastModified;

  bool freshFor(Duration ttl) => DateTime.now().difference(at) < ttl;
}

/// What [HttpCache.get] answered with. [changed] is false when the text is
/// the same as the copy kept before (served from the copy, or the server
/// said "not modified"), so callers can skip re-parsing it.
typedef CacheResult = ({String body, bool changed});

/// GET requests kept on disk (the app's cache folder, which the system may
/// clear), so lists and feeds open instantly after a restart and work
/// offline. Past their time to live they're checked with the server using
/// ETag / Last-Modified, so an unchanged feed isn't downloaded again.
class HttpCache {
  HttpCache(this.name, {this.maxEntries = 400, this.memoryEntries = 40}) {
    all[name] = this;
  }

  /// Every cache made, by [name] (Settings → Cache clears them).
  static final Map<String, HttpCache> all = {};

  /// The folder every [HttpCache] keeps its copies under.
  static Future<Directory> root() async => Directory('${(await getApplicationCacheDirectory()).path}/http');

  /// [name]'s folder, made or not.
  static Future<Directory> folderOf(String name) async => Directory('${(await root()).path}/$name');

  /// Forgets every copy kept, in memory and on disk.
  Future<void> clear() async {
    _memory.clear();
    try {
      final dir = await folderOf(name);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[HttpCache:$name] clear: $e');
    }
    _dir = null;
  }

  /// The folder under `<cache>/http/`.
  final String name;
  final int maxEntries;
  final int memoryEntries;

  /// Whether the last request couldn't reach the server.
  bool offline = false;

  final LinkedHashMap<String, CachedBody> _memory = LinkedHashMap();
  final Map<String, Future<CacheResult?>> _inFlight = {};
  Future<Directory>? _dir;
  int _writes = 0;

  Future<Directory> _folder() => _dir ??= folderOf(name).then((d) => d.create(recursive: true));

  static String _hash(String key) => sha1.convert(utf8.encode(key)).toString();

  void _remember(String key, CachedBody b) {
    _memory.remove(key);
    _memory[key] = b;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// The copy kept for [key] (the URL unless given), however old.
  Future<CachedBody?> peek(String key) async {
    final m = _memory[key];
    if (m != null) return m;
    try {
      final dir = await _folder();
      final h = _hash(key);
      final meta = File('${dir.path}/$h.meta');
      final body = File('${dir.path}/$h.body');
      if (!await meta.exists() || !await body.exists()) return null;
      final j = jsonDecode(await meta.readAsString());
      if (j is! Map || j['k'] != key) return null;
      final b = CachedBody(
        await body.readAsString(),
        DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        etag: j['e'] as String?,
        lastModified: j['l'] as String?,
      );
      _remember(key, b);
      return b;
    } catch (e) {
      debugPrint('[HttpCache:$name] read: $e');
      return null;
    }
  }

  Future<void> _save(String key, CachedBody b, {required bool body}) async {
    _remember(key, b);
    try {
      final dir = await _folder();
      final h = _hash(key);
      if (body) await File('${dir.path}/$h.body').writeAsString(b.body);
      await File('${dir.path}/$h.meta').writeAsString(jsonEncode({
        'k': key,
        't': b.at.millisecondsSinceEpoch,
        if (b.etag != null) 'e': b.etag,
        if (b.lastModified != null) 'l': b.lastModified,
      }));
      if (++_writes % 25 == 0) unawaited(_prune());
    } catch (e) {
      debugPrint('[HttpCache:$name] write: $e');
    }
  }

  /// Keeps the newest [maxEntries].
  Future<void> _prune() async {
    try {
      final dir = await _folder();
      final metas = <(File, DateTime)>[];
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.meta')) metas.add((e, (await e.stat()).modified));
      }
      if (metas.length <= maxEntries) return;
      metas.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (f, _) in metas.skip(maxEntries)) {
        final base = f.path.substring(0, f.path.length - 5);
        await f.delete().catchError((_) => f);
        final body = File('$base.body');
        await body.delete().catchError((_) => body);
      }
    } catch (_) {}
  }

  /// [url]'s text. A copy younger than [ttl] is used as is. With
  /// [staleFirst], an older copy is returned at once and refreshed in the
  /// background for next time (for lists, where a little stale beats a
  /// wait). [force] always asks the server (still conditionally). When the
  /// server can't be reached, the copy is returned whatever its age; null
  /// only when there is none. [key] names the copy when the URL varies
  /// (mirrors of one API).
  Future<CacheResult?> get(
    String url, {
    required Duration ttl,
    Duration timeout = const Duration(seconds: 20),
    Map<String, String> headers = const {},
    String? key,
    bool force = false,
    bool staleFirst = false,
    bool okOnly = false,
  }) async {
    final k = key ?? url;
    final hit = await peek(k);
    if (!force && hit != null) {
      if (hit.freshFor(ttl)) return (body: hit.body, changed: false);
      if (staleFirst) {
        unawaited(_fetch(url, k, hit, headers, timeout, okOnly));
        return (body: hit.body, changed: false);
      }
    }
    return _fetch(url, k, hit, headers, timeout, okOnly);
  }

  // The block body in whenComplete matters: `() => _inFlight.remove(key)`
  // returns this very future, and whenComplete waits on a returned future,
  // so every request that reached the network would never finish.
  Future<CacheResult?> _fetch(String url, String key, CachedBody? hit, Map<String, String> headers, Duration timeout, bool okOnly) =>
      _inFlight[key] ??= _request(url, key, hit, headers, timeout, okOnly).whenComplete(() {
        _inFlight.remove(key);
      });

  Future<CacheResult?> _request(String url, String key, CachedBody? hit, Map<String, String> headers, Duration timeout, bool okOnly) async {
    final fallback = okOnly || hit == null ? null : (body: hit.body, changed: false);
    // Two tries: a dropped connection or a slow first byte is common on phones.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _send(url, {
          ...headers,
          if (hit?.etag != null) 'If-None-Match': hit!.etag!,
          if (hit?.lastModified != null) 'If-Modified-Since': hit!.lastModified!,
        }, timeout);
        offline = false;
        if (r.status == 304 && hit != null) {
          await _save(key, CachedBody(hit.body, DateTime.now(), etag: r.headers['etag'] ?? hit.etag, lastModified: r.headers['last-modified'] ?? hit.lastModified), body: false);
          return (body: hit.body, changed: false);
        }
        // A server error may pass; anything else is a real answer.
        if (r.status >= 500 && attempt == 0) continue;
        if (r.status != 200) return fallback;
        final body = utf8.decode(r.bytes, allowMalformed: true);
        final changed = hit == null || hit.body != body;
        await _save(key, CachedBody(body, DateTime.now(), etag: r.headers['etag'], lastModified: r.headers['last-modified']), body: changed);
        return (body: body, changed: changed);
      } catch (e) {
        debugPrint('[HttpCache:$name] $url: $e');
      }
    }
    offline = true;
    return fallback;
  }

  /// [timeout] is how long the server may go quiet (before answering, or
  /// between chunks), not a cap on the whole download: a long-running
  /// show's feed can be many megabytes on a slow connection.
  static Future<({int status, Map<String, String> headers, Uint8List bytes})> _send(String url, Map<String, String> headers, Duration timeout) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
      final res = await client.send(req).timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.stream.timeout(timeout)) {
        bytes.add(chunk);
      }
      return (status: res.statusCode, headers: res.headers, bytes: bytes.takeBytes());
    } finally {
      client.close();
    }
  }
}
