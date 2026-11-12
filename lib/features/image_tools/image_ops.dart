import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/files/generated_files.dart';
import '../device/device.dart';

// The image tools (ImageOps.kt): details, resize, crop, compress, convert
// and background removal, all on the phone. Results are new files under
// the app's "images" folder; the original is never changed.

const _channel = MethodChannel('teleai/device');

const imageFormats = ['jpeg', 'png', 'webp'];

String _ext(String format) => format == 'jpeg' ? 'jpg' : format;

/// Runs [op] on the picture at [path]. [args] are the operation's options.
Future<Map<String, dynamic>> runImageOp(String op, String path, Map<String, dynamic> args, {String suffix = 'edited'}) async {
  if (!Device.supported) throw DeviceException('The image tools work in the Android app.');
  if (!File(path).existsSync()) throw DeviceException('That picture isn\'t on this phone any more.');
  String? out;
  if (op != 'info') {
    final format = '${args['format'] ?? ''}'.isNotEmpty
        ? '${args['format']}'
        : op == 'remove_background' && '${args['background'] ?? 'transparent'}' == 'transparent'
        ? 'png'
        : _formatFromPath(path);
    final stem = path.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'^[0-9a-f]{8}_|_[0-9a-f]{8}$'), '').replaceAll(RegExp(r'(_(resized|cropped|compressed|converted|cutout))+$'), '');
    final f = await uniqueGeneratedFile('${stem}_$suffix.${_ext(format == 'jpg' ? 'jpeg' : format)}', folder: 'images');
    out = f.path;
  }
  try {
    final r = await _channel.invokeMethod<Map>('imageOp', {...args, 'op': op, 'path': path, 'out': ?out});
    return Device.map(r);
  } on PlatformException catch (e) {
    if (out != null) {
      try {
        File(out).deleteSync();
      } catch (_) {}
    }
    throw DeviceException(e.message ?? e.code);
  } on MissingPluginException {
    throw DeviceException('The image tools need the Android app.');
  }
}

String _formatFromPath(String path) => switch (path.split('.').last.toLowerCase()) {
  'png' => 'png',
  'webp' => 'webp',
  _ => 'jpeg',
};

String imageMime(String format) => switch (format) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};
