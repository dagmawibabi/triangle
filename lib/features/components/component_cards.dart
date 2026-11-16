import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../app/theme.dart';
import '../chat/domain/chat_models.dart';
import '../chat/presentation/widgets/info_card_kit.dart' show openLink;
import '../chat/presentation/widgets/message_view.dart' show MarkdownTable;
import 'components.dart';

part 'component_cards_more.dart';

/// The card for a show_component call; null for other tools.
Widget? componentResultFor(ToolPart part, Map<String, dynamic> j) {
  if (part.name != 'show_component' || j['shown'] == null) return null;
  final f = part.full;
  if (f == null) return null;
  try {
    return ComponentView(data: Map<String, dynamic>.from(jsonDecode(f) as Map));
  } catch (_) {
    return null;
  }
}

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
final _compact = NumberFormat.compact();
String _fmt(double v, [String unit = '']) {
  final t = v.abs() >= 10000 ? _compact.format(v) : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() < 10 ? 2 : 1));
  if (unit.isEmpty) return t;
  return const {r'$', '€', '£', '¥'}.contains(unit) ? '$unit$t' : (unit == '%' ? '$t%' : '$t $unit');
}

/// One component, drawn from show_component's data. Also used for the
/// previews in Settings → Components.
class ComponentView extends ConsumerWidget {
  const ComponentView({super.key, required this.data, this.framed = true});
  final Map<String, dynamic> data;
  final bool framed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(componentPrefsProvider);
    final colors = prefs.palette.colors(AppColors.tint);
    final kind = ComponentKind.values.asNameMap()[_s(data['component'])];
    if (kind == null) return const SizedBox.shrink();
    final body = switch (kind) {
      ComponentKind.chart => _Chart(d: data, colors: colors, prefs: prefs),
      ComponentKind.stats => _Stats(items: _items(data)),
      ComponentKind.table => _Table(d: data),
      ComponentKind.progress => _Progress(items: _items(data), colors: colors),
      ComponentKind.timeline => _Timeline(items: _items(data), color: colors.first),
      ComponentKind.comparison => _Comparison(d: data, colors: colors),
      ComponentKind.gauge => _Gauge(d: data, color: colors.first),
      ComponentKind.radar => _Radar(d: data, colors: colors),
      ComponentKind.heatmap => _Heatmap(d: data, color: colors.first),
      ComponentKind.funnel => _Funnel(items: _items(data), colors: colors, unit: _s(data['unit'])),
      ComponentKind.breakdown => _Breakdown(items: _items(data), colors: colors, unit: _s(data['unit'])),
      ComponentKind.metric => _Metric(d: data, color: colors.first),
      ComponentKind.rings => _Rings(items: _items(data), colors: colors),
      ComponentKind.leaderboard => _Leaderboard(items: _items(data), color: colors.first, unit: _s(data['unit'])),
      ComponentKind.checklist => _Checklist(items: _items(data), color: colors.first),
      ComponentKind.steps => _Steps(items: _items(data), color: colors.first),
      ComponentKind.board => _Board(d: data, colors: colors),
      ComponentKind.callout => _Callout(d: data),
      ComponentKind.facts => _Facts(d: data, color: colors.first),
      ComponentKind.receipt => _Receipt(d: data, color: colors.first),
      ComponentKind.countdown => _Countdown(d: data, color: colors.first),
    };
    // A callout is its own coloured box: no card around it.
    if (kind == ComponentKind.callout) {
      return Padding(padding: framed ? const EdgeInsets.only(bottom: Space.s) : const EdgeInsets.all(Space.l), child: body);
    }
    // The fact sheet draws its own header (emoji, title) edge to edge.
    final ownHeader = kind == ComponentKind.facts;
    final title = _s(data['title']);
    final subtitle = _s(data['subtitle']);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ownHeader && (title.isNotEmpty || subtitle.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
            child: Row(
              children: [
                Icon(kind.icon, size: 16, color: colors.first),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty) Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle.isNotEmpty) Text(subtitle, style: context.text.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (ownHeader) body else Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.l), child: body),
      ],
    );
    if (!framed) return content;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> d) => [
    for (final i in _list(d['items'])) if (i is Map) Map<String, dynamic>.from(i),
  ];
}

// ---- chart -------------------------------------------------------------------------------

class _Series {
  _Series(this.name, this.values);
  final String name;
  final List<double> values;
}

class _Chart extends StatefulWidget {
  const _Chart({required this.d, required this.colors, required this.prefs});
  final Map<String, dynamic> d;
  final List<Color> colors;
  final ComponentPrefs prefs;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  int? _at;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final type = _s(d['chart_type']).isEmpty ? 'line' : _s(d['chart_type']);
    final unit = _s(d['unit']);
    final series = [
      for (final s in _list(d['series']))
        if (s is Map) _Series(_s(s['name']), [for (final v in _list(s['values'])) _n(v) ?? 0]),
    ];
    if (series.isEmpty) return const SizedBox.shrink();
    final n = series.map((s) => s.values.length).reduce(math.max);
    final labels = [for (var i = 0; i < n; i++) i < _list(d['labels']).length ? _s(_list(d['labels'])[i]) : '${i + 1}'];
    final colors = widget.colors;

    if (type == 'pie' || type == 'donut') return _pie(context, labels, series.first.values, unit, donut: type == 'donut');
    if (type == 'hbar') return _hbars(context, labels, series, unit);

    final legend = series.length > 1
        ? Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Wrap(
              spacing: Space.m,
              runSpacing: 4,
              children: [
                for (final (i, s) in series.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 5),
                      Text(s.name, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                    ],
                  ),
              ],
            ),
          )
        : null;

    final at = _at;
    final readout = Container(
      height: 34,
      alignment: Alignment.centerLeft,
      child: at == null
          ? Text(
              series.length == 1 && series.first.values.isNotEmpty
                  ? '${labels.last}: ${_fmt(series.first.values.last, unit)}'
                  : 'Touch the chart to read values',
              style: context.text.labelSmall,
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(labels[at], style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  for (final (i, s) in series.indexed)
                    if (at < s.values.length) ...[
                      const SizedBox(width: Space.m),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(_fmt(s.values[at], unit), style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                    ],
                ],
              ),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?legend,
        readout,
        LayoutBuilder(
          builder: (context, box) {
            void pick(Offset p) {
              const left = 40.0;
              final w = box.maxWidth - left;
              if (w <= 0 || n == 0) return;
              final i = type == 'bar' ? ((p.dx - left) / (w / n)).floor() : (((p.dx - left) / w) * (n - 1)).round();
              setState(() => _at = i.clamp(0, n - 1));
            }

            return GestureDetector(
              onTapDown: (e) => pick(e.localPosition),
              onHorizontalDragUpdate: (e) => pick(e.localPosition),
              onHorizontalDragEnd: (_) {},
              child: AnimatedBuilder(
                animation: _grow,
                builder: (context, _) => CustomPaint(
                  size: Size(box.maxWidth, 190),
                  painter: _XYPainter(
                    series: series,
                    labels: labels,
                    colors: colors,
                    type: type,
                    curved: widget.prefs.curved,
                    showValues: widget.prefs.showValues,
                    unit: unit,
                    t: Curves.easeOutCubic.transform(_grow.value),
                    selected: _at,
                    line: AppColors.line,
                    text: AppColors.text3,
                    valueText: AppColors.text2,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _pie(BuildContext context, List<String> labels, List<double> values, String unit, {required bool donut}) {
    final total = values.fold<double>(0, (a, b) => a + b.abs());
    final colors = widget.colors;
    return Row(
      children: [
        SizedBox.square(
          dimension: 132,
          child: AnimatedBuilder(
            animation: _grow,
            builder: (context, _) => CustomPaint(
              painter: _PiePainter(values: values, colors: colors, donut: donut, t: Curves.easeOutCubic.transform(_grow.value), selected: _at, gap: AppColors.surface),
              child: donut
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fmt(_at == null ? total : values[_at!], unit), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                          Text(_at == null ? 'total' : labels[_at!], maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, l) in labels.indexed)
                if (i < values.length)
                  InkWell(
                    borderRadius: BorderRadius.circular(Radii.s),
                    onTap: () => setState(() => _at = _at == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(color: AppColors.text, fontWeight: _at == i ? FontWeight.w700 : null),
                            ),
                          ),
                          Text(
                            total == 0 ? '—' : '${(values[i].abs() / total * 100).toStringAsFixed(0)}%',
                            style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures, color: AppColors.text2),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hbars(BuildContext context, List<String> labels, List<_Series> series, String unit) {
    final max = series.expand((s) => s.values).fold<double>(0, (a, b) => math.max(a, b.abs()));
    final colors = widget.colors;
    return AnimatedBuilder(
      animation: _grow,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_grow.value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, l) in labels.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text))),
                        if (widget.prefs.showValues)
                          Text(
                            series.map((s) => i < s.values.length ? _fmt(s.values[i], unit) : '').join(' · '),
                            style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures, color: AppColors.text2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final (si, s) in series.indexed)
                      if (i < s.values.length)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: Stack(
                              children: [
                                Container(height: series.length > 1 ? 6 : 9, color: AppColors.surface2),
                                FractionallySizedBox(
                                  widthFactor: max == 0 ? 0 : (s.values[i].abs() / max * t).clamp(0.0, 1.0),
                                  child: Container(height: series.length > 1 ? 6 : 9, color: colors[si % colors.length]),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _XYPainter extends CustomPainter {
  _XYPainter({
    required this.series,
    required this.labels,
    required this.colors,
    required this.type,
    required this.curved,
    required this.showValues,
    required this.unit,
    required this.t,
    required this.selected,
    required this.line,
    required this.text,
    required this.valueText,
  });

  final List<_Series> series;
  final List<String> labels;
  final List<Color> colors;
  final String type;
  final bool curved;
  final bool showValues;
  final String unit;
  final double t;
  final int? selected;
  final Color line;
  final Color text;
  final Color valueText;

  static const _left = 40.0;
  static const _bottom = 22.0;
  static const _top = 8.0;

  void _label(Canvas c, String s, Offset at, {Color? color, double size = 10, TextAlign align = TextAlign.center, double maxWidth = 60, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color ?? text, fontWeight: bold ? FontWeight.w700 : null, fontFeatures: tabularFigures)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((s) => s.values).toList();
    if (all.isEmpty) return;
    var lo = math.min(0.0, all.reduce(math.min));
    var hi = all.reduce(math.max);
    if (hi == lo) hi = lo + 1;
    // Round the top to a tidy step.
    final rawStep = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((s) => s >= rawStep, orElse: () => rawStep);
    hi = (hi / step).ceil() * step;
    lo = (lo / step).floor() * step;

    final w = size.width - _left;
    final h = size.height - _bottom - _top;
    double y(double v) => _top + h - (v - lo) / (hi - lo) * h;
    final n = labels.length;
    final bar = type == 'bar';
    double x(int i) => bar ? _left + (i + 0.5) * w / n : _left + (n == 1 ? w / 2 : i * w / (n - 1));

    // Grid.
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + step / 2; v += step) {
      final yy = y(v);
      canvas.drawLine(Offset(_left, yy), Offset(size.width, yy), grid);
      _label(canvas, _fmt(v, unit), Offset(_left - 6, yy), align: TextAlign.right, maxWidth: _left - 6);
    }
    // X labels, thinned to fit.
    final every = math.max(1, (n / (w / 44)).ceil());
    for (var i = 0; i < n; i += every) {
      _label(canvas, labels[i], Offset(x(i), size.height - _bottom / 2), maxWidth: math.max(28, w / n * every));
    }

    if (selected != null) {
      canvas.drawLine(Offset(x(selected!), _top), Offset(x(selected!), _top + h), Paint()
        ..color = text.withValues(alpha: 0.5)
        ..strokeWidth = 1);
    }

    if (bar) {
      final groupW = w / n * 0.72;
      final bw = groupW / series.length;
      for (final (si, s) in series.indexed) {
        final paint = Paint()..color = colors[si % colors.length];
        for (var i = 0; i < s.values.length && i < n; i++) {
          final v = s.values[i] * t;
          final left = x(i) - groupW / 2 + si * bw;
          final r = Rect.fromLTRB(left + 1, math.min(y(v), y(0)), left + bw - 1, math.max(y(v), y(0)));
          canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
              paint..color = colors[si % colors.length].withValues(alpha: selected == null || selected == i ? 1 : 0.45));
          if (showValues && n * series.length <= 14 && t > 0.95) {
            _label(canvas, _fmt(s.values[i], unit), Offset(left + bw / 2, r.top - 7), color: valueText, size: 9, maxWidth: bw + 16);
          }
        }
      }
      return;
    }

    for (final (si, s) in series.indexed) {
      final c = colors[si % colors.length];
      final pts = [for (var i = 0; i < s.values.length && i < n; i++) Offset(x(i), y(lo + (s.values[i] - lo) * t))];
      if (pts.isEmpty) continue;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        if (curved) {
          final p0 = pts[i - 1], p1 = pts[i];
          final mx = (p0.dx + p1.dx) / 2;
          path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
        } else {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
      }
      if (type == 'area') {
        final fill = Path.from(path)
          ..lineTo(pts.last.dx, y(math.max(lo, 0)))
          ..lineTo(pts.first.dx, y(math.max(lo, 0)))
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: series.length > 1 ? 0.22 : 0.32), c.withValues(alpha: 0.02)],
            ).createShader(Rect.fromLTWH(0, _top, size.width, h)),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (pts.length <= 16 || selected != null) {
        for (final (i, p) in pts.indexed) {
          if (pts.length > 16 && i != selected) continue;
          final big = i == selected;
          canvas.drawCircle(p, big ? 5 : 3, Paint()..color = c);
          canvas.drawCircle(p, big ? 2.4 : 1.4, Paint()..color = Colors.white);
        }
      }
      if (showValues && series.length == 1 && selected == null && t > 0.95) {
        _label(canvas, _fmt(s.values[pts.length - 1], unit), Offset(pts.last.dx - 4, pts.last.dy - 12), color: c, align: TextAlign.right, bold: true, maxWidth: 70);
      }
    }
  }

  @override
  bool shouldRepaint(_XYPainter o) => o.t != t || o.selected != selected || o.series != series || o.type != type || o.curved != curved || o.colors != colors;
}

class _PiePainter extends CustomPainter {
  _PiePainter({required this.values, required this.colors, required this.donut, required this.t, required this.selected, required this.gap});
  final List<double> values;
  final List<Color> colors;
  final bool donut;
  final double t;
  final int? selected;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b.abs());
    if (total == 0) return;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    var start = -math.pi / 2;
    for (final (i, v) in values.indexed) {
      final sweep = v.abs() / total * 2 * math.pi * t;
      final grow = selected == i ? 4.0 : 0.0;
      final rect = Rect.fromCircle(center: center, radius: r - 4 + grow);
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: selected == null || selected == i ? 1 : 0.4);
      if (donut) {
        canvas.drawArc(
          rect.deflate(11),
          start,
          math.max(0, sweep - 0.03),
          false,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 22,
        );
      } else {
        canvas.drawArc(rect, start, sweep, true, paint);
        canvas.drawArc(rect, start, sweep, true, Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter o) => o.t != t || o.selected != selected || o.values != values || o.colors != colors;
}

// ---- stats -------------------------------------------------------------------------------

class _Stats extends StatelessWidget {
  const _Stats({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth > 520 ? 3 : 2;
      final w = (box.maxWidth - Space.s * (cols - 1)) / cols;
      return Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          for (final i in items)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_s(i['label']).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(_s(i['value']), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                    ),
                    if (_n(i['delta']) case final delta?) ...[
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final good = (delta >= 0) != (i['up_is_bad'] == true);
                          final c = delta == 0 ? AppColors.text3 : (good ? AppColors.success : AppColors.danger);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(delta > 0 ? Icons.trending_up_rounded : (delta < 0 ? Icons.trending_down_rounded : Icons.trending_flat_rounded), size: 15, color: c),
                              const SizedBox(width: 3),
                              Text('${delta > 0 ? '+' : ''}${delta.toStringAsFixed(delta.abs() < 10 ? 1 : 0)}%',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c, fontFeatures: tabularFigures)),
                            ],
                          );
                        },
                      ),
                    ],
                    if (_s(i['hint']).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_s(i['hint']), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

// ---- table -------------------------------------------------------------------------------

class _Table extends StatelessWidget {
  const _Table({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) => MarkdownTable(
    head: [for (final c in _list(d['columns'])) _s(c)],
    rows: [
      for (final r in _list(d['rows']))
        if (r is List) [for (final c in r) _s(c)],
    ],
    onLink: openLink,
  );
}

// ---- progress ----------------------------------------------------------------------------

class _Progress extends StatelessWidget {
  const _Progress({required this.items, required this.colors});
  final List<Map<String, dynamic>> items;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (context, t, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          Builder(
            builder: (context) {
              final v = _n(item['value']) ?? 0;
              final max = _n(item['max']) ?? 100;
              final f = max == 0 ? 0.0 : (v / max).clamp(0.0, 1.0);
              final done = f >= 1;
              final c = done ? AppColors.success : colors[i % colors.length];
              final unit = _s(item['unit']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (done) ...[Icon(Icons.check_circle_rounded, size: 16, color: c), const SizedBox(width: 5)],
                        Expanded(child: Text(_s(item['label']), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
                        Text('${_fmt(v, unit)} / ${_fmt(max, unit)}', style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures, color: AppColors.text2)),
                        const SizedBox(width: Space.s),
                        SizedBox(
                          width: 38,
                          child: Text('${(f * 100).round()}%',
                              textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: c, fontFeatures: tabularFigures)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: f * t, minHeight: 8, color: c, backgroundColor: AppColors.surface2),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    ),
  );
}

// ---- timeline ----------------------------------------------------------------------------

class _Timeline extends StatelessWidget {
  const _Timeline({required this.items, required this.color});
  final List<Map<String, dynamic>> items;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, item) in items.indexed)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(width: 2, height: 6, color: i == 0 ? Colors.transparent : AppColors.line),
                    _dot(_s(item['status'])),
                    Expanded(child: Container(width: 2, color: i == items.length - 1 ? Colors.transparent : AppColors.line)),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_s(item['time']).isNotEmpty)
                        Text(_s(item['time']), style: context.text.labelSmall?.copyWith(color: _s(item['status']) == 'next' ? color : null, fontWeight: FontWeight.w700)),
                      Text(_s(item['title']), style: context.text.titleSmall),
                      if (_s(item['detail']).isNotEmpty) Text(_s(item['detail']), style: context.text.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _dot(String status) => switch (status) {
    'done' => Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
    'next' => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.2), border: Border.all(color: color, width: 3)),
    ),
    _ => Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface, border: Border.all(color: AppColors.text3, width: 2)),
    ),
  };
}

// ---- comparison --------------------------------------------------------------------------

class _Comparison extends StatelessWidget {
  const _Comparison({required this.d, required this.colors});
  final Map<String, dynamic> d;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final options = [for (final o in _list(d['options'])) if (o is Map) Map<String, dynamic>.from(o)];
    final scores = [for (final o in options) _n(o['score'])];
    final best = scores.every((s) => s == null) ? -1 : scores.indexOf(scores.whereType<double>().reduce(math.max));
    Widget card(int i, Map<String, dynamic> o) {
      final c = colors[i % colors.length];
      final score = scores[i];
      return Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(Radii.m),
          border: Border.all(color: i == best ? c : Colors.transparent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i == best)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)),
                child: const Text('TOP PICK', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
              ),
            Text(_s(o['name']), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (score != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(score.toStringAsFixed(score == score.roundToDouble() ? 0 : 1),
                      style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c, fontFeatures: tabularFigures)),
                  Text(' /10', style: context.text.labelSmall),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: (score / 10).clamp(0.0, 1.0), minHeight: 5, color: c, backgroundColor: AppColors.surface),
              ),
            ],
            const SizedBox(height: Space.s),
            for (final p in _list(o['pros'])) _point(context, '$p', true),
            for (final p in _list(o['cons'])) _point(context, '$p', false),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (options.length <= 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, o) in options.indexed) ...[if (i > 0) const SizedBox(width: Space.s), Expanded(child: card(i, o))],
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, o) in options.indexed) ...[if (i > 0) const SizedBox(width: Space.s), SizedBox(width: 190, child: card(i, o))],
                ],
              ),
            ),
          ),
        if (_s(d['verdict']).isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.recommend_outlined, size: 18, color: colors.first),
              const SizedBox(width: Space.s),
              Expanded(child: Text(_s(d['verdict']), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _point(BuildContext context, String text, bool pro) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(pro ? Icons.add_circle_rounded : Icons.remove_circle_rounded, size: 14, color: pro ? AppColors.success : AppColors.danger),
        const SizedBox(width: 5),
        Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(color: AppColors.text))),
      ],
    ),
  );
}

// ---- gauge -------------------------------------------------------------------------------

class _Gauge extends StatelessWidget {
  const _Gauge({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = _n(d['value']) ?? 0;
    final lo = _n(d['min']) ?? 0;
    final hi = _n(d['max']) ?? 100;
    final f = hi == lo ? 0.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    final unit = _s(d['unit']);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: f),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(
        children: [
          SizedBox(
            height: 120,
            width: 220,
            child: CustomPaint(
              painter: _GaugePainter(fraction: t, color: color, track: AppColors.surface2),
              child: Align(
                alignment: const Alignment(0, 0.75),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_fmt(v, unit), style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                    if (_s(d['label']).isNotEmpty) Text(_s(d['label']), style: context.text.labelSmall),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(_fmt(lo, unit), style: context.text.labelSmall), Text(_fmt(hi, unit), style: context.text.labelSmall)],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction, required this.color, required this.track});
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height) - 10;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height - 4), radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, base..color = track);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * fraction,
      false,
      base
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: 2 * math.pi,
          colors: [color.withValues(alpha: 0.55), color],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.fraction != fraction || o.color != color;
}
