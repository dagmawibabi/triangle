part of 'telegram_tools.dart';

// Decisions (TypeSafe Jev), MCP servers and Agent Skills: the tools omni_ai
// offers, listed here like every other tool so they have switches, details,
// approval cards and read-only rules. They run through omni_ai
// (ChatController._runCapability); keep their inputs in step with it
// (capability_tools_test checks).

const _jevState = {
  'type': 'string',
  'description': 'The content every question is about: text, or JSON (an object or list written as JSON is sent as '
      'JSON, keeping its structure).',
};

/// Pictures for Jev to look at, by placeholder.
const _jevImages = {
  'type': 'object',
  'additionalProperties': {'type': 'string'},
  'description': 'Pictures to judge: placeholder → picture. A picture is a file in this chat (an attachment, a '
      'downloaded photo or a file the assistant made, by name), or an https link. Put the placeholder in state, '
      'e.g. state {"caption": "...", "photo": "img1"} with images {"img1": "IMG_2041.jpg"}; one left out of state '
      'is added. To judge a Telegram photo, download it first. Uses a vision model (jev-preview).',
};

const _jevQuestions = {
  'type': 'object',
  'description':
      'Questions keyed by a short name. Each: {type: noul|choice|score, instructions, criteria}. noul criteria: '
      'optional {true, false} descriptions. choice criteria: {option: description}, 1 to 255 options. score '
      'criteria: 2 to 10 level descriptions, lowest first.',
  'additionalProperties': {
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['noul', 'choice', 'score'],
        'description': 'Question type.',
      },
      'instructions': {'type': 'string', 'description': 'The question or what to judge.'},
      'criteria': {
        'description': 'The options (choice: {"positive": "what counts", "negative": "..."}), levels (score: list, '
            'lowest first) or optional {true, false} (noul). Put choice options here, not under another key.',
      },
    },
    'required': ['type', 'instructions'],
  },
};

final _capabilityTools = <TelegramTool>[
  // ---- Decisions -----------------------------------------------------------
  TelegramTool(
    name: 'jev_decide',
    label: 'Deciding with Jev',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description:
        'Asks TypeSafe Jev several typed questions about one piece of content at once: yes/no (noul), one of named '
        'options (choice), a rubric score (score). Returns calibrated probabilities, not prose. Use it to classify, '
        'route, triage, moderate or grade consistently, and keep to the thresholds in the answer (yes, uncertain).',
    parameters: _obj({
      'state': _jevState,
      'images': _jevImages,
      'questions': _jevQuestions,
    }, ['state', 'questions']),
  ),
  TelegramTool(
    name: 'jev_batch',
    label: 'Deciding a batch with Jev',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description:
        'Asks Jev the same questions about many items in ONE call (up to 100): the sentiment of the last messages in a '
        'chat, the topic of each email, a score per review. Returns a short answer per item plus totals (counts per '
        'choice, yes/no counts, mean score). Always use this for two or more items instead of one Jev call per item; '
        'pass each item id (e.g. the message id) to match the answers back.',
    parameters: _obj({
      'items': {
        'type': 'array',
        'description': 'The contents to judge, 1 to 100, in order.',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': 'Your id for this item, returned with its answers, e.g. a message id.'},
            'state': {'type': 'string', 'description': 'The content: text, or JSON (sent as JSON).'},
            'images': _jevImages,
          },
          'required': ['state'],
        },
      },
      'questions': _jevQuestions,
    }, ['items', 'questions']),
  ),
  TelegramTool(
    name: 'jev_noul',
    label: 'Jev yes/no',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description: 'One yes/no question to Jev about one item: the probability it is true, and yes at your threshold. '
        'For two or more items use jev_batch.',
    parameters: _obj({
      'state': _jevState,
      'images': _jevImages,
      'instructions': {'type': 'string', 'description': 'The yes/no question, e.g. "Is this message asking for a refund?"'},
      'if_true': {'type': 'string', 'description': 'Optional: what counts as yes.'},
      'if_false': {'type': 'string', 'description': 'Optional: what counts as no.'},
    }, ['state', 'instructions']),
  ),
  TelegramTool(
    name: 'jev_choice',
    label: 'Jev choice',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description: 'Jev picks one of several named options for one item, with each option\'s probability and its confidence. '
        'For two or more items use jev_batch.',
    parameters: _obj({
      'state': _jevState,
      'images': _jevImages,
      'instructions': {'type': 'string', 'description': 'What to choose, e.g. "Which team should handle this?"'},
      'options': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'Option name to a short description (empty to judge by the name), 1 to 255 options.',
      },
    }, ['state', 'instructions', 'options']),
  ),
  TelegramTool(
    name: 'jev_score',
    label: 'Jev score',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description: 'Jev rates one item on a rubric: the probability-weighted level, each level\'s probability, and confidence. '
        'For two or more items use jev_batch.',
    parameters: _obj({
      'state': _jevState,
      'images': _jevImages,
      'instructions': {'type': 'string', 'description': 'What to rate, e.g. "How urgent is this?"'},
      'levels': {
        'type': 'array',
        'items': {'type': 'string', 'description': 'One level\'s description.'},
        'description': 'Rubric levels, lowest first: 2 to 10 descriptions.',
      },
    }, ['state', 'instructions', 'levels']),
  ),
  TelegramTool(
    name: 'jev_box',
    label: 'Jev box',
    category: ToolCategory.decisions,
    cost: ToolCost.ai,
    description:
        'Jev finds something in a picture and returns its box: top, bottom, left and right as fractions of the '
        'picture from its top-left. Give the picture in images.',
    parameters: _obj({
      'images': _jevImages,
      'state': {'type': 'string', 'description': 'Optional: the picture\'s placeholder, or JSON that includes it.'},
      'instructions': {'type': 'string', 'description': 'What to find, e.g. "the red car".'},
    }, ['images', 'instructions']),
  ),
  TelegramTool(
    name: 'jev_models',
    label: 'Listing Jev models',
    category: ToolCategory.decisions,
    cost: ToolCost.web,
    description: 'The Jev model ids your TypeSafe key can use (aliases like jev-latest and pinned versions).',
    parameters: _obj({}),
  ),

  // ---- MCP servers -----------------------------------------------------------
  TelegramTool(
    name: 'mcp_search',
    label: 'Searching MCP servers',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description:
        'Searches the official MCP Registry for servers that add tools (GitHub, Linear, docs, databases…). Returns '
        'each server\'s registry name, what it does, how it connects, and the values it needs (inputs).',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Server name or topic, at least 3 characters.'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'description': 'How many results, default 10.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'mcp_list_servers',
    label: 'Listing MCP servers',
    category: ToolCategory.mcp,
    cost: ToolCost.device,
    description: 'The MCP servers installed in the app: id, transport and address. Doesn\'t connect to them.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'mcp_is_installed',
    label: 'Checking an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.device,
    description: 'Whether an MCP server id is installed. Doesn\'t connect.',
    parameters: _obj({
      'id': {'type': 'string', 'description': 'Server id, as mcp_list_servers shows it.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'mcp_install_catalog',
    label: 'Installing an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Installs a server from the MCP Registry by its full name (from mcp_search). Give the values its inputs ask '
        'for (API keys) in headers, by header or variable name. Servers that run as a local command can only be added '
        'by the person in Settings. Asks first.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Registry name from mcp_search, e.g. io.github.user/weather.'},
      'id': {'type': 'string', 'description': 'Optional short local id; defaults to the last part of the name.'},
      'headers': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'Values for the server\'s inputs, by header or {variable} name, e.g. {"api_key": "…"}.',
      },
      'env': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'Environment values a package server needs.',
      },
    }, ['name']),
  ),
  TelegramTool(
    name: 'mcp_install',
    label: 'Adding an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.device,
    requiresApproval: true,
    description:
        'Saves an MCP server by address: a Streamable HTTP (or legacy SSE) endpoint and optional headers. Plain http '
        'only for localhost or the local network. Doesn\'t connect yet. Asks first.',
    parameters: _obj({
      'server': {
        'type': 'object',
        'description': 'The server to save.',
        'properties': {
          'id': {'type': 'string', 'description': 'Short id: letters, digits, _ and -.'},
          'transport': {
            'type': 'string',
            'enum': ['http', 'sse'],
            'description': 'http (Streamable HTTP, most servers) or sse (older servers).',
          },
          'url': {'type': 'string', 'description': 'The server\'s endpoint, e.g. https://mcp.example.com/mcp.'},
          'headers': {
            'type': 'object',
            'additionalProperties': {'type': 'string'},
            'description': 'Headers sent with every request, e.g. {"Authorization": "Bearer …"}.',
          },
        },
        'required': ['id', 'transport', 'url'],
      },
    }, ['server']),
  ),
  TelegramTool(
    name: 'mcp_uninstall',
    label: 'Removing an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.device,
    destructive: true,
    description: 'Removes an installed MCP server and its saved headers, and closes its connection.',
    parameters: _obj({
      'id': {'type': 'string', 'description': 'Server id to remove.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'mcp_list_tools',
    label: 'Opening an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description: 'Connects to an installed MCP server and lists its tools with their input schemas, for mcp_call_tool.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
    }, ['server']),
  ),
  TelegramTool(
    name: 'mcp_call_tool',
    label: 'Using an MCP tool',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Runs one tool on an installed MCP server, with arguments matching its input schema from mcp_list_tools. '
        'Works right after installing. It can do anything the server allows, so it asks first.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
      'name': {'type': 'string', 'description': 'Tool name from mcp_list_tools.'},
      'arguments': {
        'type': 'object',
        'additionalProperties': true,
        'description': 'The tool\'s input, matching its schema; {} when it takes none.',
      },
    }, ['server', 'name', 'arguments']),
  ),
  TelegramTool(
    name: 'mcp_list_resources',
    label: 'Listing MCP resources',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description: 'Connects to an installed MCP server and lists the resources (files, records, pages) it offers.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
    }, ['server']),
  ),
  TelegramTool(
    name: 'mcp_read_resource',
    label: 'Reading an MCP resource',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description: 'Reads one resource from an installed MCP server.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
      'uri': {'type': 'string', 'description': 'Resource URI from mcp_list_resources.'},
    }, ['server', 'uri']),
  ),
  TelegramTool(
    name: 'mcp_list_prompts',
    label: 'Listing MCP prompts',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description: 'Connects to an installed MCP server and lists its prompt templates and their arguments.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
    }, ['server']),
  ),
  TelegramTool(
    name: 'mcp_get_prompt',
    label: 'Loading an MCP prompt',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description: 'Loads a prompt template from an installed MCP server, filled with its arguments.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
      'name': {'type': 'string', 'description': 'Prompt name from mcp_list_prompts.'},
      'arguments': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'The prompt\'s arguments by name.',
      },
    }, ['server', 'name']),
  ),

  // ---- Skills ------------------------------------------------------------------
  TelegramTool(
    name: 'search_skills',
    label: 'Searching skills',
    category: ToolCategory.skills,
    cost: ToolCost.web,
    description:
        'Searches public skill catalogs (Skyll and skills.sh) for Agent Skills: step-by-step instructions for a kind '
        'of task. Returns what each does, its source, installs, and the install string for install_skill.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What the skill should help with, at least 2 characters.'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'description': 'How many results, default 10.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'list_skills',
    label: 'Listing skills',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    description: 'Installed skills: name, what each is for, where it came from and its bundled files.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Optional filter on name and description.'},
    }),
  ),
  TelegramTool(
    name: 'is_skill_installed',
    label: 'Checking a skill',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    description: 'Whether a skill is installed.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Skill name.'},
    }, ['name']),
  ),
  TelegramTool(
    name: 'preview_skill',
    label: 'Previewing a skill',
    category: ToolCategory.skills,
    cost: ToolCost.web,
    description: 'Reads a skill from GitHub or a SKILL.md link without installing it: its instructions and bundled files.',
    parameters: _obj({
      'source': {'type': 'string', 'description': 'owner/repo, owner/repo@skill-name, or an https link to a SKILL.md.'},
      'skill': {'type': 'string', 'description': 'Optional: the one skill to read when the repo has several.'},
    }, ['source']),
  ),
  TelegramTool(
    name: 'load_skill',
    label: 'Using a skill',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    description: 'Loads an installed skill\'s full instructions. Call it before doing a task a skill covers, then follow them.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Installed skill name from list_skills.'},
    }, ['name']),
  ),
  TelegramTool(
    name: 'read_skill_file',
    label: 'Reading a skill file',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    description: 'Reads a reference file or script bundled with an installed skill.',
    parameters: _obj({
      'skill': {'type': 'string', 'description': 'Installed skill name.'},
      'path': {'type': 'string', 'description': 'File path as load_skill lists it.'},
    }, ['skill', 'path']),
  ),
  TelegramTool(
    name: 'install_skill',
    label: 'Installing a skill',
    category: ToolCategory.skills,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Installs a skill from GitHub (owner/repo or owner/repo@skill-name) or an https link to a SKILL.md, so its '
        'instructions are available in every chat. Asks first.',
    parameters: _obj({
      'source': {'type': 'string', 'description': 'owner/repo, owner/repo@skill-name, or an https link to a SKILL.md.'},
      'skill': {'type': 'string', 'description': 'Optional: the one skill to install when the repo has several.'},
    }, ['source']),
  ),
  TelegramTool(
    name: 'uninstall_skill',
    label: 'Removing a skill',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    destructive: true,
    description: 'Removes an installed skill and its bundled files from the app.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Installed skill name.'},
    }, ['name']),
  ),
  // ---- Phone calls (Vapi) ----
  TelegramTool(
    name: 'place_phone_call',
    label: 'Placing a phone call',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    requiresApproval: true,
    alwaysAsk: true,
    description:
        'Phones a number for the user through Vapi. An AI voice agent carries out the goal and reports back with a '
        'summary, the collected answers and the transcript. Returns the call id at once (the user sees the call live); '
        'check it with get_phone_call. Costs money and reaches a real person: only when the user asked.',
    parameters: _obj({
      'to': {'type': 'string', 'description': 'The number with country code, e.g. +14155550100.'},
      'to_name': {'type': 'string', 'description': 'Who is being called, if known.'},
        'goal': {'type': 'string', 'description': 'What the call must achieve, in plain words, e.g. "Book a table for 4 at 7pm Friday".'},
        'context': {'type': 'string', 'description': 'Facts the agent may use: names, dates, order numbers, limits.'},
        'collect': {'type': 'object', 'additionalProperties': {'type': 'string'}, 'description': 'Answers to bring back, name to meaning, e.g. {"booked": "true if booked"}.'},
        'first_message': {'type': 'string', 'description': 'What to say when they answer. Leave out to let the agent open.'},
        'language': {'type': 'string', 'description': 'Language code to speak, e.g. "es". Leave out to match theirs.'},
        'voice': {'type': 'string', 'description': 'Vapi voice: Elliot, Clara, Emma, Godfrey, Kai, Layla, Naina, Neil, Nico, Sagar, Savannah, Sid.'},
        'max_minutes': {'type': 'integer', 'description': '1-30; capped by the user\'s setting.'},
        'voicemail_message': {'type': 'string', 'description': 'A short message to leave on voicemail. Leave out to hang up.'},
        'schedule_at': {'type': 'string', 'description': 'ISO date-time to call later instead of now, with the time zone.'},
    }, ['to', 'goal']),
  ),
  TelegramTool(
    name: 'place_phone_calls',
    label: 'Placing phone calls',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    requiresApproval: true,
    alwaysAsk: true,
    description:
        'Phones several numbers at once with the same goal (asking shops for a price, restaurants for a table). '
        'Returns each call id; compare results with get_phone_call. Only when the user asked.',
    parameters: _obj({
      'to': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'number': {'type': 'string', 'description': 'With country code.'},
            'name': {'type': 'string', 'description': 'Who it is.'},
          },
          'required': ['number'],
        },
        'description': 'Numbers with country code, and who each is (up to 20).',
      },
        'goal': {'type': 'string', 'description': 'What the call must achieve, in plain words, e.g. "Book a table for 4 at 7pm Friday".'},
        'context': {'type': 'string', 'description': 'Facts the agent may use: names, dates, order numbers, limits.'},
        'collect': {'type': 'object', 'additionalProperties': {'type': 'string'}, 'description': 'Answers to bring back, name to meaning, e.g. {"booked": "true if booked"}.'},
        'first_message': {'type': 'string', 'description': 'What to say when they answer. Leave out to let the agent open.'},
        'language': {'type': 'string', 'description': 'Language code to speak, e.g. "es". Leave out to match theirs.'},
        'voice': {'type': 'string', 'description': 'Vapi voice: Elliot, Clara, Emma, Godfrey, Kai, Layla, Naina, Neil, Nico, Sagar, Savannah, Sid.'},
        'max_minutes': {'type': 'integer', 'description': '1-30; capped by the user\'s setting.'},
        'voicemail_message': {'type': 'string', 'description': 'A short message to leave on voicemail. Leave out to hang up.'},
        'schedule_at': {'type': 'string', 'description': 'ISO date-time to call later instead of now, with the time zone.'},
    }, ['to', 'goal']),
  ),
  TelegramTool(
    name: 'get_phone_call',
    label: 'Checking a phone call',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    description:
        'A call\'s status, outcome, summary, collected answers, cost and transcript. With wait true, waits (up to '
        'max_wait_seconds) for the call to end and its summary to arrive.',
    parameters: _obj({
      'id': {'type': 'string', 'description': 'The call id from place_phone_call.'},
      'wait': {'type': 'boolean', 'description': 'Wait for the call to end.'},
      'max_wait_seconds': {'type': 'integer', 'description': '5-900, default 300.'},
      'include_transcript': {'type': 'boolean', 'description': 'Default true.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'list_phone_calls',
    label: 'Listing phone calls',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    description: 'Recent calls made or received through Vapi, newest first, with outcome and summary.',
    parameters: _obj({
      'limit': {'type': 'integer', 'description': '1-50, default 10.'},
      'since': {'type': 'string', 'description': 'ISO date; only calls after it.'},
    }),
  ),
  TelegramTool(
    name: 'control_phone_call',
    label: 'Steering a phone call',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Steers a call in progress: say makes the agent say text now, note gives the agent a new instruction or fact, '
        'transfer hands the call to a number, end hangs up.',
    parameters: _obj({
      'id': {'type': 'string', 'description': 'The call id.'},
      'action': {'type': 'string', 'enum': ['say', 'note', 'transfer', 'end'], 'description': 'What to do.'},
      'text': {'type': 'string', 'description': 'What to say (say), the instruction (note), or a line before transferring.'},
      'number': {'type': 'string', 'description': 'For transfer: the number to hand the call to.'},
    }, ['id', 'action']),
  ),
  TelegramTool(
    name: 'phone_call_recording',
    label: 'Getting a call recording',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    description: 'A fresh link to a finished call\'s recording (it expires after a while).',
    parameters: _obj({
      'id': {'type': 'string', 'description': 'The call id.'},
      'channel': {'type': 'string', 'enum': ['mono', 'stereo', 'customer', 'assistant'], 'description': 'Default mono.'},
    }, ['id']),
  ),
  TelegramTool(
    name: 'list_phone_numbers',
    label: 'Listing phone numbers',
    category: ToolCategory.calls,
    cost: ToolCost.web,
    description: 'The numbers in the Vapi account that calls can be made from.',
    parameters: _obj({}),
  ),
];

/// The tools above, which omni_ai runs.
final capabilityToolNames = {for (final t in _capabilityTools) t.name};
