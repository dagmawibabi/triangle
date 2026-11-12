import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The zone key the chat sets to the running tool call's id, so a download
/// started inside that call reports its progress to that call's card.
const toolCallZoneKey = #triangleToolCallId;

/// Runs [body] tagged with the tool call [callId].
Future<T> runForToolCall<T>(String callId, Future<T> Function() body) => runZoned(body, zoneValues: {toolCallZoneKey: callId});

/// Thrown out of a transfer the person cancelled.
class TransferCancelled implements Exception {
  const TransferCancelled();
  @override
  String toString() => 'Cancelled';
}

/// One transfer's progress: what, how much of how much, how fast.
@immutable
class DownloadState {
  const DownloadState({
    required this.name,
    required this.received,
    required this.startedAt,
    this.total,
    this.url,
    this.done = false,
    this.error,
    this.path,
    this.bytesPerSecond = 0,
    this.paused = false,
    this.cancelled = false,
    this.upload = false,
    this.canPause = false,
    this.canCancel = false,
    this.files = 1,
  });

  final String name;
  final int received;

  /// Null when the server didn't say how big the file is.
  final int? total;
  final String? url;
  final DateTime startedAt;
  final bool done;
  final String? error;
  final String? path;
  final double bytesPerSecond;
  final bool paused;
  final bool cancelled;

  /// Sending to Telegram rather than downloading.
  final bool upload;
  final bool canPause;
  final bool canCancel;

  /// How many files the transfer covers (an upload of several).
  final int files;

  bool get active => !done && error == null && !cancelled;

  double? get fraction => total == null || total! <= 0 ? null : (received / total!).clamp(0.0, 1.0);

  /// Seconds left at the current speed, when the size is known.
  int? get secondsLeft {
    if (total == null || bytesPerSecond <= 0 || paused) return null;
    return ((total! - received) / bytesPerSecond).ceil().clamp(0, 1 << 30);
  }

  Duration get elapsed => DateTime.now().difference(startedAt);
}

/// Live transfers by tool call id. Cards listen to [all] and drive them
/// with [of]: pause, resume, cancel. Entries stay a while after finishing
/// so the card can show the final size.
class DownloadProgress {
  DownloadProgress._(this._id, this._state);

  static final all = ValueNotifier<Map<String, DownloadState>>(const {});
  static final _live = <String, DownloadProgress>{};

  /// The transfer running for the tool call [callId], if any.
  static DownloadProgress? of(String callId) => _live[callId];

  final String _id;
  DownloadState _state;
  DateTime _tick = DateTime.now();
  int _tickBytes = 0;
  StreamSubscription<List<int>>? _sub;
  Completer<void>? _piped;
  Future<void> Function()? _onCancel;

  /// Starts tracking a download for the current tool call; null outside one.
  static DownloadProgress? start(String name, {String? url, int? total}) => _begin(DownloadState(
    name: name,
    received: 0,
    total: total != null && total > 0 ? total : null,
    url: url,
    startedAt: DateTime.now(),
    canPause: true,
    canCancel: true,
  ));

  /// Starts tracking an upload of [files] files ([total] bytes) for the
  /// current tool call; [onCancel] stops it. Null outside a tool call.
  static DownloadProgress? startUpload(String name, {required int total, int files = 1, Future<void> Function()? onCancel}) {
    final p = _begin(DownloadState(
      name: name,
      received: 0,
      total: total > 0 ? total : null,
      startedAt: DateTime.now(),
      upload: true,
      files: files,
      canCancel: onCancel != null,
    ));
    p?._onCancel = onCancel;
    return p;
  }

  static DownloadProgress? _begin(DownloadState state) {
    final id = Zone.current[toolCallZoneKey];
    if (id is! String) return null;
    final p = DownloadProgress._(id, state);
    _live[id] = p;
    p._publish();
    return p;
  }

  /// Copies [source] into [sink], counting it, and letting the card pause,
  /// resume or cancel it. A cancel throws [TransferCancelled].
  Future<void> pipe(Stream<List<int>> source, IOSink sink) {
    final done = _piped = Completer<void>();
    _sub = source.listen(
      (chunk) {
        sink.add(chunk);
        add(chunk.length);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  void pause() {
    if (!_state.canPause || !_state.active || _state.paused) return;
    _sub?.pause();
    _state = _copy(paused: true, speed: 0);
    _publish();
  }

  void resume() {
    if (!_state.paused) return;
    _sub?.resume();
    _tick = DateTime.now();
    _tickBytes = 0;
    _state = _copy(paused: false);
    _publish();
  }

  Future<void> cancel() async {
    if (!_state.active) return;
    _state = _copy(cancelled: true, paused: false, speed: 0);
    _publish();
    _forgetLater();
    await _sub?.cancel();
    final piped = _piped;
    if (piped != null && !piped.isCompleted) piped.completeError(const TransferCancelled());
    await _onCancel?.call();
  }

  /// Stops whatever is running for [callId], when its tool is stopped.
  static Future<void> cancelFor(String callId) async {
    final p = _live[callId];
    if (p != null && p._state.active) await p.cancel();
  }

  void add(int bytes) => _update(_state.received + bytes);

  /// Sets how much is done so far (an upload's progress, which Telegram
  /// reports as totals).
  void set(int received, {int? total}) => _update(received, total: total);

  void _update(int received, {int? total}) {
    if (!_state.active) return;
    _tickBytes += received - _state.received;
    final now = DateTime.now();
    final ms = now.difference(_tick).inMilliseconds;
    // Publish at most about ten times a second, with a smoothed speed.
    if (ms < 100) {
      _state = _copy(received: received, total: total);
      return;
    }
    final instant = _tickBytes * 1000 / ms;
    final speed = _state.bytesPerSecond == 0 ? instant : _state.bytesPerSecond * 0.7 + instant * 0.3;
    _tick = now;
    _tickBytes = 0;
    _state = _copy(received: received, total: total, speed: speed);
    _publish();
  }

  void finish(String path) {
    if (_state.cancelled) return;
    _state = _copy(done: true, path: path, total: _state.total ?? _state.received, received: _state.total ?? _state.received, paused: false);
    _publish();
    _forgetLater();
  }

  void fail(String error) {
    if (_state.cancelled) return;
    _state = _copy(error: error, paused: false);
    _publish();
    _forgetLater();
  }

  DownloadState _copy({int? received, double? speed, bool? done, String? path, String? error, int? total, bool? paused, bool? cancelled}) => DownloadState(
    name: _state.name,
    received: received ?? _state.received,
    total: total ?? _state.total,
    url: _state.url,
    startedAt: _state.startedAt,
    done: done ?? _state.done,
    error: error ?? _state.error,
    path: path ?? _state.path,
    bytesPerSecond: speed ?? _state.bytesPerSecond,
    paused: paused ?? _state.paused,
    cancelled: cancelled ?? _state.cancelled,
    upload: _state.upload,
    canPause: _state.canPause,
    canCancel: _state.canCancel,
    files: _state.files,
  );

  void _publish() => all.value = {...all.value, _id: _state};

  void _forgetLater() {
    if (_live[_id] == this) _live.remove(_id);
    final last = _state;
    Timer(const Duration(minutes: 2), () {
      if (all.value[_id] == last) all.value = {...all.value}..remove(_id);
    });
  }
}

/// "4.2 MB", "820 KB".
String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

/// "12 s", "3 min 20 s".
String formatSeconds(int s) {
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')} s';
  return '${s ~/ 3600} h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')} min';
}
