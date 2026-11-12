import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../ai/data/ai.dart';
import 'usage.dart';
import 'spend_limits_screen.dart';

enum _Period {
  today('Today'),
  week('7 days'),
  month('30 days'),
  all('All');

  const _Period(this.label);
  final String label;

  bool includes(DateTime t) {
    final now = DateTime.now();
    return switch (this) {
      today => t.isAfter(DateTime(now.year, now.month, now.day)),
      week => now.difference(t).inDays < 7,
      month => now.difference(t).inDays < 30,
      all => true,
    };
  }
}

enum _By {
  chat('By chat'),
  model('By model'),
  modality('By kind');

  const _By(this.label);
  final String label;
}

enum _CapBy {
  server('Servers'),
  skill('Skills'),
  tool('Tools');

  const _CapBy(this.label);
  final String label;
}

String usd(double v) => v == 0
    ? '\$0'
    : v < 0.01
    ? '\$${v.toStringAsFixed(4)}'
    : v < 1
    ? '\$${v.toStringAsFixed(3)}'
    : '\$${v.toStringAsFixed(2)}';

String compact(num n) => NumberFormat.compact().format(n);

String _duration(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(ms < 10000 ? 1 : 0)} s';

class _Group {
  _Group(this.label, {this.subtitle, this.modality});
  final String label;
  final String? subtitle;
  final Modality? modality;
  double cost = 0;
  int input = 0, output = 0, requests = 0, units = 0, failed = 0, ms = 0;
  bool estimated = false;
  DateTime? last;
  final Map<Modality, int> kinds = {};

  void add(UsageEvent e) {
    cost += e.cost;
    input += e.input;
    output += e.output;
    units += e.units;
    requests++;
    ms += e.ms;
    if (!e.ok) failed++;
    estimated |= e.estimated;
    if (last == null || e.at.isAfter(last!)) last = e.at;
    kinds.update(e.modality, (n) => n + 1, ifAbsent: () => 1);
  }
}

/// Tokens and money spent on models and decisions, and how MCP servers and
/// skills were used.
class UsageScreen extends ConsumerStatefulWidget {
  const UsageScreen({super.key});

  @override
  ConsumerState<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends ConsumerState<UsageScreen> {
  _Period _period = _Period.month;
  _By _by = _By.chat;
  _CapBy _capBy = _CapBy.server;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(usageProvider);
    final events = all.where((e) => _period.includes(e.at)).toList();
    final period = SizedBox(
      width: double.infinity,
      child: SegmentedButton<_Period>(
        showSelectedIcon: false,
        segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
        selected: {_period},
        onSelectionChanged: (v) => setState(() => _period = v.first),
      ),
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usage & cost'),
          actions: [
            IconButton(
              tooltip: 'Spending limits',
              icon: const Icon(Icons.savings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SpendLimitsScreen())),
            ),
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: all.isEmpty
                  ? null
                  : () async {
                      if (await confirmDelete(
                        context,
                        title: 'Clear usage history?',
                        message: 'This only clears the stats on this phone.',
                        action: 'Clear',
                      )) {
                        ref.read(usageProvider.notifier).clear();
                      }
                    },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'AI & decisions'),
              Tab(text: 'MCP & Skills'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _page([period, ..._models(context, events.where((e) => !e.modality.isCapability).toList())]),
            _page([period, ..._capabilities(context, events.where((e) => e.modality.isCapability).toList())]),
          ],
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4), children: children),
    ),
  );

  List<Widget> _models(BuildContext context, List<UsageEvent> events) {
    final catalog = ref.watch(modelCatalogProvider);
    final total = events.fold<double>(0, (n, e) => n + e.cost);
    final input = events.fold<int>(0, (n, e) => n + e.input);
    final output = events.fold<int>(0, (n, e) => n + e.output);
    final cached = events.fold<int>(0, (n, e) => n + e.cached);
    final decisions = events.where((e) => e.modality == Modality.decision).toList();
    final decided = decisions.fold<int>(0, (n, e) => n + e.units);
    final decisionTokens = decisions.fold<int>(0, (n, e) => n + e.input);
    final anyEstimate = events.any((e) => e.estimated);

    final groups = <String, _Group>{};
    for (final e in events) {
      final (key, label, sub) = switch (_by) {
        _By.chat => (
          e.conversationId ?? e.conversationTitle ?? '-',
          e.conversationTitle ?? (e.modality == Modality.dictation ? 'Dictation' : 'Outside a chat'),
          null,
        ),
        _By.model => (
          e.model,
          e.modality == Modality.decision ? 'TypeSafe ${e.model}' : catalog.byId(e.model)?.name ?? modelLabel(e.model),
          e.modality == Modality.decision ? 'Decisions' : modelLabel(e.model),
        ),
        _By.modality => (e.modality.name, e.modality.label, e.modality.description),
      };
      groups.putIfAbsent(key, () => _Group(label, subtitle: sub, modality: _by == _By.modality ? e.modality : null)).add(e);
    }
    // Decisions aren't priced here, so they rank by requests after paid rows.
    final rows = groups.values.toList()..sort((a, b) => b.cost != a.cost ? b.cost.compareTo(a.cost) : b.requests.compareTo(a.requests));
    final top = rows.fold<double>(0, (m, g) => g.cost > m ? g.cost : m);
    final topRequests = rows.fold<int>(0, (m, g) => g.requests > m ? g.requests : m);

    return [
      const SizedBox(height: Space.l),
      _Hero(
        label: 'SPENT',
        value: '${anyEstimate ? '≈ ' : ''}${usd(total)}',
        figures: [
          _Figure(label: 'Input tokens', value: compact(input)),
          _Figure(label: 'Output tokens', value: compact(output)),
          if (cached > 0) _Figure(label: 'Cached', value: compact(cached)),
          _Figure(label: 'Requests', value: compact(events.length - decisions.length)),
          if (decisions.isNotEmpty) _Figure(label: 'Decisions', value: compact(decided)),
          if (decisionTokens > 0) _Figure(label: 'Decision tokens', value: compact(decisionTokens)),
        ],
      ),
      const SizedBox(height: Space.xl),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<_By>(
          showSelectedIcon: false,
          segments: [for (final b in _By.values) ButtonSegment(value: b, label: Text(b.label))],
          selected: {_by},
          onSelectionChanged: (v) => setState(() => _by = v.first),
        ),
      ),
      const SizedBox(height: Space.m),
      if (rows.isEmpty) const _Empty('Nothing used in this period yet.'),
      for (final g in rows)
        _Row(
          title: g.label,
          subtitle: g.subtitle != null && g.subtitle != g.label ? g.subtitle : null,
          trailing: g.cost > 0 || g.kinds.keys.any((k) => k != Modality.decision)
              ? '${g.estimated ? '≈ ' : ''}${usd(g.cost)}'
              : '${compact(g.units)} decided',
          fraction: top > 0 && g.cost > 0 ? g.cost / top : (topRequests == 0 ? 0 : g.requests / topRequests),
          detail: [
            '${g.requests} request${g.requests == 1 ? '' : 's'}',
            if (g.input + g.output > 0) '${compact(g.input)} in · ${compact(g.output)} out',
            if (g.units > 0)
              switch (g.modality) {
                Modality.image => '${g.units} images',
                Modality.video => '${g.units} s of video',
                Modality.speech => '${compact(g.units)} characters',
                Modality.dictation => '${g.units} s of audio',
                Modality.decision => '${compact(g.units)} decisions',
                _ => '',
              },
            if (g.failed > 0) '${g.failed} failed',
            if (_by != _By.modality && g.kinds.length > 1)
              g.kinds.entries.map((k) => '${k.value} ${k.key.label.toLowerCase()}').join(', '),
          ],
        ),
      if (anyEstimate || decisions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Text(
            [
              if (anyEstimate)
                '≈ marks estimates from list prices. OpenRouter reports exact costs; other requests are priced from '
                    'the model catalog, voices by character and dictation by seconds of audio.',
              if (decisions.isNotEmpty)
                'Decisions count their input tokens: TypeSafe bills those on your TypeSafe account (output is free), '
                    'so they aren\'t in the total above.',
            ].join('\n\n'),
            style: context.text.bodySmall,
          ),
        ),
    ];
  }

  List<Widget> _capabilities(BuildContext context, List<UsageEvent> events) {
    final failed = events.where((e) => !e.ok).length;
    final avg = events.isEmpty ? 0 : events.fold<int>(0, (n, e) => n + e.ms) ~/ events.length;
    final servers = {for (final e in events.where((e) => e.modality == Modality.mcp && e.tool != 'mcp_search')) e.model};
    final skills = {for (final e in events.where((e) => e.modality == Modality.skill && e.tool != 'search_skills')) e.model};
    final shown = switch (_capBy) {
      _CapBy.server => events.where((e) => e.modality == Modality.mcp),
      _CapBy.skill => events.where((e) => e.modality == Modality.skill),
      _CapBy.tool => events,
    };
    final groups = <String, _Group>{};
    for (final e in shown) {
      final key = _capBy == _CapBy.tool ? (e.tool ?? '?') : e.model;
      groups.putIfAbsent(key, () => _Group(key, subtitle: _capBy == _CapBy.tool ? e.modality.label : null)).add(e);
    }
    final rows = groups.values.toList()..sort((a, b) => b.requests.compareTo(a.requests));
    final top = rows.isEmpty ? 0 : rows.first.requests;
    return [
      const SizedBox(height: Space.l),
      _Hero(
        label: 'CALLS',
        value: compact(events.length),
        figures: [
          _Figure(label: 'MCP servers used', value: '${servers.length}'),
          _Figure(label: 'Skills used', value: '${skills.length}'),
          _Figure(label: 'Failed', value: compact(failed)),
          if (events.isNotEmpty) _Figure(label: 'Average time', value: _duration(avg)),
        ],
      ),
      const SizedBox(height: Space.xl),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<_CapBy>(
          showSelectedIcon: false,
          segments: [for (final b in _CapBy.values) ButtonSegment(value: b, label: Text(b.label))],
          selected: {_capBy},
          onSelectionChanged: (v) => setState(() => _capBy = v.first),
        ),
      ),
      const SizedBox(height: Space.m),
      if (rows.isEmpty)
        _Empty(switch (_capBy) {
          _CapBy.server => 'No MCP calls in this period. Install a server in Settings → MCP & Skills.',
          _CapBy.skill => 'No skills used in this period.',
          _CapBy.tool => 'No MCP or skill tools used in this period.',
        }),
      for (final g in rows)
        _Row(
          title: g.label,
          subtitle: g.subtitle,
          trailing: '${g.requests} call${g.requests == 1 ? '' : 's'}',
          fraction: top == 0 ? 0 : g.requests / top,
          detail: [
            if (_capBy != _CapBy.tool && g.kinds.isNotEmpty) g.kinds.keys.first.label,
            'average ${_duration(g.ms ~/ g.requests)}',
            if (g.failed > 0) '${g.failed} failed',
            if (g.last != null) 'last ${DateFormat('d MMM HH:mm').format(g.last!)}',
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(top: Space.m),
        child: Text(
          'Counted on this phone each time the assistant uses an MCP or skill tool. A server\'s own charges, if it '
          'has any, are billed by its provider.',
          style: context.text.bodySmall,
        ),
      ),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.label, required this.value, required this.figures});
  final String label;
  final String value;
  final List<Widget> figures;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.xl),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.xl),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppColors.isLight ? [const Color(0xFFE6ECF7), AppColors.surface] : [const Color(0xFF1C2433), const Color(0xFF131316)],
      ),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Text(value, style: context.text.headlineMedium?.copyWith(fontFeatures: tabularFigures)),
        const SizedBox(height: Space.l),
        Wrap(spacing: Space.xl, runSpacing: Space.m, children: figures),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, required this.trailing, required this.fraction, required this.detail});
  final String title;
  final String? subtitle;
  final String trailing;
  final double fraction;
  final List<String> detail;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    padding: const EdgeInsets.all(Space.l),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
            Text(trailing, style: context.text.titleSmall?.copyWith(fontFeatures: tabularFigures)),
          ],
        ),
        if (subtitle != null) Text(subtitle!, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: fraction.clamp(0, 1), minHeight: 5, backgroundColor: AppColors.surface3),
        ),
        const SizedBox(height: Space.s),
        Text(detail.where((t) => t.isNotEmpty).join(' · '), style: context.text.bodySmall),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.x4),
    child: Text(text, textAlign: TextAlign.center, style: context.text.bodySmall),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: context.text.titleLarge?.copyWith(fontFeatures: tabularFigures)),
      Text(label, style: context.text.bodySmall),
    ],
  );
}
