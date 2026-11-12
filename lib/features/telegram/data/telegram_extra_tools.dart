part of 'telegram_tools.dart';

// The rest of what TDLib offers that fits an assistant: stories, contacts,
// drafts, starting bots, boosts and statistics.

final _extraTools = <TelegramTool>[
  TelegramTool(
    name: 'add_contact',
    label: 'Adding a contact',
    category: ToolCategory.contacts,
    requiresApproval: true,
    description:
        'Adds a user to contacts with a first and last name (user_id), or imports a phone number. share_phone: '
        'true shares the user\'s number with them. Needs approval.',
    parameters: _obj({
      'user_id': {'type': 'integer'},
      'phone': {'type': 'string'},
      'first_name': {'type': 'string'},
      'last_name': {'type': 'string'},
      'share_phone': {'type': 'boolean'},
    }, ['first_name']),
  ),
  TelegramTool(
    name: 'set_draft',
    label: 'Saving a draft',
    category: ToolCategory.messages,
    description:
        'Leaves a draft in a chat\'s message box (text, or empty to clear it) for the user to finish and send '
        'themselves. Nothing is sent.',
    parameters: _obj({
      'chat_id': {'type': 'integer'},
      'text': {'type': 'string'},
      'topic_id': {'type': 'integer'},
    }, ['chat_id', 'text']),
  ),
  TelegramTool(
    name: 'start_bot',
    label: 'Starting a bot',
    category: ToolCategory.bots,
    requiresApproval: true,
    description: 'Presses Start on a bot (bot user_id), with an optional start parameter from a deep link. Needs approval.',
    parameters: _obj({
      'user_id': {'type': 'integer'},
      'parameter': {'type': 'string'},
    }, ['user_id']),
  ),
  TelegramTool(
    name: 'get_chat_stats',
    label: 'Reading statistics',
    category: ToolCategory.analytics,
    description:
        'Statistics of a channel or group you admin (Telegram offers them for bigger chats): members and growth, '
        'views, shares and reactions per post, top posters, recent post performance, and boost level.',
    parameters: _obj({
      'chat_id': {'type': 'integer'},
    }, ['chat_id']),
  ),
  TelegramTool(
    name: 'get_post_stats',
    label: 'Reading post statistics',
    category: ToolCategory.analytics,
    description: 'Views, shares and reactions of one channel post you admin (chat_id, message_id).',
    parameters: _obj({
      'chat_id': {'type': 'integer'},
      'message_id': {'type': 'integer'},
    }, ['chat_id', 'message_id']),
  ),
];

String _stat(td.StatisticalValue v) =>
    '${v.value.round()}${v.previousValue == 0 ? '' : ' (was ${v.previousValue.round()}, ${v.growthRatePercentage >= 0 ? '+' : ''}${v.growthRatePercentage.toStringAsFixed(1)}%)'}';

extension _ExtraToolRuns on TelegramToolRunner {
  Map<String, dynamic> _storyJson(td.Story s) => {
    'story_id': s.id,
    'date': DateTime.fromMillisecondsSinceEpoch(s.date * 1000).toIso8601String().substring(0, 16),
    'kind': switch (s.content) {
      td.StoryContentPhoto() => 'photo',
      td.StoryContentVideo() => 'video',
      _ => 'other',
    },
    if (s.caption.text.isNotEmpty) 'caption': TelegramToolRunner._clip(s.caption.text),
    if (s.interactionInfo case final i?) ...{
      'views': i.viewCount,
      if (i.reactionCount > 0) 'reactions': i.reactionCount,
      if (i.forwardCount > 0) 'shares': i.forwardCount,
    },
    if (s.isPostedToChatPage) 'on_profile': true,
  };

  Future<ToolOutput>? _runExtra2(String name, Map<String, dynamic> args) => switch (name) {
    'get_stories' => () async {
      final c = _requireChat(args);
      final ids = <int>[];
      if (args['archived'] == true) {
        final r = await _client.send<td.Stories>(
          td.GetChatArchivedStories(chatId: c.id, fromStoryId: 0, limit: 30),
          limited: true,
        );
        return ToolOutput({
          'chat': c.title,
          'total': r.totalCount,
          'stories': [for (final s in r.stories) _storyJson(s)],
        });
      }
      final active = await _client.send<td.ChatActiveStories>(td.GetChatActiveStories(chatId: c.id), limited: true);
      ids.addAll(active.stories.map((s) => s.storyId));
      final stories = <Map<String, dynamic>>[];
      for (final id in ids.take(20)) {
        try {
          final s = await _client.send<td.Story>(
            td.GetStory(storyPosterChatId: c.id, storyId: id, onlyLocal: false),
            limited: true,
          );
          stories.add(_storyJson(s));
        } catch (_) {}
      }
      return ToolOutput({
        'chat': c.title,
        'active': stories.length,
        'stories': stories,
        if (stories.isEmpty) 'note': 'No active stories.',
      });
    }(),
    'add_contact' => () async {
      final first = '${args['first_name'] ?? ''}'.trim();
      final last = '${args['last_name'] ?? ''}'.trim();
      final userId = TelegramToolRunner._intOrNull(args, 'user_id');
      final phone = '${args['phone'] ?? ''}'.trim();
      if (userId != null) {
        await _client.send<td.Ok>(
          td.AddContact(
            userId: userId,
            contact: td.ImportedContact(phoneNumber: phone, firstName: first, lastName: last, note: null),
            sharePhoneNumber: args['share_phone'] == true,
          ),
          limited: true,
        );
        return ToolOutput({'added': '$first $last'.trim(), 'user_id': userId});
      }
      if (phone.isEmpty) throw ArgumentError('Give user_id or phone.');
      final r = await _client.send<td.ImportedContacts>(
        td.ImportContacts(
          contacts: [td.ImportedContact(phoneNumber: phone, firstName: first, lastName: last, note: null)],
        ),
        limited: true,
      );
      final id = r.userIds.firstOrNull ?? 0;
      return ToolOutput({
        'imported': '$first $last'.trim(),
        if (id != 0) 'user_id': id else 'note': 'That number isn\'t on Telegram yet.',
      });
    }(),
    'set_draft' => () async {
      final c = _requireChat(args);
      final text = '${args['text'] ?? ''}';
      await _client.send<td.Ok>(
        td.SetChatDraftMessage(
          chatId: c.id,
          topicId: topicOf(c.id, TelegramToolRunner._intOrNull(args, 'topic_id') ?? 0),
          draftMessage: text.isEmpty
              ? null
              : td.DraftMessage(
                  replyTo: null,
                  date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  content: td.DraftMessageContentText(
                    text: td.FormattedText(text: text, entities: const []),
                    linkPreviewOptions: null,
                  ),
                  effectId: 0,
                  suggestedPostInfo: null,
                ),
        ),
        limited: true,
      );
      return ToolOutput({'chat': c.title, 'draft': text.isEmpty ? 'cleared' : 'saved'});
    }(),
    'start_bot' => () async {
      final id = TelegramToolRunner._intOrNull(args, 'user_id');
      if (id == null) throw ArgumentError('user_id is required');
      final chat = await _client.send<td.Chat>(td.CreatePrivateChat(userId: id, force: false), limited: true);
      final m = await _client.send<td.Message>(
        td.SendBotStartMessage(botUserId: id, chatId: chat.id, parameter: '${args['parameter'] ?? ''}'),
        limited: true,
      );
      return ToolOutput({
        'started': _store.userName(id),
        'chat_id': chat.id,
        'ref': 'post:${m.chatId}:${m.id}',
        'note': 'Read the chat in a moment to see the bot\'s reply.',
      });
    }(),
    'get_chat_stats' => () async {
      final c = _requireChat(args);
      final out = <String, dynamic>{'chat': c.title};
      try {
        final b = await _client.send<td.ChatBoostStatus>(td.GetChatBoostStatus(chatId: c.id), limited: true);
        out['boosts'] = {
          'level': b.level,
          'boosts': b.boostCount,
          'next_level_at': b.nextLevelBoostCount,
          'premium_members': b.premiumMemberCount,
        };
      } catch (_) {}
      try {
        final s = await _client.send<td.ChatStatistics>(td.GetChatStatistics(chatId: c.id, isDark: true), limited: true);
        switch (s) {
          case td.ChatStatisticsChannel():
            out.addAll({
              'period':
                  '${DateTime.fromMillisecondsSinceEpoch(s.period.startDate * 1000).toIso8601String().substring(0, 10)} to '
                  '${DateTime.fromMillisecondsSinceEpoch(s.period.endDate * 1000).toIso8601String().substring(0, 10)}',
              'subscribers': _stat(s.memberCount),
              'mean_views_per_post': _stat(s.meanMessageViewCount),
              'mean_shares_per_post': _stat(s.meanMessageShareCount),
              'mean_reactions_per_post': _stat(s.meanMessageReactionCount),
              'notifications_on_percent': s.enabledNotificationsPercentage.toStringAsFixed(1),
              'recent_posts': [
                for (final i in s.recentInteractions.take(15))
                  {
                    if (i.objectType case td.ChatStatisticsObjectTypeMessage(:final messageId)) ...{
                      'message_id': messageId,
                      'ref': 'post:${c.id}:$messageId',
                    } else if (i.objectType case td.ChatStatisticsObjectTypeStory(:final storyId))
                      'story_id': storyId,
                    'views': i.viewCount,
                    'shares': i.forwardCount,
                    'reactions': i.reactionCount,
                  },
              ],
            });
          case td.ChatStatisticsSupergroup():
            out.addAll({
              'members': _stat(s.memberCount),
              'messages': _stat(s.messageCount),
              'viewers': _stat(s.viewerCount),
              'active_senders': _stat(s.senderCount),
              'top_senders': [
                for (final t in s.topSenders.take(10))
                  {'name': _store.userName(t.userId), 'messages': t.sentMessageCount},
              ],
            });
        }
      } on TelegramException catch (e) {
        out['statistics'] = 'Not available: ${e.message}';
      }
      return ToolOutput(out);
    }(),
    'get_post_stats' => () async {
      final c = _requireChat(args);
      final id = TelegramToolRunner._intOrNull(args, 'message_id');
      if (id == null) throw ArgumentError('message_id is required');
      final m = await _client.send<td.Message>(td.GetMessage(chatId: c.id, messageId: id), limited: true);
      final info = m.interactionInfo;
      final out = <String, dynamic>{
        'chat': c.title,
        'ref': 'post:${c.id}:$id',
        'views': info?.viewCount ?? 0,
        'shares': info?.forwardCount ?? 0,
        'comments': info?.replyInfo?.replyCount ?? 0,
        'reactions': [
          for (final r in info?.reactions?.reactions ?? const <td.MessageReaction>[])
            '${switch (r.type) {
              td.ReactionTypeEmoji(:final emoji) => emoji,
              _ => '★',
            }} ${r.totalCount}',
        ],
      };
      return ToolOutput(out, posts: [await snapshotMessage(c.id, id)]);
    }(),
    _ => null,
  };

  String? _describeExtra2(String name, Map<String, dynamic> args, String title) => switch (name) {
    'add_contact' => 'Add ${'${args['first_name'] ?? ''} ${args['last_name'] ?? ''}'.trim()} to contacts'
        '${args['phone'] != null ? ' (${args['phone']})' : ''}${args['share_phone'] == true ? ' and share your number' : ''}',
    'start_bot' =>
      'Start the bot ${_store.userName(TelegramToolRunner._intOrNull(args, 'user_id') ?? 0)}'
          '${'${args['parameter'] ?? ''}'.isEmpty ? '' : ' with “${args['parameter']}”'}',
    _ => null,
  };
}
