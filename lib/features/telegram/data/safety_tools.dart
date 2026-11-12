import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/accounts.dart';
import '../../settings/data/system_check.dart';
import 'content_filters.dart';
import 'telegram_store.dart';
import 'telegram_tools.dart' show ToolOutput;

// Runs the tools in telegram_safety_tools.dart: the system check, and
// Block & mute.

Future<ToolOutput> runSafetyTool(
  ProviderReader read,
  String name,
  Map<String, dynamic> a, {
  required String account,
}) async {
  List<String> strings(String k) => [
    for (final x in (a[k] as List? ?? const [])) '$x'.trim(),
  ].where((s) => s.isNotEmpty).toList();
  bool? flag(String k) => a[k] is bool ? a[k] as bool : null;
  final store = read(telegramStoreFamily(account));
  final filters = read(contentFiltersProvider.notifier);

  /// Everything Block & mute hides now, returned by every Block & mute tool.
  Map<String, dynamic> hidden() {
    final f = read(contentFiltersProvider);
    return {
      'blocked_chats': [
        for (final e in f.blockedChats.entries)
          {
            'id': e.key,
            'title': store.chat(e.key)?.title ?? e.value,
            'kind': switch (store.chat(e.key)) {
              final c? => store.kindOf(c) == ChatKind.channel ? 'channel' : 'group',
              null => 'chat',
            },
          },
      ],
      'muted_words': f.mutedWords,
      'blocked_accounts': read(blockedSendersProvider).length,
      'notices': {'accounts': f.labelBlockedAccounts, 'chats': f.labelBlockedChats, 'words': f.labelMutedWords},
      'in_archived': f.inArchived,
    };
  }

  /// The channel or group the call names: by chat id, or a public @username.
  Future<({int id, String title, ChatKind kind})> chat() async {
    final client = read(telegramClientFamily(account));
    final id = a['chat_id'] is num ? (a['chat_id'] as num).toInt() : int.tryParse('${a['chat_id'] ?? ''}');
    final username = '${a['username'] ?? ''}'.trim().replaceFirst(RegExp(r'^(https?://)?(t\.me/|@)'), '');
    ChatInfo? info = id == null ? null : store.chat(id);
    if (info == null) {
      final td.Chat c;
      if (id != null) {
        c = await client.send<td.Chat>(td.GetChat(chatId: id), limited: true);
      } else if (username.isNotEmpty) {
        c = await client.send<td.Chat>(td.SearchPublicChat(username: username), limited: true);
      } else {
        throw ArgumentError('Give chat_id or username.');
      }
      info = store.chat(c.id) ?? ChatInfo(id: c.id, title: c.title, type: c.type);
    }
    return (id: info.id, title: info.title, kind: store.kindOf(info));
  }

  switch (name) {
    case 'system_check':
      final areas = strings('areas').toSet();
      final unknown = areas.difference(systemCheckAreas.keys.toSet());
      if (unknown.isNotEmpty) {
        return ToolOutput({'error': 'Unknown areas: ${unknown.join(', ')}. Use: ${systemCheckAreas.keys.join(', ')}.'});
      }
      final groups = await SystemChecker(read).run(only: areas);
      return ToolOutput(SystemChecker.toJson(groups));

    case 'list_hidden':
      return ToolOutput(hidden());

    case 'block_chat':
      final c = await chat();
      if (c.kind != ChatKind.channel && c.kind != ChatKind.group) {
        return ToolOutput({
          'error': '${c.title} is a ${c.kind.name} chat. block_chat is for channels and groups; block people and bots with block_user.',
        });
      }
      await filters.blockChat(c.id, c.title);
      return ToolOutput({'blocked': {'id': c.id, 'title': c.title}, ...hidden()});

    case 'unblock_chat':
      final f = read(contentFiltersProvider);
      final id = a['chat_id'] is num ? (a['chat_id'] as num).toInt() : int.tryParse('${a['chat_id'] ?? ''}');
      // A blocked chat may be gone from Telegram; its id is enough.
      final int targetId;
      final String targetTitle;
      if (id != null && f.blockedChats.containsKey(id)) {
        targetId = id;
        targetTitle = store.chat(id)?.title ?? f.blockedChats[id]!;
      } else {
        final c = await chat();
        targetId = c.id;
        targetTitle = c.title;
      }
      if (!f.blockedChats.containsKey(targetId)) {
        return ToolOutput({'error': '$targetTitle isn\'t blocked.', ...hidden()});
      }
      await filters.unblockChat(targetId);
      return ToolOutput({'unblocked': {'id': targetId, 'title': targetTitle}, ...hidden()});

    case 'mute_words':
      final words = strings('words');
      if (words.isEmpty) return const ToolOutput({'error': 'Give the words to mute.'});
      final muted = <String>[];
      final already = <String>[];
      for (final w in words) {
        (filters.muteWord(w) ? muted : already).add(w);
      }
      return ToolOutput({'muted': muted, if (already.isNotEmpty) 'already_muted': already, ...hidden()});

    case 'unmute_words':
      final current = read(contentFiltersProvider).mutedWords;
      final all = flag('all') == true;
      final asked = {for (final w in strings('words')) w.toLowerCase()};
      if (!all && asked.isEmpty) return const ToolOutput({'error': 'Give the words to unmute, or all: true.'});
      final unmuted = [for (final w in current) if (all || asked.contains(w.toLowerCase())) w];
      for (final w in unmuted) {
        await filters.unmuteWord(w);
      }
      final missing = all ? const <String>[] : [for (final w in strings('words')) if (!current.any((x) => x.toLowerCase() == w.toLowerCase())) w];
      return ToolOutput({'unmuted': unmuted, if (missing.isNotEmpty) 'not_muted': missing, ...hidden()});

    case 'block_mute_settings':
      final changed = <String>[
        if (flag('notice_for_accounts') != null) 'notice_for_accounts',
        if (flag('notice_for_chats') != null) 'notice_for_chats',
        if (flag('notice_for_words') != null) 'notice_for_words',
        if (flag('in_archived') != null) 'in_archived',
      ];
      if (changed.isEmpty) return const ToolOutput({'error': 'Nothing to change: give at least one setting.'});
      await filters.setLabels(
        accounts: flag('notice_for_accounts'),
        chats: flag('notice_for_chats'),
        words: flag('notice_for_words'),
      );
      if (flag('in_archived') case final v?) await filters.setInArchived(v);
      return ToolOutput({'changed': changed, ...hidden()});
  }
  return ToolOutput({'error': 'Unknown tool $name.'});
}
