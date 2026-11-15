import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../../../app/theme.dart';
import '../data/file_loader.dart';
import '../data/message_content.dart';
import '../../../core/widgets/fullscreen_image.dart';

Future<void> showMediaViewer(
  BuildContext context,
  td.MessageContent content, {
  String title = 'Media',
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => MediaViewer(content: content, title: title),
  ),
);

class MediaViewer extends ConsumerStatefulWidget {
  const MediaViewer({super.key, required this.content, required this.title});
  final td.MessageContent content;
  final String title;

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
  String? _path;
  String? _error;
  VideoPlayerController? _video;
  bool _saving = false;

  td.File? get _file => switch (widget.content) {
    td.MessagePhoto(:final photo) => pickPhotoSize(
      photo.sizes,
      minWidth: 1200,
    )?.photo,
    // A picture or video sent as a file: the file itself, full quality.
    td.MessageDocument(:final document) => document.document,
    _ => previewFileOf(widget.content),
  };
  bool get _isVideo =>
      widget.content is td.MessageVideo ||
      widget.content is td.MessageAnimation ||
      (widget.content is td.MessageDocument &&
          (widget.content as td.MessageDocument).document.mimeType.startsWith('video/'));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null) {
      setState(() => _error = 'This media file is unavailable.');
      return;
    }
    final path = await ref
        .read(fileLoaderProvider)
        .download(file, priority: 30);
    if (!mounted) return;
    if (path == null) {
      setState(() => _error = 'Could not download this media.');
      return;
    }
    setState(() => _path = path);
    if (_isVideo) {
      final video = VideoPlayerController.file(File(path));
      try {
        await video.initialize();
        await video.setLooping(widget.content is td.MessageAnimation);
        if (widget.content is td.MessageAnimation) await video.play();
        if (mounted)
          setState(() => _video = video);
        else
          video.dispose();
      } catch (_) {
        video.dispose();
        if (mounted)
          setState(
            () => _error = 'This video format cannot be played on this device.',
          );
      }
    }
  }

  Future<void> _save() async {
    final path = _path;
    if (path == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (_isVideo) {
        await Gal.putVideo(path, album: 'Triangle');
      } else {
        await Gal.putImage(path, album: 'Triangle');
      }
      if (mounted) showSnack(context, 'Saved to your device');
    } catch (_) {
      if (mounted)
        showSnack(
          context,
          'Couldn\'t save this media',
          icon: Icons.error_outline_rounded,
        );
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _path == null
              ? const Center(child: CircularProgressIndicator())
              : _isVideo
              ? _VideoControls(controller: _video)
              : FullscreenZoomImage(image: FileImage(File(_path!))),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + Space.s,
          left: Space.s,
          child: IconButton.filledTonal(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + Space.s,
          right: Space.s,
          child: IconButton.filledTonal(
            tooltip: 'Save to device',
            onPressed: _path == null || _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ),
      ],
    ),
  );
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({required this.controller});
  final VideoPlayerController? controller;
  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  bool _visible = true;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized)
      return const Center(child: CircularProgressIndicator());
    final value = c.value;
    final total = value.duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    return GestureDetector(
      onTap: () => setState(() => _visible = !_visible),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (_visible)
            Positioned(
              left: Space.l,
              right: Space.l,
              bottom: Space.l,
              child: Container(
                padding: const EdgeInsets.all(Space.s),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(Radii.l),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        c.value.isPlaying ? c.pause() : c.play();
                        setState(() {});
                      },
                      icon: Icon(
                        c.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      formatDuration(value.position.inSeconds),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: value.position.inMilliseconds
                            .clamp(0, total.toInt())
                            .toDouble(),
                        max: total,
                        onChanged: (v) =>
                            c.seekTo(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Text(
                      formatDuration(value.duration.inSeconds),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    IconButton(
                      onPressed: () {
                        c.setVolume(c.value.volume == 0 ? 1 : 0);
                        setState(() {});
                      },
                      icon: Icon(
                        c.value.volume == 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
