import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../chat/presentation/widgets/dev/dev_card_kit.dart';
import '../../chat/presentation/widgets/dev/mongo_cards.dart' show MongoServerStatusView, showMongoCollection, showMongoDatabase;
import '../../chat/presentation/widgets/dev/resend_cards.dart';
import '../../chat/presentation/widgets/dev/vercel_cards.dart' show VercelDeploymentTile, VercelMonogram, VercelProjectTile, VercelUsageView, showVercelDomain, stateColor, statePill;
import '../../settings/data/settings.dart';
import '../mongo_session.dart';
import 'manage_kit.dart';

// Full pages to manage each Development service, opened from Settings →
// Development once a key is set. Everything loads behind skeletons and
// opens the same detail sheets the chat cards use.

List<Map<String, dynamic>> _l(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Future<Map<String, dynamic>> _tryRun(BuildContext context, WidgetRef ref, String tool, Map<String, dynamic> args) async {
  try {
    return await devRun(context, ref, tool, args);
  } catch (_) {
    return const {};
  }
}

Widget _heroHead(Widget avatar, String title, String subtitle) => Row(
  children: [
    avatar,
    const SizedBox(width: Space.m),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    ),
  ],
);

Widget _heroColumn(Widget head, List<Widget> stats) => Column(
  mainAxisAlignment: MainAxisAlignment.end,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    head,
    const SizedBox(height: Space.m),
    Row(children: [for (final (i, s) in stats.indexed) ...[if (i > 0) const SizedBox(width: Space.s), s]]),
  ],
);

// ---- Vercel ----------------------------------------------------------------------------

class VercelManagerScreen extends ConsumerWidget {
  const VercelManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.vercel,
    title: 'Vercel',
    colors: const [Color(0xFF27272A), Color(0xFF000000)],
    actions: [IconButton(tooltip: 'Open vercel.com', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://vercel.com/dashboard'))],
    hero: HeroLoader(
      load: (context, ref) async {
        final r = await Future.wait([
          _tryRun(context, ref, 'vercel_account', {}),
          _tryRun(context, ref, 'vercel_projects', {'limit': 100}),
          _tryRun(context, ref, 'vercel_deployments', {'limit': 40, 'since_hours': 24}),
        ]);
        return {'account': r[0], 'projects': r[1]['projects'], 'deployments': r[2]['deployments']};
      },
      builder: (context, d) {
        final u = _m(_m(d['account'])['user']);
        final projects = _l(d['projects']);
        final deps = _l(d['deployments']);
        final failing = projects.where((p) => '${_m(p['latest'])['state']}' == 'ERROR').length;
        return _heroColumn(
          _heroHead(VercelMonogram('${u['username'] ?? 'V'}', size: 46), '${u['name'] ?? u['username'] ?? 'Vercel'}', '@${u['username'] ?? ''} · ${_m(d['account'])['team'] ?? ''}'),
          [
            HeroStat('${projects.length}', 'projects'),
            HeroStat('${deps.length}', 'deploys today'),
            HeroStat('$failing', 'failing', color: failing > 0 ? const Color(0xFFFF8A8A) : null),
          ],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Projects',
        Icons.folder_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'vercel_projects', {'limit': 100}, 'projects'),
          searchHint: 'Search projects',
          matches: (p, q) => '${p['name']} ${p['repo'] ?? ''}'.toLowerCase().contains(q),
          empty: 'No projects yet. Ask the assistant to deploy one.',
          itemBuilder: (context, p, _) => Padding(padding: const EdgeInsets.symmetric(horizontal: Space.xs), child: VercelProjectTile(p)),
        ),
      ),
      ManageTab(
        'Deployments',
        Icons.rocket_launch_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'vercel_deployments', {'limit': 60}, 'deployments'),
          searchHint: 'Search by project, branch or commit',
          matches: (d, q) => '${d['name']} ${d['branch'] ?? ''} ${d['commit'] ?? ''}'.toLowerCase().contains(q),
          header: (context, items) => _StateStrip(items: items),
          itemBuilder: (context, d, _) => Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l), side: BorderSide(color: AppColors.line)),
              clipBehavior: Clip.antiAlias,
              child: VercelDeploymentTile(d),
            ),
          ),
        ),
      ),
      ManageTab(
        'Domains',
        Icons.language_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'vercel_domains', {}, 'domains'),
          searchHint: 'Search domains',
          matches: (d, q) => '${d['name']}'.toLowerCase().contains(q),
          itemBuilder: (context, d, _) => ManageTile(
            leading: TileIcon(d['verified'] == true ? Icons.verified_rounded : Icons.error_outline_rounded, color: d['verified'] == true ? AppColors.success : AppColors.warning),
            title: '${d['name']}',
            subtitle: [if (d['service_type'] != null) '${d['service_type']}', if (d['expires'] != null) 'renews ${ago(d['expires'])}'].join(' · '),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => showVercelDomain(context, '${d['name']}'),
          ),
        ),
      ),
      ManageTab(
        'Usage',
        Icons.query_stats_rounded,
        (context) => Consumer(
          builder: (context, ref, _) => ListView(
            padding: const EdgeInsets.all(Space.l),
            children: [
              Loaded<Map<String, dynamic>>(
                load: () => devRun(context, ref, 'vercel_usage', {'days': 30}),
                builder: (context, j, _) => VercelUsageView(j),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _StateStrip extends StatelessWidget {
  const _StateStrip({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final d in items) {
      counts['${d['state']}'] = (counts['${d['state']}'] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(children: [for (final e in counts.entries) Expanded(flex: e.value, child: Container(color: stateColor(e.key)))]),
            ),
          ),
          const SizedBox(height: Space.s),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in counts.entries) Row(mainAxisSize: MainAxisSize.min, children: [statePill(e.key), const SizedBox(width: 4), Text('${e.value}', style: context.text.labelSmall)])]),
        ],
      ),
    );
  }
}

// ---- Resend ----------------------------------------------------------------------------

class ResendManagerScreen extends ConsumerWidget {
  const ResendManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.resend,
    title: 'Resend',
    colors: const [Color(0xFF1F2937), Color(0xFF030712)],
    actions: [IconButton(tooltip: 'Open resend.com', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://resend.com/emails'))],
    fab: FloatingActionButton.extended(backgroundColor: AppColors.text, foregroundColor: AppColors.bg, onPressed: () => _compose(context), icon: const Icon(Icons.edit_rounded), label: const Text('Compose')),
    hero: HeroLoader(
      load: (context, ref) async {
        final r = await Future.wait([_tryRun(context, ref, 'resend_domains', {}), _tryRun(context, ref, 'resend_emails', {'limit': 100})]);
        return {'domains': r[0]['domains'], 'emails': r[1]['emails']};
      },
      builder: (context, d) {
        final domains = _l(d['domains']);
        final emails = _l(d['emails']);
        final verified = domains.where((x) => x['status'] == 'verified').length;
        final delivered = emails.where((e) => const {'delivered', 'opened', 'clicked'}.contains(e['last_event'])).length;
        final bounced = emails.where((e) => const {'bounced', 'complained'}.contains(e['last_event'])).length;
        return _heroColumn(
          _heroHead(const DevMark(DevBrand.resend, size: 46), 'Email', '$verified of ${domains.length} domains verified'),
          [
            HeroStat('${emails.length}${emails.length == 100 ? '+' : ''}', 'sent'),
            HeroStat(emails.isEmpty ? '–' : '${(delivered * 100 / emails.length).round()}%', 'delivered', color: const Color(0xFF86EFAC)),
            HeroStat('$bounced', 'bounced', color: bounced > 0 ? const Color(0xFFFF8A8A) : null),
          ],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Emails',
        Icons.outbox_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'resend_emails', {'limit': 100}, 'emails'),
          searchHint: 'Search by subject or address',
          matches: (e, q) => '${e['subject']} ${e['to']}'.toLowerCase().contains(q),
          empty: 'Nothing sent yet. Tap Compose to send one.',
          itemBuilder: (context, e, _) => ManageTile(
            leading: TileIcon(resendEventIcon(e['last_event']), color: eventColor(e['last_event'])),
            title: '${e['subject'] ?? '(no subject)'}',
            subtitle: '${e['to'] is List ? (e['to'] as List).join(', ') : e['to']} · ${ago(e['created'])}',
            trailing: Pill(resendEventLabel(e['last_event']), color: eventColor(e['last_event'])),
            onTap: () => showResendEmail(context, '${e['id']}', initial: e),
          ),
        ),
      ),
      ManageTab(
        'Domains',
        Icons.dns_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'resend_domains', {}, 'domains'),
          empty: 'No domains. Ask the assistant to add one.',
          itemBuilder: (context, d, _) => ManageTile(
            leading: TileIcon(d['status'] == 'verified' ? Icons.verified_rounded : Icons.pending_outlined, color: resendDomainColor(d['status'])),
            title: '${d['name']}',
            subtitle: '${d['region'] ?? ''} · added ${ago(d['created'])}',
            trailing: Pill('${d['status']}'.replaceAll('_', ' '), color: resendDomainColor(d['status'])),
            onTap: () => showResendDomain(context, '${d['id']}'),
          ),
        ),
      ),
      ManageTab(
        'Audiences',
        Icons.groups_2_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'resend_audiences', {}, 'audiences'),
          itemBuilder: (context, a, _) => ManageTile(
            leading: TileIcon(Icons.groups_2_outlined, color: AppColors.accent),
            title: '${a['name']}',
            subtitle: 'created ${ago(a['created'])}',
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => showResendContacts(context, '${a['id']}'),
          ),
        ),
      ),
      ManageTab(
        'Broadcasts',
        Icons.campaign_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'resend_broadcasts', {}, 'broadcasts'),
          itemBuilder: (context, b, _) => ManageTile(
            leading: TileIcon(Icons.campaign_outlined, color: resendBroadcastColor(b['status'])),
            title: '${b['subject'] ?? b['name'] ?? b['id']}',
            subtitle: b['sent_at'] != null ? 'sent ${ago(b['sent_at'])}' : 'created ${ago(b['created'])}',
            trailing: Pill('${b['status']}', color: resendBroadcastColor(b['status'])),
            onTap: () => showResendBroadcast(context, '${b['id']}', '${b['name'] ?? 'Broadcast'}'),
          ),
        ),
      ),
      ManageTab(
        'Keys',
        Icons.key_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'resend_api_keys', {}, 'api_keys'),
          itemBuilder: (context, k, reload) => Consumer(
            builder: (context, ref, _) => ManageTile(
              leading: TileIcon(Icons.key_rounded, color: AppColors.warning),
              title: '${k['name']}',
              subtitle: 'created ${ago(k['created'])}${k['last_used'] == null ? ' · never used' : ' · used ${ago(k['last_used'])}'}',
              trailing: IconButton(
                tooltip: 'Revoke',
                icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                onPressed: () async {
                  try {
                    await devRun(context, ref, 'resend_delete_api_key', {'id': k['id']}, confirmTitle: 'Revoke ${k['name']}?', confirmMessage: 'Whatever uses it stops working.', confirmLabel: 'Revoke');
                    reload();
                  } catch (e) {
                    if (context.mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
                  }
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );

  void _compose(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _Compose(),
  );
}

class _Compose extends ConsumerStatefulWidget {
  const _Compose();
  @override
  ConsumerState<_Compose> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<_Compose> {
  late final _from = TextEditingController(text: ref.read(settingsProvider).resendFrom);
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_from, _to, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final to = [for (final t in _to.text.split(RegExp(r'[,;\s]+'))) if (t.contains('@')) t];
    if (to.isEmpty || _subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      showSnack(context, 'Fill in To, Subject and the message', icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await devRun(context, ref, 'resend_send_email', {
        'to': to,
        'subject': _subject.text.trim(),
        'text': _body.text,
        if (_from.text.trim().isNotEmpty) 'from': _from.text.trim(),
      }, confirmTitle: 'Send to ${to.join(', ')}?', confirmMessage: _subject.text.trim(), confirmLabel: 'Send');
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, 'Sent');
      await showResendEmail(context, '${r['id']}', initial: _m(r['email']));
    } catch (e) {
      if (mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, MediaQuery.viewInsetsOf(context).bottom + Space.l),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [const DevMark(DevBrand.resend, size: 26), const SizedBox(width: Space.m), Text('New email', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))]),
        const SizedBox(height: Space.m),
        TextField(controller: _from, decoration: const InputDecoration(labelText: 'From', hintText: 'Me <me@yourdomain.com>', isDense: true)),
        const SizedBox(height: Space.s),
        TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'To', hintText: 'a@example.com, b@example.com', isDense: true)),
        const SizedBox(height: Space.s),
        TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject', isDense: true)),
        const SizedBox(height: Space.s),
        TextField(controller: _body, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true)),
        const SizedBox(height: Space.m),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18),
          label: const Text('Send'),
        ),
      ],
    ),
  );
}

// ---- MongoDB ---------------------------------------------------------------------------

class MongoManagerScreen extends ConsumerWidget {
  const MongoManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.mongodb,
    title: 'MongoDB',
    colors: const [Color(0xFF00684A), Color(0xFF001E2B)],
    fab: FloatingActionButton.extended(backgroundColor: AppColors.text, foregroundColor: AppColors.bg, onPressed: () => _query(context, ref), icon: const Icon(Icons.manage_search_rounded), label: const Text('Query')),
    hero: HeroLoader(
      load: (context, ref) => devRun(context, ref, 'mongodb_overview', {}),
      builder: (context, d) {
        final s = _m(d['server']);
        final dbs = _l(d['databases']);
        return _heroColumn(
          _heroHead(const DevMark(DevBrand.mongodb, size: 46), 'MongoDB ${s['version'] ?? ''}', '${s['topology'] ?? ''} · ${s['host'] ?? ''}'),
          [
            HeroStat('${dbs.length}', 'databases'),
            HeroStat(d['total_size'] == null ? '–' : bytes(d['total_size']), 'on disk'),
            HeroStat('${d['default_database']}', 'default'),
          ],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Databases',
        Icons.storage_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'mongodb_overview', {}, 'databases'),
          searchHint: 'Search databases',
          matches: (d, q) => '${d['name']}'.toLowerCase().contains(q),
          itemBuilder: (context, d, _) => ManageTile(
            leading: TileIcon(Icons.storage_rounded, color: mongoGreen),
            title: '${d['name']}',
            subtitle: bytes(d['size']),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => showMongoDatabase(context, '${d['name']}'),
          ),
        ),
      ),
      ManageTab(
        'Status',
        Icons.monitor_heart_outlined,
        (context) => Consumer(
          builder: (context, ref, _) => ListView(
            padding: const EdgeInsets.all(Space.l),
            children: [
              Loaded<Map<String, dynamic>>(
                load: () => devRun(context, ref, 'mongodb_server_status', {}),
                builder: (context, j, _) => MongoServerStatusView(_m(j['status'])),
              ),
            ],
          ),
        ),
      ),
      ManageTab(
        'Running',
        Icons.sync_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'mongodb_current_ops', {}, 'ops'),
          empty: 'Nothing running right now.',
          itemBuilder: (context, o, reload) => Consumer(
            builder: (context, ref, _) => ManageTile(
              leading: TileIcon(Icons.sync_rounded, color: (o['secs'] as num? ?? 0) > 10 ? AppColors.warning : AppColors.accent),
              title: '${o['op']} ${o['ns'] ?? ''}',
              subtitle: '${o['secs'] ?? 0}s · ${o['desc'] ?? ''}',
              trailing: IconButton(
                tooltip: 'Stop',
                icon: Icon(Icons.stop_circle_outlined, color: AppColors.danger),
                onPressed: () async {
                  try {
                    await devRun(context, ref, 'mongodb_kill_op', {'opid': o['opid']}, confirmTitle: 'Stop operation ${o['opid']}?', confirmLabel: 'Stop');
                    reload();
                  } catch (e) {
                    if (context.mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
                  }
                },
              ),
            ),
          ),
        ),
      ),
      ManageTab(
        'Users',
        Icons.person_outline_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'mongodb_users', {}, 'users'),
          empty: 'No users on the default database.',
          itemBuilder: (context, u, _) => ManageTile(
            leading: TileIcon(Icons.person_outline_rounded, color: AppColors.accent),
            title: '${u['user']}',
            subtitle: (u['roles'] as List? ?? const []).join(', '),
          ),
        ),
      ),
    ],
  );

  Future<void> _query(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final db = TextEditingController(text: s.mongoDatabase.isNotEmpty ? s.mongoDatabase : (MongoSession.databaseIn(s.mongoUri) ?? ''));
    final coll = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open a collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: db, decoration: const InputDecoration(labelText: 'Database')),
            TextField(controller: coll, autofocus: true, decoration: const InputDecoration(labelText: 'Collection')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open')),
        ],
      ),
    );
    if (ok == true && context.mounted && coll.text.trim().isNotEmpty) await showMongoCollection(context, db.text.trim(), coll.text.trim());
  }
}

// ---- Cloudflare ------------------------------------------------------------------------

const _cfOrange = Color(0xFFF38020);

class CloudflareManagerScreen extends ConsumerWidget {
  const CloudflareManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ManageScaffold(
    brand: DevBrand.cloudflare,
    title: 'Cloudflare',
    colors: const [Color(0xFF9A3412), Color(0xFF1C0A00)],
    actions: [IconButton(tooltip: 'Open dash.cloudflare.com', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openUrl('https://dash.cloudflare.com'))],
    hero: HeroLoader(
      load: (context, ref) async {
        final r = await Future.wait([
          _tryRun(context, ref, 'cloudflare_zones', {}),
          _tryRun(context, ref, 'cloudflare_workers', {}),
          _tryRun(context, ref, 'r2_buckets', {}),
        ]);
        return {'zones': r[0]['zones'], 'workers': r[1]['workers'], 'buckets': r[2]['buckets']};
      },
      builder: (context, d) {
        final zones = _l(d['zones']);
        final active = zones.where((z) => z['status'] == 'active').length;
        return _heroColumn(
          _heroHead(const DevMark(DevBrand.cloudflare, size: 46), 'Cloudflare', '$active of ${zones.length} sites active'),
          [HeroStat('${zones.length}', 'sites'), HeroStat('${_l(d['workers']).length}', 'workers'), HeroStat('${_l(d['buckets']).length}', 'R2 buckets')],
        );
      },
    ),
    tabs: [
      ManageTab(
        'Sites',
        Icons.language_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'cloudflare_zones', {}, 'zones'),
          searchHint: 'Search sites',
          matches: (z, q) => '${z['name']}'.toLowerCase().contains(q),
          itemBuilder: (context, z, _) => ManageTile(
            leading: const TileIcon(Icons.language_rounded, color: _cfOrange),
            title: '${z['name']}',
            subtitle: '${z['plan'] ?? ''} · ${(z['name_servers'] as List?)?.join(', ') ?? ''}',
            trailing: Pill('${z['status']}', color: z['status'] == 'active' ? AppColors.success : AppColors.warning),
            onTap: () => _zone(context, '${z['name']}'),
          ),
        ),
      ),
      ManageTab(
        'Workers',
        Icons.bolt_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'cloudflare_workers', {}, 'workers'),
          itemBuilder: (context, w, _) => ManageTile(leading: const TileIcon(Icons.bolt_rounded, color: _cfOrange), title: '${w['name']}', subtitle: 'changed ${ago(w['modified'])}'),
        ),
      ),
      ManageTab(
        'Pages',
        Icons.web_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'cloudflare_pages', {}, 'pages'),
          itemBuilder: (context, p, _) => ManageTile(
            leading: const TileIcon(Icons.web_rounded, color: _cfOrange),
            title: '${p['name']}',
            subtitle: '${p['subdomain'] ?? ''}${p['status'] == null ? '' : ' · ${p['status']}'}',
            trailing: Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.text3),
            onTap: p['subdomain'] == null ? null : () => openUrl('https://${p['subdomain']}'),
          ),
        ),
      ),
      ManageTab(
        'KV',
        Icons.storage_rounded,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'cloudflare_kv', {}, 'kv_namespaces'),
          itemBuilder: (context, n, _) => ManageTile(
            leading: const TileIcon(Icons.storage_rounded, color: _cfOrange),
            title: '${n['title']}',
            subtitle: '${n['id']}',
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => _list(context, 'KV · ${n['title']}', 'cloudflare_kv', {'namespace_id': n['id']}, 'kv_keys', (k) => ('${k['name']}', k['expiration'] == null ? '' : 'expires ${ago(k['expiration'])}', Icons.key_rounded)),
          ),
        ),
      ),
      ManageTab(
        'R2',
        Icons.inventory_2_outlined,
        (context) => ManagedList(
          load: (context, ref) => loadList(context, ref, 'r2_buckets', {}, 'buckets'),
          itemBuilder: (context, b, _) => ManageTile(
            leading: const TileIcon(Icons.inventory_2_outlined, color: _cfOrange),
            title: '${b['name']}',
            subtitle: 'created ${ago(b['created'])}',
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => _list(context, 'R2 · ${b['name']}', 'r2_list', {'bucket': b['name']}, 'objects', (o) => ('${o['key']}', '${bytes(o['size'])} · ${ago(o['modified'])}', Icons.insert_drive_file_outlined)),
          ),
        ),
      ),
    ],
  );

  /// A site in a sheet: its DNS records to copy, and Purge cache.
  void _zone(BuildContext context, String zone) => showDevSheet(
    context,
    brand: DevBrand.cloudflare,
    title: zone,
    subtitle: 'Site',
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
        load: () => devRun(context, ref, 'cloudflare_dns_records', {'zone': zone}),
        builder: (context, j, _) => ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: Space.x4),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0), child: WebPreview(url: 'https://$zone', height: 260, interactive: true)),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ActionButton(
                      label: 'Purge cache',
                      icon: Icons.cleaning_services_outlined,
                      done: 'Cache purged',
                      onRun: () => devRun(context, ref, 'cloudflare_purge_cache', {'zone': zone}, confirmTitle: 'Purge everything cached for $zone?', confirmLabel: 'Purge'),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: FilledButton.icon(onPressed: () => openUrl('https://$zone'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Visit'))),
                ],
              ),
            ),
            SheetLabel('DNS records · ${_l(j['dns_records']).length}'),
            SheetGroup(
              children: [
                for (final r in _l(j['dns_records']))
                  ListTile(
                    dense: true,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: '${r['content']}'));
                      showSnack(context, 'Value copied');
                    },
                    leading: SizedBox(width: 48, child: Pill('${r['type']}', color: _cfOrange)),
                    title: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r['content']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 11.5)),
                    trailing: Icon(r['proxied'] == true ? Icons.cloud_rounded : Icons.cloud_off_rounded, size: 18, color: r['proxied'] == true ? _cfOrange : AppColors.text3),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void _list(BuildContext context, String title, String tool, Map<String, dynamic> args, String key, (String, String, IconData) Function(Map<String, dynamic>) row) => showDevSheet(
    context,
    brand: DevBrand.cloudflare,
    title: title,
    builder: (context, scroll) => Consumer(
      builder: (context, ref, _) => Loaded<List<Map<String, dynamic>>>(
        load: () => loadList(context, ref, tool, args, key),
        builder: (context, items, _) => ListView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          children: [
            if (items.isEmpty) Padding(padding: const EdgeInsets.all(Space.xl), child: Text('Empty.', style: context.text.bodySmall)),
            for (final i in items)
              () {
                final (t, sub, icon) = row(i);
                return ManageTile(leading: TileIcon(icon, color: _cfOrange, size: 36), title: t, subtitle: sub);
              }(),
          ],
        ),
      ),
    ),
  );
}
