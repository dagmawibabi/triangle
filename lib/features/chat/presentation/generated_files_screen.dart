import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/files/download_progress.dart' show formatBytes;
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/net_image.dart';
import '../../library/library_favorites.dart';
import '../../media/audio_center.dart';
import '../../media/audio_player_ui.dart';
import '../../telegram/presentation/chat_actions.dart' show confirmAction;
import 'widgets/library_result_cards.dart' show EbookReader, showEpisode, showPodcast;

/// Where a file came from.
enum FileSource {
  generated('Made by AI', Icons.auto_awesome_outlined),
  sandbox('Code sandbox', Icons.terminal_rounded),
  downloads('Downloads', Icons.download_rounded),
  telegram('From Telegram', Icons.send_rounded),
  exports('Exports', Icons.ios_share_rounded),
  screenshots('Screenshots', Icons.screenshot_monitor_rounded);

  const FileSource(this.label, this.icon);
  final String label;
  final IconData icon;

}

enum _Kind {
  all('All', Icons.apps_rounded),
  images('Images', Icons.image_outlined),
  videos('Videos', Icons.movie_outlined),
  audio('Audio', Icons.graphic_eq_rounded),
  documents('Documents', Icons.description_outlined),
  books('Books', Icons.auto_stories_outlined),
  audiobooks('Audiobooks', Icons.headphones_outlined),
  podcasts('Podcasts', Icons.podcasts_rounded);

  bool get library => this == books || this == audiobooks || this == podcasts;

  /// What one file of this kind is called.
  String get single => switch (this) {
    all => 'File',
    images => 'Image',
    videos => 'Video',
    audio => 'Audio',
    documents => 'Document',
    books => 'Book',
    audiobooks => 'Audiobook chapter',
    podcasts => 'Podcast episode',
  };

  const _Kind(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _Sort {
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest first'),
  name('Name');

  const _Sort(this.label);
  final String label;
}

const _imageExt = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'bmp'};
const _videoExt = {'mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp'};
const _audioExt = {'mp3', 'm4a', 'wav', 'ogg', 'oga', 'opus', 'flac', 'aac'};

/// One file the app holds.
class _Entry {
  _Entry(this.file, this.source, this.modified, this.bytes, this.meta);
  final File file;
  final FileSource source;
  final DateTime modified;
  final int bytes;

  /// The file's sidecar: a generated file's prompt, model, voice; a
  /// download's title, author, cover and source link.
  final Map<String, dynamic> meta;

  String get name => file.path.split(RegExp(r'[\\/]')).last;
  String get ext => name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';

  /// Books, audiobook chapters and podcast episodes have tabs of their own.
  _Kind get kind => switch (meta['library']) {
    'book' => _Kind.books,
    'audiobook' => _Kind.audiobooks,
    'podcast' => _Kind.podcasts,
    _ => fileKind,
  };

  _Kind get fileKind => _imageExt.contains(ext)
      ? _Kind.images
      : _videoExt.contains(ext)
      ? _Kind.videos
      : _audioExt.contains(ext)
      ? _Kind.audio
      : _Kind.documents;

  /// What to call it: its title, the prompt that made it, or its name.
  String get title => '${meta['title'] ?? meta['prompt'] ?? meta['text'] ?? name}'.trim();

  String? get cover => meta['cover'] is String && '${meta['cover']}'.startsWith('http') ? '${meta['cover']}' : null;

  File get sidecar {
    final dot = file.path.lastIndexOf('.');
    return File('${dot < 0 ? file.path : file.path.substring(0, dot)}.meta.json');
  }
}

IconData _fileIcon(_Entry e) => switch (e.fileKind) {
  _Kind.images => Icons.image_outlined,
  _Kind.videos => Icons.movie_outlined,
  _Kind.audio => Icons.music_note_rounded,
  _ => switch (e.ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
    'html' || 'htm' => Icons.language_rounded,
    'md' || 'txt' => Icons.notes_rounded,
    'json' || 'csv' || 'xml' => Icons.data_object_rounded,
    'py' || 'js' || 'dart' || 'ts' => Icons.code_rounded,
    'epub' || 'mobi' => Icons.menu_book_outlined,
    'apk' => Icons.android_rounded,
    'doc' || 'docx' => Icons.article_outlined,
    'xls' || 'xlsx' => Icons.table_chart_outlined,
    'ppt' || 'pptx' => Icons.slideshow_outlined,
    _ => Icons.insert_drive_file_outlined,
  },
};

String _relativeTime(DateTime date) {
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays} d ago';
  return DateFormat(date.year == DateTime.now().year ? 'd MMM' : 'd MMM y').format(date);
}

/// Every file the app made or saved: images and audio the assistant
/// generated, the code sandbox's output, web, GitHub and book downloads,
/// screenshots and canvas exports. Searchable and sortable, as a list or a
/// grid on every tab, with each file's details and actions a tap away.
class GeneratedFilesScreen extends ConsumerStatefulWidget {
  const GeneratedFilesScreen({super.key});

  @override
  ConsumerState<GeneratedFilesScreen> createState() => _GeneratedFilesScreenState();
}

class _GeneratedFilesScreenState extends ConsumerState<GeneratedFilesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: _Kind.values.length, vsync: this)..addListener(() => setState(() {}));
  List<_Entry> _all = const [];
  bool _loading = true;
  final Set<FileSource> _sources = {...FileSource.values};
  String _query = '';
  bool _searching = false;
  _Sort _sort = _Sort.newest;

  /// Picked files, when choosing several.
  final Set<String> _picked = {};

  bool _grid = false;
  static const _gridKey = 'files_grid_view';
  static const _sortKey = 'files_sort';

  @override
  void initState() {
    super.initState();
    _load();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _grid = p.getBool(_gridKey) ?? false;
        _sort = _Sort.values.asNameMap()[p.getString(_sortKey)] ?? _Sort.newest;
      });
    }).ignore();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final root = (await getApplicationSupportDirectory()).path;
    // Only what the app and the assistant made or saved. Media opened while
    // reading Telegram stays in Telegram's own cache and isn't listed.
    final roots = <(String, FileSource, bool)>[
      ('$root/generated', FileSource.generated, false),
      ('$root/sandbox', FileSource.sandbox, true),
      ('$root/downloads', FileSource.downloads, true),
      ('$root/telegram', FileSource.telegram, true),
      ('$root/exports', FileSource.exports, false),
      ('$root/screenshots', FileSource.screenshots, false),
    ];
    final out = <_Entry>[];
    for (final (path, source, deep) in roots) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: deep, followLinks: false)) {
          if (e is! File) continue;
          final n = e.path.toLowerCase();
          // Sidecars, the sandbox's own scaffolding, and partial downloads.
          if (n.endsWith('.meta.json') || n.endsWith('.tmp') || n.endsWith('.part')) continue;
          if (source == FileSource.sandbox && n.endsWith('.html') && n.contains('runner')) continue;
          final stat = await e.stat();
          if (stat.size == 0) continue;
          var meta = const <String, dynamic>{};
          final dot = e.path.lastIndexOf('.');
          final side = File('${e.path.substring(0, dot < 0 ? e.path.length : dot)}.meta.json');
          if (await side.exists()) {
            try {
              final j = jsonDecode(await side.readAsString());
              if (j is Map) meta = Map<String, dynamic>.from(j);
            } catch (_) {}
          }
          out.add(_Entry(e, _sourceOf(source, e.path, meta), stat.modified, stat.size, meta));
        }
      } catch (e) {
        debugPrint('[Files] $path: $e');
      }
    }
    if (mounted) {
      setState(() {
        _all = out;
        _loading = false;
        _picked.removeWhere((p) => !out.any((e) => e.file.path == p));
      });
    }
  }

  /// Older versions saved downloads, Telegram media and sandbox output in
  /// the AI's folder too. Only media an AI model made (it has a sidecar
  /// naming what made it) counts as "Made by AI"; the rest goes where it
  /// came from.
  static FileSource _sourceOf(FileSource folder, String path, Map<String, dynamic> meta) {
    if (folder != FileSource.generated) return folder;
    final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1) : '';
    final media = _imageExt.contains(ext) || _videoExt.contains(ext) || _audioExt.contains(ext);
    final made = meta.containsKey('created_at') || meta.containsKey('provider') || meta.containsKey('prompt') || meta.containsKey('model');
    if (media && made && meta['library'] == null) return FileSource.generated;
    if (name.startsWith('e2b_')) return FileSource.sandbox;
    if (RegExp(r'^(photo|video|audio|voice|document|animation|sticker|video_note)-\d+').hasMatch(name)) return FileSource.telegram;
    return FileSource.downloads;
  }

  List<_Entry> _of(_Kind kind) {
    final q = _query.toLowerCase();
    final list = _all.where((e) {
      if (!_sources.contains(e.source)) return false;
      if (kind != _Kind.all && e.kind != kind) return false;
      return q.isEmpty || e.name.toLowerCase().contains(q) || e.title.toLowerCase().contains(q) || '${e.meta['subtitle'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case _Sort.oldest:
        list.sort((a, b) => a.modified.compareTo(b.modified));
      case _Sort.largest:
        list.sort((a, b) => b.bytes.compareTo(a.bytes));
      case _Sort.name:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  void _setGrid(bool v) {
    setState(() => _grid = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_gridKey, v)).ignore();
  }

  void _setSort(_Sort v) {
    setState(() => _sort = v);
    SharedPreferences.getInstance().then((p) => p.setString(_sortKey, v.name)).ignore();
  }

  void _toggle(_Entry e) => setState(() => _picked.contains(e.file.path) ? _picked.remove(e.file.path) : _picked.add(e.file.path));

  Future<void> _delete(List<_Entry> entries) async {
    final deletable = entries;
    if (deletable.isEmpty) return;
    final size = deletable.fold<int>(0, (n, e) => n + e.bytes);
    if (!await confirmAction(
      context,
      title: deletable.length == 1 ? 'Delete ${deletable.first.name}?' : 'Delete ${deletable.length} files?',
      message: '${formatBytes(size)} is removed from this phone.',
      action: 'Delete',
    )) {
      return;
    }
    var failed = 0;
    for (final e in deletable) {
      try {
        await e.file.delete();
        if (await e.sidecar.exists()) await e.sidecar.delete();
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      showSnack(context, failed == 0 ? 'Deleted ${deletable.length == 1 ? deletable.first.name : '${deletable.length} files'}' : 'Couldn\'t delete $failed file${failed == 1 ? '' : 's'}', icon: failed == 0 ? Icons.delete_outline_rounded : Icons.error_outline_rounded);
    }
    _picked.clear();
    await _load();
  }

  Future<void> _rename(_Entry e) async {
    final dot = e.name.lastIndexOf('.');
    final base = dot < 0 ? e.name : e.name.substring(0, dot);
    final c = TextEditingController(text: base);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(suffixText: dot < 0 ? null : '.${e.ext}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (v == null || v.isEmpty || v == base) return;
    final clean = v.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dir = e.file.parent.path;
    final target = File('$dir${Platform.pathSeparator}$clean${dot < 0 ? '' : '.${e.ext}'}');
    if (await target.exists()) {
      if (mounted) showSnack(context, 'A file with that name already exists', icon: Icons.error_outline_rounded);
      return;
    }
    try {
      final side = e.sidecar;
      await e.file.rename(target.path);
      if (await side.exists()) await side.rename('$dir${Platform.pathSeparator}$clean.meta.json');
    } catch (err) {
      if (mounted) showSnack(context, 'Couldn\'t rename: $err', icon: Icons.error_outline_rounded);
    }
    await _load();
  }

  /// Everything about one file, with what can be done to it.
  Future<void> _details(_Entry e) async {
    final action = await showAppSheet<String>(
      context,
      initialSize: 0.75,
      builder: (context, scroll) => _DetailsSheet(entry: e, scroll: scroll),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        _open(e);
      case 'rename':
        await _rename(e);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e.file.path));
        if (mounted) showSnack(context, 'Path copied');
      case 'delete':
        await _delete([e]);
    }
  }

  void _open(_Entry e) {
    if (e.fileKind == _Kind.images) {
      final images = _of(_Kind.images);
      final at = images.indexWhere((x) => x.file.path == e.file.path);
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ImageViewer(images: images.isEmpty ? [e] : images, start: at < 0 ? 0 : at, onDetails: _details)));
      return;
    }
    if (e.ext == 'txt' && e.kind == _Kind.books) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EbookReader(title: e.title, textUrl: Uri.file(e.file.path).toString())));
      return;
    }
    if (e.fileKind == _Kind.audio) {
      final same = [for (final x in _of(e.kind == _Kind.audio ? _Kind.audio : e.kind)) if (x.fileKind == _Kind.audio) x];
      Track track(_Entry x) => Track(
        chatId: 0,
        messageId: 0,
        localPath: x.file.path,
        identifier: 'file:${x.file.path}',
        title: x.title,
        subtitle: '${x.meta['subtitle'] ?? x.source.label}',
        seconds: 0,
        voice: x.meta['voice'] == true,
        artUrl: x.cover,
      );
      unawaited(ref.read(audioCenterProvider).play(track(e), playlist: [for (final x in same) track(x)]));
      showAudioPlayer(context);
      return;
    }
    OpenFilex.open(e.file.path);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _Kind.values[_tabs.index];
    final visible = _of(_Kind.all);
    final picking = _picked.isNotEmpty;
    final pickedEntries = _all.where((e) => _picked.contains(e.file.path)).toList();
    return PopScope(
      canPop: !picking,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && picking) setState(_picked.clear);
      },
      child: Scaffold(
        appBar: picking
            ? AppBar(
                leading: IconButton(tooltip: 'Done', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_picked.clear)),
                title: Text('${_picked.length} selected · ${formatBytes(pickedEntries.fold<int>(0, (n, e) => n + e.bytes))}'),
                actions: [
                  IconButton(
                    tooltip: 'Select all here',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => setState(() => _picked.addAll(_of(kind).map((e) => e.file.path))),
                  ),
                  IconButton(
                    tooltip: 'Copy paths',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: pickedEntries.map((e) => e.file.path).join('\n')));
                      showSnack(context, 'Copied ${pickedEntries.length} paths');
                    },
                  ),
                  IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger), onPressed: () => _delete(pickedEntries)),
                ],
              )
            : AppBar(
                title: _searching
                    ? TextField(
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Search files', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      )
                    : const Text('Files'),
                actions: [
                  IconButton(
                    tooltip: _searching ? 'Close search' : 'Search',
                    icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _query = '';
                    }),
                  ),
                  IconButton(
                    tooltip: _grid ? 'Show as a list' : 'Show as a grid',
                    icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                    onPressed: () => _setGrid(!_grid),
                  ),
                  PopupMenuButton<Object>(
                    tooltip: 'Sort and filter',
                    icon: const Icon(Icons.tune_rounded),
                    onSelected: (v) {
                      if (v is _Sort) _setSort(v);
                      if (v is FileSource) setState(() => _sources.contains(v) ? _sources.remove(v) : _sources.add(v));
                      if (v == 'refresh') {
                        setState(() => _loading = true);
                        _load();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(enabled: false, height: 32, child: Text('SORT')),
                      for (final s in _Sort.values) CheckedPopupMenuItem(value: s, checked: _sort == s, child: Text(s.label)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(enabled: false, height: 32, child: Text('SHOW FILES FROM')),
                      for (final s in FileSource.values)
                        if (_all.any((e) => e.source == s)) CheckedPopupMenuItem(value: s, checked: _sources.contains(s), child: Text('${s.label} · ${_all.where((e) => e.source == s).length}')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                    ],
                  ),
                ],
              ),
        body: _loading
            ? const _LoadingFiles()
            : Column(
                children: [
                  if (!picking) _StorageSummary(entries: visible, onKind: (k) => _tabs.animateTo(k.index)),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
                      children: [
                        for (final k in _Kind.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _KindPill(kind: k, count: _of(k).length, selected: _tabs.index == k.index, onTap: () => _tabs.animateTo(k.index)),
                          ),
                      ],
                    ),
                  ),
                  if (_query.isNotEmpty || _sources.length < FileSource.values.length || _sort != _Sort.newest)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                if (_query.isNotEmpty) '"$_query"',
                                if (_sources.length < FileSource.values.length) '${_sources.length} sources',
                                _sort.label.toLowerCase(),
                              ].join(' · '),
                              style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                            ),
                          ),
                          if (_sources.length < FileSource.values.length)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => setState(() => _sources.addAll(FileSource.values)),
                              child: const Text('Show all sources'),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          for (final k in _Kind.values)
                            _FilesView(
                              kind: k,
                              entries: _of(k),
                              grid: _grid,
                              picked: _picked,
                              picking: picking,
                              onTap: (e) => picking ? _toggle(e) : _open(e),
                              onLongPress: _toggle,
                              onMore: _details,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LoadingFiles extends StatelessWidget {
  const _LoadingFiles();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Space.l),
    children: [
      const Skeleton(height: 96, radius: 18),
      const SizedBox(height: Space.l),
      for (var i = 0; i < 6; i++) ...[
        const Row(children: [Skeleton(width: 48, height: 48, radius: 12), SizedBox(width: Space.m), Expanded(child: Skeleton(height: 14, radius: 6))]),
        const SizedBox(height: Space.m),
      ],
    ],
  );
}

/// The total and a bar of what takes the space, by kind; tap a kind to go
/// to its tab.
/// The [i]th biggest kind's tone in the storage bar: the text colour,
/// fading down the ranks.
Color _shade(int i) => AppColors.text.withValues(alpha: const [1.0, 0.62, 0.4, 0.26, 0.17, 0.12, 0.09][i.clamp(0, 6)]);

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.entries, required this.onKind});
  final List<_Entry> entries;
  final ValueChanged<_Kind> onKind;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (n, e) => n + e.bytes);
    final byKind = <_Kind, int>{};
    for (final e in entries) {
      byKind[e.kind] = (byKind[e.kind] ?? 0) + e.bytes;
    }
    final kinds = byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatBytes(total), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(width: Space.s),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('in ${entries.length} files', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: total == 0
                  ? Container(color: AppColors.surface3)
                  : Row(
                      children: [
                        for (final (i, k) in kinds.indexed)
                          Expanded(flex: (k.value * 1000 / total).ceil().clamp(1, 1000), child: Container(margin: const EdgeInsets.only(right: 2), color: _shade(i))),
                      ],
                    ),
            ),
          ),
          if (kinds.isNotEmpty) ...[
            const SizedBox(height: Space.s + 2),
            Wrap(
              spacing: Space.m,
              runSpacing: 4,
              children: [
                for (final (i, k) in kinds.take(5).indexed)
                  GestureDetector(
                    onTap: () => onKind(k.key),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _shade(i), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 5),
                        Text('${k.key.label} ${formatBytes(k.value)}', style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind, required this.count, required this.selected, required this.onTap});
  final _Kind kind;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.text : AppColors.surface2,
    shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.text : AppColors.line)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.icon, size: 15, color: selected ? AppColors.bg : AppColors.text2),
            const SizedBox(width: 5),
            Text(kind.label, style: context.text.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.bg : AppColors.text)),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text('$count', style: context.text.labelSmall?.copyWith(color: selected ? AppColors.bg.withValues(alpha: 0.65) : AppColors.text3, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The picture for a file: its image, its cover, or its type on its colour
/// with the extension.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry, required this.size, this.radius = Radii.m, this.fill = false});
  final _Entry entry;
  final double size;
  final double radius;

  /// Fill the space given rather than a [size] square.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    Widget box(Widget child) => fill ? child : SizedBox(width: size, height: size, child: child);
    if (e.fileKind == _Kind.images) {
      return box(
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(
            e.file,
            fit: BoxFit.cover,
            cacheWidth: fill ? 400 : (size * 3).round(),
            errorBuilder: (_, _, _) => Container(color: AppColors.surface2, child: Icon(Icons.broken_image_outlined, color: AppColors.text3)),
          ),
        ),
      );
    }
    if (e.cover != null) return box(NetImage(e.cover, fit: BoxFit.cover, radius: radius, placeholder: e.kind.icon));
    return box(
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(
          children: [
            Center(child: Icon(_fileIcon(e), color: AppColors.text2, size: fill ? 34 : size * 0.44)),
            if (e.ext.isNotEmpty && (fill || size >= 44))
              Positioned(
                left: 0,
                right: 0,
                bottom: fill ? 10 : 3,
                child: Text(
                  e.ext.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(fontSize: fill ? 11 : 8.5, fontWeight: FontWeight.w800, color: AppColors.text3, letterSpacing: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tab: its files as a list (grouped by day) or a grid, plus the
/// podcast favourites on Podcasts.
class _FilesView extends ConsumerWidget {
  const _FilesView({
    required this.kind,
    required this.entries,
    required this.grid,
    required this.picked,
    required this.picking,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });
  final _Kind kind;
  final List<_Entry> entries;
  final bool grid;
  final Set<String> picked;
  final bool picking;
  final void Function(_Entry) onTap;
  final void Function(_Entry) onLongPress;
  final void Function(_Entry) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = kind == _Kind.podcasts ? ref.watch(libraryFavoritesProvider) : const LibraryFavorites();
    final favourites = kind == _Kind.podcasts && (favs.shows.isNotEmpty || favs.episodes.isNotEmpty);
    if (entries.isEmpty && !favourites) return _Empty(kind: kind);
    final header = <Widget>[if (favourites) _PodcastFavourites(favs: favs)];
    if (grid) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList(delegate: SliverChildListDelegate(header)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: kind == _Kind.images || kind == _Kind.videos ? 140 : 180,
                mainAxisSpacing: Space.s,
                crossAxisSpacing: Space.s,
                // Books stand tall; pictures are square; other files have a caption.
                childAspectRatio: kind == _Kind.books ? 0.58 : (kind == _Kind.images ? 1 : 0.78),
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _GridTile(entry: entries[i], picked: picked.contains(entries[i].file.path), picking: picking, onTap: onTap, onLongPress: onLongPress, onMore: onMore),
                childCount: entries.length,
              ),
            ),
          ),
        ],
      );
    }
    // A list, under day headings.
    final rows = <Widget>[...header];
    String? day;
    for (final e in entries) {
      final d = _dayHeading(e.modified);
      if (d != day) {
        day = d;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.xs),
            child: Text(d.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          ),
        );
      }
      rows.add(_ListRow(entry: e, picked: picked.contains(e.file.path), picking: picking, onTap: onTap, onLongPress: onLongPress, onMore: onMore));
    }
    return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(bottom: Space.x4), children: rows);
  }

  static String _dayHeading(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (today.difference(d).inDays < 7) return 'This week';
    if (t.year == now.year && t.month == now.month) return 'This month';
    return DateFormat(t.year == now.year ? 'MMMM' : 'MMMM y').format(t);
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? AppColors.text : Colors.black.withValues(alpha: 0.35),
      border: Border.all(color: on ? AppColors.text : Colors.white.withValues(alpha: 0.8), width: 1.5),
    ),
    child: on ? Icon(Icons.check_rounded, size: 15, color: AppColors.bg) : null,
  );
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.entry, required this.picked, required this.picking, required this.onTap, required this.onLongPress, required this.onMore});
  final _Entry entry;
  final bool picked;
  final bool picking;
  final void Function(_Entry) onTap;
  final void Function(_Entry) onLongPress;
  final void Function(_Entry) onMore;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final sub = [
      if (e.meta['subtitle'] != null) '${e.meta['subtitle']}',
      if (e.ext.isNotEmpty) e.ext.toUpperCase(),
      formatBytes(e.bytes),
      _relativeTime(e.modified),
    ].join(' · ');
    return Material(
      color: picked ? AppColors.text.withValues(alpha: 0.07) : Colors.transparent,
      child: InkWell(
        onTap: () => onTap(e),
        onLongPress: () => onLongPress(e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _Thumb(entry: e, size: 48, radius: Radii.m),
                  if (picking) Positioned(right: -4, top: -4, child: _Check(on: picked)),
                ],
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(e.source.icon, size: 12, color: AppColors.text3),
                        const SizedBox(width: 4),
                        Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Details',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert_rounded, size: 20, color: AppColors.text3),
                onPressed: () => onMore(e),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.entry, required this.picked, required this.picking, required this.onTap, required this.onLongPress, required this.onMore});
  final _Entry entry;
  final bool picked;
  final bool picking;
  final void Function(_Entry) onTap;
  final void Function(_Entry) onLongPress;
  final void Function(_Entry) onMore;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final picture = e.fileKind == _Kind.images;
    return GestureDetector(
      onTap: () => onTap(e),
      onLongPress: () => onLongPress(e),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(picked ? 4 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: picked ? AppColors.text : Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Thumb(entry: e, size: 0, fill: true, radius: Radii.m),
                  if (picture || e.cover != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                        child: Text(formatBytes(e.bytes), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: picking
                        ? _Check(on: picked)
                        : GestureDetector(
                            onTap: () => onMore(e),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                              child: const Icon(Icons.more_horiz_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (!picture) ...[
              const SizedBox(height: 6),
              Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
              Text('${e.cover == null ? '${formatBytes(e.bytes)} · ' : ''}${_relativeTime(e.modified)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.kind});
  final _Kind kind;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4 * 2, Space.x4, Space.x4),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
              child: Icon(kind.icon, size: 30, color: AppColors.text2),
            ),
            const SizedBox(height: Space.l),
            Text(kind == _Kind.all ? 'No files yet' : 'No ${kind.label.toLowerCase()} yet', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Space.s),
            Text(
              switch (kind) {
                _Kind.books => 'Ask for a free ebook and download it as EPUB or Kindle to keep it here.',
                _Kind.audiobooks => 'Download chapters from an audiobook\'s sheet to listen offline.',
                _Kind.podcasts => 'Download episodes, or tap the heart on a show or episode to keep it here.',
                _ => 'Images and audio the assistant makes, code output, downloads, exports and screenshots appear here.',
              },
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The favourite podcast shows and episodes, above the downloads.
class _PodcastFavourites extends ConsumerWidget {
  const _PodcastFavourites({required this.favs});
  final LibraryFavorites favs;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (favs.shows.isNotEmpty) ...[
          Text('FAVOURITE SHOWS', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          const SizedBox(height: Space.s),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favs.shows.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.m),
              itemBuilder: (context, i) {
                final show = favs.shows[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: () => showPodcast(context, show),
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NetImage('${show['cover'] ?? ''}', width: 100, height: 100, radius: Radii.m, placeholder: Icons.podcasts_rounded),
                        const SizedBox(height: 4),
                        Text('${show['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Space.l),
        ],
        if (favs.episodes.isNotEmpty) ...[
          Text('FAVOURITE EPISODES', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          for (final ep in favs.episodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: NetImage('${ep['image'] ?? ep['show_cover'] ?? ''}', width: 48, height: 48, radius: Radii.s, placeholder: Icons.podcasts_rounded),
              title: Text('${ep['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([ep['show'], ep['published']].where((x) => x != null).join(' · '), style: context.text.bodySmall),
              trailing: IconButton(
                tooltip: 'Remove from favourites',
                icon: Icon(Icons.favorite_rounded, color: AppColors.text),
                onPressed: () => ref.read(libraryFavoritesProvider.notifier).toggleEpisode(ep),
              ),
              onTap: () {
                final t = Track.stream(
                  url: '${ep['audio']}',
                  title: '${ep['title']}',
                  subtitle: '${ep['show'] ?? ''}',
                  artUrl: (ep['image'] ?? ep['show_cover']) as String?,
                  seconds: (ep['seconds'] as int?) ?? 0,
                );
                showEpisode(context, ep, track: t, show: '${ep['show'] ?? ''}', showCover: ep['show_cover'] as String?, feed: '${ep['feed'] ?? ''}');
              },
            ),
          const SizedBox(height: Space.m),
        ],
        Text('DOWNLOADED', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// A file's sheet: a preview, every detail, and its actions. Returns the
/// action picked: open, rename, copy or delete.
class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.entry, required this.scroll});
  final _Entry entry;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final m = e.meta;
    final rows = <(String, String, bool)>[
      ('Kind', '${e.kind.single}${e.ext.isEmpty ? '' : ' · ${e.ext.toUpperCase()}'}', false),
      ('Size', '${formatBytes(e.bytes)} (${NumberFormatter.thousands(e.bytes)} bytes)', false),
      ('From', e.source.label, false),
      ('Saved', DateFormat('EEE d MMM y, HH:mm').format(e.modified), false),
      if (m['subtitle'] != null) ('By', '${m['subtitle']}', false),
      if (m['prompt'] != null) ('Prompt', '${m['prompt']}', true),
      if (m['text'] != null && m['prompt'] == null) ('Text', '${m['text']}', true),
      if (m['model'] != null) ('Model', '${m['model']}', false),
      if (m['voice'] is String) ('Voice', '${m['voice']}', false),
      if (m['source_url'] != null) ('Link', '${m['source_url']}', true),
      ('Location', e.file.path, true),
    ];
    Widget action(IconData icon, String label, String value, {Color? color}) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: (color ?? AppColors.text).withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: color ?? AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(label, style: context.text.labelSmall?.copyWith(color: color ?? AppColors.text2)),
            ],
          ),
        ),
      ),
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
            child: e.fileKind == _Kind.images
                ? ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: Image.file(e.file, fit: BoxFit.contain, cacheWidth: 900))
                : _Thumb(entry: e, size: e.kind == _Kind.books ? 120 : 96, radius: Radii.l),
          ),
        ),
        const SizedBox(height: Space.l),
        Text(e.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (e.title != e.name) Text(e.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        const SizedBox(height: Space.l),
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(
            children: [
              action(Icons.open_in_new_rounded, 'Open', 'open'),
              action(Icons.drive_file_rename_outline_rounded, 'Rename', 'rename'),
              action(Icons.copy_rounded, 'Copy path', 'copy'),
              action(Icons.delete_outline_rounded, 'Delete', 'delete', color: AppColors.danger),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        Container(
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: Space.l, endIndent: Space.l, color: AppColors.line),
                InkWell(
                  onTap: rows[i].$3
                      ? () {
                          final v = rows[i].$2;
                          if (rows[i].$1 == 'Link') {
                            launchUrl(Uri.parse(v), mode: LaunchMode.externalApplication);
                          } else {
                            Clipboard.setData(ClipboardData(text: v));
                            showSnack(context, '${rows[i].$1} copied');
                          }
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 78, child: Text(rows[i].$1, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
                        Expanded(child: Text(rows[i].$2, maxLines: rows[i].$1 == 'Prompt' || rows[i].$1 == 'Text' ? 6 : 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
                        if (rows[i].$3) ...[
                          const SizedBox(width: 6),
                          Icon(rows[i].$1 == 'Link' ? Icons.open_in_new_rounded : Icons.copy_rounded, size: 14, color: AppColors.text3),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Thousands separators without pulling a locale in.
abstract final class NumberFormatter {
  static String thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// Pictures full screen, swiping between them, with each one's details.
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.images, required this.start, required this.onDetails});
  final List<_Entry> images;
  final int start;
  final Future<void> Function(_Entry) onDetails;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late int _at = widget.start;
  late final _pages = PageController(initialPage: widget.start);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.images[_at];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16)),
            Text('${_at + 1} of ${widget.images.length} · ${formatBytes(e.bytes)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Details', icon: const Icon(Icons.info_outline_rounded), onPressed: () => widget.onDetails(e)),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _at = i),
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 6, child: Center(child: Image.file(widget.images[i].file))),
      ),
    );
  }
}
