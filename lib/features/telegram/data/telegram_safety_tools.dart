part of 'telegram_tools.dart';

// The system check, and Block & mute: channels and groups blocked on this
// phone and muted words, which hide messages in chats, groups, channels and
// comments. The chat controller runs these (they need the app's state); the
// cards are in safety_result_cards.dart. Blocking people is block_user.

const _systemCheckAreaIds = [
  'ai',
  'telegram',
  'decisions',
  'mcp',
  'skills',
  'apps',
  'connection',
  'watches',
  'routines',
  'privacy',
  'widgets',
  'voice',
  'tools',
  'phone_data',
  'upkeep',
];

const _chatRef = {
  'type': 'integer',
  'description': 'The channel or group\'s chat id (from list_chats or search). Give this or username.',
};
const _usernameRef = {
  'type': 'string',
  'description': 'A public channel or group\'s @username or t.me link, for one the user hasn\'t joined.',
};

final _safetyTools = <TelegramTool>[
  TelegramTool(
    name: 'system_check',
    label: 'Running a system check',
    category: ToolCategory.system,
    cost: ToolCost.device,
    description:
        'Checks everything the app depends on and reports what works, what is broken and what could be better, with '
        'a health score out of 100: AI keys and models, Telegram accounts (TDLib, two-step verification, unknown '
        'sessions), decisions, MCP servers, skills, connected apps, the phone and its connection (storage, memory, '
        'battery saver, network, DNS), watches and the check-in, routines (failed or stalled runs), privacy (app lock, '
        'approvals, what Block & mute hides), home-screen widgets, voice, tools and usage, money and call data, and '
        'upkeep (memories, briefs, backups, storage). It only reads. Use it when something isn\'t working, or the user '
        'asks how the app or phone is doing. The user sees a card with the score and a sheet with every finding, so '
        'answer with what matters most and how to fix it, not the whole list. A full check can take half a minute; '
        'give areas to check only some.',
    parameters: _obj({
      'areas': {
        'type': 'array',
        'items': {'type': 'string', 'enum': _systemCheckAreaIds, 'description': 'One area to check.'},
        'description': 'Only these areas; default all.',
      },
    }),
  ),
  TelegramTool(
    name: 'list_hidden',
    label: 'Checking Block & mute',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    description:
        'What Block & mute hides: the channels and groups blocked on this phone, the muted words, how many accounts are '
        'blocked on Telegram (list_blocked lists them), whether hidden messages leave a "tap to view" notice or '
        'disappear, and whether archived chats are filtered too.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'block_chat',
    label: 'Blocking a channel or group',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Blocks a channel or group on this phone (Telegram itself can\'t block a chat you\'re in): the user stays in '
        'it and can still open it, but posts forwarded from it into other chats, and what it posts in comments and '
        'groups, are hidden. For people and bots use block_user. Undo with unblock_chat.',
    parameters: _obj({'chat_id': _chatRef, 'username': _usernameRef}),
  ),
  TelegramTool(
    name: 'unblock_chat',
    label: 'Unblocking a channel or group',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Unblocks a channel or group blocked with block_chat, so its posts show again. list_hidden lists them.',
    parameters: _obj({'chat_id': _chatRef, 'username': _usernameRef}),
  ),
  TelegramTool(
    name: 'mute_words',
    label: 'Muting words',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Mutes words or phrases: messages and posts containing one are hidden in chats, groups, channels and comments '
        '(the user\'s own messages never are). Matching ignores case and is whole-word, so "cat" doesn\'t hide '
        '"education". Undo with unmute_words.',
    parameters: _obj({
      'words': {
        'type': 'array',
        'items': {'type': 'string', 'description': 'A word or short phrase to mute.'},
        'description': 'The words or phrases to mute.',
      },
    }, ['words']),
  ),
  TelegramTool(
    name: 'unmute_words',
    label: 'Unmuting words',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Unmutes words muted with mute_words, or every muted word with all: true. list_hidden lists them.',
    parameters: _obj({
      'words': {
        'type': 'array',
        'items': {'type': 'string', 'description': 'A muted word or phrase.'},
        'description': 'The muted words to unmute (any case).',
      },
      'all': {'type': 'boolean', 'description': 'Unmute every muted word.'},
    }),
  ),
  TelegramTool(
    name: 'block_mute_settings',
    label: 'Changing Block & mute',
    category: ToolCategory.chats,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'How Block & mute hides things: for each of blocked accounts, blocked chats and muted words, whether a hidden '
        'message leaves a "tap to view" notice (true) or disappears without a trace (false); and whether archived chats '
        'are filtered too. Leave out what shouldn\'t change.',
    parameters: _obj({
      'notice_for_accounts': {'type': 'boolean', 'description': 'Messages from blocked accounts leave a notice.'},
      'notice_for_chats': {'type': 'boolean', 'description': 'Posts from blocked channels and groups leave a notice.'},
      'notice_for_words': {'type': 'boolean', 'description': 'Messages with a muted word leave a notice.'},
      'in_archived': {'type': 'boolean', 'description': 'Also hide things in archived chats.'},
    }),
  ),
];

final safetyToolNames = {for (final t in _safetyTools) t.name};

const _safetyPolicies = <String, ToolPolicy>{
  'system_check': ToolPolicy(ToolAccess.read),
  'list_hidden': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'block_chat': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'unblock_chat': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'mute_words': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'unmute_words': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'block_mute_settings': ToolPolicy(ToolAccess.modify, needsTelegram: true),
};

const _hiddenFields = ['blocked_chats: id, title, kind', 'muted_words', 'blocked_accounts', 'notices: accounts, chats, words', 'in_archived'];

const _safetyReferences = <String, ToolReference>{
  'system_check': ToolReference([
    'score',
    'checked_at',
    'counts: broken, warnings, suggestions, passed, notes',
    'areas: id, title, worst, ms, results: status, title, detail, fixable_in_settings',
  ]),
  'list_hidden': ToolReference(_hiddenFields),
  'block_chat': ToolReference(['blocked', ..._hiddenFields]),
  'unblock_chat': ToolReference(['unblocked', ..._hiddenFields]),
  'mute_words': ToolReference(['muted', 'already_muted', ..._hiddenFields]),
  'unmute_words': ToolReference(['unmuted', 'not_muted', ..._hiddenFields]),
  'block_mute_settings': ToolReference(['changed', ..._hiddenFields]),
};
