import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/code_highlight.dart';
import '../../../integrations/code_editor_screen.dart';
import '../../../settings/data/settings.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../domain/chat_models.dart';

/// Cards for Cloudflare and E2B results: a code cell with its output and
/// charts (open it in the editor to change and rerun), a terminal, sandbox
/// files and sandboxes; zones, DNS records, Workers, Pages, KV, and an R2
/// file browser whose files can be downloaded or shared from the card.
Widget? cloudResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(String k) => [
    for (final x in (j[k] as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'e2b_run_code' when j['code'] is String => _CodeRunCard(run: j),
    'e2b_run_command' when j['command'] is String => _TerminalCard(result: j),
    'e2b_list_files' => _SandboxFiles(path: '${j['path']}', files: list('files')),
    'e2b_sandboxes' => _SandboxList(current: j['current'] as String?, boxes: list('sandboxes')),
    'cloudflare_zones' => _ZoneList(zones: list('zones')),
    'cloudflare_dns_records' || 'cloudflare_create_dns_record' || 'cloudflare_update_dns_record' when list('dns_records').isNotEmpty =>
      _DnsList(zone: '${j['zone'] ?? ''}', records: list('dns_records')),
    'cloudflare_workers' => _SimpleList(
      logo: _cfLogo,
      title: 'Workers · ${list('workers').length}',
      rows: [for (final w in list('workers')) ('${w['name']}', 'changed ${_day(w['modified'])}', Icons.bolt_rounded)],
    ),
    'cloudflare_pages' when j['deployments'] != null => _SimpleList(
      logo: _cfLogo,
      title: '${j['project']} · deployments',
      rows: [
        for (final d in list('deployments'))
          (
            '${d['environment'] ?? ''} · ${d['status'] ?? ''}${d['branch'] == null ? '' : ' · ${d['branch']}'}',
            '${_day(d['created'])}${d['commit'] == null ? '' : ' · ${'${d['commit']}'.split('\n').first}'}',
            d['status'] == 'success' ? Icons.check_circle_outline_rounded : (d['status'] == 'failure' ? Icons.error_outline_rounded : Icons.schedule_rounded),
          ),
      ],
      urls: [for (final d in list('deployments')) d['url'] as String?],
    ),
    'cloudflare_pages' => _SimpleList(
      logo: _cfLogo,
      title: 'Pages · ${list('pages').length}',
      rows: [
        for (final p in list('pages'))
          ('${p['name']}', '${p['subdomain'] ?? ''}${p['status'] == null ? '' : ' · ${p['status']}'}', Icons.web_rounded),
      ],
      urls: [for (final p in list('pages')) p['subdomain'] == null ? null : 'https://${p['subdomain']}'],
    ),
    'cloudflare_kv' when j['kv_namespaces'] != null => _SimpleList(
      logo: _cfLogo,
      title: 'KV namespaces · ${list('kv_namespaces').length}',
      rows: [for (final n in list('kv_namespaces')) ('${n['title']}', '${n['id']}', Icons.storage_rounded)],
    ),
    'cloudflare_kv' when j['kv_keys'] != null => _SimpleList(
      logo: _cfLogo,
      title: 'KV keys · ${list('kv_keys').length}',
      rows: [for (final k in list('kv_keys')) ('${k['name']}', k['expiration'] == null ? '' : 'expires ${_day(k['expiration'])}', Icons.key_rounded)],
    ),
    'r2_buckets' => _SimpleList(
      logo: _r2Logo,
      title: 'R2 buckets · ${list('buckets').length}',
      rows: [
        for (final b in list('buckets'))
          ('${b['name']}${b['name'] == j['default_bucket'] ? '  (default)' : ''}', 'created ${_day(b['created'])}', Icons.inventory_2_outlined),
      ],
    ),
    'r2_list' => _R2Browser(listing: j),
    'r2_share_link' when j['url'] is String => _LinkCard(url: j['url'] as String, title: '${j['key']}', hours: j['expires_in_hours']),
    _ => null,
  };
}

const _cfLogo = 'https://logos.composio.dev/api/cloudflare';
const _r2Logo = 'https://logos.composio.dev/api/cloudflare';

String _day(Object? v) {
  if (v == null) return '';
  final d = v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : DateTime.tryParse('$v');
  if (d == null) return '$v';
  final l = d.toLocal();
  return l.year == DateTime.now().year ? DateFormat('d MMM, HH:mm').format(l) : DateFormat('d MMM y').format(l);
}

String _size(Object? bytes) {
  final n = bytes is num ? bytes.toDouble() : double.tryParse('$bytes');
  if (n == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = n;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 && i > 0 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

IconData _fileIcon(String name, {bool dir = false}) {
  if (dir) return Icons.folder_rounded;
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => Icons.image_outlined,
    'mp4' || 'mov' || 'webm' || 'mkv' => Icons.movie_outlined,
    'mp3' || 'wav' || 'ogg' || 'm4a' || 'flac' => Icons.audiotrack_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'gz' || 'tar' || 'rar' || '7z' => Icons.folder_zip_outlined,
    'py' || 'js' || 'ts' || 'dart' || 'json' || 'html' || 'css' || 'sh' || 'r' || 'java' => Icons.code_rounded,
    'csv' || 'xlsx' || 'xls' => Icons.table_chart_outlined,
    'txt' || 'md' || 'log' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children, this.danger = false});
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: danger ? AppColors.danger.withValues(alpha: 0.5) : AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head({this.logo, this.icon, required this.title, this.trailing});
  final String? logo;
  final IconData? icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.s, Space.xs),
    child: Row(
      children: [
        if (logo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: NetImage(
              logo!,
              width: 18,
              height: 18,
              errorWidget: Icon(icon ?? Icons.cloud_outlined, size: 18, color: const Color(0xFFF38020)),
            ),
          )
        else
          Icon(icon ?? Icons.cloud_outlined, size: 18, color: AppColors.text2),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
        ),
        ?trailing,
      ],
    ),
  );
}

// ---- E2B --------------------------------------------------------------------------

class _CodeRunCard extends ConsumerStatefulWidget {
  const _CodeRunCard({required this.run});
  final Map<String, dynamic> run;

  @override
  ConsumerState<_CodeRunCard> createState() => _CodeRunCardState();
}

class _CodeRunCardState extends ConsumerState<_CodeRunCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final j = widget.run;
    final theme = ref.watch(settingsProvider.select((s) => s.codeTheme));
    final code = '${j['code']}';
    final language = '${j['language'] ?? 'python'}';
    final error = j['exception'] as Map?;
    final images = [for (final p in (j['created_files'] as List? ?? const [])) '$p'];
    final results = [for (final r in (j['results'] as List? ?? const [])) if (r is Map) r];
    final lines = code.split('\n').length;
    return _Panel(
      danger: error != null,
      children: [
        _Head(
          icon: Icons.terminal_rounded,
          title: 'E2B · $language${j['execution_count'] == null ? '' : ' · [${j['execution_count']}]'}${j['ms'] == null ? '' : ' · ${((j['ms'] as num) / 1000).toStringAsFixed(1)} s'}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy code',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  showSnack(context, 'Code copied');
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Edit & run'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => CodeEditorScreen(code: code, language: language)),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: lines > 8 ? () => setState(() => _open = !_open) : null,
          child: Container(
            margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightedCode(code: code, language: language, theme: theme, maxLines: _open ? null : 8),
                if (lines > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(_open ? 'Show less' : 'Show all $lines lines', style: context.text.labelSmall?.copyWith(color: AppColors.accent)),
                  ),
              ],
            ),
          ),
        ),
        if ('${j['stdout'] ?? ''}'.isNotEmpty) _Out(text: '${j['stdout']}'.trimRight()),
        if ('${j['stderr'] ?? ''}'.isNotEmpty) _Out(text: '${j['stderr']}'.trimRight(), color: AppColors.warning),
        for (final r in results)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: r['markdown'] != null
                ? MarkdownBody(data: '${r['markdown']}', selectable: true)
                : SelectableText('${r['text'] ?? ''}', style: codeTextStyle.copyWith(color: AppColors.accent)),
          ),
        for (final img in images)
          if (File(img).existsSync())
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: GestureDetector(
                onTap: () => OpenFilex.open(img),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.s),
                  child: Container(color: Colors.white, child: Image.file(File(img), fit: BoxFit.contain)),
                ),
              ),
            ),
        if (error != null)
          _Out(
            text: '${error['name']}: ${error['value']}${error['traceback'] == null ? '' : '\n${error['traceback']}'}',
            color: AppColors.danger,
            maxLines: 14,
          ),
      ],
    );
  }
}

class _Out extends StatelessWidget {
  const _Out({required this.text, this.color, this.maxLines = 18});
  final String text;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final shown = lines.length > maxLines ? '${lines.take(maxLines).join('\n')}\n… ${lines.length - maxLines} more lines' : text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(shown, style: codeTextStyle.copyWith(fontSize: 12.5, color: color ?? AppColors.text2)),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final code = result['exit_code'];
    return _Panel(
      danger: code is num && code != 0,
      children: [
        _Head(
          icon: Icons.terminal_rounded,
          title: 'E2B shell · exit ${code ?? '?'}',
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(Radii.s)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(
              TextSpan(
                style: codeTextStyle.copyWith(fontSize: 12.5),
                children: [
                  TextSpan(text: r'$ ', style: TextStyle(color: AppColors.success)),
                  TextSpan(text: '${result['command']}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (result['stdout'] != null) TextSpan(text: '${result['stdout']}'.trimRight(), style: TextStyle(color: AppColors.text2)),
                  if (result['stderr'] != null) TextSpan(text: '\n${'${result['stderr']}'.trimRight()}', style: TextStyle(color: AppColors.warning)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SandboxFiles extends StatelessWidget {
  const _SandboxFiles({required this.path, required this.files});
  final String path;
  final List<Map<String, dynamic>> files;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(icon: Icons.folder_open_rounded, title: 'E2B · $path · ${files.length}'),
      for (final f in files.take(40))
        ListTile(
          dense: true,
          leading: lead(Icon(_fileIcon('${f['name']}', dir: f['dir'] == true), color: f['dir'] == true ? const Color(0xFF8E9BAE) : AppColors.text2)),
          title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([if (f['dir'] != true) _size(f['size']), _day(f['modified'])].where((x) => x.isNotEmpty).join(' · ')),
        ),
      if (files.length > 40) Padding(padding: const EdgeInsets.all(Space.s), child: Text('${files.length - 40} more', style: context.text.labelSmall)),
    ],
  );
}

class _SandboxList extends StatelessWidget {
  const _SandboxList({required this.current, required this.boxes});
  final String? current;
  final List<Map<String, dynamic>> boxes;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(icon: Icons.dns_outlined, title: 'E2B sandboxes · ${boxes.length} running'),
      if (boxes.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('None running.', style: context.text.bodySmall)),
      for (final b in boxes)
        ListTile(
          dense: true,
          leading: lead(Icon(Icons.circle, size: 10, color: b['state'] == 'running' ? AppColors.success : AppColors.warning)),
          title: Text('${b['id']}${b['id'] == current ? '  · this app' : ''}', style: codeTextStyle.copyWith(fontSize: 12.5)),
          subtitle: Text(
            [
              '${b['template']}',
              '${b['state']}',
              if (b['cpus'] != null) '${b['cpus']} CPU · ${b['memory_mb']} MB',
              if (b['ends'] != null) 'ends ${_day(b['ends'])}',
            ].join(' · '),
          ),
        ),
    ],
  );
}

// ---- Cloudflare ---------------------------------------------------------------------

class _ZoneList extends StatelessWidget {
  const _ZoneList({required this.zones});
  final List<Map<String, dynamic>> zones;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(logo: _cfLogo, title: 'Cloudflare · ${zones.length} site${zones.length == 1 ? '' : 's'}'),
      for (final z in zones)
        ListTile(
          dense: true,
          onTap: () => launchUrl(Uri.parse('https://${z['name']}'), mode: LaunchMode.externalApplication),
          leading: lead(const Icon(Icons.language_rounded, color: Color(0xFFF38020))),
          title: Text('${z['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              '${z['plan'] ?? ''}',
              if (z['name_servers'] is List) (z['name_servers'] as List).join(', '),
            ].where((x) => x.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _Status('${z['status']}', ok: z['status'] == 'active' && z['paused'] != true),
        ),
    ],
  );
}

class _Status extends StatelessWidget {
  const _Status(this.label, {required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500)),
    );
  }
}

class _DnsList extends StatelessWidget {
  const _DnsList({required this.zone, required this.records});
  final String zone;
  final List<Map<String, dynamic>> records;

  static Color _type(String t) => switch (t) {
    'A' || 'AAAA' => const Color(0xFF74A9FF),
    'CNAME' => const Color(0xFFA78BFA),
    'MX' => const Color(0xFFFFA94D),
    'TXT' => const Color(0xFF86EFAC),
    'NS' => const Color(0xFFF9A8D4),
    _ => AppColors.text2,
  };

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(logo: _cfLogo, title: 'DNS${zone.isEmpty ? '' : ' · $zone'} · ${records.length} record${records.length == 1 ? '' : 's'}'),
      for (final (i, r) in records.take(60).indexed) ...[
        if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m),
        InkWell(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: '${r['content']}'));
            showSnack(context, 'Value copied');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _type('${r['type']}').withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                  child: Text('${r['type']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _type('${r['type']}'))),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        '${r['priority'] == null ? '' : '${r['priority']} '}${r['content']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: codeTextStyle.copyWith(fontSize: 12, color: AppColors.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      r['proxied'] == true ? Icons.cloud_rounded : Icons.cloud_off_rounded,
                      size: 18,
                      color: r['proxied'] == true ? const Color(0xFFF38020) : AppColors.text3,
                    ),
                    Text(r['ttl'] == 1 ? 'auto' : '${r['ttl']}s', style: context.text.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      if (records.length > 60) Padding(padding: const EdgeInsets.all(Space.s), child: Text('${records.length - 60} more', style: context.text.labelSmall)),
    ],
  );
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({required this.logo, required this.title, required this.rows, this.urls});
  final String logo;
  final String title;
  final List<(String, String, IconData)> rows;
  final List<String?>? urls;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(logo: logo, title: title),
      for (final (i, (t, sub, icon)) in rows.take(40).indexed)
        ListTile(
          dense: true,
          onTap: urls?[i] == null ? null : () => launchUrl(Uri.parse(urls![i]!), mode: LaunchMode.externalApplication),
          leading: lead(Icon(icon, color: const Color(0xFFF38020), size: 20)),
          title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: urls?[i] == null ? null : Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.text3),
        ),
      if (rows.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('Nothing here.', style: context.text.bodySmall)),
    ],
  );
}

/// R2 folder listing; tap a file for download and share actions.
class _R2Browser extends ConsumerWidget {
  const _R2Browser({required this.listing});
  final Map<String, dynamic> listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucket = '${listing['bucket']}';
    final prefix = '${listing['prefix'] ?? ''}';
    final folders = [for (final f in (listing['folders'] as List? ?? const [])) '$f'];
    final objects = [for (final o in (listing['objects'] as List? ?? const [])) if (o is Map) Map<String, dynamic>.from(o)];
    final total = objects.fold<num>(0, (n, o) => n + ((o['size'] as num?) ?? 0));
    return _Panel(
      children: [
        _Head(logo: _r2Logo, title: 'R2 · $bucket/${prefix.isEmpty ? '' : prefix} · ${objects.length} files${total > 0 ? ' · ${_size(total)}' : ''}'),
        for (final f in folders.take(30))
          ListTile(
            dense: true,
            leading: lead(const Icon(Icons.folder_rounded, color: Color(0xFF8E9BAE))),
            title: Text(f.substring(prefix.length).isEmpty ? f : f.substring(prefix.length)),
          ),
        for (final o in objects.take(60))
          ListTile(
            dense: true,
            leading: lead(Icon(_fileIcon('${o['key']}'), color: AppColors.text2)),
            title: Text('${o['key']}'.substring('${o['key']}'.startsWith(prefix) ? prefix.length : 0), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([_size(o['size']), _day(o['modified'])].where((x) => x.isNotEmpty).join(' · ')),
            trailing: Icon(Icons.more_horiz_rounded, size: 18, color: AppColors.text3),
            onTap: () => _actions(context, ref, bucket, '${o['key']}'),
          ),
        if (objects.length > 60 || listing['next_cursor'] != null)
          Padding(padding: const EdgeInsets.all(Space.s), child: Text('More in this bucket: ask for the next page.', style: context.text.labelSmall)),
        if (folders.isEmpty && objects.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('Empty.', style: context.text.bodySmall)),
      ],
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, String bucket, String key) async {
    final runner = ref.read(toolRunnerProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(bucket)),
            ListTile(leading: lead(const Icon(Icons.download_rounded)), title: const Text('Download and open'), onTap: () => Navigator.pop(context, 'get')),
            ListTile(leading: lead(const Icon(Icons.link_rounded)), title: const Text('Copy a 24-hour share link'), onTap: () => Navigator.pop(context, 'link')),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'link') {
      final r = await runner.run('r2_share_link', {'bucket': bucket, 'key': key, 'hours': 24});
      if (!context.mounted) return;
      if (r.json['url'] is String) {
        await Clipboard.setData(ClipboardData(text: r.json['url'] as String));
        if (context.mounted) showSnack(context, 'Link copied (works for 24 hours)');
      } else {
        showSnack(context, '${r.json['error']}', icon: Icons.error_outline_rounded);
      }
      return;
    }
    showSnack(context, 'Downloading $key…', icon: Icons.download_rounded);
    final r = await runner.run('r2_download', {'bucket': bucket, 'key': key});
    final files = r.json['created_files'] as List?;
    if (files != null && files.isNotEmpty) {
      await OpenFilex.open('${files.first}');
    } else if (context.mounted) {
      showSnack(context, '${r.json['error']}', icon: Icons.error_outline_rounded);
    }
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.url, required this.title, this.hours});
  final String url;
  final String title;
  final Object? hours;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Head(logo: _r2Logo, title: 'Share link · $title'),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
        child: Row(
          children: [
            Expanded(child: Text('Works for ${hours ?? 1} hour${hours == 1 ? '' : 's'}', style: context.text.bodySmall)),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                showSnack(context, 'Link copied');
              },
            ),
            const SizedBox(width: Space.s),
            FilledButton.tonal(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('Open')),
          ],
        ),
      ),
    ],
  );
}
