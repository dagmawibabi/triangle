import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../chat/data/chat_controller.dart';
import '../../settings/data/settings.dart';
import '../../telegram/data/telegram_store.dart';
import '../../telegram/presentation/tg_avatar.dart';
import '../online_alerts.dart';
import '../reminders.dart';
import '../watch_engine.dart';
import '../watches.dart';
import '../device_events.dart';
import '../tool_allowlist.dart';
import 'automation_widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../integrations/app_toolkits.dart';
import '../../integrations/integrations_store.dart';
import '../../account/account_switcher.dart';
import '../../../infrastructure/telegram/accounts.dart';

String watchTrigger(Watch w, TelegramStore store) => switch (w.scope) {
  WatchScope.chats => w.chatIds.map((id) => store.chat(id)?.title ?? 'chat $id').join(', '),
  WatchScope.folder => 'Folder ${store.folders.where((f) => f.id == w.folderId).firstOrNull?.title ?? w.folderId}',
  WatchScope.schedule => w.dailyAt != null ? 'Every day at ${w.dailyAt}' : 'Every ${_period(w.everyMinutes ?? 60)}',
  WatchScope.app =>
    '${w.app == null || w.app == 'any' ? 'Any app' : appLabel(w.app!)}${w.query.isEmpty ? '' : ': ${w.query}'} · every ${_period(w.everyMinutes ?? 15)}',
  WatchScope.device => w.device?.describe() ?? 'A phone event',
  _ => w.scope.label,
};

IconData watchModeIcon(WatchMode m) => switch (m) {
  WatchMode.notify => Icons.notifications_none_rounded,
  WatchMode.summarize => Icons.short_text_rounded,
  WatchMode.act => Icons.bolt_rounded,
};

IconData watchScopeIcon(WatchScope s) => switch (s) {
  WatchScope.chats => Icons.forum_outlined,
  WatchScope.allDms => Icons.person_outline_rounded,
  WatchScope.allGroups => Icons.groups_outlined,
  WatchScope.allChannels => Icons.campaign_outlined,
  WatchScope.mentions => Icons.alternate_email_rounded,
  WatchScope.folder => Icons.folder_outlined,
  WatchScope.schedule => Icons.schedule_rounded,
  WatchScope.app => Icons.apps_rounded,
  WatchScope.device => Icons.phone_android_rounded,
};

/// Short labels for the trigger grid.
String _scopeShort(WatchScope s) => switch (s) {
  WatchScope.chats => 'Chats',
  WatchScope.allDms => 'All DMs',
  WatchScope.allGroups => 'Groups',
  WatchScope.allChannels => 'Channels',
  WatchScope.mentions => 'Mentions',
  WatchScope.folder => 'Folder',
  WatchScope.schedule => 'Schedule',
  WatchScope.app => 'App',
  WatchScope.device => 'Phone',
};

String _scopeExplain(WatchScope s) => switch (s) {
  WatchScope.chats => 'New messages in the chats you pick.',
  WatchScope.allDms => 'Any new direct message from a person.',
  WatchScope.allGroups => 'New messages in any group you\'re in.',
  WatchScope.allChannels => 'New posts in any channel you follow.',
  WatchScope.mentions => 'Whenever someone @mentions or replies to you.',
  WatchScope.folder => 'New messages in one of your chat folders.',
  WatchScope.schedule => 'At a time of day, or every so often. No message needed.',
  WatchScope.app => 'Checks a connected app (Gmail, Slack…) for new things that match.',
  WatchScope.device => 'Something on the phone: battery, Wi-Fi, a place, an app opening.',
};

String _period(int minutes) => minutes < 60
    ? '$minutes min'
    : minutes % 60 == 0
    ? '${minutes ~/ 60} h'
    : '${minutes ~/ 60} h ${minutes % 60} min';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inHours < 48) return 'yesterday';
  return DateFormat('d MMM').format(t);
}

String _when(DateTime t) {
  final now = DateTime.now();
  final d = t.difference(now);
  if (d.inMinutes < 1) return 'any moment';
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day).difference(today).inDays;
  final hm = DateFormat('HH:mm').format(t);
  if (day == 0) return 'today $hm';
  if (day == 1) return 'tomorrow $hm';
  return DateFormat('EEE d MMM HH:mm').format(t);
}

/// When a schedule or app watch runs next, as the engine's tick decides it.
DateTime? watchNextRun(Watch w) {
  if (!w.enabled || (w.scope != WatchScope.schedule && w.scope != WatchScope.app)) return null;
  final now = DateTime.now();
  final last = w.lastRunAt;
  DateTime? next;
  final every = w.everyMinutes ?? (w.scope == WatchScope.app ? 15 : null);
  if (every != null) {
    next = last == null ? now : last.add(Duration(minutes: every));
    if (next.isBefore(now)) next = now;
  } else if (w.dailyAt != null) {
    final parts = w.dailyAt!.split(':');
    final h = int.tryParse(parts.first) ?? 0, m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final today = DateTime(now.year, now.month, now.day, h, m);
    next = (last == null || last.isBefore(today)) && now.isBefore(today.add(const Duration(hours: 2)))
        ? (today.isBefore(now) ? now : today)
        : today.add(const Duration(days: 1));
  }
  if (next != null && w.quietAtNight && Watch.isNight(next)) {
    final morning = DateTime(next.year, next.month, next.day, 8);
    next = next.hour >= 22 ? morning.add(const Duration(days: 1)) : morning;
  }
  return next;
}

Future<void> _runWatchNow(BuildContext context, WidgetRef ref, Watch w) async {
  showSnack(context, 'Running "${w.name}"…', icon: Icons.play_arrow_rounded);
  final problem = await ref.read(watchEngineProvider).runNow(w);
  if (!context.mounted) return;
  showSnack(
    context,
    problem ?? 'Ran "${w.name}". Its update is in its chat, with a notification if you were away.',
    icon: problem == null ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
  );
}

void _openEditor(BuildContext context, {Watch? watch, Watch? draft}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => WatchEditor(watch: watch, draft: draft),
  ),
);

/// A ready-made starting point for a new watch.
class _Template {
  const _Template(this.title, this.subtitle, this.icon, this.make);
  final String title, subtitle;
  final IconData icon;
  final Watch Function() make;
  bool get needsTelegram => make().scope.needsTelegram;
}

Watch _draft({
  required String name,
  required WatchScope scope,
  required WatchMode mode,
  String instructions = '',
  String? dailyAt,
  int? everyMinutes,
  String? app,
  String query = '',
  DeviceCondition? device,
}) => Watch(
  id: '',
  name: name,
  scope: scope,
  mode: mode,
  instructions: instructions,
  dailyAt: dailyAt,
  everyMinutes: everyMinutes,
  app: app,
  query: query,
  device: device,
  createdAt: DateTime.now(),
);

final _templates = <_Template>[
  _Template(
    'Tell me when someone posts',
    'Pick chats, get a ping',
    Icons.notifications_active_outlined,
    () => _draft(name: 'New posts', scope: WatchScope.chats, mode: WatchMode.notify),
  ),
  _Template(
    'Morning briefing',
    'Every day at 08:00',
    Icons.wb_sunny_outlined,
    () => _draft(
      name: 'Morning briefing',
      scope: WatchScope.schedule,
      mode: WatchMode.summarize,
      dailyAt: '08:00',
      instructions:
          'Summarise what happened in my chats overnight: what needs a reply first, then anything important. Skip small talk and memes.',
    ),
  ),
  _Template(
    'Answer DMs while I\'m busy',
    'Polite replies, urgent ones to you',
    Icons.reply_all_rounded,
    () => _draft(
      name: 'Busy replies',
      scope: WatchScope.allDms,
      mode: WatchMode.act,
      instructions: 'Reply politely in their language that I\'m busy and will get back to them soon. If it sounds urgent, notify me instead of replying.',
    ),
  ),
  _Template(
    'Mentions digest',
    'A short note when you\'re tagged',
    Icons.alternate_email_rounded,
    () => _draft(
      name: 'Mentions',
      scope: WatchScope.mentions,
      mode: WatchMode.summarize,
      instructions: 'Tell me who mentioned me, where, and what they want from me in one or two lines.',
    ),
  ),
  _Template(
    'Important emails',
    'Gmail, every 30 min',
    Icons.mail_outline_rounded,
    () => _draft(
      name: 'Important emails',
      scope: WatchScope.app,
      mode: WatchMode.summarize,
      app: 'gmail',
      everyMinutes: 30,
      query: 'emails that need my reply or are from people I know',
      instructions: 'Skip newsletters and promotions. One line per email: who, what, and whether it needs a reply.',
    ),
  ),
  _Template(
    'Low battery heads-up',
    'At 20%, while not charging',
    Icons.battery_alert_rounded,
    () => _draft(
      name: 'Low battery',
      scope: WatchScope.device,
      mode: WatchMode.notify,
      device: const DeviceCondition(kind: DeviceTriggerKind.batteryLow),
    ),
  ),
];

enum _Filter { all, on, off }

// ---------------------------------------------------------------------------
// Watches screen
// ---------------------------------------------------------------------------

/// Watches and routines: what they listen to and what they do.
class WatchesScreen extends ConsumerStatefulWidget {
  const WatchesScreen({super.key});

  @override
  ConsumerState<WatchesScreen> createState() => _WatchesScreenState();
}

class _WatchesScreenState extends ConsumerState<WatchesScreen> {
  _Filter _filter = _Filter.all;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keeps "in 5 min" / "2 h ago" fresh while the screen is open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(watchStoreProvider);
    final store = ref.watch(telegramStoreProvider);
    final accounts = ref.watch(accountsProvider);
    final telegram = ref.watch(telegramConnectedProvider) || accounts.signedIn.isNotEmpty;
    final custom = all.where((w) => !w.builtIn).toList()
      ..sort((a, b) {
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return (b.lastRunAt ?? b.createdAt).compareTo(a.lastRunAt ?? a.createdAt);
      });
    final on = custom.where((w) => w.enabled).length;
    final shown = switch (_filter) {
      _Filter.all => custom,
      _Filter.on => custom.where((w) => w.enabled).toList(),
      _Filter.off => custom.where((w) => !w.enabled).toList(),
    };
    final templates = _templates.where((t) => telegram || !t.needsTelegram).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Watches')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.bg,
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New watch'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 104),
        children: [
          _StatusHeader(active: on + all.where((w) => w.builtIn && w.enabled).length),
          if (all.where((w) => w.builtIn).firstOrNull case final checkIn?) ...[
            const SizedBox(height: Space.m),
            _CheckInCard(watch: checkIn),
          ],

          // ---- your watches ----
          _SectionHeader('Your watches', count: custom.isEmpty ? null : '$on of ${custom.length} on'),
          if (custom.length >= 3) ...[
            Wrap(
              spacing: 6,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    label: Text(switch (f) {
                      _Filter.all => 'All ${custom.length}',
                      _Filter.on => 'On $on',
                      _Filter.off => 'Paused ${custom.length - on}',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
          ],
          if (custom.isEmpty)
            _EmptyWatches(templates: templates)
          else ...[
            for (final w in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: _WatchCard(watch: w, store: store),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xl),
                child: Text('Nothing here.', textAlign: TextAlign.center, style: context.text.bodySmall),
              ),
            const SizedBox(height: Space.s),
            _TemplateStrip(templates: templates),
          ],

          // ---- people & reminders ----
          if (telegram) const _OnlineAlerts(),
          const _Reminders(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.count, this.trailing});
  final String title;
  final String? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xxl, Space.xs, Space.s),
    child: Row(
      children: [
        Text(title, style: context.text.titleMedium),
        if (count != null) ...[
          const SizedBox(width: Space.s),
          Text(count!, style: context.text.labelSmall?.copyWith(fontFeatures: tabularFigures)),
        ],
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// A small rounded label: "Act", "Silent", "Every 15 min".
class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.icon, this.color, this.strong = false});
  final String label;
  final IconData? icon;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: strong ? c.withValues(alpha: 0.14) : AppColors.surface2, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c, fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

/// A square, rounded icon tile at the start of a card.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.active = true, this.size = 40});
  final IconData icon;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: active ? AppColors.accentDim : AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Icon(icon, size: size * 0.5, color: active ? AppColors.accent : AppColors.text3),
  );
}

/// A softly breathing dot that says "live".
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color, required this.live});
  final Color color;
  final bool live;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.live) _c.repeat();
  }

  @override
  void didUpdateWidget(_LiveDot old) {
    super.didUpdateWidget(old);
    if (widget.live && !_c.isAnimating) _c.repeat();
    if (!widget.live && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 18,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          if (widget.live)
            Container(
              width: 8 + 10 * _c.value,
              height: 8 + 10 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ],
      ),
    ),
  );
}

/// Whether watches are running, in the background or not, and what they've
/// seen since the app started.
class _StatusHeader extends ConsumerWidget {
  const _StatusHeader({required this.active});
  final int active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return ValueListenableBuilder<WatchStatus>(
      valueListenable: ref.read(watchEngineProvider).status,
      builder: (context, st, _) {
        final live = st.listening && s.proactive;
        final color = !s.proactive ? AppColors.warning : (live ? AppColors.success : AppColors.text3);
        final title = !s.proactive ? 'All watches paused' : (live ? 'Listening' : 'Not listening');
        final sub = !s.proactive
            ? 'Proactivity is off in Settings.'
            : st.background
            ? 'Runs in the background${s.notifications ? '' : ' · notifications are off'}'
            : (s.keepAlive || s.backgroundAlways)
            ? 'Background service starts when a watch is on'
            : 'Only while the app is open';
        Widget stat(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: context.text.titleLarge?.copyWith(fontFeatures: tabularFigures, height: 1.1)),
              const SizedBox(height: 2),
              Text(label, style: context.text.labelSmall),
            ],
          ),
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.l),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: !s.proactive ? AppColors.warning.withValues(alpha: 0.4) : AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _LiveDot(color: color, live: live),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.titleSmall),
                        Text(sub, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (!s.proactive)
                    FilledButton(onPressed: () => ref.read(settingsProvider.notifier).setProactive(true), child: const Text('Turn on'))
                  else
                    Icon(
                      st.background ? Icons.nightlight_round : Icons.phone_android_rounded,
                      size: 18,
                      color: st.background ? AppColors.success : AppColors.text3,
                    ),
                  const SizedBox(width: Space.s),
                ],
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  stat('$active', 'active'),
                  stat('${st.heard}', 'heard'),
                  stat('${st.matched}', 'matched'),
                  stat('${st.opened}', 'chats open'),
                ],
              ),
              if (st.last != null) ...[
                const SizedBox(height: Space.m),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: AppColors.text2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Last match: ${st.last}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
              if (st.error != null) ...[
                const SizedBox(height: Space.s),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(st.error!, style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One watch: what starts it, what it does, when it ran and runs next.
class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch, required this.store});
  final Watch watch;
  final TelegramStore store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = watch;
    final next = watchNextRun(w);
    final trigger = watchTrigger(w, store);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: w.enabled ? 1 : 0.6,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () => _openEditor(context, watch: w),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...leadRow(_IconTile(watchScopeIcon(w.scope), active: w.enabled), Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            trigger.isEmpty ? w.scope.label : trigger,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: w.enabled,
                      onChanged: (v) => ref.read(watchStoreProvider.notifier).update(w.id, (x) => x.copyWith(enabled: v)),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Pill(
                            w.mode.label,
                            icon: watchModeIcon(w.mode),
                            color: w.mode == WatchMode.act ? AppColors.warning : null,
                            strong: w.mode == WatchMode.act,
                          ),
                          if (!w.notify) const _Pill('Silent', icon: Icons.notifications_off_outlined),
                          if (next != null) _Pill('Next ${_when(next)}', icon: Icons.schedule_rounded),
                          if (w.lastRunAt != null)
                            _Pill('Ran ${_ago(w.lastRunAt!)} · ${w.runs}×', icon: Icons.history_rounded)
                          else
                            const _Pill('Not fired yet'),
                        ],
                      ),
                    ),
                    _WatchMenu(watch: w),
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

class _WatchMenu extends ConsumerWidget {
  const _WatchMenu({required this.watch});
  final Watch watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = watch;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, color: AppColors.text3),
      onSelected: (v) async {
        switch (v) {
          case 'run':
            await _runWatchNow(context, ref, w);
          case 'chat':
            ref.read(chatControllerProvider.notifier).open(w.conversationId!);
            Navigator.of(context).popUntil((r) => r.isFirst);
          case 'copy':
            _openEditor(context, draft: w.copyWith(name: '${w.name} (copy)'));
          case 'delete':
            if (await confirmDelete(context, title: 'Delete this watch?', message: '"${w.name}" stops watching. Its chat stays.')) {
              await ref.read(watchStoreProvider.notifier).remove(w.id);
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'run', child: _MenuRow(Icons.play_arrow_rounded, 'Run now')),
        if (w.conversationId != null) const PopupMenuItem(value: 'chat', child: _MenuRow(Icons.forum_outlined, 'Open its chat')),
        const PopupMenuItem(value: 'copy', child: _MenuRow(Icons.copy_rounded, 'Duplicate')),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(Icons.delete_outline_rounded, 'Delete', color: AppColors.danger),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color ?? AppColors.text2),
      const SizedBox(width: Space.m),
      Text(label, style: TextStyle(color: color)),
    ],
  );
}

/// No watches yet: what they are, and a few to start from.
class _EmptyWatches extends StatelessWidget {
  const _EmptyWatches({required this.templates});
  final List<_Template> templates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.m),
        child: Text(
          'A watch listens for something (a message, a time, a new email, your phone) and then notifies you, '
          'writes a summary, or acts for you. Start from one of these, or just ask in chat.',
          style: context.text.bodySmall,
        ),
      ),
      LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - Space.s) / 2;
          return Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final t in templates)
                SizedBox(
                  width: w,
                  child: _TemplateCard(template: t),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// Templates as a sideways strip under the list.
class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({required this.templates});
  final List<_Template> templates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, Space.s),
        child: Text('START FROM AN IDEA', style: context.text.labelSmall),
      ),
      SizedBox(
        height: 116,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemCount: templates.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.s),
          itemBuilder: (_, i) => SizedBox(width: 168, child: _TemplateCard(template: templates[i])),
        ),
      ),
    ],
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template});
  final _Template template;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(Radii.l),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: () => _openEditor(context, draft: template.make()),
      child: Container(
        height: 116,
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconTile(template.icon, size: 32),
                const Spacer(),
                Icon(Icons.add_rounded, size: 18, color: AppColors.text3),
              ],
            ),
            const Spacer(),
            Text(template.title, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(template.subtitle, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}

/// Reminders and scheduled jobs the assistant set up ("remind me to walk in
/// 5 minutes", "every Sunday at 20:00 summarise my channels").
class _Reminders extends ConsumerWidget {
  const _Reminders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(reminderStoreProvider);
    final store = ref.read(reminderStoreProvider.notifier);
    final accounts = ref.watch(accountsProvider);
    final shown = all.where((r) => r.enabled || r.repeats).toList()
      ..sort((a, b) => (a.next ?? DateTime(9999)).compareTo(b.next ?? DateTime(9999)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('Reminders & jobs', count: shown.isEmpty ? null : '${shown.length}'),
        if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.l),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                _IconTile(Icons.alarm_rounded, active: false, size: 36),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    'None yet. Ask in chat: "remind me to walk in 5 minutes", "every weekday at 9 remind me to stand up", '
                    '"every Sunday at 20:00 summarise my channels".',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: r.enabled ? 1 : 0.6,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.l),
                  border: Border.all(color: AppColors.line),
                ),
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...leadRow(_IconTile(r.isJob ? Icons.smart_toy_outlined : Icons.alarm_rounded, active: r.enabled), Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.text, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (r.isJob) ...[
                            const SizedBox(height: 2),
                            Text(r.prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                          ],
                          const SizedBox(height: Space.s),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Pill(r.isJob ? 'Job' : 'Reminder', icon: r.isJob ? Icons.bolt_rounded : Icons.alarm_rounded),
                              if (r.cron != null) _Pill(Cron.describe(r.cron!), icon: Icons.repeat_rounded),
                              if (r.next != null && r.enabled) _Pill('Next ${_when(r.next!)}', icon: Icons.schedule_rounded),
                              if (r.isJob && accounts.hasSeveral)
                                _Pill(accountScopeLabel(accounts, r.accountIds), icon: Icons.person_outline_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Switch(
                          value: r.enabled,
                          onChanged: r.next == null && !r.repeats ? null : (v) => store.update(r.id, (x) => x.copyWith(enabled: v)),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          icon: Icon(Icons.more_horiz_rounded, color: AppColors.text3),
                          onSelected: (v) => switch (v) {
                            'test' => store.runNow(r),
                            'accounts' =>
                              pickAccountScope(
                                context,
                                initial: r.accountIds,
                                title: 'ACCOUNTS THIS JOB USES',
                                note: 'When it runs, the assistant may use only these Telegram accounts.',
                              ).then((picked) async {
                                if (picked != null) {
                                  await store.update(r.id, (x) => x.copyWith(accountIds: picked.ids, allAccounts: picked.ids == null));
                                }
                              }),
                            'delete' =>
                              confirmDelete(context, title: 'Delete this reminder?', message: '"${r.text}" won\'t remind you again.').then((
                                ok,
                              ) async {
                                if (ok) await store.remove(r.id);
                              }),
                            _ => null,
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'test', child: _MenuRow(Icons.play_arrow_rounded, 'Run now')),
                            if (r.isJob && accounts.hasSeveral)
                              const PopupMenuItem(value: 'accounts', child: _MenuRow(Icons.person_outline_rounded, 'Accounts…')),
                            PopupMenuItem(
                              value: 'delete',
                              child: _MenuRow(Icons.delete_outline_rounded, 'Delete', color: AppColors.danger),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Watch builder
// ---------------------------------------------------------------------------

class WatchEditor extends ConsumerStatefulWidget {
  const WatchEditor({super.key, this.watch, this.draft});

  /// The watch being edited; null for a new one.
  final Watch? watch;

  /// Starting values for a new watch (a template or a duplicate).
  final Watch? draft;

  @override
  ConsumerState<WatchEditor> createState() => _WatchEditorState();
}

class _WatchEditorState extends ConsumerState<WatchEditor> {
  Watch? get _init => widget.watch ?? widget.draft;

  late final _name = TextEditingController(text: _init?.name ?? '');
  late final _instructions = TextEditingController(text: _init?.instructions ?? '');
  late WatchScope _scope = _init?.scope ?? (ref.read(telegramConnectedProvider) ? WatchScope.chats : WatchScope.app);
  late WatchMode _mode = _init?.mode ?? WatchMode.notify;
  late List<int> _chatIds = [...?_init?.chatIds];
  late int? _folderId = _init?.folderId;
  late String? _dailyAt = _init?.dailyAt ?? '08:00';
  late int? _every = _init?.everyMinutes;
  late bool _includeMuted = _init?.includeMuted ?? true;
  late bool _notify = _init?.notify ?? true;
  late String _app = _init?.app ?? 'gmail';
  late final _query = TextEditingController(text: _init?.query ?? '');
  late DeviceCondition _device = _init?.device ?? const DeviceCondition(kind: DeviceTriggerKind.batteryLow);
  late ToolAllowlist? _tools = _init?.tools;
  late String _model = _init?.model ?? WatchModel.free;
  bool _advanced = false;
  bool _saving = false;

  /// The accounts it covers (null: all).
  late List<String>? _accounts = _init?.accountIds;

  /// A folder watch's account: folder ids belong to one account.
  late String _folderAccount = _init?.scope == WatchScope.folder
      ? (_init?.folderAccountId ?? legacyAccountId)
      : ref.read(activeAccountIdProvider);

  @override
  void initState() {
    super.initState();
    _name.addListener(_refresh);
    _query.addListener(_refresh);
    _instructions.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _query.dispose();
    super.dispose();
  }

  /// Plain notifications only make sense for messages and phone events;
  /// schedules and app watches always need the assistant.
  bool get _notifyAllowed => _scope.needsTelegram || _scope == WatchScope.device;
  WatchMode get _effectiveMode => !_notifyAllowed && _mode == WatchMode.notify ? WatchMode.summarize : _mode;

  /// A name from what it does, when none is typed.
  String _autoName(TelegramStore store) {
    final what = switch (_scope) {
      WatchScope.chats when _chatIds.length == 1 => store.chat(_chatIds.first)?.title ?? 'Chat',
      WatchScope.chats => _chatIds.isEmpty ? 'Chats' : '${_chatIds.length} chats',
      WatchScope.schedule when _every == null => 'Daily ${_dailyAt ?? '08:00'}',
      WatchScope.schedule => 'Every ${_period(_every!)}',
      WatchScope.app => _app == 'any' ? 'Apps' : appLabel(_app),
      WatchScope.device => _device.kind.label,
      _ => _scope.label,
    };
    final verb = switch (_effectiveMode) {
      WatchMode.notify => '',
      WatchMode.summarize => ' summary',
      WatchMode.act => ' autopilot',
    };
    return '$what$verb';
  }

  Watch _compose(String id, TelegramStore store) {
    final base = widget.watch;
    final schedule = _scope == WatchScope.schedule;
    final appWatch = _scope == WatchScope.app;
    final name = _name.text.trim().isEmpty ? _autoName(store) : _name.text.trim();
    return Watch(
      id: id,
      name: name,
      scope: _scope,
      mode: _effectiveMode,
      enabled: base?.enabled ?? true,
      chatIds: _chatIds,
      folderId: _folderId,
      instructions: _instructions.text.trim(),
      includeMuted: _includeMuted,
      notify: _notify,
      dailyAt: schedule && _every == null ? _dailyAt : null,
      everyMinutes: schedule ? _every : (appWatch ? (_every ?? 15) : null),
      conversationId: base?.conversationId,
      lastRunAt: base?.lastRunAt,
      runs: base?.runs ?? 0,
      createdAt: base?.createdAt ?? DateTime.now(),
      app: appWatch ? _app : null,
      query: appWatch ? _query.text.trim() : '',
      // Kept as they were: the editor doesn't show them.
      builtIn: base?.builtIn ?? false,
      quietAtNight: base?.quietAtNight ?? widget.draft?.quietAtNight ?? false,
      accountIds: _scope == WatchScope.folder ? null : _accounts,
      folderAccountId: _scope == WatchScope.folder ? _folderAccount : null,
      device: _scope == WatchScope.device ? _device : null,
      tools: _tools,
      model: _model,
    );
  }

  /// What still has to be filled in before it can be saved.
  String? _missing() {
    if (_scope == WatchScope.chats && _chatIds.isEmpty) return 'Pick at least one chat';
    if (_scope == WatchScope.folder && _folderId == null) return 'Pick a folder';
    if (_scope == WatchScope.device && _device.kind.needsPlace && !_device.hasPlace) {
      return 'Set the place: tap "Use where I am" while you are there';
    }
    if (_scope == WatchScope.device) {
      final d = _device;
      if (d.kind.usesUrl && d.url.trim().isEmpty) return 'Add the page to check';
      if (d.kind == DeviceTriggerKind.youtubeUpload && d.query.trim().isEmpty) return 'Add the channel';
      if ((d.kind == DeviceTriggerKind.mobileData || d.kind == DeviceTriggerKind.storageLow) && d.amount <= 0) return 'Add the amount';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_missing() case final problem?) {
      showSnack(context, problem, icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _saving = true);
    final store = ref.read(watchStoreProvider.notifier);
    final tg = ref.read(telegramStoreProvider);
    if (widget.watch == null) {
      await store.add((id) => _compose(id, tg));
    } else {
      await store.update(widget.watch!.id, (w) => _compose(w.id, tg));
    }
    if (!mounted) return;
    showSnack(context, widget.watch == null ? 'Watch created' : 'Saved');
    Navigator.pop(context);
  }

  Future<void> _pickChats() async {
    final picked = await Navigator.of(context).push<List<int>>(MaterialPageRoute(builder: (_) => _ChatPicker(selected: _chatIds)));
    if (picked != null) setState(() => _chatIds = picked);
  }

  void _addInstruction(String line) {
    final t = _instructions.text.trimRight();
    _instructions.text = t.isEmpty ? line : (t.endsWith('.') || t.endsWith('!') || t.endsWith('?') ? '$t $line' : '$t. $line');
    _instructions.selection = TextSelection.collapsed(offset: _instructions.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final accounts = ref.watch(accountsProvider);
    // The folder's account may not be signed in any more: fall back to the
    // account on screen.
    if (accounts.byId(_folderAccount)?.signedIn != true && accounts.signedIn.isNotEmpty) {
      _folderAccount = accounts.activeId;
    }
    final folderStore = ref.watch(accountStoreProvider(_folderAccount));
    final telegram = ref.watch(telegramConnectedProvider) || accounts.signedIn.isNotEmpty;
    final connected = ref.watch(integrationsProvider).connected;
    final w = widget.watch;
    final mode = _effectiveMode;
    final usesAi = mode != WatchMode.notify;
    final missing = _missing();

    return Scaffold(
      appBar: AppBar(
        title: Text(w == null ? 'New watch' : 'Edit watch'),
        actions: [
          if (w?.conversationId != null)
            IconButton(
              tooltip: 'Open its chat',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () {
                ref.read(chatControllerProvider.notifier).open(w!.conversationId!);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          if (w != null)
            IconButton(tooltip: 'Run now', icon: const Icon(Icons.play_arrow_rounded), onPressed: () => _runWatchNow(context, ref, w)),
          const SizedBox(width: Space.xs),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              if (missing != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: AppColors.text3),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(missing, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: Space.m),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(132, 48)),
                onPressed: missing == null ? _save : null,
                icon: _saving
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg))
                    : Icon(w == null ? Icons.check_rounded : Icons.save_outlined, size: 18),
                label: Text(w == null ? 'Create watch' : 'Save'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.x4),
        children: [
          // ---- name and live summary ----
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            style: context.text.titleLarge,
            decoration: InputDecoration(
              hintText: _autoName(store),
              hintStyle: context.text.titleLarge?.copyWith(color: AppColors.text3),
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s),
              suffixIcon: Icon(Icons.edit_outlined, size: 18, color: AppColors.text3),
            ),
          ),
          const SizedBox(height: Space.s),
          _SummaryCard(
            trigger: _scope == WatchScope.folder
                ? 'Folder ${folderStore.folders.where((f) => f.id == _folderId).firstOrNull?.title ?? '…'}'
                : watchTrigger(_compose('', store), store),
            scope: _scope,
            mode: mode,
            notify: _notify,
          ),

          // ---- 1. when ----
          const _Step(number: 1, title: 'When', subtitle: 'What starts it'),
          _TriggerGrid(value: _scope, telegram: telegram, onChanged: (s) => setState(() => _scope = s)),
          const SizedBox(height: Space.s),
          Text(_scopeExplain(_scope), style: context.text.bodySmall),
          if (!telegram) ...[
            const SizedBox(height: Space.s),
            _Note(
              icon: Icons.link_off_rounded,
              text: 'Connect Telegram (Settings → Apps & web) to watch chats, groups, channels and mentions.',
            ),
          ],
          const SizedBox(height: Space.m),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _triggerOptions(context, store, accounts, folderStore, connected),
          ),

          // ---- 2. then ----
          const _Step(number: 2, title: 'Then', subtitle: 'What it does'),
          Row(
            children: [
              for (final m in WatchMode.values) ...[
                if (m != WatchMode.values.first) const SizedBox(width: Space.s),
                Expanded(
                  child: _ModeCard(
                    mode: m,
                    selected: mode == m,
                    enabled: m != WatchMode.notify || _notifyAllowed,
                    onTap: () => setState(() => _mode = m),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.s),
          Text(
            !_notifyAllowed && _mode == WatchMode.notify
                ? 'Schedules and app watches always use the assistant, so this will summarise.'
                : mode.explanation,
            style: context.text.bodySmall,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !usesAi
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Space.l),
                      TextField(
                        controller: _instructions,
                        minLines: 3,
                        maxLines: 8,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Instructions',
                          alignLabelWithHint: true,
                          hintText: mode == WatchMode.act
                              ? 'e.g. Reply to each new DM politely in their language. If it\'s urgent, notify me.'
                              : 'e.g. Summarise what matters and skip memes.',
                        ),
                      ),
                      const SizedBox(height: Space.s),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s
                              in mode == WatchMode.act
                                  ? const [
                                      'Reply in their language.',
                                      'If it\'s urgent, notify me instead.',
                                      'Keep replies short and friendly.',
                                      'Never share links, money or personal details.',
                                    ]
                                  : const [
                                      'Only what needs my reply.',
                                      'Skip memes and small talk.',
                                      'Keep it to 3 bullet points.',
                                      'Translate to English.',
                                    ])
                            if (!_instructions.text.contains(s))
                              ActionChip(
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                                avatar: Icon(Icons.add_rounded, size: 14, color: AppColors.text2),
                                label: Text(s.substring(0, s.length - 1)),
                                onPressed: () => _addInstruction(s),
                              ),
                        ],
                      ),
                      if (mode == WatchMode.act) ...[
                        const SizedBox(height: Space.m),
                        _Note(
                          icon: Icons.shield_outlined,
                          warning: true,
                          text: switch (ref.watch(settingsProvider).approvalMode) {
                            ApprovalMode.ask =>
                              'Its actions will wait for your approval. To let it act on its own, change Approvals in Settings.',
                            _ => 'It will act without asking, as Approvals in Settings allow.',
                          },
                        ),
                      ],
                    ],
                  ),
          ),

          // ---- 3. delivery ----
          const _Step(number: 3, title: 'Delivery', subtitle: 'How you hear about it'),
          automationCard(context, [
            SwitchListTile(
              secondary: lead(Icon(_notify ? Icons.notifications_active_outlined : Icons.notifications_off_outlined)),
              title: const Text('Notify me'),
              subtitle: Text(
                _notify ? 'A notification each time it fires' : 'Runs quietly; results wait in its chat',
                style: context.text.bodySmall,
              ),
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
            ),
            if (_scope.needsTelegram) ...[
              Divider(height: 1, indent: Space.l, endIndent: Space.l),
              SwitchListTile(
                secondary: lead(const Icon(Icons.volume_off_outlined)),
                title: const Text('Include muted chats'),
                subtitle: Text(_includeMuted ? 'Muted chats count too' : 'Muted chats are ignored', style: context.text.bodySmall),
                value: _includeMuted,
                onChanged: (v) => setState(() => _includeMuted = v),
              ),
            ],
          ]),
          if (_scope != WatchScope.folder && accounts.hasSeveral) ...[
            const SizedBox(height: Space.l),
            AccountScopePicker(
              value: _accounts,
              onChanged: (v) => setState(() => _accounts = v),
              note: _scope.needsTelegram
                  ? 'It hears messages in these accounts, and the assistant may use only them when it runs.'
                  : 'When it runs, the assistant may use only these Telegram accounts.',
            ),
          ],

          // ---- advanced ----
          if (usesAi) ...[
            const SizedBox(height: Space.l),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.m),
                onTap: () => setState(() => _advanced = !_advanced),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.m),
                  child: Row(
                    children: [
                      Text('Advanced', style: context.text.titleSmall),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(
                          '${_tools == null ? 'All tools' : 'Some tools'} · ${WatchModel.label(_model)} model',
                          style: context.text.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AnimatedRotation(
                        turns: _advanced ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded, color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_advanced
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('TOOLS', style: context.text.labelSmall),
                        const SizedBox(height: Space.s),
                        ToolAllowlistTile(value: _tools, onChanged: (v) => setState(() => _tools = v)),
                        const SizedBox(height: Space.l),
                        Text('MODEL', style: context.text.labelSmall),
                        const SizedBox(height: Space.s),
                        AutomationModelTile(value: _model, onChanged: (v) => setState(() => _model = v)),
                      ],
                    ),
            ),
          ],

          // ---- history and delete ----
          if (w != null) ...[
            const SizedBox(height: Space.xl),
            Text(
              [
                'Created ${DateFormat('d MMM y').format(w.createdAt)}',
                if (w.lastRunAt != null) 'last ran ${_ago(w.lastRunAt!)}',
                '${w.runs} run${w.runs == 1 ? '' : 's'}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: context.text.labelSmall,
            ),
            if (!w.builtIn) ...[
              const SizedBox(height: Space.s),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete watch'),
                  onPressed: () async {
                    if (!await confirmDelete(
                      context,
                      title: 'Delete this watch?',
                      message: '"${w.name}" stops watching. Its chat stays.',
                    )) {
                      return;
                    }
                    await ref.read(watchStoreProvider.notifier).remove(w.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// The settings for the picked trigger.
  Widget _triggerOptions(
    BuildContext context,
    TelegramStore store,
    AccountsState accounts,
    TelegramStore folderStore,
    Set<String> connected,
  ) {
    Widget chip(String label, bool selected, VoidCallback onTap, {Widget? avatar}) => ChoiceChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
      avatar: avatar,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
    Widget intervals({required String Function(int) label}) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in const [15, 30, 60, 180, 360, 720])
          chip(label(m), (_every ?? (_scope == WatchScope.app ? 15 : -1)) == m, () => setState(() => _every = m)),
      ],
    );

    switch (_scope) {
      case WatchScope.chats:
        if (_chatIds.isEmpty) {
          return _DashedButton(icon: Icons.add_comment_outlined, label: 'Choose chats to watch', onTap: _pickChats);
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in _chatIds)
              InputChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
                avatar: TgAvatar(chatId: id, title: store.chat(id)?.title ?? '?', size: 22),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(store.chat(id)?.title ?? 'Chat $id', overflow: TextOverflow.ellipsis),
                ),
                onDeleted: () => setState(() => _chatIds = [..._chatIds]..remove(id)),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
              ),
            ActionChip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
              onPressed: _pickChats,
            ),
          ],
        );
      case WatchScope.folder:
        // Folders belong to one account: pick the account, then its folder.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (accounts.hasSeveral) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in accounts.signedIn)
                    chip(
                      a.label,
                      _folderAccount == a.id,
                      () => setState(() {
                        if (_folderAccount != a.id) _folderId = null;
                        _folderAccount = a.id;
                      }),
                      avatar: AccountAvatar(account: a, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: Space.s),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in folderStore.folders)
                  chip(
                    f.title,
                    _folderId == f.id,
                    () => setState(() => _folderId = f.id),
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                  ),
                if (folderStore.folders.isEmpty) Text('No folders in this account.', style: context.text.bodySmall),
              ],
            ),
          ],
        );
      case WatchScope.app:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connected.isEmpty) ...[
              _Note(icon: Icons.extension_outlined, text: 'Connect an app first (Settings → Apps & web → Composio), e.g. Gmail or Slack.'),
              const SizedBox(height: Space.m),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in {...connected, 'any', if (!connected.contains(_app) && _app != 'any') _app})
                  chip(a == 'any' ? 'Any app' : appLabel(a), _app == a, () => setState(() => _app = a)),
              ],
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _query,
              decoration: const InputDecoration(
                labelText: 'Look for',
                hintText: 'e.g. emails from my manager, Slack messages mentioning me',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
            const SizedBox(height: Space.m),
            Text('CHECK EVERY', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            intervals(label: _period),
          ],
        );
      case WatchScope.device:
        return DeviceConditionEditor(value: _device, onChanged: (d) => setState(() => _device = d));
      case WatchScope.schedule:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.today_outlined, size: 16), label: Text('Daily at a time')),
                ButtonSegment(value: false, icon: Icon(Icons.repeat_rounded, size: 16), label: Text('Every so often')),
              ],
              selected: {_every == null},
              onSelectionChanged: (v) => setState(() => _every = v.first ? null : (_every ?? 60)),
            ),
            const SizedBox(height: Space.m),
            if (_every == null)
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.l),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.l),
                  onTap: () async {
                    final parts = (_dailyAt ?? '08:00').split(':');
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                    );
                    if (t != null) {
                      setState(() => _dailyAt = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.l),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        Text(_dailyAt ?? '08:00', style: context.text.headlineMedium?.copyWith(fontFeatures: tabularFigures)),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text('every day', style: context.text.bodySmall)),
                        Icon(Icons.edit_outlined, size: 18, color: AppColors.text3),
                      ],
                    ),
                  ),
                ),
              )
            else
              intervals(label: (m) => 'Every ${_period(m)}'),
          ],
        );
      case WatchScope.allDms:
      case WatchScope.allGroups:
      case WatchScope.allChannels:
      case WatchScope.mentions:
        return const SizedBox(width: double.infinity);
    }
  }
}

/// A numbered step heading in the builder.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.subtitle});
  final int number;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x4, bottom: Space.m),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
          child: Text(
            '$number',
            style: TextStyle(color: AppColors.bg, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: Space.m),
        Text(title, style: context.text.titleMedium),
        const SizedBox(width: Space.s),
        Text(subtitle, style: context.text.labelSmall),
      ],
    ),
  );
}

/// "When ... → then ..." in one card, updated as the form changes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.trigger, required this.scope, required this.mode, required this.notify});
  final String trigger;
  final WatchScope scope;
  final WatchMode mode;
  final bool notify;

  @override
  Widget build(BuildContext context) {
    final when = switch (scope) {
      WatchScope.chats => trigger.isEmpty ? 'a message arrives in chats you pick' : 'a message arrives in $trigger',
      WatchScope.allDms => 'anyone sends you a DM',
      WatchScope.allGroups => 'a message arrives in any group',
      WatchScope.allChannels => 'any channel posts',
      WatchScope.mentions => 'someone mentions you',
      WatchScope.folder => 'a message arrives in ${trigger.replaceFirst('Folder ', 'folder ')}',
      WatchScope.schedule => trigger.replaceFirst('Every', 'every'),
      WatchScope.app => trigger,
      WatchScope.device => trigger.isEmpty ? 'something happens on the phone' : trigger,
    };
    final then = switch (mode) {
      WatchMode.notify => 'send you a notification',
      WatchMode.summarize => notify ? 'write a short summary and notify you' : 'write a short summary in its chat',
      WatchMode.act => notify ? 'follow your instructions and tell you' : 'follow your instructions quietly',
    };
    Widget line(IconData icon, String label, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(icon, size: 30),
        const SizedBox(width: Space.m),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label ',
                    style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: text),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          line(watchScopeIcon(scope), 'When', when),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 12, color: AppColors.line),
            ),
          ),
          line(watchModeIcon(mode), 'Then', then),
        ],
      ),
    );
  }
}

/// The triggers as a grid of tiles.
class _TriggerGrid extends StatelessWidget {
  const _TriggerGrid({required this.value, required this.telegram, required this.onChanged});
  final WatchScope value;
  final bool telegram;
  final ValueChanged<WatchScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final scopes = [
      for (final s in WatchScope.values)
        if (telegram || !s.needsTelegram || value == s) s,
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 480 ? 5 : 3;
        final w = (c.maxWidth - Space.s * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final s in scopes)
              SizedBox(
                width: w,
                child: _SelectTile(icon: watchScopeIcon(s), label: _scopeShort(s), selected: value == s, onTap: () => onChanged(s)),
              ),
          ],
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.enabled, required this.onTap});
  final WatchMode mode;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: _SelectTile(icon: watchModeIcon(mode), label: mode.label, selected: selected, onTap: enabled ? onTap : null, tall: true),
  );
}

/// A selectable tile: an icon over a label, outlined in the accent when picked.
class _SelectTile extends StatelessWidget {
  const _SelectTile({required this.icon, required this.label, required this.selected, this.onTap, this.tall = false});
  final IconData icon;
  final String label;
  final bool selected, tall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: tall ? 84 : 72,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.m),
          border: Border.all(color: selected ? AppColors.accent : AppColors.line, width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: tall ? 24 : 22, color: selected ? AppColors.accent : AppColors.text2),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.text : AppColors.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A wide, outlined call to add something.
class _DashedButton extends StatelessWidget {
  const _DashedButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Space.l),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: Space.s),
            Text(label, style: context.text.titleSmall?.copyWith(color: AppColors.accent)),
          ],
        ),
      ),
    ),
  );
}

/// A short tinted note with an icon.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.warning = false});
  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = warning ? AppColors.warning : AppColors.text2;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: warning ? AppColors.warning.withValues(alpha: 0.1) : AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: warning ? c : null)),
          ),
        ],
      ),
    );
  }
}

class _ChatPicker extends ConsumerStatefulWidget {
  const _ChatPicker({required this.selected, this.peopleOnly = false});
  final List<int> selected;

  /// Only one-to-one chats with people (for online alerts).
  final bool peopleOnly;

  @override
  ConsumerState<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends ConsumerState<_ChatPicker> {
  late final Set<int> _picked = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final chats =
        store.chats.values
            .where((c) => c.isListed && c.title.isNotEmpty && (_q.isEmpty || c.title.toLowerCase().contains(_q)))
            .where((c) => !widget.peopleOnly || store.kindOf(c) == ChatKind.private)
            .toList()
          ..sort((a, b) {
            final pa = _picked.contains(a.id), pb = _picked.contains(b.id);
            if (pa != pb) return pa ? -1 : 1;
            return (b.lastMessage?.date ?? 0).compareTo(a.lastMessage?.date ?? 0);
          });
    return Scaffold(
      appBar: AppBar(
        title: Text('${_picked.length} selected'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _picked.toList()), child: const Text('Done'))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase().trim()),
              decoration: const InputDecoration(isDense: true, hintText: 'Search chats', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final c = chats[i];
                return CheckboxListTile(
                  value: _picked.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _picked.add(c.id) : _picked.remove(c.id)),
                  secondary: TgAvatar(chatId: c.id, title: c.title, size: 38),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(store.kindOf(c).name, style: context.text.bodySmall),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// People the user wants to hear about when they come online.
class _OnlineAlerts extends ConsumerWidget {
  const _OnlineAlerts();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final store = ref.read(telegramStoreProvider);
    final picked = await Navigator.of(context)
        .push<List<int>>(MaterialPageRoute(builder: (_) => const _ChatPicker(selected: [], peopleOnly: true)));
    if (picked == null) return;
    for (final chatId in picked) {
      if (store.chat(chatId)?.type case td.ChatTypePrivate(:final userId)) {
        await ref.read(onlineAlertStoreProvider.notifier).add(userId, store.userName(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(onlineAlertStoreProvider);
    final store = ref.watch(telegramStoreProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          'Online alerts',
          count: alerts.isEmpty ? null : '${alerts.length}',
          trailing: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add'),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Row(
                    children: [
                      const _IconTile(Icons.circle_notifications_outlined, active: false, size: 36),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Text(
                          'Get a notification when someone comes online. Works for people who let you see their last seen.',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final a in alerts)
                Builder(
                  builder: (context) {
                    final user = store.users[a.userId];
                    final name = user == null ? a.name : store.userName(a.userId);
                    final status = user?.status;
                    final online = status is td.UserStatusOnline;
                    final hidden =
                        status is td.UserStatusRecently ||
                        status is td.UserStatusLastWeek ||
                        status is td.UserStatusLastMonth ||
                        status is td.UserStatusEmpty;
                    return ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          TgAvatar(userId: a.userId, title: name, size: 38),
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: online ? AppColors.success : AppColors.text3,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.surface2, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          online ? 'Online now' : (hidden ? 'Hides last seen; may not work' : 'Offline'),
                          a.once ? 'once' : 'every time',
                          if (a.fired > 0) 'alerted ${a.fired}×',
                        ].join(' · '),
                        style: context.text.bodySmall?.copyWith(color: hidden ? AppColors.warning : null),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: a.once ? 'Alert every time' : 'Alert once',
                            icon: Icon(a.once ? Icons.looks_one_outlined : Icons.repeat_rounded, size: 20),
                            onPressed: () => ref.read(onlineAlertStoreProvider.notifier).add(a.userId, a.name, once: !a.once),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () async {
                              if (await confirmDelete(
                                context,
                                title: 'Remove this alert?',
                                message: 'You won\'t hear when ${a.name} comes online.',
                                action: 'Remove',
                              )) {
                                await ref.read(onlineAlertStoreProvider.notifier).remove(a.userId);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The built-in check-in: every few hours the assistant looks for one new
/// thing worth the person's attention and sends it as a notification. It
/// can be changed and turned off, not deleted.
class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.watch});
  final Watch watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = watch;
    final hours = (w.everyMinutes ?? 360) / 60;
    final next = watchNextRun(w);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: () => showFormSheet<void>(context, builder: (_) => _CheckInSheet(id: w.id)),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.m),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            color: AppColors.surface,
            border: Border.all(color: w.enabled ? AppColors.accent.withValues(alpha: 0.3) : AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...leadRow(_IconTile(Icons.tips_and_updates_outlined, active: w.enabled), Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Check-in', style: context.text.titleSmall),
                        const SizedBox(width: Space.s),
                        const _Pill('Built in'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.enabled
                          ? 'Every ${_hours(hours)}${w.quietAtNight ? ', not at night' : ''}: one new thing worth your attention, with anything it prepared.'
                          : 'Off. Turn on for a nudge every few hours about what needs you.',
                      style: context.text.bodySmall,
                    ),
                    if (next != null || w.lastRunAt != null) ...[
                      const SizedBox(height: Space.s),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (next != null) _Pill('Next ${_when(next)}', icon: Icons.schedule_rounded),
                          if (w.lastRunAt != null) _Pill('Checked ${_ago(w.lastRunAt!)}', icon: Icons.history_rounded),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: w.enabled,
                onChanged: (v) => ref.read(watchStoreProvider.notifier).update(w.id, (x) => x.copyWith(enabled: v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hours(num h) => h == 1 ? 'hour' : '${h % 1 == 0 ? h.toInt() : h} hours';

class _CheckInSheet extends ConsumerStatefulWidget {
  const _CheckInSheet({required this.id});
  final String id;

  @override
  ConsumerState<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<_CheckInSheet> {
  late final _instructions = TextEditingController(text: ref.read(watchStoreProvider.notifier).byId(widget.id)?.instructions ?? '');

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _set(Watch Function(Watch) change) => ref.read(watchStoreProvider.notifier).update(widget.id, change);

  Future<void> _saveText() {
    final text = _instructions.text.trim();
    return _set((x) => x.copyWith(instructions: text.isEmpty ? checkInInstructions : text));
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(watchStoreProvider).where((x) => x.id == widget.id).firstOrNull;
    if (w == null) return const SizedBox.shrink();
    final every = w.everyMinutes ?? 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Check-in', style: context.text.titleMedium)),
            Switch(
              value: w.enabled,
              onChanged: (v) => _set((x) => x.copyWith(enabled: v)),
            ),
          ],
        ),
        Text(
          'The assistant looks across your chats, apps, reminders and calendar, picks one new thing worth your '
          'attention, prepares what helps (a summary, draft notes) and sends it as a notification. It never sends '
          'or changes anything for you. Built in: turn it off to stop it.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        Text('HOW OFTEN', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in const [1, 2, 3, 6, 12, 24])
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                label: Text('Every ${_hours(h)}'),
                selected: every == h * 60,
                onSelected: (_) => _set((x) => x.copyWith(everyMinutes: h * 60)),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Quiet at night'),
          subtitle: Text('Nothing between 22:00 and 08:00; it catches up in the morning.', style: context.text.bodySmall),
          value: w.quietAtNight,
          onChanged: (v) => _set((x) => x.copyWith(quietAtNight: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify me'),
          subtitle: Text('Off, its notes only land in its chat.', style: context.text.bodySmall),
          value: w.notify,
          onChanged: (v) => _set((x) => x.copyWith(notify: v)),
        ),
        if (ref.watch(accountsProvider).hasSeveral) ...[
          const SizedBox(height: Space.s),
          AccountScopePicker(
            value: w.accountIds,
            onChanged: (v) => _set((x) => x.copyWith(accountIds: v, allAccounts: v == null)),
            note: 'The Telegram accounts it looks through.',
          ),
          const SizedBox(height: Space.s),
        ],
        const SizedBox(height: Space.s),
        Text('MODEL', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        AutomationModelTile(
          value: w.model,
          onChanged: (v) => _set((x) => x.copyWith(model: v)),
        ),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(child: Text('WHAT TO LOOK FOR', style: context.text.labelSmall)),
            TextButton(onPressed: () => setState(() => _instructions.text = checkInInstructions), child: const Text('Reset')),
          ],
        ),
        TextField(
          controller: _instructions,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'What the check-in should look at and how it should tell you'),
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _saveText();
                  final latest = ref.read(watchStoreProvider.notifier).byId(widget.id);
                  if (latest != null) unawaited(ref.read(watchEngineProvider).runNow(latest));
                  if (context.mounted) showSnack(context, 'Checking in now. A notification follows if there is something.');
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Check now'),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await _saveText();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
