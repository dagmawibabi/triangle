import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';
import 'tile_map.dart';

/// Cards for metal and fuel prices, earthquakes, disasters and air
/// quality. Null for other tools.
Widget? worldResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'metal_prices' when maps(j['metals']).isNotEmpty => _MetalsCard(m: j),
  'fuel_prices' when maps(j['prices']).isNotEmpty => _FuelCard(f: j),
  'earthquakes' when j['earthquakes'] != null => _QuakesCard(q: j),
  'disasters' when j['events'] != null => _DisastersCard(d: j),
  'air_quality' when j['aqi'] != null => _AirCard(a: j),
  _ => null,
};

String _money(num? v, String currency, {int digits = 2}) {
  if (v == null) return '—';
  try {
    return NumberFormat.simpleCurrency(name: currency, decimalDigits: v >= 1000 ? 0 : digits).format(v);
  } catch (_) {
    return '${v.toStringAsFixed(digits)} $currency';
  }
}

// ---- metals -----------------------------------------------------------------------

const _gold = Color(0xFFD4A537);
const _metalColors = {'gold': _gold, 'silver': Color(0xFFB8BEC6), 'platinum': Color(0xFF9DB4C0), 'palladium': Color(0xFFC9B79C), 'copper': Color(0xFFB87333)};

class _MetalsCard extends StatelessWidget {
  const _MetalsCard({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final cur = '${m['currency']}';
    final metals = maps(m['metals']);
    final gold = metals.where((x) => x['metal'] == 'gold').firstOrNull;
    final karats = mapOf(m['gold_per_gram']);
    return InfoFrame(
      onTap: () => _showMetals(context, m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_gold.withValues(alpha: 0.28), _gold.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(
              children: [
                const Icon(Icons.diamond_outlined, color: _gold, size: 30),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GOLD · per ${m['unit_label']}', style: context.text.labelSmall),
                      Text(_money(numOf(gold?['price']), cur), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                    ],
                  ),
                ),
                if (karats['24k'] != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('24k / g', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                      Text(_money(numOf(karats['24k']), cur), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: infoGrid(columns: 3, [
              for (final x in metals.where((x) => x['metal'] != 'gold').take(3))
                InfoStat('${x['name']}', _money(numOf(x['price']), cur), valueColor: null),
            ]),
          ),
        ],
      ),
    );
  }
}

void _showMetals(BuildContext context, Map<String, dynamic> m) {
  final cur = '${m['currency']}';
  final karats = mapOf(m['gold_per_gram']);
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('Metal prices', subtitle: 'In $cur per ${m['unit_label']} · ${'${m['updated'] ?? ''}'.replaceFirst('T', ' ').split('.').first}'),
      const SectionLabel('Spot prices'),
      for (final x in maps(m['metals']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _metalColors[x['metal']] ?? AppColors.text3, shape: BoxShape.circle)),
              const SizedBox(width: Space.m),
              Expanded(child: Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(_money(numOf(x['price']), cur), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
            ],
          ),
        ),
      if (karats.isNotEmpty) ...[
        const SectionLabel('Gold per gram by purity'),
        for (final e in karats.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 48, child: Text(e.key.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, color: _gold))),
                Expanded(
                  child: Text(
                    '${((int.tryParse(e.key.replaceAll('k', '')) ?? 24) / 24 * 100).toStringAsFixed(1)}% gold',
                    style: TextStyle(color: AppColors.text3, fontSize: 12.5),
                  ),
                ),
                Text(_money(numOf(e.value), cur), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text('Raw metal value. Jewellery and coins sell above this (making charges, dealer margin, taxes).', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
        ),
      ],
      Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('Source: metals.dev. Not investment advice.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
    ],
  );
}

// ---- fuel -------------------------------------------------------------------------

class _FuelCard extends StatelessWidget {
  const _FuelCard({required this.f});
  final Map<String, dynamic> f;

  @override
  Widget build(BuildContext context) {
    final prices = maps(f['prices']);
    return InfoFrame(
      onTap: () => _showFuel(context, f),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.local_gas_station_outlined, 'Fuel prices · ${f['country']}', trailing: f['updated'] == null ? null : Text('${f['updated']}', style: TextStyle(fontSize: 11, color: AppColors.text3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Row(
              children: [
                for (final (i, p) in prices.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p['fuel']}'.toUpperCase(), style: context.text.labelSmall),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(_money(numOf(p['price_local']), '${p['local_currency']}'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                          ),
                          Text('per ${p['unit']} · ${_money(numOf(p['price_usd']), 'USD')}', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showFuel(BuildContext context, Map<String, dynamic> f) => showInfoSheet(
  context,
  (context) => [
    SheetTitle('Fuel in ${f['country']}', subtitle: f['updated'] == null ? null : 'Prices of ${f['updated']}'),
    for (final p in maps(f['prices'])) ...[
      SectionLabel('${p['fuel']} · per ${p['unit']}'),
      KeyValueRow('${p['local_currency']}', _money(numOf(p['price_local']), '${p['local_currency']}', digits: 3)),
      KeyValueRow('US dollars', _money(numOf(p['price_usd']), 'USD', digits: 3)),
      KeyValueRow('Euros', _money(numOf(p['price_eur']), 'EUR', digits: 3)),
      if (p['unit'] == 'litre' && numOf(p['price_usd']) != null) KeyValueRow('Per US gallon', _money(numOf(p['price_usd'])! * 3.78541, 'USD')),
      if (numOf(p['world_average_local']) != null && numOf(p['price_local']) != null) ...[
        KeyValueRow('World average', _money(numOf(p['world_average_local']), '${p['local_currency']}')),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: () {
            final pct = ((numOf(p['price_local'])! / numOf(p['world_average_local'])! - 1) * 100).round();
            return Text(
              pct == 0 ? 'About the world average' : '${pct.abs()}% ${pct > 0 ? 'above' : 'below'} the world average',
              style: TextStyle(fontWeight: FontWeight.w600, color: pct > 0 ? AppColors.warning : AppColors.success),
            );
          }(),
        ),
      ],
      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => openLink('${p['url']}'), child: const Text('History and chart'))),
    ],
    Text('Source: GlobalPetrolPrices.com (weekly, or monthly where prices are regulated).', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
  ],
);

// ---- earthquakes ------------------------------------------------------------------

Color magColor(num? m) {
  final v = m ?? 0;
  if (v >= 7) return const Color(0xFFB3261E);
  if (v >= 6) return const Color(0xFFE5484D);
  if (v >= 5) return const Color(0xFFF2994A);
  if (v >= 4) return const Color(0xFFE2B33C);
  return const Color(0xFF4CAF7A);
}

/// The magnitude in a ring, coloured by strength.
class _MagBadge extends StatelessWidget {
  const _MagBadge(this.mag, {this.size = 44});
  final num? mag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = magColor(mag);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c, Color.lerp(c, Colors.black, 0.35)!]),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: size * 0.25)],
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: size > 50 ? 2.5 : 1.5),
      ),
      child: Text(mag == null ? '?' : mag!.toStringAsFixed(1), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.34, fontFeatures: tabularFigures)),
    );
  }
}

String _ago(String? local) {
  final t = DateTime.tryParse(local ?? '');
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// "116 km E of Georgetown, Saint Helena" → ("Saint Helena", "116 km E of Georgetown").
(String, String?) _splitPlace(Object? place) {
  final p = '${place ?? 'Unknown place'}';
  final comma = p.lastIndexOf(', ');
  if (comma > 0) return (p.substring(comma + 2), p.substring(0, comma));
  final of = p.indexOf(' of ');
  if (of > 0) return (p.substring(of + 4), p.substring(0, of + 3));
  return (p, null);
}

bool _recent(Map<String, dynamic> e, [int hours = 3]) {
  final t = DateTime.tryParse('${e['time'] ?? ''}');
  return t != null && DateTime.now().difference(t).inHours < hours;
}

/// Epicentres on a map: the world, or the region of a nearby search.
class _QuakeMap extends StatelessWidget {
  const _QuakeMap({required this.quakes, this.height = 170, this.near = false, this.focus});
  final List<Map<String, dynamic>> quakes;
  final double height;
  final bool near;
  final Map<String, dynamic>? focus;

  @override
  Widget build(BuildContext context) {
    final pts = [
      for (final e in quakes)
        if (numOf(e['latitude']) != null && numOf(e['longitude']) != null) e,
    ];
    // Weakest first, so the strongest draw on top.
    pts.sort((a, b) => ((numOf(a['magnitude']) ?? 0)).compareTo(numOf(b['magnitude']) ?? 0));
    double avg(String k) => pts.isEmpty ? 0 : pts.fold<double>(0, (s, e) => s + numOf(e[k])!.toDouble()) / pts.length;
    final f = focus;
    final lat = f != null ? numOf(f['latitude'])!.toDouble() : (near ? avg('latitude') : 15.0);
    final lon = f != null ? numOf(f['longitude'])!.toDouble() : (near ? avg('longitude') : 10.0);
    return TileMap(
      lat: lat,
      lon: lon,
      fitWorld: !near && f == null,
      zoom: f != null ? 6 : (near ? 5 : null),
      height: height,
      dark: true,
      markers: [
        for (final e in pts)
          MapMarker(
            numOf(e['latitude'])!.toDouble(),
            numOf(e['longitude'])!.toDouble(),
            size: (f != null && e == f) ? 64 : (10 + ((numOf(e['magnitude']) ?? 3) - 2).clamp(0, 6) * 5.0),
            child: PulseDot(color: magColor(numOf(e['magnitude'])), pulse: (f != null && e == f) || _recent(e)),
          ),
      ],
    );
  }
}

class _QuakesCard extends StatelessWidget {
  const _QuakesCard({required this.q});
  final Map<String, dynamic> q;

  @override
  Widget build(BuildContext context) {
    final list = maps(q['earthquakes']);
    final strongest = mapOf(q['strongest']);
    final near = q['near'] != null;
    return InfoFrame(
      onTap: () => _showQuakes(context, q),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              _QuakeMap(quakes: list, near: near),
              Positioned(
                left: Space.s,
                top: Space.s,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.ssid_chart_rounded, size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '${list.length} ${near ? 'near ${q['near']}' : 'worldwide'} · M${q['min_magnitude']}+ · ${q['days']}d',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (strongest.isNotEmpty) _StrongestStrip(e: strongest),
          if (list.length > 1)
            Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs), child: _MagSpread(quakes: list)),
          if (list.isEmpty) Padding(padding: const EdgeInsets.all(Space.m), child: Text('No earthquakes recorded in that window.', style: context.text.bodySmall)),
          for (final e in list.where((e) => e['id'] != strongest['id']).take(5)) _QuakeRow(e: e),
          if (list.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Center(child: Text('Tap for all ${list.length}', style: TextStyle(fontSize: 12, color: AppColors.text3))),
            ),
        ],
      ),
    );
  }
}

/// The strongest quake, front and centre.
class _StrongestStrip extends StatelessWidget {
  const _StrongestStrip({required this.e});
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final c = magColor(numOf(e['magnitude']));
    final (region, where) = _splitPlace(e['place']);
    return InkWell(
      onTap: () => _showQuake(context, e),
      child: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.02)], begin: Alignment.centerLeft, end: Alignment.centerRight)),
        child: Row(
          children: [
            _MagBadge(numOf(e['magnitude']), size: 56),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STRONGEST', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c)),
                  Text(region, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                    [where, _ago(e['time'] as String?)].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      InfoPill('${numOf(e['depth_km'])?.round() ?? '?'} km deep', icon: Icons.vertical_align_bottom_rounded),
                      if (e['distance_km'] != null) InfoPill('${e['distance_km']} km away', icon: Icons.near_me_outlined),
                      if (e['tsunami'] == true) const InfoPill('Tsunami flag', icon: Icons.tsunami_rounded, color: Color(0xFFE5484D)),
                      if ((numOf(e['felt_reports']) ?? 0) > 0) InfoPill('${e['felt_reports']} felt it', icon: Icons.people_outline_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many fell in each magnitude band, as one bar.
class _MagSpread extends StatelessWidget {
  const _MagSpread({required this.quakes});
  final List<Map<String, dynamic>> quakes;

  @override
  Widget build(BuildContext context) {
    const bands = [(0.0, 4.0, '<4'), (4.0, 5.0, '4–5'), (5.0, 6.0, '5–6'), (6.0, 7.0, '6–7'), (7.0, 99.0, '7+')];
    final counts = [
      for (final b in bands) quakes.where((e) => (numOf(e['magnitude']) ?? 0) >= b.$1 && (numOf(e['magnitude']) ?? 0) < b.$2).length,
    ];
    final total = counts.fold<int>(0, (s, c) => s + c);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (var i = 0; i < bands.length; i++)
                  if (counts[i] > 0) Expanded(flex: counts[i], child: Container(color: magColor(bands[i].$1 + 0.5))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: Space.m,
          runSpacing: 2,
          children: [
            for (var i = 0; i < bands.length; i++)
              if (counts[i] > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: magColor(bands[i].$1 + 0.5), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('M${bands[i].$3} · ${counts[i]}', style: TextStyle(fontSize: 11, color: AppColors.text2, fontFeatures: tabularFigures)),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _QuakeRow extends StatelessWidget {
  const _QuakeRow({required this.e, this.padded = true});
  final Map<String, dynamic> e;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final c = magColor(numOf(e['magnitude']));
    final (region, where) = _splitPlace(e['place']);
    final depth = (numOf(e['depth_km']) ?? 0).toDouble();
    return InkWell(
      onTap: () => _showQuake(context, e),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padded ? Space.m : 0, vertical: 7),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _MagBadge(numOf(e['magnitude']), size: 40),
                if (_recent(e, 1))
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(width: 11, height: 11, decoration: BoxDecoration(color: const Color(0xFFE5484D), shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2))),
                  ),
              ],
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(region, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    [where, _ago(e['time'] as String?), if (e['distance_km'] != null) '${e['distance_km']} km away'].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            // Depth: shallow quakes shake harder, so the bar fills as they get shallower.
            SizedBox(
              width: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${depth.round()} km', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text2, fontFeatures: tabularFigures)),
                  const SizedBox(height: 3),
                  ShareBar((1 - (depth / 300)).clamp(0.08, 1.0), color: c, height: 4),
                ],
              ),
            ),
            if (e['tsunami'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.tsunami_rounded, size: 18, color: Color(0xFFE5484D))),
          ],
        ),
      ),
    );
  }
}

void _showQuakes(BuildContext context, Map<String, dynamic> q) {
  final list = maps(q['earthquakes']);
  showInfoSheet(
    context,
    initialSize: 0.94,
    (context) => [
      SheetTitle('${list.length} earthquakes', subtitle: '${q['near'] ?? 'Worldwide'} · M${q['min_magnitude']}+ · last ${q['days']} days'),
      const SizedBox(height: Space.m),
      ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: _QuakeMap(quakes: list, near: q['near'] != null, height: 220)),
      const SizedBox(height: Space.m),
      if (list.length > 1) _MagSpread(quakes: list),
      const SizedBox(height: Space.s),
      for (final e in list) _QuakeRow(e: e, padded: false),
      Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('Source: USGS. A red dot marks the last hour; pulsing epicentres, the last three hours.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
    ],
  );
}

String _intensity(num? m) {
  final v = m ?? 0;
  if (v >= 8) return 'Great: severe damage over a wide area';
  if (v >= 7) return 'Major: serious damage';
  if (v >= 6) return 'Strong: damaging near the centre';
  if (v >= 5) return 'Moderate: can damage weak buildings';
  if (v >= 4) return 'Light: widely felt, little damage';
  if (v >= 3) return 'Minor: felt by some';
  return 'Micro: rarely felt';
}

/// Where a magnitude sits on the scale from 2 to 9.
class _MagScale extends StatelessWidget {
  const _MagScale(this.mag);
  final num? mag;

  @override
  Widget build(BuildContext context) {
    final m = (mag ?? 0).toDouble();
    final f = ((m - 2) / 7).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) => Column(
        children: [
          SizedBox(
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(colors: [magColor(3), magColor(4), magColor(5), magColor(6), magColor(7)]),
                    ),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth * f - 9).clamp(0.0, c.maxWidth - 18),
                  top: 4,
                  child: Container(
                    width: 18,
                    height: 20,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: magColor(m), width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final v in const [2, 3, 4, 5, 6, 7, 8, 9]) Text('$v', style: TextStyle(fontSize: 10, color: AppColors.text3))],
          ),
        ],
      ),
    );
  }
}

void _showQuake(BuildContext context, Map<String, dynamic> e) {
  final c = magColor(numOf(e['magnitude']));
  final (region, where) = _splitPlace(e['place']);
  final hasPoint = numOf(e['latitude']) != null && numOf(e['longitude']) != null;
  showInfoSheet(
    context,
    initialSize: 0.88,
    (context) => [
      if (hasPoint)
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: Stack(
            children: [
              _QuakeMap(quakes: [e], focus: e, height: 210),
              Positioned(
                left: Space.m,
                bottom: Space.m,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(Radii.m)),
                  child: Text('${numOf(e['latitude'])?.toStringAsFixed(2)}°, ${numOf(e['longitude'])?.toStringAsFixed(2)}°', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: Space.l),
      Row(
        children: [
          _MagBadge(numOf(e['magnitude']), size: 64),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(region, style: context.text.titleLarge),
                if (where != null) Text(where, style: context.text.bodySmall),
                Text(_ago(e['time'] as String?), style: TextStyle(fontSize: 12, color: AppColors.text3)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.l),
      _MagScale(numOf(e['magnitude'])),
      const SizedBox(height: 6),
      Text(_intensity(numOf(e['magnitude'])), style: TextStyle(fontWeight: FontWeight.w700, color: c)),
      if (e['tsunami'] == true)
        Container(
          margin: const EdgeInsets.only(top: Space.m),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(color: const Color(0xFFE5484D).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.5))),
          child: const Row(
            children: [
              Icon(Icons.tsunami_rounded, color: Color(0xFFE5484D)),
              SizedBox(width: Space.s),
              Expanded(child: Text('USGS flagged this for possible tsunami. Follow local warnings, not this card.', style: TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      const SizedBox(height: Space.l),
      infoGrid([
        InfoStat('Magnitude', '${e['magnitude']} ${e['mag_type'] ?? ''}'.trim(), icon: Icons.ssid_chart_rounded),
        InfoStat('Depth', '${numOf(e['depth_km'])?.toStringAsFixed(1) ?? '?'} km${(numOf(e['depth_km']) ?? 0) < 70 ? ' · shallow' : (numOf(e['depth_km']) ?? 0) < 300 ? ' · intermediate' : ' · deep'}', icon: Icons.vertical_align_bottom_rounded),
        if (e['distance_km'] != null) InfoStat('Distance', '${e['distance_km']} km', icon: Icons.near_me_outlined),
        InfoStat('Felt reports', '${e['felt_reports'] ?? 0}', icon: Icons.people_outline_rounded),
        InfoStat('Local time', '${e['time'] ?? ''}'.replaceFirst('T', ' '), icon: Icons.schedule_rounded),
        InfoStat('UTC', '${e['time_utc'] ?? ''}'.replaceFirst('T', ' '), icon: Icons.public_rounded),
        InfoStat('PAGER alert', e['alert'] == null ? 'None' : '${e['alert']}'.toUpperCase(), icon: Icons.notifications_active_outlined, valueColor: e['alert'] == null ? null : _alertColor('${e['alert']}')),
        if (e['significance'] != null) InfoStat('Significance', '${e['significance']} / 1000+', icon: Icons.insights_rounded),
      ]),
      sheetButtons([
        linkButton('Map', 'https://www.openstreetmap.org/?mlat=${e['latitude']}&mlon=${e['longitude']}#map=7/${e['latitude']}/${e['longitude']}', filled: true, icon: Icons.map_outlined),
        linkButton('USGS page', textOf(e['url'])),
        TextButton.icon(onPressed: () => openLink('${textOf(e['url']) ?? ''}/tellus'), icon: const Icon(Icons.record_voice_over_outlined, size: 18), label: const Text('Did you feel it?')),
      ]),
    ],
  );
}

// ---- disasters --------------------------------------------------------------------

Color _alertColor(String a) => switch (a.toLowerCase()) {
  'red' => const Color(0xFFE5484D),
  'orange' => const Color(0xFFF2994A),
  'yellow' => const Color(0xFFE2B33C),
  _ => const Color(0xFF4CAF7A),
};

IconData _disasterIcon(Object? code) => switch ('$code') {
  'EQ' => Icons.ssid_chart_rounded,
  'TC' => Icons.cyclone_rounded,
  'FL' => Icons.flood_rounded,
  'VO' => Icons.volcano_rounded,
  'DR' => Icons.water_drop_outlined,
  'WF' => Icons.local_fire_department_rounded,
  'TS' => Icons.tsunami_rounded,
  _ => Icons.warning_amber_rounded,
};

class _DisastersCard extends StatelessWidget {
  const _DisastersCard({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final events = maps(d['events']);
    final byType = mapOf(d['by_type']);
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.warning_amber_rounded, 'GDACS alerts · last ${d['days']} days · ${d['count']}', color: (numOf(d['red']) ?? 0) > 0 ? _alertColor('red') : null),
          if (byType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if ((numOf(d['red']) ?? 0) > 0) InfoPill('${d['red']} red', color: _alertColor('red')),
                if ((numOf(d['orange']) ?? 0) > 0) InfoPill('${d['orange']} orange', color: _alertColor('orange')),
                for (final e in byType.entries) InfoPill('${e.value} ${e.key.toLowerCase()}${(numOf(e.value) ?? 0) == 1 ? '' : 's'}'),
              ]),
            ),
          if (events.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: Text('No alerts match.', style: context.text.bodySmall)),
          for (final e in events.take(7)) _DisasterRow(e: e),
          if (events.length > 7) TextButton(onPressed: () => _showDisasters(context, d), child: Text('All ${events.length} alerts')),
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

class _DisasterRow extends StatelessWidget {
  const _DisasterRow({required this.e, this.padded = true});
  final Map<String, dynamic> e;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final c = _alertColor('${e['alert']}');
    return InkWell(
      onTap: () => _showDisaster(context, e),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padded ? Space.m : 0, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.6))),
              child: Icon(_disasterIcon(e['type_code']), color: c, size: 20),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e['name'] ?? e['type']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text(
                    ['${e['type']}', if (e['country'] != null) '${e['country']}', if (e['from'] != null) '${e['from']}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
            if (e['ongoing'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: InfoPill('Ongoing')),
          ],
        ),
      ),
    );
  }
}

void _showDisasters(BuildContext context, Map<String, dynamic> d) => showInfoSheet(
  context,
  (context) => [
    SheetTitle('${d['count']} disaster alerts', subtitle: 'GDACS · last ${d['days']} days'),
    const SizedBox(height: Space.m),
    for (final e in maps(d['events'])) _DisasterRow(e: e, padded: false),
  ],
);

void _showDisaster(BuildContext context, Map<String, dynamic> e) {
  final c = _alertColor('${e['alert']}');
  showInfoSheet(
    context,
    initialSize: 0.72,
    (context) => [
      SheetTitle(
        '${e['name'] ?? e['type']}',
        subtitle: '${e['type']}${e['ongoing'] == true ? ' · ongoing' : ''}',
        leading: e['icon'] == null ? Icon(_disasterIcon(e['type_code']), color: c, size: 36) : NetImage('${e['icon']}', width: 40, height: 40, fit: BoxFit.contain, errorWidget: Icon(_disasterIcon(e['type_code']), color: c, size: 36)),
      ),
      const SizedBox(height: Space.m),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: c.withValues(alpha: 0.5))),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined, color: c),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                '${'${e['alert']}'.toUpperCase()} alert — ${switch ('${e['alert']}') { 'red' => 'severe humanitarian impact likely', 'orange' => 'moderate impact possible', _ => 'low expected impact' }}',
                style: TextStyle(fontWeight: FontWeight.w600, color: c),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.m),
      if (e['severity'] != null) KeyValueRow('Severity', '${e['severity']}'),
      if (e['country'] != null) KeyValueRow('Countries', '${e['country']}'),
      KeyValueRow('From', '${e['from'] ?? '—'}'),
      KeyValueRow('To', '${e['to'] ?? '—'}'),
      if (e['latitude'] != null) KeyValueRow('Location', '${numOf(e['latitude'])?.toStringAsFixed(2)}, ${numOf(e['longitude'])?.toStringAsFixed(2)}'),
      if (e['description'] != null) ...[const SizedBox(height: Space.m), Text('${e['description']}', style: context.text.bodyMedium?.copyWith(height: 1.45))],
      sheetButtons([
        linkButton('GDACS report', textOf(e['url']), filled: true),
        if (e['latitude'] != null) linkButton('Map', 'https://www.openstreetmap.org/?mlat=${e['latitude']}&mlon=${e['longitude']}#map=6/${e['latitude']}/${e['longitude']}', icon: Icons.map_outlined),
      ]),
    ],
  );
}

// ---- air quality ------------------------------------------------------------------

Color aqiColor(num? aqi) {
  final v = aqi ?? 0;
  if (v <= 50) return const Color(0xFF4CAF7A);
  if (v <= 100) return const Color(0xFFE2B33C);
  if (v <= 150) return const Color(0xFFF2994A);
  if (v <= 200) return const Color(0xFFE5484D);
  if (v <= 300) return const Color(0xFF8E4EC6);
  return const Color(0xFF7E0023);
}

Color uvColor(num? uv) {
  final v = uv ?? 0;
  if (v < 3) return const Color(0xFF4CAF7A);
  if (v < 6) return const Color(0xFFE2B33C);
  if (v < 8) return const Color(0xFFF2994A);
  if (v < 11) return const Color(0xFFE5484D);
  return const Color(0xFF8E4EC6);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _aqiAdvice(num? aqi) {
  final v = aqi ?? 0;
  if (v <= 50) return 'Air is clean. A good time to be outside.';
  if (v <= 100) return 'Acceptable. Unusually sensitive people may want to take it easier outdoors.';
  if (v <= 150) return 'People with asthma, heart or lung conditions, children and older adults should limit long outdoor exertion.';
  if (v <= 200) return 'Everyone may feel effects; sensitive groups should avoid long outdoor exertion.';
  if (v <= 300) return 'Health alert: avoid outdoor exertion; consider a mask outdoors.';
  return 'Emergency conditions: stay indoors with windows closed.';
}

String _uvAdvice(num? uv) {
  final v = uv ?? 0;
  if (v < 3) return 'No protection needed.';
  if (v < 6) return 'Sunscreen and sunglasses around midday.';
  if (v < 8) return 'Sunscreen SPF 30+, hat and shade from late morning to mid-afternoon.';
  if (v < 11) return 'Extra protection: avoid the midday sun, cover up, SPF 50.';
  return 'Extreme: unprotected skin burns within minutes. Stay in shade at midday.';
}

class _AirCard extends StatelessWidget {
  const _AirCard({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final aqi = mapOf(a['aqi']);
    final uv = mapOf(a['uv']);
    final sun = mapOf(a['sun']);
    final us = numOf(aqi['us']);
    final c = aqiColor(us);
    final pollen = mapOf(a['pollen']);
    final worst = pollen.entries.where((e) => mapOf(e.value)['level'] != 'none').toList()
      ..sort((x, y) => (numOf(mapOf(y.value)['grains_m3']) ?? 0).compareTo(numOf(mapOf(x.value)['grains_m3']) ?? 0));
    return InfoFrame(
      onTap: () => _showAir(context, a),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.air_rounded, 'Air & sun · ${a['place']}${a['country'] == null ? '' : ', ${a['country']}'}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Row(
              children: [
                _Ring(value: us, max: 300, color: c, label: 'US AQI'),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_cap('${aqi['us_level']}'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
                      Text(_aqiAdvice(us), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.text2, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Row(
              children: [
                Expanded(child: _Tile(icon: Icons.wb_sunny_outlined, label: 'UV now', value: '${numOf(uv['now'])?.toStringAsFixed(1) ?? '—'}', sub: 'max ${numOf(uv['max_today'])?.toStringAsFixed(0) ?? '—'} · ${uv['max_level']}', color: uvColor(numOf(uv['max_today'])))),
                const SizedBox(width: Space.s),
                Expanded(child: _Tile(icon: Icons.wb_twilight_rounded, label: 'Sun', value: '${sun['sunrise'] ?? '—'}', sub: 'sets ${sun['sunset'] ?? '—'}')),
                const SizedBox(width: Space.s),
                Expanded(
                  child: worst.isEmpty
                      ? _Tile(icon: Icons.grain_rounded, label: 'PM2.5', value: '${numOf(mapOf(a['pollutants'])['pm2_5'])?.round() ?? '—'}', sub: 'µg/m³')
                      : _Tile(icon: Icons.local_florist_outlined, label: 'Pollen', value: _cap(worst.first.key), sub: '${mapOf(worst.first.value)['level']}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.max, required this.color, required this.label, this.size = 76});
  final num? value;
  final num max;
  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(value: ((value ?? 0) / max).clamp(0.02, 1).toDouble(), strokeWidth: 7, color: color, backgroundColor: AppColors.surface3, strokeCap: StrokeCap.round),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${value?.round() ?? '—'}', style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, height: 1, fontFeatures: tabularFigures)),
            Text(label, style: TextStyle(fontSize: 9, color: AppColors.text3)),
          ],
        ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, required this.sub, this.color});
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s + 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 14, color: color ?? AppColors.text3), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, color: AppColors.text3))]),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color, fontFeatures: tabularFigures)),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.text3)),
      ],
    ),
  );
}

void _showAir(BuildContext context, Map<String, dynamic> a) {
  final aqi = mapOf(a['aqi']);
  final uv = mapOf(a['uv']);
  final sun = mapOf(a['sun']);
  final pol = mapOf(a['pollutants']);
  final pollen = mapOf(a['pollen']);
  final hourly = maps(a['hourly']);
  final days = maps(a['days']);
  const names = {'pm2_5': 'PM2.5', 'pm10': 'PM10', 'ozone': 'Ozone (O₃)', 'nitrogen_dioxide': 'Nitrogen dioxide (NO₂)', 'sulphur_dioxide': 'Sulphur dioxide (SO₂)', 'carbon_monoxide': 'Carbon monoxide (CO)', 'dust': 'Dust'};
  // WHO 24-hour guideline values, µg/m³.
  const who = {'pm2_5': 15, 'pm10': 45, 'ozone': 100, 'nitrogen_dioxide': 25, 'sulphur_dioxide': 40, 'carbon_monoxide': 4000};
  showInfoSheet(
    context,
    (context) => [
      SheetTitle('${a['place']}', subtitle: [a['region'], a['country'], '${'${a['time'] ?? ''}'.replaceFirst('T', ' ')} local'].whereType<Object>().join(' · ')),
      const SizedBox(height: Space.l),
      Row(
        children: [
          _Ring(value: numOf(aqi['us']), max: 300, color: aqiColor(numOf(aqi['us'])), label: 'US AQI', size: 88),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_cap('${aqi['us_level']}'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: aqiColor(numOf(aqi['us'])))),
                if (aqi['european'] != null) Text('European AQI ${aqi['european']}', style: context.text.bodySmall),
                const SizedBox(height: 4),
                Text(_aqiAdvice(numOf(aqi['us'])), style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
      if (hourly.isNotEmpty) ...[
        const SectionLabel('Next 24 hours · AQI'),
        MiniBars(
          values: [for (final h in hourly) numOf(h['us_aqi']) ?? 0],
          labels: [for (final h in hourly) '${h['time']}'.substring(0, 2)],
          labelEvery: 4,
          color: aqiColor(numOf(aqi['us'])),
          height: 70,
          valueLabel: (v) => 'AQI ${v.round()}',
        ),
      ],
      const SectionLabel('Pollutants', trailing: 'µg/m³ · WHO daily guideline'),
      for (final e in pol.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(names[e.key] ?? e.key, style: const TextStyle(fontSize: 13.5))),
                  Text('${numOf(e.value)?.toStringAsFixed(1)}${who[e.key] == null ? '' : ' / ${who[e.key]}'}', style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                ],
              ),
              if (who[e.key] != null) ...[
                const SizedBox(height: 3),
                ShareBar(((numOf(e.value) ?? 0) / (who[e.key]! * 2)).toDouble(), color: (numOf(e.value) ?? 0) > who[e.key]! ? AppColors.danger : AppColors.success),
              ],
            ],
          ),
        ),
      const SectionLabel('UV index'),
      Row(
        children: [
          _Ring(value: numOf(uv['max_today']), max: 12, color: uvColor(numOf(uv['max_today'])), label: 'max today', size: 64),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_cap('${uv['max_level']}')} · now ${numOf(uv['now'])?.toStringAsFixed(1) ?? '—'}', style: TextStyle(fontWeight: FontWeight.w700, color: uvColor(numOf(uv['max_today'])))),
                Text(_uvAdvice(numOf(uv['max_today'])), style: TextStyle(fontSize: 12.5, color: AppColors.text2, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
      if (hourly.any((h) => (numOf(h['uv']) ?? 0) > 0)) ...[
        const SizedBox(height: Space.m),
        MiniBars(
          values: [for (final h in hourly) numOf(h['uv']) ?? 0],
          labels: [for (final h in hourly) '${h['time']}'.substring(0, 2)],
          labelEvery: 4,
          color: uvColor(numOf(uv['max_today'])),
          height: 56,
          valueLabel: (v) => 'UV ${v.toStringAsFixed(1)}',
        ),
      ],
      const SectionLabel('Pollen'),
      if (pollen.isEmpty)
        Text('${a['pollen_note'] ?? 'No pollen data here.'}', style: context.text.bodySmall)
      else
        for (final e in pollen.entries)
          KeyValueRow(_cap(e.key), '${_cap('${mapOf(e.value)['level']}')} · ${numOf(mapOf(e.value)['grains_m3'])?.round()} grains/m³'),
      const SectionLabel('Sun'),
      infoGrid([
        InfoStat('Sunrise', '${sun['sunrise'] ?? '—'}', icon: Icons.wb_twilight_rounded),
        InfoStat('Sunset', '${sun['sunset'] ?? '—'}', icon: Icons.nights_stay_outlined),
        InfoStat('Day length', '${sun['daylight'] ?? '—'}', icon: Icons.light_mode_outlined),
        if (numOf(sun['daylight_change_tomorrow_minutes']) != null)
          InfoStat('Tomorrow', '${numOf(sun['daylight_change_tomorrow_minutes'])! >= 0 ? '+' : ''}${sun['daylight_change_tomorrow_minutes']} min of daylight', icon: Icons.trending_flat_rounded),
      ]),
      if (days.length > 1) ...[
        const SizedBox(height: Space.m),
        for (final d in days) KeyValueRow('${d['date']}', '↑ ${d['sunrise']}  ↓ ${d['sunset']} · ${d['daylight']} · UV ${numOf(d['uv_max'])?.round() ?? '—'}'),
      ],
      Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('Source: Open-Meteo (Copernicus CAMS models), the weather tool\'s provider.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
    ],
  );
}
