import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../canvas/canvas_store.dart';
import '../../../canvas/save_to_canvas.dart';
import '../../../integrations/app_toolkits.dart';
import '../../../integrations/integrations_store.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../domain/chat_models.dart';

part 'slack_channel_screen.dart';

/// Cards for what connected apps return: an inbox, Slack messages and
/// channels, Notion pages, events, files, issues and notifications, tasks,
/// a document or a spreadsheet range, and a Connect button when an app
/// still needs signing in to. Tapping a row opens it in full.
///
/// [j] is the tool's result after AppResults.summarize. Null when there is
/// nothing to draw, which keeps the plain card.
Widget? appResultFor(ToolPart part, Map<String, dynamic> j) {
  if (part.name == 'connect_app') {
    if (j['needs_connection'] == true && j['connect_url'] is String) {
      return _ConnectCard(app: '${j['app']}', url: j['connect_url'] as String);
    }
    if (j['connected'] == true) return _ConnectedChip(app: '${j['app']}');
    return null;
  }
  if (j['app'] is! String) return null;
  final app = j['app'] as String;
  List<Map<String, dynamic>> list(String k) => [
    for (final x in (j[k] as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  // The Slack conversation the call was about, when it named one by id.
  String? argChannel;
  try {
    final args = jsonDecode(part.arguments);
    final c = args is Map ? '${args['channel'] ?? args['channel_id'] ?? ''}' : '';
    if (RegExp(r'^[CGD][A-Z0-9]{6,}$').hasMatch(c)) argChannel = c;
  } catch (_) {}
  final parts = <Widget>[
    if (list('emails').isNotEmpty) _EmailList(app: app, emails: list('emails')),
    if (list('events').isNotEmpty) _EventList(app: app, events: list('events')),
    if (list('messages').isNotEmpty) _SlackList(messages: list('messages'), channelId: argChannel),
    if (list('channels').isNotEmpty) _ChannelList(channels: list('channels')),
    if (list('notifications').isNotEmpty) _NotificationList(items: list('notifications')),
    if (list('issues').isNotEmpty) _IssueList(app: app, issues: list('issues')),
    if (list('pages').isNotEmpty) _PageList(pages: list('pages')),
    if (list('tasks').isNotEmpty) _TaskList(tasks: list('tasks')),
    if (list('files').isNotEmpty) _FileList(files: list('files')),
    if (j['document'] is Map) _DocCard(app: app, doc: Map<String, dynamic>.from(j['document'] as Map)),
    if (j['table'] is Map) _TableCard(table: Map<String, dynamic>.from(j['table'] as Map)),
  ];
  if (parts.isEmpty) return null;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: parts);
}

// ---- shared ---------------------------------------------------------------------

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return DateTime.tryParse(s)?.toLocal();
}

/// 14:05 today, "Mon 14:05" this week, "12 Oct" this year, else "12 Oct 2025".
String _when(Object? v, {bool time = true}) {
  final d = _date(v);
  if (d == null) return v == null ? '' : '$v';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0 && time) return DateFormat.Hm().format(d);
  if (diff.abs() < 7 && time) return DateFormat('EEE HH:mm').format(d);
  if (d.year == now.year) return DateFormat('d MMM').format(d);
  return DateFormat('d MMM y').format(d);
}

/// `Ada Lovelace` from `Ada Lovelace <ada@x.org>`.
String _name(String party) {
  final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(party);
  if (m != null) return m.group(1)!.trim();
  return party.trim();
}

class _AppLogo extends StatelessWidget {
  const _AppLogo(this.app, {this.size = 18});
  final String app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = appToolkit(app);
    final fallback = Icon(t?.icon ?? Icons.apps_rounded, size: size, color: t?.color ?? AppColors.text2);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: AppLogo(app, size: size, fallback: fallback),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.title});
  final String app;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.xs),
    child: Row(
      children: [
        _AppLogo(app),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(title, style: context.text.labelMedium?.copyWith(color: AppColors.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

/// The first [shown] rows, and a "Show all" that opens the rest.
class _Rows extends StatefulWidget {
  const _Rows({required this.rows, this.shown = 5});
  final List<Widget> rows;
  final int shown;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final rows = _all ? widget.rows : widget.rows.take(widget.shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed) ...[if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m), r],
        if (widget.rows.length > widget.shown)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show less' : 'Show all ${widget.rows.length}'),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: c), const SizedBox(width: 3)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

Future<void> _sheet(BuildContext context, Widget Function(ScrollController) body) =>
    showAppSheet<void>(context, builder: (_, scroll) => body(scroll));

typedef _Avatar = LetterAvatar;

// ---- connect -----------------------------------------------------------------

class _ConnectCard extends ConsumerStatefulWidget {
  const _ConnectCard({required this.app, required this.url});
  final String app;
  final String url;

  @override
  ConsumerState<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends ConsumerState<_ConnectCard> with WidgetsBindingObserver {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _opened) ref.read(integrationsProvider.notifier).refresh();
  }

  Future<void> _connect() async {
    // Links expire; a fresh one when the saved one is old.
    var url = widget.url;
    try {
      url = await ref.read(integrationsProvider.notifier).linkFor(widget.app);
    } catch (_) {}
    _opened = true;
    await _open(url);
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(integrationsProvider).connected.contains(widget.app);
    final label = appLabel(widget.app);
    final t = appToolkit(widget.app);
    return _Panel(
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Row(
            children: [
              _AppLogo(widget.app, size: 36),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? '$label is connected' : 'Connect $label', style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? 'Ask again and the assistant will use it.'
                          : (t?.description ?? 'Sign in on Composio\'s page so the assistant can use your $label.'),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: connected
              ? _Pill('Connected', color: AppColors.success, icon: Icons.check_rounded)
              : FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text('Connect $label'),
                ),
        ),
      ],
    );
  }
}

class _ConnectedChip extends StatelessWidget {
  const _ConnectedChip({required this.app});
  final String app;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AppLogo(app, size: 16),
          const SizedBox(width: 6),
          _Pill('${appLabel(app)} connected', color: AppColors.success, icon: Icons.check_rounded),
        ],
      ),
    ),
  );
}

// ---- email -------------------------------------------------------------------

class _EmailList extends StatelessWidget {
  const _EmailList({required this.app, required this.emails});
  final String app;
  final List<Map<String, dynamic>> emails;

  @override
  Widget build(BuildContext context) {
    final unread = emails.where((e) => e['unread'] == true).length;
    return _Panel(
      children: [
        _Header(
          app: app,
          title: '${appLabel(app)} · ${emails.length} email${emails.length == 1 ? '' : 's'}${unread > 0 ? ' · $unread unread' : ''}',
        ),
        _Rows(rows: [for (final e in emails) _EmailRow(app: app, email: e)]),
      ],
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.app, required this.email});
  final String app;
  final Map<String, dynamic> email;

  @override
  Widget build(BuildContext context) {
    final from = _name('${email['from'] ?? ''}');
    final unread = email['unread'] == true;
    final attachments = (email['attachments'] as List?)?.length ?? 0;
    return InkWell(
      onTap: () => showEmail(context, app, email),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(from),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          from.isEmpty ? '(unknown sender)' : from,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ),
                      if (email['starred'] == true) Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                      if (attachments > 0) Icon(Icons.attach_file_rounded, size: 14, color: AppColors.text3),
                      const SizedBox(width: 4),
                      Text(_when(email['date']), style: context.text.labelSmall?.copyWith(color: unread ? AppColors.accent : AppColors.text3)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${email['subject'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
                  ),
                  if ('${email['snippet'] ?? ''}'.isNotEmpty)
                    Text(
                      '${email['snippet']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(height: 1.3),
                    ),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: Space.s, top: 6),
                child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}

String? _emailWebUrl(String app, Map<String, dynamic> e) {
  if (e['link'] is String) return e['link'] as String;
  final id = e['thread_id'] ?? e['id'];
  if (app == 'gmail' && id != null) return 'https://mail.google.com/mail/u/0/#all/$id';
  return appToolkit(app)?.openUrl;
}

void showEmail(BuildContext context, String app, Map<String, dynamic> e) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (_) => FractionallySizedBox(heightFactor: 0.94, child: _EmailReader(app: app, email: e)),
);

/// One email in full: its headers, then the message as it was styled (in a
/// web view with scripts off; links open in the browser, remote images
/// load), or its text with tappable links when there is no HTML. A Gmail
/// message listed without its body is fetched when opened.
class _EmailReader extends ConsumerStatefulWidget {
  const _EmailReader({required this.app, required this.email});
  final String app;
  final Map<String, dynamic> email;

  @override
  ConsumerState<_EmailReader> createState() => _EmailReaderState();
}

class _EmailReaderState extends ConsumerState<_EmailReader> {
  late Map<String, dynamic> _e = widget.email;
  WebViewController? _web;
  bool _loading = false;
  bool _showHeaders = true;

  @override
  void initState() {
    super.initState();
    final path = _e['html_path'] as String?;
    if (path != null && File(path).existsSync()) {
      _show(File(path).readAsStringSync());
    } else if (widget.app == 'gmail' && _e['id'] != null) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final r = await ref.read(toolRunnerProvider).run('gmail_fetch_message_by_message_id', {'message_id': _e['id'], 'format': 'full'});
    if (!mounted) return;
    final full = (r.json['emails'] as List?)?.whereType<Map>().firstOrNull;
    setState(() {
      _loading = false;
      if (full != null) _e = {..._e, ...Map<String, dynamic>.from(full)};
    });
    final path = _e['html_path'] as String?;
    if (path != null && File(path).existsSync()) _show(await File(path).readAsString());
  }

  /// The email's own HTML, made to fit a phone. Emails assume a white page.
  static String _page(String html) {
    const head = '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<style>html,body{margin:0;padding:8px;background:#fff;color:#111;font-family:-apple-system,Roboto,sans-serif;'
        'word-wrap:break-word;overflow-wrap:anywhere}img{max-width:100%!important;height:auto!important}'
        'table{max-width:100%!important}pre{white-space:pre-wrap}</style>';
    final lower = html.toLowerCase();
    if (lower.contains('<head')) return html.replaceFirst(RegExp(r'<head[^>]*>', caseSensitive: false), r'$0' + head);
    if (lower.contains('<html')) return html.replaceFirst(RegExp(r'<html[^>]*>', caseSensitive: false), r'$0<head>' + head + '</head>');
    return '<!doctype html><html><head>$head</head><body>$html</body></html>';
  }

  void _show(String html) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) {
            if (r.url.startsWith('about:') || r.url.startsWith('data:')) return NavigationDecision.navigate;
            if (r.isMainFrame) _open(r.url);
            return NavigationDecision.prevent;
          },
        ),
      );
    // A base URL lets protocol-relative image links load.
    c.loadHtmlString(_page(html.replaceAll('src="//', 'src="https://')), baseUrl: 'https://mail.teleai.local/');
    setState(() => _web = c);
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final app = widget.app;
    final body = '${e['body'] ?? ''}'.trim().isEmpty ? '${e['snippet'] ?? ''}' : '${e['body']}';
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SelectableText('${e['subject'] ?? '(no subject)'}', style: context.text.titleLarge)),
              if (_web != null)
                IconButton(
                  tooltip: _showHeaders ? 'Hide details' : 'Show details',
                  icon: Icon(_showHeaders ? Icons.unfold_less_rounded : Icons.unfold_more_rounded),
                  onPressed: () => setState(() => _showHeaders = !_showHeaders),
                ),
            ],
          ),
          if (_showHeaders) ...[
            const SizedBox(height: Space.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(_name('${e['from'] ?? ''}'), size: 40),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('${e['from'] ?? ''}', style: context.text.titleSmall),
                      if ('${e['to'] ?? ''}'.isNotEmpty) Text('to ${e['to']}', style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (e['date'] != null)
                        Text(
                          _date(e['date']) == null ? '${e['date']}' : DateFormat('EEE d MMM y, HH:mm').format(_date(e['date'])!),
                          style: context.text.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if ((e['labels'] as List? ?? const []).isNotEmpty || (e['attachments'] as List? ?? const []).isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in (e['labels'] as List? ?? const []))
                    if (!'$l'.startsWith('CATEGORY_') && !'$l'.startsWith('Label_')) _Pill('$l'.toLowerCase()),
                  for (final a in (e['attachments'] as List? ?? const [])) _Pill('$a', icon: Icons.attach_file_rounded),
                ],
              ),
            ],
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                if (_emailWebUrl(app, e) case final url?)
                  FilledButton.tonalIcon(
                    onPressed: () => _open(url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text('Open in ${appLabel(app)}'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: body));
                    showSnack(context, 'Email copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy text'),
                ),
                OutlinedButton.icon(
                  onPressed: () => saveToCanvas(
                    context,
                    ref,
                    kind: CanvasKind.email,
                    title: '${e['subject'] ?? 'Email'}',
                    text: [if ('${e['from'] ?? ''}'.isNotEmpty) 'From ${e['from']}', body.length > 1500 ? '${body.substring(0, 1500)}…' : body].join('\n\n'),
                    url: _emailWebUrl(app, e) ?? '',
                    source: appLabel(app),
                    path: '${e['html_path'] ?? ''}',
                  ),
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
                  label: const Text('Save to Canvas'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    final web = _web;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1),
        Expanded(
          child: web != null
              ? WebViewWidget(
                  controller: web,
                  gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
                )
              : _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.l),
                  child: MarkdownBody(
                    data: _linkify(body),
                    selectable: true,
                    onTapLink: (_, href, _) => _open(href),
                    styleSheet: MarkdownStyleSheet(p: const TextStyle(height: 1.5)),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Plain email text as Markdown with its web addresses as links, the
/// "Label ( https://… )" pattern newsletters use folded into the label.
String _linkify(String text) {
  final escaped = text.replaceAllMapped(RegExp(r'([\\`*_\[\]#])'), (m) => '\\${m[1]}');
  return escaped
      .replaceAllMapped(
        RegExp(r'([^\n()]{1,60}?)\s*\(\s*(https?://[^\s)]+)\s*\)'),
        (m) => '[${m[1]!.trim()}](${m[2]})',
      )
      .replaceAllMapped(
        RegExp(r'(^|[\s<])(https?://[^\s<>()\]]+[^\s<>()\].,;:!?])'),
        (m) => '${m[1]}[${_shortUrl(m[2]!)}](${m[2]})',
      )
      .replaceAll('\n', '  \n');
}

String _shortUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return url;
  final path = u.path.length > 24 ? '${u.path.substring(0, 24)}…' : u.path;
  return '${u.host.replaceFirst('www.', '')}${path == '/' ? '' : path}';
}

// ---- calendar ----------------------------------------------------------------

class _EventList extends StatelessWidget {
  const _EventList({required this.app, required this.events});
  final String app;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]..sort((a, b) => '${a['start']}'.compareTo('${b['start']}'));
    return _Panel(
      children: [
        _Header(app: app, title: '${appLabel(app)} · ${events.length} event${events.length == 1 ? '' : 's'}'),
        _Rows(rows: [for (final e in sorted) _EventRow(event: e)], shown: 6),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final start = _date(event['start']);
    final end = _date(event['end']);
    final allDay = event['all_day'] == true;
    final now = DateTime.now();
    final live = start != null && end != null && now.isAfter(start) && now.isBefore(end);
    final time = start == null
        ? '${event['start']}'
        : allDay
        ? 'All day'
        : '${DateFormat.Hm().format(start)}${end == null ? '' : ' – ${DateFormat.Hm().format(end)}'}';
    return InkWell(
      onTap: () => _open((event['meet'] ?? event['link']) as String?),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          children: [
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: (live ? AppColors.success : AppColors.accent).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              child: Column(
                children: [
                  Text(
                    start == null ? '' : DateFormat('MMM').format(start).toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: live ? AppColors.success : AppColors.accent),
                  ),
                  Text(start == null ? '?' : '${start.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.1)),
                  Text(start == null ? '' : DateFormat('EEE').format(start), style: context.text.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${event['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [time, if (event['location'] != null) '${event['location']}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                  if (live || event['attendees'] != null || event['meet'] != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (live) _Pill('Now', color: AppColors.success),
                        if (event['attendees'] != null) _Pill('${event['attendees']} guests', icon: Icons.group_outlined),
                        if (event['meet'] != null) _Pill('Video call', icon: Icons.videocam_outlined, color: AppColors.success),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (event['link'] != null || event['meet'] != null) Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

// ---- slack -------------------------------------------------------------------

class _SlackList extends StatelessWidget {
  const _SlackList({required this.messages, this.channelId});
  final List<Map<String, dynamic>> messages;

  /// The channel the call read, when the messages don't say.
  final String? channelId;

  @override
  Widget build(BuildContext context) {
    final channels = {for (final m in messages) if (m['channel'] != null) '${m['channel']}'};
    final ids = {for (final m in messages) if (m['channel_id'] != null) '${m['channel_id']}'};
    // One channel: it can open full screen.
    final id = ids.length == 1 ? ids.first : (ids.isEmpty ? channelId : null);
    final name = channels.length == 1 && channels.first != id ? channels.first : null;
    return _Panel(
      children: [
        _Header(
          app: 'slack',
          title: 'Slack · ${messages.length} message${messages.length == 1 ? '' : 's'}${name != null ? ' in #$name' : ''}',
        ),
        _Rows(rows: [for (final m in messages) _SlackRow(message: m, showChannel: channels.length > 1, channelId: id)], shown: 6),
        if (id != null)
          TextButton.icon(
            onPressed: () => openSlackChannel(context, id: id, name: name),
            icon: const Icon(Icons.open_in_full_rounded, size: 16),
            label: Text(name == null ? 'Open channel' : 'Open #$name'),
          ),
      ],
    );
  }
}

class _SlackRow extends StatelessWidget {
  const _SlackRow({required this.message, required this.showChannel, this.channelId});
  final Map<String, dynamic> message;
  final bool showChannel;
  final String? channelId;

  @override
  Widget build(BuildContext context) {
    final author = '${message['author'] ?? ''}';
    final text = _slackText('${message['text'] ?? ''}');
    final channel = message['channel_id'] as String? ?? channelId;
    final channelName = message['channel'] != null && message['channel'] != channel ? '${message['channel']}' : null;
    return InkWell(
      onTap: () => _sheet(
        context,
        (scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            Row(
              children: [
                _Avatar(author, size: 36),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author, style: context.text.titleSmall),
                      Text(
                        [if (message['channel'] != null) '#${message['channel']}', _when(message['when'])].join(' · '),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            MarkdownBody(data: text, selectable: true, onTapLink: (_, href, _) => _open(href)),
            const SizedBox(height: Space.l),
            if (channel != null) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  openSlackChannel(context, id: channel, name: channelName);
                },
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: Text(channelName == null ? 'Open the channel' : 'Open #$channelName'),
              ),
              const SizedBox(height: Space.s),
            ],
            if (message['permalink'] is String)
              FilledButton.tonalIcon(
                onPressed: () => _open(message['permalink'] as String),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open in Slack'),
              ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(author, size: 30),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      if (showChannel && message['channel'] != null) ...[
                        const SizedBox(width: 6),
                        Text('#${message['channel']}', style: context.text.labelSmall),
                      ],
                      const Spacer(),
                      Text(_when(message['when']), style: context.text.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35, fontSize: 13.5)),
                  if (message['replies'] != null || (message['reactions'] as List? ?? const []).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (message['replies'] != null) _Pill('${message['replies']} replies', icon: Icons.forum_outlined, color: AppColors.accent),
                        for (final r in (message['reactions'] as List? ?? const []).take(5)) _Pill(':$r'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slack's mrkdwn, near enough Markdown: `<url|label>` links, *bold*, ~strike~.
String _slackText(String s) => s
    .replaceAllMapped(RegExp(r'<(https?://[^|>]+)\|([^>]+)>'), (m) => '[${m[2]}](${m[1]})')
    .replaceAllMapped(RegExp(r'<(https?://[^>]+)>'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'<#\w+\|([^>]+)>'), (m) => '#${m[1]}')
    .replaceAllMapped(RegExp(r'<@(\w+)>'), (m) => '@${m[1]}')
    .replaceAllMapped(RegExp(r'(^|\s)\*([^*\n]+)\*(?=\s|$)'), (m) => '${m[1]}**${m[2]}**')
    .replaceAllMapped(RegExp(r'(^|\s)~([^~\n]+)~(?=\s|$)'), (m) => '${m[1]}~~${m[2]}~~');

class _ChannelList extends StatelessWidget {
  const _ChannelList({required this.channels});
  final List<Map<String, dynamic>> channels;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: 'slack', title: 'Slack · ${channels.length} channel${channels.length == 1 ? '' : 's'}'),
      _Rows(
        shown: 8,
        rows: [
          for (final c in channels)
            ListTile(
              dense: true,
              onTap: c['id'] == null ? null : () => openSlackChannel(context, id: '${c['id']}', name: '${c['name']}'),
              leading: lead(Icon(c['private'] == true ? Icons.lock_outline_rounded : Icons.tag_rounded, size: 20, color: AppColors.text2)),
              title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: c['topic'] == null ? null : Text('${c['topic']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c['members'] != null) Text('${c['members']}', style: context.text.labelSmall),
                  Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

// ---- github, linear ----------------------------------------------------------

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: 'github', title: 'GitHub · ${items.length} notification${items.length == 1 ? '' : 's'}'),
      _Rows(
        shown: 6,
        rows: [
          for (final n in items)
            ListTile(
              dense: true,
              onTap: () => _open(n['url'] as String?),
              leading: lead(Icon(
                n['type'] == 'PullRequest' ? Icons.merge_type_rounded : (n['type'] == 'Release' ? Icons.sell_outlined : Icons.adjust_rounded),
                size: 20,
                color: n['unread'] == true ? AppColors.accent : AppColors.text3,
              )),
              title: Text('${n['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(['${n['repo']}', '${n['reason']}'.replaceAll('_', ' '), _when(n['updated'])].where((x) => x.isNotEmpty).join(' · ')),
            ),
        ],
      ),
    ],
  );
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.app, required this.issues});
  final String app;
  final List<Map<String, dynamic>> issues;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: app, title: '${appLabel(app)} · ${issues.length} item${issues.length == 1 ? '' : 's'}'),
      _Rows(shown: 6, rows: [for (final i in issues) _IssueRow(issue: i)]),
    ],
  );
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});
  final Map<String, dynamic> issue;

  @override
  Widget build(BuildContext context) {
    final state = '${issue['state'] ?? ''}'.toLowerCase();
    final merged = issue['merged'] == true;
    final closed = merged || state == 'closed' || state == 'done' || state == 'canceled' || state == 'cancelled';
    final color = merged ? const Color(0xFFA371F7) : (closed ? AppColors.text3 : AppColors.success);
    final icon = issue['pull'] == true ? Icons.merge_type_rounded : (closed ? Icons.check_circle_outline_rounded : Icons.adjust_rounded);
    return InkWell(
      onTap: () => issue['body'] == null
          ? _open(issue['url'] as String?)
          : _sheet(
              context,
              (scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
                children: [
                  Text('${issue['title']}', style: context.text.titleLarge),
                  const SizedBox(height: Space.s),
                  Text([if (issue['repo'] != null) '${issue['repo']}', '${issue['number'] ?? ''}', '${issue['state'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '), style: context.text.bodySmall),
                  const Divider(height: Space.xxl),
                  MarkdownBody(data: '${issue['body']}', selectable: true, onTapLink: (_, href, _) => _open(href)),
                  const SizedBox(height: Space.l),
                  if (issue['url'] is String)
                    FilledButton.tonalIcon(
                      onPressed: () => _open(issue['url'] as String),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open'),
                    ),
                ],
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.m, Space.s + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${issue['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (issue['repo'] != null) '${issue['repo']}',
                      if (issue['number'] != null) '${issue['number']}',
                      if (issue['assignee'] != null) '→ ${issue['assignee']}',
                      if (issue['priority'] != null) '${issue['priority']}',
                      _when(issue['updated'], time: false),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: context.text.bodySmall,
                  ),
                  if ((issue['labels'] as List? ?? const []).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [for (final l in (issue['labels'] as List).take(5)) _Pill('$l')]),
                  ],
                ],
              ),
            ),
            if (issue['state'] != null) _Pill(merged ? 'merged' : '${issue['state']}', color: color),
          ],
        ),
      ),
    );
  }
}

// ---- notion ------------------------------------------------------------------

class _PageList extends StatelessWidget {
  const _PageList({required this.pages});
  final List<Map<String, dynamic>> pages;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: 'notion', title: 'Notion · ${pages.length} page${pages.length == 1 ? '' : 's'}'),
      _Rows(
        shown: 6,
        rows: [
          for (final p in pages)
            ListTile(
              dense: true,
              // Pages open here, read from Notion; databases (and a long
              // press on anything) open in Notion.
              onTap: p['kind'] == 'database' || p['id'] == null
                  ? () => _open(p['url'] as String?)
                  : () => showNotionPage(context, p),
              onLongPress: p['url'] == null ? null : () => _open(p['url'] as String?),
              leading: lead(SizedBox(
                width: 24,
                child: Center(
                  child: p['icon'] != null
                      ? Text('${p['icon']}', style: const TextStyle(fontSize: 18))
                      : Icon(p['kind'] == 'database' ? Icons.table_rows_outlined : Icons.description_outlined, size: 20, color: AppColors.text2),
                ),
              )),
              title: Text('${p['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [p['kind'] == 'database' ? 'Database' : 'Page', if (p['edited'] != null) 'edited ${_when(p['edited'], time: false)}', if (p['archived'] == true) 'archived'].join(' · '),
              ),
              trailing: p['kind'] == 'database'
                  ? (p['url'] == null ? null : Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.text3))
                  : Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
            ),
        ],
      ),
    ],
  );
}

/// A Notion page read in a sheet: fetched as Markdown through the Notion
/// connection and shown here, with a way out to Notion itself.
void showNotionPage(BuildContext context, Map<String, dynamic> page) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (_, scroll) => _NotionPageReader(page: page, scroll: scroll),
);

class _NotionPageReader extends ConsumerStatefulWidget {
  const _NotionPageReader({required this.page, required this.scroll});
  final Map<String, dynamic> page;
  final ScrollController scroll;

  @override
  ConsumerState<_NotionPageReader> createState() => _NotionPageReaderState();
}

class _NotionPageReaderState extends ConsumerState<_NotionPageReader> {
  String? _text;
  String? _error;
  int? _fullLength;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(toolRunnerProvider).run('notion_get_page_markdown', {'page_id': widget.page['id']});
      if (!mounted) return;
      final doc = r.json['document'];
      final text = doc is Map ? '${doc['text'] ?? ''}' : '';
      setState(() {
        _loading = false;
        if (r.json['error'] != null) {
          _error = '${r.json['error']}';
        } else if (text.trim().isEmpty) {
          _text = '';
        } else {
          _text = _clean(text);
          _fullLength = doc is Map ? (doc['truncated_from_chars'] as num?)?.toInt() : null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// Notion-flavoured Markdown wraps some blocks in tags (<callout>,
  /// <details>, <empty-block/>…) the Markdown view would print as text:
  /// keep what's inside them, drop the tags.
  static String _clean(String md) => md
      .replaceAll(RegExp(r'<empty-block\s*/?>'), '')
      .replaceAll(RegExp(r'</?(callout|details|summary|columns?|page|database|mention-\w+|table_of_contents|synced_block|toggle|span|color)\b[^>]*>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final url = p['url'] as String?;
    final icon = p['icon'] as String?;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: Space.m),
            ],
            Expanded(child: Text('${p['title'] ?? 'Untitled'}', style: context.text.headlineSmall)),
            if (url != null)
              IconButton(
                tooltip: 'Open in Notion',
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                onPressed: () => _open(url),
              ),
          ],
        ),
        if (p['edited'] != null) ...[
          const SizedBox(height: Space.xs),
          Text('Edited ${_when(p['edited'])}', style: context.text.bodySmall),
        ],
        const SizedBox(height: Space.l),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.x4),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_error != null) ...[
          Text('Couldn\'t load this page: $_error', style: context.text.bodyMedium?.copyWith(color: AppColors.danger)),
          const SizedBox(height: Space.m),
          Row(
            children: [
              OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
              if (url != null) ...[
                const SizedBox(width: Space.s),
                FilledButton.tonalIcon(onPressed: () => _open(url), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open in Notion')),
              ],
            ],
          ),
        ] else if (_text!.isEmpty)
          Text('This page is empty.', style: context.text.bodyMedium?.copyWith(color: AppColors.text3))
        else ...[
          MarkdownBody(
            data: _text!,
            selectable: true,
            onTapLink: (_, href, _) => _open(href),
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: context.text.bodyMedium?.copyWith(height: 1.5),
              blockquoteDecoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.s),
                border: Border(left: BorderSide(color: AppColors.line, width: 3)),
              ),
              codeblockDecoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
            ),
          ),
          if (_fullLength != null) ...[
            const SizedBox(height: Space.l),
            Text(
              'Showing the first part of a long page (${(_fullLength! / 1000).round()}k characters).',
              style: context.text.bodySmall,
            ),
          ],
          if (url != null) ...[
            const SizedBox(height: Space.l),
            FilledButton.tonalIcon(
              onPressed: () => _open(url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in Notion'),
            ),
          ],
        ],
      ],
    );
  }
}

// ---- todoist -----------------------------------------------------------------

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});
  final List<Map<String, dynamic>> tasks;

  // Todoist: 4 is the most urgent (p1).
  static Color _priority(Object? p) => switch (p) {
    4 => const Color(0xFFFF6B6B),
    3 => const Color(0xFFFFA94D),
    2 => const Color(0xFF74A9FF),
    _ => AppColors.text3,
  };

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: 'todoist', title: 'Todoist · ${tasks.length} task${tasks.length == 1 ? '' : 's'}'),
      _Rows(
        shown: 8,
        rows: [
          for (final t in tasks)
            ListTile(
              dense: true,
              onTap: () => _open(t['url'] as String?),
              leading: lead(Icon(
                t['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: t['done'] == true ? AppColors.success : _priority(t['priority']),
                size: 22,
              )),
              title: Text(
                '${t['content']}',
                style: TextStyle(decoration: t['done'] == true ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w500),
              ),
              subtitle: t['due'] == null && (t['labels'] as List? ?? const []).isEmpty
                  ? null
                  : Text(
                      [if (t['due'] != null) '📅 ${t['due']}', for (final l in (t['labels'] as List? ?? const [])) '@$l'].join('  '),
                      style: TextStyle(color: _overdue(t['due_date']) ? AppColors.danger : AppColors.text2),
                    ),
            ),
        ],
      ),
    ],
  );

  static bool _overdue(Object? date) {
    final d = _date(date);
    if (d == null) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }
}

// ---- drive ---------------------------------------------------------------------

class _FileList extends StatelessWidget {
  const _FileList({required this.files});
  final List<Map<String, dynamic>> files;

  static (IconData, Color) _kind(String mime) => switch (mime) {
    _ when mime.contains('folder') => (Icons.folder_rounded, const Color(0xFF8E9BAE)),
    _ when mime.contains('document') || mime.contains('word') => (Icons.description_rounded, const Color(0xFF4285F4)),
    _ when mime.contains('spreadsheet') || mime.contains('excel') || mime.contains('csv') => (Icons.table_chart_rounded, const Color(0xFF0F9D58)),
    _ when mime.contains('presentation') || mime.contains('powerpoint') => (Icons.slideshow_rounded, const Color(0xFFF4B400)),
    _ when mime.contains('pdf') => (Icons.picture_as_pdf_rounded, const Color(0xFFEA4335)),
    _ when mime.startsWith('image/') => (Icons.image_rounded, const Color(0xFFAB47BC)),
    _ when mime.startsWith('video/') => (Icons.movie_rounded, const Color(0xFFEA4335)),
    _ when mime.startsWith('audio/') => (Icons.audiotrack_rounded, const Color(0xFFFF7043)),
    _ => (Icons.insert_drive_file_rounded, AppColors.text2),
  };

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      _Header(app: 'googledrive', title: 'Drive · ${files.length} file${files.length == 1 ? '' : 's'}'),
      _Rows(
        shown: 6,
        rows: [
          for (final f in files)
            Builder(
              builder: (context) {
                final (icon, color) = _kind('${f['mime']}');
                return ListTile(
                  dense: true,
                  onTap: () => _open(f['link'] as String?),
                  leading: lead(Icon(icon, color: color)),
                  title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [
                      if (f['modified'] != null) 'modified ${_when(f['modified'], time: false)}',
                      if (f['owner'] != null) _name('${f['owner']}'),
                      if (f['shared'] == true) 'shared',
                    ].join(' · '),
                  ),
                  trailing: f['link'] == null ? null : Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.text3),
                );
              },
            ),
        ],
      ),
    ],
  );
}

// ---- documents and sheets ----------------------------------------------------------

class _DocCard extends StatelessWidget {
  const _DocCard({required this.app, required this.doc});
  final String app;
  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final raw = '${doc['text'] ?? ''}';
    final text = app == 'notion' ? _NotionPageReaderState._clean(raw) : raw;
    final title = '${doc['title'] ?? ''}'.trim();
    void open() => _sheet(
      context,
      (scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          if (title.isNotEmpty) ...[Text(title, style: context.text.titleLarge), const SizedBox(height: Space.l)],
          MarkdownBody(data: text, selectable: true, onTapLink: (_, href, _) => _open(href)),
          if (doc['url'] is String) ...[
            const SizedBox(height: Space.l),
            FilledButton.tonalIcon(
              onPressed: () => _open(doc['url'] as String),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text('Open in ${appLabel(app)}'),
            ),
          ],
        ],
      ),
    );
    return _Panel(
      children: [
        _Header(app: app, title: title.isEmpty ? appLabel(app) : '${appLabel(app)} · $title'),
        InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.4, fontSize: 13.5)),
                const SizedBox(height: Space.s),
                Text('Read all · ${(text.split(RegExp(r'\s+')).length / 230).ceil()} min', style: context.text.labelSmall?.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});
  final Map<String, dynamic> table;

  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in (table['rows'] as List? ?? const [])) if (r is List) [for (final c in r) '$c']];
    if (rows.isEmpty) return const SizedBox.shrink();
    final width = rows.fold<int>(0, (n, r) => r.length > n ? r.length : n);
    return _Panel(
      children: [
        _Header(app: 'googlesheets', title: 'Sheets · ${table['range'] ?? '${rows.length} rows'}'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 44,
            columnSpacing: Space.l,
            columns: [for (var i = 0; i < width; i++) DataColumn(label: Text(i < rows.first.length ? rows.first[i] : '', style: const TextStyle(fontWeight: FontWeight.w600)))],
            rows: [
              for (final r in rows.skip(1).take(40))
                DataRow(cells: [for (var i = 0; i < width; i++) DataCell(Text(i < r.length ? r[i] : '', maxLines: 2, overflow: TextOverflow.ellipsis))]),
            ],
          ),
        ),
        if (rows.length > 41) Padding(padding: const EdgeInsets.all(Space.s), child: Text('${rows.length - 41} more rows', style: context.text.labelSmall)),
      ],
    );
  }
}
