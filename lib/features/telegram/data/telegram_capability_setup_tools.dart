part of 'telegram_tools.dart';

// Diagnosing and setting up MCP servers and skills: the app runs these
// itself (capability_setup_tools.dart), beside omni_ai's install and use
// tools. Cards and sheets: capability_result_cards.dart.

const _modeEnum = ['ask', 'allow', 'off', 'default'];

final _capabilitySetupTools = <TelegramTool>[
  TelegramTool(
    name: 'mcp_diagnose',
    label: 'Diagnosing MCP servers',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    description:
        'Checks installed MCP servers and says what is wrong and how to fix it: the address and transport, the key or '
        'sign-in (and when it runs out), a fresh timed connection, its tools, resources and prompts, tool names some '
        'models reject, permissions, and how many recent calls failed. A failed connection is explained (needs a '
        'sign-in, key refused, wrong address, unreachable, timed out). Use it when an MCP tool fails or the user asks '
        'if a server works. Only reads. The user sees a card per server and a sheet with every finding.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'One installed server id; default all.'},
    }),
  ),
  TelegramTool(
    name: 'mcp_setup',
    label: 'Setting up an MCP server',
    category: ToolCategory.mcp,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Changes an installed MCP server, then tests it: its address or transport, the headers it sends (a key, '
        'e.g. {"Authorization": "Bearer …"}), which of its tools run without asking, ask first or are off, a fresh '
        'reconnect, refreshing or ending its sign-in. Signing in with OAuth for the first time is done by the user '
        'in Settings → MCP & Skills. Header values are never shown back. Asks first.',
    parameters: _obj({
      'server': {'type': 'string', 'description': 'Installed server id.'},
      'url': {'type': 'string', 'description': 'New endpoint, e.g. https://mcp.example.com/mcp.'},
      'transport': {'type': 'string', 'enum': ['http', 'sse'], 'description': 'http (Streamable HTTP) or sse (older servers).'},
      'headers': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'Headers to set; an empty value removes that header. Others are kept.',
      },
      'remove_headers': {'type': 'array', 'items': {'type': 'string', 'description': 'Header name.'}, 'description': 'Header names to remove.'},
      'default_mode': {
        'type': 'string',
        'enum': _modeEnum,
        'description': 'For all its tools: ask (approval each time), allow (no card), off (hidden), default (the app\'s approval setting).',
      },
      'tool_modes': {
        'type': 'object',
        'additionalProperties': {'type': 'string', 'enum': _modeEnum},
        'description': 'Per tool name: ask, allow, off, or default (follow default_mode).',
      },
      'reconnect': {'type': 'boolean', 'description': 'Drop the open connection so the next call starts fresh.'},
      'refresh_sign_in': {'type': 'boolean', 'description': 'Refresh its OAuth token now.'},
      'sign_out': {'type': 'boolean', 'description': 'Forget its OAuth sign-in and Authorization header.'},
      'test': {'type': 'boolean', 'description': 'Diagnose it after the change (default true).'},
    }, ['server']),
  ),
  TelegramTool(
    name: 'skill_diagnose',
    label: 'Diagnosing skills',
    category: ToolCategory.skills,
    cost: ToolCost.device,
    description:
        'Checks installed skills: whether each has instructions and a description that says when to use it, its size '
        'in tokens, files its instructions mention but don\'t bundle, bundled scripts, how often it was loaded, how '
        'much of every chat the skill list takes, look-alike descriptions, and (check_updates) whether its source has '
        'a newer version. Only reads. The user sees a card and a sheet with every finding.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'One installed skill; default all.'},
      'check_updates': {'type': 'boolean', 'description': 'Also compare with its GitHub or link source (slower).'},
    }),
  ),
  TelegramTool(
    name: 'skill_setup',
    label: 'Setting up a skill',
    category: ToolCategory.skills,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Changes an installed skill, then checks it: update it from its source, rename it, rewrite its description '
        '(say what it does and "Use when…"), replace its instructions, add or remove bundled files, or defer it (left '
        'out of every chat\'s skill list; the assistant still finds it). Asks first.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Installed skill name.'},
      'update': {'type': 'boolean', 'description': 'Reinstall from its source (GitHub or link), keeping it deferred if it was.'},
      'new_name': {'type': 'string', 'description': 'New name: letters, digits, _ and -.'},
      'description': {'type': 'string', 'description': 'New description, under 1024 characters.'},
      'instructions': {'type': 'string', 'description': 'New instructions (markdown), replacing the old ones.'},
      'deferred': {'type': 'boolean', 'description': 'true leaves it out of every chat\'s list; false lists it again.'},
      'files': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
        'description': 'Bundled files to write, path → text (e.g. references/checklist.md); an empty text removes it.',
      },
      'test': {'type': 'boolean', 'description': 'Check it after the change (default true).'},
    }, ['name']),
  ),
];

final capabilitySetupToolNames = {for (final t in _capabilitySetupTools) t.name};

const _capabilitySetupPolicies = <String, ToolPolicy>{
  'mcp_diagnose': ToolPolicy(ToolAccess.read),
  'skill_diagnose': ToolPolicy(ToolAccess.read),
  'mcp_setup': ToolPolicy(ToolAccess.modify),
  'skill_setup': ToolPolicy(ToolAccess.modify),
};

const _mcpServerFields =
    'servers: id, transport, address, header_names, auth (none, header, oauth), oauth: issuer, expires_at, can_refresh, '
    'server_name, protocol, connect_ms, list_ms, tools, tool_names, resources, prompts, permissions: default, allow, '
    'ask, off, calls_7d, failed_7d, status, findings: status, title, detail';
const _skillFields =
    'skills: name, description, source, deferred, chars, lines, est_tokens, files, files_bytes, scripts, '
    'missing_files, loads_30d, failed_30d, update_available, status, findings: status, title, detail';

const _capabilitySetupReferences = <String, ToolReference>{
  'mcp_diagnose': ToolReference(
    ['checked_at', 'counts: broken, warnings, suggestions, passed', _mcpServerFields],
    limits: ['Header values and tokens are never returned.', 'It can\'t sign in; the user does that in Settings.'],
  ),
  'mcp_setup': ToolReference(
    ['server', 'changed', 'check: one server as mcp_diagnose describes it'],
    limits: ['A first OAuth sign-in is done by the user in Settings → MCP & Skills.', 'Command (stdio) servers are changed in Settings.'],
  ),
  'skill_diagnose': ToolReference(['checked_at', 'installed', 'prompt_tokens', 'counts', 'general: status, title, detail', _skillFields]),
  'skill_setup': ToolReference(['skill', 'changed', 'check: one skill as skill_diagnose describes it']),
};
