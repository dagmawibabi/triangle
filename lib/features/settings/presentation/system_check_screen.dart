import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../data/system_check.dart';

export '../data/system_check.dart' show CheckStatus, CheckResult, CheckGroup;

/// Settings → System check: runs [SystemChecker] and shows what it found,
/// area by area, with a way to fix each problem. It only reads.
class SystemCheckScreen extends ConsumerStatefulWidget {
  const SystemCheckScreen({super.key});

  @override
  ConsumerState<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends ConsumerState<SystemCheckScreen> {
  List<CheckGroup> _groups = const [];
  bool _running = false;
  DateTime? _at;

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _groups = const [];
    });
    final groups = await SystemChecker(ref.read).run(
      onProgress: (groups) {
        if (mounted) setState(() => _groups = [...groups]);
      },
    );
    if (mounted) {
      setState(() {
        _groups = groups;
        _running = false;
        _at = DateTime.now();
      });
    }
  }

  // ---- the page --------------------------------------------------------------------

  /// Which results are shown.
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    // It only reads, so it starts on its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scan();
    });
  }

  /// Everything found, as plain text to paste into a chat or a bug report.
  String _report() {
    final lines = <String>[
      'Triangle system check${_at == null ? '' : ' · ${_at!.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}'}',
      '',
    ];
    for (final g in _groups) {
      lines.add('${g.title} (${g.ms} ms)');
      for (final r in [...g.results]..sort((a, b) => a.status.rank.compareTo(b.status.rank))) {
        lines.add('  [${r.status.word}] ${r.title}${r.detail.isEmpty ? '' : ': ${r.detail}'}');
      }
      lines.add('');
    }
    return lines.join('\n').trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final all = [for (final g in _groups) ...g.results];
    int count(CheckStatus s) => all.where((r) => r.status == s).length;
    final attention = count(CheckStatus.fail) + count(CheckStatus.warn);
    final score = SystemChecker.score(_groups);
    final done = _groups.where((g) => g.done).length;
    final shownGroups = [
      for (final g in _groups)
        if (!g.done || g.results.any(_filter.matches)) g,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('System check'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: _running || _groups.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _report()));
                    showSnack(context, 'Report copied');
                  },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: () async {
              if (!_running) await _scan();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ScoreRing(
                            value: _running ? (_groups.isEmpty ? 0 : done / _groups.length) : (score ?? 0) / 100,
                            label: _running ? '$done/${_groups.length}' : (score == null ? '–' : '$score'),
                            color: _running
                                ? AppColors.text2
                                : count(CheckStatus.fail) > 0
                                ? CheckStatus.fail.color
                                : attention > 0
                                ? CheckStatus.warn.color
                                : CheckStatus.ok.color,
                          ),
                          const SizedBox(width: Space.l),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _groups.isEmpty
                                      ? 'Check everything'
                                      : _running
                                      ? 'Checking ${_groups[done.clamp(0, _groups.length - 1)].title.toLowerCase()}…'
                                      : attention == 0
                                      ? 'All good'
                                      : '$attention thing${attention == 1 ? '' : 's'} need${attention == 1 ? 's' : ''} attention',
                                  style: context.text.titleLarge,
                                ),
                                const SizedBox(height: Space.xs),
                                Text(
                                  _running || _at == null
                                      ? 'It only looks; nothing is changed.'
                                      : 'Health ${score ?? '–'} of 100 · checked ${TimeOfDay.fromDateTime(_at!).format(context)}',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: Space.l),
                        Wrap(
                          spacing: Space.s,
                          runSpacing: Space.s,
                          children: [
                            for (final st in const [CheckStatus.fail, CheckStatus.warn, CheckStatus.improve, CheckStatus.ok])
                              if (count(st) > 0) _CountPill(status: st, count: count(st)),
                          ],
                        ),
                      ],
                      const SizedBox(height: Space.l),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _running ? null : _scan,
                              icon: _running
                                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.radar_rounded),
                              label: Text(_running ? 'Checking…' : (_groups.isEmpty ? 'Scan' : 'Scan again')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_groups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in _Filter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: Space.s),
                              child: ChoiceChip(
                                label: Text('${f.label} · ${all.where(f.matches).length}'),
                                selected: _filter == f,
                                onSelected: (_) => setState(() => _filter = f),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                for (final g in shownGroups) _GroupCard(key: ValueKey(g.title), group: g, filter: _filter),
                if (!_running && _groups.isNotEmpty && shownGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.xxl),
                    child: Center(
                      child: Text(
                        _filter == _Filter.attention ? 'Nothing needs attention.' : 'Nothing here.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Filter {
  all('All'),
  attention('Needs attention'),
  suggestions('Suggestions'),
  passed('Passed');

  const _Filter(this.label);
  final String label;

  bool matches(CheckResult r) => switch (this) {
    all => true,
    attention => r.status == CheckStatus.fail || r.status == CheckStatus.warn,
    suggestions => r.status == CheckStatus.improve,
    passed => r.status == CheckStatus.ok,
  };
}

/// The health score (or the scan's progress) as a ring with a number.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.value, required this.label, required this.color});
  final double value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 72,
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: v,
            strokeWidth: 6,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surface3,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Center(child: Text(label, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    ),
  );
}

/// "2 broken", "5 passed": a count of one kind of result.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.status, required this.count});
  final CheckStatus status;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 4),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 14, color: status.color),
        const SizedBox(width: 4),
        Text(
          '$count ${status.word}${count == 1 || status == CheckStatus.ok || status == CheckStatus.fail ? '' : 's'}',
          style: context.text.labelSmall?.copyWith(color: status.color),
        ),
      ],
    ),
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({super.key, required this.group, required this.filter});
  final CheckGroup group;
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final shown = g.results.where(filter.matches).toList()..sort((a, b) => a.status.rank.compareTo(b.status.rank));
    final tint = g.done ? g.worst.color : AppColors.text3;
    final summary = !g.done
        ? 'Checking…'
        : [
            for (final st in const [CheckStatus.fail, CheckStatus.warn, CheckStatus.improve, CheckStatus.ok])
              if (g.count(st) > 0) '${g.count(st)} ${st.word}${g.count(st) == 1 || st == CheckStatus.ok || st == CheckStatus.fail ? '' : 's'}',
            if (g.results.isEmpty) 'Nothing to check',
            g.ms < 1000 ? '${g.ms} ms' : '${(g.ms / 1000).toStringAsFixed(1)} s',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(
            color: g.done && (g.worst == CheckStatus.fail || g.worst == CheckStatus.warn)
                ? tint.withValues(alpha: 0.45)
                : AppColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: g.done && (filter != _Filter.all || g.worst.rank <= CheckStatus.improve.rank),
              key: ValueKey('${g.title}-${g.done}-${filter.name}'),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.m),
                ),
                child: Icon(g.icon, color: g.done ? tint : AppColors.text2, size: 20),
              ),
              title: Text(g.title),
              subtitle: Text(summary, style: context.text.bodySmall),
              trailing: !g.done
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(g.worst.icon, color: g.worst.color),
              childrenPadding: const EdgeInsets.only(bottom: Space.s),
              children: [
                for (final r in shown) _ResultRow(result: r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One finding: what was found, why it matters, and a way to fix it.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});
  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final serious = r.status == CheckStatus.fail || r.status == CheckStatus.warn;
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => r.fix!()));
    return InkWell(
      onTap: r.fix == null ? null : open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(r.status.icon, color: r.status.color, size: 18),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: context.text.bodyMedium?.copyWith(fontWeight: serious ? FontWeight.w600 : null)),
                  if (r.detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(r.detail, style: context.text.bodySmall),
                    ),
                ],
              ),
            ),
            if (r.fix != null)
              serious || r.status == CheckStatus.improve
                  ? TextButton(onPressed: open, child: const Text('Fix'))
                  : Padding(
                      padding: const EdgeInsets.all(Space.s),
                      child: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    ),
          ],
        ),
      ),
    );
  }
}
