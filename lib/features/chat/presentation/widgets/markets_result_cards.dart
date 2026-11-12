import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../domain/chat_models.dart';

/// Cards for the markets, weather and travel tools: crypto and stock prices
/// with charts, currency conversions, forecasts, flights and holidays. Each
/// opens a sheet with everything the tool returned about it. Null for other
/// tools.
Widget? marketsResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'crypto_prices' when list(j['coins']).isNotEmpty => _CryptoList(coins: list(j['coins']), vs: '${j['vs'] ?? 'usd'}'),
    'crypto_coin' when j['price'] != null => _CoinHero(coin: j),
    'crypto_trending' when list(j['coins']).isNotEmpty => _TrendingStrip(coins: list(j['coins'])),
    'stock_quote' when list(j['quotes']).length == 1 => _StockHero(quote: list(j['quotes']).first),
    'stock_quote' when list(j['quotes']).isNotEmpty => _Panel(
      icon: Icons.candlestick_chart_outlined,
      title: 'Stocks · ${_rangeLabel('${j['range']}')}',
      children: [for (final q in list(j['quotes'])) _StockRow(quote: q)],
    ),
    'stock_search' when list(j['results']).isNotEmpty => _Panel(
      icon: Icons.manage_search_rounded,
      title: 'Tickers for "${j['query']}"',
      children: [for (final r in list(j['results']).take(10)) _TickerRow(result: r)],
    ),
    'currency_convert' when list(j['conversions']).isNotEmpty => _CurrencyCard(data: j),
    'weather' when j['current'] is Map => _WeatherCard(data: j),
    'flight_status' when j['callsign'] != null => _FlightCard(flight: j),
    'flight_search' when list(j['links']).isNotEmpty => _FlightSearchCard(data: j),
    'public_holidays' when list(j['holidays']).isNotEmpty => _HolidaysCard(data: j),
    _ => null,
  };
}

// ---- formatting -----------------------------------------------------------------

double? _d(Object? v) => v is num ? v.toDouble() : null;

const _fiat = {'usd', 'eur', 'gbp', 'jpy', 'cny', 'inr', 'cad', 'aud', 'chf', 'krw', 'brl', 'rub', 'try', 'etb', 'ngn', 'zar', 'mxn', 'sek', 'nok', 'hkd', 'sgd', 'aed'};

/// A price in [currency]: currency symbol for money, more decimals for
/// small amounts, the code after it for crypto quotes.
String _money(Object? v, String? currency) {
  final x = _d(v);
  if (x == null) return '—';
  final a = x.abs();
  final digits = a >= 1000 ? 0 : (a >= 1 ? 2 : (a >= 0.01 ? 4 : 8));
  final cur = (currency ?? '').toLowerCase();
  if (cur.isEmpty || !_fiat.contains(cur)) {
    final n = NumberFormat.decimalPatternDigits(decimalDigits: digits).format(x);
    return cur.isEmpty ? n : '$n ${cur.toUpperCase()}';
  }
  return NumberFormat.simpleCurrency(name: cur.toUpperCase(), decimalDigits: a >= 1000 ? 2 : digits).format(x);
}

String _big(Object? v, [String? currency]) {
  final x = _d(v);
  if (x == null) return '—';
  final n = NumberFormat.compact().format(x);
  final cur = (currency ?? '').toLowerCase();
  if (cur.isEmpty) return n;
  return _fiat.contains(cur) ? '${NumberFormat.simpleCurrency(name: cur.toUpperCase()).currencySymbol}$n' : '$n ${cur.toUpperCase()}';
}

String _pct(Object? v) {
  final x = _d(v);
  if (x == null) return '—';
  return '${x >= 0 ? '+' : ''}${x.toStringAsFixed(2)}%';
}

String _rangeLabel(String r) => switch (r) {
  '1d' => 'today',
  '5d' => '5 days',
  '1mo' => '1 month',
  '6mo' => '6 months',
  '1y' => '1 year',
  '5y' => '5 years',
  _ => r,
};

Color _trend(Object? v) {
  final x = _d(v);
  if (x == null || x == 0) return AppColors.text2;
  return x > 0 ? AppColors.success : AppColors.danger;
}

List<double> _series(Object? v) => [for (final x in (v as List? ?? const [])) if (x is num) x.toDouble()];

Future<void> _launch(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

// ---- shared pieces --------------------------------------------------------------

/// A line chart of [values], green when it ends higher than it starts.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 28, this.width, this.fill = false, this.color});
  final List<double> values;
  final double height;
  final double? width;
  final bool fill;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height, width: width);
    final c = color ?? (values.last >= values.first ? AppColors.success : AppColors.danger);
    return SizedBox(
      height: height,
      // Without a width a CustomPaint is zero wide in a column.
      width: width ?? double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, c, fill)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.fill);
  final List<double> values;
  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - lo) / span * (size.height - 2) - 1;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = fill ? 2 : 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// A price chart that fills its width: line and shading, the high and low
/// marked, start and end times under it, an optional dashed reference
/// (yesterday's close), and press-and-drag to read any point.
class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.values, this.times = const [], this.height = 150, this.currency, this.reference, this.referenceLabel});
  final List<double> values;

  /// Milliseconds since the epoch, one per value; may be empty.
  final List<int> times;
  final double height;
  final String? currency;
  final double? reference;
  final String? referenceLabel;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _at;

  String _time(int i, {bool long = false}) {
    if (i < 0 || i >= widget.times.length || widget.times[i] == 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(widget.times[i]);
    final span = widget.times.length > 1 ? (widget.times.last - widget.times.first).abs() : 0;
    if (span <= const Duration(days: 2).inMilliseconds) return DateFormat(long ? 'EEE HH:mm' : 'HH:mm').format(t);
    if (span <= const Duration(days: 120).inMilliseconds) return DateFormat(long ? 'EEE d MMM, HH:mm' : 'd MMM').format(t);
    return DateFormat(long ? 'd MMM y' : 'MMM y').format(t);
  }

  void _pick(Offset local, double width) {
    final n = widget.values.length;
    if (n < 2 || width <= 0) return;
    final i = ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _at) setState(() => _at = i);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.values;
    if (v.length < 2) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        child: Text('No chart data', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
      );
    }
    final up = v.last >= (widget.reference ?? v.first);
    final color = up ? AppColors.success : AppColors.danger;
    final at = _at;
    final first = _time(0), last = _time(v.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 18,
          child: at == null
              ? null
              : Row(
                  children: [
                    Text(_money(v[at], widget.currency), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: Space.s),
                    _ChangeChip(v.first == 0 ? null : (v[at] - v.first) / v.first * 100),
                    const Spacer(),
                    Text(_time(at, long: true), style: context.text.labelSmall),
                  ],
                ),
        ),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragEnd: (_) => setState(() => _at = null),
            onLongPressStart: (d) => _pick(d.localPosition, c.maxWidth),
            onLongPressMoveUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onLongPressEnd: (_) => setState(() => _at = null),
            onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
            onTapUp: (_) => Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _at = null);
            }),
            child: SizedBox(
              width: c.maxWidth,
              height: widget.height,
              child: CustomPaint(
                painter: _ChartPainter(
                  values: v,
                  color: color,
                  reference: widget.reference,
                  at: at,
                  label: (x) => _money(x, widget.currency),
                  textColor: AppColors.text3,
                  lineColor: AppColors.line,
                ),
              ),
            ),
          ),
        ),
        if (first.isNotEmpty || last.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(first, style: context.text.labelSmall),
                const Spacer(),
                if (widget.referenceLabel != null && widget.reference != null)
                  Text('- - ${widget.referenceLabel}', style: context.text.labelSmall),
                const Spacer(),
                Text(last, style: context.text.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.values, required this.color, required this.reference, required this.at, required this.label, required this.textColor, required this.lineColor});
  final List<double> values;
  final Color color;
  final double? reference;
  final int? at;
  final String Function(double) label;
  final Color textColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if (reference != null) {
      lo = math.min(lo, reference!);
      hi = math.max(hi, reference!);
    }
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    const top = 14.0, bottom = 14.0;
    final h = size.height - top - bottom;
    double y(double v) => top + h - (v - lo) / span * h;
    double x(int i) => size.width * i / (values.length - 1);

    // Grid: three faint lines.
    final grid = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, top + h * f), Offset(size.width, top + h * f), grid);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      i == 0 ? path.moveTo(x(i), y(values[i])) : path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(size.width, top + h)
      ..lineTo(0, top + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, top, size.width, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (reference != null) {
      final ry = y(reference!);
      final dash = Paint()
        ..color = textColor
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, ry), Offset(math.min(dx + 4, size.width), ry), dash);
      }
    }

    // The high and the low, labelled where they happen.
    void mark(int i, bool high) {
      final tp = TextPainter(
        text: TextSpan(text: label(values[i]), style: TextStyle(fontSize: 10, color: textColor, fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final px = (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      final py = high ? y(values[i]) - tp.height - 1 : y(values[i]) + 1;
      tp.paint(canvas, Offset(px, py.clamp(0.0, size.height - tp.height)));
    }

    var hiI = 0, loI = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[hiI]) hiI = i;
      if (values[i] < values[loI]) loI = i;
    }
    mark(hiI, true);
    if (loI != hiI) mark(loI, false);

    final a = at;
    if (a != null) {
      canvas.drawLine(Offset(x(a), top), Offset(x(a), top + h), Paint()..color = textColor..strokeWidth = 1);
      canvas.drawCircle(Offset(x(a), y(values[a])), 4.5, Paint()..color = color);
      canvas.drawCircle(Offset(x(a), y(values[a])), 2, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.values != values || old.at != at || old.color != color || old.reference != reference;
}

List<int> _times(Object? v) => [for (final x in (v as List? ?? const [])) if (x is num) x.toInt()];

/// A bar for how much of the maximum supply is out.
class _SupplyBar extends StatelessWidget {
  const _SupplyBar({required this.circulating, required this.max});
  final double circulating;
  final double max;

  @override
  Widget build(BuildContext context) {
    final f = (circulating / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Supply in circulation', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
            const Spacer(),
            Text('${(f * 100).toStringAsFixed(1)}% of ${_big(max)}', style: context.text.labelSmall),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: f, minHeight: 5, color: AppColors.accent, backgroundColor: AppColors.surface3),
        ),
      ],
    );
  }
}

/// Community mood on CoinGecko: the share of up votes.
class _SentimentBar extends StatelessWidget {
  const _SentimentBar(this.upPct);
  final double upPct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text('${upPct.toStringAsFixed(0)}% bullish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
          const Spacer(),
          Text('${(100 - upPct).toStringAsFixed(0)}% bearish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(value: upPct / 100, minHeight: 5, color: AppColors.success, backgroundColor: AppColors.danger),
      ),
    ],
  );
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip(this.value, {this.label});
  final Object? value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = _trend(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '${label == null ? '' : '$label '}${_pct(value)}',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.url, {this.size = 32, this.fallback = '?'});
  final Object? url;
  final double size;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
      child: Text(
        fallback.isEmpty ? '?' : fallback.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.42, color: AppColors.text2),
      ),
    );
    final u = url;
    if (u is! String || u.isEmpty) return letter;
    return ClipOval(
      child: NetImage(u, width: size, height: size, fit: BoxFit.cover, errorWidget: letter),
    );
  }
}

/// A card with a small header and rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.children, this.trailing});
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.text2),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title.toUpperCase(), style: context.text.labelSmall)),
              ?trailing,
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    ],
  );
}

/// Stats laid out two (or three, when wide) to a row.
class _StatGrid extends StatelessWidget {
  const _StatGrid(this.stats);
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final per = c.maxWidth > 420 ? 3 : 2;
      final w = (c.maxWidth - Space.m * (per - 1)) / per;
      return Wrap(
        spacing: Space.m,
        runSpacing: Space.m,
        children: [for (final s in stats) SizedBox(width: w, child: s)],
      );
    },
  );
}

class _LinkButtons extends StatelessWidget {
  const _LinkButtons(this.links);
  final List<(String, IconData, String?)> links;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s,
    runSpacing: Space.s,
    children: [
      for (final (label, icon, url) in links)
        if (url != null && url.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: Icon(icon, size: 16),
            label: Text(label),
            onPressed: () => _launch(url),
          ),
    ],
  );
}

/// The standard detail sheet: a scrolling column with padding.
Future<void> _sheet(BuildContext context, List<Widget> children) => showAppSheet<void>(
  context,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: children,
  ),
);

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.leading, required this.title, this.subtitle});
  final Widget leading;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      leading,
      const SizedBox(width: Space.m),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleLarge),
            if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: context.text.bodySmall),
          ],
        ),
      ),
    ],
  );
}

// ---- crypto -----------------------------------------------------------------------

class _CryptoList extends StatelessWidget {
  const _CryptoList({required this.coins, required this.vs});
  final List<Map<String, dynamic>> coins;
  final String vs;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.currency_bitcoin_rounded,
    title: 'Crypto · ${vs.toUpperCase()}',
    trailing: Text('7D', style: context.text.labelSmall),
    children: [
      for (final c in coins.take(15))
        InkWell(
          onTap: () => _showCoin(context, c, vs),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                _Logo(c['image'], size: 30, fallback: '${c['symbol'] ?? ''}'),
                const SizedBox(width: Space.m),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${c['symbol']}${c['rank'] == null ? '' : ' · #${c['rank']}'}${c['market_cap'] == null ? '' : ' · ${_big(c['market_cap'], vs)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(flex: 3, child: Sparkline(values: _series(c['sparkline_7d']), height: 26)),
                const SizedBox(width: Space.m),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(c['price'], vs), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(height: 2),
                    _ChangeChip(c['change_24h']),
                  ],
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: Space.xs),
    ],
  );
}

void _showCoin(BuildContext context, Map<String, dynamic> c, String vs) => _sheet(context, [
  _SheetTitle(
    leading: _Logo(c['image'], size: 44, fallback: '${c['symbol'] ?? ''}'),
    title: '${c['name']}',
    subtitle: '${c['symbol']}${c['rank'] == null ? '' : ' · rank #${c['rank']}'}',
  ),
  const SizedBox(height: Space.l),
  Text(_money(c['price'], vs), style: context.text.headlineMedium),
  const SizedBox(height: Space.xs),
  Wrap(
    spacing: Space.s,
    children: [
      if (c['change_1h'] != null) _ChangeChip(c['change_1h'], label: '1h'),
      _ChangeChip(c['change_24h'], label: '24h'),
      if (c['change_7d'] != null) _ChangeChip(c['change_7d'], label: '7d'),
    ],
  ),
  const SizedBox(height: Space.l),
  PriceChart(values: _series(c['sparkline_7d']), height: 150, currency: vs),
  Text('Last 7 days', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
  const SizedBox(height: Space.l),
  _StatGrid([
    _Stat('Market cap', _big(c['market_cap'], vs)),
    _Stat('Cap 24h', _pct(c['market_cap_change_24h']), color: _trend(c['market_cap_change_24h'])),
    _Stat('Fully diluted', _big(c['fdv'], vs)),
    _Stat('24h volume', _big(c['volume_24h'], vs)),
    _Stat('24h high', _money(c['high_24h'], vs)),
    _Stat('24h low', _money(c['low_24h'], vs)),
    _Stat('All-time high', _money(c['ath'], vs)),
    _Stat('From ATH', _pct(c['ath_change']), color: _trend(c['ath_change'])),
    _Stat('ATH date', '${c['ath_date'] ?? '—'}'.isEmpty ? '—' : '${c['ath_date']}'),
    _Stat('All-time low', _money(c['atl'], vs)),
    _Stat('From ATL', _pct(c['atl_change']), color: _trend(c['atl_change'])),
    _Stat('Circulating', _big(c['circulating_supply'])),
  ]),
  if (_d(c['circulating_supply']) != null && (_d(c['max_supply']) ?? 0) > 0) ...[
    const SizedBox(height: Space.l),
    _SupplyBar(circulating: _d(c['circulating_supply'])!, max: _d(c['max_supply'])!),
  ],
  const SizedBox(height: Space.l),
  _LinkButtons([('CoinGecko', Icons.open_in_new_rounded, 'https://www.coingecko.com/en/coins/${c['id']}')]),
]);

class _CoinHero extends StatelessWidget {
  const _CoinHero({required this.coin});
  final Map<String, dynamic> coin;

  @override
  Widget build(BuildContext context) {
    final vs = '${coin['vs'] ?? 'usd'}';
    final chart = (coin['chart'] as Map?) ?? const {};
    final prices = _series(chart['prices']);
    final days = chart['days'];
    final change = prices.length > 1 && prices.first != 0 ? (prices.last - prices.first) / prices.first * 100 : coin['change_24h'];
    return _Panel(
      icon: Icons.currency_bitcoin_rounded,
      title: '${coin['symbol']} · ${days == 1 ? '24 hours' : '$days days'}',
      children: [
        InkWell(
          onTap: () => _showCoinFull(context, coin),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Logo(coin['image'], size: 36, fallback: '${coin['symbol'] ?? ''}'),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${coin['name']}', style: context.text.titleMedium),
                          if (coin['rank'] != null) Text('Rank #${coin['rank']}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(coin['price'], vs), style: context.text.titleMedium),
                        _ChangeChip(change),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (coin['change_1h'] != null) _ChangeChip(coin['change_1h'], label: '1h'),
                    _ChangeChip(coin['change_24h'], label: '24h'),
                    if (coin['change_7d'] != null) _ChangeChip(coin['change_7d'], label: '7d'),
                    if (coin['change_30d'] != null) _ChangeChip(coin['change_30d'], label: '30d'),
                    if (coin['change_1y'] != null) _ChangeChip(coin['change_1y'], label: '1y'),
                  ],
                ),
                const SizedBox(height: Space.s),
                PriceChart(values: prices, times: _times(chart['times']), height: 140, currency: vs),
                const SizedBox(height: Space.m),
                _StatGrid([
                  _Stat('Market cap', _big(coin['market_cap'], vs)),
                  _Stat('24h volume', _big(coin['volume_24h'], vs)),
                  _Stat('24h range', '${_money(coin['low_24h'], vs)} – ${_money(coin['high_24h'], vs)}'),
                  _Stat('Fully diluted', _big(coin['fdv'], vs)),
                  _Stat('All-time high', _money(coin['ath'], vs)),
                  _Stat('From ATH', _pct(coin['ath_change']), color: _trend(coin['ath_change'])),
                ]),
                if (_d(coin['circulating_supply']) != null && (_d(coin['max_supply']) ?? 0) > 0) ...[
                  const SizedBox(height: Space.m),
                  _SupplyBar(circulating: _d(coin['circulating_supply'])!, max: _d(coin['max_supply'])!),
                ],
                if (_d(coin['sentiment_up_pct']) != null) ...[
                  const SizedBox(height: Space.m),
                  _SentimentBar(_d(coin['sentiment_up_pct'])!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void _showCoinFull(BuildContext context, Map<String, dynamic> coin) {
  final vs = '${coin['vs'] ?? 'usd'}';
  final chart = (coin['chart'] as Map?) ?? const {};
  _sheet(context, [
    _SheetTitle(
      leading: _Logo(coin['image'], size: 44, fallback: '${coin['symbol'] ?? ''}'),
      title: '${coin['name']}',
      subtitle: '${coin['symbol']}${coin['rank'] == null ? '' : ' · rank #${coin['rank']}'}',
    ),
    const SizedBox(height: Space.l),
    Text(_money(coin['price'], vs), style: context.text.headlineMedium),
    const SizedBox(height: Space.xs),
    Wrap(
      spacing: Space.s,
      runSpacing: Space.xs,
      children: [
        _ChangeChip(coin['change_24h'], label: '24h'),
        if (coin['change_7d'] != null) _ChangeChip(coin['change_7d'], label: '7d'),
        if (coin['change_14d'] != null) _ChangeChip(coin['change_14d'], label: '14d'),
        if (coin['change_30d'] != null) _ChangeChip(coin['change_30d'], label: '30d'),
        if (coin['change_60d'] != null) _ChangeChip(coin['change_60d'], label: '60d'),
        if (coin['change_200d'] != null) _ChangeChip(coin['change_200d'], label: '200d'),
        if (coin['change_1y'] != null) _ChangeChip(coin['change_1y'], label: '1y'),
      ],
    ),
    const SizedBox(height: Space.l),
    PriceChart(values: _series(chart['prices']), times: _times(chart['times']), height: 190, currency: vs),
    Text('Last ${chart['days'] == 1 ? '24 hours' : '${chart['days']} days'}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
    const SizedBox(height: Space.l),
    _StatGrid([
      _Stat('Market cap', _big(coin['market_cap'], vs)),
      _Stat('24h volume', _big(coin['volume_24h'], vs)),
      _Stat('24h high', _money(coin['high_24h'], vs)),
      _Stat('24h low', _money(coin['low_24h'], vs)),
      _Stat('Fully diluted', _big(coin['fdv'], vs)),
      _Stat('Cap 24h', _pct(coin['market_cap_change_24h']), color: _trend(coin['market_cap_change_24h'])),
      _Stat('All-time high', _money(coin['ath'], vs)),
      _Stat('ATH date', '${coin['ath_date'] ?? ''}'.isEmpty ? '—' : '${coin['ath_date']}'),
      _Stat('All-time low', _money(coin['atl'], vs)),
      _Stat('ATL date', '${coin['atl_date'] ?? ''}'.isEmpty ? '—' : '${coin['atl_date']}'),
      _Stat('Circulating', _big(coin['circulating_supply'])),
      _Stat('Total supply', _big(coin['total_supply'])),
      _Stat('Max supply', coin['max_supply'] == null ? 'Unlimited' : _big(coin['max_supply'])),
      if (coin['genesis_date'] != null) _Stat('Launched', '${coin['genesis_date']}'),
      if (coin['hashing_algorithm'] != null) _Stat('Algorithm', '${coin['hashing_algorithm']}'),
      if (coin['watchlist_users'] != null) _Stat('Watchlists', _big(coin['watchlist_users'])),
    ]),
    if (_d(coin['circulating_supply']) != null && (_d(coin['max_supply']) ?? 0) > 0) ...[
      const SizedBox(height: Space.l),
      _SupplyBar(circulating: _d(coin['circulating_supply'])!, max: _d(coin['max_supply'])!),
    ],
    if (_d(coin['sentiment_up_pct']) != null) ...[
      const SizedBox(height: Space.l),
      _SentimentBar(_d(coin['sentiment_up_pct'])!),
    ],
    if ((coin['categories'] as List?)?.isNotEmpty == true) ...[
      const SizedBox(height: Space.l),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in coin['categories'] as List)
            Chip(label: Text('$c', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
        ],
      ),
    ],
    if ('${coin['description'] ?? ''}'.isNotEmpty) ...[
      const SizedBox(height: Space.l),
      Text('${coin['description']}', style: context.text.bodyMedium?.copyWith(height: 1.45)),
    ],
    const SizedBox(height: Space.l),
    _LinkButtons([
      ('CoinGecko', Icons.open_in_new_rounded, coin['url'] as String?),
      ('Website', Icons.language_rounded, coin['homepage'] as String?),
      ('Explorer', Icons.travel_explore_rounded, coin['explorer'] as String?),
      ('GitHub', Icons.code_rounded, coin['github'] as String?),
      ('Reddit', Icons.forum_outlined, coin['reddit'] as String?),
      ('X', Icons.alternate_email_rounded, coin['twitter'] as String?),
    ]),
  ]);
}

class _TrendingStrip extends StatelessWidget {
  const _TrendingStrip({required this.coins});
  final List<Map<String, dynamic>> coins;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.local_fire_department_outlined,
    title: 'Trending on CoinGecko',
    children: [
      SizedBox(
        height: 116,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
          scrollDirection: Axis.horizontal,
          itemCount: coins.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.s),
          itemBuilder: (context, i) {
            final c = coins[i];
            return InkWell(
              borderRadius: BorderRadius.circular(Radii.m),
              onTap: () => _showCoin(context, c, 'usd'),
              child: Container(
                width: 112,
                padding: const EdgeInsets.all(Space.s),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Logo(c['image'], size: 22, fallback: '${c['symbol'] ?? ''}'),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('${c['symbol']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    const Spacer(),
                    Text(_money(c['price'], 'usd'), maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    _ChangeChip(c['change_24h']),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

// ---- stocks -----------------------------------------------------------------------

class _StockRow extends StatelessWidget {
  const _StockRow({required this.quote});
  final Map<String, dynamic> quote;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _showStock(context, quote),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${quote['symbol']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${quote['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ],
            ),
          ),
          Expanded(flex: 3, child: Sparkline(values: _series(quote['chart']), height: 26)),
          const SizedBox(width: Space.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(quote['price'], quote['currency'] as String?), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              _ChangeChip(quote['change_pct']),
            ],
          ),
        ],
      ),
    ),
  );
}

class _StockHero extends StatelessWidget {
  const _StockHero({required this.quote});
  final Map<String, dynamic> quote;

  @override
  Widget build(BuildContext context) {
    final cur = quote['currency'] as String?;
    return _Panel(
      icon: Icons.candlestick_chart_outlined,
      title: '${quote['exchange'] ?? 'Market'} · ${_rangeLabel('${quote['range']}')}',
      children: [
        InkWell(
          onTap: () => _showStock(context, quote),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${quote['symbol']}', style: context.text.titleMedium),
                          Text('${quote['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(quote['price'], cur), style: context.text.titleMedium),
                        Text(
                          '${_d(quote['change']) == null ? '' : '${_d(quote['change'])! >= 0 ? '+' : ''}${_money(quote['change'], cur)} '}${_pct(quote['change_pct'])}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _trend(quote['change_pct'])),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                PriceChart(
                  values: _series(quote['chart']),
                  times: _times(quote['chart_times']),
                  height: 140,
                  currency: cur,
                  reference: quote['range'] == '1d' ? _d(quote['previous_close']) : null,
                  referenceLabel: 'previous close',
                ),
                const SizedBox(height: Space.m),
                _StatGrid([
                  _Stat('Day range', '${_money(quote['day_low'], cur)} – ${_money(quote['day_high'], cur)}'),
                  _Stat('52-week range', '${_money(quote['year_low'], cur)} – ${_money(quote['year_high'], cur)}'),
                  _Stat('Previous close', _money(quote['previous_close'], cur)),
                  _Stat('Volume', _big(quote['volume'])),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void _showStock(BuildContext context, Map<String, dynamic> q) {
  final cur = q['currency'] as String?;
  _sheet(context, [
    _SheetTitle(
      leading: _Logo(null, size: 44, fallback: '${q['symbol'] ?? ''}'),
      title: '${q['symbol']}',
      subtitle: [q['name'], q['exchange'], q['type']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
    ),
    const SizedBox(height: Space.l),
    Text(_money(q['price'], cur), style: context.text.headlineMedium),
    Row(
      children: [
        _ChangeChip(q['change_pct'], label: _rangeLabel('${q['range']}')),
        const SizedBox(width: Space.s),
        if (q['market_time'] != null) Text('as of ${'${q['market_time']}'.replaceFirst('T', ' ')}', style: context.text.bodySmall),
      ],
    ),
    const SizedBox(height: Space.l),
    PriceChart(
      values: _series(q['chart']),
      times: _times(q['chart_times']),
      height: 190,
      currency: cur,
      reference: q['range'] == '1d' ? _d(q['previous_close']) : null,
      referenceLabel: 'previous close',
    ),
    const SizedBox(height: Space.l),
    _StatGrid([
      _Stat('Previous close', _money(q['previous_close'], cur)),
      _Stat('Change', _money(q['change'], cur), color: _trend(q['change'])),
      _Stat('Day low', _money(q['day_low'], cur)),
      _Stat('Day high', _money(q['day_high'], cur)),
      _Stat('52-week low', _money(q['year_low'], cur)),
      _Stat('52-week high', _money(q['year_high'], cur)),
      _Stat('Volume', _big(q['volume'])),
      _Stat('Currency', '${q['currency'] ?? '—'}'),
    ]),
    const SizedBox(height: Space.l),
    Text('Prices may be delayed. Not investment advice.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
    const SizedBox(height: Space.m),
    _LinkButtons([('Yahoo Finance', Icons.open_in_new_rounded, q['url'] as String?)]),
  ]);
}

class _TickerRow extends StatelessWidget {
  const _TickerRow({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: _Logo(null, size: 30, fallback: '${result['symbol'] ?? ''}'),
    title: Text('${result['symbol']}', style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      [result['name'], result['exchange'], result['type']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.text3),
    onTap: () => _launch('https://finance.yahoo.com/quote/${Uri.encodeComponent('${result['symbol']}')}'),
  );
}

// ---- currency ---------------------------------------------------------------------

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final from = '${data['from']}';
    final rows = [for (final c in (data['conversions'] as List).whereType<Map>()) c];
    final history = data['history'] as Map?;
    final rates = _series(history?['rates']);
    return _Panel(
      icon: Icons.currency_exchange_rounded,
      title: 'Exchange · ${data['date'] ?? ''}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_money(data['amount'], from)} =', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
              const SizedBox(height: Space.xs),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text(_money(r['value'], '${r['currency']}'), style: context.text.titleLarge)),
                      Text('1 $from = ${_d(r['rate'])?.toStringAsFixed(4) ?? '—'} ${r['currency']}', style: context.text.bodySmall),
                    ],
                  ),
                ),
              if (rates.length > 1) ...[
                const SizedBox(height: Space.m),
                Sparkline(values: rates, height: 70, fill: true),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('$from → ${history?['to']}', style: context.text.bodySmall),
                    const Spacer(),
                    _ChangeChip((rates.last - rates.first) / rates.first * 100),
                    const SizedBox(width: Space.s),
                    Text('${history?['from_date']} – ${history?['to_date']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ],
              const SizedBox(height: Space.s),
              Text('ECB reference rates', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- weather ----------------------------------------------------------------------

IconData _skyIcon(Object? code, {bool day = true}) {
  final c = code is num ? code.toInt() : -1;
  return switch (c) {
    0 || 1 => day ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
    2 => day ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
    3 => Icons.cloud_outlined,
    45 || 48 => Icons.foggy,
    >= 51 && <= 67 || >= 80 && <= 82 => Icons.water_drop_outlined,
    >= 71 && <= 77 || 85 || 86 => Icons.ac_unit_rounded,
    >= 95 => Icons.thunderstorm_outlined,
    _ => Icons.thermostat_outlined,
  };
}

String _deg(Object? v) => _d(v) == null ? '—' : '${_d(v)!.round()}°';

String _weekday(Object? date, {bool short = true}) {
  final d = DateTime.tryParse('$date');
  if (d == null) return '$date';
  final today = DateTime.now();
  if (d.year == today.year && d.month == today.month && d.day == today.day) return 'Today';
  return DateFormat(short ? 'EEE' : 'EEEE d MMM').format(d);
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cur = Map<String, dynamic>.from(data['current'] as Map);
    final daily = [for (final d in (data['daily'] as List? ?? const []).whereType<Map>()) d];
    final hourly = [for (final h in (data['hourly'] as List? ?? const []).whereType<Map>()) h];
    final place = [data['place'], data['country']].where((x) => x != null).join(', ');
    final today = daily.firstOrNull;
    return _Panel(
      icon: Icons.cloud_outlined,
      title: place.isEmpty ? 'Weather' : place,
      children: [
        InkWell(
          onTap: () => _showWeather(context, data),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_skyIcon(cur['code'], day: cur['is_day'] != false), size: 44, color: AppColors.text),
                    const SizedBox(width: Space.m),
                    Text(_deg(cur['temperature']), style: context.text.displaySmall),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${cur['conditions']}', style: context.text.titleSmall),
                          Text(
                            'Feels ${_deg(cur['feels_like'])}${today == null ? '' : ' · H ${_deg(today['high'])} L ${_deg(today['low'])}'}',
                            style: context.text.bodySmall,
                          ),
                          Text(
                            'Humidity ${_d(cur['humidity'])?.round() ?? '—'}% · Wind ${_d(cur['wind'])?.round() ?? '—'} ${data['wind_unit'] ?? ''}',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hourly.isNotEmpty) ...[
                  const SizedBox(height: Space.m),
                  SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: hourly.length,
                      separatorBuilder: (_, _) => const SizedBox(width: Space.m),
                      itemBuilder: (context, i) {
                        final h = hourly[i];
                        return Column(
                          children: [
                            Text(i == 0 ? 'Now' : '${h['time']}', style: context.text.bodySmall),
                            const SizedBox(height: 4),
                            Icon(_skyIcon(h['code']), size: 18, color: AppColors.text2),
                            const SizedBox(height: 4),
                            Text(_deg(h['temperature']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            if ((_d(h['rain_chance']) ?? 0) >= 20)
                              Text('${_d(h['rain_chance'])!.round()}%', style: TextStyle(fontSize: 10, color: AppColors.accent)),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (daily.length > 1) ...[
                  const Divider(height: Space.l),
                  _DailyRows(days: daily.take(7).toList()),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Days with a bar placing each day's low–high within the week's range.
class _DailyRows extends StatelessWidget {
  const _DailyRows({required this.days, this.long = false});
  final List<Map> days;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final lows = [for (final d in days) _d(d['low']) ?? 0], highs = [for (final d in days) _d(d['high']) ?? 0];
    final lo = lows.reduce(math.min), hi = highs.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    return Column(
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: long ? 110 : 52, child: Text(_weekday(d['date'], short: !long), style: context.text.bodyMedium)),
                Icon(_skyIcon(d['code']), size: 18, color: AppColors.text2),
                SizedBox(
                  width: 40,
                  child: Text(
                    (_d(d['rain_chance']) ?? 0) >= 20 ? ' ${_d(d['rain_chance'])!.round()}%' : '',
                    style: TextStyle(fontSize: 11, color: AppColors.accent),
                  ),
                ),
                SizedBox(width: 34, child: Text(_deg(d['low']), textAlign: TextAlign.right, style: context.text.bodySmall)),
                const SizedBox(width: Space.s),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final l = ((_d(d['low']) ?? lo) - lo) / span * c.maxWidth;
                      final r = ((_d(d['high']) ?? hi) - lo) / span * c.maxWidth;
                      return Container(
                        height: 5,
                        decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(9)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: EdgeInsets.only(left: l),
                            width: math.max(4, r - l),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF5AA9E6), Color(0xFFF2A541)]),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: Space.s),
                SizedBox(width: 34, child: Text(_deg(d['high']), style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
      ],
    );
  }
}

void _showWeather(BuildContext context, Map<String, dynamic> data) {
  final cur = Map<String, dynamic>.from(data['current'] as Map);
  final daily = [for (final d in (data['daily'] as List? ?? const []).whereType<Map>()) d];
  final hourly = [for (final h in (data['hourly'] as List? ?? const []).whereType<Map>()) h];
  _sheet(context, [
    _SheetTitle(
      leading: Icon(_skyIcon(cur['code'], day: cur['is_day'] != false), size: 40),
      title: [data['place'], data['region'], data['country']].where((x) => x != null).join(', ').ifBlank('Weather'),
      subtitle: '${data['timezone'] ?? ''} · ${'${cur['time'] ?? ''}'.replaceFirst('T', ' ')}',
    ),
    const SizedBox(height: Space.l),
    _StatGrid([
      _Stat('Now', '${_deg(cur['temperature'])} ${cur['conditions']}'),
      _Stat('Feels like', _deg(cur['feels_like'])),
      _Stat('Humidity', '${_d(cur['humidity'])?.round() ?? '—'}%'),
      _Stat('Wind', '${_d(cur['wind'])?.round() ?? '—'} ${data['wind_unit'] ?? ''}'),
      _Stat('Precipitation', '${_d(cur['precipitation']) ?? 0} mm'),
      if (daily.isNotEmpty) _Stat('Sunrise · sunset', '${daily.first['sunrise']} · ${daily.first['sunset']}'),
    ]),
    if (hourly.length > 1) ...[
      const SizedBox(height: Space.l),
      Text('NEXT 24 HOURS', style: context.text.labelSmall),
      const SizedBox(height: Space.s),
      Sparkline(values: [for (final h in hourly) _d(h['temperature']) ?? 0], height: 80, fill: true, color: AppColors.accent),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${hourly.first['time']}', style: context.text.bodySmall),
          Text('${hourly.last['time']}', style: context.text.bodySmall),
        ],
      ),
    ],
    const SizedBox(height: Space.l),
    Text('${daily.length}-DAY FORECAST', style: context.text.labelSmall),
    const SizedBox(height: Space.s),
    if (daily.isNotEmpty) _DailyRows(days: daily, long: true),
    const SizedBox(height: Space.m),
    Text('Open-Meteo', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
  ]);
}

extension on String {
  String ifBlank(String other) => trim().isEmpty ? other : this;
}

// ---- flights ----------------------------------------------------------------------

class _FlightCard extends StatelessWidget {
  const _FlightCard({required this.flight});
  final Map<String, dynamic> flight;

  @override
  Widget build(BuildContext context) {
    final o = (flight['origin'] as Map?) ?? const {};
    final d = (flight['destination'] as Map?) ?? const {};
    final live = flight['live'] as Map?;
    final progress = _d(flight['progress_pct']);
    final airborne = flight['airborne'] == true;
    return _Panel(
      icon: Icons.flight_rounded,
      title: [flight['flight'], flight['airline']].where((x) => x != null).join(' · '),
      trailing: _LiveBadge(airborne: airborne, known: live != null),
      children: [
        InkWell(
          onTap: () => _showFlight(context, flight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
            child: Column(
              children: [
                Row(
                  children: [
                    _AirportEnd(airport: o, alignEnd: false),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final p = (progress ?? (airborne ? 50 : 0)) / 100;
                            return SizedBox(
                              height: 28,
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  Container(height: 2, color: AppColors.line),
                                  Container(height: 2, width: c.maxWidth * p, color: AppColors.accent),
                                  Positioned(
                                    left: (c.maxWidth - 22) * p,
                                    child: Transform.rotate(
                                      angle: math.pi / 2,
                                      child: Icon(Icons.flight_rounded, size: 22, color: airborne ? AppColors.accent : AppColors.text3),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    _AirportEnd(airport: d, alignEnd: true),
                  ],
                ),
                if (live != null) ...[
                  const SizedBox(height: Space.m),
                  _StatGrid([
                    _Stat('Altitude', live['on_ground'] == true ? 'On ground' : '${NumberFormat.decimalPattern().format(live['altitude_ft'] ?? 0)} ft'),
                    _Stat('Speed', live['speed_kt'] == null ? '—' : '${live['speed_kt']} kt'),
                    if (live['km_to_go'] != null) _Stat('To go', '${NumberFormat.decimalPattern().format(live['km_to_go'])} km'),
                    if (live['aircraft'] != null) _Stat('Aircraft', '${live['aircraft']}'),
                  ]),
                ] else ...[
                  const SizedBox(height: Space.s),
                  Text('${flight['note'] ?? ''}', style: context.text.bodySmall),
                ],
                const SizedBox(height: Space.m),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LinkButtons([('Live map', Icons.map_outlined, flight['map_url'] as String?)]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.airborne, required this.known});
  final bool airborne;
  final bool known;

  @override
  Widget build(BuildContext context) {
    final (label, color) = airborne ? ('IN THE AIR', AppColors.success) : (known ? ('ON GROUND', AppColors.warning) : ('NOT TRACKED', AppColors.text3));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
    );
  }
}

class _AirportEnd extends StatelessWidget {
  const _AirportEnd({required this.airport, required this.alignEnd});
  final Map airport;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 110),
    child: Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text('${airport['iata'] ?? airport['icao'] ?? '—'}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          '${airport['city'] ?? airport['name'] ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: context.text.bodySmall,
        ),
      ],
    ),
  );
}

void _showFlight(BuildContext context, Map<String, dynamic> f) {
  final o = (f['origin'] as Map?) ?? const {};
  final d = (f['destination'] as Map?) ?? const {};
  final live = f['live'] as Map?;
  String airport(Map a) => [a['name'], a['city'], a['country']].where((x) => x != null).join(', ');
  _sheet(context, [
    _SheetTitle(
      leading: const Icon(Icons.flight_takeoff_rounded, size: 36),
      title: '${f['flight']}',
      subtitle: [f['airline'], f['airline_country'], 'callsign ${f['callsign']}'].where((x) => x != null).join(' · '),
    ),
    const SizedBox(height: Space.l),
    if (o.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flight_takeoff_rounded), title: Text('${o['iata'] ?? o['icao']}'), subtitle: Text(airport(o))),
    if (d.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flight_land_rounded), title: Text('${d['iata'] ?? d['icao']}'), subtitle: Text(airport(d))),
    if (f['progress_pct'] != null) ...[
      const SizedBox(height: Space.s),
      LinearProgressIndicator(value: (_d(f['progress_pct']) ?? 0) / 100, minHeight: 6, borderRadius: BorderRadius.circular(9)),
      const SizedBox(height: 4),
      Text('${_d(f['progress_pct'])!.round()}% of the way', style: context.text.bodySmall),
    ],
    if (live != null) ...[
      const SizedBox(height: Space.l),
      _StatGrid([
        _Stat('Altitude', live['on_ground'] == true ? 'On ground' : '${live['altitude_ft'] ?? '—'} ft'),
        _Stat('Ground speed', '${live['speed_kt'] ?? '—'} kt'),
        _Stat('Heading', live['heading'] == null ? '—' : '${live['heading']}°'),
        _Stat('Climb', live['vertical_rate_fpm'] == null ? '—' : '${live['vertical_rate_fpm']} ft/min'),
        _Stat('Aircraft', '${live['aircraft'] ?? '—'}'),
        _Stat('Registration', '${live['registration'] ?? '—'}'),
        _Stat('Squawk', '${live['squawk'] ?? '—'}'),
        _Stat('Position', live['latitude'] == null ? '—' : '${(_d(live['latitude'])!).toStringAsFixed(2)}, ${(_d(live['longitude'])!).toStringAsFixed(2)}'),
        _Stat('Last seen', live['seen_seconds_ago'] == null ? '—' : '${live['seen_seconds_ago']} s ago'),
      ]),
    ],
    const SizedBox(height: Space.l),
    Text('${f['note'] ?? ''}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
    const SizedBox(height: Space.m),
    _LinkButtons([
      ('Live map', Icons.map_outlined, f['map_url'] as String?),
      ('Flightradar24', Icons.open_in_new_rounded, 'https://www.flightradar24.com/data/flights/${'${f['flight']}'.toLowerCase()}'),
    ]),
  ]);
}

class _FlightSearchCard extends StatelessWidget {
  const _FlightSearchCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final links = [for (final l in (data['links'] as List).whereType<Map>()) l];
    String date(Object? s) {
      final d = DateTime.tryParse('$s');
      return d == null ? '$s' : DateFormat('EEE d MMM').format(d);
    }

    return _Panel(
      icon: Icons.travel_explore_rounded,
      title: 'Flight search',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${data['from']}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: Icon(data['return_date'] == null ? Icons.arrow_forward_rounded : Icons.swap_horiz_rounded, color: AppColors.text2),
                  ),
                  Text('${data['to']}', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              Text(
                [
                  date(data['date']),
                  if (data['return_date'] != null) 'back ${date(data['return_date'])}',
                  '${data['adults']} adult${data['adults'] == 1 ? '' : 's'}',
                  '${data['cabin']}',
                ].join(' · '),
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.m),
              for (final l in links)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text('See fares on ${l['site']}'),
                      onPressed: () => _launch(l['url'] as String?),
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

// ---- holidays ---------------------------------------------------------------------

/// The holidays card follows the app's accent colour.
Color get _festive => AppColors.accent;

/// "ET" → 🇪🇹.
String _flag(String code) => code.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(code)
    ? String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65))
    : '';

int? _daysUntil(DateTime? d) {
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String _until(int? n) => switch (n) {
  null => '',
  0 => 'Today',
  1 => 'Tomorrow',
  < 0 => n == -1 ? 'Yesterday' : '${-n} days ago',
  < 14 => 'In $n days',
  < 60 => 'In ${(n / 7).round()} weeks',
  _ => 'In ${(n / 30.4).round()} months',
};

/// A tear-off calendar leaf: the month on a coloured band, the day large.
class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.date, this.size = 48, this.dim = false});
  final DateTime? date;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final d = date;
    final c = dim ? AppColors.text3 : _festive;
    return Container(
      width: size,
      height: size * 1.08,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: dim ? AppColors.line : c.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: c.withValues(alpha: dim ? 0.25 : 0.9),
            padding: EdgeInsets.symmetric(vertical: size * 0.05),
            alignment: Alignment.center,
            child: Text(
              d == null ? '' : DateFormat('MMM').format(d).toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.19,
                fontWeight: FontWeight.w800,
                // Readable on any accent, the default white one included.
                color: dim ? AppColors.text2 : (c.computeLuminance() > 0.5 ? Colors.black : Colors.white),
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(d == null ? '?' : '${d.day}', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: dim ? AppColors.text2 : AppColors.text, height: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolidaysCard extends StatelessWidget {
  const _HolidaysCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final all = [for (final h in (data['holidays'] as List).whereType<Map>()) h];
    final upcoming = all.where((h) => h['upcoming'] == true).toList();
    final next = upcoming.firstOrNull;
    final rest = (upcoming.isEmpty ? all.reversed.toList() : upcoming.skip(1).toList()).take(4).toList();
    final nd = DateTime.tryParse('${next?['date'] ?? ''}');
    final cc = '${data['country'] ?? ''}';
    final year = (data['year'] as num?)?.toInt() ?? DateTime.now().year;
    final perMonth = List.filled(12, 0);
    for (final h in all) {
      final d = DateTime.tryParse('${h['date']}');
      if (d != null && d.year == year) perMonth[d.month - 1]++;
    }
    final now = DateTime.now();
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
            child: Row(
              children: [
                Text(_flag(cc), style: const TextStyle(fontSize: 20)),
                if (_flag(cc).isNotEmpty) const SizedBox(width: Space.s),
                Expanded(child: Text('Public holidays · $year', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                Text('${all.length} days', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              ],
            ),
          ),
          if (next != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: Space.m),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_festive.withValues(alpha: 0.2), _festive.withValues(alpha: 0.04)]),
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: _festive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  _CalendarTile(date: nd, size: 60),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NEXT HOLIDAY', style: context.text.labelSmall?.copyWith(color: _festive, letterSpacing: 1, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${next['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
                        if (next['local_name'] != null && next['local_name'] != next['name'])
                          Text('${next['local_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text2)),
                        const SizedBox(height: 4),
                        Text(
                          '${nd == null ? '' : DateFormat('EEEE').format(nd)} · ${_until(_daysUntil(nd))}',
                          style: context.text.labelMedium?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // The year at a glance: a dot for each holiday, this month marked.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
            child: Row(
              children: [
                for (var m = 0; m < 12; m++)
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 22,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 2,
                            runSpacing: 2,
                            children: [
                              for (var i = 0; i < perMonth[m].clamp(0, 6); i++)
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (year < now.year || (year == now.year && m < now.month - 1)) ? AppColors.text3.withValues(alpha: 0.5) : _festive,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          DateFormat('MMM').format(DateTime(year, m + 1)).substring(0, 1),
                          style: context.text.labelSmall?.copyWith(
                            color: year == now.year && m == now.month - 1 ? _festive : AppColors.text3,
                            fontWeight: year == now.year && m == now.month - 1 ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (final h in rest) _HolidayRow(h: h),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.xs),
            child: TextButton(
              onPressed: () => _sheet(context, [
                Row(
                  children: [
                    Text(_flag(cc), style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text('Public holidays · $year', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: Space.s),
                for (var m = 1; m <= 12; m++)
                  if (all.any((h) => DateTime.tryParse('${h['date']}')?.month == m)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, 0, Space.xs),
                      child: Text(DateFormat('MMMM').format(DateTime(year, m)).toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 1, fontWeight: FontWeight.w700)),
                    ),
                    for (final h in all.where((h) => DateTime.tryParse('${h['date']}')?.month == m)) _HolidayRow(h: h, padding: EdgeInsets.zero),
                  ],
                const SizedBox(height: Space.m),
                Text('Source: Nager.Date', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
              ]),
              child: Text('All ${all.length} holidays'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({required this.h, this.padding = const EdgeInsets.symmetric(horizontal: Space.m)});
  final Map h;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse('${h['date']}');
    final past = h['upcoming'] != true;
    final n = _daysUntil(d);
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Padding(
        padding: padding.add(const EdgeInsets.symmetric(vertical: Space.s)),
        child: Row(
          children: [
            _CalendarTile(date: d, size: 40, dim: past),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${h['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      if (d != null) DateFormat('EEEE').format(d),
                      if (h['local_name'] != null && h['local_name'] != h['name']) '${h['local_name']}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!past && n != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _festive.withValues(alpha: n <= 7 ? 0.18 : 0.08), borderRadius: BorderRadius.circular(20)),
                    child: Text(_until(n), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: n <= 7 ? _festive : AppColors.text2)),
                  ),
                if (h['nationwide'] != true)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      (h['regions'] as List?)?.isNotEmpty == true ? 'Regional · ${(h['regions'] as List).length}' : 'Regional',
                      style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
