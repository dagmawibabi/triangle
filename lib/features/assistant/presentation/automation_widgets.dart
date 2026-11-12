import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/theme.dart';
import '../../ai/data/ai.dart';
import '../../settings/data/settings.dart';
import '../../settings/presentation/model_picker_screen.dart';
import '../../telegram/data/telegram_tools.dart';
import '../device_events.dart';
import '../tool_allowlist.dart';
import '../watches.dart' show WatchModel;

/// A rounded group, as Settings draws them.
Widget automationCard(BuildContext context, List<Widget> children) => Container(
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(Radii.l),
    border: Border.all(color: AppColors.line),
  ),
  clipBehavior: Clip.antiAlias,
  child: Material(type: MaterialType.transparency, child: Column(children: children)),
);

// ---- tools ----------------------------------------------------------------

/// "All tools" or the picked ones; tap to change. [value] null is all.
class ToolAllowlistTile extends StatelessWidget {
  const ToolAllowlistTile({super.key, required this.value, required this.onChanged, this.note});
  final ToolAllowlist? value;
  final ValueChanged<ToolAllowlist?> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final count = v?.pick(telegramTools).length;
    return automationCard(context, [
      ListTile(
        leading: lead(const Icon(Icons.handyman_outlined)),
        title: Text(v == null ? 'All tools' : '$count tool${count == 1 ? '' : 's'}'),
        subtitle: Text(
          v == null ? (note ?? 'Every tool the assistant has, as Settings → Tools allows') : v.describe(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final picked = await Navigator.of(context).push<_Picked>(
            MaterialPageRoute(builder: (_) => ToolAllowlistScreen(initial: v)),
          );
          if (picked != null) onChanged(picked.value);
        },
      ),
    ]);
  }
}

class _Picked {
  const _Picked(this.value);
  final ToolAllowlist? value;
}

/// Picks which tools a watch or routine may use: all of them (the default),
/// or areas, categories and single tools.
class ToolAllowlistScreen extends ConsumerStatefulWidget {
  const ToolAllowlistScreen({super.key, this.initial});
  final ToolAllowlist? initial;

  @override
  ConsumerState<ToolAllowlistScreen> createState() => _ToolAllowlistScreenState();
}

class _ToolAllowlistScreenState extends ConsumerState<ToolAllowlistScreen> {
  late bool _all = widget.initial == null;
  late final Set<String> _names = {for (final t in widget.initial?.pick(telegramTools) ?? const <TelegramTool>[]) t.name};
  String _q = '';

  /// The picked names, written as areas and categories where whole ones are
  /// picked, so tools added to them later are included.
  ToolAllowlist _compress() {
    final out = <String>{};
    for (final area in ToolArea.values) {
      final inArea = telegramTools.where((t) => ToolArea.of(t) == area).toList();
      if (inArea.isNotEmpty && inArea.every((t) => _names.contains(t.name))) {
        out.add(ToolAllowlist.area(area));
        continue;
      }
      for (final cat in {for (final t in inArea) t.category}) {
        final inCat = inArea.where((t) => t.category == cat).toList();
        if (inCat.every((t) => _names.contains(t.name))) {
          out.add(ToolAllowlist.category(cat));
        } else {
          out.addAll([for (final t in inCat) if (_names.contains(t.name)) ToolAllowlist.tool(t.name)]);
        }
      }
    }
    return ToolAllowlist(out);
  }

  bool? _state(Iterable<TelegramTool> tools) {
    final n = tools.where((t) => _names.contains(t.name)).length;
    return n == 0 ? false : (n == tools.length ? true : null);
  }

  void _set(Iterable<TelegramTool> tools, bool on) => setState(() {
    for (final t in tools) {
      on ? _names.add(t.name) : _names.remove(t.name);
    }
  });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final q = _q.toLowerCase();
    bool match(TelegramTool t) => q.isEmpty || '${t.name} ${t.label} ${t.category.label}'.toLowerCase().contains(q);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools it may use'),
        actions: [
          TextButton(
            onPressed: () {
              if (!_all && _names.isEmpty) {
                showSnack(context, 'Pick at least one tool, or allow all', icon: Icons.info_outline_rounded);
                return;
              }
              Navigator.pop(context, _Picked(_all ? null : _compress()));
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('All tools'), icon: Icon(Icons.select_all_rounded)),
              ButtonSegment(value: false, label: Text('Only these'), icon: Icon(Icons.checklist_rounded)),
            ],
            selected: {_all},
            onSelectionChanged: (v) => setState(() => _all = v.first),
          ),
          const SizedBox(height: Space.s),
          Text(
            _all
                ? 'Every tool the assistant has, as your switches in Settings → Tools allow. New tools are included as they arrive.'
                : 'Only what you tick. Whole areas and categories stay picked as tools are added to them. Your switches in Settings → Tools still apply.',
            style: context.text.bodySmall,
          ),
          if (!_all) ...[
            const SizedBox(height: Space.m),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    decoration: const InputDecoration(isDense: true, hintText: 'Search tools', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                  ),
                ),
                const SizedBox(width: Space.s),
                Text('${_names.length} picked', style: context.text.labelSmall),
              ],
            ),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -1, vertical: -3),label: const Text('Only reading'), onPressed: () => setState(() => _names..clear()..addAll([for (final t in telegramTools) if (!t.modifiesData) t.name]))),
                ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -1, vertical: -3),label: const Text('Clear'), onPressed: () => setState(_names.clear)),
              ],
            ),
            for (final area in ToolArea.values) ...[
              Builder(
                builder: (context) {
                  final inArea = telegramTools.where((t) => ToolArea.of(t) == area && match(t)).toList();
                  if (inArea.isEmpty) return const SizedBox.shrink();
                  final cats = <ToolCategory, List<TelegramTool>>{};
                  for (final t in inArea) {
                    (cats[t.category] ??= []).add(t);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: Space.l),
                    child: automationCard(context, [
                      CheckboxListTile(
                        tristate: true,
                        value: _state(inArea),
                        onChanged: (v) => _set(inArea, _state(inArea) != true),
                        title: Text(area.label, style: context.text.titleSmall),
                        subtitle: Text('${inArea.length} tools', style: context.text.bodySmall),
                      ),
                      for (final MapEntry(key: cat, value: tools) in cats.entries)
                        ExpansionTile(
                          initiallyExpanded: q.isNotEmpty,
                          leading: Checkbox(
                            tristate: true,
                            value: _state(tools),
                            onChanged: (_) => _set(tools, _state(tools) != true),
                          ),
                          title: Text(cat.label),
                          subtitle: Text('${tools.where((t) => _names.contains(t.name)).length} of ${tools.length}', style: context.text.bodySmall),
                          children: [
                            for (final t in tools)
                              CheckboxListTile(
                                dense: true,
                                value: _names.contains(t.name),
                                onChanged: (v) => _set([t], v == true),
                                title: Text(t.label),
                                subtitle: Text(
                                  [
                                    t.name,
                                    if (t.destructive) 'deletes' else if (t.modifiesData) 'acts' else 'reads',
                                    if (!t.isOn(s)) 'off in Settings',
                                  ].join(' · '),
                                  style: context.text.bodySmall,
                                ),
                              ),
                          ],
                        ),
                    ]),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Picks one tool, for a routine's "run a tool" step. Tools that delete or
/// spend aren't offered.
class ToolPickerScreen extends ConsumerStatefulWidget {
  const ToolPickerScreen({super.key, this.current});
  final String? current;

  @override
  ConsumerState<ToolPickerScreen> createState() => _ToolPickerScreenState();
}

/// Tools a routine step can't run on its own.
bool routineStepTool(TelegramTool t) =>
    !t.destructive && !t.alwaysAsk && !const {'remember', 'update_memory', 'forget_memory', 'list_memories', 'run_routine'}.contains(t.name) &&
    t.category != ToolCategory.mcp && t.category != ToolCategory.skills && t.category != ToolCategory.decisions;

class _ToolPickerScreenState extends ConsumerState<ToolPickerScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final q = _q.toLowerCase();
    final tools = telegramTools.where(routineStepTool).where((t) => q.isEmpty || '${t.name} ${t.label} ${t.category.label} ${t.description}'.toLowerCase().contains(q)).toList();
    final cats = <ToolCategory, List<TelegramTool>>{};
    for (final t in tools) {
      (cats[t.category] ??= []).add(t);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a tool')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(isDense: true, hintText: 'Search, e.g. "send", "battery", "calendar"', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final MapEntry(key: cat, value: list) in cats.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
                    child: Text(cat.label.toUpperCase(), style: context.text.labelSmall),
                  ),
                  for (final t in list)
                    ListTile(
                      selected: t.name == widget.current,
                      title: Text(t.label),
                      subtitle: Text(
                        '${t.name}${t.isOn(s) ? '' : ' · off in Settings'}\n${t.description}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, t.name),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- model ----------------------------------------------------------------

/// Which model a watch or routine runs on: free (the default), cheapest,
/// the chat's, or one picked.
class AutomationModelTile extends ConsumerWidget {
  const AutomationModelTile({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ai = ref.watch(aiProvider);
    ref.watch(modelCatalogProvider);
    final resolved = automationModel(ai, s, value);
    final main = canonicalModelId(s.model);
    final fellBack = (value == WatchModel.free || value == WatchModel.cheap) && resolved == main;
    Widget option(String v, String title, String sub) => RadioListTile<String>(
      value: v,
      title: Text(title),
      subtitle: Text(sub, style: context.text.bodySmall),
    );
    final custom = value != WatchModel.free && value != WatchModel.cheap && value != WatchModel.main;
    return automationCard(context, [
      RadioGroup<String>(
        groupValue: custom ? '_custom' : value,
        onChanged: (v) async {
          if (v == null) return;
          if (v != '_custom') return onChanged(v);
          final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ModelPickerScreen(current: custom ? value : main)));
          if (id != null && id.isNotEmpty) onChanged(id);
        },
        child: Column(
          children: [
            option(WatchModel.free, 'Free', 'A free model from a service you have a key for; the cheapest when there is none'),
            option(WatchModel.cheap, 'Cheapest', 'The lowest-priced model that can use tools'),
            option(WatchModel.main, 'Same as chat', '${modelLabel(main)}: best for careful replies'),
            option('_custom', custom ? modelLabel(value) : 'Pick a model…', 'Any model you have a key for'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
        child: Text(
          fellBack
              ? 'Right now that means ${modelLabel(resolved)}: no cheaper model was found (open Settings → AI & models to load the model list, or add an OpenRouter key for free models).'
              : 'Runs on ${modelLabel(resolved)}. If it fails, the run is tried again on ${modelLabel(main)}.',
          style: context.text.bodySmall,
        ),
      ),
    ]);
  }
}

// ---- phone triggers ---------------------------------------------------------

/// Edits what on the phone starts a watch or routine.
class DeviceConditionEditor extends StatefulWidget {
  const DeviceConditionEditor({super.key, required this.value, required this.onChanged});
  final DeviceCondition value;
  final ValueChanged<DeviceCondition> onChanged;

  @override
  State<DeviceConditionEditor> createState() => _DeviceConditionEditorState();
}

class _DeviceConditionEditorState extends State<DeviceConditionEditor> {
  late final _ssid = TextEditingController(text: widget.value.ssid);
  late final _place = TextEditingController(text: widget.value.placeName);
  late final _query = TextEditingController(text: widget.value.query);
  late final _url = TextEditingController(text: widget.value.url);
  late final _app = TextEditingController(text: widget.value.app);
  late final _amount = TextEditingController(text: widget.value.amount > 0 ? _plain(widget.value.amount) : '');
  bool _locating = false;

  static String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void dispose() {
    _ssid.dispose();
    _place.dispose();
    _query.dispose();
    _url.dispose();
    _app.dispose();
    _amount.dispose();
    super.dispose();
  }

  DeviceCondition get v => widget.value;

  /// What a trigger needs to work, said under its fields.
  static String? _needs(DeviceTriggerKind k) => switch (k) {
    DeviceTriggerKind.missedCall => 'Needs the Call log permission (Settings → Permissions).',
    DeviceTriggerKind.newSms => 'Needs the Text messages permission (Settings → Permissions).',
    DeviceTriggerKind.moneyIn || DeviceTriggerKind.moneyOut => 'Reads bank and wallet texts with Money\'s patterns: needs the Text messages permission.',
    DeviceTriggerKind.notification => 'Needs notification access for Triangle (Android Settings → Notification access).',
    DeviceTriggerKind.mobileData => 'Needs Usage access for Triangle (Android Settings → Usage access). Fires once a day.',
    DeviceTriggerKind.youtubeUpload => 'Needs the YouTube key (Settings → More apps → YouTube). About 2 quota units a check.',
    DeviceTriggerKind.pageChanged => 'Reads the page without running its scripts; pages built entirely by JavaScript may not change.',
    _ => null,
  };

  Future<void> _here() async {
    setState(() => _locating = true);
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permission is needed to use where you are', icon: Icons.location_off_outlined);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
      widget.onChanged(v.copyWith(lat: pos.latitude, lng: pos.longitude));
      if (mounted) showSnack(context, 'Place set to where you are now');
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t get your location: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text('Phone triggers work on Android.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in DeviceTriggerKind.values)
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -3),label: Text(k.label), selected: v.kind == k, onSelected: (_) => widget.onChanged(v.copyWith(kind: k))),
          ],
        ),
        const SizedBox(height: Space.s),
        Text(v.kind.explanation, style: context.text.bodySmall),
        const SizedBox(height: Space.m),
        if (v.kind == DeviceTriggerKind.batteryLow) ...[
          Text('At ${v.threshold}% or less', style: context.text.titleSmall),
          Slider(
            min: 5,
            max: 50,
            divisions: 9,
            value: v.threshold.clamp(5, 50).toDouble(),
            label: '${v.threshold}%',
            onChanged: (x) => widget.onChanged(v.copyWith(threshold: x.round())),
          ),
        ],
        if (v.kind.usesSsid) ...[
          TextField(
            controller: _ssid,
            onChanged: (x) => widget.onChanged(v.copyWith(ssid: x.trim())),
            decoration: const InputDecoration(labelText: 'Network name (optional)', hintText: 'Leave empty for any Wi-Fi'),
          ),
          const SizedBox(height: Space.xs),
          Text('Android shows the network\'s name only with location permission.', style: context.text.bodySmall),
        ],
        if (v.kind.needsPlace) ...[
          TextField(
            controller: _place,
            onChanged: (x) => widget.onChanged(v.copyWith(placeName: x.trim())),
            decoration: const InputDecoration(labelText: 'Place name', hintText: 'e.g. Home, Work, Gym'),
          ),
          const SizedBox(height: Space.s),
          Row(
            children: [
              Expanded(
                child: Text(
                  v.hasPlace ? '${v.lat!.toStringAsFixed(5)}, ${v.lng!.toStringAsFixed(5)}' : 'No place set yet',
                  style: context.text.bodySmall?.copyWith(color: v.hasPlace ? null : AppColors.warning),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _locating ? null : _here,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Use where I am'),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text('Counts as there within ${v.radius} m', style: context.text.titleSmall),
          Slider(
            min: 50,
            max: 2000,
            divisions: 39,
            value: v.radius.clamp(50, 2000).toDouble(),
            label: '${v.radius} m',
            onChanged: (x) => widget.onChanged(v.copyWith(radius: (x / 50).round() * 50)),
          ),
          Text(
            'Triangle checks where the phone is every couple of minutes while it runs in the background. '
            'Allow location "all the time" in Android settings for this to work with the screen off.',
            style: context.text.bodySmall,
          ),
        ],
        if (v.kind.usesUrl) ...[
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            onChanged: (x) => widget.onChanged(v.copyWith(url: x.trim())),
            decoration: const InputDecoration(labelText: 'Page', hintText: 'https://example.com/product'),
          ),
          const SizedBox(height: Space.s),
        ],
        if (v.kind.usesApp) ...[
          TextField(
            controller: _app,
            onChanged: (x) => widget.onChanged(v.copyWith(app: x.trim())),
            decoration: const InputDecoration(labelText: 'From app (optional)', hintText: 'e.g. WhatsApp, CBE Birr; empty for any app'),
          ),
          const SizedBox(height: Space.s),
        ],
        if (v.kind.usesQuery) ...[
          TextField(
            controller: _query,
            onChanged: (x) => widget.onChanged(v.copyWith(query: x.trim())),
            decoration: InputDecoration(
              labelText: switch (v.kind) {
                DeviceTriggerKind.missedCall => 'From (optional)',
                DeviceTriggerKind.moneyIn => 'From (optional)',
                DeviceTriggerKind.moneyOut => 'To (optional)',
                DeviceTriggerKind.pageChanged => 'Words to wait for (optional)',
                DeviceTriggerKind.youtubeUpload => 'Channel',
                _ => 'Matching (optional)',
              },
              hintText: switch (v.kind) {
                DeviceTriggerKind.missedCall => 'A name or number; empty for anyone',
                DeviceTriggerKind.moneyIn || DeviceTriggerKind.moneyOut => 'A name or bank; empty for anyone',
                DeviceTriggerKind.pageChanged => 'e.g. "In stock"; empty for any change',
                DeviceTriggerKind.youtubeUpload => '@handle, link or name',
                DeviceTriggerKind.notification => 'Words in the title or text; empty for any',
                _ => 'A sender or words; empty for any text',
              },
            ),
          ),
          const SizedBox(height: Space.xs),
        ],
        if (v.kind.usesAmount) ...[
          const SizedBox(height: Space.s),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (x) => widget.onChanged(v.copyWith(amount: double.tryParse(x.trim()) ?? 0)),
            decoration: InputDecoration(
              labelText: switch (v.kind) {
                DeviceTriggerKind.mobileData => 'Megabytes today',
                DeviceTriggerKind.storageLow => 'Gigabytes free',
                _ => 'At least (optional)',
              },
              hintText: switch (v.kind) {
                DeviceTriggerKind.mobileData => 'e.g. 500',
                DeviceTriggerKind.storageLow => 'e.g. 5',
                _ => 'e.g. 1000; empty for any amount',
              },
            ),
          ),
          const SizedBox(height: Space.xs),
        ],
        if (v.kind.interval) ...[
          const SizedBox(height: Space.s),
          Text('Check every ${v.cooldownMinutes < 60 ? '${v.cooldownMinutes} min' : '${v.cooldownMinutes ~/ 60} h'}', style: context.text.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final m in const [15, 30, 60, 180, 360, 720])
                ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                  label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                  selected: v.cooldownMinutes == m,
                  onSelected: (_) => widget.onChanged(v.copyWith(cooldownMinutes: m)),
                ),
            ],
          ),
        ],
        if (_needs(v.kind) case final note?) ...[
          const SizedBox(height: Space.xs),
          Text(note, style: context.text.bodySmall),
        ],
        if (v.kind == DeviceTriggerKind.appOpened) ...[
          Text(v.cooldownMinutes == 0 ? 'Every time' : 'At most every ${v.cooldownMinutes} minutes', style: context.text.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final m in const [0, 30, 60, 180, 720])
                ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                  label: Text(m == 0 ? 'Every time' : m < 60 ? '$m min' : '${m ~/ 60} h'),
                  selected: v.cooldownMinutes == m,
                  onSelected: (_) => widget.onChanged(v.copyWith(cooldownMinutes: m)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
