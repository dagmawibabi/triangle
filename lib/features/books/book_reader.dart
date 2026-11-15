import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/fullscreen_image.dart';
import '../ai/data/ai.dart';
import '../settings/data/settings.dart';
import '../sections/section_kit.dart' show showFieldsSheet, SheetField, sizeText;
import 'book_parsers.dart';
import 'books.dart';

/// Opens [b]: downloads it first if it's in Telegram, then the reader for
/// its format (the PDF viewer, the text reader), or another app.
Future<void> openBook(BuildContext context, WidgetRef ref, Book b) async {
  final store = ref.read(booksProvider.notifier);
  var book = b;
  if (!book.downloaded) {
    final progress = ValueNotifier<double>(0);
    var hidden = false;
    var stopped = false;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (d) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                      child: Text(book.format.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent, fontSize: 12)),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text([if (book.source.isNotEmpty) book.source, if (book.size > 0) sizeText(book.size)].join(' · '), style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.l),
                LinearProgressIndicator(value: p > 0 ? p : null, minHeight: 8, borderRadius: BorderRadius.circular(9)),
                const SizedBox(height: Space.s),
                Text(
                  p > 0 ? 'Downloading ${(p * 100).round()}%${book.size > 0 ? ' · ${sizeText((book.size * p).round())} of ${sizeText(book.size)}' : ''}' : 'Starting the download…',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.xs),
                Text('It opens as soon as it\'s here. Pause keeps what\'s downloaded; open the book again to carry on.', style: context.text.labelSmall),
                const SizedBox(height: Space.l),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                        onPressed: () async {
                          stopped = true;
                          Navigator.pop(d);
                          await store.cancelDownload(book.id);
                        },
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.pause_rounded),
                        label: const Text('Pause'),
                        onPressed: () async {
                          stopped = true;
                          Navigator.pop(d);
                          await store.pauseDownload(book.id);
                        },
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Hide'),
                        onPressed: () {
                          hidden = true;
                          Navigator.pop(d);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      book = await store.download(book.id, onProgress: (p) => progress.value = p);
    } catch (e) {
      if (context.mounted) {
        if (!hidden && !stopped) Navigator.pop(context);
        if (e is DownloadPaused || stopped) {
          showSnack(context, store.paused.value.contains(book.id) ? 'Paused · open the book again to resume' : 'Download cancelled', icon: Icons.pause_circle_outline_rounded);
        } else {
          showSnack(context, 'Couldn\'t download: $e', icon: Icons.error_outline_rounded);
        }
      }
      return;
    }
    if (!context.mounted) return;
    if (!hidden && !stopped) Navigator.pop(context);
    if (hidden) {
      showSnack(context, '“${book.title}” is ready', icon: Icons.menu_book_rounded);
      return;
    }
  }
  if (!context.mounted) return;
  if (book.format == 'pdf') {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PdfReaderScreen(bookId: book.id)));
  } else if (readableFormats.contains(book.format)) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookReaderScreen(bookId: book.id)));
  } else {
    final r = await OpenFilex.open(book.path!);
    if (r.type != ResultType.done && context.mounted) showSnack(context, 'No app here opens .${book.format} files', icon: Icons.error_outline_rounded);
  }
}

/// Counts reading time: a minute for each minute the page is open and
/// the app is in front.
mixin _ReadingClock<T extends ConsumerStatefulWidget> on ConsumerState<T>, WidgetsBindingObserver {
  Timer? _clock;
  String get clockBookId;

  void startClock() {
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => ref.read(booksProvider.notifier).readMinute(clockBookId));
  }

  void stopClock() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _clock?.cancel();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) => ref.read(booksProvider.notifier).readMinute(clockBookId));
    } else {
      _clock?.cancel();
    }
  }
}

// ---- the text reader ---------------------------------------------------------------

class BookReaderScreen extends ConsumerStatefulWidget {
  const BookReaderScreen({super.key, required this.bookId, this.startBlock});
  final String bookId;

  /// Opens at this block instead of where the reader left off.
  final int? startBlock;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> with WidgetsBindingObserver, _ReadingClock {
  ParsedDoc? _doc;
  String? _error;
  int _section = 0;
  final _scroll = ScrollController();
  bool _chrome = true;
  String? _search;
  FlutterTts? _tts;
  bool _speaking = false;
  int? _speakingBlock;
  final _keys = <int, GlobalKey>{};

  // Gestures, as in Alexandria: taps at the top and bottom page, slides
  // along the edges dim the page or change the text size.
  Offset? _downAt;
  DateTime? _downTime;
  double _dim = 0;
  String? _flash;
  double _flashValue = 0;
  Timer? _flashTimer;

  void _showFlash(String label, double v) {
    _flashTimer?.cancel();
    setState(() {
      _flash = label;
      _flashValue = v.clamp(0, 1);
    });
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downAt, time = _downTime;
    _downAt = null;
    if (down == null || time == null) return;
    if ((e.position - down).distance > 10 || DateTime.now().difference(time).inMilliseconds > 280) return;
    final h = MediaQuery.sizeOf(context).height;
    final y = e.position.dy;
    if (!_chrome && _scroll.hasClients) {
      if (y < h * 0.2) return _page(-1);
      if (y > h * 0.8) return _page(1);
    }
    setState(() => _chrome = !_chrome);
  }

  void _page(int dir) {
    final pos = _scroll.position;
    final target = (pos.pixels + dir * pos.viewportDimension * 0.86).clamp(0.0, pos.maxScrollExtent);
    if (target == pos.pixels && dir > 0 && _section + 1 < (_doc?.sections.length ?? 0)) return _goSection(_section + 1);
    if (target == pos.pixels && dir < 0 && _section > 0) return _goSection(_section - 1, at: 1);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    HapticFeedback.selectionClick();
  }

  void _edgeDrag(DragUpdateDetails d, {required bool dim}) {
    final h = MediaQuery.sizeOf(context).height;
    if (dim) {
      setState(() => _dim = (_dim + d.delta.dy / (h * 0.55)).clamp(0.0, 0.8));
      _showFlash(_dim == 0 ? 'BRIGHT' : 'DIM ${(_dim * 100).round()}%', 1 - _dim);
    } else {
      final p = ref.read(booksProvider).prefs;
      final v = (p.fontSize - d.delta.dy / 14).clamp(12.0, 34.0);
      if (v.round() != p.fontSize.round()) {
        HapticFeedback.selectionClick();
        ref.read(booksProvider.notifier).setPrefs(p.copyWith(fontSize: v.roundToDouble()));
      }
      _showFlash('SIZE ${v.round()}', (v - 12) / 22);
    }
  }

  @override
  String get clockBookId => widget.bookId;

  Book get _book => ref.read(booksProvider).byId(widget.bookId)!;

  @override
  void initState() {
    super.initState();
    startClock();
    _open();
    _scroll.addListener(_onScroll);
  }

  Future<void> _open() async {
    try {
      final d = await ref.read(booksProvider.notifier).openDoc(_book);
      if (!mounted) return;
      final b = _book;
      final start = widget.startBlock ?? b.block;
      setState(() {
        _doc = d;
        _section = d.sectionOf(start.clamp(0, d.blocks.isEmpty ? 0 : d.blocks.length - 1));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        if (widget.startBlock != null) {
          _jumpToBlock(widget.startBlock!);
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent * b.offset);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  ({int start, int end}) get _range {
    final s = _doc!.sections[_section];
    return (start: s.start, end: s.end);
  }

  /// The block at the top of the screen, roughly.
  int get _topBlock {
    final r = _range;
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return r.start;
    final f = _scroll.offset / _scroll.position.maxScrollExtent;
    return (r.start + ((r.end - r.start) * f).floor()).clamp(r.start, r.end - 1 < r.start ? r.start : r.end - 1);
  }

  void _onScroll() {
    final d = _doc;
    if (d == null || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final f = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    final r = _range;
    final before = d.wordOffsets[r.start];
    final inSection = d.wordOffsets[r.end] - before;
    final progress = d.wordCount == 0 ? 0.0 : ((before + inSection * f) / d.wordCount).clamp(0.0, 1.0);
    ref.read(booksProvider.notifier).savePosition(widget.bookId, block: _topBlock, offset: f, progress: progress);
    if (_chrome && _scroll.position.userScrollDirection != ScrollDirection.idle) setState(() => _chrome = false);
  }

  void _goSection(int i, {double at = 0}) {
    final d = _doc!;
    setState(() => _section = i.clamp(0, d.sections.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent * at);
      _onScroll();
    });
  }

  void _jumpToBlock(int block) {
    final d = _doc!;
    final s = d.sectionOf(block);
    if (s != _section) setState(() => _section = s);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = _range;
      final f = (block - r.start) / ((r.end - r.start).clamp(1, 1 << 30));
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent * f.clamp(0.0, 1.0));
      // Then exactly, once the block is built.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final ctx = _keys[block]?.currentContext;
      if (ctx != null && ctx.mounted) await Scrollable.ensureVisible(ctx, alignment: 0.05);
    });
  }

  @override
  void dispose() {
    stopClock();
    _flashTimer?.cancel();
    _tts?.stop();
    _scroll.dispose();
    super.dispose();
  }

  // ---- actions ---------------------------------------------------------------

  Future<void> _toc() async {
    final d = _doc!;
    final v = await showAppSheet<int>(
      context,
      initialSize: 0.7,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Center(child: Text('Contents', style: context.text.titleMedium)),
          for (final e in (d.toc.isEmpty ? [for (final s in d.sections) TocEntry(s.title, s.start)] : d.toc))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: Space.l + e.depth * 16.0, right: Space.l),
              title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: d.sectionOf(e.block) == _section ? FontWeight.w800 : FontWeight.w400)),
              trailing: Text('${(d.wordOffsets[e.block.clamp(0, d.blocks.length)] * 100 / (d.wordCount == 0 ? 1 : d.wordCount)).round()}%', style: context.text.labelSmall),
              onTap: () => Navigator.pop(context, e.block),
            ),
        ],
      ),
    );
    if (v != null) _jumpToBlock(v);
  }

  Future<void> _searchBook() async {
    final d = _doc!;
    final v = await showAppSheet<int>(context, initialSize: 0.8, builder: (context, scroll) => _SearchSheet(doc: d, scroll: scroll));
    if (v != null) {
      _jumpToBlock(v);
    }
  }

  Future<void> _marks() async {
    final s = ref.read(booksProvider);
    final marks = s.bookmarks.where((b) => b.bookId == widget.bookId).toList()..sort((a, b) => a.block.compareTo(b.block));
    final hl = s.highlights.where((h) => h.bookId == widget.bookId).toList()..sort((a, b) => a.block.compareTo(b.block));
    final v = await showAppSheet<int>(
      context,
      initialSize: 0.7,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Center(child: Text('Bookmarks & highlights', style: context.text.titleMedium)),
          if (marks.isEmpty && hl.isEmpty) Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Nothing yet. Bookmark a spot from the top bar, or select text to highlight it.', textAlign: TextAlign.center, style: context.text.bodySmall)),
          for (final m in marks)
            ListTile(
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(m.label),
              subtitle: m.excerpt.isEmpty ? null : Text(m.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () {
                ref.read(booksProvider.notifier).removeBookmark(m.id);
                Navigator.pop(context);
              }),
              onTap: () => Navigator.pop(context, m.block),
            ),
          for (final h in hl)
            ListTile(
              leading: Container(width: 6, height: 40, color: Color(highlightColors[h.color % highlightColors.length])),
              title: Text(h.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: h.note.isEmpty ? null : Text(h.note, style: context.text.bodySmall),
              trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () {
                ref.read(booksProvider.notifier).removeHighlight(h.id);
                Navigator.pop(context);
              }),
              onTap: () => Navigator.pop(context, h.block),
            ),
        ],
      ),
    );
    if (v != null) _jumpToBlock(v);
  }

  Future<void> _bookmark() async {
    final d = _doc!;
    final b = _topBlock;
    final excerpt = d.blocks.skip(b).firstWhere((x) => x.text.isNotEmpty, orElse: () => const Block(BlockType.paragraph)).text;
    await ref.read(booksProvider.notifier).addBookmark(widget.bookId, block: b, label: d.sections[_section].title, excerpt: excerpt.length > 140 ? '${excerpt.substring(0, 140)}…' : excerpt);
    if (mounted) showSnack(context, 'Bookmarked', icon: Icons.bookmark_added_rounded);
  }

  Future<void> _settings() => showAppSheet<void>(context, initialSize: 0.55, builder: (context, scroll) => _TypeSheet(scroll: scroll));

  Future<void> _readAloud() async {
    if (_speaking) {
      await _tts?.stop();
      setState(() {
        _speaking = false;
        _speakingBlock = null;
      });
      return;
    }
    final tts = _tts ??= FlutterTts();
    await tts.awaitSpeakCompletion(true);
    setState(() => _speaking = true);
    final d = _doc!;
    for (var i = _topBlock; i < d.blocks.length && _speaking && mounted; i++) {
      final b = d.blocks[i];
      if (b.text.isEmpty || b.type == BlockType.image) continue;
      if (d.sectionOf(i) != _section) _goSection(d.sectionOf(i));
      setState(() => _speakingBlock = i);
      final ctx = _keys[i]?.currentContext;
      if (ctx != null && ctx.mounted) unawaited(Scrollable.ensureVisible(ctx, alignment: 0.2, duration: const Duration(milliseconds: 300)));
      await tts.speak(b.text);
    }
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _onSelection(String action, int block, int start, int end, String text) async {
    final store = ref.read(booksProvider.notifier);
    switch (action) {
      case 'highlight':
        await store.addHighlight(widget.bookId, block, start, end, text);
      case 'note':
        final v = await showFieldsSheet(
          context,
          icon: Icons.edit_note_rounded,
          title: 'Note on this passage',
          subtitle: _book.title,
          preview: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: Color(highlightColors[2]).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border(left: BorderSide(color: Color(highlightColors[2]), width: 3)),
            ),
            child: Text('“$text”', maxLines: 6, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontStyle: FontStyle.italic, fontFamily: 'serif')),
          ),
          fields: const [
            SheetField('note', label: 'Your thoughts', hint: 'What it means to you, a question, a link to another idea…', maxLines: 6, suggestions: ['Important', 'Re-read this', 'Quote', 'Question', 'Disagree']),
          ],
        );
        final note = v?['note'];
        if (note != null) await store.addHighlight(widget.bookId, block, start, end, text, color: 2, note: note);
      case 'explain' || 'define':
        await _ask(action, text, block);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _ask(String kind, String text, int block) async {
    final d = _doc!;
    final around = [for (var i = (block - 2).clamp(0, d.blocks.length); i < (block + 3).clamp(0, d.blocks.length); i++) d.blocks[i].text].join('\n');
    final b = _book;
    final future = () async {
      final s = ref.read(settingsProvider);
      final r = await ref.read(aiProvider).generateText(
        model: canonicalModelId(s.model),
        system: kind == 'define'
            ? 'You are a dictionary inside an e-book reader. Define the selected word or phrase as used in the passage: part of speech, a clear meaning, and one example. Short. Answer in the language of the passage.'
            : 'You explain passages inside an e-book reader. Explain the selected text in context: what it means, any references, and why it matters here. Under 150 words. Answer in the language of the passage.',
        prompt: 'Book: ${b.title}${b.author.isEmpty ? '' : ' by ${b.author}'}\nPassage:\n$around\n\nSelected: "$text"',
        maxOutputTokens: 600,
      );
      return r.text.trim();
    }();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      initialSize: 0.5,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Text(kind == 'define' ? 'Definition' : 'Explanation', style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          Text('“$text”', maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: Space.m),
          FutureBuilder<String>(
            future: future,
            builder: (_, snap) => snap.hasError
                ? Text(aiErrorText(snap.error!), style: TextStyle(color: AppColors.danger))
                : snap.hasData
                ? SelectableText(snap.data!, style: context.text.bodyLarge?.copyWith(height: 1.5))
                : const Center(child: Padding(padding: EdgeInsets.all(Space.xl), child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ],
      ),
    );
  }

  // ---- building ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(booksProvider);
    final b = s.byId(widget.bookId);
    final prefs = s.prefs;
    final bg = Color(prefs.theme.bg), fg = Color(prefs.theme.fg);
    final d = _doc;
    if (b == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This book was removed')));
    if (d == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, foregroundColor: fg, title: Text(b.title)),
        body: Center(child: _error == null ? CircularProgressIndicator(color: fg) : Padding(padding: const EdgeInsets.all(Space.xl), child: Text('Couldn\'t open the book: $_error', style: TextStyle(color: fg)))),
      );
    }
    final r = _range;
    final highlights = <int, List<Highlight>>{};
    for (final h in s.highlights) {
      if (h.bookId == widget.bookId) highlights.putIfAbsent(h.block, () => []).add(h);
    }
    final marked = {for (final m in s.bookmarks) if (m.bookId == widget.bookId) m.block};
    final body = TextStyle(
      fontFamily: prefs.serif ? 'serif' : null,
      fontSize: prefs.fontSize,
      height: prefs.lineHeight,
      color: fg,
    );
    final section = d.sections[_section];
    final sectionWords = d.wordOffsets[r.end] - d.wordOffsets[r.start];
    final leftMin = (sectionWords * (1 - b.offset) / 230).ceil();
    final overlay = prefs.theme.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            Listener(
              onPointerDown: (e) {
                _downAt = e.position;
                _downTime = DateTime.now();
              },
              onPointerUp: _onPointerUp,
              child: SafeArea(
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(prefs.margin, 56, prefs.margin, 120),
                  itemCount: r.end - r.start + 1,
                  itemBuilder: (_, i) {
                    if (i == r.end - r.start) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.x4),
                        child: _section + 1 < d.sections.length
                            ? OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.3))),
                                onPressed: () => _goSection(_section + 1),
                                icon: const Icon(Icons.arrow_downward_rounded),
                                label: Text('Next: ${d.sections[_section + 1].title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              )
                            : Center(child: Text('The end', style: body.copyWith(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.6)))),
                      );
                    }
                    final index = r.start + i;
                    return KeyedSubtree(
                      key: _keys.putIfAbsent(index, GlobalKey.new),
                      child: _BlockView(
                        block: d.blocks[index],
                        index: index,
                        style: body,
                        fg: fg,
                        justify: prefs.justify,
                        dark: prefs.theme.dark,
                        highlights: highlights[index] ?? const [],
                        search: _search,
                        bookmarked: marked.contains(index),
                        speaking: _speakingBlock == index,
                        onSelection: _onSelection,
                      ),
                    );
                  },
                ),
              ),
            ),
            // Dimming, from the left edge.
            if (_dim > 0) IgnorePointer(child: Container(color: Colors.black.withValues(alpha: _dim))),
            for (final left in [true, false])
              Positioned(
                left: left ? 0 : null,
                right: left ? null : 0,
                top: 90,
                bottom: 90,
                width: 26,
                child: GestureDetector(behavior: HitTestBehavior.translucent, onVerticalDragUpdate: (d) => _edgeDrag(d, dim: left)),
              ),
            if (_flash != null)
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(Space.m),
                    decoration: BoxDecoration(color: fg.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(Radii.l)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_flash!, style: TextStyle(color: bg, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                        const SizedBox(height: Space.s),
                        LinearProgressIndicator(value: _flashValue, color: bg, backgroundColor: bg.withValues(alpha: 0.25), minHeight: 4, borderRadius: BorderRadius.circular(9)),
                      ],
                    ),
                  ),
                ),
              ),
            // Top bar.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _chrome ? 0 : -120,
              left: 0,
              right: 0,
              child: Material(
                color: bg.withValues(alpha: 0.96),
                elevation: _chrome ? 2 : 0,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.arrow_back_rounded, color: fg), onPressed: () => Navigator.pop(context)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                            Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(tooltip: 'Contents', icon: Icon(Icons.toc_rounded, color: fg), onPressed: _toc),
                      IconButton(tooltip: 'Search', icon: Icon(Icons.search_rounded, color: fg), onPressed: _searchBook),
                      IconButton(tooltip: 'Bookmark', icon: Icon(Icons.bookmark_add_outlined, color: fg), onPressed: _bookmark),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: fg),
                        onSelected: (v) {
                          if (v == 'marks') _marks();
                          if (v == 'type') _settings();
                          if (v == 'speak') _readAloud();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'type', child: Text('Text & theme')),
                          const PopupMenuItem(value: 'marks', child: Text('Bookmarks & highlights')),
                          PopupMenuItem(value: 'speak', child: Text(_speaking ? 'Stop reading aloud' : 'Read aloud from here')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom bar.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _chrome ? 0 : -160,
              left: 0,
              right: 0,
              child: Material(
                color: bg.withValues(alpha: 0.96),
                elevation: _chrome ? 2 : 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, Space.s),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(icon: Icon(Icons.skip_previous_rounded, color: fg), onPressed: _section > 0 ? () => _goSection(_section - 1) : null),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(activeTrackColor: fg, thumbColor: fg, inactiveTrackColor: fg.withValues(alpha: 0.2), trackHeight: 2),
                                child: Slider(
                                  value: _section.toDouble(),
                                  max: (d.sections.length - 1).clamp(1, 1 << 20).toDouble(),
                                  divisions: d.sections.length > 1 ? d.sections.length - 1 : null,
                                  label: section.title,
                                  onChanged: (v) => _goSection(v.round()),
                                ),
                              ),
                            ),
                            IconButton(icon: Icon(Icons.skip_next_rounded, color: fg), onPressed: _section + 1 < d.sections.length ? () => _goSection(_section + 1) : null),
                          ],
                        ),
                        Text(
                          '${(b.progress * 100).round()}% · ${leftMin <= 1 ? 'under a minute' : '$leftMin min'} left in this chapter · ${_section + 1}/${d.sections.length}',
                          style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_speaking)
              Positioned(
                right: Space.l,
                bottom: (_chrome ? 120 : 24) + MediaQuery.paddingOf(context).bottom,
                child: FloatingActionButton.small(onPressed: _readAloud, child: const Icon(Icons.stop_rounded)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.index,
    required this.style,
    required this.fg,
    required this.justify,
    required this.dark,
    required this.highlights,
    required this.search,
    required this.bookmarked,
    required this.speaking,
    required this.onSelection,
  });
  final Block block;
  final int index;
  final TextStyle style;
  final Color fg;
  final bool justify;
  final bool dark;
  final List<Highlight> highlights;
  final String? search;
  final bool bookmarked;
  final bool speaking;
  final Future<void> Function(String action, int block, int start, int end, String text) onSelection;

  @override
  Widget build(BuildContext context) {
    final gap = style.fontSize! * 0.8;
    Widget child;
    switch (block.type) {
      case BlockType.image:
        if (block.image == null) return const SizedBox.shrink();
        child = GestureDetector(
          onTap: () => openFullscreenFile(context, block.image!, title: block.text.isEmpty ? 'Picture' : block.text),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: Center(child: Image.file(File(block.image!), fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink())),
          ),
        );
      case BlockType.rule:
        child = Center(child: Text('· · ·', style: style.copyWith(color: fg.withValues(alpha: 0.5), letterSpacing: 6)));
      case BlockType.heading:
        final scale = switch (block.level) { <= 1 => 1.6, 2 => 1.35, 3 => 1.15, _ => 1.05 };
        child = Padding(
          padding: EdgeInsets.only(top: gap * (block.level <= 2 ? 2 : 1), bottom: gap * 0.3),
          child: _text(context, style.copyWith(fontSize: style.fontSize! * scale, fontWeight: FontWeight.w800, height: 1.25), TextAlign.left),
        );
      case BlockType.quote:
        child = Container(
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: fg.withValues(alpha: 0.35), width: 2))),
          child: _text(context, style.copyWith(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.85)), justify ? TextAlign.justify : TextAlign.left),
        );
      case BlockType.paragraph:
        child = _text(context, style, justify ? TextAlign.justify : TextAlign.left);
    }
    return Container(
      padding: EdgeInsets.only(bottom: gap),
      decoration: speaking ? BoxDecoration(border: Border(left: BorderSide(color: AppColors.accent, width: 3))) : null,
      child: bookmarked
          ? Stack(clipBehavior: Clip.none, children: [child, Positioned(right: -14, top: 2, child: Icon(Icons.bookmark_rounded, size: 14, color: AppColors.accent))])
          : child,
    );
  }

  Widget _text(BuildContext context, TextStyle base, TextAlign align) {
    final text = block.text;
    final marks = <(int, int, Color)>[
      for (final h in highlights) (h.start.clamp(0, text.length), h.end.clamp(0, text.length), Color(highlightColors[h.color % highlightColors.length]).withValues(alpha: dark ? 0.4 : 0.6)),
    ];
    final q = search;
    if (q != null && q.length > 1) {
      final lower = text.toLowerCase();
      var i = lower.indexOf(q.toLowerCase());
      while (i >= 0) {
        marks.add((i, i + q.length, Colors.orange.withValues(alpha: 0.5)));
        i = lower.indexOf(q.toLowerCase(), i + q.length);
      }
    }
    marks.sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final (a, b, c) in marks) {
      if (b <= pos) continue;
      final start = a < pos ? pos : a;
      if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
      spans.add(TextSpan(text: text.substring(start, b), style: TextStyle(backgroundColor: c)));
      pos = b;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return SelectableText.rich(
      TextSpan(style: base, children: spans),
      textAlign: align,
      contextMenuBuilder: (ctx, state) {
        final sel = state.textEditingValue.selection;
        final a = sel.start.clamp(0, text.length), b = sel.end.clamp(0, text.length);
        final chosen = b > a ? text.substring(a, b).trim() : '';
        void run(String action) {
          state.hideToolbar();
          if (chosen.isNotEmpty) onSelection(action, index, a, b, chosen);
        }

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(label: 'Highlight', onPressed: () => run('highlight')),
            ContextMenuButtonItem(label: 'Note', onPressed: () => run('note')),
            ContextMenuButtonItem(label: 'Explain', onPressed: () => run('explain')),
            ContextMenuButtonItem(label: 'Define', onPressed: () => run('define')),
            ContextMenuButtonItem(label: 'Copy', onPressed: () => run('copy')),
          ],
        );
      },
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.doc, required this.scroll});
  final ParsedDoc doc;
  final ScrollController scroll;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final q = _q.toLowerCase().trim();
    final hits = <(int, String)>[];
    if (q.length > 1) {
      for (var i = 0; i < d.blocks.length && hits.length < 200; i++) {
        final t = d.blocks[i].text;
        final at = t.toLowerCase().indexOf(q);
        if (at >= 0) {
          final from = (at - 40).clamp(0, t.length), to = (at + q.length + 60).clamp(0, t.length);
          hits.add((i, '${from > 0 ? '…' : ''}${t.substring(from, to)}${to < t.length ? '…' : ''}'));
        }
      }
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search in this book'), onChanged: (v) => setState(() => _q = v)),
        ),
        Padding(padding: const EdgeInsets.all(Space.s), child: Text(q.length > 1 ? '${hits.length}${hits.length == 200 ? '+' : ''} found' : '', style: context.text.labelSmall)),
        Expanded(
          child: ListView.builder(
            controller: widget.scroll,
            itemCount: hits.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(hits[i].$2, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
              subtitle: Text(d.sections[d.sectionOf(hits[i].$1)].title, style: context.text.labelSmall),
              onTap: () => Navigator.pop(context, hits[i].$1),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeSheet extends ConsumerWidget {
  const _TypeSheet({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(booksProvider.select((s) => s.prefs));
    final store = ref.read(booksProvider.notifier);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Text('Text & theme', style: context.text.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.l),
        Row(
          children: [
            for (final t in ReaderTheme.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => store.setPrefs(p.copyWith(theme: t)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(t.bg),
                      borderRadius: BorderRadius.circular(Radii.m),
                      border: Border.all(color: p.theme == t ? AppColors.accent : AppColors.line, width: p.theme == t ? 2.5 : 1),
                    ),
                    child: Text('Aa · ${t.label}', style: TextStyle(color: Color(t.fg), fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(children: [const Icon(Icons.text_decrease_rounded), Expanded(child: Slider(value: p.fontSize, min: 12, max: 32, divisions: 20, label: '${p.fontSize.round()}', onChanged: (v) => store.setPrefs(p.copyWith(fontSize: v)))), const Icon(Icons.text_increase_rounded)]),
        Row(children: [const Icon(Icons.format_line_spacing_rounded), Expanded(child: Slider(value: p.lineHeight, min: 1.2, max: 2.2, divisions: 10, label: p.lineHeight.toStringAsFixed(1), onChanged: (v) => store.setPrefs(p.copyWith(lineHeight: v))))]),
        Row(children: [const Icon(Icons.format_indent_increase_rounded), Expanded(child: Slider(value: p.margin, min: 8, max: 48, divisions: 10, label: '${p.margin.round()}', onChanged: (v) => store.setPrefs(p.copyWith(margin: v))))]),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: true, label: Text('Serif', style: TextStyle(fontFamily: 'serif'))), ButtonSegment(value: false, label: Text('Sans'))],
          selected: {p.serif},
          onSelectionChanged: (v) => store.setPrefs(p.copyWith(serif: v.first)),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Justify text'), value: p.justify, onChanged: (v) => store.setPrefs(p.copyWith(justify: v))),
      ],
    );
  }
}

// ---- PDF ---------------------------------------------------------------------

/// Inverts a page's colours (keeping hues) for night reading.
const _night = ColorFilter.matrix(<double>[
  -0.9, 0, 0, 0, 235, //
  0, -0.9, 0, 0, 235,
  0, 0, -0.9, 0, 235,
  0, 0, 0, 1, 0,
]);

/// PDFs, drawn natively with PDFium: zoom, text selection, page jumps,
/// bookmarks, night mode, and the reading position kept.
class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({super.key, required this.bookId, this.startPage});
  final String bookId;
  final int? startPage;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> with WidgetsBindingObserver, _ReadingClock {
  final _controller = PdfViewerController();
  int _pages = 0;
  late int _page;
  String? _error;

  @override
  String get clockBookId => widget.bookId;

  @override
  void initState() {
    super.initState();
    startClock();
    final b = ref.read(booksProvider).byId(widget.bookId)!;
    _page = widget.startPage ?? (b.page > 0 ? b.page : 1);
    _pages = b.pages;
  }

  @override
  void dispose() {
    stopClock();
    super.dispose();
  }

  void _go(int p) {
    if (_controller.isReady) _controller.goToPage(pageNumber: p.clamp(1, _pages == 0 ? 1 : _pages));
  }

  void _onPage(int? p) {
    if (p == null || !mounted) return;
    setState(() => _page = p);
    if (_pages > 0) ref.read(booksProvider.notifier).savePosition(widget.bookId, page: p, pages: _pages, progress: p / _pages);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(booksProvider);
    final b = s.byId(widget.bookId);
    if (b == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This book was removed')));
    final dark = s.prefs.pdfDark;
    Widget viewer = PdfViewer.file(
      b.path!,
      controller: _controller,
      initialPageNumber: _page,
      params: PdfViewerParams(
        backgroundColor: dark ? const Color(0xFF111111) : const Color(0xFF525659),
        textSelectionParams: const PdfTextSelectionParams(),
        onViewerReady: (doc, controller) {
          if (!mounted) return;
          setState(() => _pages = doc.pages.length);
          ref.read(booksProvider.notifier).savePosition(widget.bookId, pages: doc.pages.length, page: _page, progress: _page / doc.pages.length);
        },
        onPageChanged: _onPage,
        loadingBannerBuilder: (context, bytes, total) => Center(child: CircularProgressIndicator(value: total == null || total == 0 ? null : bytes / total, color: Colors.white70)),
        errorBannerBuilder: (context, error, stack, ref) => Center(
          child: Padding(padding: const EdgeInsets.all(Space.xl), child: Text('Couldn\'t open this PDF: $error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))),
        ),
      ),
    );
    if (dark) viewer = ColorFiltered(colorFilter: _night, child: viewer);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_pages > 0) Text('Page $_page of $_pages', style: context.text.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Go to page',
            icon: const Icon(Icons.numbers_rounded),
            onPressed: _pages == 0
                ? null
                : () async {
                    final r = await showFieldsSheet(
                      context,
                      icon: Icons.numbers_rounded,
                      title: 'Go to page',
                      subtitle: 'Now on page $_page of $_pages',
                      action: 'Go',
                      fields: [
                        SheetField(
                          'page',
                          label: 'Page (1–$_pages)',
                          number: true,
                          suggestions: ['1', '${(_pages / 4).round().clamp(1, _pages)}', '${(_pages / 2).round().clamp(1, _pages)}', '${(_pages * 3 / 4).round().clamp(1, _pages)}', '$_pages'],
                        ),
                      ],
                    );
                    final v = int.tryParse(r?['page'] ?? '');
                    if (v != null) _go(v);
                  },
          ),
          IconButton(
            tooltip: dark ? 'Day mode' : 'Night mode',
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(booksProvider.notifier).setPrefs(s.prefs.copyWith(pdfDark: !dark)),
          ),
          IconButton(
            tooltip: 'Bookmark this page',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () async {
              await ref.read(booksProvider.notifier).addBookmark(widget.bookId, page: _page, label: 'Page $_page');
              if (context.mounted) showSnack(context, 'Bookmarked page $_page', icon: Icons.bookmark_added_rounded);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final store = ref.read(booksProvider.notifier);
              if (v == 'dark') await store.setPrefs(s.prefs.copyWith(pdfDark: !dark));
              if (v == 'marks' && context.mounted) {
                final marks = s.bookmarks.where((m) => m.bookId == widget.bookId && m.page > 0).toList()..sort((a, b) => a.page.compareTo(b.page));
                final p = await showAppSheet<int>(
                  context,
                  builder: (context, scroll) => ListView(
                    controller: scroll,
                    children: [
                      Center(child: Text('Bookmarks', style: context.text.titleMedium)),
                      if (marks.isEmpty) const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: Text('No bookmarks yet'))),
                      for (final m in marks)
                        ListTile(
                          leading: const Icon(Icons.bookmark_rounded),
                          title: Text(m.label),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              store.removeBookmark(m.id);
                              Navigator.pop(context);
                            },
                          ),
                          onTap: () => Navigator.pop(context, m.page),
                        ),
                    ],
                  ),
                );
                if (p != null) _go(p);
              }
              if (v == 'open') await OpenFilex.open(b.path!);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'marks', child: Text('Bookmarks')),
              const PopupMenuItem(value: 'open', child: Text('Open in another app')),
            ],
          ),
        ],
        bottom: _pages > 0 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _page / _pages, minHeight: 2)) : null,
      ),
      body: _error != null ? Center(child: Text(_error!)) : viewer,
    );
  }
}
