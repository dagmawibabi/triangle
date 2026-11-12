part of 'telegram_tools.dart';

class ToolDocumentation {
  const ToolDocumentation({
    required this.provider,
    required this.location,
    required this.prerequisites,
    required this.effects,
    required this.billing,
    required this.outputs,
    required this.limits,
    required this.cancellation,
    required this.example,
    required this.referenceUrl,
  });
  final String provider,
      location,
      prerequisites,
      effects,
      billing,
      cancellation,
      referenceUrl;
  final List<String> outputs, limits;
  final Map<String, dynamic> example;
}

class ToolReference {
  const ToolReference(this.outputs, {this.limits = const []});
  final List<String> outputs;
  final List<String> limits;
}

ToolDocumentation documentationFor(TelegramTool tool) {
  final app = appToolkitOf(tool.name);
  final provider = app != null
      ? '${appLabel(app)} through Composio'
      : switch (tool.category) {
          ToolCategory.e2b => 'E2B',
          ToolCategory.decisions => 'TypeSafe Jev',
          ToolCategory.mcp => 'Your MCP servers, found in the official MCP Registry',
          ToolCategory.skills => 'Agent Skills from Skyll, skills.sh and GitHub',
          ToolCategory.cloudflare || ToolCategory.r2 => 'Cloudflare',
          ToolCategory.creative =>
            tool.name == 'generate_addis_voice'
                ? 'Addis AI'
                : const {
                    'generate_music',
                    'generate_sound_effect',
                  }.contains(tool.name)
                ? 'ElevenLabs'
                : 'Configured generation model',
          ToolCategory.device => 'Android',
          ToolCategory.papers => 'ScholarXIV Papers API (arXiv, Semantic Scholar, OpenAlex, PubMed and more)',
          ToolCategory.code => 'On-device Python / JavaScript sandbox',
          ToolCategory.apps => 'Composio',
          _ =>
            tool.name == 'web_search'
                ? 'Exa'
                : tool.needsTelegram
                ? 'Telegram / TDLib'
                : tool.cost == ToolCost.web
                ? 'Public web services'
                : 'Triangle',
        };
  final prerequisites = <String>[
    if (tool.needsTelegram) 'A signed-in Telegram account.',
    if (app != null)
      'A Composio key and a connected ${appLabel(app)} account with permission for this action.',
    if (tool.category == ToolCategory.apps)
      'A Composio key; running an action also needs its app connected.',
    if (tool.category == ToolCategory.papers)
      tool.name == 'paper_search' ? 'A ScholarXIV API key (any plan).' : 'A ScholarXIV API key on the Go plan or above.',
    if (tool.category == ToolCategory.device) 'Android. Permission is requested the first time it is needed; some actions also need Android settings access.',
    if (tool.category == ToolCategory.code || tool.name.startsWith('browser_'))
      'Android, iOS or macOS.',
    if (const {
      'web_screenshot',
      'web_inspect',
      'web_run_async_js',
    }.contains(tool.name))
      'Android or iOS.',
    if (tool.category == ToolCategory.e2b)
      'An E2B key. Sandbox internet and persistence follow Apps & web → E2B.',
    if (tool.category == ToolCategory.cloudflare ||
        tool.category == ToolCategory.r2)
      'A Cloudflare token with access to the requested account and resource.',
    if (const {
      'r2_list',
      'r2_download',
      'r2_share_link',
      'r2_upload',
      'r2_delete',
    }.contains(tool.name))
      'R2 access-key ID and secret, and a bucket supplied here or selected as the default.',
    if (tool.name == 'web_search') 'An Exa key in Apps & web.',
    if (tool.category == ToolCategory.decisions) 'A TypeSafe Jev key in AI & models → Decisions, with decisions turned on.',
    if (tool.category == ToolCategory.mcp && !const {'mcp_search', 'mcp_list_servers', 'mcp_is_installed', 'mcp_install', 'mcp_install_catalog'}.contains(tool.name))
      'An installed MCP server (Settings → MCP & Skills) and any key it needs.',
    if (const {'load_skill', 'read_skill_file', 'uninstall_skill'}.contains(tool.name)) 'An installed skill (Settings → MCP & Skills).',
    if (tool.category == ToolCategory.creative)
      tool.name == 'generate_addis_voice'
          ? 'An Addis AI key and a voice for the requested language.'
          : const {
              'generate_music',
              'generate_sound_effect',
            }.contains(tool.name)
          ? 'An ElevenLabs key and access to the requested generation service.'
          : 'A configured image or speech generation model and its provider key in AI & models.',
    if (tool.name == 'view_image') 'A chat model with image input. Local files/URLs do not need Telegram; Telegram message refs do.',
    if (tool.name == 'canvas_add')
      'Telegram message refs or IDs available to the signed-in account.',
    if (tool.name == 'online_alert' || tool.name == 'list_online_alerts')
      'The other person must allow this account to see their online status.',
  ];
  final ref =
      toolReferences[tool.name] ??
      const ToolReference(['Operation-specific result data.']);
  final cancellable =
      tool.name == 'run_code' ||
      tool.name.startsWith('browser_') ||
      const {
        'web_screenshot',
        'web_inspect',
        'web_run_async_js',
        'generate_music',
        'generate_sound_effect',
        'e2b_run_code',
        'e2b_run_command',
      }.contains(tool.name);
  final limits = <String>[
    ...ref.limits,
    if (tool.name == 'view_story') 'Without peek, viewing another person’s story marks it seen. This mixed tool is in Modify.',
    if (const {
      'bot_api',
      'device_volume',
      'join_chat',
      'share_folder',
    }.contains(tool.name))
      'This tool has both read and modify variants. It is in Modify and is unavailable in read-only mode.',
    if (tool.category == ToolCategory.code) 'Runs in a sandbox. First use downloads the runtime; Python dependencies are loaded from imports.',
    if (app != null) 'App responses are currently summarized: large lists/text may be reduced. A displayed result is not necessarily the full upstream response.',
    if (tool.name == 'generate_audio') 'Uses the same voice engine, model and voice as read-aloud.',
    if (tool.name == 'gmail_send_email') 'This built-in action has no attachment input. Find a suitable app action when attachments are required.',
    if (tool.name == 'googledrive_add_file_sharing_preference') 'This legacy schema does not expose role or type. Find the current Drive permission action for those controls.',
    if (tool.name == 'cloudflare_update_dns_record') 'This input schema does not expose DNS priority. Use the generic Cloudflare request for that field.',
    if (tool.name == 'data_usage') 'reset: true is not implemented by this tool. Reset counters from the app settings.',
    if (tool.description.toLowerCase().contains('deprecated')) 'Deprecated provider action. Find its documented replacement through find_app_tools before relying on it.',
    if (tool.modifiesData) 'A multi-step action may partly finish before an error. Check completed changes before retrying.',
  ];
  return ToolDocumentation(
    provider: provider,
    location: switch (tool.cost) {
      ToolCost.local =>
        'Local Telegram cache; initial cache loading may contact Telegram.',
      ToolCost.device =>
        'On this device${tool.needsTelegram ? ', with Telegram requests where required' : ''}.',
      ToolCost.telegram => 'Telegram servers through this device.',
      ToolCost.apps => 'Connected account through Composio.',
      ToolCost.cloud => 'Your cloud account.',
      _ => 'Network service accessed from this device.',
    },
    prerequisites: prerequisites.isEmpty
        ? 'No additional account or key; the input must be accessible to the app.'
        : prerequisites.join(' '),
    effects:
        '${tool.access.description}${tool.access == ToolAccess.read ? ' Temporary caches may be refreshed.' : ' Blocked in read-only mode.'}',
    billing: tool.name == 'web_search'
        ? 'Exa usage counts against your Exa account.'
        : tool.cost == ToolCost.ai
        ? 'Billed by the selected provider. Pricing and access depend on your plan; this tool may not report an exact cost.'
        : tool.cost == ToolCost.cloud || tool.cost == ToolCost.apps
        ? tool.cost.explanation
        : tool.alwaysAsk
        ? 'May spend Stars or incur a carrier charge; always asks first.'
        : 'No separate AI generation charge from this tool. Chat-model usage, network/carrier costs or third-party service charges may still apply.',
    outputs: ref.outputs,
    limits: limits,
    cancellation: cancellable
        ? 'Stop requests cancellation. Work already accepted by a site or service may still complete.'
        : 'Stop stops waiting for the result. The underlying request may still complete; check before retrying.',
    example: _toolExample(tool.parameters),
    referenceUrl: app != null
        ? 'https://docs.composio.dev/toolkits/$app'
        : tool.category == ToolCategory.e2b
        ? 'https://e2b.dev/docs'
        : tool.category == ToolCategory.decisions
        ? 'https://docs.typesafe.ai/api'
        : tool.category == ToolCategory.mcp
        ? 'https://modelcontextprotocol.io'
        : tool.category == ToolCategory.skills
        ? 'https://skills.sh'
        : tool.category == ToolCategory.cloudflare ||
              tool.category == ToolCategory.r2
        ? 'https://developers.cloudflare.com/'
        : tool.category == ToolCategory.creative &&
              const {
                'generate_music',
                'generate_sound_effect',
              }.contains(tool.name)
        ? 'https://elevenlabs.io/docs'
        : tool.needsTelegram
        ? 'https://core.telegram.org/tdlib/docs/'
        : 'https://github.com/dagmawibabi/triangle',
  );
}

final _parameterCache = Expando<Map<String, dynamic>>();
Map<String, dynamic> documentedParameters(TelegramTool tool) =>
    _parameterCache[tool] ??= {
      ...tool._parameters,
      'properties': {
        for (final entry
            in ((tool._parameters['properties'] as Map?) ?? const {}).entries)
          '${entry.key}': {
            ...Map<String, dynamic>.from(entry.value as Map),
            if ((entry.value as Map)['description'] == null ||
                '${(entry.value as Map)['description']}'.trim().isEmpty)
              'description': parameterDescription(tool.name, '${entry.key}'),
          },
      },
    };

Map<String, dynamic> _toolExample(Map<String, dynamic> schema) {
  Object? sample(Map s, String name) {
    if (s.containsKey('default')) return s['default'];
    if (s['enum'] case final List values when values.isNotEmpty)
      return values.first;
    return switch (s['type']) {
      'integer' || 'number' =>
        s['minimum'] ??
            (s['exclusiveMinimum'] is num
                ? (s['exclusiveMinimum'] as num) + 1
                : 1),
      'boolean' => true,
      'array' => [sample((s['items'] as Map?) ?? const {}, name)],
      'object' => _toolExample(Map<String, dynamic>.from(s)),
      _ =>
        name.endsWith('_id')
            ? '<${name.replaceAll('_', ' ')}>'
            : '<${name.replaceAll('_', ' ')}>',
    };
  }

  final props = (schema['properties'] as Map?) ?? const {};
  return {
    for (final key in (schema['required'] as List? ?? const []))
      '$key': sample((props[key] as Map?) ?? const {}, '$key'),
  };
}

String parameterDescription(String tool, String key) =>
    _parameterOverrides['$tool.$key'] ??
    _parameterHelp[key] ??
    'See the operation description for ${key.replaceAll('_', ' ')}.';

const _parameterOverrides = <String, String>{
  'set_alarm.days': 'Repeat weekdays: 1 Sunday through 7 Saturday. Omit for a one-time alarm.',
  'ban_member.days': 'Ban duration in days, up to 366. Zero or omitted bans forever.',
  'restrict_member.days':
      'Restriction duration in days; zero keeps it until manually lifted.',
  'recently_joined_chats.days': 'Look-back window in days; defaults to 30.',
  'set_chat_settings.auto_delete': 'Auto-delete interval in seconds. Zero disables it; other values must be supported by Telegram.',
  'set_chat_settings.slow_mode':
      'Minimum seconds between messages: 0, 10, 30, 60, 300, 900 or 3600.',
  'vote_poll.options':
      'Zero-based option indexes to vote for. An empty list retracts the vote.',
  'create_poll.options': 'Poll answer text, between 2 and 10 options.',
  'cloudflare_update_dns_record.content':
      'DNS record value, such as an IPv4 address or target hostname.',
  'cloudflare_kv.key':
      'KV key name when namespace_id is provided. Omit to list keys.',
  'set_chat_reactions.mode':
      'Reaction availability: all, some or none. some also requires emojis.',
  'create_watch.mode': 'notify sends a notification; summarize writes a summary; act follows the instructions using enabled tools.',
  'update_watch.mode': 'New watch behavior: notify, summarize or act. Omitted fields retain their current value.',
  'send_chat_action.action': 'Telegram activity indicator to show, such as typing or uploading a photo.',
  'manage_video_chat.action':
      'Group-call operation to perform; choose a value from the allowed list.',
  'data_usage.reset': 'Reset is not supported here. Leave false and reset counters through the app settings.',
  'github_list.ref':
      'Branch, tag or commit. Omit to use the repository default branch.',
  'get_stories.archived':
      'Include archived stories where the account has access.',
  'set_private_note.note':
      'Private Telegram contact note. Empty text clears the existing note.',
  'canvas_add.note': 'Optional explanation of why these posts are being saved.',
  'edit_chat_info.file':
      'An accessible image path or attachment name for the chat photo.',
  'set_member_tag.user_id': 'Member user ID from list_members or get_member.',
};

const _parameterHelp = <String, String>{
  'action': 'The operation to perform; choose from the allowed values.',
  'active_hours': 'Story lifetime in hours; Telegram Premium may be required for non-default lifetimes.',
  'add_chat_ids': 'Telegram chat IDs to add, obtained from list_chats.',
  'aggressive_antispam':
      'Enable or disable Telegram’s aggressive anti-spam mode for this group.',
  'album_id': 'Album ID returned by music_search.',
  'all': 'Apply to all items in the specified collection rather than one item.',
  'all_others': 'Log out every session except the current device.',
  'always_user_ids':
      'User IDs explicitly allowed as exceptions to the privacy audience.',
  'append': 'Append to the field instead of replacing its existing text.',
  'approve': 'True accepts the request; false declines it.',
  'archived': 'Include archived items or select archive behavior as described by this operation.',
  'artist_id': 'Artist ID from music_search.',
  'asset_url': 'Download URL of the release asset returned by github_releases.',
  'at': 'Local date and time in ISO format, for example 2026-11-01T18:30.',
  'audience': 'Privacy audience: everybody, contacts or nobody; explicit user exceptions apply separately.',
  'author': 'Author name used to narrow the book search.',
  'auto_delete': 'Auto-delete interval in seconds; zero disables it.',
  'background_id': 'Telegram background ID returned by list_backgrounds.',
  'bio': 'New profile biography. Empty text clears it; Telegram length limits apply.',
  'birthday': 'Birthday as YYYY-MM-DD or MM-DD. Empty text removes it.',
  'blur': 'Whether to blur the selected wallpaper.',
  'body': 'Full body text of the notification or request.',
  'body_json':
      'JSON request body encoded as a string. It must contain valid JSON.',
  'book_id': 'Source-prefixed book ID from search_books or find_free_copy.',
  'bot_user_id': 'Telegram user ID of the bot. Connected Bot API operations require its token stored by connect_bot.',
  'box': 'SMS collection to read: inbox, sent or all.',
  'brief_id': 'Brief ID from list_briefs, or latest for the most recent brief.',
  'can_accept_calls':
      'Whether the selected logged-in session may receive calls.',
  'caption': 'Caption text to accompany the selected media.',
  'channel': 'YouTube channel handle, channel ID or channel URL.',
  'channels_only': 'Limit the search to channel messages.',
  'chat_id': 'Telegram chat ID, including its sign, from list_chats, get_chat_info or a message ref.',
  'chat_ids': 'Telegram chat IDs from list_chats. An empty list has operation-specific meaning; see the description.',
  'check_only': 'Preview an invite link without joining the chat.',
  'closed': 'True closes the forum topic; false reopens it.',
  'code': 'Complete code to execute in the selected sandbox language.',
  'color': 'Solid background color in hexadecimal form, for example #1E2A3A.',
  'colors': 'Hexadecimal background colors; multiple colors create a gradient.',
  'column': 'Zero-based button column from get_bot_buttons.',
  'command': 'Shell command to execute in the E2B sandbox.',
  'comment': 'Human-readable comment attached to the DNS record.',
  'content': 'Complete text to remember or replace an existing memory with.',
  'country':
      'Two-letter country code used by the music catalog, for example us.',
  'cron': 'Five-field schedule in local time: minute hour day-of-month month day-of-week.',
  'daily_at': 'Daily local trigger time in HH:MM format.',
  'days': 'Duration or look-back window measured in days; see the tool’s specific rules.',
  'delete_messages': 'Also delete the member’s messages when banning them.',
  'demote': 'Remove administrator status instead of promoting the member.',
  'description':
      'Complete description text. Where supported, an empty string clears it.',
  'dialer_only': 'Open the dialer with the number instead of placing the call immediately.',
  'direction':
      'Restrict transactions to the specified incoming or outgoing direction.',
  'disconnect': 'Forget the stored bot connection instead of connecting it.',
  'discussion_chat_id': 'Discussion-group chat ID for channel comments; zero unlinks the current group.',
  'element': 'Element number from the most recent browser_open or browser_read. Read again if the page changed.',
  'emoji': 'Unicode emoji for the sticker or reaction; empty removes a story reaction where supported.',
  'emojis': 'Unicode emoji strings used to search stickers or configure allowed reactions.',
  'enabled':
      'Turn this feature on or off without deleting its saved configuration.',
  'every_minutes': 'Polling or repeating interval in minutes. Platform/background requirements still apply.',
  'except_chat_ids':
      'Chat IDs whose cached files must be preserved during cleanup.',
  'exclude_archived': 'Exclude chats in the Telegram archive.',
  'exclude_chat_ids': 'Chat IDs explicitly excluded from the folder.',
  'exclude_muted': 'Exclude chats with muted notifications.',
  'exclude_read': 'Exclude chats with no unread messages.',
  'expires_hours': 'Invite-link lifetime in hours; omit or use zero for no expiry where allowed.',
  'file':
      'Accessible local file path or attachment name from list_attachments.',
  'file_id': 'Telegram file ID returned by the relevant sticker or profile-music listing.',
  'files': 'Attachment names or accessible local paths. Use list_attachments to find files in this conversation.',
  'filter': 'Member subset to return; use an allowed value and query when searching by name.',
  'find': 'Return matching text with context rather than the next complete text window.',
  'first_name': 'Contact or profile first name.',
  'folder': 'Canvas folder ID, name or path from canvas_overview.',
  'folder_id': 'Telegram folder ID from list_chat_folders or get_folder.',
  'folder_ids': 'All Telegram folder IDs in the desired first-to-last order.',
  'follow':
      'Maximum number of parent replies to follow; default one, at most ten.',
  'for_everyone': 'Also delete for the other participants where Telegram and the account’s rights allow it.',
  'format':
      'Requested export/download format; the source must offer that format.',
  'free_only':
      'Keep only books for which the sources indicate a free reading copy.',
  'from_chat_id': 'Source Telegram chat ID of the messages being forwarded.',
  'gif_id': 'GIF identifier from search_gifs or list_saved_gifs, including its file: or inline: prefix.',
  'headers': 'HTTP header name/value pairs for this request.',
  'height': 'Media height in pixels.',
  'hide_members': 'Hide the member list where Telegram permits this setting.',
  'hide_via_bot': 'Hide the inline-bot attribution where Telegram permits it.',
  'history_for_new_members':
      'Whether new members can read earlier group history.',
  'hours': 'Signed-link lifetime in hours; default one, maximum 168.',
  'icon': 'Telegram folder icon name from the allowed names in the tool description.',
  'in_minutes': 'Minutes from now until the scheduled time; may be fractional where supported.',
  'inactive_days': 'Session inactivity timeout in days: 7, 30, 90, 180 or 365.',
  'include_muted': 'Include chats with muted notifications.',
  'include_system':
      'Include Android system applications in the installed-app list.',
  'include_types': 'Chat types automatically included in the Telegram folder.',
  'instructions': 'Full instructions the watch follows when it triggers.',
  'invite_link': 'Exact Telegram invite link returned by list_invite_links.',
  'item_ids': 'Canvas item IDs returned by canvas_overview.',
  'join_by_request':
      'Whether joining requires an administrator to approve the request.',
  'join_to_send': 'Whether a person must join the discussion group before sending messages.',
  'keep_mb': 'Target cached-storage size in megabytes for cleanup.',
  'keep_on_profile':
      'Keep the story visible on the profile after its active period expires.',
  'key': 'Exact KV key or R2 object key, including any prefix; keys are case-sensitive.',
  'keys': 'Exact R2 object keys to delete, including prefixes.',
  'kick_only': 'Remove the member but allow them to rejoin later.',
  'kind': 'Kind of content to save or retrieve; choose from allowed values.',
  'kinds':
      'Cached media kinds eligible for cleanup; other kinds are preserved.',
  'label': 'Label shown by the phone’s Clock app for this alarm or timer.',
  'language': 'Sandbox language; use a supported language name such as python or javascript.',
  'last_name': 'Contact or profile last name; may be empty.',
  'lift': 'Remove existing member restrictions instead of applying new ones.',
  'limit': 'Maximum results to return. The tool may enforce a smaller service-specific cap.',
  'link': 'Telegram public or invite link to inspect or join.',
  'list': 'List existing folder invite links instead of creating a new link.',
  'markdown': 'Complete rich-message Markdown using the supported syntax described above.',
  'max_chars': 'Maximum characters in this returned text window; use offset for continuation.',
  'member_limit':
      'Maximum invite-link uses; zero means no configured limit where allowed.',
  'memory_id': 'Saved memory ID returned by list_memories or remember.',
  'message_id': 'Telegram message ID within chat_id, from a returned post ref or message list.',
  'message_ids': 'Telegram message IDs belonging to the specified source chat.',
  'messages': 'Ordered BotFather command and answer strings. Commands run sequentially.',
  'method':
      'Exact API method name or HTTP method accepted by the target service.',
  'minute': 'Minute of the hour, from 0 through 59.',
  'mode': 'Mode to apply; choose an allowed value and supply any corresponding required fields.',
  'move_items_to': 'Destination Canvas folder for items preserved when deleting the source folder.',
  'movie_id':
      'Wikidata movie identifier returned by movie_search, for example Q25188.',
  'multiple_answers': 'Allow a voter to select more than one poll option.',
  'mute': 'Mute the selected audio stream.',
  'muted': 'True mutes chat notifications; false unmutes them.',
  'name': 'Human-readable name for the item being created or updated.',
  'namespace_id': 'Cloudflare KV namespace ID from cloudflare_kv.',
  'never_user_ids':
      'User IDs explicitly excluded as exceptions to the privacy audience.',
  'next_offset':
      'Continuation token from the previous result, passed back unchanged.',
  'note': 'Full note text to save with this item.',
  'number': 'Phone number to call, preferably in international format.',
  'offset': 'Continuation position. Numeric text offsets are character counts; service tokens must be passed unchanged.',
  'older_than_days': 'Only remove cached files older than this many days.',
  'on': 'Turn the device feature on or off; omit only when the tool supports toggling.',
  'only_expiring': 'Return only Stars subscriptions approaching expiry.',
  'only_for_me': 'Apply the background only to this account rather than both sides of a private chat.',
  'only_missed': 'Restrict the Telegram call history to missed calls.',
  'options': 'Poll answer text or zero-based answer indexes, according to the operation.',
  'package': 'Android package identifier from installed_apps, for example com.spotify.music.',
  'page': 'Android settings page to open; choose an allowed value.',
  'parameter': 'Optional bot start parameter from its deep link.',
  'params': 'JSON object containing the selected Bot API method’s arguments.',
  'parent': 'Parent Canvas folder ID/name/path. An empty parent moves a folder to the top level.',
  'path': 'Exact file or directory path in the repository or sandbox named by this tool.',
  'performer': 'Performer name to store with the profile audio.',
  'personal_channel_id':
      'Personal-channel chat ID; zero removes the current personal channel.',
  'phone': 'Phone number of the contact, preferably in international format.',
  'pinned': 'True pins the chat/topic; false unpins it.',
  'pinned_chat_ids': 'Chat IDs to pin in the folder, in their desired order.',
  'playlist': 'Public YouTube playlist URL or playlist ID.',
  'prefix': 'Case-sensitive leading portion of the key or object path to list.',
  'privacy': 'Story visibility: everyone, contacts, close_friends or selected; selected also needs user_ids.',
  'project': 'Cloudflare Pages project name; omit to list projects.',
  'prompt': 'Full task or generation description. A reminder prompt turns the reminder into an agent job.',
  'protect_content': 'Restrict forwarding and saving content from this chat.',
  'proxied':
      'Whether Cloudflare proxies traffic for this supported DNS record.',
  'query': 'Search words or filter expression supported by this tool. Omit only when listing without a filter is allowed.',
  'question': 'Full poll or quiz question.',
  'quiz': 'Create a quiz with one correct option rather than a regular poll.',
  'record_id': 'DNS record ID from cloudflare_dns_records.',
  'ref': 'Repository branch, tag or commit to read.',
  'reminder_id': 'Reminder/job ID from list_reminders.',
  'remove': 'Remove the existing association/item instead of adding it.',
  'remove_chat_ids':
      'Chat IDs to remove from the folder’s explicit inclusions and pins.',
  'reply_to_message_id':
      'Message ID to reply to in the selected Telegram chat/thread.',
  'repo':
      'Public GitHub repository as owner/name or a supported github.com URL.',
  'requires_approval':
      'Require an administrator to approve people using the invite link.',
  'reset': 'Whether to reset the indicated state. See limitations before setting true.',
  'result_id': 'Inline-query result ID from inline_bot_query.',
  'revoke': 'Existing invite link to revoke instead of creating one.',
  'revoked': 'Whether to return revoked invite links instead of active links.',
  'rights': 'Administrator-right names and boolean values to grant or revoke.',
  'role': 'Membership role to select; owner, admin or member as supported.',
  'row': 'Zero-based button row from get_bot_buttons.',
  'sandbox_id': 'Exact sandbox ID from e2b_sandboxes.',
  'script': 'JavaScript source to run in the selected browser page.',
  'season': 'TV season number; include it to retrieve that season’s episodes.',
  'seconds': 'Duration in seconds.',
  'send_as': 'media uses Telegram’s media handling; file sends the original as a document.',
  'send_now': 'Send the scheduled message immediately instead of moving its scheduled time.',
  'session_id': 'Logged-in session identifier from list_sessions.',
  'set_id': 'Sticker-set identifier from list_sticker_sets.',
  'setting': 'Privacy setting to change; choose a listed setting and its relevant input fields.',
  'sha': 'Exact Git commit identifier to inspect.',
  'share_phone':
      'Share this account’s phone number with the contact being added.',
  'short_description': 'Short bot biography shown on its profile.',
  'show_author': 'Display channel-message author profiles where supported.',
  'show_id': 'TVmaze show ID returned by tv_search.',
  'sign_messages': 'Show author signatures on channel posts.',
  'since_days': 'Look-back window in days from the current local time.',
  'since_hours': 'Look-back window in hours from now; may be fractional.',
  'slow_mode':
      'Seconds members must wait between messages; zero disables slow mode.',
  'source': 'Human-readable origin of the saved item, for example Gmail or a website.',
  'star_price':
      'Telegram Stars charged per channel direct message; zero makes it free.',
  'state':
      'Filter by the supported item state, for example open, closed or all.',
  'story_id': 'Telegram story ID belonging to the specified poster chat.',
  'stream': 'Audio stream to inspect or change, such as media, ring or alarm.',
  'subfolders': 'Include nested Canvas folders in the export.',
  'subscription_id':
      'Stars subscription ID returned by list_star_subscriptions.',
  'tags': 'Short labels used to organize and find the saved data.',
  'text': 'Complete text to send, save or replace. Empty text clears data only where explicitly supported.',
  'title': 'Human-readable title for the object, message or notification.',
  'to_folder': 'Destination Canvas folder ID/name/path from canvas_overview.',
  'to_language': 'Target translation language code, for example en or es.',
  'topic_id':
      'Forum or channel-DM topic ID from the appropriate topic-listing tool.',
  'translatable': 'Enable or disable Telegram chat translation.',
  'trigger': 'Watch trigger scope; supply its corresponding chats, folder, app or schedule inputs.',
  'ttl':
      'DNS cache lifetime in seconds; value 1 means Cloudflare automatic TTL.',
  'type':
      'Result or object type supported by this tool; select an allowed value.',
  'unban': 'Lift an existing ban instead of banning the member.',
  'unblock': 'Unblock this user instead of blocking them.',
  'unmute': 'Restore sound on the selected audio stream.',
  'unpin': 'Unpin the specified message instead of pinning it.',
  'unread': 'True marks the chat unread; false clears the unread mark.',
  'unread_only': 'Include only items not marked read; this filter itself does not mark them read.',
  'url': 'Full accessible HTTP or HTTPS URL.',
  'user_id': 'Telegram user ID from list_contacts, list_members or a user/profile result.',
  'user_ids': 'Telegram user IDs returned by contact/member/profile tools.',
  'username': 'Telegram public username without the leading @ unless the description says otherwise.',
  'value': 'Complete value to store under the specified key.',
  'video': 'Public YouTube video URL or video ID.',
  'voice': 'Provider-specific voice ID compatible with the selected speech-generation model.',
  'watch_id': 'Watch ID returned by list_watches or create_watch.',
  'welcome_message_id': 'Welcome-message ID returned by list_welcome_messages.',
  'what': 'Content subset to retrieve; select an allowed value.',
  'width': 'Media width in pixels.',
};
