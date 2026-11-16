import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../telegram/data/telegram_tools.dart' show ToolOutput;

/// Visual components the assistant can put in a chat on demand (the
/// `show_component` tool): charts, numbers, lists and plans, and cards.
/// Settings → Components turns each on or off and picks their palette.
enum ComponentKind {
  // Charts
  chart('Chart', Icons.show_chart_rounded, 'Line, area, bar, horizontal bar, pie and donut charts of one or more series.', ComponentGroup.charts),
  radar('Radar', Icons.radar_rounded, 'A spider web of scores on several axes, one shape per thing compared.', ComponentGroup.charts),
  heatmap('Heatmap', Icons.grid_on_rounded, 'A grid of cells shaded by value: activity by day and hour, scores by row and column.', ComponentGroup.charts),
  funnel('Funnel', Icons.filter_alt_outlined, 'Stages that narrow, with how many made it through each step.', ComponentGroup.charts),
  breakdown('Breakdown', Icons.stacked_bar_chart_rounded, 'One bar split into its parts, with each part\'s share.', ComponentGroup.charts),
  // Numbers
  metric('Metric', Icons.insights_rounded, 'One headline number, its change and a sparkline of its trend.', ComponentGroup.numbers),
  stats('Stat tiles', Icons.dashboard_outlined, 'A grid of headline numbers, each with a label and an optional change.', ComponentGroup.numbers),
  gauge('Gauge', Icons.speed_rounded, 'One value on a dial between a minimum and a maximum.', ComponentGroup.numbers),
  rings('Rings', Icons.donut_large_rounded, 'Up to four goals as rings inside each other, like activity rings.', ComponentGroup.numbers),
  leaderboard('Leaderboard', Icons.emoji_events_outlined, 'A ranking with medals for the top three and a bar for each.', ComponentGroup.numbers),
  // Lists & plans
  table('Table', Icons.table_chart_outlined, 'Rows and columns that scroll sideways, numbers aligned right.', ComponentGroup.lists),
  checklist('Checklist', Icons.checklist_rounded, 'Things to do or bring, ticked off, with how many are done.', ComponentGroup.lists),
  steps('Steps', Icons.format_list_numbered_rounded, 'A how-to: numbered steps, each with a title and details.', ComponentGroup.lists),
  timeline('Timeline', Icons.timeline_rounded, 'Events in order, each with a time, a title and details.', ComponentGroup.lists),
  progress('Progress', Icons.linear_scale_rounded, 'Bars showing how far each item is toward its goal.', ComponentGroup.lists),
  board('Board', Icons.view_kanban_outlined, 'Columns of cards, like a to do, doing, done board.', ComponentGroup.lists),
  // Cards
  comparison('Comparison', Icons.compare_arrows_rounded, 'Options side by side with pros, cons and a score.', ComponentGroup.cards),
  callout('Callout', Icons.campaign_outlined, 'A note that stands out: a tip, a warning, good news or something to watch.', ComponentGroup.cards),
  facts('Fact sheet', Icons.badge_outlined, 'Key facts about one thing, label by value, under a big emoji.', ComponentGroup.cards),
  receipt('Receipt', Icons.receipt_long_outlined, 'Line items with quantities and prices, tax, tip and the total, or a bill split.', ComponentGroup.cards),
  countdown('Countdown', Icons.hourglass_bottom_rounded, 'Days, hours, minutes and seconds to a moment, ticking live.', ComponentGroup.cards);

  const ComponentKind(this.label, this.icon, this.description, this.group);
  final String label;
  final IconData icon;
  final String description;
  final ComponentGroup group;
}

/// How Settings → Components sorts them.
enum ComponentGroup {
  charts('Charts'),
  numbers('Numbers'),
  lists('Lists & plans'),
  cards('Cards');

  const ComponentGroup(this.label);
  final String label;
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
  ComponentKind.radar: {
    'component': 'radar',
    'title': 'Laptops compared',
    'labels': ['Speed', 'Battery', 'Screen', 'Weight', 'Price'],
    'series': [
      {'name': 'Air', 'values': [7, 9, 7, 9, 6]},
      {'name': 'Pro', 'values': [10, 7, 9, 6, 4]},
    ],
    'max': 10,
  },
  ComponentKind.heatmap: {
    'component': 'heatmap',
    'title': 'When you chat',
    'columns': ['6a', '9a', '12p', '3p', '6p', '9p'],
    'rows': [
      {'label': 'Mon', 'values': [1, 4, 6, 5, 8, 9]},
      {'label': 'Tue', 'values': [0, 5, 7, 4, 6, 7]},
      {'label': 'Wed', 'values': [2, 6, 3, 6, 9, 10]},
      {'label': 'Thu', 'values': [1, 3, 5, 7, 5, 6]},
      {'label': 'Fri', 'values': [0, 2, 4, 6, 10, 8]},
    ],
  },
  ComponentKind.funnel: {
    'component': 'funnel',
    'title': 'Sign-ups this week',
    'items': [
      {'label': 'Visited', 'value': 12400},
      {'label': 'Started sign-up', 'value': 3100},
      {'label': 'Verified email', 'value': 1850},
      {'label': 'Paid', 'value': 420},
    ],
  },
  ComponentKind.breakdown: {
    'component': 'breakdown',
    'title': 'Where the money went',
    'unit': r'$',
    'items': [
      {'label': 'Rent', 'value': 1200},
      {'label': 'Food', 'value': 540},
      {'label': 'Transport', 'value': 180},
      {'label': 'Fun', 'value': 260},
      {'label': 'Other', 'value': 120},
    ],
  },
  ComponentKind.metric: {
    'component': 'metric',
    'title': 'Followers',
    'value': '24.8k',
    'label': 'across your channels',
    'delta': 12.4,
    'trend': [18.2, 18.9, 19.4, 20.1, 21.5, 22.0, 23.6, 24.8],
    'hint': 'Best week since March',
  },
  ComponentKind.rings: {
    'component': 'rings',
    'title': 'Today',
    'items': [
      {'label': 'Move', 'value': 420, 'max': 600, 'unit': 'kcal'},
      {'label': 'Exercise', 'value': 28, 'max': 30, 'unit': 'min'},
      {'label': 'Stand', 'value': 12, 'max': 12, 'unit': 'h'},
    ],
  },
  ComponentKind.leaderboard: {
    'component': 'leaderboard',
    'title': 'Most active in the group',
    'unit': 'msgs',
    'items': [
      {'name': 'Abebe', 'value': 412, 'subtitle': 'mostly memes'},
      {'name': 'Sara', 'value': 389},
      {'name': 'Dawit', 'value': 251},
      {'name': 'Hana', 'value': 198},
      {'name': 'Yonas', 'value': 77},
    ],
  },
  ComponentKind.checklist: {
    'component': 'checklist',
    'title': 'Trip packing',
    'items': [
      {'text': 'Passport', 'done': true},
      {'text': 'Charger and adapter', 'done': true},
      {'text': 'Sunscreen', 'note': 'SPF 50'},
      {'text': 'Book for the flight'},
    ],
  },
  ComponentKind.steps: {
    'component': 'steps',
    'title': 'Make cold brew',
    'items': [
      {'title': 'Grind coarse', 'detail': '100 g of beans, like breadcrumbs.'},
      {'title': 'Steep', 'detail': 'Stir into 1 L of cold water; leave 16 hours in the fridge.'},
      {'title': 'Strain', 'detail': 'Through a paper filter. Keeps a week.'},
    ],
  },
  ComponentKind.board: {
    'component': 'board',
    'title': 'Launch',
    'lanes': [
      {
        'name': 'To do',
        'cards': [
          {'title': 'Pick a launch date', 'tags': ['urgent'], 'due': 'Today', 'who': 'Sara Tesfaye'},
          {'title': 'Write the announcement', 'detail': 'Short, with one screenshot', 'tags': ['copy'], 'who': 'Abel'},
        ],
      },
      {
        'name': 'Doing',
        'cards': [
          {'title': 'Landing page', 'detail': 'Hero and pricing left', 'tags': ['design', 'web'], 'due': 'Fri', 'who': 'Hana M'},
        ],
      },
      {
        'name': 'Done',
        'cards': [
          {'title': 'Logo', 'tags': ['design']},
          'Domain',
        ],
      },
    ],
  },
  ComponentKind.callout: {
    'component': 'callout',
    'tone': 'tip',
    'title': 'Quick tip',
    'text': 'Long-press any message to save it to a folder, and ask me to sum up a folder any time.',
  },
  ComponentKind.facts: {
    'component': 'facts',
    'emoji': '🗼',
    'title': 'Eiffel Tower',
    'subtitle': 'Paris, France',
    'items': [
      {'label': 'Height', 'value': '330 m'},
      {'label': 'Opened', 'value': '1889'},
      {'label': 'Visitors', 'value': '~6 million a year'},
      {'label': 'Steps', 'value': '674 to the second floor'},
    ],
  },
  ComponentKind.receipt: {
    'component': 'receipt',
    'title': 'Dinner',
    'subtitle': 'Split four ways',
    'currency': r'$',
    'items': [
      {'name': 'Pizza', 'qty': 2, 'price': 14.5},
      {'name': 'Salad', 'qty': 1, 'price': 9},
      {'name': 'Drinks', 'qty': 4, 'price': 3.25},
    ],
    'tax': 8,
    'tip': 15,
    'split': 4,
  },
  ComponentKind.countdown: {
    'component': 'countdown',
    'title': 'New Year',
    'target': '2027-01-01T00:00:00',
    'label': 'until midnight',
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
    case ComponentKind.radar:
      final labels = [for (final l in _list(a['labels'])) _s(l)];
      final series = [
        for (final s in _list(a['series']))
          if (s is Map) {'name': _s(s['name']), 'values': [for (final v in _list(s['values'])) _n(v) ?? 0]},
      ];
      if (labels.length < 3) {
        problem = 'Give at least three labels (the axes)';
      } else if (series.isEmpty) {
        problem = 'Give series: [{name, values: [one number per label]}]';
      } else {
        out.addAll({'labels': labels.take(10).toList(), 'series': series.take(4).toList(), 'max': ?_n(a['max'])});
      }
    case ComponentKind.heatmap:
      final cols = [for (final c in _list(a['columns'])) _s(c)];
      final rows = [
        for (final r in _list(a['rows']))
          if (r is Map)
            {'label': _s(r['label']), 'values': [for (final v in _list(r['values'])) _n(v) ?? 0]}
          else if (r is List && r.isNotEmpty)
            {'label': _s(r.first), 'values': [for (final v in r.skip(1)) _n(v) ?? 0]},
      ];
      if (rows.isEmpty) problem = 'Give columns and rows: [{label, values: [numbers]}]';
      out.addAll({'columns': cols, 'rows': rows.take(31).toList(), if (_s(a['unit']).isNotEmpty) 'unit': _s(a['unit'])});
    case ComponentKind.funnel || ComponentKind.breakdown || ComponentKind.leaderboard:
      final items = [for (final i in _list(a['items'])) if (i is Map) Map<String, dynamic>.from(i)];
      if (items.isEmpty || items.every((i) => _n(i['value']) == null)) problem = 'Give items with a number value each';
      out.addAll({'items': items.take(kind == ComponentKind.leaderboard ? 20 : 10).toList(), if (_s(a['unit']).isNotEmpty) 'unit': _s(a['unit'])});
    case ComponentKind.metric:
      final value = _s(a['value']);
      if (value.isEmpty) problem = 'Give value (the headline number, as text)';
      out.addAll({
        'value': value,
        if (_s(a['label']).isNotEmpty) 'label': _s(a['label']),
        'delta': ?_n(a['delta']),
        if (a['up_is_bad'] == true) 'up_is_bad': true,
        if (_s(a['hint']).isNotEmpty) 'hint': _s(a['hint']),
        'trend': [for (final v in _list(a['trend'])) ?_n(v)].take(60).toList(),
      });
    case ComponentKind.rings:
      final items = [for (final i in _list(a['items'])) if (i is Map) Map<String, dynamic>.from(i)];
      if (items.isEmpty) problem = 'Give items [{label, value, max}]';
      out['items'] = items.take(4).toList();
    case ComponentKind.checklist || ComponentKind.steps || ComponentKind.facts:
      final items = [
        for (final i in _list(a['items']))
          if (i is Map) Map<String, dynamic>.from(i) else if (_s(i).isNotEmpty) {kind == ComponentKind.steps ? 'title' : 'text': _s(i)},
      ];
      if (items.isEmpty) problem = 'Give items';
      out.addAll({'items': items.take(30).toList(), if (_s(a['emoji']).isNotEmpty) 'emoji': _s(a['emoji'])});
    case ComponentKind.board:
      final lanes = [
        for (final l in _list(a['lanes']))
          if (l is Map) {'name': _s(l['name']), 'cards': [for (final c in _list(l['cards'])) c is Map ? Map<String, dynamic>.from(c) : _s(c)].take(20).toList()},
      ];
      if (lanes.isEmpty) problem = 'Give lanes: [{name, cards: [text or {title, detail, tag}]}]';
      out['lanes'] = lanes.take(5).toList();
    case ComponentKind.callout:
      final text = _s(a['text']);
      if (text.isEmpty) problem = 'Give text';
      const tones = {'info', 'tip', 'success', 'warning', 'danger'};
      final tone = _s(a['tone']).toLowerCase();
      out.addAll({'text': text, 'tone': tones.contains(tone) ? tone : 'info'});
    case ComponentKind.receipt:
      final items = [for (final i in _list(a['items'])) if (i is Map) Map<String, dynamic>.from(i)];
      if (items.isEmpty) problem = 'Give items [{name, qty, price}]';
      out.addAll({
        'items': items.take(40).toList(),
        'currency': _s(a['currency']).isEmpty ? r'$' : _s(a['currency']),
        for (final k in ['tax', 'tip', 'discount']) k: ?_n(a[k]),
        if (_n(a['split']) case final v? when v > 1) 'split': v.round(),
        if (_s(a['note']).isNotEmpty) 'note': _s(a['note']),
      });
    case ComponentKind.countdown:
      final target = DateTime.tryParse(_s(a['target']));
      if (target == null) problem = 'Give target as an ISO date and time, e.g. 2026-12-31T23:59:00 (local time unless it ends in Z)';
      out.addAll({'target': _s(a['target']), if (_s(a['label']).isNotEmpty) 'label': _s(a['label'])});
  }
  if (problem != null) {
    return ToolOutput({'error': '$problem. Example: ${jsonEncode(componentSamples[kind])}'});
  }
  return ToolOutput(
    {'shown': kind.name, 'note': 'The user sees it as a card. Don\'t repeat its numbers; add only what it doesn\'t show.'},
    full: out,
  );
}
