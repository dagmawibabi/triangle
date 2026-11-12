import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// The folder for media the assistant generates (images, video, speech),
/// which Files lists as "Made by AI". Other saved files go in their own
/// folder: see [uniqueGeneratedFile]'s `folder`.
Future<Directory> generatedDir({String folder = 'generated'}) async =>
    Directory('${(await getApplicationSupportDirectory()).path}/$folder').create(recursive: true);

/// A new file in [generatedDir] that never replaces an earlier one: [name]
/// keeps its readable stem and extension, plus a short random suffix, so
/// two downloads of `report.pdf` stay two files.
///
/// [folder] is where it goes under the app's files: `generated` for media
/// the AI made, `downloads` for downloads, `telegram` for media saved from
/// chats, `sandbox` for code output, `exports` for bundles.
Future<File> uniqueGeneratedFile(String name, {String folder = 'generated'}) async {
  final dir = await generatedDir(folder: folder);
  final base = name.split(RegExp(r'[\\/]')).last.trim();
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base).replaceAll(RegExp(r'[^\w\-. ]'), '_');
  final ext = dot > 0 ? base.substring(dot) : '';
  final id = const Uuid().v4().substring(0, 8);
  return File('${dir.path}/${stem.isEmpty ? 'file' : stem}_$id$ext');
}

/// Writes [bytes] to a [uniqueGeneratedFile] named after [name].
Future<File> saveGeneratedBytes(String name, List<int> bytes, {String folder = 'generated'}) async =>
    (await uniqueGeneratedFile(name, folder: folder)).writeAsBytes(bytes);
