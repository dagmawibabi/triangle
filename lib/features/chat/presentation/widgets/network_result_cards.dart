import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:open_filex/open_filex.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/fullscreen_image.dart';
import '../../domain/chat_models.dart';
import 'api_console.dart';
import 'info_card_kit.dart';
import 'json_tree.dart';

/// Cards for the API and network tools: a response (api_request, api_send,
/// http_request), a key check, AI balances, and the diagnostics (http
/// diagnosis, DNS, certificate, ports, IP, domain registration, URL
/// checks). Null for other tools.
Widget? networkResultFor(ToolPart part, Map<String, dynamic> j) {
  Map<String, dynamic> full() {
    if (part.full case final f?) {
      try {
        return Map<String, dynamic>.from(jsonDecode(f) as Map);
      } catch (_) {}
    }
    return j;
  }

  switch (part.name) {
    case 'api_request' || 'api_send' when j['method'] != null:
      return ResponseCard(r: full());
    // The older any-method tool: same card, method from its arguments.
    case 'http_request' when j['status'] is num:
      return ResponseCard(r: {'method': '${part.args['method'] ?? 'GET'}'.toUpperCase(), ...j, 'error': null});
    case 'test_api_key' when j['works'] != null:
      return _KeyCheckCard(k: j);
    case 'ai_balances' when j['balances'] is List:
      return _BalancesCard(
        rows: [for (final r in j['balances'] as List) if (r is Map) Map<String, dynamic>.from(r)],
        missing: [for (final m in (j['without_key'] as List? ?? const [])) '$m'],
      );
    case 'http_diagnose' when j['steps'] is List:
      return _Framed(icon: Icons.monitor_heart_outlined, title: 'Diagnosis', subtitle: '${j['url']}', child: DiagnosisPanel(d: j));
    case 'dns_lookup' when j['records'] is Map:
      return _Framed(icon: Icons.dns_outlined, title: 'DNS · ${j['name']}', child: DnsPanel(d: j));
    case 'ssl_certificate' when j['host'] != null:
      return _Framed(icon: Icons.verified_user_outlined, title: 'Certificate · ${j['host']}', child: CertPanel(c: j));
    case 'port_check' when j['ports'] is List:
      return _Framed(icon: Icons.lan_outlined, title: 'Ports · ${j['host']}', child: _Ports(d: j));
    case 'my_ip' when j['ip'] != null:
      return _Framed(icon: Icons.public_rounded, title: 'This phone on the internet', child: _Ip(d: j));
    case 'whois_lookup' when j['domain'] != null:
      return _Framed(icon: Icons.badge_outlined, title: 'Domain · ${j['domain']}', child: _Whois(d: j));
    case 'url_check' when j['results'] is List:
      return _Framed(icon: Icons.fact_check_outlined, title: '${j['up']} of ${j['checked']} up', child: _UrlChecks(d: j));
  }
  return null;
}

Color _statusColor(int? s) => switch (s) {
  null => AppColors.danger,
  < 300 => AppColors.success,
  < 400 => AppColors.tint,
  < 500 => AppColors.warning,
  _ => AppColors.danger,
};

Color methodColor(String m) => switch (m) {
  'GET' || 'HEAD' || 'OPTIONS' => const Color(0xFF2E9E6B),
  'POST' => const Color(0xFF3B7DDD),
  'PUT' || 'PATCH' => const Color(0xFFD08A1E),
  'DELETE' => const Color(0xFFD9443A),
  _ => AppColors.text2,
};

String _size(num b) => b < 1024 ? '$b B' : b < 1048576 ? '${(b / 1024).toStringAsFixed(1)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';
String _ms(num ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';

class NetChip extends StatelessWidget {
  const NetChip(this.text, this.color, {super.key, this.solid = false, this.mono = true});
  final String text;
  final Color color;
  final bool solid;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: solid ? color : color.withValues(alpha: AppColors.isLight ? 0.1 : 0.16),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: solid ? Colors.white : color,
        fontFamily: mono ? 'monospace' : null,
        fontFeatures: tabularFigures,
      ),
    ),
  );
}

typedef _Chip = NetChip;

class _Framed extends StatelessWidget {
  const _Framed({required this.icon, required this.title, this.subtitle, required this.child});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => InfoFrame(
    child: Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.tint),
              const SizedBox(width: Space.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          child,
        ],
      ),
    ),
  );
}

// ---- a response ---------------------------------------------------------------------

/// Image links anywhere in [j] (up to [max]).
List<String> imageLinksIn(Object? j, {int max = 8}) {
  final out = <String>[];
  final re = RegExp(r'^https?://\S+\.(png|jpe?g|gif|webp|avif|svg)(\?\S*)?$', caseSensitive: false);
  final keys = RegExp(r'(image|img|thumb|avatar|photo|picture|icon|logo|poster|cover)', caseSensitive: false);
  void walk(Object? v, String key) {
    if (out.length >= max) return;
    if (v is String) {
      if (re.hasMatch(v) || (keys.hasMatch(key) && v.startsWith('https://'))) {
        if (!out.contains(v)) out.add(v);
      }
    } else if (v is Map) {
      for (final e in v.entries) {
        walk(e.value, '${e.key}');
      }
    } else if (v is List) {
      for (final x in v) {
        walk(x, key);
      }
    }
  }

  walk(j, '');
  return out;
}

class ResponseCard extends StatefulWidget {
  const ResponseCard({super.key, required this.r, this.inConsole = false});
  final Map<String, dynamic> r;
  final bool inConsole;

  @override
  State<ResponseCard> createState() => _ResponseCardState();
}

class _ResponseCardState extends State<ResponseCard> {
  final _tree = JsonTreeController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final method = '${r['method']}';
    final status = (r['status'] as num?)?.toInt();
    final uri = Uri.tryParse('${r['url']}');
    final json = r['json'];
    final body = r['body'] as String?;
    final error = r['error'] as String?;
    final media = r['media'] is Map ? Map<String, dynamic>.from(r['media'] as Map) : null;
    final images = json == null ? const <String>[] : imageLinksIn(json);
    final c = _statusColor(status);
    final preview = json != null ? const JsonEncoder.withIndent('  ').convert(json) : (body ?? '');
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(
              children: [
                _Chip(method, methodColor(method), solid: true),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(uri?.host ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        uri == null ? '${r['url']}' : '${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy response',
                  icon: Icon(Icons.copy_rounded, size: 17, color: AppColors.text2),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: preview));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Response copied'), duration: Duration(seconds: 2)));
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Chip(status == null ? 'FAILED' : '$status${r['reason'] != null ? ' ${r['reason']}' : ''}', c),
                if (r['latency_ms'] != null) _Chip(_ms(r['latency_ms'] as num), AppColors.text2),
                if (r['size_bytes'] != null) _Chip(_size(r['size_bytes'] as num), AppColors.text2),
                if ('${r['content_type'] ?? ''}'.isNotEmpty) _Chip('${r['content_type']}'.split(';').first, AppColors.text2),
                if (r['used_key'] != null) _Chip('🔑 ${r['used_key']}', AppColors.tint, mono: false),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              child: Text(error, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
            )
          else ...[
            if (media != null) _Media(media: media),
            if (images.isNotEmpty) _ImageLinks(urls: images),
            if (media == null || preview.isNotEmpty) ...[
              Divider(height: 1, color: AppColors.line),
              Container(
                color: AppColors.surface2.withValues(alpha: 0.5),
                constraints: BoxConstraints(maxHeight: _open ? 560 : 220),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.m),
                  child: json != null
                      ? JsonTree(data: json, controller: _tree)
                      : SelectableText(
                          preview.isEmpty ? '(empty body)' : preview,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: preview.isEmpty ? AppColors.text3 : AppColors.text),
                        ),
                ),
              ),
            ],
            Divider(height: 1, color: AppColors.line),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(_open ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, size: 18),
                    label: Text(_open ? 'Less' : 'More'),
                  ),
                ),
                if (!widget.inConsole)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => showApiConsole(context, response: r),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Inspect'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A picture, audio, video or PDF the API sent back.
class _Media extends StatefulWidget {
  const _Media({required this.media});
  final Map<String, dynamic> media;

  @override
  State<_Media> createState() => _MediaState();
}

class _MediaState extends State<_Media> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle(String path) async {
    final p = _player ??= AudioPlayer()..onPlayerComplete.listen((_) => mounted ? setState(() => _playing = false) : null);
    if (_playing) {
      await p.pause();
    } else {
      await p.play(DeviceFileSource(path));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final path = '${widget.media['path']}';
    final kind = '${widget.media['kind']}';
    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();
    if (kind == 'image' && !path.endsWith('.svg')) {
      return GestureDetector(
        onTap: () => openFullscreenFile(context, path, title: 'API image'),
        child: Container(
          color: AppColors.surface2,
          constraints: const BoxConstraints(maxHeight: 320),
          alignment: Alignment.center,
          child: Image.file(file, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(Space.l), child: Text('Can\'t show this picture'))),
        ),
      );
    }
    final (icon, label) = switch (kind) {
      'audio' => (_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, _playing ? 'Playing' : 'Play audio'),
      'video' => (Icons.smart_display_rounded, 'Open video'),
      _ => (Icons.picture_as_pdf_rounded, 'Open document'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.m),
        child: ListTile(
          leading: Icon(icon, size: 34, color: AppColors.tint),
          title: Text(label),
          subtitle: Text('${widget.media['type']}', style: context.text.labelSmall),
          trailing: kind == 'audio' ? IconButton(tooltip: 'Open', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => OpenFilex.open(path)) : null,
          onTap: () => kind == 'audio' ? _toggle(path) : OpenFilex.open(path),
        ),
      ),
    );
  }
}

/// Pictures a JSON answer links to, as a strip.
class _ImageLinks extends StatelessWidget {
  const _ImageLinks({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
      itemCount: urls.length,
      separatorBuilder: (_, _) => const SizedBox(width: Space.s),
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => openFullscreenUrl(context, urls[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.s),
          child: Image.network(
            urls[i],
            width: 96,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(width: 84, color: AppColors.surface2, child: Icon(Icons.broken_image_outlined, color: AppColors.text3)),
          ),
        ),
      ),
    ),
  );
}

// ---- a key check ----------------------------------------------------------------------

class _KeyCheckCard extends StatelessWidget {
  const _KeyCheckCard({required this.k});
  final Map<String, dynamic> k;

  @override
  Widget build(BuildContext context) {
    final works = k['works'] == true;
    final c = works ? AppColors.success : AppColors.danger;
    return InfoFrame(
      onTap: () => showKeyCheckSheet(context, k),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.m)),
              child: Icon(works ? Icons.verified_rounded : Icons.key_off_rounded, color: c, size: 22),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${k['name'] ?? k['service']}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    works ? (k['detail'] as String?)?.isNotEmpty == true ? '${k['detail']}' : 'The key works' : '${k['problem'] ?? 'The key didn\'t work'}',
                    style: context.text.bodySmall?.copyWith(color: works ? AppColors.text2 : AppColors.danger),
                  ),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(works ? 'VALID' : 'FAILED', c),
                      if (k['ends_with'] != null) _Chip('${k['ends_with']}', AppColors.text2),
                      if (k['latency_ms'] != null) _Chip(_ms(k['latency_ms'] as num), AppColors.text2),
                      if (k['saved_key'] == true) _Chip('saved key', AppColors.tint, mono: false),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

// ---- diagnostics ----------------------------------------------------------------------

/// A request's steps as a waterfall, then its redirects, certificate and
/// notable headers.
class DiagnosisPanel extends StatelessWidget {
  const DiagnosisPanel({super.key, required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final steps = [for (final s in (d['steps'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    final redirects = [for (final s in (d['redirects'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    final total = steps.fold<int>(0, (a, s) => a + ((s['ms'] as num?)?.toInt() ?? 0)).clamp(1, 1 << 30);
    final cert = d['certificate'] is Map ? Map<String, dynamic>.from(d['certificate'] as Map) : null;
    final headers = d['headers'] is Map ? Map<String, dynamic>.from(d['headers'] as Map) : const <String, dynamic>{};
    var start = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(d['ok'] == true ? 'HEALTHY' : 'PROBLEM', d['ok'] == true ? AppColors.success : AppColors.danger),
            if (d['status'] != null) _Chip('HTTP ${d['status']}', _statusColor((d['status'] as num).toInt())),
            if (d['total_ms'] != null) _Chip('total ${_ms(d['total_ms'] as num)}', AppColors.text2),
            if (d['server'] != null) _Chip('${d['server']}', AppColors.text2),
            if (d['compressed'] == true) _Chip('compressed', AppColors.text2),
          ],
        ),
        if (d['problem'] != null) ...[
          const SizedBox(height: Space.s),
          Text('${d['problem']}', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: Space.m),
        for (final s in steps)
          Builder(
            builder: (context) {
              final ms = (s['ms'] as num?)?.toInt() ?? 0;
              final from = start / total;
              final width = (ms / total).clamp(0.02, 1.0);
              start += ms;
              final ok = s['ok'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 92, child: Text('${s['step']}', style: context.text.labelMedium)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [
                            Container(height: 12, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4))),
                            Positioned(
                              left: box.maxWidth * from.clamp(0.0, 0.98),
                              child: Container(
                                width: box.maxWidth * width,
                                height: 12,
                                decoration: BoxDecoration(color: ok ? AppColors.tint : AppColors.danger, borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 60, child: Text(_ms(ms), textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures))),
                  ],
                ),
              );
            },
          ),
        for (final s in steps)
          if ('${s['detail'] ?? ''}'.isNotEmpty && s['ok'] != true)
            Text('${s['step']}: ${s['detail']}', style: context.text.labelSmall?.copyWith(color: AppColors.danger)),
        if (redirects.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('REDIRECTS', style: context.text.labelSmall),
          for (final r in redirects)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _Chip('${r['status']}', AppColors.tint),
                  const SizedBox(width: 6),
                  Expanded(child: Text('→ ${r['to']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5))),
                ],
              ),
            ),
        ],
        if (cert != null) ...[
          const SizedBox(height: Space.m),
          CertPanel(c: {...cert, 'valid': true}),
        ],
        if (headers.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('NOTABLE HEADERS', style: context.text.labelSmall),
          for (final e in headers.entries) KeyValueRow(e.key, '${e.value}', mono: true),
        ],
      ],
    );
  }
}

class CertPanel extends StatelessWidget {
  const CertPanel({super.key, required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    if (c['valid'] == false) {
      return Text('${c['problem'] ?? 'Not trusted'}', style: context.text.bodySmall?.copyWith(color: AppColors.danger));
    }
    final days = (c['days_left'] as num?)?.toInt();
    final color = days == null ? AppColors.text2 : days < 0 ? AppColors.danger : days < 14 ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.m)),
      child: Row(
        children: [
          Icon(days != null && days < 0 ? Icons.gpp_bad_outlined : Icons.verified_user_outlined, color: color),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['subject'] ?? 'Certificate'}', style: context.text.titleSmall),
                Text('Issued by ${c['issuer'] ?? '?'} · ${c['valid_from'] ?? ''} to ${c['valid_until'] ?? ''}', style: context.text.labelSmall),
              ],
            ),
          ),
          if (days != null)
            Column(
              children: [
                Text('$days', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color, fontFeatures: tabularFigures)),
                Text(days < 0 ? 'days ago' : 'days left', style: context.text.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}

class DnsPanel extends StatelessWidget {
  const DnsPanel({super.key, required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final records = Map<String, dynamic>.from(d['records'] as Map? ?? const {});
    if (records.isEmpty) return Text('${d['note'] ?? 'No records.'}', style: context.text.bodySmall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in records.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 56, child: _Chip(e.key, AppColors.tint)),
                const SizedBox(width: Space.s),
                Expanded(
                  child: SelectableText(
                    (e.value as List).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Ports extends StatelessWidget {
  const _Ports({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final p in (d['ports'] as List))
        if (p is Map) _Chip('${p['port']} ${p['open'] == true ? 'open · ${p['ms']}ms' : 'closed'}', p['open'] == true ? AppColors.success : AppColors.text3),
    ],
  );
}

class _Ip extends StatelessWidget {
  const _Ip({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText('${d['ip']}', style: context.text.headlineSmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      const SizedBox(height: Space.s),
      if (d['network'] != null) KeyValueRow('Network', '${d['network']}${d['asn'] != null ? ' (${d['asn']})' : ''}'),
      if (d['city'] != null || d['country'] != null) KeyValueRow('Location', [d['city'], d['region'], d['country']].whereType<Object>().join(', ')),
      if (d['timezone'] != null) KeyValueRow('Time zone', '${d['timezone']}'),
    ],
  );
}

class _Whois extends StatelessWidget {
  const _Whois({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    if (d['registered'] == false) {
      return Text('Not registered: it may be available.', style: context.text.bodyMedium?.copyWith(color: AppColors.success));
    }
    if (d['problem'] != null) return Text('${d['problem']}', style: context.text.bodySmall);
    final days = (d['days_left'] as num?)?.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d['registrar'] != null) KeyValueRow('Registrar', '${d['registrar']}'),
        if (d['created'] != null) KeyValueRow('Registered', '${d['created']}'),
        if (d['expires'] != null) KeyValueRow('Expires', '${d['expires']}${days == null ? '' : ' · $days days'}', valueColor: days != null && days < 30 ? AppColors.warning : null),
        if ((d['nameservers'] as List? ?? const []).isNotEmpty) KeyValueRow('Name servers', (d['nameservers'] as List).join(', '), mono: true),
        if ((d['status'] as List? ?? const []).isNotEmpty) KeyValueRow('Status', (d['status'] as List).join(', ')),
      ],
    );
  }
}

class _UrlChecks extends StatelessWidget {
  const _UrlChecks({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final r in (d['results'] as List))
        if (r is Map)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(r['up'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 16, color: r['up'] == true ? AppColors.success : AppColors.danger),
                const SizedBox(width: 6),
                Expanded(child: Text('${r['url']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                if (r['status'] != null) ...[_Chip('${r['status']}', _statusColor((r['status'] as num).toInt())), const SizedBox(width: 4)],
                Text(_ms((r['ms'] as num?) ?? 0), style: context.text.labelSmall?.copyWith(fontFeatures: tabularFigures)),
              ],
            ),
          ),
    ],
  );
}

// ---- balances -----------------------------------------------------------------------

class _BalancesCard extends StatelessWidget {
  const _BalancesCard({required this.rows, required this.missing});
  final List<Map<String, dynamic>> rows;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    final count = NumberFormat.compact();
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoHeader(Icons.account_balance_wallet_outlined, 'AI balances'),
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, indent: Space.m, endIndent: Space.m, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
              child: Builder(
                builder: (context) {
                  final balance = r['balance'] as num?;
                  final total = r['total'] as num?;
                  final used = r['used'] as num?;
                  final usd = r['currency'] == 'USD';
                  String fmt(num v) => usd ? money.format(v) : '${count.format(v)}${r['unit'] == 'characters' ? ' chars' : ''}';
                  final fraction = balance != null && total != null && total > 0 ? (balance / total).clamp(0.0, 1.0).toDouble() : null;
                  final low = fraction != null && fraction < 0.15;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r['name']}', style: context.text.titleSmall),
                                if (r['problem'] != null || r['note'] != null || r['plan'] != null || r['resets'] != null)
                                  Text(
                                    [
                                      if (r['problem'] != null) 'Couldn\'t read it: ${r['problem']}',
                                      if (r['plan'] != null) '${r['plan']} plan',
                                      if (r['resets'] != null) 'resets ${r['resets']}',
                                      if (r['problem'] == null && r['note'] != null) '${r['note']}',
                                    ].join(' · '),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodySmall?.copyWith(color: r['problem'] != null ? AppColors.warning : AppColors.text3),
                                  ),
                              ],
                            ),
                          ),
                          if (balance != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  fmt(balance),
                                  style: context.text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: tabularFigures,
                                    color: low ? AppColors.danger : null,
                                  ),
                                ),
                                Text(used == null ? 'left' : 'left · ${fmt(used)} used', style: context.text.labelSmall),
                              ],
                            ),
                        ],
                      ),
                      if (fraction != null) ...[
                        const SizedBox(height: Space.s),
                        ShareBar(fraction, color: low ? AppColors.danger : AppColors.success),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
              child: Text('No key: ${missing.join(', ')}', style: context.text.labelSmall),
            ),
        ],
      ),
    );
  }
}
