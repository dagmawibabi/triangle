import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show MethodChannel, MissingPluginException, PlatformException;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// One picture for the model: a still, or a frame of a GIF or video.
class LoadedImage {
  const LoadedImage(this.file, {this.at});
  final File file;

  /// Where in the animation this frame is; null for a still.
  final Duration? at;
}

/// What [ImageInputLoader.loadFrames] found: a still (one image) or frames
/// spread over an animation.
class LoadedFrames {
  const LoadedFrames(this.images, {this.animated = false, this.duration, this.frameCount});
  final List<LoadedImage> images;
  final bool animated;

  /// How long the animation runs, when known.
  final Duration? duration;

  /// How many frames the animation has (GIF/WebP), when known.
  final int? frameCount;
}

/// Whether [bytes] are a video container: MP4/MOV (`ftyp`) or WebM/MKV
/// (EBML). Telegram sends GIFs as silent MP4s, and video stickers as WebM.
bool isVideoBytes(List<int> bytes) {
  if (bytes.length >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) return true;
  return bytes.length >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3;
}

/// Indexes of [count] frames spread evenly over [total]: the middle of each
/// equal slice, so a blank first or last frame is skipped.
List<int> spreadFrames(int total, int count) {
  if (total <= 0) return const [];
  if (count >= total) return [for (var i = 0; i < total; i++) i];
  return [for (var i = 0; i < count; i++) ((2 * i + 1) * total) ~/ (2 * count)];
}

/// Loads accessible image files, direct web images and inline image data.
/// Decode the actual content so extensionless files work and HTML is rejected.
class ImageInputLoader {
  ImageInputLoader({required this.directory, http.Client? httpClient})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final Directory directory;
  final http.Client _client;
  final bool _ownsClient;
  static const maxBytes = 20 * 1024 * 1024;
  static const _timeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<File> load(String source) async => (await loadFrames(source, maxFrames: 1)).images.first.file;

  /// [source] as pictures: a still as one image; a GIF, animated WebP or
  /// short video (MP4, WebM) as up to [maxFrames] frames spread over it.
  Future<LoadedFrames> loadFrames(String source, {int maxFrames = 6}) async {
    final bytes = await _bytes(source);
    if (isVideoBytes(bytes)) return _videoFrames(bytes, maxFrames);
    return _imageFrames(bytes, maxFrames);
  }

  Future<Uint8List> _bytes(String source) async {
    source = source.trim();
    if (source.isEmpty) throw const FormatException('No image supplied.');
    final uri = Uri.tryParse(source);
    Uint8List bytes;
    if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      final response = await _client
          .send(http.Request('GET', uri!))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.take(0).drain<void>();
        throw HttpException('Image request failed (${response.statusCode}).');
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        await response.stream.take(0).drain<void>();
        throw const FormatException('Image exceeds 20 MB.');
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (body.length + chunk.length > maxBytes) {
          throw const FormatException('Image exceeds 20 MB.');
        }
        body.add(chunk);
      }
      bytes = body.takeBytes();
    } else if (uri?.scheme == 'data') {
      if (source.length > maxBytes * 4) {
        throw const FormatException('Image exceeds 20 MB.');
      }
      final data = UriData.parse(source);
      if (!data.mimeType.startsWith('image/') && !data.mimeType.startsWith('video/')) {
        throw const FormatException('Expected an image data URL.');
      }
      bytes = Uint8List.fromList(data.contentAsBytes());
    } else {
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(source);
      if (await file.length() > maxBytes) {
        throw const FormatException('Image exceeds 20 MB.');
      }
      bytes = await file.readAsBytes();
    }
    if (bytes.length > maxBytes) {
      throw const FormatException('Image exceeds 20 MB.');
    }
    return bytes;
  }

  Future<File> _png(ui.Image image) async {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Could not decode this image.');
    await directory.create(recursive: true);
    return File('${directory.path}/${const Uuid().v4()}.png')
        .writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
  }

  /// A PNG copy also makes formats supported by the device's decoder usable
  /// by the model. An animated GIF or WebP gives frames spread over it.
  Future<LoadedFrames> _imageFrames(Uint8List bytes, int maxFrames) async {
    final probe = await ui.instantiateImageCodec(bytes, targetWidth: 2048, allowUpscaling: false);
    final total = probe.frameCount;
    if (total <= 1 || maxFrames <= 1) {
      try {
        final frame = await probe.getNextFrame();
        try {
          return LoadedFrames([LoadedImage(await _png(frame.image))], animated: total > 1, frameCount: total);
        } finally {
          frame.image.dispose();
        }
      } finally {
        probe.dispose();
      }
    }
    probe.dispose();
    // Frames are smaller: several go to the model at once.
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 768, allowUpscaling: false);
    try {
      final wanted = spreadFrames(total, maxFrames).toSet();
      final last = wanted.reduce((a, b) => a > b ? a : b);
      final images = <LoadedImage>[];
      var at = Duration.zero;
      for (var i = 0; i <= last; i++) {
        final frame = await codec.getNextFrame();
        try {
          if (wanted.contains(i)) images.add(LoadedImage(await _png(frame.image), at: at));
          at += frame.duration;
        } finally {
          frame.image.dispose();
        }
      }
      // The rest of the frames, only to know how long it runs.
      for (var i = last + 1; i < total && i < 2000; i++) {
        final frame = await codec.getNextFrame();
        at += frame.duration;
        frame.image.dispose();
      }
      return LoadedFrames(images, animated: true, duration: at, frameCount: total);
    } finally {
      codec.dispose();
    }
  }

  static const _device = MethodChannel('teleai/device');

  /// Stills of a short video, taken on the phone (Android).
  Future<LoadedFrames> _videoFrames(Uint8List bytes, int maxFrames) async {
    await directory.create(recursive: true);
    final video = File('${directory.path}/${const Uuid().v4()}.mp4');
    await video.writeAsBytes(bytes);
    try {
      final r = await _device.invokeMethod<Map>('imageOp', {
        'op': 'video_frames',
        'path': video.path,
        'out': directory.path,
        'count': maxFrames.clamp(1, 12),
        'max_width': maxFrames <= 1 ? 2048 : 768,
      });
      final frames = [
        for (final f in (r?['frames'] as List? ?? const []))
          if (f is Map)
            LoadedImage(File('${f['path']}'), at: Duration(milliseconds: (f['at_ms'] as num?)?.toInt() ?? 0)),
      ];
      if (frames.isEmpty) throw const FormatException('Could not read frames from this video.');
      final ms = (r?['duration_ms'] as num?)?.toInt();
      return LoadedFrames(frames, animated: true, duration: ms == null ? null : Duration(milliseconds: ms));
    } on PlatformException catch (e) {
      throw FormatException(e.message ?? 'Could not read frames from this video.');
    } on MissingPluginException {
      throw const FormatException('Reading video frames needs the Android app.');
    } finally {
      try {
        await video.delete();
      } catch (_) {}
    }
  }
}
