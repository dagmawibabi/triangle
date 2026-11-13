import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:geolocator/geolocator.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../ai/data/ai.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/data/image_input.dart' show ImageInputLoader;
import '../../device/device.dart';
import '../../integrations/app_results.dart';
import '../../integrations/app_toolkits.dart';

import 'package:omni_ai/omni_ai.dart'
    show
        AiException,
        BrowserSession,
        ExaClient,
        CloudflareClient,
        ComposioClient,
        DeviceSandbox,
        E2BClient,
        R2Credentials;

import '../../integrations/e2b_session.dart';
import '../../integrations/integrations_store.dart';
import '../../settings/data/settings.dart';
import '../../web/browser_mode.dart';
import '../../web/inapp_engine.dart';
import '../../web/web_fetch.dart';
import 'file_loader.dart' show formatDuration;
import 'message_content.dart';
import 'rich_message.dart';
import 'telegram_store.dart';
import 'account_tools.dart' show accountsParameter;
import '../../../infrastructure/telegram/td_compat.dart';
import '../../../core/files/download_progress.dart' show DownloadProgress, TransferCancelled, formatBytes, toolCallZoneKey;
import '../../device/net.dart';
import '../../ethiopian/ethiopian_calendar.dart';
import '../../qr/qr.dart';
import '../../youtube/youtube_api.dart';
import '../../retro/retro_games.dart';
import '../../papers/papers_api.dart';
import 'package:mobile_scanner/mobile_scanner.dart' show MobileScannerException;
import '../../../core/files/generated_files.dart';
import '../../library/library_api.dart';
import '../../pokemon/pokemon_api.dart' show PokemonApi, PokemonException, pokeTypes;
import '../../sports/sports_api.dart' show leagueIds, scorerCompetitions;

part 'telegram_account_tools.dart';
part 'telegram_activity_tools.dart';
part 'telegram_analytics_tools.dart';
part 'telegram_app_catalog.dart';
part 'telegram_app_tools.dart';
part 'telegram_admin_tools.dart';
part 'telegram_background_tools.dart';
part 'telegram_canvas_tools.dart';
part 'telegram_chat_tools.dart';
part 'telegram_cloud_tools.dart';
part 'telegram_destructive_tools.dart';
part 'telegram_device_tools.dart';
part 'telegram_dev_tools.dart';
part 'telegram_discover_tools.dart';
part 'telegram_extra_tools.dart';
part 'telegram_bot_tools.dart';
part 'telegram_botfather_tools.dart';
part 'telegram_media_meta_tools.dart';
part 'telegram_markets_tools.dart';
part 'telegram_news_tools.dart';
part 'telegram_bible_tools.dart';
part 'telegram_finance_tools.dart';
part 'telegram_call_history_tools.dart';
part 'telegram_library_tools.dart';
part 'telegram_pokemon_tools.dart';
part 'telegram_media_tools.dart';
part 'telegram_new_tools.dart';
part 'telegram_more_tools.dart';
part 'telegram_tools_more.dart';
part 'telegram_local_tools.dart';
part 'telegram_manage_tools.dart';
part 'telegram_star_tools.dart';
part 'telegram_web_tools.dart';
part 'telegram_tool_metadata.dart';
part 'telegram_tool_documentation.dart';
part 'telegram_tool_reference.dart';
part 'telegram_capability_tools.dart';
part 'telegram_info_tools.dart';
part 'telegram_safety_tools.dart';
part 'telegram_system_tools.dart';
part 'telegram_screen_tools.dart';
part 'telegram_utility_tools.dart';
part 'telegram_youtube_tools.dart';
part 'telegram_retro_tools.dart';
part 'telegram_papers_tools.dart';

/// What a tool hands back: JSON for the model, and the posts it showed so
/// the chat can turn citations into chips.
class ToolOutput {
  const ToolOutput(this.json, {this.posts = const [], this.full});
  final Map<String, dynamic> json;
  final List<PostSnapshot> posts;

  /// The complete response, when [json] is a shorter version made for the
  /// model: kept for the person's tool sheet and never sent to the model.
  final Object? full;

  String encode() => jsonEncode(json);
}

/// A tool the assistant may call.
///
/// Reading tools change nothing: reading history with `getChatHistory`
/// doesn't mark messages read. Tools that act are marked
/// [requiresApproval] and wait for the approval setting; [destructive] ones
/// are off until the person turns them on, and always ask.
enum ToolCategory {
  account('Account & security'),
  contacts('Contacts & profile'),
  members('Members & administration'),
  bots('Bots'),
  calls('Calls & live streams'),
  analytics('Analytics'),
  chats('Chats'),
  messages('Messages'),
  media('Media & appearance'),
  memory('Memory'),
  vault('Vault'),
  canvas('Canvas'),
  files('Files & images'),
  code('Code sandbox'),
  automation('Watches, reminders & widgets'),
  routines('Routines'),
  stories('Stories'),
  folders('Folders'),
  web('Web & browsing'),
  developer('Public GitHub'),
  discover('Video, music & social'),
  markets('Markets, weather & travel'),
  news('Reddit & Hacker News'),
  library('Books, audiobooks, radio & podcasts'),
  explore('Countries, space & Pokémon'),
  utilities('Ethiopian calendar & QR codes'),
  games('Retro games'),
  youtube('YouTube'),
  papers('Research papers'),
  bible('Bible'),
  finance('Money & banking'),
  callHistory('Call history'),
  screenTime('Screen time'),
  imageTools('Image tools'),
  packages('Packages, domains & xkcd'),
  world('Prices, quakes & air quality'),
  food('Recipes & nutrition'),
  reference('Dictionary, translation & Wikipedia'),
  sports('Sports'),
  stars('Stars'),
  creative('Create: images, video & audio'),
  device('Device'),
  system('System check'),
  screen('Screen control'),
  gmail('Gmail'),
  outlook('Outlook'),
  calendar('Google Calendar'),
  googleDocs('Drive, Docs & Sheets'),
  slack('Slack'),
  notion('Notion'),
  githubAccount('Your GitHub'),
  linear('Linear'),
  todoist('Todoist'),
  apps('Any connected app'),
  cloudflare('Cloudflare'),
  r2('Cloudflare R2 storage'),
  decisions('Decisions (Jev)'),
  mcp('MCP servers'),
  skills('Skills'),
  e2b('E2B code sandbox');

  const ToolCategory(this.label);
  final String label;

  /// Reaches the Telegram account, so it is offered only once signed in.
  bool get needsTelegram => switch (this) {
    account ||
    contacts ||
    members ||
    bots ||
    calls ||
    analytics ||
    chats ||
    messages ||
    media ||
    stories ||
    folders ||
    stars => true,
    _ => false,
  };

  /// Listed under Settings → Apps & web rather than the Telegram tools:
  /// connected apps, and the tools that reach the web.
  bool get onAppsScreen => switch (this) {
    web ||
    developer ||
    discover ||
    markets ||
    news ||
    library ||
    explore ||
    utilities ||
    games ||
    youtube ||
    papers ||
    bible ||
    finance ||
    callHistory ||
    screenTime ||
    imageTools ||
    packages ||
    world ||
    food ||
    reference ||
    sports ||
    creative ||
    memory ||
    vault ||
    routines ||
    canvas ||
    files ||
    system ||
    screen ||
    automation => true,
    gmail ||
    outlook ||
    calendar ||
    googleDocs ||
    slack ||
    notion ||
    githubAccount ||
    linear ||
    todoist ||
    apps => true,
    cloudflare || r2 || e2b => true,
    decisions || mcp || skills => true,
    _ => false,
  };
}

/// What running a tool costs.
enum ToolCost {
  local(
    'Local data',
    'Answered from what TDLib already has on the phone. Free and instant.',
  ),
  telegram(
    'Telegram requests',
    'Asks Telegram\'s servers, paced by the app\'s rate limiter.',
  ),
  ai(
    'AI model',
    'Calls an AI service using your API key; usage is billed by that provider.',
  ),
  device('This phone', 'Kept on this phone only; nothing goes to Telegram.'),
  web(
    'The web',
    'Reaches websites and APIs on the internet straight from this phone.',
  ),
  cloud(
    'Your cloud account',
    'Runs on your own Cloudflare or E2B account with the key you added; usage counts against that account.',
  ),
  apps(
    'Connected app',
    'Runs through Composio on an account you connected; counts against your Composio plan.',
  );

  const ToolCost(this.label, this.explanation);
  final String label;
  final String explanation;
}

class TelegramTool {
  const TelegramTool({
    required this.name,
    required this.label,
    required this.description,
    required Map<String, dynamic> parameters,
    bool requiresApproval = false,
    this.category = ToolCategory.messages,
    this.cost = ToolCost.telegram,
    bool destructive = false,
    this.alwaysAsk = false,
  }) : _requiresApproval = requiresApproval,
       _destructive = destructive,
       _parameters = parameters;

  /// Spends the user's money (Stars): asks every time, whatever the
  /// approval setting.
  final bool alwaysAsk;

  /// Deletes, leaves, blocks or bans: off until turned on in Settings, and
  /// always asks first.
  final bool _destructive;
  bool get destructive => access == ToolAccess.destructive;

  /// What this tool can do, independently of its approval policy.
  ToolAccess get access =>
      toolPolicies[name]?.access ??
      (_destructive ? ToolAccess.destructive : ToolAccess.modify);
  bool get modifiesData => access != ToolAccess.read;
  bool get needsTelegram => toolPolicies[name]?.needsTelegram ?? true;

  final String name;

  /// Shown on the tool card, e.g. "Reading messages".
  final String label;
  final String description;
  final Map<String, dynamic> _parameters;
  Map<String, dynamic> get parameters => documentedParameters(this);
  final bool _requiresApproval;
  bool get requiresApproval => _requiresApproval || destructive;
  ToolDocumentation get documentation => documentationFor(this);
  final ToolCategory category;
  final ToolCost cost;

  /// Whether the assistant gets this tool under [s].
  bool isOn(AppSettings s) =>
      s.toolOn(name, destructive: destructive, writes: modifiesData);

  Map<String, dynamic> get schema => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

Map<String, dynamic> _obj(
  Map<String, dynamic> props, [
  List<String> required = const [],
]) => {
  'type': 'object',
  'properties': props,
  if (required.isNotEmpty) 'required': required,
  'additionalProperties': false,
};

const _chatTypes = ['all', 'private', 'bot', 'group', 'channel', 'saved'];

final _tools = <TelegramTool>[
  TelegramTool(
    name: 'get_account_overview',
    label: 'Looking at your account',
    category: ToolCategory.account,
    cost: ToolCost.local,
    description:
        'Who the signed-in user is and counts across their whole account: channels, groups, private chats, bots, '
        'archived chats, chats with unread messages, unread DMs and mentions. Free and instant (local data).',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'list_chats',
    label: 'Listing chats',
    category: ToolCategory.chats,
    cost: ToolCost.local,
    description:
        'Lists the user\'s chats from local data (free, instant), newest activity first. Use to find chats by name, '
        'list channels/groups/DMs, or find chats with unread messages. Each chat includes its id, type, unread '
        'counts and a preview of its last message.',
    parameters: _obj({
      'type': {
        'type': 'string',
        'enum': _chatTypes,
        'description': 'Kind of chat. Default all.',
      },
      'query': {
        'type': 'string',
        'description': 'Case-insensitive match on title or @username.',
      },
      'unread_only': {
        'type': 'boolean',
        'description': 'Only chats with unread messages.',
      },
      'active_since_hours': {
        'type': 'number',
        'description': 'Only chats whose last message is newer than this.',
      },
      'include_archived': {
        'type': 'boolean',
        'description': 'Include the Archive folder. Default true.',
      },
      'archived_only': {
        'type': 'boolean',
        'description': 'Only chats in the Archive.',
      },
      'include_muted': {
        'type': 'boolean',
        'description': 'Include muted chats. Default true.',
      },
      'folder_id': {
        'type': 'integer',
        'description':
            'Only chats in this folder (ids from list_chat_folders).',
      },
      'limit': {'type': 'integer', 'description': '1-200, default 50.'},
    }),
  ),
  TelegramTool(
    name: 'get_chat_info',
    label: 'Getting chat details',
    category: ToolCategory.chats,
    description: 'Details about one chat: description/bio, member count, username, link, unread state.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'read_messages',
    label: 'Reading messages',
    description:
        'Reads messages from one chat or channel, newest first. Returns post refs to cite. Use since_hours for '
        '"today"/"this week", unread_only for what the user hasn\'t read. Does not mark anything as read.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'limit': {'type': 'integer', 'description': '1-50, default 20.'},
        'since_hours': {
          'type': 'number',
          'description': 'Only messages newer than this many hours.',
        },
        'unread_only': {
          'type': 'boolean',
          'description': 'Only messages after the user\'s last read position.',
        },
        'before_message_id': {
          'type': 'integer',
          'description': 'Page backwards from this message id.',
        },
        'topic_id': {
          'type': 'integer',
          'description':
              'In a forum group, read only this topic (from get_forum_topics).',
        },
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'get_recent_activity',
    label: 'Catching up on recent posts',
    description:
        'What\'s new: reads the latest messages across the chats with activity in the time window, most recent '
        'chats first. Best for "what\'s new today", "what did my channels post". Costs Telegram requests, so keep '
        'max_chats modest.',
    parameters: _obj({
      'since_hours': {
        'type': 'number',
        'description': 'Window in hours, default 24.',
      },
      'type': {
        'type': 'string',
        'enum': _chatTypes,
        'description': 'Default channel.',
      },
      'archived_only': {
        'type': 'boolean',
        'description': 'Only chats in the Archive.',
      },
      'unread_only': {
        'type': 'boolean',
        'description':
            'Only chats with unread messages, and only unread messages.',
      },
      'include_muted': {'type': 'boolean', 'description': 'Default true.'},
      'folder_id': {
        'type': 'integer',
        'description': 'Only chats in this folder.',
      },
      'max_chats': {'type': 'integer', 'description': '1-25, default 12.'},
      'per_chat': {
        'type': 'integer',
        'description': 'Messages per chat, 1-20, default 6.',
      },
    }),
  ),
  TelegramTool(
    name: 'search_messages',
    label: 'Searching messages',
    description: 'Full-text search of messages, in one chat (chat_id) or across all chats. Returns post refs to cite.',
    parameters: _obj(
      {
        'query': {'type': 'string'},
        'chat_id': {'type': 'integer', 'description': 'Search only this chat.'},
        'type': {
          'type': 'string',
          'enum': ['all', 'private', 'group', 'channel'],
          'description': 'Global search filter.',
        },
        'since_hours': {'type': 'number'},
        'limit': {'type': 'integer', 'description': '1-50, default 20.'},
      },
      ['query'],
    ),
  ),
  TelegramTool(
    name: 'get_message',
    label: 'Opening a message',
    description:
        'One message in full, with its link. Use when a preview was cut short.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'show_channel_post',
    label: 'Showing a channel post',
    category: ToolCategory.messages,
    description: 'Delivers one channel post into the current AI conversation for viewing, playing, or opening. This never forwards or sends it to Saved Messages.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'list_contacts',
    label: 'Listing contacts',
    category: ToolCategory.contacts,
    description: 'The user\'s Telegram contacts with usernames and last-seen status. Optional name filter.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Match on name or @username.'},
      'limit': {'type': 'integer', 'description': '1-300, default 100.'},
    }),
  ),
  TelegramTool(
    name: 'list_chat_folders',
    label: 'Listing folders',
    category: ToolCategory.folders,
    cost: ToolCost.local,
    description:
        'The user\'s chat folders (e.g. Work, Personal) with how many chats and unread chats each has. '
        'Pass folder_id to list the chats in one folder.',
    parameters: _obj({
      'folder_id': {
        'type': 'integer',
        'description': 'List the chats in this folder.',
      },
    }),
  ),
  TelegramTool(
    name: 'get_unread_mentions',
    label: 'Finding mentions',
    description: 'Messages where the user was @mentioned or replied to and hasn\'t read yet, across all chats.',
    parameters: _obj({
      'max_chats': {'type': 'integer', 'description': '1-15, default 8.'},
    }),
  ),
  TelegramTool(
    name: 'get_pinned_messages',
    label: 'Reading pinned messages',
    description: 'The pinned messages of a chat or channel, newest first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'limit': {'type': 'integer', 'description': '1-20, default 10.'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'get_comments',
    label: 'Reading comments',
    description:
        'The comments under a channel post (with who wrote each and their reactions), or the replies in a group '
        'thread. Comments live in the channel\'s discussion group: each has its own ref, usable with '
        'react_to_message, get_message_reactions or comment_on_post(reply_to_message_id).',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {
          'type': 'integer',
          'description': 'The post or the thread\'s first message.',
        },
        'limit': {'type': 'integer', 'description': '1-50, default 20.'},
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'list_shared_media',
    label: 'Browsing shared media',
    category: ToolCategory.media,
    description: 'Photos, videos, files, links, voice notes or audio shared in a chat, newest first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'type': {
          'type': 'string',
          'enum': [
            'photo',
            'video',
            'photo_and_video',
            'document',
            'link',
            'voice',
            'audio',
            'gif',
          ],
        },
        'limit': {'type': 'integer', 'description': '1-50, default 20.'},
      },
      ['chat_id', 'type'],
    ),
  ),
  TelegramTool(
    name: 'search_public_chats',
    label: 'Searching Telegram',
    category: ToolCategory.chats,
    description:
        'Finds public channels, groups and bots on Telegram by name or @username, including ones the user '
        'hasn\'t joined. Doesn\'t join anything.',
    parameters: _obj(
      {
        'query': {'type': 'string'},
      },
      ['query'],
    ),
  ),
  sendMessageTool,
  TelegramTool(
    name: 'forward_message',
    label: 'Forwarding',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Forwards one or more messages (several at once, in order) to another chat, or to several chats at once '
        'with to_chat_ids, Saved Messages included. '
        'Optionally without the sender\'s name (hide_sender) and without captions (remove_caption). The user '
        'must approve it first. Only call when the user asked for it.',
    parameters: _obj(
      {
        'from_chat_id': {'type': 'integer'},
        'message_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'to_chat_id': {
          'type': 'integer',
          'description':
              'Use the user\'s Saved Messages chat id to save posts.',
        },
        'to_chat_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description':
              'Several destination chats (instead of to_chat_id), up to 20.',
        },
        'hide_sender': {
          'type': 'boolean',
          'description': 'Send as a copy without the "Forwarded from" header. Default false.',
        },
        'remove_caption': {
          'type': 'boolean',
          'description': 'Drop media captions (sent as a copy). Default false.',
        },
      },
      ['from_chat_id', 'message_ids'],
    ),
  ),
  TelegramTool(
    name: 'get_forum_topics',
    label: 'Listing topics',
    category: ToolCategory.chats,
    description:
        'The topics of a forum group (a group with topics), with unread counts and latest activity. Read a topic '
        'with read_messages(chat_id, topic_id).',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'query': {'type': 'string', 'description': 'Filter topics by name.'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'get_user_profile',
    label: 'Opening a profile',
    category: ToolCategory.contacts,
    description:
        'A person\'s profile: name, @username, bio, last seen, whether they are a contact, their personal channel '
        'and the groups you have in common.',
    parameters: _obj({
      'user_id': {
        'type': 'integer',
        'description': 'Or pass the chat_id of your DM with them.',
      },
      'chat_id': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'send_chat_action',
    label: 'Showing chat activity',
    category: ToolCategory.messages,
    requiresApproval: true,
    cost: ToolCost.telegram,
    description: 'Shows a temporary Telegram activity indicator in a chat, such as typing, recording a voice note, uploading media, or choosing a sticker. Use only when the user explicitly asks to show that activity. The user must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'topic_id': {
          'type': 'integer',
          'description': 'Forum topic message id, if applicable. Default 0.',
        },
        'action': {
          'type': 'string',
          'enum': [
            'typing',
            'recording_video',
            'uploading_video',
            'recording_voice',
            'uploading_voice',
            'uploading_photo',
            'uploading_document',
            'choosing_sticker',
            'choosing_location',
            'choosing_contact',
            'playing_game',
            'recording_video_note',
            'uploading_video_note',
            'watching_animations',
            'cancel',
          ],
        },
        'progress': {
          'type': 'integer',
          'description': '0-100 for an uploading action. Default 0.',
        },
        'emoji': {
          'type': 'string',
          'description': 'Animated emoji for watching_animations. Default 👀.',
        },
      },
      ['chat_id', 'action'],
    ),
  ),
  TelegramTool(
    name: 'get_chat_presence',
    label: 'Checking active status',
    category: ToolCategory.chats,
    description: 'Checks whether a person in a private chat is online, or when Telegram says they were last active. Telegram may deliberately return an approximate status for privacy.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'send_live_location',
    label: 'Sharing live location',
    category: ToolCategory.messages,
    requiresApproval: true,
    cost: ToolCost.device,
    description: 'Gets the phone\'s current location and shares it in a chat, optionally live for 1 to 1440 minutes. The user must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'live_minutes': {
          'type': 'integer',
          'description':
              '0 for a one-time pin; 1-1440 to share live. Default 0.',
        },
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'browse_stickers',
    label: 'Browsing stickers',
    category: ToolCategory.media,
    description: 'Browses installed, recent and matching Telegram stickers. Results include sticker file ids for send_sticker or save_sticker.',
    parameters: _obj({
      'query': {'type': 'string'},
      'chat_id': {'type': 'integer'},
      'limit': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'browse_gifs',
    label: 'Browsing GIFs',
    category: ToolCategory.media,
    description: 'Browses GIF-style animations shared in one chat. Open a returned post to view it with playback controls, or forward it to send it elsewhere.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'limit': {'type': 'integer'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'search_stickers',
    label: 'Searching public stickers',
    category: ToolCategory.media,
    description: 'Searches public Telegram sticker sets by one or more emoji. Use browse_stickers for installed sticker keyword search.',
    parameters: _obj(
      {
        'emojis': {'type': 'string'},
        'limit': {'type': 'integer'},
      },
      ['emojis'],
    ),
  ),
  TelegramTool(
    name: 'send_sticker',
    label: 'Sending a sticker',
    category: ToolCategory.media,
    requiresApproval: true,
    description: 'Sends a sticker returned by browse_stickers or search_stickers. The user must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'file_id': {'type': 'integer'},
        'emoji': {'type': 'string'},
        'width': {'type': 'integer'},
        'height': {'type': 'integer'},
      },
      ['chat_id', 'file_id', 'emoji'],
    ),
  ),
  TelegramTool(
    name: 'save_sticker',
    label: 'Saving a sticker',
    category: ToolCategory.media,
    requiresApproval: true,
    description: 'Saves a sticker to the user\'s Telegram recent stickers. The user must approve it first.',
    parameters: _obj(
      {
        'file_id': {'type': 'integer'},
      },
      ['file_id'],
    ),
  ),
  TelegramTool(
    name: 'web_search',
    label: 'Searching the web',
    category: ToolCategory.web,
    description: 'Searches the web with the user\'s Exa key and returns source titles, URLs and highlights. Use only when the user asks for web research or current information.',
    parameters: _obj(
      {
        'query': {'type': 'string'},
        'limit': {'type': 'integer'},
      },
      ['query'],
    ),
  ),
  TelegramTool(
    name: 'react_to_message',
    label: 'Reacting',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Adds an emoji reaction to a message (or removes the user\'s reaction). The user must approve it first. '
        'Only call when the user asked you to react.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
        'emoji': {
          'type': 'string',
          'description':
              'A standard reaction emoji, e.g. 👍 ❤️ 🔥 😂 😮 😢 🙏 👏',
        },
        'remove': {
          'type': 'boolean',
          'description': 'Take the reaction back instead.',
        },
      },
      ['chat_id', 'message_id', 'emoji'],
    ),
  ),
  TelegramTool(
    name: 'set_chat_notifications',
    label: 'Changing notifications',
    category: ToolCategory.chats,
    requiresApproval: true,
    description:
        'Mutes or unmutes a chat, group or channel (muted: true/false). Use list_chats(include_muted) to see what is '
        'muted. The user must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'muted': {'type': 'boolean'},
      },
      ['chat_id', 'muted'],
    ),
  ),
  TelegramTool(
    name: 'mark_as_read',
    label: 'Marking as read',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Marks everything in a chat as read (clears its unread badge). The user must approve it first. Only call '
        'when the user asked for it.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'explore_forum',
    label: 'Exploring a forum',
    category: ToolCategory.messages,
    description:
        'Reads a forum group topic by topic: its topics (pinned and most active first) with the latest messages '
        'in each. Use for "what\'s happening in <forum>".',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'max_topics': {'type': 'integer', 'description': '1-10, default 6.'},
        'per_topic': {
          'type': 'integer',
          'description': 'Messages per topic, 1-10, default 4.',
        },
        'since_hours': {
          'type': 'number',
          'description': 'Only topics and messages newer than this.',
        },
        'unread_only': {
          'type': 'boolean',
          'description': 'Only topics with unread messages.',
        },
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'get_message_reactions',
    label: 'Reading reactions',
    category: ToolCategory.messages,
    description:
        'The reactions on a message: counts per emoji, and who reacted with what where Telegram shows it (groups, '
        'and channels the user runs). Works for comments too (use the comment\'s ref chat id).',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'comment_on_post',
    label: 'Commenting',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Posts a comment under a channel post (or replies to a comment with reply_to_message_id from get_comments). '
        'The user sees an editable draft and must approve it. Only call when the user asked you to comment.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer', 'description': 'The channel.'},
        'message_id': {'type': 'integer', 'description': 'The channel post.'},
        'text': {'type': 'string'},
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Names of files the user attached in this conversation, or generated image paths.',
        },
        'reply_to_message_id': {
          'type': 'integer',
          'description': 'A comment to reply to (its id from get_comments).',
        },
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'reply_to_message',
    label: 'Replying',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Replies to a specific message or post, optionally quoting the exact part you answer (quote must be copied '
        'word for word from it). By default the reply goes in the same chat; pass send_in_chat_id to reply from '
        'another chat, e.g. quote a channel post inside a DM. Files can be attached. The user sees an editable draft '
        'and must approve it. Only call when asked.',
    parameters: _obj(
      {
        'chat_id': {
          'type': 'integer',
          'description': 'Where the original message is.',
        },
        'message_id': {'type': 'integer'},
        'text': {'type': 'string'},
        'quote': {
          'type': 'string',
          'description': 'An exact excerpt of the original to quote.',
        },
        'send_in_chat_id': {
          'type': 'integer',
          'description': 'Send the reply in this chat instead.',
        },
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'send_as': {
          'type': 'string',
          'enum': ['media', 'file'],
          'description': 'file sends photos/videos uncompressed, as documents.',
        },
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'pin_message',
    label: 'Pinning',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Pins a message at the top of a chat, or unpins it (unpin: true). Silent by default; notify: true alerts the '
        'members. In a DM, only_for_me pins it just for the user. See current pins with get_pinned_messages. The user '
        'must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
        'unpin': {'type': 'boolean'},
        'notify': {
          'type': 'boolean',
          'description': 'Notify members about the pin. Default false.',
        },
        'only_for_me': {
          'type': 'boolean',
          'description': 'In a private chat, pin only on your side.',
        },
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'edit_message',
    label: 'Editing a message',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Changes one of the user\'s own messages or channel posts: its text or caption, and/or its media (replace the '
        'photo, video, file or audio with one from files, or add one; send_as file keeps it uncompressed). Telegram may '
        'refuse to add media to a message that was sent as plain text; the tool says so. The user must approve it '
        'first. Only call when asked.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
        'text': {
          'type': 'string',
          'description': 'The full new text or caption. Leave out to keep the current one.',
        },
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'One file to put in place of the message\'s media (a name from this conversation).',
        },
        'send_as': {
          'type': 'string',
          'enum': ['media', 'file'],
        },
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'schedule_message',
    label: 'Scheduling a message',
    category: ToolCategory.messages,
    requiresApproval: true,
    description:
        'Schedules a message (with optional files) to be sent later by Telegram itself, even if this app is closed. '
        'The user sees an editable draft and must approve it. Give send_at as local time, or in_minutes.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'text': {'type': 'string'},
        'send_at': {
          'type': 'string',
          'description': 'Local date and time, e.g. 2026-10-24T09:00.',
        },
        'in_minutes': {
          'type': 'integer',
          'description': 'Or: this many minutes from now.',
        },
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Names of files the user attached in this conversation, or generated image paths.',
        },
      },
      ['chat_id'],
    ),
  ),
  TelegramTool(
    name: 'list_scheduled_messages',
    label: 'Checking scheduled messages',
    category: ToolCategory.messages,
    description:
        'Messages the user has scheduled to send later, with when they go out. One chat, or (without chat_id) '
        'the chats with recent activity the user can write in.',
    parameters: _obj({
      'chat_id': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'reschedule_message',
    label: 'Rescheduling',
    category: ToolCategory.messages,
    requiresApproval: true,
    description: 'Moves a scheduled message to another time, or sends it right away. The user must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'message_id': {'type': 'integer'},
        'send_at': {
          'type': 'string',
          'description': 'New local date and time.',
        },
        'in_minutes': {'type': 'integer'},
        'send_now': {'type': 'boolean'},
      },
      ['chat_id', 'message_id'],
    ),
  ),
  TelegramTool(
    name: 'archive_chat',
    label: 'Archiving',
    category: ToolCategory.chats,
    requiresApproval: true,
    description:
        'Moves a chat into the Archive, or back out to the main list (archived: false). Nothing is deleted. The user '
        'must approve it first.',
    parameters: _obj(
      {
        'chat_id': {'type': 'integer'},
        'archived': {
          'type': 'boolean',
          'description': 'true to archive, false to unarchive.',
        },
      },
      ['chat_id', 'archived'],
    ),
  ),
  TelegramTool(
    name: 'remember',
    label: 'Remembering',
    category: ToolCategory.memory,
    cost: ToolCost.device,
    description:
        'Saves something to long-term memory so it is known in every future conversation: preferences, facts about '
        'people or chats, standing requests. Use when the user says "remember…", or shares something clearly worth '
        'keeping. Keep each memory short and self-contained.',
    parameters: _obj(
      {
        'content': {'type': 'string'},
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      ['content'],
    ),
  ),
  TelegramTool(
    name: 'update_memory',
    label: 'Updating a memory',
    category: ToolCategory.memory,
    cost: ToolCost.device,
    description: 'Rewrites a saved memory (ids are listed in your instructions and by list_memories).',
    parameters: _obj(
      {
        'memory_id': {'type': 'string'},
        'content': {'type': 'string'},
      },
      ['memory_id', 'content'],
    ),
  ),
  TelegramTool(
    name: 'forget_memory',
    label: 'Forgetting',
    category: ToolCategory.memory,
    cost: ToolCost.device,
    description: 'Deletes a saved memory, when the user asks you to forget something or it is no longer true.',
    parameters: _obj(
      {
        'memory_id': {'type': 'string'},
      },
      ['memory_id'],
    ),
  ),
  TelegramTool(
    name: 'list_memories',
    label: 'Checking memory',
    category: ToolCategory.memory,
    cost: ToolCost.device,
    description: 'Everything saved in long-term memory, optionally filtered.',
    parameters: _obj({
      'query': {'type': 'string'},
    }),
  ),
  TelegramTool(
    name: 'create_watch',
    label: 'Setting up a watch',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Creates a watch that runs on its own. Triggers: new messages in specific chats (chat_ids), all_dms, '
        'all_groups, all_channels, mentions of the user, a folder (these need Telegram), a schedule (daily_at "HH:MM" or '
        'every_minutes), or app: something new in a connected app (app = a toolkit like gmail, slack, github, notion, '
        'todoist, or "any"; query = what to look for, e.g. "emails from my bank"), checked every_minutes (default 15), or phone: '
        'something on the phone (phone_event: battery low, plugged in/unplugged, Wi-Fi joins/leaves, arriving at or '
        'leaving a place, a missed call, a new SMS, the user opening the app). tools limits what its runs may use; '
        'model picks a cheaper model (free by default). Modes: notify (a phone notification with the new messages), summarize (you write a short '
        'note and the user is notified), act (you follow the instructions on every trigger, e.g. reply to each new '
        'DM, and may use any tool). Use for "tell me when X posts", "watch my DMs and answer them", "every morning '
        'summarise my channels".',
    parameters: _obj(
      {
        'name': {
          'type': 'string',
          'description': 'Short label, e.g. "Liya\'s messages".',
        },
        'trigger': {
          'type': 'string',
          'enum': [
            'chats',
            'all_dms',
            'all_groups',
            'all_channels',
            'mentions',
            'folder',
            'schedule',
            'app',
            'phone',
          ],
        },
        ...phoneTriggerParams,
        'tools': {
          'type': 'array',
          'items': {'type': 'string', 'description': 'A tool name, category or area.'},
          'description':
              'Only these tools for its runs: tool names, categories (e.g. Messages, Gmail, Device) or areas '
              '(Telegram, Apps & web, Device). Leave out to allow every tool (the default).',
        },
        'model': {
          'type': 'string',
          'description':
              'The model its runs use: free (default; a free model when one is available, else the cheapest), '
              'cheap, main (the chat\'s model) or a model id. Use main only for watches that need careful writing.',
        },
        'app': {
          'type': 'string',
          'description': 'For app: the toolkit to check, e.g. gmail, slack, github, or any.',
        },
        'query': {
          'type': 'string',
          'description': 'For app: what to look for, e.g. "emails from Liya" or "PRs assigned to me".',
        },
        'chat_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'folder_id': {'type': 'integer'},
        'daily_at': {
          'type': 'string',
          'description': 'For schedule: local time "HH:MM".',
        },
        'every_minutes': {
          'type': 'integer',
          'description': 'For schedule: run this often (15 or more).',
        },
        'mode': {
          'type': 'string',
          'enum': ['notify', 'summarize', 'act'],
        },
        'instructions': {
          'type': 'string',
          'description': 'What to do each time, for summarize and act.',
        },
        'include_muted': {
          'type': 'boolean',
          'description': 'Also fire for muted chats. Default true.',
        },
        'notify': {
          'type': 'boolean',
          'description':
              'Send a phone notification when it fires. false runs it quietly in the background; results '
              'still land in its conversation. Default true.',
        },
        'accounts': accountsParameter('the watch (whose messages it hears and which its runs may use; a folder watch covers its folder\'s account)'),
      },
      ['name', 'trigger', 'mode'],
    ),
  ),
  TelegramTool(
    name: 'list_watches',
    label: 'Listing watches',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'The user\'s watches and routines, with what triggers them and what they do.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'update_watch',
    label: 'Changing a watch',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'Changes a watch: turn it on or off, rename it, change its chats, mode, schedule or instructions.',
    parameters: _obj(
      {
        'watch_id': {'type': 'string'},
        'enabled': {'type': 'boolean'},
        'name': {'type': 'string'},
        'chat_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'mode': {
          'type': 'string',
          'enum': ['notify', 'summarize', 'act'],
        },
        'instructions': {'type': 'string'},
        'daily_at': {'type': 'string'},
        'every_minutes': {'type': 'integer'},
        'include_muted': {'type': 'boolean'},
        'notify': {
          'type': 'boolean',
          'description': 'false: run quietly, no notifications.',
        },
        'accounts': accountsParameter('the watch'),
        'tools': {
          'type': 'array',
          'items': {'type': 'string', 'description': 'A tool name, category or area.'},
          'description': 'Only these tools for its runs (names, categories or areas); ["all"] allows every tool again.',
        },
        'model': {'type': 'string', 'description': 'free, cheap, main or a model id.'},
      },
      ['watch_id'],
    ),
  ),
  TelegramTool(
    name: 'delete_watch',
    label: 'Removing a watch',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'Removes a watch or routine for good.',
    parameters: _obj(
      {
        'watch_id': {'type': 'string'},
      },
      ['watch_id'],
    ),
  ),
  TelegramTool(
    name: 'create_widget',
    label: 'Making a home-screen widget',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Makes a home-screen widget (Android): a scrolling list of rows with optional pictures and links. Give '
        'shows to have the assistant keep it up to date every every_hours (subscriber counts, latest news, new '
        'movies with posters, weather, a to-do list from an app); a scheduled watch then refreshes it with '
        'update_widget. Give items for rows now (for static text, or a first fill). The user adds it from their '
        'home screen and picks what each widget shows in Settings → Home-screen widgets.',
    parameters: _obj(
      {
        'title': {
          'type': 'string',
          'description': 'Short title shown at the top of the widget.',
        },
        'shows': {
          'type': 'string',
          'description': 'What the widget should show, as instructions for its refresh, e.g. "the YouTube subscriber count of @mkbhd". Leave out for static text.',
        },
        'every_hours': {
          'type': 'integer',
          'description': 'How often to refresh, 1 to 168 hours (default 6).',
        },
        'items': {
          'type': 'array',
          'description': 'The rows, up to 20, in order.',
          'items': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description':
                    'Bold first line, e.g. a movie name or a headline.',
              },
              'text': {
                'type': 'string',
                'description': 'One or two short lines.',
              },
              'subtitle': {
                'type': 'string',
                'description':
                    'Small grey line, e.g. a date, source or number.',
              },
              'image_url': {
                'type': 'string',
                'description': 'https link to a picture (poster, thumbnail); the app saves it for the widget.',
              },
              'link': {
                'type': 'string',
                'description': 'https link opened when the row is tapped.',
              },
            },
          },
        },
      },
      ['title'],
    ),
  ),
  TelegramTool(
    name: 'update_widget',
    label: 'Updating a widget',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Replaces a home-screen widget\'s rows (and optionally its title, what it shows or how often it refreshes). '
        'Use it when refreshing a widget or when the user asks to change one.',
    parameters: _obj(
      {
        'widget_id': {
          'type': 'string',
          'description':
              'The widget to change, from list_widgets or create_widget.',
        },
        'items': {
          'type': 'array',
          'description': 'The rows, up to 20, in order.',
          'items': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description':
                    'Bold first line, e.g. a movie name or a headline.',
              },
              'text': {
                'type': 'string',
                'description': 'One or two short lines.',
              },
              'subtitle': {
                'type': 'string',
                'description':
                    'Small grey line, e.g. a date, source or number.',
              },
              'image_url': {
                'type': 'string',
                'description': 'https link to a picture (poster, thumbnail); the app saves it for the widget.',
              },
              'link': {
                'type': 'string',
                'description': 'https link opened when the row is tapped.',
              },
            },
          },
        },
        'title': {'type': 'string'},
        'shows': {'type': 'string', 'description': 'New refresh instructions.'},
        'every_hours': {
          'type': 'integer',
          'description': 'New refresh interval, 1 to 168 hours.',
        },
      },
      ['widget_id'],
    ),
  ),
  TelegramTool(
    name: 'list_widgets',
    label: 'Listing widgets',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'Lists the home-screen widgets: the built-in brief and custom ones, what each shows and when it was updated.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'delete_widget',
    label: 'Deleting a widget',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'Deletes a custom home-screen widget and stops its refresh. The brief widget can\'t be deleted.',
    parameters: _obj(
      {
        'widget_id': {
          'type': 'string',
          'description': 'The widget to delete, from list_widgets.',
        },
      },
      ['widget_id'],
    ),
  ),
  TelegramTool(
    name: 'online_alert',
    label: 'Setting an online alert',
    category: ToolCategory.contacts,
    cost: ToolCost.device,
    description:
        'Notifies the user when someone comes online ("tell me when Liya is online"). once: false keeps alerting each '
        'time (at most every 15 minutes). remove: true cancels it. Works only if that person lets the user see their '
        'last seen (contacts, or everybody); the app keeps running in the background while alerts are set.',
    parameters: _obj(
      {
        'user_id': {'type': 'integer'},
        'once': {
          'type': 'boolean',
          'description': 'Default true: alert the first time, then stop.',
        },
        'remove': {'type': 'boolean'},
      },
      ['user_id'],
    ),
  ),
  TelegramTool(
    name: 'list_online_alerts',
    label: 'Listing online alerts',
    category: ToolCategory.contacts,
    cost: ToolCost.device,
    description: 'The people the user asked to be told about when they come online, and whether each is online now.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'notify_me',
    label: 'Notifying',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Shows the user a phone notification now. Useful in watches when something needs their attention; tapping '
        'it opens this conversation.',
    parameters: _obj(
      {
        'title': {'type': 'string'},
        'body': {'type': 'string'},
      },
      ['title', 'body'],
    ),
  ),
  generateImageTool,
  getModelSettingsTool,
  generateVideoTool,
  generateAudioTool,
  generateAddisVoiceTool,
  generateSoundEffectTool,
  generateMusicTool,
  sendVoiceMessageTool,
  listAttachmentsTool,
  ..._moreTools,
  ..._mediaTools,
  ..._backgroundTools,
  ..._botTools,
  ..._activityTools,
  ..._analyticsTools,
  ..._chatTools,
  ..._adminTools,
  ..._extraTools,
  ..._botFatherTools,
  ..._destructiveTools,
  ..._canvasTools,
  ..._localPhoneTools,
  ..._webTools,
  ..._starTools,
  ..._devTools,
  ..._manageTools,
  ..._accountTools,
  ..._moreTdTools,
  ..._discoverTools,
  ..._youtubeTools,
  ..._newTools,
  ..._mediaMetaTools,
  ..._marketsTools,
  ..._newsTools,
  ..._bibleTools,
  ..._financeTools,
  ..._callHistoryTools,
  ..._libraryTools,
  ..._pokemonTools,
  ..._papersTools,
  ..._appTools,
  ..._cloudTools,
  ..._deviceTools,
  ..._utilityTools,
  ..._retroTools,
  ..._infoTools,
  ..._safetyTools,
  ..._systemTools,
  ..._screenTools,
  ..._capabilityTools,
];

const generateImageTool = TelegramTool(
  name: 'generate_image',
  label: 'Creating an image',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description:
      'Creates an image from a detailed prompt with the image model chosen in Settings. The image is shown to '
      'the user in the chat. Use when asked to draw, design or visualize something.',
  parameters: {
    'type': 'object',
    'properties': {
      'prompt': {
        'type': 'string',
        'description': 'A vivid, specific description of the image.',
      },
      'aspect': {
        'type': 'string',
        'enum': ['square', 'portrait', 'landscape'],
        'description': 'Default square.',
      },
    },
    'required': ['prompt'],
    'additionalProperties': false,
  },
);

const generateVideoTool = TelegramTool(
  name: 'generate_video',
  label: 'Creating a video',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description:
      'Creates a short video from a detailed prompt with the video model chosen in Settings, optionally starting '
      'from a picture in this chat. It is shown to the user in the chat. Videos cost far more than images and take '
      'a while: make one only when asked for a video or animation.',
  parameters: {
    'type': 'object',
    'properties': {
      'prompt': {
        'type': 'string',
        'description':
            'What happens: subject, action, setting, camera, style, sound.',
      },
      'seconds': {
        'type': 'integer',
        'description':
            'Length in seconds, if the model lets you choose (often 4 to 10).',
      },
      'aspect': {
        'type': 'string',
        'enum': ['landscape', 'portrait', 'square'],
        'description': 'Default landscape (16:9).',
      },
      'audio': {
        'type': 'boolean',
        'description': 'With sound, where the model can make it.',
      },
      'image': {
        'type': 'string',
        'description':
            'Optional: a picture in this chat (its name) to start from.',
      },
    },
    'required': ['prompt'],
    'additionalProperties': false,
  },
);

final generateAudioTool = TelegramTool(
  name: 'generate_audio',
  label: 'Creating audio',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description: 'Creates an MP3 spoken by the voice selected in Settings. When Addis AI is selected, use an available Addis voice ID (am-, om-, or ti-) to create Amharic, Afaan Oromo, or Tigrinya speech. The audio is shown in the chat and can be sent to Telegram like a generated image.',
  parameters: _obj(
    {
      'text': {'type': 'string'},
      'voice': {'type': 'string'},
    },
    ['text'],
  ),
);

final generateSoundEffectTool = TelegramTool(
  name: 'generate_sound_effect',
  label: 'Creating a sound effect',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description: 'Creates a sound effect or ambience from a description using ElevenLabs. Requires an ElevenLabs API key in Settings → AI & models. The audio appears in chat and is saved in Files. Use generate_music for songs and scores, and generate_audio for speech.',
  parameters: _obj(
    {
      'prompt': {
        'type': 'string',
        'description': 'Describe the sound, its environment and mood.',
      },
      'duration_seconds': {
        'type': 'number',
        'exclusiveMinimum': 0,
        'description':
            'Optional length in seconds; omit to let ElevenLabs choose.',
      },
      'prompt_influence': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'description': 'Optional strength of adherence to the description.',
      },
      'loop': {
        'type': 'boolean',
        'description': 'Whether to make a looping sound effect. Default false.',
      },
    },
    ['prompt'],
  ),
);

final generateMusicTool = TelegramTool(
  name: 'generate_music',
  label: 'Creating music',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description: 'Creates music, a song or a score from a description using ElevenLabs. Describe the genre, mood, instruments and any vocals. Requires an ElevenLabs API key in Settings → AI & models and access to music generation. The audio appears in chat and is saved in Files.',
  parameters: _obj(
    {
      'prompt': {
        'type': 'string',
        'description': 'Describe the music to create.',
      },
      'duration_seconds': {
        'type': 'number',
        'exclusiveMinimum': 0,
        'description': 'Requested length in seconds. Default 30.',
      },
    },
    ['prompt'],
  ),
);

final getModelSettingsTool = TelegramTool(
  name: 'get_model_settings',
  label: 'Checking the AI models',
  category: ToolCategory.creative,
  cost: ToolCost.device,
  description:
      'The AI models chosen in Settings (AI & models) for chat, decisions (Jev), images, video and audio, with each '
      'model\'s name, provider and whether it is enabled and ready to use. Audio includes the voice and dictation '
      'engines, their models and the selected voice. Reads settings only; no AI call is made.',
  parameters: _obj({}),
);

/// ElevenLabs creative tools stay visible in Settings, with their key requirement.
String? creativeToolNeeds(TelegramTool t, AppSettings s) =>
    (t.name == generateSoundEffectTool.name ||
            t.name == generateMusicTool.name) &&
        !s.hasElevenKey
    ? 'Needs an ElevenLabs key in AI & models'
    : null;

final generateAddisVoiceTool = TelegramTool(
  name: 'generate_addis_voice',
  label: 'Creating an Addis AI voice',
  category: ToolCategory.creative,
  cost: ToolCost.ai,
  description: 'Creates an MP3 with Addis Voices 2. Use for Amharic (am), Afaan Oromo (om), or Tigrinya (ti). Choose a voice ID from the live Addis AI catalog when the user names one; otherwise an available default voice for the requested language is selected. Requires the user to add an Addis AI key in Settings.',
  parameters: _obj(
    {
      'text': {
        'type': 'string',
        'description': 'Text in the requested language.',
      },
      'language': {
        'type': 'string',
        'enum': ['am', 'om', 'ti'],
        'description': 'am Amharic, om Afaan Oromo, ti Tigrinya.',
      },
      'voice_id': {
        'type': 'string',
        'description': 'Optional currently available Addis voice ID.',
      },
    },
    ['text', 'language'],
  ),
);

const sendMessageTool = TelegramTool(
  name: 'send_message',
  label: 'Sending a message',
  category: ToolCategory.messages,
  requiresApproval: true,
  description:
      'Sends a message to a chat, or posts in a channel the user can post in, optionally with photos, videos '
      'or files. The user sees an editable draft and must approve it before anything is sent; they may change '
      'the text or attachments, or decline. Only call when the user asked you to send something. Text may use '
      'Telegram formatting: **bold**, *italic*, <u>underline</u>, ~~strikethrough~~, ||spoiler||, `code`, '
      '```code block```, [text](https://link). The other person sees "typing…" or "sending a photo…" first.',
  parameters: {
    'type': 'object',
    'properties': {
      'chat_id': {'type': 'integer'},
      'text': {
        'type': 'string',
        'description':
            'The message text, or the caption when files are attached.',
      },
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Files to attach: names of files the user attached in this conversation, or image_path values from '
            'generate_image. Several photos/videos are sent as one album.',
      },
      'send_as': {
        'type': 'string',
        'enum': ['media', 'file'],
        'description':
            'media (default): photos and videos compressed, shown inline. file: sent uncompressed as documents, '
            'full quality and original file name. To send several files as one archive, zip_files first.',
      },
      'reply_to_message_id': {'type': 'integer'},
      'effect_id': {
        'type': 'string',
        'description': 'An animated effect (from list_message_effects) for a message in a private chat.',
      },
    },
    'required': ['chat_id'],
    'additionalProperties': false,
  },
);

const listAttachmentsTool = TelegramTool(
  name: 'list_attachments',
  label: 'Checking files',
  category: ToolCategory.files,
  cost: ToolCost.device,
  description:
      'Every file in this conversation that can be sent to a chat: pictures, videos, voice notes and documents the '
      'user attached, and images or audio you generated. Pass a name in files to send it.',
  parameters: {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  },
);

final sendVoiceMessageTool = TelegramTool(
  name: 'send_voice_message',
  label: 'Sending a voice message',
  category: ToolCategory.messages,
  requiresApproval: true,
  description: 'Sends one recorded voice note to a chat as a Telegram voice message. Use only for a voice-note attachment the user provided in this conversation, and only when they asked to send it.',
  parameters: _obj(
    {
      'chat_id': {'type': 'integer'},
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Exactly one recorded voice-note attachment.',
      },
      'text': {'type': 'string', 'description': 'Optional voice-note caption.'},
      'reply_to_message_id': {'type': 'integer'},
      'topic_id': {'type': 'integer'},
    },
    ['chat_id', 'files'],
  ),
);

List<TelegramTool> get telegramTools => _tools;

TelegramTool? toolNamed(String name) =>
    _tools.where((t) => t.name == name).firstOrNull;

/// Runs tools against TDLib. Anything that may reach Telegram's servers goes
/// through the client's rate limiter; list questions are answered from the
/// local store.
class TelegramToolRunner {
  TelegramToolRunner(
    this._client,
    this._store,
    this._settings, {
    WebFetcher? web,
    BrowserSession? browser,
    InAppEngine? engine,
    DeviceSandbox? sandbox,
    Future<ComposioClient?> Function()? composio,
    E2bSession? e2b,
  }) : _composio = composio,
       _e2bSession = e2b,
       _web = web ?? WebFetcher(),
       _browser = browser ?? BrowserSession(),
       _engine = engine ?? InAppEngine(),
       _sandbox = sandbox ?? DeviceSandbox();

  final TelegramClient _client;
  final TelegramStore _store;
  final AppSettings _settings;
  final WebFetcher _web;
  final BrowserSession _browser;
  final InAppEngine _engine;
  final DeviceSandbox _sandbox;

  /// A Composio client for the user's connected apps, or null without a key.
  final Future<ComposioClient?> Function()? _composio;

  /// The user's E2B sandbox, kept between runs.
  final E2bSession? _e2bSession;
  final Map<String, StreamSubscription<Position>> _liveLocationStreams = {};

  static const _maxText = 1200;

  Future<ToolOutput> run(String name, Map<String, dynamic> args) async {
    try {
      return switch (name) {
        'get_account_overview' => await _overview(),
        'list_chats' => await _listChats(args),
        'get_chat_info' => await _chatInfo(args),
        'read_messages' => await _readMessages(args),
        'get_recent_activity' => await _recentActivity(args),
        'search_messages' => await _search(args),
        'get_message' => await _getMessage(args),
        'show_channel_post' => await _getMessage(args),
        'send_message' => await _send(args),
        'send_voice_message' => await _sendVoice(args),
        'list_contacts' => await _contacts(args),
        'list_chat_folders' => await _folders(args),
        'get_unread_mentions' => await _mentions(args),
        'get_pinned_messages' => await _filtered(
          args,
          const td.SearchMessagesFilterPinned(),
          max: 20,
          fallback: 10,
        ),
        'get_comments' => await _comments(args),
        'list_shared_media' => await _sharedMedia(args),
        'get_chat_members' => await _members(args),
        'search_public_chats' => await _publicChats(args),
        'forward_message' => await _forward(args),
        'get_forum_topics' => await _topics(args),
        'get_user_profile' => await _profile(args),
        'send_chat_action' => await _sendChatAction(args),
        'get_chat_presence' => await _presence(args),
        'send_live_location' => await _sendLiveLocation(args),
        'browse_stickers' => await _browseStickers(args),
        'browse_gifs' => await _sharedMedia({...args, 'type': 'gif'}),
        'search_stickers' => await _searchStickers(args),
        'send_sticker' => await _sendSticker(args),
        'save_sticker' => await _saveSticker(args),
        'web_search' => await _webSearch(args),
        'react_to_message' => await _react(args),
        'set_chat_notifications' => await _notifications(args),
        'mark_as_read' => await _markRead(args),
        'explore_forum' => await _exploreForum(args),
        'get_message_reactions' => await _reactions(args),
        'comment_on_post' => await _comment(args),
        'edit_message' => await _edit(args),
        'reply_to_message' => await _reply(args),
        'pin_message' => await _pin(args),
        'archive_chat' => await _archive(args),
        'schedule_message' => await _schedule(args),
        'list_scheduled_messages' => await _scheduled(args),
        'reschedule_message' => await _reschedule(args),
        _ =>
          await (_runExtra(name, args) ??
              Future.value(ToolOutput({'error': 'Unknown tool $name'}))),
      };
    } on TelegramException catch (e) {
      final wait = e.retryAfterSeconds;
      return ToolOutput({
        'error': e.isFloodWait
            ? 'Telegram rate limit: wait ${wait ?? 'a few'} seconds before more requests. Answer with what you have.'
            : e.message,
      });
    } on ArgumentError catch (e) {
      return ToolOutput({'error': '${e.message}'});
    }
  }

  // ---- helpers -------------------------------------------------------------

  static int _int(
    Map<String, dynamic> a,
    String key, {
    required int fallback,
    int min = 1,
    int max = 1 << 30,
  }) {
    final v = a[key];
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
    return n.clamp(min, max);
  }

  static int? _intOrNull(Map<String, dynamic> a, String key) {
    final v = a[key];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  }

  static double? _hours(Map<String, dynamic> a, String key) {
    final v = a[key];
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return n == null || n <= 0 ? null : n;
  }

  static int _unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  static DateTime _date(int unix) =>
      DateTime.fromMillisecondsSinceEpoch(unix * 1000);
  static String _iso(int unix) =>
      _date(unix).toIso8601String().substring(0, 16);

  /// Where in [chatId] a message goes for [threadId]: a forum topic in a
  /// forum group, a post's comment thread elsewhere; none for 0.
  td.MessageTopic? topicOf(int chatId, int threadId) {
    if (threadId == 0) return null;
    final chat = _store.chat(chatId);
    if (chat != null && _store.isDirectMessagesGroup(chat)) {
      return td.MessageTopicDirectMessages(directMessagesChatTopicId: threadId);
    }
    return chat != null && _store.isForum(chat)
        ? forumTopic(threadId)
        : commentThread(threadId);
  }

  /// Send options for a scheduled send and/or an animated effect.
  static td.MessageSendOptions sendOptions({
    DateTime? sendAt,
    int effectId = 0,
  }) => td.MessageSendOptions(
    suggestedPostInfo: null,
    disableNotification: false,
    fromBackground: false,
    protectContent: false,
    allowPaidBroadcast: false,
    paidMessageStarCount: 0,
    updateOrderOfInstalledStickerSets: false,
    schedulingState: sendAt == null
        ? null
        : td.MessageSchedulingStateSendAtDate(
            sendDate: sendAt.millisecondsSinceEpoch ~/ 1000,
            repeatPeriod: 0,
          ),
    effectId: effectId,
    sendingId: 0,
    onlyPreview: false,
  );

  static String _clip(String s, [int max = _maxText]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// Tools defined in the part files, each answering null for names it
  /// doesn't own.
  Future<ToolOutput>? _runExtra(String name, Map<String, dynamic> args) =>
      _runApps(name, args) ??
      _runCloud(name, args) ??
      _runDevice(name, args) ??
      _runUtility(name, args) ??
      _runRetro(name, args) ??
      _runMore(name, args) ??
      _runMedia(name, args) ??
      _runBackgrounds(name, args) ??
      _runBots(name, args) ??
      _runActivity(name, args) ??
      _runAnalytics(name, args) ??
      _runChats(name, args) ??
      _runDestructive(name, args) ??
      _runAdmin(name, args) ??
      _runExtra2(name, args) ??
      _runBotFather(name, args) ??
      _runWeb(name, args) ??
      _runStars(name, args) ??
      _runDev(name, args) ??
      _runManage(name, args) ??
      _runAccount(name, args) ??
      _runMoreTd(name, args) ??
      _runYoutube(name, args) ??
      _runDiscover(name, args) ??
      _runNew(name, args) ??
      _runMediaMeta(name, args) ??
      _runMarkets(name, args) ??
      _runNews(name, args) ??
      _runLibrary(name, args) ??
      _runPokemon(name, args) ??
      _runPapers(name, args);

  String? _describeExtra(
    String name,
    Map<String, dynamic> args,
    String title,
  ) =>
      _describeApps(name, args) ??
      _describeCloud(name, args) ??
      _describeDevice(name, args) ??
      _describeMore(name, args, title) ??
      _describeBackgrounds(name, args, title) ??
      _describeBots(name, args, title) ??
      _describeChats(name, args, title) ??
      _describeDestructive(name, args, title) ??
      _describeAdmin(name, args, title) ??
      _describeExtra2(name, args, title) ??
      _describeBotFather(name, args) ??
      _describeWeb(name, args) ??
      _describeStars(name, args, title) ??
      _describeDev(name, args) ??
      _describeManage(name, args, title) ??
      _describeAccount(name, args) ??
      _describeMoreTd(name, args, title) ??
      _describeNew(name, args, title);

  ChatInfo _requireChat(Map<String, dynamic> args) {
    final id = _intOrNull(args, 'chat_id');
    if (id == null) throw ArgumentError('chat_id is required');
    final c = _store.chat(id);
    if (c == null || c.title.isEmpty)
      throw ArgumentError('No chat with id $id. Use list_chats to find it.');
    return c;
  }

  bool _matchesType(ChatInfo c, String type) =>
      type == 'all' || _store.kindOf(c).name == type;

  Map<String, dynamic> _chatJson(ChatInfo c, {bool preview = true}) {
    final last = c.lastMessage;
    final username = _store.chatUsername(c);
    return {
      'chat_id': c.id,
      'title': c.title,
      'type': _store.kindOf(c).name,
      if (username != null) 'username': '@$username',
      if (c.unreadCount > 0) 'unread': c.unreadCount,
      if (c.unreadMentionCount > 0) 'mentions': c.unreadMentionCount,
      if (c.markedUnread) 'marked_unread': true,
      if (c.isMuted) 'muted': true,
      if (c.inArchive && !c.inMain) 'archived': true,
      if (_store.memberCount(c) case final n? when n > 0) 'members': n,
      if (last != null) 'last_activity': _iso(last.date),
      if (preview && last != null)
        'last_message': _clip(_previewLine(last), 140),
    };
  }

  String _previewLine(td.Message m) {
    final g = gistOf(m.content);
    final text = g.text.isNotEmpty ? g.text : (g.detail ?? '');
    return g.kind == 'text' ? text : '[${g.kind}] $text'.trim();
  }

  /// A message for the model, and the snapshot a chip shows.
  (Map<String, dynamic>, PostSnapshot) _message(td.Message m, ChatInfo? chat) {
    final g = gistOf(m.content);
    final chatTitle =
        chat?.title ?? _store.chat(m.chatId)?.title ?? 'Chat ${m.chatId}';
    final kind = chat == null ? null : _store.kindOf(chat);
    final sender = kind == ChatKind.channel
        ? null
        : (m.isOutgoing ? 'You' : _store.senderName(m.senderId));
    final info = m.interactionInfo;
    final forward = m.forwardInfo;
    final json = {
      'ref': 'post:${m.chatId}:${m.id}',
      'chat': chatTitle,
      'sender': ?sender,
      if (m.senderTag.isNotEmpty) 'sender_tag': m.senderTag,
      'date': _iso(m.date),
      if (g.kind != 'text') 'media': g.kind,
      if (g.text.isNotEmpty) 'text': _clip(g.text),
      if (g.detail != null && g.detail!.isNotEmpty)
        'detail': _clip(g.detail!, 300),
      if (info != null && info.viewCount > 0) 'views': info.viewCount,
      if (info != null && info.forwardCount > 0) 'forwards': info.forwardCount,
      if (info?.replyInfo case final r? when r.replyCount > 0)
        'comments': r.replyCount,
      if (forward != null) 'forwarded_from': _origin(forward.origin),
      if (info?.reactions?.reactions case final r? when r.isNotEmpty)
        'reactions': [
          for (final x in r)
            '${switch (x.type) {
              td.ReactionTypeEmoji(:final emoji) => emoji,
              td.ReactionTypePaid() => '⭐',
              _ => 'custom',
            }} ${x.totalCount}${x.isChosen ? ' (you)' : ''}',
        ].join(', '),
      if (m.replyTo case td.MessageReplyToMessage(:final messageId)
          when messageId != 0)
        'reply_to': messageId,
      if (m.replyTo case final td.MessageReplyToMessage r
          when r.messageId != 0 || r.content != null)
        'replying_to': ?_replyContext(m, r),
      if (m.isTopicMessage) 'topic_id': m.messageThreadId,
      if (m.directMessagesTopicId case final t?) 'direct_messages_topic_id': t,
      if (m.editDate > 0) 'edited': true,
      if (chat != null && !m.isOutgoing && m.id > chat.lastReadInboxMessageId)
        'unread': true,
    };
    final snapshot = PostSnapshot(
      chatId: m.chatId,
      messageId: m.id,
      chatTitle: chatTitle,
      date: _date(m.date),
      text: g.text.isNotEmpty ? g.text : (g.detail ?? ''),
      sender: sender,
      kind: g.kind,
      accountId: _client.accountId,
    );
    return (json, snapshot);
  }

  String _origin(td.MessageOrigin o) => switch (o) {
    td.MessageOriginUser(:final senderUserId) => _store.userName(senderUserId),
    td.MessageOriginHiddenUser(:final senderName) => senderName,
    td.MessageOriginChat(:final senderChatId) =>
      _store.chat(senderChatId)?.title ?? 'a chat',
    td.MessageOriginChannel(:final chatId) =>
      _store.chat(chatId)?.title ?? 'a channel',
  };

  // ---- tools ---------------------------------------------------------------

  Future<ToolOutput> _overview() async {
    await _store.ensureChatsLoaded();
    final listed = _store.chats.values
        .where((c) => c.isListed && c.title.isNotEmpty)
        .toList();
    final byKind = <String, int>{};
    for (final c in listed) {
      byKind.update(_store.kindOf(c).name, (n) => n + 1, ifAbsent: () => 1);
    }
    final unread = listed.where((c) => c.hasUnread).toList();
    final unreadDms = unread
        .where((c) => _store.kindOf(c) == ChatKind.private)
        .toList();
    final me = _store.me;
    return ToolOutput({
      if (me != null)
        'me': {
          'name': '${me.firstName} ${me.lastName}'.trim(),
          if (_store.username(me.usernames) case final u?) 'username': '@$u',
          'is_premium': me.isPremium,
        },
      'now': DateTime.now().toIso8601String().substring(0, 16),
      'total_chats': listed.length,
      'by_type': byKind,
      'archived': listed.where((c) => c.inArchive && !c.inMain).length,
      'muted': listed.where((c) => c.isMuted).length,
      'chats_with_unread': unread.length,
      'unread_messages': unread.fold<int>(0, (n, c) => n + c.unreadCount),
      'unread_dms': {
        'chats': unreadDms.length,
        'messages': unreadDms.fold<int>(0, (n, c) => n + c.unreadCount),
        'from': [
          for (final c in unreadDms.take(15)) '${c.title} (${c.unreadCount})',
        ],
      },
      'unread_mentions': listed.fold<int>(
        0,
        (n, c) => n + c.unreadMentionCount,
      ),
    });
  }

  List<ChatInfo> _sortedChats() {
    final list =
        _store.chats.values
            .where((c) => c.isListed && c.title.isNotEmpty)
            .toList()
          ..sort(
            (a, b) =>
                (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0),
          );
    return list;
  }

  Future<ToolOutput> _listChats(Map<String, dynamic> args) async {
    await _store.ensureChatsLoaded();
    final type = '${args['type'] ?? 'all'}';
    final query = '${args['query'] ?? ''}'
        .toLowerCase()
        .replaceFirst('@', '')
        .trim();
    final unreadOnly = args['unread_only'] == true;
    final archived = args['include_archived'] != false;
    final archivedOnly = args['archived_only'] == true;
    final muted = args['include_muted'] != false;
    final since = _hours(args, 'active_since_hours');
    final limit = _int(args, 'limit', fallback: 50, max: 200);
    final after = since == null
        ? null
        : _unix(
            DateTime.now().subtract(Duration(minutes: (since * 60).round())),
          );
    final inFolder = await _folderFilter(args);

    final matches = _sortedChats().where((c) {
      if (inFolder != null && !inFolder.contains(c.id)) return false;
      if (!_matchesType(c, type)) return false;
      if (unreadOnly && !c.hasUnread) return false;
      if (!archived && !c.inMain) return false;
      if (archivedOnly && !c.inArchive) return false;
      if (!muted && c.isMuted) return false;
      if (after != null && (c.lastMessage?.date ?? 0) < after) return false;
      if (query.isNotEmpty) {
        final u = _store.chatUsername(c)?.toLowerCase() ?? '';
        if (!c.title.toLowerCase().contains(query) && !u.contains(query))
          return false;
      }
      return true;
    }).toList();
    return ToolOutput({
      'total_matching': matches.length,
      'chats': [for (final c in matches.take(limit)) _chatJson(c)],
      if (matches.length > limit)
        'note':
            'Showing $limit of ${matches.length}. Narrow with type/query or raise limit.',
    });
  }

  Future<ToolOutput> _chatInfo(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final out = _chatJson(c);
    switch (c.type) {
      case td.ChatTypeSupergroup(:final supergroupId):
        final full = await _client.send<td.SupergroupFullInfo>(
          td.GetSupergroupFullInfo(supergroupId: supergroupId),
          limited: true,
        );
        out['description'] = full.description;
        out['members'] = full.memberCount;
        if (full.inviteLink?.inviteLink case final link?)
          out['invite_link'] = link;
        final sg = _store.supergroups[supergroupId];
        if (sg != null) {
          out['can_post'] = switch (sg.status) {
            td.ChatMemberStatusCreator() => true,
            td.ChatMemberStatusAdministrator(:final rights) =>
              rights.canPostMessages || !sg.isChannel,
            td.ChatMemberStatusMember() => !sg.isChannel,
            _ => false,
          };
        }
      case td.ChatTypePrivate(:final userId):
        final full = await _client.send<td.UserFullInfo>(
          td.GetUserFullInfo(userId: userId),
          limited: true,
        );
        if (full.bio?.text case final bio? when bio.isNotEmpty)
          out['bio'] = bio;
        if (full.note?.text case final note? when note.isNotEmpty)
          out['your_private_note'] = note;
        if (full.firstProfileAudio case final a?)
          out['profile_music'] = [
            a.performer,
            a.title,
          ].where((e) => e.isNotEmpty).join(' – ');
        final u = _store.users[userId];
        if (u != null) {
          out['status'] = switch (u.status) {
            td.UserStatusOnline() => 'online',
            td.UserStatusOffline(:final wasOnline) =>
              'last seen ${_iso(wasOnline)}',
            td.UserStatusRecently() => 'recently',
            td.UserStatusLastWeek() => 'within a week',
            td.UserStatusLastMonth() => 'within a month',
            _ => 'unknown',
          };
          if (u.phoneNumber.isNotEmpty) out['is_contact'] = u.isContact;
        }
      case td.ChatTypeBasicGroup(:final basicGroupId):
        final full = await _client.send<td.BasicGroupFullInfo>(
          td.GetBasicGroupFullInfo(basicGroupId: basicGroupId),
          limited: true,
        );
        out['description'] = full.description;
        out['members'] = full.members.length;
      default:
        break;
    }
    final username = _store.chatUsername(c);
    if (username != null) out['link'] = 'https://t.me/$username';
    return ToolOutput(out);
  }

  /// Pages through a chat's history, newest first, until [limit] messages
  /// or one older than [after]. `onlyLocal: false` lets TDLib fetch what it
  /// hasn't cached; each page is one limited request.
  /// Messages seen recently, so a reply can say what it answers.
  final Map<String, td.Message> _seenMessages = {};

  void _remember(Iterable<td.Message> messages) {
    for (final m in messages) {
      _seenMessages['${m.chatId}:${m.id}'] = m;
    }
    // Plenty for a few conversations; oldest go first.
    if (_seenMessages.length > 3000) {
      for (final k
          in _seenMessages.keys.take(_seenMessages.length - 2500).toList()) {
        _seenMessages.remove(k);
      }
    }
  }

  /// Fetches the originals of replies in [messages] that aren't known yet
  /// (at most [max] requests), so the model sees what each reply answers.
  Future<void> loadRepliedMessages(
    Iterable<td.Message> messages, {
    int max = 15,
  }) async {
    _remember(messages);
    var fetched = 0;
    for (final m in messages) {
      if (fetched >= max) break;
      final r = m.replyTo;
      if (r is! td.MessageReplyToMessage ||
          r.messageId == 0 ||
          r.content != null)
        continue;
      final chat = r.chatId == 0 ? m.chatId : r.chatId;
      if (_seenMessages.containsKey('$chat:${r.messageId}')) continue;
      fetched++;
      try {
        _remember([
          await _client.send<td.Message>(
            td.GetRepliedMessage(chatId: m.chatId, messageId: m.id),
            limited: true,
          ),
        ]);
      } catch (_) {
        // Deleted, or in a chat this account can't read.
      }
    }
  }

  /// Who and what a reply answers, as far as it's known: the quoted part
  /// always, the original's sender and text when it was seen or fetched.
  Map<String, dynamic>? _replyContext(
    td.Message m,
    td.MessageReplyToMessage r,
  ) {
    final chat = r.chatId == 0 ? m.chatId : r.chatId;
    final original = _seenMessages['$chat:${r.messageId}'];
    final content = original?.content ?? r.content;
    final quote = r.quote?.text.text ?? '';
    if (original == null && content == null && quote.isEmpty) return null;
    final g = content == null ? null : gistOf(content);
    final text = g == null
        ? ''
        : (g.text.isNotEmpty ? g.text : (g.detail ?? g.kind));
    return {
      if (original != null)
        'from': original.isOutgoing
            ? 'you (the user)'
            : _store.senderName(original.senderId),
      if (r.origin != null && original == null) 'from': _origin(r.origin!),
      if (text.isNotEmpty) 'text': _clip(text, 240),
      if (g != null && g.kind != 'text') 'media': g.kind,
      if (quote.isNotEmpty) 'quoted_part': _clip(quote, 240),
      if (chat != m.chatId)
        'in_chat': _store.chat(chat)?.title ?? 'another chat',
      if (original != null) 'ref': 'post:${original.chatId}:${original.id}',
    };
  }

  Future<List<td.Message>> _history(
    ChatInfo c, {
    required int limit,
    int? after,
    int fromId = 0,
    int? minId,
    int? topicId,
  }) async {
    final out = <td.Message>[];
    var from = fromId;
    for (var page = 0; page < 6 && out.length < limit; page++) {
      final want = (limit - out.length).clamp(1, 50);
      final messages = topicId == null
          ? (await _client.send<td.Messages>(
              td.GetChatHistory(
                chatId: c.id,
                fromMessageId: from,
                offset: 0,
                limit: want,
                onlyLocal: false,
              ),
              limited: true,
            )).messages.whereType<td.Message>().toList()
          : (await topicPage(
              c.id,
              topicId,
              fromId: from,
              limit: want,
            )).where((m) => m.id != from).toList();
      if (messages.isEmpty) break;
      var stop = false;
      for (final m in messages) {
        if ((after != null && m.date < after) ||
            (minId != null && m.id <= minId)) {
          stop = true;
          break;
        }
        out.add(m);
        if (out.length >= limit) break;
      }
      if (stop) break;
      from = messages.last.id;
    }
    await loadRepliedMessages(out);
    if (_settings.aiReadOnView &&
        out.isNotEmpty &&
        (c.hasUnread || c.unreadMentionCount > 0)) {
      await markRead(c, seen: out).catchError((Object _) {});
    }
    return out;
  }

  Future<ToolOutput> _readMessages(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final limit = _int(args, 'limit', fallback: 20, max: 50);
    final since = _hours(args, 'since_hours');
    final unreadOnly = args['unread_only'] == true;
    final messages = await _history(
      c,
      limit: limit,
      after: since == null
          ? null
          : _unix(
              DateTime.now().subtract(Duration(minutes: (since * 60).round())),
            ),
      fromId: _intOrNull(args, 'before_message_id') ?? 0,
      minId: unreadOnly ? c.lastReadInboxMessageId : null,
      topicId: _intOrNull(args, 'topic_id'),
    );
    final posts = <PostSnapshot>[];
    final json = <Map<String, dynamic>>[];
    for (final m in messages) {
      final (j, p) = _message(m, c);
      json.add(j);
      posts.add(p);
    }
    return ToolOutput({
      'chat': _chatJson(c, preview: false),
      'count': json.length,
      'messages': json,
      if (json.length == limit)
        'more':
            'Older messages exist; pass before_message_id=${messages.last.id}.',
    }, posts: posts);
  }

  Future<ToolOutput> _recentActivity(Map<String, dynamic> args) async {
    await _store.ensureChatsLoaded();
    final hours = _hours(args, 'since_hours') ?? 24;
    final type = '${args['type'] ?? 'channel'}';
    final unreadOnly = args['unread_only'] == true;
    final muted = args['include_muted'] != false;
    final maxChats = _int(args, 'max_chats', fallback: 12, max: 25);
    final perChat = _int(args, 'per_chat', fallback: 6, max: 20);
    final after = _unix(
      DateTime.now().subtract(Duration(minutes: (hours * 60).round())),
    );
    final inFolder = await _folderFilter(args);

    final active = _sortedChats().where((c) {
      if (inFolder != null && !inFolder.contains(c.id)) return false;
      if (!_matchesType(c, type)) return false;
      if (args['archived_only'] == true && !c.inArchive) return false;
      if ((c.lastMessage?.date ?? 0) < after) return false;
      if (unreadOnly && !c.hasUnread) return false;
      if (!muted && c.isMuted) return false;
      return true;
    }).toList();

    final posts = <PostSnapshot>[];
    final chats = <Map<String, dynamic>>[];
    String? stopped;
    for (final c in active.take(maxChats)) {
      try {
        final messages = await _history(
          c,
          limit: perChat,
          after: after,
          minId: unreadOnly ? c.lastReadInboxMessageId : null,
        );
        final list = <Map<String, dynamic>>[];
        for (final m in messages) {
          final (j, p) = _message(m, c);
          list.add(j);
          posts.add(p);
        }
        chats.add({..._chatJson(c, preview: false), 'messages': list});
      } on TelegramException catch (e) {
        if (!e.isFloodWait) rethrow;
        stopped =
            'Telegram asked to slow down after ${chats.length} chats; the rest were skipped.';
        break;
      }
    }
    return ToolOutput({
      'window_hours': hours,
      'active_chats_in_window': active.length,
      'chats_read': chats.length,
      'chats': chats,
      if (active.length > maxChats && stopped == null)
        'not_read': [
          for (final c in active.skip(maxChats).take(40))
            '${c.title} (id ${c.id})',
        ],
      'note': ?stopped,
    }, posts: posts);
  }

  Future<ToolOutput> _search(Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) throw ArgumentError('query is required');
    final limit = _int(args, 'limit', fallback: 20, max: 50);
    final since = _hours(args, 'since_hours');
    final after = since == null
        ? 0
        : _unix(
            DateTime.now().subtract(Duration(minutes: (since * 60).round())),
          );
    final chatId = _intOrNull(args, 'chat_id');

    final List<td.Message> found;
    if (chatId != null) {
      final c = _requireChat(args);
      final r = await _client.send<td.FoundChatMessages>(
        td.SearchChatMessages(
          chatId: c.id,
          query: query,
          fromMessageId: 0,
          offset: 0,
          limit: limit,
          topicId: null,
        ),
        limited: true,
      );
      found = r.messages.where((m) => m.date >= after).toList();
    } else {
      final type = '${args['type'] ?? 'all'}';
      final r = await _client.send<td.FoundMessages>(
        td.SearchMessages(
          chatList: null,
          chatTypeFilter: switch (type) {
            'private' => const td.SearchMessagesChatTypeFilterPrivate(),
            'group' => const td.SearchMessagesChatTypeFilterGroup(),
            'channel' => const td.SearchMessagesChatTypeFilterChannel(),
            _ => null,
          },
          query: query,
          offset: '',
          limit: limit,
          minDate: after,
          maxDate: 0,
        ),
        limited: true,
      );
      found = r.messages.where((m) {
        if (type != 'private' && type != 'group') return true;
        final c = _store.chat(m.chatId);
        return c != null && _store.kindOf(c).name == type;
      }).toList();
    }
    final posts = <PostSnapshot>[];
    final json = <Map<String, dynamic>>[];
    for (final m in found) {
      final (j, p) = _message(m, _store.chat(m.chatId));
      json.add(j);
      posts.add(p);
    }
    return ToolOutput({
      'query': query,
      'count': json.length,
      'messages': json,
    }, posts: posts);
  }

  Future<ToolOutput> _getMessage(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    if (id == null) throw ArgumentError('message_id is required');
    final m = await _client.send<td.Message>(
      td.GetMessage(chatId: c.id, messageId: id),
      limited: true,
    );
    final (j, p) = _message(m, c);
    j['text'] = gistOf(m.content).text;
    final link = await messageLink(c.id, id);
    if (link != null) j['link'] = link;
    return ToolOutput({'message': j}, posts: [p]);
  }

  Future<String?> messageLink(int chatId, int messageId) async {
    try {
      final l = await _client.send<td.MessageLink>(
        td.GetMessageLink(
          chatId: chatId,
          messageId: messageId,
          mediaTimestamp: 0,
          checklistTaskId: 0,
          pollOptionId: '',
          forAlbum: false,
          inMessageThread: false,
        ),
        limited: true,
      );
      return l.link;
    } catch (_) {
      return null;
    }
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _send(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    // By now these are local paths: the approval card resolved them.
    final files = [
      for (final f in (args['files'] as List? ?? const []))
        if (File('$f').existsSync()) '$f',
    ];
    final sent = await sendToChat(
      chatId: c.id,
      text: '${args['text'] ?? ''}',
      files: files,
      asFiles: args['send_as'] == 'file',
      effectId: int.tryParse('${args['effect_id'] ?? ''}') ?? 0,
      replyToMessageId: _intOrNull(args, 'reply_to_message_id'),
    );
    final posts = [for (final m in sent) _message(m, c).$2];
    return ToolOutput({
      'sent': true,
      'chat': c.title,
      'messages': sent.length,
      if (files.isNotEmpty) 'files': files.length,
      if (sent.isNotEmpty) 'ref': 'post:${sent.first.chatId}:${sent.first.id}',
    }, posts: posts);
  }

  Future<ToolOutput> _sendVoice(Map<String, dynamic> args) async {
    final chat = _requireChat(args);
    final files = (args['files'] as List? ?? const [])
        .map((file) => '$file')
        .where((path) => File(path).existsSync())
        .toList();
    if (files.length != 1) {
      throw ArgumentError('Choose exactly one recorded voice-note attachment.');
    }
    final sent = await sendVoiceNote(
      chatId: chat.id,
      path: files.single,
      duration: _int(args, 'duration', fallback: 0, min: 0),
      caption: '${args['text'] ?? ''}',
      replyToMessageId: _intOrNull(args, 'reply_to_message_id'),
      threadId: _int(args, 'topic_id', fallback: 0, min: 0),
    );
    return ToolOutput(
      {
        'sent': true,
        'chat': chat.title,
        'voice_message': true,
        'ref': 'post:${sent.chatId}:${sent.id}',
      },
      posts: [_message(sent, chat).$2],
    );
  }

  /// Sends a native Telegram voice message from a locally recorded Opus file.
  /// Plain messages with Telegram's free formatting: **bold**, __italic__
  /// (or *italic*, _italic_), ~~strikethrough~~, ||spoiler||, `code`,
  /// ```code blocks```, [links](https://…), <u>underline</u>; "# headings"
  /// become bold lines and "- items" bullets. TDLib's lenient parser ignores
  /// mistakes, so a stray * stays a *.
  Future<td.FormattedText> formatText(String text) async {
    final plain = td.FormattedText(text: text, entities: const []);
    if (!RegExp(r'[*_~|`\[#<-]').hasMatch(text)) return plain;
    var md = text
        // Headings and bullets the way chat apps show them.
        .replaceAllMapped(
          RegExp(r'^#{1,6}\s+(.+?)\s*#*$', multiLine: true),
          (m) => '**${m[1]}**',
        )
        .replaceAllMapped(
          RegExp(r'^(\s*)[-*+]\s+(?!\[)', multiLine: true),
          (m) => '${m[1]}• ',
        )
        // Single-star and single-underscore italics, as most writers use.
        .replaceAllMapped(
          RegExp(r'(?<![*\w])\*(?![\s*])([^*\n]+?)(?<!\s)\*(?![*\w])'),
          (m) => '__${m[1]}__',
        )
        .replaceAllMapped(
          RegExp(r'(?<![_\w])_(?![\s_])([^_\n]+?)(?<!\s)_(?![_\w])'),
          (m) => '__${m[1]}__',
        );
    // Underline has no Markdown; pull <u>…</u> out and mark it afterwards.
    final underlined = <String>[];
    md = md.replaceAllMapped(RegExp(r'<u>(.+?)</u>', dotAll: true), (m) {
      underlined.add(m[1]!);
      return '\u0000${underlined.length - 1}\u0000';
    });
    td.FormattedText f;
    try {
      f = await _client.send<td.FormattedText>(
        td.ParseMarkdown(
          text: td.FormattedText(text: md, entities: const []),
        ),
      );
    } catch (_) {
      return plain;
    }
    if (underlined.isEmpty) return f;
    // Put the underlined pieces back, shifting entities that come after.
    var out = f.text;
    var entities = [...f.entities];
    for (var i = 0; i < underlined.length; i++) {
      final marker = '\u0000$i\u0000';
      final at = out.indexOf(marker);
      if (at < 0) continue;
      final piece = underlined[i];
      final delta = piece.length - marker.length;
      out = out.replaceRange(at, at + marker.length, piece);
      entities = [
        for (final e in entities)
          e.offset >= at + marker.length
              ? td.TextEntity(
                  offset: e.offset + delta,
                  length: e.length,
                  type: e.type,
                )
              : (e.offset <= at && e.offset + e.length >= at + marker.length)
              ? td.TextEntity(
                  offset: e.offset,
                  length: e.length + delta,
                  type: e.type,
                )
              : e,
        td.TextEntity(
          offset: at,
          length: piece.length,
          type: const td.TextEntityTypeUnderline(),
        ),
      ];
    }
    return td.FormattedText(text: out, entities: entities);
  }

  /// Shows the other side what's coming, the way a person sending would:
  /// "typing…" for a moment (longer for longer text), or "sending a
  /// photo/video/file…" kept up every few seconds while files upload; stop
  /// the returned timer once sent. Skipped in Saved Messages and channels,
  /// where nobody sees it.
  Future<Timer?> announceSending(
    int chatId, {
    int threadId = 0,
    String text = '',
    List<String> files = const [],
    bool asFiles = false,
    bool voice = false,
  }) async {
    final chat = _store.chat(chatId);
    if (chatId == _store.me?.id ||
        (chat != null && _store.kindOf(chat) == ChatKind.channel))
      return null;
    final td.ChatAction action = voice
        ? const td.ChatActionUploadingVoiceNote(progress: 0)
        : files.isEmpty
        ? const td.ChatActionTyping()
        : !asFiles && files.every(_isVideo)
        ? const td.ChatActionUploadingVideo(progress: 0)
        : !asFiles && files.every((f) => _isPhoto(f) || _isGif(f))
        ? const td.ChatActionUploadingPhoto(progress: 0)
        : const td.ChatActionUploadingDocument(progress: 0);
    Future<void> tell() => _client
        .send<td.Ok>(
          td.SendChatAction(
            chatId: chatId,
            topicId: topicOf(chatId, threadId),
            businessConnectionId: '',
            action: action,
          ),
        )
        .then((_) {}, onError: (Object _) {});
    await tell();
    if (files.isEmpty && !voice) {
      await Future<void>.delayed(
        Duration(milliseconds: (text.length * 25).clamp(800, 3000)),
      );
      return null;
    }
    // Telegram shows an action for about five seconds; uploads take longer.
    return Timer.periodic(const Duration(seconds: 4), (_) => tell());
  }

  Future<td.Message> sendVoiceNote({
    required int chatId,
    required String path,
    required int duration,
    String caption = '',
    int? replyToMessageId,
    int threadId = 0,
  }) async {
    final busy = await announceSending(chatId, threadId: threadId, voice: true);
    try {
      return await _sendVoiceNote(
        chatId: chatId,
        path: path,
        duration: duration,
        caption: caption,
        replyToMessageId: replyToMessageId,
        threadId: threadId,
      );
    } finally {
      busy?.cancel();
    }
  }

  Future<td.Message> _sendVoiceNote({
    required int chatId,
    required String path,
    required int duration,
    String caption = '',
    int? replyToMessageId,
    int threadId = 0,
  }) async => _client.send<td.Message>(
    td.SendMessage(
      chatId: chatId,
      topicId: topicOf(chatId, threadId),
      replyTo: replyToMessageId == null
          ? null
          : replyToMessage(replyToMessageId),
      options: null,
      replyMarkup: null,
      inputMessageContent: td.InputMessageVoiceNote(
        voiceNote: inputVoiceNote(path, duration: duration),
        caption: caption.trim().isEmpty
            ? null
            : await formatText(caption.trim()),
        selfDestructType: null,
      ),
    ),
    limited: true,
  );

  /// Sends text and files to a chat (or a forum topic), as the assistant's
  /// approved send or the person's own composer. Several photos/videos go
  /// as one album. Returns the messages with the ids Telegram settled on:
  /// a message being sent has a temporary id that stops existing once
  /// Telegram confirms it.
  Future<List<td.Message>> sendToChat({
    required int chatId,
    String text = '',
    List<String> files = const [],
    int? replyToMessageId,
    int threadId = 0,
    DateTime? sendAt,
    int? replyInChatId,
    td.InputTextQuote? quote,
    bool asFiles = false,
    int effectId = 0,
  }) async {
    text = text.trim();
    final options = sendAt == null && effectId == 0
        ? null
        : sendOptions(sendAt: sendAt, effectId: effectId);
    if (text.isEmpty && files.isEmpty) throw ArgumentError('Nothing to send.');
    // A reply to a message in another chat (a channel post quoted in a DM,
    // say) names that chat; [replyInChatId] is where the original lives.
    td.InputMessageReplyTo? replyTo = replyToMessageId == null
        ? null
        : replyInChatId != null && replyInChatId != chatId
        ? td.InputMessageReplyToExternalMessage(
            chatId: replyInChatId,
            messageId: replyToMessageId,
            quote: quote,
            checklistTaskId: 0,
            pollOptionId: '',
          )
        : replyToMessage(replyToMessageId, quote: quote);
    final sent = <td.Message>[];
    // Confirmations can arrive right after the reply, so they are collected
    // from before the first send.
    final settled = <int, td.Message>{};
    final failed = <int, td.TdError>{};
    final waiters = <int, Completer<td.Message>>{};
    // Files going up: shown on the tool card that sent them, with how much
    // of how much has gone, and a cancel that takes the messages back.
    var sizes = 0;
    for (final f in files) {
      try {
        sizes += File(f).lengthSync();
      } catch (_) {}
    }
    var cancelled = false;
    final upload = files.isEmpty || sizes == 0 || sendAt != null
        ? null
        : DownloadProgress.startUpload(
            files.length == 1 ? files.single.split(RegExp(r'[\/]')).last : '${files.length} files',
            total: sizes,
            files: files.length,
            onCancel: () async {
              cancelled = true;
              final pending = [for (final m in sent) if (m.sendingState != null && !settled.containsKey(m.id)) m.id];
              for (final w in waiters.values) {
                if (!w.isCompleted) w.completeError(const TransferCancelled());
              }
              waiters.clear();
              if (pending.isNotEmpty) {
                await _client.send<td.Ok>(td.DeleteMessages(chatId: chatId, messageIds: pending, revoke: true)).catchError((Object _) => const td.Ok());
              }
            },
          );
    final uploaded = <int, int>{};
    final sub = _client.updates.listen((u) {
      if (upload != null && u is td.UpdateFile) {
        final f = u.file;
        if (f.remote.isUploadingActive || uploaded.containsKey(f.id)) {
          final size = f.size > 0 ? f.size : f.expectedSize;
          uploaded[f.id] = f.remote.isUploadingCompleted ? size : f.remote.uploadedSize;
          upload.set(uploaded.values.fold<int>(0, (a, b) => a + b).clamp(0, sizes));
        }
        return;
      }
      if (u is td.UpdateMessageSendSucceeded && u.message.chatId == chatId) {
        settled[u.oldMessageId] = u.message;
        waiters.remove(u.oldMessageId)?.complete(u.message);
      } else if (u is td.UpdateMessageSendFailed &&
          u.message.chatId == chatId) {
        failed[u.oldMessageId] = u.error;
        waiters
            .remove(u.oldMessageId)
            ?.completeError(TelegramException(u.error.code, u.error.message));
      }
    });

    Future<void> one(td.InputMessageContent content) async {
      sent.add(
        await _client.send<td.Message>(
          td.SendMessage(
            chatId: chatId,
            topicId: topicOf(chatId, threadId),
            replyTo: replyTo,
            options: options,
            replyMarkup: null,
            inputMessageContent: content,
          ),
          limited: true,
        ),
      );
      replyTo = null;
    }

    Future<void> album(List<td.InputMessageContent> contents) async {
      if (contents.length == 1) return one(contents.single);
      final r = await _client.send<td.Messages>(
        td.SendMessageAlbum(
          chatId: chatId,
          topicId: topicOf(chatId, threadId),
          replyTo: replyTo,
          options: options,
          inputMessageContents: contents,
        ),
        limited: true,
      );
      sent.addAll(r.messages.whereType<td.Message>());
      replyTo = null;
    }

    // Scheduled messages go out later; nobody should see "typing…" now.
    final busy = sendAt == null
        ? await announceSending(
            chatId,
            threadId: threadId,
            text: text,
            files: files,
            asFiles: asFiles,
          )
        : null;
    try {
      final formatted = await formatText(text);
      // Captions are capped at 1024 characters; longer text goes on its own.
      if (files.isEmpty || formatted.text.length > 1024) {
        await one(
          td.InputMessageText(
            text: formatted,
            linkPreviewOptions: null,
            clearDraft: false,
          ),
        );
        text = '';
      }
      td.FormattedText? caption() {
        if (text.isEmpty) return null;
        text = '';
        return formatted;
      }

      // As files, pictures and videos go uncompressed, as documents.
      bool visualFile(String f) =>
          !asFiles && (_isPhoto(f) || _isVideo(f) || _isGif(f));
      final visual = files.where(visualFile).toList();
      final docs = files.where((f) => !visualFile(f)).toList();
      // Telegram groups at most ten items per album, and photos/videos can't
      // share an album with documents.
      for (var i = 0; i < visual.length; i += 10) {
        await album([
          for (final f in visual.skip(i).take(10))
            if (_isGif(f))
              td.InputMessageAnimation(
                animation: inputAnimation(f),
                caption: caption(),
                showCaptionAboveMedia: false,
                hasSpoiler: false,
              )
            else if (_isPhoto(f))
              td.InputMessagePhoto(
                photo: inputPhoto(f),
                caption: caption(),
                showCaptionAboveMedia: false,
                selfDestructType: null,
                hasSpoiler: false,
              )
            else
              td.InputMessageVideo(
                video: inputVideo(f),
                caption: caption(),
                showCaptionAboveMedia: false,
                selfDestructType: null,
                hasSpoiler: false,
              ),
        ]);
      }
      for (var i = 0; i < docs.length; i += 10) {
        await album([
          for (final f in docs.skip(i).take(10))
            td.InputMessageDocument(
              // Sent as a file on purpose: keep it a file, not a video.
              document: inputDocument(f, keepAsFile: asFiles),
              caption: caption(),
            ),
        ]);
      }

      final out = <td.Message>[];
      for (final m in sent) {
        if (m.sendingState == null || sendAt != null) {
          out.add(m);
          continue;
        }
        final done = settled[m.id];
        if (done != null) {
          out.add(done);
          continue;
        }
        if (failed[m.id] case final e?)
          throw TelegramException(e.code, e.message);
        if (cancelled) throw const TransferCancelled();
        final c = waiters[m.id] = Completer<td.Message>();
        // Uploads can take a while; past that, the temporary message is
        // still the best there is.
        out.add(
          await c.future.timeout(
            // A big upload shows its progress, so it's worth waiting for.
            Duration(seconds: files.isEmpty ? 15 : (upload != null ? 1800 : 120)),
            onTimeout: () => m,
          ),
        );
      }
      final chat = _store.chat(chatId);
      if (_settings.aiReadOnReply &&
          sendAt == null &&
          chat != null &&
          chat.hasUnread) {
        await markRead(chat).catchError((Object _) {});
      }
      upload?.finish('');
      return out;
    } catch (e) {
      if (!cancelled) upload?.fail(e is TelegramException ? e.message : '$e');
      rethrow;
    } finally {
      busy?.cancel();
      await sub.cancel();
    }
  }

  /// Sends one message and waits for Telegram to accept it, so the id
  /// handed back is the permanent one (a sending message's temporary id
  /// stops existing once it's sent). A rejected send throws Telegram's
  /// reason; past [wait], the temporary message is returned as it is.
  Future<td.Message> sendAndSettle(
    td.SendMessage request, {
    Duration wait = const Duration(seconds: 20),
  }) async {
    // Confirmations can beat the send call's own reply, so collect them first.
    final early = <int, td.Update>{};
    int? temporary;
    final done = Completer<td.Message>();
    void settle(td.Update u) {
      if (done.isCompleted) return;
      switch (u) {
        case td.UpdateMessageSendSucceeded(:final message):
          done.complete(message);
        case td.UpdateMessageSendFailed(:final error):
          done.completeError(TelegramException(error.code, error.message));
        default:
          break;
      }
    }

    final sub = _client.updates.listen((u) {
      final (chat, old) = switch (u) {
        td.UpdateMessageSendSucceeded(:final message, :final oldMessageId) => (
          message.chatId,
          oldMessageId,
        ),
        td.UpdateMessageSendFailed(:final message, :final oldMessageId) => (
          message.chatId,
          oldMessageId,
        ),
        _ => (0, 0),
      };
      if (chat != request.chatId || u is! td.Update) return;
      if (temporary == null) {
        early[old] = u;
      } else if (old == temporary) {
        settle(u);
      }
    });
    try {
      final m = await _client.send<td.Message>(request, limited: true);
      if (m.sendingState == null || request.options?.schedulingState != null)
        return m;
      temporary = m.id;
      if (early[m.id] case final u?) settle(u);
      return await done.future.timeout(wait, onTimeout: () => m);
    } finally {
      await sub.cancel();
    }
  }

  static bool _isPhoto(String path) =>
      RegExp(r'\.(jpe?g|png|webp|heic)$', caseSensitive: false).hasMatch(path);
  static bool _isGif(String path) =>
      RegExp(r'\.gif$', caseSensitive: false).hasMatch(path);
  static bool _isVideo(String path) => RegExp(
    r'\.(mp4|mov|m4v|webm|mkv|3gp)$',
    caseSensitive: false,
  ).hasMatch(path);

  Future<ToolOutput> _contacts(Map<String, dynamic> args) async {
    final users = await _client.send<td.Users>(
      const td.GetContacts(),
      limited: true,
    );
    final q = '${args['query'] ?? ''}'
        .toLowerCase()
        .replaceFirst('@', '')
        .trim();
    final limit = _int(args, 'limit', fallback: 100, max: 300);
    final list = <Map<String, dynamic>>[];
    for (final id in users.userIds) {
      final u = _store.users[id];
      if (u == null) continue;
      final username = _store.username(u.usernames);
      if (q.isNotEmpty &&
          !_store.userName(id).toLowerCase().contains(q) &&
          !(username?.toLowerCase().contains(q) ?? false)) {
        continue;
      }
      list.add({
        'user_id': id,
        'name': _store.userName(id),
        if (username != null) 'username': '@$username',
        'status': _status(u.status),
        if (u.isMutualContact) 'mutual': true,
      });
    }
    return ToolOutput({
      'total': users.totalCount,
      'matching': list.length,
      'contacts': list.take(limit).toList(),
      'note':
          'To read a DM, find it with list_chats(type: private, query: name).',
    });
  }

  String _status(td.UserStatus s) => switch (s) {
    td.UserStatusOnline() => 'online',
    td.UserStatusOffline(:final wasOnline) => 'last seen ${_iso(wasOnline)}',
    td.UserStatusRecently() => 'recently',
    td.UserStatusLastWeek() => 'within a week',
    td.UserStatusLastMonth() => 'within a month',
    _ => 'long ago',
  };

  Future<ToolOutput> _folders(Map<String, dynamic> args) async {
    await _store.ensureChatsLoaded();
    final folderId = _intOrNull(args, 'folder_id');
    if (folderId != null) {
      final title = await _folderTitle(folderId);
      final ids = (await _store.loadFolder(folderId)).toSet();
      final chats = _sortedChats().where((c) => ids.contains(c.id)).toList();
      return ToolOutput({
        'folder_id': folderId,
        'folder': title,
        'total_matching': chats.length,
        'unread_chats': chats.where((c) => c.hasUnread).length,
        'chats': [for (final c in chats.take(100)) _chatJson(c)],
      });
    }
    final folders = <Map<String, dynamic>>[];
    for (final f in _store.folders) {
      final ids = (await _store.loadFolder(f.id)).toSet();
      final chats = _store.chats.values
          .where((c) => ids.contains(c.id))
          .toList();
      folders.add({
        'folder_id': f.id,
        'title': f.title.isNotEmpty ? f.title : await _folderTitle(f.id),
        'chats': chats.length,
        'unread_chats': chats.where((c) => c.hasUnread).length,
      });
    }
    return ToolOutput({
      'folders': folders,
      if (folders.isEmpty) 'note': 'The user has no chat folders.',
    });
  }

  /// A folder's name, from the store or else straight from TDLib.
  Future<String> _folderTitle(int folderId) async {
    final known =
        _store.folders.where((f) => f.id == folderId).firstOrNull?.title ?? '';
    if (known.isNotEmpty) return known;
    try {
      final f = await _client.send<td.ChatFolder>(
        td.GetChatFolder(chatFolderId: folderId),
        limited: true,
      );
      return f.title;
    } on TelegramException {
      throw ArgumentError(
        'No folder with id $folderId. Call list_chat_folders without folder_id to see them.',
      );
    }
  }

  Future<ToolOutput> _mentions(Map<String, dynamic> args) async {
    await _store.ensureChatsLoaded();
    final maxChats = _int(args, 'max_chats', fallback: 8, max: 15);
    final chats = _sortedChats()
        .where((c) => c.unreadMentionCount > 0)
        .toList();
    final posts = <PostSnapshot>[];
    final out = <Map<String, dynamic>>[];
    for (final c in chats.take(maxChats)) {
      final r = await _client.send<td.FoundChatMessages>(
        td.SearchChatMessages(
          chatId: c.id,
          query: '',
          fromMessageId: 0,
          offset: 0,
          limit: 10,
          filter: const td.SearchMessagesFilterUnreadMention(),
          topicId: null,
        ),
        limited: true,
      );
      final list = <Map<String, dynamic>>[];
      for (final m in r.messages) {
        final (j, p) = _message(m, c);
        list.add(j);
        posts.add(p);
      }
      out.add({..._chatJson(c, preview: false), 'messages': list});
    }
    return ToolOutput({
      'chats_with_mentions': chats.length,
      'total_mentions': chats.fold<int>(0, (n, c) => n + c.unreadMentionCount),
      'chats': out,
    }, posts: posts);
  }

  Future<ToolOutput> _filtered(
    Map<String, dynamic> args,
    td.SearchMessagesFilter filter, {
    required int max,
    required int fallback,
  }) async {
    final c = _requireChat(args);
    final limit = _int(args, 'limit', fallback: fallback, max: max);
    final r = await _client.send<td.FoundChatMessages>(
      td.SearchChatMessages(
        chatId: c.id,
        query: '',
        fromMessageId: 0,
        offset: 0,
        limit: limit,
        filter: filter,
        topicId: null,
      ),
      limited: true,
    );
    final posts = <PostSnapshot>[];
    final json = <Map<String, dynamic>>[];
    for (final m in r.messages) {
      final (j, p) = _message(m, c);
      json.add(j);
      posts.add(p);
    }
    return ToolOutput({
      'chat': _chatJson(c, preview: false),
      'total': r.totalCount,
      'count': json.length,
      'messages': json,
    }, posts: posts);
  }

  Future<ToolOutput> _sharedMedia(Map<String, dynamic> args) {
    final td.SearchMessagesFilter filter =
        switch ('${args['type'] ?? 'photo'}') {
          'video' => const td.SearchMessagesFilterVideo(),
          'photo_and_video' => const td.SearchMessagesFilterPhotoAndVideo(),
          'document' => const td.SearchMessagesFilterDocument(),
          'link' => const td.SearchMessagesFilterUrl(),
          'voice' => const td.SearchMessagesFilterVoiceNote(),
          'audio' => const td.SearchMessagesFilterAudio(),
          'gif' => const td.SearchMessagesFilterAnimation(),
          _ => const td.SearchMessagesFilterPhoto(),
        };
    return _filtered(args, filter, max: 50, fallback: 20);
  }

  Future<ToolOutput> _comments(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    if (id == null) throw ArgumentError('message_id is required');
    final limit = _int(args, 'limit', fallback: 20, max: 50);
    final r = await _client.send<td.Messages>(
      td.GetMessageThreadHistory(
        chatId: c.id,
        messageId: id,
        fromMessageId: 0,
        offset: 0,
        limit: limit,
      ),
      limited: true,
    );
    final posts = <PostSnapshot>[];
    final json = <Map<String, dynamic>>[];
    for (final m in r.messages.whereType<td.Message>()) {
      final (j, p) = _message(m, _store.chat(m.chatId));
      json.add(j);
      posts.add(p);
    }
    final commenters = <String, int>{};
    for (final j in json) {
      final who = j['sender'];
      if (who is String)
        commenters.update(who, (n) => n + 1, ifAbsent: () => 1);
    }
    return ToolOutput({
      'post': 'post:${c.id}:$id',
      'total': r.totalCount,
      'count': json.length,
      if (commenters.isNotEmpty)
        'commenters': [
          for (final e
              in (commenters.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            '${e.key} (${e.value})',
        ],
      'messages': json,
    }, posts: posts);
  }

  Map<String, dynamic> _person(
    td.MessageSender s, {
    String? role,
    int? joined,
    String tag = '',
  }) {
    final userId = s is td.MessageSenderUser ? s.userId : null;
    final username = userId == null
        ? null
        : _store.username(_store.users[userId]?.usernames);
    return {
      'user_id': ?userId,
      'name': _store.senderName(s),
      if (username != null) 'username': '@$username',
      if (tag.isNotEmpty) 'tag': tag,
      'role': ?role,
      if (joined != null && joined > 0) 'joined': _iso(joined),
    };
  }

  static String _role(td.ChatMemberStatus s) => switch (s) {
    td.ChatMemberStatusCreator() => 'owner',
    td.ChatMemberStatusAdministrator() => 'admin',
    td.ChatMemberStatusRestricted() => 'restricted',
    _ => 'member',
  };

  Future<ToolOutput> _members(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final filter = '${args['filter'] ?? 'recent'}';
    final limit = _int(args, 'limit', fallback: 30, max: 100);
    if (filter == 'admins' || _store.kindOf(c) == ChatKind.channel) {
      final r = await _client.send<td.ChatAdministrators>(
        td.GetChatAdministrators(chatId: c.id),
        limited: true,
      );
      return ToolOutput({
        'chat': c.title,
        'members': [
          for (final a in r.administrators)
            _person(
              td.MessageSenderUser(userId: a.userId),
              role: a.isOwner
                  ? 'owner'
                  : (a.customTitle.isEmpty ? 'admin' : a.customTitle),
            ),
        ],
      });
    }
    switch (c.type) {
      case td.ChatTypeSupergroup(:final supergroupId):
        final r = await _client.send<td.ChatMembers>(
          td.GetSupergroupMembers(
            supergroupId: supergroupId,
            filter: filter == 'bots'
                ? const td.SupergroupMembersFilterBots()
                : const td.SupergroupMembersFilterRecent(),
            offset: 0,
            limit: limit,
          ),
          limited: true,
        );
        return ToolOutput({
          'chat': c.title,
          'total': r.totalCount,
          'members': [
            for (final m in r.members)
              _person(
                m.memberId,
                role: _role(m.status),
                joined: m.joinedChatDate,
                tag: m.tag,
              ),
          ],
        });
      case td.ChatTypeBasicGroup(:final basicGroupId):
        final full = await _client.send<td.BasicGroupFullInfo>(
          td.GetBasicGroupFullInfo(basicGroupId: basicGroupId),
          limited: true,
        );
        return ToolOutput({
          'chat': c.title,
          'total': full.members.length,
          'members': [
            for (final m in full.members.take(limit))
              _person(
                m.memberId,
                role: _role(m.status),
                joined: m.joinedChatDate,
              ),
          ],
        });
      default:
        throw ArgumentError('${c.title} is not a group.');
    }
  }

  Future<ToolOutput> _publicChats(Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) throw ArgumentError('query is required');
    final r = await _client.send<td.Chats>(
      td.SearchPublicChats(query: query),
      limited: true,
    );
    final results = <Map<String, dynamic>>[];
    for (final id in r.chatIds.take(20)) {
      final c = _store.chat(id);
      if (c == null || c.title.isEmpty) continue;
      results.add({..._chatJson(c, preview: false), 'joined': c.isListed});
    }
    return ToolOutput({'query': query, 'chats': results});
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _forward(Map<String, dynamic> args) async {
    final from = _intOrNull(args, 'from_chat_id');
    final targets = forwardTargets(args);
    final ids = [
      for (final v in (args['message_ids'] as List? ?? const []))
        if (v is num) v.toInt(),
    ];
    if (from == null || targets.isEmpty || ids.isEmpty) {
      throw ArgumentError(
        'from_chat_id, message_ids and to_chat_id (or to_chat_ids) are required',
      );
    }
    final done = <String>[];
    final failed = <String, String>{};
    var count = 0;
    for (final to in targets.take(20)) {
      final target = _store.chat(to);
      if (target == null) {
        failed['$to'] = 'No chat with that id.';
        continue;
      }
      try {
        count += await forwardTo(
          to,
          from,
          ids,
          hideSender: args['hide_sender'] == true,
          removeCaption: args['remove_caption'] == true,
        );
        done.add(target.title);
      } catch (e) {
        failed[target.title] = e is TelegramException
            ? e.friendlyMessage
            : '$e';
      }
    }
    return ToolOutput({
      'sent': done.isNotEmpty,
      'forwarded': count,
      if (done.length == 1) 'chat': done.first else 'chats': done,
      if (failed.isNotEmpty) 'failed': failed,
      if (args['hide_sender'] == true) 'without_sender': true,
      if (args['remove_caption'] == true) 'without_captions': true,
    });
  }

  Future<ToolOutput> _topics(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    if (!_store.isForum(c))
      throw ArgumentError(
        '${c.title} has no topics; read it with read_messages.',
      );
    final r = await _client.send<td.ForumTopics>(
      td.GetForumTopics(
        chatId: c.id,
        query: '${args['query'] ?? ''}',
        offsetDate: 0,
        offsetMessageId: 0,
        offsetForumTopicId: 0,
        limit: 100,
      ),
      limited: true,
    );
    return ToolOutput({
      'chat': c.title,
      'total': r.totalCount,
      'topics': [
        for (final t in r.topics)
          {
            'topic_id': t.info.messageThreadId,
            'name': t.info.name,
            if (t.info.isGeneral) 'general': true,
            if (t.isPinned) 'pinned': true,
            if (t.info.isClosed) 'closed': true,
            if (t.unreadCount > 0) 'unread': t.unreadCount,
            if (t.lastMessage case final m?) 'last_activity': _iso(m.date),
            if (t.lastMessage case final m?)
              'last_message': _clip(_previewLine(m), 140),
          },
      ],
    });
  }

  Future<ToolOutput> _profile(Map<String, dynamic> args) async {
    var userId = _intOrNull(args, 'user_id');
    if (userId == null) {
      final c = _requireChat(args);
      if (c.type is! td.ChatTypePrivate)
        throw ArgumentError('${c.title} is not a person; use get_chat_info.');
      userId = (c.type as td.ChatTypePrivate).userId;
    }
    final u =
        _store.users[userId] ??
        await _client.send<td.User>(td.GetUser(userId: userId), limited: true);
    final full = await _client.send<td.UserFullInfo>(
      td.GetUserFullInfo(userId: userId),
      limited: true,
    );
    td.Chats? common;
    if (full.groupInCommonCount > 0) {
      common = await _client.send<td.Chats>(
        td.GetGroupsInCommon(userId: userId, offsetChatId: 0, limit: 20),
        limited: true,
      );
    }
    final personal = full.personalChatId == 0
        ? null
        : _store.chat(full.personalChatId);
    return ToolOutput({
      'user_id': userId,
      'name': '${u.firstName} ${u.lastName}'.trim(),
      if (_store.username(u.usernames) case final n?) 'username': '@$n',
      if (full.bio?.text case final b? when b.isNotEmpty) 'bio': b,
      'status': _status(u.status),
      'is_contact': u.isContact,
      if (u.isMutualContact) 'mutual_contact': true,
      if (u.isPremium) 'premium': true,
      if (u.type is td.UserTypeBot) 'bot': true,
      if (u.isContact && u.phoneNumber.isNotEmpty) 'phone': '+${u.phoneNumber}',
      if (personal != null)
        'personal_channel': {'chat_id': personal.id, 'title': personal.title},
      'groups_in_common': full.groupInCommonCount,
      if (common != null)
        'common_groups': [
          for (final id in common.chatIds)
            if (_store.chat(id) case final g?)
              {'chat_id': id, 'title': g.title},
        ],
    });
  }

  Future<ToolOutput> _presence(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    if (c.type is! td.ChatTypePrivate)
      throw ArgumentError(
        'Active status is available for people in private chats only.',
      );
    final id = (c.type as td.ChatTypePrivate).userId;
    final u =
        _store.users[id] ??
        await _client.send<td.User>(td.GetUser(userId: id), limited: true);
    return ToolOutput({
      'chat_id': c.id,
      'chat': c.title,
      'user_id': id,
      'status': _status(u.status),
      'online': u.status is td.UserStatusOnline,
    });
  }

  Future<ToolOutput> _sendChatAction(Map<String, dynamic> args) async {
    final chat = _requireChat(args);
    final type = '${args['action'] ?? ''}'.trim().toLowerCase();
    final progress = _int(args, 'progress', fallback: 0, min: 0, max: 100);
    final action = switch (type) {
      'typing' => const td.ChatActionTyping(),
      'recording_video' => const td.ChatActionRecordingVideo(),
      'uploading_video' => td.ChatActionUploadingVideo(progress: progress),
      'recording_voice' => const td.ChatActionRecordingVoiceNote(),
      'uploading_voice' => td.ChatActionUploadingVoiceNote(progress: progress),
      'uploading_photo' => td.ChatActionUploadingPhoto(progress: progress),
      'uploading_document' => td.ChatActionUploadingDocument(
        progress: progress,
      ),
      'choosing_sticker' => const td.ChatActionChoosingSticker(),
      'choosing_location' => const td.ChatActionChoosingLocation(),
      'choosing_contact' => const td.ChatActionChoosingContact(),
      'playing_game' => const td.ChatActionStartPlayingGame(),
      'recording_video_note' => const td.ChatActionRecordingVideoNote(),
      'uploading_video_note' => td.ChatActionUploadingVideoNote(
        progress: progress,
      ),
      'watching_animations' => td.ChatActionWatchingAnimations(
        emoji: '${args['emoji'] ?? '👀'}',
      ),
      'cancel' => null,
      _ => throw ArgumentError('Unknown activity "$type".'),
    };
    final topic = _int(args, 'topic_id', fallback: 0, min: 0);
    await _client.send<td.Ok>(
      td.SendChatAction(
        chatId: chat.id,
        topicId: topicOf(chat.id, topic),
        businessConnectionId: '',
        action: action,
      ),
      limited: true,
    );
    return ToolOutput({
      'activity_sent': true,
      'chat': chat.title,
      'action': type,
      if (action != null && type.startsWith('uploading_')) 'progress': progress,
    });
  }

  /// Posts a poll or quiz, as the composer or the assistant drafted it.
  Future<td.Message> sendPoll(int chatId, PollDraft d, {int threadId = 0}) {
    if (d.question.isEmpty) throw ArgumentError('The poll needs a question.');
    if (d.options.length < 2 || d.options.length > 10)
      throw ArgumentError('A poll takes 2 to 10 options.');
    td.FormattedText f(String t) =>
        td.FormattedText(text: t, entities: const []);
    return _client.send<td.Message>(
      td.SendMessage(
        chatId: chatId,
        topicId: topicOf(chatId, threadId),
        replyTo: null,
        options: null,
        replyMarkup: null,
        inputMessageContent: td.InputMessagePoll(
          question: f(d.question),
          options: [
            for (final o in d.options)
              td.InputPollOption(text: f(o), media: null),
          ],
          description: null,
          media: null,
          isAnonymous: d.anonymous,
          allowsMultipleAnswers: d.multipleAnswers && !d.quiz,
          allowsRevoting: !d.quiz,
          membersOnly: false,
          countryCodes: const [],
          shuffleOptions: false,
          hideResultsUntilCloses: false,
          type: d.quiz
              ? td.InputPollTypeQuiz(
                  correctOptionIds: [
                    d.correctOption.clamp(0, d.options.length - 1),
                  ],
                  explanation: f(d.explanation),
                  explanationMedia: null,
                )
              : const td.InputPollTypeRegular(allowAddingOptions: false),
          openPeriod: d.openSeconds,
          closeDate: 0,
          isClosed: false,
        ),
      ),
      limited: true,
    );
  }

  /// Shares a Telegram user as a contact card.
  Future<td.Message> sendContact(int chatId, int userId) async {
    final u =
        _store.users[userId] ??
        await _client.send<td.User>(td.GetUser(userId: userId), limited: true);
    return _client.send<td.Message>(
      td.SendMessage(
        chatId: chatId,
        topicId: null,
        replyTo: null,
        options: null,
        replyMarkup: null,
        inputMessageContent: td.InputMessageContact(
          contact: td.Contact(
            phoneNumber: u.phoneNumber,
            firstName: u.firstName,
            lastName: u.lastName,
            vcard: '',
            userId: u.id,
          ),
        ),
      ),
      limited: true,
    );
  }

  /// Sends the phone's location, live for [liveMinutes] when above 0.
  Future<ToolOutput> sendLocation(int chatId, {int liveMinutes = 0}) =>
      _sendLiveLocation({'chat_id': chatId, 'live_minutes': liveMinutes});

  Future<ToolOutput> _sendLiveLocation(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    if (!await Geolocator.isLocationServiceEnabled())
      throw ArgumentError('Location services are turned off on this device.');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw ArgumentError(
        'Location permission was not granted. Allow it in Settings before sharing.',
      );
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final mins = _int(args, 'live_minutes', fallback: 0, min: 0, max: 1440);
    final sent = await _client.send<td.Message>(
      td.SendMessage(
        chatId: c.id,
        topicId: null,
        replyTo: null,
        options: null,
        replyMarkup: null,
        inputMessageContent: mins == 0
            ? td.InputMessageLocation(
                location: td.Location(
                  latitude: p.latitude,
                  longitude: p.longitude,
                  horizontalAccuracy: p.accuracy,
                ),
              )
            : td.InputMessageLiveLocation(
                location: td.LiveLocation(
                  location: td.Location(
                    latitude: p.latitude,
                    longitude: p.longitude,
                    horizontalAccuracy: p.accuracy,
                  ),
                  livePeriod: mins * 60,
                  heading: 0,
                  proximityAlertRadius: 0,
                ),
              ),
      ),
      limited: true,
    );
    if (mins > 0) {
      final key = '${sent.chatId}:${sent.id}';
      _liveLocationStreams[key]?.cancel();
      final stream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((next) async {
            try {
              await _client.send<td.Message>(
                td.EditMessageLiveLocation(
                  chatId: sent.chatId,
                  messageId: sent.id,
                  location: td.LiveLocation(
                    location: td.Location(
                      latitude: next.latitude,
                      longitude: next.longitude,
                      horizontalAccuracy: next.accuracy,
                    ),
                    livePeriod: 0,
                    heading: next.heading.isFinite && next.heading > 0
                        ? next.heading.round().clamp(1, 360)
                        : 0,
                    proximityAlertRadius: 0,
                  ),
                ),
                limited: true,
              );
            } catch (_) {}
          });
      _liveLocationStreams[key] = stream;
      Future<void>.delayed(Duration(minutes: mins), () async {
        await stream.cancel();
        _liveLocationStreams.remove(key);
      });
    }
    return ToolOutput({
      'sent': true,
      'chat': c.title,
      'live_minutes': mins,
      'ref': 'post:${sent.chatId}:${sent.id}',
    });
  }

  Map<String, dynamic> _stickerJson(td.Sticker s) => {
    'file_id': s.sticker.id,
    'sticker_id': s.id,
    'emoji': s.emoji,
    'width': s.width,
    'height': s.height,
    'set_id': s.setId,
  };

  Future<ToolOutput> _browseStickers(Map<String, dynamic> args) async {
    final limit = _int(args, 'limit', fallback: 30, max: 100);
    final r = await _client.send<td.Stickers>(
      td.GetStickers(
        stickerType: const td.StickerTypeRegular(),
        query: '${args['query'] ?? ''}'.trim(),
        limit: limit,
        chatId: _intOrNull(args, 'chat_id') ?? 0,
      ),
      limited: true,
    );
    return ToolOutput({
      'count': r.stickers.length,
      'stickers': [for (final s in r.stickers) _stickerJson(s)],
    });
  }

  Future<ToolOutput> _searchStickers(Map<String, dynamic> args) async {
    final emojis = '${args['emojis'] ?? ''}'.trim();
    if (emojis.isEmpty) throw ArgumentError('emojis is required');
    final r = await _client.send<td.Stickers>(
      td.SearchStickers(
        stickerType: const td.StickerTypeRegular(),
        emojis: emojis,
        query: '',
        inputLanguageCodes: const [],
        offset: 0,
        limit: _int(args, 'limit', fallback: 30, min: 1, max: 100),
      ),
      limited: true,
    );
    return ToolOutput({
      'count': r.stickers.length,
      'stickers': [for (final s in r.stickers) _stickerJson(s)],
    });
  }

  Future<ToolOutput> _sendSticker(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final fileId = _intOrNull(args, 'file_id');
    if (fileId == null) throw ArgumentError('file_id is required');
    final m = await _client.send<td.Message>(
      td.SendMessage(
        chatId: c.id,
        topicId: null,
        replyTo: null,
        options: null,
        replyMarkup: null,
        inputMessageContent: td.InputMessageSticker(
          sticker: td.InputSticker(
            sticker: td.InputFileId(id: fileId),
            thumbnail: null,
            width: _int(args, 'width', fallback: 512),
            height: _int(args, 'height', fallback: 512),
          ),
          emoji: '${args['emoji'] ?? ''}',
        ),
      ),
      limited: true,
    );
    return ToolOutput({
      'sent': true,
      'chat': c.title,
      'ref': 'post:${m.chatId}:${m.id}',
    });
  }

  Future<ToolOutput> _saveSticker(Map<String, dynamic> args) async {
    final fileId = _intOrNull(args, 'file_id');
    if (fileId == null) throw ArgumentError('file_id is required');
    await _client.send<td.Stickers>(
      td.AddRecentSticker(
        isAttached: false,
        sticker: td.InputFileId(id: fileId),
      ),
      limited: true,
    );
    return const ToolOutput({'saved': true});
  }

  Future<ToolOutput> _webSearch(Map<String, dynamic> args) async {
    if (!_settings.hasExaKey)
      return const ToolOutput({
        'error': 'Add an Exa web search key in Settings → AI & models first.',
      });
    final q = '${args['query'] ?? ''}'.trim();
    if (q.isEmpty) throw ArgumentError('query is required');
    try {
      final results = await ExaClient(apiKey: _settings.exaKey)
          .search(q, numResults: _int(args, 'limit', fallback: 5, max: 10));
      return ToolOutput({
        'query': q,
        'results': [
          for (final r in results)
            {
              'title': r.title,
              'url': r.url,
              'published_at': ?r.publishedDate,
              'highlights': r.highlights,
            },
        ],
      });
    } on AiException catch (e) {
      return ToolOutput({'error': 'Exa search failed: ${e.message}'});
    }
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _react(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    final emoji = '${args['emoji'] ?? ''}'.trim();
    if (id == null || emoji.isEmpty)
      throw ArgumentError('message_id and emoji are required');
    final type = td.ReactionTypeEmoji(emoji: emoji);
    if (args['remove'] == true) {
      await _client.send<td.Ok>(
        td.RemoveMessageReaction(
          chatId: c.id,
          messageId: id,
          reactionType: type,
        ),
        limited: true,
      );
    } else {
      await _client.send<td.Ok>(
        td.AddMessageReaction(
          chatId: c.id,
          messageId: id,
          reactionType: type,
          isBig: false,
          updateRecentReactions: true,
        ),
        limited: true,
      );
    }
    return ToolOutput({
      'done': true,
      'chat': c.title,
      'reaction': emoji,
      'removed': args['remove'] == true,
    });
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _notifications(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final muted = args['muted'] == true;
    final current =
        c.notifications ??
        (await _client.send<td.Chat>(td.GetChat(chatId: c.id)))
            .notificationSettings;
    await _client.send<td.Ok>(
      td.SetChatNotificationSettings(
        chatId: c.id,
        notificationSettings: current.copyWith(
          useDefaultMuteFor: false,
          muteFor: muted ? 0x7fffffff : 0,
        ),
      ),
      limited: true,
    );
    return ToolOutput({'done': true, 'chat': c.title, 'muted': muted});
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _markRead(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    if (c.lastMessage == null)
      return ToolOutput({
        'done': true,
        'chat': c.title,
        'note': 'Nothing to mark.',
      });
    await markRead(c);
    return ToolOutput({
      'done': true,
      'chat': c.title,
      'was_unread': c.unreadCount,
    });
  }

  /// One page of a forum topic, newest first, from [fromId] (0 = latest).
  /// A search scoped to the topic is what TDLib answers reliably for forum
  /// topics; the thread-history call is the fallback.
  Future<List<td.Message>> topicPage(
    int chatId,
    int topicId, {
    int fromId = 0,
    int limit = 40,
  }) async {
    final chat = _store.chat(chatId);
    if (chat != null && _store.isDirectMessagesGroup(chat)) {
      final r = await _client.send<td.Messages>(
        td.GetDirectMessagesChatTopicHistory(
          chatId: chatId,
          topicId: topicId,
          fromMessageId: fromId,
          offset: 0,
          limit: limit,
        ),
        limited: true,
      );
      return r.messages.whereType<td.Message>().toList();
    }
    if (chat != null && _store.isForum(chat)) {
      final r = await _client.send<td.Messages>(
        td.GetForumTopicHistory(
          chatId: chatId,
          forumTopicId: topicId,
          fromMessageId: fromId,
          offset: 0,
          limit: limit,
        ),
        limited: true,
      );
      return r.messages.whereType<td.Message>().toList();
    }
    {
      final r = await _client.send<td.Messages>(
        td.GetMessageThreadHistory(
          chatId: chatId,
          messageId: topicId,
          fromMessageId: fromId,
          offset: 0,
          limit: limit,
        ),
        limited: true,
      );
      return r.messages.whereType<td.Message>().toList();
    }
  }

  Future<Set<int>?> _folderFilter(Map<String, dynamic> args) async {
    final folderId = _intOrNull(args, 'folder_id');
    if (folderId == null) return null;
    if (_store.folders.every((f) => f.id != folderId)) {
      throw ArgumentError(
        'No folder with id $folderId. Use list_chat_folders.',
      );
    }
    return (await _store.loadFolder(folderId)).toSet();
  }

  Future<ToolOutput> _exploreForum(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    if (!_store.isForum(c))
      throw ArgumentError('${c.title} has no topics; use read_messages.');
    final maxTopics = _int(args, 'max_topics', fallback: 6, max: 10);
    final perTopic = _int(args, 'per_topic', fallback: 4, max: 10);
    final since = _hours(args, 'since_hours');
    final after = since == null
        ? null
        : _unix(
            DateTime.now().subtract(Duration(minutes: (since * 60).round())),
          );
    final unreadOnly = args['unread_only'] == true;
    final r = await _client.send<td.ForumTopics>(
      td.GetForumTopics(
        chatId: c.id,
        query: '',
        offsetDate: 0,
        offsetMessageId: 0,
        offsetForumTopicId: 0,
        limit: 100,
      ),
      limited: true,
    );
    final topics =
        r.topics.where((t) {
          if (unreadOnly && t.unreadCount == 0) return false;
          if (after != null && (t.lastMessage?.date ?? 0) < after) return false;
          return true;
        }).toList()..sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
        });
    final posts = <PostSnapshot>[];
    final out = <Map<String, dynamic>>[];
    for (final t in topics.take(maxTopics)) {
      final list = <Map<String, dynamic>>[];
      try {
        final messages = t.info.isGeneral
            ? (await _history(
                c,
                limit: perTopic * 3,
                after: after,
              )).where((m) => !m.isTopicMessage).take(perTopic)
            : (await _history(
                c,
                limit: perTopic,
                after: after,
                topicId: t.info.messageThreadId,
              ));
        for (final m in messages) {
          final (j, p) = _message(m, c);
          list.add(j);
          posts.add(p);
        }
      } on TelegramException catch (e) {
        if (e.isFloodWait) break;
      }
      out.add({
        'topic_id': t.info.messageThreadId,
        'name': t.info.name,
        if (t.info.isGeneral) 'general': true,
        if (t.isPinned) 'pinned': true,
        if (t.unreadCount > 0) 'unread': t.unreadCount,
        'messages': list,
      });
    }
    return ToolOutput({
      'chat': c.title,
      'topics_total': r.totalCount,
      'topics_matching': topics.length,
      'topics': out,
      if (topics.length > maxTopics)
        'not_read': [
          for (final t in topics.skip(maxTopics).take(30)) t.info.name,
        ],
    }, posts: posts);
  }

  Future<ToolOutput> _reactions(Map<String, dynamic> args) async {
    final chatId = _intOrNull(args, 'chat_id');
    final id = _intOrNull(args, 'message_id');
    if (chatId == null || id == null)
      throw ArgumentError('chat_id and message_id are required');
    final m = await _client.send<td.Message>(
      td.GetMessage(chatId: chatId, messageId: id),
      limited: true,
    );
    String emojiOf(td.ReactionType t) => switch (t) {
      td.ReactionTypeEmoji(:final emoji) => emoji,
      td.ReactionTypePaid() => '⭐',
      _ => 'custom emoji',
    };
    final counts = [
      for (final r
          in m.interactionInfo?.reactions?.reactions ??
              const <td.MessageReaction>[])
        {
          'reaction': emojiOf(r.type),
          'count': r.totalCount,
          if (r.isChosen) 'you': true,
        },
    ];
    final who = <Map<String, dynamic>>[];
    String? note;
    try {
      final r = await _client.send<td.AddedReactions>(
        td.GetMessageAddedReactions(
          chatId: chatId,
          messageId: id,
          offset: '',
          limit: 100,
        ),
        limited: true,
      );
      for (final a in r.reactions) {
        who.add({
          'name': a.isOutgoing ? 'You' : _store.senderName(a.senderId),
          'reaction': emojiOf(a.type),
          'date': _iso(a.date),
        });
      }
    } on TelegramException {
      note = 'Telegram only shows counts here, not who reacted.';
    }
    final paid =
        m.interactionInfo?.reactions?.paidReactors ?? const <td.PaidReactor>[];
    return ToolOutput({
      'ref': 'post:$chatId:$id',
      'reactions': counts,
      if (who.isNotEmpty) 'reacted_by': who,
      if (paid.isNotEmpty)
        'star_supporters': [
          for (final p in paid)
            '${p.isMe ? 'You' : (p.isAnonymous || p.senderId == null ? 'Anonymous' : _store.senderName(p.senderId!))}: ${p.starCount} ⭐',
        ],
      'note': ?note,
    });
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _comment(Map<String, dynamic> args) async {
    final channel = _requireChat(args);
    final postId = _intOrNull(args, 'message_id');
    if (postId == null) throw ArgumentError('message_id is required');
    final info = await _client.send<td.MessageThreadInfo>(
      td.GetMessageThread(chatId: channel.id, messageId: postId),
      limited: true,
    );
    final files = [
      for (final f in (args['files'] as List? ?? const []))
        if (File('$f').existsSync()) '$f',
    ];
    final sent = await sendToChat(
      chatId: info.chatId,
      threadId: info.messageThreadId,
      text: '${args['text'] ?? ''}',
      files: files,
      replyToMessageId:
          _intOrNull(args, 'reply_to_message_id') ?? info.messageThreadId,
    );
    final group = _store.chat(info.chatId);
    return ToolOutput(
      {
        'sent': true,
        'chat': 'comments on ${channel.title}',
        'messages': sent.length,
        if (sent.isNotEmpty)
          'ref': 'post:${sent.first.chatId}:${sent.first.id}',
      },
      posts: [for (final m in sent) _message(m, group).$2],
    );
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _reply(Map<String, dynamic> args) async {
    final origin = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    if (id == null) throw ArgumentError('message_id is required');
    final target = _intOrNull(args, 'send_in_chat_id') ?? origin.id;
    final dest = _store.chat(target);
    if (dest == null) throw ArgumentError('No chat with id $target.');
    final original = await _client.send<td.Message>(
      td.GetMessage(chatId: origin.id, messageId: id),
      limited: true,
    );
    // Telegram only takes a quote that is really in the message, with its
    // formatting; buildQuote cuts it from the message itself.
    String? note;
    td.InputTextQuote? quote;
    final wanted = '${args['quote'] ?? ''}'.trim();
    if (wanted.isNotEmpty) {
      final g = gistOf(original.content);
      quote = buildQuote(
        g.formatted ?? td.FormattedText(text: g.text, entities: const []),
        wanted,
      );
      if (quote == null) {
        note = "The quote isn't in the message, so the reply went without it. Copy the excerpt from the message's text.";
      }
    }
    final files = [
      for (final f in (args['files'] as List? ?? const []))
        if (File('$f').existsSync()) '$f',
    ];
    Future<List<td.Message>> send(td.InputTextQuote? q) => sendToChat(
      chatId: target,
      text: '${args['text'] ?? ''}',
      files: files,
      asFiles: args['send_as'] == 'file',
      replyToMessageId: id,
      replyInChatId: origin.id,
      quote: q,
      threadId: original.chatId == target && original.isTopicMessage
          ? original.messageThreadId
          : 0,
    );
    List<td.Message> sent;
    try {
      sent = await send(quote);
    } on TelegramException catch (e) {
      // Telegram still refused the quote (it checks things it doesn't
      // explain): the reply matters more, so it goes without.
      if (quote == null || !e.message.toUpperCase().contains('QUOTE')) rethrow;
      note =
          'Telegram refused the quote (${e.message}), so the reply went without it.';
      quote = null;
      sent = await send(null);
    }
    return ToolOutput(
      {
        'sent': true,
        'chat': dest.title,
        'reply_to': 'post:${origin.id}:$id',
        if (quote != null) 'quoted': quote.text.text,
        'note': ?note,
        if (sent.isNotEmpty)
          'ref': 'post:${sent.first.chatId}:${sent.first.id}',
      },
      posts: [for (final m in sent) _message(m, dest).$2],
    );
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _pin(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    if (id == null) throw ArgumentError('message_id is required');
    final unpin = args['unpin'] == true;
    if (unpin) {
      await _client.send<td.Ok>(
        td.UnpinChatMessage(chatId: c.id, messageId: id),
        limited: true,
      );
    } else {
      await _client.send<td.Ok>(
        td.PinChatMessage(
          chatId: c.id,
          messageId: id,
          disableNotification: args['notify'] != true,
          onlyForSelf:
              args['only_for_me'] == true && c.type is td.ChatTypePrivate,
        ),
        limited: true,
      );
    }
    return ToolOutput({
      'done': true,
      'chat': c.title,
      unpin ? 'unpinned' : 'pinned': 'post:${c.id}:$id',
    });
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _archive(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final archive = args['archived'] != false;
    await _client.send<td.Ok>(
      td.AddChatToList(
        chatId: c.id,
        chatList: archive
            ? const td.ChatListArchive()
            : const td.ChatListMain(),
      ),
      limited: true,
    );
    return ToolOutput({'done': true, 'chat': c.title, 'archived': archive});
  }

  /// When a scheduled message should go, from send_at or in_minutes.
  static DateTime? _when(Map<String, dynamic> args) {
    final minutes = _intOrNull(args, 'in_minutes');
    if (minutes != null) return DateTime.now().add(Duration(minutes: minutes));
    final at = DateTime.tryParse('${args['send_at'] ?? ''}');
    return at;
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _edit(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    final newText = args['text'] == null ? null : '${args['text']}'.trim();
    final file = [
      for (final f in (args['files'] as List? ?? const []))
        if (File('$f').existsSync()) '$f',
    ].firstOrNull;
    if (id == null) throw ArgumentError('message_id is required');
    if (file == null && (newText == null || newText.isEmpty)) {
      throw ArgumentError(
        (args['files'] as List? ?? const []).isNotEmpty
            ? 'That file isn\'t in this conversation. list_attachments shows what there is.'
            : 'Give the new text, or a file to replace the media with.',
      );
    }
    final m = await _client.send<td.Message>(
      td.GetMessage(chatId: c.id, messageId: id),
      limited: true,
    );
    final current = gistOf(m.content);
    final caption = newText == null
        ? (current.formatted ??
              td.FormattedText(text: current.text, entities: const []))
        : await formatText(newText);
    final td.Message edited;
    if (file != null) {
      try {
        edited = await _client.send<td.Message>(
          td.EditMessageMedia(
            chatId: c.id,
            messageId: id,
            inputMessageContent: _mediaContent(
              file,
              caption,
              asFile: args['send_as'] == 'file',
            ),
          ),
          limited: true,
          timeout: const Duration(minutes: 3),
        );
      } on TelegramException catch (e) {
        if (m.content is! td.MessageText || e.isFloodWait) rethrow;
        throw ArgumentError(
          'Telegram won\'t add media to this message because it was sent as text (${e.message}). Offer to send a new '
          'message with the file instead, or to delete this one and send it again with the file.',
        );
      }
    } else if (m.content is td.MessageText) {
      edited = await _client.send<td.Message>(
        td.EditMessageText(
          chatId: c.id,
          messageId: id,
          inputMessageContent: td.InputMessageText(
            text: caption,
            linkPreviewOptions: null,
            clearDraft: false,
          ),
        ),
        limited: true,
      );
    } else {
      edited = await _client.send<td.Message>(
        td.EditMessageCaption(
          chatId: c.id,
          messageId: id,
          caption: caption,
          showCaptionAboveMedia: false,
        ),
        limited: true,
      );
    }
    return ToolOutput({
      'done': true,
      'edited': true,
      'chat': c.title,
      if (file != null) 'media_replaced': file.split(RegExp(r'[\\/]')).last,
      'ref': 'post:${c.id}:${edited.id}',
    });
  }

  /// A local file as message content of the kind its type calls for, or a
  /// document when [asFile].
  td.InputMessageContent _mediaContent(
    String f,
    td.FormattedText? caption, {
    bool asFile = false,
  }) {
    if (caption != null && caption.text.isEmpty) caption = null;
    if (asFile)
      return td.InputMessageDocument(
        document: inputDocument(f, keepAsFile: true),
        caption: caption,
      );
    if (_isGif(f)) {
      return td.InputMessageAnimation(
        animation: inputAnimation(f),
        caption: caption,
        showCaptionAboveMedia: false,
        hasSpoiler: false,
      );
    }
    if (_isPhoto(f)) {
      return td.InputMessagePhoto(
        photo: inputPhoto(f),
        caption: caption,
        showCaptionAboveMedia: false,
        selfDestructType: null,
        hasSpoiler: false,
      );
    }
    if (_isVideo(f)) {
      return td.InputMessageVideo(
        video: inputVideo(f),
        caption: caption,
        showCaptionAboveMedia: false,
        selfDestructType: null,
        hasSpoiler: false,
      );
    }
    if (RegExp(
      r'\.(mp3|m4a|flac|wav|ogg|opus|aac)$',
      caseSensitive: false,
    ).hasMatch(f)) {
      return td.InputMessageAudio(audio: inputAudio(f), caption: caption);
    }
    return td.InputMessageDocument(
      document: inputDocument(f),
      caption: caption,
    );
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _schedule(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final at = _when(args);
    if (at == null ||
        at.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
      throw ArgumentError('Give a future send_at (local time) or in_minutes.');
    }
    final files = [
      for (final f in (args['files'] as List? ?? const []))
        if (File('$f').existsSync()) '$f',
    ];
    final sent = await sendToChat(
      chatId: c.id,
      text: '${args['text'] ?? ''}',
      files: files,
      sendAt: at,
    );
    return ToolOutput({
      'scheduled': true,
      'chat': c.title,
      'send_at': at.toIso8601String().substring(0, 16),
      'messages': [for (final m in sent) m.id],
    });
  }

  Future<ToolOutput> _scheduled(Map<String, dynamic> args) async {
    final chatId = _intOrNull(args, 'chat_id');
    final chats = chatId != null
        ? [_requireChat(args)]
        : _sortedChats().where(_store.canPost).take(25).toList();
    final out = <Map<String, dynamic>>[];
    for (final c in chats) {
      final r = await _client.send<td.Messages>(
        td.GetChatScheduledMessages(chatId: c.id),
        limited: true,
      );
      for (final m in r.messages.whereType<td.Message>()) {
        final g = gistOf(m.content);
        final when = switch (m.schedulingState) {
          td.MessageSchedulingStateSendAtDate(:final sendDate) => _iso(
            sendDate,
          ),
          td.MessageSchedulingStateSendWhenOnline() => 'when they come online',
          _ => 'scheduled',
        };
        out.add({
          'chat_id': c.id,
          'chat': c.title,
          'message_id': m.id,
          'send_at': when,
          if (g.kind != 'text') 'media': g.kind,
          'text': _clip(g.text.isNotEmpty ? g.text : (g.detail ?? '')),
        });
      }
    }
    return ToolOutput({
      'count': out.length,
      'scheduled': out,
      if (chatId == null)
        'note':
            'Checked the ${chats.length} most recent chats you can write in.',
    });
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _reschedule(Map<String, dynamic> args) async {
    final c = _requireChat(args);
    final id = _intOrNull(args, 'message_id');
    if (id == null) throw ArgumentError('message_id is required');
    final now = args['send_now'] == true;
    final at = now ? null : _when(args);
    if (!now && at == null)
      throw ArgumentError('Give send_at, in_minutes or send_now.');
    await _client.send<td.Ok>(
      td.EditMessageSchedulingState(
        chatId: c.id,
        messageId: id,
        schedulingState: at == null
            ? null
            : td.MessageSchedulingStateSendAtDate(
                sendDate: at.millisecondsSinceEpoch ~/ 1000,
                repeatPeriod: 0,
              ),
      ),
      limited: true,
    );
    return ToolOutput({
      'done': true,
      'chat': c.title,
      if (now)
        'sent_now': true
      else
        'send_at': at!.toIso8601String().substring(0, 16),
    });
  }

  /// A short line for the approval card: what an action other than a
  /// message would do.
  String describeAction(String name, Map<String, dynamic> args) {
    final id = _intOrNull(args, 'chat_id');
    final title = id == null
        ? 'a chat'
        : (_store.chat(id)?.title ?? 'chat $id');
    return switch (name) {
      'react_to_message' =>
        args['remove'] == true
            ? 'Remove your ${args['emoji']} reaction from message ${args['message_id']} in $title'
            : 'React ${args['emoji']} to message ${args['message_id']} in $title',
      'set_chat_notifications' =>
        args['muted'] == true ? 'Mute $title' : 'Unmute $title',
      'mark_as_read' => 'Mark everything in $title as read',
      'pin_message' =>
        args['unpin'] == true
            ? 'Unpin message ${args['message_id']} in $title'
            : 'Pin message ${args['message_id']} in $title${args['notify'] == true ? ' and notify members' : ' silently'}',
      'archive_chat' =>
        args['archived'] == false
            ? 'Move $title out of the Archive'
            : 'Move $title to the Archive',
      'edit_message' => [
        'Edit message ${args['message_id']} in $title',
        if ((args['files'] as List? ?? const []).isNotEmpty)
          'Replace its media with ${'${(args['files'] as List).first}'.split(RegExp(r'[\\/]')).last}'
              '${args['send_as'] == 'file' ? ' (as a file)' : ''}',
        if (args['text'] != null) 'New text:\n“${args['text']}”',
      ].join('\n'),
      'reschedule_message' =>
        args['send_now'] == true
            ? 'Send scheduled message ${args['message_id']} in $title now'
            : 'Move scheduled message ${args['message_id']} in $title to ${_when(args)?.toIso8601String().substring(0, 16).replaceFirst('T', ' ') ?? '?'}',
      _ => _describeExtra(name, args, title) ?? name,
    };
  }

  /// Where a forward goes: to_chat_id and/or to_chat_ids.
  static List<int> forwardTargets(Map<String, dynamic> args) => {
    if (_intOrNull(args, 'to_chat_id') case final id?) id,
    for (final v in (args['to_chat_ids'] as List? ?? const []))
      if (v is num) v.toInt() else if (int.tryParse('$v') case final n?) n,
  }.toList();

  /// Forwards [ids] from [from] to [to]; returns how many arrived.
  Future<int> forwardTo(
    int to,
    int from,
    List<int> ids, {
    bool hideSender = false,
    bool removeCaption = false,
  }) async {
    final r = await _client.send<td.Messages>(
      td.ForwardMessages(
        chatId: to,
        topicId: null,
        fromChatId: from,
        messageIds: ids,
        options: null,
        sendCopy: hideSender || removeCaption,
        removeCaption: removeCaption,
      ),
      limited: true,
    );
    return r.messages.length;
  }

  /// A short line for the approval card: where the message would go.
  String describeTarget(Map<String, dynamic> args, {String? tool}) {
    if (tool == 'forward_message') {
      final names = [
        for (final id in forwardTargets(args))
          _store.chat(id)?.title ?? 'chat $id',
      ];
      return names.isEmpty ? 'Unknown chat' : names.join(', ');
    }
    if (tool == 'reply_to_message') {
      final from = _store.chat(_intOrNull(args, 'chat_id') ?? 0);
      final to = _store.chat(
        _intOrNull(args, 'send_in_chat_id') ?? from?.id ?? 0,
      );
      final quote = '${args['quote'] ?? ''}'.trim();
      return [
        to?.title ?? 'a chat',
        if (to?.id != from?.id)
          'replying to a message from ${from?.title ?? 'another chat'}'
        else
          'replying to message ${args['message_id']}',
        if (quote.isNotEmpty)
          'quoting “${quote.length > 80 ? '${quote.substring(0, 80)}…' : quote}”',
      ].join(' · ');
    }
    if (tool == 'schedule_message') {
      final ch = _store.chat(_intOrNull(args, 'chat_id') ?? 0);
      final at = _when(args);
      return '${ch?.title ?? 'a chat'} · scheduled for ${at == null ? '?' : at.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}';
    }
    if (tool == 'comment_on_post') {
      final ch = _store.chat(_intOrNull(args, 'chat_id') ?? 0);
      final reply = _intOrNull(args, 'reply_to_message_id');
      return 'Comments on ${ch?.title ?? 'a channel'} post ${args['message_id']}${reply == null ? '' : ', replying to comment $reply'}';
    }
    final id = _intOrNull(args, 'chat_id') ?? _intOrNull(args, 'to_chat_id');
    final c = id == null ? null : _store.chat(id);
    if (c == null) return 'Unknown chat';
    return '${c.title} · ${_store.kindOf(c).name}';
  }
}

/// Each account's tool runner: the assistant's Telegram tools act on the
/// account whose runner they run in.
final toolRunnerFamily = Provider.family<TelegramToolRunner, String>(
  (ref, accountId) => TelegramToolRunner(
    ref.watch(telegramClientFamily(accountId)),
    ref.watch(telegramStoreFamily(accountId)),
    ref.watch(settingsProvider),
    web: ref.watch(webFetcherProvider),
    browser: ref.watch(aiProvider).browser.session,
    engine: ref.watch(inAppEngineProvider),
    sandbox: ref.watch(aiProvider).deviceSandbox.sandbox,
    composio: ref.read(integrationsProvider.notifier).client,
    e2b: ref.read(e2bSessionProvider),
  ),
);

/// The active account's tool runner.
final toolRunnerProvider = Provider<TelegramToolRunner>(
  (ref) => ref.watch(toolRunnerFamily(ref.watch(activeAccountIdProvider))),
);
