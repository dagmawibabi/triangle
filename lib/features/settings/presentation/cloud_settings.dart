import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../integrations/code_editor_screen.dart';
import 'package:omni_ai/omni_ai.dart' show CloudflareClient, E2BClient, E2BSandboxInfo, R2Credentials;

import '../../ai/data/ai.dart';
import '../../integrations/e2b_session.dart';
import '../../development/manage/app_managers.dart' show E2bManagerScreen;
import '../../telegram/data/telegram_tools.dart';
import '../../telegram/presentation/chat_actions.dart' show confirmAction;
import '../data/settings.dart';

String _when(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final now = DateTime.now();
  return l.day == now.day && l.month == now.month && l.year == now.year ? DateFormat.Hm().format(l) : DateFormat('d MMM, HH:mm').format(l);
}

String _span(Duration d) => d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : (d.inMinutes > 0 ? '${d.inMinutes} min' : '${d.inSeconds} s');

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children, this.trailing});
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
      ),
    ],
  );
}

/// A key or setting typed in and saved with the check; secrets are hidden.
/// Used at the top of each Apps & web tab.
class KeyField extends StatefulWidget {
  const KeyField({super.key, required this.label, required this.value, required this.onSave, this.hint, this.secret = false, this.verify, this.help, this.action});
  final String label;
  final String value;
  final String? hint;
  final bool secret;
  final Future<void> Function(String) onSave;

  /// Null when it works, else what went wrong.
  final Future<String?> Function(String)? verify;
  final Uri? help;

  /// A button beside "Get one", e.g. Manage once connected.
  final Widget? action;

  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  late final _ctrl = TextEditingController(text: widget.value);
  late bool _hidden = widget.secret;
  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void didUpdateWidget(KeyField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final v = _ctrl.text.trim();
    setState(() {
      _busy = true;
      _status = null;
    });
    await widget.onSave(v);
    String? error;
    if (v.isNotEmpty && widget.verify != null) error = await widget.verify!(v);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = error == null;
      _status = v.isEmpty ? 'Removed' : (error == null ? (widget.verify == null ? 'Saved' : 'Saved and working') : 'Saved, but the check failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label, style: context.text.titleSmall)),
            ?widget.action,
            if (widget.help != null)
              TextButton(
                onPressed: () => launchUrl(widget.help!, mode: LaunchMode.externalApplication),
                child: const Text('Get one'),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        TextField(
          controller: _ctrl,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => _status = null),
          onSubmitted: (_) => _save(),
          style: widget.secret ? const TextStyle(fontFamily: 'monospace', fontSize: 14) : null,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    tooltip: widget.secret ? 'Remove API key' : 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: _busy ? null : () {
                      setState(() => _ctrl.clear());
                      _save();
                    },
                  ),
                if (widget.secret)
                  IconButton(
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                IconButton(
                  tooltip: 'Save',
                  icon: _busy
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 20),
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(_status!, style: context.text.bodySmall?.copyWith(color: _ok ? AppColors.success : AppColors.warning)),
          ),
      ],
    ),
  );
}

// ---- Cloudflare -------------------------------------------------------------------------

class CloudflareTab extends ConsumerStatefulWidget {
  const CloudflareTab({super.key, this.extra = const [], this.onManage});

  /// Opens the Cloudflare manager; shown once a token is set.
  final VoidCallback? onManage;

  /// Shown after the account, e.g. the Cloudflare tools.
  final List<Widget> extra;

  @override
  ConsumerState<CloudflareTab> createState() => _CloudflareTabState();
}

class _CloudflareTabState extends ConsumerState<CloudflareTab> {
  List<Map>? _zones;
  List<Map>? _buckets;
  String? _error;
  bool _loading = false;
  String? _r2Check;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  CloudflareClient _client(AppSettings s, {String? account}) => CloudflareClient(
    token: s.cloudflareToken,
    accountId: account ?? s.cloudflareAccountId,
    r2: R2Credentials(accountId: account ?? s.cloudflareAccountId, accessKeyId: s.r2AccessKeyId, secretAccessKey: s.r2SecretKey),
  );

  Future<void> _load() async {
    final s = ref.read(settingsProvider);
    if (!s.hasCloudflare) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = _client(s);
    try {
      final zones = await c.call('GET', '/zones', query: {'per_page': '50'});
      final acc = await c.account();
      if (s.cloudflareAccountId.isEmpty) await ref.read(settingsProvider.notifier).setCloudflareAccountId(acc);
      List<Map>? buckets;
      try {
        final r = await c.call('GET', '/accounts/$acc/r2/buckets');
        buckets = [for (final b in (r is Map ? (r['buckets'] as List? ?? const []) : const [])) b as Map];
      } catch (_) {
        buckets = null; // The token may not have R2 rights.
      }
      if (mounted) {
        setState(() {
          _zones = [for (final z in zones as List) z as Map];
          _buckets = buckets;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testR2() async {
    final s = ref.read(settingsProvider);
    setState(() => _r2Check = 'Checking…');
    final c = _client(s, account: s.cloudflareAccountId.isEmpty ? null : s.cloudflareAccountId);
    try {
      if (c.accountId.isEmpty) await c.account();
      final bucket = s.r2Bucket.isNotEmpty ? s.r2Bucket : (_buckets?.firstOrNull?['name'] as String?);
      if (bucket == null) {
        setState(() => _r2Check = 'Set a default bucket to test the key.');
        return;
      }
      final cc = _client(s, account: c.accountId);
      final r = await cc.listObjects(bucket, max: 5);
      setState(() => _r2Check = 'Works: $bucket has ${(r['objects'] as List).length}${r['next_cursor'] == null ? '' : '+'} files at its top level.');
    } catch (e) {
      setState(() => _r2Check = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
            children: [
              Text(
                'Lets the assistant read and manage your Cloudflare sites, DNS, cache, Workers, Pages, KV and R2 storage. '
                'Reading needs nothing more; changes ask you first and deletions are under Destructive. Keys stay on this phone.',
                style: context.text.bodySmall,
              ),
              _Section(
                'API',
                children: [
                  KeyField(
                    label: 'API token',
                    hint: 'Cloudflare → My Profile → API Tokens',
                    value: s.cloudflareToken,
                    secret: true,
                    onSave: (v) async {
                      await ctl.setCloudflareToken(v);
                      unawaited(_load());
                    },
                    verify: (k) => ref.read(aiProvider).verifyKey('cloudflare', key: k),
                    help: Uri.parse('https://dash.cloudflare.com/profile/api-tokens'),
                    action: s.hasCloudflare && widget.onManage != null
                        ? FilledButton.tonalIcon(onPressed: widget.onManage, icon: const Icon(Icons.dashboard_customize_outlined, size: 16), label: const Text('Manage'))
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                    child: Text(
                      'Give the token what you want the assistant to do: Zone → DNS (edit), Zone → Cache Purge, Account → Workers '
                      'Scripts, Cloudflare Pages, Workers KV Storage and Workers R2 Storage (read or edit).',
                      style: context.text.bodySmall,
                    ),
                  ),
                  const Divider(indent: Space.l, endIndent: Space.l),
                  KeyField(
                    label: 'Account ID',
                    hint: 'Found from the token when empty',
                    value: s.cloudflareAccountId,
                    onSave: ctl.setCloudflareAccountId,
                  ),
                ],
              ),
              _Section(
                'R2 storage',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                    child: Text(
                      'Buckets are listed with the token. Reading and writing files uses R2\'s S3 API, which needs an access key: '
                      'R2 → Manage API tokens → Create (Object Read & Write).',
                      style: context.text.bodySmall,
                    ),
                  ),
                  KeyField(
                    label: 'Access key ID',
                    value: s.r2AccessKeyId,
                    secret: true,
                    onSave: (v) => ctl.setR2Keys(accessKeyId: v),
                    help: Uri.parse('https://dash.cloudflare.com/?to=/:account/r2/api-tokens'),
                  ),
                  KeyField(label: 'Secret access key', value: s.r2SecretKey, secret: true, onSave: (v) => ctl.setR2Keys(secret: v)),
                  const Divider(indent: Space.l, endIndent: Space.l),
                  if (_buckets != null && _buckets!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
                      child: DropdownButtonFormField<String>(
                        initialValue: _buckets!.any((b) => b['name'] == s.r2Bucket) ? s.r2Bucket : null,
                        decoration: const InputDecoration(labelText: 'Default bucket', isDense: true),
                        items: [for (final b in _buckets!) DropdownMenuItem(value: '${b['name']}', child: Text('${b['name']}'))],
                        onChanged: (v) => ctl.setR2Bucket(v ?? ''),
                      ),
                    )
                  else
                    KeyField(label: 'Default bucket', hint: 'Used when the assistant isn\'t told which', value: s.r2Bucket, onSave: ctl.setR2Bucket),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: s.hasCloudflare && s.hasR2Keys ? _testR2 : null,
                          icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                          label: const Text('Test R2 access'),
                        ),
                        const SizedBox(width: Space.m),
                        if (_r2Check != null) Expanded(child: Text(_r2Check!, style: context.text.bodySmall)),
                      ],
                    ),
                  ),
                ],
              ),
              if (s.hasCloudflare)
                _Section(
                  'Your account',
                  trailing: _loading
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : InkWell(onTap: _load, child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.text3)),
                  children: [
                    if (_error != null)
                      Padding(padding: const EdgeInsets.all(Space.l), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger))),
                    for (final z in _zones ?? const <Map>[])
                      ListTile(
                        dense: true,
                        leading: lead(const Icon(Icons.language_rounded, color: Color(0xFFF38020))),
                        title: Text('${z['name']}'),
                        subtitle: Text('${(z['plan'] as Map?)?['name'] ?? ''} · ${z['status']}'),
                        trailing: Icon(Icons.circle, size: 10, color: z['status'] == 'active' ? AppColors.success : AppColors.warning),
                      ),
                    for (final b in _buckets ?? const <Map>[])
                      ListTile(
                        dense: true,
                        leading: lead(const Icon(Icons.inventory_2_outlined, color: Color(0xFFF38020))),
                        title: Text('${b['name']}'),
                        subtitle: Text('R2 bucket${b['name'] == s.r2Bucket ? ' · default' : ''}'),
                      ),
                    if (!_loading && _error == null && (_zones?.isEmpty ?? true) && (_buckets?.isEmpty ?? true))
                      Padding(padding: const EdgeInsets.all(Space.l), child: Text('This token sees no sites or buckets yet.', style: context.text.bodySmall)),
                  ],
                ),
              ...widget.extra,
            ],
          ),
        ),
      ),
    );
  }
}

// ---- E2B ----------------------------------------------------------------------------------

class E2bTab extends ConsumerStatefulWidget {
  const E2bTab({super.key});

  @override
  ConsumerState<E2bTab> createState() => _E2bTabState();
}

class _E2bTabState extends ConsumerState<E2bTab> {
  List<E2BSandboxInfo>? _account;
  String? _error;
  String? _busy;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadAccount);
    // Keeps "expires in" current.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    final s = ref.read(settingsProvider);
    if (!s.hasE2bKey) return;
    try {
      final list = await ref.read(e2bSessionProvider).client().sandboxes();
      if (mounted) {
        setState(() {
          _account = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _do(String what, Future<void> Function() work) async {
    setState(() => _busy = what);
    try {
      await work();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = null);
      unawaited(_loadAccount());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final session = ref.watch(e2bSessionProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: RefreshIndicator(
          onRefresh: _loadAccount,
          child: ValueListenableBuilder(
            valueListenable: session.changes,
            builder: (context, _, _) {
              final box = session.current;
              final expires = session.expiresAt;
              final entry = box == null ? null : session.history.where((e) => e.id == box.id).firstOrNull;
              return ListView(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
                children: [
                  Text(
                    'E2B runs code in cloud sandboxes: Linux VMs with Python, Node, R and Java, internet and pip. The assistant uses '
                    'it for heavy work (as ScholarXIV does for executePython), and you can write and run code yourself in the editor.',
                    style: context.text.bodySmall,
                  ),
                  _Section(
                    'Key',
                    children: [
                      KeyField(
                        label: 'E2B API key',
                        hint: 'e2b.dev → Dashboard → API Keys',
                        value: s.e2bKey,
                        secret: true,
                        onSave: (v) async {
                          await ctl.setE2bKey(v);
                          unawaited(_loadAccount());
                        },
                        verify: (k) => ref.read(aiProvider).verifyKey('e2b', key: k),
                        help: Uri.parse('https://e2b.dev/dashboard?tab=keys'),
                        action: s.hasE2bKey
                            ? FilledButton.tonalIcon(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const E2bManagerScreen())),
                                icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
                                label: const Text('Manage'),
                              )
                            : null,
                      ),
                    ],
                  ),
                  _Section(
                    'This app\'s sandbox',
                    children: [
                      ListTile(
                        leading: lead(Icon(Icons.circle, size: 12, color: box == null ? AppColors.text3 : AppColors.success)),
                        title: Text(box == null ? 'Not running' : 'Running', style: context.text.titleSmall),
                        subtitle: Text(
                          box == null
                              ? (s.e2bKeepAlive ? 'One starts with the first run, or start it now.' : 'Each run gets its own sandbox, stopped after.')
                              : [
                                  box.id,
                                  box.template,
                                  'started ${_when(box.startedAt)}',
                                  if (entry != null) '${entry.runs} run${entry.runs == 1 ? '' : 's'}',
                                  if (expires != null)
                                    expires.isAfter(DateTime.now()) ? 'stops when idle in ${_span(expires.difference(DateTime.now()))}' : 'probably timed out',
                                ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                        child: Wrap(
                          spacing: Space.s,
                          runSpacing: Space.s,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: !s.hasE2bKey || _busy != null || box != null ? null : () => _do('start', session.start),
                              icon: _busy == 'start' ? const _Spin() : const Icon(Icons.play_arrow_rounded, size: 18),
                              label: const Text('Start'),
                            ),
                            OutlinedButton.icon(
                              onPressed: !s.hasE2bKey || _busy != null ? null : () => _do('restart', session.restart),
                              icon: _busy == 'restart' ? const _Spin() : const Icon(Icons.restart_alt_rounded, size: 18),
                              label: const Text('Restart'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                              onPressed: box == null || _busy != null
                                  ? null
                                  : () => _do('stop', () async {
                                      if (await confirmAction(
                                        context,
                                        title: 'Shut the sandbox down?',
                                        message: 'Its variables, installed packages and files are lost.',
                                        action: 'Shut down',
                                      )) {
                                        await session.stop(null, 'shut down in Settings');
                                      }
                                    }),
                              icon: _busy == 'stop' ? const _Spin() : const Icon(Icons.power_settings_new_rounded, size: 18),
                              label: const Text('Shut down'),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CodeEditorScreen())),
                              icon: const Icon(Icons.code_rounded, size: 18),
                              label: const Text('Code editor'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    'Sandbox options',
                    children: [
                      SwitchListTile(
                        title: const Text('Keep the sandbox between runs'),
                        subtitle: Text(
                          'Variables, files and installed packages carry over until it idles out. Off: a fresh sandbox each run.',
                          style: context.text.bodySmall,
                        ),
                        value: s.e2bKeepAlive,
                        onChanged: ctl.setE2bKeepAlive,
                      ),
                      SwitchListTile(
                        title: const Text('Internet access'),
                        subtitle: Text('pip install, downloads and APIs. Applies to the next sandbox.', style: context.text.bodySmall),
                        value: s.e2bInternet,
                        onChanged: ctl.setE2bInternet,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                        child: Text('Stop when idle for ${s.e2bTimeoutMinutes} min', style: context.text.titleSmall),
                      ),
                      Slider(
                        min: 1,
                        max: 60,
                        divisions: 59,
                        value: s.e2bTimeoutMinutes.toDouble().clamp(1, 60),
                        label: '${s.e2bTimeoutMinutes} min',
                        onChanged: (v) => ctl.setE2bTimeoutMinutes(v.round()),
                      ),
                      KeyField(
                        label: 'Template',
                        hint: E2BClient.defaultTemplate,
                        value: s.e2bTemplate,
                        onSave: ctl.setE2bTemplate,
                      ),
                    ],
                  ),
                  if (s.hasE2bKey)
                    _Section(
                      'Running on your E2B account',
                      trailing: InkWell(onTap: _loadAccount, child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.text3)),
                      children: [
                        if (_error != null)
                          Padding(padding: const EdgeInsets.all(Space.l), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger))),
                        if (_account != null && _account!.isEmpty)
                          Padding(padding: const EdgeInsets.all(Space.l), child: Text('Nothing running.', style: context.text.bodySmall)),
                        for (final b in _account ?? const <E2BSandboxInfo>[])
                          ListTile(
                            dense: true,
                            leading: lead(Icon(Icons.circle, size: 10, color: b.state == 'running' ? AppColors.success : AppColors.warning)),
                            title: Text('${b.id}${b.id == box?.id ? '  · this app' : ''}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                            subtitle: Text(
                              [b.template, b.state, if (b.startedAt != null) 'since ${_when(b.startedAt)}', if (b.cpus != null) '${b.cpus} CPU · ${b.memoryMb} MB'].join(' · '),
                            ),
                            trailing: IconButton(
                              tooltip: 'Shut down',
                              icon: Icon(Icons.power_settings_new_rounded, color: AppColors.danger, size: 20),
                              onPressed: _busy != null
                                  ? null
                                  : () => _do('kill ${b.id}', () async {
                                      if (!await confirmAction(
                                        context,
                                        title: 'Shut down ${b.id}?',
                                        message: b.id == box?.id ? 'This is the app\'s sandbox; its state is lost.' : 'It may belong to another app on your E2B account.',
                                        action: 'Shut down',
                                      )) {
                                        return;
                                      }
                                      if (b.id == box?.id) {
                                        await session.stop(null, 'shut down in Settings');
                                      } else {
                                        await session.client().kill(b.id);
                                        await session.markStopped(b.id, 'shut down in Settings');
                                      }
                                    }),
                            ),
                          ),
                      ],
                    ),
                  _Section(
                    'History',
                    trailing: session.history.any((e) => !e.live)
                        ? InkWell(
                            onTap: session.clearHistory,
                            child: Text('Clear', style: context.text.labelSmall?.copyWith(color: AppColors.accent)),
                          )
                        : null,
                    children: [
                      if (session.history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(Space.l),
                          child: Text('Sandboxes this app starts and stops are listed here.', style: context.text.bodySmall),
                        ),
                      for (final e in session.history.take(50))
                        ListTile(
                          dense: true,
                          leading: lead(Icon(
                            e.live ? Icons.play_circle_outline_rounded : Icons.stop_circle_outlined,
                            color: e.live ? AppColors.success : AppColors.text3,
                          )),
                          title: Text(e.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                          subtitle: Text(
                            [
                              'Created ${_when(e.started)} by ${e.by.isEmpty ? 'the app' : e.by}',
                              if (e.ended != null) 'destroyed ${_when(e.ended)} (${e.endReason ?? 'stopped'}) after ${_span(e.ended!.difference(e.started))}',
                              if (e.live) 'running',
                              '${e.runs} run${e.runs == 1 ? '' : 's'}',
                              e.template,
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin();

  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2));
}

// ---- Exa --------------------------------------------------------------------------------

/// Exa web search: the key, and the tools it powers.
class ExaTab extends ConsumerStatefulWidget {
  const ExaTab({super.key});

  @override
  ConsumerState<ExaTab> createState() => _ExaTabState();
}

class _ExaTabState extends ConsumerState<ExaTab> {
  String? _test;

  Future<void> _search() async {
    setState(() => _test = 'Searching…');
    final r = await ref.read(toolRunnerProvider).run('web_search', {'query': 'latest news about Ethiopia', 'limit': 3});
    if (!mounted) return;
    final results = r.json['results'] as List?;
    setState(
      () => _test = r.json['error'] != null
          ? '${r.json['error']}'
          : 'Works: ${results?.length ?? 0} results, e.g. “${(results?.firstOrNull as Map?)?['title'] ?? ''}”',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final tool = toolNamed('web_search');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
          children: [
            _Section(
              'Key',
              children: [
                KeyField(
                  label: 'Exa API key',
                  hint: 'dashboard.exa.ai → API keys',
                  value: s.exaKey,
                  secret: true,
                  onSave: ctl.setExaKey,
                  help: Uri.parse('https://dashboard.exa.ai/api-keys'),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            Text(
              'Exa is a search engine made for AI: the assistant searches the web with it when you ask about news, facts, products, '
              'people or anything outside Telegram, and gets the pages\' key passages to answer from and cite. Pages themselves '
              'are read with fetch_url and the browser, which need no key.',
              style: context.text.bodySmall,
            ),
            if (tool != null)
              _Section(
                'Tool',
                children: [
                  SwitchListTile(
                    secondary: lead(const Icon(Icons.travel_explore_rounded)),
                    title: const Text('web_search'),
                    subtitle: Text(s.hasExaKey ? 'Searches the web with Exa' : 'Needs the key above', style: context.text.bodySmall),
                    value: s.toolChosen(tool.name),
                    onChanged: (v) => ctl.setToolEnabled(tool.name, v),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: s.hasExaKey ? _search : null,
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Try a search'),
                        ),
                        const SizedBox(width: Space.m),
                        if (_test != null) Expanded(child: Text(_test!, style: context.text.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
