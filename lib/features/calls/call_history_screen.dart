import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/net_image.dart';
import '../device/device.dart';
import '../finance/finance_insights.dart' show FinPeriod;
import '../finance/ui/finance_ui.dart' show Caption, CardTitle, DeltaBadge, FinCard, Pill, PillTabs, RingProgress, SectionTitle, listOf, mapOf, numOf;
import '../settings/presentation/feature_tools_tab.dart';
import '../telegram/data/telegram_tools.dart' show ToolCategory;
import 'call_history.dart';
import 'call_ui.dart';

/// Settings → Call history: the phone's call log analysed. Overview,
/// people, every call, and the assistant's call history tools.
class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3))..addListener(() => setState(() {}));
  String _period = 'last_30_days';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await CallHistory.instance.load(fresh: true);
    ref.invalidate(callHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(callHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call history'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: PillTabs<int>(options: const [(0, 'Overview'), (1, 'People'), (2, 'Calls'), (3, 'Tools')], value: _tabs.index, onChanged: _tabs.animateTo),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _guard(log, (all) => _Overview(all: all, period: _period, onPeriod: (p) => setState(() => _period = p))),
          _guard(log, (all) => _People(all: all, period: _period, onPeriod: (p) => setState(() => _period = p))),
          _guard(log, (all) => _Calls(all: all)),
          const FeatureToolsTab(
            category: ToolCategory.callHistory,
            intro:
                'With these on, the assistant can read and analyse your phone\'s call log when you ask: totals, missed calls, who you '
                'talk to most and when, and your history with one person. It only reads; nothing is changed or sent anywhere but '
                'your AI provider, and each read shows in the activity log.',
            examples: [
              'How much time did I spend on calls this month?',
              'Which missed calls haven\'t I returned?',
              'Who do I talk to the most?',
              'When do people usually call me?',
            ],
          ),
        ],
      ),
    );
  }

  Widget _guard(AsyncValue<List<CallRecord>> log, Widget Function(List<CallRecord>) child) {
    if (!Device.supported) return const _Message(icon: Icons.phone_android_rounded, title: 'Android only', text: 'Call history reads the phone\'s call log, which is only available in the Android app.');
    return log.when(
      data: (all) => all.isEmpty ? const _Message(icon: Icons.call_outlined, title: 'No calls yet', text: 'Your call log is empty.') : RefreshIndicator(onRefresh: _refresh, child: child(all)),
      loading: () => const _Loading(),
      error: (e, _) => _Message(
        icon: Icons.lock_outline_rounded,
        title: 'Can\'t read the call log',
        text: e is DeviceException ? e.message : 'Allow call log access for Triangle in Android\'s settings, then refresh.',
        action: FilledButton(onPressed: _refresh, child: const Text('Try again')),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Space.l),
    children: const [
      Skeleton(width: 140, height: 14, radius: 6),
      SizedBox(height: Space.s),
      Skeleton(width: 220, height: 34, radius: 8),
      SizedBox(height: Space.xl),
      Skeleton(height: 120, radius: 20),
      SizedBox(height: Space.m),
      Skeleton(height: 200, radius: 20),
      SizedBox(height: Space.m),
      Skeleton(height: 120, radius: 20),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            child: Icon(icon, size: 30, color: AppColors.text2),
          ),
          const SizedBox(height: Space.l),
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Space.s),
          Text(text, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45)),
          if (action != null) ...[const SizedBox(height: Space.l), action!],
        ],
      ),
    ),
  );
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
    child: PillTabs<String>(options: callPeriods, value: value, onChanged: onChanged),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.all, required this.period, required this.onPeriod});
  final List<CallRecord> all;
  final String period;
  final ValueChanged<String> onPeriod;

  @override
  Widget build(BuildContext context) {
    final s = callSummary(all, FinPeriod.resolve(period));
    final prev = mapOf(s['previous']);
    final rate = s['answer_rate'];
    final unreturned = listOf(s['unreturned_missed']);
    final hours = [for (final h in (s['hours'] as List)) (h as num).toInt()];
    final weekdays = [for (final h in (s['weekdays'] as List)) (h as num).toInt()];
    final points = listOf(mapOf(s['series'])['points']);
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Caption('On the phone · ${mapOf(s['period'])['label']}', color: AppColors.text2),
              const SizedBox(height: 4),
              Text('${s['talk_time']}', style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Text('${s['calls']} calls · ${s['calls_per_day']} a day', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
                  const SizedBox(width: Space.s),
                  if (prev['talk_change_pct'] is num && (prev['talk_change_pct'] as num).abs() <= 500) DeltaBadge(pct: (prev['talk_change_pct'] as num).toDouble(), upIsGood: true, suffix: 'time'),
                ],
              ),
            ],
          ),
        ),
        _PeriodTabs(value: period, onChanged: onPeriod),
        FinCard(child: CallTypeSplit(incoming: numOf(s['incoming']).toInt(), outgoing: numOf(s['outgoing']).toInt(), missed: numOf(s['missed']).toInt() + numOf(s['rejected']).toInt())),
        if (points.isNotEmpty)
          FinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle('Calls by ${mapOf(s['series'])['bucket']}'),
                const SizedBox(height: Space.m),
                CallStackBars(points: points),
              ],
            ),
          ),
        FinCard(
          child: Row(
            children: [
              RingProgress(
                value: rate is num ? rate / 100 : 0,
                color: rate is num && rate >= 80 ? callOutgoing : (rate is num && rate >= 50 ? AppColors.warning : callMissed),
                size: 92,
                stroke: 9,
                child: Text(rate is num ? '${rate.round()}%' : '—', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: Space.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Answered', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Caption('Of the calls that reached you', color: AppColors.text2),
                    const SizedBox(height: Space.s),
                    Caption('${s['incoming']} picked up · ${s['missed']} missed · ${s['rejected']} declined${numOf(s['blocked']) > 0 ? ' · ${s['blocked']} blocked' : ''}', maxLines: 2),
                    Caption('Average call ${talkTime(numOf(s['avg_call_seconds']))}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (unreturned.isNotEmpty) ...[
          SectionTitle('Missed and not returned', action: '${unreturned.length}'),
          FinCard(padding: const EdgeInsets.symmetric(vertical: Space.xs), child: Column(children: [for (final c in unreturned.take(5)) CallRow(call: c, showDay: true)])),
        ],
        FinCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardTitle('When calls happen', caption: s['busiest_hour'] == null ? null : 'Busiest around ${_hour(s['busiest_hour'] as int)} · ${s['busiest_day']}s'),
              const SizedBox(height: Space.m),
              HourStrip(hours: hours),
              const SizedBox(height: Space.l),
              WeekdayBars(weekdays: weekdays),
            ],
          ),
        ),
        if (s['longest'] is Map) ...[
          const SectionTitle('Longest call'),
          FinCard(padding: const EdgeInsets.symmetric(vertical: Space.xs), child: CallRow(call: mapOf(s['longest']), showDay: true)),
        ],
      ],
    );
  }

  static String _hour(int h) => h == 0 ? '12 am' : h < 12 ? '$h am' : h == 12 ? '12 pm' : '${h - 12} pm';
}

class _People extends StatefulWidget {
  const _People({required this.all, required this.period, required this.onPeriod});
  final List<CallRecord> all;
  final String period;
  final ValueChanged<String> onPeriod;

  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  String _by = 'calls';

  @override
  Widget build(BuildContext context) {
    final s = callSummary(widget.all, FinPeriod.resolve(widget.period));
    final list = listOf(_by == 'calls' ? s['top_by_calls'] : s['top_by_time']);
    final max = list.fold(0.0, (m, p) => numOf(p[_by == 'calls' ? 'calls' : 'seconds']) > m ? numOf(p[_by == 'calls' ? 'calls' : 'seconds']) : m);
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        _PeriodTabs(value: widget.period, onChanged: widget.onPeriod),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
          child: Row(
            children: [
              Pill(dense: true, label: 'Most calls', selected: _by == 'calls', onTap: () => setState(() => _by = 'calls')),
              const SizedBox(width: 6),
              Pill(dense: true, label: 'Most time', selected: _by == 'seconds', onTap: () => setState(() => _by = 'seconds')),
              const Spacer(),
              Caption('${s['people']} people'),
            ],
          ),
        ),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(Space.x4), child: Center(child: Caption('No calls in this period.'))),
        if (list.isNotEmpty)
          FinCard(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Column(children: [for (final p in list) PersonRow(person: p, max: max, metric: _by == 'calls' ? 'calls' : 'seconds')]),
          ),
      ],
    );
  }
}

class _Calls extends StatefulWidget {
  const _Calls({required this.all});
  final List<CallRecord> all;

  @override
  State<_Calls> createState() => _CallsState();
}

class _CallsState extends State<_Calls> {
  String _type = 'all';
  String _q = '';
  int _shown = 80;

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.all.where((c) {
      if (_type == 'missed' && !c.missed) return false;
      if (_type != 'all' && _type != 'missed' && c.type != _type) return false;
      return q.isEmpty || c.who.toLowerCase().contains(q) || c.number.contains(q);
    }).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Search names or numbers',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() {
              _q = v.trim();
              _shown = 80;
            }),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
            children: [
              for (final (k, l) in const [('all', 'All'), ('missed', 'Missed'), ('incoming', 'Incoming'), ('outgoing', 'Outgoing'), ('blocked', 'Blocked')])
                Padding(padding: const EdgeInsets.only(right: 6), child: Pill(dense: true, label: l, selected: _type == k, onTap: () => setState(() => _type = k))),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0), child: Caption('${list.length} calls · ${talkTime(list.fold(0, (s, c) => s + c.seconds))}')),
        ...callsByDay([for (final c in list.take(_shown)) describeCall(c)]),
        if (list.length > _shown) TextButton(onPressed: () => setState(() => _shown += 150), child: Text('Show more (${list.length - _shown})')),
      ],
    );
  }
}
