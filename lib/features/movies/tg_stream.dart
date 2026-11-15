import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/telegram_client.dart';

/// Streams Telegram videos to the player, the way Telegram's own player
/// does: a small HTTP server on this phone (127.0.0.1 only) answers the
/// player's byte-range requests, asking TDLib for just those parts of the
/// file as they're needed. Playback starts in seconds and seeking jumps
/// ahead without downloading what's skipped.
class TgStream {
  TgStream(this._client);
  final TelegramClient _client;
  HttpServer? _server;
  final _files = <int, ({int size, String mime})>{};
  static const _chunk = 512 * 1024;

  /// A link the player can open for [file].
  Future<Uri> url(td.File file, {String mime = 'video/mp4'}) async {
    final s = _server ??= await _start();
    _files[file.id] = (size: file.size > 0 ? file.size : file.expectedSize, mime: mime);
    return Uri.parse('http://127.0.0.1:${s.port}/f/${file.id}');
  }

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) => unawaited(_serve(r)));
    return s;
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final id = int.tryParse(req.uri.pathSegments.lastOrNull ?? '');
      final info = id == null ? null : _files[id];
      if (id == null || info == null || info.size <= 0) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final size = info.size;
      var start = 0;
      var end = size - 1;
      final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        if (range.group(1)!.isNotEmpty) start = int.parse(range.group(1)!);
        if (range.group(2)!.isNotEmpty) end = int.parse(range.group(2)!).clamp(0, size - 1);
        if (range.group(1)!.isEmpty && range.group(2)!.isNotEmpty) {
          // "bytes=-500": the last 500 bytes.
          start = (size - int.parse(range.group(2)!)).clamp(0, size - 1);
          end = size - 1;
        }
      }
      if (start >= size) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await res.close();
        return;
      }
      res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
      res.headers
        ..contentType = ContentType.parse(info.mime)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      var pos = start;
      while (pos <= end) {
        final want = (end - pos + 1).clamp(1, _chunk);
        // Has TDLib fetch this part (it keeps what's fetched), then reads it.
        await _client.send<td.File>(
          td.DownloadFile(fileId: id, priority: 32, offset: pos, limit: want, synchronous: true),
          timeout: const Duration(minutes: 2),
        );
        final part = await _client.send<td.Data>(td.ReadFilePart(fileId: id, offset: pos, count: want), timeout: const Duration(seconds: 30));
        final bytes = base64Decode(part.data);
        if (bytes.isEmpty) break;
        res.add(bytes);
        await res.flush();
        pos += bytes.length;
      }
      await res.close();
    } catch (e) {
      // The player hung up (a seek, or the page closed).
      debugPrint('[Stream] $e');
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

final tgStreamFamily = Provider.family<TgStream, String>((ref, account) {
  final s = TgStream(ref.watch(telegramClientFamily(account)));
  ref.onDispose(s.close);
  return s;
});
