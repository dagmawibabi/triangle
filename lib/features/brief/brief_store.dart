import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../assistant/notifications.dart';
import '../chat/data/chat_controller.dart';
import '../chat/domain/chat_models.dart';
import '../auth/data/auth_controller.dart';
import '../integrations/integrations_store.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/data/account_tools.dart' show accountHandle;
import '../../infrastructure/telegram/accounts.dart';
import '../settings/data/settings.dart';
import '../voice/speaker.dart';
import 'brief_prefs.dart';
import 'brief_widget.dart';

enum BriefKind {
  morning('Morning brief', '☀️'),
  night('Night brief', '🌙'),
  manual('Brief', '⚡');

  const BriefKind(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// One generated brief: the assistant's turn that wrote it (with its tool
/// calls and the posts it cites) and when, for which window.
class Brief {
  Brief({
    required this.id,
    required this.kind,
    required this.at,
    required this.since,
    required this.conversation,
    this.error,
  });
  final String id;
  final BriefKind kind;
  final DateTime at;

  /// The start of the window it covers.
  final DateTime since;
  final Conversation conversation;
  final String? error;

  AssistantEntry? get answer => conversation.entries.whereType<AssistantEntry>().lastOrNull;

  String get text => (answer?.steps ?? const <ModelStep>[])
      .map((s) => s.text)
      .where((t) => t.trim().isNotEmpty)
      .join('\n\n')
      .trim();

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'at': at.toIso8601String(),
    'since': since.toIso8601String(),
    'conversation': conversation.toJson(),
    'error': ?error,
  };

  factory Brief.fromJson(Map<String, dynamic> j) => Brief(
    id: j['id'],
    kind: BriefKind.values.asNameMap()[j['kind']] ?? BriefKind.manual,
    at: DateTime.tryParse(j['at'] ?? '') ?? DateTime.now(),
    since: DateTime.tryParse(j['since'] ?? '') ?? DateTime.now(),
    conversation: Conversation.fromJson(Map<String, dynamic>.from(j['conversation'])),
    error: j['error'],
  );
}

class BriefState {
  const BriefState({this.briefs = const [], this.running, this.live});
  final List<Brief> briefs;

  /// The kind being written right now.
  final BriefKind? running;

  /// The brief being written, as it happens: its tool calls and text.
  final Conversation? live;

  BriefState copyWith({List<Brief>? briefs, BriefKind? running, Conversation? live, bool idle = false}) => BriefState(
    briefs: briefs ?? this.briefs,
    running: idle ? null : (running ?? this.running),
    live: idle ? null : (live ?? this.live),
  );
}

String _briefPrompt(
  BriefKind kind,
  DateTime since,
  DateTime now,
  BriefPrefs p, {
  required String Function(int id) titleOf,
  required Set<String> apps,
  bool telegram = true,
  List<String> accounts = const [],
  Map<String, List<int>> excludedFolders = const {},
}) {
  final hours = now.difference(since).inMinutes / 60;
  String chats(Iterable<int> ids) => ids.map((id) => '${titleOf(id)} (chat_id $id)').join(', ');
  final kinds = p.kinds;
  final skipped = [
    if (!p.privateChats) 'private chats',
    if (!p.groups) 'groups',
    if (!p.channels) 'channels',
    if (!p.bots) 'bots',
  ];
  final mail = apps.contains('gmail') || apps.contains('outlook');
  final calendar = apps.contains('googlecalendar') || apps.contains('outlook');
  final work = [
    if (apps.contains('slack')) 'Slack (slack_search_messages or unread channel messages)',
    if (apps.contains('todoist')) 'Todoist (tasks due today or overdue)',
    if (apps.contains('linear')) 'Linear (issues assigned to me that changed)',
    if (apps.contains('github')) 'GitHub (github_list_notifications)',
    if (apps.contains('notion')) 'Notion (pages edited since then, only if quick)',
  ];
  // Without Telegram the brief is about the apps, whatever the setting.
  final useApps = (p.apps || !telegram) && (mail || calendar || work.isNotEmpty);
  var step = 0;
  String n() => '${++step}.';
  final research = [
    // With several accounts, the brief spans the ones chosen in Settings.
    if (telegram && accounts.length > 1)
      '${n()} The user has several Telegram accounts; this brief covers ${accounts.join(' and ')}. Do every Telegram step below in each of them '
          '(pass account to each Telegram tool), and in the brief say which account each item is from.'
    else if (telegram && accounts.length == 1)
      '${n()} Cover only the Telegram account ${accounts.single} (pass it as account to every Telegram tool).',
    if (!telegram)
      '${n()} Telegram isn\'t connected: skip it and use no Telegram tools.${useApps ? '' : ' No apps are connected either, so say briefly that there is nothing to brief on yet and that Telegram or apps (Gmail, Calendar, Slack…) can be connected under Settings → Apps & web.'}'
    else if (p.scope == BriefScope.chosen)
      '${n()} Cover only these chats: ${p.chosen.isEmpty ? '(none chosen: say so and stop)' : chats(p.chosen)}. read_messages on each with since_hours ${hours.ceil()}.'
    else ...[
      '${n()} get_account_overview, then get_recent_activity with since_hours ${hours.ceil()} for ${kinds.isEmpty ? 'all chats' : kinds.join(', ')}.',
      '${n()} read_messages on the chats that matter (people waiting on me first), and on the busiest ${p.channels ? 'channels' : 'groups'}.',
    ],
    if (telegram) ...[
      if (p.mentions) '${n()} get_unread_mentions for anything addressed to me.',
      if (p.missedCalls) '${n()} list_calls with only_missed for missed calls in the window.',
      if (p.mutedChats)
        '${n()} Include muted chats like any other.'
      else
        '${n()} Skip muted chats unless something there is clearly important.',
      if (skipped.isNotEmpty && p.scope == BriefScope.all) '${n()} Leave out ${skipped.join(', ')} entirely.',
      if (p.excluded.isNotEmpty) '${n()} Never read, cite or mention these chats: ${chats(p.excluded)}.',
      for (final e in excludedFolders.entries)
        if (e.value.isNotEmpty)
          '${n()} Leave out the folder ${e.key} entirely: never read, cite or mention its chats (chat_ids ${e.value.join(', ')}).'
        else
          '${n()} Leave out anything in the folder ${e.key}.',
    ],
    if (useApps) ...[
      if (mail) '${n()} Email (read-only): unread and important messages since then, e.g. gmail_fetch_emails with query "is:unread after:${since.toIso8601String().substring(0, 10).replaceAll('-', '/')}" and max_results 20.',
      if (calendar) '${n()} Calendar: ${kind == BriefKind.night ? 'tomorrow' : 'today'}\'s events (googlecalendar_events_list with timeMin/timeMax, singleEvents true).',
      if (work.isNotEmpty) '${n()} Also check ${work.join('; ')}.',
    ],
  ];
  final custom = p.instructions.trim();
  return '''
Write my ${kind == BriefKind.morning ? 'morning' : kind == BriefKind.night ? 'end-of-day' : ''} brief: a briefing on everything that happened ${!telegram ? 'in my connected apps' : p.scope == BriefScope.chosen ? 'in the chats below' : 'across my Telegram'}${useApps && telegram ? ' and my connected apps' : ''} since ${since.toIso8601String().substring(0, 16)} (the last ${hours.toStringAsFixed(1)} hours).

How to research it (stay within Telegram's rate limits; this is read-only, change nothing, send nothing and mark nothing read):
${research.join('\n')}

How to write it (markdown):
- ${p.length.instruction}
- Tone: ${p.tone.instruction}.${p.language.trim().isEmpty ? '' : '\n- Write it in ${p.language.trim()}.'}
- Start with a 2-3 line **TL;DR**.
- **🔴 Needs you now**: questions or requests waiting on my reply, mentions, ${p.missedCalls ? 'missed calls, ' : ''}deadlines${useApps && mail ? ', emails that need an answer' : ''}. Say who, what they want, and since when.
- **🟠 Important**: significant news, decisions and updates in groups and from people.
- **🟡 Worth knowing**: notable ${p.channels ? 'channel posts' : 'messages'}, grouped by topic, a sentence or two each.${useApps ? '\n- **📬 Other apps**: email, calendar${work.isNotEmpty ? ', Slack, tasks and issues' : ''}, briefly, most important first.' : ''}
${p.length == BriefLength.short ? '' : '- **⚪ Low priority**: one line per chat for the rest, or "nothing else notable".\n'}- ${kind == BriefKind.morning ? 'End with **Today**: what I should do first today.' : kind == BriefKind.night ? 'End with **Tomorrow**: open loops to pick up tomorrow.' : 'End with **Next steps**: what I should do next.'}
Cite every message you mention with its post ref link so I can open it. Be specific (names, numbers, times); no filler.${custom.isEmpty ? '' : '\n\nMy own instructions for briefs (follow them; they win over the above):\n$custom'}
''';
}

/// Briefs: written on request and, when Settings say so, each morning and
/// night. Kept on the phone, newest first.
class BriefStore extends Notifier<BriefState> {
  @override
  BriefState build() {
    _load();
    return const BriefState();
  }

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/briefs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _load() async {
    try {
      final d = await _dir();
      final list = <Brief>[];
      await for (final f in d.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          list.add(Brief.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
        } catch (_) {}
      }
      list.sort((a, b) => b.at.compareTo(a.at));
      state = state.copyWith(briefs: list);
      unawaited(BriefHomeWidget.publish(list));
    } catch (e) {
      debugPrint('[Brief] load: $e');
    }
  }

  Future<void> deleteAll() async {
    for (final b in [...state.briefs]) {
      await delete(b.id);
    }
  }

  Future<void> delete(String id) async {
    state = state.copyWith(briefs: state.briefs.where((b) => b.id != id).toList());
    unawaited(BriefHomeWidget.publish(state.briefs));
    try {
      final f = File('${(await _dir()).path}/$id.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Writes a brief now, covering [window] back or the time since the last
  /// one. Returns null when one is already being written or there is no AI
  /// key.
  Future<Brief?> generate(BriefKind kind, {Duration? window}) async {
    if (state.running != null) return null;
    final settings = ref.read(settingsProvider);
    if (!settings.hasAnyKey) return null;
    state = state.copyWith(running: kind);
    final now = DateTime.now();
    final last = state.briefs.where((b) => b.error == null).firstOrNull?.at;
    var since = last ?? now.subtract(const Duration(hours: 12));
    if (now.difference(since).inHours > 36) since = now.subtract(const Duration(hours: 36));
    if (now.difference(since).inMinutes < 60) since = now.subtract(const Duration(hours: 6));
    if (window != null) since = now.subtract(window);
    final prefs = ref.read(briefPrefsProvider);
    final accounts = ref.read(accountsProvider);
    final covered = accounts.within(prefs.accountIds);
    // Chat titles from whichever covered account knows the chat.
    String titleOf(int id) {
      for (final a in covered) {
        final t = ref.read(telegramStoreFamily(a.id)).chat(id)?.title;
        if (t != null && t.isNotEmpty) return t;
      }
      return ref.read(telegramStoreProvider).chat(id)?.title ?? prefs.chatTitles[id] ?? 'chat $id';
    }

    // Excluded folders, as the chats in them now ("Work (Dagi)": [ids]).
    final folderChats = <String, List<int>>{};
    for (final e in prefs.excludedFolders.entries) {
      final cut = e.key.indexOf(':');
      final account = cut < 0 ? accounts.activeId : e.key.substring(0, cut);
      final folderId = int.tryParse(cut < 0 ? e.key : e.key.substring(cut + 1));
      final owner = accounts.byId(account);
      if (folderId == null || owner?.signedIn != true) continue;
      final label = accounts.hasSeveral ? '"${e.value}" (${owner!.label})' : '"${e.value}"';
      try {
        folderChats[label] = await ref.read(telegramStoreFamily(account)).loadFolder(folderId);
      } catch (_) {
        folderChats[label] = const [];
      }
    }

    try {
      final c = await ref
          .read(chatControllerProvider.notifier)
          .runHidden(
            '${kind.label} · ${now.toIso8601String().substring(0, 10)}',
            _briefPrompt(
              kind,
              since,
              now,
              prefs,
              titleOf: titleOf,
              apps: ref.read(settingsProvider).hasComposioKey ? ref.read(integrationsProvider).connected : const {},
              // Covered accounts the assistant may read; none means the
              // brief is about the apps alone.
              telegram: accounts.signedIn.isEmpty
                  ? ref.read(telegramConnectedProvider)
                  : covered.any((a) => a.aiAccess),
              accounts: accounts.hasSeveral ? [for (final a in covered) if (a.aiAccess) accountHandle(a)] : const [],
              excludedFolders: folderChats,
            ),
            onStart: (c) => state = state.copyWith(live: c),
            accounts: accounts.hasSeveral ? prefs.accountIds : null,
          );
      final answer = c.entries.whereType<AssistantEntry>().lastOrNull;
      final b = Brief(
        id: '${now.millisecondsSinceEpoch}',
        kind: kind,
        at: now,
        since: since,
        conversation: c,
        error: answer?.error,
      );
      await File('${(await _dir()).path}/${b.id}.json').writeAsString(jsonEncode(b.toJson()));
      state = state.copyWith(briefs: [b, ...state.briefs], idle: true);
      unawaited(BriefHomeWidget.publish(state.briefs));
      if (settings.notifications && kind != BriefKind.manual) {
        final text = Speaker.clean(b.text);
        await ref
            .read(appNotifierProvider)
            .show(
              '${kind.emoji} ${kind.label}',
              text.isEmpty ? 'Your brief is ready.' : (text.length > 400 ? '${text.substring(0, 400)}…' : text),
            );
      }
      return b;
    } catch (e) {
      debugPrint('[Brief] $e');
      state = state.copyWith(idle: true);
      return null;
    }
  }

  DateTime? _lastCheck;

  /// Called every half minute by the watch engine's clock: writes the
  /// morning or night brief once its time has come (within two hours, so a
  /// phone that was off doesn't brief at noon).
  Future<void> tick() async {
    final s = ref.read(settingsProvider);
    if (!s.briefsScheduled || state.running != null) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!).inSeconds < 50) return;
    _lastCheck = now;
    for (final (kind, at) in [
      if (s.briefMorningOn) (BriefKind.morning, s.briefMorning),
      if (s.briefNightOn) (BriefKind.night, s.briefNight),
    ]) {
      final parts = at.split(':');
      final due = DateTime(now.year, now.month, now.day, int.tryParse(parts.first) ?? 8, int.tryParse(parts.last) ?? 0);
      if (now.isBefore(due) || now.difference(due).inHours >= 2) continue;
      final done = state.briefs.any((b) => b.kind == kind && !b.at.isBefore(due));
      if (!done) {
        await generate(kind);
        return;
      }
    }
  }
}

final briefStoreProvider = NotifierProvider<BriefStore, BriefState>(BriefStore.new);
