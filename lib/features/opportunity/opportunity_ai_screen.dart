import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../assistant/presentation/automation_widgets.dart' show AutomationModelTile;
import '../marketplace/market_screen.dart' show LegitBadge;
import '../sections/ai_run.dart';
import '../sections/section_kit.dart' show agoText;
import 'opportunity.dart';
import 'opportunity_detail.dart' show openEvent, openJob;
import 'opportunity_screen.dart' show editProfile, oppColor;

/// The Opportunity page's AI tidy-up, as the Marketplace has it: what the
/// model fills in for events and jobs, its model and your instructions,
/// and the run itself with pause, continue, stop and a trace of every call.
class OpportunitySettingsScreen extends ConsumerStatefulWidget {
  const OpportunitySettingsScreen({super.key});

  @override
  ConsumerState<OpportunitySettingsScreen> createState() => _OpportunitySettingsScreenState();

  /// Loaded posts of [k] that haven't been read yet, up to [max].
  static List<OppPost> unread(WidgetRef ref, OppKind k, {int max = 48}) {
    final o = ref.read(opportunityProvider);
    final have = k == OppKind.event ? o.events : o.jobs;
    final feed = ref.read(oppFeedProvider(k));
    return [
      for (final s in o.sourcesOf(k))
        for (final p in feed.bySource[s.key] ?? const <OppPost>[])
          if (!have.containsKey(p.key) && !o.hidden.contains(p.key)) p,
    ].take(max).toList();
  }

}

AiRunStatus _statusOf(OppTidyStatus s) => switch (s) {
  OppTidyStatus.idle => AiRunStatus.idle,
  OppTidyStatus.running => AiRunStatus.running,
  OppTidyStatus.paused => AiRunStatus.paused,
  OppTidyStatus.stopping => AiRunStatus.stopping,
  OppTidyStatus.stopped => AiRunStatus.stopped,
  OppTidyStatus.done => AiRunStatus.done,
};

class _OpportunitySettingsScreenState extends ConsumerState<OpportunitySettingsScreen> {
  late final OpportunityStore _store = ref.read(opportunityProvider.notifier);
  late final _view = MappedListenable<OppTidyJob, AiRunView>(_store.readJob, (j) {
    final o = ref.read(opportunityProvider);
    final left = OpportunitySettingsScreen.unread(ref, OppKind.event, max: 9999).length + OpportunitySettingsScreen.unread(ref, OppKind.job, max: 9999).length;
    return AiRunView(
      status: _statusOf(j.status),
      model: j.model,
      total: j.total,
      done: j.done,
      failed: j.failed,
      current: j.current,
      startedAt: j.startedAt,
      endedAt: j.endedAt,
      lastError: j.lastError,
      summary: o.ai.enabled ? '${o.events.length} events and ${o.jobs.length} jobs tidied · $left loaded posts not yet' : 'Turn it on under Settings to read posts into events and jobs.',
      entries: [
        for (final l in j.log)
          AiRunEntry(
            title: l.name,
            subtitle: [l.kind == OppKind.event ? 'Event' : 'Job', l.source, if (l.line.isNotEmpty) l.line].join(' · '),
            error: l.error,
            skipped: l.skipped,
            badge: l.legit == null ? null : LegitBadge(score: l.legit!),
            at: l.at,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OppTraceScreen(log: l))),
          ),
      ],
    );
  });

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    if (!ref.read(opportunityProvider).ai.enabled) {
      showSnack(context, 'Turn on “Tidy posts with AI” under Settings first', icon: Icons.auto_awesome_rounded);
      return;
    }
    final store = ref.read(opportunityProvider.notifier);
    final events = OpportunitySettingsScreen.unread(ref, OppKind.event), jobs = OpportunitySettingsScreen.unread(ref, OppKind.job);
    if (events.isEmpty && jobs.isEmpty) {
      showSnack(context, 'Every loaded post is already tidied', icon: Icons.check_rounded);
      return;
    }
    if (events.isNotEmpty) unawaited(store.read(OppKind.event, events));
    if (jobs.isNotEmpty) unawaited(store.read(OppKind.job, jobs));
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(opportunityProvider);
    final ai = o.ai;
    final store = ref.read(opportunityProvider.notifier);
    Future<void> set(OppAi v) => store.setAi(v);
    Widget sw(IconData icon, String title, String sub, bool v, OppAi Function(bool) f) => SwitchListTile(
      secondary: lead(Icon(icon)),
      title: Text(title),
      subtitle: Text(sub, style: context.text.bodySmall),
      value: v,
      onChanged: ai.enabled ? (x) => set(f(x)) : null,
    );
    Widget heading(String t) => Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s), child: Text(t, style: context.text.labelSmall));
    return AiRunPage(
      title: 'AI tidy-up',
      icon: Icons.auto_awesome_rounded,
      color: oppColor,
      view: _view,
      live: store.live,
      about: 'Reads each post into a clean event or job, checks job ads for scams and scores them against your profile.',
      onRun: () => _runNow(context, ref),
      onPause: store.pauseTidy,
      onResume: store.resumeTidy,
      onStop: store.stopTidy,
      onClear: store.clearTidyLog,
      settings: [
          SwitchListTile(
            secondary: lead(const Icon(Icons.auto_awesome_rounded)),
            title: const Text('Tidy posts with AI', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              'A model reads each post into a clean event (when, where, how to register) or job (role, pay, deadline, how to apply), '
              'and checks job ads for scams. Each batch of 6 posts is one model call. Off: dates and deadlines are guessed from the words.',
              style: context.text.bodySmall,
            ),
            value: ai.enabled,
            onChanged: (v) => set(ai.copyWith(enabled: v)),
          ),
          const Divider(),
          sw(Icons.bolt_rounded, 'Automatically', 'Tidy posts as they load. Off: only when you tap Run now. Pressing Stop pauses this until you run it again.', ai.auto, (v) => ai.copyWith(auto: v)),
          sw(Icons.filter_alt_outlined, 'Hide posts that aren\'t events or jobs', 'News, greetings, results and ads for the channel', ai.hideOthers, (v) => ai.copyWith(hideOthers: v)),
          heading('EVENTS'),
          sw(Icons.notes_rounded, 'Summaries', 'Two plain lines: what it is and who it\'s for', ai.eventSummary, (v) => ai.copyWith(eventSummary: v)),
          sw(Icons.place_outlined, 'Where', 'Venue, city, and whether it\'s online', ai.eventPlace, (v) => ai.copyWith(eventPlace: v)),
          sw(Icons.sell_outlined, 'Price', 'Free or what a ticket costs', ai.eventPrice, (v) => ai.copyWith(eventPrice: v)),
          sw(Icons.confirmation_number_outlined, 'Registration link', 'The link to register, buy a ticket or join', ai.eventLink, (v) => ai.copyWith(eventLink: v)),
          sw(Icons.category_outlined, 'Category and tags', 'Tech, Music, Faith, Career… for the filters', ai.eventTags, (v) => ai.copyWith(eventTags: v)),
          heading('JOBS'),
          sw(Icons.payments_outlined, 'Pay', 'Salary range, currency and period, however it\'s written', ai.jobPay, (v) => ai.copyWith(jobPay: v)),
          sw(Icons.send_outlined, 'How to apply', 'The link, email and steps', ai.jobApply, (v) => ai.copyWith(jobApply: v)),
          sw(Icons.checklist_rounded, 'Requirements and skills', 'Degree, years, must-haves and skills', ai.jobRequirements, (v) => ai.copyWith(jobRequirements: v)),
          sw(Icons.notes_rounded, 'Summaries', 'Two plain lines about the role', ai.jobSummary, (v) => ai.copyWith(jobSummary: v)),
          sw(Icons.verified_user_outlined, 'Trust check', 'How genuine the ad looks, and why: fees to apply, pay too good, no real employer', ai.jobTrust, (v) => ai.copyWith(jobTrust: v)),
          sw(Icons.donut_large_rounded, 'Fit for me', o.profile.isEmpty ? 'Needs your profile (below)' : 'A 0-100 score against your profile, with the reason', ai.jobMatch, (v) => ai.copyWith(jobMatch: v)),
          ListTile(
            leading: lead(const Icon(Icons.badge_outlined)),
            title: const Text('Your profile'),
            subtitle: Text(o.profile.isEmpty ? 'Not set: jobs won\'t get a fit score' : o.profile, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => editProfile(context, ref),
          ),
          heading('MODEL'),
          AutomationModelTile(value: ai.model, onChanged: (v) => set(ai.copyWith(model: v))),
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: TextFormField(
              initialValue: ai.extra,
              enabled: ai.enabled,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Your own instructions (optional)',
                hintText: 'e.g. Times are in East Africa Time. Flag any job that asks for money. Skip church events.',
              ),
              onChanged: (v) => set(ai.copyWith(extra: v)),
            ),
          ),
          if (o.profile.isNotEmpty && o.jobs.isNotEmpty)
            ValueListenableBuilder<OppTidyJob>(
              valueListenable: store.readJob,
              builder: (context, j, _) => ListTile(
                leading: lead(const Icon(Icons.refresh_rounded)),
                title: const Text('Score loaded jobs again'),
                subtitle: Text('After you change your profile', style: context.text.bodySmall),
                enabled: ai.enabled && !j.active,
                onTap: () {
                  final feed = ref.read(oppFeedProvider(OppKind.job));
                  unawaited(store.read(OppKind.job, [for (final s in o.jobSources) ...?feed.bySource[s.key]], force: true));
                },
              ),
            ),
          SwitchListTile(secondary: lead(const Icon(Icons.menu_rounded)), title: const Text('Show in the side menu'), value: o.inDrawer, onChanged: store.setInDrawer),
          ListTile(
            leading: lead(Icon(Icons.restart_alt_rounded, color: AppColors.danger)),
            title: const Text('Forget what the model wrote'),
            subtitle: Text('${o.events.length} events and ${o.jobs.length} jobs tidied so far', style: context.text.bodySmall),
            onTap: () async {
              if (!await confirmDelete(context, title: 'Forget AI readings?', message: 'Events and jobs go back to their raw posts until tidied again.', action: 'Forget')) return;
              await store.forgetReadings(OppKind.event);
              await store.forgetReadings(OppKind.job);
            },
          ),
      ],
    );
  }
}

/// The tidy-up as it runs: progress, what's being read now, what came
/// back, and pause, continue and stop.
class OppTidyMonitor extends StatelessWidget {
  const OppTidyMonitor({super.key, required this.store});
  final OpportunityStore store;

  String _elapsed(OppTidyJob j) {
    final from = j.startedAt;
    if (from == null) return '';
    final d = (j.endedAt != null && !j.active ? j.endedAt! : DateTime.now()).difference(from);
    return d.inMinutes > 0 ? '${d.inMinutes} min ${d.inSeconds % 60} s' : '${d.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<OppTidyJob>(
    valueListenable: store.readJob,
    builder: (context, j, _) {
      if (j.status == OppTidyStatus.idle && j.log.isEmpty) return const SizedBox.shrink();
      final (label, color) = switch (j.status) {
        OppTidyStatus.running => ('Running', oppColor),
        OppTidyStatus.paused => ('Paused', const Color(0xFFF59E0B)),
        OppTidyStatus.stopping => ('Stopping after this batch', const Color(0xFFEF4444)),
        OppTidyStatus.stopped => ('Stopped', AppColors.text3),
        OppTidyStatus.done => ('Finished', const Color(0xFF22C55E)),
        OppTidyStatus.idle => ('Idle', AppColors.text3),
      };
      Widget stat(String v, String l) => Expanded(
        child: Column(children: [Text(v, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)), Text(l, style: context.text.labelSmall)]),
      );
      return Container(
        margin: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: Space.s),
                Expanded(child: Text(label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                if (j.model.isNotEmpty) Flexible(child: Text(j.model.split(':').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
              ],
            ),
            const SizedBox(height: Space.m),
            LinearProgressIndicator(value: j.total == 0 ? null : j.fraction, minHeight: 8, color: color, borderRadius: BorderRadius.circular(9)),
            const SizedBox(height: Space.m),
            Row(children: [stat('${j.done - j.failed}', 'tidied'), stat('${j.failed}', 'failed'), stat('${j.left}', 'left'), stat(_elapsed(j), 'time')]),
            if (j.current.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text('READING NOW', style: context.text.labelSmall),
              for (final c in j.current.take(6)) Text('· $c', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
            if (j.active) ...[
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: j.status == OppTidyStatus.paused
                        ? FilledButton.icon(onPressed: store.resumeTidy, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Continue'))
                        : OutlinedButton.icon(onPressed: j.status == OppTidyStatus.stopping ? null : store.pauseTidy, icon: const Icon(Icons.pause_rounded), label: const Text('Pause')),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: j.status == OppTidyStatus.stopping ? null : store.stopTidy,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ],
            if (j.log.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(child: Text('RESULTS', style: context.text.labelSmall)),
                  if (!j.active) TextButton(onPressed: store.clearTidyLog, child: const Text('Clear')),
                ],
              ),
              for (final l in j.log.take(25))
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.s),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OppTraceScreen(log: l))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        if (l.error != null)
                          Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger)
                        else if (l.legit != null)
                          LegitBadge(score: l.legit!)
                        else
                          Icon(l.kind == OppKind.event ? Icons.event_rounded : Icons.work_outline_rounded, size: 16, color: l.skipped ? AppColors.text3 : oppColor),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: l.skipped ? AppColors.text3 : AppColors.text, fontWeight: FontWeight.w600)),
                              Text(
                                l.error ?? (l.skipped ? 'Not ${l.kind == OppKind.event ? 'an event' : 'a job'} · hidden' : [l.source, if (l.line.isNotEmpty) l.line].join(' · ')),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall?.copyWith(color: l.error != null ? AppColors.danger : null),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// One result in full: the post, what the model was told and sent, what it
/// answered, and what the call cost.
class OppTraceScreen extends ConsumerWidget {
  const OppTraceScreen({super.key, required this.log});
  final OppTidyLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = log.trace;
    String? pick(String? json, {bool answer = false}) {
      if (json == null || log.index == null) return null;
      try {
        final list = jsonDecode(answer ? json.substring(json.indexOf('['), json.lastIndexOf(']') + 1) : json) as List;
        final mine = answer ? list.whereType<Map>().where((o) => (o['i'] as num?)?.toInt() == log.index).firstOrNull : list[log.index!];
        return mine == null ? null : const JsonEncoder.withIndent('  ').convert(mine);
      } catch (_) {
        return null;
      }
    }

    final sent = pick(t?.prompt);
    final answer = pick(t?.response, answer: true);
    var n = 0;
    Widget step(String title, String subtitle, Widget child, {Color? color}) {
      n++;
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: (color ?? oppColor).withValues(alpha: 0.18),
              child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color ?? oppColor)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(subtitle, style: context.text.labelSmall),
                  const SizedBox(height: Space.s),
                  child,
                ],
              ),
            ),
          ],
        ),
      );
    }

    final facts = <(IconData, String)>[
      if (t != null) ...[
        (Icons.memory_rounded, t.model.split(':').last),
        (Icons.timer_outlined, '${(t.ms / 1000).toStringAsFixed(1)} s'),
        (Icons.input_rounded, '${t.inputTokens} tokens in'),
        (Icons.output_rounded, '${t.outputTokens} tokens out'),
        if (t.cost != null) (Icons.payments_outlined, 'USD ${t.cost!.toStringAsFixed(5)}'),
        (Icons.layers_outlined, '${t.batch} posts in this call'),
      ],
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('AI trace')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Row(
            children: [
              if (log.error != null) Icon(Icons.error_outline_rounded, color: AppColors.danger) else if (log.legit != null) LegitBadge(score: log.legit!, big: true),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${log.source} · ${agoText(log.at)}', style: context.text.bodySmall),
                  ],
                ),
              ),
              if (log.postKey != null)
                IconButton.filledTonal(
                  tooltip: log.kind == OppKind.event ? 'Open the event' : 'Open the job',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () => log.kind == OppKind.event ? openEvent(context, ref, log.postKey!) : openJob(context, ref, log.postKey!),
                ),
            ],
          ),
          const SizedBox(height: Space.l),
          if (facts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
              child: Wrap(
                spacing: Space.l,
                runSpacing: Space.s,
                children: [
                  for (final (icon, text) in facts)
                    Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: AppColors.text3), const SizedBox(width: 4), Text(text, style: context.text.labelMedium)]),
                ],
              ),
            ),
          const SizedBox(height: Space.l),
          step('The post', 'What the channel posted', _Code(log.postText.isEmpty ? '(no text)' : log.postText, collapsed: 10)),
          if (t != null) ...[
            step('Instructions', 'The system prompt the model was given', _Code(t.system, collapsed: 8)),
            step('Request', sent == null ? 'The posts sent in this call' : 'This post as sent (one of ${t.batch})', _Code(sent ?? t.prompt), color: const Color(0xFF3B82F6)),
            if (t.error != null)
              step('Error', 'The call failed', Text(t.error!, style: TextStyle(color: AppColors.danger)), color: AppColors.danger)
            else ...[
              step('Model reply', answer == null ? 'The whole answer' : 'Its answer for this post', _Code(answer ?? t.response ?? ''), color: const Color(0xFF22C55E)),
              if (answer != null && t.response != null) step('Full reply', 'Everything the model wrote for the batch', _Code(t.response!, collapsed: 6), color: const Color(0xFF22C55E)),
            ],
          ] else
            step('No trace', 'This result has no recorded call', const SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Monospace text that folds to [collapsed] lines, with copy.
class _Code extends StatefulWidget {
  const _Code(this.text, {this.collapsed = 14});
  final String text;
  final int collapsed;

  @override
  State<_Code> createState() => _CodeState();
}

class _CodeState extends State<_Code> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.split('\n').length > widget.collapsed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(widget.text, maxLines: _open || !long ? null : widget.collapsed, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4)),
          Row(
            children: [
              if (long) TextButton(onPressed: () => setState(() => _open = !_open), child: Text(_open ? 'Show less' : 'Show all')),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.text));
                  if (context.mounted) showSnack(context, 'Copied');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
