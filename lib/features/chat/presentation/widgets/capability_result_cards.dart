import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../settings/data/system_check.dart' show CheckStatus;
import '../../../settings/presentation/capability_settings.dart';
import '../../../settings/presentation/mcp_server_screen.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

// Cards and sheets for diagnosing and setting up MCP servers and skills
// (mcp_diagnose, mcp_setup, skill_diagnose, skill_setup). Null for other
// tools.

Widget? capabilityResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'mcp_diagnose' when j['servers'] is List => _McpDiagnoseCard(j: j),
  'skill_diagnose' when j['skills'] is List => _SkillDiagnoseCard(j: j),
  'mcp_setup' when j['changed'] is List => _SetupCard(j: j, mcp: true),
  'skill_setup' when j['changed'] is List => _SetupCard(j: j, mcp: false),
  _ => null,
};

CheckStatus _status(Object? v) => CheckStatus.values.asNameMap()['$v'] ?? CheckStatus.info;

String _ms(num? ms) => ms == null ? '—' : (ms < 1000 ? '${ms.round()} ms' : '${(ms / 1000).toStringAsFixed(1)} s');

String _when(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'ended ${_ago(-d)} ago';
  return 'ends in ${_ago(d)}';
}

String _ago(Duration d) => d.inDays > 0
    ? '${d.inDays} d'
    : d.inHours > 0
    ? '${d.inHours} h'
    : '${d.inMinutes} min';

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// "2 broken · 1 warning" as coloured pills.
Widget _countPills(Map<String, dynamic> counts) {
  final pairs = [
    (CheckStatus.fail, counts['broken'], 'broken'),
    (CheckStatus.warn, counts['warnings'], 'warning'),
    (CheckStatus.improve, counts['suggestions'], 'suggestion'),
    (CheckStatus.ok, counts['passed'], 'passed'),
  ];
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (s, n, w) in pairs)
        if (n is num && n > 0)
          InfoPill(s == CheckStatus.fail || s == CheckStatus.ok ? '${n.toInt()} $w' : _plural(n.toInt(), w), color: s.color, icon: s.icon),
    ],
  );
}

/// A coloured square with an icon, tinted by [status].
class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.status, {this.size = 36});
  final IconData icon;
  final CheckStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: status.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.m)),
    child: Icon(icon, size: size * 0.5, color: status.color),
  );
}

/// One finding: icon, title, detail.
class _FindingRow extends StatelessWidget {
  const _FindingRow(this.f);
  final Map<String, dynamic> f;

  @override
  Widget build(BuildContext context) {
    final s = _status(f['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(s.icon, size: 17, color: s.color)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${f['title']}', style: context.text.bodyMedium?.copyWith(fontWeight: s.rank <= CheckStatus.warn.rank ? FontWeight.w600 : null)),
                if (textOf(f['detail']) case final d?)
                  Padding(padding: const EdgeInsets.only(top: 2), child: SelectableText(d, style: context.text.bodySmall)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded box of rows with dividers.
class _Box extends StatelessWidget {
  const _Box(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, color: AppColors.line),
          c,
        ],
      ],
    ),
  );
}

/// The card footer: a line of text and a chevron.
Widget _footer(BuildContext context, String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
  decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
  child: Row(
    children: [
      Expanded(child: Text(text, style: context.text.labelSmall?.copyWith(color: AppColors.text2))),
      Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
    ],
  ),
);

/// One server's or skill's line on a card: badge, name, a short summary.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.icon, required this.title, required this.subtitle, required this.status});
  final IconData icon;
  final String title;
  final String subtitle;
  final CheckStatus status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
    child: Row(
      children: [
        _Badge(icon, status, size: 32),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: Space.s),
        Icon(status.icon, size: 18, color: status.color),
      ],
    ),
  );
}

/// The first serious finding's title, or [fallback].
String _headline(Map<String, dynamic> item, String fallback) {
  final serious = maps(item['findings']).where((f) => _status(f['status']).rank <= CheckStatus.warn.rank).firstOrNull;
  return serious == null ? fallback : '${serious['title']}';
}

// ---- MCP ------------------------------------------------------------------------

String _mcpSummary(Map<String, dynamic> s) {
  if (s['server_name'] == null) return _headline(s, 'Didn\'t connect');
  final parts = [
    _plural((s['tools'] as num? ?? 0).toInt(), 'tool'),
    if ((s['resources'] as num? ?? 0) > 0) _plural((s['resources'] as num).toInt(), 'resource'),
    if ((s['prompts'] as num? ?? 0) > 0) _plural((s['prompts'] as num).toInt(), 'prompt'),
    _ms(s['connect_ms'] as num?),
  ];
  final status = _status(s['status']);
  return status.rank <= CheckStatus.warn.rank ? '${_headline(s, '')} · ${parts.join(' · ')}' : 'Connected · ${parts.join(' · ')}';
}

String _authLabel(Map<String, dynamic> s) => switch (s['auth']) {
  'oauth' => 'Signed in${mapOf(s['oauth'])['issuer'] == null ? '' : ' (${mapOf(s['oauth'])['issuer']})'}',
  'header' => 'Key in ${strs(s['header_names']).join(', ')}',
  _ => 'None',
};

class _McpDiagnoseCard extends StatelessWidget {
  const _McpDiagnoseCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final servers = maps(j['servers']);
    final counts = mapOf(j['counts']);
    if (servers.isEmpty) {
      return InfoFrame(
        onTap: () => _open(context, const McpSkillsSettingsScreen()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoHeader(Icons.hub_outlined, 'MCP diagnosis'),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text('No MCP servers installed yet.', style: context.text.bodyMedium),
            ),
            _footer(context, 'Open MCP & Skills'),
          ],
        ),
      );
    }
    final ok = servers.where((s) => _status(s['status']).rank > CheckStatus.warn.rank).length;
    final findings = servers.fold<int>(0, (n, s) => n + maps(s['findings']).length);
    return InfoFrame(
      onTap: () => showMcpDiagnosisSheet(context, j),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(
            Icons.hub_outlined,
            'MCP diagnosis',
            trailing: Text(_plural(servers.length, 'server'), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok == servers.length
                      ? (servers.length == 1 ? 'Working' : 'All ${servers.length} working')
                      : '${servers.length - ok} of ${servers.length} need${servers.length - ok == 1 ? 's' : ''} attention',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 6),
                _countPills(counts),
              ],
            ),
          ),
          for (final s in servers.take(4))
            _ItemRow(icon: Icons.dns_outlined, title: '${s['id']}', subtitle: _mcpSummary(s), status: _status(s['status'])),
          _footer(context, servers.length > 4 ? '${servers.length - 4} more · $findings findings' : 'All $findings findings'),
        ],
      ),
    );
  }
}

/// Every MCP server checked, worst first, with its details and findings.
Future<void> showMcpDiagnosisSheet(BuildContext context, Map<String, dynamic> j) {
  final servers = maps(j['servers'])..sort((a, b) => _status(a['status']).rank.compareTo(_status(b['status']).rank));
  String report() => [
    'MCP diagnosis · ${j['checked_at'] ?? ''}',
    for (final s in servers) ...[
      '',
      '${s['id']} (${s['transport']}) ${s['address'] ?? ''}',
      for (final f in maps(s['findings'])) '  [${_status(f['status']).word}] ${f['title']}${f['detail'] == null ? '' : ': ${f['detail']}'}',
    ],
  ].join('\n');
  return showInfoSheet(context, (context) => [
    SheetTitle('MCP diagnosis', subtitle: '${_plural(servers.length, 'server')} · ${'${j['checked_at'] ?? ''}'.split('.').first.replaceFirst('T', ' ')}'),
    const SizedBox(height: Space.m),
    _countPills(mapOf(j['counts'])),
    for (final s in servers) ..._mcpServerSection(context, s),
    sheetButtons([
      FilledButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          _open(context, const McpSkillsSettingsScreen());
        },
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text('MCP & Skills'),
      ),
      OutlinedButton.icon(
        onPressed: () => copyText(context, report(), 'Report copied'),
        icon: const Icon(Icons.copy_all_rounded, size: 18),
        label: const Text('Copy report'),
      ),
    ]),
  ]);
}

/// One server in a sheet: a header, its details and its findings.
List<Widget> _mcpServerSection(BuildContext context, Map<String, dynamic> s) {
  final status = _status(s['status']);
  final perms = mapOf(s['permissions']);
  final oauth = mapOf(s['oauth']);
  final tools = strs(s['tool_names']);
  return [
    Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Row(
        children: [
          _Badge(Icons.dns_outlined, status, size: 30),
          const SizedBox(width: Space.s),
          Expanded(child: Text('${s['id']}', style: context.text.titleSmall)),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _open(context, McpServerScreen(serverId: '${s['id']}'));
            },
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('Settings'),
          ),
        ],
      ),
    ),
    _Box([
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
        child: Column(
          children: [
            KeyValueRow('Address', '${s['address'] ?? '—'}', mono: true),
            KeyValueRow('Transport', '${s['transport']}'),
            if (s['server_name'] != null) KeyValueRow('Server', '${s['server_name']} · ${s['protocol'] ?? ''}'),
            KeyValueRow('Sign-in', _authLabel(s)),
            if (oauth['expires_at'] != null) KeyValueRow('Token', '${_when(oauth['expires_at'])}${oauth['can_refresh'] == true ? ' · refreshes' : ''}'),
            KeyValueRow('Connect', '${_ms(s['connect_ms'] as num?)}${s['list_ms'] == null ? '' : ' · tools in ${_ms(s['list_ms'] as num?)}'}'),
            if (s['server_name'] != null)
              KeyValueRow('Offers', '${_plural((s['tools'] as num? ?? 0).toInt(), 'tool')} · ${_plural((s['resources'] as num? ?? 0).toInt(), 'resource')} · ${_plural((s['prompts'] as num? ?? 0).toInt(), 'prompt')}'),
            KeyValueRow(
              'Permissions',
              [
                'default ${perms['default'] == 'app' ? 'app setting' : perms['default']}',
                if ((perms['allow'] as num? ?? 0) > 0) '${perms['allow']} allowed',
                if ((perms['ask'] as num? ?? 0) > 0) '${perms['ask']} ask',
                if ((perms['off'] as num? ?? 0) > 0) '${perms['off']} off',
              ].join(' · '),
            ),
            KeyValueRow(
              'Last 7 days',
              '${_plural((s['calls_7d'] as num? ?? 0).toInt(), 'call')}${(s['failed_7d'] as num? ?? 0) > 0 ? ' · ${s['failed_7d']} failed' : ''}',
              valueColor: (s['failed_7d'] as num? ?? 0) > 0 ? CheckStatus.warn.color : null,
            ),
          ],
        ),
      ),
      for (final f in maps(s['findings'])) _FindingRow(f),
    ]),
    if (tools.isNotEmpty) ...[
      SectionLabel('Tools', trailing: '${s['tools']}', top: Space.m),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tools) InfoPill(t, icon: Icons.build_outlined)]),
    ],
  ];
}

// ---- Skills ----------------------------------------------------------------------

String _skillSummary(Map<String, dynamic> s) {
  final parts = [
    '~${s['est_tokens'] ?? 0} tokens',
    if (strs(s['files']).isNotEmpty) _plural(strs(s['files']).length, 'file'),
    if (s['deferred'] == true) 'deferred',
    if (s['update_available'] == true) 'update available',
  ];
  final status = _status(s['status']);
  return status.rank <= CheckStatus.improve.rank ? '${_headline(s, '${maps(s['findings']).firstOrNull?['title'] ?? ''}')} · ${parts.join(' · ')}' : parts.join(' · ');
}

class _SkillDiagnoseCard extends StatelessWidget {
  const _SkillDiagnoseCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final skills = maps(j['skills']);
    if (skills.isEmpty) {
      return InfoFrame(
        onTap: () => _open(context, const McpSkillsSettingsScreen(initialTab: 1)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoHeader(Icons.school_outlined, 'Skill diagnosis'),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text('No skills installed yet.', style: context.text.bodyMedium),
            ),
            _footer(context, 'Open MCP & Skills'),
          ],
        ),
      );
    }
    final attention = skills.where((s) => _status(s['status']).rank <= CheckStatus.warn.rank).length;
    final updates = skills.where((s) => s['update_available'] == true).length;
    final findings = skills.fold<int>(0, (n, s) => n + maps(s['findings']).length) + maps(j['general']).length;
    return InfoFrame(
      onTap: () => showSkillDiagnosisSheet(context, j),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(
            Icons.school_outlined,
            'Skill diagnosis',
            trailing: Text(_plural(skills.length, 'skill'), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attention == 0 ? (skills.length == 1 ? 'Ready to use' : 'All ${skills.length} ready') : '$attention need${attention == 1 ? 's' : ''} attention',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _countPills(mapOf(j['counts'])),
                    if (updates > 0) InfoPill(_plural(updates, 'update'), icon: Icons.system_update_alt_rounded, color: CheckStatus.improve.color),
                    if (j['prompt_tokens'] != null) InfoPill('~${j['prompt_tokens']} tokens per chat', icon: Icons.notes_rounded),
                  ],
                ),
              ],
            ),
          ),
          for (final s in skills.take(4))
            _ItemRow(icon: Icons.auto_stories_outlined, title: '${s['name']}', subtitle: _skillSummary(s), status: _status(s['status'])),
          _footer(context, skills.length > 4 ? '${skills.length - 4} more · $findings findings' : 'All $findings findings'),
        ],
      ),
    );
  }
}

/// Every skill checked, worst first, with its details and findings.
Future<void> showSkillDiagnosisSheet(BuildContext context, Map<String, dynamic> j) {
  final skills = maps(j['skills'])..sort((a, b) => _status(a['status']).rank.compareTo(_status(b['status']).rank));
  final general = maps(j['general']);
  String report() => [
    'Skill diagnosis · ${j['checked_at'] ?? ''}',
    for (final f in general) '[${_status(f['status']).word}] ${f['title']}',
    for (final s in skills) ...[
      '',
      '${s['name']} (${s['source']})',
      for (final f in maps(s['findings'])) '  [${_status(f['status']).word}] ${f['title']}${f['detail'] == null ? '' : ': ${f['detail']}'}',
    ],
  ].join('\n');
  return showInfoSheet(context, (context) => [
    SheetTitle(
      'Skill diagnosis',
      subtitle: '${j['installed'] ?? skills.length} installed · ~${j['prompt_tokens'] ?? 0} tokens of every chat',
    ),
    const SizedBox(height: Space.m),
    _countPills(mapOf(j['counts'])),
    if (general.isNotEmpty) ...[
      const SectionLabel('Across skills', top: Space.l),
      _Box([for (final f in general) _FindingRow(f)]),
    ],
    for (final s in skills) ..._skillSection(context, s),
    sheetButtons([
      FilledButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          _open(context, const McpSkillsSettingsScreen(initialTab: 1));
        },
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text('MCP & Skills'),
      ),
      OutlinedButton.icon(
        onPressed: () => copyText(context, report(), 'Report copied'),
        icon: const Icon(Icons.copy_all_rounded, size: 18),
        label: const Text('Copy report'),
      ),
    ]),
  ]);
}

List<Widget> _skillSection(BuildContext context, Map<String, dynamic> s) {
  final files = strs(s['files']);
  final missing = strs(s['missing_files']);
  return [
    Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Row(
        children: [
          _Badge(Icons.auto_stories_outlined, _status(s['status']), size: 30),
          const SizedBox(width: Space.s),
          Expanded(child: Text('${s['name']}', style: context.text.titleSmall)),
          if (s['update_available'] == true) InfoPill('Update', icon: Icons.system_update_alt_rounded, color: CheckStatus.improve.color),
        ],
      ),
    ),
    _Box([
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (textOf(s['description']) case final d?)
              Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: SelectableText(d, style: context.text.bodyMedium)),
            KeyValueRow('Source', '${s['source']}', mono: true),
            KeyValueRow('Size', '${s['lines']} lines · ~${s['est_tokens']} tokens'),
            KeyValueRow('Files', files.isEmpty ? 'None' : '${files.length} · ${fileSize(s['files_bytes'] as num?)}'),
            KeyValueRow('Listed', s['deferred'] == true ? 'Deferred (found when needed)' : 'In every chat'),
            KeyValueRow(
              'Last 30 days',
              '${_plural((s['loads_30d'] as num? ?? 0).toInt(), 'load')}${(s['failed_30d'] as num? ?? 0) > 0 ? ' · ${s['failed_30d']} failed' : ''}',
            ),
          ],
        ),
      ),
      for (final f in maps(s['findings'])) _FindingRow(f),
    ]),
    if (files.isNotEmpty || missing.isNotEmpty) ...[
      SectionLabel('Files', trailing: missing.isEmpty ? null : '${missing.length} missing', top: Space.m),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final f in files) InfoPill(f, icon: Icons.description_outlined),
          for (final f in missing) InfoPill(f, icon: Icons.help_outline_rounded, color: CheckStatus.warn.color),
        ],
      ),
    ],
  ];
}

// ---- Setup ----------------------------------------------------------------------

/// What mcp_setup or skill_setup changed, and how the check after it went.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.j, required this.mcp});
  final Map<String, dynamic> j;
  final bool mcp;

  @override
  Widget build(BuildContext context) {
    final changed = strs(j['changed']);
    final check = mapOf(j['check']);
    final status = check.isEmpty ? CheckStatus.ok : _status(check['status']);
    final name = '${j[mcp ? 'server' : 'skill'] ?? ''}';
    return InfoFrame(
      onTap: () => _showSetupSheet(context, j, mcp: mcp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(mcp ? Icons.settings_input_component_outlined : Icons.edit_note_rounded, mcp ? 'MCP setup' : 'Skill setup'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Badge(mcp ? Icons.dns_outlined : Icons.auto_stories_outlined, status),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                          Text(
                            check.isEmpty
                                ? _plural(changed.length, 'change')
                                : mcp
                                ? _mcpSummary(check)
                                : _skillSummary(check),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s + 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in changed.take(6)) InfoPill(c, icon: Icons.check_rounded),
                    if (changed.length > 6) InfoPill('+${changed.length - 6} more'),
                  ],
                ),
              ],
            ),
          ),
          _footer(context, check.isEmpty ? 'Details' : '${_plural(maps(check['findings']).length, 'finding')} after the change'),
        ],
      ),
    );
  }
}

Future<void> _showSetupSheet(BuildContext context, Map<String, dynamic> j, {required bool mcp}) {
  final changed = strs(j['changed']);
  final check = mapOf(j['check']);
  final name = '${j[mcp ? 'server' : 'skill'] ?? ''}';
  return showInfoSheet(context, (context) => [
    SheetTitle(
      name,
      subtitle: mcp ? 'MCP server set up' : 'Skill set up',
      leading: _Badge(mcp ? Icons.dns_outlined : Icons.auto_stories_outlined, check.isEmpty ? CheckStatus.ok : _status(check['status']), size: 44),
    ),
    const SectionLabel('Changed', top: Space.l),
    _Box([
      for (final c in changed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
          child: Row(
            children: [
              Icon(Icons.check_rounded, size: 17, color: CheckStatus.ok.color),
              const SizedBox(width: Space.m),
              Expanded(child: Text(c, style: context.text.bodyMedium)),
            ],
          ),
        ),
    ]),
    if (check.isNotEmpty) ...(mcp ? _mcpServerSection(context, check) : _skillSection(context, check)),
    sheetButtons([
      FilledButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          _open(context, mcp ? McpServerScreen(serverId: name) : const McpSkillsSettingsScreen(initialTab: 1));
        },
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: Text(mcp ? 'Server settings' : 'MCP & Skills'),
      ),
    ]),
  ]);
}
