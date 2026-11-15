import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../ai/data/ai.dart';
import '../../../telegram/data/net_diagnostics.dart';
import '../../../telegram/data/network_tools.dart' show keyProbes;
import '../../data/chat_controller.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';
import 'network_result_cards.dart';

/// An API console in a sheet: the response in full, a request composer to
/// edit and send it again (or anything else), and a step-by-step diagnosis
/// of the address with its DNS and certificate.
Future<void> showApiConsole(BuildContext context, {Map<String, dynamic>? response, int tab = 0}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.94,
    minChildSize: 0.5,
    maxChildSize: 1,
    builder: (context, scroll) => _ApiConsole(response: response, scroll: scroll, tab: tab),
  ),
);

class _Header {
  _Header(String name, String value) : name = TextEditingController(text: name), value = TextEditingController(text: value);
  final TextEditingController name;
  final TextEditingController value;
  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _ApiConsole extends ConsumerStatefulWidget {
  const _ApiConsole({required this.response, required this.scroll, required this.tab});
  final Map<String, dynamic>? response;
  final ScrollController scroll;
  final int tab;

  @override
  ConsumerState<_ApiConsole> createState() => _ApiConsoleState();
}

class _ApiConsoleState extends ConsumerState<_ApiConsole> {
  late String _tab = widget.response != null && widget.tab == 0 ? 'response' : (widget.tab == 2 ? 'diagnose' : 'request');
  late String _method = '${widget.response?['method'] ?? 'GET'}';
  late final _url = TextEditingController(text: '${widget.response?['url'] ?? 'https://'}');
  late final _body = TextEditingController(text: '${widget.response?['request_body'] ?? ''}');
  final _headers = <_Header>[];
  String? _useKey;
  int _timeout = 30;
  bool _sending = false;
  ToolPart? _sent;
  String? _problem;

  Map<String, dynamic>? _diagnosis;
  Map<String, dynamic>? _dns;
  Map<String, dynamic>? _cert;
  bool _diagnosing = false;

  @override
  void initState() {
    super.initState();
    final h = widget.response?['request_headers'];
    if (h is Map) {
      for (final e in h.entries) {
        if ('${e.key}'.toLowerCase() == 'user-agent' || '${e.value}' == '•••' || '${e.key}'.toLowerCase() == 'accept') continue;
        _headers.add(_Header('${e.key}', '${e.value}'));
      }
    }
    _useKey = widget.response?['used_key'] as String?;
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _body.dispose();
    for (final h in _headers) {
      h.dispose();
    }
    super.dispose();
  }

  List<String> get _keysForHost {
    final host = Uri.tryParse(_url.text.trim())?.host ?? '';
    return [for (final e in keyProbes.entries) if (e.value.hosts.contains(host)) e.key];
  }

  Future<void> _send() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasAuthority) {
      setState(() => _problem = 'Enter a full http(s) address.');
      return;
    }
    final read = const {'GET', 'HEAD', 'OPTIONS'}.contains(_method);
    final args = <String, dynamic>{
      'url': uri.toString(),
      'method': _method,
      'timeout_seconds': _timeout,
      if (_useKey != null && _keysForHost.contains(_useKey)) 'use_key': _useKey,
      if (_headers.any((h) => h.name.text.trim().isNotEmpty))
        'headers': {for (final h in _headers) if (h.name.text.trim().isNotEmpty) h.name.text.trim(): h.value.text},
    };
    final body = _body.text.trim();
    if (!read && body.isNotEmpty) {
      try {
        args['json'] = jsonDecode(body);
      } catch (_) {
        args['body'] = body;
      }
    }
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      final part = await ref.read(chatControllerProvider.notifier).runToolManually(read ? 'api_request' : 'api_send', args);
      if (mounted) setState(() => _sent = part);
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _diagnose() async {
    final raw = _url.text.trim();
    setState(() {
      _diagnosing = true;
      _diagnosis = _dns = _cert = null;
    });
    try {
      final host = Uri.tryParse(raw)?.host ?? raw;
      final results = await Future.wait([
        diagnoseUrl(raw).catchError((Object e) => <String, dynamic>{'ok': false, 'problem': '$e', 'steps': const []}),
        dnsLookup(host).catchError((Object e) => <String, dynamic>{'records': const {}, 'note': '$e'}),
      ]);
      if (!mounted) return;
      setState(() {
        _diagnosis = results[0];
        _dns = results[1];
        _cert = _diagnosis?['certificate'] is Map ? Map<String, dynamic>.from(_diagnosis!['certificate'] as Map) : null;
      });
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.response;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            Icon(Icons.api_rounded, color: AppColors.tint),
            const SizedBox(width: Space.s),
            Text('API console', style: context.text.titleLarge),
          ],
        ),
        const SizedBox(height: Space.m),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            if (r != null) const ButtonSegment(value: 'response', label: Text('Response'), icon: Icon(Icons.inbox_outlined, size: 16)),
            const ButtonSegment(value: 'request', label: Text('Request'), icon: Icon(Icons.send_rounded, size: 16)),
            const ButtonSegment(value: 'diagnose', label: Text('Diagnose'), icon: Icon(Icons.monitor_heart_outlined, size: 16)),
          ],
          selected: {_tab},
          onSelectionChanged: (v) {
            setState(() => _tab = v.first);
            if (v.first == 'diagnose' && _diagnosis == null && !_diagnosing) _diagnose();
          },
        ),
        const SizedBox(height: Space.l),
        ...switch (_tab) {
          'response' => _response(context, r!),
          'diagnose' => _diagnoseTab(context),
          _ => _request(context),
        },
      ],
    );
  }

  List<Widget> _response(BuildContext context, Map<String, dynamic> r) => [
    ResponseCard(r: r, inConsole: true),
    const SectionLabel('Response headers', top: Space.l),
    for (final e in (r['headers'] as Map? ?? const {}).entries) KeyValueRow('${e.key}', '${e.value}', mono: true),
    if (r['request_headers'] is Map) ...[
      const SectionLabel('Request headers'),
      for (final e in (r['request_headers'] as Map).entries) KeyValueRow('${e.key}', '${e.value}', mono: true),
    ],
    if (r['request_body'] != null) ...[
      const SectionLabel('Request body'),
      Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
        child: SelectableText('${r['request_body']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    ],
    const SizedBox(height: Space.l),
    OutlinedButton.icon(
      onPressed: () => setState(() => _tab = 'request'),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('Edit and send again'),
    ),
  ];

  List<Widget> _request(BuildContext context) {
    final read = const {'GET', 'HEAD', 'OPTIONS'}.contains(_method);
    final keys = _keysForHost;
    return [
      Row(
        children: [
          DropdownButton<String>(
            value: _method,
            underline: const SizedBox.shrink(),
            items: [
              for (final m in const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'])
                DropdownMenuItem(value: m, child: NetChip(m, methodColor(m), solid: true)),
            ],
            onChanged: (v) => setState(() => _method = v ?? 'GET'),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: TextField(
              controller: _url,
              autocorrect: false,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: 'https://api.example.com/v1/items'),
            ),
          ),
        ],
      ),
      const SectionLabel('Headers', top: Space.l),
      for (final h in _headers)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Row(
            children: [
              Expanded(flex: 2, child: TextField(controller: h.name, autocorrect: false, decoration: const InputDecoration(isDense: true, hintText: 'Name'))),
              const SizedBox(width: Space.s),
              Expanded(flex: 3, child: TextField(controller: h.value, autocorrect: false, decoration: const InputDecoration(isDense: true, hintText: 'Value'))),
              IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _headers.remove(h..dispose()))),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _headers.add(_Header('', ''))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add header'),
        ),
      ),
      if (!read) ...[
        const SectionLabel('Body', top: Space.m),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 14,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(hintText: '{ "name": "value" }  (JSON is sent as JSON; anything else as text)'),
        ),
      ],
      const SectionLabel('Options', top: Space.l),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send a saved key'),
        subtitle: Text(
          keys.isEmpty ? 'No saved key belongs to this host.' : 'Adds the ${_useKey ?? keys.first} key; it never leaves for another host.',
          style: context.text.bodySmall,
        ),
        value: _useKey != null && keys.contains(_useKey),
        onChanged: keys.isEmpty ? null : (v) => setState(() => _useKey = v ? keys.first : null),
      ),
      Row(
        children: [
          Expanded(child: Text('Time limit', style: context.text.bodyMedium)),
          Text('$_timeout s', style: context.text.labelMedium),
        ],
      ),
      Slider(value: _timeout.toDouble(), min: 5, max: 120, divisions: 23, onChanged: (v) => setState(() => _timeout = v.round())),
      if (_problem != null) Text(_problem!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
      const SizedBox(height: Space.s),
      FilledButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
        label: Text(_sending ? 'Sending…' : 'Send $_method'),
      ),
      if (!read)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text('It changes data on the server, so it runs exactly as written.', style: context.text.labelSmall),
        ),
      if (_sent case final p?) ...[
        const SizedBox(height: Space.l),
        if (_cardFor(p) case final card?) card else Text(p.result ?? '', style: context.text.bodySmall),
      ],
    ];
  }

  Widget? _cardFor(ToolPart p) {
    try {
      return networkResultFor(p, Map<String, dynamic>.from(jsonDecode(p.result ?? '{}') as Map));
    } catch (_) {
      return null;
    }
  }

  List<Widget> _diagnoseTab(BuildContext context) => [
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _url,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(isDense: true, hintText: 'https://example.com'),
          ),
        ),
        const SizedBox(width: Space.s),
        FilledButton.tonal(onPressed: _diagnosing ? null : _diagnose, child: Text(_diagnosis == null ? 'Run' : 'Again')),
      ],
    ),
    const SizedBox(height: Space.l),
    if (_diagnosing)
      const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
    else if (_diagnosis != null) ...[
      DiagnosisPanel(d: _diagnosis!),
      if (_cert == null && Uri.tryParse(_url.text)?.scheme == 'https') ...[
        const SizedBox(height: Space.m),
        OutlinedButton.icon(
          onPressed: () async {
            final c = await certificateOf(_url.text);
            if (mounted) setState(() => _cert = c);
          },
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: const Text('Check the certificate'),
        ),
      ],
      if (_dns != null) ...[
        const SectionLabel('DNS records', top: Space.l),
        DnsPanel(d: _dns!),
      ],
    ] else
      Text('Times each step of a request (DNS, connect, TLS, redirects, first byte) to find where it is slow or failing.', style: context.text.bodySmall),
  ];
}

// ---- key check sheet ----------------------------------------------------------------------

/// A key check in full: status, what the service said, timing, and options
/// to test the saved key again, diagnose its endpoint, or read the balance.
Future<void> showKeyCheckSheet(BuildContext context, Map<String, dynamic> k) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 1,
    builder: (context, scroll) => _KeySheet(k: k, scroll: scroll),
  ),
);

class _KeySheet extends ConsumerStatefulWidget {
  const _KeySheet({required this.k, required this.scroll});
  final Map<String, dynamic> k;
  final ScrollController scroll;

  @override
  ConsumerState<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends ConsumerState<_KeySheet> {
  late Map<String, dynamic> _k = widget.k;
  bool _testing = false;
  bool _diagnoseOn = false;
  bool _balanceOn = false;
  Map<String, dynamic>? _diagnosis;
  String? _balance;

  String? get _creditsId => switch ('${_k['service']}') {
    'openrouter' => 'openrouter',
    'vercel' => 'gateway',
    _ => null,
  };

  Future<void> _retest() async {
    setState(() => _testing = true);
    final part = await ref.read(chatControllerProvider.notifier).runToolManually('test_api_key', {'service': _k['service']});
    if (!mounted) return;
    try {
      setState(() => _k = Map<String, dynamic>.from(jsonDecode(part.result ?? '{}') as Map));
    } catch (_) {}
    setState(() => _testing = false);
  }

  Future<void> _setDiagnose(bool on) async {
    setState(() => _diagnoseOn = on);
    if (!on || _diagnosis != null || _k['endpoint'] == null) return;
    final d = await diagnoseUrl('${_k['endpoint']}').catchError((Object e) => <String, dynamic>{'problem': '$e', 'steps': const []});
    if (mounted) setState(() => _diagnosis = d);
  }

  Future<void> _setBalance(bool on) async {
    setState(() => _balanceOn = on);
    if (!on || _balance != null || _creditsId == null) return;
    try {
      final c = await ref.read(aiProvider).credits(_creditsId!);
      if (mounted) {
        setState(() => _balance = c.balance == null ? 'No balance reported' : '\$${c.balance!.toStringAsFixed(2)} left${c.source == 'key' ? ' on this key\'s limit' : ''}');
      }
    } catch (e) {
      if (mounted) setState(() => _balance = 'Couldn\'t read it: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _k;
    final works = k['works'] == true;
    final c = works ? AppColors.success : AppColors.danger;
    final saved = k['saved_key'] == true;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: c.withValues(alpha: 0.3))),
          child: Row(
            children: [
              Icon(works ? Icons.verified_rounded : Icons.key_off_rounded, color: c, size: 36),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${k['name'] ?? k['service']}', style: context.text.titleLarge),
                    Text(works ? 'This key works' : 'This key didn\'t work', style: context.text.bodyMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Details', top: Space.l),
        if (k['detail'] != null) KeyValueRow('Account', '${k['detail']}'),
        if (k['problem'] != null) KeyValueRow('Problem', '${k['problem']}', valueColor: AppColors.danger),
        KeyValueRow('Key', '${k['ends_with'] ?? '—'}${saved ? ' (saved in the app)' : ' (given in chat, not saved)'}', mono: true),
        if (k['status'] != null) KeyValueRow('HTTP status', '${k['status']}'),
        if (k['latency_ms'] != null) KeyValueRow('Response time', '${k['latency_ms']} ms'),
        if (k['endpoint'] != null) KeyValueRow('Checked at', '${k['endpoint']}', mono: true),
        const SectionLabel('Options', top: Space.l),
        if (k['endpoint'] != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Diagnose the endpoint'),
            subtitle: Text('Times DNS, connection, TLS and the answer', style: context.text.bodySmall),
            value: _diagnoseOn,
            onChanged: _setDiagnose,
          ),
        if (_diagnoseOn) _diagnosis == null ? const LinearProgressIndicator(minHeight: 2) : DiagnosisPanel(d: _diagnosis!),
        if (_creditsId != null && saved)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show the balance'),
            subtitle: Text(_balanceOn ? (_balance ?? 'Reading…') : 'Credit left on this account', style: context.text.bodySmall),
            value: _balanceOn,
            onChanged: _setBalance,
          ),
        const SizedBox(height: Space.l),
        if (saved)
          FilledButton.icon(
            onPressed: _testing ? null : _retest,
            icon: _testing ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
            label: const Text('Test again'),
          )
        else
          Text('Keys given in chat aren\'t kept, so this one can\'t be tested again from here.', style: context.text.labelSmall),
      ],
    );
  }
}
