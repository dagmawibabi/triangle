import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/files/generated_files.dart';
import '../settings/data/settings.dart';
import 'package:omni_ai/omni_ai.dart' show AiException, E2BClient, E2BExecution, E2BSandbox, SandboxGoneException;

import '../ai/data/ai.dart';

/// A finished run, as the chat card and the code editor show it.
class E2bRun {
  const E2bRun({
    required this.code,
    required this.language,
    required this.stdout,
    required this.stderr,
    required this.results,
    required this.images,
    this.error,
    this.count,
    this.sandboxId,
    this.ms = 0,
  });
  final String code;
  final String language;
  final String stdout;
  final String stderr;

  /// Text, Markdown, HTML or JSON results (images are in [images]).
  final List<Map<String, dynamic>> results;

  /// Charts and pictures the cell produced, saved on the phone.
  final List<String> images;
  final Map<String, dynamic>? error;
  final int? count;
  final String? sandboxId;
  final int ms;

  static String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}… [${s.length - max} more characters]';

  Map<String, dynamic> toJson() => {
    'sandbox': 'e2b',
    'code': clip(code, 20000),
    'language': language,
    if (stdout.isNotEmpty) 'stdout': clip(stdout, 12000),
    if (stderr.isNotEmpty) 'stderr': clip(stderr, 6000),
    if (results.isNotEmpty) 'results': results,
    if (error != null) 'exception': error,
    'execution_count': ?count,
    'sandbox_id': ?sandboxId,
    'ms': ms,
    if (images.isNotEmpty) ...{
      'image_path': images.first,
      'created_files': images,
      'note': 'The ${images.length == 1 ? 'chart is' : '${images.length} images are'} shown to the user; send with send_message if asked. Don\'t describe the image data.',
    },
  };
}

/// One sandbox this app started, and how it ended.
class E2bHistoryEntry {
  const E2bHistoryEntry({required this.id, required this.template, required this.started, this.ended, this.endReason, this.runs = 0, this.by = ''});
  final String id;
  final String template;
  final DateTime started;
  final DateTime? ended;

  /// "stopped", "restarted", "timed out", "stopped by the assistant"…
  final String? endReason;
  final int runs;

  /// Who started it: the assistant, the code editor or Settings.
  final String by;

  bool get live => ended == null;

  E2bHistoryEntry copyWith({DateTime? ended, String? endReason, int? runs}) => E2bHistoryEntry(
    id: id,
    template: template,
    started: started,
    ended: ended ?? this.ended,
    endReason: endReason ?? this.endReason,
    runs: runs ?? this.runs,
    by: by,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'template': template,
    'started': started.toIso8601String(),
    'ended': ?ended?.toIso8601String(),
    'reason': ?endReason,
    'runs': runs,
    'by': by,
  };

  factory E2bHistoryEntry.fromJson(Map<String, dynamic> j) => E2bHistoryEntry(
    id: '${j['id']}',
    template: '${j['template'] ?? ''}',
    started: DateTime.tryParse('${j['started']}') ?? DateTime.now(),
    ended: DateTime.tryParse('${j['ended'] ?? ''}'),
    endReason: j['reason'] as String?,
    runs: (j['runs'] as num?)?.toInt() ?? 0,
    by: '${j['by'] ?? ''}',
  );
}

/// The user's E2B sandbox. With "keep the sandbox" on, one sandbox is
/// reused until it times out, so variables, installed packages and files
/// carry over between runs (the assistant's and the code editor's);
/// otherwise each run gets a fresh sandbox that is stopped afterwards.
class E2bSession {
  E2bSession(this._ref) {
    _loadHistory();
  }
  final Ref _ref;
  E2BSandbox? _sandbox;
  DateTime? _lastUsed;

  E2BSandbox? get current => _sandbox;
  DateTime? get lastUsed => _lastUsed;

  /// Bumped whenever the live sandbox or the history changes, for screens.
  final changes = ValueNotifier<int>(0);

  /// Sandboxes this app started, newest first (the last 100).
  List<E2bHistoryEntry> history = const [];
  static const _historyKey = 'e2b_history.v1';

  /// When the kept sandbox will be stopped by E2B for being idle.
  DateTime? get expiresAt => _lastUsed?.add(Duration(minutes: _s.e2bTimeoutMinutes));

  Future<void> _loadHistory() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_historyKey);
      if (raw == null) return;
      history = [
        for (final e in jsonDecode(raw) as List) E2bHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      // A sandbox left running when the app closed has since timed out.
      history = [
        for (final e in history)
          e.live ? e.copyWith(ended: e.started.add(Duration(minutes: _s.e2bTimeoutMinutes)), endReason: 'timed out') : e,
      ];
      changes.value++;
    } catch (e) {
      debugPrint('[E2B] history: $e');
    }
  }

  Future<void> _record(E2bHistoryEntry Function(List<E2bHistoryEntry>)? add, {String? endId, String? reason, String? ranId}) async {
    var list = [...history];
    if (endId != null) {
      list = [for (final e in list) e.id == endId && e.live ? e.copyWith(ended: DateTime.now(), endReason: reason) : e];
    }
    if (ranId != null) list = [for (final e in list) e.id == ranId ? e.copyWith(runs: e.runs + 1) : e];
    if (add != null) list.insert(0, add(list));
    history = list.take(100).toList();
    changes.value++;
    try {
      await (await SharedPreferences.getInstance()).setString(_historyKey, jsonEncode([for (final e in history) e.toJson()]));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    history = [for (final e in history) if (e.live) e];
    await _record(null);
  }

  /// Who is using the sandbox, for its history entry.
  String by = 'the assistant';

  AppSettings get _s => _ref.read(settingsProvider);

  /// omni_ai's E2B client, with the key from Settings.
  E2BClient client() {
    if (!_s.hasE2bKey) throw const AiException('Add an E2B API key in Settings → Apps & web → E2B first.', provider: 'e2b');
    return _ref.read(aiProvider).e2b.client..apiKey = _s.e2bKey;
  }

  bool get _alive {
    final at = _lastUsed;
    return _sandbox != null && at != null && DateTime.now().difference(at) < Duration(minutes: _s.e2bTimeoutMinutes) - const Duration(seconds: 20);
  }

  /// The sandbox to use now, made when there is none (or it timed out).
  Future<E2BSandbox> sandbox(E2BClient c, {bool fresh = false, String? reason}) async {
    if (!fresh && _alive) {
      _lastUsed = DateTime.now();
      changes.value++;
      try {
        await c.keepAlive(_sandbox!.id, Duration(minutes: _s.e2bTimeoutMinutes));
      } catch (_) {}
      return _sandbox!;
    }
    final old = _sandbox;
    if (old != null) {
      // Timed out, or replaced: say so in the history.
      await _record(null, endId: old.id, reason: reason ?? (fresh ? 'replaced' : 'timed out'));
      if (fresh) {
        try {
          await c.kill(old.id);
        } catch (_) {}
      }
    }
    final box = _sandbox = await c.create(template: _s.e2bTemplate, timeout: Duration(minutes: _s.e2bTimeoutMinutes), internet: _s.e2bInternet);
    _lastUsed = DateTime.now();
    await _record((_) => E2bHistoryEntry(id: box.id, template: box.template, started: box.startedAt ?? DateTime.now(), by: by));
    return box;
  }

  /// Starts a sandbox now (or keeps the running one), from Settings.
  Future<E2BSandbox> start() async {
    final c = client();
    try {
      by = 'Settings';
      return await sandbox(c);
    } finally {
      by = 'the assistant';
    }
  }

  /// A clean sandbox in place of the running one.
  Future<E2BSandbox> restart() async {
    final c = client();
    try {
      by = 'Settings';
      return await sandbox(c, fresh: true, reason: 'restarted');
    } finally {
      by = 'the assistant';
    }
  }

  /// Runs code; restarts the sandbox once if it had stopped.
  Future<E2bRun> run(String code, {String language = 'python', void Function(String line, {required bool error})? onLine, Duration timeout = const Duration(seconds: 120)}) async {
    final c = client();
    final watch = Stopwatch()..start();
    var box = await sandbox(c);
    E2BExecution ex;
    try {
      ex = await c.run(box, code, language: language, onOutput: onLine, timeout: timeout);
    } on SandboxGoneException {
      box = await sandbox(c, fresh: true);
      ex = await c.run(box, code, language: language, onOutput: onLine, timeout: timeout);
    }
    await _record(null, ranId: box.id);
    final images = await _saveImages(ex);
    final run = E2bRun(
      code: code,
      language: language,
      stdout: ex.stdout.toString(),
      stderr: ex.stderr.toString(),
      results: [
        for (final r in ex.results)
          {
            for (final k in const ['text', 'markdown', 'html', 'latex', 'json'])
              if (r[k] != null) k: k == 'json' ? r[k] : E2bRun.clip('${r[k]}', 8000),
            if (r['main'] == true) 'main': true,
          },
      ]..removeWhere((r) => r.isEmpty || r.keys.every((k) => k == 'main')),
      images: images,
      error: ex.error == null
          ? null
          : {
              'name': ex.error!['name'],
              'value': ex.error!['value'],
              if (ex.error!['traceback'] != null) 'traceback': E2bRun.clip(_noAnsi('${ex.error!['traceback']}'), 6000),
            },
      count: ex.count,
      sandboxId: box.id,
      ms: watch.elapsedMilliseconds,
    );
    if (!_s.e2bKeepAlive) await stop(c, 'finished (not kept)');
    return run;
  }

  static String _noAnsi(String s) => s.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');

  Future<List<String>> _saveImages(E2BExecution ex) async {
    final out = <String>[];
    for (final r in ex.results) {
      final (b64, ext) = r['png'] is String ? ('${r['png']}', 'png') : (r['jpeg'] is String ? ('${r['jpeg']}', 'jpg') : (null, ''));
      if (b64 == null) continue;
      final f = await uniqueGeneratedFile('e2b.$ext', folder: 'sandbox');
      await f.writeAsBytes(base64Decode(b64));
      out.add(f.path);
    }
    return out;
  }

  /// Stops the kept sandbox.
  Future<void> stop([E2BClient? c, String reason = 'stopped']) async {
    final box = _sandbox;
    _sandbox = null;
    _lastUsed = null;
    if (box == null) return;
    await _record(null, endId: box.id, reason: reason);
    final client = c ?? this.client();
    try {
      await client.kill(box.id);
    } catch (_) {
      // Already gone.
    }
  }

  /// Runs [work] against the current sandbox (making one if needed).
  /// Marks [id] stopped in the history (it was stopped from elsewhere).
  Future<void> markStopped(String id, String reason) async {
    if (_sandbox?.id == id) {
      _sandbox = null;
      _lastUsed = null;
    }
    await _record(null, endId: id, reason: reason);
  }

  Future<T> withSandbox<T>(Future<T> Function(E2BClient c, E2BSandbox box) work) async {
    final c = client();
    return work(c, await sandbox(c));
  }
}

final e2bSessionProvider = Provider<E2bSession>(E2bSession.new);
