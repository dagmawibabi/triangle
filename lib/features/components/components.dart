import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../telegram/data/telegram_tools.dart' show ToolOutput;

/// Visual components the assistant can put in a chat on demand (the
/// `show_component` tool): charts, stat tiles, tables, progress, timelines,
/// comparisons and gauges. Settings → Components turns each on or off and
/// picks their palette.
enum ComponentKind {
  chart('Chart', Icons.show_chart_rounded, 'Line, area, bar, horizontal bar, pie and donut charts of one or more series.'),
  stats('Stat tiles', Icons.dashboard_outlined, 'A grid of headline numbers, each with a label and an optional change.'),
  table('Table', Icons.table_chart_outlined, 'Rows and columns that scroll sideways, numbers aligned right.'),
  progress('Progress', Icons.linear_scale_rounded, 'Bars showing how far each item is toward its goal.'),
  timeline('Timeline', Icons.timeline_rounded, 'Events in order, each with a time, a title and details.'),
  comparison('Comparison', Icons.compare_arrows_rounded, 'Options side by side with pros, cons and a score.'),
  gauge('Gauge', Icons.speed_rounded, 'One value on a dial between a minimum and a maximum.');

  const ComponentKind(this.label, this.icon, this.description);
  final String label;
  final IconData icon;
  final String description;
}

/// Colour sets the components draw with.
enum ComponentPalette {
  vivid('Vivid'),
  accent('Accent'),
  pastel('Pastel'),
  mono('Monochrome');

  const ComponentPalette(this.label);
  final String label;

  List<Color> colors(Color tint) => switch (this) {
    vivid => const [Color(0xFF4F7CFF), Color(0xFFFF7A59), Color(0xFF2EC4B6), Color(0xFFFFB84D), Color(0xFFA06CF5), Color(0xFFEF476F), Color(0xFF06D6A0), Color(0xFF118AB2)],
    ComponentPalette.accent => [tint, const Color(0xFFFF7A59), const Color(0xFF2EC4B6), const Color(0xFFFFB84D), const Color(0xFFA06CF5), const Color(0xFFEF476F)],
    pastel => const [Color(0xFF9DB4FF), Color(0xFFFFB5A0), Color(0xFF8EDFD7), Color(0xFFFFD99A), Color(0xFFCDB4F7), Color(0xFFF7A1B6)],
    mono => [for (final a in [1.0, 0.78, 0.6, 0.45, 0.32, 0.22]) tint.withValues(alpha: a)],
  };
}

@immutable
class ComponentPrefs {
  const ComponentPrefs({this.disabled = const {}, this.palette = ComponentPalette.vivid, this.curved = true, this.showValues = true});
  final Set<ComponentKind> disabled;
  final ComponentPalette palette;

  /// Line and area charts draw smooth curves.
  final bool curved;

  /// Bars and points carry their value.
  final bool showValues;

  bool isOn(ComponentKind k) => !disabled.contains(k);

  ComponentPrefs copyWith({Set<ComponentKind>? disabled, ComponentPalette? palette, bool? curved, bool? showValues}) => ComponentPrefs(
    disabled: disabled ?? this.disabled,
    palette: palette ?? this.palette,
    curved: curved ?? this.curved,
    showValues: showValues ?? this.showValues,
  );

  Map<String, dynamic> toJson() => {
    'disabled': [for (final k in disabled) k.name],
    'palette': palette.name,
    'curved': curved,
    'values': showValues,
  };

  factory ComponentPrefs.fromJson(Map j) => ComponentPrefs(
    disabled: {
      for (final n in _list(j['disabled']))
        if (ComponentKind.values.asNameMap()['$n'] case final k?) k,
    },
    palette: ComponentPalette.values.asNameMap()[j['palette']] ?? ComponentPalette.vivid,
    curved: j['curved'] != false,
    showValues: j['values'] != false,
  );
}

class ComponentPrefsStore extends Notifier<ComponentPrefs> {
  static const _key = 'components.v1';
  late Future<void> ready;

  @override
  ComponentPrefs build() {
    ready = _load();
    return const ComponentPrefs();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) state = ComponentPrefs.fromJson(jsonDecode(raw) as Map);
    } catch (_) {}
  }

  Future<void> _set(ComponentPrefs p) async {
    await ready;
    state = p;
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(p.toJson()));
  }

  Future<void> setEnabled(ComponentKind k, bool on) =>
      _set(state.copyWith(disabled: on ? ({...state.disabled}..remove(k)) : {...state.disabled, k}));
  Future<void> setPalette(ComponentPalette p) => _set(state.copyWith(palette: p));
  Future<void> setCurved(bool v) => _set(state.copyWith(curved: v));
  Future<void> setShowValues(bool v) => _set(state.copyWith(showValues: v));
}

final componentPrefsProvider = NotifierProvider<ComponentPrefsStore, ComponentPrefs>(ComponentPrefsStore.new);

/// Example data for each component: the settings previews, and what the
/// tool's errors point to.
const componentSamples = <ComponentKind, Map<String, dynamic>>{
  ComponentKind.chart: {
    'component': 'chart',
    'title': 'Weekly messages',
    'chart_type': 'area',
    'labels': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    'series': [
      {'name': 'Received', 'values': [42, 58, 51, 74, 66, 39, 47]},
      {'name': 'Sent', 'values': [18, 25, 22, 31, 40, 12, 20]},
    ],
  },
  ComponentKind.stats: {
    'component': 'stats',
    'title': 'This month',
    'items': [
      {'label': 'Revenue', 'value': r'$12.4k', 'delta': 8.2},
      {'label': 'Orders', 'value': '318', 'delta': -3.1},
      {'label': 'New users', 'value': '1,204', 'delta': 14},
      {'label': 'Refunds', 'value': '6', 'delta': -40, 'up_is_bad': true},
    ],
  },
  ComponentKind.table: {
    'component': 'table',
    'title': 'Top channels',
    'columns': ['Channel', 'Posts', 'Views'],
    'rows': [
      ['Tech News', '42', '18.2k'],
      ['Daily Design', '17', '9.4k'],
      ['Crypto Wire', '65', '31.0k'],
    ],
  },
  ComponentKind.progress: {
    'component': 'progress',
    'title': 'Goals',
    'items': [
      {'label': 'Read 12 books', 'value': 7, 'max': 12},
      {'label': 'Save \$2,000', 'value': 1450, 'max': 2000, 'unit': r'$'},
      {'label': 'Run 100 km', 'value': 100, 'max': 100, 'unit': 'km'},
    ],
  },
  ComponentKind.timeline: {
    'component': 'timeline',
    'title': 'Release',
    'items': [
      {'time': 'Mon 09:00', 'title': 'Code freeze', 'detail': 'Only fixes after this.'},
      {'time': 'Wed 14:00', 'title': 'Beta', 'detail': 'Testers get the build.', 'status': 'done'},
      {'time': 'Fri 10:00', 'title': 'Launch', 'status': 'next'},
    ],
  },
  ComponentKind.comparison: {
    'component': 'comparison',
    'title': 'Which phone?',
    'options': [
      {'name': 'Phone A', 'score': 8.5, 'pros': ['Great camera', 'Light'], 'cons': ['Pricey']},
      {'name': 'Phone B', 'score': 7.2, 'pros': ['Battery', 'Cheap'], 'cons': ['Slow charging', 'Heavy']},
    ],
    'verdict': 'Phone A, unless battery life matters most.',
  },
  ComponentKind.gauge: {
    'component': 'gauge',
    'title': 'Air quality',
    'value': 62,
    'min': 0,
    'max': 200,
    'label': 'AQI · Moderate',
  },
};

/// A list from what a model sent: a list, a JSON array as text, or text
/// split on new lines, semicolons or commas.
List<Object?> _list(Object? v) {
  if (v == null) return const [];
  if (v is List) return v;
  if (v is Map) return [v];
  final s = '$v'.trim();
  if (s.isEmpty) return const [];
  if (s.startsWith('[')) {
    try {
      final j = jsonDecode(s);
      if (j is List) return j;
    } catch (_) {}
  }
  final bullet = RegExp(r'^[-*•]\s*');
  return [
    for (final p in s.split(RegExp(r'\n|;|,(?![^(]*\))')))
      if (p.trim().replaceFirst(bullet, '').isNotEmpty) p.trim().replaceFirst(bullet, ''),
  ];
}

String _s(Object? v) => v == null ? '' : '$v'.trim();
double? _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[,\s%$€£]'), ''));

/// Runs show_component: checks the data fits the component and gives the
/// card a clean copy. The model gets a short note, not the data back.
Future<ToolOutput> runShowComponent(ComponentPrefs prefs, Map<String, dynamic> a) async {
  final kind = ComponentKind.values.asNameMap()[_s(a['component']).toLowerCase()];
  final on = [for (final k in ComponentKind.values) if (prefs.isOn(k)) k.name];
  if (kind == null) return ToolOutput({'error': 'Unknown component. Use one of: ${on.join(', ')}.'});
  if (!prefs.isOn(kind)) {
    return ToolOutput({'error': 'The user turned off the ${kind.label} component. Use ${on.isEmpty ? 'plain text or a markdown table' : 'one of: ${on.join(', ')}'}.'});
  }
  final out = <String, dynamic>{'component': kind.name, if (_s(a['title']).isNotEmpty) 'title': _s(a['title']), if (_s(a['subtitle']).isNotEmpty) 'subtitle': _s(a['subtitle'])};
  String? problem;
  switch (kind) {
    case ComponentKind.chart:
      final type = _s(a['chart_type']).isEmpty ? 'line' : _s(a['chart_type']).toLowerCase();
      const types = {'line', 'area', 'bar', 'hbar', 'pie', 'donut'};
      final labels = [for (final l in _list(a['labels'])) _s(l)];
      final series = [
        for (final s in _list(a['series']))
          if (s is Map) {'name': _s(s['name']), 'values': [for (final v in _list(s['values'])) _n(v) ?? 0]},
      ];
      if (!types.contains(type)) {
        problem = 'chart_type must be one of ${types.join(', ')}';
      } else if (series.isEmpty || (series.first['values'] as List).isEmpty) {
        problem = 'Give series: [{name, values: [numbers]}] and labels';
      } else {
        out.addAll({'chart_type': type, 'labels': labels, 'series': series, if (_s(a['unit']).isNotEmpty) 'unit': _s(a['unit'])});
      }
    case ComponentKind.stats || ComponentKind.progress || ComponentKind.timeline:
      final items = [for (final i in _list(a['items'])) if (i is Map) Map<String, dynamic>.from(i)];
      if (items.isEmpty) problem = 'Give items';
      out['items'] = items.take(kind == ComponentKind.timeline ? 30 : 12).toList();
    case ComponentKind.table:
      final cols = [for (final c in _list(a['columns'])) _s(c)];
      final rows = [
        for (final r in _list(a['rows']))
          if (r is List) [for (final c in r) _s(c)] else if (r is Map) [for (final c in cols) _s(r[c])],
      ];
      if (rows.isEmpty) problem = 'Give columns and rows';
      out.addAll({'columns': cols, 'rows': rows.take(200).toList()});
    case ComponentKind.comparison:
      final options = [for (final o in _list(a['options'])) if (o is Map) Map<String, dynamic>.from(o)];
      if (options.length < 2) problem = 'Give at least two options';
      out.addAll({'options': options.take(4).toList(), if (_s(a['verdict']).isNotEmpty) 'verdict': _s(a['verdict'])});
    case ComponentKind.gauge:
      final value = _n(a['value']);
      if (value == null) problem = 'Give value (and min, max)';
      out.addAll({'value': value, 'min': _n(a['min']) ?? 0, 'max': _n(a['max']) ?? 100, if (_s(a['label']).isNotEmpty) 'label': _s(a['label']), if (_s(a['unit']).isNotEmpty) 'unit': _s(a['unit'])});
  }
  if (problem != null) {
    return ToolOutput({'error': '$problem. Example: ${jsonEncode(componentSamples[kind])}'});
  }
  return ToolOutput(
    {'shown': kind.name, 'note': 'The user sees it as a card. Don\'t repeat its numbers; add only what it doesn\'t show.'},
    full: out,
  );
}
