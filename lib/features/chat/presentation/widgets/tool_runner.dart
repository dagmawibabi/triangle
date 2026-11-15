import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../settings/data/settings.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../data/chat_controller.dart';
import '../../domain/chat_models.dart';
import 'rich_results.dart' show richResultFor;
import 'tool_result_view.dart';
import 'tool_card.dart' show toolIcon;

/// A form for one tool's inputs, built from its JSON schema, that runs it
/// for real (your tap is the approval) and shows the result card. Used by a
/// tool sheet's "Try it" tab and by the /tool command.
class ToolTryPanel extends ConsumerStatefulWidget {
  const ToolTryPanel({super.key, required this.tool, this.initial = const {}});
  final TelegramTool tool;
  final Map<String, dynamic> initial;

  @override
  ConsumerState<ToolTryPanel> createState() => _ToolTryPanelState();
}

class _ToolTryPanelState extends ConsumerState<ToolTryPanel> {
  final _text = <String, TextEditingController>{};
  final _choice = <String, Object?>{};
  late final _json = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(widget.initial));
  bool _asJson = false;
  bool _running = false;
  String? _problem;
  ToolPart? _last;

  Map<String, dynamic> get _props => Map<String, dynamic>.from((widget.tool.parameters['properties'] as Map?) ?? const {});
  Set<String> get _required => {for (final r in (widget.tool.parameters['required'] as List? ?? const [])) '$r'};

  @override
  void initState() {
    super.initState();
    for (final e in _props.entries) {
      final schema = e.value is Map ? e.value as Map : const {};
      final v = widget.initial[e.key];
      if (schema['enum'] is List || schema['type'] == 'boolean') {
        _choice[e.key] = v;
      } else {
        _text[e.key] = TextEditingController(text: _show(v, schema));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _json.dispose();
    super.dispose();
  }

  static String _show(Object? v, Map schema) {
    if (v == null) return '';
    if (v is List && (schema['items'] as Map?)?['type'] == 'string') return v.join(', ');
    if (v is Map || v is List) return jsonEncode(v);
    return '$v';
  }

  /// The inputs as the tool takes them; throws FormatException on bad JSON.
  Map<String, dynamic> _args() {
    if (_asJson) {
      final j = jsonDecode(_json.text.trim().isEmpty ? '{}' : _json.text);
      if (j is! Map) throw const FormatException('The inputs must be a JSON object.');
      return Map<String, dynamic>.from(j);
    }
    final out = <String, dynamic>{};
    for (final e in _props.entries) {
      final schema = e.value is Map ? e.value as Map : const {};
      if (_choice.containsKey(e.key)) {
        if (_choice[e.key] != null) out[e.key] = _choice[e.key];
        continue;
      }
      final raw = _text[e.key]!.text.trim();
      if (raw.isEmpty) continue;
      final type = schema['type'];
      out[e.key] = switch (type) {
        'integer' => int.tryParse(raw) ?? (throw FormatException('${e.key} must be a whole number.')),
        'number' => num.tryParse(raw) ?? (throw FormatException('${e.key} must be a number.')),
        'array' when !raw.startsWith('[') && ((schema['items'] as Map?)?['type'] == 'string' || (schema['items'] as Map?)?['type'] == 'integer') => [
          for (final p in raw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty))
            (schema['items'] as Map)['type'] == 'integer' ? (int.tryParse(p) ?? p) : p,
        ],
        'array' || 'object' => jsonDecode(raw),
        _ when schema['type'] == null && (raw.startsWith('{') || raw.startsWith('[')) => jsonDecode(raw),
        _ => raw,
      };
    }
    return out;
  }

  void _toggleJson(bool on) {
    setState(() {
      _problem = null;
      if (on) {
        try {
          _json.text = const JsonEncoder.withIndent('  ').convert(_args());
        } catch (_) {}
      } else {
        try {
          final j = Map<String, dynamic>.from(jsonDecode(_json.text) as Map);
          for (final e in _props.entries) {
            final schema = e.value is Map ? e.value as Map : const {};
            if (_choice.containsKey(e.key)) {
              _choice[e.key] = j[e.key];
            } else {
              _text[e.key]!.text = _show(j[e.key], schema);
            }
          }
        } catch (_) {}
      }
      _asJson = on;
    });
  }

  Future<void> _run({bool inChat = false}) async {
    final tool = widget.tool;
    Map<String, dynamic> args;
    try {
      args = _args();
    } on FormatException catch (e) {
      setState(() => _problem = e.message);
      return;
    }
    final missing = _required.where((r) => args[r] == null || (args[r] is String && (args[r] as String).isEmpty)).toList();
    if (missing.isNotEmpty) {
      setState(() => _problem = 'Fill in ${missing.join(', ')}.');
      return;
    }
    if (tool.modifiesData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tool.destructive ? 'Run ${tool.label.toLowerCase()}? It can\'t be undone.' : 'Run it for real?'),
          content: Text(
            tool.destructive
                ? 'This deletes, removes or spends something. It runs exactly as filled in.'
                : '${tool.label} changes or sends something. It runs now, exactly as filled in.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: tool.destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Run'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _running = true;
      _problem = null;
    });
    try {
      final controller = ref.read(chatControllerProvider.notifier);
      if (inChat) {
        final part = await controller.runToolInChat(tool.name, args);
        if (!mounted) return;
        if (part.status == ToolStatus.error && part.result != null && part.result!.contains('Wait for the answer')) {
          setState(() => _problem = 'Wait for the answer in this chat to finish.');
          return;
        }
        // Back to the chat, where the call's card now is.
        Navigator.of(context).popUntil((r) => r is! PopupRoute);
        return;
      }
      final part = await controller.runToolManually(tool.name, args);
      if (mounted) setState(() => _last = part);
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final settings = ref.watch(settingsProvider);
    final on = tool.isOn(settings);
    final props = _props;
    final last = _last;
    Map<String, dynamic>? result;
    if (last?.result != null) {
      try {
        result = Map<String, dynamic>.from(jsonDecode(last!.result!) as Map);
      } catch (_) {}
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!on)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              settings.readOnlyMode && tool.modifiesData
                  ? 'Read-only mode is on, so this tool can\'t run.'
                  : 'This tool is turned off in Settings → Tools; turn it on to run it.',
              style: context.text.bodySmall?.copyWith(color: AppColors.warning),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                props.isEmpty ? 'Takes no inputs.' : 'Inputs${_required.isEmpty ? '' : ' · * required'}',
                style: context.text.labelSmall,
              ),
            ),
            if (props.isNotEmpty) ...[
              Text('JSON', style: context.text.labelSmall),
              Switch(value: _asJson, onChanged: _toggleJson),
            ],
          ],
        ),
        if (_asJson)
          TextField(
            controller: _json,
            maxLines: 12,
            minLines: 4,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: const InputDecoration(hintText: '{ }', isDense: true),
          )
        else
          for (final e in props.entries) _field(context, e.key, e.value is Map ? e.value as Map : const {}),
        if (_problem != null) ...[
          const SizedBox(height: Space.s),
          Text(_problem!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: tool.destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
                onPressed: !on || _running ? null : _run,
                icon: _running
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_running ? 'Running…' : (last == null ? 'Run here' : 'Run again')),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: !on || _running ? null : () => _run(inChat: true),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Run in chat'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(
            'Here shows the result below. In chat adds the call to this conversation, so the assistant can use its result.',
            style: context.text.labelSmall,
          ),
        ),
        if (last != null) ...[
          const SizedBox(height: Space.l),
          Row(
            children: [
              Icon(
                last.status == ToolStatus.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                size: 16,
                color: last.status == ToolStatus.error ? AppColors.danger : AppColors.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${last.status == ToolStatus.error ? 'Failed' : 'Done'}${last.durationMs == null ? '' : ' in ${(last.durationMs! / 1000).toStringAsFixed(2)} s'}',
                  style: context.text.labelMedium,
                ),
              ),
              IconButton(
                tooltip: 'Copy result',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: last.full ?? last.result ?? ''));
                  showSnack(context, 'Result copied');
                },
              ),
            ],
          ),
          if (richResultFor(last) case final rich?) ...[rich, const SizedBox(height: Space.s)],
          if (result != null) ToolResultView(name: tool.name, json: result),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, String name, Map schema) {
    final req = _required.contains(name);
    final label = '$name${req ? ' *' : ''}';
    final help = '${schema['description'] ?? ''}'.trim();
    final type = schema['type'];
    Widget field;
    if (schema['enum'] is List) {
      final options = [for (final o in schema['enum'] as List) o];
      // As wide as its longest choice, not the whole sheet.
      field = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.only(left: Space.m, right: Space.xs),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: AppColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Object?>(
                value: options.contains(_choice[name]) ? _choice[name] : null,
                isDense: true,
                borderRadius: BorderRadius.circular(Radii.m),
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                hint: Text(req ? 'Choose' : '— not set —', style: context.text.bodyMedium?.copyWith(color: AppColors.text3)),
                items: [
                  if (!req) const DropdownMenuItem<Object?>(value: null, child: Text('— not set —')),
                  for (final o in options) DropdownMenuItem<Object?>(value: o, child: Text('$o')),
                ],
                onChanged: (v) => setState(() => _choice[name] = v),
              ),
            ),
          ),
        ],
      );
    } else if (type == 'boolean') {
      field = Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(fontFamily: 'monospace'))),
          SegmentedButton<Object?>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: null, label: Text('—')),
              ButtonSegment(value: true, label: Text('true')),
              ButtonSegment(value: false, label: Text('false')),
            ],
            selected: {_choice[name]},
            onSelectionChanged: (v) => setState(() => _choice[name] = v.first),
          ),
        ],
      );
    } else {
      final itemsType = (schema['items'] as Map?)?['type'];
      final complex = type == 'object' || (type == 'array' && itemsType != 'string' && itemsType != 'integer') || type == null;
      field = TextField(
        controller: _text[name],
        autocorrect: false,
        minLines: 1,
        maxLines: complex ? 6 : 3,
        keyboardType: type == 'integer' || type == 'number' ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        style: complex ? const TextStyle(fontFamily: 'monospace', fontSize: 12.5) : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          hintText: switch (type) {
            'array' when itemsType == 'string' || itemsType == 'integer' => 'Comma separated',
            'array' => '[ … ] JSON',
            'object' => '{ … } JSON',
            'integer' => 'Whole number',
            'number' => 'Number',
            _ => null,
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          if (help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 2),
              child: Text(help, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
            ),
        ],
      ),
    );
  }
}

// ---- /tool -------------------------------------------------------------------------------

/// The /tool command: search every tool, read about it, and run it.
Future<void> showToolPicker(BuildContext context, {String query = ''}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 1,
    builder: (context, scroll) => _ToolPicker(scroll: scroll, query: query),
  ),
);

class _ToolPicker extends ConsumerStatefulWidget {
  const _ToolPicker({required this.scroll, required this.query});
  final ScrollController scroll;
  final String query;

  @override
  ConsumerState<_ToolPicker> createState() => _ToolPickerState();
}

class _ToolPickerState extends ConsumerState<_ToolPicker> {
  late final _search = TextEditingController(text: widget.query);
  TelegramTool? _picked;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    final exact = toolNamed(widget.query.trim());
    if (exact != null) _picked = exact;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return picked == null ? _list(context) : _detail(context, picked);
  }

  Widget _list(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final q = _search.text.trim().toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final hits = [
      for (final t in telegramTools)
        if (words.every((w) => t.name.contains(w) || t.label.toLowerCase().contains(w) || t.category.label.toLowerCase().contains(w) || (q.length > 3 && t.description.toLowerCase().contains(w)))) t,
    ]..sort((a, b) {
        final an = a.name.startsWith(q) ? 0 : 1, bn = b.name.startsWith(q) ? 0 : 1;
        return an != bn ? an - bn : a.name.compareTo(b.name);
      });
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
      children: [
        Text('Run a tool', style: context.text.titleLarge),
        Text('${telegramTools.length} tools. Pick one to read about it and run it with your own inputs.', style: context.text.bodySmall),
        const SizedBox(height: Space.m),
        TextField(
          controller: _search,
          autofocus: widget.query.isEmpty,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: 'Search by name, label or group',
            suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: _search.clear),
          ),
        ),
        const SizedBox(height: Space.s),
        Text('${hits.length} match${hits.length == 1 ? '' : 'es'}', style: context.text.labelSmall),
        for (final t in hits.take(150))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(toolIcon(t.name), color: t.isOn(settings) ? AppColors.text2 : AppColors.text3),
            title: Text(t.name, style: TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: t.isOn(settings) ? null : AppColors.text3)),
            subtitle: Text('${t.label} · ${t.category.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.destructive) Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger) else if (t.modifiesData) Icon(Icons.edit_outlined, size: 15, color: AppColors.warning),
                Icon(Icons.chevron_right_rounded, color: AppColors.text3),
              ],
            ),
            onTap: () => setState(() => _picked = t),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context, TelegramTool t) {
    Widget pill(String text, [Color? c]) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (c ?? AppColors.text2).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c ?? AppColors.text2)),
    );
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            IconButton(tooltip: 'All tools', onPressed: () => setState(() => _picked = null), icon: const Icon(Icons.arrow_back_rounded)),
            Icon(toolIcon(t.name), color: AppColors.accent),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.label, style: context.text.titleMedium),
                  Text(t.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            pill(t.category.label),
            pill(t.cost.label),
            pill(t.access.label, t.destructive ? AppColors.danger : (t.modifiesData ? AppColors.warning : AppColors.success)),
            if (t.requiresApproval) pill('Asks the assistant first'),
          ],
        ),
        const SizedBox(height: Space.m),
        Text(t.description, style: context.text.bodySmall?.copyWith(height: 1.45)),
        const Divider(height: Space.xxl),
        ToolTryPanel(key: ValueKey(t.name), tool: t),
      ],
    );
  }
}
