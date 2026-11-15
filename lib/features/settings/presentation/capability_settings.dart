import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_ai/omni_ai.dart'
    show ApprovalPolicy, McpCatalogHit, McpInput, McpRegistry, McpServer, McpTransportKind, Skill, SkillHit, SkillRegistry;

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../ai/data/ai.dart';
import '../../integrations/mcp_oauth.dart';
import '../../telegram/data/telegram_tools.dart' show ToolCategory;
import 'mcp_server_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart' show FeatureTools;

/// Settings → MCP & Skills: servers the assistant can call through the
/// Model Context Protocol, and skills (SKILL.md instructions) it can load.
class McpSkillsSettingsScreen extends StatelessWidget {
  const McpSkillsSettingsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('MCP & Skills'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'MCP servers'),
            Tab(text: 'Skills'),
          ],
        ),
      ),
      body: const TabBarView(children: [McpTab(), SkillsTab()]),
    ),
  );
}

/// A settings column the width of the other settings pages.
class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl), children: children),
    ),
  );
}

/// A search field that runs on submit, with a spinner while it does.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hint, required this.busy, required this.onSearch});
  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => onSearch(),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: busy
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward_rounded), onPressed: onSearch),
    ),
  );
}

/// A one-line message inside a card: empty lists, errors.
class _CardNote extends StatelessWidget {
  const _CardNote(this.text, {this.icon = Icons.info_outline_rounded, this.danger = false});
  final String text;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: lead(Icon(icon, color: danger ? AppColors.danger : AppColors.text3)),
    title: Text(text, style: context.text.bodySmall?.copyWith(color: danger ? AppColors.danger : null)),
  );
}

/// A sheet's title, with an icon and a subtitle.
class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
        child: Icon(icon, color: AppColors.text2),
      ),
      const SizedBox(width: Space.m),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleMedium),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    ],
  );
}

/// A label and a value, for the facts at the top of a details sheet.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: Text(label, style: context.text.bodySmall)),
        Expanded(
          child: SelectableText(
            value,
            style: context.text.bodyMedium?.copyWith(fontFamily: mono ? 'monospace' : null, fontSize: mono ? 13 : null),
          ),
        ),
      ],
    ),
  );
}

/// A rounded panel for long text in a sheet.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Space.l),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
    child: child,
  );
}

Text _sectionLabel(BuildContext context, String text) => Text(text.toUpperCase(), style: context.text.labelSmall);

String _errorText(Object e) => '$e'.replaceFirst(RegExp(r'^(\w*Exception|ArgumentError|Invalid argument\(s\)):?\s*'), '');

// ─── MCP ────────────────────────────────────────────────────────────────

class McpTab extends ConsumerStatefulWidget {
  const McpTab({super.key});

  @override
  ConsumerState<McpTab> createState() => _McpTabState();
}

class _McpTabState extends ConsumerState<McpTab> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  List<McpCatalogHit>? _hits;
  String? _searchError;
  bool _searching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ref.read(aiProvider).mcp.load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isNotEmpty && q.length < 3) {
      setState(() => _searchError = 'Type at least 3 characters.');
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final hits = await ref.read(aiProvider).mcp.search(q, limit: 30);
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _searchError = _errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mcp = ref.watch(aiProvider).mcp;
    // A no-op once loaded; a new client (after a restore) reads its servers.
    unawaited(mcp.load());
    return _Page(
      children: [
        const SettingsHeader('Installed'),
        ListenableBuilder(
          listenable: mcp,
          builder: (context, _) {
            final servers = mcp.servers..sort((a, b) => a.id.compareTo(b.id));
            return SettingsCard(
              children: [
                if (servers.isEmpty) const _CardNote('No servers yet. Find one below, or add one by its address.', icon: Icons.hub_outlined),
                for (final s in servers) ...[
                  ListTile(
                    leading: lead(const Icon(Icons.hub_rounded)),
                    title: Text(s.id),
                    subtitle: Text(
                      '${s.transport.name.toUpperCase()} · ${Uri.tryParse(s.url ?? '')?.host ?? s.command ?? ''}'
                      '${s.approval.kind == 'always' ? ' · asks first' : ''}',
                      style: context.text.bodySmall,
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => showMcpServerSheet(context, s),
                  ),
                  const Divider(indent: 56),
                ],
                ListTile(
                  leading: lead(const Icon(Icons.add_link_rounded)),
                  title: const Text('Add by address'),
                  subtitle: Text('A Streamable HTTP or SSE server URL', style: context.text.bodySmall),
                  onTap: () => showMcpEditSheet(context),
                ),
              ],
            );
          },
        ),
        const SettingsHeader('Find servers', note: 'Official MCP Registry'),
        _SearchField(controller: _query, hint: 'GitHub, Notion, weather…', busy: _searching, onSearch: _search),
        const SizedBox(height: Space.s),
        if (_searchError != null)
          SettingsCard(children: [_CardNote(_searchError!, icon: Icons.error_outline_rounded, danger: true)])
        else if (_hits case final hits?)
          SettingsCard(
            children: [
              if (hits.isEmpty) const _CardNote('Nothing found. Try another word.'),
              for (final (i, h) in hits.indexed) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  leading: lead(Icon(h.hasRemote ? Icons.cloud_outlined : Icons.terminal_rounded)),
                  title: Text(h.name.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    h.description.isEmpty ? h.name : h.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                  trailing: ListenableBuilder(
                    listenable: mcp,
                    builder: (_, _) => mcp[h.suggestedId] != null
                        ? Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                        : Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  ),
                  onTap: () => _showCatalogSheet(context, h),
                ),
              ],
            ],
          ),
        const SettingsHeader('Assistant tools'),
        const FeatureTools(category: ToolCategory.mcp),
      ],
    );
  }
}

/// An installed server's page: status, sign-in, permissions and tools.
Future<void> showMcpServerSheet(BuildContext context, McpServer server) => openMcpServer(context, server);

/// Adds or edits a server by its address.
Future<void> showMcpEditSheet(BuildContext context, {McpServer? server, McpServer? draft}) =>
    showFormSheet<void>(context, builder: (_) => _McpEditSheet(server: server, draft: draft));

class _McpEditSheet extends ConsumerStatefulWidget {
  const _McpEditSheet({this.server, this.draft});

  /// The installed server being edited.
  final McpServer? server;

  /// Values to start a new server from.
  final McpServer? draft;

  @override
  ConsumerState<_McpEditSheet> createState() => _McpEditSheetState();
}

class _HeaderRow {
  _HeaderRow(String name, String value) : name = TextEditingController(text: name), value = TextEditingController(text: value);
  final TextEditingController name;
  final TextEditingController value;
  bool hidden = true;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _McpEditSheetState extends ConsumerState<_McpEditSheet> {
  late final McpServer? _start = widget.server ?? widget.draft;
  late final _id = TextEditingController(text: _start?.id ?? '');
  late final _url = TextEditingController(text: _start?.url ?? '');
  late McpTransportKind _transport = _start?.transport == McpTransportKind.sse ? McpTransportKind.sse : McpTransportKind.http;
  late bool _askFirst = _start?.approval.kind == 'always';
  late final List<_HeaderRow> _headers = [for (final e in (_start?.headers ?? const {}).entries) _HeaderRow(e.key, e.value)];
  String? _idError;
  String? _urlError;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.server != null;

  @override
  void dispose() {
    _id.dispose();
    _url.dispose();
    for (final h in _headers) {
      h.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    final raw = _url.text.trim();
    final uri = Uri.tryParse(raw);
    final mcp = ref.read(aiProvider).mcp;
    setState(() {
      _idError = !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_\-]{0,47}$').hasMatch(id)
          ? 'Letters, digits, - and _, up to 48.'
          : (!_editing && mcp[id] != null ? 'A server with this name exists.' : null);
      _urlError = uri == null || !uri.hasAuthority || !(uri.scheme == 'https' || uri.scheme == 'http')
          ? 'A full https:// address.'
          : (uri.scheme == 'http' && !McpRegistry.isLocalHost(uri.host) ? 'Plain http only on this network; use https.' : null);
      _error = null;
    });
    if (_idError != null || _urlError != null) return;
    final headers = {
      for (final h in _headers)
        if (h.name.text.trim().isNotEmpty) h.name.text.trim(): h.value.text.trim(),
    };
    final approval = _askFirst ? ApprovalPolicy.always : ApprovalPolicy.never;
    final server = _transport == McpTransportKind.sse
        ? McpServer.sse(id, url: raw, headers: headers, approval: approval)
        : McpServer.http(id, url: raw, headers: headers, approval: approval);
    setState(() => _saving = true);
    try {
      if (_editing && widget.server!.id != id) await mcp.uninstall(widget.server!.id);
      await mcp.install(server);
      // Servers behind OAuth answer 401 and point at their sign-in: run it
      // now, in the app, instead of failing on the first tool call.
      final plan = await McpOAuth.probe(raw, headers: headers);
      var signedIn = false;
      if (plan != null && mounted) {
        try {
          signedIn = await McpOAuth.signInAndInstall(context, mcp, server, plan);
        } catch (e) {
          if (mounted) setState(() => _error = 'Saved, but sign-in failed: ${_errorText(e)}');
          return;
        }
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(
          context,
          plan != null && !signedIn
              ? 'Saved $id. Open it and tap Connect to sign in.'
              : '${_editing ? 'Saved' : 'Added'} $id${signedIn ? ' and signed in' : ''}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetTitle(
        icon: Icons.add_link_rounded,
        title: _editing ? 'Edit ${widget.server!.id}' : 'Add an MCP server',
        subtitle: 'Remote servers only: this phone can\'t run local commands.',
      ),
      const SizedBox(height: Space.m),
      const _McpExplainer(),
      const SizedBox(height: Space.l),
      _FormStep(
        number: 1,
        title: 'How it talks',
        body: _transport == McpTransportKind.http ? 'Most servers. Addresses usually end in /mcp.' : 'Older servers whose address ends in /sse.',
      ),
      const SizedBox(height: Space.s),
      SegmentedButton<McpTransportKind>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: McpTransportKind.http, label: Text('Streamable HTTP')),
          ButtonSegment(value: McpTransportKind.sse, label: Text('SSE')),
        ],
        selected: {_transport},
        onSelectionChanged: (v) => setState(() => _transport = v.first),
      ),
      const SizedBox(height: Space.l),
      const _FormStep(
        number: 2,
        title: 'Where it is',
        body: 'A short name, and the https address from its docs.',
      ),
      const SizedBox(height: Space.s),
      TextField(
        controller: _id,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'github',
          errorText: _idError,
        ),
      ),
      const SizedBox(height: Space.s),
      TextField(
        controller: _url,
        autocorrect: false,
        keyboardType: TextInputType.url,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        decoration: InputDecoration(labelText: 'Address', hintText: 'https://example.com/mcp', errorText: _urlError),
      ),
      const SizedBox(height: Space.l),
      const _FormStep(
        number: 3,
        title: 'How it signs in',
        body: 'Leave empty for public or sign-in servers (you sign in after adding). Add a header only for an API key.',
      ),
      const SizedBox(height: Space.xs),
      Row(
        children: [
          Expanded(child: _sectionLabel(context, 'Headers')),
          TextButton.icon(
            onPressed: () => setState(() => _headers.add(_HeaderRow(_headers.isEmpty ? 'Authorization' : '', _headers.isEmpty ? 'Bearer ' : ''))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add header'),
          ),
        ],
      ),
      if (_headers.isEmpty)
        const SizedBox.shrink(),
      for (final h in _headers)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(controller: h.name, autocorrect: false, decoration: const InputDecoration(hintText: 'Name')),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: h.value,
                  autocorrect: false,
                  obscureText: h.hidden,
                  decoration: InputDecoration(
                    hintText: 'Value',
                    suffixIcon: IconButton(
                      tooltip: h.hidden ? 'Show' : 'Hide',
                      icon: Icon(h.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      onPressed: () => setState(() => h.hidden = !h.hidden),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove header',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _headers.remove(h..dispose())),
              ),
            ],
          ),
        ),
      const SizedBox(height: Space.l),
      const _FormStep(
        number: 4,
        title: 'What the assistant may do',
        body: 'Fine-tune each tool later on the server\'s page.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ask before each tool call'),
        subtitle: Text('Every call to this server waits for your OK.', style: context.text.bodySmall),
        value: _askFirst,
        onChanged: (v) => setState(() => _askFirst = v),
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.s),
        Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
      ],
      const SizedBox(height: Space.m),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_editing ? 'Save' : 'Add server'),
      ),
    ],
  );
}

/// A registry server: what it is, the values it needs, install.
Future<void> _showCatalogSheet(BuildContext context, McpCatalogHit hit) =>
    showAppSheet<void>(context, initialSize: 0.75, builder: (context, scroll) => _CatalogSheet(hit: hit, scroll: scroll));

class _CatalogSheet extends ConsumerStatefulWidget {
  const _CatalogSheet({required this.hit, required this.scroll});
  final McpCatalogHit hit;
  final ScrollController scroll;

  @override
  ConsumerState<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends ConsumerState<_CatalogSheet> {
  late final _id = TextEditingController(text: widget.hit.suggestedId);
  late final List<McpInput> _inputs = widget.hit.inputs;
  late final _values = {for (final i in _inputs) i.name: TextEditingController()};
  String? _error;
  bool _installing = false;

  @override
  void dispose() {
    _id.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _install() async {
    final mcp = ref.read(aiProvider).mcp;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      final values = {
        for (final e in _values.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      };
      final server = widget.hit.toServer(id: _id.text.trim(), headers: values);
      await mcp.install(server);
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Installed ${server.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final h = widget.hit;
    final remote = h.remotes.where((r) => r.url.isNotEmpty).firstOrNull;
    final installed = ref.watch(aiProvider).mcp[h.suggestedId] != null;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      children: [
        _SheetTitle(icon: remote != null ? Icons.cloud_outlined : Icons.terminal_rounded, title: h.name.split('/').last, subtitle: h.name),
        if (h.description.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(h.description, style: context.text.bodyMedium),
        ],
        const SizedBox(height: Space.l),
        if (h.version.isNotEmpty) _Fact('Version', h.version),
        if (remote != null) ...[
          _Fact('Transport', remote.type),
          _Fact('Address', remote.url, mono: true),
        ],
        if (h.repositoryUrl != null) _Fact('Source', h.repositoryUrl!, mono: true),
        const SizedBox(height: Space.l),
        if (remote == null)
          _Panel(
            child: Row(
              children: [
                Icon(Icons.phonelink_off_rounded, color: AppColors.text2),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    'This server runs as a local program on a computer, which this phone can\'t start. '
                    'If it is hosted somewhere, add it by its address instead.',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          )
        else ...[
          TextField(
            controller: _id,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Name in Triangle'),
          ),
          for (final i in _inputs) ...[
            const SizedBox(height: Space.s),
            TextField(
              controller: _values[i.name],
              autocorrect: false,
              obscureText: i.isSecret,
              decoration: InputDecoration(
                labelText: '${i.name}${i.isRequired ? '' : ' (if you have one)'}',
                helperText: i.description.isEmpty ? null : i.description,
                helperMaxLines: 3,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.m),
            Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: Space.l),
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(installed ? Icons.refresh_rounded : Icons.download_rounded),
            label: Text(installed ? 'Reinstall' : 'Install'),
          ),
          const SizedBox(height: Space.s),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showMcpEditSheet(
                context,
                draft: _transportOf(remote.type) == McpTransportKind.sse
                    ? McpServer.sse(_safeId(_id.text), url: remote.url)
                    : McpServer.http(_safeId(_id.text), url: remote.url),
              );
            },
            child: const Text('Set it up by hand'),
          ),
        ],
      ],
    );
  }

  static McpTransportKind _transportOf(String type) => type.toLowerCase() == 'sse' ? McpTransportKind.sse : McpTransportKind.http;

  static String _safeId(String id) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_\-]{0,47}$').hasMatch(id.trim()) ? id.trim() : 'mcp';
}

// ─── Skills ─────────────────────────────────────────────────────────────

class SkillsTab extends ConsumerStatefulWidget {
  const SkillsTab({super.key});

  @override
  ConsumerState<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<SkillsTab> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  List<SkillHit>? _hits;
  String? _searchError;
  bool _searching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ref.read(aiProvider).skills.load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final hits = await ref.read(aiProvider).skills.search(q, limit: 30);
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _searchError = _errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final skills = ref.watch(aiProvider).skills;
    unawaited(skills.load());
    return _Page(
      children: [
        const SettingsHeader('Installed'),
        ListenableBuilder(
          listenable: skills,
          builder: (context, _) {
            final all = skills.all..sort((a, b) => a.name.compareTo(b.name));
            return SettingsCard(
              children: [
                if (all.isEmpty) const _CardNote('No skills yet. Find one below, or install one from GitHub.', icon: Icons.auto_stories_outlined),
                for (final s in all) ...[
                  ListTile(
                    leading: lead(const Icon(Icons.auto_stories_rounded)),
                    title: Text(s.name),
                    subtitle: Text(
                      s.description.isEmpty ? (s.source ?? 'Added here') : s.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () => showSkillSheet(context, s),
                  ),
                  const Divider(indent: 56),
                ],
                ListTile(
                  leading: lead(const Icon(Icons.add_rounded)),
                  title: const Text('Install from a source'),
                  subtitle: Text('owner/repo, a GitHub link, or a SKILL.md address', style: context.text.bodySmall),
                  onTap: () => showFormSheet<void>(context, builder: (_) => const _SkillSourceSheet()),
                ),
              ],
            );
          },
        ),
        const SettingsHeader('Find skills', note: 'Skyll · skills.sh'),
        _SearchField(controller: _query, hint: 'PDF, slides, code review…', busy: _searching, onSearch: _search),
        const SizedBox(height: Space.s),
        if (_searchError != null)
          SettingsCard(children: [_CardNote(_searchError!, icon: Icons.error_outline_rounded, danger: true)])
        else if (_hits case final hits?)
          SettingsCard(
            children: [
              if (hits.isEmpty) const _CardNote('Nothing found. Try another word.'),
              for (final (i, h) in hits.indexed) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  leading: lead(const Icon(Icons.auto_stories_outlined)),
                  title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [if (h.description.isNotEmpty) h.description else h.source, if (h.installs > 0) '${_count(h.installs)} installs']
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                  trailing: ListenableBuilder(
                    listenable: skills,
                    builder: (_, _) => skills[Skill.sanitizeName(h.name)] != null
                        ? Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                        : Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  ),
                  onTap: () => showSkillPreviewSheet(context, hit: h),
                ),
              ],
            ],
          ),
        const SettingsHeader('Assistant tools'),
        const FeatureTools(category: ToolCategory.skills),
      ],
    );
  }

  static String _count(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';
}

/// One skill's details: description, source, instructions and files.
class _SkillDetails extends StatelessWidget {
  const _SkillDetails({required this.skill});
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final s = skill;
    final files = s.files.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.description.isNotEmpty) Text(s.description, style: context.text.bodyMedium),
        const SizedBox(height: Space.m),
        if (s.source != null) _Fact('Source', s.source!, mono: true),
        _Fact('Size', '${_kb(s.content.length)} instructions${files.isEmpty ? '' : ' · ${files.length} files'}'),
        _Fact('Loading', s.deferred ? 'When the task needs it' : 'Always in the prompt'),
        const SizedBox(height: Space.l),
        _sectionLabel(context, 'Instructions'),
        const SizedBox(height: Space.s),
        _Panel(child: MarkdownBody(data: s.content, selectable: true)),
        if (files.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          _sectionLabel(context, 'Files · ${files.length}'),
          const SizedBox(height: Space.s),
          SettingsCard(
            children: [
              for (final (i, f) in files.indexed) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  dense: true,
                  leading: lead(Icon(_fileIcon(f), size: 20)),
                  title: Text(f, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  subtitle: Text(_kb(s.files[f]!.length), style: context.text.bodySmall),
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                  onTap: () => showSkillFileSheet(context, name: f, content: s.files[f]!),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static String _kb(int chars) => chars < 1024 ? '$chars B' : '${(chars / 1024).toStringAsFixed(1)} KB';

  static IconData _fileIcon(String f) => switch (f.split('.').last.toLowerCase()) {
    'md' || 'txt' => Icons.description_outlined,
    'py' || 'js' || 'ts' || 'sh' || 'dart' => Icons.code_rounded,
    'json' || 'yaml' || 'yml' || 'toml' => Icons.data_object_rounded,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// An installed skill: its details, and remove.
Future<void> showSkillSheet(BuildContext context, Skill skill) => showAppSheet<void>(
  context,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      children: [
        _SheetTitle(icon: Icons.auto_stories_rounded, title: skill.name, subtitle: 'Installed'),
        const SizedBox(height: Space.l),
        _SkillDetails(skill: skill),
        const SizedBox(height: Space.xl),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () async {
            final ok = await confirmDelete(
              context,
              title: 'Remove ${skill.name}?',
              message: 'The assistant can no longer load it. You can install it again later.',
              action: 'Remove',
            );
            if (!ok || !context.mounted) return;
            await ref.read(aiProvider).skills.uninstall(skill.name);
            if (context.mounted) {
              Navigator.pop(context);
              showSnack(context, 'Removed ${skill.name}');
            }
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Remove skill'),
        ),
      ],
    ),
  ),
);

/// One bundled file, readable and copyable.
Future<void> showSkillFileSheet(BuildContext context, {required String name, required String content}) => showAppSheet<void>(
  context,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
    children: [
      Row(
        children: [
          Expanded(child: Text(name, style: context.text.titleMedium?.copyWith(fontFamily: 'monospace'))),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              showSnack(context, 'Copied $name');
            },
          ),
        ],
      ),
      const SizedBox(height: Space.m),
      _Panel(
        child: name.toLowerCase().endsWith('.md')
            ? MarkdownBody(data: content, selectable: true)
            : SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4)),
      ),
    ],
  ),
);

/// Skills fetched from a search hit or a source, shown before installing.
Future<void> showSkillPreviewSheet(BuildContext context, {SkillHit? hit, String? source, String? skill}) => showAppSheet<void>(
  context,
  builder: (context, scroll) => _SkillPreviewSheet(hit: hit, source: source, skill: skill, scroll: scroll),
);

class _SkillPreviewSheet extends ConsumerStatefulWidget {
  const _SkillPreviewSheet({this.hit, this.source, this.skill, required this.scroll});
  final SkillHit? hit;
  final String? source;
  final String? skill;
  final ScrollController scroll;

  @override
  ConsumerState<_SkillPreviewSheet> createState() => _SkillPreviewSheetState();
}

class _SkillPreviewSheetState extends ConsumerState<_SkillPreviewSheet> {
  late Future<List<Skill>> _preview = _load();
  int _selected = 0;
  bool _installing = false;
  String? _error;

  SkillRegistry get _registry => ref.read(aiProvider).skills;

  Future<List<Skill>> _load() {
    final hit = widget.hit;
    final fetch = hit != null ? _registry.previewHit(hit) : _registry.listRemote(widget.source!, skill: widget.skill);
    return fetch.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('GitHub took too long to answer. Check your connection and try again.'),
    );
  }

  void _retry() => setState(() => _preview = _load());

  Future<void> _install(Skill s) async {
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await _registry.add(s);
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Installed ${s.name}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }


  @override
  Widget build(BuildContext context) => FutureBuilder<List<Skill>>(
    future: _preview,
    builder: (context, snap) {
      final title = widget.hit?.name ?? widget.source ?? 'Skill';
      final subtitle = widget.hit?.source ?? widget.source;
      final children = <Widget>[_SheetTitle(icon: Icons.auto_stories_outlined, title: title, subtitle: subtitle), const SizedBox(height: Space.l)];
      if (snap.connectionState != ConnectionState.done) {
        children.addAll([
          if (widget.hit?.description case final d? when d.isNotEmpty) ...[
            Text(d, style: context.text.bodyMedium),
            const SizedBox(height: Space.l),
          ],
          Row(
            children: [
              const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Space.m),
              Text('Fetching its instructions and files…', style: context.text.bodySmall),
            ],
          ),
        ]);
      } else if (snap.hasError) {
        final error = snap.error;
        children.addAll([
          _Panel(
            child: Text(
              'Couldn\'t fetch it: ${error is TimeoutException ? error.message : _errorText(error!)}',
              style: context.text.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ),
          const SizedBox(height: Space.m),
          OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
        ]);
      } else if (snap.data!.isEmpty) {
        children.add(_Panel(child: Text('No SKILL.md found there.', style: context.text.bodySmall)));
      } else {
        final list = snap.data!;
        final s = list[_selected.clamp(0, list.length - 1)];
        final installed = _registry[s.name] != null;
        if (list.length > 1) {
          children.addAll([
            Text('${list.length} skills here. Pick one to read and install.', style: context.text.bodySmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, x) in list.indexed)
                  ChoiceChip(label: Text(x.name), selected: i == _selected, onSelected: (_) => setState(() => _selected = i)),
              ],
            ),
            const SizedBox(height: Space.l),
          ]);
        }
        children.addAll([
          FilledButton.icon(
            onPressed: _installing ? null : () => _install(s),
            icon: _installing
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(installed ? Icons.refresh_rounded : Icons.download_rounded),
            label: Text(installed ? 'Update ${s.name}' : 'Install ${s.name}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.s),
            Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: Space.l),
          _SkillDetails(skill: s),
        ]);
      }
      return ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        children: children,
      );
    },
  );
}

/// Asks where to install a skill from, then previews it.
class _SkillSourceSheet extends StatefulWidget {
  const _SkillSourceSheet();

  @override
  State<_SkillSourceSheet> createState() => _SkillSourceSheetState();
}

class _SkillSourceSheetState extends State<_SkillSourceSheet> {
  final _source = TextEditingController();
  final _skill = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    _skill.dispose();
    super.dispose();
  }

  void _next() {
    final source = _source.text.trim();
    final uri = Uri.tryParse(source);
    final isRepo = RegExp(r'^[\w.\-]+/[\w.\-]+(@[\w.\-/]+)?$').hasMatch(source);
    if (!isRepo && !(uri != null && uri.scheme == 'https' && uri.hasAuthority)) {
      setState(() => _error = 'Use owner/repo or an https:// link.');
      return;
    }
    Navigator.pop(context);
    showSkillPreviewSheet(context, source: source, skill: _skill.text.trim().isEmpty ? null : _skill.text.trim());
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SheetTitle(
        icon: Icons.add_rounded,
        title: 'Install a skill',
        subtitle: 'You\'ll see its instructions and files before anything is installed.',
      ),
      const SizedBox(height: Space.l),
      TextField(
        controller: _source,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.url,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(labelText: 'Source', hintText: 'anthropics/skills', errorText: _error),
      ),
      const SizedBox(height: Space.s),
      TextField(
        controller: _skill,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Skill in that repository (if it has several)', hintText: 'pdf'),
      ),
      const SizedBox(height: Space.l),
      FilledButton(onPressed: _next, child: const Text('Preview')),
    ],
  );
}


/// A numbered step of the add-a-server form, with what it is for.
class _FormStep extends StatelessWidget {
  const _FormStep({required this.number, required this.title, required this.body});
  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(top: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.tint.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Text('$number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accent)),
      ),
      const SizedBox(width: Space.s),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(body, style: context.text.bodySmall?.copyWith(height: 1.4)),
          ],
        ),
      ),
    ],
  );
}

/// What an MCP server is, folded until asked.
class _McpExplainer extends StatefulWidget {
  const _McpExplainer();

  @override
  State<_McpExplainer> createState() => _McpExplainerState();
}

class _McpExplainerState extends State<_McpExplainer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface2,
    borderRadius: BorderRadius.circular(Radii.m),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text('What is an MCP server?', style: context.text.titleSmall)),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.text2),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: Space.s),
              Text(
                'MCP (Model Context Protocol) is a standard way for apps and services to offer tools to an AI. A '
                'server might let the assistant search your GitHub issues, read a Notion page, check a wallet or '
                'trade. Once added, the assistant sees its tools and can call them when a request needs one.\n\n'
                'Only add servers you trust: a tool can do whatever the server lets it, so new servers ask before '
                'each call unless you allow them. You can find servers under "Find servers" on the MCP page, or '
                'paste an address from a service\'s docs here.',
                style: context.text.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
