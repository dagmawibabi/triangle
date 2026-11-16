import 'dart:async';
import 'dart:io';

import 'package:omni_ai/omni_ai.dart' show AiException, McpClient, McpRegistry, McpServer, McpToolInfo, McpTransportKind, Skill, createMcpClient;

import '../../ai/data/ai.dart';
import '../../integrations/mcp_oauth.dart';
import '../../integrations/mcp_permissions.dart';
import '../../settings/data/system_check.dart' show CheckStatus, ProviderReader;
import '../../usage/usage.dart';
import 'telegram_tools.dart' show ToolOutput;

// Runs the tools in telegram_capability_setup_tools.dart: diagnosing and
// setting up MCP servers and skills. Header values and tokens are never
// returned, only their names. Cards: capability_result_cards.dart.

Future<ToolOutput> runCapabilitySetupTool(ProviderReader read, String name, Map<String, dynamic> a) async {
  try {
    return switch (name) {
      'mcp_diagnose' => await _mcpDiagnose(read, a),
      'mcp_setup' => await _mcpSetup(read, a),
      'skill_diagnose' => await _skillDiagnose(read, a),
      'skill_setup' => await _skillSetup(read, a),
      _ => ToolOutput({'error': 'Unknown tool $name.'}),
    };
  } on AiException catch (e) {
    return ToolOutput({'error': e.message});
  } on ArgumentError catch (e) {
    return ToolOutput({'error': '${e.message}'});
  }
}

// ---- Shared -------------------------------------------------------------------

Map<String, dynamic> _finding(CheckStatus s, String title, [String? detail]) => {
  'status': s.name,
  'title': title,
  if (detail != null && detail.isNotEmpty) 'detail': detail,
};

CheckStatus _worst(List<Map<String, dynamic>> findings) {
  for (final s in const [CheckStatus.fail, CheckStatus.warn, CheckStatus.improve]) {
    if (findings.any((f) => f['status'] == s.name)) return s;
  }
  return CheckStatus.ok;
}

Map<String, int> _counts(Iterable<Map<String, dynamic>> findings) {
  int n(CheckStatus s) => findings.where((f) => f['status'] == s.name).length;
  return {
    'broken': n(CheckStatus.fail),
    'warnings': n(CheckStatus.warn),
    'suggestions': n(CheckStatus.improve),
    'passed': n(CheckStatus.ok),
  };
}

String? _text(Map<String, dynamic> a, String k) {
  final v = a[k];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

String _error(Object e) => '$e'.replaceFirst(RegExp(r'^\w*Exception:?\s*'), '');

Future<T> _timed<T>(Future<T> f, int seconds) => f.timeout(Duration(seconds: seconds));

// ---- MCP: diagnose --------------------------------------------------------------

/// Tool names some model providers reject.
final _toolNameRule = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

Future<ToolOutput> _mcpDiagnose(ProviderReader read, Map<String, dynamic> a) async {
  final mcp = read(aiProvider).mcp;
  await mcp.load();
  final only = _text(a, 'server');
  if (only != null && mcp[only] == null) {
    return ToolOutput({
      'error': 'No MCP server "$only". Installed: ${mcp.servers.isEmpty ? 'none' : mcp.servers.map((s) => s.id).join(', ')}.',
    });
  }
  final targets = only == null ? mcp.servers : [mcp[only]!];
  if (targets.isEmpty) {
    return ToolOutput({
      'checked_at': DateTime.now().toIso8601String(),
      'servers': const [],
      'counts': _counts(const []),
      'note': 'No MCP servers are installed. mcp_search finds one and mcp_install_catalog installs it; servers that '
          'need a sign-in are added in Settings → MCP & Skills.',
    });
  }
  final servers = await Future.wait([for (final s in targets) diagnoseMcpServer(read, s)]);
  return ToolOutput({
    'checked_at': DateTime.now().toIso8601String(),
    'counts': _counts([for (final s in servers) ...(s['findings'] as List).cast<Map<String, dynamic>>()]),
    'servers': servers,
  });
}

/// Everything about one server: its settings, sign-in, a fresh connection
/// (its own, so the chat's cached one isn't disturbed), what it offers,
/// permissions and recent calls.
Future<Map<String, dynamic>> diagnoseMcpServer(ProviderReader read, McpServer s) async {
  final findings = <Map<String, dynamic>>[];
  final out = <String, dynamic>{
    'id': s.id,
    'transport': s.transport.name,
    'address': s.transport == McpTransportKind.stdio
        ? [s.command, ...s.args].whereType<String>().join(' ')
        : (Uri.tryParse(s.url ?? '')?.replace(query: '').toString().replaceFirst(RegExp(r'\?$'), '') ?? s.url),
    'header_names': s.headers.keys.toList(),
  };

  // Settings.
  if (s.transport == McpTransportKind.stdio) {
    findings.add(
      (Platform.isAndroid || Platform.isIOS)
          ? _finding(CheckStatus.fail, 'Runs a local command', 'Command servers only run on a computer. Use its HTTP address instead, if it has one.')
          : _finding(CheckStatus.info, 'Runs a local command', '${s.command} must be installed here.'),
    );
  } else {
    final uri = Uri.tryParse(s.url ?? '');
    if (uri == null || uri.host.isEmpty) {
      findings.add(_finding(CheckStatus.fail, 'No valid address', 'Set its URL with mcp_setup.'));
    } else if (uri.scheme == 'http') {
      findings.add(
        McpRegistry.isLocalHost(uri.host)
            ? _finding(CheckStatus.info, 'Plain http on the local network', 'Fine at home; it won\'t work away from this network.')
            : _finding(CheckStatus.fail, 'Plain http on the internet', 'Use https.'),
      );
    }
    if (s.transport == McpTransportKind.sse) {
      findings.add(_finding(CheckStatus.improve, 'Uses legacy SSE', 'Most servers now speak Streamable HTTP; try transport http if it has an /mcp endpoint.'));
    }
  }

  // Sign-in.
  final hasAuthHeader = s.headers.keys.any((k) => k.toLowerCase() == 'authorization');
  final oauth = await McpOAuth.status(s.id);
  out['auth'] = oauth.signedIn
      ? 'oauth'
      : s.headers.isNotEmpty
      ? 'header'
      : 'none';
  if (oauth.signedIn) {
    out['oauth'] = {
      'issuer': ?oauth.issuer,
      'expires_at': ?oauth.expiresAt?.toIso8601String(),
      'can_refresh': oauth.canRefresh,
    };
    final ends = oauth.expiresAt;
    if (ends != null && ends.isBefore(DateTime.now())) {
      findings.add(
        oauth.canRefresh
            ? _finding(CheckStatus.warn, 'Sign-in token ran out', 'It refreshes on the next use, or now with mcp_setup refresh_sign_in.')
            : _finding(CheckStatus.fail, 'Sign-in ran out', 'Sign in again in Settings → MCP & Skills → ${s.id}.'),
      );
    } else if (ends != null && !oauth.canRefresh && ends.difference(DateTime.now()).inHours < 24) {
      findings.add(_finding(CheckStatus.warn, 'Sign-in ends within a day', 'It can\'t refresh itself; sign in again then.'));
    } else {
      findings.add(_finding(CheckStatus.ok, 'Signed in${oauth.issuer == null ? '' : ' with ${oauth.issuer}'}'));
    }
    if (!hasAuthHeader) {
      findings.add(_finding(CheckStatus.fail, 'Sign-in token missing', 'Signed in, but no Authorization header is sent. Sign in again.'));
    }
  }

  // A fresh connection, timed.
  McpClient? client;
  final clock = Stopwatch()..start();
  List<McpToolInfo> tools = const [];
  try {
    final c = await _timed(createMcpClient(s, timeout: const Duration(seconds: 20)), 25);
    client = c;
    out['connect_ms'] = clock.elapsedMilliseconds;
    out['server_name'] = c.serverName;
    out['protocol'] = c.protocolVersion;
    clock.reset();
    tools = await _timed(c.listTools(), 20);
    out['list_ms'] = clock.elapsedMilliseconds;
    out['tools'] = tools.length;
    out['tool_names'] = [for (final t in tools.take(40)) t.name];
    // Resources and prompts are optional: a server without them is fine.
    try {
      out['resources'] = (await _timed(c.listResources(), 15)).length;
    } catch (_) {
      out['resources'] = 0;
    }
    try {
      out['prompts'] = (await _timed(c.listPrompts(), 15)).length;
    } catch (_) {
      out['prompts'] = 0;
    }
    final ms = out['connect_ms'] as int;
    findings.add(_finding(
      ms > 5000 ? CheckStatus.warn : CheckStatus.ok,
      'Connected in ${ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s'}',
      '${c.serverName} · protocol ${c.protocolVersion}',
    ));
    if (tools.isEmpty) {
      findings.add(_finding(
        (out['resources'] as int) + (out['prompts'] as int) > 0 ? CheckStatus.info : CheckStatus.warn,
        'Offers no tools',
        (out['resources'] as int) + (out['prompts'] as int) > 0
            ? 'Only resources or prompts.'
            : 'It may need a key or a sign-in before it shows them.',
      ));
    } else {
      findings.add(_finding(CheckStatus.ok, '${tools.length} tool${tools.length == 1 ? '' : 's'}'));
    }
    final badNames = [for (final t in tools) if (!_toolNameRule.hasMatch(t.name)) t.name];
    if (badNames.isNotEmpty) {
      findings.add(_finding(CheckStatus.warn, '${badNames.length} tool name${badNames.length == 1 ? '' : 's'} some models reject', badNames.take(5).join(', ')));
    }
    final undocumented = [for (final t in tools) if (t.description.trim().isEmpty) t.name];
    if (undocumented.isNotEmpty) {
      findings.add(_finding(CheckStatus.improve, '${undocumented.length} tool${undocumented.length == 1 ? '' : 's'} without a description', 'The assistant may not know when to use ${undocumented.take(3).join(', ')}.'));
    }
    if (tools.length > 60) {
      findings.add(_finding(CheckStatus.improve, 'Many tools (${tools.length})', 'Turn off the ones you don\'t need with mcp_setup tool_modes, so the assistant picks well.'));
    }
  } catch (e) {
    out['connect_ms'] = clock.elapsedMilliseconds;
    findings.add(await _connectionProblem(s, e, hasAuthHeader));
  } finally {
    try {
      await client?.close();
    } catch (_) {}
  }

  // Permissions.
  final perms = read(mcpPermissionsProvider.notifier);
  await perms.ready;
  final p = perms.of(s.id);
  final modes = {for (final t in tools) t.name: p.modeFor(t.name)};
  out['permissions'] = {
    'default': p.defaultMode?.name ?? 'app',
    'allow': modes.values.where((m) => m == McpToolMode.allow).length,
    'ask': modes.values.where((m) => m == McpToolMode.ask).length,
    'off': modes.values.where((m) => m == McpToolMode.off).length,
  };
  if (tools.isNotEmpty) {
    final stale = [for (final t in p.tools.keys) if (!modes.containsKey(t)) t];
    if (stale.isNotEmpty) {
      findings.add(_finding(CheckStatus.improve, 'Settings for ${stale.length} tool${stale.length == 1 ? '' : 's'} it no longer has', stale.take(5).join(', ')));
    }
    if (modes.isNotEmpty && modes.values.every((m) => m == McpToolMode.off)) {
      findings.add(_finding(CheckStatus.warn, 'Every tool is turned off', 'The assistant can\'t use this server.'));
    }
  }

  // Recent calls.
  final week = read(usageProvider).where((e) => e.modality == Modality.mcp && e.model == s.id && DateTime.now().difference(e.at).inDays < 7).toList();
  final failed = week.where((e) => !e.ok).length;
  out['calls_7d'] = week.length;
  out['failed_7d'] = failed;
  if (week.length >= 3 && failed / week.length > 0.3) {
    findings.add(_finding(CheckStatus.warn, '$failed of ${week.length} calls failed this week', 'See Usage → MCP & Skills.'));
  }

  findings.sort((x, y) => CheckStatus.values.byName('${x['status']}').rank.compareTo(CheckStatus.values.byName('${y['status']}').rank));
  out['status'] = _worst(findings).name;
  out['findings'] = findings;
  return out;
}

/// What a failed connection most likely means, and how to fix it.
Future<Map<String, dynamic>> _connectionProblem(McpServer s, Object e, bool hasAuthHeader) async {
  final code = e is AiException ? e.statusCode : null;
  final msg = _error(e);
  if (e is TimeoutException) return _finding(CheckStatus.fail, 'Timed out', 'The server didn\'t answer in time. It may be down or slow.');
  if (e is SocketException || e is HandshakeException || msg.contains('Failed host lookup')) {
    return _finding(CheckStatus.fail, 'Can\'t reach it', 'Check the address and the connection. $msg');
  }
  if (code == 401 || code == 403) {
    final url = s.url;
    final plan = url == null ? null : await McpOAuth.probe(url, headers: s.headers);
    if (plan != null) {
      return _finding(CheckStatus.fail, 'Needs a sign-in with ${plan.host}', 'Sign in in Settings → MCP & Skills → ${s.id} (the assistant can\'t do it for you).');
    }
    return _finding(
      CheckStatus.fail,
      hasAuthHeader ? 'Its key was refused' : 'Needs a key',
      hasAuthHeader ? 'Replace the key with mcp_setup headers.' : 'Add it with mcp_setup headers, e.g. {"Authorization": "Bearer …"}.',
    );
  }
  if (code == 404 || code == 405) {
    return _finding(CheckStatus.fail, 'Wrong address ($code)', 'Nothing speaks MCP there. The endpoint usually ends in /mcp (or /sse for transport sse).');
  }
  if (code != null && code >= 500) return _finding(CheckStatus.fail, 'Server error ($code)', msg);
  return _finding(CheckStatus.fail, 'Didn\'t connect', msg);
}

// ---- MCP: setup -----------------------------------------------------------------

Future<ToolOutput> _mcpSetup(ProviderReader read, Map<String, dynamic> a) async {
  final mcp = read(aiProvider).mcp;
  await mcp.load();
  final id = _text(a, 'server') ?? '';
  var s = mcp[id];
  if (s == null) {
    return ToolOutput({'error': 'No MCP server "$id". Installed: ${mcp.servers.isEmpty ? 'none' : mcp.servers.map((s) => s.id).join(', ')}.'});
  }
  final changed = <String>[];
  final url = _text(a, 'url');
  final transport = switch (_text(a, 'transport')) {
    'http' => McpTransportKind.http,
    'sse' => McpTransportKind.sse,
    null => null,
    final t => throw ArgumentError('transport is http or sse, not $t.'),
  };
  if ((url != null || transport != null) && s.transport == McpTransportKind.stdio) {
    throw ArgumentError('${s.id} runs a local command; change it in Settings → MCP & Skills.');
  }
  final headers = {...s.headers};
  if (a['headers'] is Map) {
    for (final e in (a['headers'] as Map).entries) {
      final k = '${e.key}'.trim();
      if (k.isEmpty) continue;
      final v = '${e.value ?? ''}'.trim();
      final existing = headers.keys.firstWhere((h) => h.toLowerCase() == k.toLowerCase(), orElse: () => k);
      if (v.isEmpty) {
        if (headers.remove(existing) != null) changed.add('Removed header $existing');
      } else {
        headers.remove(existing);
        headers[k] = v;
        changed.add('Set header $k');
      }
    }
  }
  for (final k in [for (final x in (a['remove_headers'] as List? ?? const [])) '$x'.trim()]) {
    final existing = headers.keys.where((h) => h.toLowerCase() == k.toLowerCase()).firstOrNull;
    if (existing != null && headers.remove(existing) != null) changed.add('Removed header $existing');
  }
  if (a['sign_out'] == true) {
    if (await McpOAuth.isOAuth(s.id)) {
      await McpOAuth.forget(s.id);
      changed.add('Signed out');
    }
    final auth = headers.keys.where((h) => h.toLowerCase() == 'authorization').firstOrNull;
    if (auth != null) headers.remove(auth);
  }
  if (url != null && url != s.url) changed.add('Address → $url');
  if (transport != null && transport != s.transport) changed.add('Transport → ${transport.name}');
  final configChanged = url != null && url != s.url ||
      transport != null && transport != s.transport ||
      !_sameMap(headers, s.headers);
  if (configChanged) {
    s = await mcp.install(McpServer(
      id: s.id,
      transport: transport ?? s.transport,
      url: url ?? s.url,
      headers: headers,
      command: s.command,
      args: s.args,
      env: s.env,
      approval: s.approval,
      protocolVersionDiscovery: s.protocolVersionDiscovery,
    ));
  } else if (a['reconnect'] == true) {
    // Saving it again drops the cached connection; the next call reconnects.
    s = await mcp.install(s);
    changed.add('Reconnected');
  }
  if (a['refresh_sign_in'] == true) {
    if (!await McpOAuth.isOAuth(s.id)) throw ArgumentError('${s.id} didn\'t sign in here, so there\'s nothing to refresh.');
    final ok = await McpOAuth.refresh(mcp, s.id, force: true);
    changed.add(ok ? 'Refreshed sign-in' : 'Sign-in refresh failed: sign in again in Settings');
    s = mcp[s.id] ?? s;
  }

  // Permissions.
  final perms = read(mcpPermissionsProvider.notifier);
  await perms.ready;
  McpToolMode? mode(String v) => switch (v) {
    'ask' => McpToolMode.ask,
    'allow' => McpToolMode.allow,
    'off' => McpToolMode.off,
    'app' || 'default' => null,
    _ => throw ArgumentError('Modes are ask, allow, off or default, not $v.'),
  };
  if (_text(a, 'default_mode') case final d?) {
    await perms.setDefault(s.id, mode(d));
    changed.add('All tools → ${mode(d)?.label ?? 'app setting'}');
  }
  if (a['tool_modes'] is Map) {
    for (final e in (a['tool_modes'] as Map).entries) {
      final m = mode('${e.value}');
      await perms.setTool(s.id, '${e.key}', m);
      changed.add('${e.key} → ${m?.label ?? 'server default'}');
    }
  }
  if (changed.isEmpty) {
    return const ToolOutput({
      'error': 'Nothing to change. Give url, transport, headers, remove_headers, default_mode, tool_modes, reconnect, '
          'refresh_sign_in or sign_out.',
    });
  }
  return ToolOutput({
    'server': s.id,
    'changed': changed,
    if (a['test'] != false) 'check': await diagnoseMcpServer(read, s),
  });
}

bool _sameMap(Map<String, String> x, Map<String, String> y) =>
    x.length == y.length && x.entries.every((e) => y[e.key] == e.value);

// ---- Skills: diagnose -------------------------------------------------------------

/// Paths a skill's instructions point at: `references/x.md`, `scripts/run.py`,
/// and relative markdown links.
final _bundledPath = RegExp(r'(?<![\w/.-])((?:references|reference|scripts|assets|templates|examples|resources)/[\w./-]+\w)');
final _mdLink = RegExp(r'\]\(([^)\s#]+)\)');

Future<ToolOutput> _skillDiagnose(ProviderReader read, Map<String, dynamic> a) async {
  final reg = read(aiProvider).skills;
  await reg.load();
  final only = _text(a, 'name');
  final all = reg.all;
  if (only != null && reg[Skill.sanitizeName(only)] == null) {
    return ToolOutput({'error': 'No skill "$only". Installed: ${all.isEmpty ? 'none' : all.map((s) => s.name).join(', ')}.'});
  }
  final targets = only == null ? all : [reg[Skill.sanitizeName(only)]!];
  final promptChars = all.where((s) => !s.deferred).fold<int>(0, (n, s) => n + s.name.length + s.description.length);
  if (targets.isEmpty) {
    return ToolOutput({
      'checked_at': DateTime.now().toIso8601String(),
      'skills': const [],
      'counts': _counts(const []),
      'note': 'No skills are installed. search_skills finds them and install_skill adds one.',
    });
  }
  final checkUpdates = a['check_updates'] == true;
  final skills = await Future.wait([for (final s in targets) diagnoseSkill(read, s, checkUpdates: checkUpdates)]);
  final general = <Map<String, dynamic>>[
    if (promptChars > 8000)
      _finding(CheckStatus.improve, 'Skill descriptions fill ${(promptChars / 4).round()} tokens of every chat',
          'Mark rarely used skills deferred with skill_setup; the assistant still finds them.'),
  ];
  // Two skills that describe themselves the same way confuse the choice.
  final seen = <String, String>{};
  for (final s in all) {
    final key = s.description.trim().toLowerCase();
    if (key.length < 12) continue;
    if (seen[key] case final other?) {
      general.add(_finding(CheckStatus.improve, '${s.name} and $other have the same description', 'Make each say when to use it.'));
    } else {
      seen[key] = s.name;
    }
  }
  return ToolOutput({
    'checked_at': DateTime.now().toIso8601String(),
    'installed': all.length,
    'prompt_tokens': (promptChars / 4).round(),
    'counts': _counts([...general, for (final s in skills) ...(s['findings'] as List).cast<Map<String, dynamic>>()]),
    if (general.isNotEmpty) 'general': general,
    'skills': skills,
  });
}

/// Everything about one installed skill: whether its description lets the
/// assistant pick it, its size, the files it mentions and bundles, recent
/// use and (with [checkUpdates]) whether its source has changed.
Future<Map<String, dynamic>> diagnoseSkill(ProviderReader read, Skill s, {bool checkUpdates = false}) async {
  final findings = <Map<String, dynamic>>[];
  final content = s.content;
  final lines = content.isEmpty ? 0 : '\n'.allMatches(content).length + 1;
  final bytes = s.files.values.fold<int>(0, (n, f) => n + f.length);
  final scripts = [for (final p in s.files.keys) if (RegExp(r'\.(py|sh|js|ts|mjs|rb|ps1)$').hasMatch(p)) p];
  final mentioned = <String>{
    for (final m in _bundledPath.allMatches(content)) m[1]!,
    for (final m in _mdLink.allMatches(content))
      if (!m[1]!.contains(':') && !m[1]!.startsWith('/') && m[1]!.contains('.')) m[1]!.replaceFirst(RegExp(r'^\./'), ''),
  };
  final missing = [for (final p in mentioned) if (!s.files.containsKey(p)) p];
  final out = <String, dynamic>{
    'name': s.name,
    'description': s.description,
    'source': s.source ?? 'inline',
    'deferred': s.deferred,
    'chars': content.length,
    'lines': lines,
    'est_tokens': (content.length / 4).round(),
    'files': s.files.keys.toList(),
    'files_bytes': bytes,
    if (scripts.isNotEmpty) 'scripts': scripts,
    if (missing.isNotEmpty) 'missing_files': missing,
  };

  if (content.trim().isEmpty) {
    findings.add(_finding(CheckStatus.fail, 'No instructions', 'Loading it gives the assistant nothing. Update it from its source or remove it.'));
  } else {
    findings.add(_finding(CheckStatus.ok, 'Instructions: $lines lines, about ${out['est_tokens']} tokens'));
    if (content.length > 40000) {
      findings.add(_finding(CheckStatus.warn, 'Very long instructions', 'Each load uses about ${out['est_tokens']} tokens. Move detail into reference files.'));
    } else if (lines > 500) {
      findings.add(_finding(CheckStatus.improve, 'Over 500 lines', 'Skills work best short, with detail in reference files.'));
    }
  }
  final d = s.description.trim();
  if (d.isEmpty) {
    findings.add(_finding(CheckStatus.warn, 'No description', 'The assistant picks skills by their description. Add one with skill_setup.'));
  } else if (d.length < 40) {
    findings.add(_finding(CheckStatus.improve, 'Short description', 'Say what it does and when to use it, so the assistant picks it at the right time.'));
  } else if (d.length > 1024) {
    findings.add(_finding(CheckStatus.warn, 'Description over 1024 characters', 'Some tools cut it off. Shorten it with skill_setup.'));
  } else if (!RegExp(r'\b(use (it )?(when|for|to)|when|whenever|if the user)\b', caseSensitive: false).hasMatch(d)) {
    findings.add(_finding(CheckStatus.improve, 'Description doesn\'t say when to use it', 'Add "Use when…" so it\'s picked at the right time.'));
  } else {
    findings.add(_finding(CheckStatus.ok, 'Clear description'));
  }
  if (missing.isNotEmpty) {
    findings.add(_finding(CheckStatus.warn, 'Mentions ${missing.length} file${missing.length == 1 ? '' : 's'} it doesn\'t have', missing.take(5).join(', ')));
  }
  if (scripts.isNotEmpty) {
    findings.add(_finding(CheckStatus.info, 'Bundles ${scripts.length} script${scripts.length == 1 ? '' : 's'}', 'Readable with read_skill_file; running one needs run_code or an E2B sandbox.'));
  }
  if (s.deferred) {
    findings.add(_finding(CheckStatus.info, 'Deferred', 'Not listed in every chat; the assistant finds it when a task needs it.'));
  }

  // Recent use.
  final month = read(usageProvider).where((e) => e.modality == Modality.skill && e.model == s.name && DateTime.now().difference(e.at).inDays < 30).toList();
  out['loads_30d'] = month.where((e) => e.tool == 'load_skill').length;
  out['failed_30d'] = month.where((e) => !e.ok).length;

  // Its source.
  final src = s.source;
  if (src == null || src == 'inline') {
    findings.add(_finding(CheckStatus.info, 'Installed from text', 'It has no source to update from.'));
  } else if (checkUpdates) {
    try {
      final at = src.indexOf('@');
      final remote = await _timed(read(aiProvider).skills.listRemote(src, skill: at < 0 && !src.startsWith('https://') ? s.name : null), 30);
      final match = remote.where((r) => r.name == s.name).firstOrNull ?? (remote.length == 1 ? remote.first : null);
      if (match == null) {
        out['update_available'] = false;
        findings.add(_finding(CheckStatus.warn, 'Gone from its source', '$src no longer has ${s.name}.'));
      } else {
        final differs = match.content != s.content || match.description != s.description || !_sameMap(match.files, s.files);
        out['update_available'] = differs;
        findings.add(differs
            ? _finding(CheckStatus.improve, 'Update available', 'Its source changed. Update with skill_setup update.')
            : _finding(CheckStatus.ok, 'Up to date with $src'));
      }
    } catch (e) {
      findings.add(_finding(CheckStatus.warn, 'Couldn\'t reach its source', _error(e)));
    }
  }

  findings.sort((x, y) => CheckStatus.values.byName('${x['status']}').rank.compareTo(CheckStatus.values.byName('${y['status']}').rank));
  out['status'] = _worst(findings).name;
  out['findings'] = findings;
  return out;
}

// ---- Skills: setup ----------------------------------------------------------------

Future<ToolOutput> _skillSetup(ProviderReader read, Map<String, dynamic> a) async {
  final reg = read(aiProvider).skills;
  await reg.load();
  final name = Skill.sanitizeName(_text(a, 'name') ?? '');
  var s = reg[name];
  if (s == null) {
    return ToolOutput({'error': 'No skill "${a['name']}". Installed: ${reg.all.isEmpty ? 'none' : reg.all.map((s) => s.name).join(', ')}.'});
  }
  final changed = <String>[];

  if (a['update'] == true) {
    final src = s.source;
    if (src == null || src == 'inline') throw ArgumentError('${s.name} was installed from text, so it has no source to update from.');
    final at = src.indexOf('@');
    final wasDeferred = s.deferred;
    final added = await reg.install(src, skill: at < 0 && !src.startsWith('https://') ? s.name : null);
    final fresh = added.where((x) => x.name == s!.name).firstOrNull ?? (added.length == 1 ? added.first : null);
    if (fresh == null) throw ArgumentError('$src no longer has ${s.name}.');
    // Extra skills the repo brought along weren't asked for.
    for (final x in added) {
      if (x.name != fresh.name && x.name != s.name) await reg.uninstall(x.name);
    }
    s = fresh.deferred == wasDeferred ? fresh : await reg.add(_copy(fresh, deferred: wasDeferred));
    changed.add('Updated from $src');
  }

  final newName = _text(a, 'new_name') == null ? null : Skill.sanitizeName(_text(a, 'new_name')!);
  if (newName != null && newName != s.name && reg[newName] != null) throw ArgumentError('A skill named $newName is already installed.');
  final files = {...s.files};
  if (a['files'] is Map) {
    for (final e in (a['files'] as Map).entries) {
      final p = '${e.key}'.trim().replaceFirst(RegExp(r'^\./'), '');
      if (p.isEmpty || p.contains('..')) continue;
      final v = '${e.value ?? ''}';
      if (v.isEmpty) {
        if (files.remove(p) != null) changed.add('Removed $p');
      } else {
        files[p] = v;
        changed.add('Wrote $p');
      }
    }
  }
  final description = _text(a, 'description');
  final instructions = a['instructions'] is String && (a['instructions'] as String).trim().isNotEmpty ? (a['instructions'] as String).trim() : null;
  final deferred = a['deferred'] is bool ? a['deferred'] as bool : null;
  if (description != null && description != s.description) changed.add('New description');
  if (instructions != null && instructions != s.content) changed.add('New instructions');
  if (deferred != null && deferred != s.deferred) changed.add(deferred ? 'Deferred' : 'Listed in every chat');
  if (newName != null && newName != s.name) changed.add('Renamed ${s.name} → $newName');

  final edited = _copy(s, name: newName, description: description, content: instructions, deferred: deferred, files: files);
  if (edited.name != s.name || edited.description != s.description || edited.content != s.content || edited.deferred != s.deferred || !_sameMap(edited.files, s.files)) {
    if (edited.name != s.name) await reg.uninstall(s.name);
    s = await reg.add(edited);
  }
  if (changed.isEmpty) {
    return const ToolOutput({'error': 'Nothing to change. Give update, new_name, description, instructions, deferred or files.'});
  }
  return ToolOutput({
    'skill': s.name,
    'changed': changed,
    if (a['test'] != false) 'check': await diagnoseSkill(read, s),
  });
}

Skill _copy(Skill s, {String? name, String? description, String? content, bool? deferred, Map<String, String>? files}) => Skill(
  name: name ?? s.name,
  description: description ?? s.description,
  content: content ?? s.content,
  deferred: deferred ?? s.deferred,
  files: files ?? s.files,
  source: s.source,
);
