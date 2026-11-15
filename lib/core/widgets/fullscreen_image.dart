import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A picture that fills the whole screen (edge to edge, letterboxed with
/// [BoxFit.contain]) and can be pinched/double-tapped to zoom.
///
/// Images inside a bare `Center` render at their intrinsic size, which on a
/// high-density phone is a small square in the middle. This sizes the image
/// to the viewport first, then lets [InteractiveViewer] zoom it.
class FullscreenZoomImage extends StatefulWidget {
  const FullscreenZoomImage({super.key, required this.image, this.maxScale = 6});
  final ImageProvider image;
  final double maxScale;

  @override
  State<FullscreenZoomImage> createState() => _FullscreenZoomImageState();
}

class _FullscreenZoomImageState extends State<FullscreenZoomImage> with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _zoom;
  TapDownDetails? _tap;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_zoom != null) _controller.value = _zoom!.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end;
    if (zoomed) {
      end = Matrix4.identity();
    } else {
      final p = _tap?.localPosition ?? Offset.zero;
      const s = 2.5;
      end = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _zoom = Matrix4Tween(begin: _controller.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: (d) => _tap = d,
    onDoubleTap: _toggleZoom,
    child: InteractiveViewer(
      transformationController: _controller,
      maxScale: widget.maxScale,
      child: SizedBox.expand(
        child: Image(
          image: widget.image,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white70)),
        ),
      ),
    ),
  );
}

/// Opens [image] in a black, immersive, full-screen page.
Future<void> openFullscreenImage(BuildContext context, ImageProvider image, {String? title, List<Widget> actions = const []}) =>
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => FullscreenImagePage(image: image, title: title, actions: actions),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );

Future<void> openFullscreenFile(BuildContext context, String path, {String? title, List<Widget> actions = const []}) =>
    openFullscreenImage(context, FileImage(File(path)), title: title ?? path.split(RegExp(r'[\\/]')).last, actions: actions);

Future<void> openFullscreenUrl(BuildContext context, String url, {String? title, List<Widget> actions = const []}) =>
    openFullscreenImage(context, NetworkImage(url), title: title, actions: actions);

class FullscreenImagePage extends StatefulWidget {
  const FullscreenImagePage({super.key, required this.image, this.title, this.actions = const []});
  final ImageProvider image;
  final String? title;
  final List<Widget> actions;

  @override
  State<FullscreenImagePage> createState() => _FullscreenImagePageState();
}

class _FullscreenImagePageState extends State<FullscreenImagePage> {
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _chrome = !_chrome),
              child: FullscreenZoomImage(image: widget.image),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: EdgeInsets.fromLTRB(4, top + 4, 4, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      ...widget.actions,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
