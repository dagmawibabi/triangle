import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../../../telegram/data/telegram_tools.dart';
import '../../../domain/chat_models.dart';
import 'dev_card_kit.dart';

// Vercel cards: the account, projects and one project, deployments that
// follow a build live (with a preview of the site once it is up), build and
// runtime logs with highlighting, env vars, domains, DNS, usage as a chart,
// files, aliases, webhooks, Edge Config, checks. Every card opens a sheet:
// a project (Visit, preview, Pause / Redeploy / Live logs), a deployment
// (Visit, preview, actions, details, live build log), or the full result.

List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// HTML the deploy call published, for "Preview source".
String? _deployedHtml(Map<String, dynamic> args) {
  if ('${args['html'] ?? ''}'.trim().isNotEmpty) return '${args['html']}';
  for (final f in _l(args['text_files'])) {
    final path = '${f['path'] ?? ''}'.toLowerCase();
    if (path == 'index.html' || path == '/index.html') return '${f['content'] ?? ''}';
  }
  for (final f in _l(args['text_files'])) {
    if ('${f['path'] ?? ''}'.toLowerCase().endsWith('.html')) return '${f['content'] ?? ''}';
  }
  return null;
}

Widget? vercelResultFor(ToolPart part, Map<String, dynamic> j) {
  if (j['dev'] != 'vercel') return null;
  void raw(BuildContext context, String title) => showJsonSheet(context, brand: DevBrand.vercel, title: title, value: j);
  return switch (part.name) {
    'vercel_account' => _AccountCard(j: j),
    'vercel_projects' => _ProjectList(projects: _l(j['projects'])),
    'vercel_project' => _ProjectCard(j: j),
    'vercel_deployments' => _DeploymentList(deployments: _l(j['deployments']), project: j['project'] as String?),
    'vercel_deployment' ||
    'vercel_deploy' ||
    'vercel_redeploy' ||
    'vercel_promote' ||
    'vercel_rollback' ||
    'vercel_cancel_deployment' when j['deployment'] is Map => LiveDeploymentCard(
      initial: _m(j['deployment']),
      action: switch (part.name) {
        'vercel_deploy' => 'Deployed',
        'vercel_redeploy' => 'Redeploying',
        'vercel_promote' => 'Promoted to production',
        'vercel_rollback' => 'Rolled back to',
        'vercel_cancel_deployment' => 'Cancelled',
        _ => null,
      },
      files: [for (final f in (j['files'] as List? ?? const [])) '$f'],
      sourceHtml: part.name == 'vercel_deploy' ? _deployedHtml(part.args) : null,
    ),
    'vercel_build_logs' => _LogsCard(deployment: _m(j['deployment']), lines: _l(j['lines'])),
    'vercel_runtime_logs' => _RuntimeLogsCard(lines: _l(j['lines']), args: part.args, note: j['note'] as String?),
    'vercel_env' => _EnvCard(project: '${j['project'] ?? ''}', env: _l(j['env'])),
    'vercel_domains' when j['domains'] != null => _DomainList(domains: _l(j['domains'])),
    'vercel_domains' when j['domain'] is Map => _DomainConfigCard(domain: _m(j['domain']), config: _m(j['config'])),
    'vercel_project_domains' => _DomainList(domains: _l(j['domains']), project: '${j['project'] ?? ''}'),
    'vercel_domain_check' => _DomainCheckCard(j: j),
    'vercel_dns_records' => _DnsCard(domain: '${j['domain']}', records: _l(j['dns_records'])),
    'vercel_usage' => _UsageCard(j: j),
    'vercel_deployment_files' => _FilesCard(deployment: _m(j['deployment']), files: _l(j['files'])),
    'vercel_aliases' => _Rows(
      title: 'Aliases · ${_l(j['aliases']).length}',
      onOpen: (c) => raw(c, 'Aliases'),
      rows: [for (final a in _l(j['aliases'])) (Icons.alternate_email_rounded, '${a['alias']}', ago(a['created']), 'https://${a['alias']}')],
    ),
    'vercel_webhooks' => _Rows(
      title: 'Webhooks · ${_l(j['webhooks']).length}',
      onOpen: (c) => raw(c, 'Webhooks'),
      rows: [for (final w in _l(j['webhooks'])) (Icons.webhook_rounded, '${w['url']}', (w['events'] as List?)?.join(', ') ?? '', null)],
    ),
    'vercel_team_members' => _Rows(
      title: 'Team · ${_l(j['members']).length} members',
      onOpen: (c) => raw(c, 'Team members'),
      rows: [for (final m in _l(j['members'])) (Icons.person_outline_rounded, '${m['name'] ?? m['username']}', '${m['role'] ?? ''} · ${m['email'] ?? ''}', null)],
    ),
    'vercel_edge_config' when j['edge_configs'] != null => _Rows(
      title: 'Edge Config · ${_l(j['edge_configs']).length}',
      onOpen: (c) => raw(c, 'Edge Config'),
      rows: [for (final e in _l(j['edge_configs'])) (Icons.tune_rounded, '${e['slug']}', '${e['items'] ?? 0} items · ${bytes(e['size'])} · ${e['id']}', null)],
    ),
    'vercel_edge_config' => _EdgeItems(id: '${j['id']}', items: _l(j['items'])),
    'vercel_checks' => _Rows(
      title: 'Checks · ${_l(j['checks']).length}',
      onOpen: (c) => raw(c, 'Checks'),
      rows: [
        for (final c in _l(j['checks']))
          (c['conclusion'] == 'succeeded' ? Icons.check_circle_outline_rounded : (c['conclusion'] == 'failed' ? Icons.error_outline_rounded : Icons.schedule_rounded), '${c['name']}', '${c['status']} · ${c['conclusion'] ?? ''}', c['url'] as String?),
      ],
    ),
    _ => null,
  };
}

// ---- state ---------------------------------------------------------------------------

bool _live(Object? state) => const {'BUILDING', 'QUEUED', 'INITIALIZING'}.contains('$state'.toUpperCase());

Color stateColor(Object? state) => switch ('$state'.toUpperCase()) {
  'READY' => AppColors.success,
  'ERROR' => AppColors.danger,
  'CANCELED' => AppColors.text3,
  _ => AppColors.warning,
};

String _stateLabel(Object? state) => switch ('$state'.toUpperCase()) {
  'READY' => 'Ready',
  'ERROR' => 'Failed',
  'CANCELED' => 'Cancelled',
  'BUILDING' => 'Building',
  'QUEUED' => 'Queued',
  'INITIALIZING' => 'Starting',
  final s => s.isEmpty ? '—' : s,
};

Widget statePill(Object? state) => Pill(_stateLabel(state), color: stateColor(state), pulse: _live(state));

String? _bestUrl(Map d) {
  final aliases = d['aliases'] as List?;
  if (aliases != null && aliases.isNotEmpty) return 'https://${aliases.first}';
  return d['url'] as String?;
}

const _monoColors = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF14B8A6)];

/// A project's tile: its initial on a colour picked from its name.
class _Monogram extends StatelessWidget {
  const _Monogram(this.name, {this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = _monoColors[name.codeUnits.fold<int>(0, (a, b) => a + b) % _monoColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, Colors.black, 0.35)!]),
      ),
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

IconData _frameworkIcon(Object? f) => switch ('$f') {
  'nextjs' || 'remix' || 'gatsby' => Icons.change_history_rounded,
  'vite' || 'svelte' || 'sveltekit' || 'sveltekit-1' => Icons.bolt_rounded,
  'astro' => Icons.rocket_launch_outlined,
  'nuxtjs' || 'vue' => Icons.terrain_rounded,
  'null' || '' => Icons.web_asset_rounded,
  _ => Icons.code_rounded,
};

// ---- log highlighting ------------------------------------------------------------------

final _logToken = RegExp(
  r'(?<time>\b\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\b|\b\d{4}-\d{2}-\d{2}T[\d:.]+Z?\b)'
  r'|(?<err>\b(?:error|errors|failed|failure|fatal|exception|ELIFECYCLE|TypeError|ReferenceError|SyntaxError|Cannot find)\b|ERR!|✗|✘|×)'
  r'|(?<warn>\b(?:warn|warning|warnings|deprecated|WARN)\b|⚠)'
  r'|(?<ok>\b(?:success|successfully|done|ready|compiled|completed|deployed|built|passed|Build Completed|Deployment completed)\b|✓|✔)'
  r'|(?<url>https?://[^\s)]+)'
  r'|(?<pkg>(?:@[\w.-]+/)?[\w.-]+@\d+\.\d+[\w.+-]*)'
  r'|(?<path>(?:\.{0,2}/)?(?:[\w.-]+/)+[\w.-]+\.\w{1,5}\b)'
  r'|(?<dur>\b\d+(?:\.\d+)?\s?(?:ms|s|m)\b|\b\d+(?:\.\d+)?\s?(?:kB|KB|MB|B)\b)'
  r'|(?<str>"[^"\n]*"|`[^`\n]*`)'
  r'|(?<cmd>^\s*(?:>|\$|Running|Installing|Cloning|Building|Detected|Collecting|Generating|Linting)\b)',
  caseSensitive: false,
);

/// One log line in colour: errors red, warnings amber, success green,
/// times dim, URLs and paths blue, sizes and durations cyan, packages violet.
List<TextSpan> highlightLog(String line, {bool stderr = false}) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in _logToken.allMatches(line)) {
    if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
    final text = m[0]!;
    TextStyle style;
    if (m.namedGroup('time') != null) {
      style = const TextStyle(color: Color(0xFF6B7280));
    } else if (m.namedGroup('err') != null) {
      style = const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700);
    } else if (m.namedGroup('warn') != null) {
      style = const TextStyle(color: Color(0xFFFFC857), fontWeight: FontWeight.w600);
    } else if (m.namedGroup('ok') != null) {
      style = const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w600);
    } else if (m.namedGroup('url') != null) {
      style = const TextStyle(color: Color(0xFF60A5FA), decoration: TextDecoration.underline, decorationColor: Color(0xFF60A5FA));
    } else if (m.namedGroup('pkg') != null) {
      style = const TextStyle(color: Color(0xFFC4B5FD));
    } else if (m.namedGroup('path') != null) {
      style = const TextStyle(color: Color(0xFF93C5FD));
    } else if (m.namedGroup('dur') != null) {
      style = const TextStyle(color: Color(0xFF67E8F9));
    } else if (m.namedGroup('str') != null) {
      style = const TextStyle(color: Color(0xFFBEF264));
    } else {
      style = const TextStyle(color: Color(0xFFF0ABFC), fontWeight: FontWeight.w600);
    }
    spans.add(TextSpan(text: text, style: style));
    at = m.end;
  }
  if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
  return [TextSpan(children: spans, style: stderr ? const TextStyle(color: Color(0xFFFCA5A5)) : null)];
}

class _Terminal extends StatelessWidget {
  const _Terminal({required this.lines, this.max = 60, this.numbers = true, this.title = 'Log', this.subtitle});
  final List<Map<String, dynamic>> lines;
  final int max;
  final bool numbers;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    final first = lines.length - shown.length;
    return Stack(
      children: [
        _box(shown, first),
        if (lines.isNotEmpty)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: const Color(0xFF1F2937),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Full screen',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_full_rounded, size: 16, color: Colors.white70),
                onPressed: () => showLogViewer(context, title: title, subtitle: subtitle, lines: lines),
              ),
            ),
          ),
      ],
    );
  }

  Widget _box(List<Map<String, dynamic>> shown, int first) {
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0F),
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: shown.isEmpty
          ? Text('No output yet.', style: codeTextStyle.copyWith(fontSize: 12, color: Colors.white54))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(
                TextSpan(
                  style: codeTextStyle.copyWith(fontSize: 11.5, height: 1.45, color: const Color(0xFFD4D4D8)),
                  children: [
                    if (first > 0) TextSpan(text: '… $first earlier lines\n', style: const TextStyle(color: Colors.white38)),
                    for (final (i, l) in shown.indexed) ...[
                      if (numbers) TextSpan(text: '${first + i + 1}'.padLeft(4), style: const TextStyle(color: Color(0xFF3F3F46))),
                      if (numbers) const TextSpan(text: '  '),
                      if (l['status'] != null)
                        TextSpan(
                          text: '${l['status']} ',
                          style: TextStyle(color: (l['status'] is num && (l['status'] as num) >= 400) ? const Color(0xFFFF6B6B) : const Color(0xFF4ADE80), fontWeight: FontWeight.w700),
                        ),
                      if (l['method'] != null) TextSpan(text: '${l['method']} ${l['path'] ?? ''}  ', style: const TextStyle(color: Color(0xFF93C5FD))),
                      ...highlightLog('${l['text'] ?? ''}', stderr: l['type'] == 'stderr' || '${l['level']}' == 'error'),
                      const TextSpan(text: '\n'),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ---- account ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final u = _m(j['user']);
    final teams = _l(j['teams']);
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.vercel, title: '${u['name'] ?? u['username']}', subtitle: 'Vercel account', value: j),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Vercel account', subtitle: 'acting as ${j['team']}'),
        ListTile(
          leading: _Monogram('${u['username'] ?? '?'}'),
          title: Text('${u['name'] ?? u['username']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(['@${u['username']}', if (u['email'] != null) '${u['email']}'].join(' · ')),
          trailing: u['plan'] == null ? null : Pill('${u['plan']}'.toUpperCase(), color: AppColors.accent),
        ),
        if (teams.isNotEmpty)
          pad(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in teams)
                  Pill(
                    '${t['name']}${t['role'] == null ? '' : ' · ${'${t['role']}'.toLowerCase()}'}',
                    color: t['id'] == j['team'] ? AppColors.success : AppColors.text2,
                    icon: Icons.groups_2_outlined,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- projects --------------------------------------------------------------------------

class _ProjectList extends StatelessWidget {
  const _ProjectList({required this.projects});
  final List<Map<String, dynamic>> projects;

  @override
  Widget build(BuildContext context) {
    final states = [for (final p in projects) '${_m(p['latest'])['state'] ?? ''}'.toUpperCase()];
    final ready = states.where((s) => s == 'READY').length;
    final failed = states.where((s) => s == 'ERROR').length;
    final building = states.where(_live).length;
    return DevPanel(
      onTap: () => showDevSheet(
        context,
        brand: DevBrand.vercel,
        title: 'Projects',
        subtitle: '${projects.length} on this account',
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          children: [for (final p in projects) _ProjectRow(p: p)],
        ),
      ),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Projects', subtitle: '${projects.length} on this account'),
        if (projects.isNotEmpty)
          pad(
            Row(
              children: [
                _Count(n: ready, label: 'live', color: AppColors.success),
                const SizedBox(width: Space.s),
                _Count(n: building, label: 'building', color: AppColors.warning),
                const SizedBox(width: Space.s),
                _Count(n: failed, label: 'failed', color: AppColors.danger),
              ],
            ),
            top: Space.xs,
          ),
        for (final p in projects.take(12)) _ProjectRow(p: p),
        if (projects.length > 12) MoreRow(label: 'All ${projects.length} projects', onTap: null),
        if (projects.isEmpty) pad(Text('No projects yet.', style: context.text.bodySmall), top: Space.s),
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.n, required this.label, required this.color});
  final int n;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.s),
      decoration: BoxDecoration(color: color.withValues(alpha: n == 0 ? 0.04 : 0.1), borderRadius: BorderRadius.circular(Radii.s)),
      // Number over label, so three fit side by side on a phone.
      child: Column(
        children: [
          Text('$n', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: n == 0 ? AppColors.text3 : color)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: n == 0 ? AppColors.text3 : color)),
        ],
      ),
    ),
  );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final latest = _m(p['latest']);
    final prod = '${p['production_url'] ?? ''}'.replaceFirst('https://', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, 2, Space.s, 2),
      child: Material(
        color: AppColors.surface2.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Radii.m),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.m),
          onTap: () => showVercelProject(context, '${p['name']}'),
          child: Padding(
            padding: const EdgeInsets.all(Space.s + 2),
            child: Row(
              children: [
                _Monogram('${p['name']}'),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                          const SizedBox(width: 6),
                          Icon(_frameworkIcon(p['framework']), size: 13, color: AppColors.text3),
                        ],
                      ),
                      if (prod.isNotEmpty)
                        Text(prod, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.accent)),
                      Row(
                        children: [
                          if (p['repo'] != null) ...[
                            Icon(Icons.commit_rounded, size: 12, color: AppColors.text3),
                            const SizedBox(width: 2),
                            Flexible(child: Text('${p['repo']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
                            const SizedBox(width: 6),
                          ],
                          if (latest['created'] != null) Text(ago(latest['created']), style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                if (p['paused'] == true) Pill('Paused', color: AppColors.text3, icon: Icons.pause_rounded) else if (latest.isNotEmpty) statePill(latest['state']),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final p = _m(j['project']);
    final domains = _l(j['domains']);
    final deps = _l(j['deployments']);
    final prod = p['production_url'] as String?;
    void open() => showVercelProject(context, '${p['name']}');
    return DevPanel(
      onTap: open,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: Row(
            children: [
              _Monogram('${p['name']}', size: 44),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name']}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text([p['framework'], p['repo']].whereType<Object>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
              const DevMark(DevBrand.vercel),
            ],
          ),
        ),
        if (prod != null) pad(WebPreview(url: prod, height: 190, onTap: open)),
        if (domains.isNotEmpty)
          pad(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in domains.take(6))
                  Pill('${d['name']}', color: d['verified'] == true ? AppColors.success : AppColors.warning, icon: d['verified'] == true ? Icons.verified_rounded : Icons.error_outline_rounded),
              ],
            ),
          ),
        for (final d in deps.take(3)) _DeploymentRow(d: d, dense: true),
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

/// The project in a sheet: Visit, a live preview, Pause / Redeploy / Live
/// logs, then settings, domains, deployments, crons and env vars.
Future<void> showVercelProject(BuildContext context, String project) => showDevSheet(
  context,
  brand: DevBrand.vercel,
  title: project,
  subtitle: 'Vercel project',
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'vercel_project', {'project': project}),
      builder: (context, j, reload) => _ProjectSheetBody(j: j, scroll: scroll, reload: reload),
    ),
  ),
);

class _ProjectSheetBody extends ConsumerWidget {
  const _ProjectSheetBody({required this.j, required this.scroll, required this.reload});
  final Map<String, dynamic> j;
  final ScrollController scroll;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = _m(j['project']);
    final deps = _l(j['deployments']);
    final domains = _l(j['domains']);
    final crons = _l(j['crons']);
    final prod = deps.where((d) => d['target'] == 'production' && d['state'] == 'READY').firstOrNull;
    final name = '${p['name']}';
    final url = p['production_url'] as String? ?? (prod == null ? null : _bestUrl(prod));
    final paused = p['paused'] == true;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        _VisitBar(url: url, onLogs: () => showVercelRuntimeLogs(context, name)),
        if (url != null) Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0), child: WebPreview(url: url, height: 340, interactive: true)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: paused ? 'Resume' : 'Pause',
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  done: paused ? 'Resumed' : 'Paused',
                  onRun: () async {
                    await devRun(context, ref, 'vercel_pause_project', {'project': name, 'pause': !paused},
                        confirmTitle: paused ? 'Resume $name?' : 'Pause $name?',
                        confirmMessage: paused ? 'Its deployments serve again.' : 'Its deployments stop serving until resumed.',
                        confirmLabel: paused ? 'Resume' : 'Pause');
                    reload();
                  },
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: ActionButton(
                  label: 'Redeploy',
                  icon: Icons.replay_rounded,
                  done: 'Redeploy started',
                  onRun: () async {
                    if (prod == null) throw 'No ready production deployment to rebuild.';
                    final r = await devRun(context, ref, 'vercel_redeploy', {'deployment': prod['id'], 'production': true},
                        confirmTitle: 'Redeploy $name?', confirmMessage: 'Builds production again from the same source.', confirmLabel: 'Redeploy');
                    if (context.mounted) unawaited(showVercelDeployment(context, '${_m(r['deployment'])['id']}'));
                  },
                ),
              ),
            ],
          ),
        ),
        const SheetLabel('Settings'),
        SheetGroup(
          children: [
            for (final (k, label) in const [
              ('framework', 'Framework'),
              ('repo', 'Repository'),
              ('production_branch', 'Branch'),
              ('build_command', 'Build'),
              ('install_command', 'Install'),
              ('output_directory', 'Output'),
              ('root_directory', 'Root'),
              ('node_version', 'Node'),
              ('serverless_region', 'Region'),
              ('id', 'Project ID'),
            ])
              if (p[k] != null && '${p[k]}'.isNotEmpty) CopyRow(label: label, value: '${p[k]}'),
          ],
        ),
        if (domains.isNotEmpty) ...[
          SheetLabel('Domains · ${domains.length}'),
          SheetGroup(
            children: [
              for (final d in domains)
                ListTile(
                  dense: true,
                  onTap: () => showVercelDomain(context, '${d['name']}'),
                  leading: Icon(d['verified'] == true ? Icons.verified_rounded : Icons.error_outline_rounded, size: 20, color: d['verified'] == true ? AppColors.success : AppColors.warning),
                  title: Text('${d['name']}'),
                  subtitle: d['redirect'] != null ? Text('→ ${d['redirect']}') : (d['git_branch'] != null ? Text('branch ${d['git_branch']}') : null),
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                ),
            ],
          ),
        ],
        SheetLabel('Recent deployments · ${deps.length}'),
        SheetGroup(children: [for (final d in deps) _DeploymentRow(d: d)]),
        if (crons.isNotEmpty) ...[
          SheetLabel('Cron jobs · ${crons.length}'),
          SheetGroup(
            children: [
              for (final c in crons)
                ListTile(dense: true, leading: const Icon(Icons.schedule_rounded, size: 20), title: Text('${c['path']}', style: codeTextStyle.copyWith(fontSize: 12.5)), subtitle: Text('${c['schedule']}')),
            ],
          ),
        ],
        const SheetLabel('Environment variables'),
        _EnvLoader(project: name),
      ],
    );
  }
}

/// The address, first in a sheet, with Copy, Logs and Visit as icons.
class _VisitBar extends StatelessWidget {
  const _VisitBar({required this.url, this.onLogs});
  final String? url;
  final VoidCallback? onLogs;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.m, 0),
    child: Row(
      children: [
        Icon(Icons.public_rounded, size: 18, color: url == null ? AppColors.text3 : AppColors.success),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(url == null ? 'Not live yet' : url!.replaceFirst('https://', ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (url != null)
          IconButton(
            tooltip: 'Copy link',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url!));
              showSnack(context, 'Link copied');
            },
          ),
        if (onLogs != null)
          IconButton(tooltip: 'Logs', visualDensity: VisualDensity.compact, icon: const Icon(Icons.receipt_long_rounded, size: 19), onPressed: onLogs),
        IconButton.filled(
          style: solidIconButton,
          tooltip: 'Visit',
          visualDensity: VisualDensity.compact,
          onPressed: url == null ? null : () => openUrl(url!),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _EnvLoader extends ConsumerStatefulWidget {
  const _EnvLoader({required this.project});
  final String project;
  @override
  ConsumerState<_EnvLoader> createState() => _EnvLoaderState();
}

class _EnvLoaderState extends ConsumerState<_EnvLoader> {
  bool _show = false;
  @override
  Widget build(BuildContext context) {
    if (!_show) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: OutlinedButton.icon(onPressed: () => setState(() => _show = true), icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Show variables (names only)')),
      );
    }
    return Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'vercel_env', {'project': widget.project}),
      builder: (context, j, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: _EnvCard(project: widget.project, env: _l(j['env']), embedded: true),
      ),
    );
  }
}

// ---- deployments -----------------------------------------------------------------------

class _DeploymentList extends StatelessWidget {
  const _DeploymentList({required this.deployments, this.project});
  final List<Map<String, dynamic>> deployments;
  final String? project;

  @override
  Widget build(BuildContext context) {
    final building = deployments.where((d) => _live(d['state'])).length;
    return DevPanel(
      glow: building > 0 ? AppColors.warning : null,
      onTap: () => showDevSheet(
        context,
        brand: DevBrand.vercel,
        title: 'Deployments',
        subtitle: project,
        builder: (context, scroll) => ListView(controller: scroll, children: [for (final d in deployments) _LiveRow(initial: d)]),
      ),
      children: [
        DevHead(
          brand: DevBrand.vercel,
          title: 'Deployments${project == null ? '' : ' · $project'} · ${deployments.length}',
          subtitle: building > 0 ? '$building building now' : null,
        ),
        for (final (i, d) in deployments.take(12).indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 40),
          _LiveRow(initial: d),
        ],
        if (deployments.length > 12) MoreRow(label: 'All ${deployments.length}', onTap: null),
        if (deployments.isEmpty) pad(Text('No deployments match.', style: context.text.bodySmall), top: Space.s),
      ],
    );
  }
}

/// A deployment row that keeps polling while its build runs.
class _LiveRow extends ConsumerStatefulWidget {
  const _LiveRow({required this.initial});
  final Map<String, dynamic> initial;
  @override
  ConsumerState<_LiveRow> createState() => _LiveRowState();
}

class _LiveRowState extends ConsumerState<_LiveRow> with _Poll {
  @override
  Map<String, dynamic> get initial => widget.initial;

  @override
  Widget build(BuildContext context) => _DeploymentRow(d: d);
}

/// Polls a deployment every few seconds while it is building.
mixin _Poll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Map<String, dynamic> get initial;
  late Map<String, dynamic> d = Map<String, dynamic>.from(initial);
  Timer? _timer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_live(d['state']) || _polls > 240) return;
    _timer = Timer(const Duration(seconds: 4), _poll);
  }

  Future<void> _poll() async {
    _polls++;
    try {
      final r = await ref.read(toolRunnerProvider).run('vercel_deployment', {'deployment': d['id']});
      if (!mounted) return;
      if (r.json['deployment'] is Map) setState(() => d = _m(r.json['deployment']));
    } catch (_) {}
    if (mounted) _schedule();
  }

  void replace(Map<String, dynamic> next) {
    setState(() => d = next);
    _polls = 0;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _DeploymentRow extends StatelessWidget {
  const _DeploymentRow({required this.d, this.dense = false});
  final Map<String, dynamic> d;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final live = _live(d['state']);
    return InkWell(
      onTap: () => showVercelDeployment(context, '${d['id']}'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.m, vertical: dense ? 6 : Space.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: Space.m, left: 4),
                  decoration: BoxDecoration(
                    color: stateColor(d['state']),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: stateColor(d['state']).withValues(alpha: 0.5), blurRadius: 6)],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d['commit'] ?? d['name'] ?? d['id']}'.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      Text(
                        [
                          d['target'] == 'production' ? 'Production' : 'Preview',
                          if (d['branch'] != null) '${d['branch']}',
                          if (d['sha'] != null) '${d['sha']}',
                          if (d['creator'] != null) '${d['creator']}',
                          ago(d['created']),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                statePill(d['state']),
              ],
            ),
            if (live)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 26),
                child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 3, color: AppColors.warning, backgroundColor: AppColors.surface2)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Queued → Building → Ready, with the current step spinning.
class _Steps extends StatelessWidget {
  const _Steps({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final live = _live(state);
    final step = switch (state) {
      'QUEUED' || 'INITIALIZING' => 0,
      'BUILDING' => 1,
      _ => 2,
    };
    return Row(
      children: [
        for (final (i, label) in const ['Queued', 'Building', 'Ready'].indexed) ...[
          if (i > 0) Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 4), color: i <= step ? stateColor(state) : AppColors.line)),
          _Step(
            label: i == 2 && state == 'ERROR' ? 'Failed' : (i == 2 && state == 'CANCELED' ? 'Cancelled' : label),
            state: i < step || (i == step && !live) ? (state == 'ERROR' && i == 2 ? 'error' : 'done') : (i == step ? 'live' : 'todo'),
          ),
        ],
      ],
    );
  }
}

/// A deployment that follows its build to the end: steps, elapsed time,
/// the URL with a preview once it is ready, and promote, redeploy and cancel.
/// A tap opens the deployment's sheet.
class LiveDeploymentCard extends ConsumerStatefulWidget {
  const LiveDeploymentCard({super.key, required this.initial, this.action, this.files = const [], this.sourceHtml});
  final Map<String, dynamic> initial;
  final String? action;
  final List<String> files;

  /// The HTML that was deployed, for "Preview source".
  final String? sourceHtml;

  @override
  ConsumerState<LiveDeploymentCard> createState() => _LiveDeploymentCardState();
}

class _LiveDeploymentCardState extends ConsumerState<LiveDeploymentCard> with _Poll {
  @override
  Map<String, dynamic> get initial => widget.initial;

  @override
  Widget build(BuildContext context) {
    final state = '${d['state'] ?? ''}'.toUpperCase();
    final live = _live(state);
    final url = _bestUrl(d);
    final started = parseWhen(d['building_at'] ?? d['created']);
    final done = parseWhen(d['ready']);
    void open() => showVercelDeployment(context, '${d['id']}');
    return DevPanel(
      glow: stateColor(state),
      danger: state == 'ERROR',
      onTap: open,
      children: [
        DevHead(
          brand: DevBrand.vercel,
          title: '${widget.action ?? 'Deployment'} · ${d['name'] ?? ''}',
          subtitle: [d['target'] == 'production' ? 'Production' : 'Preview', if (d['branch'] != null) '${d['branch']}', if (d['creator'] != null) 'by ${d['creator']}'].join(' · '),
          trailing: Padding(padding: const EdgeInsets.only(right: Space.xs), child: statePill(state)),
        ),
        pad(_Steps(state: state), top: Space.s),
        if (live) pad(ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 4, color: AppColors.warning, backgroundColor: AppColors.surface2))),
        if (started != null)
          pad(
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: AppColors.text3),
                const SizedBox(width: 4),
                Elapsed(from: started, until: live ? null : (done ?? started)),
                const Spacer(),
                if (widget.files.isNotEmpty) Text('${widget.files.length} file${widget.files.length == 1 ? '' : 's'}', style: context.text.labelSmall),
              ],
            ),
          ),
        if (url != null && state == 'READY') pad(WebPreview(url: url, height: 210, onTap: open)),
        if (url != null && state != 'READY')
          pad(
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: AppColors.text3),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(url.replaceFirst('https://', ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text3))),
                ],
              ),
            ),
          ),
        if (d['commit'] != null) pad(Text('${d['commit']}'.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall)),
        if (d['error'] != null)
          pad(
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.s)),
              child: Text.rich(TextSpan(style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.danger), children: highlightLog('${d['error']}'))),
            ),
          ),
        pad(
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (url != null && state == 'READY') FilledButton.icon(onPressed: () => openUrl(url), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Visit')),
              if (widget.sourceHtml != null)
                OutlinedButton.icon(
                  onPressed: () => showHtmlPreview(context, widget.sourceHtml!, title: '${d['name'] ?? 'Page'} source'),
                  icon: const Icon(Icons.code_rounded, size: 18),
                  label: const Text('Preview source'),
                ),
              OutlinedButton.icon(onPressed: open, icon: Icon(live ? Icons.terminal_rounded : Icons.receipt_long_rounded, size: 18), label: Text(live ? 'Watch build' : 'Logs')),
              ..._deploymentActions(context, ref, d, replace),
            ],
          ),
        ),
      ],
    );
  }
}

/// Promote, Redeploy and Cancel, as they apply to [d].
List<Widget> _deploymentActions(BuildContext context, WidgetRef ref, Map<String, dynamic> d, void Function(Map<String, dynamic>) replace) {
  final state = '${d['state'] ?? ''}'.toUpperCase();
  final live = _live(state);
  return [
    if (state == 'READY' && d['target'] != 'production' && d['project_id'] != null)
      ActionButton(
        label: 'Promote',
        icon: Icons.rocket_launch_outlined,
        done: 'Now in production',
        onRun: () => devRun(context, ref, 'vercel_promote', {'project': d['project_id'], 'deployment': d['id']},
            confirmTitle: 'Promote to production?', confirmMessage: 'Production domains will serve this deployment.', confirmLabel: 'Promote'),
      ),
    if (!live)
      ActionButton(
        label: 'Redeploy',
        icon: Icons.replay_rounded,
        onRun: () async {
          final r = await devRun(context, ref, 'vercel_redeploy', {'deployment': d['id']},
              confirmTitle: 'Redeploy?', confirmMessage: 'Builds this deployment again from the same source.', confirmLabel: 'Redeploy');
          if (r['deployment'] is Map) replace(_m(r['deployment']));
        },
      ),
    if (live)
      ActionButton(
        label: 'Cancel',
        icon: Icons.stop_circle_outlined,
        danger: true,
        onRun: () async {
          final r = await devRun(context, ref, 'vercel_cancel_deployment', {'deployment': d['id']},
              confirmTitle: 'Cancel this build?', confirmMessage: 'It stops and the deployment won\'t go live.', confirmLabel: 'Cancel build');
          if (r['deployment'] is Map) replace(_m(r['deployment']));
        },
      ),
  ];
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state});
  final String label;

  /// done, live, error or todo.
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'done' => AppColors.success,
      'live' => AppColors.warning,
      'error' => AppColors.danger,
      _ => AppColors.text3,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color.withValues(alpha: state == 'todo' ? 0.08 : 0.18), shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
          child: switch (state) {
            'done' => Icon(Icons.check_rounded, size: 14, color: color),
            'error' => Icon(Icons.close_rounded, size: 14, color: color),
            'live' => Padding(padding: const EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2, color: color)),
            _ => null,
          },
        ),
        const SizedBox(height: 3),
        Text(label, style: context.text.labelSmall?.copyWith(color: state == 'todo' ? AppColors.text3 : color)),
      ],
    );
  }
}

/// A deployment in a sheet: Visit, a live preview of the site, actions,
/// details, and the build log, which keeps tailing while it builds.
Future<void> showVercelDeployment(BuildContext context, String id) => showDevSheet(
  context,
  brand: DevBrand.vercel,
  title: 'Deployment',
  subtitle: id,
  builder: (context, scroll) => _DeploymentSheet(id: id, scroll: scroll),
);

class _DeploymentSheet extends ConsumerStatefulWidget {
  const _DeploymentSheet({required this.id, required this.scroll});
  final String id;
  final ScrollController scroll;
  @override
  ConsumerState<_DeploymentSheet> createState() => _DeploymentSheetState();
}

class _DeploymentSheetState extends ConsumerState<_DeploymentSheet> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _lines = const [];
  String? _error;
  String? _logError;
  Timer? _timer;
  bool _errorsOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final runner = ref.read(toolRunnerProvider);
    final id = _d?['id'] ?? widget.id;
    try {
      final results = await Future.wait([
        runner.run('vercel_deployment', {'deployment': id}),
        runner.run('vercel_build_logs', {'deployment': id, 'limit': 800}),
      ]);
      if (!mounted) return;
      setState(() {
        _error = results[0].json['error'] as String?;
        if (results[0].json['deployment'] is Map) _d = _m(results[0].json['deployment']);
        if (results[1].json['lines'] is List) _lines = _l(results[1].json['lines']);
        _logError = results[1].json['error'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    _timer?.cancel();
    if (mounted && _d != null && _live(_d!['state'])) _timer = Timer(const Duration(seconds: 3), _load);
  }

  void _replace(Map<String, dynamic> next) {
    setState(() => _d = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return _error != null
          ? Padding(padding: const EdgeInsets.all(Space.l), child: Text(_error!, style: TextStyle(color: AppColors.danger)))
          : const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    final state = '${d['state'] ?? ''}'.toUpperCase();
    final live = _live(state);
    final url = _bestUrl(d);
    final started = parseWhen(d['building_at'] ?? d['created']);
    final lines = _errorsOnly ? _lines.where((l) => l['type'] == 'stderr' || l['type'] == 'warning').toList() : _lines;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        _VisitBar(
          url: state == 'READY' ? url : null,
          onLogs: () => showLogViewer(context, title: 'Build log', subtitle: '${d['name'] ?? ''} · ${d['id']}', lines: _lines),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Row(
            children: [
              statePill(state),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  [d['target'] == 'production' ? 'Production' : 'Preview', if (d['branch'] != null) '${d['branch']}', if (d['sha'] != null) '${d['sha']}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ),
              if (started != null) Elapsed(from: started, until: live ? null : (parseWhen(d['ready']) ?? started)),
            ],
          ),
        ),
        if (live) Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0), child: _Steps(state: state)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: state == 'READY' && url != null
              ? WebPreview(url: url, height: 360, interactive: true)
              : Container(
                  height: 150,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (live) const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.4)) else Icon(state == 'ERROR' ? Icons.error_outline_rounded : Icons.web_asset_off_rounded, size: 30, color: stateColor(state)),
                      const SizedBox(height: Space.s),
                      Text(live ? 'The preview appears when the build is ready' : (state == 'ERROR' ? 'The build failed: see the log below' : 'Nothing to preview'), style: context.text.bodySmall),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Wrap(spacing: Space.s, runSpacing: Space.s, children: _deploymentActions(context, ref, d, _replace)),
        ),
        if (d['error'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.s)),
              child: Text('${d['error']}', style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          ),
        SheetLabel(
          'Build log · ${_lines.length} lines${live ? ' · live' : ''}',
          trailing: FilterChip(
            visualDensity: VisualDensity.compact,
            label: const Text('Errors only'),
            selected: _errorsOnly,
            onSelected: (v) => setState(() => _errorsOnly = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: _logError != null && _lines.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(Space.m),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.s)),
                  child: Text('Couldn\'t load the log: $_logError', style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
                )
              : _Terminal(lines: lines, max: 400, title: 'Build log', subtitle: '${d['name'] ?? ''}'),
        ),
        const SheetLabel('Details'),
        SheetGroup(
          children: [
            for (final (k, label) in const [
              ('id', 'ID'),
              ('url', 'URL'),
              ('target', 'Target'),
              ('branch', 'Branch'),
              ('sha', 'Commit'),
              ('commit', 'Message'),
              ('repo', 'Repository'),
              ('creator', 'By'),
              ('source', 'Source'),
              ('created', 'Created'),
              ('ready', 'Ready'),
              ('inspector_url', 'Inspector'),
            ])
              if (d[k] != null) CopyRow(label: label, value: '${d[k]}', mono: k != 'commit'),
            for (final a in (d['aliases'] as List? ?? const [])) CopyRow(label: 'Alias', value: 'https://$a'),
          ],
        ),
      ],
    );
  }
}

// ---- logs ------------------------------------------------------------------------------

class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.deployment, required this.lines});
  final Map<String, dynamic> deployment;
  final List<Map<String, dynamic>> lines;

  @override
  Widget build(BuildContext context) {
    final errors = lines.where((l) => l['type'] == 'stderr').length;
    final warnings = lines.where((l) => l['type'] == 'warning').length;
    void open() => showVercelDeployment(context, '${deployment['id']}');
    return DevPanel(
      danger: deployment['state'] == 'ERROR',
      onTap: open,
      children: [
        DevHead(
          brand: DevBrand.vercel,
          title: 'Build log · ${deployment['name'] ?? ''}',
          subtitle: '${lines.length} lines',
          trailing: Padding(padding: const EdgeInsets.only(right: Space.xs), child: statePill(deployment['state'])),
        ),
        if (errors + warnings > 0)
          pad(
            Wrap(spacing: 6, children: [
              if (errors > 0) Pill('$errors errors', color: AppColors.danger, icon: Icons.error_outline_rounded),
              if (warnings > 0) Pill('$warnings warnings', color: AppColors.warning, icon: Icons.warning_amber_rounded),
            ]),
          ),
        pad(_Terminal(lines: lines, max: 30, title: 'Build log', subtitle: '${deployment['name'] ?? ''}')),
        pad(Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: open, icon: const Icon(Icons.open_in_full_rounded, size: 18), label: const Text('Full log & deployment')))),
      ],
    );
  }
}

class _RuntimeLogsCard extends ConsumerStatefulWidget {
  const _RuntimeLogsCard({required this.lines, required this.args, this.note, this.embedded = false});
  final List<Map<String, dynamic>> lines;
  final Map<String, dynamic> args;
  final String? note;
  final bool embedded;
  @override
  ConsumerState<_RuntimeLogsCard> createState() => _RuntimeLogsCardState();
}

class _RuntimeLogsCardState extends ConsumerState<_RuntimeLogsCard> {
  late List<Map<String, dynamic>> _lines = widget.lines;
  bool _busy = false;

  Future<void> _more() async {
    setState(() => _busy = true);
    try {
      final r = await devRun(context, ref, 'vercel_runtime_logs', {...widget.args, 'seconds': 8});
      if (mounted) setState(() => _lines = [..._lines, ..._l(r['lines'])]);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failures = _lines.where((l) => l['status'] is num && (l['status'] as num) >= 400).length;
    return DevPanel(
      onTap: widget.embedded ? null : () => showVercelRuntimeLogs(context, '${widget.args['project'] ?? ''}'),
      children: [
        DevHead(
          brand: DevBrand.vercel,
          title: 'Runtime logs · ${widget.args['project'] ?? ''}',
          subtitle: '${_lines.length} lines${failures > 0 ? ' · $failures failed requests' : ''}',
          trailing: _busy
              ? const Padding(padding: EdgeInsets.all(Space.s), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(tooltip: 'Listen again', icon: const Icon(Icons.refresh_rounded, size: 18), onPressed: _more),
        ),
        if (_lines.isEmpty) pad(Text(widget.note ?? 'Nothing logged while listening.', style: context.text.bodySmall)) else pad(_Terminal(lines: _lines, max: widget.embedded ? 1000 : 40, numbers: false, title: 'Runtime logs', subtitle: '${widget.args['project'] ?? ''}')),
      ],
    );
  }
}

/// Live runtime logs in a sheet, listening again on refresh.
Future<void> showVercelRuntimeLogs(BuildContext context, String project) => showDevSheet(
  context,
  brand: DevBrand.vercel,
  title: 'Runtime logs',
  subtitle: project,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'vercel_runtime_logs', {'project': project, 'seconds': 8}),
      builder: (context, j, reload) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Space.l),
        children: [_RuntimeLogsCard(lines: _l(j['lines']), args: {'project': project}, note: j['note'] as String?, embedded: true)],
      ),
    ),
  ),
);

// ---- env, domains, DNS -----------------------------------------------------------------

class _EnvCard extends StatefulWidget {
  const _EnvCard({required this.project, required this.env, this.embedded = false});
  final String project;
  final List<Map<String, dynamic>> env;
  final bool embedded;
  @override
  State<_EnvCard> createState() => _EnvCardState();
}

class _EnvCardState extends State<_EnvCard> {
  final _shown = <String>{};

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (i, e) in (widget.embedded ? widget.env : widget.env.take(12)).indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(e['type'] == 'sensitive' ? Icons.lock_rounded : Icons.key_rounded, size: 14, color: AppColors.text3),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${e['key']}', style: codeTextStyle.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
                  if (e['value'] != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(_shown.contains('${e['id']}') ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
                      onPressed: () => setState(() => _shown.contains('${e['id']}') ? _shown.remove('${e['id']}') : _shown.add('${e['id']}')),
                    ),
                  if (e['value'] != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '${e['value']}'));
                        showSnack(context, '${e['key']} copied');
                      },
                    ),
                ],
              ),
              if (e['value'] != null)
                Text(
                  _shown.contains('${e['id']}') ? '${e['value']}' : '•' * '${e['value']}'.length.clamp(6, 24),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.text2),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in (e['targets'] as List? ?? const []))
                    Pill('$t', color: switch ('$t') {
                      'production' => AppColors.success,
                      'preview' => AppColors.accent,
                      _ => AppColors.text2,
                    }),
                  if (e['branch'] != null) Pill('${e['branch']}', color: AppColors.warning, icon: Icons.call_split_rounded),
                  Pill('${e['type']}', color: AppColors.text3),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
    if (widget.embedded) return SheetGroup(children: rows.isEmpty ? [pad(const Text('No variables.'), top: Space.m)] : rows);
    return DevPanel(
      onTap: () => showDevSheet(
        context,
        brand: DevBrand.vercel,
        title: 'Environment',
        subtitle: widget.project,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          children: [Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: _EnvCard(project: widget.project, env: widget.env, embedded: true))],
        ),
      ),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Environment · ${widget.project}', subtitle: '${widget.env.length} variables'),
        ...rows,
        if (widget.env.length > 12) MoreRow(label: 'All ${widget.env.length}', onTap: null),
        const SizedBox(height: Space.xs),
      ],
    );
  }
}

/// One domain in a sheet: its configuration, name servers and the records Vercel expects.
Future<void> showVercelDomain(BuildContext context, String domain) => showDevSheet(
  context,
  brand: DevBrand.vercel,
  title: domain,
  subtitle: 'Domain',
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'vercel_domains', {'domain': domain}),
      builder: (context, j, _) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          _VisitBar(url: 'https://$domain'),
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0), child: WebPreview(url: 'https://$domain', height: 280, interactive: true)),
          Padding(padding: const EdgeInsets.all(Space.l), child: _DomainConfigCard(domain: _m(j['domain']), config: _m(j['config']), embedded: true)),
          const SheetLabel('Everything'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: JsonTree(value: j, openDepth: 1)),
        ],
      ),
    ),
  ),
);

class _DomainList extends StatelessWidget {
  const _DomainList({required this.domains, this.project});
  final List<Map<String, dynamic>> domains;
  final String? project;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => showJsonSheet(context, brand: DevBrand.vercel, title: 'Domains', subtitle: project, value: domains),
    children: [
      DevHead(brand: DevBrand.vercel, title: 'Domains${project == null ? '' : ' · $project'} · ${domains.length}'),
      for (final d in domains.take(40))
        ListTile(
          dense: true,
          onTap: () => showVercelDomain(context, '${d['name']}'),
          leading: lead(Icon(d['verified'] == true ? Icons.verified_rounded : Icons.error_outline_rounded, color: d['verified'] == true ? AppColors.success : AppColors.warning)),
          title: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              if (d['redirect'] != null) '→ ${d['redirect']}',
              if (d['git_branch'] != null) 'branch ${d['git_branch']}',
              if (d['service_type'] != null) '${d['service_type']}',
              if (d['expires'] != null) 'renews ${ago(d['expires'])}',
              if (d['verification'] != null) 'needs DNS verification',
            ].join(' · '),
          ),
          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
        ),
    ],
  );
}

class _DomainConfigCard extends StatelessWidget {
  const _DomainConfigCard({required this.domain, required this.config, this.embedded = false});
  final Map<String, dynamic> domain;
  final Map<String, dynamic> config;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final bad = config['misconfigured'] == true;
    return DevPanel(
      glow: bad ? AppColors.warning : AppColors.success,
      onTap: embedded ? null : () => showVercelDomain(context, '${domain['name']}'),
      children: [
        DevHead(
          brand: DevBrand.vercel,
          title: '${domain['name']}',
          subtitle: '${domain['service_type'] ?? ''}',
          trailing: Padding(padding: const EdgeInsets.only(right: Space.xs), child: Pill(bad ? 'Misconfigured' : 'Configured', color: bad ? AppColors.warning : AppColors.success)),
        ),
        if (domain['name_servers'] is List) CopyRow(label: 'Name servers', value: (domain['name_servers'] as List).join('\n')),
        if (config['configuredBy'] != null) CopyRow(label: 'Set up by', value: '${config['configuredBy']}', mono: false),
        for (final ip in (config['aValues'] as List? ?? const [])) CopyRow(label: 'A record', value: '$ip'),
        for (final c in (config['cnames'] as List? ?? const [])) CopyRow(label: 'CNAME', value: '$c'),
        if (domain['expires'] != null) CopyRow(label: 'Expires', value: '${domain['expires']}', mono: false),
        const SizedBox(height: Space.s),
      ],
    );
  }
}

class _DomainCheckCard extends StatelessWidget {
  const _DomainCheckCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final ok = j['available'] == true;
    return DevPanel(
      glow: ok ? AppColors.success : null,
      onTap: () => showJsonSheet(context, brand: DevBrand.vercel, title: '${j['domain']}', subtitle: 'Domain check', value: j),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Domain check'),
        ListTile(
          leading: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_outlined, color: ok ? AppColors.success : AppColors.text3, size: 30),
          title: Text('${j['domain']}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(ok ? 'Available${j['price'] == null ? '' : ' · \$${j['price']}${j['period'] == null ? '' : ' for ${j['period']} yr'}'}' : (j['available'] == false ? 'Taken' : '${j['problem'] ?? 'Unknown'}')),
        ),
      ],
    );
  }
}

class _DnsCard extends StatelessWidget {
  const _DnsCard({required this.domain, required this.records});
  final String domain;
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => showJsonSheet(context, brand: DevBrand.vercel, title: 'DNS · $domain', subtitle: '${records.length} records', value: records),
    children: [
      DevHead(brand: DevBrand.vercel, title: 'DNS · $domain · ${records.length}'),
      for (final (i, r) in records.take(40).indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: '${r['value']}'));
            showSnack(context, 'Value copied');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6)),
                  child: Text('${r['type']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${'${r['name']}'.isEmpty ? '@' : r['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${r['mx_priority'] == null ? '' : '${r['mx_priority']} '}${r['value']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.text2)),
                    ],
                  ),
                ),
                Text('${r['ttl'] ?? ''}s', style: context.text.labelSmall),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

// ---- usage -----------------------------------------------------------------------------

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.j, this.embedded = false});
  final Map<String, dynamic> j;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final services = _l(j['by_service']);
    final days = _l(j['by_day']);
    final top = services.isEmpty ? 1.0 : (services.first['cost'] as num).toDouble();
    final peak = days.fold<double>(0, (m, d) => (d['cost'] as num).toDouble() > m ? (d['cost'] as num).toDouble() : m);
    final cur = '${j['currency'] ?? 'USD'}' == 'USD' ? '\$' : '${j['currency']} ';
    return DevPanel(
      onTap: embedded
          ? null
          : () => showDevSheet(
              context,
              brand: DevBrand.vercel,
              title: 'Usage',
              subtitle: 'last ${j['days']} days',
              builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(Space.l), children: [_UsageCard(j: j, embedded: true)]),
            ),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Usage · last ${j['days']} days'),
        pad(
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$cur${(j['total'] as num? ?? 0).toStringAsFixed(2)}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
              const SizedBox(width: Space.s),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('billed', style: context.text.bodySmall)),
            ],
          ),
        ),
        if (days.length > 1)
          pad(
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Tooltip(
                        message: '${d['day']}: $cur${d['cost']}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: peak <= 0 ? 2 : (56 * (d['cost'] as num).toDouble() / peak).clamp(2, 56),
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.75), borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        for (final s in (embedded ? services : services.take(6)))
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${s['service']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall)),
                    Text('$cur${(s['cost'] as num).toStringAsFixed(2)}', style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                  ],
                ),
                const SizedBox(height: 3),
                ShareBar(value: top <= 0 ? 0 : (s['cost'] as num).toDouble() / top),
              ],
            ),
          ),
        if (embedded)
          for (final d in days.reversed) CopyRow(label: '${d['day']}', value: '$cur${d['cost']}', mono: false),
        if (services.isEmpty) pad(Text('${j['note'] ?? 'No billed usage.'}', style: context.text.bodySmall)),
      ],
    );
  }
}

// ---- files, edge config, rows ----------------------------------------------------------

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.deployment, required this.files});
  final Map<String, dynamic> deployment;
  final List<Map<String, dynamic>> files;

  @override
  Widget build(BuildContext context) {
    final total = files.fold<num>(0, (s, f) => s + ((f['size'] as num?) ?? 0));
    return DevPanel(
      onTap: () => showVercelDeployment(context, '${deployment['id']}'),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Files · ${deployment['name'] ?? ''}', subtitle: '${files.length} files${total > 0 ? ' · ${bytes(total)}' : ''}'),
        for (final f in files.take(30))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 3),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 15, color: AppColors.text3),
                const SizedBox(width: Space.s),
                Expanded(child: Text('${f['path']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 12))),
                Text(bytes(f['size']), style: context.text.labelSmall),
              ],
            ),
          ),
        if (files.length > 30) pad(Text('${files.length - 30} more', style: context.text.labelSmall), top: Space.xs),
        const SizedBox(height: Space.s),
      ],
    );
  }
}

class _EdgeItems extends StatelessWidget {
  const _EdgeItems({required this.id, required this.items});
  final String id;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final tree = {for (final i in items) '${i['key']}': i['value']};
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: DevBrand.vercel, title: 'Edge Config', subtitle: id, value: tree),
      children: [
        DevHead(brand: DevBrand.vercel, title: 'Edge Config · ${items.length} items', subtitle: id),
        pad(JsonTree(value: tree, openDepth: 1)),
      ],
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.title, required this.rows, required this.onOpen});
  final String title;
  final List<(IconData, String, String, String?)> rows;
  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => onOpen(context),
    children: [
      DevHead(brand: DevBrand.vercel, title: title),
      for (final (icon, t, sub, url) in rows.take(30))
        ListTile(
          dense: true,
          onTap: url == null ? () => onOpen(context) : () => openUrl(url),
          leading: lead(Icon(icon, size: 20, color: AppColors.text2)),
          title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Icon(url == null ? Icons.chevron_right_rounded : Icons.open_in_new_rounded, size: 16, color: AppColors.text3),
        ),
      if (rows.isEmpty) pad(Text('Nothing here.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

// ---- full-screen logs ------------------------------------------------------------------

/// A log full screen: numbered, highlighted lines. Tap a line to select
/// it, long-press another to select everything between; copy the
/// selection or all of it. Search, errors only, and wrapping long lines.
Future<void> showLogViewer(BuildContext context, {required String title, String? subtitle, required List<Map<String, dynamic>> lines}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _LogViewer(title: title, subtitle: subtitle, lines: lines)));

class _LogViewer extends StatefulWidget {
  const _LogViewer({required this.title, required this.lines, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> lines;
  @override
  State<_LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<_LogViewer> {
  final _selected = <int>{};
  int? _anchor;
  bool _errorsOnly = false;
  bool _wrap = true;
  bool _searching = false;
  String _q = '';
  final _scroll = ScrollController();

  static bool _isError(Map l) => l['type'] == 'stderr' || '${l['level']}' == 'error' || (l['status'] is num && (l['status'] as num) >= 400);
  static bool _isWarning(Map l) => l['type'] == 'warning' || '${l['level']}' == 'warning';

  static String _plain(Map l) => [
    if (l['status'] != null) '${l['status']}',
    if (l['method'] != null) '${l['method']} ${l['path'] ?? ''}',
    '${l['text'] ?? ''}',
  ].join(' ').trim();

  List<int> get _visible => [
    for (var i = 0; i < widget.lines.length; i++)
      if ((!_errorsOnly || _isError(widget.lines[i]) || _isWarning(widget.lines[i])) && (_q.isEmpty || _plain(widget.lines[i]).toLowerCase().contains(_q.toLowerCase()))) i,
  ];

  void _copy(Iterable<int> which, String what) {
    final text = [for (final i in which.toList()..sort()) _plain(widget.lines[i])].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$what copied');
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final errors = widget.lines.where(_isError).length;
    final width = '${widget.lines.length}'.length;
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0B0B0F)),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF111118),
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          // The app's titles take the page's text colour; this bar is always dark.
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          title: _searching
              ? TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(hintText: 'Search the log', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none),
                  onChanged: (v) => setState(() => _q = v),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(
                      [if (widget.subtitle != null && widget.subtitle!.isNotEmpty) widget.subtitle!, '${widget.lines.length} lines', if (errors > 0) '$errors errors'].join(' · '),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search',
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _q = '';
              }),
            ),
            IconButton(
              tooltip: _errorsOnly ? 'Show every line' : 'Errors and warnings only',
              icon: Icon(Icons.error_outline_rounded, color: _errorsOnly ? const Color(0xFFFF6B6B) : null),
              onPressed: () => setState(() => _errorsOnly = !_errorsOnly),
            ),
            IconButton(tooltip: _wrap ? 'Don\'t wrap' : 'Wrap lines', icon: Icon(_wrap ? Icons.wrap_text_rounded : Icons.notes_rounded), onPressed: () => setState(() => _wrap = !_wrap)),
            IconButton(tooltip: 'Copy all', icon: const Icon(Icons.copy_all_rounded), onPressed: () => _copy(visible, '${visible.length} lines')),
          ],
        ),
        body: visible.isEmpty
            ? Center(child: Text(_q.isEmpty ? 'No lines.' : 'Nothing matches "$_q".', style: const TextStyle(color: Colors.white54)))
            : Scrollbar(
                controller: _scroll,
                interactive: true,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  itemCount: visible.length,
                  itemBuilder: (context, k) {
                    final i = visible[k];
                    final l = widget.lines[i];
                    final selected = _selected.contains(i);
                    final row = Text.rich(
                      TextSpan(
                        style: codeTextStyle.copyWith(fontSize: 12, height: 1.45, color: const Color(0xFFD4D4D8)),
                        children: [
                          if (l['status'] != null)
                            TextSpan(text: '${l['status']} ', style: TextStyle(color: _isError(l) ? const Color(0xFFFF6B6B) : const Color(0xFF4ADE80), fontWeight: FontWeight.w700)),
                          if (l['method'] != null) TextSpan(text: '${l['method']} ${l['path'] ?? ''}  ', style: const TextStyle(color: Color(0xFF93C5FD))),
                          ...highlightLog('${l['text'] ?? ''}', stderr: _isError(l)),
                        ],
                      ),
                      softWrap: _wrap,
                    );
                    return InkWell(
                      onTap: () => setState(() {
                        selected ? _selected.remove(i) : _selected.add(i);
                        _anchor = i;
                      }),
                      onLongPress: () => setState(() {
                        final from = _anchor ?? i;
                        for (final j in visible) {
                          if (j >= (from < i ? from : i) && j <= (from < i ? i : from)) _selected.add(j);
                        }
                        _anchor = i;
                      }),
                      child: Container(
                        color: selected
                            ? const Color(0xFF2563EB).withValues(alpha: 0.28)
                            : (_isError(l) ? const Color(0xFFFF6B6B).withValues(alpha: 0.07) : null),
                        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}'.padLeft(width), style: codeTextStyle.copyWith(fontSize: 12, height: 1.45, color: selected ? Colors.white : const Color(0xFF52525B))),
                            const SizedBox(width: Space.m),
                            Expanded(child: _wrap ? row : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
        bottomNavigationBar: _selected.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  color: const Color(0xFF111118),
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${_selected.length} line${_selected.length == 1 ? '' : 's'} selected', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                      ),
                      TextButton(onPressed: () => setState(_selected.clear), style: TextButton.styleFrom(foregroundColor: Colors.white70), child: const Text('Clear')),
                      const SizedBox(width: Space.s),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        tooltip: 'Copy',
                        onPressed: () => _copy(_selected, '${_selected.length} lines'),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

// ---- for the Vercel manager page -------------------------------------------------------

/// A project row that opens the project sheet.
class VercelProjectTile extends StatelessWidget {
  const VercelProjectTile(this.project, {super.key});
  final Map<String, dynamic> project;
  @override
  Widget build(BuildContext context) => _ProjectRow(p: project);
}

/// A deployment row that follows its build and opens its sheet.
class VercelDeploymentTile extends StatelessWidget {
  const VercelDeploymentTile(this.deployment, {super.key});
  final Map<String, dynamic> deployment;
  @override
  Widget build(BuildContext context) => _LiveRow(initial: deployment);
}

/// The usage chart and breakdown.
class VercelUsageView extends StatelessWidget {
  const VercelUsageView(this.usage, {super.key});
  final Map<String, dynamic> usage;
  @override
  Widget build(BuildContext context) => _UsageCard(j: usage, embedded: true);
}

/// A project's monogram tile.
class VercelMonogram extends StatelessWidget {
  const VercelMonogram(this.name, {super.key, this.size = 40});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => _Monogram(name, size: size);
}
