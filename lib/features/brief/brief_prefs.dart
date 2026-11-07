import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which chats a brief reads.
enum BriefScope {
  all('All chats', 'Everything with activity, except the chats you leave out'),
  chosen('Only chosen chats', 'Just the chats you pick');

  const BriefScope(this.label, this.explanation);
  final String label;
  final String explanation;
}

enum BriefTone {
  neutral('Neutral', 'plain and factual'),
  friendly('Friendly', 'warm and conversational, like a helpful friend'),
  professional('Professional', 'crisp and businesslike, like an executive assistant'),
  casual('Casual', 'relaxed and informal'),
  witty('Witty', 'light, with a little humour where it fits, never at the expense of clarity'),
  blunt('Blunt', 'direct and no-nonsense: the facts and what to do, no softening');

  const BriefTone(this.label, this.instruction);
  final String label;
  final String instruction;
}

enum BriefLength {
  short('Short', 'Keep it short: a TL;DR, what needs me, and at most 8 bullets in all. Skip the low-priority section.'),
  standard('Standard', 'A thorough brief, but trim filler: a sentence or two per item.'),
  extensive('Extensive', 'An extensive, detailed briefing.');

  const BriefLength(this.label, this.instruction);
  final String label;
  final String instruction;
}

/// How briefs are written: which chats and what to cover, and the tone,
/// length, language and instructions. Kept on the phone.
@immutable
class BriefPrefs {
  const BriefPrefs({
    this.scope = BriefScope.all,
    this.chosen = const {},
    this.excluded = const {},
    this.chatTitles = const {},
    this.privateChats = true,
    this.groups = true,
    this.channels = true,
    this.bots = false,
    this.mentions = true,
    this.missedCalls = true,
    this.mutedChats = false,
    this.apps = true,
    this.tone = BriefTone.neutral,
    this.length = BriefLength.extensive,
    this.language = '',
    this.instructions = '',
    this.accountIds,
    this.excludedFolders = const {},
  });

  /// Folders never read or mentioned, as "<account id>:<folder id>" (a
  /// folder id means a folder of one account) to the folder's name. Their
  /// chats are looked up each time a brief is written, so chats added to
  /// the folder later are left out too.
  final Map<String, String> excludedFolders;

  /// The Telegram accounts briefs cover. Null: every account.
  final List<String>? accountIds;

  final BriefScope scope;

  /// Chat ids read when [scope] is chosen.
  final Set<int> chosen;

  /// Chat ids never read or mentioned.
  final Set<int> excluded;

  /// Titles of [chosen] and [excluded] chats as they were picked, for when
  /// the chat list hasn't loaded.
  final Map<int, String> chatTitles;

  final bool privateChats;
  final bool groups;
  final bool channels;
  final bool bots;
  final bool mentions;
  final bool missedCalls;
  final bool mutedChats;

  /// Also covers connected apps: email, calendar, Slack, tasks.
  final bool apps;

  final BriefTone tone;
  final BriefLength length;

  /// Language briefs are written in; empty for the language of the chats.
  final String language;

  /// The user's own instructions for briefs.
  final String instructions;

  BriefPrefs copyWith({
    BriefScope? scope,
    Set<int>? chosen,
    Set<int>? excluded,
    Map<int, String>? chatTitles,
    bool? privateChats,
    bool? groups,
    bool? channels,
    bool? bots,
    bool? mentions,
    bool? missedCalls,
    bool? mutedChats,
    bool? apps,
    BriefTone? tone,
    BriefLength? length,
    String? language,
    String? instructions,
    List<String>? accountIds,
    bool allAccounts = false,
    Map<String, String>? excludedFolders,
  }) => BriefPrefs(
    scope: scope ?? this.scope,
    chosen: chosen ?? this.chosen,
    excluded: excluded ?? this.excluded,
    chatTitles: chatTitles ?? this.chatTitles,
    privateChats: privateChats ?? this.privateChats,
    groups: groups ?? this.groups,
    channels: channels ?? this.channels,
    bots: bots ?? this.bots,
    mentions: mentions ?? this.mentions,
    missedCalls: missedCalls ?? this.missedCalls,
    mutedChats: mutedChats ?? this.mutedChats,
    apps: apps ?? this.apps,
    tone: tone ?? this.tone,
    length: length ?? this.length,
    language: language ?? this.language,
    instructions: instructions ?? this.instructions,
    accountIds: allAccounts ? null : (accountIds ?? this.accountIds),
    excludedFolders: excludedFolders ?? this.excludedFolders,
  );

  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'chosen': chosen.toList(),
    'excluded': excluded.toList(),
    'titles': {for (final e in chatTitles.entries) '${e.key}': e.value},
    'dms': privateChats,
    'groups': groups,
    'channels': channels,
    'bots': bots,
    'mentions': mentions,
    'calls': missedCalls,
    'muted': mutedChats,
    'apps': apps,
    'tone': tone.name,
    'length': length.name,
    'language': language,
    'instructions': instructions,
    'accounts': ?accountIds,
    if (excludedFolders.isNotEmpty) 'excluded_folders': excludedFolders,
  };

  factory BriefPrefs.fromJson(Map<String, dynamic> j) {
    const d = BriefPrefs();
    Set<int> ids(Object? v) => {
      for (final x in (v as List? ?? const []))
        if (x is num) x.toInt(),
    };
    return BriefPrefs(
      scope: BriefScope.values.asNameMap()[j['scope']] ?? d.scope,
      chosen: ids(j['chosen']),
      excluded: ids(j['excluded']),
      chatTitles: {
        for (final e in ((j['titles'] as Map?) ?? const {}).entries)
          if (int.tryParse('${e.key}') case final id?) id: '${e.value}',
      },
      privateChats: j['dms'] ?? d.privateChats,
      groups: j['groups'] ?? d.groups,
      channels: j['channels'] ?? d.channels,
      bots: j['bots'] ?? d.bots,
      mentions: j['mentions'] ?? d.mentions,
      missedCalls: j['calls'] ?? d.missedCalls,
      mutedChats: j['muted'] ?? d.mutedChats,
      apps: j['apps'] ?? d.apps,
      tone: BriefTone.values.asNameMap()[j['tone']] ?? d.tone,
      length: BriefLength.values.asNameMap()[j['length']] ?? d.length,
      language: j['language'] ?? d.language,
      instructions: j['instructions'] ?? d.instructions,
      accountIds: (j['accounts'] as List?)?.map((e) => '$e').toList(),
      excludedFolders: {
        for (final e in ((j['excluded_folders'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
      },
    );
  }

  /// The kinds of chat covered, for the prompt and the settings summary.
  List<String> get kinds => [
    if (privateChats) 'private chats (DMs)',
    if (groups) 'groups',
    if (channels) 'channels',
    if (bots) 'bots',
  ];
}

class BriefPrefsController extends Notifier<BriefPrefs> {
  static const _key = 'brief_prefs.v1';

  @override
  BriefPrefs build() {
    _load();
    return const BriefPrefs();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) state = BriefPrefs.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('[BriefPrefs] $e');
    }
  }

  Future<void> update(BriefPrefs Function(BriefPrefs) change) async {
    state = change(state);
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> choose(int chatId, String title, {required bool excluded}) => update((p) {
    final chosen = {...p.chosen};
    final out = {...p.excluded};
    if (excluded) {
      out.add(chatId);
      chosen.remove(chatId);
    } else {
      chosen.add(chatId);
      out.remove(chatId);
    }
    return p.copyWith(chosen: chosen, excluded: out, chatTitles: {...p.chatTitles, chatId: title});
  });

  Future<void> drop(int chatId) => update(
    (p) => p.copyWith(
      chosen: {...p.chosen}..remove(chatId),
      excluded: {...p.excluded}..remove(chatId),
      chatTitles: {...p.chatTitles}..remove(chatId),
    ),
  );

  /// Leaves folder [folderId] of [accountId] out of briefs.
  Future<void> excludeFolder(String accountId, int folderId, String title) =>
      update((p) => p.copyWith(excludedFolders: {...p.excludedFolders, '$accountId:$folderId': title}));

  Future<void> dropFolder(String key) => update((p) => p.copyWith(excludedFolders: {...p.excludedFolders}..remove(key)));

  Future<void> reset() => update((_) => const BriefPrefs());
}

final briefPrefsProvider = NotifierProvider<BriefPrefsController, BriefPrefs>(BriefPrefsController.new);
