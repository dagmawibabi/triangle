import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';

/// Downloads Telegram files and keeps track of the ones already on the
/// phone.
///
/// TDLib keeps every downloaded file in its files folder (the file database
/// is on), so a photo or song fetched once opens instantly afterwards, even
/// offline. Message objects carry a file's state as of when they were
/// fetched, so this also follows `updateFile` to know about files finished
/// since, and remembers each finished path for the session.
class FileLoader {
  FileLoader(this._client) {
    _sub = _client.updates.listen((u) {
      if (u is! td.UpdateFile) return;
      final f = u.file;
      _latest[f.id] = f;
      final total = f.size > 0 ? f.size : f.expectedSize;
      if (total > 0) _progress[f.id]?.value = (f.local.downloadedSize / total).clamp(0, 1).toDouble();
      if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
        _paths[f.id] = f.local.path;
        _progress[f.id]?.value = 1;
        _waiters.remove(f.id)?.complete(f.local.path);
      }
    });
  }

  final TelegramClient _client;
  late final StreamSubscription<td.TdObject> _sub;
  final Map<int, td.File> _latest = {};
  final Map<int, String> _paths = {};
  final Map<int, Completer<String?>> _waiters = {};
  final Map<int, ValueNotifier<double>> _progress = {};

  /// The local path when the file is fully on the phone.
  String? cachedPath(td.File? file) {
    if (file == null) return null;
    final known = _paths[file.id];
    if (known != null) return known;
    final f = _latest[file.id] ?? file;
    if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty && File(f.local.path).existsSync()) {
      return _paths[file.id] = f.local.path;
    }
    return null;
  }

  /// 0..1 while downloading.
  ValueListenable<double> progress(td.File file) =>
      _progress.putIfAbsent(file.id, () => ValueNotifier(cachedPath(file) != null ? 1 : 0));

  bool isDownloading(td.File file) => _waiters.containsKey(file.id);

  /// Downloads [file] (once) and returns its local path. [priority] 1..32;
  /// what the person tapped goes ahead of background thumbnails.
  Future<String?> download(td.File file, {int priority = 8}) {
    final cached = cachedPath(file);
    if (cached != null) return Future.value(cached);
    final waiting = _waiters[file.id];
    if (waiting != null) return waiting.future;
    final c = _waiters[file.id] = Completer<String?>();
    progress(file);
    unawaited(() async {
      try {
        final f = await _client.send<td.File>(
          td.DownloadFile(fileId: file.id, priority: priority, offset: 0, limit: 0, synchronous: false),
        );
        _latest[f.id] = f;
        if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
          _paths[f.id] = f.local.path;
          _progress[f.id]?.value = 1;
          _waiters.remove(f.id)?.complete(f.local.path);
        }
      } catch (e) {
        debugPrint('[Files] ${file.id}: $e');
        _waiters.remove(file.id)?.complete(null);
      }
    }());
    return c.future;
  }

  /// Downloads paused by the person (the part already fetched is kept).
  final paused = ValueNotifier<Set<int>>(const {});
  bool isPaused(td.File file) => paused.value.contains(file.id);

  /// Stops [file]'s download but keeps what's fetched; [resume] carries on.
  Future<void> pause(td.File file) async {
    paused.value = {...paused.value, file.id};
    try {
      await _client.send<td.Ok>(td.CancelDownloadFile(fileId: file.id, onlyIfPending: false));
    } catch (_) {}
    _waiters.remove(file.id)?.complete(null);
  }

  /// Carries on a paused (or stopped) download from where it was.
  Future<String?> resume(td.File file, {int priority = 32}) {
    paused.value = {...paused.value}..remove(file.id);
    return download(file, priority: priority);
  }

  /// Stops [file]'s download; with [delete], the part fetched goes too.
  Future<void> cancel(td.File file, {bool delete = false}) async {
    paused.value = {...paused.value}..remove(file.id);
    try {
      await _client.send<td.Ok>(td.CancelDownloadFile(fileId: file.id, onlyIfPending: false));
      if (delete) await _client.send<td.Ok>(td.DeleteFile(fileId: file.id));
    } catch (_) {}
    _waiters.remove(file.id)?.complete(null);
    _progress[file.id]?.value = 0;
  }

  void dispose() => _sub.cancel();
}

/// Each account's loader. TDLib file ids belong to one instance: the same
/// number names a different file (or none) in another account, so a file
/// must be fetched through the account its message came from.
final fileLoaderFamily = Provider.family<FileLoader, String>((ref, account) {
  final loader = FileLoader(ref.watch(telegramClientFamily(account)));
  ref.onDispose(loader.dispose);
  return loader;
});

/// The loader of the account on screen.
final fileLoaderProvider = Provider<FileLoader>(
  (ref) => ref.watch(fileLoaderFamily(ref.watch(activeAccountIdProvider))),
);

/// [account]'s loader, or the one on screen when it isn't known.
FileLoader fileLoaderFor(WidgetRef ref, String? account) =>
    ref.read(account == null ? fileLoaderProvider : fileLoaderFamily(account));

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
