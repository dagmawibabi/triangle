import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../chat/presentation/widgets/dev/dev_card_kit.dart';
import '../chat/presentation/widgets/dev/mongo_cards.dart' show showMongoDatabase;
import '../chat/presentation/widgets/dev/resend_cards.dart' show showResendDomain;
import '../chat/presentation/widgets/dev/vercel_cards.dart' show showVercelProject, statePill;
import '../settings/data/settings.dart';
import '../settings/presentation/cloud_settings.dart' show CloudflareTab, KeyField;
import '../settings/presentation/tools_screen.dart' show ServiceTools, ToolGroup, ToolsScreen;
import '../telegram/data/telegram_tools.dart' show ToolCategory, telegramTools;
import 'dev_apis.dart';
import 'mongo_session.dart';
import 'manage/managers.dart';

/// The services under Settings → Development.
enum DevService {
  vercel('Vercel', DevBrand.vercel, {ToolCategory.vercel}),
  resend('Resend', DevBrand.resend, {ToolCategory.resend}),
  mongodb('MongoDB', DevBrand.mongodb, {ToolCategory.mongodb}),
  cloudflare('Cloudflare', DevBrand.cloudflare, {ToolCategory.cloudflare, ToolCategory.r2});

  const DevService(this.label, this.brand, this.categories);
  final String label;
  final DevBrand brand;
  final Set<ToolCategory> categories;

  bool ready(AppSettings s) => switch (this) {
    vercel => s.hasVercelToken,
    resend => s.hasResendKey,
    mongodb => s.hasMongoUri,
    cloudflare => s.hasCloudflare,
  };

  int get toolCount => telegramTools.where((t) => categories.contains(t.category)).length;

  static DevService of(ToolCategory c) => DevService.values.firstWhere((s) => s.categories.contains(c), orElse: () => DevService.vercel);
}

/// Settings → Development: the developer platforms the assistant reaches
/// with your own keys (Vercel, Resend, MongoDB, Cloudflare), each with its
/// key, a live look at the account, and its tools by what they do.
class DevelopmentScreen extends ConsumerWidget {
  const DevelopmentScreen({super.key, this.service = DevService.vercel});
  final DevService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return DefaultTabController(
      length: DevService.values.length,
      initialIndex: service.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Development'),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ToolsScreen(group: ToolGroup.development))),
              icon: const Icon(Icons.handyman_outlined, size: 18),
              label: const Text('All tools'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final d in DevService.values)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DevMark(d.brand, size: 16),
                      const SizedBox(width: Space.s),
                      Text(d.label),
                      if (d.ready(s)) ...[const SizedBox(width: 4), Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success)],
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _VercelTab(),
            const _ResendTab(),
            const _MongoTab(),
            CloudflareTab(
              onManage: () => _manage(context, DevService.cloudflare),
              extra: [_Box('Tools · ${DevService.cloudflare.toolCount}', children: [_tools(DevService.cloudflare)])]),
          ],
        ),
      ),
    );
  }
}

/// The service's full manager page.
void _manage(BuildContext context, DevService d) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => switch (d) {
      DevService.vercel => const VercelManagerScreen(),
      DevService.resend => const ResendManagerScreen(),
      DevService.mongodb => const MongoManagerScreen(),
      DevService.cloudflare => const CloudflareManagerScreen(),
    },
  ),
);

/// "Manage", once [d] is connected.
Widget? _manageButton(BuildContext context, AppSettings s, DevService d) => d.ready(s)
    ? FilledButton.tonalIcon(onPressed: () => _manage(context, d), icon: const Icon(Icons.dashboard_customize_outlined, size: 16), label: const Text('Manage'))
    : null;

Widget _tools(DevService d) => Padding(padding: const EdgeInsets.all(Space.m), child: ServiceTools(categories: d.categories));

class _Box extends StatelessWidget {
  const _Box(this.title, {required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
        child: Row(children: [Expanded(child: Text(title.toUpperCase(), style: context.text.labelSmall)), ?trailing]),
      ),
      Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ),
    ],
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4), children: children);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.brand, required this.text, required this.points});
  final DevBrand brand;
  final String text;
  final List<(IconData, String)> points;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.l),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [DevMark(brand, size: 32), const SizedBox(width: Space.m), Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(height: 1.4)))]),
        const SizedBox(height: Space.m),
        for (final (icon, p) in points)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Icon(icon, size: 16, color: AppColors.text2), const SizedBox(width: Space.s), Expanded(child: Text(p, style: context.text.bodySmall))],
            ),
          ),
      ],
    ),
  );
}

Widget _errorText(BuildContext context, String e) => Padding(
  padding: const EdgeInsets.all(Space.l),
  child: Text(e, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
);

Widget _refresh(bool loading, VoidCallback onTap) => loading
    ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
    : InkWell(onTap: onTap, child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.text3));

// ---- Vercel ----------------------------------------------------------------------------

class _VercelTab extends ConsumerStatefulWidget {
  const _VercelTab();
  @override
  ConsumerState<_VercelTab> createState() => _VercelTabState();
}

class _VercelTabState extends ConsumerState<_VercelTab> {
  Map? _user;
  List<Map> _teams = const [];
  List<Map> _projects = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final s = ref.read(settingsProvider);
    if (!s.hasVercelToken) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = VercelApi(token: s.vercelToken, teamId: s.vercelTeamId);
    try {
      final u = await api.call('GET', '/v2/user') as Map;
      List<Map> teams = const [];
      try {
        final t = await api.call('GET', '/v2/teams', query: {'limit': '50'}) as Map;
        teams = (t['teams'] as List? ?? const []).whereType<Map>().toList();
      } catch (_) {}
      final p = await api.call('GET', '/v9/projects', query: {'limit': '20'}) as Map;
      if (mounted) {
        setState(() {
          _user = u['user'] as Map? ?? u;
          _teams = teams;
          _projects = (p['projects'] as List? ?? const []).whereType<Map>().toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    return _Page(
      onRefresh: _load,
      children: [
        const _Intro(
          brand: DevBrand.vercel,
          text: 'The assistant can see and run your Vercel projects: deployments as they build, logs, env vars, domains, DNS and usage. It can also publish files from a chat to a live URL.',
          points: [
            (Icons.visibility_outlined, 'Reading runs without asking.'),
            (Icons.edit_outlined, 'Deploying, promoting, rolling back and editing env vars or domains ask first.'),
            (Icons.delete_outline_rounded, 'Deleting is a destructive tool: off until you turn it on, and it always asks.'),
          ],
        ),
        _Box(
          'Access',
          children: [
            KeyField(
              label: 'Access token',
              hint: 'vercel.com → Account Settings → Tokens',
              value: s.vercelToken,
              secret: true,
              onSave: (v) async {
                await ctl.setVercelToken(v);
                unawaited(_load());
              },
              verify: (k) async {
                final api = VercelApi(token: k);
                try {
                  await api.call('GET', '/v2/user');
                  return null;
                } catch (e) {
                  return '$e';
                } finally {
                  api.close();
                }
              },
              help: Uri.parse('https://vercel.com/account/settings/tokens'),
              action: _manageButton(context, s, DevService.vercel),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              child: Text('This is a different key from the AI Gateway key in AI & models. Scope the token to the team you want the assistant to reach.', style: context.text.bodySmall),
            ),
            if (_teams.isNotEmpty) ...[
              const Divider(indent: Space.l, endIndent: Space.l),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                child: DropdownButtonFormField<String>(
                  initialValue: _teams.any((t) => t['id'] == s.vercelTeamId) ? s.vercelTeamId : '',
                  decoration: const InputDecoration(labelText: 'Act on', isDense: true),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Personal account')),
                    for (final t in _teams) DropdownMenuItem(value: '${t['id']}', child: Text('${t['name']}')),
                  ],
                  onChanged: (v) async {
                    await ctl.setVercelTeamId(v ?? '');
                    unawaited(_load());
                  },
                ),
              ),
            ] else if (s.hasVercelToken)
              KeyField(label: 'Team ID (optional)', hint: 'team_…', value: s.vercelTeamId, onSave: ctl.setVercelTeamId),
          ],
        ),
        if (s.hasVercelToken)
          _Box(
            'Your projects',
            trailing: _refresh(_loading, _load),
            children: [
              if (_error != null) _errorText(context, _error!),
              if (_user != null)
                ListTile(
                  leading: lead(const Icon(Icons.account_circle_outlined)),
                  title: Text('${_user!['name'] ?? _user!['username']}'),
                  subtitle: Text('@${_user!['username']} · ${s.vercelTeamId.isEmpty ? 'personal account' : (_teams.where((t) => t['id'] == s.vercelTeamId).firstOrNull?['name'] ?? s.vercelTeamId)}'),
                ),
              for (final p in _projects)
                ListTile(
                  dense: true,
                  onTap: () => showVercelProject(context, '${p['name']}'),
                  leading: lead(Icon(Icons.folder_outlined, color: AppColors.text2)),
                  title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p['framework'] ?? 'other'} · ${ago(p['updatedAt'])}'),
                  trailing: (p['latestDeployments'] as List?)?.isNotEmpty == true
                      ? statePill(((p['latestDeployments'] as List).first as Map)['readyState'])
                      : null,
                ),
              if (!_loading && _error == null && _projects.isEmpty && _user != null)
                Padding(padding: const EdgeInsets.all(Space.l), child: Text('No projects on this account yet.', style: context.text.bodySmall)),
            ],
          ),
        _Box('Tools · ${DevService.vercel.toolCount}', children: [_tools(DevService.vercel)]),
      ],
    );
  }
}

// ---- Resend ----------------------------------------------------------------------------

class _ResendTab extends ConsumerStatefulWidget {
  const _ResendTab();
  @override
  ConsumerState<_ResendTab> createState() => _ResendTabState();
}

class _ResendTabState extends ConsumerState<_ResendTab> {
  List<Map>? _domains;
  int? _sent;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final s = ref.read(settingsProvider);
    if (!s.hasResendKey) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ResendApi(key: s.resendKey);
    try {
      final d = await api.call('GET', '/domains') as Map;
      int? sent;
      try {
        final e = await api.call('GET', '/emails', query: {'limit': '100'}) as Map;
        sent = (e['data'] as List? ?? const []).length;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _domains = (d['data'] as List? ?? const []).whereType<Map>().toList();
          _sent = sent;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final verified = _domains?.where((d) => d['status'] == 'verified').toList() ?? const [];
    return _Page(
      onRefresh: _load,
      children: [
        const _Intro(
          brand: DevBrand.resend,
          text: 'The assistant can send email from your own domain through Resend, with chat files as attachments or scheduled for later. It can also follow whether each email was delivered and manage domains, contacts and broadcasts.',
          points: [
            (Icons.front_hand_outlined, 'Every email asks you first. Batches and broadcasts always ask, whatever your approval setting.'),
            (Icons.delete_outline_rounded, 'Removing domains, keys, audiences or contacts is destructive and starts off.'),
          ],
        ),
        _Box(
          'Access',
          children: [
            KeyField(
              label: 'API key',
              hint: 're_…',
              value: s.resendKey,
              secret: true,
              onSave: (v) async {
                await ctl.setResendKey(v);
                unawaited(_load());
              },
              verify: (k) async {
                final api = ResendApi(key: k);
                try {
                  await api.call('GET', '/domains');
                  return null;
                } catch (e) {
                  return '$e';
                } finally {
                  api.close();
                }
              },
              help: Uri.parse('https://resend.com/api-keys'),
              action: _manageButton(context, s, DevService.resend),
            ),
            const Divider(indent: Space.l, endIndent: Space.l),
            KeyField(
              label: 'Send from',
              hint: verified.isEmpty ? 'Me <me@yourdomain.com>' : 'Me <me@${verified.first['name']}>',
              value: s.resendFrom,
              onSave: ctl.setResendFrom,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              child: Text('Used when the assistant isn\'t told who to send as. It must be on a verified domain below. Without one, onboarding@resend.dev can only email you.', style: context.text.bodySmall),
            ),
          ],
        ),
        if (s.hasResendKey)
          _Box(
            'Sending domains',
            trailing: _refresh(_loading, _load),
            children: [
              if (_error != null) _errorText(context, _error!),
              if (_sent != null)
                ListTile(dense: true, leading: lead(const Icon(Icons.outbox_outlined)), title: Text('$_sent${_sent == 100 ? '+' : ''} recent emails sent')),
              for (final d in _domains ?? const <Map>[])
                ListTile(
                  dense: true,
                  onTap: () => showResendDomain(context, '${d['id']}'),
                  leading: lead(Icon(d['status'] == 'verified' ? Icons.verified_rounded : Icons.pending_outlined, color: d['status'] == 'verified' ? AppColors.success : AppColors.warning)),
                  title: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${d['region'] ?? ''} · ${d['status']}'),
                  trailing: Icon(Icons.dns_outlined, size: 18, color: AppColors.text3),
                ),
              if (_domains != null && _domains!.isEmpty)
                Padding(padding: const EdgeInsets.all(Space.l), child: Text('No domains yet. Ask the assistant to add one, or add it at resend.com/domains.', style: context.text.bodySmall)),
            ],
          ),
        _Box('Tools · ${DevService.resend.toolCount}', children: [_tools(DevService.resend)]),
      ],
    );
  }
}

// ---- MongoDB ---------------------------------------------------------------------------

class _MongoTab extends ConsumerStatefulWidget {
  const _MongoTab();
  @override
  ConsumerState<_MongoTab> createState() => _MongoTabState();
}

class _MongoTabState extends ConsumerState<_MongoTab> {
  String? _version;
  List<Map>? _dbs;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final s = ref.read(settingsProvider);
    if (!s.hasMongoUri) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final m = MongoSession.instance;
    try {
      final info = await m.command(s.mongoUri, 'admin', {'buildInfo': 1});
      List<Map>? dbs;
      try {
        final r = await m.command(s.mongoUri, 'admin', {'listDatabases': 1, 'nameOnly': false, 'authorizedDatabases': true});
        dbs = (r['databases'] as List? ?? const []).whereType<Map>().toList();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _version = '${info['version']}';
          _dbs = dbs;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _size(Object? v) => v is num ? v : (v is Map ? num.tryParse('${v[r'$numberLong'] ?? 0}') ?? 0 : 0);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final current = s.mongoDatabase.isNotEmpty ? s.mongoDatabase : (MongoSession.databaseIn(s.mongoUri) ?? 'test');
    final top = (_dbs ?? const <Map>[]).fold<num>(1, (m, d) => _size(d['sizeOnDisk']) > m ? _size(d['sizeOnDisk']) : m);
    return _Page(
      onRefresh: _load,
      children: [
        const _Intro(
          brand: DevBrand.mongodb,
          text: 'The assistant connects straight to your MongoDB (Atlas or your own server) to browse databases, query and aggregate documents, infer schemas and explain slow queries. It can also export or import data and manage indexes.',
          points: [
            (Icons.visibility_outlined, 'Finding, counting, aggregating and stats run without asking.'),
            (Icons.edit_outlined, 'Inserting, updating, importing and creating indexes ask first.'),
            (Icons.delete_outline_rounded, 'Deleting documents and dropping collections or databases are destructive tools.'),
            (Icons.shield_outlined, 'Use a database user with only the roles you want the assistant to have, e.g. read for browsing.'),
          ],
        ),
        _Box(
          'Connection',
          children: [
            KeyField(
              label: 'Connection string',
              hint: 'mongodb+srv://user:password@cluster.mongodb.net/mydb',
              value: s.mongoUri,
              secret: true,
              onSave: (v) async {
                await MongoSession.instance.close();
                await ctl.setMongoUri(v);
                unawaited(_load());
              },
              verify: (k) async {
                if (!k.startsWith('mongodb://') && !k.startsWith('mongodb+srv://')) return 'It should start with mongodb:// or mongodb+srv://';
                try {
                  await MongoSession.instance.command(k, 'admin', {'ping': 1});
                  return null;
                } catch (e) {
                  return '$e';
                }
              },
              help: Uri.parse('https://www.mongodb.com/docs/manual/reference/connection-string/'),
              action: _manageButton(context, s, DevService.mongodb),
            ),
            if (s.hasMongoUri)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                child: Text('Server ${MongoSession.hostsOf(s.mongoUri)}. On Atlas, allow this phone\'s IP under Network Access.', style: context.text.bodySmall),
              ),
            const Divider(indent: Space.l, endIndent: Space.l),
            if (_dbs != null && _dbs!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
                child: DropdownButtonFormField<String>(
                  initialValue: _dbs!.any((d) => d['name'] == current) ? current : null,
                  decoration: const InputDecoration(labelText: 'Default database', isDense: true),
                  items: [for (final d in _dbs!) DropdownMenuItem(value: '${d['name']}', child: Text('${d['name']}'))],
                  onChanged: (v) => ctl.setMongoDatabase(v ?? ''),
                ),
              )
            else
              KeyField(label: 'Default database', hint: 'From the connection string when empty', value: s.mongoDatabase, onSave: ctl.setMongoDatabase),
          ],
        ),
        if (s.hasMongoUri)
          _Box(
            _version == null ? 'Server' : 'MongoDB $_version',
            trailing: _refresh(_loading, _load),
            children: [
              if (_error != null) _errorText(context, _error!),
              for (final d in _dbs ?? const <Map>[])
                InkWell(
                  onTap: () => showMongoDatabase(context, '${d['name']}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.storage_rounded, size: 18, color: d['name'] == current ? mongoGreen : AppColors.text3),
                            const SizedBox(width: Space.s),
                            Expanded(child: Text('${d['name']}${d['name'] == current ? '  · default' : ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(bytes(_size(d['sizeOnDisk'])), style: context.text.labelSmall),
                            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ShareBar(value: _size(d['sizeOnDisk']) / top, color: mongoGreen.withValues(alpha: 0.75), height: 4),
                      ],
                    ),
                  ),
                ),
              if (_dbs == null && _error == null && !_loading && _version != null)
                Padding(padding: const EdgeInsets.all(Space.l), child: Text('This user can\'t list databases; name one as the default.', style: context.text.bodySmall)),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 9, color: MongoSession.instance.connected ? AppColors.success : AppColors.text3),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(MongoSession.instance.connected ? 'Connected; closes after a few idle minutes' : 'Not connected', style: context.text.bodySmall)),
                    TextButton(
                      onPressed: () async {
                        await MongoSession.instance.close();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        _Box('Tools · ${DevService.mongodb.toolCount}', children: [_tools(DevService.mongodb)]),
      ],
    );
  }
}
