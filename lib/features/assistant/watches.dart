import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../infrastructure/telegram/accounts.dart';

/// What a watch listens to.
enum WatchScope {
  chats('Specific chats'),
  allDms('All DMs'),
  allGroups('All groups'),
  allChannels('All channels'),
  mentions('Mentions of me'),
  folder('A folder'),
  schedule('On a schedule'),
  app('New in an app');

  const WatchScope(this.label);
  final String label;

  /// Fires on Telegram messages, so it needs Telegram connected. Schedules
  /// and app watches work without it.
  bool get needsTelegram => this != schedule && this != app;
}

/// What a watch does when it fires.
enum WatchMode {
  notify('Notify me', 'A notification with the new messages. No AI.'),
  summarize('Summarize', 'The assistant writes a short note in the watch\'s chat and notifies you.'),
  act('Act', 'The assistant follows your instructions: it may reply, react or use any tool.');

  const WatchMode(this.label, this.explanation);
  final String label;
  final String explanation;
}

/// A standing order: "tell me when X posts", "answer my DMs", "every morning
/// at 8, summarise my channels".
@immutable
class Watch {
  const Watch({
    required this.id,
    required this.name,
    required this.scope,
    required this.mode,
    this.enabled = true,
    this.chatIds = const [],
    this.folderId,
    this.instructions = '',
    this.includeMuted = true,
    this.notify = true,
    this.dailyAt,
    this.everyMinutes,
    this.conversationId,
    this.lastRunAt,
    this.runs = 0,
    required this.createdAt,
    this.app,
    this.query = '',
    this.builtIn = false,
    this.quietAtNight = false,
    this.accountIds,
    this.folderAccountId,
  });

  /// The Telegram accounts it covers: it hears their messages, and its
  /// assistant runs may use only them. Null: every account.
  final List<String>? accountIds;

  /// A folder belongs to one account (folder ids repeat across accounts),
  /// so a folder watch covers that account alone. Folder watches made
  /// before several accounts existed belong to the first one.
  final String? folderAccountId;

  /// Whether this watch hears messages in [accountId].
  bool covers(String accountId) => scope == WatchScope.folder
      ? (folderAccountId ?? legacyAccountId) == accountId
      : coversAccount(accountIds, accountId);

  /// The accounts its assistant runs may use (null: all).
  List<String>? get runAccounts => scope == WatchScope.folder ? [folderAccountId ?? legacyAccountId] : accountIds;

  /// One of the app's own watches (the check-in): it can be changed and
  /// turned off, never deleted.
  final bool builtIn;

  /// Scheduled runs skip 22:00 to 08:00 and catch up in the morning.
  final bool quietAtNight;

  /// Whether [at] falls in the quiet night hours.
  static bool isNight(DateTime at) => at.hour >= 22 || at.hour < 8;

  /// For [WatchScope.app]: the app to check (a Composio toolkit such as
  /// gmail, slack, github, or "any" for every connected app) and what to
  /// look for, e.g. "emails from my manager" or "messages mentioning me".
  final String? app;
  final String query;

  final String id;
  final String name;
  final WatchScope scope;
  final WatchMode mode;
  final bool enabled;
  final List<int> chatIds;
  final int? folderId;

  /// What the assistant should do, for summarize and act.
  final String instructions;
  final bool includeMuted;

  /// Alerts the person when it fires. Off, it runs quietly in the
  /// background: results land in its conversation, with no notification.
  final bool notify;

  /// For [WatchScope.schedule]: "HH:MM" local time each day, or a period.
  final String? dailyAt;
  final int? everyMinutes;

  /// The assistant conversation this watch writes in.
  final String? conversationId;
  final DateTime? lastRunAt;
  final int runs;
  final DateTime createdAt;

  Watch copyWith({
    String? name,
    WatchScope? scope,
    WatchMode? mode,
    bool? enabled,
    List<int>? chatIds,
    int? folderId,
    String? instructions,
    bool? includeMuted,
    bool? notify,
    String? dailyAt,
    int? everyMinutes,
    String? conversationId,
    DateTime? lastRunAt,
    int? runs,
    String? app,
    String? query,
    bool? quietAtNight,
    List<String>? accountIds,
    bool allAccounts = false,
    String? folderAccountId,
  }) => Watch(
    id: id,
    name: name ?? this.name,
    scope: scope ?? this.scope,
    mode: mode ?? this.mode,
    enabled: enabled ?? this.enabled,
    chatIds: chatIds ?? this.chatIds,
    folderId: folderId ?? this.folderId,
    instructions: instructions ?? this.instructions,
    includeMuted: includeMuted ?? this.includeMuted,
    notify: notify ?? this.notify,
    dailyAt: dailyAt ?? this.dailyAt,
    everyMinutes: everyMinutes ?? this.everyMinutes,
    conversationId: conversationId ?? this.conversationId,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    runs: runs ?? this.runs,
    createdAt: createdAt,
    app: app ?? this.app,
    query: query ?? this.query,
    builtIn: builtIn,
    quietAtNight: quietAtNight ?? this.quietAtNight,
    accountIds: allAccounts ? null : (accountIds ?? this.accountIds),
    folderAccountId: folderAccountId ?? this.folderAccountId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'scope': scope.name,
    'mode': mode.name,
    'enabled': enabled,
    'chat_ids': chatIds,
    'folder_id': folderId,
    'instructions': instructions,
    'include_muted': includeMuted,
    'notify': notify,
    'daily_at': dailyAt,
    'every_minutes': everyMinutes,
    'conversation_id': conversationId,
    'last_run': lastRunAt?.toIso8601String(),
    'runs': runs,
    'created': createdAt.toIso8601String(),
    'app': ?app,
    if (query.isNotEmpty) 'query': query,
    if (builtIn) 'built_in': true,
    if (quietAtNight) 'quiet_at_night': true,
    'accounts': ?accountIds,
    'folder_account': ?folderAccountId,
  };

  factory Watch.fromJson(Map<String, dynamic> j) => Watch(
    id: j['id'],
    name: j['name'] ?? 'Watch',
    scope: WatchScope.values.asNameMap()[j['scope']] ?? WatchScope.chats,
    mode: WatchMode.values.asNameMap()[j['mode']] ?? WatchMode.notify,
    enabled: j['enabled'] ?? true,
    chatIds: [for (final c in (j['chat_ids'] as List? ?? const [])) (c as num).toInt()],
    folderId: (j['folder_id'] as num?)?.toInt(),
    instructions: j['instructions'] ?? '',
    includeMuted: j['include_muted'] ?? true,
    notify: j['notify'] ?? true,
    dailyAt: j['daily_at'],
    everyMinutes: (j['every_minutes'] as num?)?.toInt(),
    conversationId: j['conversation_id'],
    lastRunAt: DateTime.tryParse(j['last_run'] ?? ''),
    runs: (j['runs'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
    app: j['app'],
    query: j['query'] ?? '',
    builtIn: j['built_in'] ?? false,
    quietAtNight: j['quiet_at_night'] ?? false,
    accountIds: (j['accounts'] as List?)?.map((e) => '$e').toList(),
    folderAccountId: j['folder_account'],
  );

  /// For the assistant and the Watches screen.
  Map<String, dynamic> describe() => {
    'watch_id': id,
    'name': name,
    'enabled': enabled,
    'trigger': scope.name,
    if (chatIds.isNotEmpty) 'chat_ids': chatIds,
    'folder_id': ?folderId,
    'daily_at': ?dailyAt,
    'every_minutes': ?everyMinutes,
    'app': ?app,
    if (query.isNotEmpty) 'query': query,
    'mode': mode.name,
    if (instructions.isNotEmpty) 'instructions': instructions,
    if (!includeMuted) 'include_muted': false,
    if (!notify) 'notify': false,
    'runs': runs,
    if (lastRunAt != null) 'last_run': lastRunAt!.toIso8601String().substring(0, 16),
    if (builtIn) 'built_in': 'can be changed or turned off, not deleted',
    if (quietAtNight) 'quiet_at_night': true,
    'accounts': accountIds ?? 'all',
  };
}

/// The id of the built-in check-in watch.
const checkInWatchId = 'check-in';

/// What the check-in asks for, until the person changes it.
const checkInInstructions =
    'Find the single most useful thing to bring to the user right now. With read-only tools, look at what is new '
    'since the last check-in: unread Telegram DMs and mentions, connected apps (email, calendar, Slack and others), '
    'reminders, and events in the next day. Pick ONE topic worth their attention. If a little preparation helps, do '
    'it: summarise a long thread, draft notes for a meeting, draft a reply. Never send, post or change anything on '
    'their behalf. Then answer with one short, friendly note that greets them by first name and says what it is and '
    'what you prepared or can do, e.g. "Hey Joe, Hannah sent meeting notes on Slack; I summarised them for you." '
    'Keep it under 300 characters. If nothing new is worth their attention, answer with exactly NOTHING_NEW.';

/// The check-in as the app first sets it up: every six hours, quiet at night.
Watch defaultCheckIn() => Watch(
  id: checkInWatchId,
  name: 'Check-in',
  scope: WatchScope.schedule,
  mode: WatchMode.act,
  everyMinutes: 6 * 60,
  instructions: checkInInstructions,
  builtIn: true,
  quietAtNight: true,
  createdAt: DateTime.now(),
);

class WatchStore extends Notifier<List<Watch>> {
  static const _key = 'watches.v1';
  static const _uuid = Uuid();

  /// Completes once saved watches are loaded; changes wait for it, so one
  /// made at start-up isn't overwritten by the load (or a deleted one
  /// brought back).
  late Future<void> ready;

  @override
  List<Watch> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    var loaded = <Watch>[];
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) loaded = [for (final w in jsonDecode(raw) as List) Watch.fromJson(Map<String, dynamic>.from(w))];
    } catch (e) {
      debugPrint('[Watches] $e');
    }
    // The check-in is always there; turning it off is how it stops.
    final missing = !loaded.any((w) => w.id == checkInWatchId);
    state = [if (missing) defaultCheckIn(), ...loaded];
    if (missing) await _save();
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final w in state) w.toJson()]));

  Watch? byId(String id) => state.where((w) => w.id == id).firstOrNull;

  Future<Watch> add(Watch Function(String id) make) async {
    await ready;
    final w = make(_uuid.v4().substring(0, 8));
    state = [...state, w];
    await _save();
    return w;
  }

  Future<Watch?> update(String id, Watch Function(Watch) change) async {
    await ready;
    Watch? updated;
    state = [
      for (final w in state)
        if (w.id == id) updated = change(w) else w,
    ];
    await _save();
    return updated;
  }

  /// Deletes a watch. Built-in ones can only be turned off: false.
  Future<bool> remove(String id) async {
    await ready;
    if (byId(id)?.builtIn ?? false) return false;
    final before = state.length;
    state = state.where((w) => w.id != id).toList();
    await _save();
    return before != state.length;
  }
}

final watchStoreProvider = NotifierProvider<WatchStore, List<Watch>>(WatchStore.new);
