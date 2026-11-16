import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:omni_ai/omni_ai.dart' show CancelToken, FilePart, OmniAI, ReasoningDelta, ReasoningEffort, TextDelta, Usage;

import '../../app/theme.dart';
import '../ai/data/ai.dart' show aiErrorText;

// The AI runs that read many things in batches — the Marketplace and
// Opportunities tidy-ups and the Gallery's smart search — share this:
// one robust model call (streams its thinking and words as they come,
// stops the moment Stop is tapped, retries rate limits and empty or
// malformed answers, falls back to a second model) and one page to
// watch a run on, with the same layout and controls everywhere.

/// Thrown when a run is stopped mid-call.
class AiCancelled implements Exception {
  const AiCancelled();
  @override
  String toString() => 'Stopped';
}

/// What the model call in flight is doing, as it happens.
@immutable
class AiLive {
  const AiLive({this.phase = '', this.model = '', this.reasoning = '', this.text = '', this.items = const [], this.images = const [], this.startedAt, this.attempt = 1, this.notes = const []});

  /// '' when idle; else what's happening: "Fetching 4 photos", "Waiting
  /// for the model", "Thinking", "Writing".
  final String phase;
  final String model;
  final String reasoning;
  final String text;

  /// What this call is about.
  final List<String> items;

  /// Pictures sent with it (small), for the page to show.
  final List<Uint8List> images;
  final DateTime? startedAt;
  final int attempt;

  /// Things worth saying about the run: retries, a model switch.
  final List<String> notes;

  bool get busy => phase.isNotEmpty;

  AiLive copyWith({String? phase, String? model, String? reasoning, String? text, List<String>? items, List<Uint8List>? images, DateTime? startedAt, int? attempt, List<String>? notes}) => AiLive(
    phase: phase ?? this.phase,
    model: model ?? this.model,
    reasoning: reasoning ?? this.reasoning,
    text: text ?? this.text,
    items: items ?? this.items,
    images: images ?? this.images,
    startedAt: startedAt ?? this.startedAt,
    attempt: attempt ?? this.attempt,
    notes: notes ?? this.notes,
  );
}

class AiLiveNotifier extends ValueNotifier<AiLive> {
  AiLiveNotifier() : super(const AiLive());

  void begin({required List<String> items, List<Uint8List> images = const [], String phase = 'Preparing'}) =>
      value = AiLive(phase: phase, items: items, images: images, startedAt: DateTime.now(), notes: value.notes);
  void phase(String p) => value = value.copyWith(phase: p);
  void note(String n) => value = value.copyWith(notes: [n, ...value.notes].take(12).toList());
  void idle() => value = AiLive(notes: value.notes);
  void clearNotes() => value = value.copyWith(notes: const []);
}

/// What one model call returned.
@immutable
class AiCallResult {
  const AiCallResult({required this.model, required this.text, this.reasoning = '', this.inputTokens = 0, this.outputTokens = 0, this.cost, required this.ms, this.attempts = 1, this.usage = const Usage()});
  final String model;

  /// The call's usage, for the usage page.
  final Usage usage;
  final String text;
  final String reasoning;
  final int inputTokens;
  final int outputTokens;
  final double? cost;
  final int ms;
  final int attempts;
}

/// Reads a JSON array of objects out of a model's answer, forgiving code
/// fences, prose around it, trailing commas, an object wrapping the list
/// (`{"items": [...]}`) or a single object.
List<Map<String, dynamic>> parseJsonRows(String text) {
  var t = text
      // Thinking some models put in the answer, which has brackets and
      // quotes of its own.
      .replaceAll(RegExp(r'<think(?:ing)?>[\s\S]*?</think(?:ing)?>', caseSensitive: false), '')
      .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
      .trim();
  // Start at the list of objects, past any prose with brackets before it.
  final list = RegExp(r'\[\s*\{').firstMatch(t);
  if (list != null) t = t.substring(list.start);
  Object? decoded;
  Object? tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      try {
        return jsonDecode(s.replaceAll(RegExp(r',\s*([\]}])'), r'$1'));
      } catch (_) {
        return null;
      }
    }
  }

  final a = t.indexOf('['), b = t.lastIndexOf(']');
  if (a >= 0 && b > a) decoded = tryDecode(t.substring(a, b + 1));
  if (decoded == null) {
    final c = t.indexOf('{'), d = t.lastIndexOf('}');
    if (c >= 0 && d > c) decoded = tryDecode(t.substring(c, d + 1));
  }
  if (decoded is Map) {
    final list = decoded.values.whereType<List>().firstOrNull;
    decoded = list ?? [decoded];
  }
  if (decoded is! List) return _salvageObjects(t);
  return [for (final o in decoded) if (o is Map) Map<String, dynamic>.from(o)];
}

/// The whole objects in an answer that was cut off or malformed: what the
/// model finished is kept, even if the list never closed.
List<Map<String, dynamic>> _salvageObjects(String t) {
  final out = <Map<String, dynamic>>[];
  var depth = 0, start = -1;
  var inString = false, escaped = false;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (c == '}' && depth > 0) {
      depth--;
      if (depth == 0 && start >= 0) {
        final s = t.substring(start, i + 1);
        Object? o;
        try {
          o = jsonDecode(s);
        } catch (_) {
          try {
            o = jsonDecode(s.replaceAll(RegExp(r',\s*([\]}])'), r'$1'));
          } catch (_) {}
        }
        if (o is Map) out.add(Map<String, dynamic>.from(o));
        start = -1;
      }
    }
  }
  return out;
}

bool _rateLimited(Object e) => RegExp(r'429|rate.?limit|too many requests|overloaded|503|temporarily', caseSensitive: false).hasMatch('$e');

/// One model call that answers with a JSON array: streams thinking and
/// text into [live], stops at once when [cancel] fires (throwing
/// [AiCancelled]), waits and retries when rate limited, asks once more
/// when the answer isn't JSON, and switches to [fallbackModel] when
/// [model] keeps failing.
Future<(List<Map<String, dynamic>>, AiCallResult)> aiJsonCall({
  required OmniAI ai,
  required String model,
  String? fallbackModel,
  required String system,
  required String prompt,
  List<FilePart> files = const [],
  required int maxOutputTokens,
  required CancelToken cancel,
  AiLiveNotifier? live,
  // These runs read short posts into fields: a little thinking is plenty,
  // and long thinking only burns tokens and context.
  ReasoningEffort? effort = ReasoningEffort.low,
}) async {
  var current = model;
  var nudge = false;
  Object? lastError;
  final started = DateTime.now();
  for (var attempt = 1; attempt <= 4; attempt++) {
    if (cancel.isCancelled) throw const AiCancelled();
    live?.value = (live.value).copyWith(phase: 'Waiting for the model', model: current, reasoning: '', text: '', attempt: attempt);
    final reasoning = StringBuffer(), text = StringBuffer();
    StreamSubscription<Object?>? sub;
    try {
      final s = ai.streamText(
        model: current,
        system: nudge ? '$system\nReply with ONLY the JSON array — no prose, no code fences.' : system,
        prompt: prompt,
        files: files,
        maxOutputTokens: maxOutputTokens,
        cancelToken: cancel,
        reasoning: effort,
      );
      var lastPush = DateTime.now();
      sub = s.fullStream.listen((p) {
        if (p is ReasoningDelta) {
          reasoning.write(p.text);
        } else if (p is TextDelta) {
          text.write(p.text);
        } else {
          return;
        }
        // A few updates a second is plenty for the page.
        if (live != null && DateTime.now().difference(lastPush).inMilliseconds > 120) {
          lastPush = DateTime.now();
          live.value = live.value.copyWith(phase: text.isEmpty ? 'Thinking' : 'Writing', reasoning: reasoning.toString(), text: text.toString());
        }
      }, onError: (_) {});
      final r = await Future.any<dynamic>([
        s.result,
        cancel.whenCancelled.then<dynamic>((_) => throw const AiCancelled()),
      ]);
      // Some providers leave the final text empty though it streamed in.
      final answer = (r.text as String).trim().isNotEmpty ? r.text as String : text.toString();
      final thought = reasoning.isEmpty ? r.reasoning as String : reasoning.toString();
      live?.value = live.value.copyWith(reasoning: thought, text: answer);
      var rows = parseJsonRows(answer);
      // Some models write the answer inside their thinking.
      if (rows.isEmpty && thought.trim().isNotEmpty) rows = parseJsonRows(thought);
      final result = AiCallResult(
        model: current,
        text: answer,
        reasoning: r.reasoning as String,
        inputTokens: r.usage.inputTokens as int,
        outputTokens: r.usage.outputTokens as int,
        cost: r.usage.cost as double?,
        ms: DateTime.now().difference(started).inMilliseconds,
        attempts: attempt,
        usage: r.usage as Usage,
      );
      if (rows.isNotEmpty || attempt >= 3) return (rows, result);
      // Nothing usable came back (often a thinking model that ran out of
      // room, or prose): once more, plainly.
      final got = answer.trim().isEmpty ? 'an empty answer' : '“${answer.trim().replaceAll(RegExp(r'\s+'), ' ').characters.take(80)}…”';
      lastError = 'The model didn’t answer with a list (got $got)';
      live?.note(nudge ? 'Still no list from ${current.split(':').last} (got $got)' : 'No list in the answer (got $got) — asking again');
      // A low thinking setting can leave some models with nothing to say:
      // the retry uses the model's own default.
      effort = null;
      if (nudge && fallbackModel != null && fallbackModel != current) {
        live?.note('Switching to ${fallbackModel.split(':').last}');
        current = fallbackModel;
      }
      nudge = true;
    } on AiCancelled {
      rethrow;
    } catch (e) {
      if (cancel.isCancelled) throw const AiCancelled();
      lastError = e;
      if (_rateLimited(e) && attempt < 4) {
        live?.note('Rate limited — waiting ${attempt * 3} s');
        live?.phase('Waiting (rate limit)');
        await Future.any([Future<void>.delayed(Duration(seconds: attempt * 3)), cancel.whenCancelled]);
        continue;
      }
      if (fallbackModel != null && fallbackModel != current) {
        live?.note('${current.split(':').last} failed (${aiErrorText(e)}) — switching to ${fallbackModel.split(':').last}');
        current = fallbackModel;
        continue;
      }
      rethrow;
    } finally {
      await sub?.cancel();
    }
  }
  throw lastError ?? 'The model didn’t answer';
}

// ---- the page --------------------------------------------------------------------

enum AiRunStatus { idle, running, paused, stopping, stopped, done }

/// One result in a run.
@immutable
class AiRunEntry {
  const AiRunEntry({required this.title, this.subtitle = '', this.error, this.skipped = false, this.leading, this.badge, this.onTap, required this.at});
  final String title;
  final String subtitle;
  final String? error;
  final bool skipped;
  final Widget? leading;
  final Widget? badge;
  final VoidCallback? onTap;
  final DateTime at;
}

/// What a run looks like right now.
@immutable
class AiRunView {
  const AiRunView({this.status = AiRunStatus.idle, this.model = '', this.total = 0, this.done = 0, this.failed = 0, this.current = const [], this.entries = const [], this.startedAt, this.endedAt, this.lastError, this.summary = ''});
  final AiRunStatus status;
  final String model;
  final int total;
  final int done;
  final int failed;
  final List<String> current;
  final List<AiRunEntry> entries;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? lastError;

  /// A line for when nothing has run yet: "Knows 120 of 300 photos".
  final String summary;

  bool get active => status == AiRunStatus.running || status == AiRunStatus.paused || status == AiRunStatus.stopping;
  int get left => (total - done).clamp(0, 1 << 30);
  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

/// The full page of an AI run: a header with the progress ring, status,
/// counts, model and controls; what it's working on now, with its
/// thinking and answer streaming in; the results; and the run's settings.
class AiRunPage extends StatefulWidget {
  const AiRunPage({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.view,
    required this.live,
    this.onRun,
    this.runLabel = 'Run now',
    this.onPause,
    this.onResume,
    this.onStop,
    this.onClear,
    this.settings = const [],
    this.about = '',
  });
  final String title;
  final IconData icon;
  final Color color;
  final ValueListenable<AiRunView> view;
  final ValueListenable<AiLive> live;
  final VoidCallback? onRun;
  final String runLabel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onClear;

  /// The run's settings, shown under the Settings tab.
  final List<Widget> settings;

  /// What the run does, in a sentence or two.
  final String about;

  @override
  State<AiRunPage> createState() => _AiRunPageState();
}

class _AiRunPageState extends State<AiRunPage> {
  bool _settings = false;
  bool _thinkingOpen = true;
  bool _answerOpen = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The elapsed time moves while a run is on.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.view.value.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(AiRunView v) {
    final from = v.startedAt;
    if (from == null) return '–';
    final d = (v.endedAt != null && !v.active ? v.endedAt! : DateTime.now()).difference(from);
    return d.inMinutes > 0 ? '${d.inMinutes}m ${d.inSeconds % 60}s' : '${d.inSeconds}s';
  }

  (String, Color) _status(AiRunView v) => switch (v.status) {
    AiRunStatus.running => ('Running', widget.color),
    AiRunStatus.paused => ('Paused', const Color(0xFFF59E0B)),
    AiRunStatus.stopping => ('Stopping', const Color(0xFFEF4444)),
    AiRunStatus.stopped => ('Stopped', AppColors.text3),
    AiRunStatus.done => ('Finished', const Color(0xFF22C55E)),
    AiRunStatus.idle => ('Ready', AppColors.text3),
  };

  Widget _header(BuildContext context, AiRunView v) {
    final (label, color) = _status(v);
    final minimal = AppLook.minimalExplore;
    final fg = minimal ? AppColors.text : Colors.white;
    final fg2 = minimal ? AppColors.text2 : Colors.white70;
    Widget stat(String value, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.m)),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 17, fontFeatures: tabularFigures)),
            Text(l, style: TextStyle(color: fg2, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(Space.l, MediaQuery.paddingOf(context).top + kToolbarHeight, Space.l, Space.l),
      decoration: BoxDecoration(
        color: minimal ? AppColors.bg : null,
        gradient: minimal ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(widget.color, Colors.black, 0.55)!, Color.lerp(widget.color, Colors.black, 0.88)!]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: v.active || v.done > 0 ? v.fraction : 0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, f, _) => CircularProgressIndicator(
                        value: v.status == AiRunStatus.running && v.total == 0 ? null : f,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        color: minimal ? AppColors.text : Colors.white,
                        backgroundColor: fg.withValues(alpha: 0.14),
                      ),
                    ),
                    Center(
                      child: v.total == 0
                          ? Icon(widget.icon, color: fg, size: 30)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${(v.fraction * 100).round()}%', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w900)),
                                Text('${v.done}/${v.total}', style: TextStyle(color: fg2, fontSize: 10.5, fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: 0.6))),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (v.status == AiRunStatus.running) _Pulse(color: minimal ? color : Colors.white) else Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      v.active || v.total > 0 ? '${v.done - v.failed} done${v.failed > 0 ? ' · ${v.failed} failed' : ''}${v.left > 0 ? ' · ${v.left} left' : ''}' : (v.summary.isEmpty ? widget.about : v.summary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    if (v.model.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.memory_rounded, size: 14, color: fg2),
                          const SizedBox(width: 4),
                          Flexible(child: Text(v.model.split(':').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg2, fontSize: 12, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (v.active || v.total > 0) ...[
            const SizedBox(height: Space.l),
            Row(
              children: [
                stat('${v.done - v.failed}', 'done'),
                const SizedBox(width: Space.s),
                stat('${v.failed}', 'failed'),
                const SizedBox(width: Space.s),
                stat('${v.left}', 'left'),
                const SizedBox(width: Space.s),
                stat(_elapsed(v), 'time'),
              ],
            ),
          ],
          const SizedBox(height: Space.l),
          Row(
            children: [
              if (v.active) ...[
                Expanded(
                  child: v.status == AiRunStatus.paused
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: minimal ? AppColors.bg : Colors.black, minimumSize: const Size(0, 46)),
                          onPressed: widget.onResume,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Continue'),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.4)), minimumSize: const Size(0, 46)),
                          onPressed: v.status == AiRunStatus.stopping ? null : widget.onPause,
                          icon: const Icon(Icons.pause_rounded),
                          label: const Text('Pause'),
                        ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
                    onPressed: v.status == AiRunStatus.stopping ? null : widget.onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop now'),
                  ),
                ),
              ] else
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: minimal ? AppColors.bg : Colors.black, minimumSize: const Size(0, 46)),
                    onPressed: widget.onRun,
                    icon: Icon(widget.icon, size: 18),
                    label: Text(widget.runLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _now(BuildContext context, AiLive live, AiRunView v) {
    if (!v.active && !live.busy && live.notes.isEmpty) return const SizedBox.shrink();
    final c = widget.color;
    Widget block({required String title, required IconData icon, required bool open, required VoidCallback toggle, required String text, bool mono = false}) => Container(
      margin: const EdgeInsets.only(top: Space.s),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: toggle,
            borderRadius: BorderRadius.circular(Radii.m),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 10, Space.s, 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.text2),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800))),
                  Text('${text.length} chars', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: AppColors.text3),
                ],
              ),
            ),
          ),
          if (open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
                child: SelectableText(
                  text,
                  style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.text2, fontFamily: mono ? 'monospace' : null, fontStyle: mono ? null : FontStyle.italic),
                ),
              ),
            ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: live.busy ? c.withValues(alpha: 0.5) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (live.busy) SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c)) else Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.text3),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  live.busy ? '${live.phase}${live.attempt > 1 ? ' · try ${live.attempt}' : ''}' : (v.status == AiRunStatus.paused ? 'Paused between batches' : 'Between batches'),
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (live.busy && live.startedAt != null) Text('${DateTime.now().difference(live.startedAt!).inSeconds}s', style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures)),
            ],
          ),
          if (live.images.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: live.images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.s),
                  child: Stack(
                    children: [
                      Image.memory(live.images[i], width: 72, height: 72, fit: BoxFit.cover, gaplessPlayback: true),
                      if (live.busy) Positioned.fill(child: _Scan(color: c)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (live.items.isNotEmpty && live.busy) ...[
            const SizedBox(height: Space.m),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final it in live.items.take(10))
                  Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99), border: Border.all(color: c.withValues(alpha: 0.25))),
                    child: Text(it, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
                  ),
              ],
            ),
          ],
          if (live.busy) ...[
            const SizedBox(height: Space.s),
            _Steps(phase: live.phase, color: c),
          ],
          if (live.reasoning.trim().isNotEmpty)
            block(title: 'Thinking', icon: Icons.psychology_alt_outlined, open: _thinkingOpen, toggle: () => setState(() => _thinkingOpen = !_thinkingOpen), text: live.reasoning.trim()),
          if (live.text.trim().isNotEmpty)
            block(title: 'Answer', icon: Icons.data_object_rounded, open: _answerOpen, toggle: () => setState(() => _answerOpen = !_answerOpen), text: live.text.trim(), mono: true),
          if (live.notes.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            for (final n in live.notes.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(child: Text(n, style: context.text.labelSmall?.copyWith(color: AppColors.text2))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _results(BuildContext context, AiRunView v) {
    if (v.entries.isEmpty) {
      if (v.active) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          children: [
            Icon(widget.icon, size: 40, color: AppColors.text3),
            const SizedBox(height: Space.s),
            Text(v.lastError ?? 'Nothing has run yet', textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: v.lastError != null ? AppColors.danger : null)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.s, Space.xs),
          child: Row(
            children: [
              Text('RESULTS', style: context.text.labelSmall),
              const SizedBox(width: 6),
              Text('${v.entries.length}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              const Spacer(),
              if (!v.active && widget.onClear != null) TextButton(onPressed: widget.onClear, child: const Text('Clear')),
            ],
          ),
        ),
        for (final e in v.entries.take(120))
          InkWell(
            onTap: e.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 8),
              child: Row(
                children: [
                  Container(width: 3, height: 40, decoration: BoxDecoration(color: e.error != null ? AppColors.danger : (e.skipped ? AppColors.text3 : const Color(0xFF22C55E)), borderRadius: BorderRadius.circular(9))),
                  const SizedBox(width: Space.m),
                  if (e.leading != null) ...[ClipRRect(borderRadius: BorderRadius.circular(Radii.s), child: SizedBox.square(dimension: 44, child: e.leading)), const SizedBox(width: Space.m)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          e.error ?? (e.skipped ? 'Skipped · ${e.subtitle}' : e.subtitle),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: e.error != null ? AppColors.danger : AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  if (e.badge != null) ...[const SizedBox(width: Space.s), e.badge!],
                  if (e.onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AiRunView>(
    valueListenable: widget.view,
    builder: (context, v, _) => Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppLook.minimalExplore ? AppColors.text : Colors.white,
        title: Text(widget.title),
        actions: [
          if (widget.settings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppLook.minimalExplore ? AppColors.text : Colors.white,
                  selectedForegroundColor: AppLook.minimalExplore ? AppColors.bg : Colors.black,
                  selectedBackgroundColor: AppLook.minimalExplore ? AppColors.text : Colors.white,
                  side: BorderSide(color: (AppLook.minimalExplore ? AppColors.text : Colors.white).withValues(alpha: 0.4)),
                ),
                segments: const [ButtonSegment(value: false, label: Text('Run')), ButtonSegment(value: true, label: Text('Settings'))],
                selected: {_settings},
                onSelectionChanged: (s) => setState(() => _settings = s.first),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: Space.x4 + MediaQuery.paddingOf(context).bottom),
        children: [
          _header(context, v),
          if (_settings)
            ...widget.settings
          else ...[
            ValueListenableBuilder<AiLive>(valueListenable: widget.live, builder: (context, live, _) => _now(context, live, v)),
            if (v.lastError != null && v.entries.isNotEmpty && !v.active)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                child: Text('Last error: ${v.lastError}', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
              ),
            _results(context, v),
          ],
        ],
      ),
    ),
  );
}

/// A one-line bar for a section's page while its run is on; tap for the
/// full page.
class AiRunBar extends StatelessWidget {
  const AiRunBar({super.key, required this.view, required this.color, required this.label, required this.onOpen});
  final AiRunView view;
  final Color color;
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (!view.active) return const SizedBox.shrink();
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Text(view.status == AiRunStatus.paused ? '$label paused · ${view.done}/${view.total}' : '$label · ${view.done}/${view.total}', style: context.text.labelSmall),
            const SizedBox(width: Space.s),
            Expanded(child: LinearProgressIndicator(value: view.total == 0 ? null : view.fraction, minHeight: 3, color: color, borderRadius: BorderRadius.circular(9))),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// The steps of a call, the current one lit.
class _Steps extends StatelessWidget {
  const _Steps({required this.phase, required this.color});
  final String phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const steps = ['Preparing', 'Waiting', 'Thinking', 'Writing'];
    final at = steps.indexWhere((s) => phase.startsWith(s) || (s == 'Preparing' && phase.startsWith('Fetching')));
    return Row(
      children: [
        for (final (i, s) in steps.indexed) ...[
          if (i > 0) Expanded(child: Container(height: 2, color: i <= at ? color : AppColors.line)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: i == at ? color.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(99), border: Border.all(color: i <= at ? color : AppColors.line)),
            child: Text(s, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: i <= at ? AppColors.text : AppColors.text3)),
          ),
        ],
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.3, end: 1.0).animate(_a),
    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}

/// A light sweeping over a picture being looked at.
class _Scan extends StatefulWidget {
  const _Scan({required this.color});
  final Color color;

  @override
  State<_Scan> createState() => _ScanState();
}

class _ScanState extends State<_Scan> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, _) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, widget.color.withValues(alpha: 0.45), Colors.transparent],
          stops: [(_a.value - 0.15).clamp(0, 1), _a.value, (_a.value + 0.15).clamp(0, 1)],
        ),
      ),
    ),
  );
}

/// A [ValueListenable] read through [map] from [source].
class MappedListenable<S, T> extends ChangeNotifier implements ValueListenable<T> {
  MappedListenable(this.source, this.map) {
    source.addListener(notifyListeners);
  }
  final ValueListenable<S> source;
  final T Function(S) map;

  @override
  T get value => map(source.value);

  @override
  void dispose() {
    source.removeListener(notifyListeners);
    super.dispose();
  }
}
