import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_ai/omni_ai.dart' show McpServer, McpToolInfo, McpTransportKind;

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../ai/data/ai.dart';
import '../../integrations/mcp_oauth.dart';
import '../../integrations/mcp_permissions.dart';
import '../../pc/pc_screen.dart';
import 'capability_settings.dart' show showMcpEditSheet;

/// Opens an installed server's page.
Future<void> openMcpServer(BuildContext context, McpServer server) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => McpServerScreen(serverId: server.id)));

enum _Status { connecting, connected, signIn, failed }

/// One MCP server: whether it answers, how it signs in, what the assistant
/// may do with it, and every tool with its inputs. Connects on open.
class McpServerScreen extends ConsumerStatefulWidget {
  const McpServerScreen({super.key, required this.serverId});
  final String serverId;

  @override
  ConsumerState<McpServerScreen> createState() => _McpServerScreenState();
}

class _McpServerScreenState extends ConsumerState<McpServerScreen> {
  _Status _status = _Status.connecting;
  List<McpToolInfo> _tools = const [];
  String? _serverName;
  String? _error;
  McpOAuthPlan? _signIn;
  bool _oauth = false;
  int? _ms;
  PcLink? _pc;
  final _search = TextEditingController();

  McpServer? get _server => ref.read(aiProvider).mcp[widget.serverId];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    McpOAuth.isOAuth(widget.serverId).then((v) => mounted ? setState(() => _oauth = v) : null);
    final s = _server;
    if (s != null) {
      final link = PcLink.fromServer(s);
      link?.probe().then((info) {
        if (info != null && mounted) setState(() => _pc = link);
      });
    }
    _connect();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _status = _Status.connecting;
      _error = null;
    });
    final mcp = ref.read(aiProvider).mcp;
    final clock = Stopwatch()..start();
    try {
      await McpOAuth.refresh(mcp, widget.serverId);
      final client = await mcp.connect(widget.serverId);
      final tools = await client.listTools();
      if (!mounted) return;
      setState(() {
        _tools = [...tools]..sort((a, b) => a.name.compareTo(b.name));
        _serverName = client.serverName;
        _ms = clock.elapsedMilliseconds;
        _status = _Status.connected;
        _signIn = null;
      });
    } catch (e) {
      final current = mcp[widget.serverId];
      final plan = current?.url == null ? null : await McpOAuth.probe(current!.url!, headers: current.headers);
      if (plan != null && await McpOAuth.refresh(mcp, widget.serverId, force: true)) return _connect();
      if (!mounted) return;
      setState(() {
        _signIn = plan;
        _status = plan != null ? _Status.signIn : _Status.failed;
        _error = '$e'.replaceFirst(RegExp(r'^(\w*Exception):?\s*'), '');
      });
    }
  }

  Future<void> _runSignIn() async {
    final plan = _signIn;
    final server = _server;
    if (plan == null || server == null) return;
    try {
      if (await McpOAuth.signInAndInstall(context, ref.read(aiProvider).mcp, server, plan)) {
        if (!mounted) return;
        setState(() => _oauth = true);
        showSnack(context, 'Signed in to ${widget.serverId}');
        await _connect();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDelete(
      context,
      title: 'Remove ${widget.serverId}?',
      message: 'The assistant loses its tools. Its saved headers, sign-in and permissions are deleted from this phone.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await ref.read(aiProvider).mcp.uninstall(widget.serverId);
    await McpOAuth.forget(widget.serverId);
    await ref.read(mcpPermissionsProvider.notifier).forget(widget.serverId);
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, 'Removed ${widget.serverId}');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aiProvider).mcp[widget.serverId];
    ref.watch(mcpPermissionsProvider);
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This server was removed.')));
    }
    final perms = ref.read(mcpPermissionsProvider.notifier).of(s.id);
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _tools
        : _tools.where((t) => t.name.toLowerCase().contains(q) || t.description.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.id),
        actions: [
          IconButton(tooltip: 'Reconnect', onPressed: _status == _Status.connecting ? null : _connect, icon: const Icon(Icons.refresh_rounded)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                await showMcpEditSheet(context, server: s);
                if (mounted) await _connect();
              } else if (v == 'remove') {
                await _remove();
              } else if (v == 'copy' && s.url != null) {
                await Clipboard.setData(ClipboardData(text: s.url!));
                if (context.mounted) showSnack(context, 'Address copied');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
              if (s.url != null) const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Copy address'))),
              PopupMenuItem(
                value: 'remove',
                child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger), title: Text('Remove', style: TextStyle(color: AppColors.danger))),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _connect,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
          children: [
            _hero(context, s),
            if (_pc != null) ...[
              const SizedBox(height: Space.m),
              FilledButton.tonalIcon(
                onPressed: () => PcScreen.open(context, link: _pc),
                icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                label: const Text('Open PC screen'),
              ),
            ],
            if (_status == _Status.signIn) _signInCard(context),
            if (_status == _Status.failed) _failedCard(context),
            _label(context, 'Connection'),
            _card([
              _row(context, Icons.swap_horiz_rounded, 'Transport', switch (s.transport) {
                McpTransportKind.http => 'Streamable HTTP',
                McpTransportKind.sse => 'Server-sent events (SSE)',
                _ => s.transport.name,
              }),
              if (s.url != null) _row(context, Icons.link_rounded, 'Address', s.url!, mono: true),
              if (s.command != null) _row(context, Icons.terminal_rounded, 'Command', [s.command!, ...s.args].join(' '), mono: true),
              _row(
                context,
                _oauth ? Icons.verified_user_outlined : Icons.key_outlined,
                'Sign-in',
                _oauth
                    ? 'Signed in with OAuth · token refreshes itself'
                    : s.headers.isEmpty
                    ? 'None (public server)'
                    : 'Headers: ${s.headers.keys.join(', ')}',
              ),
            ]),
            _label(context, 'Permissions'),
            _permissionsCard(context, s, perms),
            _label(context, _status == _Status.connected ? 'Tools · ${_tools.length}' : 'Tools'),
            if (_status == _Status.connected && _tools.length > 6)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search ${_tools.length} tools',
                    suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: _search.clear),
                  ),
                ),
              ),
            if (_status == _Status.connecting)
              const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_status != _Status.connected)
              Text('Connect to see the tools it offers.', style: context.text.bodySmall)
            else if (_tools.isEmpty)
              Text('This server offers no tools.', style: context.text.bodySmall)
            else
              for (final t in shown)
                _ToolTile(
                  key: ValueKey(t.name),
                  tool: t,
                  mode: perms.tools[t.name],
                  inherited: perms.defaultMode,
                  onMode: (m) => ref.read(mcpPermissionsProvider.notifier).setTool(s.id, t.name, m),
                ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, McpServer s) {
    final (color, label, icon) = switch (_status) {
      _Status.connecting => (AppColors.text3, 'Connecting…', Icons.sync_rounded),
      _Status.connected => (AppColors.success, 'Connected${_ms == null ? '' : ' · ${_ms}ms'}', Icons.check_circle_rounded),
      _Status.signIn => (AppColors.warning, 'Needs sign-in', Icons.lock_outline_rounded),
      _Status.failed => (AppColors.danger, 'Can\'t connect', Icons.error_outline_rounded),
    };
    final host = Uri.tryParse(s.url ?? '')?.host ?? s.command ?? '';
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.tint.withValues(alpha: AppColors.isLight ? 0.10 : 0.16), AppColors.surface],
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
                alignment: Alignment.center,
                child: Text(
                  s.id.characters.first.toUpperCase(),
                  style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.tint),
                ),
              ),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2.5)),
                ),
              ),
            ],
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_serverName?.isNotEmpty == true ? _serverName! : s.id, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (host.isNotEmpty) Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(label, color, icon: icon),
                    if (_status == _Status.connected) _Pill('${_tools.length} tool${_tools.length == 1 ? '' : 's'}', AppColors.text2, icon: Icons.handyman_outlined),
                    if (_oauth) _Pill('OAuth', AppColors.tint, icon: Icons.verified_user_outlined),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signInCard(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in to use this server', style: context.text.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${_signIn!.resourceName ?? widget.serverId} uses OAuth. You\'ll sign in on ${_signIn!.host} inside the app; '
            'Triangle keeps only the token it gets back, on this phone.'
            '${_signIn!.scopes.isEmpty ? '' : ' It asks for: ${_signIn!.scopes.join(', ')}.'}',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.m),
          FilledButton.icon(onPressed: _runSignIn, icon: const Icon(Icons.login_rounded, size: 18), label: Text('Sign in with ${_signIn!.host}')),
        ],
      ),
    ),
  );

  Widget _failedCard(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Couldn\'t connect', style: context.text.titleSmall?.copyWith(color: AppColors.danger)),
          const SizedBox(height: 4),
          SelectableText(_error ?? '', style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          Row(
            children: [
              OutlinedButton.icon(onPressed: _connect, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
              const SizedBox(width: Space.s),
              TextButton(
                onPressed: () async {
                  final s = _server;
                  if (s == null) return;
                  await showMcpEditSheet(context, server: s);
                  if (mounted) await _connect();
                },
                child: const Text('Edit server'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _permissionsCard(BuildContext context, McpServer s, McpServerPermissions perms) {
    final mode = perms.defaultMode;
    final overrides = perms.tools.length;
    return _card([
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('When the assistant uses its tools', style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(
              switch (mode) {
                null => s.approval.kind == 'always'
                    ? 'Each call asks first (set when the server was added).'
                    : 'Follows your approval setting in Settings → Approvals.',
                final m => '${m.explanation}, unless a tool below says otherwise.',
              },
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.m),
            SegmentedButton<McpToolMode?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Default')),
                ButtonSegment(value: McpToolMode.ask, label: Text('Ask')),
                ButtonSegment(value: McpToolMode.allow, label: Text('Allow')),
                ButtonSegment(value: McpToolMode.off, label: Text('Off')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => ref.read(mcpPermissionsProvider.notifier).setDefault(s.id, v.first),
            ),
            if (overrides > 0) ...[
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Expanded(child: Text('$overrides tool${overrides == 1 ? ' has its' : 's have their'} own setting', style: context.text.labelSmall)),
                  TextButton(
                    onPressed: () async {
                      for (final t in perms.tools.keys.toList()) {
                        await ref.read(mcpPermissionsProvider.notifier).setTool(s.id, t, null);
                      }
                    },
                    child: const Text('Reset all'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.xs),
            Text(
              'Even when allowed, a call waits for you if the assistant has just read messages, emails or pages from '
              'others in that run, since they could try to steer it.',
              style: context.text.labelSmall,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: Space.xl, bottom: Space.s, left: 4),
    child: Text(text.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, indent: Space.l, color: AppColors.line),
          c,
        ],
      ],
    ),
  );

  Widget _row(BuildContext context, IconData icon, String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.text3),
        const SizedBox(width: Space.m),
        SizedBox(width: 84, child: Text(label, style: context.text.bodySmall)),
        Expanded(
          child: SelectableText(
            value,
            style: context.text.bodyMedium?.copyWith(fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12.5 : null),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

Color _modeColor(McpToolMode? m) => switch (m) {
  McpToolMode.allow => AppColors.success,
  McpToolMode.ask => AppColors.warning,
  McpToolMode.off => AppColors.danger,
  null => AppColors.text3,
};

/// A tool: name, what it does and its permission; opens to its inputs.
class _ToolTile extends StatefulWidget {
  const _ToolTile({super.key, required this.tool, required this.mode, required this.inherited, required this.onMode});
  final McpToolInfo tool;
  final McpToolMode? mode;
  final McpToolMode? inherited;
  final ValueChanged<McpToolMode?> onMode;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _open = false;
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    final effective = widget.mode ?? widget.inherited;
    final props = (t.inputSchema['properties'] as Map?) ?? const {};
    final required = {for (final r in (t.inputSchema['required'] as List? ?? const [])) '$r'};
    final off = effective == McpToolMode.off;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: context.text.titleSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 13.5,
                              color: off ? AppColors.text3 : null,
                              decoration: off ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (t.description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              t.description,
                              maxLines: _open ? null : 2,
                              overflow: _open ? null : TextOverflow.ellipsis,
                              style: context.text.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Permission',
                      onSelected: (v) => widget.onMode(McpToolMode.values.asNameMap()[v]),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'default',
                          child: Text('Like the server (${widget.inherited?.label ?? 'approval setting'})'),
                        ),
                        for (final m in McpToolMode.values) PopupMenuItem(value: m.name, child: Text(m.label)),
                      ],
                      child: Container(
                        margin: const EdgeInsets.only(left: Space.s, right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _modeColor(effective).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: widget.mode == null ? null : Border.all(color: _modeColor(effective).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              effective?.label ?? 'Default',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _modeColor(effective)),
                            ),
                            Icon(Icons.arrow_drop_down_rounded, size: 16, color: _modeColor(effective)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_open && props.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final k in props.keys.take(6)) _ParamChip('$k', required: required.contains('$k')),
                      if (props.length > 6) _ParamChip('+${props.length - 6}', required: false),
                    ],
                  ),
                ],
                if (_open) ...[
                  const SizedBox(height: Space.m),
                  if (props.isEmpty)
                    Text('Takes no inputs.', style: context.text.labelSmall)
                  else
                    for (final e in props.entries) _param(context, '${e.key}', e.value is Map ? e.value as Map : const {}, required.contains('${e.key}')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() => _raw = !_raw),
                      icon: Icon(_raw ? Icons.expand_less_rounded : Icons.data_object_rounded, size: 16),
                      label: Text(_raw ? 'Hide schema' : 'Raw schema'),
                    ),
                  ),
                  if (_raw)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(right: Space.s),
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(t.inputSchema),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _param(BuildContext context, String name, Map p, bool required) {
    final type = p['type'] is List ? (p['type'] as List).join(' | ') : '${p['type'] ?? (p['enum'] != null ? 'enum' : 'any')}';
    final enums = p['enum'] is List ? (p['enum'] as List).map((e) => '$e').join(', ') : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s, right: Space.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w700)),
                    Text(type, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.tint)),
                    if (required) Text('required', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.warning)),
                  ],
                ),
                if ('${p['description'] ?? ''}'.isNotEmpty) Text('${p['description']}', style: context.text.bodySmall),
                if (enums != null) Text('One of: $enums', style: context.text.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip(this.text, {required this.required});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6)),
    child: Text(
      required ? '$text*' : text,
      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: required ? AppColors.text : AppColors.text2),
    ),
  );
}
