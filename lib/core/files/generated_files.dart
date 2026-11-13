import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The folder for media the assistant generates (images, video, speech),
/// which Files lists as "Made by AI". Other saved files go in their own
/// folder: see [uniqueGeneratedFile]'s `folder`.
Future<Directory> generatedDir({String folder = 'generated'}) async =>
    Directory('${(await getApplicationSupportDirectory()).path}/$folder').create(recursive: true);

/// [name] made safe as a file name: only characters a file name can't hold
/// (path separators, `:*?"<>|` and control characters) are replaced, so
/// names in any script (Amharic, Arabic…) stay as they are.
String safeFileName(String name, {String fallback = 'file'}) {
  final base = name.split(RegExp(r'[\\/]')).last.trim();
  final safe = base.replaceAll(RegExp(r'[:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'^\.+'), '').trim();
  return safe.isEmpty ? fallback : safe;
}

/// A new file in [dir] named [name], or `name (2).ext`, `name (3).ext`… when
/// that is taken, like a browser's downloads. Two downloads of `report.pdf`
/// stay two files, and a file an earlier chat points to is never replaced.
/// The file is created empty at once, so two saves at the same time can't
/// pick the same name.
Future<File> claimFile(Directory dir, String name) async {
  await dir.create(recursive: true);
  final base = safeFileName(name);
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot) : '';
  for (var n = 1; ; n++) {
    final file = File('${dir.path}/${n == 1 ? stem : '$stem ($n)'}$ext');
    try {
      await file.create(exclusive: true);
      return file;
    } on FileSystemException {
      if (!await file.exists()) rethrow;
    }
  }
}

/// A new file in [generatedDir] that never replaces an earlier one: [name]
/// as it is, numbered only when taken (see [claimFile]).
///
/// [folder] is where it goes under the app's files: `generated` for media
/// the AI made, `downloads` for downloads, `telegram` for media saved from
/// chats, `sandbox` for code output, `exports` for bundles.
Future<File> uniqueGeneratedFile(String name, {String folder = 'generated'}) async =>
    claimFile(await generatedDir(folder: folder), name);

/// Writes [bytes] to a [uniqueGeneratedFile] named after [name].
Future<File> saveGeneratedBytes(String name, List<int> bytes, {String folder = 'generated'}) async =>
    (await uniqueGeneratedFile(name, folder: folder)).writeAsBytes(bytes);
