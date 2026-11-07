part of 'telegram_tools.dart';

// The Content Canvas: the user's own folders of saved posts, messages,
// comments and notes. These run on the phone (ChatController); they only
// read Telegram to snapshot the messages being saved.

const _canvasItems = {
  'type': 'array',
  'description': 'Messages as refs ("post:<chat_id>:<message_id>") from earlier tool results.',
  'items': {'type': 'string'},
};

final _canvasTools = <TelegramTool>[
  TelegramTool(
    name: 'list_briefs',
    label: 'Opening briefs',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'The briefs written so far (morning, night and on demand), newest first, with brief_id values.',
    parameters: _obj({
      'limit': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'read_brief',
    label: 'Reading a brief',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'The full text of a brief (brief_id from list_briefs, or "latest").',
    parameters: _obj({
      'brief_id': {'type': 'string'},
    }, ['brief_id']),
  ),
  TelegramTool(
    name: 'write_brief',
    label: 'Writing a brief',
    category: ToolCategory.automation,
    cost: ToolCost.ai,
    description:
        'Writes a new brief now, like "Brief me now" in the app: a priority-ordered rundown of what happened across '
        'Telegram and connected apps, following the user\'s brief settings. Read-only research; the brief is saved '
        'with the others and its full text comes back. Takes a minute or two. Use when the user asks for a brief, '
        'a catch-up or "what did I miss".',
    parameters: _obj({
      'since_hours': {
        'type': 'number',
        'description': 'Hours back to cover, 1 to 72. Omit to cover the time since the last brief (6 to 36 hours).',
        'minimum': 1,
        'maximum': 72,
      },
    }),
  ),
  TelegramTool(
    name: 'canvas_overview',
    label: 'Opening the Content Canvas',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description:
        'The Content Canvas: every folder (with folder_id, path and item count) and, with folder, the items in it '
        '(item_id, kind, chat, text, note). Use before organising things into it.',
    parameters: _obj({
      'folder': {'type': 'string', 'description': 'A folder_id, name or path "A/B" to list its items.'},
    }),
  ),
  TelegramTool(
    name: 'canvas_create_folder',
    label: 'Making a canvas folder',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description:
        'Creates a folder in the Content Canvas (or returns the existing one with that name), optionally inside '
        'parent (folder_id or name).',
    parameters: _obj({
      'name': {'type': 'string'},
      'parent': {'type': 'string'},
      'description': {'type': 'string'},
    }, ['name']),
  ),
  TelegramTool(
    name: 'canvas_update_folder',
    label: 'Changing a canvas folder',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description: 'Renames a canvas folder, changes its description, or moves it under parent ("" for the top).',
    parameters: _obj({
      'folder': {'type': 'string'},
      'name': {'type': 'string'},
      'description': {'type': 'string'},
      'parent': {'type': 'string'},
    }, ['folder']),
  ),
  TelegramTool(
    name: 'canvas_export',
    label: 'Exporting a canvas folder',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description:
        'Exports a Content Canvas folder (and its subfolders unless subfolders: false) as json, md (Markdown), html or '
        'pdf. Returns the file\'s name; it appears in Files, and send_message can send it (files: [name]).',
    parameters: _obj({
      'folder': {'type': 'string'},
      'format': {
        'type': 'string',
        'enum': ['json', 'md', 'html', 'pdf'],
      },
      'subfolders': {'type': 'boolean'},
    }, ['folder', 'format']),
  ),
  TelegramTool(
    name: 'canvas_delete_folder',
    label: 'Deleting a canvas folder',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Deletes a canvas folder and its subfolders (only the canvas, nothing in Telegram). Its items are deleted '
        'too unless move_items_to names another folder. Needs approval.',
    parameters: _obj({
      'folder': {'type': 'string'},
      'move_items_to': {'type': 'string'},
    }, ['folder']),
  ),
  TelegramTool(
    name: 'canvas_add',
    label: 'Saving to the canvas',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description:
        'Saves posts, DMs or comments into a canvas folder (made if missing), with an optional note on why. Pass '
        'refs, or chat_id with message_ids. Use one call per folder when classifying.',
    parameters: _obj({
      'folder': {'type': 'string', 'description': 'folder_id, name or path; created when new.'},
      'refs': _canvasItems,
      'chat_id': {'type': 'integer'},
      'message_ids': {
        'type': 'array',
        'items': {'type': 'integer'},
      },
      'note': {'type': 'string'},
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    }, ['folder']),
  ),
  TelegramTool(
    name: 'canvas_save',
    label: 'Saving to the canvas',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description:
        'Saves anything that isn\'t a Telegram message into a canvas folder (made if missing): a web link, an email, a file '
        'of this conversation, or an item from a connected app (a Notion page, Slack message, issue, task, calendar event, '
        'R2 file…). Give a title, its url and/or file, a short text (the gist or an excerpt), and source (e.g. "Gmail").',
    parameters: _obj({
      'folder': {'type': 'string', 'description': 'folder_id, name or path; created when new.'},
      'kind': {'type': 'string', 'enum': ['link', 'email', 'file', 'app', 'note']},
      'title': {'type': 'string'},
      'text': {'type': 'string'},
      'url': {'type': 'string'},
      'file': {'type': 'string', 'description': 'A file of this conversation.'},
      'source': {'type': 'string'},
      'note': {'type': 'string', 'description': 'Why it is here.'},
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    }, ['folder', 'kind', 'title']),
  ),
  TelegramTool(
    name: 'canvas_add_note',
    label: 'Writing a canvas note',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description: 'Adds a text note (markdown) to a canvas folder, e.g. a summary of what the folder holds.',
    parameters: _obj({
      'folder': {'type': 'string'},
      'text': {'type': 'string'},
    }, ['folder', 'text']),
  ),
  TelegramTool(
    name: 'canvas_move',
    label: 'Moving canvas items',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description: 'Moves canvas items (item_ids from canvas_overview) to another folder.',
    parameters: _obj({
      'item_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'to_folder': {'type': 'string'},
    }, ['item_ids', 'to_folder']),
  ),
  TelegramTool(
    name: 'canvas_remove',
    label: 'Removing canvas items',
    category: ToolCategory.canvas,
    cost: ToolCost.device,
    description: 'Removes items (item_ids) from the canvas. Nothing in Telegram is touched.',
    parameters: _obj({
      'item_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    }, ['item_ids']),
  ),
];

/// The canvas tools' names, for the controller.
final canvasToolNames = {for (final t in _canvasTools) t.name};

extension TelegramSnapshots on TelegramToolRunner {
  /// A message as the canvas and post chips keep it.
  Future<PostSnapshot> snapshotMessage(int chatId, int messageId) async {
    final m = await _client.send<td.Message>(td.GetMessage(chatId: chatId, messageId: messageId), limited: true);
    final g = gistOf(m.content);
    final chat = _store.chat(chatId);
    final channel = chat != null && _store.kindOf(chat) == ChatKind.channel;
    return PostSnapshot(
      chatId: chatId,
      messageId: messageId,
      chatTitle: chat?.title ?? 'Chat',
      date: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
      text: g.text.isNotEmpty ? g.text : (g.detail ?? ''),
      sender: channel ? null : (m.isOutgoing ? 'You' : _store.senderName(m.senderId)),
      kind: g.kind,
      accountId: _client.accountId,
    );
  }
}
