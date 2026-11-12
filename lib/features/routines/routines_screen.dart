import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../assistant/device_events.dart';
import '../assistant/presentation/automation_widgets.dart';
import '../chat/data/chat_controller.dart';
import '../settings/data/settings.dart';
import '../telegram/data/telegram_tools.dart';
import 'routine_runner.dart';
import 'routines.dart';

String _toolLabel(String name) => toolNamed(name)?.label ?? name;

/// Settings → Routines: the user's routines, and where new ones start.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  Future<void> _new(BuildContext context) async {
    final picked = await showAppSheet<Routine>(
      context,
      initialSize: 0.7,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Text('New routine', style: context.text.titleMedium),
          const SizedBox(height: Space.m),
          automationCard(context, [
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: lead(const Icon(Icons.add_rounded)),
              title: const Text('Start from scratch'),
              subtitle: Text('An empty routine you build step by step', style: context.text.bodySmall),
              onTap: () => Navigator.pop(context, Routine(id: '', name: '', createdAt: DateTime.now())),
            ),
          ]),
          const SizedBox(height: Space.l),
          Text('FROM A TEMPLATE', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          automationCard(context, [
            for (final (i, t) in routineTemplates().indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              ListTile(
                titleAlignment: ListTileTitleAlignment.center,
                leading: lead(Icon(t.trigger.kind.icon)),
                title: Text(t.name),
                subtitle: Text('${t.description}\n${t.trigger.describe()} · ${t.steps.length} steps', style: context.text.bodySmall),
                onTap: () => Navigator.pop(context, t),
              ),
            ],
          ]),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineBuilderScreen(template: picked)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineStoreProvider);
    final runner = ref.read(routineRunnerProvider);
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.bg,
        onPressed: () => _new(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New routine'),
      ),
      body: ValueListenableBuilder<Map<String, int>>(
        valueListenable: runner.progress,
        builder: (context, progress, _) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 96),
          children: [
            Text(
              'A routine is a list of steps that runs by hand, at a time, every so often, or when something happens on '
              'the phone: ask the assistant, run a tool, notify you, wait, or continue only if a result says so.',
              style: context.text.bodySmall,
            ),
            if (!s.proactive && routines.any((r) => r.trigger.kind != RoutineTriggerKind.manual))
              Container(
                margin: const EdgeInsets.only(top: Space.m),
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline_rounded, color: AppColors.warning),
                    const SizedBox(width: Space.m),
                    const Expanded(child: Text('Proactivity is off, so routines only run by hand.')),
                    TextButton(onPressed: () => ref.read(settingsProvider.notifier).setProactive(true), child: const Text('Turn on')),
                  ],
                ),
              ),
            const SizedBox(height: Space.m),
            if (routines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Text(
                  'No routines yet. Start from a template, build one from scratch, or ask in chat: '
                  '"every weekday at 7:30 brief me on my calendar and unread DMs".',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
              ),
            for (final r in routines)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.l),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.l),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineBuilderScreen(routineId: r.id))),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xs, Space.m),
                      child: Row(
                        children: [
                          ...leadRow(Icon(r.trigger.kind.icon, color: r.enabled ? AppColors.accent : AppColors.text3), Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: context.text.titleSmall),
                                Text('${r.trigger.describe()} · ${r.steps.length} step${r.steps.length == 1 ? '' : 's'}', style: context.text.bodySmall),
                                if (progress[r.id] case final step?)
                                  Text('Running step ${step + 1}…', style: context.text.labelSmall?.copyWith(color: AppColors.accent))
                                else if (r.history.isNotEmpty)
                                  Text(
                                    '${r.history.first.ok ? 'Ran' : 'Failed'} ${DateFormat('d MMM HH:mm').format(r.history.first.at)} · ${r.runs} runs',
                                    style: context.text.labelSmall?.copyWith(color: r.history.first.ok ? null : AppColors.danger),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: progress.containsKey(r.id) ? 'Stop' : 'Run now',
                            icon: Icon(progress.containsKey(r.id) ? Icons.stop_rounded : Icons.play_arrow_rounded),
                            onPressed: r.steps.isEmpty
                                ? null
                                : () {
                                    if (progress.containsKey(r.id)) return runner.stop(r.id);
                                    unawaited(runner.run(r));
                                    showSnack(context, 'Running "${r.name}"');
                                  },
                          ),
                          Switch(value: r.enabled, onChanged: (v) => ref.read(routineStoreProvider.notifier).update(r.id, (x) => x.copyWith(enabled: v))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Builds or edits one routine. Changes are kept until Save.
class RoutineBuilderScreen extends ConsumerStatefulWidget {
  const RoutineBuilderScreen({super.key, this.routineId, this.template});

  /// An existing routine to edit.
  final String? routineId;

  /// A new routine's starting point.
  final Routine? template;

  @override
  ConsumerState<RoutineBuilderScreen> createState() => _RoutineBuilderScreenState();
}

class _RoutineBuilderScreenState extends ConsumerState<RoutineBuilderScreen> {
  late Routine _r;
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _dirty = false;
  bool get _isNew => widget.routineId == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.routineId == null ? null : ref.read(routineStoreProvider.notifier).byId(widget.routineId!);
    final base = existing ?? widget.template ?? Routine(id: '', name: '', createdAt: DateTime.now());
    _r = base.id.isEmpty
        ? Routine(
            id: RoutineStore.newId(),
            name: base.name,
            description: base.description,
            createdAt: DateTime.now(),
            trigger: base.trigger,
            steps: [for (final s in base.steps) RoutineStep.fromJson({...s.toJson(), 'id': RoutineStore.newStepId()})],
            model: base.model,
            tools: base.tools,
          )
        : base;
    _name = TextEditingController(text: _r.name);
    _description = TextEditingController(text: _r.description);
    _dirty = _isNew;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _change(Routine Function(Routine) f) => setState(() {
    _r = f(_r);
    _dirty = true;
  });

  String? _problem() {
    if (_name.text.trim().isEmpty) return 'Give the routine a name';
    if (_r.steps.isEmpty) return 'Add at least one step';
    for (final (i, s) in _r.steps.indexed) {
      if (s.kind == RoutineStepKind.ask && s.prompt.trim().isEmpty) return 'Step ${i + 1} needs an instruction';
      if (s.kind == RoutineStepKind.tool && s.tool.isEmpty) return 'Step ${i + 1} needs a tool';
    }
    final d = _r.trigger.device;
    if (_r.trigger.kind == RoutineTriggerKind.device && d != null && d.kind.needsPlace && !d.hasPlace) return 'Set the place for the trigger';
    return null;
  }

  Future<bool> _save({bool quiet = false}) async {
    final problem = _problem();
    if (problem != null) {
      showSnack(context, problem, icon: Icons.info_outline_rounded);
      return false;
    }
    final store = ref.read(routineStoreProvider.notifier);
    // Run history and counts may have changed while editing.
    final latest = store.byId(_r.id);
    _r = _r.copyWith(
      name: _name.text.trim(),
      description: _description.text.trim(),
      history: latest?.history,
      runs: latest?.runs,
      lastRunAt: latest?.lastRunAt,
      conversationId: latest?.conversationId,
    );
    await store.put(_r);
    setState(() => _dirty = false);
    if (!quiet && mounted) showSnack(context, 'Saved');
    return true;
  }

  Future<void> _editStep(int? index, {RoutineStepKind? kind}) async {
    final step = index == null ? RoutineStep(id: RoutineStore.newStepId(), kind: kind!) : _r.steps[index];
    final edited = await Navigator.of(context).push<RoutineStep>(
      MaterialPageRoute(builder: (_) => _StepEditor(step: step, number: (index ?? _r.steps.length) + 1, routine: _r)),
    );
    if (edited == null) return;
    _change((r) {
      final steps = [...r.steps];
      index == null ? steps.add(edited) : steps[index] = edited;
      return r.copyWith(steps: steps);
    });
  }

  Future<void> _addStep() async {
    final kind = await showFormSheet<RoutineStepKind>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a step', style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          for (final k in RoutineStepKind.values)
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              contentPadding: EdgeInsets.zero,
              leading: lead(Icon(k.icon)),
              title: Text(k.label),
              subtitle: Text(k.explanation, style: context.text.bodySmall),
              onTap: () => Navigator.pop(context, k),
            ),
        ],
      ),
    );
    if (kind != null) await _editStep(null, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(routineStoreProvider).where((x) => x.id == _r.id).firstOrNull;
    final runner = ref.read(routineRunnerProvider);
    final t = _r.trigger;
    final hasAsk = _r.steps.any((s) => s.kind == RoutineStepKind.ask);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Save your changes?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, 'discard'), child: const Text('Discard')),
              FilledButton(onPressed: () => Navigator.pop(d, 'save'), child: const Text('Save')),
            ],
          ),
        );
        if (!context.mounted || leave == null) return;
        if (leave == 'save' && !await _save(quiet: true)) return;
        setState(() => _dirty = false);
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew && saved == null ? 'New routine' : 'Edit routine'),
          actions: [
            ValueListenableBuilder<Map<String, int>>(
              valueListenable: runner.progress,
              builder: (context, progress, _) => IconButton(
                tooltip: progress.containsKey(_r.id) ? 'Stop' : 'Save and run now',
                icon: Icon(progress.containsKey(_r.id) ? Icons.stop_rounded : Icons.play_arrow_rounded),
                onPressed: () async {
                  if (progress.containsKey(_r.id)) return runner.stop(_r.id);
                  if (!await _save(quiet: true)) return;
                  final r = ref.read(routineStoreProvider.notifier).byId(_r.id);
                  if (r == null) return;
                  if (context.mounted) showSnack(context, 'Running "${r.name}"');
                  await runner.run(r);
                },
              ),
            ),
            if (saved != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirmDelete(context, title: 'Delete "${saved.name}"?', message: 'The routine and its run history are removed.')) return;
                  await ref.read(routineStoreProvider.notifier).remove(saved.id);
                  setState(() => _dirty = false);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
          children: [
            TextField(controller: _name, onChanged: (_) => _dirty = true, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Good morning')),
            const SizedBox(height: Space.m),
            TextField(
              controller: _description,
              onChanged: (_) => _dirty = true,
              decoration: const InputDecoration(labelText: 'What it\'s for (optional)', hintText: 'The assistant reads this in "ask" steps'),
            ),
            const SizedBox(height: Space.xl),
            Text('WHEN', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in RoutineTriggerKind.values)
                  ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    avatar: Icon(k.icon, size: 16, color: AppColors.text),
                    label: Text(k.label),
                    selected: t.kind == k,
                    onSelected: (_) => _change(
                      (r) => r.copyWith(
                        trigger: t.copyWith(kind: k, device: k == RoutineTriggerKind.device ? (t.device ?? const DeviceCondition(kind: DeviceTriggerKind.charging)) : null),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            if (t.kind == RoutineTriggerKind.manual)
              Text('Run it from here, from the Routines page, or ask the assistant to run it.', style: context.text.bodySmall),
            if (t.kind == RoutineTriggerKind.daily) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(t.at),
                onPressed: () async {
                  final p = t.at.split(':');
                  final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                  if (picked != null) {
                    _change((r) => r.copyWith(trigger: t.copyWith(at: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}')));
                  }
                },
              ),
              const SizedBox(height: Space.s),
              Wrap(
                spacing: 4,
                children: [
                  for (final (i, d) in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'].indexed)
                    FilterChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                      showCheckmark: false,
                      label: Text(d),
                      selected: t.days.contains(i + 1),
                      onSelected: (on) {
                        final days = {...t.days};
                        on ? days.add(i + 1) : days.remove(i + 1);
                        if (days.isNotEmpty) _change((r) => r.copyWith(trigger: t.copyWith(days: days)));
                      },
                    ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(t.describe(), style: context.text.bodySmall),
            ],
            if (t.kind == RoutineTriggerKind.interval) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in const [15, 30, 60, 120, 180, 360, 720, 1440])
                    ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                      label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                      selected: t.everyMinutes == m,
                      onSelected: (_) => _change((r) => r.copyWith(trigger: t.copyWith(everyMinutes: m))),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet at night'),
                subtitle: Text('Not between 22:00 and 08:00', style: context.text.bodySmall),
                value: t.quietAtNight,
                onChanged: (v) => _change((r) => r.copyWith(trigger: t.copyWith(quietAtNight: v))),
              ),
            ],
            if (t.kind == RoutineTriggerKind.device)
              DeviceConditionEditor(
                value: t.device ?? const DeviceCondition(kind: DeviceTriggerKind.charging),
                onChanged: (d) => _change((r) => r.copyWith(trigger: t.copyWith(device: d))),
              ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(child: Text('STEPS', style: context.text.labelSmall)),
                Text('Hold and drag to reorder', style: context.text.labelSmall),
              ],
            ),
            const SizedBox(height: Space.s),
            if (_r.steps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Text('No steps yet.', textAlign: TextAlign.center, style: context.text.bodySmall),
              ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _r.steps.length,
              onReorder: (from, to) => _change((r) {
                final steps = [...r.steps];
                final s = steps.removeAt(from);
                steps.insert(to > from ? to - 1 : to, s);
                return r.copyWith(steps: steps);
              }),
              itemBuilder: (context, i) {
                final s = _r.steps[i];
                return Padding(
                  key: ValueKey(s.id),
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.l),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.l),
                      onTap: () => _editStep(i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, 0, Space.s),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(padding: const EdgeInsets.all(Space.s), child: Icon(Icons.drag_indicator_rounded, color: AppColors.text3)),
                            ),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: s.enabled ? AppColors.accentDim : AppColors.surface2,
                              child: Text('${i + 1}', style: context.text.labelSmall),
                            ),
                            const SizedBox(width: Space.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(s.kind.icon, size: 16, color: s.enabled ? AppColors.text2 : AppColors.text3),
                                      const SizedBox(width: 6),
                                      Text(s.kind.label, style: context.text.titleSmall?.copyWith(color: s.enabled ? null : AppColors.text3)),
                                      if (!s.enabled) Text('  · off', style: context.text.labelSmall),
                                    ],
                                  ),
                                  Text(s.summary(_toolLabel), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) => _change((r) {
                                final steps = [...r.steps];
                                switch (v) {
                                  case 'toggle':
                                    steps[i] = s.copyWith(enabled: !s.enabled);
                                  case 'copy':
                                    steps.insert(i + 1, RoutineStep.fromJson({...s.toJson(), 'id': RoutineStore.newStepId()}));
                                  case 'up':
                                    if (i > 0) steps.insert(i - 1, steps.removeAt(i));
                                  case 'down':
                                    if (i < steps.length - 1) steps.insert(i + 1, steps.removeAt(i));
                                  case 'delete':
                                    steps.removeAt(i);
                                }
                                return r.copyWith(steps: steps);
                              }),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'toggle', child: Text(s.enabled ? 'Turn off' : 'Turn on')),
                                const PopupMenuItem(value: 'copy', child: Text('Duplicate')),
                                if (i > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                                if (i < _r.steps.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            OutlinedButton.icon(onPressed: _addStep, icon: const Icon(Icons.add_rounded), label: const Text('Add a step')),
            if (hasAsk) ...[
              const SizedBox(height: Space.xl),
              Text('TOOLS FOR "ASK" STEPS', style: context.text.labelSmall),
              const SizedBox(height: Space.s),
              ToolAllowlistTile(value: _r.tools, onChanged: (v) => _change((r) => r.copyWith(tools: v, allTools: v == null))),
              const SizedBox(height: Space.xl),
              Text('MODEL FOR "ASK" STEPS', style: context.text.labelSmall),
              const SizedBox(height: Space.s),
              AutomationModelTile(value: _r.model, onChanged: (v) => _change((r) => r.copyWith(model: v))),
            ],
            const SizedBox(height: Space.l),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify me when it finishes'),
              subtitle: Text('With the last step\'s result, unless a step already notified. Failures always notify.', style: context.text.bodySmall),
              value: _r.notifyWhenDone,
              onChanged: (v) => _change((r) => r.copyWith(notifyWhenDone: v)),
            ),
            const SizedBox(height: Space.l),
            FilledButton(onPressed: _save, child: const Text('Save')),
            if (saved != null && saved.history.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  Expanded(child: Text('RECENT RUNS', style: context.text.labelSmall)),
                  if (saved.conversationId != null)
                    TextButton.icon(
                      onPressed: () {
                        ref.read(chatControllerProvider.notifier).open(saved.conversationId!);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                      icon: const Icon(Icons.forum_outlined, size: 16),
                      label: const Text('Its conversation'),
                    ),
                ],
              ),
              const SizedBox(height: Space.s),
              automationCard(context, [
                for (final (i, run) in saved.history.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ExpansionTile(
                    leading: Icon(
                      run.ok ? (run.stoppedEarly ? Icons.call_split_rounded : Icons.check_circle_outline_rounded) : Icons.error_outline_rounded,
                      color: run.ok ? AppColors.success : AppColors.danger,
                    ),
                    title: Text(DateFormat('EEE d MMM, HH:mm').format(run.at)),
                    subtitle: Text(
                      run.error ?? (run.stoppedEarly ? 'Stopped by a condition · ${run.trigger}' : run.trigger),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                    children: [
                      for (final st in run.steps)
                        ListTile(
                          titleAlignment: ListTileTitleAlignment.center,
                          dense: true,
                          leading: Icon(
                            st.skipped ? Icons.redo_rounded : (st.ok ? Icons.check_rounded : Icons.close_rounded),
                            size: 18,
                            color: st.skipped ? AppColors.text3 : (st.ok ? AppColors.success : AppColors.danger),
                          ),
                          title: Text('${st.label}${st.skipped ? ' (skipped)' : ''}'),
                          subtitle: st.output.isEmpty
                              ? null
                              : Text(st.output, maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                          trailing: Text('${(st.ms / 1000).toStringAsFixed(1)} s', style: context.text.labelSmall),
                        ),
                    ],
                  ),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// The text a step can use: chips that insert a variable.
class _Variables extends StatelessWidget {
  const _Variables({required this.controller, required this.number});
  final TextEditingController controller;
  final int number;

  void _insert(String v) {
    final sel = controller.selection;
    final text = controller.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(text: text.replaceRange(at, end, v), selection: TextSelection.collapsed(offset: at + v.length));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (v, tip) in [
          if (number > 1) ('{{last}}', 'The previous step\'s result'),
          for (var i = 1; i < number && i <= 4; i++) ('{{step$i}}', 'Step $i\'s result'),
          ('{{trigger}}', 'What started the routine'),
          ('{{date}}', 'Today\'s date'),
          ('{{time}}', 'The time now'),
          ('{{vault:}}', 'A vault item: put its name after the colon'),
        ])
          Tooltip(
            message: tip,
            child: ActionChip(
              label: Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              onPressed: () => _insert(v),
            ),
          ),
      ],
    ),
  );
}

/// Edits one step; pops with the changed step.
class _StepEditor extends ConsumerStatefulWidget {
  const _StepEditor({required this.step, required this.number, required this.routine});
  final RoutineStep step;
  final int number;
  final Routine routine;

  @override
  ConsumerState<_StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends ConsumerState<_StepEditor> {
  late RoutineStep _s = widget.step;
  late final _prompt = TextEditingController(text: _s.prompt);
  late final _title = TextEditingController(text: _s.title);
  late final _body = TextEditingController(text: _s.body);
  late final _value = TextEditingController(text: _s.value);
  late int _waitAmount = _s.seconds % 3600 == 0 ? _s.seconds ~/ 3600 : (_s.seconds % 60 == 0 ? _s.seconds ~/ 60 : _s.seconds);
  late int _waitUnit = _s.seconds % 3600 == 0 ? 3600 : (_s.seconds % 60 == 0 ? 60 : 1);
  final Map<String, TextEditingController> _args = {};
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    _syncArgs();
  }

  void _syncArgs() {
    for (final c in _args.values) {
      c.dispose();
    }
    _args.clear();
    for (final e in _s.args.entries) {
      _args[e.key] = TextEditingController(text: e.value is String ? e.value as String : jsonEncode(e.value));
    }
  }

  @override
  void dispose() {
    for (final c in [_prompt, _title, _body, _value, ..._args.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _schema => (toolNamed(_s.tool)?.parameters['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<String> get _required => [for (final r in (toolNamed(_s.tool)?.parameters['required'] as List? ?? const [])) '$r'];

  Map<String, dynamic> _argsNow() => {
    for (final e in _args.entries)
      if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
  };

  RoutineStep _built() => _s.copyWith(
    prompt: _prompt.text.trim(),
    title: _title.text.trim(),
    body: _body.text.trim(),
    value: _value.text.trim(),
    seconds: (_waitAmount * _waitUnit).clamp(1, 6 * 3600),
    args: _s.kind == RoutineStepKind.tool ? _argsNow() : null,
  );

  Future<void> _pickTool() async {
    final name = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ToolPickerScreen(current: _s.tool)));
    if (name == null || name == _s.tool) return;
    setState(() {
      _s = _s.copyWith(tool: name, args: const {});
      _syncArgs();
    });
  }

  Future<void> _tryTool() async {
    final missing = [for (final r in _required) if ((_args[r]?.text.trim() ?? '').isEmpty) r];
    if (missing.isNotEmpty) {
      showSnack(context, 'Fill in ${missing.join(', ')} first', icon: Icons.info_outline_rounded);
      return;
    }
    final tool = toolNamed(_s.tool);
    if (tool != null && tool.modifiesData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Run it for real?'),
          content: Text('${tool.label} acts for real: whatever it sends or changes happens now. Variables are left empty.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Run')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _trying = true);
    try {
      final args = RoutineRunner.coerceArgs(_s.tool, _argsNow(), (t) => RoutineRunner.fill(t, last: '', outputs: const [], trigger: 'Test from the builder'));
      final out = await ref.read(chatControllerProvider.notifier).runRoutineTool(_s.tool, args, routine: widget.routine);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(out.containsKey('error') ? 'It failed' : 'Result'),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(out),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  Widget _argField(String key, Map<String, dynamic> spec) {
    final c = _args[key] ??= TextEditingController();
    final type = spec['type'];
    final options = spec['enum'] is List ? [for (final o in spec['enum'] as List) '$o'] : null;
    final label = '$key${_required.contains(key) ? ' *' : ''}';
    final help = '${spec['description'] ?? ''}'.trim();
    if (options != null || type == 'boolean') {
      final values = options ?? const ['true', 'false'];
      final current = values.contains(c.text) ? c.text : '';
      return DropdownButtonFormField<String>(
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, helperText: help.isEmpty ? null : help, helperMaxLines: 3),
        items: [
          const DropdownMenuItem(value: '', child: Text('(not set)')),
          for (final v in values) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: (v) => setState(() => c.text = v ?? ''),
      );
    }
    return TextField(
      controller: c,
      minLines: 1,
      maxLines: type == 'string' && (key == 'text' || key == 'prompt' || key == 'body' || key == 'message') ? 6 : 3,
      keyboardType: type == 'integer' || type == 'number' ? const TextInputType.numberWithOptions(signed: true, decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: [
          if (help.isNotEmpty) help,
          if (type == 'array') 'A list: comma-separated, or JSON',
          if (type == 'object') 'JSON',
        ].join(' · '),
        helperMaxLines: 3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final tool = toolNamed(s.tool);
    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${widget.number} · ${s.kind.label}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _built()), child: const Text('Done'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(s.kind.explanation, style: context.text.bodySmall),
          const SizedBox(height: Space.l),
          switch (s.kind) {
            RoutineStepKind.ask => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _prompt,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Instruction',
                    alignLabelWithHint: true,
                    hintText: 'e.g. Summarise my unread DMs and today\'s calendar in 4 lines.',
                  ),
                ),
                _Variables(controller: _prompt, number: widget.number),
                const SizedBox(height: Space.s),
                Text(
                  'The assistant sees the previous step\'s result too. It may use the tools picked for this routine\'s "ask" steps; '
                  'actions follow your approval settings for automatic runs.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
            RoutineStepKind.tool => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                automationCard(context, [
                  ListTile(
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: lead(const Icon(Icons.handyman_outlined)),
                    title: Text(tool?.label ?? 'Pick a tool'),
                    subtitle: tool == null ? null : Text(tool.name, style: context.text.bodySmall),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickTool,
                  ),
                ]),
                if (tool != null) ...[
                  const SizedBox(height: Space.s),
                  Text(tool.description, style: context.text.bodySmall),
                  if (tool.modifiesData)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s),
                      child: Text(
                        'This tool acts. It runs without an approval card each time the routine runs, since you set it up here.',
                        style: context.text.bodySmall?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  const SizedBox(height: Space.l),
                  Text('INPUTS', style: context.text.labelSmall),
                  if (_schema.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.s), child: Text('This tool takes no inputs.', style: context.text.bodySmall)),
                  for (final e in _schema.entries)
                    Padding(padding: const EdgeInsets.only(top: Space.m), child: _argField(e.key, Map<String, dynamic>.from(e.value as Map))),
                  const SizedBox(height: Space.s),
                  Text('Text inputs can use {{last}}, {{step1}}, {{trigger}}, {{date}}, {{time}} and {{vault:Name}}.', style: context.text.bodySmall),
                  const SizedBox(height: Space.l),
                  OutlinedButton.icon(
                    onPressed: _trying ? null : _tryTool,
                    icon: _trying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Try this step now'),
                  ),
                ],
              ],
            ),
            RoutineStepKind.notify => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _title, decoration: InputDecoration(labelText: 'Title', hintText: widget.routine.name.isEmpty ? 'The routine\'s name' : widget.routine.name)),
                _Variables(controller: _title, number: widget.number),
                const SizedBox(height: Space.m),
                TextField(
                  controller: _body,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Text', alignLabelWithHint: true, hintText: 'Empty: the previous step\'s result'),
                ),
                _Variables(controller: _body, number: widget.number),
              ],
            ),
            RoutineStepKind.wait => Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: '$_waitAmount',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Wait'),
                    onChanged: (v) => _waitAmount = (int.tryParse(v) ?? 1).clamp(1, 3600),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('sec')),
                      ButtonSegment(value: 60, label: Text('min')),
                      ButtonSegment(value: 3600, label: Text('hours')),
                    ],
                    selected: {_waitUnit},
                    onSelectionChanged: (v) => setState(() => _waitUnit = v.first),
                  ),
                ),
              ],
            ),
            RoutineStepKind.condition => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Continue only if the previous step\'s result…', style: context.text.titleSmall),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in ConditionTest.values)
                      ChoiceChip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(horizontal: -1, vertical: -3),label: Text(t.label), selected: s.test == t, onSelected: (_) => setState(() => _s = s.copyWith(test: t))),
                  ],
                ),
                if (s.test.needsValue) ...[
                  const SizedBox(height: Space.m),
                  TextField(controller: _value, decoration: const InputDecoration(labelText: 'Text', hintText: 'Not case-sensitive')),
                ],
                const SizedBox(height: Space.l),
                Text('Otherwise', style: context.text.titleSmall),
                const SizedBox(height: Space.s),
                SegmentedButton<ConditionOtherwise>(
                  segments: [for (final o in ConditionOtherwise.values) ButtonSegment(value: o, label: Text(o.label))],
                  selected: {s.otherwise},
                  onSelectionChanged: (v) => setState(() => _s = s.copyWith(otherwise: v.first)),
                ),
              ],
            ),
          },
          if (s.kind == RoutineStepKind.ask || s.kind == RoutineStepKind.tool) ...[
            const SizedBox(height: Space.l),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep going if it fails'),
              subtitle: Text('Off: a failure stops the routine and notifies you', style: context.text.bodySmall),
              value: s.continueOnError,
              onChanged: (v) => setState(() => _s = s.copyWith(continueOnError: v)),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Step is on'),
            subtitle: Text('Off: skipped when the routine runs', style: context.text.bodySmall),
            value: s.enabled,
            onChanged: (v) => setState(() => _s = s.copyWith(enabled: v)),
          ),
        ],
      ),
    );
  }
}
