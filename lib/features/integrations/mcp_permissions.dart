import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the assistant may do with an MCP tool.
enum McpToolMode {
  ask('Ask first', 'Each call waits for your approval'),
  allow('Allow', 'Runs without asking'),
  off('Off', 'The assistant can\'t use it');

  const McpToolMode(this.label, this.explanation);
  final String label;
  final String explanation;
}

/// One server's permissions: a default for all its tools (null follows the
/// app's approval setting) and per-tool overrides.
@immutable
class McpServerPermissions {
  const McpServerPermissions({this.defaultMode, this.tools = const {}});
  final McpToolMode? defaultMode;
  final Map<String, McpToolMode> tools;

  McpToolMode? modeFor(String tool) => tools[tool] ?? defaultMode;

  bool get isEmpty => defaultMode == null && tools.isEmpty;

  Map<String, dynamic> toJson() => {
    'default': ?defaultMode?.name,
    if (tools.isNotEmpty) 'tools': {for (final e in tools.entries) e.key: e.value.name},
  };

  factory McpServerPermissions.fromJson(Map j) => McpServerPermissions(
    defaultMode: McpToolMode.values.asNameMap()[j['default']],
    tools: {
      for (final e in (j['tools'] as Map? ?? const {}).entries)
        if (McpToolMode.values.asNameMap()[e.value] case final m?) '${e.key}': m,
    },
  );
}

/// Per-server, per-tool permissions for MCP tools, kept on the phone.
/// The chat controller asks [modeFor] before each `mcp_call_tool`: Allow
/// skips the approval card, Ask always shows it, Off refuses the call (and
/// hides the tool from `mcp_list_tools`). Nothing set follows the app's
/// approval setting, as before.
class McpPermissionStore extends Notifier<Map<String, McpServerPermissions>> {
  static const _key = 'mcp_permissions.v1';

  late Future<void> ready;

  @override
  Map<String, McpServerPermissions> build() {
    ready = _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      state = {for (final e in j.entries) '${e.key}': McpServerPermissions.fromJson(e.value as Map)};
    } catch (e) {
      debugPrint('[McpPermissions] $e');
    }
  }

  Future<void> _save() async => (await SharedPreferences.getInstance()).setString(
    _key,
    jsonEncode({
      for (final e in state.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    }),
  );

  McpServerPermissions of(String server) => state[server] ?? const McpServerPermissions();

  /// The mode for [tool] on [server]; null follows the app's approvals.
  McpToolMode? modeFor(String server, String tool) => state[server]?.modeFor(tool);

  Future<void> setDefault(String server, McpToolMode? mode) async {
    await ready;
    final p = of(server);
    state = {...state, server: McpServerPermissions(defaultMode: mode, tools: p.tools)};
    await _save();
  }

  /// Sets [tool]'s own mode; null makes it follow the server's default.
  Future<void> setTool(String server, String tool, McpToolMode? mode) async {
    await ready;
    final p = of(server);
    final tools = {...p.tools};
    if (mode == null) {
      tools.remove(tool);
    } else {
      tools[tool] = mode;
    }
    state = {...state, server: McpServerPermissions(defaultMode: p.defaultMode, tools: tools)};
    await _save();
  }

  Future<void> forget(String server) async {
    await ready;
    state = {...state}..remove(server);
    await _save();
  }
}

final mcpPermissionsProvider = NotifierProvider<McpPermissionStore, Map<String, McpServerPermissions>>(McpPermissionStore.new);
