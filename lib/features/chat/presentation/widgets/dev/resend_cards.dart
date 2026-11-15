import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../../../telegram/data/telegram_tools.dart';
import '../../../domain/chat_models.dart';
import 'dev_card_kit.dart';

// Resend cards: a sent email that follows its delivery live (sent →
// delivered → opened → clicked, or bounced) and opens into a sheet with
// every detail, the message itself, and toggles for live updates and the
// domain's open and click tracking; sent mail, domains with their DNS
// records and Verify, audiences, contacts, broadcasts, API keys, webhooks.

List<Map<String, dynamic>> _l(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Widget? resendResultFor(ToolPart part, Map<String, dynamic> j) {
  if (j['dev'] != 'resend') return null;
  return switch (part.name) {
    'resend_send_email' ||
    'resend_email' when j['email'] is Map => LiveEmailCard(initial: _m(j['email']), sent: part.name == 'resend_send_email', html: part.args['html'] as String?),
    'resend_cancel_email' || 'resend_reschedule_email' => _NoteCard(
      icon: part.name == 'resend_cancel_email' ? Icons.cancel_schedule_send_outlined : Icons.schedule_send_outlined,
      text: part.name == 'resend_cancel_email' ? 'Scheduled email cancelled' : 'Rescheduled for ${j['scheduled_at']}',
      sub: '${j['id']}',
      onTap: (c) => showResendEmail(c, '${j['id']}'),
    ),
    'resend_emails' => _EmailList(emails: _l(j['emails'])),
    'resend_send_batch' => _NoteCard(
      icon: Icons.all_inbox_rounded,
      text: '${j['count']} emails sent',
      sub: (j['ids'] as List? ?? const []).take(3).join(', '),
      onTap: (c) => showJsonSheet(c, brand: DevBrand.resend, title: 'Batch', subtitle: '${j['count']} emails', value: j),
    ),
    'resend_domains' => _DomainList(domains: _l(j['domains'])),
    'resend_domain' || 'resend_add_domain' || 'resend_verify_domain' when j['domain'] is Map => _DomainCard(domain: _m(j['domain']), records: _l(j['records'])),
    'resend_api_keys' => _Rows(
      title: 'API keys · ${_l(j['api_keys']).length}',
      value: j,
      rows: [
        for (final k in _l(j['api_keys']))
          (
            Icons.key_rounded,
            '${k['name']}',
            'created ${ago(k['created'])}${k['last_used'] == null ? ' · never used' : ' · used ${ago(k['last_used'])}'}',
            null,
          ),
      ],
    ),
    'resend_create_api_key' when j['token'] != null => _SecretCard(title: 'New API key', secret: '${j['token']}'),
    'resend_create_webhook' when j['signing_secret'] != null => _SecretCard(title: 'Webhook signing secret', secret: '${j['signing_secret']}'),
    'resend_audiences' => _Rows(
      title: 'Audiences · ${_l(j['audiences']).length}',
      value: j,
      rows: [for (final a in _l(j['audiences'])) (Icons.groups_2_outlined, '${a['name']}', 'created ${ago(a['created'])}', a['id'] as String?)],
      onTap: (context, id) => showResendContacts(context, id),
    ),
    'resend_contacts' => _ContactList(audience: '${j['audience']}', contacts: _l(j['contacts'])),
    'resend_broadcasts' when j['broadcast'] is Map => _BroadcastCard(b: _m(j['broadcast'])),
    'resend_broadcasts' => _BroadcastList(broadcasts: _l(j['broadcasts'])),
    'resend_webhooks' => _Rows(
      title: 'Webhooks · ${_l(j['webhooks']).length}',
      value: j,
      rows: [
        for (final w in _l(j['webhooks']))
          (Icons.webhook_rounded, '${w['endpoint']}', '${w['status'] ?? ''} · ${(w['events'] as List?)?.join(', ') ?? ''}', null),
      ],
    ),
    _ => null,
  };
}

Color eventColor(Object? e) => switch ('$e') {
  'delivered' || 'opened' || 'clicked' => AppColors.success,
  'bounced' || 'complained' || 'failed' => AppColors.danger,
  'canceled' => AppColors.text3,
  'delivery_delayed' => AppColors.warning,
  'scheduled' => adapt(const Color(0xFF60A5FA), const Color(0xFF2563EB)),
  _ => AppColors.accent,
};

IconData _eventIcon(Object? e) => switch ('$e') {
  'delivered' => Icons.mark_email_read_outlined,
  'opened' => Icons.drafts_outlined,
  'clicked' => Icons.ads_click_rounded,
  'bounced' || 'failed' => Icons.error_outline_rounded,
  'complained' => Icons.report_outlined,
  'canceled' => Icons.cancel_schedule_send_outlined,
  'scheduled' => Icons.schedule_send_outlined,
  'delivery_delayed' => Icons.hourglass_bottom_rounded,
  _ => Icons.outgoing_mail,
};

String _eventLabel(Object? e) => switch ('$e') {
  'delivery_delayed' => 'Delayed',
  '' || 'null' || 'queued' => 'Sent',
  final s => '${s[0].toUpperCase()}${s.substring(1)}',
};

/// Events after which nothing more will happen to an email.
bool _final(Object? e) => const {'clicked', 'bounced', 'complained', 'canceled', 'failed'}.contains('$e');

String _plain(String html) => (html_parser.parse(html).body?.text ?? html).replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();

String _addr(Object? v) => v is List ? v.join(', ') : '${v ?? ''}';

/// When this phone first saw each email reach each step, for the timeline.
final _seen = <String, Map<String, DateTime>>{};

void _note(Map<String, dynamic> e) {
  final id = '${e['id']}';
  final ev = '${e['last_event'] ?? 'sent'}';
  final m = _seen.putIfAbsent(id, () => {});
  if (e['created'] != null) m.putIfAbsent('sent', () => parseWhen(e['created']) ?? DateTime.now());
  m.putIfAbsent(ev == 'queued' ? 'sent' : ev, DateTime.now);
}

/// Follows an email's delivery: often at first, then less often, for up to
/// two days, until it reaches a final event or is turned off.
mixin _Follow<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Map<String, dynamic> get startEmail;
  late Map<String, dynamic> email = {...startEmail};
  Timer? _timer;
  bool following = true;
  bool checking = false;
  DateTime? checkedAt;
  final _since = DateTime.now();

  @override
  void initState() {
    super.initState();
    _note(email);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!following || _final(email['last_event']) || email['last_event'] == 'scheduled') return;
    final created = parseWhen(email['created']);
    if (created != null && DateTime.now().difference(created) > const Duration(days: 2)) return;
    final age = DateTime.now().difference(_since);
    final wait = age < const Duration(minutes: 1)
        ? const Duration(seconds: 5)
        : age < const Duration(minutes: 10)
        ? const Duration(seconds: 15)
        : const Duration(minutes: 1);
    _timer = Timer(wait, check);
  }

  Future<void> check() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      final r = await ref.read(toolRunnerProvider).run('resend_email', {'id': email['id']});
      if (mounted && r.json['email'] is Map) {
        setState(() {
          email = {...email, ..._m(r.json['email'])};
          checkedAt = DateTime.now();
        });
        _note(email);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => checking = false);
      _schedule();
    }
  }

  void setFollowing(bool on) {
    setState(() => following = on);
    if (on) {
      check();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ---- one email -------------------------------------------------------------------------

/// An email that keeps checking its delivery, opens and clicks; a tap opens
/// its sheet.
class LiveEmailCard extends ConsumerStatefulWidget {
  const LiveEmailCard({super.key, required this.initial, this.sent = false, this.html});
  final Map<String, dynamic> initial;
  final bool sent;

  /// The HTML that was sent, shown in the sheet before Resend returns it.
  final String? html;

  @override
  ConsumerState<LiveEmailCard> createState() => _LiveEmailCardState();
}

class _LiveEmailCardState extends ConsumerState<LiveEmailCard> with _Follow {
  @override
  Map<String, dynamic> get startEmail => widget.initial;

  @override
  Widget build(BuildContext context) {
    final e = email;
    final event = '${e['last_event'] ?? 'sent'}';
    final failed = const {'bounced', 'complained', 'failed', 'canceled'}.contains(event);
    final body = '${e['text'] ?? (e['html'] != null ? _plain('${e['html']}') : '')}'.trim();
    final id = '${e['id']}';
    void open() => showResendEmail(context, id, initial: e, html: widget.html);
    return DevPanel(
      glow: eventColor(event),
      danger: failed && event != 'canceled',
      onTap: open,
      children: [
        DevHead(
          brand: DevBrand.resend,
          title: widget.sent ? (event == 'scheduled' ? 'Email scheduled' : 'Email sent') : 'Email',
          subtitle: [if (e['created'] != null) ago(e['created']), if (checkedAt != null) 'checked ${ago(checkedAt!.toIso8601String())}'].join(' · '),
          trailing: Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: Pill(_eventLabel(event), color: eventColor(event), icon: _eventIcon(event), pulse: following && !_final(event) && event != 'scheduled'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e['subject'] ?? '(no subject)'}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _Line(label: 'To', value: _addr(e['to'])),
              if (e['cc'] != null) _Line(label: 'Cc', value: _addr(e['cc'])),
              if (e['from'] != null) _Line(label: 'From', value: _addr(e['from'])),
              if (e['scheduled_at'] != null && event == 'scheduled') _Line(label: 'At', value: '${e['scheduled_at']}'),
              if (e['attachments'] is List) _Line(label: 'Files', value: (e['attachments'] as List).join(', ')),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: id));
                  showSnack(context, 'Email ID copied');
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text('ID', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                      ),
                      Expanded(
                        child: Text(
                          id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: codeTextStyle.copyWith(fontSize: 11.5, color: AppColors.text2),
                        ),
                      ),
                      Icon(Icons.copy_rounded, size: 13, color: AppColors.text3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!failed && event != 'scheduled') pad(_Timeline(id: id, event: event)),
        if (body.isNotEmpty)
          pad(
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
              child: Text(body, maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(height: 1.4)),
            ),
          ),
        pad(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    OutlinedButton.icon(onPressed: open, icon: const Icon(Icons.drafts_outlined, size: 18), label: const Text('Details')),
                    if (event == 'scheduled')
                      ActionButton(
                        label: 'Cancel send',
                        icon: Icons.cancel_schedule_send_outlined,
                        danger: true,
                        done: 'Cancelled',
                        onRun: () async {
                          await devRun(
                            context,
                            ref,
                            'resend_cancel_email',
                            {'id': e['id']},
                            confirmTitle: 'Cancel this email?',
                            confirmMessage: 'It won\'t be sent.',
                            confirmLabel: 'Cancel email',
                          );
                          if (mounted) setState(() => email = {...email, 'last_event': 'canceled'});
                        },
                      ),
                  ],
                ),
              ),
              checking
                  ? const Padding(
                      padding: EdgeInsets.all(Space.s),
                      child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(tooltip: 'Check now', icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: check),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sent → Delivered → Opened → Clicked, with when each was seen.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.id, required this.event});
  final String id;
  final String event;

  @override
  Widget build(BuildContext context) {
    const steps = ['sent', 'delivered', 'opened', 'clicked'];
    final reached = steps.indexOf(event == 'queued' ? 'sent' : event);
    final seen = _seen[id] ?? const {};
    return Row(
      children: [
        for (final (i, s) in steps.indexed) ...[
          if (i > 0)
            Expanded(
              child: Container(height: 2, margin: const EdgeInsets.only(bottom: 26), color: i <= reached ? AppColors.success : AppColors.line),
            ),
          Column(
            children: [
              Icon(
                i <= reached ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: i <= reached ? AppColors.success : AppColors.text3,
              ),
              Text(_eventLabel(s), style: context.text.labelSmall?.copyWith(color: i <= reached ? AppColors.success : AppColors.text3)),
              Text(
                seen[s] == null || i > reached ? ' ' : DateFormat.Hm().format(seen[s]!),
                style: context.text.labelSmall?.copyWith(fontSize: 10, color: AppColors.text3),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
        ),
        Expanded(
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
        ),
      ],
    ),
  );
}

/// The email in a sheet: its status and timeline, toggles for live
/// updates and the sending domain's open and click tracking, the message as
/// HTML or text, every address and ID, and Cancel, Reschedule or Send again.
Future<void> showResendEmail(BuildContext context, String id, {Map<String, dynamic>? initial, String? html}) => showDevSheet(
  context,
  brand: DevBrand.resend,
  title: 'Email',
  subtitle: id,
  builder: (context, scroll) => _EmailSheet(id: id, initial: initial, html: html, scroll: scroll),
);

class _EmailSheet extends ConsumerStatefulWidget {
  const _EmailSheet({required this.id, required this.scroll, this.initial, this.html});
  final String id;
  final Map<String, dynamic>? initial;
  final String? html;
  final ScrollController scroll;
  @override
  ConsumerState<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends ConsumerState<_EmailSheet> with _Follow {
  @override
  Map<String, dynamic> get startEmail => {'id': widget.id, ...?widget.initial};

  bool _asHtml = true;
  Map<String, dynamic>? _domain;
  String? _domainError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await check();
      await _loadDomain();
    });
  }

  String get _fromDomain {
    final from = _addr(email['from']);
    final m = RegExp(r'@([^>\s]+)').firstMatch(from);
    return m?[1]?.toLowerCase() ?? '';
  }

  Future<void> _loadDomain() async {
    final name = _fromDomain;
    if (name.isEmpty || name == 'resend.dev') return;
    try {
      final r = await ref.read(toolRunnerProvider).run('resend_domain', {'domain': name});
      if (!mounted) return;
      setState(() {
        if (r.json['domain'] is Map) _domain = _m(r.json['domain']);
        _domainError = r.json['error'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _domainError = '$e');
    }
  }

  Future<void> _setTracking(String key, bool on) async {
    final d = _domain;
    if (d == null) return;
    try {
      await devRun(
        context,
        ref,
        'resend_update_domain',
        {'domain': d['id'], key: on},
        confirmTitle: '${on ? 'Turn on' : 'Turn off'} ${key == 'open_tracking' ? 'open' : 'click'} tracking?',
        confirmMessage: 'Applies to new emails from ${d['name']}.',
        confirmLabel: on ? 'Turn on' : 'Turn off',
      );
      if (mounted) setState(() => _domain = {...d, key: on});
    } catch (e) {
      if (mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _reschedule() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 30)), initialDate: now);
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null || !mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    try {
      await devRun(
        context,
        ref,
        'resend_reschedule_email',
        {'id': email['id'], 'scheduled_at': at.toUtc().toIso8601String()},
        confirmTitle: 'Send it at ${DateFormat('d MMM, HH:mm').format(at)}?',
        confirmLabel: 'Reschedule',
      );
      if (mounted) setState(() => email = {...email, 'scheduled_at': at.toIso8601String(), 'last_event': 'scheduled'});
    } catch (e) {
      if (mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = email;
    final event = '${e['last_event'] ?? 'sent'}';
    final html = e['html'] as String? ?? widget.html;
    final text = e['text'] as String?;
    final tracking = _domain;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: eventColor(event).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.l)),
            child: Row(
              children: [
                Icon(_eventIcon(event), color: eventColor(event), size: 30),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _eventLabel(event),
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: eventColor(event)),
                      ),
                      Text('${e['subject'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    ],
                  ),
                ),
                checking
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(tooltip: 'Check now', icon: const Icon(Icons.refresh_rounded), onPressed: check),
              ],
            ),
          ),
        ),
        if (!const {'bounced', 'complained', 'failed', 'canceled', 'scheduled'}.contains(event))
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: _Timeline(id: '${e['id']}', event: event),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (event == 'scheduled') ...[
                OutlinedButton.icon(onPressed: _reschedule, icon: const Icon(Icons.edit_calendar_outlined, size: 18), label: const Text('Reschedule')),
                ActionButton(
                  label: 'Cancel',
                  icon: Icons.cancel_schedule_send_outlined,
                  danger: true,
                  done: 'Cancelled',
                  onRun: () async {
                    await devRun(context, ref, 'resend_cancel_email', {'id': e['id']}, confirmTitle: 'Cancel this email?', confirmLabel: 'Cancel email');
                    if (mounted) setState(() => email = {...email, 'last_event': 'canceled'});
                  },
                ),
              ],
              if (e['to'] != null && e['subject'] != null && (text != null || html != null))
                ActionButton(
                  label: 'Send again',
                  icon: Icons.forward_to_inbox_rounded,
                  done: 'Sent again',
                  onRun: () => devRun(
                    context,
                    ref,
                    'resend_send_email',
                    {
                      'to': e['to'] is List ? e['to'] : ['${e['to']}'],
                      'subject': e['subject'],
                      'from': ?(e['from'] is String ? e['from'] : null),
                      'text': ?text,
                      'html': ?html,
                    },
                    confirmTitle: 'Send this email again?',
                    confirmMessage: 'To ${_addr(e['to'])}',
                    confirmLabel: 'Send',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${e['id']}'));
                  showSnack(context, 'Email ID copied');
                },
                icon: const Icon(Icons.tag_rounded, size: 18),
                label: const Text('Copy ID'),
              ),
            ],
          ),
        ),
        const SheetLabel('Tracking'),
        SheetGroup(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.sync_rounded),
              title: const Text('Live updates'),
              subtitle: Text(
                _final(event)
                    ? 'Nothing more will happen to this email.'
                    : (following ? 'Checking for delivery, opens and clicks' : 'Paused: tap refresh to check'),
                style: context.text.bodySmall,
              ),
              value: following && !_final(event),
              onChanged: _final(event) ? null : setFollowing,
            ),
            if (tracking != null) ...[
              SwitchListTile(
                secondary: const Icon(Icons.drafts_outlined),
                title: const Text('Open tracking'),
                subtitle: Text('Opens on ${tracking['name']} are only reported when this is on.', style: context.text.bodySmall),
                value: tracking['open_tracking'] == true,
                onChanged: (v) => _setTracking('open_tracking', v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.ads_click_rounded),
                title: const Text('Click tracking'),
                subtitle: Text('Link clicks are only reported when this is on.', style: context.text.bodySmall),
                value: tracking['click_tracking'] == true,
                onChanged: (v) => _setTracking('click_tracking', v),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Text(
                  _domainError ??
                      (_fromDomain == 'resend.dev'
                          ? 'Emails from resend.dev can\'t track opens or clicks.'
                          : 'Opens and clicks show only when the sending domain tracks them.'),
                  style: context.text.bodySmall,
                ),
              ),
          ],
        ),
        SheetLabel(
          'Message',
          trailing: html == null
              ? null
              : SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: true, label: Text('HTML')),
                    ButtonSegment(value: false, label: Text('Text')),
                  ],
                  selected: {_asHtml},
                  onSelectionChanged: (v) => setState(() => _asHtml = v.first),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: html != null && _asHtml
              ? WebPreview(html: html, height: 440, interactive: true)
              : Container(
                  padding: const EdgeInsets.all(Space.m),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                  child: SelectableText(text ?? (html == null ? '(not returned yet)' : _plain(html)), style: context.text.bodyMedium?.copyWith(height: 1.5)),
                ),
        ),
        const SheetLabel('Details'),
        SheetGroup(
          children: [
            CopyRow(label: 'From', value: _addr(e['from']), mono: false),
            CopyRow(label: 'To', value: _addr(e['to']), mono: false),
            if (e['cc'] != null) CopyRow(label: 'Cc', value: _addr(e['cc']), mono: false),
            if (e['bcc'] != null) CopyRow(label: 'Bcc', value: _addr(e['bcc']), mono: false),
            if (e['reply_to'] != null) CopyRow(label: 'Reply to', value: _addr(e['reply_to']), mono: false),
            CopyRow(label: 'Subject', value: '${e['subject'] ?? ''}', mono: false),
            if (e['created'] != null) CopyRow(label: 'Sent', value: '${e['created']}', mono: false),
            if (e['scheduled_at'] != null) CopyRow(label: 'Scheduled', value: '${e['scheduled_at']}', mono: false),
            if (e['attachments'] is List) CopyRow(label: 'Files', value: (e['attachments'] as List).join(', '), mono: false),
            CopyRow(label: 'ID', value: '${e['id']}'),
            if (checkedAt != null) CopyRow(label: 'Checked', value: DateFormat('d MMM, HH:mm:ss').format(checkedAt!), mono: false),
          ],
        ),
      ],
    );
  }
}

// ---- lists -----------------------------------------------------------------------------

class _EmailList extends StatelessWidget {
  const _EmailList({required this.emails, this.embedded = false});
  final List<Map<String, dynamic>> emails;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final e in emails) {
      counts['${e['last_event']}'] = (counts['${e['last_event']}'] ?? 0) + 1;
    }
    final shown = embedded ? emails : emails.take(12).toList();
    return DevPanel(
      onTap: embedded
          ? null
          : () => showDevSheet(
              context,
              brand: DevBrand.resend,
              title: 'Sent email',
              subtitle: '${emails.length} emails',
              builder: (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(Space.l),
                children: [_EmailList(emails: emails, embedded: true)],
              ),
            ),
      children: [
        DevHead(brand: DevBrand.resend, title: 'Sent email · ${emails.length}'),
        if (counts.isNotEmpty)
          pad(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in counts.entries) Pill('${_eventLabel(c.key)} ${c.value}', color: eventColor(c.key), icon: _eventIcon(c.key))],
            ),
            top: Space.xs,
          ),
        for (final (i, e) in shown.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 52, endIndent: Space.m),
          InkWell(
            onTap: () => showResendEmail(context, '${e['id']}', initial: e),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: Space.m),
                    decoration: BoxDecoration(color: eventColor(e['last_event']).withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: Icon(_eventIcon(e['last_event']), size: 16, color: eventColor(e['last_event'])),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e['subject'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        Text(
                          '${_addr(e['to'])} · ${ago(e['created'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _eventLabel(e['last_event']),
                    style: context.text.labelSmall?.copyWith(color: eventColor(e['last_event']), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (emails.length > shown.length) MoreRow(label: 'All ${emails.length}', onTap: null),
        if (emails.isEmpty) pad(Text('Nothing sent yet.', style: context.text.bodySmall), top: Space.s),
      ],
    );
  }
}

Color _domainColor(Object? s) => switch ('$s') {
  'verified' => AppColors.success,
  'failed' || 'temporary_failure' => AppColors.danger,
  _ => AppColors.warning,
};

class _DomainList extends StatelessWidget {
  const _DomainList({required this.domains});
  final List<Map<String, dynamic>> domains;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: domains.length == 1
        ? () => showResendDomain(context, '${domains.first['id']}')
        : () => showJsonSheet(context, brand: DevBrand.resend, title: 'Sending domains', value: domains),
    children: [
      DevHead(brand: DevBrand.resend, title: 'Sending domains · ${domains.length}'),
      for (final d in domains)
        ListTile(
          dense: true,
          onTap: () => showResendDomain(context, '${d['id']}'),
          leading: lead(Icon(d['status'] == 'verified' ? Icons.verified_rounded : Icons.pending_outlined, color: _domainColor(d['status']))),
          title: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${d['region'] ?? ''} · added ${ago(d['created'])}'),
          trailing: Pill('${d['status']}'.replaceAll('_', ' '), color: _domainColor(d['status'])),
        ),
      if (domains.isEmpty) pad(Text('No domains yet. Add one to send from your own address.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

class _DomainCard extends ConsumerWidget {
  const _DomainCard({required this.domain, required this.records});
  final Map<String, dynamic> domain;
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verified = records.where((r) => r['status'] == 'verified').length;
    void open() => showResendDomain(context, '${domain['id']}');
    return DevPanel(
      glow: _domainColor(domain['status']),
      onTap: open,
      children: [
        DevHead(
          brand: DevBrand.resend,
          title: '${domain['name']}',
          subtitle: '$verified of ${records.length} records verified · ${domain['region'] ?? ''}',
          trailing: Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: Pill('${domain['status']}'.replaceAll('_', ' '), color: _domainColor(domain['status'])),
          ),
        ),
        pad(
          ShareBar(value: records.isEmpty ? 0 : verified / records.length, color: _domainColor(domain['status'])),
          top: Space.xs,
        ),
        for (final r in records.take(4)) _RecordTile(r: r),
        pad(
          Wrap(
            spacing: Space.s,
            children: [
              OutlinedButton.icon(
                onPressed: open,
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: Text(records.length > 4 ? 'All ${records.length} records' : 'Open'),
              ),
              if (domain['status'] != 'verified')
                ActionButton(
                  label: 'Verify now',
                  icon: Icons.refresh_rounded,
                  done: 'Checking DNS…',
                  onRun: () => devRun(
                    context,
                    ref,
                    'resend_verify_domain',
                    {'domain': domain['id']},
                    confirmTitle: 'Check ${domain['name']} again?',
                    confirmLabel: 'Verify',
                  ),
                ),
            ],
          ),
          top: Space.s,
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.xs),
    child: Container(
      padding: const EdgeInsets.all(Space.s + 2),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['record']} · ${r['type']}${r['priority'] == null ? '' : ' · priority ${r['priority']}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: Space.s),
              Pill('${r['status']}'.replaceAll('_', ' '), color: _domainColor(r['status'])),
            ],
          ),
          const SizedBox(height: 4),
          _CopyField(label: 'Name', value: '${r['name']}'),
          _CopyField(label: 'Value', value: '${r['value']}'),
        ],
      ),
    ),
  );
}

class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      Clipboard.setData(ClipboardData(text: value));
      showSnack(context, '$label copied');
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
          Expanded(
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 11.5)),
          ),
          Icon(Icons.copy_rounded, size: 13, color: AppColors.text3),
        ],
      ),
    ),
  );
}

/// A domain in a sheet: Verify and refresh, open and click tracking
/// switches, and every DNS record to copy.
Future<void> showResendDomain(BuildContext context, String id) => showDevSheet(
  context,
  brand: DevBrand.resend,
  title: 'Domain',
  subtitle: id,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'resend_domain', {'domain': id}),
      builder: (context, j, reload) {
        final d = _m(j['domain']);
        final records = _l(j['records']);
        Future<void> toggle(String key, bool on) async {
          try {
            await devRun(
              context,
              ref,
              'resend_update_domain',
              {'domain': d['id'], key: on},
              confirmTitle: '${on ? 'Turn on' : 'Turn off'} ${key.replaceAll('_', ' ')}?',
              confirmLabel: on ? 'Turn on' : 'Turn off',
            );
            reload();
          } catch (e) {
            if (context.mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
          }
        }

        return ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: Space.x4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${d['name']}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Pill('${d['status']}'.replaceAll('_', ' '), color: _domainColor(d['status'])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ActionButton(
                      label: 'Verify now',
                      icon: Icons.verified_outlined,
                      filled: true,
                      onRun: () async {
                        await devRun(context, ref, 'resend_verify_domain', {'domain': id}, confirmTitle: 'Check ${d['name']} again?', confirmLabel: 'Verify');
                        reload();
                      },
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
                  ),
                ],
              ),
            ),
            const SheetLabel('Tracking'),
            SheetGroup(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.drafts_outlined),
                  title: const Text('Open tracking'),
                  value: d['open_tracking'] == true,
                  onChanged: (v) => toggle('open_tracking', v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.ads_click_rounded),
                  title: const Text('Click tracking'),
                  value: d['click_tracking'] == true,
                  onChanged: (v) => toggle('click_tracking', v),
                ),
                if (d['region'] != null) CopyRow(label: 'Region', value: '${d['region']}', mono: false),
                if (d['tls'] != null) CopyRow(label: 'TLS', value: '${d['tls']}', mono: false),
              ],
            ),
            const SheetLabel('DNS records'),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Text('Add these at your DNS provider, then verify. Tap a value to copy it.', style: context.text.bodySmall),
            ),
            for (final r in records)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: _RecordTile(r: r),
              ),
          ],
        );
      },
    ),
  ),
);

class _ContactList extends ConsumerWidget {
  const _ContactList({required this.audience, required this.contacts, this.embedded = false});
  final String audience;
  final List<Map<String, dynamic>> contacts;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = contacts.where((c) => c['unsubscribed'] != true).length;
    return DevPanel(
      onTap: embedded ? null : () => showResendContacts(context, audience),
      children: [
        DevHead(brand: DevBrand.resend, title: 'Contacts · ${contacts.length}', subtitle: '$subscribed subscribed · $audience'),
        pad(
          ShareBar(value: contacts.isEmpty ? 0 : subscribed / contacts.length, color: AppColors.success),
          top: Space.xs,
        ),
        for (final c in (embedded ? contacts : contacts.take(15)))
          ListTile(
            dense: true,
            leading: lead(
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.surface2,
                child: Text(
                  '${c['first_name'] ?? c['email'] ?? '?'}'.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            title: Text(
              [c['first_name'], c['last_name']].whereType<Object>().join(' ').isEmpty
                  ? '${c['email']}'
                  : [c['first_name'], c['last_name']].whereType<Object>().join(' '),
            ),
            subtitle: Text('${c['email']}'),
            trailing: Switch(
              value: c['unsubscribed'] != true,
              onChanged: (v) async {
                try {
                  await devRun(
                    context,
                    ref,
                    'resend_update_contact',
                    {'audience': audience, 'contact': c['id'], 'unsubscribed': !v},
                    confirmTitle: v ? 'Resubscribe ${c['email']}?' : 'Unsubscribe ${c['email']}?',
                    confirmLabel: v ? 'Resubscribe' : 'Unsubscribe',
                  );
                  if (context.mounted) showSnack(context, v ? 'Resubscribed' : 'Unsubscribed');
                } catch (e) {
                  if (context.mounted && !cancelled(e)) showSnack(context, '$e', icon: Icons.error_outline_rounded);
                }
              },
            ),
          ),
        if (!embedded && contacts.length > 15) MoreRow(label: 'All ${contacts.length}', onTap: null),
      ],
    );
  }
}

/// An audience's contacts in a sheet, each with a subscribed switch.
Future<void> showResendContacts(BuildContext context, String audience) => showDevSheet(
  context,
  brand: DevBrand.resend,
  title: 'Contacts',
  subtitle: audience,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'resend_contacts', {'audience': audience}),
      builder: (context, j, _) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Space.l),
        children: [_ContactList(audience: audience, contacts: _l(j['contacts']), embedded: true)],
      ),
    ),
  ),
);

Color _broadcastColor(Object? s) => switch ('$s') {
  'sent' => AppColors.success,
  'queued' || 'scheduled' => AppColors.warning,
  _ => AppColors.text2,
};

void _openBroadcast(BuildContext context, String id, String title) => showDevSheet(
  context,
  brand: DevBrand.resend,
  title: title,
  subtitle: id,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) => Loaded<Map<String, dynamic>>(
      load: () => devRun(context, ref, 'resend_broadcasts', {'id': id}),
      builder: (context, j, _) {
        final b = _m(j['broadcast']);
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.all(Space.l),
          children: [
            _BroadcastCard(b: b, embedded: true),
            if (b['html'] != null) ...[const SizedBox(height: Space.m), WebPreview(html: '${b['html']}', height: 420, interactive: true)],
          ],
        );
      },
    ),
  ),
);

class _BroadcastList extends StatelessWidget {
  const _BroadcastList({required this.broadcasts});
  final List<Map<String, dynamic>> broadcasts;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => showJsonSheet(context, brand: DevBrand.resend, title: 'Broadcasts', value: broadcasts),
    children: [
      DevHead(brand: DevBrand.resend, title: 'Broadcasts · ${broadcasts.length}'),
      for (final b in broadcasts.take(30))
        ListTile(
          dense: true,
          onTap: () => _openBroadcast(context, '${b['id']}', '${b['name'] ?? b['subject'] ?? 'Broadcast'}'),
          leading: lead(Icon(Icons.campaign_outlined, color: _broadcastColor(b['status']))),
          title: Text('${b['subject'] ?? b['name'] ?? b['id']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (b['sent_at'] != null) 'sent ${ago(b['sent_at'])}' else 'created ${ago(b['created'])}',
              if (b['scheduled_at'] != null) 'for ${b['scheduled_at']}',
            ].join(' · '),
          ),
          trailing: Pill('${b['status']}', color: _broadcastColor(b['status'])),
        ),
    ],
  );
}

class _BroadcastCard extends ConsumerWidget {
  const _BroadcastCard({required this.b, this.embedded = false});
  final Map<String, dynamic> b;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = '${b['text'] ?? (b['html'] != null ? _plain('${b['html']}') : '')}'.trim();
    return DevPanel(
      onTap: embedded ? null : () => _openBroadcast(context, '${b['id']}', '${b['name'] ?? 'Broadcast'}'),
      children: [
        DevHead(
          brand: DevBrand.resend,
          title: 'Broadcast · ${b['name'] ?? ''}',
          subtitle: 'audience ${b['audience']}',
          trailing: Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: Pill('${b['status']}', color: _broadcastColor(b['status'])),
          ),
        ),
        pad(
          Text('${b['subject'] ?? ''}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          top: Space.xs,
        ),
        if (b['from'] != null) pad(Text('from ${b['from']}', style: context.text.bodySmall)),
        if (body.isNotEmpty && !embedded)
          pad(
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
              child: Text(body, maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(height: 1.4)),
            ),
          ),
        if (b['status'] == 'draft')
          pad(
            ActionButton(
              label: 'Send to audience',
              icon: Icons.send_rounded,
              filled: true,
              done: 'Broadcast queued',
              onRun: () => devRun(
                context,
                ref,
                'resend_send_broadcast',
                {'id': b['id']},
                confirmTitle: 'Send this broadcast?',
                confirmMessage: 'Every subscribed contact in the audience gets it now.',
                confirmLabel: 'Send',
              ),
            ),
          ),
      ],
    );
  }
}

// ---- small cards -----------------------------------------------------------------------

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.icon, required this.text, this.sub, this.onTap});
  final IconData icon;
  final String text;
  final String? sub;
  final void Function(BuildContext context)? onTap;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: onTap == null ? null : () => onTap!(context),
    children: [
      ListTile(
        leading: const DevMark(DevBrand.resend, size: 28),
        title: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.success),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        subtitle: sub == null || sub!.isEmpty ? null : Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: codeTextStyle.copyWith(fontSize: 11.5)),
        trailing: onTap == null ? null : Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      ),
    ],
  );
}

class _SecretCard extends StatefulWidget {
  const _SecretCard({required this.title, required this.secret});
  final String title;
  final String secret;
  @override
  State<_SecretCard> createState() => _SecretCardState();
}

class _SecretCardState extends State<_SecretCard> {
  bool _shown = false;
  @override
  Widget build(BuildContext context) => DevPanel(
    glow: AppColors.warning,
    onTap: () => setState(() => _shown = !_shown),
    children: [
      DevHead(brand: DevBrand.resend, title: widget.title, subtitle: 'Shown once: copy it now'),
      pad(
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
          child: Row(
            children: [
              Expanded(child: Text(_shown ? widget.secret : '•' * 24, style: codeTextStyle.copyWith(fontSize: 12.5))),
              IconButton(
                icon: Icon(_shown ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                onPressed: () => setState(() => _shown = !_shown),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.secret));
                  showSnack(context, 'Copied');
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Rows extends StatelessWidget {
  const _Rows({required this.title, required this.rows, required this.value, this.onTap});
  final String title;
  final List<(IconData, String, String, String?)> rows;
  final Object value;
  final void Function(BuildContext context, String id)? onTap;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => showJsonSheet(context, brand: DevBrand.resend, title: title, value: value),
    children: [
      DevHead(brand: DevBrand.resend, title: title),
      for (final (icon, t, sub, id) in rows.take(40))
        ListTile(
          dense: true,
          onTap: onTap == null || id == null ? () => showJsonSheet(context, brand: DevBrand.resend, title: t, value: value) : () => onTap!(context, id),
          leading: lead(Icon(icon, size: 20, color: AppColors.text2)),
          title: Text(
            t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ),
      if (rows.isEmpty) pad(Text('Nothing here.', style: context.text.bodySmall), top: Space.s),
    ],
  );
}

// ---- for the Resend manager page -------------------------------------------------------

IconData resendEventIcon(Object? e) => _eventIcon(e);
String resendEventLabel(Object? e) => _eventLabel(e);
Color resendDomainColor(Object? s) => _domainColor(s);
Color resendBroadcastColor(Object? s) => _broadcastColor(s);

/// A broadcast in a sheet, with its preview and Send.
void showResendBroadcast(BuildContext context, String id, String title) => _openBroadcast(context, id, title);
