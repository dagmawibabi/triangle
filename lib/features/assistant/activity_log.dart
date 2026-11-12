import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// What started the run that took an action.
enum ActivitySource {
  chat('Chat', 'Chats'),
  watch('Watch', 'Watches'),
  job('Scheduled job', 'Jobs'),
  routine('Routine', 'Routines'),
  brief('Brief', 'Briefs'),
  you('You', 'You');

  const ActivitySource(this.label, this.plural);
  final String label;
  final String plural;
}

/// The tool name a run's entry carries (as opposed to an action's).
const runTool = '_run';

/// Why an action was allowed to run.
enum ActivityApproval {
  tapped('You approved it'),
  rule('A standing rule allowed it'),
  setting('Your approval setting let it run'),
  routineStep('A step in a routine you built'),
  notNeeded('Needs no approval'),
  declined('You declined it'),
  blocked('Blocked');

  const ActivityApproval(this.label);
  final String label;
}

enum ActivityOutcome { done, failed, declined, blocked }

/// What sort of thing an entry records, for the log's filters.
enum ActivityKind {
  action('Actions', 'What the assistant sent, changed or deleted'),
  access('Data access', 'When the assistant read personal data: texts, calls, contacts, money, email, files'),
  run('Runs', 'Watches, routines, scheduled jobs and briefs running'),
  settings('Settings', 'Approval, read-only mode, tools turned on or off, keys added or removed'),
  security('Security', 'App lock turned on, off or changed');

  const ActivityKind(this.label, this.description);
  final String label;
  final String description;
}

/// How an entry can be taken back.
enum UndoKind {
  /// Deletes the messages it sent, for everyone.
  deleteMessages,

  /// Runs the same tool again with these arguments.
  rerunTool,

  /// Removes something the app keeps: a watch, reminder, memory, vault
  /// item or routine.
  removeLocal,
}

@immutable
class UndoAction {
  const UndoAction({required this.kind, required this.label, this.tool, this.args = const {}, this.messages = const [], this.localKind, this.localId});

  final UndoKind kind;

  /// The button's words, e.g. "Delete the message".
  final String label;

  /// For [UndoKind.rerunTool].
  final String? tool;
  final Map<String, dynamic> args;

  /// For [UndoKind.deleteMessages]: (chat id, message id) pairs.
  final List<(int, int)> messages;

  /// For [UndoKind.removeLocal]: watch, reminder, memory, vault, routine.
  final String? localKind;
  final String? localId;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'label': label,
    'tool': ?tool,
    if (args.isNotEmpty) 'args': args,
    if (messages.isNotEmpty) 'messages': [for (final (c, m) in messages) [c, m]],
    'local_kind': ?localKind,
    'local_id': ?localId,
  };

  static UndoAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = UndoKind.values.asNameMap()[j['kind']];
    if (kind == null) return null;
    return UndoAction(
      kind: kind,
      label: '${j['label'] ?? 'Undo'}',
      tool: j['tool'] as String?,
      args: j['args'] is Map ? Map<String, dynamic>.from(j['args'] as Map) : const {},
      messages: [
        for (final p in (j['messages'] as List? ?? const []))
          if (p is List && p.length == 2) ((p[0] as num).toInt(), (p[1] as num).toInt()),
      ],
      localKind: j['local_kind'] as String?,
      localId: j['local_id'] as String?,
    );
  }
}

/// One thing the assistant did (or tried to do) that changes something.
@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.at,
    required this.tool,
    required this.toolLabel,
    required this.source,
    required this.approval,
    required this.outcome,
    this.sourceName,
    this.conversationId,
    this.account,
    this.arguments = '',
    this.result = '',
    this.summary = '',
    this.durationMs,
    this.undo,
    this.undoneAt,
    this.undoError,
    this.destructive = false,
    ActivityKind? kind,
  }) : _kind = kind;

  final ActivityKind? _kind;

  /// Older entries have no kind saved: a run, or an action.
  ActivityKind get kind => _kind ?? (tool == runTool ? ActivityKind.run : ActivityKind.action);

  final String id;
  final DateTime at;
  final String tool;
  final String toolLabel;
  final ActivitySource source;

  /// The watch, job or routine's name.
  final String? sourceName;
  final String? conversationId;
  final String? account;
  final ActivityApproval approval;
  final ActivityOutcome outcome;

  /// The call's arguments and result as JSON text, clipped.
  final String arguments;
  final String result;

  /// One line: "Sent 2 messages to Liya", "Reacted 👍 in Work".
  final String summary;
  final int? durationMs;
  final UndoAction? undo;
  final DateTime? undoneAt;
  final String? undoError;
  final bool destructive;

  bool get canUndo => undo != null && undoneAt == null && outcome == ActivityOutcome.done;

  /// A watch, routine, job or brief running, rather than one action.
  bool get isRun => tool == runTool;

  Map<String, dynamic> get args {
    try {
      final v = jsonDecode(arguments.isEmpty ? '{}' : arguments);
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }

  ActivityEntry copyWith({DateTime? undoneAt, String? undoError, bool clearUndoError = false}) => ActivityEntry(
    id: id,
    at: at,
    tool: tool,
    toolLabel: toolLabel,
    source: source,
    sourceName: sourceName,
    conversationId: conversationId,
    account: account,
    approval: approval,
    outcome: outcome,
    arguments: arguments,
    result: result,
    summary: summary,
    durationMs: durationMs,
    undo: undo,
    undoneAt: undoneAt ?? this.undoneAt,
    undoError: clearUndoError ? null : (undoError ?? this.undoError),
    destructive: destructive,
    kind: _kind,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'tool': tool,
    'label': toolLabel,
    'source': source.name,
    'source_name': ?sourceName,
    'conversation': ?conversationId,
    'account': ?account,
    'approval': approval.name,
    'outcome': outcome.name,
    if (arguments.isNotEmpty) 'args': arguments,
    if (result.isNotEmpty) 'result': result,
    if (summary.isNotEmpty) 'summary': summary,
    'ms': ?durationMs,
    if (undo != null) 'undo': undo!.toJson(),
    if (undoneAt != null) 'undone': undoneAt!.toIso8601String(),
    'undo_error': ?undoError,
    if (destructive) 'destructive': true,
    if (_kind != null) 'kind': _kind.name,
  };

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
    id: '${j['id']}',
    at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
    tool: '${j['tool']}',
    toolLabel: '${j['label'] ?? j['tool']}',
    source: ActivitySource.values.asNameMap()[j['source']] ?? ActivitySource.chat,
    sourceName: j['source_name'] as String?,
    conversationId: j['conversation'] as String?,
    account: j['account'] as String?,
    approval: ActivityApproval.values.asNameMap()[j['approval']] ?? ActivityApproval.notNeeded,
    outcome: ActivityOutcome.values.asNameMap()[j['outcome']] ?? ActivityOutcome.done,
    arguments: '${j['args'] ?? ''}',
    result: '${j['result'] ?? ''}',
    summary: '${j['summary'] ?? ''}',
    durationMs: (j['ms'] as num?)?.toInt(),
    undo: UndoAction.fromJson(j['undo']),
    undoneAt: DateTime.tryParse('${j['undone'] ?? ''}'),
    undoError: j['undo_error'] as String?,
    destructive: j['destructive'] == true,
    kind: ActivityKind.values.asNameMap()[j['kind']],
  );
}

/// The audit trail, newest first, kept on this phone: every action the
/// assistant took or tried, its reads of personal data, runs of watches and
/// routines, and changes to approval, tools, keys and the app lock.
class ActivityLog extends Notifier<List<ActivityEntry>> {
  static const _key = 'activity_log.v1';
  static const _max = 1500;
  static const _clip = 4000;
  static const _uuid = Uuid();

  late Future<void> ready;

  @override
  List<ActivityEntry> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final loaded = [for (final e in jsonDecode(raw) as List) ActivityEntry.fromJson(Map<String, dynamic>.from(e as Map))];
      // Entries recorded while loading stay on top.
      state = [...state, ...loaded];
    } catch (e) {
      debugPrint('[Activity] $e');
    }
  }

  Future<void> _save() async {
    try {
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final e in state) e.toJson()]));
    } catch (e) {
      debugPrint('[Activity] save: $e');
    }
  }

  static String clip(String s) => s.length <= _clip ? s : '${s.substring(0, _clip)}…';

  Future<ActivityEntry> record({
    required String tool,
    required String toolLabel,
    required ActivitySource source,
    required ActivityApproval approval,
    required ActivityOutcome outcome,
    String? sourceName,
    String? conversationId,
    String? account,
    String arguments = '',
    String result = '',
    String summary = '',
    int? durationMs,
    UndoAction? undo,
    bool destructive = false,
    ActivityKind? kind,
  }) async {
    final e = ActivityEntry(
      id: _uuid.v4(),
      at: DateTime.now(),
      tool: tool,
      toolLabel: toolLabel,
      source: source,
      sourceName: sourceName,
      conversationId: conversationId,
      account: account,
      approval: approval,
      outcome: outcome,
      arguments: clip(arguments),
      result: clip(result),
      summary: summary,
      durationMs: durationMs,
      undo: undo,
      destructive: destructive,
      kind: kind,
    );
    state = [e, ...state.take(_max - 1)];
    await _save();
    return e;
  }

  /// A watch, routine, job or brief ran: what started it and what it said.
  Future<ActivityEntry> recordRun({
    required ActivitySource source,
    required String name,
    required bool ok,
    String text = '',
    String? conversationId,
    String? model,
    String? trigger,
    int? durationMs,
    Map<String, dynamic> details = const {},
  }) {
    final first = text.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    final quiet = first.contains('NOTHING_NEW');
    return record(
      tool: runTool,
      toolLabel: '${source.label} ran',
      source: source,
      sourceName: name,
      conversationId: conversationId,
      approval: ActivityApproval.notNeeded,
      outcome: ok ? ActivityOutcome.done : ActivityOutcome.failed,
      arguments: jsonEncode({'trigger': ?trigger, 'model': ?model, ...details}),
      result: text,
      summary: '$name${quiet ? ': nothing new' : first.isEmpty ? '' : ': ${first.length > 140 ? '${first.substring(0, 140)}…' : first}'}',
      durationMs: durationMs,
    );
  }

  ActivityEntry? byId(String id) => state.where((e) => e.id == id).firstOrNull;

  /// A settings or security change, or another event that isn't a tool
  /// call: [title] is the line shown, [detail] the specifics.
  Future<ActivityEntry> recordEvent({required ActivityKind kind, required String title, String detail = '', ActivitySource source = ActivitySource.you}) => record(
    tool: '_${kind.name}',
    toolLabel: title,
    source: source,
    approval: ActivityApproval.notNeeded,
    outcome: ActivityOutcome.done,
    summary: title,
    result: detail,
    kind: kind,
  );

  Future<void> markUndone(String id, {String? error}) async {
    state = [
      for (final e in state)
        if (e.id == id) (error == null ? e.copyWith(undoneAt: DateTime.now(), clearUndoError: true) : e.copyWith(undoError: error)) else e,
    ];
    await _save();
  }

  Future<void> clear() async {
    state = const [];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _save();
  }
}

final activityLogProvider = NotifierProvider<ActivityLog, List<ActivityEntry>>(ActivityLog.new);

/// The tools whose sent messages Undo deletes.
bool sendsMessages(String tool) =>
    tool.startsWith('send_') || tool.startsWith('reply_') || tool.startsWith('forward_') || tool == 'post_to_channel';

/// What Undo does for a finished call, when it can be taken back.
UndoAction? undoFor(String tool, Map<String, dynamic> args, Map<String, dynamic> result, List<(int, int)> sent) {
  if (result.containsKey('error')) return null;
  String? str(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
  if (sent.isNotEmpty && sendsMessages(tool)) {
    return UndoAction(
      kind: UndoKind.deleteMessages,
      label: sent.length == 1 ? 'Delete the message' : 'Delete the ${sent.length} messages',
      messages: sent,
    );
  }
  switch (tool) {
    case 'react_to_message':
      return UndoAction(
        kind: UndoKind.rerunTool,
        label: result['removed'] == true ? 'Put the reaction back' : 'Remove the reaction',
        tool: tool,
        args: {...args, 'remove': result['removed'] != true},
      );
    case 'pin_message':
      return UndoAction(
        kind: UndoKind.rerunTool,
        label: args['unpin'] == true ? 'Pin it again' : 'Unpin it',
        tool: tool,
        args: {...args, 'unpin': args['unpin'] != true},
      );
    case 'archive_chat':
      final archived = result['archived'] != false;
      return UndoAction(
        kind: UndoKind.rerunTool,
        label: archived ? 'Move it out of the Archive' : 'Archive it again',
        tool: tool,
        args: {...args, 'archived': !archived},
      );
    case 'create_watch':
      final id = str(result['watch_id']);
      return id == null ? null : UndoAction(kind: UndoKind.removeLocal, label: 'Delete the watch', localKind: 'watch', localId: id);
    case 'create_reminder':
      final id = str(result['reminder_id'] ?? result['id']);
      return id == null ? null : UndoAction(kind: UndoKind.removeLocal, label: 'Delete the reminder', localKind: 'reminder', localId: id);
    case 'remember':
      final id = str(result['memory_id']);
      return id == null ? null : UndoAction(kind: UndoKind.removeLocal, label: 'Forget it', localKind: 'memory', localId: id);
    case 'vault_save':
      final id = str(result['item_id']);
      return id == null || result['created'] != true
          ? null
          : UndoAction(kind: UndoKind.removeLocal, label: 'Remove it from the vault', localKind: 'vault', localId: id);
    case 'create_routine':
      final id = str(result['routine_id']);
      return id == null ? null : UndoAction(kind: UndoKind.removeLocal, label: 'Delete the routine', localKind: 'routine', localId: id);
  }
  return null;
}
