part of 'component_cards.dart';

// The newer components: radar, heatmap, funnel, breakdown, metric, rings,
// leaderboard, checklist, steps, board, callout, fact sheet, receipt and
// countdown. Same helpers and look as the first seven.

List<Map<String, dynamic>> _maps(Object? v) => [for (final i in _list(v)) if (i is Map) Map<String, dynamic>.from(i)];

/// A soft fill of [c] for chips and panels.
Color _soft(Color c, [double a = 0.14]) => c.withValues(alpha: a);

// ---- radar -------------------------------------------------------------------------------

class _Radar extends StatelessWidget {
  const _Radar({required this.d, required this.colors});
  final Map<String, dynamic> d;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final labels = [for (final l in _list(d['labels'])) _s(l)];
    final series = [
      for (final s in _list(d['series']))
        if (s is Map) _Series(_s(s['name']), [for (var i = 0; i < labels.length; i++) i < _list(s['values']).length ? (_n(_list(s['values'])[i]) ?? 0) : 0]),
    ];
    if (labels.length < 3 || series.isEmpty) return const SizedBox.shrink();
    final top = _n(d['max']) ?? series.expand((s) => s.values).fold<double>(0, math.max);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutBack,
          builder: (context, t, _) => SizedBox(
            height: 250,
            child: CustomPaint(
              size: const Size(double.infinity, 250),
              painter: _RadarPainter(
                labels: labels,
                series: series,
                max: top <= 0 ? 1 : top,
                colors: colors,
                t: t,
                grid: AppColors.line,
                text: AppColors.text2,
                style: context.text.labelSmall ?? const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: Space.s),
          _Legend(names: [for (final s in series) s.name], colors: colors),
        ],
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.labels, required this.series, required this.max, required this.colors, required this.t, required this.grid, required this.text, required this.style});
  final List<String> labels;
  final List<_Series> series;
  final double max;
  final List<Color> colors;
  final double t;
  final Color grid;
  final Color text;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 34;
    final n = labels.length;
    Offset at(int i, double f) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * f;
    }

    final web = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;
    for (final level in [0.25, 0.5, 0.75, 1.0]) {
      final p = Path();
      for (var i = 0; i < n; i++) {
        final o = at(i, level);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p..close(), web);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, at(i, 1), web);
      final tp = TextPainter(text: TextSpan(text: labels[i], style: style.copyWith(color: text, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')
        ..layout(maxWidth: 80);
      final o = at(i, 1.18);
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
    for (final (k, s) in series.indexed) {
      final col = colors[k % colors.length];
      final p = Path();
      for (var i = 0; i < n; i++) {
        final o = at(i, (s.values[i] / max).clamp(0.0, 1.0) * t);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      p.close();
      canvas.drawPath(p, Paint()..color = col.withValues(alpha: 0.18));
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..color = col,
      );
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(at(i, (s.values[i] / max).clamp(0.0, 1.0) * t), 3.2, Paint()..color = col);
      }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter o) => o.t != t || o.colors != colors || o.grid != grid;
}

/// Coloured dots with names, for components with several series.
class _Legend extends StatelessWidget {
  const _Legend({required this.names, required this.colors});
  final List<String> names;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: Space.m,
    runSpacing: 4,
    children: [
      for (final (i, n) in names.indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(n, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
          ],
        ),
    ],
  );
}

// ---- heatmap -----------------------------------------------------------------------------

class _Heatmap extends StatefulWidget {
  const _Heatmap({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  State<_Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<_Heatmap> {
  (int, int)? _at;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final cols = [for (final c in _list(d['columns'])) _s(c)];
    final rows = [
      for (final r in _maps(d['rows'])) (label: _s(r['label']), values: [for (final v in _list(r['values'])) _n(v) ?? 0]),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final n = rows.map((r) => r.values.length).fold<int>(cols.length, math.max);
    final all = rows.expand((r) => r.values);
    final lo = all.isEmpty ? 0.0 : all.reduce(math.min);
    final hi = all.isEmpty ? 1.0 : all.reduce(math.max);
    final unit = _s(d['unit']);
    final every = n > 12 ? (n / 6).ceil() : 1;
    Color shade(double v) {
      final f = hi == lo ? 1.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
      return Color.lerp(AppColors.surface2, widget.color, 0.12 + 0.88 * f)!;
    }

    final at = _at;
    final labelStyle = context.text.labelSmall?.copyWith(fontSize: 10.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: Text(
            at == null
                ? 'Tap a cell to read it'
                : '${rows[at.$1].label}${at.$2 < cols.length ? ' · ${cols[at.$2]}' : ''}: ${_fmt(at.$2 < rows[at.$1].values.length ? rows[at.$1].values[at.$2] : 0, unit)}',
            style: at == null ? context.text.labelSmall : context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 44),
            for (var c = 0; c < n; c++)
              Expanded(
                child: Text(c < cols.length && c % every == 0 ? cols[c] : '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: labelStyle),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (r, row) in rows.indexed)
          Row(
            children: [
              SizedBox(width: 44, child: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle?.copyWith(fontWeight: FontWeight.w600))),
              for (var c = 0; c < n; c++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _at = _at == (r, c) ? null : (r, c)),
                    child: AspectRatio(
                      aspectRatio: n > 12 ? 0.8 : 1.25,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: shade(c < row.values.length ? row.values[c] : lo),
                          borderRadius: BorderRadius.circular(n > 12 ? 3 : 5),
                          border: at == (r, c) ? Border.all(color: AppColors.text, width: 1.5) : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: Space.s),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: labelStyle),
            const SizedBox(width: 5),
            for (final f in [0.0, 0.25, 0.5, 0.75, 1.0])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(color: Color.lerp(AppColors.surface2, widget.color, 0.12 + 0.88 * f), borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 5),
            Text('More', style: labelStyle),
          ],
        ),
      ],
    );
  }
}

// ---- funnel ------------------------------------------------------------------------------

class _Funnel extends StatelessWidget {
  const _Funnel({required this.items, required this.colors, required this.unit});
  final List<Map<String, dynamic>> items;
  final List<Color> colors;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = [for (final i in items) _n(i['value']) ?? 0];
    final top = values.fold<double>(0, math.max);
    if (top <= 0) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.south_rounded, size: 13, color: AppColors.text3),
                    const SizedBox(width: 3),
                    Text(
                      values[i - 1] == 0 ? '—' : '${(values[i] / values[i - 1] * 100).toStringAsFixed(values[i] / values[i - 1] < 0.1 ? 1 : 0)}% continue',
                      style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            Text(_s(item['label']), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text2)),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: math.max(0.22, values[i] / top) * (0.6 + 0.4 * t),
              child: Container(
                height: 38,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [colors[i % colors.length], Color.lerp(colors[i % colors.length], Colors.white, 0.15)!]),
                  borderRadius: BorderRadius.circular(Radii.m),
                  boxShadow: [BoxShadow(color: colors[i % colors.length].withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_fmt(values[i], unit), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, fontFeatures: tabularFigures)),
                ),
              ),
            ),
          ],
          if (values.length > 1 && values.first > 0) ...[
            const SizedBox(height: Space.m),
            Text(
              '${(values.last / values.first * 100).toStringAsFixed(values.last / values.first < 0.1 ? 1 : 0)}% made it all the way',
              style: context.text.labelMedium?.copyWith(color: AppColors.text2, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- breakdown ---------------------------------------------------------------------------

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.items, required this.colors, required this.unit});
  final List<Map<String, dynamic>> items;
  final List<Color> colors;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final parts = [for (final i in items) (label: _s(i['label']), value: math.max(0.0, _n(i['value']) ?? 0))];
    final total = parts.fold<double>(0, (a, p) => a + p.value);
    if (total <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_fmt(total, unit), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
            const SizedBox(width: 6),
            Text('in total', style: context.text.labelSmall),
          ],
        ),
        const SizedBox(height: Space.s),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (final (i, p) in parts.indexed)
                    if (p.value > 0)
                      Expanded(
                        flex: math.max(1, (p.value / total * 1000 * t).round()),
                        child: Container(
                          margin: EdgeInsets.only(right: i == parts.length - 1 ? 0 : 2),
                          color: colors[i % colors.length],
                        ),
                      ),
                  if (t < 1) Expanded(flex: math.max(1, ((1 - t) * 1000).round()), child: Container(color: AppColors.surface2)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        for (final (i, p) in parts.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: Space.s),
                Expanded(child: Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
                Text(_fmt(p.value, unit), style: context.text.labelMedium?.copyWith(color: AppColors.text2, fontFeatures: tabularFigures)),
                const SizedBox(width: Space.s),
                Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(color: _soft(colors[i % colors.length]), borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '${(p.value / total * 100).toStringAsFixed(p.value / total < 0.1 ? 1 : 0)}%',
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.text, fontFeatures: tabularFigures),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- metric ------------------------------------------------------------------------------

class _Metric extends StatelessWidget {
  const _Metric({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final delta = _n(d['delta']);
    final trend = [for (final v in _list(d['trend'])) ?_n(v)];
    final good = delta == null || ((delta >= 0) != (d['up_is_bad'] == true));
    final dc = delta == null || delta == 0 ? AppColors.text3 : (good ? AppColors.success : AppColors.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_s(d['value']), style: context.text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, fontFeatures: tabularFigures)),
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: Space.m),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _soft(dc, 0.15), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(delta > 0 ? Icons.arrow_upward_rounded : (delta < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded), size: 14, color: dc),
                    const SizedBox(width: 2),
                    Text('${delta.abs().toStringAsFixed(delta.abs() < 10 ? 1 : 0)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: dc, fontFeatures: tabularFigures)),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (_s(d['label']).isNotEmpty) Text(_s(d['label']), style: context.text.bodySmall),
        if (trend.length > 1) ...[
          const SizedBox(height: Space.m),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(size: const Size(double.infinity, 64), painter: _SparkPainter(values: trend, color: color, t: t)),
          ),
        ],
        if (_s(d['hint']).isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(child: Text(_s(d['hint']), style: context.text.labelMedium?.copyWith(color: AppColors.text2))),
            ],
          ),
        ],
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color, required this.t});
  final List<double> values;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi == lo ? 1.0 : hi - lo;
    final pts = [
      for (var i = 0; i < values.length; i++) Offset(size.width * i / (values.length - 1), 6 + (size.height - 12) * (1 - (values[i] - lo) / span)),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.restore();
    if (t >= 1) {
      canvas.drawCircle(pts.last, 6, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.t != t || o.color != color;
}

// ---- rings -------------------------------------------------------------------------------

class _Rings extends StatelessWidget {
  const _Rings({required this.items, required this.colors});
  final List<Map<String, dynamic>> items;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final rings = [
      for (final i in items.take(4))
        (label: _s(i['label']), value: _n(i['value']) ?? 0, max: _n(i['max']) ?? 100, unit: _s(i['unit'])),
    ];
    if (rings.isEmpty) return const SizedBox.shrink();
    final fractions = [for (final r in rings) r.max == 0 ? 0.0 : (r.value / r.max).clamp(0.0, 1.0)];
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            size: const Size.square(132),
            painter: _RingsPainter(fractions: [for (final f in fractions) f * t], colors: colors),
          ),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, r) in rings.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: colors[i % colors.length], fontWeight: FontWeight.w800)),
                          ),
                          if (fractions[i] >= 1) Icon(Icons.check_circle_rounded, size: 15, color: colors[i % colors.length]),
                        ],
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: _fmt(r.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: ' / ${_fmt(r.max, r.unit)}', style: TextStyle(color: AppColors.text3)),
                          ],
                        ),
                        style: context.text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.fractions, required this.colors});
  final List<double> fractions;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const stroke = 13.0;
    const gap = 3.5;
    for (var i = 0; i < fractions.length; i++) {
      final r = size.width / 2 - stroke / 2 - i * (stroke + gap);
      if (r <= stroke / 2) break;
      final col = colors[i % colors.length];
      final rect = Rect.fromCircle(center: c, radius: r);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(c, r, p..color = col.withValues(alpha: 0.16));
      if (fractions[i] > 0) {
        canvas.drawArc(
          rect,
          -math.pi / 2,
          2 * math.pi * fractions[i],
          false,
          p
            ..shader = SweepGradient(
              startAngle: 0,
              endAngle: 2 * math.pi,
              transform: const GradientRotation(-math.pi / 2),
              colors: [Color.lerp(col, Colors.white, 0.2)!, col],
            ).createShader(rect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.fractions != fractions || o.colors != colors;
}

// ---- leaderboard -------------------------------------------------------------------------

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.items, required this.color, required this.unit});
  final List<Map<String, dynamic>> items;
  final Color color;
  final String unit;

  static const _medals = [Color(0xFFF5B700), Color(0xFFA8B2BD), Color(0xFFCD7F32)];

  @override
  Widget build(BuildContext context) {
    final rows = [for (final i in items) (name: _s(i['name'] ?? i['label']), value: _n(i['value']) ?? 0, sub: _s(i['subtitle']))]..sort((a, b) => b.value.compareTo(a.value));
    if (rows.isEmpty) return const SizedBox.shrink();
    final top = rows.first.value <= 0 ? 1.0 : rows.first.value;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Column(
        children: [
          for (final (i, r) in rows.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              decoration: BoxDecoration(
                color: i == 0 ? _soft(_medals.first, 0.12) : AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.m),
                border: i == 0 ? Border.all(color: _medals.first.withValues(alpha: 0.5)) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: i < 3 ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(_medals[i], Colors.white, 0.35)!, _medals[i]]) : null,
                      color: i < 3 ? null : AppColors.surface3,
                    ),
                    child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: i < 3 ? Colors.white : AppColors.text2)),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                            Text(_fmt(r.value, unit), style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                          ],
                        ),
                        if (r.sub.isNotEmpty) Text(r.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (r.value / top).clamp(0.0, 1.0) * t,
                            minHeight: 5,
                            color: i < 3 ? _medals[i] : color,
                            backgroundColor: AppColors.surface3.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- checklist ---------------------------------------------------------------------------

class _Checklist extends StatefulWidget {
  const _Checklist({required this.items, required this.color});
  final List<Map<String, dynamic>> items;
  final Color color;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  /// Ticks changed here, over what was sent.
  final _ticked = <int, bool>{};

  bool _done(int i) => _ticked[i] ?? (widget.items[i]['done'] == true || _s(widget.items[i]['done']) == 'true');

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final done = [for (var i = 0; i < items.length; i++) if (_done(i)) i].length;
    final f = items.isEmpty ? 0.0 : done / items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('$done of ${items.length} done', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: f >= 1 ? AppColors.success : AppColors.text2)),
            const SizedBox(width: Space.m),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: f),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: f >= 1 ? AppColors.success : widget.color, backgroundColor: AppColors.surface2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        for (var i = 0; i < items.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(Radii.m),
            onTap: () => setState(() => _ticked[i] = !_done(i)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: _done(i)
                        ? Icon(Icons.check_circle_rounded, key: const ValueKey(true), size: 22, color: AppColors.success)
                        : Icon(Icons.radio_button_unchecked_rounded, key: const ValueKey(false), size: 22, color: AppColors.text3),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: (context.text.bodyMedium ?? const TextStyle()).copyWith(
                            color: _done(i) ? AppColors.text3 : AppColors.text,
                            decoration: _done(i) ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.text3,
                          ),
                          child: Text(_s(items[i]['text'] ?? items[i]['title'] ?? items[i]['label'])),
                        ),
                        if (_s(items[i]['note']).isNotEmpty) Text(_s(items[i]['note']), style: context.text.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- steps -------------------------------------------------------------------------------

class _Steps extends StatelessWidget {
  const _Steps({required this.items, required this.color});
  final List<Map<String, dynamic>> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final on = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.2)!, color]),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: on)),
                      ),
                      if (i < items.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(color: _soft(color, 0.35), borderRadius: BorderRadius.circular(1)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 4, bottom: i < items.length - 1 ? Space.l : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_s(item['title'] ?? item['text']), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        if (_s(item['detail']).isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_s(item['detail']), style: context.text.bodySmall?.copyWith(height: 1.4)),
                        ],
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
}

// ---- board -------------------------------------------------------------------------------

/// A board: a strip showing how the work is spread, then the lanes side by
/// side, each a soft wash of its colour holding its cards. A card can carry
/// tags, who has it and when it's due; cards in a "done" lane read as done.
class _Board extends StatelessWidget {
  const _Board({required this.d, required this.colors});
  final Map<String, dynamic> d;
  final List<Color> colors;

  static final _doneLane = RegExp(r'\b(done|complete[d]?|finished|shipped|closed)\b', caseSensitive: false);

  /// A tag's colour: urgent ones red, quiet ones grey, the rest from the
  /// palette, the same tag always the same colour.
  Color _tagColor(String tag) {
    final t = tag.toLowerCase();
    if (RegExp(r'urgent|high|bug|blocker|critical|asap').hasMatch(t)) return AppColors.danger;
    if (RegExp(r'low|later|someday|nice to have').hasMatch(t)) return AppColors.text3;
    return colors[(t.codeUnits.fold<int>(7, (a, c) => a * 31 + c) & 0x7fffffff) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final lanes = [
      for (final l in _maps(d['lanes']))
        (name: _s(l['name']), cards: [for (final c in _list(l['cards'])) c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{'title': _s(c)}]),
    ];
    if (lanes.isEmpty) return const SizedBox.shrink();
    final total = lanes.fold<int>(0, (a, l) => a + l.cards.length);
    final doneAt = lanes.indexWhere((l) => _doneLane.hasMatch(l.name));
    Color laneColor(int i) => i == doneAt ? AppColors.success : colors[i % colors.length];

    final summary = total == 0
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('$total ${total == 1 ? 'card' : 'cards'}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (doneAt >= 0)
                    Text(
                      '${(lanes[doneAt].cards.length / total * 100).round()}% done',
                      style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      for (final (i, l) in lanes.indexed)
                        if (l.cards.isNotEmpty)
                          Expanded(
                            flex: l.cards.length,
                            child: Container(margin: EdgeInsets.only(right: i == lanes.length - 1 ? 0 : 2), color: laneColor(i)),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.m),
            ],
          );

    Widget card(Map<String, dynamic> m, Color c, bool done) {
      final tags = [
        for (final t in _list(m['tags'])) _s(t),
        if (_s(m['tag']).isNotEmpty) _s(m['tag']),
      ].where((t) => t.isNotEmpty).toSet().toList();
      final who = _s(m['who'] ?? m['assignee']);
      final due = _s(m['due']);
      final late = RegExp(r'overdue|today|late|now', caseSensitive: false).hasMatch(due);
      final detail = _s(m['detail']);
      return Container(
        margin: const EdgeInsets.only(bottom: Space.s),
        padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.m),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.m),
          border: Border.all(color: AppColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppColors.isLight ? 0.06 : 0.25), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tags.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: _soft(_tagColor(t), 0.16), borderRadius: BorderRadius.circular(99)),
                      child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Color.lerp(_tagColor(t), AppColors.text, 0.25))),
                    ),
                ],
              ),
              const SizedBox(height: Space.s),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (done) ...[
                  Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    _s(m['title'] ?? m['text']),
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: done ? AppColors.text2 : AppColors.text),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(height: 1.35)),
            ],
            if (who.isNotEmpty || due.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Row(
                children: [
                  if (due.isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: late && !done ? _soft(AppColors.danger, 0.12) : AppColors.surface2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 12, color: late && !done ? AppColors.danger : AppColors.text3),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                due,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: late && !done ? AppColors.danger : AppColors.text2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (who.isNotEmpty)
                    Tooltip(
                      message: who,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(_tagColor(who), Colors.white, 0.25)!, _tagColor(who)]),
                          border: Border.all(color: AppColors.surface, width: 1.5),
                        ),
                        child: Text(
                          who.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w.characters.first.toUpperCase()).join(),
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    Widget lane(int i) {
      final l = lanes[i];
      final c = laneColor(i);
      final done = i == doneAt;
      return Container(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_soft(c, 0.13), _soft(c, 0.04)]),
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: c.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 2, Space.s + 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)]),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(l.name.isEmpty ? 'Lane ${i + 1}' : l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      '${l.cards.length}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black),
                    ),
                  ),
                ],
              ),
            ),
            for (final m in l.cards) card(m, c, done),
            if (l.cards.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: Space.s),
                padding: const EdgeInsets.symmetric(vertical: Space.l),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.m),
                  border: Border.all(color: c.withValues(alpha: 0.3)),
                ),
                child: Text('Nothing here yet', textAlign: TextAlign.center, style: context.text.labelSmall),
              ),
            const SizedBox(height: Space.s),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?summary,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          // Lanes as tall as the tallest, like a real board.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < lanes.length; i++) ...[if (i > 0) const SizedBox(width: Space.s + 2), SizedBox(width: 220, child: lane(i))],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- callout -----------------------------------------------------------------------------

class _Callout extends StatelessWidget {
  const _Callout({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final (color, icon, fallback) = switch (_s(d['tone'])) {
      'tip' => (const Color(0xFFA06CF5), Icons.lightbulb_outline_rounded, 'Tip'),
      'success' => (AppColors.success, Icons.check_circle_outline_rounded, 'Good news'),
      'warning' => (AppColors.warning, Icons.warning_amber_rounded, 'Heads up'),
      'danger' => (AppColors.danger, Icons.error_outline_rounded, 'Important'),
      _ => (const Color(0xFF4F7CFF), Icons.info_outline_rounded, 'Note'),
    };
    final title = _s(d['title']).isEmpty ? fallback : _s(d['title']);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_soft(color, 0.16), _soft(color, 0.06)]),
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: _soft(color, 0.2), borderRadius: BorderRadius.circular(Radii.m)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Color.lerp(color, AppColors.text, 0.3))),
                const SizedBox(height: 3),
                Text(_s(d['text']), style: context.text.bodyMedium?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- fact sheet --------------------------------------------------------------------------

class _Facts extends StatelessWidget {
  const _Facts({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final items = _maps(d['items']);
    final emoji = _s(d['emoji']);
    final title = _s(d['title']);
    final subtitle = _s(d['subtitle']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (emoji.isNotEmpty || title.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_soft(color, 0.22), _soft(color, 0.04)]),
            ),
            child: Row(
              children: [
                if (emoji.isNotEmpty) ...[
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Radii.l),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 30)),
                  ),
                  const SizedBox(width: Space.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty) Text(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (subtitle.isNotEmpty) Text(subtitle, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
          child: Column(
            children: [
              for (final (i, f) in items.indexed) ...[
                if (i > 0) Divider(height: 1, color: AppColors.line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: Text(_s(f['label']), style: context.text.bodySmall?.copyWith(color: AppColors.text2))),
                      const SizedBox(width: Space.m),
                      Expanded(
                        flex: 3,
                        child: Text(_s(f['value']), textAlign: TextAlign.right, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---- receipt -----------------------------------------------------------------------------

class _Receipt extends StatelessWidget {
  const _Receipt({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cur = _s(d['currency']).isEmpty ? r'$' : _s(d['currency']);
    String money(double v) {
      final t = v.abs().toStringAsFixed(2);
      final s = const {r'$', '€', '£', '¥'}.contains(cur) ? '$cur$t' : '$t $cur';
      return v < 0 ? '−$s' : s;
    }

    final lines = [
      for (final i in _maps(d['items'])) (name: _s(i['name'] ?? i['label']), qty: _n(i['qty']) ?? 1, price: _n(i['price']) ?? _n(i['value']) ?? 0),
    ];
    final subtotal = lines.fold<double>(0, (a, l) => a + l.qty * l.price);
    final discount = _n(d['discount']) ?? 0;
    final taxPct = _n(d['tax']) ?? 0;
    final tipPct = _n(d['tip']) ?? 0;
    final base = subtotal - discount;
    final tax = base * taxPct / 100;
    final tip = base * tipPct / 100;
    final total = base + tax + tip;
    final split = (_n(d['split']) ?? 1).round();
    final mono = (context.text.bodyMedium ?? const TextStyle()).copyWith(fontFeatures: tabularFigures);
    Widget row(String l, String v, {bool strong = false, Color? c}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(l, style: strong ? mono.copyWith(fontWeight: FontWeight.w800, fontSize: 16) : mono.copyWith(color: AppColors.text2))),
          Text(v, style: strong ? mono.copyWith(fontWeight: FontWeight.w900, fontSize: 18) : mono.copyWith(color: c)),
        ],
      ),
    );
    String pct(double p) => p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);

    return ClipPath(
      clipper: const _ZigzagClipper(),
      child: Container(
        color: AppColors.surface2,
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xl + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 34, child: Text('${_fmt(l.qty)}×', style: mono.copyWith(color: AppColors.text3, fontWeight: FontWeight.w700))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.name, style: mono.copyWith(fontWeight: FontWeight.w600)),
                          if (l.qty != 1) Text('${money(l.price)} each', style: context.text.labelSmall),
                        ],
                      ),
                    ),
                    Text(money(l.qty * l.price), style: mono),
                  ],
                ),
              ),
            const SizedBox(height: Space.s),
            const _DashedLine(),
            const SizedBox(height: Space.s),
            row('Subtotal', money(subtotal)),
            if (discount != 0) row('Discount', money(-discount), c: AppColors.success),
            if (taxPct != 0) row('Tax (${pct(taxPct)}%)', money(tax)),
            if (tipPct != 0) row('Tip (${pct(tipPct)}%)', money(tip)),
            const SizedBox(height: Space.s),
            const _DashedLine(),
            const SizedBox(height: Space.s),
            row('Total', money(total), strong: true),
            if (split > 1) ...[
              const SizedBox(height: Space.m),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                decoration: BoxDecoration(color: _soft(color, 0.16), borderRadius: BorderRadius.circular(Radii.m)),
                child: Row(
                  children: [
                    Icon(Icons.group_outlined, size: 18, color: color),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text('Split $split ways', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                    Text('${money(total / split)} each', style: mono.copyWith(fontWeight: FontWeight.w900, color: Color.lerp(color, AppColors.text, 0.3))),
                  ],
                ),
              ),
            ],
            if (_s(d['note']).isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text(_s(d['note']), textAlign: TextAlign.center, style: context.text.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(AppColors.text3.withValues(alpha: 0.5)));
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

/// The torn bottom edge of a till receipt.
class _ZigzagClipper extends CustomClipper<Path> {
  const _ZigzagClipper();

  @override
  Path getClip(Size size) {
    const tooth = 10.0;
    const depth = 7.0;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - depth);
    var x = size.width;
    var down = true;
    while (x > 0) {
      x = math.max(0, x - tooth / 2);
      p.lineTo(x, down ? size.height : size.height - depth);
      down = !down;
    }
    return p..close();
  }

  @override
  bool shouldReclip(_ZigzagClipper oldClipper) => false;
}

// ---- countdown ---------------------------------------------------------------------------

class _Countdown extends StatefulWidget {
  const _Countdown({required this.d, required this.color});
  final Map<String, dynamic> d;
  final Color color;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final target = DateTime.tryParse(_s(widget.d['target']))?.toLocal();
    if (target == null) return const SizedBox.shrink();
    final left = target.difference(DateTime.now());
    final past = left.isNegative;
    final a = left.abs();
    final parts = [
      (a.inDays, a.inDays == 1 ? 'day' : 'days'),
      (a.inHours % 24, 'hours'),
      (a.inMinutes % 60, 'min'),
      (a.inSeconds % 60, 'sec'),
    ];
    final when =
        '${_days[target.weekday - 1]} ${target.day} ${_months[target.month - 1]} ${target.year}, ${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
    final c = widget.color;
    return Column(
      children: [
        if (past)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text('🎉 It\'s here', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        Row(
          children: [
            for (final (i, (v, l)) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: Space.m),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_soft(c, past ? 0.08 : 0.2), _soft(c, 0.05)]),
                    borderRadius: BorderRadius.circular(Radii.m),
                    border: Border.all(color: c.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(position: Tween(begin: const Offset(0, -0.3), end: Offset.zero).animate(anim), child: child),
                        ),
                        child: Text(
                          i == 0 ? '$v' : v.toString().padLeft(2, '0'),
                          key: ValueKey(v),
                          style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, fontFeatures: tabularFigures, color: past ? AppColors.text3 : AppColors.text),
                        ),
                      ),
                      Text(l.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Space.m),
        Text(
          [if (_s(widget.d['label']).isNotEmpty) past ? 'since ${_s(widget.d['label']).replaceFirst(RegExp(r'^until\s+', caseSensitive: false), '')}' : _s(widget.d['label']), when].join(' · '),
          textAlign: TextAlign.center,
          style: context.text.labelMedium?.copyWith(color: AppColors.text2),
        ),
      ],
    );
  }
}
