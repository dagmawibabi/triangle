part of 'telegram_tools.dart';

// Tools that run on the phone and are carried out by the chat controller:
// reminders and scheduled jobs, and packing files into a zip.

final _localPhoneTools = <TelegramTool>[
  TelegramTool(
    name: 'create_reminder',
    label: 'Setting a reminder',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Sets a reminder or a scheduled (cron) job. "Remind me to walk in 5 minutes" → text "Walk", in_minutes 5. '
        '"Remind me at 18:30" → at. Repeating: cron, five fields "minute hour day-of-month month day-of-week" in local '
        'time, e.g. "0 9 * * 1-5" weekdays at 9:00, "*/30 * * * *" every 30 minutes, "0 20 * * 0" Sundays at 20:00. '
        'A plain reminder is a phone notification that arrives on time even if the app is closed. Give prompt to make '
        'it a job: at that time you run the prompt (e.g. "summarise my unread channels", "send Liya good morning") and '
        'your answer becomes the notification.',
    parameters: _obj({
      'text': {'type': 'string', 'description': 'What the reminder says, short: "Walk", "Call mom".'},
      'in_minutes': {'type': 'number', 'description': 'Fire once, this many minutes from now.'},
      'at': {'type': 'string', 'description': 'Fire once at this local time, ISO "2026-10-23T18:30".'},
      'cron': {'type': 'string', 'description': 'Repeat on this cron schedule (local time).'},
      'prompt': {'type': 'string', 'description': 'Makes it a job: what you do when it fires.'},
      'accounts': accountsParameter('a job (the accounts you may use when it runs)'),
    }, ['text']),
  ),
  TelegramTool(
    name: 'list_reminders',
    label: 'Listing reminders',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'The user\'s reminders and scheduled jobs: what they say, when they fire next, how they repeat.',
    parameters: _obj({
      'include_done': {'type': 'boolean', 'description': 'Also list one-off reminders that already fired.'},
    }),
  ),
  TelegramTool(
    name: 'update_reminder',
    label: 'Changing a reminder',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description:
        'Changes a reminder or job: its text, time (in_minutes / at), cron schedule, prompt, or turns it on/off. '
        'Pass cron "" to make a repeating one fire just once at the new time.',
    parameters: _obj({
      'reminder_id': {'type': 'string'},
      'text': {'type': 'string'},
      'in_minutes': {'type': 'number'},
      'at': {'type': 'string'},
      'cron': {'type': 'string'},
      'prompt': {'type': 'string'},
      'enabled': {'type': 'boolean'},
      'accounts': accountsParameter('a job'),
    }, ['reminder_id']),
  ),
  TelegramTool(
    name: 'delete_reminder',
    label: 'Removing a reminder',
    category: ToolCategory.automation,
    cost: ToolCost.device,
    description: 'Removes a reminder or scheduled job for good.',
    parameters: _obj({
      'reminder_id': {'type': 'string'},
    }, ['reminder_id']),
  ),
  TelegramTool(
    name: 'zip_files',
    label: 'Zipping files',
    category: ToolCategory.files,
    cost: ToolCost.device,
    description:
        'Packs files of this conversation (attachments, generated or downloaded files) into one .zip, which then is '
        'a file of this conversation too: send it with send_message. Use when asked to zip or compress files, or to '
        'send many files as one.',
    parameters: _obj({
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Names of the files to pack.',
      },
      'name': {'type': 'string', 'description': 'Name of the zip, e.g. "photos.zip".'},
    }, ['files']),
  ),
];
