import 'dart:io';

import 'package:mime/mime.dart' show lookupMimeType;
import 'package:path_provider/path_provider.dart';

// The files the app keeps (downloads, Telegram media saved from chats, what
// the assistant made, code output, exports, screenshots, edited images and
// attachments), for the list_files and read_file tools and for finding a
// file by name in any conversation. Only the app's own folders: never
// anywhere else on the phone.

/// A folder of saved files, as the tools name it, and whether files sit in
/// subfolders.
const appFileFolders = <String, bool>{
  'downloads': true,
  'telegram': true,
  'generated': false,
  'sandbox': true,
  'exports': false,
  'screenshots': false,
  'images': false,
  'attachments': false,
};

/// One saved file.
class AppFile {
  const AppFile({required this.file, required this.folder, required this.size, required this.modified});
  final File file;
  final String folder;
  final int size;
  final DateTime modified;

  String get path => file.path;
  String get name => file.uri.pathSegments.last;
  String get mime => lookupMimeType(path) ?? 'application/octet-stream';

  /// image, video, audio, pdf, text, document, archive or other.
  String get kind => fileKind(path);

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'folder': folder,
        'type': kind,
        'size_kb': (size / 1024).ceil(),
        'modified': modified.toIso8601String().substring(0, 16),
      };
}

const _textExtensions = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'jsonl', 'xml', 'html', 'htm', 'yaml', 'yml', 'toml', 'ini', 'log',
  'srt', 'vtt', 'py', 'js', 'ts', 'dart', 'java', 'kt', 'c', 'cpp', 'h', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'sql', 'css',
};

/// What kind of file [path] is: image, video, audio, pdf, text, document,
/// archive or other.
String fileKind(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  final mime = lookupMimeType(path) ?? '';
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'audio';
  if (ext == 'pdf') return 'pdf';
  if (mime.startsWith('text/') || _textExtensions.contains(ext)) return 'text';
  if (const {'doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp', 'epub'}.contains(ext)) return 'document';
  if (const {'zip', 'rar', '7z', 'tar', 'gz', 'tgz'}.contains(ext)) return 'archive';
  return 'other';
}

/// The folder all the app's files live under.
Future<String> appFilesRoot() async => (await getApplicationSupportDirectory()).path;

bool _skip(String path) {
  final n = path.toLowerCase();
  return n.endsWith('.meta.json') || n.endsWith('.tmp') || n.endsWith('.part');
}

/// The app's saved files under [root], newest first: in [folder] only when
/// given, and with every word of [query] in the name when given.
List<AppFile> listAppFilesSync(String root, {String? folder, String? query}) {
  final words = (query ?? '').toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <AppFile>[];
  for (final e in appFileFolders.entries) {
    if (folder != null && folder.isNotEmpty && folder != e.key) continue;
    final dir = Directory('$root/${e.key}');
    if (!dir.existsSync()) continue;
    try {
      for (final f in dir.listSync(recursive: e.value, followLinks: false)) {
        if (f is! File || _skip(f.path)) continue;
        final name = f.uri.pathSegments.last.toLowerCase();
        if (!words.every(name.contains)) continue;
        final stat = f.statSync();
        if (stat.size == 0) continue;
        out.add(AppFile(file: f, folder: e.key, size: stat.size, modified: stat.modified));
      }
    } catch (_) {}
  }
  out.sort((a, b) => b.modified.compareTo(a.modified));
  return out;
}

Future<List<AppFile>> listAppFiles({String? folder, String? query}) async =>
    listAppFilesSync(await appFilesRoot(), folder: folder, query: query);

/// The saved file [nameOrPath] stands for under [root]: that path when it is
/// one of the app's files, else the newest file with exactly that name, else
/// the newest whose name contains it. Null when none.
AppFile? findAppFileSync(String root, String nameOrPath) {
  final want = nameOrPath.trim();
  if (want.isEmpty) return null;
  final all = listAppFilesSync(root);
  final byPath = all.where((f) => f.path == want).firstOrNull;
  if (byPath != null) return byPath;
  final lower = want.split(RegExp(r'[\\/]')).last.toLowerCase();
  return all.where((f) => f.name.toLowerCase() == lower).firstOrNull ??
      all.where((f) => f.name.toLowerCase().contains(lower)).firstOrNull;
}
