import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../features/playlists/add_tracks_screen.dart' show pickTelegramChat;
import '../../features/sections/section_kit.dart' show sizeText;
import '../../features/telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../../infrastructure/telegram/accounts.dart';
import '../../infrastructure/telegram/td_compat.dart' show inputPhoto;
import 'app_sheet.dart';
import 'image_disk_cache.dart';

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
    openFullscreenImages(context, [image], title: title, actions: actions);

/// Opens [images] full screen at [index], swiping between them.
Future<void> openFullscreenImages(BuildContext context, List<ImageProvider> images, {int index = 0, String? title, List<Widget> actions = const []}) =>
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => FullscreenImagePage(images: images, index: index, title: title, actions: actions),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );

Future<void> openFullscreenFile(BuildContext context, String path, {String? title, List<Widget> actions = const []}) =>
    openFullscreenImage(context, FileImage(File(path)), title: title ?? path.split(RegExp(r'[\\/]')).last, actions: actions);

Future<void> openFullscreenUrl(BuildContext context, String url, {String? title, List<Widget> actions = const []}) {
  // The saved copy when there is one.
  final f = ImageDiskCache.peek(url);
  return openFullscreenImage(context, f != null ? FileImage(f) : NetworkImage(url), title: title, actions: actions);
}

/// Pictures full screen, like the Gallery's viewer: swipe between them, tap
/// to hide the bars, and save, share or look up the details of each.
class FullscreenImagePage extends ConsumerStatefulWidget {
  const FullscreenImagePage({super.key, required this.images, this.index = 0, this.title, this.actions = const []});
  final List<ImageProvider> images;
  final int index;
  final String? title;

  /// Extra buttons beside the info button at the top.
  final List<Widget> actions;

  @override
  ConsumerState<FullscreenImagePage> createState() => _FullscreenImagePageState();
}

class _FullscreenImagePageState extends ConsumerState<FullscreenImagePage> {
  late final _pages = PageController(initialPage: widget.index);
  late int _at = widget.index.clamp(0, widget.images.length - 1);
  bool _chrome = true;
  bool _busy = false;

  /// Each picture's size once it has loaded, by page.
  final _sizes = <int, Size>{};

  ImageProvider get _image => widget.images[_at];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _measure(_at);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _measure(int i) {
    if (_sizes.containsKey(i)) return;
    final stream = widget.images[i].resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        stream.removeListener(l);
        if (mounted) setState(() => _sizes[i] = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      },
      onError: (_, _) => stream.removeListener(l),
    );
    stream.addListener(l);
  }

  /// Where the picture's link points, for network pictures.
  static String? _url(ImageProvider p) => switch (p) {
    NetworkImage(:final url) => url,
    ResizeImage(:final imageProvider) => _url(imageProvider),
    _ => null,
  };

  /// The file behind the picture, fetched or written out when it has none.
  Future<File?> _source(ImageProvider p) async => switch (p) {
    FileImage(:final file) => file,
    ResizeImage(:final imageProvider) => _source(imageProvider),
    NetworkImage(:final url) => ImageDiskCache.get(url),
    _ => null,
  };

  /// The picture's bytes: its file's, or the decoded picture as a PNG.
  Future<Uint8List?> _bytes(ImageProvider p) async {
    if (p is MemoryImage) return p.bytes;
    final f = await _source(p);
    if (f != null && await f.exists()) return f.readAsBytes();
    final stream = p.resolve(ImageConfiguration.empty);
    final info = await _first(stream);
    final data = await info?.image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<ImageInfo?> _first(ImageStream stream) {
    final done = Completer<ImageInfo?>();
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        stream.removeListener(l);
        if (!done.isCompleted) done.complete(info);
      },
      onError: (_, _) {
        stream.removeListener(l);
        if (!done.isCompleted) done.complete(null);
      },
    );
    stream.addListener(l);
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () => null);
  }

  static String _ext(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
    if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
    return 'jpg';
  }

  /// A copy of the picture with the right extension, to save or send.
  Future<String?> _file() async {
    final b = await _bytes(_image);
    if (b == null || b.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final name = (widget.title ?? 'image').replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    final f = File('${dir.path}/${name.isEmpty ? 'image' : name}_${DateTime.now().millisecondsSinceEpoch}.${_ext(b)}');
    await f.writeAsBytes(b, flush: true);
    return f.path;
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    try {
      final path = await _file();
      if (path == null) throw 'the picture couldn’t be read';
      await Gal.putImage(path, album: 'Triangle');
      if (mounted) showSnack(context, 'Saved to your phone’s gallery', icon: Icons.download_done_rounded);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t save: ${e is GalException ? e.type.message : e}', icon: Icons.error_outline_rounded);
    }
  });

  Future<void> _share() async {
    final chat = await pickTelegramChat(context, title: 'Share to…');
    if (chat == null || !mounted) return;
    await _run(() async {
      try {
        final path = await _file();
        if (path == null) throw 'the picture couldn’t be read';
        await ref.read(toolRunnerFamily(ref.read(activeAccountIdProvider))).sendAndSettle(
          td.SendMessage(
            chatId: chat,
            inputMessageContent: td.InputMessagePhoto(
              photo: inputPhoto(path),
              caption: td.FormattedText(text: widget.title ?? '', entities: const []),
              showCaptionAboveMedia: false,
              selfDestructType: null,
              hasSpoiler: false,
            ),
          ),
        );
        if (mounted) showSnack(context, 'Shared', icon: Icons.forward_rounded);
      } catch (e) {
        if (mounted) showSnack(context, 'Couldn’t share: $e', icon: Icons.error_outline_rounded);
      }
    });
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) showSnack(context, 'Link copied', icon: Icons.link_rounded);
  }

  Future<void> _info() async {
    final p = _image;
    final size = _sizes[_at];
    final url = _url(p);
    final f = await _source(p);
    final bytes = f != null && await f.exists() ? await f.length() : (p is MemoryImage ? p.bytes.length : 0);
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      initialSize: 0.4,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Space.l),
        children: [
          Text('Details', style: context.text.titleMedium),
          const SizedBox(height: Space.m),
          if (widget.title?.isNotEmpty ?? false) Text(widget.title!, style: context.text.titleSmall),
          if (size != null) Text('${size.width.round()} × ${size.height.round()}'),
          if (bytes > 0) Text(sizeText(bytes)),
          if (url != null) ...[const SizedBox(height: Space.m), SelectableText(url, style: context.text.bodySmall)],
          if (url == null && p is FileImage) ...[const SizedBox(height: Space.m), SelectableText(p.file.path, style: context.text.bodySmall)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final top = MediaQuery.paddingOf(context).top;
    final many = widget.images.length > 1;
    final size = _sizes[_at];
    final url = _url(_image);
    final sub = [
      if (size != null) '${size.width.round()} × ${size.height.round()}',
      if (many) '${_at + 1} of ${widget.images.length}',
    ].join(' · ');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.images.length,
              onPageChanged: (i) {
                setState(() => _at = i);
                _measure(i);
              },
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _chrome = !_chrome),
                child: FullscreenZoomImage(image: widget.images[i]),
              ),
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
                      IconButton(tooltip: 'Close', color: white, onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      ...widget.actions,
                      IconButton(tooltip: 'Details', color: white, onPressed: _info, icon: const Icon(Icons.info_outline_rounded)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: EdgeInsets.fromLTRB(Space.s, Space.l, Space.s, MediaQuery.paddingOf(context).bottom + Space.s),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)]),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Action(icon: Icons.download_rounded, label: 'Save', onTap: _busy ? null : _save),
                      _Action(icon: Icons.forward_rounded, label: 'Share', onTap: _busy ? null : _share),
                      if (url != null) _Action(icon: Icons.link_rounded, label: 'Copy link', onTap: () => _copyLink(url)),
                      _Action(icon: Icons.info_outline_rounded, label: 'Details', onTap: _info),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white70)),
        ],
      ),
    );
  }
}

/// A labelled button on the viewer's bottom bar.
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 32,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}
