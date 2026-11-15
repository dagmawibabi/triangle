part of 'telegram_tools.dart';

// Reporting (chats, messages, group spam, a group's anti-spam), Telegram
// Premium (emoji status, Saved Messages tags, Telegram's own transcription,
// story stealth mode, boosts, giveaways) and Telegram Business (quick
// replies, away and greeting messages, opening hours, location, chatbot).

const _businessRecipients = {
  'type': 'object',
  'description':
      'Who it applies to: existing_chats, new_chats, contacts, non_contacts (booleans), chat_ids to include, '
      'excluded_chat_ids. Default: everyone.',
  'properties': {
    'existing_chats': {'type': 'boolean', 'description': 'Private chats that already exist.'},
    'new_chats': {'type': 'boolean', 'description': 'People writing for the first time.'},
    'contacts': {'type': 'boolean', 'description': 'People in the user\'s contacts.'},
    'non_contacts': {'type': 'boolean', 'description': 'People not in the contacts.'},
    'chat_ids': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'Specific private chats to include.'},
    'excluded_chat_ids': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'Private chats to leave out.'},
  },
};

final _premiumTools = <TelegramTool>[
  // ---- reporting
  TelegramTool(
    name: 'report_chat',
    label: 'Reporting to Telegram',
    category: ToolCategory.chats,
    requiresApproval: true,
    alwaysAsk: true,
    description:
        'Reports a chat, or messages in it (message_ids), to Telegram moderators: spam, violence, scams, illegal '
        'content and the like. Telegram asks for a reason in steps: give reason in words (e.g. "spam", "scam", '
        '"violence") and the closest option is picked at each step; without one, the options come back to ask the '
        'user. text adds a comment where Telegram wants one. Only when the user asks; it always asks first.',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The chat to report.'},
      'message_ids': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'Messages to report; empty reports the chat.'},
      'reason': {'type': 'string', 'description': 'Why, in words: spam, scam, fake, violence, child abuse, illegal drugs, personal details…'},
      'text': {'type': 'string', 'description': 'A comment for the moderators, when needed.'},
    }, ['chat_id']),
  ),
  TelegramTool(
    name: 'report_spam',
    label: 'Reporting spam',
    category: ToolCategory.members,
    requiresApproval: true,
    alwaysAsk: true,
    description:
        'Reports messages as spam. In a group the user administers, reports the members\' messages (message_ids) '
        'through Telegram\'s group spam report; elsewhere reports the chat (or messages) as spam. Pair with '
        'ban_member or delete_messages to also remove the spammer. Always asks first.',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The group or chat.'},
      'message_ids': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'The spam messages.'},
    }, ['chat_id']),
  ),
  TelegramTool(
    name: 'set_group_protection',
    label: 'Changing spam protection',
    category: ToolCategory.members,
    requiresApproval: true,
    description:
        'As an admin of a large group: turns Telegram\'s aggressive anti-spam on or off, and hides or shows the '
        'member list.',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The group.'},
      'aggressive_anti_spam': {'type': 'boolean', 'description': 'Telegram removes likely spam on its own.'},
      'hide_members': {'type': 'boolean', 'description': 'Only admins see the member list.'},
    }, ['chat_id']),
  ),
  // ---- Premium
  TelegramTool(
    name: 'list_emoji_statuses',
    label: 'Listing emoji statuses',
    category: ToolCategory.account,
    cost: ToolCost.telegram,
    description: 'Emoji statuses the user can wear next to their name (Premium): default and recent ones, with ids.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'set_emoji_status',
    label: 'Setting your emoji status',
    category: ToolCategory.account,
    requiresApproval: true,
    description:
        'Sets the emoji status next to the user\'s name (Telegram Premium), from list_emoji_statuses, for a while or '
        'until changed. clear true removes it.',
    parameters: _obj({
      'custom_emoji_id': {'type': 'string', 'description': 'The status\'s custom_emoji_id.'},
      'emoji': {'type': 'string', 'description': 'Or an emoji; the matching status is picked.'},
      'hours': {'type': 'number', 'description': 'How long it lasts; leave out for until changed.'},
      'clear': {'type': 'boolean', 'description': 'Remove the status.'},
    }),
  ),
  TelegramTool(
    name: 'saved_message_tags',
    label: 'Reading Saved Messages tags',
    category: ToolCategory.account,
    description:
        'The tags (reactions) used in Saved Messages (Premium), with their labels and how many messages each has. '
        'With emoji and label, names a tag.',
    parameters: _obj({
      'emoji': {'type': 'string', 'description': 'A tag\'s emoji, to label it.'},
      'label': {'type': 'string', 'description': 'The new label for that tag (empty removes it).'},
    }),
  ),
  TelegramTool(
    name: 'telegram_transcribe',
    label: 'Transcribing with Telegram',
    category: ToolCategory.media,
    description:
        'Telegram\'s own speech-to-text for a voice note or video note (Premium, or a few free tries a week). Waits '
        'up to wait_seconds for the text. transcribe_message uses the app\'s AI keys instead.',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The chat.'},
      'message_id': {'type': 'integer', 'description': 'The voice or video note.'},
      'wait_seconds': {'type': 'integer', 'description': '1-60, default 25.'},
    }, ['chat_id', 'message_id']),
  ),
  TelegramTool(
    name: 'story_stealth_mode',
    label: 'Turning on stealth mode',
    category: ToolCategory.stories,
    requiresApproval: true,
    description:
        'Story stealth mode (Premium): hides that the user viewed stories in the last 5 minutes and for the next 25. '
        'Can be used again after a cooldown.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'list_boost_slots',
    label: 'Checking your boosts',
    category: ToolCategory.account,
    description: 'The user\'s Premium boost slots: which chat each boosts, until when, and which are free.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'boost_chat',
    label: 'Boosting a channel',
    category: ToolCategory.chats,
    requiresApproval: true,
    description:
        'Gives a channel or group the user\'s Premium boosts (slots from list_boost_slots; default the free ones, '
        'or one slot when none is free, moving it).',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The channel or group.'},
      'slot_ids': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'Which slots; default the free ones.'},
    }, ['chat_id']),
  ),
  TelegramTool(
    name: 'giveaway_info',
    label: 'Checking a giveaway',
    category: ToolCategory.chats,
    description: 'A giveaway post\'s state: ongoing or finished, whether the user takes part or won, winners count.',
    parameters: _obj({
      'chat_id': {'type': 'integer', 'description': 'The channel.'},
      'message_id': {'type': 'integer', 'description': 'The giveaway message.'},
    }, ['chat_id', 'message_id']),
  ),
  // ---- Business
  TelegramTool(
    name: 'list_quick_replies',
    label: 'Listing quick replies',
    category: ToolCategory.account,
    description:
        'The user\'s Telegram Business quick replies (shortcuts like /hello), with ids and their first message. Away '
        'and greeting messages use one of these.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'set_away_message',
    label: 'Setting the away message',
    category: ToolCategory.account,
    requiresApproval: true,
    description:
        'Telegram Business: sends a quick reply automatically when the user is away. schedule: always, '
        'outside_hours (outside opening hours) or custom (from and until, ISO times). off true turns it off.',
    parameters: _obj({
      'shortcut': {'type': 'string', 'description': 'The quick reply\'s name (e.g. away) or id.'},
      'schedule': {'type': 'string', 'enum': ['always', 'outside_hours', 'custom'], 'description': 'Default always.'},
      'from': {'type': 'string', 'description': 'custom: ISO start time.'},
      'until': {'type': 'string', 'description': 'custom: ISO end time.'},
      'offline_only': {'type': 'boolean', 'description': 'Only when the user is offline.'},
      'recipients': _businessRecipients,
      'off': {'type': 'boolean', 'description': 'Turn the away message off.'},
    }),
  ),
  TelegramTool(
    name: 'set_greeting_message',
    label: 'Setting the greeting',
    category: ToolCategory.account,
    requiresApproval: true,
    description:
        'Telegram Business: greets people who write for the first time, or after inactivity_days (7, 14, 21 or 28) '
        'of silence, with a quick reply. off true turns it off.',
    parameters: _obj({
      'shortcut': {'type': 'string', 'description': 'The quick reply\'s name (e.g. hello) or id.'},
      'inactivity_days': {'type': 'integer', 'description': '7, 14, 21 or 28; default 7.'},
      'recipients': _businessRecipients,
      'off': {'type': 'boolean', 'description': 'Turn the greeting off.'},
    }),
  ),
  TelegramTool(
    name: 'set_opening_hours',
    label: 'Setting opening hours',
    category: ToolCategory.account,
    requiresApproval: true,
    description:
        'Telegram Business: the opening hours shown on the profile. hours: [{"day": "mon", "open": "09:00", '
        '"close": "17:00"}, …] (days mon-sun; close after midnight runs into the next day). off true removes them.',
    parameters: _obj({
      'time_zone': {'type': 'string', 'description': 'IANA time zone, e.g. Africa/Addis_Ababa; default the phone\'s.'},
      'hours': {'type': 'array', 'items': {'type': 'object'}, 'description': 'Opening intervals by day.'},
      'off': {'type': 'boolean', 'description': 'Remove the opening hours.'},
    }),
  ),
  TelegramTool(
    name: 'set_business_location',
    label: 'Setting the business address',
    category: ToolCategory.account,
    requiresApproval: true,
    description: 'Telegram Business: the address (and map point) shown on the profile. off true removes it.',
    parameters: _obj({
      'address': {'type': 'string', 'description': 'The address as written.'},
      'latitude': {'type': 'number', 'description': 'Optional map point.'},
      'longitude': {'type': 'number', 'description': 'Optional map point.'},
      'off': {'type': 'boolean', 'description': 'Remove the location.'},
    }),
  ),
  TelegramTool(
    name: 'set_business_bot',
    label: 'Connecting a business bot',
    category: ToolCategory.bots,
    requiresApproval: true,
    alwaysAsk: true,
    description:
        'Telegram Business: connects a chatbot (by @username) that can read and answer the user\'s private chats '
        '(can_reply), for the recipients given; off true disconnects it. The bot sees those chats, so it always asks.',
    parameters: _obj({
      'bot': {'type': 'string', 'description': 'The bot\'s @username.'},
      'can_reply': {'type': 'boolean', 'description': 'Let it answer, not only read; default true.'},
      'recipients': _businessRecipients,
      'off': {'type': 'boolean', 'description': 'Disconnect the current bot.'},
    }),
  ),
];

const _premiumToolPolicies = <String, ToolPolicy>{
  'report_chat': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'report_spam': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'set_group_protection': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'list_emoji_statuses': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'set_emoji_status': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'saved_message_tags': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'telegram_transcribe': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'story_stealth_mode': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'list_boost_slots': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'boost_chat': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'giveaway_info': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'list_quick_replies': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'set_away_message': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'set_greeting_message': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'set_opening_hours': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'set_business_location': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'set_business_bot': ToolPolicy(ToolAccess.modify, needsTelegram: true),
};

const _premiumToolReferences = <String, ToolReference>{
  'report_chat': ToolReference(['reported', 'chat', 'reason', 'options (when a reason is needed)', 'needs_text']),
  'report_spam': ToolReference(['reported', 'chat', 'messages', 'how']),
  'set_group_protection': ToolReference(['chat', 'aggressive_anti_spam', 'hide_members']),
  'list_emoji_statuses': ToolReference(['statuses: custom_emoji_id, emoji', 'premium']),
  'set_emoji_status': ToolReference(['status', 'until']),
  'saved_message_tags': ToolReference(['tags: emoji, label, count', 'labeled']),
  'telegram_transcribe': ToolReference(['text', 'pending', 'error']),
  'story_stealth_mode': ToolReference(['active']),
  'list_boost_slots': ToolReference(['slots: slot_id, boosting, until, free, cooldown_until']),
  'boost_chat': ToolReference(['boosted', 'chat', 'slots']),
  'giveaway_info': ToolReference(['state, created, taking_part, won, winners_selected, refunded']),
  'list_quick_replies': ToolReference(['shortcuts: id, name, messages, first_message']),
  'set_away_message': ToolReference(['away_message: on/off, shortcut, schedule']),
  'set_greeting_message': ToolReference(['greeting: on/off, shortcut, inactivity_days']),
  'set_opening_hours': ToolReference(['opening_hours: on/off, time_zone, intervals']),
  'set_business_location': ToolReference(['location: on/off, address']),
  'set_business_bot': ToolReference(['bot: on/off, username, can_reply']),
};

extension _PremiumToolRuns on TelegramToolRunner {
  bool get _premium => _store.me?.isPremium == true;

  ToolOutput _needsPremium(String what) =>
      ToolOutput({'error': '$what needs Telegram Premium, and this account doesn\'t have it.', 'premium': false});

  List<int> _intList(Map<String, dynamic> args, String key) => [
    for (final v in (args[key] as List? ?? const []))
      if (v is num) v.toInt() else if (int.tryParse('$v') case final n?) n,
  ];

  td.BusinessRecipients _recipients(Object? raw) {
    final r = raw is Map ? raw : const {};
    List<int> ids(String k) => [for (final v in (r[k] as List? ?? const [])) if (v is num) v.toInt()];
    final any = r.isNotEmpty;
    return td.BusinessRecipients(
      chatIds: ids('chat_ids'),
      excludedChatIds: ids('excluded_chat_ids'),
      selectExistingChats: any ? r['existing_chats'] == true : true,
      selectNewChats: any ? r['new_chats'] == true : true,
      selectContacts: any ? r['contacts'] == true : true,
      selectNonContacts: any ? r['non_contacts'] == true : true,
      excludeSelected: false,
    );
  }

  /// The user's quick replies, gathered from the updates Telegram sends
  /// after asking it to load them.
  Future<List<td.QuickReplyShortcut>> _quickReplies() async {
    final found = <int, td.QuickReplyShortcut>{};
    final sub = _client.updates.listen((u) {
      if (u is td.UpdateQuickReplyShortcut) found[u.shortcut.id] = u.shortcut;
    });
    try {
      await _client.send<td.Ok>(const td.LoadQuickReplyShortcuts());
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    } finally {
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<td.QuickReplyShortcut> _shortcut(Map<String, dynamic> args) async {
    final want = '${args['shortcut'] ?? ''}'.trim().replaceFirst('/', '').toLowerCase();
    if (want.isEmpty) throw ArgumentError('Give shortcut: a quick reply\'s name or id (list_quick_replies).');
    final all = await _quickReplies();
    final hit = all.where((s) => '${s.id}' == want || s.name.toLowerCase() == want).firstOrNull;
    if (hit == null) {
      throw ArgumentError('No quick reply "$want". The user has: ${all.isEmpty ? 'none (make one in Telegram: Settings → Business → Quick replies)' : all.map((s) => '/${s.name}').join(', ')}.');
    }
    return hit;
  }

  String _text(td.MessageContent c) => switch (c) {
    td.MessageText(:final text) => text.text,
    _ => gistOf(c).text.isNotEmpty ? gistOf(c).text : gistOf(c).kind,
  };

  Future<ToolOutput>? _runPremium(String name, Map<String, dynamic> args) => switch (name) {
    'report_chat' => () async {
      final c = _requireChat(args);
      final ids = _intList(args, 'message_ids');
      final reason = '${args['reason'] ?? ''}'.toLowerCase().trim();
      var option = '';
      final chosen = <String>[];
      for (var step = 0; step < 4; step++) {
        final r = await _client.send<td.ReportChatResult>(
          td.ReportChat(chatId: c.id, optionId: option, messageIds: ids, text: '${args['text'] ?? ''}'),
          limited: true,
        );
        switch (r) {
          case td.ReportChatResultOk():
            return ToolOutput({'reported': true, 'chat': c.title, if (ids.isNotEmpty) 'messages': ids.length, 'reason': chosen.join(' → ')});
          case td.ReportChatResultTextRequired(:final optionId, :final isOptional):
            if (!isOptional && '${args['text'] ?? ''}'.trim().isEmpty) {
              return ToolOutput({'reported': false, 'needs_text': true, 'note': 'Telegram wants a short comment for "${chosen.join(' → ')}": ask the user, then call again with text and the same reason.'});
            }
            option = optionId;
          case td.ReportChatResultOptionRequired(:final title, :final options):
            final words = reason.split(RegExp(r'[^a-z]+')).where((w) => w.length > 2);
            final pick = reason.isEmpty
                ? null
                : options.where((o) => words.any(o.text.toLowerCase().contains)).firstOrNull;
            if (pick == null) {
              return ToolOutput({
                'reported': false,
                'question': title,
                'options': [for (final o in options) o.text],
                'note': 'Ask the user which fits, then call again with reason set to it.',
              });
            }
            chosen.add(pick.text);
            option = pick.id;
          case td.ReportChatResultMessagesRequired():
            return ToolOutput({'reported': false, 'note': 'Telegram wants the messages to report: call again with message_ids.'});
        }
      }
      return ToolOutput({'reported': false, 'note': 'Telegram kept asking for more; report it from the Telegram app.'});
    }(),
    'report_spam' => () async {
      final c = _requireChat(args);
      final ids = _intList(args, 'message_ids');
      if (c.type case td.ChatTypeSupergroup(:final supergroupId, isChannel: false) when ids.isNotEmpty && _store.isAdmin(c)) {
        await _client.send<td.Ok>(td.ReportSupergroupSpam(supergroupId: supergroupId, messageIds: ids), limited: true);
        return ToolOutput({'reported': true, 'chat': c.title, 'messages': ids.length, 'how': 'group spam report'});
      }
      return _runPremium('report_chat', {...args, 'reason': 'spam'})!;
    }(),
    'set_group_protection' => () async {
      final c = _requireChat(args);
      final sg = switch (c.type) {
        td.ChatTypeSupergroup(:final supergroupId, isChannel: false) => supergroupId,
        _ => throw ArgumentError('Only for groups (supergroups).'),
      };
      if (args['aggressive_anti_spam'] is bool) {
        await _client.send<td.Ok>(td.ToggleSupergroupHasAggressiveAntiSpamEnabled(supergroupId: sg, hasAggressiveAntiSpamEnabled: args['aggressive_anti_spam'] as bool), limited: true);
      }
      if (args['hide_members'] is bool) {
        await _client.send<td.Ok>(td.ToggleSupergroupHasHiddenMembers(supergroupId: sg, hasHiddenMembers: args['hide_members'] as bool), limited: true);
      }
      return ToolOutput({'chat': c.title, 'aggressive_anti_spam': ?args['aggressive_anti_spam'], 'hide_members': ?args['hide_members']});
    }(),
    'list_emoji_statuses' => () async {
      final def = await _client.send<td.EmojiStatuses>(const td.GetDefaultEmojiStatuses());
      final recent = await _client.send<td.EmojiStatuses>(const td.GetRecentEmojiStatuses());
      final ids = <int>{
        for (final s in [...recent.emojiStatuses, ...def.emojiStatuses])
          if (s.type case td.EmojiStatusTypeCustomEmoji(:final customEmojiId)) customEmojiId,
      }.take(60).toList();
      final stickers = ids.isEmpty ? const <td.Sticker>[] : (await _client.send<td.Stickers>(td.GetCustomEmojiStickers(customEmojiIds: ids))).stickers;
      final emojiOf = {
        for (final s in stickers)
          if (s.fullType case td.StickerFullTypeCustomEmoji(:final customEmojiId)) customEmojiId: s.emoji,
      };
      return ToolOutput({
        'premium': _premium,
        'statuses': [for (final id in ids) {'custom_emoji_id': '$id', 'emoji': emojiOf[id] ?? ''}],
      });
    }(),
    'set_emoji_status' => () async {
      if (!_premium) return _needsPremium('An emoji status');
      if (args['clear'] == true) {
        await _client.send<td.Ok>(const td.SetEmojiStatus(emojiStatus: null));
        return ToolOutput({'status': null});
      }
      var id = int.tryParse('${args['custom_emoji_id'] ?? ''}');
      if (id == null && '${args['emoji'] ?? ''}'.isNotEmpty) {
        final list = (await _runPremium('list_emoji_statuses', const {})!).json['statuses'] as List;
        final hit = list.cast<Map>().where((s) => s['emoji'] == '${args['emoji']}').firstOrNull;
        id = int.tryParse('${hit?['custom_emoji_id']}');
        if (id == null) return ToolOutput({'error': 'No status for ${args['emoji']}. Use one from list_emoji_statuses.'});
      }
      if (id == null) throw ArgumentError('Give custom_emoji_id or emoji.');
      final hours = (args['hours'] as num?)?.toDouble();
      final until = hours == null ? 0 : DateTime.now().add(Duration(minutes: (hours * 60).round())).millisecondsSinceEpoch ~/ 1000;
      await _client.send<td.Ok>(td.SetEmojiStatus(emojiStatus: td.EmojiStatus(type: td.EmojiStatusTypeCustomEmoji(customEmojiId: id), expirationDate: until)));
      return ToolOutput({'status': '$id', 'until': until == 0 ? 'changed' : DateTime.fromMillisecondsSinceEpoch(until * 1000).toIso8601String().substring(0, 16)});
    }(),
    'saved_message_tags' => () async {
      if (!_premium) return _needsPremium('Saved Messages tags');
      final emoji = '${args['emoji'] ?? ''}'.trim();
      if (emoji.isNotEmpty && args.containsKey('label')) {
        await _client.send<td.Ok>(td.SetSavedMessagesTagLabel(tag: td.ReactionTypeEmoji(emoji: emoji), label: '${args['label'] ?? ''}'));
      }
      final tags = await _client.send<td.SavedMessagesTags>(const td.GetSavedMessagesTags(savedMessagesTopicId: 0));
      return ToolOutput({
        'tags': [
          for (final t in tags.tags)
            {
              'emoji': switch (t.tag) {
                td.ReactionTypeEmoji(:final emoji) => emoji,
                td.ReactionTypeCustomEmoji(:final customEmojiId) => 'custom:$customEmojiId',
                _ => '?',
              },
              if (t.label.isNotEmpty) 'label': t.label,
              'count': t.count,
            },
        ],
        if (emoji.isNotEmpty && args.containsKey('label')) 'labeled': emoji,
      });
    }(),
    'telegram_transcribe' => () async {
      final c = _requireChat(args);
      final id = TelegramToolRunner._intOrNull(args, 'message_id') ?? (throw ArgumentError('message_id is required'));
      await _client.send<td.Ok>(td.RecognizeSpeech(chatId: c.id, messageId: id), limited: true);
      final wait = ((args['wait_seconds'] as num?)?.toInt() ?? 25).clamp(1, 60);
      var partial = '';
      for (var i = 0; i < wait * 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final m = await _client.send<td.Message>(td.GetMessage(chatId: c.id, messageId: id));
        final r = switch (m.content) {
          td.MessageVoiceNote(:final voiceNote) => voiceNote.speechRecognitionResult,
          td.MessageVideoNote(:final videoNote) => videoNote.speechRecognitionResult,
          _ => throw ArgumentError('That message isn\'t a voice or video note.'),
        };
        switch (r) {
          case td.SpeechRecognitionResultText(:final text):
            return ToolOutput({'text': text, 'chat': c.title});
          case td.SpeechRecognitionResultError(:final error):
            return ToolOutput({'error': 'Telegram couldn\'t transcribe it: ${error.message}${_premium ? '' : ' (free accounts get a few a week; transcribe_message uses the app\'s AI instead)'}'});
          case td.SpeechRecognitionResultPending(:final partialText):
            partial = partialText;
          case null:
            break;
        }
      }
      return ToolOutput({'pending': true, if (partial.isNotEmpty) 'text': partial, 'note': 'Still transcribing; call again shortly.'});
    }(),
    'story_stealth_mode' => () async {
      if (!_premium) return _needsPremium('Story stealth mode');
      await _client.send<td.Ok>(const td.ActivateStoryStealthMode());
      return ToolOutput({'active': true, 'note': 'Views from the last 5 minutes and the next 25 are hidden.'});
    }(),
    'list_boost_slots' => () async {
      final s = await _client.send<td.ChatBoostSlots>(const td.GetAvailableChatBoostSlots());
      String? date(int t) => t == 0 ? null : DateTime.fromMillisecondsSinceEpoch(t * 1000).toIso8601String().substring(0, 10);
      return ToolOutput({
        'premium': _premium,
        'slots': [
          for (final x in s.slots)
            {
              'slot_id': x.slotId,
              'free': x.currentlyBoostedChatId == 0,
              if (x.currentlyBoostedChatId != 0) 'boosting': _store.chat(x.currentlyBoostedChatId)?.title ?? x.currentlyBoostedChatId,
              'until': ?date(x.expirationDate),
              'cooldown_until': ?date(x.cooldownUntilDate),
            },
        ],
      });
    }(),
    'boost_chat' => () async {
      final c = _requireChat(args);
      var slots = _intList(args, 'slot_ids');
      if (slots.isEmpty) {
        final all = (await _client.send<td.ChatBoostSlots>(const td.GetAvailableChatBoostSlots())).slots;
        if (all.isEmpty) return _needsPremium('Boosting');
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final free = [for (final x in all) if (x.currentlyBoostedChatId == 0) x.slotId];
        slots = free.isNotEmpty ? free : [for (final x in all) if (x.cooldownUntilDate <= now && x.currentlyBoostedChatId != c.id) x.slotId].take(1).toList();
        if (slots.isEmpty) return ToolOutput({'error': 'No boost slot can move yet (they\'re cooling down or already on this chat).'});
      }
      await _client.send<td.ChatBoostSlots>(td.BoostChat(chatId: c.id, slotIds: slots), limited: true);
      return ToolOutput({'boosted': true, 'chat': c.title, 'slots': slots});
    }(),
    'giveaway_info' => () async {
      final c = _requireChat(args);
      final id = TelegramToolRunner._intOrNull(args, 'message_id') ?? (throw ArgumentError('message_id is required'));
      final g = await _client.send<td.GiveawayInfo>(td.GetGiveawayInfo(chatId: c.id, messageId: id));
      String d(int t) => DateTime.fromMillisecondsSinceEpoch(t * 1000).toIso8601String().substring(0, 10);
      return ToolOutput(switch (g) {
        td.GiveawayInfoOngoing(:final creationDate, :final status, :final isEnded) => {
          'state': isEnded ? 'ended, winners not chosen yet' : 'ongoing',
          'created': d(creationDate),
          'taking_part': status is td.GiveawayParticipantStatusParticipating,
          'status': status.runtimeType.toString().replaceFirst('GiveawayParticipantStatus', ''),
        },
        td.GiveawayInfoCompleted(:final creationDate, :final actualWinnersSelectionDate, :final wasRefunded, :final isWinner) => {
          'state': 'finished',
          'created': d(creationDate),
          'winners_selected': d(actualWinnersSelectionDate),
          'won': isWinner,
          if (wasRefunded) 'refunded': true,
        },
      });
    }(),
    'list_quick_replies' => () async {
      final all = await _quickReplies();
      return ToolOutput({
        'shortcuts': [
          for (final s in all) {'id': s.id, 'name': '/${s.name}', 'messages': s.messageCount, 'first_message': _text(s.firstMessage.content)},
        ],
        if (all.isEmpty) 'note': 'No quick replies. Make them in Telegram: Settings → Business → Quick replies.',
      });
    }(),
    'set_away_message' => () async {
      if (args['off'] == true) {
        await _client.send<td.Ok>(const td.SetBusinessAwayMessageSettings(awayMessageSettings: null));
        return ToolOutput({'away_message': 'off'});
      }
      if (!_premium) return _needsPremium('An away message (Telegram Business)');
      final s = await _shortcut(args);
      int t(String k) => (DateTime.tryParse('${args[k] ?? ''}') ?? (throw ArgumentError('custom needs $k as an ISO time'))).millisecondsSinceEpoch ~/ 1000;
      final schedule = switch ('${args['schedule'] ?? 'always'}') {
        'outside_hours' => const td.BusinessAwayMessageScheduleOutsideOfOpeningHours() as td.BusinessAwayMessageSchedule,
        'custom' => td.BusinessAwayMessageScheduleCustom(startDate: t('from'), endDate: t('until')),
        _ => const td.BusinessAwayMessageScheduleAlways(),
      };
      await _client.send<td.Ok>(td.SetBusinessAwayMessageSettings(
        awayMessageSettings: td.BusinessAwayMessageSettings(shortcutId: s.id, recipients: _recipients(args['recipients']), schedule: schedule, offlineOnly: args['offline_only'] == true),
      ));
      return ToolOutput({'away_message': 'on', 'shortcut': '/${s.name}', 'schedule': args['schedule'] ?? 'always'});
    }(),
    'set_greeting_message' => () async {
      if (args['off'] == true) {
        await _client.send<td.Ok>(const td.SetBusinessGreetingMessageSettings(greetingMessageSettings: null));
        return ToolOutput({'greeting': 'off'});
      }
      if (!_premium) return _needsPremium('A greeting message (Telegram Business)');
      final s = await _shortcut(args);
      final days = (args['inactivity_days'] as num?)?.toInt() ?? 7;
      final allowed = const [7, 14, 21, 28].reduce((a, b) => (a - days).abs() <= (b - days).abs() ? a : b);
      await _client.send<td.Ok>(td.SetBusinessGreetingMessageSettings(
        greetingMessageSettings: td.BusinessGreetingMessageSettings(shortcutId: s.id, recipients: _recipients(args['recipients']), inactivityDays: allowed),
      ));
      return ToolOutput({'greeting': 'on', 'shortcut': '/${s.name}', 'inactivity_days': allowed});
    }(),
    'set_opening_hours' => () async {
      if (args['off'] == true) {
        await _client.send<td.Ok>(const td.SetBusinessOpeningHours(openingHours: null));
        return ToolOutput({'opening_hours': 'off'});
      }
      if (!_premium) return _needsPremium('Opening hours (Telegram Business)');
      const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      int minute(String hhmm) {
        final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim()) ?? (throw ArgumentError('Times are HH:MM, got "$hhmm".'));
        return int.parse(m[1]!) * 60 + int.parse(m[2]!);
      }

      final intervals = <td.BusinessOpeningHoursInterval>[];
      for (final h in (args['hours'] as List? ?? const [])) {
        if (h is! Map) continue;
        final day = days.indexWhere((d) => '${h['day']}'.toLowerCase().startsWith(d));
        if (day < 0) throw ArgumentError('Unknown day "${h['day']}"; use mon-sun.');
        final open = minute('${h['open']}'), close = minute('${h['close']}');
        final start = day * 1440 + open;
        intervals.add(td.BusinessOpeningHoursInterval(startMinute: start, endMinute: day * 1440 + (close <= open ? close + 1440 : close)));
      }
      if (intervals.isEmpty) throw ArgumentError('Give hours: [{"day": "mon", "open": "09:00", "close": "17:00"}].');
      final zone = '${args['time_zone'] ?? ''}'.trim().isNotEmpty ? '${args['time_zone']}' : DateTime.now().timeZoneName;
      await _client.send<td.Ok>(td.SetBusinessOpeningHours(openingHours: td.BusinessOpeningHours(timeZoneId: zone, openingHours: intervals)));
      return ToolOutput({'opening_hours': 'on', 'time_zone': zone, 'intervals': intervals.length});
    }(),
    'set_business_location' => () async {
      if (args['off'] == true) {
        await _client.send<td.Ok>(const td.SetBusinessLocation(location: null));
        return ToolOutput({'location': 'off'});
      }
      if (!_premium) return _needsPremium('A business location (Telegram Business)');
      final address = '${args['address'] ?? ''}'.trim();
      if (address.isEmpty) throw ArgumentError('Give address.');
      final lat = (args['latitude'] as num?)?.toDouble(), lon = (args['longitude'] as num?)?.toDouble();
      await _client.send<td.Ok>(td.SetBusinessLocation(
        location: td.BusinessLocation(address: address, location: lat == null || lon == null ? null : td.Location(latitude: lat, longitude: lon, horizontalAccuracy: 0)),
      ));
      return ToolOutput({'location': 'on', 'address': address});
    }(),
    'set_business_bot' => () async {
      if (args['off'] == true) {
        final current = await _client.send<td.BusinessConnectedBot>(const td.GetBusinessConnectedBot());
        await _client.send<td.Ok>(td.DeleteBusinessConnectedBot(botUserId: current.botUserId));
        return ToolOutput({'bot': 'off'});
      }
      if (!_premium) return _needsPremium('A business chatbot (Telegram Business)');
      final username = '${args['bot'] ?? ''}'.trim().replaceFirst('@', '');
      if (username.isEmpty) throw ArgumentError('Give bot: its @username.');
      final chat = await _client.send<td.Chat>(td.SearchPublicChat(username: username));
      final botId = switch (chat.type) {
        td.ChatTypePrivate(:final userId) => userId,
        _ => throw ArgumentError('@$username isn\'t a bot.'),
      };
      final reply = args['can_reply'] != false;
      await _client.send<td.Ok>(td.SetBusinessConnectedBot(
        bot: td.BusinessConnectedBot(
          botUserId: botId,
          recipients: _recipients(args['recipients']),
          rights: td.BusinessBotRights(
            canReply: reply,
            canReadMessages: true,
            canDeleteSentMessages: false,
            canDeleteAllMessages: false,
            canEditName: false,
            canEditBio: false,
            canEditProfilePhoto: false,
            canEditUsername: false,
            canViewGiftsAndStars: false,
            canSellGifts: false,
            canChangeGiftSettings: false,
            canTransferAndUpgradeGifts: false,
            canTransferStars: false,
            canManageStories: false,
          ),
        ),
      ));
      return ToolOutput({'bot': 'on', 'username': '@$username', 'can_reply': reply});
    }(),
    _ => null,
  };

  String? _describePremium(String name, Map<String, dynamic> args, String title) => switch (name) {
    'report_chat' => '⚠ Report ${(args['message_ids'] as List?)?.isNotEmpty == true ? '${(args['message_ids'] as List).length} message(s) in ' : ''}$title to Telegram'
        '${args['reason'] != null ? ' for ${args['reason']}' : ''}',
    'report_spam' => '⚠ Report spam in $title',
    'set_group_protection' => 'Change spam protection in $title',
    'set_emoji_status' => args['clear'] == true ? 'Remove your emoji status' : 'Set your emoji status${args['emoji'] != null ? ' to ${args['emoji']}' : ''}',
    'story_stealth_mode' => 'Turn on story stealth mode',
    'boost_chat' => 'Boost $title with your Premium boosts',
    'set_away_message' => args['off'] == true ? 'Turn off your away message' : 'Auto-reply /${args['shortcut']} when you\'re away',
    'set_greeting_message' => args['off'] == true ? 'Turn off your greeting' : 'Greet new chats with /${args['shortcut']}',
    'set_opening_hours' => args['off'] == true ? 'Remove your opening hours' : 'Set your business opening hours',
    'set_business_location' => args['off'] == true ? 'Remove your business address' : 'Set your business address to ${args['address']}',
    'set_business_bot' => args['off'] == true ? 'Disconnect your business bot' : '⚠ Let @${'${args['bot']}'.replaceFirst('@', '')} read${args['can_reply'] == false ? '' : ' and answer'} your private chats',
    _ => null,
  };
}
