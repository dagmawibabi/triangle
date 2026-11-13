import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../app/theme.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for the image tools. Null for other tools.
Widget? imageResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'image_info' when j['width'] != null => _InfoCard(i: j, path: '${part.args['file'] ?? ''}'),
  'image_resize' || 'image_crop' || 'image_compress' || 'image_convert' || 'image_remove_background' when j['image_path'] is String => _EditCard(r: j),
  _ => null,
};

String _dims(Object? w, Object? h) => '$w × $h';

String _title(String op) => switch (op) {
  'resize' => 'Resized',
  'crop' => 'Cropped',
  'compress' => 'Compressed',
  'convert' => 'Converted',
  'remove_background' => 'Background removed',
  _ => 'Edited',
};

IconData _icon(String op) => switch (op) {
  'resize' => Icons.photo_size_select_large_rounded,
  'crop' => Icons.crop_rounded,
  'compress' => Icons.compress_rounded,
  'convert' => Icons.transform_rounded,
  _ => Icons.auto_fix_high_rounded,
};

/// A grey-and-white checkerboard behind transparent pictures.
class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CheckerPainter(), child: child);
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 10.0;
    final a = Paint()..color = const Color(0xFFE6E6E6);
    final b = Paint()..color = const Color(0xFFFFFFFF);
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), ((x / s).floor() + (y / s).floor()).isEven ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _file(String path, {BoxFit fit = BoxFit.cover, double? width, double? height}) => File(path).existsSync()
    ? Image.file(File(path), fit: fit, width: width, height: height, gaplessPlayback: true, errorBuilder: (_, _, _) => _missing(width, height))
    : _missing(width, height);

Widget _missing(double? w, double? h) => Container(
  width: w,
  height: h,
  color: AppColors.surface2,
  alignment: Alignment.center,
  child: Icon(Icons.broken_image_outlined, color: AppColors.text3),
);

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.label, required this.caption, this.checker = false});
  final String path;
  final String label;
  final String caption;
  final bool checker;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.m),
          child: checker ? Checkerboard(child: _file(path, fit: BoxFit.contain)) : ColoredBox(color: AppColors.surface2, child: _file(path, fit: BoxFit.contain)),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      Text(caption, maxLines: 2, style: TextStyle(fontSize: 11.5, color: AppColors.text3, fontFeatures: tabularFigures)),
    ],
  );
}

class _EditCard extends StatelessWidget {
  const _EditCard({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final op = '${r['done'] ?? ''}';
    final saved = numOf(r['saved_percent']);
    final cutout = op == 'remove_background' && '${r['background'] ?? 'transparent'}' == 'transparent';
    final src = '${r['source_path'] ?? ''}';
    return InfoFrame(
      onTap: () => showImageCompare(context, r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(
            _icon(op),
            _title(op),
            trailing: saved != null && saved > 0 && op != 'remove_background' ? InfoPill('−$saved%', color: AppColors.success) : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Thumb(
                    path: src,
                    label: 'Before',
                    caption: '${_dims(r['original_width'], r['original_height'])}\n${fileSize(numOf(r['original_bytes']))} · ${'${r['original_mime'] ?? ''}'.replaceFirst('image/', '').toUpperCase()}',
                  ),
                ),
                Padding(padding: const EdgeInsets.only(top: 60, left: 6, right: 6), child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.text3)),
                Expanded(
                  child: _Thumb(
                    path: '${r['image_path']}',
                    label: 'After',
                    checker: cutout,
                    caption: '${_dims(r['width'], r['height'])}\n${fileSize(numOf(r['bytes']))} · ${'${r['format'] ?? ''}'.toUpperCase()}${r['quality'] == null ? '' : ' q${r['quality']}'}',
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

Future<void> _save(BuildContext context, String path) async {
  try {
    if (!await Gal.hasPermission()) await Gal.requestPermission();
    await Gal.putImage(path, album: 'Triangle');
    if (context.mounted) showSnack(context, 'Saved to the gallery');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t save: $e', icon: Icons.error_outline_rounded);
  }
}

/// Before and after, with a slider to wipe between them, and the details.
Future<void> showImageCompare(BuildContext context, Map<String, dynamic> r) {
  final op = '${r['done'] ?? ''}';
  final cutout = op == 'remove_background' && '${r['background'] ?? 'transparent'}' == 'transparent';
  final src = '${r['source_path'] ?? ''}';
  final out = '${r['image_path']}';
  final ratio = (numOf(r['width']) ?? 1) / (numOf(r['height']) ?? 1);
  final sameFrame = op != 'crop';
  return showInfoSheet(
    context,
    initialSize: 0.94,
    (context) => [
      SheetTitle(_title(op), subtitle: '${r['source'] ?? ''} → ${r['name'] ?? ''}'),
      const SizedBox(height: Space.m),
      if (sameFrame && File(src).existsSync())
        _CompareSlider(before: src, after: out, ratio: ratio.toDouble(), checker: cutout)
      else
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: InteractiveViewer(maxScale: 6, child: cutout ? Checkerboard(child: _file(out, fit: BoxFit.contain)) : _file(out, fit: BoxFit.contain)),
        ),
      if (sameFrame && File(src).existsSync())
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Drag across the picture to compare', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
        ),
      const SectionLabel('Details'),
      Table(
        columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
        children: [
          TableRow(children: [const SizedBox(), _th('Before'), _th('After')]),
          _tr('Size', _dims(r['original_width'], r['original_height']), _dims(r['width'], r['height'])),
          _tr('File', fileSize(numOf(r['original_bytes'])), fileSize(numOf(r['bytes']))),
          _tr('Format', '${r['original_mime'] ?? ''}'.replaceFirst('image/', '').toUpperCase(), '${r['format'] ?? ''}'.toUpperCase()),
          if (r['quality'] != null) _tr('Quality', '—', '${r['quality']}'),
        ],
      ),
      if (numOf(r['saved_percent']) != null && op != 'remove_background')
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Text(
            numOf(r['saved_percent'])! >= 0 ? '${r['saved_percent']}% smaller' : '${-(numOf(r['saved_percent'])!)}% larger',
            style: TextStyle(fontWeight: FontWeight.w700, color: numOf(r['saved_percent'])! >= 0 ? AppColors.success : AppColors.warning),
          ),
        ),
      sheetButtons([
        FilledButton.icon(onPressed: () => OpenFilex.open(out), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Open')),
        OutlinedButton.icon(onPressed: () => _save(context, out), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Save to gallery')),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: Space.l),
        child: Text('Made on this phone; nothing was uploaded. The original is unchanged.', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
      ),
    ],
  );
}

Widget _th(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)));

TableRow _tr(String label, String a, String b) => TableRow(
  children: [
    Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(label, style: TextStyle(color: AppColors.text3, fontSize: 13))),
    Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(a, style: const TextStyle(fontSize: 13, fontFeatures: tabularFigures))),
    Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(b, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: tabularFigures))),
  ],
);

class _CompareSlider extends StatefulWidget {
  const _CompareSlider({required this.before, required this.after, required this.ratio, this.checker = false});
  final String before;
  final String after;
  final double ratio;
  final bool checker;

  @override
  State<_CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<_CompareSlider> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(Radii.l),
    child: AspectRatio(
      aspectRatio: widget.ratio.clamp(0.4, 3.0),
      child: LayoutBuilder(
        builder: (context, c) => GestureDetector(
          onHorizontalDragUpdate: (d) => setState(() => _split = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          onTapDown: (d) => setState(() => _split = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.checker ? Checkerboard(child: _file(widget.after, fit: BoxFit.contain)) : ColoredBox(color: Colors.black, child: _file(widget.after, fit: BoxFit.contain)),
              ClipRect(
                clipper: _LeftClip(_split),
                child: ColoredBox(color: Colors.black, child: _file(widget.before, fit: BoxFit.contain)),
              ),
              Positioned(
                left: c.maxWidth * _split - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white),
              ),
              Positioned(
                left: c.maxWidth * _split - 16,
                top: c.maxHeight / 2 - 16,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)]),
                  child: const Icon(Icons.compare_arrows_rounded, size: 18, color: Colors.black),
                ),
              ),
              Positioned(left: 8, top: 8, child: _tag('Before')),
              Positioned(right: 8, top: 8, child: _tag('After')),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tag(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.split);
  final double split;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);
  @override
  bool shouldReclip(_LeftClip old) => old.split != split;
}

// ---- details ----------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.i, required this.path});
  final Map<String, dynamic> i;
  final String path;

  @override
  Widget build(BuildContext context) => InfoFrame(
    child: Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(Radii.m), child: _file(path, width: 84, height: 84)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i['file'] ?? 'Picture'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${_dims(i['width'], i['height'])} · ${fileSize(numOf(i['bytes']))} · ${'${i['mime'] ?? ''}'.replaceFirst('image/', '').toUpperCase()}',
                  style: TextStyle(fontSize: 12.5, color: AppColors.text2, fontFeatures: tabularFigures),
                ),
                Text(
                  '${((numOf(i['width']) ?? 0) * (numOf(i['height']) ?? 0) / 1e6).toStringAsFixed(1)} MP',
                  style: TextStyle(fontSize: 12.5, color: AppColors.text3),
                ),
                if (i['camera'] != null || i['taken'] != null)
                  Text([i['camera'], i['taken']].whereType<Object>().join(' · '), style: TextStyle(fontSize: 12, color: AppColors.text3)),
                const SizedBox(height: 6),
                if (i['has_location'] == true)
                  InfoPill(
                    'Has GPS location',
                    icon: Icons.location_on_outlined,
                    color: AppColors.warning,
                    onTap: () => openLink('https://www.openstreetmap.org/?mlat=${i['latitude']}&mlon=${i['longitude']}#map=15/${i['latitude']}/${i['longitude']}'),
                  )
                else
                  const InfoPill('No location', icon: Icons.location_off_outlined),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
