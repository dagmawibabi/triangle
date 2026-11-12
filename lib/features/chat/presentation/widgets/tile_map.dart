import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// A point on a [TileMap].
class MapMarker {
  const MapMarker(this.lat, this.lon, {required this.child, this.size = 24});
  final double lat;
  final double lon;
  final Widget child;
  final double size;
}

/// A light slippy map: Esri's grey canvas basemap tiles (no key) around a
/// centre at a fractional zoom, with widgets pinned at coordinates. No
/// panning; the cards only need a picture of where.
class TileMap extends StatelessWidget {
  const TileMap({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom,
    this.markers = const [],
    this.height = 180,
    this.dark,
    this.fitWorld = false,
  });
  final double lat;
  final double lon;

  /// Null with [fitWorld] picks the zoom that shows the whole width of the
  /// world.
  final double? zoom;
  final List<MapMarker> markers;
  final double height;
  final bool? dark;
  final bool fitWorld;

  static double _x(double lon, double world) => (lon + 180) / 360 * world;
  static double _y(double lat, double world) {
    final l = lat.clamp(-85.0, 85.0) * math.pi / 180;
    return (1 - math.log(math.tan(l) + 1 / math.cos(l)) / math.pi) / 2 * world;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
      final h = height;
      final z = fitWorld ? math.log(w / 256) / math.ln2 : (zoom ?? 4);
      final tz = z.floor().clamp(0, 18);
      final scale = math.pow(2, z - tz).toDouble();
      final tiles = 1 << tz;
      final world = 256.0 * tiles * scale;
      final cx = _x(lon, world), cy = _y(lat, world);
      // Keep the picture inside the world vertically.
      final top = (cy - h / 2).clamp(0.0, math.max(0.0, world - h));
      final left = fitWorld ? 0.0 : cx - w / 2;
      final ts = 256 * scale;
      final isDark = dark ?? !AppColors.isLight;
      final style = isDark ? 'World_Dark_Gray_Base' : 'World_Light_Gray_Base';
      final children = <Widget>[];
      for (var ty = (top / ts).floor(); ty <= ((top + h) / ts).floor(); ty++) {
        if (ty < 0 || ty >= tiles) continue;
        for (var tx = (left / ts).floor(); tx <= ((left + w) / ts).floor(); tx++) {
          final wrapped = ((tx % tiles) + tiles) % tiles;
          children.add(Positioned(
            left: tx * ts - left,
            top: ty * ts - top,
            width: ts + 0.5,
            height: ts + 0.5,
            child: Image.network(
              'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/$style/MapServer/tile/$tz/$ty/$wrapped',
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ));
        }
      }
      for (final m in markers) {
        var mx = _x(m.lon, world) - left;
        if (!fitWorld) {
          // The nearer copy of the world.
          if (mx < -world / 2) mx += world;
          if (mx > world / 2 + w) mx -= world;
        }
        final my = _y(m.lat, world) - top;
        if (mx < -m.size || mx > w + m.size || my < -m.size || my > h + m.size) continue;
        children.add(Positioned(left: mx - m.size / 2, top: my - m.size / 2, width: m.size, height: m.size, child: m.child));
      }
      return SizedBox(
        width: w,
        height: h,
        child: ClipRect(
          child: ColoredBox(
            color: isDark ? const Color(0xFF1E2126) : const Color(0xFFE8EEF2),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ...children,
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: Text('Esri, HERE, Garmin, © OpenStreetMap', style: TextStyle(fontSize: 8, color: isDark ? Colors.white54 : Colors.black45)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A glowing dot with rings, for an epicentre or a pin.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.pulse = false, this.core = 0.34});
  final Color color;
  final bool pulse;
  final double core;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(painter: _DotPainter(widget.color, widget.pulse ? _c.value : 0.55, widget.core)),
  );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.t, this.core);
  final Color color;
  final double t;
  final double core;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r * (0.45 + 0.55 * t), Paint()..color = color.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(c, r * 0.62, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawCircle(c, r * core, Paint()..color = color);
    canvas.drawCircle(c, r * core, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.t != t || old.color != color;
}
