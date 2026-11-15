import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_ai/omni_ai.dart' show PhoneCallView, VapiPhoneNumber;
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../ai/data/ai.dart';
import '../settings/presentation/settings_screen.dart' show SettingsCard, SettingsKeyTile;
import '../chat/domain/chat_models.dart';
import 'vapi.dart';
import '../development/manage/app_managers.dart' show VapiManagerScreen;

/// Cards for the Vapi call tools; null for other tools.
Widget? vapiResultFor(ToolPart part, Map<String, dynamic> j) {
  if (!vapiToolNames.contains(part.name) || j['error'] != null) return null;
  return switch (part.name) {
    'place_phone_call' || 'get_phone_call' when j['id'] != null => _LiveCall(id: '${j['id']}'),
    'place_phone_calls' when j['calls'] is List => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in (j['calls'] as List).take(4))
          if (c is Map && c['id'] != null) _LiveCall(id: '${c['id']}'),
        if ((j['calls'] as List).length > 4) Text('+${(j['calls'] as List).length - 4} more calls'),
      ],
    ),
    'list_phone_calls' when j['calls'] is List => _CallList(calls: [for (final c in j['calls'] as List) if (c is Map) Map<String, dynamic>.from(c)]),
    'phone_call_recording' when j['url'] != null => _Recording(url: '${j['url']}'),
    'list_phone_numbers' when j['numbers'] is List => _Numbers(numbers: [for (final n in j['numbers'] as List) if (n is Map) Map<String, dynamic>.from(n)]),
    _ => null,
  };
}

Widget _frame(Widget child) => Builder(
  builder: (context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: child,
  ),
);

/// A call, followed live from Vapi (status, transcript, summary, Hang up).
class _LiveCall extends ConsumerWidget {
  const _LiveCall({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _frame(PhoneCallView(client: ref.read(aiProvider).vapi.client, callId: id));
}

Future<void> showPhoneCall(BuildContext context, String id) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    builder: (context, scroll) => SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
      child: _LiveCall(id: id),
    ),
  ),
);

class _CallList extends StatelessWidget {
  const _CallList({required this.calls});
  final List<Map<String, dynamic>> calls;

  @override
  Widget build(BuildContext context) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              Icon(Icons.phone_in_talk_outlined, size: 18, color: AppColors.tint),
              const SizedBox(width: Space.s),
              Text('${calls.length} call${calls.length == 1 ? '' : 's'}', style: context.text.titleSmall),
            ],
          ),
        ),
        if (calls.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('No calls yet.', style: context.text.bodySmall)),
        for (final c in calls)
          ListTile(
            dense: true,
            leading: Icon(
              '${c['status']}' == 'ended' ? Icons.call_end_rounded : Icons.phone_forwarded_rounded,
              color: '${c['outcome'] ?? ''}'.contains('success') ? AppColors.success : AppColors.text2,
            ),
            title: Text('${c['to_name'] ?? c['to'] ?? c['customer'] ?? 'Call'}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${c['summary'] ?? c['status'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            onTap: () => showPhoneCall(context, '${c['id']}'),
          ),
      ],
    ),
  );
}

class _Recording extends StatefulWidget {
  const _Recording({required this.url});
  final String url;

  @override
  State<_Recording> createState() => _RecordingState();
}

class _RecordingState extends State<_Recording> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) => mounted ? setState(() => _playing = false) : null);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _frame(
    ListTile(
      leading: IconButton.filledTonal(
        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        onPressed: () async {
          _playing ? await _player.pause() : await _player.play(UrlSource(widget.url));
          setState(() => _playing = !_playing);
        },
      ),
      title: const Text('Call recording'),
      subtitle: Text('The link expires after a while', style: context.text.bodySmall),
      trailing: IconButton(
        tooltip: 'Open',
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
      ),
    ),
  );
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.numbers});
  final List<Map<String, dynamic>> numbers;

  @override
  Widget build(BuildContext context) => _frame(
    Column(
      children: [
        for (final n in numbers)
          ListTile(
            dense: true,
            leading: const Icon(Icons.dialpad_rounded),
            title: Text('${n['number'] ?? n['name'] ?? n['id']}', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: Text([n['name'], n['provider'], n['status']].whereType<Object>().join(' · '), style: context.text.bodySmall),
          ),
        if (numbers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Text('No numbers. Add one at dashboard.vapi.ai to make calls.', style: context.text.bodySmall),
          ),
      ],
    ),
  );
}

// ---- settings ----------------------------------------------------------------------------

/// Settings → Phone calls: the Vapi key and how calls are made.
class VapiSettingsScreen extends ConsumerStatefulWidget {
  const VapiSettingsScreen({super.key});

  @override
  ConsumerState<VapiSettingsScreen> createState() => _VapiSettingsScreenState();
}

class _VapiSettingsScreenState extends ConsumerState<VapiSettingsScreen> {
  final _name = TextEditingController();
  final _country = TextEditingController();
  String _voice = 'Elliot';
  int _minutes = 10;
  bool _loaded = false;

  static const _voices = ['Elliot', 'Clara', 'Emma', 'Godfrey', 'Kai', 'Layla', 'Naina', 'Neil', 'Nico', 'Sagar', 'Savannah', 'Sid'];

  @override
  void initState() {
    super.initState();
    VapiStore.load().then((_) {
      if (!mounted) return;
      setState(() {
        _name.text = VapiStore.onBehalfOf;
        _country.text = VapiStore.countryCode;
        _voice = _voices.contains(VapiStore.voice) ? VapiStore.voice : 'Elliot';
        _minutes = VapiStore.maxMinutes;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  /// The call settings; the key saves itself from its own field.
  Future<void> _save() async {
    await VapiStore.save(onBehalfOf: _name.text, countryCode: _country.text, voice: _voice, maxMinutes: _minutes);
    VapiStore.apply(ref.read(aiProvider));
    if (mounted) showSnack(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Phone calls'),
      actions: [
        if (VapiStore.ready)
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VapiManagerScreen())),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text('Your calls'),
          ),
      ],
    ),
    body: !_loaded
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            children: [
              Text(
                'With a Vapi key, the assistant can phone people and businesses for you: an AI voice agent makes the '
                'call, then reports back with a summary, the answers it collected and the transcript. Every call asks '
                'you first, and emergency numbers are never called.',
                style: context.text.bodySmall?.copyWith(height: 1.45),
              ),
              const SizedBox(height: Space.l),
              // The same key field as AI & models: show/hide, Check, Saved or the error, Get a key.
              SettingsCard(
                children: [
                  SettingsKeyTile(
                    title: 'Vapi',
                    subtitle: 'dashboard.vapi.ai → Organization → API keys. Use the private key.',
                    value: VapiStore.key,
                    onSave: (k) async {
                      await VapiStore.save(key: k);
                      VapiStore.apply(ref.read(aiProvider));
                      if (mounted) setState(() {});
                    },
                    verify: (k) => ref.read(aiProvider).verifyKey('vapi', key: k),
                    help: Uri.parse('https://dashboard.vapi.ai/org/api-keys'),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Calls are made on behalf of', hintText: 'Your name', helperText: 'The agent says who it calls for.'),
              ),
              const SizedBox(height: Space.m),
              TextField(
                controller: _country,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Default country code', hintText: '+251', helperText: 'For numbers written without one.'),
              ),
              const SizedBox(height: Space.m),
              DropdownButtonFormField<String>(
                initialValue: _voice,
                decoration: const InputDecoration(labelText: 'Agent voice'),
                items: [for (final v in _voices) DropdownMenuItem(value: v, child: Text(v))],
                onChanged: (v) => setState(() => _voice = v ?? 'Elliot'),
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(child: Text('Longest call', style: context.text.bodyMedium)),
                  Text('$_minutes min', style: context.text.labelMedium),
                ],
              ),
              Slider(value: _minutes.toDouble(), min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() => _minutes = v.round())),
              const SizedBox(height: Space.m),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save call settings'),
              ),
              if (VapiStore.ready) ...[
                const SizedBox(height: Space.s),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      useSafeArea: true,
                      // Full width on any screen, not Material's 640 px cap.
                      constraints: const BoxConstraints(maxWidth: double.infinity),
                      builder: (_) => const _NumberChooser(),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.dialpad_rounded, size: 18),
                  label: Text(VapiStore.phoneNumberId.isEmpty ? 'Number to call from' : 'Calling from a chosen number'),
                ),
              ],
            ],
          ),
  );
}


/// Picks the Vapi number calls are made from (or the account's first).
class _NumberChooser extends ConsumerStatefulWidget {
  const _NumberChooser();

  @override
  ConsumerState<_NumberChooser> createState() => _NumberChooserState();
}

class _NumberChooserState extends ConsumerState<_NumberChooser> {
  List<VapiPhoneNumber>? _numbers;
  String? _error;
  String _picked = VapiStore.phoneNumberId;

  @override
  void initState() {
    super.initState();
    ref.read(aiProvider).vapi.client.listPhoneNumbers().then(
      (n) => mounted ? setState(() => _numbers = n) : null,
      onError: (Object e) => mounted ? setState(() => _error = '$e') : null,
    );
  }

  Future<void> _pick(String id) async {
    setState(() => _picked = id);
    await VapiStore.save(phoneNumberId: id);
    VapiStore.apply(ref.read(aiProvider));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final numbers = _numbers;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Number to call from', style: context.text.titleMedium),
            Text('Calls show this number to the people the agent phones.', style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            if (_error != null)
              Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger))
            else if (numbers == null)
              const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (numbers.isEmpty)
              Text('This Vapi account has no numbers. Add one at dashboard.vapi.ai → Phone numbers.', style: context.text.bodySmall)
            else
              RadioGroup<String>(
                groupValue: _picked,
                onChanged: (v) => _pick(v ?? ''),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: '',
                      title: const Text('Automatic'),
                      subtitle: Text('The account\'s first active number', style: context.text.bodySmall),
                    ),
                    for (final n in numbers)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: n.id,
                        title: Text(n.number ?? n.sipUri ?? n.name ?? n.id, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                          [
                            ?n.name,
                            ?n.provider,
                            if (n.status != null && n.status != 'active') n.status!,
                            if (n.provider == 'vapi') 'no international calls',
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
