import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../library/library_api.dart';
import '../../../library/library_favorites.dart';
import '../../../media/audio_center.dart';
import '../../domain/chat_models.dart';

/// Cards for the free books, audiobooks, radio and podcast tools. Each card
/// opens a sheet that keeps going on its own: an ebook reads in the app or
/// downloads, an audiobook's chapters and a show's episodes load and play,
/// stations play at a tap. Null for other tools.
Widget? libraryResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'ebook_search' when list(j['books']).isNotEmpty => _EbookShelf(books: list(j['books']), total: (j['total'] as num?)?.toInt()),
    'ebook_details' when j['title'] != null => _EbookShelf(books: [j]),
    'book_search' when list(j['books']).isNotEmpty => _CatalogueList(query: '${j['query'] ?? ''}', books: list(j['books'])),
    'ebook_download' || 'audio_download' when j['file'] != null => _FileCard(data: j, ebook: part.name == 'ebook_download'),
    'audiobook_search' when list(j['audiobooks']).isNotEmpty => _AudiobookList(books: list(j['audiobooks'])),
    'audiobook_chapters' when list(j['chapters']).isNotEmpty => _ChapterList(data: j, chapters: list(j['chapters'])),
    'radio_search' when list(j['stations']).isNotEmpty => _StationList(stations: list(j['stations'])),
    'podcast_search' || 'podcast_top' when list(j['shows']).isNotEmpty => _ShowStrip(
      title: part.name == 'podcast_top' ? 'Top podcasts · ${'${j['country'] ?? 'us'}'.toUpperCase()}' : 'Podcasts · "${j['query']}"',
      shows: list(j['shows']),
    ),
    'podcast_episodes' when list(j['episodes']).isNotEmpty => _EpisodeCard(show: j, episodes: list(j['episodes'])),
    'play_audio' when j['playing'] == true => const _NowPlayingCard(),
    _ => null,
  };
}

/// Icons and highlights follow the app's monochrome look.
Color get _ink => AppColors.text2;

String _len(Object? seconds) {
  final s = seconds is num ? seconds.toInt() : 0;
  if (s <= 0) return '';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String _n(Object? v) => v is num ? NumberFormat.compact().format(v) : '';

String _authors(Map b) => (b['authors'] as List? ?? const []).whereType<Map>().map((a) => '${a['name']}').where((s) => s.isNotEmpty).join(', ');

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

String _flag(Object? code) {
  final c = '${code ?? ''}'.toUpperCase();
  if (c.length != 2) return '';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 65));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.children, this.trailing});
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              Icon(icon, size: 16, color: _ink),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
              ?trailing,
            ],
          ),
        ),
        ...children,
        const SizedBox(height: Space.xs),
      ],
    ),
  );
}

/// A cover picture with a fallback tile.
class _Cover extends StatelessWidget {
  const _Cover(this.url, {this.width = 56, this.height = 80, this.icon = Icons.menu_book_rounded, this.radius = Radii.s});
  final Object? url;
  final double width;
  final double height;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_ink.withValues(alpha: 0.35), AppColors.surface2]),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: AppColors.text2, size: width * 0.4),
    );
    final u = url;
    if (u is! String || u.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: NetImage(u, width: width, height: height, fit: BoxFit.cover, errorWidget: fallback),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: AppColors.text2), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11, color: AppColors.text2)),
      ],
    ),
  );
}

// ---- playing ---------------------------------------------------------------------------

/// Plays [track] in the app's player, with [queue] after it.
void _play(WidgetRef ref, BuildContext context, Track track, {List<Track>? queue}) {
  unawaited(ref.read(audioCenterProvider).play(track, playlist: queue));
}

/// A play / pause button for one stream.
class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.track, this.queue, this.size = 40, this.onPlay});
  final Track track;
  final List<Track>? queue;
  final double size;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final mine = a.current?.key == track.key;
    return SizedBox.square(
      dimension: size,
      child: IconButton.filled(
        style: IconButton.styleFrom(backgroundColor: mine ? AppColors.text : AppColors.surface2, foregroundColor: mine ? AppColors.bg : AppColors.text),
        padding: EdgeInsets.zero,
        iconSize: size * 0.55,
        tooltip: mine && a.playing ? 'Pause' : 'Play',
        onPressed: () {
          onPlay?.call();
          _play(ref, context, track, queue: queue);
        },
        icon: mine && a.loading
            ? SizedBox.square(dimension: size * 0.4, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg))
            : Icon(mine && a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}

class _NowPlayingCard extends ConsumerWidget {
  const _NowPlayingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    if (t == null) return const SizedBox.shrink();
    return _Panel(
      icon: t.live ? Icons.radio_rounded : Icons.headphones_rounded,
      title: t.live ? 'Live now' : 'Now playing',
      children: [
        ListTile(
          titleAlignment: ListTileTitleAlignment.center,
          leading: _Cover(t.artUrl, width: 44, height: 44, icon: t.live ? Icons.radio_rounded : Icons.headphones_rounded),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: t.subtitle.isEmpty ? null : Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(icon: Icon(a.playing ? Icons.pause_circle_rounded : Icons.play_circle_rounded, size: 34, color: AppColors.text), onPressed: a.toggle),
        ),
      ],
    );
  }
}

// ---- downloads -------------------------------------------------------------------------

/// Downloads [url] as [name] with a progress ring, then offers to open it.
class _DownloadButton extends StatefulWidget {
  const _DownloadButton({required this.url, required this.name, this.label = 'Download', this.icon = Icons.download_rounded, this.meta});
  final String url;
  final String name;

  /// What Files shows it as (library, title, subtitle, cover).
  final Map<String, Object?>? meta;
  final String label;
  final IconData icon;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  double? _progress;
  String? _path;

  Future<void> _go() async {
    if (_path != null) {
      await OpenFilex.open(_path!);
      return;
    }
    setState(() => _progress = 0);
    try {
      final f = await LibraryApi.instance.download(widget.url, widget.name, meta: widget.meta, progress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _path = f.path;
        _progress = null;
      });
      showSnack(context, 'Saved to Files · ${switch (widget.meta?['library']) {
        'book' => 'Books',
        'audiobook' => 'Audiobooks',
        'podcast' => 'Podcasts',
        _ => 'Made by AI',
      }}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      showSnack(context, 'Download failed: $e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return OutlinedButton.icon(
      onPressed: busy ? null : _go,
      icon: busy
          ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, value: _progress == 0 ? null : _progress))
          : Icon(_path != null ? Icons.folder_open_rounded : widget.icon, size: 18),
      label: Text(busy ? '${((_progress ?? 0) * 100).round()}%' : (_path != null ? 'Open' : widget.label)),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.data, required this.ebook});
  final Map<String, dynamic> data;
  final bool ebook;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: ebook ? Icons.book_rounded : Icons.audio_file_rounded,
    title: ebook ? 'Ebook saved' : 'Audio saved',
    children: [
      ListTile(
        titleAlignment: ListTileTitleAlignment.center,
        leading: _Cover(data['cover'], width: 40, height: ebook ? 56 : 40, icon: ebook ? Icons.book_rounded : Icons.audio_file_rounded),
        title: Text('${data['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${'${data['format'] ?? ''}'.toUpperCase()} · ${data['size_kb']} KB · in Files', style: context.text.bodySmall),
        trailing: FilledButton.tonal(onPressed: () => OpenFilex.open('${data['file']}'), child: const Text('Open')),
      ),
    ],
  );
}

// ---- ebooks -----------------------------------------------------------------------------

class _EbookShelf extends StatelessWidget {
  const _EbookShelf({required this.books, this.total});
  final List<Map<String, dynamic>> books;
  final int? total;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.auto_stories_rounded,
    title: 'Free ebooks${total == null ? '' : ' · ${_n(total)} found'}',
    children: [
      SizedBox(
        height: 236,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
          scrollDirection: Axis.horizontal,
          itemCount: books.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.m),
          itemBuilder: (context, i) {
            final b = books[i];
            return InkWell(
              borderRadius: BorderRadius.circular(Radii.m),
              onTap: () => showEbook(context, b),
              child: SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Cover(b['cover'], width: 112, height: 160),
                    const SizedBox(height: 6),
                    Text('${b['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
                    Text(_authors(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

Map<String, Object?> _bookMeta(Map b) => {'library': 'book', 'title': b['title'], 'subtitle': _authors(b), 'cover': b['cover']};

/// An ebook's sheet: summary, subjects, and read / download / listen.
Future<void> showEbook(BuildContext context, Map<String, dynamic> b) => showAppSheet<void>(
  context,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(b['cover'], width: 96, height: 140),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b['title']}', style: context.text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  (b['authors'] as List? ?? const []).whereType<Map>().map((a) => '${a['name']}${a['years'] == null ? '' : ' (${a['years']})'}').join(', '),
                  style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
                ),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (b['downloads'] != null) _Chip('${_n(b['downloads'])} downloads', icon: Icons.download_rounded),
                    for (final l in (b['languages'] as List? ?? const [])) _Chip('$l'.toUpperCase(), icon: Icons.translate_rounded),
                    _Chip('${b['source'] ?? 'Project Gutenberg'}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.l),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          if (b['text'] != null)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EbookReader(title: '${b['title']}', textUrl: '${b['text']}'))),
              icon: const Icon(Icons.chrome_reader_mode_rounded, size: 18),
              label: const Text('Read now'),
            ),
          if (b['epub'] != null)
            _DownloadButton(url: '${b['epub']}', name: LibraryApi.fileName('${b['title']}', 'epub'), label: 'EPUB', meta: _bookMeta(b)),
          if (b['kindle'] != null)
            _DownloadButton(url: '${b['kindle']}', name: LibraryApi.fileName('${b['title']}', 'mobi'), label: 'Kindle', meta: _bookMeta(b)),
          OutlinedButton.icon(
            onPressed: () => showAudiobookSearch(context, '${b['title']}'),
            icon: const Icon(Icons.headphones_rounded, size: 18),
            label: const Text('Listen'),
          ),
          if (b['url'] != null) TextButton.icon(onPressed: () => _open('${b['url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Gutenberg')),
        ],
      ),
      if (b['summary'] != null) ...[
        const SizedBox(height: Space.l),
        Text('ABOUT', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Text('${b['summary']}', style: context.text.bodyMedium?.copyWith(height: 1.45)),
      ],
      if ((b['subjects'] as List?)?.isNotEmpty == true || (b['bookshelves'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: Space.l),
        Text('SUBJECTS', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [for (final s in [...(b['bookshelves'] as List? ?? const []), ...(b['subjects'] as List? ?? const [])]) _Chip('$s'.split(' -- ').first)],
        ),
      ],
    ],
  ),
);

/// Reads a Gutenberg book's text in the app: chapters as pages, a font size,
/// and the place kept while the screen is open.
class EbookReader extends StatefulWidget {
  const EbookReader({super.key, required this.title, required this.textUrl});
  final String title;
  final String textUrl;

  @override
  State<EbookReader> createState() => _EbookReaderState();
}

class _EbookReaderState extends State<EbookReader> {
  List<String>? _pages;
  String? _error;
  int _page = 0;
  double _size = 17;
  bool _serif = true;
  final _controller = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await LibraryApi.instance.ebookText(widget.textUrl);
      // Pages of about 3,000 characters, broken at paragraphs.
      final paras = text.split(RegExp(r'\n\s*\n'));
      final pages = <String>[];
      final buf = StringBuffer();
      for (final p in paras) {
        final clean = p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
        if (clean.isEmpty) continue;
        if (buf.length + clean.length > 3000 && buf.isNotEmpty) {
          pages.add(buf.toString().trim());
          buf.clear();
        }
        buf.writeln(clean);
        buf.writeln();
      }
      if (buf.isNotEmpty) pages.add(buf.toString().trim());
      if (mounted) setState(() => _pages = pages);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Smaller text', icon: const Icon(Icons.text_decrease_rounded), onPressed: () => setState(() => _size = (_size - 1).clamp(13, 28))),
          IconButton(tooltip: 'Larger text', icon: const Icon(Icons.text_increase_rounded), onPressed: () => setState(() => _size = (_size + 1).clamp(13, 28))),
          IconButton(tooltip: _serif ? 'Sans-serif' : 'Serif', icon: const Icon(Icons.font_download_outlined), onPressed: () => setState(() => _serif = !_serif)),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text('Couldn\'t load the book: $_error')))
          : pages == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.x4),
                      child: SelectableText(
                        pages[i],
                        style: TextStyle(fontSize: _size, height: 1.65, fontFamily: _serif ? 'serif' : null, color: AppColors.text),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.m),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _page == 0 ? null : () => _controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                        ),
                        Expanded(
                          child: Slider(
                            value: _page.toDouble(),
                            max: (pages.length - 1).clamp(1, 100000).toDouble(),
                            onChanged: (v) => _controller.jumpToPage(v.round()),
                          ),
                        ),
                        Text('${_page + 1} / ${pages.length}', style: context.text.labelSmall),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _page >= pages.length - 1 ? null : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
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

class _CatalogueList extends StatelessWidget {
  const _CatalogueList({required this.query, required this.books});
  final String query;
  final List<Map<String, dynamic>> books;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.local_library_outlined,
    title: 'Open Library · "$query"',
    children: [
      for (final b in books.take(10))
        InkWell(
          onTap: () => _open(b['read_url'] as String? ?? b['url'] as String?),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                _Cover(b['cover'], width: 44, height: 64),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(_authors(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (b['year'] != null) _Chip('${b['year']}'),
                          if (b['pages'] != null) _Chip('${b['pages']} pages'),
                          if (b['rating'] != null) _Chip('${b['rating']}', icon: Icons.star_rounded),
                          if (b['free_to_read'] == true) const _Chip('Free to read', icon: Icons.lock_open_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

// ---- audiobooks -------------------------------------------------------------------------

class _AudiobookList extends StatelessWidget {
  const _AudiobookList({required this.books});
  final List<Map<String, dynamic>> books;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.headphones_rounded,
    title: 'Free audiobooks · ${books.length}',
    children: [for (final b in books.take(12)) _AudiobookRow(book: b)],
  );
}

class _AudiobookRow extends StatelessWidget {
  const _AudiobookRow({required this.book});
  final Map<String, dynamic> book;

  @override
  Widget build(BuildContext context) {
    final b = book;
    return InkWell(
      onTap: () => showAudiobook(context, b),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        child: Row(
          children: [
            _Cover(b['cover'], width: 52, height: 52, icon: Icons.headphones_rounded),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${b['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${b['author'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _Chip(b['source'] == 'librivox' ? 'LibriVox' : 'Internet Archive'),
                      if (_len(b['seconds']).isNotEmpty) _Chip(_len(b['seconds']), icon: Icons.schedule_rounded),
                      if (b['sections'] != null) _Chip('${b['sections']} parts'),
                      if ('${b['language'] ?? ''}'.isNotEmpty) _Chip('${b['language']}'),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// Finds audiobooks for [query] and shows them in a sheet (from an ebook's
/// Listen button).
Future<void> showAudiobookSearch(BuildContext context, String query) => showAppSheet<void>(
  context,
  builder: (context, scroll) => FutureBuilder<List<Map<String, dynamic>>>(
    future: LibraryApi.instance.audiobooks(query, limit: 10),
    builder: (context, snap) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, Space.x4),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Text('Audiobooks of "$query"', style: context.text.titleMedium),
        ),
        const SizedBox(height: Space.s),
        if (snap.connectionState != ConnectionState.done)
          const Padding(padding: EdgeInsets.all(Space.x4), child: Center(child: CircularProgressIndicator()))
        else if (snap.hasError)
          Padding(padding: const EdgeInsets.all(Space.l), child: Text('${snap.error}'))
        else if (snap.data!.isEmpty)
          Padding(padding: const EdgeInsets.all(Space.l), child: Text('No free recording found.', style: context.text.bodySmall))
        else
          for (final b in snap.data!) _AudiobookRow(book: b),
      ],
    ),
  ),
);

/// An audiobook's sheet: about it, and its chapters to play or download.
Future<void> showAudiobook(BuildContext context, Map<String, dynamic> b) => showAppSheet<void>(
  context,
  builder: (context, scroll) => _AudiobookSheet(book: b, scroll: scroll),
);

class _AudiobookSheet extends StatefulWidget {
  const _AudiobookSheet({required this.book, required this.scroll, this.chapters});
  final Map<String, dynamic> book;
  final ScrollController scroll;
  final List<Map<String, dynamic>>? chapters;

  @override
  State<_AudiobookSheet> createState() => _AudiobookSheetState();
}

class _AudiobookSheetState extends State<_AudiobookSheet> {
  late Future<List<Map<String, dynamic>>> _chapters = widget.chapters != null
      ? Future.value(widget.chapters)
      : LibraryApi.instance.audiobookTracks('${widget.book['source']}', '${widget.book['id']}');

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _chapters,
      builder: (context, snap) {
        final chapters = snap.data ?? const [];
        final queue = [
          for (final c in chapters)
            Track.stream(url: '${c['url']}', title: '${c['title']}', subtitle: '${b['title']}', artUrl: b['cover'] as String?, seconds: (c['seconds'] as int?) ?? 0),
        ];
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(b['cover'], width: 96, height: 96, icon: Icons.headphones_rounded, radius: Radii.m),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b['title']}', style: context.text.titleLarge),
                      Text('${b['author'] ?? ''}', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
                      const SizedBox(height: Space.s),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _Chip(b['source'] == 'librivox' ? 'LibriVox' : 'Internet Archive'),
                          if (_len(b['seconds']).isNotEmpty) _Chip(_len(b['seconds']), icon: Icons.schedule_rounded),
                          if (chapters.isNotEmpty) _Chip('${chapters.length} chapters'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            Row(
              children: [
                Consumer(
                  builder: (context, ref, _) => FilledButton.icon(
                    onPressed: queue.isEmpty ? null : () => _play(ref, context, queue.first, queue: queue),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play from the start'),
                  ),
                ),
                const SizedBox(width: Space.s),
                if (b['url'] != null) TextButton.icon(onPressed: () => _open('${b['url']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Source')),
              ],
            ),
            if ('${b['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text('${b['description']}', style: context.text.bodyMedium?.copyWith(height: 1.45)),
            ],
            const SizedBox(height: Space.l),
            Text('CHAPTERS', style: context.text.labelSmall),
            if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Row(
                  children: [
                    Expanded(child: Text('Couldn\'t load chapters: ${snap.error}')),
                    TextButton(
                      onPressed: () => setState(() => _chapters = LibraryApi.instance.audiobookTracks('${b['source']}', '${b['id']}')),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              for (final (i, c) in chapters.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  titleAlignment: ListTileTitleAlignment.center,
                  leading: _PlayButton(track: queue[i], queue: queue, size: 36),
                  title: Text('${c['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([_len(c['seconds']), if (c['reader'] != null) 'read by ${c['reader']}'].where((s) => s.isNotEmpty).join(' · '), style: context.text.bodySmall),
                  trailing: IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () async {
                      showSnack(context, 'Downloading ${c['title']}…', icon: Icons.download_rounded);
                      try {
                        await LibraryApi.instance.download(
                          '${c['url']}',
                          LibraryApi.fileName('${b['title']} - ${c['title']}', 'mp3'),
                          meta: {'library': 'audiobook', 'title': c['title'], 'subtitle': b['title'], 'author': b['author'], 'cover': b['cover'], 'n': c['n']},
                        );
                        if (context.mounted) showSnack(context, 'Saved to Files · Audiobooks');
                      } catch (e) {
                        if (context.mounted) showSnack(context, 'Download failed: $e', icon: Icons.error_outline_rounded);
                      }
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ChapterList extends ConsumerWidget {
  const _ChapterList({required this.data, required this.chapters});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = '${data['title'] ?? 'Audiobook'}';
    final queue = [for (final c in chapters) Track.stream(url: '${c['url']}', title: '${c['title']}', subtitle: title, seconds: (c['seconds'] as int?) ?? 0)];
    return _Panel(
      icon: Icons.headphones_rounded,
      title: '$title · ${chapters.length} chapters${_len(data['total_seconds']).isEmpty ? '' : ' · ${_len(data['total_seconds'])}'}',
      trailing: TextButton(
        onPressed: () => showAppSheet<void>(
          context,
          builder: (context, scroll) => _AudiobookSheet(book: {'title': title, 'source': data['source'], 'id': data['id']}, scroll: scroll, chapters: chapters),
        ),
        child: const Text('All'),
      ),
      children: [
        for (final (i, c) in chapters.take(5).indexed)
          ListTile(
            dense: true,
            titleAlignment: ListTileTitleAlignment.center,
            leading: _PlayButton(track: queue[i], queue: queue, size: 34),
            title: Text('${c['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(_len(c['seconds']), style: context.text.labelSmall),
          ),
      ],
    );
  }
}

// ---- radio ------------------------------------------------------------------------------

Track _stationTrack(Map<String, dynamic> s) => Track.stream(
  url: '${s['stream']}',
  title: '${s['name']}',
  subtitle: [s['country'], ...(s['tags'] as List? ?? const []).take(2)].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
  artUrl: s['logo'] as String?,
  live: true,
);

class _StationList extends StatelessWidget {
  const _StationList({required this.stations});
  final List<Map<String, dynamic>> stations;

  @override
  Widget build(BuildContext context) {
    final queue = [for (final s in stations) _stationTrack(s)];
    return _Panel(
      icon: Icons.radio_rounded,
      title: 'Live radio · ${stations.length} stations',
      children: [
        for (final (i, s) in stations.take(12).indexed)
          InkWell(
            onTap: () => showStation(context, s, queue: queue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
              child: Row(
                children: [
                  _Cover(s['logo'], width: 44, height: 44, icon: Icons.radio_rounded, radius: Radii.m),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            '${_flag(s['country_code'])} ${s['country'] ?? ''}'.trim(),
                            ...(s['tags'] as List? ?? const []).take(3),
                          ].where((x) => '$x'.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (s['bitrate'] is num && (s['bitrate'] as num) > 0) Padding(padding: const EdgeInsets.only(right: Space.s), child: Text('${s['bitrate']}k', style: context.text.labelSmall)),
                  _PlayButton(track: queue[i], queue: queue, size: 38, onPlay: () => LibraryApi.instance.countClick('${s['id']}')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A station's sheet: what it is, and play or open its site.
Future<void> showStation(BuildContext context, Map<String, dynamic> s, {List<Track>? queue}) => showAppSheet<void>(
  context,
  initialSize: 0.6,
  builder: (context, scroll) {
    final t = _stationTrack(s);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Center(child: _Cover(s['logo'], width: 120, height: 120, icon: Icons.radio_rounded, radius: Radii.xl)),
        const SizedBox(height: Space.m),
        Text('${s['name']}', style: context.text.titleLarge, textAlign: TextAlign.center),
        Text(
          [
            '${_flag(s['country_code'])} ${s['country'] ?? ''}'.trim(),
            if (s['state'] != null) '${s['state']}',
            if ('${s['language'] ?? ''}'.isNotEmpty) '${s['language']}',
          ].where((x) => x.isNotEmpty).join(' · '),
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.l),
        Center(child: _PlayButton(track: t, queue: queue, size: 64, onPlay: () => LibraryApi.instance.countClick('${s['id']}'))),
        const SizedBox(height: Space.l),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final tag in (s['tags'] as List? ?? const [])) _Chip('$tag'),
            if (s['codec'] != null) _Chip('${s['codec']}${s['bitrate'] is num && (s['bitrate'] as num) > 0 ? ' · ${s['bitrate']} kbps' : ''}', icon: Icons.graphic_eq_rounded),
            if (s['votes'] != null) _Chip('${_n(s['votes'])} votes', icon: Icons.thumb_up_alt_outlined),
            if (s['listeners'] != null) _Chip('${_n(s['listeners'])} recent plays', icon: Icons.headphones_rounded),
          ],
        ),
        if (s['homepage'] != null) ...[
          const SizedBox(height: Space.l),
          Center(child: OutlinedButton.icon(onPressed: () => _open('${s['homepage']}'), icon: const Icon(Icons.language_rounded, size: 18), label: const Text('Station website'))),
        ],
      ],
    );
  },
);

// ---- podcasts ---------------------------------------------------------------------------

class _ShowStrip extends StatelessWidget {
  const _ShowStrip({required this.title, required this.shows});
  final String title;
  final List<Map<String, dynamic>> shows;

  @override
  Widget build(BuildContext context) => _Panel(
    icon: Icons.podcasts_rounded,
    title: title,
    children: [
      SizedBox(
        height: 196,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
          scrollDirection: Axis.horizontal,
          itemCount: shows.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.m),
          itemBuilder: (context, i) {
            final s = shows[i];
            return InkWell(
              borderRadius: BorderRadius.circular(Radii.m),
              onTap: () => showPodcast(context, s),
              child: SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        _Cover(s['cover'], width: 120, height: 120, icon: Icons.podcasts_rounded, radius: Radii.m),
                        if (s['rank'] != null)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                              child: Text('#${s['rank']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${s['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
                    Text('${s['author'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// A show's sheet: about it and its episodes, loaded from its feed.
Future<void> showPodcast(BuildContext context, Map<String, dynamic> show) => showAppSheet<void>(
  context,
  builder: (context, scroll) => _PodcastSheet(show: show, scroll: scroll),
);

enum _EpisodeSort {
  newest('Newest'),
  oldest('Oldest'),
  longest('Longest'),
  shortest('Shortest');

  const _EpisodeSort(this.label);
  final String label;
}

class _PodcastSheet extends ConsumerStatefulWidget {
  const _PodcastSheet({required this.show, required this.scroll, this.feed});
  final Map<String, dynamic> show;
  final ScrollController scroll;
  final Map<String, dynamic>? feed;

  @override
  ConsumerState<_PodcastSheet> createState() => _PodcastSheetState();
}

class _PodcastSheetState extends ConsumerState<_PodcastSheet> {
  late Future<Map<String, dynamic>> _feed = widget.feed != null && (widget.feed!['episodes'] as List?)?.isNotEmpty == true ? Future.value(widget.feed) : _load();
  String _q = '';
  _EpisodeSort _sort = _EpisodeSort.newest;

  Future<Map<String, dynamic>> _load() async {
    var url = '${widget.show['feed'] ?? ''}';
    if (url.isEmpty && widget.show['id'] != null) url = await LibraryApi.instance.feedFor(widget.show['id']!) ?? '';
    if (url.isEmpty) throw const LibraryException('This show has no public feed.');
    return LibraryApi.instance.podcastFeed(url, limit: 100);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _feed,
    builder: (context, snap) {
      final f = snap.data ?? const {};
      final s = widget.show;
      final cover = (f['cover'] ?? s['cover']) as String?;
      final title = '${f['title'] ?? s['title'] ?? ''}';
      final showCard = {...s, 'title': title, 'author': f['author'] ?? s['author'], 'cover': cover, 'feed': f['feed'] ?? s['feed']};
      final favs = ref.watch(libraryFavoritesProvider);
      final all = [for (final e in (f['episodes'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
      final q = _q.toLowerCase();
      final episodes = all.where((e) => q.isEmpty || '${e['title']} ${e['description'] ?? ''}'.toLowerCase().contains(q)).toList();
      int secs(Map e) => (e['seconds'] as int?) ?? 0;
      switch (_sort) {
        case _EpisodeSort.newest:
          episodes.sort((a, b) => '${b['published'] ?? ''}'.compareTo('${a['published'] ?? ''}'));
        case _EpisodeSort.oldest:
          episodes.sort((a, b) => '${a['published'] ?? ''}'.compareTo('${b['published'] ?? ''}'));
        case _EpisodeSort.longest:
          episodes.sort((a, b) => secs(b).compareTo(secs(a)));
        case _EpisodeSort.shortest:
          episodes.sort((a, b) => secs(a).compareTo(secs(b)));
      }
      final queue = [for (final e in episodes) _episodeTrack(e, title, cover)];
      final starred = favs.hasShow(showCard);
      return ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(cover, width: 104, height: 104, icon: Icons.podcasts_rounded, radius: Radii.m),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleLarge),
                    Text('${f['author'] ?? s['author'] ?? ''}', style: context.text.bodyMedium?.copyWith(color: AppColors.text2)),
                    const SizedBox(height: Space.s),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final c in (f['categories'] as List? ?? [s['genre']]).where((x) => x != null)) _Chip('$c'),
                        if (s['episodes'] != null) _Chip('${s['episodes']} episodes'),
                        if (s['explicit'] == true) const _Chip('Explicit'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ('${f['description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Text('${f['description']}', maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(height: 1.4)),
          ],
          const SizedBox(height: Space.m),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              FilledButton.icon(
                onPressed: queue.isEmpty ? null : () => _play(ref, context, queue.first, queue: queue),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_sort == _EpisodeSort.newest && q.isEmpty ? 'Latest episode' : 'Play first'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final on = await ref.read(libraryFavoritesProvider.notifier).toggleShow(showCard);
                  if (context.mounted) showSnack(context, on ? 'Added to favourites · Files → Podcasts' : 'Removed from favourites');
                },
                icon: Icon(starred ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 18),
                label: Text(starred ? 'Favourite' : 'Add to favourites'),
              ),
              if (s['url'] != null || f['link'] != null)
                TextButton.icon(onPressed: () => _open('${s['url'] ?? f['link']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Show page')),
            ],
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(child: Text('EPISODES${all.isEmpty ? '' : ' · ${episodes.length}${episodes.length == all.length ? '' : ' of ${all.length}'}'}', style: context.text.labelSmall)),
              PopupMenuButton<_EpisodeSort>(
                tooltip: 'Sort',
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [for (final v in _EpisodeSort.values) CheckedPopupMenuItem(value: v, checked: _sort == v, child: Text(v.label))],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.sort_rounded, size: 18, color: AppColors.text2), const SizedBox(width: 4), Text(_sort.label, style: context.text.labelMedium)],
                  ),
                ),
              ),
            ],
          ),
          if (all.length > 5) ...[
            const SizedBox(height: Space.s),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(isDense: true, hintText: 'Search episodes', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ],
          if (snap.connectionState != ConnectionState.done)
            const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
          else if (snap.hasError)
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Row(
                children: [
                  Expanded(child: Text('Couldn\'t load episodes: ${snap.error}')),
                  TextButton(onPressed: () => setState(() => _feed = _load()), child: const Text('Retry')),
                ],
              ),
            )
          else if (episodes.isEmpty)
            Padding(padding: const EdgeInsets.all(Space.l), child: Text('No episodes match.', style: context.text.bodySmall))
          else
            for (final (i, e) in episodes.indexed) EpisodeTile(episode: e, track: queue[i], queue: queue, show: title, showCover: cover, feed: '${showCard['feed'] ?? ''}'),
        ],
      );
    },
  );
}

/// A podcast episode as a stream for the player.
Track _episodeTrack(Map e, String show, String? showCover) => Track.stream(
  url: '${e['audio']}',
  title: '${e['title']}',
  subtitle: show,
  artUrl: (e['image'] ?? showCover) as String?,
  seconds: (e['seconds'] as int?) ?? 0,
);

/// One episode: its cover, title and date, play, and a sheet with the rest.
class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({super.key, required this.episode, required this.track, required this.queue, required this.show, this.showCover, this.feed = ''});
  final Map<String, dynamic> episode;
  final Track track;
  final List<Track> queue;
  final String show;
  final String? showCover;
  final String feed;

  Map<String, dynamic> get _fav => {...episode, 'show': show, 'show_cover': showCover, 'feed': feed};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = episode;
    final cover = (e['image'] ?? showCover) as String?;
    final starred = ref.watch(libraryFavoritesProvider).hasEpisode(_fav);
    return InkWell(
      onTap: () => showEpisode(context, e, track: track, queue: queue, show: show, showCover: showCover, feed: feed),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _Cover(cover, width: 52, height: 52, icon: Icons.podcasts_rounded, radius: Radii.s),
                _PlayButton(track: track, queue: queue, size: 30),
              ],
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (e['season'] != null) 'S${e['season']}',
                      if (e['episode'] != null) 'E${e['episode']}',
                      e['published'],
                      _len(e['seconds']),
                    ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: starred ? 'Remove from favourites' : 'Add to favourites',
              visualDensity: VisualDensity.compact,
              icon: Icon(starred ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: starred ? AppColors.text : AppColors.text3),
              onPressed: () => ref.read(libraryFavoritesProvider.notifier).toggleEpisode(_fav),
            ),
          ],
        ),
      ),
    );
  }
}

/// An episode's sheet: cover, play, download, favourite, notes.
Future<void> showEpisode(
  BuildContext context,
  Map<String, dynamic> e, {
  required Track track,
  List<Track>? queue,
  required String show,
  String? showCover,
  String feed = '',
}) => showAppSheet<void>(
  context,
  initialSize: 0.7,
  builder: (context, scroll) => Consumer(
    builder: (context, ref, _) {
      final fav = {...e, 'show': show, 'show_cover': showCover, 'feed': feed};
      final starred = ref.watch(libraryFavoritesProvider).hasEpisode(fav);
      final cover = (e['image'] ?? showCover) as String?;
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(cover, width: 96, height: 96, icon: Icons.podcasts_rounded, radius: Radii.m),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['title']}', style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text([show, e['published'], _len(e['seconds'])].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              _PlayButton(track: track, queue: queue, size: 48),
              const SizedBox(width: Space.m),
              _DownloadButton(
                url: '${e['audio']}',
                name: LibraryApi.fileName('$show - ${e['title']}', 'mp3'),
                meta: {'library': 'podcast', 'title': e['title'], 'subtitle': show, 'cover': cover, 'published': e['published'], 'feed': feed},
              ),
              const SizedBox(width: Space.s),
              IconButton(
                tooltip: starred ? 'Remove from favourites' : 'Add to favourites',
                icon: Icon(starred ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                onPressed: () => ref.read(libraryFavoritesProvider.notifier).toggleEpisode(fav),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          SelectableText('${e['description'] ?? ''}', style: context.text.bodyMedium?.copyWith(height: 1.45)),
          if (e['link'] != null) ...[
            const SizedBox(height: Space.m),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => _open('${e['link']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Episode page')),
            ),
          ],
        ],
      );
    },
  ),
);

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.show, required this.episodes});
  final Map<String, dynamic> show;
  final List<Map<String, dynamic>> episodes;

  @override
  Widget build(BuildContext context) {
    final title = '${show['title'] ?? 'Podcast'}';
    final queue = [for (final e in episodes) _episodeTrack(e, title, show['cover'] as String?)];
    return _Panel(
      icon: Icons.podcasts_rounded,
      title: title,
      trailing: TextButton(
        onPressed: () => showAppSheet<void>(context, builder: (context, scroll) => _PodcastSheet(show: show, scroll: scroll, feed: show)),
        child: const Text('All'),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Row(
            children: [
              _Cover(show['cover'], width: 64, height: 64, icon: Icons.podcasts_rounded, radius: Radii.m),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text('${show['description'] ?? show['author'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Column(
            children: [
              for (final (i, e) in episodes.take(5).indexed)
                EpisodeTile(episode: e, track: queue[i], queue: queue, show: title, showCover: show['cover'] as String?, feed: '${show['feed'] ?? ''}'),
            ],
          ),
        ),
      ],
    );
  }
}
