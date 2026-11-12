import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../assistant/activity_log.dart';
import '../assistant/notifications.dart';
import '../assistant/untrusted.dart';
import '../assistant/watches.dart';
import '../chat/data/chat_controller.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_tools.dart';
import '../vault/vault.dart';
import '../voice/speaker.dart';
import 'routines.dart';

/// Runs routines: by hand, on their schedule (the watch engine's clock calls
/// [tick]) and on phone events (the engine calls [fireDevice]).
class RoutineRunner {
  RoutineRunner(this._ref);
  final Ref _ref;

  /// Routines running now, by id; [progress] says which step.
  final Set<String> _running = {};
  final ValueNotifier<Map<String, int>> progress = ValueNotifier(const {});
  final Set<String> _stopping = {};

  bool isRunning(String id) => _running.contains(id);

  void stop(String id) => _stopping.add(id);

  /// Every scheduled routine that is due now starts.
  void tick(DateTime now) {
    if (!_ref.read(settingsProvider).proactive) return;
    for (final r in _ref.read(routineStoreProvider)) {
      if (!r.enabled || _running.contains(r.id) || r.steps.isEmpty) continue;
      final t = r.trigger;
      var due = false;
      switch (t.kind) {
        case RoutineTriggerKind.daily:
          if (!t.days.contains(now.weekday)) break;
          final p = t.at.split(':');
          final at = DateTime(now.year, now.month, now.day, int.tryParse(p.first) ?? 8, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
          due = !now.isBefore(at) && (r.lastRunAt == null || r.lastRunAt!.isBefore(at)) && now.difference(at).inHours < 2;
        case RoutineTriggerKind.interval:
          if (t.quietAtNight && Watch.isNight(now)) break;
          due = r.lastRunAt == null || now.difference(r.lastRunAt!).inMinutes >= t.everyMinutes;
        case RoutineTriggerKind.manual || RoutineTriggerKind.device:
          break;
      }
      if (due) unawaited(run(r, trigger: t.describe()));
    }
  }

  /// A phone event for a routine with a device trigger.
  void fireDevice(String routineId, String event) {
    final r = _ref.read(routineStoreProvider.notifier).byId(routineId);
    if (r == null || !r.enabled || !_ref.read(settingsProvider).proactive) return;
    unawaited(run(r, trigger: event));
  }

  /// Fills `{{last}}`, `{{step2}}`, `{{trigger}}`, `{{date}}`, `{{time}}`
  /// and `{{vault:Label}}` in [text].
  static String fill(String text, {required String last, required List<String> outputs, required String trigger, List<({String label, String value})> vault = const []}) {
    final now = DateTime.now();
    return text.replaceAllMapped(RegExp(r'\{\{\s*([^}]+?)\s*\}\}'), (m) {
      final key = m[1]!;
      final lower = key.toLowerCase();
      if (lower == 'last') return last;
      if (lower == 'trigger') return trigger;
      if (lower == 'date') return DateFormat('EEEE d MMMM y').format(now);
      if (lower == 'time') return DateFormat.Hm().format(now);
      final step = RegExp(r'^step\s*(\d+)$').firstMatch(lower);
      if (step != null) {
        final i = int.parse(step[1]!) - 1;
        return i >= 0 && i < outputs.length ? outputs[i] : '';
      }
      if (lower.startsWith('vault:')) {
        final want = key.substring(6).trim().toLowerCase();
        return vault.where((v) => v.label.toLowerCase() == want).firstOrNull?.value ??
            vault.where((v) => v.label.toLowerCase().contains(want)).firstOrNull?.value ??
            '';
      }
      return m[0]!;
    });
  }

  /// Tool inputs with their text filled and turned into the types the
  /// tool's schema asks for ("12" for an integer becomes 12).
  static Map<String, dynamic> coerceArgs(String tool, Map<String, dynamic> args, String Function(String) fill) {
    final props = (toolNamed(tool)?.parameters['properties'] as Map?) ?? const {};
    final out = <String, dynamic>{};
    for (final e in args.entries) {
      var v = e.value;
      if (v is String) v = fill(v);
      final type = (props[e.key] as Map?)?['type'];
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) continue;
        switch (type) {
          case 'integer':
            v = int.tryParse(s) ?? num.tryParse(s)?.toInt() ?? v;
          case 'number':
            v = num.tryParse(s) ?? v;
          case 'boolean':
            v = s.toLowerCase() == 'true' ? true : (s.toLowerCase() == 'false' ? false : v);
          case 'array' || 'object':
            try {
              v = jsonDecode(s);
            } catch (_) {
              // A list typed as "a, b": its items.
              if (type == 'array') v = [for (final x in s.split(',')) if (x.trim().isNotEmpty) x.trim()];
            }
        }
      }
      out[e.key] = v;
    }
    return out;
  }

  static String _clip(String s, [int max = 4000]) => s.length <= max ? s : '${s.substring(0, max)}…';

  /// A tool result as text for the next step: its main text field when it
  /// has one, else the JSON.
  static String resultText(Map<String, dynamic> j) {
    for (final k in const ['text', 'result', 'answer', 'summary', 'message', 'output', 'stdout']) {
      final v = j[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return jsonEncode(j);
  }

  /// Runs [r] from its first step; returns what each step did.
  Future<RoutineRun> run(Routine r, {String trigger = 'Run by hand'}) async {
    if (_running.contains(r.id)) {
      return RoutineRun(at: DateTime.now(), trigger: trigger, ok: false, steps: const [], error: 'Already running.');
    }
    _running.add(r.id);
    _stopping.remove(r.id);
    final began = DateTime.now();
    final results = <StepResult>[];
    final outputs = <String>[];
    var last = '';
    var lastOk = true;
    var notified = false;
    var stoppedEarly = false;
    String? error;
    final controller = _ref.read(chatControllerProvider.notifier);
    await _ref.read(vaultProvider.notifier).ready;
    final vault = [for (final v in _ref.read(vaultProvider)) (label: v.label, value: v.value)];
    String fillIn(String s) => fill(s, last: last, outputs: outputs, trigger: trigger, vault: vault);
    var conversationId = r.conversationId;
    final steps = r.steps.where((s) => s.enabled).toList();
    try {
      var skip = false;
      for (final (i, s) in steps.indexed) {
        if (_stopping.contains(r.id)) {
          error = 'Stopped.';
          break;
        }
        progress.value = {...progress.value, r.id: i};
        final label = '${i + 1}. ${s.kind.label}';
        if (skip) {
          skip = false;
          results.add(StepResult(stepId: s.id, label: label, ok: true, skipped: true));
          outputs.add('');
          continue;
        }
        final clock = Stopwatch()..start();
        var ok = true;
        var out = '';
        try {
          switch (s.kind) {
            case RoutineStepKind.ask:
              final asked = fillIn(s.prompt);
              final job = Watch(
                id: r.runId,
                name: r.name,
                scope: WatchScope.schedule,
                mode: WatchMode.act,
                instructions: r.description,
                conversationId: conversationId,
                createdAt: r.createdAt,
                tools: r.tools,
                model: r.model,
              );
              final previous = last.trim().isEmpty ? '' : '\n\nThe previous step\'s result:\n${fence(_clip(last), 'previous routine step')}';
              final result = await controller.runAutomatic(
                job,
                'Routine "${r.name}" (started by: $trigger), step ${i + 1} of ${steps.length}. Do this: $asked$previous\n'
                'Answer with the result only; it is passed to the next step.',
              );
              if (result == null) {
                ok = false;
                out = 'No AI key: add one in Settings.';
              } else {
                conversationId = result.conversationId;
                out = result.text;
                ok = !out.startsWith('Something went wrong') && out.trim().isNotEmpty;
              }
            case RoutineStepKind.tool:
              if (s.tool.isEmpty) throw StateError('No tool picked.');
              final args = coerceArgs(s.tool, s.args, fillIn);
              final res = await controller.runRoutineTool(s.tool, args, routine: r);
              ok = !res.containsKey('error');
              out = ok ? resultText(res) : '${res['error']}';
            case RoutineStepKind.notify:
              final title = fillIn(s.title).trim();
              final body = fillIn(s.body.isEmpty ? '{{last}}' : s.body).trim();
              final text = Speaker.clean(body);
              await _ref.read(appNotifierProvider).show(
                title.isEmpty ? r.name : title,
                text.isEmpty ? 'Done.' : _clip(text, 600),
                conversationId: conversationId,
              );
              notified = true;
              out = body;
            case RoutineStepKind.wait:
              final end = DateTime.now().add(Duration(seconds: s.seconds));
              while (DateTime.now().isBefore(end) && !_stopping.contains(r.id)) {
                await Future<void>.delayed(const Duration(seconds: 1));
              }
              out = last;
            case RoutineStepKind.condition:
              final v = s.value.trim().toLowerCase();
              final passed = switch (s.test) {
                ConditionTest.contains => last.toLowerCase().contains(v),
                ConditionTest.notContains => !last.toLowerCase().contains(v),
                ConditionTest.isEmpty => last.trim().isEmpty,
                ConditionTest.notEmpty => last.trim().isNotEmpty,
                ConditionTest.succeeded => lastOk,
                ConditionTest.failed => !lastOk,
              };
              out = last;
              results.add(StepResult(stepId: s.id, label: label, ok: true, output: passed ? 'Passed' : 'Not met: ${s.otherwise.label.toLowerCase()}', ms: clock.elapsedMilliseconds));
              outputs.add(last);
              if (!passed) {
                if (s.otherwise == ConditionOtherwise.stop) {
                  stoppedEarly = true;
                  break;
                }
                skip = true;
              }
              continue;
          }
        } catch (e) {
          ok = false;
          out = e is StateError ? e.message : '$e';
        }
        results.add(StepResult(stepId: s.id, label: label, ok: ok, output: _clip(out), ms: clock.elapsedMilliseconds));
        outputs.add(out);
        if (s.kind != RoutineStepKind.wait) {
          last = out;
          lastOk = ok;
        }
        if (!ok && !s.continueOnError) {
          error = 'Step ${i + 1} failed: ${_clip(out, 200)}';
          break;
        }
      }
      if (stoppedEarly) {
        // Ended by a condition: nothing else to say.
      } else if (error == null && r.notifyWhenDone && !notified && steps.isNotEmpty && _ref.read(settingsProvider).notifications) {
        final text = Speaker.clean(last);
        await _ref.read(appNotifierProvider).show(r.name, text.isEmpty ? 'Done.' : _clip(text, 400), conversationId: conversationId);
      } else if (error != null && error != 'Stopped.' && _ref.read(settingsProvider).notifications) {
        await _ref.read(appNotifierProvider).show('Routine failed · ${r.name}', error, conversationId: conversationId);
      }
    } finally {
      _running.remove(r.id);
      _stopping.remove(r.id);
      progress.value = {...progress.value}..remove(r.id);
    }
    final run = RoutineRun(at: DateTime.now(), trigger: trigger, ok: error == null, steps: results, stoppedEarly: stoppedEarly, error: error);
    unawaited(
      _ref.read(activityLogProvider.notifier).recordRun(
        source: ActivitySource.routine,
        name: r.name,
        ok: error == null,
        text: error ?? (stoppedEarly ? 'Stopped by a condition.' : last),
        conversationId: conversationId,
        trigger: trigger,
        durationMs: DateTime.now().difference(began).inMilliseconds,
        details: {
          'steps': [for (final st in results) '${st.label}: ${st.skipped ? 'skipped' : st.ok ? 'ok' : 'failed'}'],
        },
      ),
    );
    final store = _ref.read(routineStoreProvider.notifier);
    if (conversationId != null && conversationId != r.conversationId) {
      await store.update(r.id, (x) => x.copyWith(conversationId: conversationId));
    }
    await store.recordRun(r.id, run);
    return run;
  }
}

final routineRunnerProvider = Provider<RoutineRunner>((ref) => RoutineRunner(ref));
