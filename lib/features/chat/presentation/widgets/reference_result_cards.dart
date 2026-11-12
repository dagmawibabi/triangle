import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../info/info_api.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for packages, domains, xkcd, the dictionary, translation and
/// Wikipedia. Null for other tools.
Widget? referenceResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'package_info' when j['version'] != null => _PackageCard(p: j),
  'package_search' when maps(j['packages']).isNotEmpty => _PackageList(r: j),
  'domain_lookup' when j['domain'] != null => _DomainCard(d: j),
  'xkcd' when j['image'] != null => _XkcdCard(x: j),
  'define_word' when j['meanings'] != null => _WordCard(w: j),
  'translate_text' when j['translation'] != null => _TranslationCard(t: j),
  'wikipedia_search' when maps(j['results']).isNotEmpty => _WikiList(r: j),
  'wikipedia_summary' when j['title'] != null => _WikiCard(a: j),
  'wikipedia_on_this_day' when j['date'] != null => _OnThisDayCard(d: j),
  _ => null,
};

String _compact(Object? v) => v is num ? NumberFormat.compact().format(v) : '—';

String _ago(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  if (t == null) return '—';
  final d = DateTime.now().difference(t);
  if (d.inDays >= 365) return '${(d.inDays / 365).floor()} y ago';
  if (d.inDays >= 30) return '${(d.inDays / 30).floor()} mo ago';
  if (d.inDays >= 1) return '${d.inDays} d ago';
  if (d.inHours >= 1) return '${d.inHours} h ago';
  return 'just now';
}

// ---- packages ---------------------------------------------------------------------

const _registryColors = {'npm': Color(0xFFCB3837), 'pypi': Color(0xFF3775A9), 'pub': Color(0xFF0175C2)};
const _registryNames = {'npm': 'npm', 'pypi': 'PyPI', 'pub': 'pub.dev'};

class _RegistryBadge extends StatelessWidget {
  const _RegistryBadge(this.registry);
  final String registry;

  @override
  Widget build(BuildContext context) {
    final c = _registryColors[registry] ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      child: Text(_registryNames[registry] ?? registry, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final reg = '${p['registry']}';
    return InfoFrame(
      onTap: () => showPackage(context, p),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _RegistryBadge(reg),
                const SizedBox(width: Space.s),
                Expanded(child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Text('v${p['version']}', style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.text2)),
              ],
            ),
            if (p['deprecated'] != null || p['yanked'] == true) ...[
              const SizedBox(height: Space.s),
              InfoPill(p['yanked'] == true ? 'Yanked' : 'Deprecated: ${p['deprecated']}', color: AppColors.danger, icon: Icons.warning_amber_rounded),
            ],
            if (textOf(p['description']) != null) ...[
              const SizedBox(height: Space.s),
              Text('${p['description']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text2, height: 1.35)),
            ],
            const SizedBox(height: Space.m),
            infoGrid(columns: 3, [
              InfoStat('Published', _ago(p['published'])),
              if (p['weekly_downloads'] != null)
                InfoStat('Weekly', _compact(p['weekly_downloads']))
              else if (p['monthly_downloads'] != null)
                InfoStat('Monthly', _compact(p['monthly_downloads']))
              else
                InfoStat('Versions', '${p['versions_count'] ?? '—'}'),
              if (reg == 'pub') InfoStat('Points', '${p['pub_points'] ?? '—'}/${p['max_points'] ?? 160}') else InfoStat('Licence', '${p['license'] ?? '—'}'),
            ]),
            const SizedBox(height: Space.m),
            _InstallLine('${p['install']}'),
          ],
        ),
      ),
    );
  }
}

class _InstallLine extends StatelessWidget {
  const _InstallLine(this.command);
  final String command;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface2,
    borderRadius: BorderRadius.circular(Radii.s),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.s),
      onTap: () => copyText(context, command, 'Copied the install command'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 8),
        child: Row(
          children: [
            Text('\$ ', style: TextStyle(fontFamily: 'monospace', color: AppColors.text3)),
            Expanded(child: Text(command, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
            Icon(Icons.copy_rounded, size: 15, color: AppColors.text3),
          ],
        ),
      ),
    ),
  );
}

Future<void> showPackage(BuildContext context, Map<String, dynamic> p) {
  final reg = '${p['registry']}';
  final versions = maps(p['recent_versions']);
  return showInfoSheet(
    context,
    (context) => [
      SheetTitle('${p['name']}', subtitle: 'v${p['version']} · ${_registryNames[reg] ?? reg}', trailing: _RegistryBadge(reg)),
      if (textOf(p['description']) != null) ...[const SizedBox(height: Space.m), SelectableText('${p['description']}', style: context.text.bodyMedium?.copyWith(height: 1.45))],
      const SizedBox(height: Space.l),
      _InstallLine('${p['install']}'),
      const SizedBox(height: Space.l),
      infoGrid([
        InfoStat('Latest', 'v${p['version']}', icon: Icons.sell_outlined),
        InfoStat('Published', '${'${p['published'] ?? ''}'.split('T').first} (${_ago(p['published'])})', icon: Icons.event_outlined),
        InfoStat('Licence', '${p['license'] ?? '—'}', icon: Icons.balance_rounded),
        InfoStat('Versions', '${p['versions_count'] ?? '—'}', icon: Icons.layers_outlined),
        if (p['weekly_downloads'] != null) InfoStat('Downloads / week', NumberFormat.decimalPattern().format(p['weekly_downloads']), icon: Icons.download_rounded),
        if (p['monthly_downloads'] != null) InfoStat('Downloads / month', NumberFormat.decimalPattern().format(p['monthly_downloads']), icon: Icons.download_rounded),
        if (p['likes'] != null) InfoStat('Likes', _compact(p['likes']), icon: Icons.thumb_up_alt_outlined),
        if (p['pub_points'] != null) InfoStat('Pub points', '${p['pub_points']} / ${p['max_points']}', icon: Icons.verified_outlined),
        if (p['requires_python'] != null) InfoStat('Python', '${p['requires_python']}', icon: Icons.code_rounded),
        if (p['publisher'] != null) InfoStat('Publisher', '${p['publisher']}', icon: Icons.verified_user_outlined),
        if (p['author'] != null) InfoStat('Author', '${p['author']}', icon: Icons.person_outline_rounded),
        InfoStat('Dependencies', '${p['dependencies'] ?? 0}', icon: Icons.account_tree_outlined),
      ]),
      if (strs(p['platforms']).isNotEmpty || p['null_safe'] == true || p['dart3'] == true || p['types'] == true) ...[
        const SizedBox(height: Space.m),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pl in strs(p['platforms'])) InfoPill(pl),
          if (p['dart3'] == true) InfoPill('Dart 3', color: AppColors.success),
          if (p['types'] == true) InfoPill('TypeScript types', color: AppColors.success),
        ]),
      ],
      if (versions.isNotEmpty) ...[
        const SectionLabel('Recent versions'),
        for (final v in versions) KeyValueRow('${v['version']}', '${v['date']}', mono: false),
      ],
      if (strs(p['dependency_names']).isNotEmpty) ...[
        const SectionLabel('Depends on'),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final d in strs(p['dependency_names'])) InfoPill(d)]),
      ],
      if (strs(p['keywords']).isNotEmpty) ...[
        const SectionLabel('Keywords'),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final k in strs(p['keywords'])) InfoPill('#$k')]),
      ],
      if (strs(p['maintainers']).isNotEmpty) ...[const SectionLabel('Maintainers'), Text(strs(p['maintainers']).join(', '), style: context.text.bodySmall)],
      sheetButtons([
        linkButton(_registryNames[reg] ?? 'Registry', '${p['url']}', filled: true),
        linkButton('Repository', textOf(p['repository']), icon: Icons.code_rounded),
        if (p['homepage'] != p['repository']) linkButton('Homepage', textOf(p['homepage']), icon: Icons.home_outlined),
      ]),
    ],
  );
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final list = maps(r['packages']);
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.inventory_2_outlined, '${_registryNames[r['registry']] ?? r['registry']} · "${r['query']}" · ${list.length}'),
          for (final p in list)
            InkWell(
              onTap: () => showLoadingSheet(context, () => InfoApi.instance.package('${p['registry']}', '${p['name']}'), (context, full) => [_PackageSheetBody(p: full)]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (p['version'] != null) Text('v${p['version']}', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.text3)),
                      ],
                    ),
                    if (textOf(p['description']) != null) Text('${p['description']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    Text(
                      [
                        if (p['weekly_downloads'] != null) '${_compact(p['weekly_downloads'])}/week',
                        if (p['monthly_downloads'] != null) '${_compact(p['monthly_downloads'])}/month',
                        if (p['likes'] != null) '${_compact(p['likes'])} likes',
                        if (p['pub_points'] != null) '${p['pub_points']} points',
                        if (p['published'] != null) _ago(p['published']),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: AppColors.text3),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

/// The package sheet's content when it was loaded from a search row.
class _PackageSheetBody extends StatelessWidget {
  const _PackageSheetBody({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PackageCard(p: p),
      sheetButtons([
        linkButton(_registryNames[p['registry']] ?? 'Registry', '${p['url']}', filled: true),
        linkButton('Repository', textOf(p['repository']), icon: Icons.code_rounded),
      ]),
    ],
  );
}

// ---- domains ----------------------------------------------------------------------

class _DomainCard extends StatelessWidget {
  const _DomainCard({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final w = mapOf(d['whois']), dns = mapOf(d['dns']), ssl = mapOf(d['ssl']);
    final expiry = numOf(w['days_until_expiry']);
    final sslDays = numOf(ssl['days_left']);
    Color tone(num? days) => days == null
        ? AppColors.text3
        : days < 0
        ? AppColors.danger
        : days < 30
        ? AppColors.warning
        : AppColors.success;
    final a = maps(mapOf(dns['records'])['A']);
    return InfoFrame(
      onTap: () => _showDomain(context, d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.dns_outlined, 'Domain', trailing: null),
          Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s), child: Text('${d['domain']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          if (d['whois'] != null)
            _DomainRow(
              Icons.badge_outlined,
              'Registration',
              w['error'] != null
                  ? '${w['error']}'
                  : w['registered'] == false
                  ? 'Not registered (or no RDAP record)'
                  : '${w['registrar'] ?? 'Unknown registrar'} · since ${'${w['created'] ?? '—'}'.split('T').first}',
              trailing: expiry == null ? null : InfoPill(expiry < 0 ? 'Expired' : 'Expires in ${expiry}d', color: tone(expiry)),
            ),
          if (d['dns'] != null)
            _DomainRow(
              Icons.lan_outlined,
              'DNS',
              dns['error'] != null ? '${dns['error']}' : a.isEmpty ? 'No A record' : '${a.map((r) => r['value']).take(2).join(', ')}${a.length > 2 ? ' +${a.length - 2}' : ''}',
              trailing: dns['error'] != null ? null : InfoPill(dns['mail'] == true ? 'Mail ✓' : 'No mail', color: dns['mail'] == true ? AppColors.success : null),
            ),
          if (d['ssl'] != null)
            _DomainRow(
              ssl['valid'] == true ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
              'HTTPS',
              ssl['error'] != null ? '${ssl['error']}' : '${ssl['issuer'] ?? '—'} · until ${ssl['expires']}',
              trailing: sslDays == null ? null : InfoPill(ssl['trusted'] == false ? 'Untrusted' : (sslDays < 0 ? 'Expired' : '${sslDays}d left'), color: ssl['trusted'] == false ? AppColors.danger : tone(sslDays)),
            ),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}

class _DomainRow extends StatelessWidget {
  const _DomainRow(this.icon, this.label, this.value, {this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.text2),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: AppColors.text3)),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Space.s), trailing!],
      ],
    ),
  );
}

void _showDomain(BuildContext context, Map<String, dynamic> d) {
  final w = mapOf(d['whois']), dns = mapOf(d['dns']), ssl = mapOf(d['ssl']);
  final records = mapOf(dns['records']);
  String date(Object? v) => '${v ?? '—'}'.split('T').first;
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${d['domain']}', subtitle: w['registered'] == true ? 'Registered ${w['age_years'] == null ? '' : '${w['age_years']} years ago'}' : null),
      if (d['whois'] != null) ...[
        const SectionLabel('Registration (RDAP)'),
        if (w['error'] != null)
          Text('${w['error']}', style: context.text.bodySmall)
        else if (w['registered'] == false)
          Text('${w['note']}', style: context.text.bodySmall)
        else ...[
          KeyValueRow('Registrar', '${w['registrar'] ?? '—'}', onTap: textOf(w['registrar_url']) == null ? null : () => openLink('${w['registrar_url']}')),
          if (w['registrant'] != null) KeyValueRow('Registrant', '${w['registrant']}'),
          KeyValueRow('Created', date(w['created'])),
          KeyValueRow('Updated', date(w['updated'])),
          KeyValueRow('Expires', '${date(w['expires'])}${w['days_until_expiry'] == null ? '' : '  (${w['days_until_expiry']} days)'}'),
          KeyValueRow('DNSSEC', w['dnssec'] == true ? 'Signed' : 'Not signed'),
          if (w['abuse_email'] != null) KeyValueRow('Abuse contact', '${w['abuse_email']}', onTap: () => copyText(context, '${w['abuse_email']}')),
          if (strs(w['nameservers']).isNotEmpty) KeyValueRow('Nameservers', strs(w['nameservers']).join('\n'), mono: true),
          if (strs(w['status']).isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in strs(w['status'])) InfoPill(s)]),
          ],
        ],
      ],
      if (d['ssl'] != null) ...[
        const SectionLabel('HTTPS certificate'),
        if (ssl['error'] != null)
          Text('${ssl['error']}', style: context.text.bodySmall)
        else ...[
          KeyValueRow('Status', ssl['valid'] == true ? 'Valid and trusted' : (ssl['trusted'] == false ? 'Not trusted by this phone' : 'Expired'), valueColor: ssl['valid'] == true ? AppColors.success : AppColors.danger),
          KeyValueRow('Issued to', '${ssl['subject'] ?? '—'}'),
          KeyValueRow('Issuer', '${ssl['issuer'] ?? '—'}${ssl['issuer_cn'] == null || ssl['issuer_cn'] == ssl['issuer'] ? '' : ' (${ssl['issuer_cn']})'}'),
          KeyValueRow('Valid', '${ssl['valid_from']} → ${ssl['expires']}'),
          KeyValueRow('Days left', '${ssl['days_left']} of ${ssl['lifetime_days']}'),
          if (ssl['protocol'] != null) KeyValueRow('Protocol', '${ssl['protocol']}'),
        ],
      ],
      if (d['dns'] != null) ...[
        const SectionLabel('DNS records'),
        if (dns['error'] != null)
          Text('${dns['error']}', style: context.text.bodySmall)
        else ...[
          for (final e in records.entries)
            KeyValueRow(e.key, [for (final r in maps(e.value)) '${r['value']}'].join('\n'), mono: true, onTap: () => copyText(context, [for (final r in maps(e.value)) '${r['value']}'].join('\n'))),
          const SizedBox(height: Space.s),
          Wrap(spacing: 6, runSpacing: 6, children: [
            InfoPill(dns['has_spf'] == true ? 'SPF set' : 'No SPF', color: dns['has_spf'] == true ? AppColors.success : AppColors.warning),
            InfoPill(dns['ipv6'] == true ? 'IPv6' : 'No IPv6', color: dns['ipv6'] == true ? AppColors.success : null),
          ]),
        ],
      ],
      sheetButtons([linkButton('Open site', 'https://${d['domain']}', filled: true, icon: Icons.language_rounded)]),
    ],
  );
}

// ---- xkcd -------------------------------------------------------------------------

class _XkcdCard extends StatelessWidget {
  const _XkcdCard({required this.x});
  final Map<String, dynamic> x;

  @override
  Widget build(BuildContext context) => InfoFrame(
    onTap: () => _showXkcd(context, x),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoHeader(Icons.draw_outlined, 'xkcd #${x['number']} · ${x['date']}'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Space.m), child: Text('${x['title']}', style: context.text.titleMedium)),
        const SizedBox(height: Space.s),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(Space.s),
          constraints: const BoxConstraints(maxHeight: 420),
          child: NetImage('${x['image']}', fit: BoxFit.contain),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Text('${x['alt'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.text2, fontSize: 13)),
        ),
      ],
    ),
  );
}

void _showXkcd(BuildContext context, Map<String, dynamic> x) {
  final n = numOf(x['number'])?.toInt() ?? 1;
  final latest = numOf(x['latest'])?.toInt() ?? n;
  void go(BuildContext ctx, {int? number, bool random = false}) {
    Navigator.pop(ctx);
    showLoadingSheet(context, () => InfoApi.instance.xkcd(number: number, random: random), (c, next) => [_XkcdBody(x: next, onGo: (num, rnd) => go(c, number: num, random: rnd))], initialSize: 0.94);
  }

  showInfoSheet(context, initialSize: 0.94, (ctx) => [_XkcdBody(x: x, latest: latest, onGo: (num, rnd) => go(ctx, number: num, random: rnd))]);
}

class _XkcdBody extends StatelessWidget {
  const _XkcdBody({required this.x, required this.onGo, this.latest});
  final Map<String, dynamic> x;
  final int? latest;
  final void Function(int? number, bool random) onGo;

  @override
  Widget build(BuildContext context) {
    final n = numOf(x['number'])?.toInt() ?? 1;
    final last = latest ?? numOf(x['latest'])?.toInt() ?? n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle('${x['title']}', subtitle: 'xkcd #$n · ${x['date']}'),
        const SizedBox(height: Space.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.m),
          child: Container(color: Colors.white, padding: const EdgeInsets.all(Space.s), child: InteractiveViewer(maxScale: 5, child: NetImage('${x['image']}', fit: BoxFit.contain))),
        ),
        const SizedBox(height: Space.m),
        SelectableText('${x['alt'] ?? ''}', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.text2, height: 1.45)),
        const SizedBox(height: Space.l),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.outlined(onPressed: n > 1 ? () => onGo(n == 405 ? 403 : n - 1, false) : null, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous'),
            OutlinedButton.icon(onPressed: () => onGo(null, true), icon: const Icon(Icons.shuffle_rounded, size: 18), label: const Text('Random')),
            IconButton.outlined(onPressed: n < last ? () => onGo(n == 403 ? 405 : n + 1, false) : null, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next'),
          ],
        ),
        sheetButtons([linkButton('xkcd.com', '${x['url']}'), linkButton('Explain xkcd', '${x['explain_url']}', icon: Icons.help_outline_rounded)]),
      ],
    );
  }
}

// ---- dictionary -------------------------------------------------------------------

AudioPlayer? _wordPlayer;

Future<void> _say(String? url) async {
  if (url == null) return;
  try {
    final p = _wordPlayer ??= AudioPlayer();
    await p.stop();
    await p.play(UrlSource(url));
  } catch (_) {}
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.w});
  final Map<String, dynamic> w;

  @override
  Widget build(BuildContext context) {
    final meanings = maps(w['meanings']);
    return InfoFrame(
      onTap: () => _showWord(context, w),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${w['word']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      if (w['phonetic'] != null) Text('${w['phonetic']}', style: TextStyle(color: AppColors.text2, fontSize: 14)),
                    ],
                  ),
                ),
                if (w['audio'] != null) IconButton.filledTonal(onPressed: () => _say('${w['audio']}'), icon: const Icon(Icons.volume_up_rounded), tooltip: 'Pronounce'),
              ],
            ),
            for (final m in meanings.take(2)) ...[
              const SizedBox(height: Space.m),
              Text('${m['part_of_speech']}', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.text3, fontSize: 12.5)),
              for (final (i, d) in maps(m['definitions']).take(2).indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${i + 1}. ${d['definition']}', style: const TextStyle(height: 1.35)),
                ),
            ],
            if (meanings.length > 2 || meanings.any((m) => maps(m['definitions']).length > 2)) ...[
              const SizedBox(height: Space.s),
              Text('More meanings, examples and synonyms…', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ],
          ],
        ),
      ),
    );
  }
}

void _showWord(BuildContext context, Map<String, dynamic> w) => showInfoSheet(
  context,
  (context) => [
    SheetTitle(
      '${w['word']}',
      subtitle: textOf(w['phonetic']),
      trailing: w['audio'] == null ? null : IconButton.filledTonal(onPressed: () => _say('${w['audio']}'), icon: const Icon(Icons.volume_up_rounded)),
    ),
    for (final m in maps(w['meanings'])) ...[
      SectionLabel('${m['part_of_speech']}'),
      for (final (i, d) in maps(m['definitions']).indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('${i + 1}. ${d['definition']}', style: const TextStyle(height: 1.4)),
              if (d['example'] != null) Padding(padding: const EdgeInsets.only(left: 16, top: 2), child: Text('"${d['example']}"', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.text2))),
            ],
          ),
        ),
      if (strs(m['synonyms']).isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [Text('Synonyms ', style: TextStyle(color: AppColors.text3, fontSize: 12)), for (final s in strs(m['synonyms'])) InfoPill(s)]),
      ],
      if (strs(m['antonyms']).isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [Text('Antonyms ', style: TextStyle(color: AppColors.text3, fontSize: 12)), for (final s in strs(m['antonyms'])) InfoPill(s)]),
      ],
    ],
    if (w['origin'] != null) ...[const SectionLabel('Origin'), Text('${w['origin']}')],
    sheetButtons([linkButton('Wiktionary', textOf(w['source_url']), icon: Icons.menu_book_outlined)]),
  ],
);

// ---- translation ------------------------------------------------------------------

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({required this.t});
  final Map<String, dynamic> t;

  @override
  Widget build(BuildContext context) => InfoFrame(
    child: Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InfoPill('${t['from'] ?? '?'}'.toUpperCase()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.text3)),
              InfoPill('${t['to']}'.toUpperCase(), color: AppColors.text),
              const Spacer(),
              Text('${t['engine']}${t['match'] == null ? '' : ' · ${t['match']}% match'}', style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
          ),
          const SizedBox(height: Space.m),
          Text('${t['text']}', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text3, fontSize: 13.5)),
          const SizedBox(height: Space.s),
          SelectableText('${t['translation']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35)),
          if (strs(t['alternatives']).isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text('Also: ${strs(t['alternatives']).join(' · ')}', style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: () => copyText(context, '${t['translation']}'), icon: const Icon(Icons.copy_rounded, size: 16), label: const Text('Copy')),
          ),
        ],
      ),
    ),
  );
}

/// ---- Wikipedia --------------------------------------------------------------------

Future<void> showWikiArticle(BuildContext context, String title, {String? language}) =>
    showLoadingSheet(context, () => InfoApi.instance.wikiSummary(title, language: language), (context, a) => _wikiBody(context, a));

/// Wikipedia's own look: a serif title over a hairline rule.
const _wikiSerif = TextStyle(fontFamily: 'serif', fontFamilyFallback: ['Noto Serif', 'Georgia', 'Times New Roman']);

/// "WIKIPEDIA · EN" with the W mark.
class _WikiMark extends StatelessWidget {
  const _WikiMark({required this.language, this.onImage = false});
  final String language;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final fg = onImage ? Colors.white : AppColors.text2;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
      decoration: BoxDecoration(
        color: onImage ? Colors.black.withValues(alpha: 0.45) : AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: onImage ? Colors.white : AppColors.text, shape: BoxShape.circle),
            child: Text('W', style: _wikiSerif.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: onImage ? Colors.black : AppColors.bg, height: 1)),
          ),
          const SizedBox(width: 6),
          Text('Wikipedia · ${language.toUpperCase()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

void _showWikiImage(BuildContext context, String url) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.92),
  builder: (context) => GestureDetector(
    onTap: () => Navigator.pop(context),
    child: InteractiveViewer(maxScale: 5, child: Center(child: NetImage(url, fit: BoxFit.contain, errorWidget: const SizedBox.shrink()))),
  ),
);

List<Widget> _wikiBody(BuildContext context, Map<String, dynamic> a) {
  final image = textOf(a['image']) ?? textOf(a['thumbnail']);
  final language = '${a['language'] ?? 'en'}';
  final paragraphs = '${a['extract'] ?? ''}'.split(RegExp(r'\n+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final updated = a['updated'] == null ? null : _ago(a['updated']);
  return [
    if (image != null) ...[
      GestureDetector(
        onTap: () => _showWikiImage(context, image),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: Container(
            height: 240,
            color: AppColors.surface2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(image, fit: BoxFit.cover, alignment: Alignment.topCenter, errorWidget: const SizedBox.shrink()),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)]),
                  ),
                ),
                Positioned(left: Space.m, bottom: Space.m, child: _WikiMark(language: language, onImage: true)),
                Positioned(
                  right: Space.m,
                  bottom: Space.m,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                    child: const Icon(Icons.zoom_out_map_rounded, size: 15, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: Space.l),
    ] else ...[
      Align(alignment: Alignment.centerLeft, child: _WikiMark(language: language)),
      const SizedBox(height: Space.m),
    ],
    SelectableText('${a['title']}', style: _wikiSerif.copyWith(fontSize: 28, height: 1.15, fontWeight: FontWeight.w500, color: AppColors.text)),
    if (textOf(a['description']) case final d?) ...[
      const SizedBox(height: 4),
      Text(d[0].toUpperCase() + d.substring(1), style: TextStyle(fontSize: 14, color: AppColors.text2, fontStyle: FontStyle.italic, height: 1.35)),
    ],
    const SizedBox(height: Space.m),
    Divider(height: 1, color: AppColors.line),
    const SizedBox(height: Space.l),
    SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, para) in paragraphs.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: i == paragraphs.length - 1 ? 0 : Space.m),
              child: Text(para, style: TextStyle(fontSize: i == 0 ? 16 : 15, height: 1.65, color: i == 0 ? AppColors.text : AppColors.text.withValues(alpha: 0.88))),
            ),
          if (paragraphs.isEmpty) Text('No summary for this article.', style: TextStyle(color: AppColors.text3)),
        ],
      ),
    ),
    if (a['latitude'] != null || updated != null) ...[
      const SizedBox(height: Space.l),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          if (a['latitude'] != null)
            InfoPill(
              '${(a['latitude'] as num).toStringAsFixed(3)}, ${(a['longitude'] as num).toStringAsFixed(3)}',
              icon: Icons.place_outlined,
              onTap: () => openLink('https://www.openstreetmap.org/?mlat=${a['latitude']}&mlon=${a['longitude']}#map=10/${a['latitude']}/${a['longitude']}'),
            ),
          if (updated != null) InfoPill('Edited $updated', icon: Icons.history_rounded),
        ],
      ),
    ],
    const SizedBox(height: Space.xl),
    Row(
      children: [
        if (textOf(a['url']) case final url?) ...[
          Expanded(child: FilledButton.icon(onPressed: () => openLink(url), icon: const Icon(Icons.menu_book_rounded, size: 18), label: const Text('Read full article'))),
          const SizedBox(width: Space.s),
          IconButton.filledTonal(tooltip: 'Copy link', onPressed: () => copyText(context, url, 'Copied the link'), icon: const Icon(Icons.link_rounded, size: 20)),
        ],
      ],
    ),
    const SizedBox(height: Space.s),
    Text('Text from Wikipedia under CC BY-SA 4.0', style: TextStyle(fontSize: 11, color: AppColors.text3)),
  ];
}

class _WikiCard extends StatelessWidget {
  const _WikiCard({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final image = textOf(a['image']) ?? textOf(a['thumbnail']);
    final language = '${a['language'] ?? 'en'}';
    return InfoFrame(
      onTap: () => showInfoSheet(context, (c) => _wikiBody(c, a)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image != null)
            SizedBox(
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(image, fit: BoxFit.cover, alignment: Alignment.topCenter, errorWidget: ColoredBox(color: AppColors.surface2)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x80000000)]),
                    ),
                  ),
                  Positioned(left: Space.m, bottom: Space.s, child: _WikiMark(language: language, onImage: true)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image == null) ...[_WikiMark(language: language), const SizedBox(height: Space.s)],
                Text('${a['title']}', style: _wikiSerif.copyWith(fontSize: 21, height: 1.2, fontWeight: FontWeight.w500, color: AppColors.text)),
                if (textOf(a['description']) case final d?)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(d, style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.text2))),
                const SizedBox(height: Space.s),
                Text('${a['extract'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.text)),
                const SizedBox(height: Space.s),
                Row(
                  children: [
                    Text('Read more', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.text),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WikiList extends StatelessWidget {
  const _WikiList({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) => InfoFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoHeader(Icons.public_rounded, 'Wikipedia · ${maps(r['results']).length} articles'),
        for (final a in maps(r['results']))
          InkWell(
            onTap: () => showWikiArticle(context, '${a['title']}', language: '${r['language'] ?? 'en'}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.s),
                    child: a['thumbnail'] == null
                        ? Container(width: 48, height: 48, color: AppColors.surface2, child: Icon(Icons.article_outlined, color: AppColors.text3, size: 20))
                        : NetImage('${a['thumbnail']}', width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (a['description'] != null) Text('${a['description']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text2)),
                        if (a['extract'] != null) Text('${a['extract']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.xs),
      ],
    ),
  );
}

class _OnThisDayCard extends StatelessWidget {
  const _OnThisDayCard({required this.d});
  final Map<String, dynamic> d;

  List<(String, List<Map<String, dynamic>>)> get _sections => [
    for (final k in ['selected', 'events', 'births', 'deaths', 'holidays'])
      if (maps(d[k]).isNotEmpty) (k, maps(d[k])),
  ];

  @override
  Widget build(BuildContext context) {
    final first = _sections.firstOrNull;
    return InfoFrame(
      onTap: () => _show(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.history_edu_rounded, 'On this day · ${d['label']}'),
          if (first != null) for (final e in first.$2.take(4)) _Event(e: e, language: '${d['language']}'),
          if (_sections.fold<int>(0, (s, x) => s + x.$2.length) > 4)
            Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: Text('Tap for more', style: TextStyle(fontSize: 12, color: AppColors.text3))),
        ],
      ),
    );
  }

  void _show(BuildContext context) => showInfoSheet(
    context,
    (context) => [
      SheetTitle(d['label'] == null ? 'On this day' : '${d['label']}', subtitle: 'On this day in history · Wikipedia'),
      for (final (k, items) in _sections) ...[
        SectionLabel(switch (k) { 'selected' => 'Highlights', 'events' => 'Events', 'births' => 'Born', 'deaths' => 'Died', _ => 'Holidays and observances' }, trailing: '${items.length}'),
        for (final e in items) _Event(e: e, language: '${d['language']}', padded: false),
      ],
    ],
  );
}

class _Event extends StatelessWidget {
  const _Event({required this.e, required this.language, this.padded = true});
  final Map<String, dynamic> e;
  final String language;
  final bool padded;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: e['article'] == null ? null : () => showWikiArticle(context, '${e['article']}', language: language),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: padded ? Space.m : 0, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(e['year'] == null ? '•' : '${e['year']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, fontFeatures: tabularFigures)),
          ),
          Expanded(child: Text('${e['text']}', style: const TextStyle(fontSize: 13.5, height: 1.35))),
          if (e['thumbnail'] != null) ...[
            const SizedBox(width: Space.s),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: NetImage('${e['thumbnail']}', width: 40, height: 40, fit: BoxFit.cover, errorWidget: const SizedBox(width: 40))),
          ],
        ],
      ),
    ),
  );
}
