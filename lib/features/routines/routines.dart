import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../assistant/device_events.dart';
import '../assistant/tool_allowlist.dart';
import '../assistant/watches.dart' show WatchModel;

/// What starts a routine.
enum RoutineTriggerKind {
  manual('Only when I run it', Icons.touch_app_outlined),
  daily('At a time of day', Icons.schedule_rounded),
  interval('Every so often', Icons.repeat_rounded),
  device('On the phone', Icons.phone_android_rounded);

  const RoutineTriggerKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

@immutable
class RoutineTrigger {
  const RoutineTrigger({
    this.kind = RoutineTriggerKind.manual,
    this.at = '08:00',
    this.days = const {1, 2, 3, 4, 5, 6, 7},
    this.everyMinutes = 60,
    this.device,
    this.quietAtNight = false,
  });

  final RoutineTriggerKind kind;

  /// For daily: "HH:MM" local time, on [days] (1 Monday … 7 Sunday).
  final String at;
  final Set<int> days;

  /// For interval.
  final int everyMinutes;

  /// For device.
  final DeviceCondition? device;

  /// Interval runs skip 22:00 to 08:00.
  final bool quietAtNight;

  RoutineTrigger copyWith({
    RoutineTriggerKind? kind,
    String? at,
    Set<int>? days,
    int? everyMinutes,
    DeviceCondition? device,
    bool? quietAtNight,
  }) => RoutineTrigger(
    kind: kind ?? this.kind,
    at: at ?? this.at,
    days: days ?? this.days,
    everyMinutes: everyMinutes ?? this.everyMinutes,
    device: device ?? this.device,
    quietAtNight: quietAtNight ?? this.quietAtNight,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (kind == RoutineTriggerKind.daily) 'at': at,
    if (kind == RoutineTriggerKind.daily) 'days': (days.toList()..sort()),
    if (kind == RoutineTriggerKind.interval) 'every_minutes': everyMinutes,
    if (device != null) 'device': device!.toJson(),
    if (quietAtNight) 'quiet_at_night': true,
  };

  factory RoutineTrigger.fromJson(Object? j) {
    if (j is! Map) return const RoutineTrigger();
    final days = {for (final d in (j['days'] as List? ?? const [])) if (d is num && d >= 1 && d <= 7) d.toInt()};
    return RoutineTrigger(
      kind: RoutineTriggerKind.values.asNameMap()['${j['kind']}'] ?? RoutineTriggerKind.manual,
      at: _hhmm('${j['at'] ?? '08:00'}') ?? '08:00',
      days: days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : days,
      everyMinutes: (j['every_minutes'] as num?)?.toInt().clamp(15, 7 * 24 * 60) ?? 60,
      device: DeviceCondition.fromJson(j['device']),
      quietAtNight: j['quiet_at_night'] == true,
    );
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String describe() => switch (kind) {
    RoutineTriggerKind.manual => 'Run by hand',
    RoutineTriggerKind.daily =>
      days.length == 7
          ? 'Every day at $at'
          : (days.length == 5 && !days.contains(6) && !days.contains(7))
          ? 'Weekdays at $at'
          : (days.length == 2 && days.containsAll({6, 7}))
          ? 'Weekends at $at'
          : '${(days.toList()..sort()).map((d) => _dayNames[d - 1]).join(', ')} at $at',
    RoutineTriggerKind.interval =>
      'Every ${everyMinutes < 60 ? '$everyMinutes min' : everyMinutes % 60 == 0 ? '${everyMinutes ~/ 60} h' : '$everyMinutes min'}${quietAtNight ? ', not at night' : ''}',
    RoutineTriggerKind.device => device?.describe() ?? 'A phone event',
  };
}

String? _hhmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// The kinds of step a routine is made of.
enum RoutineStepKind {
  ask('Ask the assistant', Icons.auto_awesome_outlined, 'The assistant follows an instruction and may use tools'),
  tool('Run a tool', Icons.handyman_outlined, 'Run one tool with the inputs you set, no AI'),
  notify('Notify me', Icons.notifications_none_rounded, 'Show a phone notification'),
  wait('Wait', Icons.hourglass_empty_rounded, 'Pause before the next step'),
  condition('Only continue if…', Icons.call_split_rounded, 'Check the last step\'s result and stop or skip');

  const RoutineStepKind(this.label, this.icon, this.explanation);
  final String label;
  final IconData icon;
  final String explanation;
}

/// How a condition step tests the previous step's output.
enum ConditionTest {
  contains('contains'),
  notContains('doesn\'t contain'),
  isEmpty('is empty'),
  notEmpty('isn\'t empty'),
  succeeded('succeeded'),
  failed('failed');

  const ConditionTest(this.label);
  final String label;
  bool get needsValue => this == contains || this == notContains;
}

/// What a condition step does when its test fails.
enum ConditionOtherwise {
  stop('Stop the routine'),
  skipNext('Skip the next step');

  const ConditionOtherwise(this.label);
  final String label;
}

@immutable
class RoutineStep {
  const RoutineStep({
    required this.id,
    required this.kind,
    this.prompt = '',
    this.tool = '',
    this.args = const {},
    this.title = '',
    this.body = '',
    this.seconds = 60,
    this.test = ConditionTest.contains,
    this.value = '',
    this.otherwise = ConditionOtherwise.stop,
    this.continueOnError = false,
    this.enabled = true,
  });

  final String id;
  final RoutineStepKind kind;

  /// For ask: the instruction.
  final String prompt;

  /// For tool: its name and inputs (text may hold {{variables}}).
  final String tool;
  final Map<String, dynamic> args;

  /// For notify.
  final String title;
  final String body;

  /// For wait.
  final int seconds;

  /// For condition.
  final ConditionTest test;
  final String value;
  final ConditionOtherwise otherwise;

  /// A failure doesn't stop the routine.
  final bool continueOnError;
  final bool enabled;

  RoutineStep copyWith({
    String? prompt,
    String? tool,
    Map<String, dynamic>? args,
    String? title,
    String? body,
    int? seconds,
    ConditionTest? test,
    String? value,
    ConditionOtherwise? otherwise,
    bool? continueOnError,
    bool? enabled,
  }) => RoutineStep(
    id: id,
    kind: kind,
    prompt: prompt ?? this.prompt,
    tool: tool ?? this.tool,
    args: args ?? this.args,
    title: title ?? this.title,
    body: body ?? this.body,
    seconds: seconds ?? this.seconds,
    test: test ?? this.test,
    value: value ?? this.value,
    otherwise: otherwise ?? this.otherwise,
    continueOnError: continueOnError ?? this.continueOnError,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (tool.isNotEmpty) 'tool': tool,
    if (args.isNotEmpty) 'args': args,
    if (title.isNotEmpty) 'title': title,
    if (body.isNotEmpty) 'body': body,
    if (kind == RoutineStepKind.wait) 'seconds': seconds,
    if (kind == RoutineStepKind.condition) ...{'test': test.name, 'value': value, 'otherwise': otherwise.name},
    if (continueOnError) 'continue_on_error': true,
    if (!enabled) 'enabled': false,
  };

  factory RoutineStep.fromJson(Map<String, dynamic> j) => RoutineStep(
    id: '${j['id'] ?? const Uuid().v4().substring(0, 6)}',
    kind: RoutineStepKind.values.asNameMap()['${j['kind']}'] ?? RoutineStepKind.ask,
    prompt: '${j['prompt'] ?? ''}',
    tool: '${j['tool'] ?? ''}',
    args: j['args'] is Map ? Map<String, dynamic>.from(j['args'] as Map) : const {},
    title: '${j['title'] ?? ''}',
    body: '${j['body'] ?? ''}',
    seconds: (j['seconds'] as num?)?.toInt().clamp(1, 6 * 60 * 60) ?? 60,
    test: ConditionTest.values.asNameMap()['${j['test']}'] ?? ConditionTest.contains,
    value: '${j['value'] ?? ''}',
    otherwise: ConditionOtherwise.values.asNameMap()['${j['otherwise']}'] ?? ConditionOtherwise.stop,
    continueOnError: j['continue_on_error'] == true,
    enabled: j['enabled'] != false,
  );

  /// One line for the builder's list.
  String summary(String Function(String tool) toolLabel) => switch (kind) {
    RoutineStepKind.ask => prompt.isEmpty ? 'No instruction yet' : prompt,
    RoutineStepKind.tool => tool.isEmpty ? 'No tool picked yet' : '${toolLabel(tool)}${args.isEmpty ? '' : ' · ${args.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'}',
    RoutineStepKind.notify => title.isEmpty && body.isEmpty ? 'Shows the last step\'s result' : [title, body].where((s) => s.isNotEmpty).join(' — '),
    RoutineStepKind.wait => seconds < 60 ? '$seconds seconds' : seconds % 3600 == 0 ? '${seconds ~/ 3600} h' : '${(seconds / 60).round()} min',
    RoutineStepKind.condition => 'If the last result ${test.label}${test.needsValue ? ' "$value"' : ''}, else ${otherwise.label.toLowerCase()}',
  };
}

/// What one step did in a run.
@immutable
class StepResult {
  const StepResult({required this.stepId, required this.label, required this.ok, this.output = '', this.ms = 0, this.skipped = false});
  final String stepId;
  final String label;
  final bool ok;
  final String output;
  final int ms;
  final bool skipped;

  Map<String, dynamic> toJson() => {
    'step': stepId,
    'label': label,
    'ok': ok,
    if (output.isNotEmpty) 'output': output,
    'ms': ms,
    if (skipped) 'skipped': true,
  };

  factory StepResult.fromJson(Map<String, dynamic> j) => StepResult(
    stepId: '${j['step']}',
    label: '${j['label'] ?? ''}',
    ok: j['ok'] == true,
    output: '${j['output'] ?? ''}',
    ms: (j['ms'] as num?)?.toInt() ?? 0,
    skipped: j['skipped'] == true,
  );
}

@immutable
class RoutineRun {
  const RoutineRun({required this.at, required this.trigger, required this.ok, required this.steps, this.stoppedEarly = false, this.error});
  final DateTime at;
  final String trigger;
  final bool ok;
  final List<StepResult> steps;

  /// A condition ended it before the last step.
  final bool stoppedEarly;
  final String? error;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'trigger': trigger,
    'ok': ok,
    'steps': [for (final s in steps) s.toJson()],
    if (stoppedEarly) 'stopped_early': true,
    'error': ?error,
  };

  factory RoutineRun.fromJson(Map<String, dynamic> j) => RoutineRun(
    at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
    trigger: '${j['trigger'] ?? ''}',
    ok: j['ok'] == true,
    steps: [for (final s in (j['steps'] as List? ?? const [])) StepResult.fromJson(Map<String, dynamic>.from(s as Map))],
    stoppedEarly: j['stopped_early'] == true,
    error: j['error'] as String?,
  );
}

/// A routine: a named list of steps that runs by hand, on a schedule or
/// when something happens on the phone. "Good morning": read my calendar,
/// summarise unread DMs, notify me. "Leaving work": text my partner.
@immutable
class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description = '',
    this.enabled = true,
    this.trigger = const RoutineTrigger(),
    this.steps = const [],
    this.model = WatchModel.free,
    this.tools,
    this.notifyWhenDone = true,
    this.conversationId,
    this.lastRunAt,
    this.runs = 0,
    this.history = const [],
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final RoutineTrigger trigger;
  final List<RoutineStep> steps;

  /// The model its "ask" steps use (see [WatchModel]).
  final String model;

  /// The tools its "ask" steps may use; null for all.
  final ToolAllowlist? tools;

  /// A notification with the last step's result when it finishes (unless a
  /// step already notified).
  final bool notifyWhenDone;

  /// Where its "ask" steps talk.
  final String? conversationId;
  final DateTime? lastRunAt;
  final int runs;

  /// The latest runs, newest first.
  final List<RoutineRun> history;
  final DateTime createdAt;

  /// The id watches and the activity log know its runs by.
  String get runId => 'routine-$id';

  Routine copyWith({
    String? name,
    String? description,
    bool? enabled,
    RoutineTrigger? trigger,
    List<RoutineStep>? steps,
    String? model,
    ToolAllowlist? tools,
    bool allTools = false,
    bool? notifyWhenDone,
    String? conversationId,
    DateTime? lastRunAt,
    int? runs,
    List<RoutineRun>? history,
  }) => Routine(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    trigger: trigger ?? this.trigger,
    steps: steps ?? this.steps,
    model: model ?? this.model,
    tools: allTools ? null : (tools ?? this.tools),
    notifyWhenDone: notifyWhenDone ?? this.notifyWhenDone,
    conversationId: conversationId ?? this.conversationId,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    runs: runs ?? this.runs,
    history: history ?? this.history,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'enabled': enabled,
    'trigger': trigger.toJson(),
    'steps': [for (final s in steps) s.toJson()],
    'model': model,
    if (tools != null) 'tools': tools!.entries.toList(),
    'notify_when_done': notifyWhenDone,
    'conversation_id': ?conversationId,
    'last_run': lastRunAt?.toIso8601String(),
    'runs': runs,
    'history': [for (final r in history) r.toJson()],
    'created': createdAt.toIso8601String(),
  };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
    id: '${j['id']}',
    name: '${j['name'] ?? 'Routine'}',
    description: '${j['description'] ?? ''}',
    enabled: j['enabled'] != false,
    trigger: RoutineTrigger.fromJson(j['trigger']),
    steps: [for (final s in (j['steps'] as List? ?? const [])) RoutineStep.fromJson(Map<String, dynamic>.from(s as Map))],
    model: '${j['model'] ?? WatchModel.free}',
    tools: j['tools'] is List ? ToolAllowlist.parse(j['tools'] as List) : null,
    notifyWhenDone: j['notify_when_done'] != false,
    conversationId: j['conversation_id'] as String?,
    lastRunAt: DateTime.tryParse('${j['last_run'] ?? ''}'),
    runs: (j['runs'] as num?)?.toInt() ?? 0,
    history: [for (final r in (j['history'] as List? ?? const [])) RoutineRun.fromJson(Map<String, dynamic>.from(r as Map))],
    createdAt: DateTime.tryParse('${j['created'] ?? ''}') ?? DateTime.now(),
  );

  /// For the assistant.
  Map<String, dynamic> describe() => {
    'routine_id': id,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'enabled': enabled,
    'trigger': trigger.describe(),
    'steps': [
      for (final (i, s) in steps.indexed)
        {'n': i + 1, 'kind': s.kind.name, ...s.toJson()..remove('id')..remove('kind')},
    ],
    'model': model,
    'tools': tools?.toModel() ?? 'all',
    'runs': runs,
    if (lastRunAt != null) 'last_run': lastRunAt!.toIso8601String().substring(0, 16),
    if (history.isNotEmpty) 'last_result': history.first.ok ? 'ok' : (history.first.error ?? 'failed'),
  };
}

class RoutineStore extends Notifier<List<Routine>> {
  static const _key = 'routines.v1';
  static const _uuid = Uuid();
  static const keepRuns = 20;

  late Future<void> ready;

  @override
  List<Routine> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      state = [for (final r in jsonDecode(raw) as List) Routine.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      debugPrint('[Routines] $e');
    }
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final r in state) r.toJson()]));

  static String newId() => _uuid.v4().substring(0, 8);
  static String newStepId() => _uuid.v4().substring(0, 6);

  Routine? byId(String id) => state.where((r) => r.id == id || r.runId == id).firstOrNull;

  Future<Routine> add(Routine Function(String id) make) async {
    await ready;
    final r = make(newId());
    state = [...state, r];
    await _save();
    return r;
  }

  /// Adds or replaces [r] as a whole (the builder's Save).
  Future<void> put(Routine r) async {
    await ready;
    state = state.any((x) => x.id == r.id) ? [for (final x in state) x.id == r.id ? r : x] : [...state, r];
    await _save();
  }

  Future<Routine?> update(String id, Routine Function(Routine) change) async {
    await ready;
    Routine? updated;
    state = [
      for (final r in state)
        if (r.id == id) updated = change(r) else r,
    ];
    await _save();
    return updated;
  }

  Future<bool> remove(String id) async {
    await ready;
    final before = state.length;
    state = state.where((r) => r.id != id).toList();
    await _save();
    return before != state.length;
  }

  Future<void> recordRun(String id, RoutineRun run) => update(
    id,
    (r) => r.copyWith(lastRunAt: run.at, runs: r.runs + 1, history: [run, ...r.history.take(keepRuns - 1)]),
  );

  Future<void> reorder(List<String> ids) async {
    await ready;
    final byId = {for (final r in state) r.id: r};
    state = [for (final id in ids) ?byId[id], ...state.where((r) => !ids.contains(r.id))];
    await _save();
  }
}

final routineStoreProvider = NotifierProvider<RoutineStore, List<Routine>>(RoutineStore.new);

/// Starting points for the builder.
List<Routine> routineTemplates() {
  RoutineStep step(RoutineStepKind k, {String prompt = '', String title = '', String body = '', String tool = '', Map<String, dynamic> args = const {}, ConditionTest test = ConditionTest.contains, String value = '', int seconds = 60}) =>
      RoutineStep(id: RoutineStore.newStepId(), kind: k, prompt: prompt, title: title, body: body, tool: tool, args: args, test: test, value: value, seconds: seconds);
  final now = DateTime.now();
  return [
    Routine(
      id: '',
      name: 'Good morning',
      description: 'A short briefing when the day starts',
      createdAt: now,
      trigger: const RoutineTrigger(kind: RoutineTriggerKind.daily, at: '07:30', days: {1, 2, 3, 4, 5}),
      steps: [
        step(RoutineStepKind.ask, prompt: 'Look at my unread DMs and mentions, today\'s calendar and any reminders. Write a 4-line morning briefing: the most important thing first.'),
        step(RoutineStepKind.notify, title: 'Good morning', body: '{{last}}'),
      ],
    ),
    Routine(
      id: '',
      name: 'Low battery heads-up',
      description: 'Tell the people waiting on you that your phone is about to die',
      createdAt: now,
      trigger: const RoutineTrigger(kind: RoutineTriggerKind.device, device: DeviceCondition(kind: DeviceTriggerKind.batteryLow, threshold: 10)),
      steps: [
        step(RoutineStepKind.notify, title: 'Battery low', body: 'Plug in soon. {{trigger}}'),
      ],
    ),
    Routine(
      id: '',
      name: 'Arrived at work',
      description: 'Quiet the phone and catch up when you get to the office',
      createdAt: now,
      trigger: const RoutineTrigger(kind: RoutineTriggerKind.device, device: DeviceCondition(kind: DeviceTriggerKind.arrive, placeName: 'Work')),
      steps: [
        step(RoutineStepKind.tool, tool: 'ringer_mode', args: {'mode': 'vibrate'}),
        step(RoutineStepKind.ask, prompt: 'Summarise what came in on Slack and email since yesterday evening, in 5 bullets.'),
        step(RoutineStepKind.notify, title: 'At work', body: '{{last}}'),
      ],
    ),
    Routine(
      id: '',
      name: 'Evening wind-down',
      description: 'Plan tomorrow and get a nudge to rest',
      createdAt: now,
      trigger: const RoutineTrigger(kind: RoutineTriggerKind.daily, at: '21:30'),
      steps: [
        step(RoutineStepKind.ask, prompt: 'What is on my calendar tomorrow, and is anyone waiting on a reply from me? Answer in 3 short lines, or NOTHING if there is nothing.'),
        step(RoutineStepKind.condition, test: ConditionTest.notContains, value: 'NOTHING'),
        step(RoutineStepKind.notify, title: 'For tomorrow', body: '{{last}}'),
      ],
    ),
  ];
}
