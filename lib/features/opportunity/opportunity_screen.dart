import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../sections/section_kit.dart';
import '../telegram/presentation/tg_avatar.dart';
import 'opportunity.dart';
import '../marketplace/market_screen.dart' show LegitBadge;
import 'opportunity_ai_screen.dart';
import 'opportunity_detail.dart';

import '../sections/skeletons.dart';
/// The section's colour; the app's own in the monochrome look.
Color get oppColor => AppLook.brand(const Color(0xFF8B5CF6));

/// Events and jobs from the channels and groups that post them: an events
/// calendar in the spirit of Luma, and a job board with an application
/// tracker.
class OpportunityScreen extends ConsumerStatefulWidget {
  const OpportunityScreen({super.key, this.initialTab = 0});
  final int initialTab;

  static Future<void> open(BuildContext context, {int tab = 0}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OpportunityScreen(initialTab: tab)));

  @override
  ConsumerState<OpportunityScreen> createState() => _OpportunityScreenState();
}

class _OpportunityScreenState extends ConsumerState<OpportunityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(opportunityProvider.notifier).ready;
      if (!mounted) return;
      for (final k in OppKind.values) {
        unawaited(ref.read(oppFeedProvider(k).notifier).loadAll(mineOf(ref, k)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(opportunityProvider);
    final events = allEvents(o, ref.watch(oppFeedProvider(OppKind.event)));
    final jobs = allJobs(o, ref.watch(oppFeedProvider(OppKind.job)));
    final going = o.savedEvents.where((e) => e.status == EventStatus.going && (e.start == null || e.start!.isAfter(DateTime.now().subtract(const Duration(hours: 6))))).length;
    final applied = o.tracked.where((t) => t.status != JobStatus.saved).length;
    return SectionScaffold(
      initialTab: widget.initialTab,
      title: 'Opportunity',
      icon: Icons.rocket_launch_rounded,
      color: oppColor,
      tabs: [
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event_rounded, size: 16), const SizedBox(width: 6), Text('Events${events.isEmpty ? '' : ' · ${events.length}'}')])),
        Tab(height: 46, child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.work_outline_rounded, size: 16), const SizedBox(width: 6), Text('Jobs${jobs.isEmpty ? '' : ' · ${jobs.length}'}')])),
      ],
      actions: [
        ValueListenableBuilder<OppReadJob>(
          valueListenable: ref.read(opportunityProvider.notifier).readJob,
          builder: (context, j, _) => IconButton(
            tooltip: 'AI reading',
            icon: j.running
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: j.total == 0 ? null : j.done / j.total, color: oppColor))
                : Icon(Icons.auto_awesome_rounded, color: o.ai.enabled ? oppColor : null),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OpportunitySettingsScreen())),
          ),
        ),
        IconButton(tooltip: 'Sources', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => showSourcesSheet(context, ref)),
      ],
      hero: SectionHero(
        subtitle: o.eventSources.isEmpty && o.jobSources.isEmpty ? 'Events and jobs from the channels that post them, in one place.' : 'What\'s on, and who\'s hiring',
        stats: [
          ('${events.length}', 'upcoming'),
          ('$going', 'going'),
          ('${jobs.length}', 'open jobs'),
          ('$applied', 'applied'),
        ],
      ),
      views: const [EventsTab(), JobsTab()],
      bottomBar: const BottomAudioBar(),
    );
  }
}

List<SourceRef> mineOf(WidgetRef ref, OppKind k) => [
  for (final s in ref.read(opportunityProvider).sourcesOf(k))
    if (s.account == ref.read(activeAccountIdProvider)) s,
];

Future<void> addSources(BuildContext context, WidgetRef ref, OppKind k) async {
  final o = ref.read(opportunityProvider);
  final picked = await pickSources(
    context,
    account: ref.read(activeAccountIdProvider),
    current: o.sourcesOf(k),
    title: k == OppKind.event ? 'Event channels' : 'Job channels',
    hint: k == OppKind.event
        ? 'Channels and groups that announce events, meetups, workshops and conferences.'
        : 'Channels and groups that post vacancies, internships and freelance work.',
  );
  if (picked == null) return;
  await ref.read(opportunityProvider.notifier).setSources(k, picked);
  unawaited(ref.read(oppFeedProvider(k).notifier).loadAll(mineOf(ref, k)));
}

// ---- small pieces ---------------------------------------------------------------------

/// "Today", "Tomorrow", "Monday" or "Mon 16 Nov".
String dayName(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(d);
  return DateFormat(d.year == now.year ? 'EEE d MMM' : 'EEE d MMM y').format(d);
}

String timeText(DateTime d) => DateFormat.jm().format(d);

/// "in 3 h", "in 2 days", "now", "2 h ago".
String countdown(DateTime d) {
  final diff = d.difference(DateTime.now());
  final a = diff.abs();
  String n;
  if (a.inMinutes < 1) return 'now';
  if (a.inHours < 1) {
    n = '${a.inMinutes} min';
  } else if (a.inDays < 1) {
    n = '${a.inHours} h';
  } else if (a.inDays < 14) {
    n = '${a.inDays} ${a.inDays == 1 ? 'day' : 'days'}';
  } else {
    n = '${(a.inDays / 7).round()} weeks';
  }
  return diff.isNegative ? '$n ago' : 'in $n';
}

/// A post's first picture, or a soft gradient with an icon.
class OppThumb extends StatelessWidget {
  const OppThumb({super.key, required this.post, this.size = 96, this.radius = 16, this.icon = Icons.event_rounded, this.cacheWidth = 360});
  final OppPost? post;
  final double size;
  final double radius;
  final IconData icon;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final pic = post?.pictures.firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: pic == null
            ? _Placeholder(seed: post?.source ?? '', icon: icon)
            : TgPicture(file: pic.file, mini: pic.mini, cacheWidth: cacheWidth, account: post?.account, placeholder: _Placeholder(seed: post?.source ?? '', icon: icon)),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed, required this.icon});
  final String seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final minimal = AppLook.minimalExplore;
    final hue = (seed.hashCode % 360).abs().toDouble();
    final a = minimal ? AppColors.surface3 : HSLColor.fromAHSL(1, hue, 0.55, AppColors.isLight ? 0.78 : 0.32).toColor();
    final b = minimal ? AppColors.surface2 : HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, AppColors.isLight ? 0.68 : 0.22).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
      child: Center(child: Icon(icon, color: (minimal ? AppColors.text3 : Colors.white).withValues(alpha: 0.8))),
    );
  }
}

/// A small icon and a line of text, like "🕐 6:00 PM".
class IconLine extends StatelessWidget {
  const IconLine(this.icon, this.text, {super.key, this.color, this.trailing, this.maxLines = 1, this.size = 14});
  final IconData icon;
  final String text;
  final Color? color;
  final Widget? trailing;
  final int maxLines;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(top: 1.5), child: Icon(icon, size: size + 1, color: AppColors.text3)),
      const SizedBox(width: 6),
      Flexible(child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: color ?? AppColors.text2, height: 1.25))),
      ?trailing,
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: FilterChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
      showCheckmark: false,
      avatar: icon == null ? null : Icon(icon, size: 15, color: selected ? AppLook.onBrand(oppColor) : AppColors.text2),
      label: Text(label),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppLook.onBrand(oppColor) : AppColors.text),
      selectedColor: oppColor,
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged, required this.value});
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      isDense: true,
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      hintText: hint,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: oppColor, width: 1.4)),
    ),
  );
}

class _ReadingBanner extends ConsumerWidget {
  const _ReadingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ValueListenableBuilder<OppReadJob>(
    valueListenable: ref.read(opportunityProvider.notifier).readJob,
    builder: (context, j, _) {
      if (!j.running && j.error == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
        decoration: BoxDecoration(color: oppColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
        child: Row(
          children: [
            if (j.running)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: oppColor, value: j.total == 0 ? null : j.done / j.total))
            else
              Icon(Icons.error_outline_rounded, size: 18, color: AppColors.warning),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                j.running ? 'Reading posts with AI · ${j.done}/${j.total}' : 'Some posts couldn\'t be read: ${j.error}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ),
            if (j.running) TextButton(onPressed: ref.read(opportunityProvider.notifier).stopReading, child: const Text('Stop')),
          ],
        ),
      );
    },
  );
}

// ---- events ---------------------------------------------------------------------------

class EventsTab extends ConsumerStatefulWidget {
  const EventsTab({super.key});

  @override
  ConsumerState<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<EventsTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  EventWhen _when = EventWhen.upcoming;
  bool? _online;
  bool _free = false;
  String? _category;
  DateTime? _day;
  final _debounce = Debounce();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce.cancel();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(oppFeedProvider(OppKind.event).notifier).loadAll(mineOf(ref, OppKind.event), refresh: true);

  Future<void> _more() async {
    final feed = ref.read(oppFeedProvider(OppKind.event).notifier);
    await pooled(mineOf(ref, OppKind.event), 3, (s) => feed.load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final o = ref.watch(opportunityProvider);
    final feed = ref.watch(oppFeedProvider(OppKind.event));
    if (o.eventSources.isEmpty) {
      return SectionEmpty(
        icon: Icons.celebration_outlined,
        title: 'Find what\'s on',
        body: 'Pick the channels and groups that announce meetups, workshops, conferences and parties. Their posts become a calendar you can plan from.',
        action: 'Add event channels',
        onAction: () => addSources(context, ref, OppKind.event),
      );
    }
    final list = allEvents(o, feed, query: _q, when: _when, online: _online, freeOnly: _free, category: _category, day: _day);
    final upcomingAll = allEvents(o, feed);
    final categories = <String>{for (final e in upcomingAll) if (e.category.isNotEmpty) e.category}.toList()..sort();
    final mine = [
      for (final s in o.savedEvents)
        if (s.status != EventStatus.went && (s.start == null || s.start!.isAfter(DateTime.now().subtract(const Duration(hours: 6))))) s,
    ]..sort((a, b) => (a.start ?? DateTime(9999)).compareTo(b.start ?? DateTime(9999)));
    // Group by day, keeping order; unknown dates last.
    final groups = <String, List<EventView>>{};
    for (final e in list) {
      final s = e.start;
      groups.putIfAbsent(s == null ? '' : DateTime(s.year, s.month, s.day).toIso8601String(), () => []).add(e);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: oppColor,
      child: CustomScrollView(
        key: const PageStorageKey('events'),
        slivers: [
          const SliverToBoxAdapter(child: _ReadingBanner()),
          SliverToBoxAdapter(child: _YourEvents(events: mine)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: _SearchField(hint: 'Search events', value: _q, onChanged: (v) => _debounce(const Duration(milliseconds: 250), () => setState(() => _q = v))),
            ),
          ),
          SliverToBoxAdapter(
            child: _DayStrip(
              events: upcomingAll,
              selected: _day,
              onPick: (d) => setState(() => _day = (_day != null && d != null && DateUtils.isSameDay(_day, d)) ? null : d),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
                children: [
                  for (final w in EventWhen.values) _FilterChip(label: w.label, selected: _day == null && _when == w, onTap: () => setState(() {
                    _when = w;
                    _day = null;
                  })),
                  Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), color: AppColors.line),
                  _FilterChip(label: 'Online', icon: Icons.wifi_tethering_rounded, selected: _online == true, onTap: () => setState(() => _online = _online == true ? null : true)),
                  _FilterChip(label: 'In person', icon: Icons.place_outlined, selected: _online == false, onTap: () => setState(() => _online = _online == false ? null : false)),
                  _FilterChip(label: 'Free', icon: Icons.money_off_rounded, selected: _free, onTap: () => setState(() => _free = !_free)),
                  for (final c in categories) _FilterChip(label: c, selected: _category == c, onTap: () => setState(() => _category = _category == c ? null : c)),
                ],
              ),
            ),
          ),
          if (list.isEmpty && feed.anyLoading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: Space.l), child: SkeletonRows(count: 6, art: 92, artRadius: 14, lines: 3)))
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  children: [
                    Icon(feed.anyLoading ? Icons.hourglass_top_rounded : Icons.event_busy_outlined, size: 40, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text(
                      feed.anyLoading
                          ? 'Reading your channels…'
                          : _day != null
                          ? 'Nothing on ${dayName(_day!)}.'
                          : 'No events here. Try another filter, read older posts, or turn on AI reading to find events in long posts.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          for (final g in groups.entries) ...[
            SliverToBoxAdapter(child: _DayHeader(dayKey: g.key)),
            SliverList.builder(itemCount: g.value.length, itemBuilder: (_, i) => EventRow(event: g.value[i], last: i == g.value.length - 1)),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 120),
              child: Center(
                child: feed.anyLoading
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: oppColor))
                    : OutlinedButton.icon(onPressed: _more, icon: const Icon(Icons.history_rounded, size: 18), label: const Text('Read older posts')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.dayKey});
  final String dayKey;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(dayKey);
    final name = d == null ? 'Date to be announced' : dayName(d);
    final sub = d == null ? '' : (name == DateFormat.EEEE().format(d) ? DateFormat('d MMMM').format(d) : DateFormat.EEEE().format(d));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.3)),
            if (sub.isNotEmpty) TextSpan(text: '  /  $sub', style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w600, fontSize: 17)),
          ],
        ),
      ),
    );
  }
}

/// The next two weeks, with a dot under days that have something on.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.events, required this.selected, required this.onPick});
  final List<EventView> events;
  final DateTime? selected;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = <String, int>{};
    for (final e in events) {
      final s = e.start;
      if (s == null) continue;
      final k = DateTime(s.year, s.month, s.day).toIso8601String();
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        itemCount: 21,
        itemBuilder: (context, i) {
          final d = today.add(Duration(days: i));
          final n = counts[d.toIso8601String()] ?? 0;
          final on = selected != null && DateUtils.isSameDay(selected, d);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: on ? oppColor : (n > 0 ? AppColors.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onPick(d),
                child: Container(
                  width: 48,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? Colors.transparent : AppColors.line)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(i == 0 ? 'Today' : DateFormat.E().format(d), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: on ? AppLook.onBrand(oppColor) : AppColors.text3)),
                      const SizedBox(height: 2),
                      Text('${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: on ? AppLook.onBrand(oppColor) : AppColors.text, fontFeatures: tabularFigures)),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var k = 0; k < n.clamp(0, 3); k++)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppLook.onBrand(oppColor) : oppColor),
                            ),
                          if (n == 0) const SizedBox(height: 4),
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
    );
  }
}

/// The events you're going to or interested in, as a rail of tickets.
class _YourEvents extends ConsumerWidget {
  const _YourEvents({required this.events});
  final List<SavedEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
          child: Row(
            children: [
              Expanded(child: Text('Your events', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.3))),
              if (events.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyEventsScreen())),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Text('View all', style: TextStyle(color: AppColors.text3)), Icon(Icons.chevron_right_rounded, color: AppColors.text3)]),
                ),
            ],
          ),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
                  child: Icon(Icons.confirmation_number_outlined, color: AppColors.text3, size: 28),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No upcoming events', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text2)),
                      const SizedBox(height: 2),
                      Text('Events you mark Going or Interested show up here.', style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (context, i) => _Ticket(e: events[i]),
            ),
          ),
      ],
    );
  }
}

/// A saved event, small: its picture, title and when.
class _Ticket extends ConsumerWidget {
  const _Ticket({required this.e});
  final SavedEvent e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final going = e.status == EventStatus.going;
    final soon = e.start != null && e.start!.difference(DateTime.now()).inHours < 24;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openEvent(context, ref, e.key),
        child: Container(
          width: 216,
          padding: const EdgeInsets.fromLTRB(6, 6, Space.m, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: going ? oppColor.withValues(alpha: 0.45) : AppColors.line)),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: e.mini == null ? const _Placeholder(seed: '', icon: Icons.event_rounded) : Image.memory(base64Decode(e.mini!), fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: going ? oppColor : AppColors.surface3, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)),
                      child: Icon(going ? Icons.check_rounded : Icons.star_rounded, size: 10, color: going ? AppLook.onBrand(oppColor) : AppColors.text2),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: Space.s + 2),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      e.start == null ? 'Date to be announced' : '${dayName(e.start!)}${e.hasTime ? ' · ${timeText(e.start!)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: soon ? FontWeight.w600 : FontWeight.w400, color: soon ? AppColors.warning : AppColors.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An event in the list: picture on the left, host, title, time and place.
class EventRow extends ConsumerWidget {
  const EventRow({super.key, required this.event, this.last = false});
  final EventView event;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final saved = ref.watch(opportunityProvider.select((o) => o.savedEvent(e.key)?.status));
    final s = e.start;
    final soon = s != null && !e.past && s.difference(DateTime.now()).inHours < 3;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EventScreen(event: e))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.6)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(tag: 'event-${e.key}', child: OppThumb(post: e.post, size: 92, radius: 14)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TgAvatar(chatId: e.post.chatId, title: e.post.source, size: 18, accountId: e.post.account),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.organizer, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text2, fontWeight: FontWeight.w500))),
                      if (saved != null) Icon(saved == EventStatus.going ? Icons.check_circle_rounded : Icons.star_rounded, size: 16, color: oppColor),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.22, letterSpacing: -0.1)),
                  const SizedBox(height: 6),
                  if (s != null)
                    IconLine(
                      Icons.schedule_rounded,
                      e.hasTime ? '${timeText(s)}${e.end != null && DateUtils.isSameDay(s, e.end) ? ' – ${timeText(e.end!)}' : ''}' : 'All day',
                      trailing: soon ? Padding(padding: const EdgeInsets.only(left: 6), child: _Pill(countdown(s), color: AppColors.warning)) : null,
                    ),
                  if (s != null) const SizedBox(height: 3),
                  if (e.online)
                    const IconLine(Icons.videocam_outlined, 'Online')
                  else if (e.place.isNotEmpty)
                    IconLine(Icons.location_on_outlined, e.place),
                  if (e.price.isNotEmpty || e.free == true) ...[
                    const SizedBox(height: 3),
                    IconLine(Icons.sell_outlined, e.free == true ? 'Free' : e.price),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- jobs ---------------------------------------------------------------------------------

class JobsTab extends ConsumerStatefulWidget {
  const JobsTab({super.key});

  @override
  ConsumerState<JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends ConsumerState<JobsTab> with AutomaticKeepAliveClientMixin {
  String _q = '';
  String? _workplace;
  String? _type;
  bool _closingSoon = false;
  bool _showClosed = false;
  JobSort _sort = JobSort.newest;
  String? _category;
  final _debounce = Debounce();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce.cancel();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(oppFeedProvider(OppKind.job).notifier).loadAll(mineOf(ref, OppKind.job), refresh: true);

  Future<void> _more() async {
    final feed = ref.read(oppFeedProvider(OppKind.job).notifier);
    await pooled(mineOf(ref, OppKind.job), 3, (s) => feed.load(s, more: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final o = ref.watch(opportunityProvider);
    final feed = ref.watch(oppFeedProvider(OppKind.job));
    if (o.jobSources.isEmpty) {
      return SectionEmpty(
        icon: Icons.work_outline_rounded,
        title: 'Your job board',
        body: 'Pick the channels and groups that post vacancies. Each post becomes a clear listing with pay, deadline and how to apply, and you can track every application.',
        action: 'Add job channels',
        onAction: () => addSources(context, ref, OppKind.job),
      );
    }
    final all = allJobs(o, feed, hideClosed: false);
    final list = allJobs(
      o,
      feed,
      query: _q,
      workplace: _workplace,
      type: _type,
      category: _category,
      hideClosed: !_showClosed,
      closingWithinDays: _closingSoon ? 7 : null,
      sort: _sort,
    );
    final types = <String>{for (final j in all) if (j.type.isNotEmpty) j.type}.toList()..sort();
    final cats = <String>{for (final j in all) if ((j.info?.category ?? '').isNotEmpty) j.info!.category}.toList()..sort();
    final counts = {for (final s in JobStatus.values) s: o.tracked.where((t) => t.status == s).length};
    final hasMatch = all.any((j) => j.match != null);
    return RefreshIndicator(
      onRefresh: _refresh,
      color: oppColor,
      child: CustomScrollView(
        key: const PageStorageKey('jobs'),
        slivers: [
          const SliverToBoxAdapter(child: _ReadingBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
              child: _TrackerStrip(counts: counts),
            ),
          ),
          if (o.profile.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                child: _ProfilePrompt(onTap: () => editProfile(context, ref)),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: Row(
                children: [
                  Expanded(child: _SearchField(hint: 'Role, company or skill', value: _q, onChanged: (v) => _debounce(const Duration(milliseconds: 250), () => setState(() => _q = v)))),
                  const SizedBox(width: Space.s),
                  PopupMenuButton<JobSort>(
                    tooltip: 'Sort',
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      for (final s in JobSort.values)
                        if (s != JobSort.match || hasMatch) CheckedPopupMenuItem(value: s, checked: _sort == s, child: Text(s.label)),
                    ],
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
                      child: Row(children: [Icon(Icons.swap_vert_rounded, size: 18, color: AppColors.text2), const SizedBox(width: 4), Text(_sort.label.split(' ').first, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600))]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 4),
                children: [
                  for (final (w, label, icon) in const [('remote', 'Remote', Icons.home_work_outlined), ('hybrid', 'Hybrid', Icons.sync_alt_rounded), ('onsite', 'On-site', Icons.apartment_rounded)])
                    _FilterChip(label: label, icon: icon, selected: _workplace == w, onTap: () => setState(() => _workplace = _workplace == w ? null : w)),
                  _FilterChip(label: 'Closing soon', icon: Icons.timer_outlined, selected: _closingSoon, onTap: () => setState(() => _closingSoon = !_closingSoon)),
                  _FilterChip(label: 'Show closed', icon: Icons.history_toggle_off_rounded, selected: _showClosed, onTap: () => setState(() => _showClosed = !_showClosed)),
                  if (types.isNotEmpty) Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), color: AppColors.line),
                  for (final t in types) _FilterChip(label: t, selected: _type == t, onTap: () => setState(() => _type = _type == t ? null : t)),
                  for (final c in cats) _FilterChip(label: c, selected: _category == c, onTap: () => setState(() => _category = _category == c ? null : c)),
                ],
              ),
            ),
          ),
          if (list.isEmpty && feed.anyLoading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: Space.s), child: SkeletonCards(count: 4)))
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  children: [
                    Icon(feed.anyLoading ? Icons.hourglass_top_rounded : Icons.work_off_outlined, size: 40, color: AppColors.text3),
                    const SizedBox(height: Space.m),
                    Text(feed.anyLoading ? 'Reading your channels…' : 'No jobs match. Try fewer filters or read older posts.', textAlign: TextAlign.center, style: context.text.bodySmall),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              sliver: SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => JobCard(job: list[i])),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 120),
              child: Center(
                child: feed.anyLoading
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: oppColor))
                    : OutlinedButton.icon(onPressed: _more, icon: const Icon(Icons.history_rounded, size: 18), label: const Text('Read older posts')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerStrip extends StatelessWidget {
  const _TrackerStrip({required this.counts});
  final Map<JobStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    final items = [
      (JobStatus.saved, Icons.bookmark_outline_rounded),
      (JobStatus.applied, Icons.send_outlined),
      (JobStatus.interview, Icons.forum_outlined),
      (JobStatus.offer, Icons.emoji_events_outlined),
    ];
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ApplicationsScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: Space.s),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
          child: Row(
            children: [
              for (final (i, (s, icon)) in items.indexed) ...[
                if (i > 0) Container(width: 1, height: 30, color: AppColors.line),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 15, color: (counts[s] ?? 0) > 0 ? oppColor : AppColors.text3),
                          const SizedBox(width: 4),
                          Text('${counts[s] ?? 0}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text, fontFeatures: tabularFigures)),
                        ],
                      ),
                      Text(s.label, style: TextStyle(fontSize: 11, color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
              Icon(Icons.chevron_right_rounded, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePrompt extends StatelessWidget {
  const _ProfilePrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: oppColor.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(Radii.l),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: oppColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(Icons.badge_outlined, color: oppColor),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add your profile', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text('Your skills and the work you want: AI reading then scores each job for you and drafts applications.', style: context.text.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ],
        ),
      ),
    ),
  );
}

/// A job: logo, role, company and place, the facts as chips, and how long is
/// left to apply.
class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job});
  final JobView job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = job;
    final tracked = ref.watch(opportunityProvider.select((o) => o.trackedJob(j.key)?.status));
    final left = j.daysLeft;
    final urgent = left != null && left <= 3;
    final isNew = j.post.date.isAfter(DateTime.now().subtract(const Duration(hours: 36)));
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JobScreen(job: j))),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'job-${j.key}',
                      child: j.post.pictures.isEmpty
                          ? LetterAvatar(j.company.isNotEmpty ? j.company : j.post.source, size: 46)
                          : OppThumb(post: j.post, size: 46, radius: 12, icon: Icons.work_outline_rounded, cacheWidth: 160),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.22)),
                          const SizedBox(height: 3),
                          Text(
                            [if (j.company.isNotEmpty) j.company, if (j.location.isNotEmpty) j.location].join(' · ').ifEmpty(j.post.source),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: AppColors.text2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    if (j.match != null) MatchRing(value: j.match!, size: 40) else if (isNew) _Pill('New', color: oppColor),
                  ],
                ),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (j.type.isNotEmpty) _Pill(j.type, icon: Icons.schedule_rounded),
                    if (j.workplace.isNotEmpty) _Pill(j.workplace[0].toUpperCase() + j.workplace.substring(1), icon: j.workplace == 'remote' ? Icons.home_work_outlined : Icons.apartment_rounded),
                    if (j.level.isNotEmpty) _Pill(j.level, icon: Icons.stairs_outlined),
                    if (j.salary.isNotEmpty) _Pill(j.salary, icon: Icons.payments_outlined, color: AppColors.success),
                    if (j.info?.legit case final l?) LegitBadge(score: l),
                  ],
                ),
                const SizedBox(height: Space.s),
                Row(
                  children: [
                    TgAvatar(chatId: j.post.chatId, title: j.post.source, size: 16, accountId: j.post.account),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${j.post.source} · ${agoText(j.post.date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.text3)),
                    ),
                    if (j.closed)
                      _Pill('Closed', color: AppColors.text3)
                    else if (left != null)
                      _Pill(left == 0 ? 'Closes today' : 'Closes in $left d', color: urgent ? AppColors.danger : AppColors.text2, icon: Icons.timer_outlined),
                    const SizedBox(width: 4),
                    InkResponse(
                      radius: 20,
                      onTap: () async {
                        final store = ref.read(opportunityProvider.notifier);
                        if (tracked == null) {
                          await store.track(j, JobStatus.saved);
                          if (context.mounted) showSnack(context, 'Saved to your applications', icon: Icons.bookmark_added_outlined);
                        } else if (tracked == JobStatus.saved) {
                          await store.untrack(j.key);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          tracked == null ? Icons.bookmark_border_rounded : (tracked == JobStatus.saved ? Icons.bookmark_rounded : Icons.task_alt_rounded),
                          color: tracked == null ? AppColors.text3 : oppColor,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A ring showing how well a job fits, 0-100.
class MatchRing extends StatelessWidget {
  const MatchRing({super.key, required this.value, this.size = 44});
  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = value >= 75 ? AppColors.success : (value >= 50 ? oppColor : AppColors.text3);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(value: value / 100, strokeWidth: 3.5, color: c, backgroundColor: c.withValues(alpha: 0.15), strokeCap: StrokeCap.round),
          Center(child: Text('$value', style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, color: AppColors.text))),
        ],
      ),
    );
  }
}

// ---- sources and settings -------------------------------------------------------------

Future<void> showSourcesSheet(BuildContext context, WidgetRef ref) => showAppSheet<void>(
  context,
  initialSize: 0.7,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final o = ref.watch(opportunityProvider);
      Widget section(OppKind k) {
        final list = o.sourcesOf(k);
        final feed = ref.watch(oppFeedProvider(k));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(k == OppKind.event ? Icons.event_rounded : Icons.work_outline_rounded, size: 18, color: oppColor),
                const SizedBox(width: Space.s),
                Expanded(child: Text(k == OppKind.event ? 'EVENT CHANNELS' : 'JOB CHANNELS', style: context.text.labelSmall)),
                TextButton.icon(onPressed: () => addSources(context, ref, k), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
              ],
            ),
            if (list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Text('None yet.', style: context.text.bodySmall)),
            for (final s in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TgAvatar(chatId: s.chatId, title: s.title, size: 38, accountId: s.account),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.hidden ? AppColors.text3 : AppColors.text)),
                subtitle: Text(
                  feed.errors[s.key] != null ? 'Couldn\'t read it' : '${feed.bySource[s.key]?.length ?? 0} posts read${s.hidden ? ' · hidden' : ''}',
                  style: context.text.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: s.hidden ? 'Show' : 'Hide',
                      icon: Icon(s.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                      onPressed: () => ref.read(opportunityProvider.notifier).setSources(k, [for (final x in list) x.key == s.key ? x.copyWith(hidden: !x.hidden) : x]),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => ref.read(opportunityProvider.notifier).setSources(k, [for (final x in list) if (x.key != s.key) x]),
                    ),
                  ],
                ),
              ),
          ],
        );
      }

      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Text('Sources', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text('A channel can feed both tabs. Hidden ones stay saved but out of the lists.', style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          section(OppKind.event),
          const SizedBox(height: Space.l),
          section(OppKind.job),
        ],
      );
    },
  ),
);

Future<void> editProfile(BuildContext context, WidgetRef ref) async {
  final o = ref.read(opportunityProvider);
  final out = await showFieldsSheet(
    context,
    icon: Icons.badge_outlined,
    title: 'Your profile',
    subtitle: 'Used only to score jobs and draft applications.',
    color: oppColor,
    fields: [
      SheetField(
        'profile',
        label: 'About you',
        initial: o.profile,
        maxLines: 8,
        hint: 'e.g. Name. Flutter developer, 3 years. Dart, Firebase, REST. BSc Computer Science. Want remote or Addis Ababa, full-time, from 40,000 ETB a month.',
      ),
      SheetField('city', label: 'Your city (optional)', initial: o.city, hint: 'e.g. Addis Ababa'),
    ],
  );
  if (out == null) return;
  final store = ref.read(opportunityProvider.notifier);
  await store.setProfile(out['profile'] ?? '');
  await store.setCity(out['city'] ?? '');
}
